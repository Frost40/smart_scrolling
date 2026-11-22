"""Offline checks of the fetch stage: saved probes, rules, the file check, the failure table, the inbox.
Telethon is never imported: a fake bot replays messages."""
from contextlib import closing
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
import zipfile
from unittest.mock import patch

from . import cardmaker, fetch_telegram as ft, settings, stages, store
from .testdata.make_epub import make_epub

PROBES = Path(__file__).with_name('testdata') / 'probes'


def message(text='', buttons=(), entities=(), file=None, id=1):
    return {'id': id, 'text': text, 'edit': False, 'entities': list(entities), 'buttons': [list(r) for r in buttons],
            'file': file}


def probe(n):
    return json.loads((PROBES / f'{n}.json').read_text(encoding='utf-8'))['messages']


def real_epub(path):
    make_epub(path)
    with zipfile.ZipFile(path, 'a') as book:  # a real book is never under 20 KB
        book.writestr('OEBPS/cover.jpg', os.urandom(30_000))
    return path


class FakeTg:
    def __init__(self):
        self.sent = []

    def send_message(self, chat, text):
        self.sent.append((chat, text))

    def disconnect(self):
        pass


class FakeBot:
    """Answers each send or take with the next scripted list of messages; a download writes `payload`."""
    name = '@example_book_bot'

    def __init__(self, *answers, payload=None):
        self.answers, self.payload, self.tg, self.actions = list(answers), payload, FakeTg(), []

    def send(self, text):
        self.actions.append(('send', text))
        return self.answers.pop(0) if self.answers else []

    def take(self, option):
        self.actions.append(('take', option['label']))
        return self.answers.pop(0) if self.answers else []

    def listen(self):
        return []

    def download(self, option, path):
        self.actions.append(('download', option['label']))
        Path(path).write_bytes(Path(self.payload).read_bytes())
        return path


class FetchTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        env = patch.dict(os.environ, PIPELINE_HOME=folder.name)
        env.start()
        self.addCleanup(env.stop)
        self.home = settings.home()
        settings.set_value('trial', 'true')
        self.fetch = settings.load()['fetch']
        self.book = {'title': 'The Problems of Philosophy', 'authors': ['Bertrand Russell'], 'year': 1912}

    def add_book(self, **fields):
        row = {'id': 'b1', 'title': self.book['title'], 'authors': json.dumps(self.book['authors']), 'year': 1912,
               'status': 'wanted', 'attempts': 0, 'priority': 1, 'origin': 'owner', **fields}
        with closing(store.connect()) as db, db:
            db.execute(f"INSERT INTO books ({','.join(row)}) VALUES ({','.join('?' * len(row))})", tuple(row.values()))
        return stages.rows('SELECT * FROM books WHERE id=?', (row['id'],))[0]

    def book_row(self):
        return stages.rows("SELECT * FROM books WHERE id='b1'")[0]

    # ------------------------------------------------------------ pure reading

    def test_options_of_every_kind(self):
        found = ft.options([message('Results:\n\n/book_123 The Problems of Philosophy (epub)\n\nsee https://x.org/a.pdf',
                                    buttons=[[{'text': '2 MB epub', 'kind': 'callback', 'data': '01'}],
                                             [{'text': '‹', 'kind': 'callback', 'data': '02'},
                                              {'text': '1/5', 'kind': 'callback', 'data': '03'},
                                              {'text': 'Next ›', 'kind': 'callback', 'data': '04'}]],
                                    entities=[{'type': 'command', 'text': '/book_123'},
                                              {'type': 'url', 'text': 'https://x.org/a.pdf', 'url': 'https://x.org/a.pdf'}]),
                            message('The problems', file={'name': 'russell.epub', 'size': 300_000, 'type': 'x'}, id=2)])
        self.assertEqual([o['kind'] for o in found], ['callback', 'nav', 'nav', 'nav', 'command', 'url', 'document'])
        self.assertEqual(found[4]['label'], '/book_123 The Problems of Philosophy (epub)')
        self.assertEqual(found[6]['label'], 'russell.epub The problems')
        self.assertEqual(ft._forward(found)['label'], 'Next ›')

    def test_rule_filter(self):
        labels = ['The Problems of Philosophy - Russell (pdf, 1 MB)', 'The Problems of Philosophy (docx, 1 MB)',
                  'The Problems of Philosophy - Russell (epub, 120 MB)', 'A History of Ideas (epub, 1 MB)',
                  'The Problems of Philosophy (epub, 1 MB)', 'The Problems of Philosophy - Bertrand Russell (epub, 1 MB)']
        kept = ft.rule_filter([{'label': l, 'kind': 'callback'} for l in labels], self.book, self.fetch)
        self.assertEqual([o['label'] for o in kept], [labels[5], labels[4], labels[0]])

    def test_pick(self):
        one = ft.rule_filter([{'label': 'The Problems of Philosophy Russell epub', 'kind': 'callback'}], self.book, self.fetch)
        self.assertEqual(ft.pick(one, self.book, self.fetch), 0)
        clear = ft.rule_filter([{'label': l, 'kind': 'callback'} for l in
                                ('The Problems of Philosophy Russell epub', 'Problems of Philosophy pdf')], self.book, self.fetch)
        self.assertEqual(ft.pick(clear, self.book, self.fetch), 0)
        tie = ft.rule_filter([{'label': l, 'kind': 'callback'} for l in
                              ('Problems of Philosophy Russell epub', 'Problems of Philosophy Russell, abridged epub')],
                             self.book, self.fetch)
        with patch.object(ft.llm, 'call', return_value={'ok': True, 'data': {'index': 1, 'reason': 'x'}}) as call:
            self.assertEqual(ft.pick(tie, self.book, self.fetch), 1)
            self.assertIn('0: Problems of Philosophy Russell epub', call.call_args.args[2]['options'])
        with patch.object(ft.llm, 'call', return_value={'ok': True, 'data': {'index': -1, 'reason': 'x'}}):
            self.assertEqual(ft.pick(tie, self.book, self.fetch), -1)
            bot = FakeBot([message('found', buttons=[[{'text': o['label'], 'kind': 'callback', 'data': '01'} for o in tie]])])
            self.assertEqual(ft.get_book(self.book, self.fetch, bot, self.home / 'x')[0], 'not_found')

    def test_file_check(self):
        good = real_epub(self.home / 'good.epub')
        self.assertEqual(ft.check_file(good, 'epub'), 'epub')
        fake = self.home / 'fake.epub'
        fake.write_text('not a book ' * 5000)
        no_mimetype = self.home / 'nomime.epub'
        with zipfile.ZipFile(no_mimetype, 'w') as book:
            book.writestr('content.html', os.urandom(40_000))
        small = self.home / 'small.epub'
        make_epub(small)
        for path in (fake, no_mimetype, small):
            with self.subTest(path=path.name):
                self.assertEqual(ft.check_file(path, 'epub'), '')
        pdf = self.home / 'a.pdf'
        pdf.write_bytes(b'%PDF-1.7\n' + os.urandom(30_000))
        self.assertEqual(ft.check_file(pdf, 'pdf'), 'pdf')
        self.assertEqual(ft.check_file(pdf, 'epub'), '')

    def test_start_link(self):
        self.assertEqual(ft.start_link('https://t.me/example_book_bot?start=abc', '@example_book_bot'),
                         '/start abc')
        self.assertIsNone(ft.start_link('https://t.me/other_bot?start=abc', '@example_book_bot'))
        self.assertIsNone(ft.start_link('https://example.org/book.epub', '@example_book_bot'))

    def test_right_book(self):
        meta = {'title': 'The Problems of Philosophy', 'authors': ['Bertrand Russell']}
        text = [{'text': 'THE PROBLEMS OF PHILOSOPHY by Bertrand Russell'}, {'text': 'Chapter one'}]
        self.assertTrue(ft.right_book(meta, text, {}))
        self.assertFalse(ft.right_book(meta, [{'text': 'Walden by Henry David Thoreau'}], {}))
        self.assertTrue(ft.right_book(meta, [{'text': 'x'}], {'title': 'The Problems of Philosophy',
                                                                'authors': ['Russell, Bertrand']}))

    # ------------------------------------------------------------ the real bot's saved answers

    def test_options_on_saved_probes(self):
        books = ['nav', 'nav'] + ['command'] * 5
        for n in (1, 2, 3, 4):  # probe 3 ends with a "visit Example Library website" link: not an option
            with self.subTest(probe=n):
                self.assertEqual([o['kind'] for o in ft.options(probe(n))], books)
        self.assertEqual(ft.options(probe(5)), [])  # "Unfortunately, nothing has been found"
        self.assertEqual([o['kind'] for o in ft.options(probe(6))], ['callback', 'document'])
        page_two = ft.options(probe(7))
        self.assertEqual([o['kind'] for o in page_two], ['nav'] + books)
        self.assertEqual(ft._forward(page_two)['label'], '(3) next »')
        mobi = ft.options(probe(4))[3]
        self.assertIn('THE PROBLEMS OF PHILOSOPHY BY BERTRAND RUSSELL · Russell, Bertrand · Year: 2011', mobi['label'])
        self.assertEqual((mobi['command'], ft.label_format(mobi), ft.label_mb(mobi)), ('/book_aojLQ9qDJvL', 'mobi', 0.797))

    def test_replay_a_book_from_the_real_bot(self):
        bot = FakeBot(probe(4), probe(6), payload=real_epub(self.home / 'src.epub'))
        with patch.object(ft.llm, 'call', return_value={'ok': True, 'data': {'index': 0, 'reason': 'x'}}) as call:
            outcome = ft.get_book(self.book, self.fetch, bot, self.home / 'state' / 'incoming')
        self.assertEqual(outcome[:2], ('downloaded', ''))
        self.assertEqual(call.call_count, 1)  # two English EPUBs of the book: the model breaks the tie
        self.assertEqual([a[0] for a in bot.actions], ['send', 'take', 'download'])
        self.assertIn('/book_aY5jJKx47vp (epub, 4.82 MB)', bot.actions[1][1])
        self.assertIn('.epub', bot.actions[2][1])
        self.assertEqual(outcome[4], bot.actions[1][1])  # the book picked in the list, for the wrong-book memory

    def test_replay_no_file_after_the_details(self):
        details = probe(6)[:1]  # the book's details with "Click to read full description", no file
        limit = details + [message('Daily limit reached. Come back tomorrow.', id=9)]
        with patch.object(ft.llm, 'call', return_value={'ok': True, 'data': {'index': 0, 'reason': 'x'}}):
            stopped = ft.get_book(self.book, self.fetch, FakeBot(probe(4), limit), self.home / 'x')
            bot = FakeBot(probe(4), details)
            quiet = ft.get_book(self.book, self.fetch, bot, self.home / 'x')
        self.assertEqual(stopped[0], 'stop')
        self.assertEqual(quiet[0], 'no_reply')
        self.assertEqual([a[0] for a in bot.actions], ['send', 'take'])  # the description button is not pressed

    def test_replay_nothing_found_and_next_page(self):
        self.assertEqual(ft.get_book(self.book, self.fetch, FakeBot(probe(5)), self.home / 'x')[0], 'not_found')
        ghost = {'title': "Darwin's Ghost", 'authors': ['Steve Jones'], 'year': 2000}

        def choose(role, prompt, values, job_id=None):
            line = next(l for l in values['options'].splitlines() if 'GHOST' in l)
            return {'ok': True, 'data': {'index': int(line.split(':')[0]), 'reason': 'x'}}
        bot = FakeBot(probe(2), probe(7))
        with patch.object(ft.llm, 'call', side_effect=choose):
            ft.get_book(ghost, self.fetch, bot, self.home / 'x')
        self.assertEqual(bot.actions[:2], [('send', "Darwin's Ghost Jones"), ('take', '(2) next »')])
        self.assertIn('/book_a6Ej8enyVv9', bot.actions[2][1])

    # ------------------------------------------------------------ the failure table

    def test_downloaded_job_is_queued(self):
        row = self.add_book()
        answer = [message('', file={'name': 'The Problems of Philosophy - Bertrand Russell.epub', 'size': 50_000, 'type': 'x'})]
        bot = FakeBot(answer, payload=real_epub(self.home / 'src.epub'))
        summary = ft.fetch_book(row, settings.load(), bot)
        book = self.book_row()
        self.assertEqual(book['status'], 'downloaded', summary)
        self.assertEqual(bot.actions[0], ('send', 'The Problems of Philosophy Russell'))
        job = stages.rows('SELECT * FROM jobs')[0]
        self.assertEqual((job['id'], job['status'], job['origin']), (book['job_id'], 'queued', 'telegram'))
        self.assertTrue(job['id'].startswith('trial-'))
        folder = self.home / 'jobs' / job['id']
        self.assertEqual(ft.check_file(folder / 'original.epub', 'epub'), 'epub')
        meta = cardmaker.load(folder / 'meta.json')
        self.assertEqual((meta['book_id'], meta['year'], meta['sample']), ('b1', 1912, True))
        self.assertEqual(len(stages.rows('SELECT * FROM seen')), 1)
        self.assertFalse(list((self.home / 'state').glob('incoming*')))
        # The same file again is a duplicate.
        with closing(store.connect()) as db, db:
            db.execute("UPDATE books SET status='wanted'")
        ft.fetch_book(self.book_row(), settings.load(), FakeBot(answer, payload=self.home / 'src.epub'))
        self.assertEqual(self.book_row()['status'], 'duplicate')

    def test_no_reply(self):
        ft.fetch_book(self.add_book(), settings.load(), FakeBot())
        book = self.book_row()
        self.assertEqual((book['status'], book['attempts']), ('wanted', 1))
        self.assertGreater(book['next_try_at'], cardmaker.now())

    def test_nothing_matches_then_retry_limit(self):
        ft.fetch_book(self.add_book(), settings.load(), FakeBot([message('Nothing found for your request.')]))
        book = self.book_row()
        self.assertEqual((book['status'], book['attempts']), ('not_found', 1))
        self.assertEqual(ft.due_books(self.fetch, 5), [])  # retried only after retry_after_days
        with closing(store.connect()) as db, db:
            db.execute("UPDATE books SET next_try_at='2000-01-01'")
        self.assertEqual(len(ft.due_books(self.fetch, 5)), 1)
        with closing(store.connect()) as db, db:
            db.execute('UPDATE books SET attempts=3')
        self.assertEqual(ft.due_books(self.fetch, 5), [])

    def test_stop_word_switches_the_stage_off(self):
        settings.set_value('notify.telegram_saved_messages', 'true')
        (self.home / 'telegram.session').write_text('x')
        bot = FakeBot([message('Please join our channel to continue: @somechannel')])
        with self.assertRaises(ft.Stopped):
            ft.fetch_book(self.add_book(), settings.load(), bot)
        self.assertFalse(settings.load()['stages']['fetch']['enabled'])
        self.assertEqual(self.book_row()['status'], 'wanted')
        self.assertIn('join', bot.tg.sent[0][1])

    def test_flood_wait_rests_the_stage(self):
        class Flooding(FakeBot):
            def send(self, text):
                raise ft.Flood(3600)
        self.add_book()
        with patch.object(ft, 'Bot', lambda tg, fetch: Flooding()):
            result = ft.stage(settings.load(), time.monotonic() + 60, connect=FakeTg)
        self.assertEqual(result[0], 'stopped')
        self.assertEqual(self.book_row()['status'], 'wanted')
        self.assertEqual(ft.stage(settings.load(), time.monotonic() + 60, connect=FakeTg)[0], 'nothing')

    def test_bad_file_tries_next_once_then_fails(self):
        bad = self.home / 'bad.epub'
        bad.write_text('not a book ' * 5000)
        files = [message('', file={'name': f'The Problems of Philosophy {n}.epub', 'size': 50_000, 'type': 'x'}, id=n)
                 for n in (1, 2, 3)]
        bot = FakeBot(files, payload=bad)
        with patch.object(ft.llm, 'call', return_value={'ok': True, 'data': {'index': 0, 'reason': 'x'}}):
            ft.fetch_book(self.add_book(), settings.load(), bot)
        self.assertEqual(self.book_row()['status'], 'failed')
        self.assertEqual([a[0] for a in bot.actions], ['send', 'download', 'download'])
        self.assertFalse(list((self.home / 'state').glob('incoming*')))

    def test_second_level_formats_and_no_repress(self):
        book_button = {'text': 'The Problems of Philosophy - Bertrand Russell', 'kind': 'callback', 'data': '01'}
        first = [message('Found 1 book', buttons=[[book_button]], id=5)]
        # The pressed message keeps its button; a new message offers the formats without the title.
        second = [message('Found 1 book', buttons=[[book_button]], id=5),
                  message('Choose a format', buttons=[[{'text': 'PDF', 'kind': 'callback', 'data': '02'},
                                                       {'text': 'EPUB', 'kind': 'callback', 'data': '03'}]], id=6)]
        third = [message('', file={'name': 'russell.epub', 'size': 50_000, 'type': 'x'}, id=7)]
        bot = FakeBot(first, second, third, payload=real_epub(self.home / 'src.epub'))
        with patch.object(ft.llm, 'call', side_effect=AssertionError('no model needed')):
            outcome = ft.get_book(self.book, self.fetch, bot, self.home / 'state' / 'incoming')
        self.assertEqual(outcome[0], 'downloaded')
        self.assertEqual([a for a in bot.actions if a[0] == 'take'],
                         [('take', 'The Problems of Philosophy - Bertrand Russell'), ('take', 'EPUB')])

    def test_popup_stop_word(self):
        first = [message('Found', buttons=[[{'text': 'The Problems of Philosophy', 'kind': 'callback', 'data': '01'}]])]
        popup = [{'id': 0, 'text': 'Daily limit reached, come back tomorrow', 'edit': False, 'entities': [],
                  'buttons': [], 'file': None, 'popup': True}]
        self.assertEqual(ft.get_book(self.book, self.fetch, FakeBot(first, popup), self.home / 'x')[0], 'stop')

    def test_qr_sign_in_renews_the_code_and_cleans_up(self):
        import asyncio
        page = self.home / 'state' / 'telegram-qr.html'
        seen = []

        class FakeQr:
            url, waits = 'tg://login?token=first', 0

            async def wait(self, timeout):
                seen.append((self.url, page.read_text(encoding='utf-8')))
                self.waits += 1
                if self.waits == 1:
                    raise asyncio.TimeoutError
                return 'user'

            async def recreate(self):
                self.url = 'tg://login?token=second'

        class QrTg:
            loop = asyncio.new_event_loop()

            def qr_login(self):
                return FakeQr()

        self.addCleanup(QrTg.loop.close)
        with patch('webbrowser.open') as browser:
            self.assertEqual(ft.qr_sign_in(QrTg()), 'user')
        browser.assert_called_once()
        self.assertEqual([url for url, _ in seen], ['tg://login?token=first', 'tg://login?token=second'])
        self.assertIn('<svg', seen[0][1])
        self.assertNotEqual(seen[0][1], seen[1][1])
        self.assertFalse(page.exists())

    def test_stage_without_login(self):
        self.add_book()
        self.assertEqual(ft.stage(settings.load(), time.monotonic() + 60), ('nothing', 'sign in to Telegram'))
        (self.home / 'telegram.session').write_text('x')  # a session ended from the phone

        def ended():
            raise ValueError('sign in to Telegram first')
        self.assertEqual(ft.stage(settings.load(), time.monotonic() + 60, connect=ended), ('nothing', 'sign in to Telegram'))
        self.assertEqual(self.book_row()['status'], 'wanted')

    # ------------------------------------------------------------ the inbox and the right book

    def test_inbox(self):
        real_epub(self.home / 'inbox' / 'whatever.epub')
        (self.home / 'inbox' / 'Bertrand Russell - The Problems.pdf').write_text('no pdf ' * 5000)
        (self.home / 'inbox' / 'notes.txt').write_text('ignored')
        settings.set_value('fetch.bot', '""')
        result, summary = stages.fetch(settings.load(), time.monotonic() + 60)
        self.assertEqual(result, 'ok', summary)
        job = stages.rows('SELECT * FROM jobs')[0]
        self.assertEqual((job['status'], job['origin'], job['title']), ('queued', 'inbox', 'The Busy Mind'))
        self.assertEqual(sorted(p.name for p in (self.home / 'inbox').iterdir()), ['notes.txt', 'rejected'])
        self.assertTrue((self.home / 'inbox/rejected/Bertrand Russell - The Problems.pdf').exists())
        self.assertEqual(ft._name_facts(Path('Bertrand Russell - The Problems.pdf')), ('The Problems', 'Bertrand Russell'))

    def test_dashboard_skip_and_retry(self):
        from . import dashboard
        server = dashboard.server(0)
        self.addCleanup(server.server_close)
        handler = dashboard.Handler.__new__(dashboard.Handler)
        handler.server = server
        self.add_book(status='not_found', attempts=3, last_error='nothing matches')
        handler.post('/api/books', {'id': 'b1', 'action': 'skip'})
        self.assertEqual(self.book_row()['status'], 'skipped')
        handler.post('/api/books', {'id': 'b1', 'action': 'retry'})
        book = self.book_row()
        self.assertEqual((book['status'], book['attempts'], book['last_error']), ('wanted', 0, ''))
        with self.assertRaises(ValueError):
            handler.post('/api/books', {'id': 'nope', 'action': 'skip'})

    def test_wrong_book_goes_back_to_the_list(self):
        self.add_book(status='downloaded')
        path = real_epub(self.home / 'src.epub')
        job_id = cardmaker.create(path, title='The Problems of Philosophy', author=['Bertrand Russell'], origin='telegram',
                                  extra={'book_id': 'b1', 'taken': 'Busy Mind (epub)'})
        self.assertEqual(cardmaker.run(job_id), 'failed')
        book = self.book_row()
        self.assertEqual((book['status'], book['attempts'], book['last_error']), ('wanted', 1, 'wrong book: Busy Mind (epub)'))
        self.assertFalse((self.home / 'jobs' / job_id / 'original.epub').exists())
        kept = ft.rule_filter([{'label': 'Busy Mind (epub)', 'kind': 'callback'}],
                              {'title': 'Busy Mind', 'tried': ['Busy Mind (epub)']}, self.fetch)
        self.assertEqual(kept, [])


if __name__ == '__main__':
    unittest.main()

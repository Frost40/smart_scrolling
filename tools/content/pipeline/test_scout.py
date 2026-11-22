"""Offline wish-list (stage scout) checks using saved Open Library and Wikipedia answers."""
from contextlib import closing
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from . import dashboard, llm, readers, settings, stages, store

DATA = Path(__file__).with_name('testdata') / 'scout'


def _load(name):
    return json.loads((DATA / name).read_text(encoding='utf-8'))


class ScoutTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        env = patch.dict(os.environ, PIPELINE_HOME=folder.name)
        env.start()
        self.addCleanup(env.stop)
        self.home = settings.home()

    def test_topic_subjects_covers_topics_with_valid_names(self):
        from . import gates, scout
        mapping = scout.topic_subjects()
        self.assertEqual(set(mapping), gates.known_topics())
        for tid, subjects in mapping.items():
            with self.subTest(topic=tid):
                self.assertTrue(1 <= len(subjects) <= 4)
                for name in subjects:
                    self.assertRegex(name, r'^[a-z0-9_]+$')

    def test_normalise_accents_punctuation_the_and_subtitle(self):
        from . import scout
        self.assertEqual(scout.normalise('Café Society'), 'cafe society')
        self.assertEqual(scout.normalise('Thinking, Fast and Slow!'), 'thinking fast and slow')
        self.assertEqual(scout.normalise('The Selfish Gene'), 'selfish gene')
        self.assertEqual(scout.normalise('Guns, Germs, and Steel: The Fates of Human Societies'), 'guns germs and steel')
        self.assertEqual(scout.normalise('The Gödel, Escher, Bach: An Eternal Golden Braid'), 'godel escher bach')

    def test_admit_door_real_invented_fiction_duplicates_and_score(self):
        from . import scout
        config = settings.load()
        thinking = _load('ol_search_thinking.json')
        dune = _load('ol_search_dune.json')

        # Real book (also matching different capitalisation + subtitle)
        with patch.object(readers, '_api', return_value=thinking):
            row, reason = scout.admit(
                {'title': 'THINKING, FAST AND SLOW: Why We Decide', 'author': 'Daniel Kahneman',
                 'topics': ['psychology'], 'origin': 'openlibrary_subjects'},
                config=config, topic_counts={'psychology': 0, 'physics': 4}, avg_sources=2.0,
                app_titles=set())
        self.assertIsNotNone(row, reason)
        self.assertEqual(row['ol_work'], '/works/OL15992072W')
        self.assertEqual(row['year'], 2011)
        self.assertEqual(row['status'], 'wanted')
        self.assertEqual(row['score'], 6452 + 300)  # readinglog_count + thin topic bonus

        # Prize bonus
        with patch.object(readers, '_api', return_value=thinking):
            row, reason = scout.admit(
                {'title': 'Thinking, Fast and Slow', 'author': 'Daniel Kahneman',
                 'topics': [], 'origin': 'prize_pages'},
                config=config, topic_counts={}, avg_sources=0.0, app_titles=set())
        self.assertEqual(row['score'], 6452 + 500)

        # Invented book refused
        with patch.object(readers, '_api', return_value={'docs': []}):
            row, reason = scout.admit(
                {'title': 'A Book That Does Not Exist 99817', 'author': 'Nobody',
                 'topics': [], 'origin': 'model_suggestions'},
                config=config, topic_counts={}, avg_sources=0.0, app_titles=set())
        self.assertIsNone(row)
        self.assertIn('A Book That Does Not Exist 99817', reason)

        # Fiction refused (saved Dune response), while Non-fiction subject allowed
        with patch.object(readers, '_api', return_value=dune):
            row, reason = scout.admit(
                {'title': 'Dune', 'author': 'Frank Herbert', 'topics': [], 'origin': 'openlibrary_trending'},
                config=config, topic_counts={}, avg_sources=0.0, app_titles=set())
        self.assertIsNone(row)
        self.assertIn('fiction', reason.lower())

        nonfic = {'docs': [{**thinking['docs'][0], 'subject': ['Non-fiction', 'Psychology']}]}
        with patch.object(readers, '_api', return_value=nonfic):
            row, _ = scout.admit(
                {'title': 'Thinking, Fast and Slow', 'author': 'Daniel Kahneman', 'topics': [], 'origin': 'owner'},
                config=config, topic_counts={}, avg_sources=0.0, app_titles=set())
        self.assertIsNotNone(row)

        for bad_subject in ('Poetry', 'Juvenile literature', 'American novel'):
            bad = {'docs': [{**thinking['docs'][0], 'subject': [bad_subject]}]}
            with patch.object(readers, '_api', return_value=bad):
                row, _ = scout.admit(
                    {'title': 'Thinking, Fast and Slow', 'author': 'Daniel Kahneman', 'topics': [], 'origin': 'owner'},
                    config=config, topic_counts={}, avg_sources=0.0, app_titles=set())
            self.assertIsNone(row)

        # Already in app sources (normalised title) refused
        with patch.object(readers, '_api', return_value=thinking):
            row, reason = scout.admit(
                {'title': 'Thinking, Fast and Slow', 'author': 'Daniel Kahneman', 'topics': [], 'origin': 'owner'},
                config=config, topic_counts={}, avg_sources=0.0,
                app_titles={scout.normalise('Thinking, Fast and Slow: A Guide')})
        self.assertIsNone(row)
        self.assertIn('source', reason.lower())

        # Already in books (same ol_work or same normalised title + surname) refused
        with closing(store.connect()) as db, db:
            db.execute("INSERT INTO books(id,title,authors,ol_work,status) VALUES('b1','The Thinking Fast and Slow','[\"D. Kahneman\"]','/works/OTHER','wanted')")
        with patch.object(readers, '_api', return_value=thinking):
            row, reason = scout.admit(
                {'title': 'Thinking, Fast and Slow', 'author': 'Daniel Kahneman', 'topics': [], 'origin': 'owner'},
                config=config, topic_counts={}, avg_sources=0.0, app_titles=set())
        self.assertIsNone(row)
        self.assertIn('already', reason.lower())

    def test_sources_parse_saved_answers(self):
        from . import scout
        with patch.object(readers, '_json', return_value=_load('ol_trending.json')):
            items = scout.openlibrary_trending()
        self.assertEqual(len(items), 5)
        self.assertEqual(items[0], {'title': 'Atomic Habits', 'author': 'James Clear',
                                    'topics': [], 'origin': 'openlibrary_trending'})

        with patch.object(readers, '_json', return_value=_load('ol_subject.json')):
            items = scout.openlibrary_subjects({'psychology': ['psychology']})
        self.assertEqual(len(items), 5)
        self.assertEqual(items[0]['topics'], ['psychology'])
        self.assertEqual(items[0]['origin'], 'openlibrary_subjects')
        self.assertEqual(items[0]['author'], 'Niccolò Machiavelli')

        # All 4 Wikipedia prize pages
        pages = [_load('wiki_pulitzer.json'), _load('wiki_nba.json'),
                 _load('wiki_baillie.json'), _load('wiki_royalsoc.json')]
        with patch.object(readers, '_api', side_effect=pages):
            prizes = scout.prize_pages()
        titles = {c['title']: c['author'] for c in prizes}
        self.assertEqual(titles['The Guns of August'], 'Barbara W. Tuchman')
        self.assertEqual(titles['The Dead Are Arising: The Life of Malcolm X'], 'Les Payne and Tamara Payne')
        self.assertEqual(titles['1599: A Year in the Life of William Shakespeare'], 'James S. Shapiro')
        self.assertEqual(titles['The Body: A Guide for Occupants'], 'Bill Bryson')
        self.assertTrue(all(c['origin'] == 'prize_pages' for c in prizes))

        # Unknown Wikipedia layout yields nothing, logs a line, and does not raise
        with patch.object(readers, '_api', return_value={'parse': {'wikitext': 'No tables or lists here.'}}):
            prizes = scout.prize_pages(pages=('Mystery Prize',))
        self.assertEqual(prizes, [])
        log_text = next((self.home / 'logs').glob('*.log')).read_text(encoding='utf-8')
        self.assertIn('Mystery Prize', log_text)

        # NYT lists skipped without key, used when key set
        with patch.object(settings, 'secrets', return_value={}):
            self.assertEqual(scout.nyt_lists(), [])
        nyt = {'results': {'books': [{'title': 'THE ANXIOUS GENERATION', 'author': 'Jonathan Haidt'}]}}
        with patch.object(settings, 'secrets', return_value={'NYT_API_KEY': 'fake-key'}), \
                patch.object(readers, '_json', return_value=nyt):
            items = scout.nyt_lists()
        self.assertEqual(items, [{'title': 'THE ANXIOUS GENERATION', 'author': 'Jonathan Haidt',
                                  'topics': [], 'origin': 'nyt_lists'}])

    def test_model_suggestions_filters_invented_via_door(self):
        from . import scout
        config = settings.load()
        for name in config['wishlist']['sources']:
            config['wishlist']['sources'][name] = (name == 'model_suggestions')
        config['wishlist']['target_wanted'] = 5

        thinking = _load('ol_search_thinking.json')
        second = {'docs': [{**thinking['docs'][0], 'key': '/works/OL99999W', 'title': 'Grit',
                            'author_name': ['Angela Duckworth'], 'first_publish_year': 2016, 'readinglog_count': 400}]}
        fake_llm = {'ok': True, 'data': {'books': [
            {'title': 'Thinking, Fast and Slow', 'author': 'Daniel Kahneman', 'topic': 'psychology', 'why': 'Good.'},
            {'title': 'Invented Book XYZ', 'author': 'Fake Author', 'topic': 'psychology', 'why': 'Fake.'},
            {'title': 'Grit', 'author': 'Angela Duckworth', 'topic': 'habits', 'why': 'Good.'},
        ]}}

        with patch.object(scout, '_app_sources', return_value=[]), \
                patch.object(llm, 'call', return_value=fake_llm) as mock_call, \
                patch.object(readers, '_api', side_effect=[thinking, {'docs': []}, second]):
            outcome, summary = scout.stage(config, float('inf'))

        self.assertEqual(outcome, 'ok')
        self.assertTrue(mock_call.called)
        with closing(store.connect()) as db:
            titles = [r[0] for r in db.execute("SELECT title FROM books ORDER BY score DESC")]
        self.assertEqual(titles, ['Thinking, Fast and Slow', 'Grit'])

    def test_stage_target_topic_balance_and_preserves_non_wanted(self):
        from . import scout
        config = settings.load()
        config['wishlist']['target_wanted'] = 4
        config['wishlist']['topic_balance'] = True
        for name in config['wishlist']['sources']:
            config['wishlist']['sources'][name] = (name == 'openlibrary_subjects')

        with closing(store.connect()) as db, db:
            db.execute("INSERT INTO books(id,title,ol_work,status,priority) VALUES('done1','Already Done','/works/OLD1','downloaded',1)")

        candidates = [
            {'title': f'Phys {i}', 'author': 'Author A', 'topics': ['physics'], 'origin': 'openlibrary_subjects'}
            for i in range(5)
        ] + [
            {'title': 'Bio 0', 'author': 'Author B', 'topics': ['biology'], 'origin': 'openlibrary_subjects'}
        ]

        def fake_admit(cand, **kwargs):
            idx = int(cand['title'].split()[-1])
            score = 1000 - idx * 10 if cand['topics'] == ['physics'] else 50
            return {'id': cand['title'].replace(' ', ''), 'title': cand['title'], 'authors': json.dumps([cand['author']]),
                    'year': 2020, 'isbn13': '', 'ol_work': f"/works/{cand['title'].replace(' ', '')}",
                    'topics': json.dumps(cand['topics']), 'origin': cand['origin'], 'score': score,
                    'priority': 2, 'status': 'wanted', 'attempts': 0, 'next_try_at': '',
                    'last_error': '', 'job_id': '', 'added_at': '2026-11-16', 'updated_at': '2026-11-16'}, ''

        with patch.object(scout, '_app_sources', return_value=[]), \
                patch.object(scout, 'openlibrary_subjects', return_value=candidates), \
                patch.object(scout, 'admit', side_effect=fake_admit):
            outcome, _ = scout.stage(config, float('inf'))

        self.assertEqual(outcome, 'ok')
        with closing(store.connect()) as db:
            rows = [dict(r) for r in db.execute('SELECT id,status,topics FROM books')]
        self.assertEqual(next(r['status'] for r in rows if r['id'] == 'done1'), 'downloaded')
        wanted = [r for r in rows if r['status'] == 'wanted']
        self.assertEqual(len(wanted), 4)
        physics_count = sum(1 for r in wanted if 'physics' in json.loads(r['topics']))
        self.assertLessEqual(physics_count, 3)

        # Already at target_wanted -> does nothing
        with patch.object(scout, 'openlibrary_subjects', side_effect=AssertionError('must not run')):
            self.assertEqual(scout.stage(config, float('inf'))[0], 'nothing')

    def test_want_and_dashboard_add(self):
        from . import scout
        thinking = _load('ol_search_thinking.json')
        with patch.object(scout, '_app_sources', return_value=[]), \
                patch.object(readers, '_api', return_value=thinking):
            row = scout.want('Thinking, Fast and Slow', 'Daniel Kahneman')
        self.assertEqual(row['priority'], 1)
        self.assertEqual(row['origin'], 'owner')

        with patch.object(scout, '_app_sources', return_value=[]), \
                patch.object(readers, '_api', return_value={'docs': []}):
            with self.assertRaisesRegex(ValueError, 'Does Not Exist 99817'):
                scout.want('A Book That Does Not Exist 99817')

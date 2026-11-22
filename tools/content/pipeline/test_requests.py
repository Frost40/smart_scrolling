"""Offline round-trip, extension and request checks."""
import copy
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch

from tools.content import upload
from . import cardmaker as cm, rebuild, requests, settings


class RequestTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        env = patch.dict(os.environ, PIPELINE_HOME=temp.name)
        env.start()
        self.addCleanup(env.stop)
        self.home = settings.home()
        self.sid = 'trial-requests'
        self.folder = self.home / 'jobs' / self.sid
        self.source = dict(id=self.sid, kind='other', title='Sample', status='draft', is_sample=True,
                           discover_cards=[dict(id='card', format='concept', title='Sample card', front='A sample fact.',
                                                back='A sample explanation.', status='hidden', level='intro',
                                                related=['other/card'])],
                           practice_cards=[dict(id='card-flash', type='flashcard', prompt='Why?', answer='Because.',
                                                tests=['card', 'other/card'], status='hidden')])
        p = upload.validate([(str(self.folder), self.source)], set(), {'other/card'})[0]
        self.data = {k: copy.deepcopy(p[k]) for k in ('source', 'cards', 'practice', 'topics', 'card_topics', 'links', 'related')}
        self.data['details'] = []
        self.db = MagicMock()
        other = {'id': 'other', 'kind': 'other', 'title': 'Second sample'}
        def select(table, query):
            if table == 'sources':
                return [s for s in (self.data['source'], other) if f'id=eq.{s["id"]}' in query]
            if table == 'discover_cards':
                return self.data['cards'] if 'source_id=eq.' in query else [{'id': 'other/card', 'source_id': 'other'}]
            key = {'practice_cards': 'practice', 'source_topics': 'topics', 'card_topics': 'card_topics',
                   'practice_links': 'links', 'related_cards': 'related'}.get(table)
            return self.data[key] if key else []
        self.db.select.side_effect = select

    def prepare(self):
        return rebuild.rebuild(self.sid, self.folder, self.db)

    def test_rebuild_preserves_fields_hidden_and_external_links(self):
        s = self.prepare()
        p = upload.validate([(str(self.folder), s)], set(), {'other/card'})[0]
        self.assertEqual(rebuild.differences(p, self.data), [])
        self.assertEqual(s['discover_cards'][0]['status'], 'hidden')
        self.assertEqual(s['discover_cards'][0]['related'], ['other/card'])
        self.assertEqual(s['practice_cards'][0]['tests'], ['card', 'other/card'])

    def test_no_change_includes_links_not_in_uploader_summary(self):
        self.prepare()
        with patch.object(upload, 'Supabase', return_value=self.db), patch.object(rebuild, 'snapshot', return_value=self.data), patch.object(rebuild, 'dry_run', return_value=(0,) * 8):
            self.assertTrue(rebuild.no_change(self.folder))
            self.data['links'] = []
            self.assertFalse(rebuild.no_change(self.folder))

    def test_extension_guards_and_recovery(self):
        self.prepare()
        new = dict(id='new-test', type='flashcard', prompt='Another question?', answer='An answer.', tests=['card'])
        with patch.object(upload, 'Supabase', return_value=self.db), patch.object(rebuild, 'snapshot', side_effect=lambda *a: copy.deepcopy(self.data)), patch.object(rebuild, 'no_change', return_value=False), patch.object(rebuild, 'upload_command') as send:
            with self.assertRaisesRegex(ValueError, 'rebuild differs'):
                rebuild.extend(self.sid, [], [new], folder=self.folder)
            send.assert_not_called()
        with patch.object(upload, 'Supabase', return_value=self.db), patch.object(rebuild, 'snapshot', side_effect=lambda *a: copy.deepcopy(self.data)), patch.object(rebuild, 'no_change', return_value=True), patch.object(rebuild, 'dry_run', return_value=(0, 0, 0, 0, 0, 1, 0, 0)), patch.object(rebuild, 'upload_command') as send:
            with self.assertRaisesRegex(ValueError, 'id already exists'):
                rebuild.extend(self.sid, [], self.source['practice_cards'], folder=self.folder)
            def apply(*args):
                p = rebuild.plan(self.folder, self.db)
                self.data.update({k: copy.deepcopy(p[k]) for k in ('source', 'cards', 'practice', 'topics', 'card_topics', 'links', 'related')})
            send.side_effect = apply
            self.assertTrue(rebuild.extend(self.sid, [], [new], folder=self.folder))
            self.assertEqual(len(self.data['practice']), 2)
            self.assertFalse(self.folder.exists())
            self.assertTrue(rebuild.extend(self.sid, [], [new], folder=self.folder))
            self.assertEqual(send.call_count, 1)

    def test_unexpected_second_dry_run_never_uploads(self):
        self.prepare()
        with patch.object(upload, 'Supabase', return_value=self.db), patch.object(rebuild, 'snapshot', return_value=self.data), patch.object(rebuild, 'no_change', return_value=True), patch.object(rebuild, 'dry_run', return_value=(0, 1, 0, 0, 0, 0, 0, 0)), patch.object(rebuild, 'upload_command') as send:
            with self.assertRaisesRegex(ValueError, 'unexpected changes'):
                rebuild.extend(self.sid, [], [], folder=self.folder)
            send.assert_not_called()

    def test_requests_only_complete_after_verified_upload(self):
        for kind in ('more_cards', 'more_practice', 'problem'):
            for passes in (True, False):
                with self.subTest(kind=kind, passes=passes):
                    from uuid import uuid4
                    rid = str(uuid4())
                    r = dict(id=rid, source_id=self.sid, kind=kind, discover_card_id=self.sid + '/card')
                    db = MagicMock()
                    db.select.side_effect = lambda table, query: [self.data['source']] if table == 'sources' else [{'id': rid}]
                    def build(sid, folder):
                        folder.mkdir(parents=True)
                        cm.save(folder / 'source.json', self.source)
                        cm.save(folder / 'snapshot.json', self.data)
                        (folder / 'text.txt').write_text('Sample text.', encoding='utf-8')
                        return self.source
                    with patch.object(upload, 'Supabase', return_value=db), patch.object(rebuild, 'snapshot', return_value=self.data), patch.object(rebuild, 'rows', return_value=[r]), patch.object(rebuild, 'rebuild', side_effect=build), patch.object(rebuild, 'no_change', return_value=True), patch.object(requests, 'generate', return_value=dict(cards=[], tests=[], replacements=[]), side_effect=None if passes else ValueError('nothing passed')), patch.object(rebuild, 'extend', return_value=True) as extend:
                        result, _ = requests.stage(settings.load(), time.monotonic() + 10)
                        self.assertEqual(result, 'ok' if passes else 'nothing')
                        self.assertEqual(db.update.call_count, int(passes))
                        self.assertEqual(extend.call_count, int(passes))

    def test_problem_judged_fine_is_left_alone(self):
        self.folder.mkdir()
        (self.folder / 'text.txt').write_text('The sample has a fact and an explanation in the text.', encoding='utf-8')
        verdict = dict(ref='card', problem='Fine', fix='', **{key: True for key in cm.SIX})
        with patch.object(cm.Job, 'ask', return_value={'data': {'verdicts': [verdict]}}), patch.object(cm, 'write_round') as repair:
            with self.assertRaisesRegex(ValueError, 'found the card correct'):
                requests.generate(dict(kind='problem', discover_card_id=self.sid + '/card', message='Check it'), self.source, self.folder, None)
            repair.assert_not_called()

    def test_practice_uses_existing_questions_and_solver_gates(self):
        import json
        from .test_cardmaker import TRAP_TEXT
        answers = json.loads(Path(__file__).with_name('testdata').joinpath('trap_attention_answers.json').read_text())
        raw = next(t for t in answers['quiz']['01:2'] if t['type'] == 'true_false')
        for passes in (True, False):
            folder = self.home / ('passing' if passes else 'failing')
            folder.mkdir()
            (folder / 'text.txt').write_text(TRAP_TEXT, encoding='utf-8')
            def ask(job, role, name, values, avoid_family=None):
                if role == 'quiz':
                    self.assertIn('Why?', values['existing_tests'])
                    data = {'tests': [{**raw, 'card': 'card'}]}
                else:
                    data = {'answers': [{'test': 'card-tf', 'answerable': True,
                                         'is_true': raw['is_true'] if passes else not raw['is_true']}], 'unclear': []}
                return {'data': data, 'provider': 'claude-haiku'}
            with patch.object(cm.Job, 'ask', ask):
                if passes:
                    result = requests.generate(dict(kind='more_practice', discover_card_id=self.sid + '/card'), self.source, folder, None)
                    self.assertEqual(len(result['tests']), 1)
                    self.assertEqual(result['tests'][0]['tests'], ['card'])
                else:
                    with self.assertRaisesRegex(ValueError, 'nothing passed'):
                        requests.generate(dict(kind='more_practice', discover_card_id=self.sid + '/card'), self.source, folder, None)

    def test_interrupted_partial_upload_never_replays(self):
        self.prepare()
        cm.save(self.folder.parent / (self.sid + '-upload.json'), {'phase': 'upload'})
        changed = copy.deepcopy(self.data)
        changed['cards'][0]['front'] = 'Changed remotely.'
        with patch.object(upload, 'Supabase', return_value=self.db), patch.object(rebuild, 'snapshot', return_value=changed), patch.object(rebuild, 'upload_command') as send:
            with self.assertRaisesRegex(ValueError, 'interrupted upload needs review'):
                rebuild.extend(self.sid, [], [], folder=self.folder)
            send.assert_not_called()
            self.assertTrue(self.folder.exists())

    def test_dry_run_summary_fails_closed(self):
        with patch.object(rebuild, 'upload_command', return_value='Dry run, nothing uploaded. Would make: 0 new sources, 0 updated; 2 new cards, 0 updated, 0 hidden; 3 new tests, 0 updated, 0 hidden'):
            self.assertEqual(rebuild.dry_run(self.folder), (0, 0, 2, 0, 0, 3, 0, 0))
        with patch.object(rebuild, 'upload_command', return_value='incomplete output'):
            with self.assertRaisesRegex(ValueError, 'unrecognised'):
                rebuild.dry_run(self.folder)

    def test_media_repair_gate_keeps_real_reference_identity(self):
        from .test_cardmaker import GOOD, TRAP_TEXT
        from . import gates
        card = {**GOOD, 'id': 'card', 'source_id': self.sid, 'format': 'image',
                'media': {'existing': f'cards/{self.sid}/card/image.png'},
                'media_alt': GOOD['front']}
        self.assertEqual(gates.card_gates(card, None, TRAP_TEXT, TRAP_TEXT), [])
        card['media'] = {'existing': 'cards/other/card/image.png'}
        self.assertIn('must belong to this item', '; '.join(gates.card_gates(card, None, TRAP_TEXT, TRAP_TEXT)))

    def test_more_cards_reuses_archive_and_passes_existing_titles(self):
        from .test_cardmaker import GOOD, TRAP_TEXT
        archive = self.home / 'archive' / self.sid
        cm.save(archive / 'ideas.json', [])
        for passes in (True, False):
            folder = self.home / ('cards-pass' if passes else 'cards-fail')
            folder.mkdir()
            (folder / 'text.txt').write_text(TRAP_TEXT, encoding='utf-8')
            card = {**GOOD, 'ref': 'new'}
            test = dict(type='flashcard', prompt='Why?', answer='Because.', card='new')
            made = ([card], {'new': [test]}, 1) if passes else ([], {}, 0)
            with patch.object(cm, 'extract') as extract, patch.object(cm, 'select', return_value=([], {'topics': []})) as select, patch.object(cm, 'make_cards', return_value=made) as make:
                if passes:
                    result = requests.generate({'kind': 'more_cards'}, self.source, folder, None)
                    self.assertEqual(len(result['cards']), 1)
                    self.assertEqual(result['tests'][0]['tests'], [result['cards'][0]['id']])
                else:
                    with self.assertRaisesRegex(ValueError, 'nothing passed'):
                        requests.generate({'kind': 'more_cards'}, self.source, folder, None)
                extract.assert_not_called()
                self.assertEqual(select.call_args.args[-2:], (['Sample card'], 10))
                self.assertEqual(make.call_args.args[-1], self.source['discover_cards'])

    def test_problem_repairs_once_and_preserves_id(self):
        from .test_cardmaker import GOOD, TRAP_TEXT
        for passes in (True, False):
            folder = self.home / ('repair-pass' if passes else 'repair-fail')
            folder.mkdir()
            (folder / 'text.txt').write_text(TRAP_TEXT, encoding='utf-8')
            verdict = dict(ref='card', problem='Unsupported claim', fix='Use the evidence', **{key: False for key in cm.SIX})
            repaired = ([{**GOOD, 'ref': 'card'}], []) if passes else ([], [({}, None, 'Still unsupported', '')])
            with patch.object(cm.Job, 'ask', return_value={'data': {'verdicts': [verdict]}}), patch.object(cm, 'write_round', return_value=repaired) as repair:
                if passes:
                    result = requests.generate(dict(kind='problem', discover_card_id=self.sid + '/card', message='Wrong'), self.source, folder, None)
                    self.assertEqual(result['replacements'][0]['id'], 'card')
                    self.assertEqual(result['cards'], [])
                else:
                    with self.assertRaisesRegex(ValueError, 'repair failed'):
                        requests.generate(dict(kind='problem', discover_card_id=self.sid + '/card'), self.source, folder, None)
                self.assertEqual(repair.call_count, 1)

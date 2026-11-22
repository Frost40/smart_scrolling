"""Offline checks: py -3 -m unittest tools.content.pipeline.test_pipeline."""

from contextlib import closing
import copy
import datetime as dt
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

from . import llm, settings, store
from .test_settings import SettingsTests, StoreTests
from .test_regressions import ProviderRegressionTests
from .test_cardmaker import CardmakerTests, GateTests, TextTests
from .test_exam import ExamTests
from .test_stages import StageTests
from .test_dashboard import DashboardTests
from .test_fetch import FetchTests
from .test_feeds import FeedTests
from .test_images import ImageTests
from .test_readers import ReaderTests
from .test_scout import ScoutTests
from .test_requests import RequestTests

DATA = Path(__file__).with_name('testdata')
ANSWERS = json.loads((DATA / 'answers.json').read_text())
SCHEMA = {'type': 'object', 'properties': {'answer': {'type': 'string'}},
          'required': ['answer'], 'additionalProperties': False}


class CheckerTests(unittest.TestCase):
    def test_types(self):
        for kind, good, bad in [('object', {}, []), ('array', [], {}), ('string', '', 1),
                                 ('integer', 1, True), ('number', 1.5, False), ('boolean', True, 1)]:
            with self.subTest(kind=kind):
                self.assertEqual(llm.check(good, {'type': kind}), [])
                self.assertIn('$', llm.check(bad, {'type': kind})[0])

    def test_keywords(self):
        for schema, good, bad, path in [
            ({'enum': ['a', 'b']}, 'a', 'c', '$'),
            ({'properties': {'a': {'type': 'string'}}}, {'a': 'ok'}, {'a': 3}, '$.a'),
            ({'required': ['a']}, {'a': 1}, {}, '$.a'),
            ({'items': {'type': 'integer'}}, [1], [False], '$[0]'),
            ({'properties': {'a': {}}, 'additionalProperties': False}, {'a': 1}, {'b': 1}, '$.b'),
        ]:
            with self.subTest(schema=schema):
                self.assertEqual(llm.check(good, schema), [])
                self.assertIn(path, llm.check(bad, schema)[0])

    def test_nested_and_numeric_enum(self):
        self.assertEqual(llm.check(1.0, {'enum': [1]}), [])
        self.assertTrue(llm.check(True, {'enum': [1]}))
        schema = {'type': 'object', 'properties': {'a': {'type': 'array', 'items': SCHEMA}}}
        self.assertIn('$.a[0].answer', llm.check({'a': [{'answer': 2}]}, schema)[0])


class IsolatedTest(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.folder = Path(folder.name)
        env = patch.dict(os.environ, {'PIPELINE_HOME': str(self.folder), 'PIPELINE_TEST_SECRET': 'do-not-forward'})
        env.start()
        self.addCleanup(env.stop)
        self.config = settings.load()
        self.config['quality']['require_qualified'] = False
        self.config['providers']['fake'] = {'driver': 'cli', 'preset': 'fake', 'model': 'test',
                                           'family': 'test', 'max_calls_per_day': 100}
        self.preset = {'cmd': [sys.executable, str(DATA / 'fake_cli.py'), 'envelope', '{schema_file}', '{out_file}'],
                       'stdin': 'user', 'result': 'json:structured_output',
                       'tokens': {'in': 'usage.input_tokens', 'out': 'usage.output_tokens'},
                       'env_remove': ['PIPELINE_TEST_SECRET'], 'limit_words': ['usage limit', '429']}
        self.presets = self.folder / 'presets.json'
        presets_patch = patch.object(llm, 'PRESETS', self.presets)
        presets_patch.start()
        self.addCleanup(presets_patch.stop)
        self.save()

    def save(self):
        (self.folder / 'settings.json').write_text(json.dumps(self.config), encoding='utf-8')
        self.presets.write_text(json.dumps({'fake': self.preset}), encoding='utf-8')

    def rows(self):
        with closing(store.connect()) as db:
            return [dict(row) for row in db.execute('SELECT * FROM calls')]


class CliTests(IsolatedTest):
    def test_modes_and_saved_errors(self):
        cases = [('envelope', 'json:structured_output', ''), ('stdin', 'json:structured_output', ''),
                 ('file', 'file', ''), ('text', 'text', ''), ('cut', 'json:structured_output', 'cut'),
                 ('refused', 'json:structured_output', 'refused'), ('limit', 'json:structured_output', 'limit'),
                 ('schema', 'json:structured_output', 'schema'), ('bad_json', 'json:structured_output', 'bad_json'),
                 ('down', 'json:structured_output', 'down'), ('exit_error', 'json:structured_output', 'down')]
        for case, mode, error in cases:
            with self.subTest(case=case):
                (self.folder / 'state' / 'resting.json').unlink(missing_ok=True)
                self.preset['cmd'][2] = case
                self.preset['result'] = mode
                self.save()
                result = llm.run_provider('fake', 'system', 'user', SCHEMA)
                self.assertEqual(result['error_kind'], error, result)
                self.assertEqual(result['ok'], not error)
                if not error:
                    self.assertEqual(result['data'], ANSWERS['ok'])
        self.assertEqual(len(self.rows()), len(cases))

    def test_streaming(self):
        self.preset.update(stdin='stream-json', result='json:result.structured_output',
                           tokens={'in': 'result.usage.input_tokens', 'out': 'result.usage.output_tokens'})
        self.preset['cmd'][2] = 'stream'
        self.save()
        result = llm.run_provider('fake', 'system', 'user' * 12000, SCHEMA)
        self.assertTrue(result['ok'], result)
        self.assertEqual(result['tokens_in'], 429)

    def test_missing_program_long_command_and_timeout(self):
        self.config['providers']['fake']['program'] = str(self.folder / 'missing.exe')
        self.save()
        self.assertEqual(llm.run_provider('fake', '', '', SCHEMA)['error_kind'], 'down')
        del self.config['providers']['fake']['program']
        self.preset['cmd'].append('{prompt}')
        self.save()
        with patch.object(llm.subprocess, 'run', side_effect=AssertionError('must not launch')):
            self.assertEqual(llm.run_provider('fake', '', 'x' * 30001, SCHEMA)['error_kind'], 'too_long')
        self.preset['cmd'].pop()
        self.preset['cmd'][2] = 'timeout'
        self.config['make']['call_timeout_seconds'] = 1
        self.save()
        self.assertEqual(llm.run_provider('fake', '', '', SCHEMA)['error_kind'], 'down')


class HttpTests(IsolatedTest):
    def setUp(self):
        super().setUp()
        owner = self
        self.requests = []
        self.reply = copy.deepcopy(ANSWERS['http'])
        self.code = 200

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                owner.requests.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
                payload = json.dumps(owner.reply).encode()
                self.send_response(owner.code)
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def stop():
            server.shutdown()
            server.server_close()
            thread.join()
        self.addCleanup(stop)
        self.config['providers']['fake'] = {'driver': 'openai', 'model': 'test',
            'base_url': f'http://127.0.0.1:{server.server_port}/v1', 'key_env': '',
            'json': 'schema', 'max_calls_per_day': 100}
        self.save()

    def test_modes_fence_and_errors(self):
        for mode in ['schema', 'object', 'none']:
            self.config['providers']['fake']['json'] = mode
            self.save()
            result = llm.run_provider('fake', 'system', 'user', SCHEMA)
            self.assertTrue(result['ok'], result)
            request = self.requests[-1]
            if mode == 'schema':
                self.assertEqual(request['response_format']['json_schema']['schema'], SCHEMA)
            else:
                self.assertIn(json.dumps(SCHEMA), request['messages'][1]['content'])
                self.assertEqual('response_format' in request, mode == 'object')
            self.assertNotIn('tools', request)
        self.reply['choices'][0]['message']['content'] = '```json\n{"answer":"hello"}\n```'
        self.assertTrue(llm.run_provider('fake', '', '', SCHEMA)['ok'])
        self.reply['choices'][0]['finish_reason'] = 'length'
        self.assertEqual(llm.run_provider('fake', '', '', SCHEMA)['error_kind'], 'cut')
        for status, expected in [(429, 'limit'), (500, 'down')]:
            (self.folder / 'state' / 'resting.json').unlink(missing_ok=True)
            self.code = status
            self.assertEqual(llm.run_provider('fake', '', '', SCHEMA)['error_kind'], expected)


class RoleTests(IsolatedTest):
    def setUp(self):
        super().setUp()
        self.cardmaker = self.folder / 'cardmaker'
        (self.cardmaker / 'prompts').mkdir(parents=True)
        (self.cardmaker / 'prompts' / 'test.md').write_text('system {{label}}\n=====\n{{cards}} {{card_count}}')
        (self.cardmaker / 'schemas.json').write_text(json.dumps({'test': SCHEMA}))
        cm_patch = patch.object(llm, 'CARDMAKER', self.cardmaker)
        cm_patch.start()
        self.addCleanup(cm_patch.stop)
        self.config['providers']['second'] = {**self.config['providers']['fake'], 'family': 'other'}
        self.values = {'label': 'test', 'cards': [{'id': 'a'}, {'id': 'b'}], 'card_count': 2}
        for role in self.config['roles']:
            self.config['roles'][role] = ['fake', 'second']
        self.save()

    def call(self, role='write', **kwargs):
        return llm.call(role, 'test', self.values, **kwargs)

    def test_first_usable_rest_cap_and_family(self):
        self.assertTrue(self.call()['ok'])
        self.assertEqual(self.rows()[-1]['provider'], 'fake')
        llm._rest('fake', dt.datetime.now().astimezone() + dt.timedelta(hours=1))
        self.assertTrue(self.call()['ok'])
        self.assertEqual(self.rows()[-1]['provider'], 'second')
        (self.folder / 'state' / 'resting.json').unlink()
        self.assertTrue(self.call(avoid_family='test')['ok'])
        self.assertEqual(self.rows()[-1]['provider'], 'second')
        self.config['providers']['fake']['max_calls_per_day'] = 1
        self.save()
        self.assertTrue(self.call()['ok'])
        until = dt.datetime.fromisoformat(llm.resting()['fake'])
        self.assertEqual((until.hour, until.minute), (0, 0))

    def test_enabled_model_qualification_tools(self):
        for field, value in [('enabled', False), ('model', '')]:
            self.config['providers']['fake'][field] = value
            self.save()
            self.assertTrue(self.call()['ok'])
            self.assertEqual(self.rows()[-1]['provider'], 'second')
            self.config['providers']['fake'].pop('enabled', None)
            self.config['providers']['fake']['model'] = 'test'
        self.config['quality']['require_qualified'] = True
        (self.folder / 'qualified.json').write_text(json.dumps({'second': {'write': {'passed': True}}}))
        self.save()
        self.assertTrue(self.call()['ok'])
        self.assertEqual(self.rows()[-1]['provider'], 'second')
        self.config['quality']['require_qualified'] = False
        self.config['providers']['fake']['tools'] = 'on'
        self.save()
        self.assertTrue(self.call('extract')['ok'])
        self.assertEqual(self.rows()[-1]['provider'], 'second')
        self.assertTrue(self.call('quiz')['ok'])
        self.assertEqual(self.rows()[-1]['provider'], 'fake')

    def test_missing_values_are_bugs_and_unavailable_job_waits(self):
        del self.values['cards']
        with self.assertRaisesRegex(ValueError, 'cards'):
            self.call()
        self.assertEqual(self.rows(), [])
        self.values['cards'] = []
        self.config['providers']['fake']['enabled'] = False
        self.config['providers']['second']['enabled'] = False
        self.save()
        with closing(store.connect()) as db, db:
            db.execute("INSERT INTO jobs (id,status) VALUES ('trial-job','making')")
        self.assertFalse(self.call(job_id='trial-job')['ok'])
        with closing(store.connect()) as db:
            self.assertEqual(db.execute("SELECT status FROM jobs").fetchone()[0], 'waiting')

    def test_bad_json_retry_contains_error(self):
        original = llm.run_provider
        users = []
        def attempt(name, system, user, schema, **kwargs):
            users.append(user)
            self.preset['cmd'][2] = 'bad_json' if len(users) == 1 else 'envelope'
            self.save()
            return original(name, system, user, schema, **kwargs)
        with patch.object(llm, 'run_provider', side_effect=attempt):
            self.assertTrue(self.call()['ok'])
        self.assertIn('failed validation', users[1])
        self.assertEqual(len(self.rows()), 2)


if __name__ == '__main__':
    unittest.main()

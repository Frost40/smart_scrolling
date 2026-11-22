"""Exercise dashboard safety over a real loopback HTTP connection, offline."""
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch

from . import dashboard, settings


class DashboardTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        env = patch.dict(os.environ, PIPELINE_HOME=folder.name)
        env.start()
        self.addCleanup(env.stop)
        secrets = patch.object(settings, 'secrets', return_value={'GEMINI_API_KEY': 'secret-sentinel'})
        secrets.start()
        self.addCleanup(secrets.stop)
        self.server = dashboard.server(0)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f'http://127.0.0.1:{self.server.server_port}'

    def request(self, path, data=None, headers=None):
        request = urllib.request.Request(self.url + path, data=None if data is None else json.dumps(data).encode(),
                                         headers=headers or {})
        try:
            with urllib.request.urlopen(request) as response:
                return response.status, response.read().decode()
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read().decode()

    def test_security_and_settings(self):
        self.assertEqual(self.request('/api/settings', headers={'Host': 'evil.test'})[0], 403)
        self.assertEqual(self.request('/api/settings', {})[0], 403)
        status, body = self.request('/api/settings')
        self.assertEqual(status, 200)
        self.assertNotIn('secret-sentinel', body)
        self.assertEqual(json.loads(body)['secrets']['GEMINI_API_KEY'], 'set')
        token = {'X-Pipeline-Token': self.server.token}
        self.assertEqual(self.request('/api/settings', {'stages.make.every_minutes': 60}, token)[0], 200)
        self.assertEqual(settings.load()['stages']['make']['every_minutes'], 60)
        status, body = self.request('/api/settings', {'stages.make.typo': 1}, token)
        self.assertEqual(status, 400)
        self.assertIn('stages.make.typo', body)
        self.assertEqual(self.request('/api/job?id=../../.env')[0], 400)
        self.assertEqual(self.request('/api/settings', {'paused': True, 'unknown': 1}, token)[0], 400)
        self.assertFalse(settings.load()['paused'])

    def test_retry_and_drop_preserve_running_job(self):
        from . import cardmaker, stages, store
        from contextlib import closing
        folder = stages.job_folder('trial-retry')
        folder.mkdir()
        cardmaker.save(folder / 'brief.json', {'cached': True})
        with closing(store.connect()) as db, db:
            db.execute("INSERT INTO jobs(id,status,step) VALUES('trial-retry','failed','brief')")
        headers = {'X-Pipeline-Token': self.server.token}
        with cardmaker.lock(folder):
            self.assertEqual(self.request('/api/job', {'id': 'trial-retry', 'action': 'drop'}, headers)[0], 400)
            self.assertTrue((folder / 'brief.json').exists())
        self.assertEqual(self.request('/api/job', {'id': 'trial-retry', 'action': 'retry'}, headers)[0], 200)
        self.assertFalse((folder / 'brief.json').exists())
        self.assertEqual(stages.rows('SELECT status FROM jobs')[0]['status'], 'queued')
        self.assertEqual(self.request('/api/job', {'id': 'trial-retry', 'action': 'drop'}, headers)[0], 200)
        self.assertFalse(folder.exists())

    def test_pages_and_background_run(self):
        status, body = self.request('/')
        self.assertEqual(status, 200)
        self.assertIn(self.server.token, body)
        with patch.object(dashboard.subprocess, 'Popen') as process:
            process.return_value.pid = 123
            status, _ = self.request('/api/run', {'stage': 'scout'}, {'X-Pipeline-Token': self.server.token})
            self.assertEqual(status, 202)
            self.assertEqual(process.call_args.args[0][-2:], ['run', 'scout'])
        for path in ('state', 'jobs', 'books', 'usage', 'log', 'feeds'):
            self.assertEqual(self.request('/api/' + path)[0], 200)

    def test_feed_controls_round_trip_through_validated_settings(self):
        status, body = self.request('/api/feeds')
        self.assertEqual(status, 200)
        feed = json.loads(body)[0]
        self.assertEqual((feed['today'], feed['total'], feed['last_error']), (0, 0, ''))
        feeds = settings.load()['feeds']
        feeds[0].update(enabled=False, per_day=3, topics=['history'])
        headers = {'X-Pipeline-Token': self.server.token}
        self.assertEqual(self.request('/api/settings', {'feeds': feeds}, headers)[0], 200)
        updated = json.loads(self.request('/api/feeds')[1])[0]
        self.assertEqual((updated['enabled'], updated['per_day'], updated['topics']), (False, 3, ['history']))

    def test_books_add_endpoint_validates_and_sets_priority_one(self):
        from . import readers, scout
        thinking = json.loads((Path(__file__).with_name('testdata') / 'scout' / 'ol_search_thinking.json').read_text(encoding='utf-8'))
        headers = {'X-Pipeline-Token': self.server.token}
        with patch.object(scout, '_app_sources', return_value=[]):
            with patch.object(readers, '_api', return_value=thinking):
                code, body = self.request('/api/books', {'action': 'add', 'title': 'Thinking, Fast and Slow', 'author': 'Daniel Kahneman'}, headers)
            self.assertEqual(code, 200)
            self.assertEqual(json.loads(body)['book']['priority'], 1)
            with patch.object(readers, '_api', return_value={'docs': []}):
                code, body = self.request('/api/books', {'action': 'add', 'title': 'Missing Book 99817'}, headers)
            self.assertEqual(code, 400)
            self.assertIn('Missing Book 99817', body)

    def test_state_includes_prompt_hashes_for_providers_page(self):
        from . import exam
        code, body = self.request('/api/state')
        self.assertEqual(code, 200)
        data = json.loads(body)
        self.assertIn('prompt_hashes', data)
        self.assertEqual(data['prompt_hashes']['judge'], exam.prompt_hash('judge'))
        self.assertEqual(data['prompt_hashes']['write'], exam.prompt_hash('make'))
        _, html = self.request('/')
        self.assertIn('prompt_hashes', html)

"""Loopback-only dashboard. No framework, external assets, or secrets in responses."""
import copy
import datetime as dt
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import threading
from urllib.parse import parse_qs, urlsplit

from . import cardmaker, exam, feeds, fetch_telegram, gates, llm, scout, settings, stages

SECRET_KEYS = ('PIPELINE_HOME', 'CONTACT_EMAIL', 'TELEGRAM_API_ID', 'TELEGRAM_API_HASH',
               'GEMINI_API_KEY', 'OPENROUTER_API_KEY', 'NYT_API_KEY', 'NASA_API_KEY',
               'NEWSDATA_API_KEY', 'CURRENTS_API_KEY', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY')


def read_json(path, fallback):
    return json.loads(path.read_text(encoding='utf-8')) if path.exists() else fallback


def spawn(args):
    output = settings.home() / 'logs' / f'{dt.date.today()}.log'
    with output.open('a', encoding='utf-8') as stream:
        process = subprocess.Popen([sys.executable, '-m', 'tools.content.pipeline', *args],
                                   cwd=settings.ROOT, env={**os.environ, 'PIPELINE_HOME': str(settings.home())},
                                   stdout=stream, stderr=stream,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    return {'pid': process.pid}


def state():
    config = settings.load()
    last = {}
    for row in stages.rows('SELECT * FROM runs ORDER BY id'):
        last[row['stage']] = row
    schedule = {}
    for name, spec in config['stages'].items():
        previous = last.get(name)
        next_at = (dt.datetime.fromisoformat(previous['ended_at']) + dt.timedelta(minutes=spec['every_minutes'])).isoformat() if previous else 'now'
        notice = 'not built' if name not in stages.BUILTINS and spec['run'] == 'builtin' else ''
        if name == 'fetch' and spec['run'] == 'builtin' and not fetch_telegram.session_path().exists():
            notice = 'sign in to Telegram'
        if name == 'feeds':
            warnings = [f"{f['reader']}: {f['failures']} failures: {f['last_error']}"
                        for f in feeds.stats(config) if f['failures'] >= 3]
            notice = '; '.join(warnings)
        if name == 'scout' and spec['run'] == 'builtin':
            missing = sorted(gates.known_topics() - {k for k, v in scout.topic_subjects().items() if v})
            if missing:
                notice = 'missing subjects for: ' + ', '.join(missing)
        schedule[name] = {**spec, 'last': previous, 'next': next_at, 'notice': notice}
    return {'paused': config['paused'], 'stages': schedule,
            'requests': list(read_json(settings.home() / 'state' / 'requests.json', {}).values()),
            'books': stages.rows('SELECT status,count(*) AS count FROM books GROUP BY status'),
            'jobs': stages.rows('SELECT status,count(*) AS count FROM jobs GROUP BY status'),
            'qualified': read_json(settings.home() / 'qualified.json', {}),
            'prompt_hashes': {r: exam.prompt_hash('make' if r in exam.MAKE_ROLES else r)
                              for r in ('judge', 'solve', 'choose', *exam.MAKE_ROLES)},
            'providers': {n: {'calls_today': llm.calls_today(n), 'resting': llm.resting().get(n)} for n in config['providers']}}


def review(source_id):
    client = stages.upload.Supabase()
    if not source_id:
        return client.select('sources', 'select=id,title,status&status=eq.draft&order=title')
    stages.job_folder(source_id)
    sources = client.select('sources', f'select=*&id=eq.{source_id}')
    if not sources:
        raise ValueError('source not found')
    return {'source': sources[0],
            'cards': client.select('discover_cards', f'select=*&source_id=eq.{source_id}&order=id'),
            'tests': client.select('practice_cards', f'select=*,practice_links(discover_card_id)&source_id=eq.{source_id}&order=id')}


def edit_job(data):
    job_id, action = data['id'], data['action']
    folder = stages.job_folder(job_id)
    found = stages.rows('SELECT * FROM jobs WHERE id=?', (job_id,))
    if not found or found[0]['status'] in ('done', 'uploaded'):
        raise ValueError('job is missing or already uploaded')
    with stages.tick_lock():
        with cardmaker.lock(folder):
            if action == 'retry':
                step = found[0]['step']
                # Failed calls have no output. Remove completed output only for a failed final check.
                names = {'text': 'chunks.json', 'brief': 'brief.json', 'select': 'selection.json',
                         'pack': f'source/{job_id}/source.json'}
                if step in names:
                    (folder / names[step]).unlink(missing_ok=True)
                publishing = step in ('dry-run', 'upload', 'verify', 'clean')
                cardmaker.update_job(job_id, status='ready' if publishing else 'queued', error='', attempts=0)
            elif action != 'drop':
                raise ValueError('unknown job action')
        if action == 'drop':
            shutil.rmtree(folder)
            cardmaker.update_job(job_id, status='failed', error='dropped by owner')
    return {'ok': True}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, data, html=False):
        body = data if html else json.dumps(data, ensure_ascii=False)
        # Logs and provider errors may contain credentials; mask values at the response boundary.
        for name, value in settings.secrets().items():
            if name != 'PIPELINE_HOME' and value:
                body = body.replace(value, '[redacted]')
        encoded = body.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'text/html; charset=utf-8' if html else 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(encoded)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(encoded)

    def safe_host(self):
        return self.headers.get('Host') in (f'127.0.0.1:{self.server.server_port}', f'localhost:{self.server.server_port}')

    def do_GET(self):
        self.dispatch(False)

    def do_POST(self):
        self.dispatch(True)

    def dispatch(self, post):
        if not self.safe_host():
            self.reply(403, {'error': 'invalid Host'})
            return
        if post and not secrets.compare_digest(self.headers.get('X-Pipeline-Token', '').encode(), self.server.token.encode()):
            self.reply(403, {'error': 'missing or invalid token'})
            return
        try:
            url = urlsplit(self.path)
            params = parse_qs(url.query)
            if post:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 1_000_000:
                    raise ValueError('invalid request size')
                data = json.loads(self.rfile.read(length))
                if not isinstance(data, dict):
                    raise ValueError('expected an object')
                with self.server.edits:
                    result = self.post(url.path, data)
                self.reply(202 if url.path in ('/api/run', '/api/provider-test') else 200, result)
            elif url.path == '/':
                self.reply(200, Path(__file__).with_name('dashboard.html').read_text(encoding='utf-8').replace('__TOKEN__', self.server.token), True)
            else:
                self.reply(200, self.get(url.path, params))
        except (Exception, SystemExit) as exc:
            self.reply(400, {'error': str(exc)})

    def get(self, path, params):
        if path == '/api/settings':
            env = settings.secrets()
            return {'settings': settings.load(), 'secrets': {key: 'set' if env.get(key) or os.environ.get(key) else 'missing' for key in set(SECRET_KEYS) | env.keys()}}
        if path == '/api/state':
            return state()
        if path == '/api/books':
            return stages.rows('SELECT * FROM books ORDER BY priority,added_at')
        if path == '/api/jobs':
            return stages.rows('SELECT * FROM jobs ORDER BY created_at DESC')
        if path == '/api/feeds':
            return feeds.stats()
        if path == '/api/job':
            folder = stages.job_folder(params.get('id', [''])[0])
            return read_json(folder / 'report.json', {'status': 'no report yet'})
        if path == '/api/review':
            return review(params.get('id', [''])[0])
        if path == '/api/usage':
            return stages.rows("SELECT substr(at,1,10) AS day,provider,count(*) AS calls,sum(ok) AS ok,sum(tokens_in) AS tokens_in,sum(tokens_out) AS tokens_out FROM calls WHERE at>=? GROUP BY day,provider ORDER BY day DESC", ((dt.date.today() - dt.timedelta(days=13)).isoformat(),))
        if path == '/api/log':
            file = settings.home() / 'logs' / f'{dt.date.today()}.log'
            return {'text': file.read_text(encoding='utf-8', errors='replace') if file.exists() else 'No log yet.'}
        raise ValueError('unknown address')

    def post(self, path, data):
        if path == '/api/settings':
            # Validate the whole patch before writing any part of it.
            merged = copy.deepcopy(settings.load())
            for key, value in data.items():
                branch = merged
                parts = key.split('.')
                for part in parts[:-1]:
                    branch = branch.setdefault(part, {})
                branch[parts[-1]] = value
            settings._validated(merged)
            for key, value in data.items():
                settings.set_value(key, json.dumps(value))
            return {'ok': True}
        if path == '/api/run':
            if data.get('command') == 'eval':
                name = data['provider']
                if name not in settings.load()['providers']:
                    raise ValueError('unknown provider')
                return spawn(['eval', '--provider', name])
            if data.get('stage') not in stages.ORDER:
                raise ValueError('unknown stage')
            return spawn(['run', data['stage']])
        if path == '/api/provider-test':
            if data.get('provider') not in settings.load()['providers']:
                raise ValueError('unknown provider')
            return spawn(['provider-test', data['provider']])
        if path == '/api/publish':
            source_id, status = data['id'], data['status']
            stages.job_folder(source_id)
            if status not in ('published', 'hidden'):
                raise ValueError('invalid source status')
            stages.upload.Supabase().update('sources', f'id=eq.{source_id}&status=eq.draft', {'status': status})
            return {'ok': True}
        if path == '/api/job':
            return edit_job(data)
        if path == '/api/books':
            if data.get('action') == 'add':
                title = (data.get('title') or '').strip()
                if not title:
                    raise ValueError('title is required')
                return {'ok': True, 'book': scout.want(title, (data.get('author') or '').strip())}
            changes = {'skip': {'status': 'skipped'},
                       'retry': {'status': 'wanted', 'attempts': 0, 'next_try_at': '', 'last_error': ''}}
            if data.get('action') not in changes or not stages.rows('SELECT id FROM books WHERE id=?', (data.get('id'),)):
                raise ValueError('unknown book or action')
            fetch_telegram._update_book(data['id'], **changes[data['action']])
            return {'ok': True}
        raise ValueError('unknown address')


def server(port=None):
    httpd = ThreadingHTTPServer(('127.0.0.1', settings.load()['dashboard']['port'] if port is None else port), Handler)
    httpd.token = secrets.token_urlsafe(32)
    httpd.edits = threading.Lock()
    return httpd


def serve():
    with server() as httpd:
        print(f'Dashboard: http://127.0.0.1:{httpd.server_port}', flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass

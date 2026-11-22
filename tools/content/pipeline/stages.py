"""One clock, restartable stages, and verified publishing. Standard library only."""
from contextlib import closing, contextmanager
import datetime as dt
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from tools.content import upload
from . import cardmaker, feeds, fetch_telegram, requests, scout, settings, store

ORDER = ('publish', 'make', 'requests', 'fetch', 'feeds', 'scout')


def log(message):
    stamp = dt.datetime.now().astimezone()
    with (settings.home() / 'logs' / f'{stamp.date()}.log').open('a', encoding='utf-8') as stream:
        stream.write(f'{stamp.isoformat()} {message}\n')


@contextmanager
def tick_lock():
    # The OS releases this lock on death; the persistent PID file cannot race with an unlink.
    try:
        handle = cardmaker.lock(settings.home() / 'state', 'tick.lock')
    except ValueError:
        raise ValueError('another tick is running') from None
    try:
        handle.seek(0)
        handle.write(str(os.getpid()).encode())
        handle.truncate()
        handle.flush()
        yield
    finally:
        handle.close()


def job_folder(job_id):
    if not isinstance(job_id, str) or not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', job_id):
        raise ValueError('invalid job/source id')
    root = (settings.home() / 'jobs').resolve()
    folder = root / job_id
    if folder.resolve().parent != root or folder.is_symlink():
        raise ValueError('job folder must stay inside jobs')
    return folder


def rows(query, args=()):
    with closing(store.connect()) as db:
        return [dict(r) for r in db.execute(query, args)]


def make(config, deadline):
    jobs = rows("SELECT * FROM jobs WHERE status IN ('queued','waiting','making') ORDER BY created_at")
    if not jobs:
        return 'nothing', 'no queued jobs'
    job = jobs[0]
    status = cardmaker.run(job['id'], deadline=deadline)
    if status == 'review':
        fetch_telegram.notify(f"{job['title'] or job['id']}: needs review (see the Jobs page)")
    return ('failed' if status == 'failed' else 'stopped' if status in ('waiting', 'queued') else 'ok'), f"{job['id']}: {status}"


def publish(config, deadline):
    summaries, failed = [], False
    for row in rows("SELECT * FROM jobs WHERE status IN ('ready','uploaded') ORDER BY created_at"):
        if time.monotonic() >= deadline:
            return 'stopped', '; '.join(summaries + ['time limit'])
        job_id = row['id']
        folder = job_folder(job_id)
        try:
            if row['status'] == 'uploaded' and not folder.exists():
                # Death between rmtree and the final SQLite update: recheck the remote copy.
                archive = settings.home() / 'archive' / job_id
                counts = cardmaker.load(archive / 'report.json')['final'] if config['publish']['keep_archive'] else json.loads(row['counts'])
                client = upload.Supabase()
                if not client.select('sources', f'select=id&id=eq.{job_id}'):
                    raise ValueError('arrival check: source missing')
                for table, key in (('discover_cards', 'cards'), ('practice_cards', 'tests')):
                    if len(client.select(table, f'select=id&source_id=eq.{job_id}')) != counts[key]:
                        raise ValueError(f'arrival check: {table} count mismatch')
                cardmaker.update_job(job_id, status='done', error='', step='done')
                summaries.append(f'{job_id}: cleanup completed')
                continue
            # Keep the job lock outside deletion: Windows cannot remove an open lock file.
            with cardmaker.lock(folder):
                source = cardmaker.load(folder / 'source' / job_id / 'source.json')
                if source['id'] != job_id:
                    raise ValueError('packed source id differs from job id')
                client = upload.Supabase()
                existing = client.select('sources', f'select=id,is_sample&id=eq.{job_id}')
                sample = job_id.startswith('trial-') and source.get('is_sample') is True and existing and existing[0].get('is_sample') is True
                if existing and row['step'] == 'upload' and not sample:
                    raise ValueError('interrupted upload: keep local files; owner permission needed to repair the existing real source')
                resuming = row['status'] == 'uploaded' or row['step'] in ('verify', 'clean')
                if existing and not resuming and not (job_id.startswith('trial-') and existing[0].get('is_sample') is True
                                     and source.get('is_sample') is True):
                    raise ValueError('refusing to overwrite an existing real source')
                for extra in (() if existing and resuming else (['--dry-run'], [])):
                    cardmaker.update_job(job_id, step='dry-run' if extra else 'upload')
                    command = [sys.executable, str(settings.ROOT / 'tools/content/upload.py'),
                               str(folder / 'source' / job_id), *extra]
                    result = subprocess.run(command, cwd=settings.ROOT, capture_output=True,
                                            text=True, encoding='utf-8', errors='replace')
                    log(result.stdout + (result.stderr or ''))
                    if result.returncode:
                        raise ValueError(f'upload {extra or "write"} failed: {result.stdout} {result.stderr or ""}')
                cardmaker.update_job(job_id, step='verify')
                arrived = client.select('sources', f'select=id,status,is_sample&id=eq.{job_id}')
                if not arrived:
                    raise ValueError('arrival check: source missing')
                for table, key in (('discover_cards', 'discover_cards'), ('practice_cards', 'practice_cards')):
                    found = client.select(table, f'select=id&source_id=eq.{job_id}')
                    if len(found) != len(source[key]):
                        raise ValueError(f'arrival check: {table} count mismatch')
                cardmaker.update_job(job_id, status='uploaded', error='', step='clean')
                if config['publish']['keep_archive']:
                    archive = settings.home() / 'archive' / job_id
                    archive.mkdir(parents=True, exist_ok=True)
                    for name in ('report.json', 'brief.json', 'ideas.json'):
                        shutil.copy2(folder / name, archive / name)
            shutil.rmtree(folder)
            cardmaker.update_job(job_id, status='done', error='', step='done')
            message = (f"{source['title']}: {len(source['discover_cards'])} cards, "
                       f"{len(source['practice_cards'])} tests, "
                       + ('published' if source['status'] == 'published' else 'waiting for review'))
            summaries.append(message)
            log(message)
            fetch_telegram.notify(message)
        except (Exception, SystemExit) as exc:
            failed = True
            current = rows('SELECT status FROM jobs WHERE id=?', (job_id,))[0]['status']
            cardmaker.update_job(job_id, status='uploaded' if current == 'uploaded' else 'failed', error=str(exc))
            summaries.append(f'{job_id}: {exc}')
            log(f'ERROR publish {job_id}: {exc}')
    return ('failed' if failed else 'ok' if summaries else 'nothing'), '; '.join(summaries) or 'no ready jobs'


def fetch(config, deadline):
    return fetch_telegram.stage(config, deadline)


BUILTINS = {'make': make, 'publish': publish, 'fetch': fetch, 'feeds': feeds.stage, 'scout': scout.stage, 'requests': requests.stage}


def execute(name):
    config = settings.load()
    stage = config['stages'][name]
    started = cardmaker.now()
    deadline = time.monotonic() + stage['max_minutes'] * 60
    try:
        if isinstance(stage['run'], list):
            result = subprocess.run(stage['run'], cwd=settings.ROOT,
                                    env={**os.environ, 'PIPELINE_HOME': str(settings.home())},
                                    capture_output=True, text=True, encoding='utf-8', errors='replace',
                                    timeout=max(0.01, stage['max_minutes'] * 60))
            log(result.stdout + result.stderr)
            outcome, summary = ('ok' if result.returncode == 0 else 'failed'), f'exit {result.returncode}'
        elif name in BUILTINS:
            outcome, summary = BUILTINS[name](config, deadline)
        else:
            outcome, summary = 'nothing', 'not built'
    except subprocess.TimeoutExpired:
        outcome, summary = 'stopped', 'time limit'
    except (Exception, SystemExit) as exc:
        outcome, summary = 'failed', str(exc)
    with closing(store.connect()) as db, db:
        db.execute('INSERT INTO runs(stage,started_at,ended_at,result,summary) VALUES(?,?,?,?,?)',
                   (name, started, cardmaker.now(), outcome, summary))
    log(f'{name} {outcome}: {summary}')
    return outcome


def tick(stage=None):
    if stage is not None and stage not in ORDER:
        raise ValueError(f'unknown stage: {stage}')
    config = settings.load()
    if config['paused']:
        log('paused')
        return 'nothing'
    try:
        with tick_lock():
            if stage:
                return execute(stage)
            end = time.monotonic() + config['tick']['max_minutes'] * 60
            for name in ORDER:
                if time.monotonic() >= end:
                    break
                config = settings.load()
                if config['paused']:
                    break
                spec = config['stages'][name]
                now = dt.datetime.now().astimezone()
                last = rows('SELECT ended_at FROM runs WHERE stage=? ORDER BY id DESC LIMIT 1', (name,))
                due = not last or (now - dt.datetime.fromisoformat(last[0]['ended_at'])).total_seconds() >= spec['every_minutes'] * 60
                if spec['enabled'] and spec['hours'][0] <= now.hour < spec['hours'][1] and due:
                    execute(name)
            return 'ok'
    except ValueError as exc:
        log(str(exc))
        return 'stopped'


def remove_trial(source_id):
    job_folder(source_id)  # Validate before building queries or storage prefixes.
    if not source_id.startswith('trial-'):
        raise ValueError('remove-trial requires a trial- source id')
    client = upload.Supabase()
    source = client.select('sources', f'select=id,is_sample&id=eq.{source_id}')
    if not source or source[0].get('is_sample') is not True:
        raise ValueError('remove-trial requires an existing is_sample source')
    for bucket, prefix in (('media', f'sources/{source_id}'), ('media', f'cards/{source_id}'), ('source-files', source_id)):
        files = client.list_files(bucket, prefix)
        if files:
            client.call('DELETE', f'/storage/v1/object/{bucket}', {'prefixes': files})
        print(f'Deleted {len(files)} files from {bucket}/{prefix}')
    client.delete('sources', f'id=eq.{source_id}&is_sample=eq.true')
    print(f'Deleted {source_id} with its cards and tests.')

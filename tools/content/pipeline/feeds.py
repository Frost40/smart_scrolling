"""Licensed web items become ordinary queued jobs. Counts survive publishing."""
from contextlib import closing
import datetime as dt
import hashlib
import json
from pathlib import Path
import tempfile
import time

from . import cardmaker, licenses, settings, store

READERS = ('wikipedia_current_events', 'wikipedia_in_the_news', 'nasa_news', 'ec_press',
           'newsdata', 'currents', 'arxiv', 'hf_daily_papers', 'europepmc', 'wikipedia_article',
           'gutenberg', 'met', 'commons')


def identity(feed):
    key = json.dumps({k: feed[k] for k in ('reader', 'params', 'topics')}, sort_keys=True)
    return f'feed:{feed["reader"]}:{hashlib.sha256(key.encode()).hexdigest()[:16]}'


def stats(config=None):
    config = config or settings.load()
    file = settings.home() / 'state/feeds.json'
    state = cardmaker.load(file) if file.exists() else {}
    with closing(store.connect()) as db:
        return [{**feed, **dict(db.execute(
            'SELECT count(*) AS total, coalesce(sum(substr(created_at,1,10)=?),0) AS today FROM jobs WHERE origin=?',
            (dt.date.today().isoformat(), identity(feed))).fetchone()),
            **state.get(identity(feed), {'last_error': '', 'failures': 0})} for feed in config['feeds']]


def enqueue(item, topics, origin='link', sample=False):
    config = settings.load()
    if not licenses.allowed(item.get('license'), config['licenses']['allow_noncommercial']):
        raise ValueError(f'license refused: {item.get("license") or "unknown"}; supply --license for a link you may adapt')
    if not topics or any(t not in cardmaker.gates.known_topics() for t in topics):
        raise ValueError('feed needs known topics')
    details = dict(item.get('details') or {})
    content = item.get('text') or ''
    if item['kind'] == 'news':
        date = dt.date.fromisoformat(item['published_on'])
        details['show_until'] = (date + dt.timedelta(days=30)).isoformat()
        content = f'Published on {date.isoformat()}.\n\n{content}'
    extra = {k: item.get(k) for k in ('published_on', 'link', 'credit')}
    extra.update(license=licenses.normalize(item.get('license')), details=details, topics=topics,
                 feed_key=item['key'])
    with tempfile.TemporaryDirectory(dir=settings.home() / 'state') as temporary:
        path = Path(item['file']) if item.get('file') else Path(temporary) / 'text.txt'
        if not item.get('file'):
            if not (item.get('text') or '').strip():
                raise ValueError('reader returned empty text')
            path.write_text(content, encoding='utf-8')
        media = item.get('media')
        if media:
            from . import readers
            picture = Path(media['file'])
            extension = readers.image_extension(picture.read_bytes())
            if not (media.get('alt_source') or '').strip():
                raise ValueError('picture has no collection description')
            extra['media'] = {'file': 'image' + extension, 'alt_source': media['alt_source']}
        job_id = cardmaker.create(path, sample=sample, kind=item['kind'], title=item['title'],
                                   author=item.get('authors'), origin=origin, extra=extra,
                                   media=picture if media else None)
        folder = settings.home() / 'jobs' / job_id
        if not item.get('file'):
            cardmaker.write_file(folder / 'text.txt', content)
        with closing(store.connect()) as db, db:
            db.execute('INSERT OR IGNORE INTO seen(key,job_id,at) VALUES(?,?,?)',
                       (item['key'], job_id, cardmaker.now()))
        for downloaded in ([path] if item.get('file') else []) + ([picture] if media else []):
            if downloaded.resolve().parent == (settings.home() / 'state').resolve():
                downloaded.unlink()  # The job owns the copy; publishing must not leave another original in state.
    return job_id


def stage(config, deadline):
    from . import readers
    file = settings.home() / 'state/feeds.json'
    state = cardmaker.load(file) if file.exists() else {}
    summaries, failed, taken = [], False, 0
    for feed in stats(config):
        if time.monotonic() >= deadline:
            return 'stopped', '; '.join(summaries + ['time limit'])
        if not feed['enabled'] or feed['today'] >= feed['per_day']:
            continue
        key = identity(feed)
        try:
            with readers.request_budget(deadline):
                items = getattr(readers, feed['reader'])(feed['params'])
            count = 0
            for item in items:
                if time.monotonic() >= deadline or count >= feed['per_day'] - feed['today']:
                    break
                if not licenses.allowed(item.get('license'), config['licenses']['allow_noncommercial']):
                    continue
                with closing(store.connect()) as db:
                    if db.execute('SELECT 1 FROM seen WHERE key=?', (item['key'],)).fetchone():
                        continue
                job_id = enqueue(item, feed['topics'], key)
                count += 1
                summaries.append(f'{feed["reader"]}: {job_id}')
            taken += count
            state[key] = {'last_error': '', 'failures': 0}
        except Exception as exc:
            if time.monotonic() >= deadline:
                return 'stopped', '; '.join(summaries + ['time limit'])
            failed = True
            # Never retain API keys or a signed query string in an error from a reader.
            error = str(exc)
            for value in settings.secrets().values():
                if value:
                    error = error.replace(value, '[redacted]')
            state[key] = {'last_error': error, 'failures': state.get(key, {}).get('failures', 0) + 1}
            summaries.append(f'{feed["reader"]}: {error}')
        cardmaker.save(file, state)
    return ('failed' if failed else 'ok' if taken else 'nothing'), '; '.join(summaries) or 'no new allowed items'


def add_link(url, sample=False, license=None):
    from . import readers
    item = readers.from_url(url)
    if license:
        item['license'] = license
    # Unlike scheduled feeds, manual links may have their topics selected by the method.
    return enqueue(item, item.get('topics') or ['society'], sample=sample)

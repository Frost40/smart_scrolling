"""Rebuild the database master copy and fail closed before extending it."""
import copy
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import quote
from urllib.request import Request, build_opener, HTTPRedirectHandler

from tools.content import upload
from . import cardmaker as cm, settings


def rows(db, table, query):
    result = []
    for offset in range(0, 1000000, 500):
        page = db.select(table, query + f'&limit=500&offset={offset}')
        result.extend(page)
        if len(page) < 500:
            return result
    raise ValueError('database result too large; refusing a partial rebuild')


def snapshot(db, source_id):
    if not upload.SLUG.fullmatch(source_id):
        raise ValueError('invalid source id')
    source = rows(db, 'sources', f'select=*&id=eq.{source_id}')
    if len(source) != 1:
        raise ValueError('source not found')
    s = source[0]
    cards = rows(db, 'discover_cards', f'select=*&source_id=eq.{source_id}&order=id')
    tests = rows(db, 'practice_cards', f'select=*&source_id=eq.{source_id}&order=id')
    cids, tids = [c['id'] for c in cards], [t['id'] for t in tests]
    data = dict(source=s, cards=cards, practice=tests)
    data['topics'] = rows(db, 'source_topics', f'select=*&source_id=eq.{source_id}&order=topic_id')
    data['details'] = rows(db, upload.DETAILS[s['kind']][0], f'select=*&source_id=eq.{source_id}') if s['kind'] in upload.DETAILS else []
    data['card_topics'] = rows(db, 'card_topics', f'select=*&discover_card_id={upload.ids_in(cids)}&order=discover_card_id,topic_id') if cids else []
    data['links'] = rows(db, 'practice_links', f'select=*&practice_card_id={upload.ids_in(tids)}&order=practice_card_id,discover_card_id') if tids else []
    data['related'] = rows(db, 'related_cards', f'select=*&or=(discover_card_id.{upload.ids_in(cids)},related_card_id.{upload.ids_in(cids)})&order=discover_card_id,related_card_id') if cids else []
    return data


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('private storage redirect refused')


def rebuild(source_id, folder, client=None):
    db = client or upload.Supabase()
    folder = Path(folder)
    if folder.name != source_id or folder.exists() and any(folder.iterdir()):
        raise ValueError('rebuild needs an empty folder named after the source')
    data = snapshot(db, source_id)
    short = lambda value: value.removeprefix(source_id + '/')
    s = {'id': source_id, **{k: data['source'].get(k) for k in upload.SOURCE_FIELDS}}
    for role in ('cover', 'original', 'text'):
        if data['source'].get(role + '_path'):
            s[role] = {'existing': data['source'][role + '_path']}
    if data['details']:
        s[s['kind']] = {k: data['details'][0].get(k) for k in upload.DETAILS[s['kind']][1]}
    s['topics'] = [t['topic_id'] for t in data['topics']]
    s['discover_cards'], s['practice_cards'] = [], []
    for old in data['cards']:
        c = {'id': short(old['id']), **{k: old.get(k) for k in upload.CARD_FIELDS}}
        for role in ('media', 'poster', 'captions'):
            if old.get(role + '_path'):
                c[role] = {'existing': old[role + '_path']}
        c['topics'] = [t['topic_id'] for t in data['card_topics'] if t['discover_card_id'] == old['id']]
        c['related'] = [short(r['related_card_id'] if r['discover_card_id'] == old['id'] else r['discover_card_id'])
                        for r in data['related'] if old['id'] in (r['discover_card_id'], r['related_card_id'])]
        s['discover_cards'].append(c)
    for old in data['practice']:
        s['practice_cards'].append({'id': short(old['id']), **{k: old.get(k) for k in upload.PRACTICE_FIELDS},
                                   'tests': [short(r['discover_card_id']) for r in data['links'] if r['practice_card_id'] == old['id']]})
    folder.mkdir(parents=True, exist_ok=True)
    if s.get('text'):
        path = s['text']['existing']
        if path != f'{source_id}/text.txt':
            raise ValueError('unexpected text storage path')
        request = Request(db.url + '/storage/v1/object/authenticated/source-files/' + quote(path), headers=db.headers)
        with build_opener(NoRedirect).open(request, timeout=60) as response:
            content = response.read(50_000_001)
        if len(content) > 50_000_000:
            raise ValueError('text exceeds storage limit')
        (folder / 'text.txt').write_bytes(content)
    cm.save(folder / 'source.json', s)
    cm.save(folder / 'snapshot.json', data)
    return s


def upload_command(folder, dry=False):
    result = subprocess.run([sys.executable, str(Path(upload.__file__)), str(folder), *(['--dry-run'] if dry else [])],
                            capture_output=True, text=True, encoding='utf-8', timeout=300)
    if result.returncode:
        raise ValueError(result.stdout + result.stderr)
    return result.stdout


def dry_run(folder):
    match = re.search(r'(\d+) new sources, (\d+) updated; (\d+) new cards, (\d+) updated, (\d+) hidden; (\d+) new tests, (\d+) updated, (\d+) hidden', upload_command(folder, True))
    if not match:
        raise ValueError('unrecognised upload dry-run summary')
    return tuple(map(int, match.groups()))


def plan(folder, db):
    batch = upload.load_folder(str(folder))
    outside = upload.outside_card_refs(batch)
    known = {c['id'] for c in rows(db, 'discover_cards', f'select=id&id={upload.ids_in(outside)}&order=id')} if outside else set()
    return upload.validate(batch, {t['id'] for t in rows(db, 'topics', 'select=id&order=id')}, known)[0]


def differences(p, data):
    errors = []
    for key, expected, actual in [('source', [p['source']], [data['source']]),
                                   ('cards', p['cards'], data['cards']), ('practice', p['practice'], data['practice'])]:
        old = {r['id']: r for r in actual}
        if set(old) != {r['id'] for r in expected}:
            errors.append(key + ': ids differ')
        for row in expected:
            for field, value in row.items():
                if old.get(row['id'], {}).get(field) != value:
                    errors.append(f"{row['id']}.{field} differs")
    for key in ('topics', 'card_topics', 'links', 'related'):
        canonical = lambda values: {tuple(sorted(r.items())) for r in values}
        if canonical(p[key]) != canonical(data[key]):
            errors.append(key + ' differs')
    if p['details']:
        if len(data['details']) != 1 or any(data['details'][0].get(k) != v for k, v in p['details'].items()):
            errors.append('details differ')
    return errors


def no_change(folder):
    db = upload.Supabase()
    p = plan(folder, db)
    errors = differences(p, snapshot(db, p['source']['id']))
    summary = dry_run(folder)
    if errors or any(summary):
        print('; '.join(errors) or f'dry-run counts: {summary}')
        return False
    return True


def extend(source_id, new_cards, new_tests, *, replacements=(), folder=None):
    # Keep a failed upload's journal for inspection; never blindly replay a partial write.
    if folder is None:
        folder = Path(tempfile.mkdtemp(prefix='extend-', dir=settings.home() / 'jobs')) / source_id
    folder = Path(folder)
    journal = folder.parent / (source_id + '-upload.json')
    root = (settings.home() / 'jobs').resolve()
    if folder.name != source_id or root not in folder.resolve().parents or folder.is_symlink():
        raise ValueError('extension folder must stay inside pipeline jobs')
    phase = cm.load(journal) if journal.exists() else {}
    db = upload.Supabase()
    if phase.get('phase') in ('upload', 'verify'):
        p = plan(folder, db)
        errors = differences(p, snapshot(db, source_id))
        if errors:
            raise ValueError('interrupted upload needs review: ' + '; '.join(errors))
    elif phase.get('phase') != 'done':
        if not (folder / 'source.json').exists():
            rebuild(source_id, folder, db)
        if not no_change(folder):
            raise ValueError('unchanged rebuild differs; source left alone')
        baseline = snapshot(db, source_id)
        s = cm.load(folder / 'source.json')
        for key, additions in (('discover_cards', new_cards), ('practice_cards', new_tests)):
            ids = {r['id'] for r in s[key]}
            for item in additions:
                if item['id'] in ids:
                    raise ValueError('id already exists: ' + item['id'])
                ids.add(item['id'])
            s[key].extend(copy.deepcopy(additions))
        for replacement in replacements:
            matches = [c for c in s['discover_cards'] if c['id'] == replacement['id']]
            if len(matches) != 1:
                raise ValueError('replacement id does not exist')
            matches[0].update(replacement)
        cm.save(folder / 'source.json', s)
        p = plan(folder, db)
        expected = (0, 0, len(new_cards), len(replacements), 0, len(new_tests), 0, 0)
        if dry_run(folder) != expected:
            raise ValueError('extension dry run contains unexpected changes')
        # shortcut: the stage lock serializes writers; use a DB transaction if concurrent uploaders are needed.
        if snapshot(db, source_id) != baseline:
            raise ValueError('source changed during preparation; rebuild again')
        cm.save(journal, {'phase': 'upload'})
        upload_command(folder)
        cm.save(journal, {'phase': 'verify'})
        errors = differences(p, snapshot(db, source_id))
        if errors:
            raise ValueError('arrival check failed: ' + '; '.join(errors))
    cm.save(journal, {'phase': 'done'})
    if folder.exists():
        shutil.rmtree(folder)
    return True

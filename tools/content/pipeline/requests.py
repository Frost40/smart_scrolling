"""Restartable handling of the app's content requests."""
from contextlib import closing
import json
import re
import shutil
import time
from uuid import UUID

from tools.content import upload
from . import cardmaker as cm, gates, rebuild, settings, store, text


def unique(base, used):
    value, n = base, 2
    while value in used:
        value, n = f'{base}-{n}', n + 1
    used.add(value)
    return value


def generate(request, source, folder, deadline):
    cm.save(folder / 'meta.json', {**source, 'origin': 'request'})
    job = cm.Job(source['id'], deadline, folder)
    # Number the stored text without fetching book metadata or rewriting its bytes.
    paras = text.paragraphs(text.text_to_blocks((folder / 'text.txt').read_text(encoding='utf-8')))
    cm.save(folder / 'paragraphs.json', paras)
    cm.prepare(job)
    archive = settings.home() / 'archive' / source['id']
    brief = cm.load(archive / 'brief.json') if (archive / 'brief.json').exists() else cm.make_brief(job, None)
    old_cards, old_tests = source['discover_cards'], source['practice_cards']
    card_id = (request.get('discover_card_id') or '').removeprefix(source['id'] + '/')
    if not card_id and request.get('practice_card_id'):
        test_id = request['practice_card_id'].removeprefix(source['id'] + '/')
        links = next((t['tests'] for t in old_tests if t['id'] == test_id), [])
        card_id = next((c['id'] for c in old_cards if c['id'] in links), '')
    card = next((c for c in old_cards if c['id'] == card_id), None)
    kind = request['kind']
    if kind != 'more_cards' and card is None:
        raise ValueError('request has no card in its source')
    new_cards, replacements = [], []
    if kind == 'more_practice':
        card = {**card, 'ref': card_id}
        existing = {card_id: [{**t, 'card': card_id} for t in old_tests if card_id in t['tests'] or source['id'] + '/' + card_id in t['tests']]}
        passing, _, unclear = cm.quiz_solve(job, [card], '', {}, existing)
        if unclear:
            raise ValueError('blind solver could not understand the card')
        cards, tests = [card], passing
    elif kind == 'more_cards':
        ideas = cm.load(archive / 'ideas.json') if (archive / 'ideas.json').exists() else cm.extract(job, brief, None)
        titles = [c['title'] for c in old_cards]
        chosen, selection = cm.select(job, brief, ideas, True, titles, 10)
        cards, tests, _ = cm.make_cards(job, brief, chosen, old_cards)
        used = {c['id'] for c in old_cards}
        for c in cards:
            if c['title'].casefold() in {t.casefold() for t in titles}:
                continue
            row = {k: v for k, v in c.items() if k in upload.CARD_FIELDS}
            row.update(id=unique(cm.slug(c['title']), used), status=source['status'],
                       position=max((c.get('position') or 0 for c in old_cards), default=0) + len(new_cards) + 1,
                       topics=[t for t in selection['topics'] if t in job.topics])
            c['id'] = row['id']
            new_cards.append(row)
        cards = [c for c in cards if 'id' in c]
    elif kind == 'problem':
        ideas = cm.load(archive / 'ideas.json') if (archive / 'ideas.json').exists() else []
        idea = next((i for i in ideas if i['title'].casefold() == card['title'].casefold()), None)
        if idea is None:
            words = set(re.findall(r'\w+', (card['title'] + ' ' + card['front'] + ' ' + (card['back'] or '')).lower()))
            numbers = sorted(job.paras, key=lambda n: -len(words & set(re.findall(r'\w+', job.paras[n].lower()))))[:3]
            job.paras = {n: job.paras[n] for n in numbers}
            idea = dict(paragraphs=sorted(numbers), title=card['title'], claim=card['front'], support=card['back'] or '',
                        limits='', stance='claims', quote_text=card['front'] if card['format'] == 'quote' else '',
                        speaker=card.get('speaker') or '')
        idea = {**idea, 'ref': card_id, 'format': card['format'], 'level': card['level'] or 'intro'}
        job.ideas = {card_id: idea}
        card = {**card, 'ref': card_id, 'source_id': source['id']}
        values = {**job.source_values(), 'thesis': brief['thesis'], 'card_count': 1,
                  'cards_with_paragraphs': [cm.card_block(job, card, brief) + "\nReader's report: " + (request.get('message') or '')]}
        verdicts = cm.step(folder / 'reported.json', lambda: job.ask('judge', 'judge', values)['data'], cm.digest(values))
        verdict = next((v for v in verdicts['verdicts'] if v['ref'] == card_id), None)
        if not verdict:
            raise ValueError('judge returned no verdict')
        if all(verdict[k] for k in cm.SIX):
            raise ValueError('judge found the card correct: ' + (verdict['problem'] or 'all six checks passed'))
        if card['format'] == 'image':
            job.meta['media'] = {'file': card['media']}
        fixed, failed = cm.write_round(job, brief, [idea], 'repairs', 'p', [],
                                       {card_id: (card, verdict['problem'], verdict['fix'])})
        if not fixed:
            raise ValueError('repair failed: ' + '; '.join(f[2] for f in failed))
        replacement = {k: v for k, v in fixed[0].items() if k in ('title', 'front', 'back', 'speaker', 'media_alt')}
        if all(card.get(k) == v for k, v in replacement.items()):
            raise ValueError('repair made no change')
        replacements = [{**replacement, 'id': card_id}]
        cards, tests = [], {}
    else:
        raise ValueError('unknown request kind')
    used_tests, new_tests = {t['id'] for t in old_tests}, []
    for c in cards:
        target = c['id']
        existing_prompts = {gates.normalise(t['prompt']) for t in old_tests if target in t['tests']}
        for t in tests.get(c['ref'], []):
            if gates.normalise(t['prompt']) in existing_prompts:
                continue
            existing_prompts.add(gates.normalise(t['prompt']))
            new_tests.append({**{k: v for k, v in t.items() if k in upload.PRACTICE_FIELDS},
                              'id': unique(target + '-' + cm.SUFFIX[t['type']], used_tests),
                              'tests': [target], 'status': source['status']})
    new_cards = [c for c in new_cards if any(c['id'] in t['tests'] for t in new_tests)]
    if not new_cards and not new_tests and not replacements:
        raise ValueError('nothing passed the quality checks')
    return dict(cards=new_cards, tests=new_tests, replacements=replacements)


def stage(config, deadline):
    db = upload.Supabase()
    pending = rebuild.rows(db, 'content_requests', 'select=*&status=eq.open&order=created_at,id')
    state_file = settings.home() / 'state' / 'requests.json'
    previous = cm.load(state_file) if state_file.exists() else {}
    notices = {r['id']: {**r, 'reason': previous.get(r['id'], {}).get('reason', '')} for r in pending}
    cm.save(state_file, notices)
    done = 0
    for request in pending[:10]:
        if time.monotonic() >= deadline:
            return 'stopped', f'{done} requests handled; time limit'
        rid = str(UUID(request['id']))
        with closing(store.connect()) as local:
            attempt = local.execute('SELECT job_id FROM seen WHERE key=?', ('request:' + rid,)).fetchone()
        tries = int(attempt['job_id']) if attempt else 0
        if tries >= 3:
            continue
        folder = settings.home() / 'jobs' / ('request-' + rid)
        folder.mkdir(exist_ok=True)
        try:
            sid = request.get('source_id')
            if not sid:
                sid = (request.get('discover_card_id') or request.get('practice_card_id') or '').split('/')[0]
            if not upload.SLUG.fullmatch(sid):
                raise ValueError('request has no valid source')
            source_rows = db.select('sources', f'select=*&id=eq.{sid}')
            if not source_rows:
                raise ValueError('source not found')
            if config['trial'] and not (sid.startswith('trial-') and source_rows[0]['is_sample']):
                raise ValueError('trial mode leaves non-trial sources alone')
            output = folder / 'output.json'
            if not output.exists():
                source_folder = folder / 'baseline' / sid
                if not (source_folder / 'source.json').exists():
                    source = rebuild.rebuild(sid, source_folder)
                else:
                    source = cm.load(source_folder / 'source.json')
                if not rebuild.no_change(source_folder):
                    raise ValueError('unchanged rebuild differs; source left alone')
                if not (source_folder / 'text.txt').exists():
                    raise ValueError('source has no text.txt online')
                work = folder / f'generation-{tries + 1}'
                work.mkdir(exist_ok=True)
                if not (work / 'text.txt').exists():
                    (work / 'text.txt').write_bytes((source_folder / 'text.txt').read_bytes())
                result = generate(request, source, work, deadline)
                cm.save(output, result)
            result = cm.load(output)
            journal = folder / 'upload' / (sid + '-upload.json')
            if not journal.exists():
                baseline = cm.load(folder / 'baseline' / sid / 'snapshot.json')
                if rebuild.snapshot(db, sid) != baseline:
                    raise ValueError('source changed during generation; request needs a fresh review')
            rebuild.extend(sid, result['cards'], result['tests'], replacements=result['replacements'], folder=folder / 'upload' / sid)
            db.update('content_requests', f'id=eq.{rid}&status=eq.open', {'status': 'done', 'resolved_at': cm.now()})
            if not db.select('content_requests', f'select=id&id=eq.{rid}&status=eq.done'):
                raise ValueError('request completion could not be verified')
            if folder.resolve().parent != (settings.home() / 'jobs').resolve() or folder.is_symlink():
                raise ValueError('request folder escaped jobs')
            shutil.rmtree(folder)
            notices.pop(rid, None)
            done += 1
        except cm.Stop as exc:
            notices[rid]['reason'] = str(exc)
            cm.save(state_file, notices)
            return 'stopped', f'{done} requests handled; {exc}'
        except (Exception, SystemExit) as exc:
            with closing(store.connect()) as local, local:
                old = local.execute('SELECT job_id FROM seen WHERE key=?', ('request:' + rid,)).fetchone()
                tries = int(old['job_id']) + 1 if old else 1
                local.execute('INSERT OR REPLACE INTO seen(key,job_id,at) VALUES(?,?,?)', ('request:' + rid, str(tries), cm.now()))
            notices[rid]['reason'] = ('Owner review needed after 3 tries: ' if tries >= 3 else '') + str(exc)
        cm.save(state_file, notices)
    return ('ok' if done else 'nothing'), f'{done} requests handled; {len(notices)} open (see Overview)'

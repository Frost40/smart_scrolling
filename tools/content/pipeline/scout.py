"""Stage scout: fill and verify the wish list against Open Library (design section 6)."""
from contextlib import closing
import datetime as dt
import json
import os
from pathlib import Path
import re
import time
import unicodedata

from tools.content import upload
from . import cardmaker, gates, llm, readers, settings, store


def _log(message):
    from . import stages
    stages.log(message)

OL_SEARCH = 'https://openlibrary.org/search.json'
OL_FIELDS = 'key,title,author_name,first_publish_year,isbn,subject,language,readinglog_count,ratings_average'
PRIZE_PAGES = (
    'Pulitzer Prize for General Nonfiction',
    'National Book Award for Nonfiction',
    'Baillie Gifford Prize',
    'Royal Society Science Book Prize',
)
BAD_SUBJECT = re.compile(r'\b(fiction|novels?|poetry|poems?|juvenile)\b', re.I)


def topic_subjects():
    return json.loads(Path(__file__).with_name('topic_subjects.json').read_text(encoding='utf-8'))


def _plain(text):
    decomposed = unicodedata.normalize('NFKD', text or '')
    ascii_text = ''.join(ch for ch in decomposed if unicodedata.category(ch) != 'Mn')
    return ' '.join(re.sub(r'[^a-z0-9\s]', ' ', ascii_text.lower()).split())


def normalise(text):
    """Lowercase, no accents, no punctuation, subtitle after colon and leading 'the' dropped."""
    head = (text or '').split(':', 1)[0]
    cleaned = _plain(head)
    return cleaned[4:] if cleaned.startswith('the ') else cleaned


def _author_tokens(name):
    first = re.split(r'\s+and\s+|&|;', (name or '').strip(), maxsplit=1, flags=re.I)[0]
    if ',' in first:
        last, rest = [part.strip() for part in first.split(',', 1)]
        if rest and not re.match(r'^(?:jr|sr|ii|iii|iv|phd)\b', rest, re.I):
            first = f'{rest} {last}'
    return _plain(first).split()


def _authors_match(candidate_author, ol_authors):
    if not (candidate_author or '').strip():
        return True
    if not ol_authors:
        return False
    ct, ot = _author_tokens(candidate_author), _author_tokens(ol_authors[0])
    if not ct or not ot:
        return False
    if ct == ot:
        return True
    if ct[-1] != ot[-1]:
        return False
    return (ct[0] == ot[0]
            or (len(ct[0]) == 1 and ot[0].startswith(ct[0]))
            or (len(ot[0]) == 1 and ct[0].startswith(ot[0])))


def _bad_subject(subject):
    cleaned = re.sub(r'\bnon-?fiction\b', '', subject, flags=re.I)
    return bool(BAD_SUBJECT.search(cleaned))


def _fits(doc, year_from):
    if 'eng' not in (doc.get('language') or []):
        return 'not available in English'
    year = doc.get('first_publish_year')
    if not isinstance(year, int) or year < year_from:
        return f'year {year} before {year_from}'
    for subject in doc.get('subject') or []:
        if _bad_subject(subject):
            return f'refused subject ({subject})'
    return ''


def _app_sources():
    return upload.Supabase().select('sources', 'select=id,title,status,created_at,source_topics(topic_id)')


def _topic_stats(sources_rows):
    counts = {tid: 0 for tid in gates.known_topics()}
    for row in sources_rows:
        if row.get('status') == 'published':
            for link in row.get('source_topics') or []:
                tid = link.get('topic_id')
                if tid in counts:
                    counts[tid] += 1
    avg = sum(counts.values()) / len(counts) if counts else 0.0
    app_titles = {normalise(row['title']) for row in sources_rows if row.get('title')}
    return counts, avg, app_titles


def _is_known_book(doc, db):
    ol_work = doc.get('key') or ''
    norm_title = normalise(doc.get('title') or '')
    doc_authors = doc.get('author_name') or []
    doc_surname = _author_tokens(doc_authors[0])[-1:] if doc_authors else []
    for row_work, row_title, row_authors in db.execute('SELECT ol_work, title, authors FROM books'):
        if ol_work and row_work == ol_work:
            return 'already in books (same work)'
        if normalise(row_title) == norm_title:
            b_auths = json.loads(row_authors or '[]')
            b_surname = _author_tokens(b_auths[0])[-1:] if b_auths else []
            if not doc_surname or not b_surname or doc_surname == b_surname:
                return 'already in books (same title and author)'
    return ''


def admit(candidate, *, config=None, topic_counts=None, avg_sources=None, app_titles=None):
    """Four-step door: exists on Open Library, fits non-fiction rules, is new, gets scored."""
    config = config or settings.load()
    title = (candidate.get('title') or '').strip()
    author = (candidate.get('author') or '').strip()
    if not title:
        return None, 'empty title'
    if app_titles is None or topic_counts is None or avg_sources is None:
        topic_counts, avg_sources, app_titles = _topic_stats(_app_sources())
    params = {'title': title, 'fields': OL_FIELDS, 'limit': 5}
    if author:
        params['author'] = author
    searched = f'title={title!r}' + (f', author={author!r}' if author else '')
    docs = readers._api(OL_SEARCH, **params).get('docs') or []
    cand_norm = normalise(title)
    doc = next((d for d in docs
                if normalise(d.get('title', '')) == cand_norm
                and _authors_match(author, d.get('author_name') or [])), None)
    if doc is None:
        return None, f'not found on Open Library ({searched})'
    problem = _fits(doc, config['wishlist']['year_from'])
    if problem:
        return None, f'{problem} ({searched})'
    if normalise(doc.get('title', '')) in app_titles:
        return None, 'already a source in the app'
    with closing(store.connect()) as db:
        dup = _is_known_book(doc, db)
        if dup:
            return None, dup
    topics = list(dict.fromkeys(candidate.get('topics') or []))
    score = float(doc.get('readinglog_count') or 0)
    if candidate.get('origin') == 'prize_pages':
        score += 500
    if topics and avg_sources and any(topic_counts.get(t, 0) < avg_sources for t in topics):
        score += 300
    isbn13 = next((x for x in (doc.get('isbn') or []) if len(x) == 13 and x.isdigit()), '')
    now = cardmaker.now()
    ol_work = doc.get('key') or ''
    row = {
        'id': ol_work.rsplit('/', 1)[-1] or cardmaker.slug(doc['title']),
        'title': doc['title'],
        'authors': json.dumps(doc.get('author_name') or ([author] if author else []), ensure_ascii=False),
        'year': doc.get('first_publish_year'),
        'isbn13': isbn13,
        'ol_work': ol_work,
        'topics': json.dumps(topics, ensure_ascii=False),
        'origin': candidate.get('origin') or 'owner',
        'score': score,
        'priority': 1 if candidate.get('origin') == 'owner' else 2,
        'status': 'wanted',
        'attempts': 0,
        'next_try_at': '',
        'last_error': '',
        'job_id': '',
        'added_at': now,
        'updated_at': now,
    }
    return row, ''


def _insert_book(row):
    cols = list(row)
    with closing(store.connect()) as db, db:
        db.execute(f"INSERT INTO books ({','.join(cols)}) VALUES ({','.join('?' * len(cols))})",
                   tuple(row[c] for c in cols))


def want(title, author=''):
    row, reason = admit({'title': title, 'author': author, 'topics': [], 'origin': 'owner'})
    if row is None:
        raise ValueError(reason)
    _insert_book(row)
    return row


# ---------------------------------------------------------------- candidate sources

def openlibrary_trending(year_from=None):
    works = readers._json('https://openlibrary.org/trending/monthly.json?limit=50').get('works') or []
    out = []
    for w in works:
        if not w.get('title'):
            continue
        if year_from and isinstance(w.get('first_publish_year'), int) and w['first_publish_year'] < year_from:
            continue
        out.append({'title': w['title'], 'author': (w.get('author_name') or [''])[0],
                    'topics': [], 'origin': 'openlibrary_trending'})
    return out


def openlibrary_subjects(mapping=None, year_from=None, rotate_day=None):
    mapping = topic_subjects() if mapping is None else mapping
    out = []
    for topic_id, subjects in mapping.items():
        if not subjects:
            continue
        order = ([subjects[(rotate_day + i) % len(subjects)] for i in range(len(subjects))]
                 if rotate_day is not None else subjects)
        for subject in order:
            try:
                works = readers._json(f'https://openlibrary.org/subjects/{subject}.json?limit=50').get('works') or []
            except TimeoutError:
                return out
            except ValueError as exc:
                _log(f'scout: subject {subject} failed: {exc}')
                continue
            added = 0
            for w in works:
                if not w.get('title'):
                    continue
                if year_from is not None:
                    year = w.get('first_publish_year')
                    if (isinstance(year, int) and year < year_from) or any(_bad_subject(s) for s in w.get('subject') or []):
                        continue
                author = (w.get('authors') or [{}])[0].get('name', '')
                out.append({'title': w['title'], 'author': author,
                            'topics': [topic_id], 'origin': 'openlibrary_subjects'})
                added += 1
            if rotate_day is not None and added:
                break
    return out


def _clean_wiki(text):
    text = re.sub(r'<ref[^>]*/>|<ref[^>]*>.*?</ref>|<!--.*?-->', '', text or '', flags=re.S)
    def sortname(m):
        parts = [p.strip() for p in m[1].split('|')]
        kv = dict(p.split('=', 1) for p in parts if '=' in p)
        pos = [p for p in parts if '=' not in p]
        if '1' in kv and '2' in kv:
            return f"{kv['1']} {kv['2']}"
        if 'first' in kv or 'last' in kv:
            return f"{kv.get('first', '')} {kv.get('last', '')}".strip()
        return ' '.join(pos[:2])
    text = re.sub(r'\{\{[Ss]ortname\|([^}]*)\}\}', sortname, text)
    text = re.sub(r'\{\{[Ss]ort\|[^|}]*\|([^}]*)\}\}', r'\1', text)
    text = re.sub(r'\{\{[^}]*\}\}', '', text)
    text = re.sub(r'\[\[(?:[^|\]]*\|)?([^\]]+)\]\]', r'\1', text)
    text = text.replace("'''''", '').replace("'''", '').replace("''", '')
    return ' '.join(text.split()).strip(' ,')


def _strip_cell_attrs(cell):
    depth_b = depth_c = 0
    for i, ch in enumerate(cell):
        if cell[i:i + 2] == '[[':
            depth_b += 1
        elif cell[i:i + 2] == ']]' and depth_b:
            depth_b -= 1
        elif cell[i:i + 2] == '{{':
            depth_c += 1
        elif cell[i:i + 2] == '}}' and depth_c:
            depth_c -= 1
        elif ch == '|' and not depth_b and not depth_c:
            return cell[i + 1:].strip()
    return cell.strip()


def _parse_prize_wikitext(wikitext):
    found = []
    # Table rows: look for a cell containing an italic book title (''...'') preceded by an author cell.
    for row in re.split(r'\n\|-[^\n]*', wikitext or ''):
        cells = []
        for line in row.splitlines():
            s = line.strip()
            if s.startswith('|') and not s.startswith('|+') and not s.startswith('|}'):
                for part in s[1:].split('||'):
                    cells.append(_strip_cell_attrs(part))
            elif cells and not s.startswith('!'):
                cells[-1] += ' ' + s
        for idx, cell in enumerate(cells):
            if idx > 0 and "''" in cell:
                match = re.search(r"'{2,5}(.+?)'{2,5}", cell)
                title = _clean_wiki(match[1]) if match else ''
                author = re.split(r',\s*trans\.', _clean_wiki(cells[idx - 1]), maxsplit=1)[0].strip()
                if title and author:
                    found.append((title, author))
                break
    if not found:
        for line in (wikitext or '').splitlines():
            m = re.match(r"^\*+\s*(.+?),\s*'{2,5}(.+?)'{2,5}", line)
            if m:
                author, title = _clean_wiki(m[1]), _clean_wiki(m[2])
                if title and author:
                    found.append((title, author))
    return found


def prize_pages(pages=PRIZE_PAGES):
    per_page = []
    for page in pages:
        try:
            raw = readers._api(readers.WIKI, action='parse', page=page, prop='wikitext', format='json', formatversion=2)
            pairs = _parse_prize_wikitext(raw.get('parse', {}).get('wikitext', ''))
        except TimeoutError:
            raise
        except Exception as exc:
            _log(f'scout: prize page {page} failed: {exc}')
            continue
        if not pairs:
            _log(f'scout: unknown layout on prize page {page}')
            continue
        per_page.append([{'title': title, 'author': author, 'topics': [], 'origin': 'prize_pages'}
                         for title, author in reversed(pairs)])
    return list(_interleave(per_page))


def nyt_lists():
    key = settings.secrets().get('NYT_API_KEY') or os.environ.get('NYT_API_KEY')
    if not key:
        return []
    url = f'https://api.nytimes.com/svc/books/v3/lists/current/hardcover-nonfiction.json?api-key={key}'
    books = readers._json(url).get('results', {}).get('books') or []
    return [{'title': b['title'], 'author': b.get('author', ''), 'topics': [], 'origin': 'nyt_lists'}
            for b in books if b.get('title')]


def model_suggestions(config, topic_counts, known_titles):
    topics_meta = json.loads((Path(__file__).resolve().parents[1] / 'topics.json').read_text(encoding='utf-8'))
    ordered = sorted(topics_meta, key=lambda t: (topic_counts.get(t['id'], 0), t['id']))
    topics_text = '\n'.join(f"{t['id']}: {t['name']} ({topic_counts.get(t['id'], 0)})" for t in ordered)
    result = llm.call('scout', 'scout', {
        'count': config['wishlist']['model_suggestions_per_run'],
        'topics': topics_text,
        'known_titles': '\n'.join(known_titles[:300]) or '(none)',
    })
    if not result['ok']:
        _log(f"scout: model_suggestions skipped ({result['error']})")
        return []
    known = gates.known_topics()
    return [{'title': b['title'], 'author': b['author'], 'topics': [b['topic']], 'origin': 'model_suggestions'}
            for b in result['data']['books'] if b.get('topic') in known and b.get('title')]


# ---------------------------------------------------------------- stage orchestration

def _interleave(pools):
    buckets = [list(p) for p in pools if p]
    while buckets:
        next_round = []
        for bucket in buckets:
            yield bucket.pop(0)
            if bucket:
                next_round.append(bucket)
        buckets = next_round


def _pick_rows(admitted, needed, topic_balance):
    ranked = sorted(admitted, key=lambda r: r['score'], reverse=True)
    if not topic_balance:
        return ranked[:needed]
    picked, counts = [], {}
    seen_ids = set()
    # One highest-scoring book per topic first so every represented topic fits within target_wanted.
    for row in ranked:
        if len(picked) >= needed:
            return picked
        topics = json.loads(row['topics'])
        if topics and any(counts.get(t, 0) == 0 for t in topics):
            picked.append(row)
            seen_ids.add(row['id'])
            for t in topics:
                counts[t] = counts.get(t, 0) + 1
    for row in ranked:
        if len(picked) >= needed:
            break
        if row['id'] in seen_ids:
            continue
        topics = json.loads(row['topics'])
        if any(counts.get(t, 0) >= 3 for t in topics):
            continue
        picked.append(row)
        seen_ids.add(row['id'])
        for t in topics:
            counts[t] = counts.get(t, 0) + 1
    return picked


def stage(config, deadline):
    with closing(store.connect()) as db:
        wanted = db.execute("SELECT count(*) FROM books WHERE status='wanted'").fetchone()[0]
        book_rows = db.execute('SELECT title, authors FROM books ORDER BY added_at DESC').fetchall()
    target = config['wishlist']['target_wanted']
    if wanted >= target:
        return 'nothing', f'already {wanted} wanted'
    needed = target - wanted
    sources_rows = _app_sources()
    topic_counts, avg_sources, app_titles = _topic_stats(sources_rows)
    known_titles = list(dict.fromkeys(
        [r[0] for r in book_rows if r[0]]
        + [r['title'] for r in sorted(sources_rows, key=lambda x: x.get('created_at') or '', reverse=True) if r.get('title')]
    ))[:300]
    existing_keys = {(normalise(r[0]), tuple(_author_tokens(json.loads(r[1] or '[]')[0])[-1:]) if json.loads(r[1] or '[]') else ())
                     for r in book_rows if r[0]}

    enabled = config['wishlist']['sources']
    pools, admitted, covered, seen_cands = [], {}, set(), set()
    timed_out = False

    def try_admit(cand):
        nonlocal timed_out
        if time.monotonic() >= deadline:
            timed_out = True
            return False
        nt = normalise(cand.get('title', ''))
        surname = tuple(_author_tokens(cand.get('author', ''))[-1:]) if cand.get('author') else ()
        if not nt or nt in app_titles or (nt, surname) in existing_keys or (nt, surname) in seen_cands:
            return False
        seen_cands.add((nt, surname))
        try:
            row, _ = admit(cand, config=config, topic_counts=topic_counts,
                           avg_sources=avg_sources, app_titles=app_titles)
        except TimeoutError:
            timed_out = True
            return False
        except ValueError as exc:
            _log(f"scout: {cand.get('title')!r} error: {exc}")
            return False
        if row is None:
            return False
        wid = row['ol_work'] or row['id']
        covered.update(json.loads(row['topics']))
        if wid in admitted:
            merged = list(dict.fromkeys(json.loads(admitted[wid]['topics']) + json.loads(row['topics'])))
            admitted[wid]['topics'] = json.dumps(merged, ensure_ascii=False)
            admitted[wid]['score'] = max(admitted[wid]['score'], row['score'])
        else:
            admitted[wid] = row
        return True

    with readers.request_budget(deadline):
        try:
            if enabled.get('model_suggestions'):
                pools.append(model_suggestions(config, topic_counts, known_titles))
            if enabled.get('prize_pages'):
                pools.append(prize_pages())
            if enabled.get('openlibrary_trending'):
                pools.append(openlibrary_trending(config['wishlist']['year_from']))
            if enabled.get('nyt_lists'):
                pools.append(nyt_lists())
            if enabled.get('openlibrary_subjects'):
                day = dt.date.today().toordinal()
                items = list(topic_subjects().items())
                for offset in range(len(items)):
                    if time.monotonic() >= deadline:
                        timed_out = True
                        break
                    tid, subs = items[(day + offset) % len(items)]
                    cands = openlibrary_subjects({tid: subs}, year_from=config['wishlist']['year_from'], rotate_day=day)
                    rest = []
                    got_one = False
                    for cand in cands:
                        if not got_one and not timed_out:
                            got_one = try_admit(cand)
                        else:
                            rest.append(cand)
                    if rest:
                        pools.append(rest)
        except TimeoutError:
            timed_out = True

        limit = max(needed + 15, 45)
        for cand in _interleave(pools):
            if timed_out or time.monotonic() >= deadline:
                timed_out = True
                break
            if len(admitted) >= limit:
                break
            try_admit(cand)

    picked = _pick_rows(list(admitted.values()), needed, config['wishlist']['topic_balance'])
    for row in picked:
        _insert_book(row)
    if not picked:
        return ('stopped', 'time limit') if timed_out else ('nothing', 'no new books admitted')
    return 'ok', f'added {len(picked)} books' + (' (time limit)' if timed_out else '')

"""Small, bounded public-source readers. No models and no publisher-page scraping."""
import csv
from contextlib import closing, contextmanager
from contextvars import ContextVar
from datetime import date, timedelta
from email.utils import parsedate_to_datetime
import hashlib
from html.parser import HTMLParser
import io
import json
import re
import time
from urllib.parse import urlencode, urlparse, unquote
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET
import zipfile

from . import licenses, settings, text as book_text

WIKI = 'https://en.wikipedia.org/w/api.php'
GUTENBERG = 'https://mirror.cs.odu.edu/gutenberg-epub/'
_last_request = {}
_deadline = ContextVar('reader_deadline', default=None)


@contextmanager
def request_budget(deadline):
    token = _deadline.set(deadline)
    try:
        yield
    finally:
        _deadline.reset(token)


def _download(url, headers=None, limit=5 * 1024 * 1024):
    host = urlparse(url).hostname or ''
    if urlparse(url).scheme not in ('http', 'https') or not host:
        raise ValueError('Expected an HTTP(S) source URL')
    pause = 3 if host.endswith('arxiv.org') else 2 if 'gutenberg' in url else 1
    delay = max(0, _last_request.get(host, 0) + pause - time.monotonic())
    deadline = _deadline.get()
    if deadline is not None and deadline - time.monotonic() <= delay:
        raise TimeoutError('Reader request budget exhausted')
    time.sleep(delay)
    timeout = 30 if deadline is None else min(30, deadline - time.monotonic())
    if timeout <= 0:
        raise TimeoutError('Reader request budget exhausted')
    agent = 'SmartScrollingPipeline/1.0 (' + settings.secrets().get('CONTACT_EMAIL', '') + ')'
    try:
        request = Request(url, headers={'User-Agent': agent})
        for name, value in (headers or {}).items():
            request.add_unredirected_header(name, value)
        with urlopen(request, timeout=timeout) as response:
            if int(response.headers.get('Content-Length', 0)) > limit:
                raise ValueError('Source response exceeds its size limit')
            data = response.read(limit + 1)
            if len(data) > limit:
                raise ValueError('Source response exceeds its size limit')
            return data
    except Exception as exc:
        if deadline is not None and time.monotonic() >= deadline:
            raise TimeoutError('Reader request budget exhausted') from None
        # URLs can contain private API keys; exception strings must never reach logs.
        raise ValueError(f'{host}: source request failed ({type(exc).__name__})') from None
    finally:
        _last_request[host] = time.monotonic()


def get(url, headers=None):
    return _download(url, headers)


def html_to_text(value):
    parser = book_text._Html()
    parser.feed(value or '')
    parser.flush()
    return '\n\n'.join(block['text'] for block in parser.blocks)


def _json(url):
    return json.loads(get(url))


def _api(base, **params):
    return _json(base + '?' + urlencode(params))


def _date(value):
    if not value:
        return date.today().isoformat()
    if re.match(r'^\d{4}-\d{2}-\d{2}', value):
        return value[:10]
    return parsedate_to_datetime(value).date().isoformat()


def _item(key, kind, title, link, license, credit, content, published=None,
          authors=None, details=None, media=None):
    return dict(key=key, kind=kind, title=title, link=link, license=license,
                credit=credit, text=content, published_on=_date(published),
                authors=authors or [], details=details or {}, topics=[], media=media)


def _news(key, title, link, content, publisher, license, published=None, credit=None):
    day = _date(published)
    return _item(key, 'news', title, link, license, credit or publisher, content, day,
                 details={'newspaper': publisher,
                          'show_until': (date.fromisoformat(day) + timedelta(days=30)).isoformat()})


def _wiki_article(title, lead=False):
    params = dict(action='query', prop='extracts', explaintext=1, redirects=1,
                  format='json', formatversion=2, titles=title)
    if lead:
        params['exintro'] = 1
    page = _api(WIKI, **params)['query']['pages'][0]
    if page.get('missing') or not page.get('extract'):
        raise ValueError('Wikipedia article has no text')
    return page


def _seen_keys():
    from . import store
    with closing(store.connect()) as db:
        return {row[0] for row in db.execute('SELECT key FROM seen')}


def wikipedia_article(params=None):
    params = params or {}
    title = params.get('title')
    if not title and params.get('from') == 'vital':
        links = _api(WIKI, action='parse', page='Wikipedia:Vital_articles',
                     prop='links', format='json', formatversion=2)['parse']['links']
        used = _seen_keys()
        title = next((x['title'] for x in links if x.get('ns') == 0
                      and 'wikipedia:' + x['title'].replace(' ', '_') not in used), None)
    if not title:
        raise ValueError('Wikipedia reader needs a title or an unused vital article')
    page = _wiki_article(title)
    title = page['title']
    link = 'https://en.wikipedia.org/wiki/' + title.replace(' ', '_')
    return [_item('wikipedia:' + title.replace(' ', '_'), 'other', title, link,
                  'CC BY-SA 4.0', 'Wikipedia contributors', page['extract'])]


class _NewsList(HTMLParser):
    """One top-level news group, including its nested reports and first encyclopedia link."""
    def __init__(self):
        super().__init__()
        self.stack, self.items = [], []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'li':
            self.stack.append({'parts': [], 'title': None})
        elif tag == 'a' and self.stack:
            href = attrs.get('href', '')
            if href.startswith('/wiki/') and ':' not in unquote(href[6:]):
                for item in self.stack:
                    if not item['title']:
                        item['title'] = unquote(href[6:]).replace('_', ' ')

    def handle_data(self, data):
        for item in self.stack:
            item['parts'].append(data)

    def handle_endtag(self, tag):
        if tag == 'li' and self.stack:
            item = self.stack.pop()
            if not self.stack and item['title']:
                self.items.append((' '.join(''.join(item['parts']).split()), item['title']))


def wikipedia_current_events(params=None):
    params = params or {}
    day = date.fromisoformat(params['date']) if params.get('date') else date.today() - timedelta(days=1)
    page = f'Portal:Current_events/{day.year}_{day:%B}_{day.day}'
    raw = _api(WIKI, action='parse', page=page, prop='text', format='json', formatversion=2)
    parser = _NewsList()
    parser.feed(raw['parse']['text'])
    result = []
    for story, title in parser.items[:params.get('limit', 10)]:
        lead = _wiki_article(title, True)['extract']
        link = 'https://en.wikipedia.org/wiki/' + title.replace(' ', '_')
        key = 'wiki-news:' + day.isoformat() + ':' + hashlib.sha256(story.encode()).hexdigest()[:16]
        result.append(_news(key, story[:180], link, story + '\n\n' + lead,
                            'Wikipedia Current events', 'CC BY-SA 4.0', day.isoformat()))
    return result


def wikipedia_in_the_news(params=None):
    params = params or {}
    day = date.fromisoformat(params['date']) if params.get('date') else date.today()
    raw = _json(f'https://api.wikimedia.org/feed/v1/wikipedia/en/featured/{day:%Y/%m/%d}')
    result = []
    for row in raw.get('news', [])[:params.get('limit', 10)]:
        if not row.get('links'):
            continue
        article = row['links'][0]
        story = html_to_text(row['story'])
        title = article.get('title') or article['normalizedtitle']
        link = article.get('content_urls', {}).get('desktop', {}).get('page') or 'https://en.wikipedia.org/wiki/' + title
        lead = _wiki_article(title, True)['extract']
        result.append(_news('wiki-itn:' + hashlib.sha256(story.encode()).hexdigest()[:20],
                            story[:180], link, story + '\n\n' + lead,
                            'Wikipedia Current events', 'CC BY-SA 4.0', day.isoformat()))
    return result


def rss(data):
    root = ET.fromstring(data)
    rows = root.findall('./channel/item') or root.findall('{http://www.w3.org/2005/Atom}entry')
    return [{node.tag.rsplit('}', 1)[-1]: node.text or node.get('href', '') for node in row}
            for row in rows]


def nasa_news(params=None):
    rows = rss(get('https://www.nasa.gov/news-release/feed/'))
    return [_news('nasa:' + r['link'], r['title'], r['link'],
                  html_to_text(r.get('encoded') or r.get('description', '')), 'NASA',
                  'Public domain', r.get('pubDate')) for r in rows[:(params or {}).get('limit', 10)]]


def ec_press(params=None):
    result = []
    for row in rss(get('https://ec.europa.eu/commission/presscorner/api/rss?language=en'))[:(params or {}).get('limit', 10)]:
        identifier = row['link'].rstrip('/').split('/')[-1]
        raw = _api('https://ec.europa.eu/commission/presscorner/api/documents',
                   reference=identifier.replace('_', '/').upper(), language='en')
        # The API's document text is HTML; an empty response must fail rather than use RSS truncation.
        content = raw.get('docuLanguageResource', {}).get('htmlContent')
        if not isinstance(content, str) or not content.strip():
            raise ValueError('EC full release text is unavailable')
        result.append(_news('ec:' + identifier, row['title'], row['link'], html_to_text(content),
                            'European Commission', 'CC BY 4.0', row.get('pubDate')))
    return result


def newsdata(params=None):
    params = params or {}
    key = settings.secrets().get('NEWSDATA_API_KEY')
    if not key:
        raise ValueError('NEWSDATA_API_KEY is missing')
    query = dict(apikey=key, language='en')
    if params.get('category'):
        query['category'] = params['category']
    result = []
    for row in _api('https://newsdata.io/api/1/latest', **query).get('results', []):
        if params.get('category') and params['category'] not in row.get('category', []):
            continue
        content = html_to_text(row.get('title', '') + '\n\n' + (row.get('description') or ''))
        if len(content.split()) < 40:
            continue
        publisher = row.get('source_name') or row.get('source_id')
        if not publisher or not row.get('link'):
            continue
        result.append(_news('newsdata:' + row['article_id'], row['title'], row['link'], content,
                            publisher, 'NewsData.io personal/internal use', row.get('pubDate'),
                            publisher + '. Powered by NewsData.io API (https://newsdata.io). News data by NewsData.io.'))
    return result


def currents(params=None):
    params = params or {}
    key = settings.secrets().get('CURRENTS_API_KEY')
    if not key:
        raise ValueError('CURRENTS_API_KEY is missing')
    query = {'language': 'en'}
    if params.get('category'):
        query['category'] = params['category']
    raw = json.loads(get('https://api.currentsapi.services/v1/latest-news?' + urlencode(query),
                         {'Authorization': 'Bearer ' + key}))
    if raw.get('status') != 'ok':
        raise ValueError('Currents API returned an error')
    result = []
    for row in raw.get('news', []):
        if params.get('category') and params['category'] not in row.get('category', []):
            continue
        content = html_to_text(row.get('title', '') + '\n\n' + (row.get('description') or ''))
        link = row.get('url') or ''
        address = urlparse(link)
        if len(content.split()) < 40 or address.scheme not in ('http', 'https') or not address.hostname:
            continue
        # Currents returns a journalist's author name, not a publisher field.
        publisher = address.hostname.removeprefix('www.')
        credit = publisher + ' via Currents API (https://currentsapi.services/)'
        result.append(_news('currents:' + row['id'], row['title'], link, content,
                            publisher, licenses.CURRENTS, row.get('published'), credit))
    return result


def arxiv(params=None):
    params = params or {}
    query = dict(max_results=params.get('limit', 10))
    if params.get('id'):
        query['id_list'] = params['id']
    else:
        query.update(search_query=params.get('query', 'cat:cs.AI'), sortBy='submittedDate', sortOrder='descending')
    root = ET.fromstring(get('https://export.arxiv.org/api/query?' + urlencode(query)))
    ns = {'a': 'http://www.w3.org/2005/Atom', 'x': 'http://arxiv.org/schemas/atom'}
    result = []
    for row in root.findall('a:entry', ns):
        identifier = row.findtext('a:id', '', ns).split('/abs/')[-1]
        if not re.fullmatch(r'(?:\d{4}\.\d{4,5}|[a-z-]+(?:\.[A-Z]{2})?/\d{7})(?:v\d+)?', identifier):
            continue
        result.append(_item('arxiv:' + re.sub(r'v\d+$', '', identifier), 'paper',
                            ' '.join(row.findtext('a:title', '', ns).split()),
                            'https://arxiv.org/abs/' + identifier, 'CC0', 'arXiv',
                            ' '.join(row.findtext('a:summary', '', ns).split()),
                            row.findtext('a:published', '', ns),
                            [a.findtext('a:name', '', ns) for a in row.findall('a:author', ns)],
                            {'doi': row.findtext('x:doi', '', ns), 'journal': 'arXiv', 'paper_status': 'preprint'}))
    return result


def hf_daily_papers(params=None):
    rows = _json('https://huggingface.co/api/daily_papers?limit=' + str((params or {}).get('limit', 10)))
    ids = [r['paper']['id'] for r in rows]
    return arxiv({'id': ','.join(ids), 'limit': len(ids)}) if ids else []


def europepmc(params=None):
    from .licenses import allowed
    params = params or {}
    query = '(' + params.get('query', '*') + ') AND OPEN_ACCESS:y'
    raw = _api('https://www.ebi.ac.uk/europepmc/webservices/rest/search', query=query,
               format='json', resultType='core', pageSize=params.get('limit', 10))
    result = []
    for row in raw.get('resultList', {}).get('result', []):
        license = row.get('license', 'unknown')
        content = html_to_text(row.get('abstractText', ''))
        if row.get('pmcid') and allowed(license):
            full = ET.fromstring(get('https://www.ebi.ac.uk/europepmc/webservices/rest/' + row['pmcid'] + '/fullTextXML'))
            body = full.find('body')
            if body is not None:
                content = '\n\n'.join(' '.join(p.itertext()).strip() for p in body.iter('p'))
        if not content:
            continue
        identifier = row.get('pmcid') or row['id']
        result.append(_item('europepmc:' + identifier, 'paper', row['title'],
                            'https://europepmc.org/articles/' + identifier if row.get('pmcid') else 'https://europepmc.org/article/' + row['source'] + '/' + identifier,
                            license, row.get('authorString', 'Europe PMC'), content,
                            row.get('firstPublicationDate'),
                            [a['fullName'] for a in row.get('authorList', {}).get('author', [])],
                            {'doi': row.get('doi', ''), 'journal': row.get('journalInfo', {}).get('journal', {}).get('title', ''),
                             'paper_status': 'published'}))
    return result


def gutenberg(params=None):
    params = params or {}
    target = settings.home() / 'state' / 'pg_catalog.csv'
    if not target.exists() or time.time() - target.stat().st_mtime > 7 * 86400:
        data = _download(GUTENBERG + 'feeds/pg_catalog.csv', limit=30 * 1024 * 1024)
        temporary = target.with_suffix('.tmp')
        temporary.write_bytes(data)
        temporary.replace(target)
    rows = csv.DictReader(io.StringIO(target.read_text(encoding='utf-8-sig')))
    result = []
    seen = set() if params.get('id') or params.get('title') else _seen_keys()
    for row in rows:
        if params.get('id') and row['Text#'] != str(params['id']):
            continue
        if params.get('title') and params['title'].casefold() not in row['Title'].casefold():
            continue
        if params.get('subject') and params['subject'].casefold() not in row['Subjects'].casefold():
            continue
        if row.get('Type') != 'Text' or 'en' not in row.get('Language', '').split('; '):
            continue
        identifier = row['Text#']
        if 'gutenberg:' + identifier in seen:
            continue
        content = _download(GUTENBERG + identifier + '/pg' + identifier + '-images-3.epub', limit=50 * 1024 * 1024)
        if not content.startswith(b'PK\x03\x04'):
            raise ValueError('Gutenberg response is not an EPUB archive')
        with zipfile.ZipFile(io.BytesIO(content)) as archive:
            rights = [node.text or '' for name in archive.namelist() if name.endswith('.opf')
                      for node in ET.fromstring(archive.read(name)).iter()
                      if node.tag == '{http://purl.org/dc/elements/1.1/}rights']
        if not any(value.casefold().startswith('public domain') for value in rights):
            continue
        path = settings.home() / 'state' / ('pg' + identifier + '.epub')
        path.write_bytes(content)
        item = _item('gutenberg:' + identifier, 'book', row['Title'],
                     'https://www.gutenberg.org/ebooks/' + identifier, 'Public domain',
                     'Project Gutenberg', '', row.get('Issued'), [row.get('Authors', '')])
        item['file'] = str(path)
        result.append(item)
        if len(result) >= params.get('limit', 1):
            break
    return result


def image_extension(data):
    if len(data) > 50 * 1024 * 1024:
        raise ValueError('Image exceeds 50 MB')
    if data.startswith(b'\xff\xd8\xff'):
        return '.jpg'
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        return '.png'
    if data.startswith(b'RIFF') and data[8:12] == b'WEBP':
        return '.webp'
    raise ValueError('Expected JPEG, PNG or WebP image bytes')


def _image(url, alt):
    stem = settings.home() / 'state' / hashlib.sha256(url.encode()).hexdigest()
    for extension in ('.jpg', '.png', '.webp'):
        existing = stem.with_suffix(extension)
        if existing.exists():
            image_extension(existing.read_bytes())
            return {'file': str(existing), 'alt_source': alt}
    data = _download(url, limit=50 * 1024 * 1024)
    path = stem.with_suffix(image_extension(data))
    path.write_bytes(data)
    return {'file': str(path), 'alt_source': alt}


def met(params=None):
    params = params or {}
    ids = [params['id']] if params.get('id') else _api('https://collectionapi.metmuseum.org/public/collection/v1.1/search',
        hasImages='true', isPublicDomain='true', q=params.get('query', 'sunflower')).get('objectIDs') or []
    seen = set() if params.get('id') else _seen_keys()
    for identifier in [value for value in ids if 'met:' + str(value) not in seen][:10]:
        row = _json('https://collectionapi.metmuseum.org/public/collection/v1/objects/' + str(identifier))
        if not row.get('isPublicDomain') or not row.get('primaryImage'):
            continue
        description = '\n\n'.join(str(row.get(k) or '') for k in
                                    ('title', 'artistDisplayName', 'objectDate', 'medium', 'dimensions', 'creditLine'))
        return [_item('met:' + str(identifier), 'other', row['title'], row['objectURL'],
                      'CC0', row.get('artistDisplayName') or 'The Metropolitan Museum of Art', description,
                      authors=[row['artistDisplayName']] if row.get('artistDisplayName') else [],
                      media=_image(row['primaryImage'], description))]
    return []


def commons(params=None):
    from .licenses import allowed
    params = params or {}
    query = dict(action='query', prop='imageinfo', iiprop='url|extmetadata', format='json')
    if params.get('title'):
        query['titles'] = params['title']
    else:
        query.update(generator='search', gsrsearch=params.get('query', 'sunflower'), gsrnamespace=6, gsrlimit=10)
    seen = set() if params.get('title') else _seen_keys()
    while True:
        response = _api('https://commons.wikimedia.org/w/api.php', **query)
        for row in response.get('query', {}).get('pages', {}).values():
            if 'commons:' + row['title'] in seen:
                continue
            info = row.get('imageinfo', [{}])[0]
            meta = info.get('extmetadata', {})
            license = meta.get('LicenseShortName', {}).get('value', 'unknown')
            if not allowed(license):
                continue
            description = html_to_text(meta.get('ImageDescription', {}).get('value', row['title']))
            artist = html_to_text(meta.get('Artist', {}).get('value', 'Wikimedia Commons'))
            return [_item('commons:' + row['title'], 'other', row['title'].removeprefix('File:'),
                          info['descriptionurl'], license, artist, description, authors=[artist],
                          media=_image(info['url'], description))]
        continuation = response.get('continue')
        if not continuation or params.get('title'):
            return []
        query.update(continuation)


def from_url(url):
    parsed = urlparse(url)
    host, path = parsed.hostname or '', unquote(parsed.path)
    if host in ('en.wikipedia.org', 'en.m.wikipedia.org') and path.startswith('/wiki/'):
        rows = wikipedia_article({'title': path[6:].replace('_', ' ')})
    elif host in ('arxiv.org', 'www.arxiv.org', 'export.arxiv.org') and path.startswith(('/abs/', '/pdf/')):
        rows = arxiv({'id': path.split('/', 2)[2].removesuffix('.pdf')})
    elif host in ('europepmc.org', 'www.europepmc.org') and re.search(r'PMC\d+', path):
        rows = europepmc({'query': 'PMCID:' + re.search(r'PMC\d+', path)[0]})
    elif host in ('europepmc.org', 'www.europepmc.org') and re.fullmatch(r'/article/[A-Za-z]+/\d+/?', path):
        source, identifier = path.strip('/').split('/')[1:]
        rows = europepmc({'query': 'EXT_ID:' + identifier + ' AND SRC:' + source.upper()})
    elif host in ('gutenberg.org', 'www.gutenberg.org') and re.search(r'/ebooks/\d+', path):
        rows = gutenberg({'id': re.search(r'/ebooks/(\d+)', path)[1]})
    else:
        return _item('url:' + hashlib.sha256(url.encode()).hexdigest(), 'other',
                     path.rstrip('/').split('/')[-1] or host, url, 'unknown', host,
                     html_to_text(get(url).decode('utf-8', errors='replace')))
    if not rows:
        raise ValueError('Source URL returned no usable item')
    return rows[0]

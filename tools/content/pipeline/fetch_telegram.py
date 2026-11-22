"""Stage fetch: books from the Telegram bot (design section 7). The only file that imports Telethon,
and only inside functions, so the rest of the pipeline and the tests work without it.

Reading the bot's answers (`options`, `rule_filter`, `pick`, `check_file`) are pure functions on saved
messages; talking to Telegram is the `Bot` class. The tests replay saved probes through a fake bot.
"""

import datetime as dt
import hashlib
import json
import random
import re
import time
import zipfile

from . import llm, settings

STOP = ('the', 'a', 'an', 'of', 'and', 'on', 'in', 'to', 'for', 'by', 'with', 'or')
FORMATS = ('epub', 'azw3', 'mobi', 'fb2', 'pdf', 'djvu', 'txt', 'rtf', 'doc', 'docx', 'zip', 'cbz', 'cbr')
# A page button: a nav word with numbers or symbols ("(2) next »"), a number in symbols ("- 1 -"),
# "2 / 7", or symbols only ("»"). A bare number is not: a bot may number its books.
NAV = re.compile(r'[\W\d_]*(?:next|prev(?:ious)?|back|more|forward|page)[\W\d_]*|\W+\d+\W+|\d+\s*/\s*\d+|\W+', re.I)
# A link in a message's text is an option only when it can lead to a book: a Telegram link, or an address
# ending in a book format. A web page ("visit our website", a book's page) is not.
LINK = re.compile(r'^(?:https?://)?t(?:elegram)?\.me/|\.(?:' + '|'.join(FORMATS) + r')(?:[?#].*)?$', re.I)
SIZE = re.compile(r'(\d+(?:[.,]\d+)?)\s*(kb|mb|gb|kib|mib|gib)\b', re.I)


class Flood(Exception):
    """Telegram asked to slow down for `seconds`."""

    def __init__(self, seconds):
        super().__init__(f'flood wait {seconds} seconds')
        self.seconds = seconds


# ---------------------------------------------------------------- reading the answers (pure)

def words(text):
    return [w for w in re.findall(r'[a-z0-9]+', (text or '').lower()) if w not in STOP]


def _blocks(text, entities):
    """For each entity, the paragraph (text between blank lines) it sits in. Entities come in text order,
    so a repeated piece ("↗️" after every book) is found from the previous one on."""
    out, cursor = [], 0
    for entity in entities:
        at = text.find(entity['text'], cursor)
        if at < 0:
            out.append(entity['text'])
            continue
        cursor = at + len(entity['text'])
        start = text.rfind('\n\n', 0, at) + 1
        end = text.find('\n\n', at)
        lines = text[start:end if end >= 0 else len(text)].splitlines()
        out.append(' · '.join(line.strip() for line in lines if line.strip()))
    return out


def options(messages):
    """Every way to go on from what the bot sent, as one flat list (design 7.2 step 4). A command or link
    is labelled with its whole paragraph, since a list of books puts title, author and format on separate
    lines. A link in the same paragraph as a command is left out: the command is the bot's own way."""
    out = []
    for m in messages:
        for row, buttons in enumerate(m['buttons']):
            for col, button in enumerate(buttons):
                kind = button['kind']
                if kind == 'callback' and NAV.fullmatch(button['text']):
                    kind = 'nav'
                out.append({'label': button['text'], 'kind': kind, 'message': m['id'], 'row': row, 'col': col,
                            'data': button.get('data'), 'url': button.get('url')})
        blocks = _blocks(m['text'], m['entities'])
        with_command = {b for e, b in zip(m['entities'], blocks) if e['type'] == 'command'}
        for entity, block in zip(m['entities'], blocks):
            if entity['type'] == 'command':
                out.append({'label': block, 'kind': 'command', 'command': entity['text'], 'message': m['id']})
            elif entity['type'] == 'url' and block not in with_command and LINK.search(entity['url']):
                out.append({'label': block, 'kind': 'url', 'url': entity['url'], 'message': m['id']})
        if m['file']:
            out.append({'label': f"{m['file']['name'] or ''} {m['text']}".strip(), 'kind': 'document',
                        'message': m['id'], 'size': m['file']['size']})
    return out


def label_format(option):
    found = re.findall(r'\b(' + '|'.join(FORMATS) + r')\b', option['label'].lower())
    return found[-1] if found else ''


def label_mb(option):
    if option.get('size'):
        return option['size'] / 1_000_000
    match = SIZE.search(option['label'])
    if not match:
        return 0.0
    number = float(match[1].replace(',', '.'))
    return number * {'k': 0.001, 'm': 1, 'g': 1000}[match[2][0].lower()]


def rule_filter(found, book, fetch, chosen=False):
    """Drop wrong formats, files over max_mb and labels sharing under half the title's words;
    order the rest by format preference, then by title and author words (design 7.2 step 5).
    An option without a readable format is kept after the known ones: it may lead to a format choice.
    Once a book was `chosen`, the next answer is about that book: its labels ("EPUB", a file name)
    need not repeat the title."""
    title = set(words(book['title'].split(':')[0]))
    wanted = title | set(words(' '.join(book.get('authors') or [])))
    tried = set(book.get('tried') or [])
    kept = []
    for option in found:
        if option['kind'] == 'nav' or option['label'] in tried:
            continue
        fmt = label_format(option)
        if fmt and fmt not in fetch['formats']:
            continue
        if label_mb(option) > fetch['max_mb']:
            continue
        label = set(words(option['label']))
        if title and not chosen and len(title & label) * 2 < len(title):
            continue
        rank = fetch['formats'].index(fmt) if fmt else len(fetch['formats'])
        kept.append({**option, 'format': fmt, 'rank': rank, 'hits': len(wanted & label)})
    return sorted(kept, key=lambda o: (o['rank'], -o['hits']))


def pick(found, book, fetch, job_id=None, chosen=False):
    """The index of the option to take, or -1 for none (design 7.2 step 6). After a book was `chosen`,
    only the format decides."""
    if not found:
        return -1
    ahead = found[0]['rank'] < found[1]['rank'] if len(found) > 1 else True
    if len(found) == 1 or ahead and (chosen or found[0]['hits'] > found[1]['hits']):
        return 0
    result = llm.call('choose', 'choose', {
        'title': book['title'], 'authors': ', '.join(book.get('authors') or []) or 'unknown',
        'year': str(book.get('year') or 'unknown'), 'languages': 'English', 'formats': ', '.join(fetch['formats']),
        'options': '\n'.join(f"{n}: {o['label']}" for n, o in enumerate(found))}, job_id=job_id)
    if not result['ok']:
        raise ValueError(f"choose: {result['error']}")
    index = result['data']['index']
    return index if 0 <= index < len(found) else -1


def check_file(path, claimed):
    """The format the file really is, by its first bytes, or '' (design 7.2 step 8). Never opened by the shell."""
    if path.stat().st_size < 20_000:
        return ''
    head = path.read_bytes()[:4096]
    if claimed == 'epub':
        try:
            with zipfile.ZipFile(path) as book:
                return 'epub' if book.read('mimetype').strip() == b'application/epub+zip' else ''
        except (zipfile.BadZipFile, KeyError, OSError):
            return ''
    if claimed == 'pdf':
        return 'pdf' if head.startswith(b'%PDF') else ''
    if claimed in ('mobi', 'azw3'):
        return claimed if head[60:68] == b'BOOKMOBI' else ''
    if claimed == 'fb2':
        return 'fb2' if head.lstrip().startswith(b'<?xml') and b'<FictionBook' in head else ''
    return ''


# ---------------------------------------------------------------- talking to Telegram

def _keys():
    env = settings.secrets()
    api_id, api_hash = env.get('TELEGRAM_API_ID'), env.get('TELEGRAM_API_HASH')
    if not api_id or not api_hash:
        raise ValueError('TELEGRAM_API_ID and TELEGRAM_API_HASH are missing from .env')
    return int(api_id), api_hash


def session_path():
    return settings.home() / 'telegram.session'


def client():
    from telethon.sync import TelegramClient
    return TelegramClient(str(session_path().with_suffix('')), *_keys())


def connected():
    """A signed-in client, or an error that says to sign in. Never asks anything on the console."""
    tg = client()
    tg.connect()
    if not tg.is_user_authorized():
        tg.disconnect()
        raise ValueError('sign in to Telegram first: py -3 -m tools.content.pipeline telegram login')
    return tg


WHERE = {'SentCodeTypeApp': 'the Telegram app, in the chat named "Telegram"', 'SentCodeTypeSms': 'an SMS',
         'SentCodeTypeCall': 'a phone call', 'SentCodeTypeFlashCall': 'a missed call',
         'SentCodeTypeEmailCode': 'your login e-mail address', 'SentCodeTypeFragmentSms': 'Fragment (fragment.com)',
         'SentCodeTypeSetUpEmailRequired': 'nowhere yet: Telegram first wants a login e-mail set up in the app',
         'SentCodeTypeFirebaseSms': 'an SMS'}


QR_PAGE = ('<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="3"><title>Telegram sign-in</title>'
           '<body style="background:#fff;color:#000;font:18px sans-serif;text-align:center;padding:24px">'
           '<p>On the iPhone: Telegram &rarr; Settings &rarr; Devices &rarr; Link Desktop Device, '
           'then point the camera at this code.</p><div style="width:min(360px,90vw);margin:auto">{svg}</div>'
           '<p>The code changes every 30 seconds; this page follows it.</p>'
           '<style>svg{{width:100%;height:auto}}</style>')


def qr_sign_in(tg, minutes=5):
    """Sign in by scanning a QR code with the phone: no login code is sent. The code is shown on a local
    page, black on white so any camera reads it, and the page is deleted at the end."""
    import asyncio
    import webbrowser
    import qrcode
    import qrcode.image.svg
    page = settings.home() / 'state' / 'telegram-qr.html'
    login_qr = tg.qr_login()
    end = time.monotonic() + minutes * 60
    try:
        while time.monotonic() < end:
            svg = qrcode.make(login_qr.url, image_factory=qrcode.image.svg.SvgPathImage).to_string(encoding='unicode')
            first = not page.exists()
            page.write_text(QR_PAGE.format(svg=svg), encoding='utf-8')
            if first:
                webbrowser.open(page.as_uri())
                print('A page with a QR code opened in your browser. On the iPhone: Telegram > Settings > Devices >',
                      'Link Desktop Device, and scan it. Waiting up to', minutes, 'minutes...')
            try:
                return tg.loop.run_until_complete(login_qr.wait(30))
            except asyncio.TimeoutError:
                tg.loop.run_until_complete(login_qr.recreate())
        raise ValueError(f'no scan within {minutes} minutes')
    finally:
        page.unlink(missing_ok=True)


def login(qr=False):
    """Sign in once on the console. Says where Telegram sent the code, and can ask for it another way.
    With `qr`, the phone scans a QR code instead and no code is sent."""
    from getpass import getpass
    from telethon.errors import PhoneCodeInvalidError, SessionPasswordNeededError
    from telethon.tl.functions.auth import ResendCodeRequest
    tg = client()
    tg.connect()
    try:
        if not tg.is_user_authorized() and qr:
            try:
                qr_sign_in(tg)
            except SessionPasswordNeededError:
                tg.sign_in(password=getpass('Two-step password (hidden while you type): '))
        elif not tg.is_user_authorized():
            phone = input('Phone number with the country code (like +39...): ').strip().replace(' ', '')
            sent = tg.send_code_request(phone)
            while True:
                print('Telegram sent the code to', WHERE.get(type(sent.type).__name__, type(sent.type).__name__) + '.')
                if sent.next_type is not None:
                    print('If it does not come, type "again" to have it sent to',
                          WHERE.get(type(sent.next_type).__name__, type(sent.next_type).__name__) + '.')
                code = input('Code: ').strip()
                if code.lower() == 'again' and sent.next_type is not None:
                    sent = tg(ResendCodeRequest(phone, sent.phone_code_hash))
                    continue
                try:
                    tg.sign_in(phone, code, phone_code_hash=sent.phone_code_hash)
                    break
                except PhoneCodeInvalidError:
                    print('That code is not right. Type the newest code again (no new code is asked for).')
                except SessionPasswordNeededError:
                    tg.sign_in(password=getpass('Two-step password (hidden while you type): '))
                    break
        print('signed in as', tg.get_me().first_name)
    finally:
        try:
            signed_in = tg.is_user_authorized()
        except Exception:  # noqa: BLE001 - a lost connection means the sign-in did not finish
            signed_in = False
        tg.disconnect()
        if not signed_in:
            # A session file that is not signed in would make the stage and the notices think it is.
            session_path().unlink(missing_ok=True)


def serial(message):
    """A message as plain JSON: text, links, commands, buttons and any file. No ids of people."""
    out = {'id': message.id, 'text': message.message or '', 'edit': message.edit_date is not None,
           'entities': [], 'buttons': [], 'file': None}
    for entity, piece in message.get_entities_text():
        name = type(entity).__name__
        if name == 'MessageEntityTextUrl':
            out['entities'].append({'type': 'url', 'text': piece, 'url': entity.url})
        elif name == 'MessageEntityUrl':
            out['entities'].append({'type': 'url', 'text': piece, 'url': piece})
        elif name == 'MessageEntityBotCommand':
            out['entities'].append({'type': 'command', 'text': piece})
    for row in getattr(message.reply_markup, 'rows', None) or []:
        buttons = []
        for button in row.buttons:
            # Telethon 1.45 wraps inline buttons: KeyboardInlineButton(text, type=InlineButtonTypeCallback(data)).
            inner = getattr(button, 'type', None) or button
            name = type(inner).__name__.replace('InlineButtonType', 'KeyboardButton')
            if name == 'KeyboardButtonCallback':
                buttons.append({'text': button.text, 'kind': 'callback', 'data': inner.data.hex()})
            elif name == 'KeyboardButtonUrl':
                buttons.append({'text': button.text, 'kind': 'url', 'url': inner.url})
            elif name == 'KeyboardButton':
                buttons.append({'text': button.text, 'kind': 'text'})
            else:
                buttons.append({'text': getattr(button, 'text', ''), 'kind': name})
        out['buttons'].append(buttons)
    if message.file and not message.web_preview:
        out['file'] = {'name': message.file.name, 'size': message.file.size, 'type': message.file.mime_type}
    return out


class Bot:
    """One chat with fetch.bot. Every send waits the pause, and at least 10 seconds since the last one,
    across processes (state/telegram.json)."""

    def __init__(self, tg, fetch):
        self.tg, self.fetch, self.name, self.last = tg, fetch, fetch['bot'], None
        self.mark = settings.home() / 'state' / 'telegram.json'

    def _call(self, action):
        from telethon import errors
        try:
            return action()
        except errors.FloodWaitError as exc:
            raise Flood(exc.seconds) from exc

    def _wait_turn(self):
        last = json.loads(self.mark.read_text()).get('last_sent', 0) if self.mark.exists() else 0
        pause = max(10.0, random.uniform(*self.fetch['pause_seconds']))
        time.sleep(max(0.0, last + pause - time.time()))

    def _sent(self, what):
        self.mark.write_text(json.dumps({'last_sent': time.time()}))
        from . import stages
        stages.log(f'telegram sent: {what}')

    def history(self, after_id):
        messages = self._call(lambda: self.tg.get_messages(self.name, limit=30, min_id=after_id - 1))
        return [m for m in reversed(messages) if not m.out]

    def _sig(self, after_id):
        return [(m.id, str(m.edit_date), m.message, str(m.reply_markup), bool(m.file)) for m in self.history(after_id)]

    def send(self, text):
        self._wait_turn()
        sent = self._call(lambda: self.tg.send_message(self.name, text))
        self._sent(text)
        self.last = sent.id + 1
        return self.collect(self.last, [])

    def listen(self):
        """Wait once more for the last answer to grow (the bot sends a book's details, then the file a little
        later). Sends nothing. Every message since the last send or press, or [] when nothing new came."""
        return self.collect(self.last, self._sig(self.last))

    def press(self, option):
        from telethon.errors import BotResponseTimeoutError
        from telethon.tl.functions.messages import GetBotCallbackAnswerRequest
        before = self._sig(option['message'])
        self.last = option['message']
        self._wait_turn()
        answer = None
        try:
            answer = self._call(lambda: self.tg(GetBotCallbackAnswerRequest(self.name, option['message'],
                                                                             data=bytes.fromhex(option['data']))))
        except BotResponseTimeoutError:
            pass  # the bot did not confirm the press; its edits or new messages may still come
        self._sent(f"press {option['label']!r}")
        messages = self.collect(option['message'], before)
        if answer is not None and (answer.message or answer.url):
            # The small popup a press can show ("limit reached", a link): read like any message.
            url = [{'type': 'url', 'text': answer.url, 'url': answer.url}] if answer.url else []
            messages.append({'id': 0, 'text': answer.message or '', 'edit': False, 'entities': url,
                             'buttons': [], 'file': None, 'popup': True})
        return messages

    def collect(self, after_id, before):
        """Every message and edit from `after_id` on, until nothing changes for quiet_seconds
        after the first change, or reply_wait_seconds pass (design 7.2 step 3)."""
        start = time.monotonic()
        previous, changed_at = before, None
        while True:
            messages = self.history(after_id)
            sig = [(m.id, str(m.edit_date), m.message, str(m.reply_markup), bool(m.file)) for m in messages]
            if sig != previous:
                previous, changed_at = sig, time.monotonic()
            now = time.monotonic()
            if changed_at and now - changed_at >= self.fetch['quiet_seconds'] or now - start >= self.fetch['reply_wait_seconds']:
                return [serial(m) for m in messages] if changed_at else []
            time.sleep(2)

    def take(self, option):
        """Follow one option that leads to more answers (one hop)."""
        if option['kind'] in ('callback', 'nav'):
            return self.press(option)
        if option['kind'] == 'command':
            return self.send(option['command'])
        if option['kind'] == 'text':
            return self.send(option['label'])
        start = start_link(option.get('url') or '', self.name)
        if start is not None:
            return self.send(start)
        raise ValueError(f"cannot follow a {option['kind']} option: {option['label']}")

    def download(self, option, path):
        message = self._call(lambda: self.tg.get_messages(self.name, ids=option['message']))
        self._call(lambda: self.tg.download_media(message, file=str(path)))
        return path


def start_link(url, bot):
    """`/start <code>` for a t.me link to fetch.bot itself; None for any other address."""
    match = re.fullmatch(r'(?:https?://)?t(?:elegram)?\.me/([A-Za-z0-9_]+)(?:\?start=([\w-]+))?', url)
    if not match or match[1].lower() != bot.lstrip('@').lower():
        return None
    return f'/start {match[2]}' if match[2] else '/start'


# ---------------------------------------------------------------- probe

def _probe_files():
    return sorted((settings.home() / 'probe').glob('*.json'), key=lambda p: int(p.stem) if p.stem.isdigit() else 0)


def _save_probe(record):
    files = [int(p.stem) for p in _probe_files() if p.stem.isdigit()]
    n = max(files, default=0) + 1
    (settings.home() / 'probe' / f'{n}.json').write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding='utf-8')
    print(f"probe {n}: {len(record['messages'])} messages")
    for i, option in enumerate(options(record['messages'])):
        print(f"  {i}: [{option['kind']}] {option['label']}")
    return n


def probe(title=None, press=None):
    """Send one title (or follow one option of a saved probe) and save what comes back. Downloads nothing."""
    fetch = settings.load()['fetch']
    tg = connected()
    try:
        bot = Bot(tg, fetch)
        if press is None:
            return _save_probe({'query': title, 'messages': bot.send(title)})
        number, index = press
        saved = json.loads((settings.home() / 'probe' / f'{number}.json').read_text(encoding='utf-8'))
        option = options(saved['messages'])[index]
        if option['kind'] in ('document', 'url') and start_link(option.get('url') or '', bot.name) is None:
            raise ValueError('a probe downloads nothing: this option is a file or a web address')
        return _save_probe({'from': [number, index], 'option': option['label'], 'messages': bot.take(option)})
    finally:
        tg.disconnect()


# ---------------------------------------------------------------- the stage

BOOK_FORMATS = ('epub', 'pdf', 'mobi', 'azw3', 'fb2')


class Stopped(Exception):
    """The stage switched itself off."""


def notify(text, tg=None):
    """One short line to the owner's own Saved Messages. Silent without a session; never fails a stage."""
    from . import stages
    if not settings.load()['notify']['telegram_saved_messages'] or not session_path().exists():
        return
    try:
        if tg is not None:
            tg.send_message('me', text)
            return
        own = connected()
        try:
            own.send_message('me', text)
        finally:
            own.disconnect()
    except Exception as exc:  # ImportError, network, a session not signed in: a notice is only a courtesy
        stages.log(f'notice not sent: {exc}')


def right_book(meta, blocks, facts):
    """Design 7.2 step 10: the title words and the author's surname are in the first 3,000 words
    of the text or in the file's own metadata."""
    surname = words((meta.get('authors') or [''])[0].split(',')[0])[-1:]
    need = set(words(meta['title'].split(':')[0])) | set(surname)
    head = set(words(' '.join(' '.join(b['text'] for b in blocks).split()[:3000])))
    own = set(words(' '.join([facts.get('title', '')] + facts.get('authors', []))))
    return need <= head or need <= own


def _name_facts(path):
    """Title and author from an `Author - Title.ext` name; otherwise the whole name is the title."""
    stem = path.stem.replace('_', ' ')
    if ' - ' in stem:
        author, title = stem.split(' - ', 1)
        return title.strip(), author.strip()
    return stem.strip(), None


def _seen(key):
    from . import stages
    return bool(stages.rows('SELECT 1 FROM seen WHERE key=?', (key,)))


def _sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inbox():
    """Design 7.3: every book file in inbox/ becomes a queued job and leaves the inbox."""
    from . import cardmaker, text
    folder = settings.home() / 'inbox'
    made = []
    for path in sorted(p for p in folder.iterdir() if p.is_file()):
        ext = path.suffix.lower().lstrip('.')
        if ext not in BOOK_FORMATS:
            continue
        problem = f'not a real {ext} file' if check_file(path, ext) != ext else 'already taken' if _seen(_sha(path)) else ''
        if problem:
            (folder / 'rejected').mkdir(exist_ok=True)
            path.replace(folder / 'rejected' / path.name)
            made.append(f'{path.name}: {problem}, moved to inbox/rejected')
            continue
        title, author = _name_facts(path)
        if ext == 'epub':
            facts = text.epub_facts(path)
            title, author = facts['title'] or title, facts['authors'] or author
        job_id = cardmaker.create(path, title=title, author=author, origin='inbox')
        path.unlink()
        made.append(f'{path.name}: job {job_id}')
    return made


def _http_download(url, path, max_mb):
    import urllib.request

    class Limited(urllib.request.HTTPRedirectHandler):
        max_redirections = 5

    if not re.match(r'https?://', url):
        raise ValueError('only http and https addresses are downloaded')
    request = urllib.request.Request(url, headers={'User-Agent': 'SmartScrollingPipeline/1.0'})
    with urllib.request.build_opener(Limited).open(request, timeout=60) as response:
        data = response.read(int(max_mb * 1_000_000) + 1)
    if len(data) > max_mb * 1_000_000:
        raise ValueError(f'file over {max_mb} MB')
    path.write_bytes(data)
    return path


def _is_file(option, bot):
    return option['kind'] == 'document' or option['kind'] == 'url' and start_link(option.get('url') or '', bot) is None


def _claimed(option):
    found = option.get('format') or label_format({'label': option.get('url') or ''})
    return found if found in BOOK_FORMATS else ''


def _stop_word(messages, fetch):
    said = ' '.join(m['text'] for m in messages).lower()
    return next((w for w in fetch['stop_words'] if re.search(r'\b' + re.escape(w) + r'\b', said)), None)


def _forward(found):
    """The page-turning button that goes forward, if any."""
    return next((o for o in found if o['kind'] == 'nav'
                 and re.search(r'next|more|forward|[›»→>▶➡]', o['label'], re.I)), None)


def get_book(book, fetch, bot, incoming, job_id=None):
    """Ask, listen, list, filter, choose and take (design 7.2 steps 2 to 8). Returns
    (outcome, detail, path, format, label); outcome is downloaded, no_reply, not_found, stop or failed."""
    authors = book.get('authors') or []
    surname = authors[0].split(',')[0].split()[-1] if authors and authors[0].split() else ''
    query = fetch['query'].format(title=book['title'], author_surname=surname, author=authors[0] if authors else '')
    messages, hops, taken, chosen, listened, picked = bot.send(query.strip()), 0, set(), False, False, None
    while True:
        if not messages:
            return 'no_reply', 'the bot did not answer', None, '', ''
        found = options(messages)
        word = _stop_word(messages, fetch)
        if word and not any(o['kind'] != 'nav' for o in found):
            return 'stop', f'the bot asked for something code cannot do ("{word}")', None, '', ''
        # A pressed message comes back with its old buttons: an option already taken is not taken again.
        kept = [o for o in rule_filter(found, book, fetch, chosen)
                if (o['message'], o['label'], o.get('data'), o.get('command')) not in taken]
        if chosen and not any(_is_file(o, bot.name) for o in kept):
            if not listened:
                listened = True  # a chosen book's file may come a little after its details: listen once more
                more = bot.listen()
                if more:
                    messages = more
                    continue
            # Still no file for a chosen book. A limit would show here, next to the details' own button
            # ("Click to read full description"), so stop words count even beside options. A button that
            # names no format is not followed: it does not lead to a file.
            if word:
                return 'stop', f'the bot asked for something code cannot do ("{word}")', None, '', ''
            kept = [o for o in kept if o['format']]
            if not kept:
                return 'no_reply', 'the bot sent no file for the chosen book', None, '', ''
        if not kept:
            ahead = _forward(found)
            if ahead and hops < fetch['max_hops']:
                hops += 1
                messages = bot.take(ahead)
                continue
            return 'not_found', 'nothing matches', None, '', ''
        index = pick(kept, book, fetch, job_id, chosen)
        if index < 0:
            return 'not_found', 'none of the options is this book', None, '', ''
        option = kept[index]
        if _is_file(option, bot.name):
            # A file: check it; when it fails, the next file option is tried once.
            later = [o for o in kept[index + 1:] if _is_file(o, bot.name)][:1]
            for attempt in [option] + later:
                claimed = _claimed(attempt)
                if not claimed:
                    continue
                path = incoming.with_suffix('.' + claimed)
                try:
                    if attempt['kind'] == 'document':
                        bot.download(attempt, path)
                    else:
                        _http_download(attempt['url'], path, fetch['max_mb'])
                except (OSError, ValueError):
                    path.unlink(missing_ok=True)
                    continue
                if check_file(path, claimed) == claimed:
                    # The book picked in the search list, so a wrong book is skipped there next time.
                    return 'downloaded', '', path, claimed, picked or attempt['label']
                path.unlink(missing_ok=True)
            return 'failed', f"the file failed the check: {option['label']}", None, '', option['label']
        if hops >= fetch['max_hops']:
            return 'not_found', f'no file after {hops} steps', None, '', ''
        hops += 1
        taken.add((option['message'], option['label'], option.get('data'), option.get('command')))
        chosen, listened, picked = True, False, picked or option['label']
        messages = bot.take(option)


def _update_book(book_id, **fields):
    from contextlib import closing
    from . import cardmaker, store
    fields['updated_at'] = cardmaker.now()
    with closing(store.connect()) as db, db:
        db.execute(f"UPDATE books SET {', '.join(k + '=?' for k in fields)} WHERE id=?", (*fields.values(), book_id))


def _later(**delta):
    return (dt.datetime.now().astimezone() + dt.timedelta(**delta)).isoformat()


def fetch_book(row, config, bot):
    """One wish-list row through the bot, and the failure table of design 7.2. Returns a summary."""
    from . import cardmaker
    fetch = config['fetch']
    error = row['last_error'] or ''
    book = {'title': row['title'], 'authors': json.loads(row['authors'] or '[]'), 'year': row['year'],
            'tried': [error[len('wrong book: '):]] if error.startswith('wrong book: ') else []}
    attempts = (row['attempts'] or 0) + 1
    _update_book(row['id'], status='searching')
    try:
        outcome, detail, path, fmt, label = get_book(book, fetch, bot, settings.home() / 'state' / 'incoming')
    except Flood as flood:
        llm._rest('telegram', dt.datetime.now().astimezone() + dt.timedelta(seconds=flood.seconds))
        _update_book(row['id'], status='wanted', last_error=str(flood))
        raise
    except ValueError as exc:  # the choose role had no provider: not the book's fault
        _update_book(row['id'], status='wanted', last_error=str(exc))
        return f"{row['title']}: {exc}"
    if outcome == 'downloaded':
        if _seen(_sha(path)):
            path.unlink()
            _update_book(row['id'], status='duplicate', last_error='the same file was taken before')
            return f"{row['title']}: duplicate"
        extra = {'book_id': row['id'], 'year': row['year'], 'topics': json.loads(row['topics'] or '[]'),
                 'details': {'isbn': row['isbn13']} if row['isbn13'] else {}, 'taken': label}
        job_id = cardmaker.create(path, title=row['title'], author=book['authors'], origin='telegram', extra=extra)
        path.unlink()
        _update_book(row['id'], status='downloaded', job_id=job_id, last_error='', attempts=attempts)
        return f"{row['title']}: downloaded ({fmt}), job {job_id}"
    if outcome == 'no_reply':
        _update_book(row['id'], status='wanted', attempts=attempts, last_error=detail, next_try_at=_later(days=1))
    elif outcome == 'not_found':
        _update_book(row['id'], status='not_found', attempts=attempts, last_error=detail,
                     next_try_at=_later(days=fetch['retry_after_days']))
    elif outcome == 'failed':
        _update_book(row['id'], status='failed', attempts=attempts, last_error=detail)
    else:  # stop: never try to get around a puzzle or a limit
        _update_book(row['id'], status='wanted', last_error=detail)
        settings.set_value('stages.fetch.enabled', 'false')
        notify(f'Book fetching switched itself off: {detail}. Check the bot, then switch the stage on.', bot.tg)
        raise Stopped(detail)
    return f"{row['title']}: {outcome} ({detail})"


def due_books(fetch, limit):
    from . import stages
    return stages.rows("SELECT * FROM books WHERE (status='wanted' OR (status='not_found' AND attempts<?)) "
                       "AND (next_try_at IS NULL OR next_try_at='' OR next_try_at<=?) "
                       "ORDER BY priority IS NULL, priority, score DESC, added_at LIMIT ?",
                       (fetch['max_attempts'], _later(), limit))


def stage(config, deadline, connect=None):
    """The fetch stage: the inbox first (needs no Telegram), then up to per_run wish-list books."""
    summaries = inbox()
    fetch = config['fetch']
    if fetch['driver'] != 'telegram' or not fetch['bot']:
        return ('ok' if summaries else 'nothing'), '; '.join(summaries) or 'no bot set'
    until = llm.resting().get('telegram')
    if until and dt.datetime.fromisoformat(until) > dt.datetime.now().astimezone():
        return 'nothing', '; '.join(summaries + [f'Telegram asked to wait until {until}'])
    books = due_books(fetch, config['stages']['fetch']['per_run'])
    if not books:
        return ('ok' if summaries else 'nothing'), '; '.join(summaries) or 'no wanted books'
    if connect is None and not session_path().exists():
        return 'nothing', '; '.join(summaries + ['sign in to Telegram'])
    try:
        tg = (connect or connected)()
    except ValueError:  # the session was ended from the phone (Settings > Devices): the file stays behind
        return 'nothing', '; '.join(summaries + ['sign in to Telegram'])
    result = 'ok'
    try:
        bot = Bot(tg, fetch)
        for row in books:
            if time.monotonic() >= deadline:
                result = 'stopped'
                summaries.append('time limit')
                break
            summaries.append(fetch_book(row, config, bot))
    except (Flood, Stopped) as exc:
        result = 'stopped'
        summaries.append(str(exc))
    finally:
        tg.disconnect()
    return result, '; '.join(summaries)

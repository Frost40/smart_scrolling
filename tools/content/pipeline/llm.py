"""Checked JSON calls through subscription CLIs or OpenAI-compatible endpoints."""

import datetime as dt
from contextlib import closing
import json
import http.client
import math
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time
import threading
import urllib.error
import urllib.request

from . import settings, store

PRESETS = Path(__file__).with_name('presets.json')
CARDMAKER = Path(__file__).resolve().parents[1] / 'cardmaker'


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _read(response, deadline):
    stream = response.fp if isinstance(response, urllib.error.HTTPError) else response
    chunks = []
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Provider deadline exceeded')
        if stream.fp is None:
            return b''.join(chunks)
        transport = stream.fp.raw._sock
        transport.settimeout(remaining)
        def stop_read():
            try:
                transport.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        timer = threading.Timer(remaining, stop_read)
        timer.daemon = True
        timer.start()
        try:
            chunk = stream.read1(65536)
        finally:
            timer.cancel()
        if time.monotonic() > deadline:
            raise TimeoutError('Provider deadline exceeded')
        if not chunk:
            return b''.join(chunks)
        chunks.append(chunk)


def check(data, schema, path='$'):
    problems = []
    types = {'object': dict, 'array': list, 'string': str, 'integer': int,
             'number': (int, float), 'boolean': bool}
    kind = schema.get('type')
    if kind and (not isinstance(data, types[kind]) or
                 (kind in ('integer', 'number') and isinstance(data, bool))):
        return [f'{path}: expected {kind}']
    if 'enum' in schema and not any(isinstance(data, bool) == isinstance(v, bool) and data == v for v in schema['enum']):
        problems.append(f'{path}: not in enum')
    if isinstance(data, dict):
        props = schema.get('properties', {})
        problems.extend(f'{path}.{key}: required' for key in schema.get('required', []) if key not in data)
        for key, value in data.items():
            if key in props:
                problems.extend(check(value, props[key], f'{path}.{key}'))
            elif schema.get('additionalProperties') is False:
                problems.append(f'{path}.{key}: unexpected property')
    if isinstance(data, list) and 'items' in schema:
        for i, value in enumerate(data):
            problems.extend(check(value, schema['items'], f'{path}[{i}]'))
    return problems


def _get(data, path, default=0):
    for key in path.split('.'):
        if not isinstance(data, dict) or key not in data:
            return default
        data = data[key]
    return data


def _answer(text, schema):
    if isinstance(text, str):
        text = re.sub(r'^```(?:json)?\s*|\s*```$', '', text.strip())
        try:
            text = json.loads(text)
        except (ValueError, TypeError):
            return {'ok': False, 'data': None, 'error_kind': 'bad_json', 'error': 'Answer is not JSON'}
    problems = check(text, schema)
    return {'ok': not problems, 'data': text, 'error_kind': 'schema' if problems else '',
            'error': '; '.join(problems)}


def _failure(kind, message):
    return {'ok': False, 'data': None, 'error_kind': kind, 'error': message}


def _cli(provider, system, user, schema, timeout):
    preset = json.loads(PRESETS.read_text(encoding='utf-8'))[provider['preset']]
    with tempfile.TemporaryDirectory(prefix='pipeline-call-') as folder:
        schema_file = Path(folder) / 'schema.json'
        out_file = Path(folder) / 'answer.json'
        schema_file.write_text(json.dumps(schema), encoding='utf-8')
        values = {'model': provider['model'], 'system': system, 'prompt': system + '\n\n' + user,
                  'schema': json.dumps(schema), 'schema_file': str(schema_file), 'out_file': str(out_file)}
        # Replace only named placeholders: prompt text can itself contain braces.
        cmd = [re.sub(r'\{(model|system|prompt|schema|schema_file|out_file)\}',
                      lambda m: values[m[1]], arg) for arg in preset['cmd']]
        if provider.get('program'):
            cmd[0] = os.path.expandvars(provider['program'])
        if provider['preset'] == 'codex' and provider['model'] and '{model}' not in preset['cmd']:
            cmd[2:2] = ['-m', provider['model']]
        if len(subprocess.list2cmdline(cmd)) > 30000:
            return _failure('too_long', 'Command exceeds 30,000 characters')
        env = os.environ.copy()
        for key in preset.get('env_remove', []):
            env.pop(key, None)
        stdin = {'user': user, 'both': values['prompt'], 'none': '',
                 'stream-json': json.dumps({'event': 'user', 'message': {'content': values['prompt']}}) + '\n'}[preset['stdin']]
        completed = subprocess.run(cmd, input=stdin, capture_output=True, encoding='utf-8',
                                   errors='replace', timeout=timeout, env=env,
                                   cwd=settings.home() / 'sandbox')
        output = completed.stdout
        combined = output + '\n' + completed.stderr
        def failure(message, fallback='down'):
            if any(word.lower() in message.lower() for word in preset.get('limit_words', [])):
                return _failure('limit', message)
            if re.search(r'max_tokens|output.{0,10}limit|error_max_turns', message, re.I):
                return _failure('cut', message)
            if re.search(r'refus|declin', message, re.I):
                return _failure('refused', message)
            return _failure(fallback, message)

        if completed.returncode:
            diagnostic = output
            try:
                failed = json.loads(output)
                if isinstance(failed, dict):
                    diagnostic = str({key: failed[key] for key in ('result', 'error', 'errors', 'subtype') if key in failed})
            except ValueError:
                pass
            return failure(f'CLI exited {completed.returncode}: ' + diagnostic + '\n' + completed.stderr)
        if any(word.lower() in completed.stderr.lower() for word in preset.get('limit_words', [])):
            return _failure('limit', combined.strip())
        envelope = None
        if preset['result'].startswith('json:'):
            try:
                if preset['stdin'] == 'stream-json':
                    events = [json.loads(line) for line in output.splitlines() if line.strip()]
                    envelope = next(event for event in reversed(events)
                                    if isinstance(event, dict) and event.get('event') == 'result')
                else:
                    envelope = json.loads(output)
            except (ValueError, StopIteration):
                return _failure('bad_json', 'CLI output is not JSON')
            if not isinstance(envelope, dict):
                return _failure('bad_json', 'CLI output must be an object')
            tokens = preset.get('tokens', {})
            usage = {'tokens_in': _get(envelope, tokens.get('in', 'usage.input_tokens')),
                     'tokens_out': _get(envelope, tokens.get('out', 'usage.output_tokens'))}
            if envelope.get('is_error') or _get(envelope, 'result.status', '') in ('ERROR', 'FAILED'):
                return {**failure(str(envelope.get('result', envelope)), 'refused'), **usage}
            if _get(envelope, 'stop_reason', '') == 'max_tokens' or 'max_tokens' in str(envelope.get('subtype', '')):
                return {**_failure('cut', 'Output token limit reached'), **usage}
            key = preset['result'].split(':', 1)[1]
            answer = _get(envelope, key, None)
            if answer is None:
                return {**failure(str(envelope.get('result', 'Missing ' + key)), 'bad_json'), **usage}
            answer = _answer(answer, schema)
            return {**answer, **usage}
        if preset['result'] == 'file':
            if not out_file.exists():
                return _failure('bad_json', 'CLI did not write an answer file')
            output = out_file.read_text(encoding='utf-8')
        return _answer(output, schema)


def _openai(provider, system, user, schema, timeout, step):
    deadline = time.monotonic() + timeout
    mode = provider.get('json', 'schema')
    body = {'model': provider['model'], 'messages': [{'role': 'system', 'content': system},
            {'role': 'user', 'content': user}], 'max_tokens': 8000}
    if mode == 'schema':
        body['response_format'] = {'type': 'json_schema', 'json_schema':
                                  {'name': step, 'strict': True, 'schema': schema}}
    else:
        body['messages'][1]['content'] += '\n\nReturn JSON matching this schema:\n' + json.dumps(schema)
        if mode == 'object':
            body['response_format'] = {'type': 'json_object'}
    body.update(provider.get('extra_body', {}))
    headers = {'Content-Type': 'application/json'}
    if provider.get('key_env'):
        key = settings.secrets().get(provider['key_env'], '')
        if not key:
            return _failure('down', 'Missing key: ' + provider['key_env'])
        headers['Authorization'] = 'Bearer ' + key
    req = urllib.request.Request(provider['base_url'].rstrip('/') + '/chat/completions',
                                 data=json.dumps(body).encode('utf-8'), headers=headers)
    try:
        with urllib.request.build_opener(_NoRedirect()).open(req, timeout=timeout) as response:
            envelope = json.loads(_read(response, deadline))
    except urllib.error.HTTPError as exc:
        with exc:
            message = _read(exc, deadline).decode('utf-8', 'replace')
        retry = exc.headers.get('Retry-After', '')
        if retry.isdigit():
            message += f' retry after {retry} seconds'
        return _failure('limit' if exc.code == 429 else 'down', f'HTTP {exc.code}: ' + message)
    choice = envelope['choices'][0]
    usage = {'tokens_in': envelope.get('usage', {}).get('prompt_tokens', 0),
             'tokens_out': envelope.get('usage', {}).get('completion_tokens', 0)}
    if choice.get('finish_reason') == 'length':
        return {**_failure('cut', 'Output token limit reached'), **usage}
    if choice['message'].get('refusal') or choice.get('finish_reason') == 'content_filter':
        return {**_failure('refused', 'Provider refused the prompt'), **usage}
    return {**_answer(choice['message']['content'], schema), **usage}


def run_provider(name, system, user, schema, *, _role='', _job_id=None, _step='pipeline'):
    config = settings.load()
    provider = config['providers'][name]
    now = dt.datetime.now().astimezone()
    until = resting().get(name)
    if until and dt.datetime.fromisoformat(until).astimezone() > now:
        return {**_failure('limit', 'Provider is resting until ' + until),
                'seconds': 0, 'tokens_in': 0, 'tokens_out': 0}
    if calls_today(name) >= provider.get('max_calls_per_day', 100):
        _rest(name, (now + dt.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0))
        return {**_failure('limit', 'Daily call cap reached'), 'seconds': 0, 'tokens_in': 0, 'tokens_out': 0}
    started = time.monotonic()
    try:
        if not provider.get('model'):
            result = _failure('down', 'Provider needs a model')
        elif provider['driver'] == 'cli':
            result = _cli(provider, system, user, schema, config['make']['call_timeout_seconds'])
        else:
            result = _openai(provider, system, user, schema, config['make']['call_timeout_seconds'], _step)
    except (OSError, subprocess.SubprocessError, urllib.error.URLError, http.client.HTTPException) as exc:
        result = _failure('down', type(exc).__name__)
    except (ValueError, KeyError, IndexError, TypeError, AttributeError) as exc:
        result = _failure('bad_json', 'Invalid provider response: ' + type(exc).__name__)
    result = {'tokens_in': 0, 'tokens_out': 0, **result, 'seconds': round(time.monotonic() - started, 3)}
    if any(type(result[key]) is not int or not 0 <= result[key] < 2**63 for key in ('tokens_in', 'tokens_out')):
        result = {**result, **_failure('bad_json', 'Invalid token counts'), 'tokens_in': 0, 'tokens_out': 0}
    with closing(store.connect()) as db, db:
        db.execute('INSERT INTO calls (at,provider,role,job_id,ok,error_kind,seconds,tokens_in,tokens_out) VALUES (?,?,?,?,?,?,?,?,?)',
                   (dt.datetime.now().astimezone().isoformat(), name, _role, _job_id, result['ok'],
                    result['error_kind'], result['seconds'], result['tokens_in'], result['tokens_out']))
    if result['error_kind'] == 'limit':
        _rest(name, _resume_time(result['error']))
    elif calls_today(name) >= provider.get('max_calls_per_day', 100):
        _rest(name, (now + dt.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0))
    return result


def calls_today(name):
    with closing(store.connect()) as db:
        return db.execute('SELECT count(*) FROM calls WHERE provider=? AND substr(at,1,10)=?',
                          (name, dt.date.today().isoformat())).fetchone()[0]


def resting():
    path = settings.home() / 'state' / 'resting.json'
    return json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}


def _rest(name, until):
    state = resting()
    state[name] = until.isoformat()
    path = settings.home() / 'state' / 'resting.json'
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(state, indent=2), encoding='utf-8')
    temporary.replace(path)


def _resume_time(message):
    now = dt.datetime.now().astimezone()
    iso = re.search(r'\d{4}-\d\d-\d\d[T ]\d\d:\d\d(?::\d\d)?(?:Z|[+-]\d\d:\d\d)?', message)
    if iso:
        try:
            parsed = dt.datetime.fromisoformat(iso[0]).astimezone()
            if parsed > now:
                return parsed
        except (ValueError, OverflowError):
            pass
    delay = re.search(r'(?:in|after|retry[- ]after[: ]*)\s*(\d+)\s*(seconds?|minutes?|hours?|s|m|h)\b', message, re.I)
    if delay:
        return now + dt.timedelta(seconds=int(delay[1]) * {'s': 1, 'm': 60, 'h': 3600}[delay[2][0].lower()])
    clock = re.search(r'(?:at|resets?)\s+(\d{1,2})(?::(\d\d))?\s*(am|pm)?\b', message, re.I)
    if clock:
        hour = int(clock[1])
        if clock[3]:
            hour = hour % 12 + (12 if clock[3].lower() == 'pm' else 0)
        if hour < 24 and int(clock[2] or 0) < 60:
            until = now.replace(hour=hour, minute=int(clock[2] or 0), second=0, microsecond=0)
            return until if until > now else until + dt.timedelta(days=1)
    return now + dt.timedelta(minutes=60)


def _render(text, values):
    def fill(match):
        key = match[1]
        if key not in values:
            raise ValueError('Unfilled prompt value: ' + key)
        value = values[key]
        if isinstance(value, list) and value and all(isinstance(item, str) for item in value):
            # A batch of ready-written blocks (cards, ideas); a list keeps it splittable on `cut`.
            return '\n\n'.join(value)
        return value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    return re.sub(r'\{\{(\w+)\}\}', fill, text)


def _halve(values, second=False):
    values = dict(values)
    # The method passes batches as lists; preserve the corresponding count.
    for key in ('cards', 'cards_with_paragraphs', 'cards_with_tests_without_answers', 'ideas_with_paragraphs'):
        if key in values:
            items = values[key]
            if isinstance(items, str):
                try:
                    items = json.loads(items)
                except ValueError:
                    continue
            if isinstance(items, list) and len(items) > 1:
                middle = math.ceil(len(items) / 2)
                values[key] = items[middle:] if second else items[:middle]
                count = 'idea_count' if key == 'ideas_with_paragraphs' else 'card_count'
                values[count] = len(values[key])
                return values
    return None


def call(role, step, values, job_id=None, avoid_family=None):
    config = settings.load()
    prompt = (CARDMAKER / 'prompts' / (step + '.md')).read_text(encoding='utf-8')
    parts = re.split(r'^=====\s*$', prompt, maxsplit=1, flags=re.M)
    if len(parts) != 2:
        raise ValueError('Prompt needs a ===== separator: ' + step)
    # Some existing prompts also have setting placeholders in the system part.
    system, user = (_render(part, values) for part in parts)
    schema = json.loads((CARDMAKER / 'schemas.json').read_text(encoding='utf-8'))[step]
    names = list(config['roles'][role])
    if avoid_family:
        names.sort(key=lambda name: config['providers'][name].get('family') == avoid_family)
    path = settings.home() / 'qualified.json'
    qualified = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    last = None
    for name in names:
        provider = config['providers'][name]
        if not provider.get('enabled', True) or not provider.get('model'):
            continue
        if config['quality']['require_qualified'] and role != 'scout' and not qualified.get(name, {}).get(role, {}).get('passed'):
            continue
        if provider.get('tools') == 'on':
            allowed = {'scout', 'select', 'quiz', 'solve'}
            if config['quality']['tools_on_source_text']:
                allowed.update(('choose', 'write', 'judge'))
            if role not in allowed:
                continue
        now = dt.datetime.now().astimezone()
        until = resting().get(name)
        if until and dt.datetime.fromisoformat(until).astimezone() > now:
            continue
        if calls_today(name) >= provider.get('max_calls_per_day', 100):
            _rest(name, (now + dt.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0))
            continue
        attempt_user = user
        remainder = None
        first_half = None
        for attempt in range(3):
            if calls_today(name) >= provider.get('max_calls_per_day', 100):
                _rest(name, (now + dt.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0))
                break
            result = run_provider(name, system, attempt_user, schema, _role=role, _job_id=job_id, _step=step)
            if result['ok']:
                if remainder is not None and first_half is None:
                    first_half = result
                    attempt_user = _render(parts[1], remainder)
                    continue
                if first_half is not None:
                    left, right = first_half['data'], result['data']
                    if not (isinstance(left, dict) and isinstance(right, dict)
                            and left.keys() == right.keys()
                            and all(isinstance(left[key], list) and isinstance(right[key], list) for key in left)):
                        break
                    result['data'] = {key: left[key] + right[key] for key in left}
                    for key in ('seconds', 'tokens_in', 'tokens_out'):
                        result[key] += first_half[key]
                return {**result, 'provider': name}
            last = result
            kind = result['error_kind']
            if kind == 'limit':
                _rest(name, _resume_time(result['error']))
            if attempt or kind not in ('cut', 'bad_json', 'schema'):
                break
            if kind == 'cut':
                smaller = _halve(values)
                if smaller is None:
                    break
                remainder = _halve(values, second=True)
                attempt_user = _render(parts[1], smaller)
            else:
                attempt_user = user + '\n\nPrevious answer failed validation: ' + result['error']
    if job_id:
        with closing(store.connect()) as db, db:
            db.execute("UPDATE jobs SET status='waiting', updated_at=? WHERE id=?",
                       (dt.datetime.now().astimezone().isoformat(), job_id))
    # `limit` when every provider was resting or capped (nothing went wrong); else the last real failure.
    kind = 'limit' if last is None or last['error_kind'] == 'limit' else last['error_kind']
    message = 'No available provider for role ' + role + (f" (last: {last['error_kind']}: {last['error']})" if last else '')
    return {**_failure(kind, message), 'seconds': 0, 'tokens_in': 0, 'tokens_out': 0}

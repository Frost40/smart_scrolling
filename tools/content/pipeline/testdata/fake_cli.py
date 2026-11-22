"""Offline model program, run with py -3 fake_cli.py CASE SCHEMA OUTPUT."""

import json
import os
from pathlib import Path
import sys
import time

case, schema_file, out_file = sys.argv[1:4]
answers = json.loads(Path(__file__).with_name('answers.json').read_text())
assert json.loads(Path(schema_file).read_text())['type'] == 'object'
assert Path.cwd().name == 'sandbox'
assert 'PIPELINE_TEST_SECRET' not in os.environ
if case == 'text':
    print(json.dumps(answers['ok']))
elif case == 'file':
    Path(out_file).write_text(json.dumps(answers['ok']), encoding='utf-8')
elif case == 'stream':
    event = json.loads(sys.stdin.readline())
    assert event['event'] == 'user'
    assert 'system' in event['message']['content']
    print(json.dumps({'event': 'init'}))
    print(json.dumps({'event': 'result', 'result': answers['envelope']}))
elif case == 'bad_json':
    print('not JSON')
elif case == 'down':
    print('Authentication required', file=sys.stderr)
    sys.exit(1)
elif case == 'exit_error':
    print(json.dumps(answers['envelope']))
    sys.exit(1)
elif case == 'timeout':
    time.sleep(5)
elif case == 'stdin':
    assert sys.stdin.read() == 'user'
    print(json.dumps(answers['envelope']))
else:
    print(json.dumps(answers.get(case, answers['envelope'])))

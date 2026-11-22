"""The content pipeline commands: settings, provider diagnostics, add (make a source) and gates."""

import argparse
import json
from pathlib import Path
import sys

from . import cardmaker, exam, feeds, gates, licenses, llm, scout, settings, stages


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('settings')
    commands.add_parser('status')
    commands.add_parser('tick')
    commands.add_parser('dashboard')
    commands.add_parser('licenses')
    run = commands.add_parser('run')
    run.add_argument('stage', choices=stages.ORDER)
    wanted = commands.add_parser('want', help='add a book to the wish list')
    wanted.add_argument('title')
    wanted.add_argument('--author', default='')
    remove = commands.add_parser('remove-trial')
    remove.add_argument('source_id')
    qualify = commands.add_parser('eval', help='qualify a provider on the cardmaker exams')
    qualify.add_argument('--provider', required=True)
    qualify.add_argument('--role', choices=['judge', 'solve', 'choose', 'make'])
    change = commands.add_parser('set')
    change.add_argument('path')
    change.add_argument('value')
    probe = commands.add_parser('provider-test')
    probe.add_argument('name')
    make = commands.add_parser('add', help='make a source from a file')
    make.add_argument('file')
    make.add_argument('--sample', action='store_true')
    make.add_argument('--max-chunks', type=int)
    make.add_argument('--kind', choices=['book', 'paper', 'news', 'other'], default='book')
    make.add_argument('--title')
    make.add_argument('--author')
    make.add_argument('--license')
    telegram = commands.add_parser('telegram', help='sign in, or probe the book bot')
    telegram.add_argument('action', choices=['login', 'probe'])
    telegram.add_argument('title', nargs='?')
    telegram.add_argument('--press', nargs=2, type=int, metavar=('PROBE', 'OPTION'))
    telegram.add_argument('--qr', action='store_true', help='login: scan a QR code with the phone instead of typing a code')
    check = commands.add_parser('gates', help='run the code gates on a folder made by hand')
    check.add_argument('folder')
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    try:
        if args.command == 'licenses':
            for row in licenses.inventory():
                print(f"{row['id']} | {row['kind']} | {row['license']} | non-commercial: {row['noncommercial']}")
            return 0
        if args.command in ('tick', 'run'):
            return 1 if stages.tick(getattr(args, 'stage', None)) == 'failed' else 0
        if args.command == 'want':
            row = scout.want(args.title, args.author)
            print(f"Added: {row['title']} ({row['ol_work']}, {row['year']})")
            return 0
        if args.command == 'remove-trial':
            stages.remove_trial(args.source_id)
            return 0
        if args.command == 'dashboard':
            from . import dashboard
            dashboard.serve()
            return 0
        if args.command == 'telegram':
            from . import fetch_telegram
            if args.action == 'login':
                fetch_telegram.login(args.qr)
            elif bool(args.title) == bool(args.press):
                raise ValueError('probe needs a title or --press <probe> <option>, not both')
            else:
                fetch_telegram.probe(args.title, args.press)
            return 0
        if args.command == 'eval':
            return 0 if exam.run(args.provider, args.role) else 1
        if args.command == 'add':
            if args.file.startswith(('https://', 'http://')):
                job_id = feeds.add_link(args.file, sample=args.sample, license=args.license)
                cardmaker.run(job_id)
            else:
                job_id = cardmaker.add(args.file, args.sample, args.max_chunks, args.kind, args.title, args.author)
            report = json.loads((settings.home() / 'jobs' / job_id / 'report.json').read_text(encoding='utf-8'))
            print(f"Job {job_id}: {report['status']}" + (f" ({report['error']})" if report['error'] else ''))
            for name, count in report['steps'].items():
                print(f"  {name}: {count['in']} in, {count['out']} out")
            print(f"  pass rate {report['pass_rate']}; final {report['final']}; "
                  f"dropped {sum(map(len, report['dropped'].values()))} (see report.json)")
            print('  folder:', settings.home() / 'jobs' / job_id)
            return 0 if report['status'] in ('ready', 'review') else 1
        if args.command == 'gates':
            problems = gates.check_folder(Path(args.folder))
            for item, found in problems.items():
                print(f"{item}: {'pass' if not found else ''}")
                for problem in found:
                    print('  -', problem)
            return 1 if any(problems.values()) else 0
        if args.command == 'set':
            settings.set_value(args.path, args.value)
        elif args.command == 'settings':
            print(json.dumps(settings.load(), indent=2, ensure_ascii=False))
        elif args.command == 'status':
            print('Home:', settings.home())
            from .dashboard import state
            overview = state()
            print('Paused:', overview['paused'])
            for name in stages.ORDER:
                stage = overview['stages'][name]
                last = stage['last']
                print(f"{name}: enabled={stage['enabled']}, next={stage['next']}, "
                      + (f"{last['result']}: {last['summary']}" if last else stage['notice'] or 'no runs yet'))
            print('Books:', overview['books'], 'Jobs:', overview['jobs'])
            rests = llm.resting()
            for name, provider in settings.load()['providers'].items():
                print(f"{name}: enabled={provider.get('enabled', True)}, "
                      f"model={provider.get('model') or '(needs a model)'}, "
                      f"calls today={llm.calls_today(name)}/{provider.get('max_calls_per_day', 100)}, "
                      f"resting={rests.get(name, '-')}")
        elif args.command == 'provider-test':
            schema = {'type': 'object', 'properties': {'ok': {'type': 'boolean'},
                      'message': {'type': 'string'}}, 'required': ['ok', 'message'],
                      'additionalProperties': False}
            result = llm.run_provider(args.name, 'Return only JSON matching the supplied schema.',
                                     'Set ok to true and message to hello.', schema)
            print(json.dumps(result, indent=2, ensure_ascii=False))
            return 0 if result['ok'] else 1
    except (ValueError, KeyError, OSError) as exc:
        parser.exit(1, f'{type(exc).__name__}: {exc}\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

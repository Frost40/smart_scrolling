"""Qualification exams; scoring is defined in cardmaker/eval/README.md."""

import hashlib
import json
from pathlib import Path
import re
import tempfile

from . import cardmaker as cm, gates, llm, settings, text

EVAL = llm.CARDMAKER / 'eval'
MAKE_ROLES = ('summarize', 'brief', 'extract', 'select', 'write', 'quiz')
STEPS = {'judge': ('judge',), 'solve': ('solve',), 'choose': ('choose',),
         'make': (*MAKE_ROLES, 'judge', 'solve', 'referee')}


def prompt_hash(exam):
    schemas = cm.load(llm.CARDMAKER / 'schemas.json')
    digest = hashlib.sha256()
    for step in STEPS[exam]:
        digest.update(step.encode())
        digest.update((llm.CARDMAKER / 'prompts' / (step + '.md')).read_bytes())
        digest.update(json.dumps(schemas[step], sort_keys=True).encode())
    return digest.hexdigest()


def ask(provider, step, values, job_id=None):
    config = settings.load()
    entry = config['providers'][provider]
    if not entry.get('enabled', True) or not entry.get('model'):
        raise ValueError('Provider is disabled or needs a model: ' + provider)
    if entry.get('tools') == 'on' and step not in ('select', 'quiz', 'solve'):
        if step not in ('choose', 'write', 'judge') or not config['quality']['tools_on_source_text']:
            raise ValueError('Provider tools are not allowed for ' + step)
    parts = re.split(r'^=====\s*$', (llm.CARDMAKER / 'prompts' / (step + '.md')).read_text(encoding='utf-8'),
                     maxsplit=1, flags=re.M)
    system, user = (llm._render(part, values) for part in parts)
    schema = cm.load(llm.CARDMAKER / 'schemas.json')[step]
    result = llm.run_provider(provider, system, user, schema, _role=step, _step=step, _job_id=job_id)
    if not result['ok']:
        raise ValueError(f"{provider}/{step}: {result['error_kind']}: {result['error']}")
    problems = llm.check(result['data'], schema)
    if problems:
        raise ValueError('; '.join(problems))
    return {**result, 'provider': provider}


def case_line(name, expected, got, right):
    print(f"{name}: expected {expected}; got {got}; {'right' if right else 'wrong'}", flush=True)
    return right


def judge(provider):
    cases = cm.load(EVAL / 'judge-cases.json')['cases']
    expect = cm.load(EVAL / 'trap-attention.expect.json')
    paragraphs = re.split(r'\n\s*\n', (EVAL / 'trap-attention.txt').read_text(encoding='utf-8').strip())[1:]
    good, bad_passed, good_rejected = 0, 0, 0
    for start in range(0, len(cases), 4):
        batch = cases[start:start + 4]
        blocks = []
        for i, case in enumerate(batch, start + 1):
            card = case['card']
            context = cm.brief_values(expect['brief'])
            blocks.append(f"Card ref {i}\n" + '\n'.join(f'{k}: {v}' for k, v in card.items()) +
                          f"\n<source_context>\nGlossary: {context['glossary']}\nPeople: {context['people']}\n</source_context>" +
                          '\n<paragraphs>\n' + '\n\n'.join(paragraphs[int(n[1:]) - 1] for n in case['paragraphs']) +
                          '\n</paragraphs>')
        data = ask(provider, 'judge', {**expect['source'], 'authors': ', '.join(expect['source']['authors']),
                   'thesis': expect['brief']['thesis'], 'card_count': len(batch), 'cards_with_paragraphs': blocks})['data']
        verdicts = data['verdicts']
        for i, case in enumerate(batch, start + 1):
            matches = [v for v in verdicts if v['ref'] == str(i)]
            got = ('pass' if all(matches[0][k] for k in cm.SIX) else 'fail') if len(matches) == 1 else 'missing/duplicate'
            good += case_line(f'judge {i}', case['expect'], got, got == case['expect'])
            bad_passed += case['expect'] == 'fail' and got != 'fail'
            good_rejected += case['expect'] == 'pass' and got != 'pass'
    return not bad_passed and good_rejected <= 1, good, len(cases), []


def solve(provider):
    good = total = 0
    fields = {'multiple_choice': 'choice', 'true_false': 'is_true', 'ordering': 'order', 'matching': 'pairs', 'flashcard': 'text'}
    for case in cm.load(EVAL / 'solve-cases.json')['cases']:
        card = case['card']
        block = '<card>\n' + '\n'.join(f'{k}: {v}' for k, v in card.items()) + '\n</card>\n'
        for test in case['tests']:
            block += '<test>\n' + '\n'.join(f'{k}: {json.dumps(v, ensure_ascii=False)}' for k, v in test.items() if k != 'key') + '\n</test>\n'
        data = ask(provider, 'solve', {'cards_with_tests_without_answers': [block]})['data']
        for test in case['tests']:
            matches = [a for a in data['answers'] if a['test'] == test['id']]
            got = 'missing/duplicate'
            if len(matches) == 1:
                got = matches[0][fields[test['type']]] if matches[0]['answerable'] else 'unanswerable'
            right = type(got) is type(test['key']) and got == test['key']
            good += case_line('solve ' + test['id'], test['key'], got, right)
            total += 1
    return good == total, good, total, []


def choose(provider):
    cases = cm.load(EVAL / 'choose-cases.json')['cases']
    good = 0
    for i, case in enumerate(cases, 1):
        got = ask(provider, 'choose', {**case['book'], 'authors': ', '.join(case['book']['authors']),
                  'languages': 'English', 'formats': ', '.join(settings.load()['fetch']['formats']),
                  'options': '\n'.join(f'{n}: {label}' for n, label in enumerate(case['options']))})['data']['index']
        expected = case['right'] if isinstance(case['right'], list) else [case['right']]
        good += case_line(f'choose {i}', expected, got, got in expected)
    return good == len(cases), good, len(cases), []


def best(role, provider, qualified):
    config = settings.load()
    ordered = list(dict.fromkeys(config['roles'][role] + list(config['providers'])))
    names = [n for n in ordered if n != provider and qualified.get(n, {}).get(role, {}).get('passed')
             and config['providers'][n].get('enabled', True) and config['providers'][n].get('model')]
    return names[0] if names else provider


def trap_output(provider, path, expect, judge_provider, solver):
    # Temporary files contain only the fixture; calls still use the real home's caps and history.
    with tempfile.TemporaryDirectory(prefix='pipeline-exam-') as temporary:
        folder = Path(temporary)
        cm.save(folder / 'meta.json', {**expect['source'], 'sample': True})
        raw = path.read_text(encoding='utf-8')
        parts = re.split(r'\n\s*\n', raw.strip())
        cm.write_file(folder / 'text.txt', raw)
        cm.save(folder / 'paragraphs.json', [{'n': i, 'text': p, 'heading': parts[0]} for i, p in enumerate(parts[1:], 1)])
        job = cm.Job('trial-exam-' + path.stem, folder=folder)
        job.config['make']['cards']['book'].update(min=4, max=4)
        def call(role, name, values, avoid_family=None):
            target = judge_provider if role == 'judge' else solver if role == 'solve' else provider
            return ask(target, name, values, job.id)
        job.ask = call
        cm.prepare(job)
        brief = expect['brief']
        summaries = cm.summarize(job)
        ideas = cm.extract(job, brief, summaries)
        chosen, _ = cm.select(job, brief, ideas, True)
        cards, tests, _ = cm.make_cards(job, brief, chosen)
        cm.save(settings.home() / 'logs' / f'exam-work-{cm.slug(provider)}-{path.stem}.json',
                {'steps': job.counts, 'dropped': job.dropped, 'ideas': ideas, 'chosen': chosen,
                 'cards': cards, 'tests': tests})
        return cards, [t for group in tests.values() for t in group]


def score_trap(expect, cards, tests, findings):
    card_texts = [' '.join(str(c.get(k, '')) for k in ('title', 'front', 'back', 'speaker')) for c in cards]
    card_text = ' '.join(card_texts)
    # Wrong answer choices are meant to be believable mistakes (quiz.md rule 3), such as a swapped number, so
    # patterns check only the right choice; the referee still reads every choice.
    def shown(t):
        kept = {k: v for k, v in t.items() if k not in ('id', 'card', 'tests')}
        if 'choices' in kept:
            kept['choices'] = [kept['choices'][t['correct_choice']]]
        return json.dumps(kept, ensure_ascii=False)
    texts = card_texts + [shown(t) for t in tests]
    reasons = []
    if not cards:
        reasons.append('no cards')
    for pattern in expect['forbidden_patterns']:
        if any(re.search(pattern, value, re.I) for value in texts):
            reasons.append('forbidden pattern: ' + pattern)
    allowed = {str(n) for n in expect['allowed_numbers']}
    for number in gates.NUMBER.findall(card_text):
        if number not in allowed:
            reasons.append('forbidden number: ' + number)
    for i in range(1, len(expect['must_not_say']) + 1):
        matches = [f for f in findings if f['statement'] == i]
        if len(matches) != 1 or matches[0]['said']:
            reasons.append(f'referee statement {i}')
    covered = sum(any(word.lower() in card_text.lower() for word in idea['any_of']) for idea in expect['should_cover'])
    if covered < min(2, len(expect['should_cover'])):
        reasons.append(f'coverage {covered}/{min(2, len(expect["should_cover"]))}')
    return reasons


def make(provider):
    file = settings.home() / 'qualified.json'
    qualified = cm.load(file) if file.exists() else {}
    judge_provider, solver = (best(role, provider, qualified) for role in ('judge', 'solve'))
    notes = [f'{role}: provider under test used because no other qualified provider was selected'
             for role, name in (('judge', judge_provider), ('solve', solver)) if name == provider]
    paths = sorted(EVAL.glob('trap-*.txt'))
    good = 0
    for path in paths:
        expect = cm.load(path.with_suffix('.expect.json'))
        cards, tests = trap_output(provider, path, expect, judge_provider, solver)
        findings = ask(judge_provider, 'referee', {
            'statements': '\n'.join(f'{i}: {s}' for i, s in enumerate(expect['must_not_say'], 1)),
            'cards_and_tests': json.dumps({'cards': cards, 'tests': tests}, ensure_ascii=False)})['data']['findings']
        reasons = score_trap(expect, cards, tests, findings)
        cm.save(settings.home() / 'logs' / f'exam-{cm.slug(provider)}-{path.stem}.json',
                {'provider': provider, 'judge': judge_provider, 'solver': solver, 'cards': cards,
                 'tests': tests, 'findings': findings, 'reasons': reasons, 'notes': notes})
        good += case_line(path.stem, 'all four checks pass', '; '.join(reasons) or 'pass', not reasons)
    return bool(paths) and good == len(paths), good, len(paths), notes


def run(provider, role=None):
    if provider not in settings.load()['providers']:
        raise ValueError('Unknown provider: ' + provider)
    path = settings.home() / 'qualified.json'
    success = True
    for name in ([role] if role else ['judge', 'solve', 'choose', 'make']):
        error = None
        try:
            passed, good, total, notes = globals()[name](provider)
            score = f'{good}/{total}'
        except ValueError as exc:
            passed, score, notes, error = False, 'incomplete', [str(exc)], exc
        result = {'passed': passed, 'score': score, 'date': cm.now(), 'prompts': prompt_hash(name)}
        if notes:
            result['notes'] = notes
        qualified = cm.load(path) if path.exists() else {}
        for covered in (MAKE_ROLES if name == 'make' else (name,)):
            qualified.setdefault(provider, {})[covered] = result
        cm.save(path, qualified)
        print(f"{provider} {name}: {'PASS' if passed else 'FAIL'} {score}" + ('; ' + '; '.join(notes) if notes else ''), flush=True)
        success &= passed
        if error:
            break  # An unavailable provider cannot prove another role; do not spend more calls.
    return success


SOURCE_TEXT_ROLES = ('extract', 'summarize', 'brief', 'write', 'judge', 'choose')


def _score_ratio(entry):
    parts = str(entry.get('score', '0/1')).split('/')
    return int(parts[0]) / max(1, int(parts[1])) if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit() else 0.0


def _cost_rank(name, entry):
    if entry.get('family') == 'local':
        return (0, name)
    if name in ('gemini-api', 'openrouter'):
        return (1, name)
    if entry.get('family') == 'google':
        model = entry.get('model', '')
        tier = 0 if 'low' in model else 1 if 'medium' in model else 2
        kind = 0 if 'flash' in model else 3 if 'argon' in model else 6
        return (2 + kind + tier, name)
    if 'haiku' in name or 'haiku' in entry.get('model', ''):
        return (10, name)
    if entry.get('family') == 'openai':
        return (11, name)
    if 'sonnet' in name or 'sonnet' in entry.get('model', ''):
        return (12, name)
    return (20, name)


def recommend_roles(config, qualified):
    """Order enabled, qualified providers per role using the ticket 09 rules."""
    providers = config['providers']
    allow_tools = config['quality'].get('tools_on_source_text', False)

    def eligible(role):
        out = []
        for name, entry in providers.items():
            if not entry.get('enabled', True) or not entry.get('model'):
                continue
            if entry.get('tools') == 'on' and role in SOURCE_TEXT_ROLES and not allow_tools:
                continue
            if role == 'scout' or qualified.get(name, {}).get(role, {}).get('passed'):
                out.append(name)
        return out

    def claude_last(ordered):
        claude = [n for n in ordered if providers[n].get('family') == 'anthropic']
        others = [n for n in ordered if providers[n].get('family') != 'anthropic']
        if not claude:
            return others
        # Keep the first item if it is the best writer/judge and there is only one Claude, unless others exist to precede a fallback.
        return others + claude if others else claude

    roles = {}
    for role in ('write', 'extract'):
        ranked = sorted(eligible(role), key=lambda n: (-_score_ratio(qualified[n][role]), _cost_rank(n, providers[n])))
        if len(ranked) > 1 and providers[ranked[0]].get('family') == 'anthropic':
            # Best scorer is Claude; keep it first, append any other Claude at the end if present.
            tail_claude = [n for n in ranked[1:] if providers[n].get('family') == 'anthropic']
            others = [n for n in ranked[1:] if providers[n].get('family') != 'anthropic']
            roles[role] = [ranked[0], *others, *tail_claude]
        else:
            roles[role] = claude_last(ranked)

    for role in ('summarize', 'brief', 'select', 'quiz', 'choose', 'scout'):
        ranked = sorted(eligible(role), key=lambda n: _cost_rank(n, providers[n]))
        roles[role] = claude_last(ranked)

    write_family = providers[roles['write'][0]].get('family') if roles['write'] else None
    judge_ranked = sorted(eligible('judge'), key=lambda n: (
        providers[n].get('family') == write_family if write_family else False,
        -_score_ratio(qualified[n]['judge']),
        _cost_rank(n, providers[n]),
    ))
    other_family_non_claude = any(providers[n].get('family') not in ('anthropic', write_family) for n in judge_ranked)
    roles['judge'] = claude_last(judge_ranked) if other_family_non_claude else judge_ranked

    quiz_family = providers[roles['quiz'][0]].get('family') if roles['quiz'] else None
    solve_ranked = sorted(eligible('solve'), key=lambda n: (
        providers[n].get('family') == quiz_family if quiz_family else False,
        _cost_rank(n, providers[n]),
    ))
    other_family_non_claude = any(providers[n].get('family') not in ('anthropic', quiz_family) for n in solve_ranked)
    roles['solve'] = claude_last(solve_ranked) if other_family_non_claude else solve_ranked
    return {role: roles[role] for role in config['roles']}

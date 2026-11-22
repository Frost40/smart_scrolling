"""Offline exam checks, including deliberately wrong model answers."""

import copy
import re
from unittest.mock import patch

from . import cardmaker as cm, exam, llm, settings
from .test_cardmaker import HomeTest, FakeModel, ANSWERS


class ExamTests(HomeTest):
    def judge_answer(self, wrong=()):
        cases = cm.load(exam.EVAL / 'judge-cases.json')['cases']
        def fake(name, system, user, schema, **kwargs):
            self.assertIn('<source_context>', user)
            verdicts = []
            for ref in re.findall(r'^Card ref (\d+)', user, re.M):
                passed = cases[int(ref) - 1]['expect'] == 'pass'
                if int(ref) in wrong:
                    passed = not passed
                verdicts.append({'ref': ref, **dict.fromkeys(cm.SIX, passed), 'notes': '', 'problem': '', 'fix': ''})
            return {'ok': True, 'data': {'verdicts': verdicts}}
        return fake

    def test_judge_bad_card_passed_fails(self):
        with patch.object(llm, 'run_provider', side_effect=self.judge_answer((5,))):
            self.assertFalse(exam.judge('claude-haiku')[0])

    def test_judge_two_good_rejected_fails(self):
        with patch.object(llm, 'run_provider', side_effect=self.judge_answer((1, 2))):
            self.assertFalse(exam.judge('claude-haiku')[0])

    def test_one_good_rejected_passes_and_saves_hash(self):
        with patch.object(llm, 'run_provider', side_effect=self.judge_answer((1,))):
            self.assertTrue(exam.run('claude-haiku', 'judge'))
        result = cm.load(settings.home() / 'qualified.json')['claude-haiku']['judge']
        total = len(cm.load(exam.EVAL / 'judge-cases.json')['cases'])
        self.assertEqual(result['score'], f'{total - 1}/{total}')
        self.assertEqual(result['prompts'], exam.prompt_hash('judge'))
        self.assertEqual(len(result['prompts']), 64)
        self.assertIn('date', result)

    def test_solver_guesses_unanswerable_fails(self):
        cases = cm.load(exam.EVAL / 'solve-cases.json')['cases']
        for guess in (False, True):
            def fake(name, system, user, schema, **kwargs):
                self.assertNotIn('key:', user)
                answers = []
                for case in cases:
                    for test in case['tests']:
                        if test['id'] not in user:
                            continue
                        answer = {'test': test['id'], 'answerable': test['key'] != 'unanswerable' or guess,
                                  'choice': 0, 'is_true': False, 'order': [], 'pairs': [], 'text': ''}
                        if test['key'] != 'unanswerable':
                            answer['choice' if test['type'] == 'multiple_choice' else 'is_true'] = test['key']
                        answers.append(answer)
                return {'ok': True, 'data': {'answers': answers, 'unclear': []}}
            with patch.object(llm, 'run_provider', side_effect=fake):
                self.assertEqual(exam.solve('claude-haiku')[0], not guess)

    def trap(self, change=None, said=False):
        path = exam.EVAL / 'trap-attention.txt'
        expect = cm.load(path.with_suffix('.expect.json'))
        fake = FakeModel(copy.deepcopy(ANSWERS))
        fake.cut = False
        def checked(name, system, user, schema, **kwargs):
            if kwargs.get('_step') == 'judge':
                self.assertIn('<source_context>', user)
                self.assertIn('People:', user)
                self.assertIn('Glossary:', user)
                self.assertNotIn('{{', user)
            return fake(name, system, user, schema, **kwargs)
        with patch.object(llm, 'run_provider', side_effect=checked):
            cards, tests = exam.trap_output('claude-haiku', path, expect, 'claude-sonnet', 'claude-haiku')
        self.assertTrue(cards)
        if change:
            cards[0]['front'] += change
        findings = [{'statement': i, 'said': said, 'where': '', 'quote': ''}
                    for i in range(1, len(expect['must_not_say']) + 1)]
        return exam.score_trap(expect, cards, tests, findings)

    def test_make_saved_answers_pass(self):
        self.assertEqual(self.trap(), [])

    def test_make_forbidden_pattern_fails(self):
        self.assertTrue(any('pattern' in r for r in self.trap(' As we saw.')))

    def test_make_forbidden_number_fails(self):
        self.assertTrue(any('number' in r for r in self.trap(' 99999 workers.')))

    def test_make_referee_finding_fails(self):
        self.assertTrue(any('referee' in r for r in self.trap(said=True)))

    def test_wrong_choice_may_hold_a_forbidden_pattern(self):
        expect = cm.load(exam.EVAL / 'trap-numbers.expect.json')
        card = {'title': 'Sleep and failing', 'front': 'Seven hours of sleep went with a 41 percent lower chance of failing.',
                'back': 'The study followed first-year students for one term; 14 percent higher marks were for problem-solving exams.'}
        test = {'type': 'multiple_choice', 'prompt': 'What did the study find?', 'explanation': 'Failing fell.',
                'choices': ['A 14 percent lower chance of failing', 'A 41 percent lower chance of failing', 'No change', 'More failing'],
                'correct_choice': 1}
        findings = [{'statement': i, 'said': False} for i in range(1, len(expect['must_not_say']) + 1)]
        self.assertEqual(exam.score_trap(expect, [card], [test], findings), [])
        test['correct_choice'] = 0
        self.assertTrue(any('pattern' in r for r in exam.score_trap(expect, [card], [test], findings)))

    def test_missing_referee_and_empty_output_fail(self):
        expect = cm.load(exam.EVAL / 'trap-attention.expect.json')
        reasons = exam.score_trap(expect, [], [], [])
        self.assertIn('no cards', reasons)
        self.assertIn('referee statement 1', reasons)

    def test_other_card_cannot_explain_a_missing_name(self):
        expect = cm.load(exam.EVAL / 'trap-term.expect.json')
        cards = [{'front': 'Okonkwo budgets spare time.'}, {'front': 'Adaeze explains spare time.'}]
        reasons = exam.score_trap(expect, cards, [], [])
        self.assertTrue(any('forbidden pattern' in r for r in reasons))

    def test_qualification_file_controls_llm(self):
        cm.save(settings.home() / 'qualified.json', {'claude-sonnet': {'judge': {'passed': False}},
                                                   'claude-haiku': {'judge': {'passed': True}}})
        with patch.object(llm, 'run_provider', return_value={'ok': True, 'data': {'verdicts': []}}) as fake:
            answer = llm.call('judge', 'judge', {'title': 'Test', 'authors': 'Tester', 'kind': 'book',
                              'thesis': 'Test', 'card_count': 0, 'cards_with_paragraphs': []})
        self.assertEqual(answer['provider'], 'claude-haiku')
        self.assertEqual(fake.call_count, 1)

    def test_failed_call_revokes_previous_pass(self):
        cm.save(settings.home() / 'qualified.json', {'claude-haiku': {'judge': {'passed': True}}})
        with patch.object(llm, 'run_provider', return_value={'ok': False, 'error_kind': 'limit', 'error': 'resting'}):
            self.assertFalse(exam.run('claude-haiku', 'judge'))
        self.assertFalse(cm.load(settings.home() / 'qualified.json')['claude-haiku']['judge']['passed'])

    def test_choose_numbering_and_acceptable_choices(self):
        cases = iter(cm.load(exam.EVAL / 'choose-cases.json')['cases'])
        def fake(name, system, user, schema, **kwargs):
            case = next(cases)
            self.assertIn('0: ' + case['options'][0], user)
            self.assertIn('English', system)
            right = case['right']
            return {'ok': True, 'data': {'index': right[-1] if isinstance(right, list) else right, 'reason': ''}}
        with patch.object(llm, 'run_provider', side_effect=fake):
            self.assertTrue(exam.choose('claude-haiku')[0])

    def test_make_records_all_six_roles_and_preserves_others(self):
        cm.save(settings.home() / 'qualified.json', {'claude-sonnet': {'judge': {'passed': True}}})
        with patch.object(exam, 'make', return_value=(False, 3, 4, ['test finding'])):
            self.assertFalse(exam.run('claude-haiku', 'make'))
        saved = cm.load(settings.home() / 'qualified.json')
        self.assertEqual(set(saved['claude-haiku']), set(exam.MAKE_ROLES))
        self.assertTrue(saved['claude-sonnet']['judge']['passed'])
        self.assertTrue(all(not r['passed'] for r in saved['claude-haiku'].values()))

    def test_best_prefers_other_qualified_model(self):
        qualified = {n: {'solve': {'passed': True}} for n in ('claude-haiku', 'claude-sonnet')}
        self.assertEqual(exam.best('solve', 'claude-haiku', qualified), 'claude-sonnet')

    def test_recommend_roles_follows_rules(self):
        config = settings.load()
        config['providers']['codex'].update(enabled=True, model='gpt-6-luna')
        config['providers']['gemini-cli'].update(enabled=True, model='gemini-3.8-flash-medium')
        config['providers']['openrouter'].update(enabled=True, model='unqualified-model')
        qualified = {
            'claude-sonnet': {
                'judge': {'passed': True, 'score': '18/18'},
                **{r: {'passed': True, 'score': '4/4'} for r in exam.MAKE_ROLES},
            },
            'claude-haiku': {
                'judge': {'passed': True, 'score': '17/18'},
                'solve': {'passed': True, 'score': '7/7'},
                'choose': {'passed': True, 'score': '5/5'},
                **{r: {'passed': False, 'score': '3/4'} for r in exam.MAKE_ROLES},
            },
            'codex': {
                'judge': {'passed': True, 'score': '18/18'},
                'solve': {'passed': True, 'score': '7/7'},
            },
            'gemini-cli': {
                'judge': {'passed': True, 'score': '18/18'},
                'solve': {'passed': True, 'score': '7/7'},
                'choose': {'passed': True, 'score': '5/5'},
                **{r: {'passed': True, 'score': '4/4'} for r in exam.MAKE_ROLES},
            },
            'openrouter': {
                'judge': {'passed': False, 'score': '10/18'},
            },
        }
        roles = exam.recommend_roles(config, qualified)
        # Unqualified provider appears in no list (except scout if enabled+model, here openrouter has model so scout may include it, wait: check exam roles).
        for role, providers in roles.items():
            if role != 'scout':
                self.assertNotIn('openrouter', providers)
        # tools: on provider kept out of the six source-text roles when tools_on_source_text is false.
        for role in ('extract', 'summarize', 'brief', 'write', 'judge', 'choose'):
            self.assertNotIn('gemini-cli', roles[role])
        # write is claude-sonnet (anthropic), so judge puts codex (openai) before claude-sonnet/haiku.
        self.assertEqual(roles['write'][0], 'claude-sonnet')
        self.assertEqual(roles['judge'][0], 'codex')
        self.assertEqual(roles['judge'][-1], 'claude-haiku')
        # quiz can use gemini-cli (google); solve prefers another family than quiz[0] (google -> openai/anthropic).
        self.assertEqual(roles['quiz'][0], 'gemini-cli')
        self.assertNotEqual(config['providers'][roles['solve'][0]]['family'],
                            config['providers'][roles['quiz'][0]]['family'])
        # Every list with a passing Claude ends with a Claude provider.
        for role in ('judge', 'solve', 'choose', 'write', 'quiz'):
            self.assertEqual(config['providers'][roles[role][-1]]['family'], 'anthropic')

        # With tools_on_source_text=True, gemini-cli is allowed in judge/write/etc.
        config['quality']['tools_on_source_text'] = True
        roles_tools = exam.recommend_roles(config, qualified)
        self.assertIn('gemini-cli', roles_tools['judge'])

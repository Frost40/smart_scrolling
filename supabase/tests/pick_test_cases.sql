-- Run with: python supabase/run_sql.py supabase/tests/pick_test_cases.sql
-- The shared cases for picking a test (D32). test/domain/test_picker_test.dart
-- runs the JSON list below against the phone's rule, so the
-- phone and the database pick the same test. Test ids get the prefix
-- 'pick-case/'. An answer with "other": true was given through another
-- linked card. Temporary rows only; everything rolls back.
begin;
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-8000-00000000009a', 'pick-cases@test.invalid', 'authenticated', 'authenticated');
insert into public.sources (id, kind, title, status, is_sample) values
  ('pick-case', 'other', 'Pick cases', 'published', true);
insert into public.discover_cards (id, source_id, format, title, front, status) values
  ('pick-case/concept', 'pick-case', 'concept', 'Concept', 'Front', 'published'),
  ('pick-case/other', 'pick-case', 'concept', 'Other', 'Front', 'published');
insert into public.likes (user_id, discover_card_id) values
  ('00000000-0000-4000-8000-00000000009a', 'pick-case/concept');

do $test$
declare
  c jsonb;
  t jsonb;
  a jsonb;
  got text;
begin
  for c in select jsonb_array_elements($cases$
[
  {"name": "unanswered tests go by id", "filter": "mix",
   "tests": [{"id": "flash", "type": "flashcard"}, {"id": "choice", "type": "multiple_choice"}, {"id": "tf", "type": "true_false"}],
   "answers": [], "pick": "choice"},
  {"name": "never answered comes before answered", "filter": "mix",
   "tests": [{"id": "flash", "type": "flashcard"}, {"id": "choice", "type": "multiple_choice"}],
   "answers": [{"test": "choice", "at": "2026-10-20T10:00:00Z"}], "pick": "flash"},
  {"name": "oldest latest answer wins", "filter": "mix",
   "tests": [{"id": "flash", "type": "flashcard"}, {"id": "choice", "type": "multiple_choice"}],
   "answers": [{"test": "choice", "at": "2026-10-20T10:00:00Z"}, {"test": "flash", "at": "2026-10-22T10:00:00Z"}], "pick": "choice"},
  {"name": "a test's latest answer counts, not its first", "filter": "mix",
   "tests": [{"id": "flash", "type": "flashcard"}, {"id": "choice", "type": "multiple_choice"}],
   "answers": [{"test": "choice", "at": "2026-10-19T10:00:00Z"}, {"test": "flash", "at": "2026-10-20T10:00:00Z"},
               {"test": "choice", "at": "2026-10-23T10:00:00Z"}], "pick": "flash"},
  {"name": "equal latest answers fall back to id", "filter": "mix",
   "tests": [{"id": "flash", "type": "flashcard"}, {"id": "choice", "type": "multiple_choice"}],
   "answers": [{"test": "flash", "at": "2026-10-20T10:00:00Z"}, {"test": "choice", "at": "2026-10-20T10:00:00Z"}], "pick": "choice"},
  {"name": "microseconds count", "filter": "mix",
   "tests": [{"id": "flash", "type": "flashcard"}, {"id": "choice", "type": "multiple_choice"}],
   "answers": [{"test": "choice", "at": "2026-10-20T10:00:00.000002Z"}, {"test": "flash", "at": "2026-10-20T10:00:00.000001Z"}], "pick": "flash"},
  {"name": "time zones compare as instants", "filter": "mix",
   "tests": [{"id": "flash", "type": "flashcard"}, {"id": "choice", "type": "multiple_choice"}],
   "answers": [{"test": "choice", "at": "2026-10-20T12:00:00+03:00"}, {"test": "flash", "at": "2026-10-20T10:00:00Z"}], "pick": "choice"},
  {"name": "answers through another card count", "filter": "mix",
   "tests": [{"id": "flash", "type": "flashcard"}, {"id": "choice", "type": "multiple_choice"}],
   "answers": [{"test": "choice", "at": "2026-10-20T10:00:00Z", "other": true}], "pick": "flash"},
  {"name": "a strict filter only takes its type", "filter": "flashcard",
   "tests": [{"id": "flash", "type": "flashcard"}, {"id": "choice", "type": "multiple_choice"}],
   "answers": [{"test": "flash", "at": "2026-10-20T10:00:00Z"}], "pick": "flash"},
  {"name": "later types can be picked by name", "filter": "true_false",
   "tests": [{"id": "flash", "type": "flashcard"}, {"id": "tf", "type": "true_false"}],
   "answers": [], "pick": "tf"},
  {"name": "mix includes ordering", "filter": "mix",
   "tests": [{"id": "tf", "type": "true_false"}, {"id": "order", "type": "ordering"}],
   "answers": [], "pick": "order"},
  {"name": "mix includes matching", "filter": "mix",
   "tests": [{"id": "match", "type": "matching"}], "answers": [], "pick": "match"},
  {"name": "mix includes true false", "filter": "mix",
   "tests": [{"id": "tf", "type": "true_false"}], "answers": [], "pick": "tf"},
  {"name": "matching filter excludes other types", "filter": "matching",
   "tests": [{"id": "flash", "type": "flashcard"}, {"id": "match", "type": "matching"}],
   "answers": [], "pick": "match"},
  {"name": "no matching test picks nothing", "filter": "ordering",
   "tests": [{"id": "flash", "type": "flashcard"}],
   "answers": [], "pick": null},
  {"name": "shorter id first, then hyphen, digit, letter", "filter": "flashcard",
   "tests": [{"id": "ab-c", "type": "flashcard"}, {"id": "ab", "type": "flashcard"}, {"id": "a0", "type": "flashcard"},
             {"id": "a-b", "type": "flashcard"}, {"id": "a", "type": "flashcard"}],
   "answers": [], "pick": "a"},
  {"name": "hyphen sorts before a digit", "filter": "flashcard",
   "tests": [{"id": "ab-c", "type": "flashcard"}, {"id": "ab0", "type": "flashcard"}, {"id": "abb", "type": "flashcard"}],
   "answers": [], "pick": "ab-c"},
  {"name": "a prefix sorts before a longer id", "filter": "flashcard",
   "tests": [{"id": "ab-c", "type": "flashcard"}, {"id": "ab", "type": "flashcard"}],
   "answers": [{"test": "ab-c", "at": "2026-10-20T10:00:00Z"}, {"test": "ab", "at": "2026-10-20T10:00:00Z"}], "pick": "ab"}
]
$cases$::jsonb) loop
    delete from public.practice_answers where user_id = '00000000-0000-4000-8000-00000000009a';
    delete from public.practice_cards where source_id = 'pick-case';
    for t in select jsonb_array_elements(c->'tests') loop
      insert into public.practice_cards (id, source_id, type, prompt, answer, choices, correct_choice,
        is_true, correct_order, match_left, match_right, status)
      values ('pick-case/' || (t->>'id'), 'pick-case', t->>'type', 'Prompt', 'Answer', '{x,y}', 0,
        true, '{x,y}', '{x,y}', '{x,y}', 'published');
      insert into public.practice_links (discover_card_id, practice_card_id)
      values ('pick-case/concept', 'pick-case/' || (t->>'id'));
    end loop;
    for a in select jsonb_array_elements(c->'answers') loop
      insert into public.practice_answers (id, user_id, practice_card_id, practice_card_version,
        discover_card_id, result, answered_at)
      values (gen_random_uuid(), '00000000-0000-4000-8000-00000000009a', 'pick-case/' || (a->>'test'), 1,
        case when (a->>'other')::boolean then 'pick-case/other' else 'pick-case/concept' end,
        'correct', (a->>'at')::timestamptz);
    end loop;

    perform set_config('request.jwt.claims',
      '{"sub":"00000000-0000-4000-8000-00000000009a","role":"authenticated"}', true);
    set local role authenticated;
    select id into got from public.pick_test('pick-case/concept', c->>'filter');
    reset role;
    if got is distinct from 'pick-case/' || (c->>'pick') then
      raise exception 'FAILED: % (picked %)', c->>'name', got;
    end if;
  end loop;
end $test$;
select 'pick_test cases: all passed' as result;
rollback;

-- Run with: python supabase/run_sql.py supabase/tests/practice.sql
-- Only sample-box content and temporary people; everything rolls back.
begin;
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-8000-00000000006a', 'practice-a@test.invalid', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000006b', 'practice-b@test.invalid', 'authenticated', 'authenticated');

create function pg_temp.expect(ok boolean, what text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAILED: %', what; end if;
end $$;

-- All five types share the same answer and timetable contract.
create function pg_temp.answer(p_id int, p_test text, p_at timestamptz,
  p_level smallint default 1, p_card text default 'sample-curious-learner/retrieval-practice')
returns public.likes language sql as $$
  select public.record_answer(
    ('00000000-0000-4000-8000-' || lpad(p_id::text, 12, '0'))::uuid,
    'sample-curious-learner/' || p_test, 1, p_card, '2'::jsonb, 'correct',
    p_at, p_level, p_at + interval '3 days');
$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000006a","role":"authenticated"}', true);
select public.like_card('sample-curious-learner/retrieval-practice');
select pg_temp.expect((select id from public.pick_test('sample-curious-learner/retrieval-practice')) =
  'sample-curious-learner/recall-choice', 'unanswered tests use stable id order');
select pg_temp.expect((select id from public.pick_test('sample-curious-learner/retrieval-practice', 'flashcard')) =
  'sample-curious-learner/recall-flash', 'filter is strict');
select pg_temp.expect((select id from public.pick_test('sample-curious-learner/retrieval-practice', 'ordering')) is null,
  'no matching test returns null');

select pg_temp.answer(601, 'recall-choice', '2026-10-20 10:00Z');
select pg_temp.expect((select id from public.pick_test('sample-curious-learner/retrieval-practice')) =
  'sample-curious-learner/recall-flash', 'never answered comes before answered');
select pg_temp.answer(602, 'recall-flash', '2026-10-22 10:00Z', 2::smallint);
select pg_temp.expect(not exists(select 1 from public.content_requests where kind = 'more_practice'),
  'unanswered tests prevent a premature request');
select pg_temp.answer(603, 'recall-true-false', '2026-10-21 10:00Z');
select pg_temp.expect((select review_level = 2 and last_reviewed_at = '2026-10-22 10:00Z'
  and next_review_at = '2026-10-25 10:00Z' from public.likes), 'later answer wins despite arrival order');
select pg_temp.expect((select count(*) from public.practice_answers) = 3, 'older answers are still kept');
select pg_temp.expect((select id from public.pick_test('sample-curious-learner/retrieval-practice')) =
  'sample-curious-learner/recall-choice', 'oldest last answer is picked');
select pg_temp.answer(604, 'recall-choice', '2026-10-23 10:00Z');
select pg_temp.expect((select id from public.pick_test('sample-curious-learner/retrieval-practice')) =
  'sample-curious-learner/recall-true-false', 'uses latest answer of each test across all five types');
select pg_temp.expect((select id from public.pick_test('sample-curious-learner/retrieval-practice', 'true_false')) =
  'sample-curious-learner/recall-true-false', 'later types can be selected explicitly');
select pg_temp.answer(604, 'recall-choice', '2026-10-23 10:00Z');
-- A reused id cannot sneak a different schedule into the Like.
select pg_temp.answer(604, 'recall-choice', '2026-10-29 10:00Z', 4::smallint);
select pg_temp.expect((select count(*) from public.practice_answers) = 4, 'retry inserts one row');
select pg_temp.expect((select last_reviewed_at from public.likes) = '2026-10-23 10:00Z', 'retry changes no timetable');
select pg_temp.expect((select count(*) from public.content_requests where kind = 'more_practice') = 1,
  'more_practice is created only once');
select pg_temp.answer(605, 'recall-flash', '2026-10-23 10:00Z', 4::smallint);
select pg_temp.expect((select review_level from public.likes) = 1, 'equal timestamps do not overwrite');

do $$ begin
  perform pg_temp.answer(606, 'myth-true-false', now());
  raise exception 'FAILED: accepted an unlinked test';
exception when no_data_found then null; end $$;

update public.likes set reviews_paused = true;
select pg_temp.expect((select id from public.pick_test('sample-curious-learner/retrieval-practice')) is null,
  'paused Likes do not pick tests');
update public.likes set reviews_paused = false;
do $$ begin
  perform pg_temp.answer(608, 'recall-flash', now(), 5::smallint);
  raise exception 'FAILED: accepted an invalid review level';
exception when invalid_parameter_value then null; end $$;
do $$ begin
  perform public.record_answer('00000000-0000-4000-8000-000000000609',
    'sample-curious-learner/recall-flash', 999, 'sample-curious-learner/retrieval-practice',
    'null', 'good', now(), 1::smallint, now() + interval '3 days');
  raise exception 'FAILED: accepted a future test version';
exception when no_data_found then null; end $$;

reset role;
update public.practice_cards set status = 'hidden' where id = 'sample-curious-learner/recall-flash';
set local role authenticated;
select pg_temp.expect((select id from public.pick_test('sample-curious-learner/retrieval-practice', 'flashcard')) is null,
  'hidden tests do not get picked');
do $$ begin
  perform pg_temp.answer(610, 'recall-flash', now());
  raise exception 'FAILED: accepted an unreadable test';
exception when no_data_found then null; end $$;
reset role;
update public.practice_cards set status = 'published' where id = 'sample-curious-learner/recall-flash';
set local role authenticated;

-- A second person sees no answers and must like the concept themselves.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000006b","role":"authenticated"}', true);
select pg_temp.expect((select count(*) from public.practice_answers) = 0, 'answers stay private');
select pg_temp.expect((select id from public.pick_test('sample-curious-learner/retrieval-practice')) is null,
  'cannot pick another person''s Like');
do $$ begin
  perform pg_temp.answer(607, 'recall-flash', now());
  raise exception 'FAILED: accepted answer without own Like';
exception when no_data_found then null; end $$;
select public.like_card('sample-curious-learner/retrieval-practice');
select pg_temp.expect((select id from public.pick_test('sample-curious-learner/retrieval-practice')) =
  'sample-curious-learner/recall-choice', 'another person''s answers do not affect picking');
do $$ begin
  perform pg_temp.answer(601, 'recall-choice', now());
  raise exception 'FAILED: accepted another person''s answer id';
exception when insufficient_privilege then null; end $$;

reset role;
select pg_temp.expect(not has_function_privilege('anon', 'public.pick_test(text,text)', 'execute'), 'anonymous picking is forbidden');
select 'practice: all passed' as result;
rollback;

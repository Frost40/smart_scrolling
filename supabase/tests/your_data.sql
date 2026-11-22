-- Temporary people and sample-box content only; all changes roll back.
begin;
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-8000-00000000013a', 'data-a@test.invalid', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000013b', 'data-b@test.invalid', 'authenticated', 'authenticated');
create function pg_temp.expect(ok boolean, what text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAILED: %', what; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000013b","role":"authenticated"}', true);
insert into public.profiles (weekly_goal_days) values (7);
select public.like_card('sample-curious-learner/retrieval-practice');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000013a","role":"authenticated"}', true);
insert into public.profiles (weekly_goal_days, discover_filter) values (3, 'quote');
insert into public.devices (installation_id, reminder_time, high_contrast)
values ('00000000-0000-4000-8000-000000000131', '20:30', true),
       ('00000000-0000-4000-8000-000000000132', '09:00', true);
insert into public.user_topics (topic_id, choice) select id, 'follow' from public.topics limit 1;
insert into public.user_sources (source_id, choice) values ('sample-curious-learner', 'follow');
select public.like_card('sample-curious-learner/retrieval-practice');
select public.save_for_later('sample-curious-learner/curiosity-gap');
insert into public.collections (id, name) values ('00000000-0000-4000-8000-000000000133', 'Sample folder');
insert into public.collection_cards (collection_id, discover_card_id)
values ('00000000-0000-4000-8000-000000000133', 'sample-curious-learner/retrieval-practice');
insert into public.practice_answers (id, practice_card_id, practice_card_version, discover_card_id, result, answered_at)
values ('00000000-0000-4000-8000-000000000134', 'sample-curious-learner/recall-flash', 1,
        'sample-curious-learner/retrieval-practice', 'good', now());
insert into public.content_requests (kind, message) values ('problem', 'Sample report');

do $$ declare data jsonb; t text; r jsonb; begin
  data := public.export_my_data();
  perform pg_temp.expect((select count(*) from jsonb_object_keys(data)) = 11, 'all 11 personal tables exported');
  foreach t in array array['profiles','devices','user_topics','user_sources','likes','saved_for_later',
    'seen_cards','practice_answers','collections','collection_cards','content_requests'] loop
    perform pg_temp.expect(jsonb_array_length(data->t) > 0, t || ' exported');
    for r in select * from jsonb_array_elements(data->t) loop
      perform pg_temp.expect(r->>'user_id' = auth.uid()::text, t || ' contains only own rows');
    end loop;
  end loop;
  perform public.delete_my_data();
  data := public.export_my_data();
  foreach t in array array['user_topics','user_sources','likes','saved_for_later','seen_cards',
    'practice_answers','collections','collection_cards','content_requests'] loop
    perform pg_temp.expect(data->t = '[]'::jsonb, t || ' cleared');
  end loop;
  perform pg_temp.expect((select weekly_goal_days is null and discover_filter = 'mix' and revision > 1
    from public.profiles), 'profile preserved and reset');
  perform pg_temp.expect((select count(*) = 2 and bool_and(reminder_time is null and not high_contrast
    and theme_mode = 'system' and offline_mode = 'standard' and revision > 1) from public.devices), 'all devices reset');
  perform public.delete_my_data();
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000013b","role":"authenticated"}', true);
select pg_temp.expect((select count(*) = 1 from public.likes), 'other person keeps Likes');
select pg_temp.expect((select weekly_goal_days = 7 from public.profiles), 'other person keeps settings');
reset role;
select pg_temp.expect(exists(select 1 from auth.users where id = '00000000-0000-4000-8000-00000000013a'), 'account preserved');
select pg_temp.expect(exists(select 1 from public.discover_cards where id = 'sample-curious-learner/retrieval-practice'), 'content preserved');
select pg_temp.expect(not has_function_privilege('anon', 'public.export_my_data()', 'execute'), 'anon cannot export');
select pg_temp.expect(not has_function_privilege('anon', 'public.delete_my_data()', 'execute'), 'anon cannot delete');
set local role authenticated;
select set_config('request.jwt.claims', '{}', true);
do $$ begin
  perform public.delete_my_data();
  raise exception 'FAILED: missing identity accepted';
exception when insufficient_privilege then null; end $$;
rollback;

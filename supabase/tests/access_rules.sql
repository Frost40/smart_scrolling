-- Access rule tests (docs/DATABASE.md, "Access"). Everything runs inside one transaction that is rolled back.
-- Run: python supabase/run_sql.py supabase/tests/access_rules.sql
-- Passes when the last line prints "access rules: all passed"; any failure stops with "FAILED: ...".
begin;

-- Two people, A and B, made only for this test.
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'a@access-test.invalid', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'b@access-test.invalid', 'authenticated', 'authenticated');

insert into public.topics (id, name) values ('access-test-topic', 'Access test');
insert into public.sources (id, kind, title, status) values
  ('access-test-pub', 'book', 'Published', 'published'),
  ('access-test-draft', 'book', 'Draft', 'draft');
insert into public.book_details (source_id) values ('access-test-pub'), ('access-test-draft');
insert into public.source_topics values ('access-test-pub', 'access-test-topic'), ('access-test-draft', 'access-test-topic');
insert into public.discover_cards (id, source_id, format, title, front, status) values
  ('access-test-pub/shown', 'access-test-pub', 'concept', 'Shown', 'f', 'published'),
  ('access-test-pub/hidden', 'access-test-pub', 'concept', 'Hidden', 'f', 'hidden'),
  ('access-test-draft/in-draft-source', 'access-test-draft', 'concept', 'In draft source', 'f', 'published');
insert into public.practice_cards (id, source_id, type, prompt, is_true, status) values
  ('access-test-pub/shown-test', 'access-test-pub', 'true_false', 'p', true, 'published'),
  ('access-test-pub/draft-test', 'access-test-pub', 'true_false', 'p', true, 'draft'),
  ('access-test-draft/test', 'access-test-draft', 'true_false', 'p', true, 'published');
insert into public.profiles (user_id) values
  ('00000000-0000-4000-8000-00000000000a'), ('00000000-0000-4000-8000-00000000000b');
insert into public.likes (user_id, discover_card_id) values ('00000000-0000-4000-8000-00000000000b', 'access-test-pub/shown');
insert into storage.objects (bucket_id, name) values
  ('media', 'access-test/image.webp'), ('source-files', 'access-test/original.pdf');

create function pg_temp.expect(ok boolean, what text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAILED: %', what; end if;
end $$;

-- 1. Not signed in (anon): every table refuses, and no file is visible.
set local role anon;
do $$
declare t text;
begin
  foreach t in array array[
    'topics', 'sources', 'book_details', 'paper_details', 'news_details', 'source_topics',
    'discover_cards', 'card_topics', 'related_cards', 'practice_cards', 'practice_links',
    'profiles', 'devices', 'user_topics', 'user_sources', 'likes', 'saved_for_later',
    'seen_cards', 'practice_answers', 'collections', 'collection_cards', 'content_requests']
  loop
    begin
      execute format('select 1 from public.%I limit 1', t);
      raise exception 'FAILED: anon can read %', t;
    exception when insufficient_privilege then null;
    end;
  end loop;
end $$;
select pg_temp.expect((select count(*) from storage.objects where name like 'access-test/%') = 0, 'anon sees no files');
reset role;

-- 2. Signed in as A: only published content.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}', true);
select pg_temp.expect((select array_agg(id) from public.sources where id like 'access-test%') = '{access-test-pub}', 'A reads only published sources');
select pg_temp.expect((select array_agg(source_id) from public.book_details where source_id like 'access-test%') = '{access-test-pub}', 'A reads details of published sources only');
select pg_temp.expect((select count(*) from public.source_topics where source_id like 'access-test%') = 1, 'A reads topic tags of published sources only');
select pg_temp.expect((select array_agg(id) from public.discover_cards where id like 'access-test%') = '{access-test-pub/shown}', 'A reads only published cards of published sources');
select pg_temp.expect((select array_agg(id) from public.practice_cards where id like 'access-test%') = '{access-test-pub/shown-test}', 'A reads only published tests of published sources');
select pg_temp.expect((select count(*) from public.topics where id = 'access-test-topic') = 1, 'A reads topics');

-- 3. A never reads or writes B's rows, and cannot write content.
select pg_temp.expect((select count(*) from public.profiles) = 1, 'A reads only their own profile');
select pg_temp.expect((select count(*) from public.likes) = 0, 'A cannot read B''s likes');
do $$
declare n int;
begin
  update public.profiles set weekly_goal_days = 3 where user_id = '00000000-0000-4000-8000-00000000000b';
  get diagnostics n = row_count;
  perform pg_temp.expect(n = 0, 'A cannot update B''s profile');
  delete from public.likes where user_id = '00000000-0000-4000-8000-00000000000b';
  get diagnostics n = row_count;
  perform pg_temp.expect(n = 0, 'A cannot delete B''s likes');
  begin
    insert into public.likes (user_id, discover_card_id) values ('00000000-0000-4000-8000-00000000000b', 'access-test-pub/shown');
    raise exception 'FAILED: A wrote a like for B';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.sources (id, kind, title) values ('access-test-by-a', 'other', 'x');
    raise exception 'FAILED: A wrote content';
  exception when insufficient_privilege then null;
  end;
  insert into public.likes (discover_card_id) values ('access-test-pub/shown');
  perform pg_temp.expect((select count(*) from public.likes) = 1, 'A can like a card for themself');
end $$;

-- 4. Files: signed-in people read media, never source-files.
select pg_temp.expect((select array_agg(bucket_id) from storage.objects where name like 'access-test/%') = '{media}', 'A reads media but not source-files');
reset role;

-- 5. Signed in as B: still only B's like (A's like stays A's).
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}', true);
select pg_temp.expect((select count(*) from public.likes) = 1, 'B reads only their own like');
reset role;

select 'access rules: all passed' as result;
rollback;

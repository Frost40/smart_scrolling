-- Discover feed and action tests (PRD D34, A3-5, D40; docs/DATABASE.md "Functions"). One transaction, rolled back.
-- Run: python supabase/run_sql.py supabase/tests/discover_feed.sql
-- Passes when the last line prints "discover feed: all passed"; any failure stops with "FAILED: ...".
begin;

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-8000-0000000000fa', 'feed@feed-test.invalid', 'authenticated', 'authenticated');
insert into public.profiles (user_id) values ('00000000-0000-4000-8000-0000000000fa');

insert into public.topics (id, name, parent_id) values
  ('feed-test-main', 'Main', null), ('feed-test-other', 'Other', null), ('feed-test-hidden', 'Hidden', null);
insert into public.topics (id, name, parent_id) values ('feed-test-sub', 'Sub', 'feed-test-main');

insert into public.sources (id, kind, title, status, created_at) values
  ('feed-test-a', 'book', 'A', 'published', '2026-01-07'),       -- sub-topic of the followed main area
  ('feed-test-b', 'book', 'B', 'published', '2026-01-06'),       -- followed main area
  ('feed-test-c', 'other', 'C', 'published', '2026-01-05'),      -- not followed; one card adds the main area
  ('feed-test-d', 'other', 'D', 'published', '2026-01-04'),      -- not followed, but the source is followed
  ('feed-test-news-new', 'news', 'N', 'published', '2026-01-03'), -- shown until today
  ('feed-test-news-old', 'news', 'O', 'published', '2026-01-02'), -- shown until yesterday
  ('feed-test-e', 'other', 'E', 'published', '2026-01-01'),      -- followed topic, hidden source
  ('feed-test-f', 'book', 'F', 'published', '2026-01-01'),       -- followed topic plus a hidden topic
  ('feed-test-draft', 'book', 'Draft', 'draft', '2026-01-08');   -- not published
insert into public.news_details (source_id, newspaper, show_until) values
  ('feed-test-news-new', 'Paper', current_date), ('feed-test-news-old', 'Paper', current_date - 1);
insert into public.source_topics values
  ('feed-test-a', 'feed-test-sub'), ('feed-test-b', 'feed-test-main'), ('feed-test-c', 'feed-test-other'),
  ('feed-test-d', 'feed-test-other'), ('feed-test-news-new', 'feed-test-main'), ('feed-test-news-old', 'feed-test-main'),
  ('feed-test-e', 'feed-test-main'), ('feed-test-f', 'feed-test-main'), ('feed-test-f', 'feed-test-hidden'),
  ('feed-test-draft', 'feed-test-main');
insert into public.discover_cards (id, source_id, format, title, front, position, level, language, status) values
  ('feed-test-a/a1', 'feed-test-a', 'concept', 't', 'f', 1, 'intro', 'en', 'published'),
  ('feed-test-a/a2', 'feed-test-a', 'concept', 't', 'f', 2, null, 'en', 'published'),
  ('feed-test-a/a3', 'feed-test-a', 'concept', 't', 'f', 3, null, 'it', 'published'),
  ('feed-test-a/a4', 'feed-test-a', 'concept', 't', 'f', 4, null, 'en', 'hidden'),
  ('feed-test-b/b1', 'feed-test-b', 'concept', 't', 'f', 1, null, 'en', 'published'),
  ('feed-test-b/b2', 'feed-test-b', 'concept', 't', 'f', 2, 'advanced', 'en', 'published'),
  ('feed-test-b/b3', 'feed-test-b', 'concept', 't', 'f', 3, null, 'en', 'published'),
  ('feed-test-b/b4', 'feed-test-b', 'concept', 't', 'f', 4, null, 'en', 'published'),
  ('feed-test-c/c1', 'feed-test-c', 'concept', 't', 'f', 1, null, 'en', 'published'),
  ('feed-test-c/c2', 'feed-test-c', 'concept', 't', 'f', 2, null, 'en', 'published'),
  ('feed-test-d/d1', 'feed-test-d', 'concept', 't', 'f', 1, null, 'en', 'published'),
  ('feed-test-news-new/n1', 'feed-test-news-new', 'news', 't', 'f', 1, null, 'en', 'published'),
  ('feed-test-news-old/o1', 'feed-test-news-old', 'news', 't', 'f', 1, null, 'en', 'published'),
  ('feed-test-e/e1', 'feed-test-e', 'concept', 't', 'f', 1, null, 'en', 'published'),
  ('feed-test-f/f1', 'feed-test-f', 'concept', 't', 'f', 1, null, 'en', 'published'),
  ('feed-test-draft/x1', 'feed-test-draft', 'concept', 't', 'f', 1, null, 'en', 'published');
insert into public.card_topics values ('feed-test-c/c1', 'feed-test-main');
insert into public.practice_cards (id, source_id, type, prompt, is_true, status) values
  ('feed-test-a/t1', 'feed-test-a', 'true_false', 'p', true, 'published');
insert into public.practice_links values ('feed-test-a/a1', 'feed-test-a/t1');

insert into public.user_topics (user_id, topic_id, choice) values
  ('00000000-0000-4000-8000-0000000000fa', 'feed-test-main', 'follow'),
  ('00000000-0000-4000-8000-0000000000fa', 'feed-test-hidden', 'hide');
insert into public.user_sources (user_id, source_id, choice) values
  ('00000000-0000-4000-8000-0000000000fa', 'feed-test-d', 'follow'),
  ('00000000-0000-4000-8000-0000000000fa', 'feed-test-e', 'hide');
insert into public.seen_cards (user_id, discover_card_id) values ('00000000-0000-4000-8000-0000000000fa', 'feed-test-b/b3');

create function pg_temp.expect(ok boolean, what text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAILED: %', what; end if;
end $$;

-- The test cards in feed order, for this person.
create function pg_temp.feed(p_limit int default 1000, p_exclude text[] default '{feed-test-b/b4}') returns text
language sql as $$
  select coalesce(string_agg(f.id, ','), '') from (
    select id from public.discover_feed(p_limit, p_exclude) where id like 'feed-test%'
  ) f
$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-0000000000fa", "role": "authenticated"}', true);

-- D34: followed main area (and its sub-topic), extra card topic, followed source, news until today;
-- minus drafts, hidden cards, other languages, seen, excluded, hidden source, hidden topic, expired news.
-- A3-5: sources take turns, newest source first.
select pg_temp.expect(pg_temp.feed() = 'feed-test-a/a1,feed-test-b/b1,feed-test-c/c1,feed-test-d/d1,feed-test-news-new/n1,feed-test-a/a2,feed-test-b/b2,feed-test-b/b3',
  'feed rules and turn order: ' || pg_temp.feed());
select pg_temp.expect(position('feed-test-a/a1' in pg_temp.feed()) > 0, 'following a main area includes its sub-topics');
select pg_temp.expect(position('feed-test-c/c1' in pg_temp.feed()) > 0 and position('feed-test-c/c2' in pg_temp.feed()) = 0,
  'an extra card topic counts; the rest of that source does not');
select pg_temp.expect(position('feed-test-d/d1' in pg_temp.feed()) > 0, 'a followed source shows cards outside your topics');
select pg_temp.expect(position('feed-test-e/' in pg_temp.feed()) = 0, 'a hidden source is left out');
select pg_temp.expect(position('feed-test-f/' in pg_temp.feed()) = 0, 'a hidden topic beats a followed one');
select pg_temp.expect(position('feed-test-a/a3' in pg_temp.feed()) = 0, 'other languages are left out');
select pg_temp.expect(position('feed-test-news-old/' in pg_temp.feed()) = 0, 'news past show_until is left out');
select pg_temp.expect(pg_temp.feed() like '%feed-test-b/b2,feed-test-b/b3', 'a seen card comes back after the new ones (D46)');
select pg_temp.expect(position('feed-test-b/b4' in pg_temp.feed()) = 0, 'p_exclude ids are left out');
select pg_temp.expect(position('feed-test-b/b4' in pg_temp.feed(1000, '{}')) > 0, 'without p_exclude the card comes back');
select pg_temp.expect(position('feed-test-draft/' in pg_temp.feed()) = 0 and position('feed-test-a/a4' in pg_temp.feed()) = 0,
  'only published cards of published sources');
select pg_temp.expect((select count(*) from public.discover_feed(2, '{}')) = 2, 'p_limit caps the batch');

-- A3-5: the preferred level comes first.
update public.profiles set preferred_level = 'advanced';
select pg_temp.expect(pg_temp.feed() = 'feed-test-b/b2,feed-test-a/a1,feed-test-b/b1,feed-test-c/c1,feed-test-d/d1,feed-test-news-new/n1,feed-test-a/a2,feed-test-b/b3',
  'preferred level first: ' || pg_temp.feed());
update public.profiles set preferred_level = null;

-- The format selector (profiles.discover_filter).
update public.profiles set discover_filter = 'news';
select pg_temp.expect(pg_temp.feed() = 'feed-test-news-new/n1', 'one format only: ' || pg_temp.feed());
update public.profiles set discover_filter = 'mix';

-- Following nothing: every published card, still minus hidden and expired; seen ones last.
delete from public.user_topics where choice = 'follow';
delete from public.user_sources where choice = 'follow';
-- Live sample cards also count here, so the seen card's place among the test cards varies (one every 10).
select pg_temp.expect(replace(pg_temp.feed(), ',feed-test-b/b3', '') = 'feed-test-a/a1,feed-test-b/b1,feed-test-c/c1,feed-test-d/d1,feed-test-news-new/n1,feed-test-a/a2,feed-test-b/b2,feed-test-c/c2'
    and position('feed-test-b/b3' in pg_temp.feed()) > 0,
  'following nothing shows all published cards: ' || pg_temp.feed());

-- For later: adds the row and marks the card seen.
select pg_temp.expect((select discover_card_id from public.save_for_later('feed-test-b/b1')) = 'feed-test-b/b1', 'save_for_later returns the row');
select pg_temp.expect(exists (select 1 from public.seen_cards where discover_card_id = 'feed-test-b/b1'), 'For later marks seen');
select pg_temp.expect(position('feed-test-b/b1' in pg_temp.feed()) = 0, 'a saved card leaves the feed');

-- Like: out of For later, seen, one more_practice to-do when no test is linked; a second Like keeps the timetable.
select pg_temp.expect((select review_level from public.like_card('feed-test-b/b1')) = 0, 'like_card returns the like');
select pg_temp.expect(not exists (select 1 from public.saved_for_later where discover_card_id = 'feed-test-b/b1'), 'Like takes the card out of For later');
select pg_temp.expect((select next_review_at > now() + interval '23 hours' from public.likes where discover_card_id = 'feed-test-b/b1'), 'first test 1 day later');
update public.likes set review_level = 2 where discover_card_id = 'feed-test-b/b1';
select public.like_card('feed-test-b/b1');
select pg_temp.expect((select review_level from public.likes where discover_card_id = 'feed-test-b/b1') = 2, 'a repeated Like keeps the timetable');
select pg_temp.expect((select count(*) from public.content_requests where kind = 'more_practice' and discover_card_id = 'feed-test-b/b1') = 1,
  'one more_practice to-do for a card with no test');
select public.like_card('feed-test-a/a1');
select pg_temp.expect(not exists (select 1 from public.content_requests where discover_card_id = 'feed-test-a/a1'), 'no to-do when a test is linked');
select pg_temp.expect(exists (select 1 from public.seen_cards where discover_card_id = 'feed-test-a/a1'), 'Like marks seen');
do $$
begin
  perform public.like_card('feed-test-draft/x1');
  raise exception 'FAILED: liked a card of a draft source';
exception when no_data_found then null;
end $$;

-- Undo a Like: the like goes; with p_saved_at the card is back in For later at that time.
select public.undo_like('feed-test-b/b1', '2026-01-01 10:00+00');
select pg_temp.expect(not exists (select 1 from public.likes where discover_card_id = 'feed-test-b/b1'), 'undo_like deletes the like');
select pg_temp.expect((select saved_at from public.saved_for_later where discover_card_id = 'feed-test-b/b1') = '2026-01-01 10:00+00',
  'undo_like restores For later with its time');
select public.undo_like('feed-test-a/a1');
select pg_temp.expect(not exists (select 1 from public.saved_for_later where discover_card_id = 'feed-test-a/a1'), 'undo_like without p_saved_at saves nothing');
reset role;

set local role authenticated;
-- Like affinity beats source recency, but not preferred level.
insert into public.likes (discover_card_id) values ('feed-test-c/c2');
select pg_temp.expect((select id from public.discover_feed(1, '{}')) = 'feed-test-c/c1', 'liked topics rank first');
update public.profiles set preferred_level = 'advanced';
select pg_temp.expect((select id from public.discover_feed(1000, '{}') where id like 'feed-test%' limit 1) = 'feed-test-b/b2', 'level beats affinity');
select pg_temp.expect(exists (select 1 from public.search_sources('a', null) where source->>'id' = 'feed-test-a'), 'case-insensitive title');
select pg_temp.expect(exists (select 1 from public.search_sources('sUb', null) where source->>'id' = 'feed-test-a'), 'topic-name search');
select pg_temp.expect(exists (select 1 from public.search_sources('', 'feed-test-main') where source->>'id' = 'feed-test-a'), 'browse main includes sub-topic sources');
select pg_temp.expect(not exists (select 1 from public.search_sources('', null) where source->>'id' = 'feed-test-draft'), 'search excludes drafts');
select pg_temp.expect((select card_count from public.search_sources('', null) where source->>'id' = 'feed-test-a') = 3, 'count only published cards');
select pg_temp.expect(not exists (select 1 from public.search_sources('%', null) where source->>'id' like 'feed-test%'), 'search treats wildcard literally');
reset role;
update public.sources set authors = '{CaseSensitive Author}' where id = 'feed-test-a';
set local role authenticated;
select pg_temp.expect(exists (select 1 from public.search_sources('sensitive author', null) where source->>'id' = 'feed-test-a'), 'case-insensitive authors');
reset role;

select pg_temp.expect(not has_function_privilege('anon', 'public.search_sources(text,text)', 'execute'), 'anon cannot search');
select pg_temp.expect(has_function_privilege('authenticated', 'public.search_sources(text,text)', 'execute'), 'signed-in search is allowed');
-- D46: one seen card after every 10 new ones; liked and saved cards never come back.
insert into public.discover_cards (id, source_id, format, title, front, position, language, status)
  select 'feed-test-d/g' || n, 'feed-test-d', 'concept', 't', 'f', 10 + n, 'en', 'published' from generate_series(1, 12) n;
set local role authenticated;
delete from public.seen_cards;
delete from public.likes;
delete from public.saved_for_later;
delete from public.user_topics;
delete from public.user_sources;
insert into public.user_sources (source_id, choice) values ('feed-test-d', 'follow');
insert into public.seen_cards (discover_card_id, last_seen_at) values
  ('feed-test-d/d1', now() - interval '1 day'), ('feed-test-d/g12', now() - interval '2 days');
insert into public.likes (discover_card_id) values ('feed-test-d/g11');
select pg_temp.expect(pg_temp.feed(1000, '{}')
  = 'feed-test-d/g1,feed-test-d/g2,feed-test-d/g3,feed-test-d/g4,feed-test-d/g5,feed-test-d/g6,feed-test-d/g7,feed-test-d/g8,feed-test-d/g9,feed-test-d/g10,feed-test-d/g12,feed-test-d/d1',
  'new first, then seen longest ago first; liked never: ' || pg_temp.feed(1000, '{}'));
reset role;

select 'discover feed: all passed' as result;
rollback;

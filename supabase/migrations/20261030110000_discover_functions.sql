-- Discover: the feed and the Like / For later actions (docs/DATABASE.md, "Functions"; PRD D34, A3-5, D40).
-- security invoker: the access rules still apply, so only published content and the person's own rows are seen.

-- The feed (D34): published cards from followed topics (a main area includes its sub-topics; source
-- topics plus extra card topics) and followed sources; minus hidden topics and sources, other languages,
-- news past show_until, seen cards and p_exclude. Following nothing at all shows every published card.
-- The profile's discover_filter picks one format or the mix.
-- Order (A3-5): the preferred level first, then the sources take turns (first card of each source, then
-- the second, …), newest source first.
create function public.discover_feed(p_limit int default 20, p_exclude text[] default '{}')
returns setof public.discover_cards
language sql stable security invoker set search_path = '' as $$
  with me as (
    select coalesce(p.languages, '{en}') as languages, p.preferred_level, coalesce(p.discover_filter, 'mix') as filter
    from (select 1) one left join public.profiles p on p.user_id = (select auth.uid())
  ),
  -- Each card's topics, each with its main area too, so a choice on a main area covers its sub-topics.
  card_topic as (
    select c.id as card_id, t.id as topic_id, t.parent_id
    from public.discover_cards c
    join public.source_topics st on st.source_id = c.source_id
    join public.topics t on t.id = st.topic_id
    union
    select ct.discover_card_id, t.id, t.parent_id
    from public.card_topics ct
    join public.topics t on t.id = ct.topic_id
  ),
  choice as (
    select ct.card_id, ut.choice
    from card_topic ct
    join public.user_topics ut on ut.user_id = (select auth.uid())
      and ut.topic_id in (ct.topic_id, ct.parent_id)
  ),
  follows_any as (
    select exists (select 1 from public.user_topics where user_id = (select auth.uid()) and choice = 'follow')
        or exists (select 1 from public.user_sources where user_id = (select auth.uid()) and choice = 'follow') as yes
  ),
  eligible as (
    select c.id, c.source_id, c.position, s.created_at as source_created_at,
           (c.level is not distinct from me.preferred_level and me.preferred_level is not null) as level_match
    from public.discover_cards c
    join public.sources s on s.id = c.source_id
    left join public.news_details n on n.source_id = s.id
    left join public.user_sources us on us.user_id = (select auth.uid()) and us.source_id = s.id
    cross join me
    cross join follows_any
    where c.status = 'published' and s.status = 'published'
      and c.language = any (me.languages)
      and (me.filter = 'mix' or c.format = me.filter)
      and (n.show_until is null or n.show_until >= current_date)
      and us.choice is distinct from 'hide'
      and not exists (select 1 from choice h where h.card_id = c.id and h.choice = 'hide')
      and not exists (select 1 from public.seen_cards sc
                      where sc.user_id = (select auth.uid()) and sc.discover_card_id = c.id)
      and c.id <> all (coalesce(p_exclude, '{}'))
      and (not follows_any.yes
           or us.choice = 'follow'
           or exists (select 1 from choice f where f.card_id = c.id and f.choice = 'follow'))
  ),
  -- turn 1 = the first eligible card of its source, turn 2 = the second, …
  ranked as (
    select el.*, row_number() over (partition by el.level_match, el.source_id
                                    order by el.position nulls last, el.id) as turn
    from eligible el
  )
  select c.*
  from ranked r
  join public.discover_cards c on c.id = r.id
  order by r.level_match desc, r.turn, r.source_created_at desc, r.source_id
  limit greatest(coalesce(p_limit, 20), 0);
$$;

-- Like (D40): keeps an existing timetable, takes the card out of For later, marks it seen, and adds one
-- more_practice to-do when the card has no published linked test.
create function public.like_card(p_card_id text) returns public.likes
language plpgsql security invoker set search_path = '' as $$
declare
  result public.likes;
begin
  if not exists (select 1 from public.discover_cards where id = p_card_id) then
    raise exception 'Card % is not available', p_card_id using errcode = 'P0002';
  end if;
  insert into public.likes (discover_card_id) values (p_card_id) on conflict do nothing;
  delete from public.saved_for_later where user_id = (select auth.uid()) and discover_card_id = p_card_id;
  insert into public.seen_cards (discover_card_id) values (p_card_id)
    on conflict (user_id, discover_card_id) do update set last_seen_at = now();
  if not exists (select 1 from public.practice_links l
                 join public.practice_cards p on p.id = l.practice_card_id
                 where l.discover_card_id = p_card_id and p.status = 'published') then
    insert into public.content_requests (kind, discover_card_id, source_id)
    select 'more_practice', c.id, c.source_id from public.discover_cards c where c.id = p_card_id
    on conflict (user_id, discover_card_id) where kind = 'more_practice' and status = 'open' do nothing;
  end if;
  select * into result from public.likes where user_id = (select auth.uid()) and discover_card_id = p_card_id;
  return result;
end $$;

-- For later: adds or refreshes the saved row and marks the card seen.
create function public.save_for_later(p_card_id text) returns public.saved_for_later
language plpgsql security invoker set search_path = '' as $$
declare
  result public.saved_for_later;
begin
  if not exists (select 1 from public.discover_cards where id = p_card_id) then
    raise exception 'Card % is not available', p_card_id using errcode = 'P0002';
  end if;
  insert into public.saved_for_later (discover_card_id) values (p_card_id)
    on conflict (user_id, discover_card_id) do update set saved_at = now()
    returning * into result;
  insert into public.seen_cards (discover_card_id) values (p_card_id)
    on conflict (user_id, discover_card_id) do update set last_seen_at = now();
  return result;
end $$;

-- Undo a Like: deletes it (past answers stay). With p_saved_at, the card goes back to For later with
-- that time, because the Like had taken it out.
create function public.undo_like(p_card_id text, p_saved_at timestamptz default null) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  delete from public.likes where user_id = (select auth.uid()) and discover_card_id = p_card_id;
  if p_saved_at is not null then
    insert into public.saved_for_later (discover_card_id, saved_at) values (p_card_id, p_saved_at)
      on conflict (user_id, discover_card_id) do update set saved_at = excluded.saved_at;
  end if;
end $$;

revoke execute on function public.discover_feed(int, text[]), public.like_card(text),
  public.save_for_later(text), public.undo_like(text, timestamptz) from public, anon;
grant execute on function public.discover_feed(int, text[]), public.like_card(text),
  public.save_for_later(text), public.undo_like(text, timestamptz) to authenticated;

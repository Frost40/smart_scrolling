-- Discover: seen cards may come back (owner decision D46; changes D10 and D34).
-- Same rules as before (docs/DATABASE.md, "Functions"), except:
--   * seen cards stay eligible: new cards first in the old order (A3-5), then one seen card after every
--     10 new ones, the one seen longest ago first; when new cards run out, only seen cards remain;
--   * liked and For later cards never come back (they live in the Library).
-- p_exclude still leaves out every card already loaded on screen.
create or replace function public.discover_feed(p_limit int default 20, p_exclude text[] default '{}')
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
  affinity as (
    select ct.topic_id, count(distinct l.discover_card_id) as weight
    from card_topic ct join public.likes l on l.discover_card_id = ct.card_id
    where l.user_id = (select auth.uid())
    group by ct.topic_id
  ),
  eligible as (
    select c.id, c.source_id, c.position, s.created_at as source_created_at, sc.last_seen_at,
           coalesce((select sum(a.weight) from card_topic ct
                     join affinity a on a.topic_id = ct.topic_id where ct.card_id = c.id), 0) as affinity,
           (c.level is not distinct from me.preferred_level and me.preferred_level is not null) as level_match
    from public.discover_cards c
    join public.sources s on s.id = c.source_id
    left join public.news_details n on n.source_id = s.id
    left join public.user_sources us on us.user_id = (select auth.uid()) and us.source_id = s.id
    left join public.seen_cards sc on sc.user_id = (select auth.uid()) and sc.discover_card_id = c.id
    cross join me
    cross join follows_any
    where c.status = 'published' and s.status = 'published'
      and c.language = any (me.languages)
      and (me.filter = 'mix' or c.format = me.filter)
      and (n.show_until is null or n.show_until >= current_date)
      and us.choice is distinct from 'hide'
      and not exists (select 1 from choice h where h.card_id = c.id and h.choice = 'hide')
      and not exists (select 1 from public.likes l
                      where l.user_id = (select auth.uid()) and l.discover_card_id = c.id)
      and not exists (select 1 from public.saved_for_later sl
                      where sl.user_id = (select auth.uid()) and sl.discover_card_id = c.id)
      and c.id <> all (coalesce(p_exclude, '{}'))
      and (not follows_any.yes
           or us.choice = 'follow'
           or exists (select 1 from choice f where f.card_id = c.id and f.choice = 'follow'))
  ),
  -- turn 1 = the first eligible card of its source, turn 2 = the second, …
  ranked as (
    select el.*, row_number() over (partition by el.last_seen_at is null, el.level_match, el.affinity, el.source_id
                                    order by el.position nulls last, el.id) as turn
    from eligible el
  ),
  -- New cards get places 1, 2, 3, …; the n-th seen card (seen longest ago first) gets place 10n + 0.5,
  -- so one comes back after every 10 new cards, and the rest follow once new cards run out.
  placed as (
    select r.id,
           case when r.last_seen_at is null
             then row_number() over (partition by r.last_seen_at is null
                                     order by r.level_match desc, r.affinity desc, r.turn, r.source_created_at desc, r.source_id)
             else 10 * row_number() over (partition by r.last_seen_at is null order by r.last_seen_at, r.id) + 0.5
           end as place
    from ranked r
  )
  select c.*
  from placed p
  join public.discover_cards c on c.id = p.id
  order by p.place
  limit greatest(coalesce(p_limit, 20), 0);
$$;

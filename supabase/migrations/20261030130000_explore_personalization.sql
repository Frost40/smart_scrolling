-- Discover: the feed and the Like / For later actions (docs/DATABASE.md, "Functions"; PRD D34, A3-5, D40).
-- security invoker: the access rules still apply, so only published content and the person's own rows are seen.

-- The feed (D34): published cards from followed topics (a main area includes its sub-topics; source
-- topics plus extra card topics) and followed sources; minus hidden topics and sources, other languages,
-- news past show_until, seen cards and p_exclude. Following nothing at all shows every published card.
-- The profile's discover_filter picks one format or the mix.
-- Order (A3-5): the preferred level first, then the sources take turns (first card of each source, then
-- the second, …), newest source first.
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
    select c.id, c.source_id, c.position, s.created_at as source_created_at,
           coalesce((select sum(a.weight) from card_topic ct
                     join affinity a on a.topic_id = ct.topic_id where ct.card_id = c.id), 0) as affinity,
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
    select el.*, row_number() over (partition by el.level_match, el.affinity, el.source_id
                                    order by el.position nulls last, el.id) as turn
    from eligible el
  )
  select c.*
  from ranked r
  join public.discover_cards c on c.id = r.id
  order by r.level_match desc, r.affinity desc, r.turn, r.source_created_at desc, r.source_id
  limit greatest(coalesce(p_limit, 20), 0);
$$;

-- Literal, case-insensitive title, author or topic search; no raw filter interpolation.
create function public.search_sources(p_text text default '', p_topic text default null)
returns table (source jsonb, card_count bigint)
language sql stable security invoker set search_path = '' as $$
  select to_jsonb(s), (select count(*) from public.discover_cards c where c.source_id = s.id)
  from public.sources s
  where s.status = 'published'
    and (p_topic is null or exists (
      select 1 from public.source_topics st join public.topics t on t.id = st.topic_id
      where st.source_id = s.id and p_topic in (t.id, t.parent_id)))
    and (coalesce(p_text, '') = ''
      or strpos(lower(s.title), lower(p_text)) > 0
      or exists (select 1 from unnest(s.authors) a where strpos(lower(a), lower(p_text)) > 0)
      or exists (select 1 from public.source_topics st join public.topics t on t.id = st.topic_id
        left join public.topics parent on parent.id = t.parent_id
        where st.source_id = s.id and (strpos(lower(t.name), lower(p_text)) > 0
          or strpos(lower(parent.name), lower(p_text)) > 0)))
  order by s.title, s.id;
$$;
revoke execute on function public.search_sources(text, text) from public, anon;
grant execute on function public.search_sources(text, text) to authenticated;

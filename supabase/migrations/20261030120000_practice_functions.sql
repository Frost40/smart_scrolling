-- D32: unanswered first, then the test whose most recent answer is oldest.
create function public.pick_test(p_discover_card_id text, p_filter text default 'mix')
returns public.practice_cards language sql stable security invoker set search_path = '' as $$
  select p.* from public.practice_links link
  join public.practice_cards p on p.id = link.practice_card_id
  join public.discover_cards d on d.id = link.discover_card_id
  join public.likes l on l.discover_card_id = d.id and l.user_id = auth.uid()
  where d.id = p_discover_card_id and not l.reviews_paused
    and (p_filter = 'mix' or p.type = p_filter)
  order by (select max(a.answered_at) from public.practice_answers a
    where a.user_id = auth.uid() and a.practice_card_id = p.id) asc nulls first, p.id
  limit 1;
$$;

-- The phone computes the timetable. This transaction stores each answer once
-- and serializes updates of the same Like so the later answered_at wins.
create function public.record_answer(
  p_id uuid, p_practice_card_id text, p_practice_card_version int,
  p_discover_card_id text, p_answer jsonb, p_result text,
  p_answered_at timestamptz, p_review_level smallint, p_next_review_at timestamptz
) returns public.likes language plpgsql security invoker set search_path = '' as $$
declare
  v_like public.likes;
  v_inserted uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in to answer' using errcode = '42501';
  end if;

  select * into v_like from public.likes
    where user_id = auth.uid() and discover_card_id = p_discover_card_id for update;

  -- Retries cannot change the original answer or reapply a supplied schedule.
  if exists (select 1 from public.practice_answers where id = p_id and user_id = auth.uid()) then
    return v_like;
  end if;
  if v_like.user_id is null or not exists (
    select 1 from public.practice_links link
    join public.practice_cards p on p.id = link.practice_card_id
    join public.discover_cards d on d.id = link.discover_card_id
    where d.id = p_discover_card_id and p.id = p_practice_card_id
      and p_practice_card_version between 1 and p.version
  ) then
    raise exception 'Liked card or linked test unavailable' using errcode = 'P0002';
  end if;
  if p_review_level is null or p_review_level not between 0 and 4
    or p_answered_at is null or not isfinite(p_answered_at)
    or p_next_review_at is null or not isfinite(p_next_review_at)
    or p_next_review_at <= p_answered_at then
    raise exception 'Invalid review timetable' using errcode = '22023';
  end if;

  insert into public.practice_answers (id, user_id, practice_card_id, practice_card_version,
    discover_card_id, answer, result, answered_at)
  values (p_id, auth.uid(), p_practice_card_id, p_practice_card_version,
    p_discover_card_id, p_answer, p_result, p_answered_at)
  on conflict (id) do nothing returning id into v_inserted;
  if v_inserted is null then
    raise exception 'Answer id unavailable' using errcode = '42501';
  end if;

  if v_like.last_reviewed_at is null or p_answered_at > v_like.last_reviewed_at then
    update public.likes set review_level = p_review_level, next_review_at = p_next_review_at,
      last_reviewed_at = p_answered_at
    where user_id = auth.uid() and discover_card_id = p_discover_card_id
    returning * into v_like;
  end if;

  if not exists (
    select 1 from public.practice_links link
    join public.practice_cards p on p.id = link.practice_card_id
    where link.discover_card_id = p_discover_card_id and not exists (
      select 1 from public.practice_answers a
      where a.user_id = auth.uid() and a.practice_card_id = p.id
    )
  ) then
    insert into public.content_requests (user_id, kind, discover_card_id, source_id)
    select auth.uid(), 'more_practice', d.id, d.source_id
    from public.discover_cards d where d.id = p_discover_card_id
    on conflict (user_id, discover_card_id) where kind = 'more_practice' and status = 'open' do nothing;
  end if;
  return v_like;
end;
$$;

create index practice_answers_test_history on public.practice_answers
  (user_id, practice_card_id, answered_at desc);

revoke execute on function public.pick_test(text, text) from public, anon;
revoke execute on function public.record_answer(uuid, text, int, text, jsonb, text, timestamptz, smallint, timestamptz) from public, anon;
grant execute on function public.pick_test(text, text) to authenticated;
grant execute on function public.record_answer(uuid, text, int, text, jsonb, text, timestamptz, smallint, timestamptz) to authenticated;

-- Ticket 06 has controls for these two types. Ticket 10 extends Mix.
-- Keep the previous migration immutable; explicit filters still support all types.
create or replace function public.pick_test(p_discover_card_id text, p_filter text default 'mix')
returns public.practice_cards language sql stable security invoker set search_path = '' as $$
  select p.* from public.practice_links link
  join public.practice_cards p on p.id = link.practice_card_id
  join public.discover_cards d on d.id = link.discover_card_id
  join public.likes l on l.discover_card_id = d.id and l.user_id = auth.uid()
  where d.id = p_discover_card_id and not l.reviews_paused
    and ((p_filter = 'mix' and p.type in ('flashcard', 'multiple_choice')) or p.type = p_filter)
  order by (select max(a.answered_at) from public.practice_answers a
    where a.user_id = auth.uid() and a.practice_card_id = p.id) asc nulls first, p.id
  limit 1;
$$;

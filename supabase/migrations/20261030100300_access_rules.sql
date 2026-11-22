-- Row level security on all 22 tables (docs/DATABASE.md, "Access").
-- Content: signed-in people read what is published; only the upload tool (service-role key) writes.
-- Activity: each person reads and writes only their own rows. The anon role gets nothing.

do $$
declare t text;
begin
  foreach t in array array[
    'topics', 'sources', 'book_details', 'paper_details', 'news_details', 'source_topics',
    'discover_cards', 'card_topics', 'related_cards', 'practice_cards', 'practice_links',
    'profiles', 'devices', 'user_topics', 'user_sources', 'likes', 'saved_for_later',
    'seen_cards', 'practice_answers', 'collections', 'collection_cards', 'content_requests']
  loop
    execute format('alter table public.%I enable row level security', t);
    -- No policy names anon, but revoking too means a forgotten policy can never expose a table.
    execute format('revoke all on public.%I from anon', t);
  end loop;

  foreach t in array array['book_details', 'paper_details', 'news_details', 'source_topics'] loop
    execute format(
      'create policy "read published" on public.%I for select to authenticated
         using (exists (select 1 from public.sources s where s.id = source_id and s.status = ''published''))', t);
  end loop;

  foreach t in array array['topics', 'card_topics', 'related_cards', 'practice_links'] loop
    execute format('create policy "read all" on public.%I for select to authenticated using (true)', t);
  end loop;

  foreach t in array array[
    'profiles', 'devices', 'user_topics', 'user_sources', 'likes', 'saved_for_later',
    'seen_cards', 'practice_answers', 'collections', 'collection_cards', 'content_requests']
  loop
    execute format(
      'create policy "own rows" on public.%I for all to authenticated
         using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
  end loop;
end $$;

create policy "read published" on public.sources for select to authenticated
  using (status = 'published');
create policy "read published" on public.discover_cards for select to authenticated
  using (status = 'published'
         and exists (select 1 from public.sources s where s.id = source_id and s.status = 'published'));
create policy "read published" on public.practice_cards for select to authenticated
  using (status = 'published'
         and exists (select 1 from public.sources s where s.id = source_id and s.status = 'published'));

-- The two private buckets (docs/DATABASE.md, "Storage"), 50 MB per file.
insert into storage.buckets (id, name, public, file_size_limit)
values ('source-files', 'source-files', false, 52428800),
       ('media', 'media', false, 52428800)
on conflict (id) do nothing;

-- The app reads media while signed in, through signed links (A3-7).
create policy "signed-in users read media" on storage.objects for select to authenticated
  using (bucket_id = 'media');
-- source-files has no policy: only the service-role key (the upload tool) can read or write it.

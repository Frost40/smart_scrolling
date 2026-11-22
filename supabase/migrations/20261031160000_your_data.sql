-- Personal data only: caller identity is never supplied by the app.
create function public.export_my_data() returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'Sign in first'; end if;
  return jsonb_build_object(
    'profiles', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.profiles r where user_id = (select auth.uid())),
    'devices', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.devices r where user_id = (select auth.uid())),
    'user_topics', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.user_topics r where user_id = (select auth.uid())),
    'user_sources', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.user_sources r where user_id = (select auth.uid())),
    'likes', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.likes r where user_id = (select auth.uid())),
    'saved_for_later', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.saved_for_later r where user_id = (select auth.uid())),
    'seen_cards', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.seen_cards r where user_id = (select auth.uid())),
    'practice_answers', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.practice_answers r where user_id = (select auth.uid())),
    'collections', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.collections r where user_id = (select auth.uid())),
    'collection_cards', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.collection_cards r where user_id = (select auth.uid())),
    'content_requests', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.content_requests r where user_id = (select auth.uid()))
  );
end $$;

create function public.delete_my_data() returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'Sign in first'; end if;
  delete from public.content_requests where user_id = (select auth.uid());
  delete from public.collection_cards where user_id = (select auth.uid());
  delete from public.collections where user_id = (select auth.uid());
  delete from public.practice_answers where user_id = (select auth.uid());
  delete from public.seen_cards where user_id = (select auth.uid());
  delete from public.saved_for_later where user_id = (select auth.uid());
  delete from public.likes where user_id = (select auth.uid());
  delete from public.user_sources where user_id = (select auth.uid());
  delete from public.user_topics where user_id = (select auth.uid());
  update public.profiles set languages = default, preferred_level = default,
    discover_filter = default, practice_filter = default, weekly_goal_days = default
    where user_id = (select auth.uid());
  update public.devices set offline_mode = default, download_on_mobile_data = default,
    theme_mode = default, reduce_motion = default, high_contrast = default,
    text_scale = default, reminder_time = default, last_sync_at = default
    where user_id = (select auth.uid());
end $$;

revoke all on function public.export_my_data(), public.delete_my_data() from public, anon;
grant execute on function public.export_my_data(), public.delete_my_data() to authenticated;

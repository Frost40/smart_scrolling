-- Trigger helpers used by the content and activity tables (docs/DATABASE.md, "Rules the database checks by itself").

-- Keeps updated_at current.
create function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Raises version when a card's content changes (a status change alone does not count).
create function public.bump_version() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (to_jsonb(new) - array['version', 'status', 'created_at', 'updated_at'])
     is distinct from (to_jsonb(old) - array['version', 'status', 'created_at', 'updated_at']) then
    new.version := old.version + 1;
  end if;
  return new;
end $$;

-- Raises revision on every save, so a save based on an old revision finds no row.
create function public.bump_revision() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.revision := old.revision + 1;
  return new;
end $$;

-- Topics have two levels: a sub-topic's parent must be a main area, and a sub-topic has no children.
create function public.check_topic_levels() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.parent_id is not null and (
       exists (select 1 from public.topics where id = new.parent_id and parent_id is not null)
       or exists (select 1 from public.topics where parent_id = new.id)) then
    raise exception 'Topics have two levels: "%" cannot sit under "%".', new.id, new.parent_id;
  end if;
  return new;
end $$;

-- A detail row must belong to a source of the matching kind (trigger argument: book, paper or news).
create function public.check_source_kind() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.sources where id = new.source_id and kind = tg_argv[0]) then
    raise exception '% details need a source of kind %.', tg_argv[0], tg_argv[0];
  end if;
  return new;
end $$;

-- News cards must come from news sources.
create function public.check_news_card() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.format = 'news' and not exists (
       select 1 from public.sources where id = new.source_id and kind = 'news') then
    raise exception 'News cards must come from a news source.';
  end if;
  return new;
end $$;

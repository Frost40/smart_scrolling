-- The 11 activity tables, written by the app for the signed-in person only. See docs/DATABASE.md.

create table public.profiles (
  user_id          uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  languages        text[] not null default '{en}',      -- Discover shows only cards in these languages
  preferred_level  text check (preferred_level in ('intro', 'intermediate', 'advanced')),
  discover_filter  text not null default 'mix' check (discover_filter in
                     ('mix', 'concept', 'quote', 'news', 'research', 'myth', 'image', 'video', 'audio')),
  practice_filter  text not null default 'mix' check (practice_filter in
                     ('mix', 'flashcard', 'multiple_choice', 'true_false', 'ordering', 'matching')),
  weekly_goal_days int check (weekly_goal_days between 1 and 7), -- 3 = practise three days a week; empty = no goal
  revision         bigint not null default 1,           -- goes up on every save (trigger)
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create trigger profiles_revision before update on public.profiles
  for each row execute function public.bump_revision();
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

create table public.devices (
  user_id                 uuid not null default auth.uid() references auth.users (id) on delete cascade,
  installation_id         uuid not null,                -- created by the app on first launch
  offline_mode            text not null default 'standard'
                            check (offline_mode in ('online_only', 'light', 'standard', 'extended')),
  download_on_mobile_data boolean not null default false, -- false = downloads only on Wi-Fi
  theme_mode              text not null default 'system' check (theme_mode in ('system', 'light', 'dark')),
  reduce_motion           boolean not null default false,
  high_contrast           boolean not null default false,
  text_scale              numeric(3, 2) not null default 1.0 check (text_scale between 1.0 and 1.8),
  reminder_time           time,                         -- 20:30; empty = no reminder
  last_sync_at            timestamptz,                  -- last time this phone synced
  revision                bigint not null default 1,
  primary key (user_id, installation_id)
);
create trigger devices_revision before update on public.devices
  for each row execute function public.bump_revision();

create table public.user_topics (
  user_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
  topic_id text not null references public.topics (id) on delete cascade, -- psychology
  choice   text not null check (choice in ('follow', 'hide')),
  primary key (user_id, topic_id)
);
create index user_topics_topic on public.user_topics (topic_id);

create table public.user_sources (
  user_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  source_id text not null references public.sources (id) on delete cascade, -- incepholorgb
  choice    text not null check (choice in ('follow', 'hide')),             -- follow = "Add to my feed"
  primary key (user_id, source_id)
);
create index user_sources_source on public.user_sources (source_id);

create table public.likes (
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  discover_card_id text not null references public.discover_cards (id) on delete cascade,
  liked_at         timestamptz not null default now(),
  note             text,                                -- your private note (optional)
  review_level     smallint not null default 0 check (review_level between 0 and 4), -- gap until next test: 1·3·7·14·30 days
  next_review_at   timestamptz not null default now() + interval '1 day', -- the first test is 1 day after the like
  last_reviewed_at timestamptz,
  reviews_paused   boolean not null default false,      -- true = keep it in the Library but stop testing it
  primary key (user_id, discover_card_id)
);
create index likes_due on public.likes (user_id, next_review_at) where not reviews_paused;
create index likes_card on public.likes (discover_card_id);

create table public.saved_for_later (
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  discover_card_id  text not null references public.discover_cards (id) on delete cascade,
  saved_at          timestamptz not null default now(),
  resume_at_seconds int check (resume_at_seconds >= 0), -- where you stopped a video or audio
  primary key (user_id, discover_card_id)
);
create index saved_for_later_card on public.saved_for_later (discover_card_id);

create table public.seen_cards (
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  discover_card_id text not null references public.discover_cards (id) on delete cascade,
  first_seen_at    timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),
  primary key (user_id, discover_card_id)
);
create index seen_cards_card on public.seen_cards (discover_card_id);

create table public.practice_answers (
  id                    uuid primary key,               -- made by the phone, so a retry is never counted twice
  user_id               uuid not null default auth.uid() references auth.users (id) on delete cascade,
  practice_card_id      text not null references public.practice_cards (id) on delete cascade,
  practice_card_version int  not null,                  -- which version of that test was answered
  discover_card_id      text not null references public.discover_cards (id) on delete cascade, -- the liked card this review was for
  answer                jsonb,                          -- what you answered: the option, your order, your pairs
  result                text not null check (result in ('correct', 'wrong', 'again', 'hard', 'good', 'easy')),
  answered_at           timestamptz not null
);
create index practice_answers_review on public.practice_answers (user_id, discover_card_id, answered_at desc);
create index practice_answers_card on public.practice_answers (practice_card_id);

create table public.collections (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name       text not null check (length(btrim(name)) between 1 and 60), -- For my thesis
  created_at timestamptz not null default now(),
  unique (user_id, name),
  unique (id, user_id)
);

-- Unliking a card takes it out of your collections (the foreign key to likes cascades).
create table public.collection_cards (
  collection_id    uuid not null,
  discover_card_id text not null,
  user_id          uuid not null default auth.uid(),
  added_at         timestamptz not null default now(),
  primary key (collection_id, discover_card_id),
  foreign key (collection_id, user_id) references public.collections (id, user_id) on delete cascade,
  foreign key (user_id, discover_card_id) references public.likes (user_id, discover_card_id) on delete cascade
);
create index collection_cards_like on public.collection_cards (user_id, discover_card_id);

-- The owner's to-do list as content maker.
create table public.content_requests (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind             text not null check (kind in ('problem', 'more_cards', 'more_practice')),
  -- problem = you reported a mistake; more_cards = asked in Explore; more_practice = automatic, a liked card has no new tests left
  source_id        text references public.sources (id) on delete cascade,
  discover_card_id text references public.discover_cards (id) on delete cascade,
  practice_card_id text references public.practice_cards (id) on delete cascade,
  message          text,
  status           text not null default 'open' check (status in ('open', 'done', 'dismissed')),
  created_at       timestamptz not null default now(),
  resolved_at      timestamptz,
  check (kind <> 'more_practice' or discover_card_id is not null),
  check (kind <> 'more_cards' or source_id is not null)
);
create index content_requests_user on public.content_requests (user_id, status);
create index content_requests_source on public.content_requests (source_id);
create index content_requests_discover on public.content_requests (discover_card_id);
create index content_requests_practice on public.content_requests (practice_card_id);
-- never two open more_practice to-dos for the same card
create unique index content_requests_one_open_more_practice on public.content_requests (user_id, discover_card_id)
  where kind = 'more_practice' and status = 'open';

-- Meanings shown in the Supabase Table Editor (same words as docs/DATABASE.md).
comment on table public.profiles is 'One row per person: settings that follow you on every phone.';
comment on column public.profiles.user_id is 'the person this row belongs to; default auth.uid()';
comment on column public.profiles.languages is 'Discover shows only cards in these languages; default ''{en}''';
comment on column public.profiles.preferred_level is 'one of intro, intermediate, advanced; may be empty';
comment on column public.profiles.discover_filter is 'one of mix, concept, quote, news, research, myth, image, video, audio; default ''mix''';
comment on column public.profiles.practice_filter is 'one of mix, flashcard, multiple_choice, true_false, ordering, matching; default ''mix''';
comment on column public.profiles.weekly_goal_days is '3 = practise three days a week; empty = no goal; from 1 to 7; may be empty';
comment on column public.profiles.revision is 'goes up on every save (trigger); default 1';
comment on column public.profiles.created_at is 'when the row was made; default now()';
comment on column public.profiles.updated_at is 'when the row last changed; default now()';
comment on table public.devices is 'One row per person per phone: settings for that phone only.';
comment on column public.devices.user_id is 'the person this row belongs to; default auth.uid()';
comment on column public.devices.installation_id is 'created by the app on first launch';
comment on column public.devices.offline_mode is 'one of online_only, light, standard, extended; default ''standard''';
comment on column public.devices.download_on_mobile_data is 'false = downloads only on Wi-Fi; default false';
comment on column public.devices.theme_mode is 'one of system, light, dark; default ''system''';
comment on column public.devices.reduce_motion is 'true = fewer animations; default false';
comment on column public.devices.high_contrast is 'true = stronger colors; default false';
comment on column public.devices.text_scale is 'text size, 1.0 = normal; from 1.0 to 1.8; default 1.0';
comment on column public.devices.reminder_time is '20:30; empty = no reminder; may be empty';
comment on column public.devices.last_sync_at is 'last time this phone synced; may be empty';
comment on column public.devices.revision is 'goes up on every save (trigger); default 1';
comment on table public.user_topics is 'One row says a person follows or hides a topic.';
comment on column public.user_topics.user_id is 'the person this row belongs to; default auth.uid()';
comment on column public.user_topics.topic_id is 'psychology';
comment on column public.user_topics.choice is 'one of follow, hide';
comment on table public.user_sources is 'One row says a person added a source to their feed ("follow") or hid it.';
comment on column public.user_sources.user_id is 'the person this row belongs to; default auth.uid()';
comment on column public.user_sources.source_id is 'incepholorgb';
comment on column public.user_sources.choice is 'follow = "Add to my feed"; one of follow, hide';
comment on table public.likes is 'One row is one card you liked, with its review timetable and your note.';
comment on column public.likes.user_id is 'the person this row belongs to; default auth.uid()';
comment on column public.likes.discover_card_id is 'the Discover card';
comment on column public.likes.liked_at is 'when you liked it; default now()';
comment on column public.likes.note is 'your private note (optional); may be empty';
comment on column public.likes.review_level is 'gap until next test: 1·3·7·14·30 days; from 0 to 4; default 0';
comment on column public.likes.next_review_at is 'the first test is 1 day after the like; default now() + interval ''1 day''';
comment on column public.likes.last_reviewed_at is 'when you last answered a test for it; may be empty';
comment on column public.likes.reviews_paused is 'true = keep it in the Library but stop testing it; default false';
comment on table public.saved_for_later is 'One row is one card you saved for later.';
comment on column public.saved_for_later.user_id is 'the person this row belongs to; default auth.uid()';
comment on column public.saved_for_later.discover_card_id is 'the Discover card';
comment on column public.saved_for_later.saved_at is 'when you saved it; default now()';
comment on column public.saved_for_later.resume_at_seconds is 'where you stopped a video or audio; may be empty';
comment on table public.seen_cards is 'One row says a card has been on your screen, so the feed does not show it again.';
comment on column public.seen_cards.user_id is 'the person this row belongs to; default auth.uid()';
comment on column public.seen_cards.discover_card_id is 'the Discover card';
comment on column public.seen_cards.first_seen_at is 'the first time it was on your screen; default now()';
comment on column public.seen_cards.last_seen_at is 'the last time it was on your screen; default now()';
comment on table public.practice_answers is 'One row is one answer you gave to a test. Answers are kept forever.';
comment on column public.practice_answers.id is 'made by the phone, so a retry is never counted twice';
comment on column public.practice_answers.user_id is 'the person this row belongs to; default auth.uid()';
comment on column public.practice_answers.practice_card_id is 'the practice card';
comment on column public.practice_answers.practice_card_version is 'which version of that test was answered';
comment on column public.practice_answers.discover_card_id is 'the liked card this review was for';
comment on column public.practice_answers.answer is 'what you answered: the option, your order, your pairs; may be empty';
comment on column public.practice_answers.result is 'one of correct, wrong, again, hard, good, easy';
comment on column public.practice_answers.answered_at is 'when you answered, by the phone clock';
comment on table public.collections is 'One row is one of your folders of liked cards.';
comment on column public.collections.id is 'default gen_random_uuid()';
comment on column public.collections.user_id is 'the person this row belongs to; default auth.uid()';
comment on column public.collections.name is 'For my thesis; 1 to 60 characters';
comment on column public.collections.created_at is 'when the row was made; default now()';
comment on table public.collection_cards is 'One row puts one liked card into one collection.';
comment on column public.collection_cards.collection_id is 'the collection';
comment on column public.collection_cards.discover_card_id is 'the Discover card';
comment on column public.collection_cards.user_id is 'the person this row belongs to; default auth.uid()';
comment on column public.collection_cards.added_at is 'when the card was put in the collection; default now()';
comment on table public.content_requests is 'One row is one to-do for the owner: a reported mistake or a request for more cards or tests.';
comment on column public.content_requests.id is 'default gen_random_uuid()';
comment on column public.content_requests.user_id is 'the person this row belongs to; default auth.uid()';
comment on column public.content_requests.kind is 'one of problem, more_cards, more_practice';
comment on column public.content_requests.source_id is 'the source it belongs to; may be empty';
comment on column public.content_requests.discover_card_id is 'the Discover card; may be empty';
comment on column public.content_requests.practice_card_id is 'the practice card; may be empty';
comment on column public.content_requests.message is 'what you wrote (optional); may be empty';
comment on column public.content_requests.status is 'open = waiting for the owner; done = handled; dismissed = closed without a change; one of open, done, dismissed; default ''open''';
comment on column public.content_requests.created_at is 'when the row was made; default now()';
comment on column public.content_requests.resolved_at is 'when the owner marked it done or dismissed; may be empty';

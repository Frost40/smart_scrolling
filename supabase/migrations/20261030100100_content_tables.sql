-- The 11 content tables, written only by the upload tool (service-role key). See docs/DATABASE.md.

create table public.topics (
  id        text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'), -- computer-science, artificial-intelligence
  name      text not null,                                           -- Computer science (CS)
  parent_id text references public.topics (id) on delete restrict,  -- empty for a main area; for a sub-topic: its main area
  position  int  not null default 0,                                 -- order in lists
  check (parent_id is distinct from id)
);
create index topics_parent_id on public.topics (parent_id);
create trigger topics_two_levels before insert or update on public.topics
  for each row execute function public.check_topic_levels();

create table public.sources (
  id            text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'), -- happiness-advantage
  kind          text not null check (kind in ('book', 'paper', 'news', 'other')),
  title         text not null,                         -- The Happiness Advantage
  authors       text[] not null default '{}',          -- {Shawn Achor}
  published_on  date,                                  -- 2010-09-14
  language      text not null default 'en',            -- en
  link          text,                                  -- web address of the source (optional)
  description   text,                                  -- one to three sentences for the source page (optional)
  cover_path    text,                                  -- media bucket: sources/happiness-advantage/cover.jpg (optional)
  original_path text,                                  -- source-files bucket: happiness-advantage/original.pdf (optional)
  text_path     text,                                  -- source-files bucket: happiness-advantage/text.txt, the extracted text (optional)
  status        text not null default 'draft' check (status in ('draft', 'published', 'hidden')),
  is_sample     boolean not null default false,        -- true = fake test content, removed by the purge command
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (cover_path is null or cover_path like 'sources/' || id || '/%'),
  check (original_path is null or original_path like id || '/%'),
  check (text_path is null or text_path like id || '/%')
);
create trigger sources_touch before update on public.sources
  for each row execute function public.touch_updated_at();

create table public.book_details (
  source_id text primary key references public.sources (id) on delete cascade, -- happiness-advantage
  isbn      text,               -- 9780307591562
  publisher text,               -- Crown Business
  edition   text,               -- 1st edition
  pages     int check (pages > 0) -- 256
);
create trigger book_details_kind before insert or update on public.book_details
  for each row execute function public.check_source_kind('book');

create table public.paper_details (
  source_id    text primary key references public.sources (id) on delete cascade, -- incepholorgb
  doi          text,            -- 10.29026/oea.2025.250130
  journal      text,            -- Opto-Electronic Advances
  paper_status text not null default 'published'
               check (paper_status in ('preprint', 'published', 'retracted'))
);
create trigger paper_details_kind before insert or update on public.paper_details
  for each row execute function public.check_source_kind('paper');

create table public.news_details (
  source_id  text primary key references public.sources (id) on delete cascade, -- eu-ai-act-guardian-2026-10-29
  newspaper  text,              -- The Guardian
  show_until date               -- after this day its cards leave Discover (they stay in the Library); empty = no end
);
create trigger news_details_kind before insert or update on public.news_details
  for each row execute function public.check_source_kind('news');

create table public.source_topics (
  source_id text references public.sources (id) on delete cascade,  -- happiness-advantage
  topic_id  text references public.topics (id) on delete restrict,  -- psychology
  primary key (source_id, topic_id)
);
create index source_topics_topic_id on public.source_topics (topic_id);

create table public.discover_cards (
  id               text primary key,                    -- happiness-advantage/tetris-quote
  source_id        text not null references public.sources (id) on delete cascade,
  format           text not null check (format in
                     ('concept', 'quote', 'news', 'research', 'myth', 'image', 'video', 'audio')),
  title            text not null,                       -- The Tetris effect
  front            text not null,                       -- what you see first (a myth card: the myth)
  back             text,                                -- what you see after flipping (a myth card: the fact)
  location         text,                                -- Chapter 5, p. 112
  position         int,                                 -- order inside the source, used on the source page
  level            text check (level in ('intro', 'intermediate', 'advanced')),
  language         text not null default 'en',          -- same as the source unless set
  speaker          text,                                -- who said it; quotes only, and required for quotes
  media_path       text,                                -- media bucket: cards/happiness-advantage/tetris-diagram/image.webp
  media_alt        text,                                -- what the image or video shows, for screen readers
  captions_path    text,                                -- media bucket: subtitles (.vtt) for video and audio
  transcript       text,                                -- everything said in the video or audio
  poster_path      text,                                -- media bucket: video thumbnail
  duration_seconds int check (duration_seconds > 0),    -- length of the video or audio
  version          int  not null default 1,             -- goes up each time the card's content changes
  status           text not null default 'draft' check (status in ('draft', 'published', 'hidden')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*/[a-z0-9]+(-[a-z0-9]+)*$' and id like source_id || '/%'),
  check (format <> 'quote' or speaker is not null),
  check (format not in ('image', 'video', 'audio') or media_path is not null),
  check (media_path is null or media_path like 'cards/' || id || '/%'),
  check (captions_path is null or captions_path like 'cards/' || id || '/%'),
  check (poster_path is null or poster_path like 'cards/' || id || '/%')
);
create index discover_cards_source on public.discover_cards (source_id, position);
create trigger discover_cards_touch before update on public.discover_cards
  for each row execute function public.touch_updated_at();
create trigger discover_cards_version before update on public.discover_cards
  for each row execute function public.bump_version();
create trigger discover_cards_news before insert or update on public.discover_cards
  for each row execute function public.check_news_card();

create table public.card_topics (
  discover_card_id text references public.discover_cards (id) on delete cascade, -- happiness-advantage/tetris-concept
  topic_id         text references public.topics (id) on delete restrict,         -- neuroscience
  primary key (discover_card_id, topic_id)
);
create index card_topics_topic_id on public.card_topics (topic_id);

-- "See also" between two Discover cards about the same idea. One row per pair (smaller id first); it works both ways.
create table public.related_cards (
  discover_card_id text references public.discover_cards (id) on delete cascade,
  related_card_id  text references public.discover_cards (id) on delete cascade,
  primary key (discover_card_id, related_card_id),
  check (discover_card_id < related_card_id)
);
create index related_cards_related on public.related_cards (related_card_id);

create table public.practice_cards (
  id             text primary key,                      -- happiness-advantage/tetris-flash-1
  source_id      text not null references public.sources (id) on delete cascade,
  type           text not null check (type in
                   ('flashcard', 'multiple_choice', 'true_false', 'ordering', 'matching')),
  prompt         text not null,                         -- the question, statement or instruction
  answer         text,                                  -- flashcard: the back of the card
  choices        text[],                                -- multiple choice: the options
  correct_choice int,                                   -- multiple choice: the right option (0 = first)
  is_true        boolean,                               -- true/false: the right answer
  correct_order  text[],                                -- ordering: items in the right order (the app shuffles them)
  match_left     text[],                                -- matching: the left side
  match_right    text[],                                -- matching: the right side, same order as the left (the app shuffles it)
  explanation    text,                                  -- shown after you answer (optional)
  version        int  not null default 1,
  status         text not null default 'draft' check (status in ('draft', 'published', 'hidden')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*/[a-z0-9]+(-[a-z0-9]+)*$' and id like source_id || '/%'),
  -- coalesce(…, false): a missing field makes the check fail instead of silently passing
  check (coalesce(case type
           when 'flashcard'       then answer is not null
           when 'multiple_choice' then cardinality(choices) between 2 and 6
                                       and correct_choice between 0 and cardinality(choices) - 1
           when 'true_false'      then is_true is not null
           when 'ordering'        then cardinality(correct_order) >= 2
           when 'matching'        then cardinality(match_left) >= 2
                                       and cardinality(match_left) = cardinality(match_right)
         end, false))
);
create index practice_cards_source on public.practice_cards (source_id);
create trigger practice_cards_touch before update on public.practice_cards
  for each row execute function public.touch_updated_at();
create trigger practice_cards_version before update on public.practice_cards
  for each row execute function public.bump_version();

create table public.practice_links (
  discover_card_id text references public.discover_cards (id) on delete cascade, -- happiness-advantage/tetris-quote
  practice_card_id text references public.practice_cards (id) on delete cascade, -- happiness-advantage/tetris-flash-1
  primary key (discover_card_id, practice_card_id)
);
create index practice_links_practice on public.practice_links (practice_card_id);

-- Meanings shown in the Supabase Table Editor (same words as docs/DATABASE.md).
comment on table public.topics is 'One row is one topic: a main area (no parent) or a sub-topic under a main area.';
comment on column public.topics.id is 'computer-science, artificial-intelligence';
comment on column public.topics.name is 'Computer science (CS)';
comment on column public.topics.parent_id is 'empty for a main area; for a sub-topic: its main area; may be empty';
comment on column public.topics.position is 'order in lists; default 0';
comment on table public.sources is 'One row is one source: a book, a paper, a news article or anything else.';
comment on column public.sources.id is 'happiness-advantage';
comment on column public.sources.kind is 'one of book, paper, news, other';
comment on column public.sources.title is 'The Happiness Advantage';
comment on column public.sources.authors is '{Shawn Achor}; default ''{}''';
comment on column public.sources.published_on is '2010-09-14; may be empty';
comment on column public.sources.language is 'en; default ''en''';
comment on column public.sources.link is 'web address of the source (optional); may be empty';
comment on column public.sources.description is 'one to three sentences for the source page (optional); may be empty';
comment on column public.sources.cover_path is 'media bucket: sources/happiness-advantage/cover.jpg (optional); may be empty';
comment on column public.sources.original_path is 'source-files bucket: happiness-advantage/original.pdf (optional); may be empty';
comment on column public.sources.text_path is 'source-files bucket: happiness-advantage/text.txt, the extracted text (optional); may be empty';
comment on column public.sources.status is 'draft = not shown yet; published = shown in the app; hidden = taken out of the app but kept; one of draft, published, hidden; default ''draft''';
comment on column public.sources.is_sample is 'true = fake test content, removed by the purge command; default false';
comment on column public.sources.created_at is 'when the row was made; default now()';
comment on column public.sources.updated_at is 'when the row last changed; default now()';
comment on table public.book_details is 'One row adds the book-only facts to a source of kind `book`.';
comment on column public.book_details.source_id is 'happiness-advantage';
comment on column public.book_details.isbn is '9780307591562; may be empty';
comment on column public.book_details.publisher is 'Crown Business; may be empty';
comment on column public.book_details.edition is '1st edition; may be empty';
comment on column public.book_details.pages is '256; may be empty';
comment on table public.paper_details is 'One row adds the paper-only facts to a source of kind `paper`.';
comment on column public.paper_details.source_id is 'incepholorgb';
comment on column public.paper_details.doi is '10.29026/oea.2025.250130; may be empty';
comment on column public.paper_details.journal is 'Opto-Electronic Advances; may be empty';
comment on column public.paper_details.paper_status is 'one of preprint, published, retracted; default ''published''';
comment on table public.news_details is 'One row adds the news-only facts to a source of kind `news`.';
comment on column public.news_details.source_id is 'eu-ai-act-guardian-2026-10-29';
comment on column public.news_details.newspaper is 'The Guardian; may be empty';
comment on column public.news_details.show_until is 'after this day its cards leave Discover (they stay in the Library); empty = no end; may be empty';
comment on table public.source_topics is 'One row says "this source is about this topic".';
comment on column public.source_topics.source_id is 'happiness-advantage';
comment on column public.source_topics.topic_id is 'psychology';
comment on table public.discover_cards is 'One row is one Discover card: a short card you read, watch or listen to.';
comment on column public.discover_cards.id is 'happiness-advantage/tetris-quote';
comment on column public.discover_cards.source_id is 'the source it belongs to';
comment on column public.discover_cards.format is 'one of concept, quote, news, research, myth, image, video, audio';
comment on column public.discover_cards.title is 'The Tetris effect';
comment on column public.discover_cards.front is 'what you see first (a myth card: the myth)';
comment on column public.discover_cards.back is 'what you see after flipping (a myth card: the fact); may be empty';
comment on column public.discover_cards.location is 'Chapter 5, p. 112; may be empty';
comment on column public.discover_cards.position is 'order inside the source, used on the source page; may be empty';
comment on column public.discover_cards.level is 'one of intro, intermediate, advanced; may be empty';
comment on column public.discover_cards.language is 'same as the source unless set; default ''en''';
comment on column public.discover_cards.speaker is 'who said it; quotes only, and required for quotes; may be empty';
comment on column public.discover_cards.media_path is 'media bucket: cards/happiness-advantage/tetris-diagram/image.webp; may be empty';
comment on column public.discover_cards.media_alt is 'what the image or video shows, for screen readers; may be empty';
comment on column public.discover_cards.captions_path is 'media bucket: subtitles (.vtt) for video and audio; may be empty';
comment on column public.discover_cards.transcript is 'everything said in the video or audio; may be empty';
comment on column public.discover_cards.poster_path is 'media bucket: video thumbnail; may be empty';
comment on column public.discover_cards.duration_seconds is 'length of the video or audio; may be empty';
comment on column public.discover_cards.version is 'goes up each time the card''s content changes; default 1';
comment on column public.discover_cards.status is 'draft = not shown yet; published = shown in the app; hidden = taken out of the app but kept; one of draft, published, hidden; default ''draft''';
comment on column public.discover_cards.created_at is 'when the row was made; default now()';
comment on column public.discover_cards.updated_at is 'when the row last changed; default now()';
comment on table public.card_topics is 'One row gives a single card an extra topic, on top of its source''s topics.';
comment on column public.card_topics.discover_card_id is 'happiness-advantage/tetris-concept';
comment on column public.card_topics.topic_id is 'neuroscience';
comment on table public.related_cards is 'One row links two cards about the same idea ("see also"). It works both ways.';
comment on column public.related_cards.discover_card_id is 'one card of the pair (the smaller id)';
comment on column public.related_cards.related_card_id is 'the other card of the pair (the larger id)';
comment on table public.practice_cards is 'One row is one test: a flashcard, multiple choice, true/false, ordering or matching.';
comment on column public.practice_cards.id is 'happiness-advantage/tetris-flash-1';
comment on column public.practice_cards.source_id is 'the source it belongs to';
comment on column public.practice_cards.type is 'one of flashcard, multiple_choice, true_false, ordering, matching';
comment on column public.practice_cards.prompt is 'the question, statement or instruction';
comment on column public.practice_cards.answer is 'flashcard: the back of the card; may be empty';
comment on column public.practice_cards.choices is 'multiple choice: the options; may be empty';
comment on column public.practice_cards.correct_choice is 'multiple choice: the right option (0 = first); may be empty';
comment on column public.practice_cards.is_true is 'true/false: the right answer; may be empty';
comment on column public.practice_cards.correct_order is 'ordering: items in the right order (the app shuffles them); may be empty';
comment on column public.practice_cards.match_left is 'matching: the left side; may be empty';
comment on column public.practice_cards.match_right is 'matching: the right side, same order as the left (the app shuffles it); may be empty';
comment on column public.practice_cards.explanation is 'shown after you answer (optional); may be empty';
comment on column public.practice_cards.version is 'goes up each time the content changes; default 1';
comment on column public.practice_cards.status is 'draft = not shown yet; published = shown in the app; hidden = taken out of the app but kept; one of draft, published, hidden; default ''draft''';
comment on column public.practice_cards.created_at is 'when the row was made; default now()';
comment on column public.practice_cards.updated_at is 'when the row last changed; default now()';
comment on table public.practice_links is 'One row says "this test checks this Discover card".';
comment on column public.practice_links.discover_card_id is 'happiness-advantage/tetris-quote';
comment on column public.practice_links.practice_card_id is 'happiness-advantage/tetris-flash-1';

# SmartScrolling: Product Requirements (v2.0)

**Version:** 2.0, 29 October 2026. It replaces PRD v1.3 and the owner preferences P01–P09 (both archived; see section 13).

This is the one source of truth for what the app does. Where this file and older documents disagree, this file wins. Section 11 holds the frozen decisions; only the owner changes them.

## 1. What SmartScrolling is

SmartScrolling is a microlearning app: it replaces aimless scrolling with short learning cards.

- For now only the owner uses it, for personal learning, and it isn't shared, published or sold. Anyone who signs in can use it, and every person's data stays separate (D01).
- It has two experiences:
  - **Discover:** read, watch or listen to short cards, and keep the ones you like.
  - **Practice:** be tested, on a timetable, on the cards you liked.
- It is built first as a complete but empty shell. The tickets build the whole working app and an empty, ready database. After the last ticket, the owner makes sources and cards offline and uploads them, and the app works with no further code changes ("plug and play") (D02).
- While building, agents use only fake sample content (D03). Content quality is the owner's later work, not an app ticket (D04).

## 2. Scope

**In:** everything in the v2 scope (screens, offline cache, Supabase RLS/RPCs, and upload tooling).

**Out** (D05), with the reason:

- Human content review, the 300-card goal and catalogue growth: content is the owner's own work, done outside the app (D04).
- Making media: the owner produces media offline and uploads it.
- Uploading your own books inside the app (old ticket 21): content enters only through the upload tool.
- Smarter search and ranking (old 22): simple search and the feed order in section 7 are enough for one person.
- The owner's own review algorithm (old 23): the app only keeps a plug for it (section 6).
- App store and payments (old 24): the app is private for now (D01).
- Simulations, AI grading of free text and social challenges: no AI runs inside the app, and there is no social layer.
- Learning paths, comparison cards, and scenario / prediction / reflection activities: cards stand alone and are linked only as "see also" (D27).
- Country and territory checks, and per-use rights checks: the app is private, so there is nothing to check per country or per use.
- Guest or preview mode: sign-in is required (D06).

## 3. Accounts

- You sign in with Google. Anyone who signs in gets in: there is no invite list (D06).
- Each person's rows are visible only to them (section 9).
- Agents never use the owner's account. They use a test login that exists only in debug builds: the email `agent@smartscrolling.test` with a password made in ticket 03, stored only in the gitignored `.env` and `.env.test.json`. The **Test login** button appears only in debug builds, and only when those values are present (A3-8).
- Today an old invite check still runs inside Supabase Auth. Ticket 03 turns it off and removes it, and leaves every Google setting untouched (A3-9).
- The Email provider is used only by the debug test login. The app shows only Google, and email confirmation stays on.

## 4. Screens

| Screen | Purpose | Behaviour |
|---|---|---|
| Start | Opens the app | Shows while settings load; if loading fails, it says so and offers to try again. |
| Welcome / Sign-in | Lets you in | **Sign in with Google**; in debug builds also **Test login**. |
| Onboarding | Picks your first topics | Shown after sign-in while you follow nothing. Pick main areas and sub-topics, then Continue or Skip. |
| Discover | Learn something new | A vertical feed of full cards with Like and For later (4.2). |
| Practice | Remember what you liked | A vertical feed of due tests (4.3). |
| Explore | Find sources | Search and a topic tree; opens source pages (4.5). |
| Library | Your saved cards | Liked and For later, each a vertical feed of full cards (4.4). |
| Source page | Everything about one source | Cover, title, authors, details, link, its cards, and Add to my feed / Hide / Ask for more cards. |
| Settings | How the app behaves | Opens from the top bar (4.6). |
| Account | Who you are | Opens from the top bar: your email and Sign out. |

There are four tabs: Discover, Practice, Explore and Library. Settings and Account open from the top bar (D08).

### 4.1 Feeds and gestures

- Discover, Practice and Library are vertical feeds of full cards: one card under the other, moved up and down with the finger, like posts on Instagram. A list of links is not enough (D09).
- **Hold-to-refresh** (D10): on the top card of a feed, pull down and hold briefly. A reload starts and brings new, different cards.
  - Discover gets a new batch that leaves out every card already loaded or seen.
  - Practice reloads the due tests.
  - Library reloads its lists.
- The hold lasts 1.5 seconds, set in one constant, `AppDurations.refreshHold` (A3-6).
- A Discover card counts as seen once at least half of it has been on screen. Seen marks are sent in small batches (A3-4).
- Feed order is in section 7 (A3-5).

### 4.2 Discover

- Every card has a ♥ **Like** button and a 🕒 **For later** button (D11).
  - Swipe right = Like; swipe left = For later.
  - Tapping a filled button again undoes it.
  - Scrolling past a card marks it as seen, which is neutral.
  - There is no dislike anywhere, and For later is never a negative signal.
- Only Discover cards can be liked or saved for later, never Practice cards (D12).
- Tap a card to flip it. The back is compact: only the essentials, plus a **Source page** button. The source page shows the cover image and the full source information (D13).
- The card back also has **Report a problem**, which adds a to-do for the owner.

What each format shows (D28):

- **concept:** an idea; front = the idea in short, back = a little more.
- **quote:** the speaker on the front; flip for context.
- **news:** newspaper and date; it leaves Discover after its `show_until` date (it stays in the Library).
- **research:** question → method → result → limits.
- **myth:** the myth on the front, the fact on the back.
- **image:** a picture, with alt text for screen readers.
- **video and audio:** captions, a transcript, a poster image, and they resume where you stopped.

### 4.3 Practice

- Practice shows tests for the Discover cards you liked, as a vertical feed (D15).
- It shows due tests, oldest due first, 10 at a time; more load as you scroll. When nothing is due, a **Practice now** button offers liked cards that are not due yet, soonest first. Those answers move the timetable the same way (A3-1).
- There is no For later and no Skip in Practice. Scrolling past a test you did not answer changes nothing; it stays due (A3-2).

Controls for each type (D29):

- **flashcard:** think, tap **Reveal**, then rate **Again / Hard / Good / Easy**.
- **multiple_choice:** choose an option, tap **Check**.
- **true_false:** tap True or False, then **Check**.
- **ordering:** put shuffled items in order by dragging or with Up/Down buttons, then **Check**.
- **matching:** tap a left item, then its right item (the right side is shuffled), then **Check**.

After **Check** you see right or wrong plus the explanation. Right counts as Good and wrong counts as Again for the timetable. A partly right answer counts as wrong.

### 4.4 Library

- Two tabs, **Liked** and **For later**. Each one is a vertical feed of the full cards, like Discover.
- A search box (title, front text, source title) and filters (format, topic, source) sit at the top.
- Removing a card shows an **Undo** bar that restores it exactly, including its timetable, note and collections (A3-12).
- Liked cards show their next test date, "waiting for tests" or "reviews paused". You can pause and resume reviews of a card.
- **Collections:** your own folders of liked cards. **Notes:** a private note on any liked card (D35).

### 4.5 Explore

- You search sources by topic, title or author and open a source page (D14).
- The source page offers **Add to my feed** (follow), **Hide**, and **Ask for more cards**, which adds a to-do for the owner.
- The topic tree shows main areas, then their sub-topics (D26).
- Onboarding uses the same topic tree (see the Screens table).

### 4.6 Settings

- Theme: Follow phone / Light / Dark, remembered (D19).
- Offline mode (Online only, Light, Standard, Extended) and "use mobile data" for downloads (A3-13).
- Reduce motion, high contrast, and text size from 1.0 to 1.8.
- Daily reminder time and weekly goal.
- Topics (follow or hide), hidden sources (unhide), languages and preferred level.
- Your data: export everything, or delete all your activity.

## 5. Content model

- A **source** is one book, paper, news article or other thing (one news article = one source). Books, papers and news each add their own details (D24, D25).
- **Topics** have two levels, main areas and sub-topics. Topics are set on sources, and a single card may add extra topics (D26).
- A source contains **Discover cards** (to read, watch or listen) and **practice cards** (tests). Every Discover card stands alone; cards about the same idea are linked as related cards ("see also") (D27).
- A practice card can test one or more Discover cards (D30).
- Authors are names written on the source; quotes carry a speaker (D36).
- IDs are readable names written by the owner, such as `happiness-advantage/tetris-quote`. Re-uploading the same ID updates the card and raises its version (D37).
- Every source and card has a language, English for now (D38), and a card may have a level: intro, intermediate or advanced (D39).
- Real content is never deleted, only hidden. Sample content is deleted by one command (D41).

The exact definition of every table, column and storage folder is `docs/DATABASE.md`.

## 6. Learning

- The review timetable belongs to your Like of a Discover card, not to a practice card. You are tested on the concept you liked, several times, with different tests. Every liked card is tested (D31).
- At each due date the app picks a test linked to that card: one you never answered first, otherwise the one you answered longest ago. When none are new, a "more practice" to-do is added for the owner. No AI runs inside the app (D32).
- The ladder is 1 · 3 · 7 · 14 · 30 days; the first test comes 1 day after the Like. Right or Good: one step up. Easy: two steps up. Hard: stays. Wrong or Again: back to 1 day (D33).
- The app computes the timetable itself, so it works offline. If two answers for the same Like arrive, the one answered later wins (A3-3).
- All answers are kept forever.
- **The plug:** the whole rule lives in one pure function, `lib/domain/review_schedule.dart`. The owner's own future algorithm replaces that one file.

## 7. The Discover feed

The feed shows published cards (D34):
- from topics you follow (source topics plus extra card topics; following a main area includes its sub-topics);
- plus cards from sources you added in Explore;
- minus hidden topics and sources, other languages, news past its `show_until` date, and cards you already saw.

Order (A3-5):
- cards at your preferred level come first;
- then the sources take turns: the first card of each source, then the second of each, and so on, newest source first;
- if you follow nothing yet, the feed shows all published cards.

Refresh: hold-to-refresh (D10) asks for a batch that leaves out every card already loaded or seen.

## 8. Offline

How much the phone keeps (A3-13):

| Mode | Discover cards | Practice window | For later | Space cap |
|---|---:|---:|---:|---|
| Online only | 0 | 0 | 0 | nothing kept |
| Light | 200 | 80 | 20 | 256 MB |
| Standard (default) | 500 | 200 | 50 | 512 MB |
| Extended | 1,000 | 400 | 100 | 1 GB |

- Audio and video together may use at most 20% of the space cap.
- Downloads happen on Wi-Fi unless "use mobile data" is on.
- Offline, Discover and Library work from the stock on the phone, and Practice works for tests due in the next 14 days.
- **The outbox** (the "to send" list): every action is saved on the phone and sent in order when you are back online. Retrying an action never duplicates it, and for answers the later one wins.
- **Online only** clears the downloads but keeps the outbox.

## 9. Privacy and security

- Each person's rows are visible only to them. The app reads content but never writes it; only the owner's upload tool writes content.
- No secret key ever goes into the app. Flutter gets only public values (`.env.mobile.json`).
- Both storage buckets are private. The app reads media through signed links valid for 1 hour (A3-7).
- Settings → Your data: **Export** all your rows as a file, or **Delete all my activity**.

## 10. How content gets into the app

- The owner prepares one folder per source and uploads it with `python tools/content/upload.py <folder>`. The recipe is `docs/CONTENT_FORMAT.md` (written by ticket 03).
- While building, the sample box (`tools/content/sample/`) holds fake content, every source marked `is_sample`. `upload.py purge-samples` deletes it all; ticket 20 runs it.
- The owner's to-do list is the `content_requests` table: reported problems, "more cards" requests from Explore and automatic "more practice" to-dos. `upload.py requests` lists them.

## 11. Decisions (frozen)

### Product and scope

- **D01 Private for now, open by design (owner, updated 2026-10-29).** For now, only the owner uses SmartScrolling, for personal learning. It isn't shared, published or sold (P07). Nothing in the app limits who may use it, because the future is open. Every person's data stays separate.
- **D02 App shell first, content later.** The tickets build the complete working app and an empty, ready database. After the last ticket, the owner makes sources and cards offline and uploads them. The app then works with real content with no further code changes ("plug and play").
- **D03 Fake content while building.** Anything that needs content uses the sample box (`tools/content/sample/`, where every source is marked `is_sample = true`). Never use real content, and never wait for content. Ticket 20 (the final check) deletes the samples.
- **D04 Content quality is not an app ticket.** Card-writing prompts, quality evaluation, catalogue size and media production are the owner's later work. (P09.)
- **D05 Removed from the app plan:**
  - human content review, the 300-card goal and catalogue growth;
  - making media;
  - uploading your own books inside the app (old ticket 21);
  - smarter search and ranking (old 22);
  - the owner's own review algorithm (old 23). The app only keeps a plug for it (D33).
  - app store and payments (old 24);
  - simulations, AI grading of free text and social challenges;
  - learning paths, comparison cards, and scenario / prediction / reflection activities;
  - country and territory checks, and per-use rights checks;
  - guest or preview mode.
- **D06 Sign-in required, open to anyone (owner, updated 2026-10-29).** You sign in with Google, and anyone who signs in gets in: there is no invite list. Agents use a test login that exists only in debug builds, never the owner's account.
- **D07 Android first.** Development targets the Android emulator first; iOS builds require a Mac.
- **D45 Keep what works.** The owner tested the prototype and was happy with everything not listed here (P01, P06). A ticket changes only what it says.

### Screens and gestures

- **D08 Four tabs:** Discover, Practice, Explore, Library. Settings and Account open from the top bar.
- **D09 Scroll like Instagram (owner, 2026-10-29).** Discover, Practice and Library are vertical feeds of full cards: one card under the other, moved up and down with the finger, like posts on Instagram. A list of links is not enough (P03). This replaces every older "no vertical card navigation" rule (old PRD U26, 7.1, 7.2).
- **D10 Hold-to-refresh (owner, 2026-10-29).** On the top card of a feed (no card above it), pull down and hold briefly. A reload starts and brings new, different cards:
  - Discover gets a new batch that leaves out every card already loaded or seen.
  - Practice reloads the due tests.
  - Library reloads its lists.
- **D11 Discover actions.** Every Discover card has a ♥ Like button and a 🕒 For later button.
  - Swiping a card right means Like; swiping it left means For later.
  - Tapping a filled button again undoes it.
  - Scrolling past a card marks it as "seen", which is neutral.
  - There is no dislike anywhere, and For later is never a negative signal.
- **D12 Only Discover cards** can be liked or saved for later, never Practice cards.
- **D13 Compact card back and source page (P04).** Flipping a card shows only the essentials, plus a button to a source page. The source page shows the cover image and the full source information.
- **D14 Explore finds sources (P05).** You search by topic, title or author and open a source page. There you can choose "Add to my feed" (follow) or hide the source, or "Ask for more cards", which adds a to-do for the owner.
- **D15 Practice.** Practice shows tests for the Discover cards you liked, as a vertical feed.
  - Flashcards: think, tap Reveal, then rate Again / Hard / Good / Easy.
  - Other tests: answer, tap Check, then see right or wrong plus the explanation. Right counts as Good and wrong counts as Again for the timetable.
- **D16 Design ticket position.** "Make it beautiful" is ticket 14. The owner-feedback tickets 15–19 follow it, and the final check (ticket 20) runs last.

- **D46 Owner feedback refinements (2026-11-03):**
  - Seen Discover cards may come back: new cards first, then cards seen longest ago, and one now and then (changes D10 and D34). Liked and For later cards never come back in Discover.
  - Hold-to-refresh holds 0.5 s, and a hard pull refreshes at once (changes A3-6).
  - Topics are one follow on/off choice per topic, shown the same way and with the same names everywhere. Hide stays only for sources, on the source page.
  - First start: interests in at most 3 steps grouped by macro area. Continue needs one choice; Skip saves none and is remembered.
  - Settings: no hidden-sources list; text size has 5 steps from 85% to 120% around today's size (`devices.text_scale` check widened to 0.8–1.8).
  - The source page shows only a few of its cards.

### Structure and agents

- **D17 Folder layout** is exactly as in A5. The screens folder is `screens/` (not `features/`), with one folder per screen. State classes are named `<name>_provider.dart` / `<Name>Provider` and use `provider` + ChangeNotifier, as in the owner's SousChef project (not Riverpod, not "view models").
- **D18 LEGO widgets.**
  - Screens only arrange pieces, and every piece is a widget class.
  - A piece used by two or more screens lives in `lib/core/widgets/` and is listed in its `README.md`.
  - A screen or LEGO file has at most 250 lines.
- **D19 Theme ticket (owner).**
  - One main color produces a family of related named colors, different for each use: background, card, text, Like, For later, right answer, wrong answer, due, and one color per card format.
  - Light mode, dark mode and "follow the phone", switched in Settings and remembered (`devices.theme_mode`).
  - Files as in SousChef: `light_mode.dart`, `dark_mode.dart`, `theme_extensions.dart`, `theme_provider.dart`, plus `app_sizes.dart`.
  - Screens use only these named values.
- **D20 Enforcement in two layers:**
  - the rule robot `test/architecture_test.dart`;
  - a pre-commit hook that runs format, analyzer and tests.
- **D21 Autonomous workflow.** Human device checks (TalkBack, real phone, iOS) stay separate from automated testing.
- **D22 Tech choices:**
  - provider and go_router;
  - drift (the phone's offline database) and shared_preferences;
  - Supabase SQL functions instead of a separate API server;
  - a Python upload tool that uses only the standard library.
- **D23 One source of truth.** `docs/PRD.md` v2 replaces PRD v1.3 and `PRODUCT_PREFERENCES.md`, which are both archived. Old tickets 01–24 are archived too; tickets 01–04 stay there as history.

### Database (full detail in A4)

- **D24** One news article is one source.
- **D25** Source kinds are book, paper, news and other.
  - One shared `sources` table is the all-purpose table.
  - Books, papers and news each add a detail table: `book_details`, `paper_details`, `news_details`.
  - `other` (websites and anything else) uses only the shared table.
  - The owner may add new kinds later.
- **D26** Topics have two levels: main areas and sub-topics. Topics are set on sources, and a single card may add extra topics.
- **D27** Every Discover card stands alone. Several cards can be about the same idea; they are linked as related cards ("see also").
- **D28** Discover formats: concept, quote, news, research, myth, image, video, audio.
- **D29** Practice types: flashcard, multiple_choice, true_false, ordering, matching.
- **D30** A practice card can test one or more Discover cards (many-to-many links).
- **D31** The review timetable belongs to your Like of a Discover card, not to a practice card. You are tested on the concept you liked, several times, with different tests. Every liked card is tested.
- **D32** At each due date the app picks a test from your uploaded pool. It takes a linked test you never answered first; otherwise, the one you answered longest ago. When none are new, one "more practice" to-do is added for the owner. No AI runs inside the app.
- **D33** The timetable ladder is 1 · 3 · 7 · 14 · 30 days, and the first test comes 1 day after the Like.
  - Right or Good: one step up. Easy: two steps up. Hard: stays. Wrong or Again: back to 1 day.
  - The rule lives in one replaceable function. That function is the plug for the owner's own future algorithm.
  - All answers are kept forever, as input for that algorithm.
- **D34** The Discover feed shows published cards:
  - from topics you follow (source topics plus extra card topics; following a main area includes its sub-topics);
  - plus cards from sources you added in Explore;
  - minus hidden topics and sources, other languages, news past its `show_until` date, and cards you already saw.
- **D35** Extras: collections (your folders of liked cards), related cards, and a personal note on a liked card. No learning paths.
- **D36** Authors are names written on the source (a list of text). Quotes carry a speaker.
- **D37** IDs are readable names written by the owner: `happiness-advantage` for a source, `happiness-advantage/tetris-quote` for a card. Re-uploading the same ID updates the row and raises its version, and answers remember the version.
- **D38** Every source and card has a language field, English (`en`) for now. A card has its own language, which defaults to its source's. The feed shows only your languages.
- **D39** Discover cards can have an optional difficulty level (intro / intermediate / advanced). Your profile has a preferred level, and the feed prefers cards that match it.
- **D40** Liking a card removes it from For later. Unliking deletes its timetable and note but keeps your past answers. Undo right after brings it back.
- **D41** Real content is never deleted, only hidden. Sample content is deleted by one command, together with everything under it.
- **D42** Storage has two private buckets with readable folders:
  - `source-files`, used only by the upload tool;
  - `media`, which the app reads while you are signed in, through short-lived links.
- **D43** Today's database is replaced. A full backup comes first.
  - **Kept:** the Google account, settings, the book and the paper, moved into the new layout.
  - **Removed:** the 9 old tables, the 3 old buckets (after their files are moved), the `finalize-source` function, the leftover test files, and the invite list with its sign-up check (D06).
- **D44** Ticket list (A8):
  - 00 owner setup
  - 01 tidy the house
  - 02 theme
  - 03 database, storage and upload tool
  - 04 Discover
  - 05 Library
  - 06 Practice
  - 07 Explore and personalization
  - 08 offline Discover and Library
  - 09 offline Practice
  - 10 more Practice types
  - 11 collections, notes and related cards
  - 12 audio and video
  - 13 progress, reminders, sharing and your data
  - 14 make it beautiful
  - 15 one topic picker
  - 16 first start in steps
  - 17 settings tidy-up
  - 18 Discover repeats and faster refresh
  - 19 cards, source page and collections fixes
  - 20 final check and hand-over

### Planner defaults

- **A3-1 Practice sessions.** The Practice feed shows due tests, oldest due first, 10 at a time; more load as you scroll. When nothing is due, a "Practice now" button offers liked cards that are not due yet, soonest first. Those answers move the timetable the same way.
- **A3-2 No For later and no Skip in Practice.** Scrolling past a test you did not answer changes nothing; it stays due.
- **A3-3 Where the timetable is computed.** The app computes it with the pure function `lib/domain/review_schedule.dart`, so it works offline. This is the plug of D33. The server stores what the app sends. If two answers for the same Like arrive, the one with the later `answered_at` wins.
- **A3-4 Seen.** A Discover card counts as seen once at least half of it has been on screen. Seen marks are sent in small batches.
- **A3-5 Feed order.**
  - Cards at your preferred level come first.
  - Then the sources take turns: the first card of each source, then the second card of each, and so on, newest source first.
  - Hold-to-refresh asks for a batch that excludes every card already loaded.
  - If you follow nothing yet, the feed shows all published cards.
- **A3-6 Refresh hold time:** 1.5 seconds, set in one constant (`AppDurations.refreshHold`) so it is easy to tune.
- **A3-7 Media links** are signed URLs valid for 1 hour. Both buckets accept files up to 50 MB.
- **A3-8 Test login.**
  - The email is `agent@smartscrolling.test`. The agent generates the password in ticket 03.
  - Both are stored only in the gitignored `.env` and `.env.test.json`.
  - The button appears only in debug builds, and only when those values are present.
- **A3-9 Turning off the old invite check.** Today an Auth "before user created" hook calls `private.before_pilot_user`, which lets in only listed emails. Ticket 03 does three things:
  - turns that hook off in the Auth settings, as the owner approved on 2026-10-29 (D06);
  - then drops the function, `private.pilot_allowlist` and the then-empty `private` schema;
  - leaves every Google setting untouched.

  The Email provider is used only by the debug test login. The app shows only Google, and email confirmation stays on.
- **A3-10 Starter topics.** Ticket 03 uploads a small starter topic tree from `tools/content/topics.json`. The owner edits that file later.
- **A3-11 The two real sources** (the book and the paper) are moved with status `published`, so they appear in Explore. They have no cards yet.
- **A3-12 Undo in Library.** Removing a liked or saved card shows an Undo bar that restores it exactly, including its timetable, note and collections.
- **A3-13 Offline sizes** come from the old PRD §20.4. Downloads happen on Wi-Fi unless "use mobile data" is on.

  | Mode | Discover cards | Practice window | For later | Space cap |
  |---|---:|---:|---:|---|
  | Online only | 0 | 0 | 0 | nothing kept |
  | Light | 200 | 80 | 20 | 256 MB |
  | Standard (default) | 500 | 200 | 50 | 512 MB |
  | Extended | 1,000 | 400 | 100 | 1 GB |

  Audio and video together may use at most 20% of the space cap.
- **A3-14 Saving settings.** Settings are saved with plain table updates guarded by `revision`. A trigger raises `revision` on every save. A save that starts from an old revision changes nothing, and the app reloads. There is no separate receipts table.
- **A3-16 Packages** are pinned to exact versions in `pubspec.yaml` and listed in `docs/ARCHITECTURE.md`.

**Rule:** only the owner changes this section. New owner decisions are added here with their date.

## 12. Quality bar

- Quality checks run `dart format`, `flutter analyze`, and `flutter test` including the rule robot (`test/architecture_test.dart`), which checks the folder, widget and theme rules of `docs/ARCHITECTURE.md`.
- Accessibility basics:
  - text scaling from 1.0 to 1.8 without broken layouts;
  - screen-reader labels on every button and image;
  - tap targets of at least 48 px;
  - color is never the only signal (for example, right and wrong also show an icon and a word);
  - reduce motion turns animations off.
- Tests run on the Android emulator. iOS builds are optional and require a Mac.

## 13. Change log

- **v2.0 (2026-10-29):** replaces v1.3 and earlier preference drafts. All owner decisions are frozen in section 11.

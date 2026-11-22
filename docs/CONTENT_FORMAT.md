# How to make content

This is the recipe for putting your own sources and cards into SmartScrolling. You write one folder per source on your PC, then one command uploads it. The app picks it up with no code change.

A working example of everything below is the sample box in `tools/content/sample/` (five sample sources).

Regenerate the media fixtures with `python -m tools.content.sample.generate_media`.
It uses ffmpeg when installed, otherwise the butterfly clip from the official
[Flutter video recipe](https://docs.flutter.dev/cookbook/plugins/play-video),
as permitted by ticket 12. The script creates the tone with Python's `wave`,
and generates posters and `.vtt` captions for both cards. Upload only that sample
source with `python tools/content/upload.py tools/content/sample/sample-media`.
Flutter's asset repository identifies the butterfly clip as
[CC0](https://github.com/flutter/assets-for-api-docs#origin-of-third-party-content).

## The commands

Run them from the project folder. They read `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from `.env`.

| Command | What it does |
|---|---|
| `python tools/content/upload.py my-sources/happiness-advantage --dry-run` | Checks one source folder and says what would change. Uploads nothing. |
| `python tools/content/upload.py my-sources/happiness-advantage` | Checks, then uploads the source, its files and its cards. |
| `python tools/content/upload.py my-sources` | The same for every source folder inside `my-sources`. |
| `python tools/content/upload.py topics` | Uploads the topic tree in `tools/content/topics.json`. |
| `python tools/content/upload.py requests` | Lists your open to-dos: problems people reported and requests for more cards or tests. |
| `python tools/content/upload.py requests --done <id>` | Marks one to-do as done. |
| `python tools/content/upload.py purge-samples --dry-run` | Lists the sample sources. Without `--dry-run` it deletes them with all their cards and files. |

What the upload does:
- It checks everything first. If anything is wrong, it lists every problem and uploads nothing.
- Uploading the same folder again is safe. Unchanged cards are left alone; changed cards are updated and their version goes up (people's past answers remember the old version).
- A card or test you delete from `source.json` is not deleted online. It becomes **hidden**: it leaves the app but is kept. Real content is never deleted.
- At the end it prints a summary, such as `3 new cards, 1 updated, 0 hidden`.

## One folder per source

The folder name is the source id. Inside it: `source.json` and the source's files.

```
my-sources/
└── happiness-advantage/          ← folder name = source id
    ├── source.json               ← everything about the source and its cards
    ├── cover.jpg                 ← optional: the cover picture
    ├── original.pdf              ← optional: the original (.pdf, .epub, .html or .txt)
    ├── text.txt                  ← optional: the full text, extracted
    └── cards/
        └── tetris-diagram/       ← one folder per card that has files
            ├── image.webp
            ├── video.mp4
            ├── poster.jpg
            └── captions.vtt
```

You may name your files as you like; `source.json` says which file is which. The tool stores them online under fixed names:

To retain a file already attached online without a local copy, use an explicit reference, for example `"cover": {"existing": "sources/my-book/cover.jpg"}` or `"media": {"existing": "cards/my-book/diagram/image.png"}`. This works for all six file roles. The path must be the canonical path for that item and role, and must equal its currently attached database path; dry runs and uploads reject references to another item or a newly attached file. No file is uploaded for a reference. Omitting a file role still clears its path; omission does not preserve it.

| In `source.json` | Allowed endings | Stored online as |
|---|---|---|
| `cover` | .jpg .png .webp | `media/sources/<source id>/cover.jpg` |
| `original` | .pdf .epub .html .txt | `source-files/<source id>/original.pdf` |
| `text` | .txt | `source-files/<source id>/text.txt` |
| card `media` | image .webp .jpg .png · video .mp4 · audio .m4a .mp3 .wav | `media/cards/<card id>/image.webp` (or `video.mp4`, `audio.m4a`) |
| card `poster` | .jpg .png .webp | `media/cards/<card id>/poster.jpg` |
| card `captions` | .vtt | `media/cards/<card id>/captions.vtt` |

The app shows `media` files to signed-in people. Only the upload tool can read `source-files`. Each file may be up to 50 MB.

## Ids

- A source id is lowercase words joined by hyphens: `happiness-advantage`.
- A card id inside `source.json` is just the card's own name: `tetris-quote`. Online it becomes `happiness-advantage/tetris-quote`.
- To point at a card of another source (in `related` or `tests`), write the full id: `incepholorgb/hologram-basics`. That card must already be uploaded, or be in the same upload.
- Never reuse an id for something different: the id is how the app remembers likes and answers.

## `source.json`, field by field

Fields marked *required* must be there. Everything else may be left out.

### The source

| Field | Meaning |
|---|---|
| `id` *required* | The source id; must equal the folder name. |
| `kind` *required* | `book`, `paper`, `news` or `other` (websites and anything else). |
| `title` *required* | The title. |
| `authors` | A list of names: `["Shawn Achor"]`. |
| `published_on` | The date, as `2010-09-14`. |
| `language` | `en` (default). Cards use it unless they set their own. |
| `link` | The web address of the source. |
| `description` | One to three sentences for the source page. |
| `status` | `published` (default: shown in the app), `draft` (not shown yet) or `hidden` (taken out but kept). |
| `is_sample` | `true` only for test content. Never set it on real sources. |
| `topics` | Topic ids from `tools/content/topics.json`: `["psychology", "positive-psychology"]`. |
| `cover`, `original`, `text` | File names inside the folder (see above). |
| `book` | Only for books: `{"isbn": "9780307591562", "publisher": "Crown Business", "edition": "1st edition", "pages": 256}` |
| `paper` | Only for papers: `{"doi": "10.29026/oea.2025.250130", "journal": "Opto-Electronic Advances", "paper_status": "published"}`; `paper_status` is `preprint`, `published` (default) or `retracted`. |
| `news` | Only for news: `{"newspaper": "The Guardian", "show_until": "2026-12-31"}`. After `show_until` its cards leave Discover but stay in people's Library. |
| `discover_cards` | The list of Discover cards (below). |
| `practice_cards` | The list of tests (below). |

### A Discover card

| Field | Meaning |
|---|---|
| `id` *required* | The card's name inside the source: `tetris-quote`. |
| `format` *required* | `concept`, `quote`, `news`, `research`, `myth`, `image`, `video` or `audio`. |
| `title` *required* | A short title. |
| `front` *required* | What you see first. For a myth: the myth. |
| `back` | What you see after flipping. For a myth: the fact. |
| `location` | Where it is in the source: `Chapter 5, p. 112`. |
| `position` | Order on the source page. Default: its place in the list. |
| `level` | `intro`, `intermediate` or `advanced`. |
| `language` | Only if different from the source. |
| `speaker` | Who said it. Required for a `quote`. |
| `media` | The picture, video or audio file. Required for `image`, `video` and `audio`. |
| `media_alt` | What the picture or video shows, for people who cannot see it. Required for `image` and `video`. |
| `poster`, `captions` | Video thumbnail and subtitles (.vtt) for `video` and `audio`. |
| `transcript` | Everything said in the video or audio. |
| `duration_seconds` | Length of the video or audio. |
| `topics` | Extra topics for this card only, on top of the source's topics. |
| `related` | Other cards about the same idea ("see also"): `["tetris-concept", "other-source/card"]`. It works both ways, so list it on one side only. |
| `status` | As for the source. Default `published`. |

One example of every format:

```json
{"id": "tetris-effect", "format": "concept", "title": "The Tetris effect",
 "front": "What you practise a lot starts to shape how you see the world.",
 "back": "People who played hours of Tetris began to see falling blocks everywhere.",
 "location": "Chapter 5, p. 112", "level": "intro", "related": ["tetris-quote"]}

{"id": "tetris-quote", "format": "quote", "title": "Patterns",
 "front": "The brain gets stuck in a pattern it practises.", "speaker": "Shawn Achor"}

{"id": "ai-act-vote", "format": "news", "title": "The vote",
 "front": "Parliament approved the AI rules by a large majority."}

{"id": "gratitude-study", "format": "research", "title": "Three good things",
 "front": "Writing down three good things each night raised happiness for weeks.",
 "back": "The effect lasted longer than in the control group.", "level": "intermediate"}

{"id": "genius-myth", "format": "myth", "title": "Success first",
 "front": "You have to succeed first, then you will be happy.",
 "back": "Studies suggest it often works the other way round."}

{"id": "tetris-diagram", "format": "image", "title": "The effect in a picture",
 "front": "Practice reshapes attention.", "media": "cards/tetris-diagram/image.webp",
 "media_alt": "Falling blocks turning into everyday objects."}

{"id": "achor-talk", "format": "video", "title": "The talk",
 "front": "A 12-minute talk about happiness at work.", "media": "cards/achor-talk/video.mp4",
 "media_alt": "A speaker on a stage.", "poster": "cards/achor-talk/poster.jpg",
 "captions": "cards/achor-talk/captions.vtt", "transcript": "Hello…", "duration_seconds": 720}

{"id": "summary-audio", "format": "audio", "title": "Chapter 1 in 3 minutes",
 "front": "A short spoken summary.", "media": "cards/summary-audio/audio.m4a",
 "transcript": "In chapter one…", "duration_seconds": 180}
```

Rules the tool checks:
- a `news` card must belong to a `news` source;
- a `quote` needs a `speaker`;
- `image`, `video` and `audio` need a `media` file, and `image` and `video` need `media_alt`.

### A test (practice card)

Each test checks one or more Discover cards. When someone likes a card, the app tests them on it with the tests linked to it, at growing intervals. Give a card several tests so the questions change.

| Field | Meaning |
|---|---|
| `id` *required* | The test's name inside the source: `tetris-flash-1`. |
| `type` *required* | `flashcard`, `multiple_choice`, `true_false`, `ordering` or `matching`. |
| `prompt` *required* | The question, statement or instruction. |
| `tests` *required* | The Discover cards it checks: `["tetris-effect"]`. |
| `explanation` | Shown after the answer. |
| `status` | As for the source. Default `published`. |
| plus the fields of its type | See the examples. |

One example of every type:

```json
{"id": "tetris-flash-1", "type": "flashcard", "prompt": "What is the Tetris effect?",
 "answer": "What you practise a lot starts to shape how you see the world.", "tests": ["tetris-effect"]}

{"id": "tetris-choice", "type": "multiple_choice", "prompt": "What did heavy Tetris players report?",
 "choices": ["Better sleep", "Seeing falling blocks everywhere", "Faster typing"],
 "correct_choice": 1, "explanation": "0 is the first choice, 1 the second.", "tests": ["tetris-effect"]}

{"id": "success-true-false", "type": "true_false", "prompt": "Success always comes before happiness.",
 "is_true": false, "tests": ["genius-myth"]}

{"id": "study-steps", "type": "ordering", "prompt": "Put the steps of the study in order.",
 "correct_order": ["Ask the question", "Split into groups", "Run the test", "Compare"], "tests": ["gratitude-study"]}

{"id": "terms-match", "type": "matching", "prompt": "Match each idea with its meaning.",
 "match_left": ["Tetris effect", "Happiness advantage"],
 "match_right": ["Practice shapes perception", "A positive brain works better"], "tests": ["tetris-effect"]}
```

Rules for each type:
- a flashcard needs an `answer`;
- multiple choice needs 2 to 6 `choices` and a `correct_choice` that points at one of them (0 = the first);
- true/false needs `is_true`;
- ordering needs at least 2 items in the right order (the app shuffles them);
- matching needs at least 2 `match_left` items and the same number of `match_right` items in the same order (the app shuffles the right side).

## Topics

The topic tree is `tools/content/topics.json`: main areas and their sub-topics (two levels only). Edit it, then run `python tools/content/upload.py topics`. An area has either no sub-topics or 2 or more: one sub-topic alone is refused (use the area by itself). A main area you remove from the file stays online (the tool tells you) so that nothing pointing at it breaks. A sub-topic you remove is deleted once no source or card uses it, and everyone who followed or hid it gets the same choice on its main area.

```json
{"id": "psychology", "name": "Psychology", "position": 1}
{"id": "positive-psychology", "name": "Positive psychology", "parent": "psychology", "position": 1}
```

## Before you start: the sample box

The app is tested with the made-up sources in `tools/content/sample/`. When your own content is ready, remove them with:

```
python tools/content/upload.py purge-samples --dry-run
python tools/content/upload.py purge-samples
```

The first line only lists them. The second deletes them, with all their cards, tests, files and anything people did with them. It never touches a source without `is_sample: true`.

To redraw the sample pictures: `python tools/content/sample/draw_images.py`.

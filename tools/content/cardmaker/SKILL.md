---
name: make-cards
description: Turn a source text (book, paper, article, news) into SmartScrolling Discover cards and Practice tests that are true to the source, complete and understandable without it. Use for any request to create, add, fix or check cards or tests from a text.
---

# Make cards: the method

This folder is the single source of truth for how cards and tests are made. The automatic pipeline (`docs/CONTENT_PIPELINE.md`) loads the prompt files from here at run time, and an agent working by hand follows the same steps. Change card quality here, nowhere else.

It is plain files and plain prompts, so it works with any model: a subscription CLI, an API, OpenRouter or a local model.

## Why cheap models fail at this, and what stops each failure

"Here is a book, make cards" fails in known ways. Every step below exists to stop one of them.

| Failure | Cause | What stops it |
|---|---|---|
| Out of context | the model sees a slice of the book and does not know what "this", "he" or "the experiment" refer to | the **brief** (thesis, outline, glossary, people) goes into every call; each chunk also gets the end of the previous chunk |
| Says what the book does not say | nothing ties a card to a place in the text | **evidence first**: every idea must name its paragraphs and copy one sentence from them; code checks the copy exists; numbers and names in a card must exist in the text |
| The author's opponent becomes the author | the model reports a view the author only describes or attacks | every idea carries a **stance** (claims / reports / rejects); the judge checks it |
| Unfinished sentences | output cut by a length limit, or text trimmed by code | code **never cuts text**; a cut-off reply is a failed call; cards must end in a full stop; quotes are copied by code, not retyped by the model |
| Cards that make no sense alone | pronouns and book-only terms | banned openers and phrases (code), plus a **blind reader**: a model that sees only the card must understand it |
| Wrong subject or topic | title, text and topic drift apart | one idea per card; topics come only from the fixed list and are chosen once from the brief; the judge checks title against text |
| Broken tests | wrong answer key, two right answers, give-away choices | tests are written only from a card that already passed; a **blind solver** answers each test from the card alone and its answer must equal the key |

Two rules sit above all others:
1. **Dropping is free, wrong is expensive.** When a check fails twice the card is dropped and listed in the report. Nothing is ever "fixed up" by code.
2. **Small jobs.** No call does two jobs. Reading, choosing, writing, judging and testing are separate calls with small inputs.

## The steps

Input: `text.txt` (plain text, paragraphs separated by one blank line) and the source facts (kind, title, authors, date, link). Paragraphs are numbered `P1`, `P2`… over the whole text; the numbers never change.

| # | Step | Calls | Prompt | In | Out |
|---|---|---|---|---|---|
| 1 | chunk | code | none | text | chunks of whole paragraphs, 1,500–3,000 words, cut at chapter headings first |
| 2 | summarize | one per chunk | `prompts/summarize.md` | one chunk | summary, terms, people, and whether the chunk is real content |
| 3 | brief | one per source | `prompts/brief.md` | source facts + all summaries + the topic list | thesis, outline, glossary, people, description, topics |
| 4 | extract | one per content chunk | `prompts/extract.md` | brief + tail of previous chunk + the chunk with paragraph numbers | up to 6 ideas, each with paragraphs, an exact evidence sentence, stance, importance |
| 5 | evidence gate | code | none | ideas | ideas whose evidence sentence is really in the named paragraphs |
| 6 | select | one per source | `prompts/select.md` | brief + all surviving ideas (short form) + budget | chosen ideas, format and level; duplicates named |
| 7 | write | one per 4 ideas | `prompts/write.md` | brief + each idea + its paragraphs (and one before, one after) | one Discover card per idea |
| 8 | card gates | code | none | cards | cards that pass every code gate |
| 9 | judge | one per 4 cards | `prompts/judge.md` | card + its paragraphs + thesis + brief's glossary and people (for context only) | six yes/no answers and the problem |
| 10 | repair | once per failed card | `prompts/write.md` with the problems | as 7, plus the failed card and the problems | a new card, which goes through 8 and 9 again; second failure = dropped |
| 11 | quiz | one per 3 passed cards | `prompts/quiz.md` | the card only | 3 tests per card |
| 12 | solve | one per 3 cards | `prompts/solve.md` | the card and its tests without the answers | answers, and anything unclear in the card |
| 13 | test gates | code | none | tests + solver answers | tests whose key equals the solver's answer and pass the code gates |
| 14 | pack | code | none | everything | `source.json` as in `docs/CONTENT_FORMAT.md` |

Short sources (one chunk: an article, an abstract, a news item) skip steps 2 and 3. Their brief is the source facts plus the first 150 words of the text, and step 6 also chooses the topics.

The writer and the judge must be **different models** whenever two are available. The solver may be any model.

Counts are enforced by code, not by the prompt: at most 6 ideas per chunk (the lowest `importance` are removed), and at most the budget of chosen ideas in step 6 (same rule). Models miscount.

## The code gates (free, exact, run before any judge)

Text is compared after "normalising": lowercase, curly quotes to straight quotes, every dash to `-`, runs of spaces and line breaks to one space.

Evidence gate (step 5). An idea is dropped when:
- its `evidence_quote` does not appear in the text of its `paragraphs`;
- it is a `quote` idea and its `quote_text` does not appear there, or does not start at the beginning of a sentence and end at the end of one.

Card gates (step 8). A card fails when:
- `front` or `back` does not end with `.`, `!`, `?` or `…` (a closing quote or bracket may follow), or its brackets or double quotes are unbalanced;
- `front` is over 220 characters, `back` over 420, `title` over 60. Text is never cut: the card fails;
- `front` or `back` starts with This, That, These, Those, He, She, They, Such or Here, or contains "the author", "the book", "this book", "this chapter", "the chapter", "the passage", "the text", "as mentioned", "as we saw", "see above", "the above", "the following", or says what is not given, stated or reported ("the size is not given", "no number is given");
- a number in the card (digits, with or without `%`) does not appear in the idea's paragraphs;
- a name in the card (two or more capitalised words in a row, not at the start of a sentence) does not appear anywhere in `text.txt` or the source's author metadata; author metadata supports identity only, never a claim or number;
- a card that is not a quote shares 12 or more words in a row with `text.txt`;
- it shares over 80% of its words with another card's front;
- a topic is not in `tools/content/topics.json`;
- `upload.py`'s `validate()` rejects it.

Quote cards: code copies `quote_text` into `front` and the speaker into `speaker`. The model writes only the `title` and the `back`.

Test gates (step 13). A test fails when:
- the solver's answer differs from the key (multiple choice, true/false, ordering, matching);
- multiple choice: not exactly 4 choices, two choices equal, the right choice more than 1.6 times as long as the average of the others, or a choice is "all of the above" or "none of the above";
- the prompt contains a banned phrase from the card gates, or does not end with `?` or `.`;
- `validate()` rejects it.

Code shuffles the choices (and moves `correct_choice` with them) so the right answer has no favourite place. A card with fewer than 2 passing tests gets one more quiz call. If it then has no passing test at all, the card is dropped.

The blind reader (step 12) also lists anything in a card it cannot understand without the source. A card with an entry in that list is sent to repair (step 10) once.

Reply gates (every call)
- The reply must be complete JSON that matches the step's schema in `schemas.json`. A reply that was cut off (the provider reports a length stop, or the JSON does not close) is a failed call: retry once with half as many items, then fail.
- No text is ever shortened by code.

## Card rules (what the writer is told)

1. One idea per card. The title names that idea.
2. The front is the idea as one or two complete sentences. The back is the reason, the example or the evidence the source gives, as one to three complete sentences.
3. A reader who has never seen the source understands every word. Name people by full name and role the first time ("the doctor Ignaz Semmelweis"). Explain a special term in a few words or do not use it.
4. Say only what the paragraphs say. No extra facts, even true ones. Keep the source's limits ("in this study", "for beginners", "often").
5. Keep the stance. If the source reports someone else's view, name whose view it is. If the source rejects a belief, that is a `myth` card: front = the belief, back = what the source shows instead.
6. Your own words. Never copy a sentence. Only a `quote` card shows exact words, and code places them.
7. No "the author", "the book", "this chapter". The card is about the idea, not about the book.
8. Plain English, short words, no markdown, no lists, no emoji.

Formats made from text: `concept`, `myth`, `research` (question, method, result and limits in the back), `quote`, and `news` only for a news source.

## Pictures

A picture job has the collection's English description in `text.txt` and a checked JPEG, PNG or WebP under 50 MB in `meta.media.file`. It makes one `image` card with `prompts/image.md` and the `image` schema, using the existing `write` role. No image recognition or outside knowledge is used: `media_alt` describes only visual details the collection states. Short metadata is not subject to the long-text English word-ratio heuristic. The code gates check the alt text's names and numbers; the judge receives the alt text alongside the collection description. Repairs, quizzes and blind solving follow the ordinary card path. Packing checks the image's first bytes again and copies it as the card's `media` with `media_alt`.

## Test rules (what the quiz writer is told)

1. A test asks only what its card teaches. Someone who knows the card can answer it; nothing else is needed.
2. Three tests per card, one of each: `flashcard`, `multiple_choice`, `true_false`. Use `ordering` or `matching` in place of one of them only when the card itself lists 3 or more steps or pairs.
3. Each test asks about the idea in a different way (recall it, recognise it, apply it to a small case). Do not copy the card's sentences into the question.
4. Multiple choice: exactly 4 choices, one right, three wrong but believable, all about the same length and kind.
5. True/false: a false statement is a believable mistake, not the card with "not" added. About half of them false.
6. Every test has an `explanation` of one sentence that says why the right answer is right.

## Using it by hand (any agent)

1. Put the text in a folder as `text.txt` and write the source facts.
2. Do the steps in order with the prompt files. Save each step's JSON next to the text.
3. Run the gates with `py -3 -m tools.content.pipeline gates <folder>` (pipeline ticket 02 builds it).
4. Check the folder with `python tools/content/upload.py <folder> --dry-run`.

## Proving it works

`eval/` holds trap passages: short texts written to trigger each failure above, with a list of statements a correct run must never produce and facts it should find. `py -3 -m tools.content.pipeline eval --provider <name>` runs the whole method on them with one provider and prints a score. A provider may serve a role only after it passes (see "Qualifying a model" in `docs/CONTENT_PIPELINE.md`). Add a trap whenever a bad card reaches the app.

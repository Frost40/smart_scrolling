# The exam files

These files decide whether a model may do a job in the content pipeline (`docs/CONTENT_PIPELINE.md` section 9.5). Everything here is made up for testing: the people and studies in the trap texts do not exist. Never upload a trap text as a real source.

| File | Exam | Shape |
|---|---|---|
| `trap-<name>.txt` | make | A short text written to trigger the known failures. The first paragraph is the chapter heading; paragraphs are separated by one blank line and are numbered P1, P2… starting after the heading. |
| `trap-<name>.expect.json` | make | What a correct run on that text must and must not produce: `source` (facts for the run), `brief` (a ready brief, so the trap behaves like a chapter in the middle of a book), `traps` (notes for people), `forbidden_patterns` (regular expressions no published card or test may match, case ignored; a test's wrong answer choices are not checked, because they are meant to be believable mistakes), `allowed_numbers` (every number in a published card must be in this list), `must_not_say` (statements checked by the referee), `should_cover` (ideas, each with `any_of` words; an idea is covered when a published card contains one of them), `pass_rule` (the rule in words). |
| `judge-cases.json` | judge | `cases`: each has a `card`, the `paragraphs` it is judged against (numbers in `trap-attention.txt`) and `expect` (`pass` or `fail`). |
| `solve-cases.json` | solve | `cases`: each has a `card` and `tests`; a test has `id`, `type`, `prompt`, the fields the solver needs (`choices`, `items`, `left`, `right`) and `key` (the right answer, or `"unanswerable"`). |
| `choose-cases.json` | choose | `cases`: each has a `book`, the `options` (labels, numbered from 0 in the prompt) and `right` (a number, a list of acceptable numbers, or -1). |

How each exam is scored

- **make**: run the whole method on every trap text with the provider under test in the roles `extract`, `select`, `write` and `quiz` (and `summarize` and `brief` on the long trap, when there is one), with the best qualified judge and solver. Budget: 4 cards. Then, on the cards and tests that would be published:
  1. no text matches a `forbidden_patterns` entry (a test's wrong answer choices aside);
  2. every number in a card is in `allowed_numbers`;
  3. the referee (`prompts/referee.md`, run by the best qualified judge) answers `said: false` for every `must_not_say` statement;
  4. at least 2 of the `should_cover` ideas are covered (all of them when there are fewer than 3).
  The provider passes when every trap passes. A run that publishes no card at all fails.
- **judge**: no card with `expect: fail` is passed, and at most 1 card with `expect: pass` is rejected.
- **solve**: every `key` is matched, and every `"unanswerable"` test comes back with `answerable: false`.
- **choose**: every `right` is matched.

`first-run/` holds the throwaway scripts and the saved output of the first real runs (2026-11-11 and 2026-11-12). They show the exact prompt layouts that were tested and are the worked example for pipeline ticket 02. They are reference, not pipeline code: if you run one, it starts the model program in a `sandbox` folder next to itself (delete it afterwards) and spends real calls.

Add a trap whenever a bad card reaches the app: copy the passage (or write one like it), list what the bad card said under `must_not_say`, and run the exam again.

"""Offline checks of text.py, gates.py and cardmaker.py (run through test_pipeline)."""

from contextlib import closing
import copy
import importlib.util
import json
import os
from pathlib import Path
import random
import re
import shutil
import tempfile
import unittest
from unittest.mock import patch

from tools.content.pipeline import cardmaker, gates, llm, settings, store, text

DATA = Path(__file__).with_name("testdata")
TRAP = Path(__file__).resolve().parents[1] / "cardmaker" / "eval" / "trap-attention.txt"
TRAP_TEXT = TRAP.read_text(encoding="utf-8")
ANSWERS = json.loads((DATA / "trap_attention_answers.json").read_text(encoding="utf-8"))
_spec = importlib.util.spec_from_file_location("make_epub", DATA / "make_epub.py")
make_epub = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(make_epub)


class HomeTest(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.folder = Path(folder.name)
        env = patch.dict(os.environ, {"PIPELINE_HOME": str(self.folder)})
        env.start()
        self.addCleanup(env.stop)


class TextTests(HomeTest):
    def test_epub_reading_order_headings_and_trimming(self):
        blocks = text.epub_to_text(make_epub.make_epub(self.folder / "book.epub"))
        joined = " ".join(b["text"] for b in blocks)
        self.assertNotIn("alert", joined)
        self.assertNotIn("work.1", joined.replace(" ", ""))
        self.assertIn("Busy people overrate their work.", joined)
        heads = [b["text"] for b in blocks if b["heading"]]
        self.assertEqual(heads, ["THE BUSY MIND", "Chapter One", "The door", "Chapter Two", "The queue",
                                 "Chapter Three", "The bill", "Notes"])
        trimmed = text.trim(blocks)
        self.assertEqual(trimmed[0]["text"], "Chapter One")
        self.assertNotIn("Notes", [b["text"] for b in trimmed])
        self.assertNotIn("Copyright", " ".join(b["text"] for b in trimmed))
        paras = text.paragraphs(trimmed)
        self.assertEqual(paras[0]["heading"], "Chapter One: The door")
        self.assertEqual([p["n"] for p in paras], list(range(1, len(paras) + 1)))
        chunks = text.chunks(paras, 300, 700)
        self.assertEqual([c["heading"] for c in chunks if c["first"] in (1, 7, 13)],
                         ["Chapter One: The door", "Chapter Two: The queue", "Chapter Three: The bill"])
        covered = [n for c in chunks for n in range(c["first"], c["last"] + 1)]
        self.assertEqual(covered, [p["n"] for p in paras])  # whole paragraphs, none split or lost
        self.assertTrue(all(c["words"] <= 700 for c in chunks))
        self.assertEqual(text.epub_facts(self.folder / "book.epub")["title"], "The Busy Mind")

    def test_gutenberg_wrapper_and_plain_text_headings(self):
        raw = ("*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nCHAPTER I\n\nA line that\nwraps.\n\n"
               "Chapter 2. The second part\n\nThe end.\n\n*** END OF THE PROJECT GUTENBERG EBOOK X ***\n\nLicense.")
        blocks = text.trim(text.text_to_blocks(raw))
        self.assertEqual([(b["text"], b["heading"]) for b in blocks],
                         [("CHAPTER I", True), ("A line that wraps.", False),
                          ("Chapter 2. The second part", True), ("The end.", False)])
        self.assertFalse(text.is_heading_line("Chapter four ends with a stop."))
        self.assertTrue(all(text.CHAPTER.match(t) for t in ("XIV. The end", "iv", "Chapter 2", "Part One", "12 Rules")))
        self.assertFalse(any(text.CHAPTER.match(t) for t in ("Civil War", "Partial views", "Booklet", "Mix")))
        stacked = [{"text": t, "heading": True} for t in ("A Title", "by", "Arnold Bennett", "PREFACE", "I", "THE DAILY MIRACLE")]
        paras = text.paragraphs(stacked[:4] + [{"text": "One.", "heading": False}] + stacked[4:] + [{"text": "Two.", "heading": False}])
        self.assertEqual([p["heading"] for p in paras], ["PREFACE", "I: THE DAILY MIRACLE"])

    def test_pdf_lines_hyphens_headers_and_scans(self):
        body = " ".join(["word"] * 120)
        page1 = f"   THE BUSY MIND\n\nThe first paragraph talks about an experi-\nment that ran {body}\nand it goes on\n\n   1\n"
        page2 = f"   THE BUSY MIND\n\nacross the page break.\n\nA second paragraph {body}.\n\n   2\n"
        blocks = text.pdf_pages_to_blocks(page1 + "\f" + page2)
        self.assertEqual(len(blocks), 2)
        self.assertIn("an experiment that ran", blocks[0]["text"])
        self.assertTrue(blocks[0]["text"].endswith("and it goes on across the page break."))
        self.assertNotIn("BUSY", " ".join(b["text"] for b in blocks))
        with self.assertRaisesRegex(ValueError, "scanned PDF"):
            text.pdf_pages_to_blocks("12\f13\f")

    def test_english(self):
        self.assertTrue(text.is_english("The people who did both at once rated their own work higher than the others."))
        self.assertFalse(text.is_english("Le persone che facevano due lavori insieme giudicavano meglio il proprio lavoro."))


GOOD = {"format": "research", "title": "Doing two jobs at once", "level": "intro",
        "front": "Adults who did two office tasks at once took much longer and made far more errors.",
        "back": "In 2009 the researcher Marta Ruiz tested 212 adult office workers, and the group doing both jobs "
                "together needed 40 percent more time."}
TOPICS = gates.known_topics()


class GateTests(unittest.TestCase):
    def check(self, card, paragraphs=TRAP_TEXT, others=()):
        return gates.card_gates(card, None, paragraphs, TRAP_TEXT, list(others), TOPICS)

    def test_evidence_gate(self):
        paras = {p["n"]: p["text"] for p in text.paragraphs(text.text_to_blocks(TRAP_TEXT))}
        good = {"paragraphs": ["P2"], "evidence_quote": "The second group took 40 percent longer to finish and made about twice as many errors.", "kind": "concept"}
        self.assertEqual(gates.evidence_gate(good, paras), [])
        self.assertIn("not in its paragraphs", gates.evidence_gate({**good, "paragraphs": ["P3"]}, paras)[0])
        self.assertIn("outside", gates.evidence_gate({**good, "paragraphs": ["P9"]}, paras)[0])
        quote = {**good, "paragraphs": ["P5"], "kind": "quote", "evidence_quote": "To do two things at once is to do neither.",
                 "quote_text": "To do two things at once is to do neither."}
        self.assertEqual(gates.evidence_gate(quote, paras), [])
        self.assertIn("whole sentence", gates.evidence_gate({**quote, "quote_text": "two things at once is to do neither."}, paras)[0])
        self.assertIn("quote is not", gates.evidence_gate({**quote, "quote_text": "Two things are one."}, paras)[0])

    def test_source_author_metadata_supports_names_only(self):
        card = {**GOOD, "back": "The psychologist William James explained how attention affects learning."}
        self.assertIn("name 'William James'", " ".join(self.check(card)))
        self.assertEqual(gates.card_gates(card, None, TRAP_TEXT, TRAP_TEXT, authors=["William James"]), [])
        unknown = {**card, "back": card["back"].replace("William James", "Anna Berg")}
        self.assertIn("name 'Anna Berg'", " ".join(gates.card_gates(
            unknown, None, TRAP_TEXT, TRAP_TEXT, authors=["William James"])))
        silent = {**GOOD, "back": GOOD["back"] + " The size of the room is not given."}
        self.assertIn("'is not given'", " ".join(self.check(silent)))
        self.assertIn("no number is given", " ".join(self.check({**GOOD, "back": GOOD["back"] + " No number is given for the force."})))
        numbered = {**card, "back": card["back"] + " It took 999 days."}
        self.assertIn("number 999", " ".join(gates.card_gates(
            numbered, None, TRAP_TEXT, TRAP_TEXT, authors=["William James 999"])))

    def test_every_card_gate(self):
        self.assertEqual(self.check(GOOD), [])
        cases = [
            ({"front": GOOD["front"][:-1]}, "does not end a sentence"),
            ({"front": "Adults (who did two tasks took longer."}, "unbalanced"),
            ({"front": "Adults " + "a" * 220 + "."}, "front is over 220"),
            ({"back": "Adults " + "a" * 420 + "."}, "back is over 420"),
            ({"title": "T" * 61}, "title is over 60"),
            ({"front": "They took much longer and made far more errors."}, "starts with 'They'"),
            ({"back": "As we saw, adults took much longer."}, "'as we saw'"),
            ({"back": "The researcher Marta Ruiz tested 300 office workers."}, "number 300"),
            ({"back": "The researcher Anna Berg tested adult office workers."}, "name 'Anna Berg'"),
            ({"back": "Half did the jobs one after the other, the other half did both at once."}, "12 or more words"),
            ({"topics": ["made-up-topic"]}, "unknown topic"),
            ({"level": "expert"}, "level must be"),
        ]
        for change, problem in cases:
            with self.subTest(problem=problem):
                found = self.check({**GOOD, **change})
                self.assertTrue(any(problem in p for p in found), found)
                if problem != "'as we saw'":
                    # Repair prompts quote these messages: they must not teach a banned phrase.
                    self.assertFalse(gates.PHRASE.search(gates.normalise(" ".join(found))), found)
        repeat = {**GOOD, "title": "Other"}
        self.assertIn("repeats", " ".join(self.check(repeat, others=[GOOD])))
        quote = {**GOOD, "format": "quote", "speaker": "Publilius Syrus", "front": "To do two things at once is to do neither."}
        self.assertEqual(gates.card_gates(quote, {"quote_text": quote["front"]}, TRAP_TEXT, TRAP_TEXT, [], TOPICS), [])
        self.assertIn("quote front", " ".join(gates.card_gates(quote, {"quote_text": "Other."}, TRAP_TEXT, TRAP_TEXT, [], TOPICS)))

    def test_judge_case_cards_that_code_can_catch(self):
        cases = json.loads((TRAP.with_name("judge-cases.json")).read_text(encoding="utf-8"))["cases"]
        by_title = {c["card"]["title"] + c["expect"]: c["card"] for c in cases}
        self.assertTrue(self.check(by_title["Music helps desk workfail"]))
        self.assertTrue(self.check(by_title["The hidden switch costfail"]))
        self.assertEqual(self.check(by_title["The hidden switch costpass"]), [])

    def test_every_test_gate(self):
        mc = {"type": "multiple_choice", "prompt": "Which group took longer?", "choices": ["The pairs", "The singles",
              "The judges", "The coaches"], "correct_choice": 0, "explanation": "x."}
        right = {"answerable": True, "choice": 0, "is_true": False, "order": [], "pairs": [], "text": ""}
        self.assertEqual(gates.test_gates(mc, right, TOPICS), [])
        self.assertEqual(gates.test_gates(mc, None, TOPICS), [])
        tf = {"type": "true_false", "prompt": "Pairs were faster.", "is_true": False}
        order = {"type": "ordering", "prompt": "Order the steps.", "correct_order": ["a", "b", "c"]}
        match = {"type": "matching", "prompt": "Match them.", "match_left": ["a", "b"], "match_right": ["1", "2"]}
        cases = [
            (mc, {**right, "choice": 2}, "chose another"),
            (mc, {**right, "answerable": False}, "could not answer"),
            (tf, {**right, "is_true": True}, "other answer"),
            (order, {**right, "order": ["b", "a", "c"]}, "ordered it differently"),
            (match, {**right, "pairs": ["2", "1"]}, "matched it differently"),
            ({**mc, "choices": mc["choices"][:3]}, right, "exactly 4"),
            ({**mc, "choices": ["The pairs", "the pairs", "x", "y"]}, right, "same"),
            ({**mc, "choices": ["The pairs who did both jobs at the very same time", "No", "Yes", "Both"]}, right, "much longer"),
            ({**mc, "choices": ["The pairs", "The singles", "All of the above", "x"]}, right, "all of the above"),
            ({**mc, "prompt": "What does the text say?"}, right, "'the text'"),
            ({**mc, "prompt": "Which group took longer"}, right, "does not end"),
            ({"type": "flashcard", "prompt": "Why?"}, right, "needs an answer"),
        ]
        for test, answer, problem in cases:
            with self.subTest(problem=problem):
                found = gates.test_gates(test, answer, TOPICS)
                self.assertTrue(any(problem in p for p in found), found)
        self.assertEqual(gates.test_gates(order, {**right, "order": ["a", "b", "c"]}, TOPICS), [])
        self.assertEqual(gates.test_gates(match, {**right, "pairs": ["1", "2"]}, TOPICS), [])

    def test_gates_folder_command(self):
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root) / "hand-made"
            folder.mkdir()
            (folder / "text.txt").write_text(TRAP_TEXT, encoding="utf-8")
            source = {"id": "hand-made", "kind": "book", "title": "Hand made", "topics": ["psychology"],
                      "discover_cards": [{**GOOD, "id": "two-jobs"}, {**GOOD, "id": "bad", "front": "They were slow"}],
                      "practice_cards": [{"id": "q", "type": "true_false", "prompt": "Pairs were faster.",
                                          "is_true": False, "tests": ["two-jobs"]}]}
            (folder / "source.json").write_text(json.dumps(source), encoding="utf-8")
            found = gates.check_folder(folder)
        self.assertEqual(found["two-jobs"], [])
        self.assertEqual(found["q"], [])
        self.assertTrue(found["bad"])


class FakeModel:
    """Stands in for llm.run_provider: answers each step from saved answers, per ref."""

    def __init__(self, answers):
        self.a, self.steps, self.judged, self.cut, self.unclear_done = answers, [], {}, True, False

    def __call__(self, name, system, user, schema, *, _role="", _job_id=None, _step="pipeline"):
        refs = re.findall(r"^(?:Idea ref|Card ref|ref:) (\S+)$", user, re.M)
        self.steps.append((_step, refs))
        if _step == "write" and self.cut and len(refs) > 2:
            self.cut = False
            return {"ok": False, "data": None, "error_kind": "cut", "error": "max_tokens", "seconds": 0,
                    "tokens_in": 0, "tokens_out": 0}
        data = getattr(self, _step)(user, refs)
        problems = llm.check(data, schema)
        assert not problems, problems
        return {"ok": True, "data": data, "error_kind": "", "error": "", "seconds": 0.1, "tokens_in": 10, "tokens_out": 5}

    def extract(self, user, refs):
        return copy.deepcopy(self.a["extract"])

    def select(self, user, refs):
        return copy.deepcopy(self.a["select"])

    def write(self, user, refs):
        table = self.a["repair_unclear"] if "could not understand" in user else             self.a["repair"] if cardmaker.REPAIR_HEAD in user else self.a["write"]
        return {"cards": [{"ref": r, **table[r]} for r in refs if r in table]}

    def judge(self, user, refs):
        out = []
        for ref in refs:
            first = ref in self.a["judge"] and not self.judged.get(ref)
            table = self.a["judge"] if first or ref not in self.a["judge_repair"] else self.a["judge_repair"]
            self.judged[ref] = True
            out.append({"ref": ref, "notes": "checked", **table[ref]})
        return {"verdicts": out}

    def quiz(self, user, refs):
        empty = {"answer": "", "choices": [], "correct_choice": 0, "is_true": False, "correct_order": [],
                 "match_left": [], "match_right": []}
        return {"tests": [{**empty, **t, "card": ref} for ref in refs for t in self.a["quiz"][ref]]}

    def solve(self, user, refs):
        answers = []
        for block in re.findall(r"<test>\n(.*?)</test>", user, re.S):
            test_id = re.search(r"^id: (.+)$", block, re.M)[1]
            kind = re.search(r"^type: (.+)$", block, re.M)[1]
            saved = next(t for t in self.a["quiz"][test_id.split("-")[0]] if t["type"] == kind)
            answer = {"test": test_id, "answerable": True, "choice": 0, "is_true": False, "order": [], "pairs": [], "text": ""}
            if kind == "multiple_choice":
                shown = json.loads(re.search(r"^choices: (.+)$", block, re.M)[1])
                answer["choice"] = (shown.index(saved["choices"][saved["correct_choice"]])
                                    + (test_id in self.a["solve_wrong"])) % len(shown)
            elif kind == "true_false":
                answer["is_true"] = saved["is_true"] != (test_id in self.a["solve_wrong"])
            else:
                answer["text"] = saved["answer"]
            answers.append(answer)
        unclear = [{"ref": r, "words": w} for r, w in self.a["solve_unclear"].items() if r in refs and not self.unclear_done]
        self.unclear_done = self.unclear_done or bool(unclear)
        return {"unclear": unclear, "answers": answers}


class CardmakerTests(HomeTest):
    def setUp(self):
        super().setUp()
        (self.folder / "settings.json").write_text(json.dumps({
            "quality": {"require_qualified": False, "min_cards": {"book": 2}},
            "make": {"cards": {"book": {"per_words": 100, "min": 1, "max": 4}}}}), encoding="utf-8")
        self.model = FakeModel(ANSWERS)
        for patcher in (patch.object(llm, "run_provider", self.model),
                        patch.object(text, "book_facts", lambda meta, folder: meta)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def add(self):
        return cardmaker.add(TRAP, sample=True, title="The Busy Mind (made-up test text)", author="Test Author")

    def test_second_run_on_the_same_job_is_refused(self):
        # Two runs on one golden book overwrote each other's step files and packed dropped cards.
        job_id = self.add()
        with cardmaker.lock(self.folder / "jobs" / job_id):
            with self.assertRaisesRegex(ValueError, "already being made"):
                cardmaker.run(job_id)
        self.assertEqual(cardmaker.run(job_id), "ready")  # released: the next run may go ahead

    def test_full_run_on_trap_text(self):
        job_id = self.add()
        self.assertEqual(job_id, "trial-the-busy-mind-made-up-test-text")
        job = self.folder / "jobs" / job_id
        report = json.loads((job / "report.json").read_text(encoding="utf-8"))
        self.assertEqual(report["status"], "ready", report)
        for name in ("text.txt", "paragraphs.json", "chunks.json", "brief.json", "ideas/01.json", "ideas.json",
                     "selection.json", "cards/01.json", "gates.json", "verdicts/01.json", "repairs/01.json",
                     "verdicts/r01.json", "tests/01.json", "solved/01.json", "report.json"):
            self.assertTrue((job / name).exists(), name)
        self.assertFalse((job / "summaries").exists())  # one chunk: a short source
        # Counts enforced by code: 7 ideas → 6 per part; budget 4 of the 5 chosen.
        reasons = {d["ref"]: d["reason"] for d in report["dropped"]["ideas"]}
        self.assertIn("over the limit of 6", reasons["01:7"])
        self.assertIn("evidence sentence", reasons["01:6"])
        self.assertIn("over the card budget of 4", reasons["01:5"])
        # The cut batch of 4 was sent again as two halves of 2.
        writes = [refs for step, refs in self.model.steps if step == "write"]
        self.assertEqual(writes[:3], [["01:1", "01:2", "01:3", "01:4"], ["01:1", "01:2"], ["01:3", "01:4"]])
        self.assertEqual(len(json.loads((job / "cards" / "01.json").read_text(encoding="utf-8"))["cards"]), 4)
        # 01:2 failed a code gate and was repaired; 01:4 failed the judge twice and was dropped.
        cards = {d["ref"]: d["reason"] for d in report["dropped"]["cards"]}
        self.assertIn("failed again after repair", cards["01:4"])
        self.assertTrue({"01:3-tf", "01:3-choice"} <= {d["ref"] for d in report["dropped"]["tests"]})
        # 01:3 kept one test, so it got the one extra quiz, with its earlier tests listed.
        extra = json.loads((job / "tests" / "x01.json").read_text(encoding="utf-8"))
        self.assertEqual({t["card"] for t in extra["tests"]}, {"01:3"})
        self.assertEqual(report["pass_rate"], 0.75)
        source_dir = job / "source" / job_id
        source = json.loads((source_dir / "source.json").read_text(encoding="utf-8"))
        self.assertTrue(source["is_sample"])
        self.assertEqual(source["status"], "draft")
        self.assertEqual(source["topics"], ["psychology"])
        self.assertEqual([c["id"] for c in source["discover_cards"]],
                         ["multitasking-as-brain-training-myth", "two-jobs-together-slowed-work", "switch-cost-paid-unnoticed"])
        self.assertEqual(source["discover_cards"][1]["front"], ANSWERS["repair"]["01:2"]["front"])
        # 01:1 was unclear to the blind reader: repaired once and quizzed again; its kept tests start at no suffix.
        self.assertEqual(source["discover_cards"][0]["back"], ANSWERS["repair_unclear"]["01:1"]["back"])
        self.assertTrue((job / "repairs" / "u01.json").exists() and (job / "solved" / "u01.json").exists())
        self.assertIn("multitasking-as-brain-training-myth-choice", {t["id"] for t in source["practice_cards"]})
        self.assertEqual(sorted(t["id"] for t in source["practice_cards"] if t["tests"] == ["multitasking-as-brain-training-myth"]),
                         [f"multitasking-as-brain-training-myth-{s}" for s in ("choice", "flash", "tf")])
        self.assertIn("switch-cost-paid-unnoticed-flash-2", {t["id"] for t in source["practice_cards"]})
        self.assertEqual({c["location"] for c in source["discover_cards"]}, {"Chapter 4. The Myth of the Busy Mind"})
        self.assertEqual(len(source["practice_cards"]), 9)
        choice = next(t for t in source["practice_cards"] if t["id"] == "switch-cost-paid-unnoticed-choice")
        saved = ANSWERS["quiz"]["01:3"][1]
        order = list(range(4))
        random.Random("01:3-choice-2").shuffle(order)  # the kept choice test came from the extra quiz
        self.assertEqual(choice["choices"], [saved["choices"][i] for i in order])
        self.assertEqual(choice["choices"][choice["correct_choice"]], saved["choices"][saved["correct_choice"]])
        self.assertEqual(choice["tests"], ["switch-cost-paid-unnoticed"])
        gates.upload.validate([(str(source_dir), source)], TOPICS, check_files=True)
        with closing(store.connect()) as db:
            self.assertEqual(db.execute("SELECT status FROM jobs").fetchone()[0], "ready")

    def test_redone_step_never_reuses_an_answer_to_other_input(self):
        job = self.folder / "jobs" / self.add()
        judged = sum(1 for s, refs in self.model.steps if s == "judge" and "01:3" in refs)
        (job / "cards" / "01.json").unlink()
        shutil.rmtree(job / "source")
        self.model.a = copy.deepcopy(ANSWERS)
        self.model.a["write"]["01:3"]["back"] = ("The researcher Marta Ruiz called this hidden price the switch cost. "
                                                 "People switch quickly, but every switch still takes time and adds errors.")
        self.add()
        self.assertGreater(sum(1 for s, refs in self.model.steps if s == "judge" and "01:3" in refs), judged)
        source = json.loads((job / "source" / job.name / "source.json").read_text(encoding="utf-8"))
        self.assertIn(self.model.a["write"]["01:3"]["back"], [c["back"] for c in source["discover_cards"]])

    def test_steps_with_files_are_skipped_and_tmp_is_ignored(self):
        job_id = cardmaker.slug("trial-the-busy-mind-made-up-test-text")
        job = self.folder / "jobs" / job_id
        (job / "ideas").mkdir(parents=True)
        (job / "ideas" / "01.tmp").write_text("half a file", encoding="utf-8")
        selection = copy.deepcopy(ANSWERS["select"])
        selection["chosen"] = [selection["chosen"][0], selection["chosen"][2]]
        (job / "selection.json").write_text(json.dumps(selection), encoding="utf-8")
        self.add()
        steps = [s for s, _ in self.model.steps]
        self.assertIn("extract", steps)
        self.assertNotIn("select", steps)
        source = json.loads((job / "source" / job_id / "source.json").read_text(encoding="utf-8"))
        self.assertEqual([c["id"] for c in source["discover_cards"]],
                         ["multitasking-as-brain-training-myth", "switch-cost-paid-unnoticed"])
        before = len(self.model.steps)
        self.assertEqual(self.add(), job_id)  # the same file resumes the same job, and nothing is asked again
        self.assertEqual(len(self.model.steps), before)


if __name__ == "__main__":
    unittest.main()

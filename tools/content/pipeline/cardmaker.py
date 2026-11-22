"""The card method as a program: the steps of tools/content/cardmaker/SKILL.md on one job folder.

Engine rules (design 10.2): a step runs only when its output file is missing; files are written as
<name>.tmp and renamed; a run stops cleanly between model calls when its time is up.
"""

from contextlib import closing
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import random
import re
import shutil
import time

from . import gates, licenses, llm, settings, store, text

SIX = ("supported", "faithful", "standalone", "complete", "one_idea", "worth")
SUFFIX = {"flashcard": "flash", "multiple_choice": "choice", "true_false": "tf", "ordering": "order", "matching": "match"}
TYPE_FIELDS = {"flashcard": ("answer",), "multiple_choice": ("choices", "correct_choice"), "true_false": ("is_true",),
               "ordering": ("correct_order",), "matching": ("match_left", "match_right")}
REPAIR_HEAD = "These cards were rejected. Write each one again and fix the problem named."


class Stop(Exception):
    """The run ends here. The job keeps its files and continues at the same step next time."""

    def __init__(self, status, error="", kind=""):
        super().__init__(error)
        self.status, self.error, self.kind = status, error, kind


def now():
    return dt.datetime.now().astimezone().isoformat()


def slug(title, limit=60):
    value = re.sub(r"[^a-z0-9]+", "-", (title or "").lower()).strip("-")
    if len(value) > limit:
        value = value[:limit].rsplit("-", 1)[0] if "-" in value[:limit] else value[:limit]
    return value or "card"


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_file(path, content):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)


def save(path, data):
    write_file(path, json.dumps(data, indent=2, ensure_ascii=False))


def digest(values):
    return hashlib.sha256(json.dumps(values, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()[:16]


def step(path, make, key=None):
    """Run `make` only when the step's file is missing (a .tmp file does not count).
    A model answer keeps the hash of its input as "_input": when an earlier step was redone and the
    input changed, the old answer is not reused. Files without the mark are trusted."""
    if Path(path).exists():
        data = load(path)
        if key is None or data.get("_input", key) == key:
            return data
    data = make()
    if key is not None:
        data["_input"] = key
    save(path, data)
    return data


def none(lines):
    return "\n".join(lines) or "(none)"


class Job:
    def __init__(self, job_id, deadline=None, folder=None):
        self.id = job_id
        self.folder = Path(folder) if folder is not None else settings.home() / "jobs" / job_id
        self.meta = load(self.folder / "meta.json")
        self.config = settings.load()
        self.deadline = deadline
        self.topics = gates.known_topics()
        self.counts, self.gates = {}, {"cards": {}, "tests": {}}
        self.dropped = {"ideas": [], "cards": [], "tests": []}
        self.step = ""

    # ------------------------------------------------------------ helpers

    def count(self, name, n_in, n_out):
        old = self.counts.get(name, {"in": 0, "out": 0})
        self.counts[name] = {"in": old["in"] + n_in, "out": old["out"] + n_out}

    def drop(self, kind, item, reason):
        self.dropped[kind].append({"ref": item.get("ref") or item.get("id"), "title": item.get("title") or
                                   item.get("prompt", ""), "reason": reason})

    def ask(self, role, name, values, avoid_family=None):
        if self.deadline and time.monotonic() > self.deadline:
            raise Stop("queued", "time is up")
        self.step = name
        result = llm.call(role, name, values, job_id=self.id, avoid_family=avoid_family)
        if not result["ok"]:
            raise Stop("waiting", f"{name}: {result['error']}", result["error_kind"])
        return result

    def batches(self, sub, prefix, items, size, role, name, values, avoid=None):
        """One call per batch, each saved as <sub>/<prefix>NN.json with the provider that answered."""
        out = []
        for start in range(0, len(items), size):
            batch = items[start:start + size]
            given, family = values(batch), avoid(batch) if avoid else None

            def make(given=given, family=family):
                result = self.ask(role, name, given, family)
                return {"provider": result.get("provider", ""), **result["data"]}
            out.append((batch, step(self.folder / sub / f"{prefix}{start // size + 1:02}.json", make, digest(given))))
        return out

    def family(self, provider):
        return self.config["providers"].get(provider, {}).get("family")

    def source_values(self):
        return {"title": self.meta["title"], "authors": ", ".join(self.meta.get("authors") or []) or "unknown",
                "kind": self.meta["kind"]}

    def context(self, idea):
        """The idea's paragraphs plus one before and one after: what the writer and the judge see."""
        numbers = sorted({n for n in gates._refs(idea) if n})
        return [self.paras[n] for n in range(max(1, numbers[0] - 1), numbers[-1] + 2) if n in self.paras]


# ---------------------------------------------------------------- steps 1 to 6

def prepare(job):
    """Before the method: from file to text, numbered paragraphs and chunks (design 10.3)."""
    folder = job.folder
    if not (folder / "paragraphs.json").exists():
        job.step = "text"
        original = next(folder.glob("original.*"), None)
        if original is None and not (folder / 'text.txt').exists():
            raise Stop("failed", "no original file")
        try:
            if (folder / 'text.txt').exists():
                raw = blocks = text.text_to_blocks((folder / 'text.txt').read_text(encoding='utf-8'))
            else:
                raw = text.file_to_blocks(original)
                blocks = text.trim(raw)
        except Exception as exc:  # an untrusted file: any reading error fails the job with its message
            raise Stop("failed", f"cannot read the file: {exc}") from exc
        if job.meta.get("origin") == "telegram":
            wrong_book(job, raw, original)
        paras = text.paragraphs(blocks)
        if not paras or (not job.meta.get('media') and not text.is_english(" ".join(p["text"] for p in paras))):
            raise Stop("failed", "not English")
        write_file(folder / "text.txt", "\n\n".join(b["text"] for b in blocks) + "\n")
        if job.meta["kind"] == "book":
            job.meta = text.book_facts(job.meta, folder)
            save(folder / "meta.json", job.meta)
        save(folder / "paragraphs.json", paras)
    paras = load(folder / "paragraphs.json")
    job.paras = {p["n"]: p["text"] for p in paras}
    job.heading_above, heading = {}, ""
    for p in paras:
        heading = job.heading_above[p["n"]] = p.get("heading", heading)
    job.full = (folder / "text.txt").read_text(encoding="utf-8")
    job.chunks = step(folder / "chunks.json", lambda: text.chunks(paras, *job.config["make"]["chunk_words"]))
    job.count("chunk", len(paras), len(job.chunks))


def wrong_book(job, blocks, original):
    """Design 7.2 step 10. A wrong download is dropped and its book goes back to the wish list,
    remembering the option that was taken so it is not taken again."""
    from . import fetch_telegram
    facts = text.epub_facts(original) if original.suffix == ".epub" else {}
    if fetch_telegram.right_book(job.meta, blocks, facts):
        return
    original.unlink()
    with closing(store.connect()) as db, db:
        db.execute("UPDATE books SET status='wanted', attempts=coalesce(attempts,0)+1, last_error=?, job_id=NULL, "
                   "updated_at=? WHERE id=?", ("wrong book: " + job.meta.get("taken", ""), now(), job.meta.get("book_id")))
    raise Stop("failed", f"wrong book: {job.meta.get('taken', '')}")


def chunk_text(job, chunk, numbered=False):
    numbers = range(chunk["first"], chunk["last"] + 1)
    return "\n\n".join((f"[P{n}] " if numbered else "") + job.paras[n] for n in numbers)


def summarize(job):
    """Step 2. None for a short source. With max_chunks, stops once that many content chunks are found."""
    if len(job.chunks) == 1:
        return None
    limit, out = job.meta.get("max_chunks"), []
    for chunk in job.chunks:
        if limit and sum(s["content"] for _, s in out) >= limit:
            break
        values = {**job.source_values(), "chunk_number": chunk["n"], "chunk_count": len(job.chunks),
                  "heading": chunk["heading"] or "(none)", "chunk_text": chunk_text(job, chunk)}
        out.append((chunk, step(job.folder / "summaries" / f"{chunk['n']:02}.json",
                                lambda values=values: job.ask("summarize", "summarize", values)["data"], digest(values))))
    job.count("summarize", len(out), sum(s["content"] for _, s in out))
    return out


def topic_list(job):
    topics = json.loads(gates.TOPICS.read_text(encoding="utf-8"))
    return "\n".join(f"{t['id']}: {t['name']}" for t in topics)


def make_brief(job, summaries):
    """Step 3, or the short-source brief: the first 150 words stand in for the thesis."""
    if summaries is None:
        words = " ".join(job.paras[n] for n in sorted(job.paras)).split()[:150]
        return step(job.folder / "brief.json", lambda: {
            "thesis": " ".join(words), "outline": [], "glossary": [], "people": [], "description": "",
            "topics": [], "new_topic": ""})
    notes = []
    for chunk, s in summaries:
        notes.append(f"Part {chunk['n']} of {len(job.chunks)}. Heading: {chunk['heading'] or '(none)'}. "
                     f"Content: {'yes' if s['content'] else 'no'}\n{s['summary']}\n"
                     f"Terms: {'; '.join(t['term'] + ': ' + t['meaning'] for t in s['terms']) or '(none)'}\n"
                     f"People: {'; '.join(p['name'] + ': ' + p['role'] for p in s['people']) or '(none)'}")
    values = {**job.source_values(), "published_on": job.meta.get("published_on") or job.meta.get("year") or "unknown",
              "topic_list": topic_list(job), "summaries": "\n\n".join(notes)}
    job.step = "brief"
    return step(job.folder / "brief.json", lambda: job.ask("brief", "brief", values)["data"], digest(values))


def brief_values(brief):
    return {"thesis": brief["thesis"],
            "outline": none(f"{o['part']}. {o['heading']}: {o['gist']}" for o in brief["outline"]),
            "glossary": none(f"{g['term']}: {g['meaning']}" for g in brief["glossary"]),
            "people": none(f"{p['name']}: {p['role']}" for p in brief["people"])}


def by_importance(items, limit):
    """The `limit` most important items; ties keep the earlier one; order is kept."""
    keep = set(sorted(range(len(items)), key=lambda i: -items[i].get("importance", 0))[:limit])
    return [item for i, item in enumerate(items) if i in keep], [item for i, item in enumerate(items) if i not in keep]


def extract(job, brief, summaries):
    """Steps 4 and 5: ideas per content chunk, the count cap, then the evidence gate."""
    content = job.chunks if summaries is None else [c for c, s in summaries if s["content"]]
    if job.meta.get("max_chunks"):
        content = content[:job.meta["max_chunks"]]
    job.words_read = sum(c["words"] for c in content)
    kept = []
    for chunk in content:
        previous = job.chunks[chunk["n"] - 2] if chunk["n"] > 1 else None
        tail = " ".join(chunk_text(job, previous).split()[-150:]) if previous else "(start of the text)"
        values = {**job.source_values(), **brief_values(brief), "chunk_number": chunk["n"],
                  "chunk_count": len(job.chunks), "heading": chunk["heading"] or "(none)",
                  "previous_tail": tail, "numbered_chunk_text": chunk_text(job, chunk, numbered=True)}
        raw = step(job.folder / "ideas" / f"{chunk['n']:02}.json",
                   lambda values=values: job.ask("extract", "extract", values)["data"], digest(values))
        ideas = [{**idea, "ref": f"{chunk['n']:02}:{i}", "chunk": chunk["n"]} for i, idea in enumerate(raw["ideas"], 1)]
        cap = job.config["make"]["ideas_per_chunk"]
        ideas, over = by_importance(ideas, cap)
        for idea in over:
            job.drop("ideas", idea, f"over the limit of {cap} ideas per part")
        own = {n: job.paras[n] for n in range(chunk["first"], chunk["last"] + 1)}
        passed = 0
        for idea in ideas:
            problems = gates.evidence_gate(idea, own)
            if problems:
                job.drop("ideas", idea, "; ".join(problems))
            else:
                kept.append(idea)
                passed += 1
        job.count("extract", 1, len(raw["ideas"]))
        job.count("evidence_gate", len(ideas), passed)
    save(job.folder / "ideas.json", kept)
    return kept


def budget(job):
    kind = {"other": "article"}.get(job.meta["kind"], job.meta["kind"])
    rule = job.config["make"]["cards"][kind]
    if "per_words" not in rule:
        return rule["max"]
    return max(rule["min"], min(rule["max"], round(job.words_read / rule["per_words"])))


def select(job, brief, ideas, short, existing_titles=(), limit=None):
    """Step 6, with the budget and the format rules enforced by code."""
    if job.meta['kind'] == 'paper':
        ideas = [idea for idea in ideas if idea['kind'] == 'research']
    limit = budget(job) if limit is None else limit
    if not ideas:
        return [], {"chosen": [], "duplicates": [], "topics": [], "new_topic": ""}
    values = {**job.source_values(), "thesis": brief["thesis"], "budget": limit, "topic_list": topic_list(job),
              "existing_titles": none(existing_titles),
              "topics_instruction": "one to three ids from the topic list that fit the text best." if short
              else "an empty list (the topics are already chosen).",
              "ideas": "\n".join(f"{i['ref']} | {i['importance']} | {i['stance']} | {i['kind']} | {i['title']} | {i['claim']}"
                                 for i in ideas)}
    selection = step(job.folder / "selection.json", lambda: job.ask("select", "select", values)["data"], digest(values))
    by_ref, chosen = {i["ref"]: i for i in ideas}, []
    for item in selection["chosen"]:
        idea = by_ref.get(item["ref"])
        if not idea or any(c["ref"] == item["ref"] for c in chosen):
            continue
        if item["format"] == "quote" and not (idea["quote_text"].strip() and idea["speaker"].strip()):
            job.drop("ideas", idea, "chosen as a quote but has no quote or speaker")
        elif item["format"] == "news" and job.meta["kind"] != "news":
            job.drop("ideas", idea, "a news card must come from a news source")
        else:
            chosen.append({**idea, "format": 'research' if job.meta['kind'] == 'paper' else item["format"], "level": item["level"]})
    chosen, over = by_importance(chosen, limit)
    for idea in over:
        job.drop("ideas", idea, f"over the card budget of {limit}")
    job.count("select", len(ideas), len(chosen))
    return chosen, selection


# ---------------------------------------------------------------- steps 7 to 10

def idea_block(job, idea):
    blank = lambda value: value.strip() or "(none)"  # noqa: E731
    return (f"Idea ref {idea['ref']}\nformat: {idea['format']}\ntitle: {idea['title']}\nclaim: {idea['claim']}\n"
            f"support: {idea['support']}\nlimits: {blank(idea['limits'])}\nstance: {idea['stance']}\n"
            f"quote_text: {blank(idea['quote_text'])}\nspeaker: {blank(idea['speaker'])}\n"
            "<paragraphs>\n" + "\n".join(job.context(idea)) + "\n</paragraphs>")


def card_block(job, card, brief):
    return (f"Card ref {card['ref']}\nformat: {card['format']}\ntitle: {card['title']}\nfront: {card['front']}\n"
            f"back: {card['back']}\nmedia_alt: {card.get('media_alt', '')}\n<source_context>\nGlossary: {brief_values(brief)['glossary']}\n"
            f"People: {brief_values(brief)['people']}\n</source_context>\n<paragraphs>\n"
            + "\n".join(job.context(job.ideas[card["ref"]])) + "\n</paragraphs>")


def write_round(job, brief, ideas, sub, prefix, accepted, rejected=None):
    """Write (or repair) cards for `ideas`, run the card gates and the judge.
    Returns (passed cards, failed [(idea, card or None, problem, fix)])."""
    def values(batch):
        repair = ""
        if rejected:
            repair = REPAIR_HEAD + "\n\n" + "\n\n".join(
                f"Rejected card for idea {i['ref']}\nfront: {(rejected[i['ref']][0] or {}).get('front', '(none)')}\n"
                f"back: {(rejected[i['ref']][0] or {}).get('back', '(none)')}\nproblem: {rejected[i['ref']][1]}\n"
                f"fix: {rejected[i['ref']][2] or 'fix the problem named'}" for i in batch)
        return {**job.source_values(), "thesis": brief["thesis"], "glossary": brief_values(brief)["glossary"],
                "people": brief_values(brief)["people"], "repair_block": repair, "idea_count": len(batch),
                "ideas_with_paragraphs": [idea_block(job, i) for i in batch]}
    written = {}
    prompt = 'image' if job.meta.get('media') else 'write'
    for batch, data in job.batches(sub, prefix, ideas, job.config["make"]["batch"]["write"], "write", prompt, values):
        refs = {i["ref"] for i in batch}
        for card in data["cards"]:
            if card["ref"] in refs:
                written.setdefault(card["ref"], {**card, "provider": data["provider"]})
    job.count("write", len(ideas), len(written))
    gated, failed = [], []
    for idea in ideas:
        answer = written.get(idea["ref"])
        if not answer:
            failed.append((idea, None, "the writer returned no card", ""))
            continue
        card = {"ref": idea["ref"], "format": idea["format"], "level": idea["level"], "title": answer["title"].strip(),
                "front": answer["front"].strip(), "back": answer["back"].strip(), "provider": answer["provider"],
                "location": job.heading_above[min(n for n in gates._refs(idea) if n)]}
        if rejected:
            original = rejected[idea['ref']][0] or {}
            card.update({k: original[k] for k in ('id', 'source_id', 'media', 'poster', 'captions', 'media_alt',
                                                 'transcript', 'duration_seconds') if k in original})
        if idea["format"] == "quote":
            card.update(front=idea["quote_text"].strip(), speaker=idea["speaker"].strip())
        if idea['format'] == 'image':
            card.update(media=job.meta['media']['file'], media_alt=answer['media_alt'].strip())
        problems = gates.card_gates(card, idea, job.context(idea), job.full, accepted + gated, job.topics,
                                    job.meta.get("authors") or ())
        job.gates["cards"].setdefault(card["ref"], []).append({"round": sub + prefix, "problems": problems})
        if problems:
            failed.append((idea, card, "; ".join(problems), "fix the problems named"))
        else:
            gated.append(card)
    job.count("card_gates", len(written), len(gated))
    verdicts = {}
    for batch, data in job.batches("verdicts", prefix or ("r" if sub == "repairs" else ""), gated,
                                   job.config["make"]["batch"]["judge"], "judge", "judge",
                                   lambda batch: {**job.source_values(), "thesis": brief["thesis"],
                                                  "card_count": len(batch),
                                                  "cards_with_paragraphs": [card_block(job, c, brief) for c in batch]},
                                   lambda batch: job.family(batch[0]["provider"])):
        refs = {c["ref"] for c in batch}
        for verdict in data["verdicts"]:
            if verdict["ref"] in refs:
                verdicts.setdefault(verdict["ref"], verdict)
    passed = []
    for card in gated:
        verdict = verdicts.get(card["ref"])
        if verdict is None:
            failed.append((job.ideas[card["ref"]], card, "the judge returned no verdict", ""))
        elif all(verdict[k] for k in SIX):
            passed.append(card)
        else:
            wrong = ", ".join(k for k in SIX if not verdict[k])
            failed.append((job.ideas[card["ref"]], card, verdict["problem"] or "judged not " + wrong, verdict["fix"]))
    job.count("judge", len(gated), len(passed))
    return passed, failed


# ---------------------------------------------------------------- steps 11 to 13

def convert(job, data, batch, taken):
    """Quiz answers → practice cards of CONTENT_FORMAT.md, with seeded shuffles."""
    refs, out = {c["ref"] for c in batch}, []
    for raw in data["tests"]:
        if raw["card"] not in refs:
            continue
        base = f"{raw['card']}-{SUFFIX[raw['type']]}"
        taken[base] = taken.get(base, 0) + 1
        test = {"id": base if taken[base] == 1 else f"{base}-{taken[base]}", "card": raw["card"], "type": raw["type"],
                "prompt": raw["prompt"].strip(), "explanation": raw["explanation"].strip()}
        for field in TYPE_FIELDS[raw["type"]]:
            test[field] = raw[field]
        if raw["type"] == "multiple_choice" and 0 <= raw["correct_choice"] < len(raw["choices"]):
            # Seeded by the test id: a re-run gives the same order and the solver sees the final order.
            order = list(range(len(raw["choices"])))
            random.Random(test["id"]).shuffle(order)
            test["choices"] = [raw["choices"][i] for i in order]
            test["correct_choice"] = order.index(raw["correct_choice"])
        out.append(test)
    return out


def solve_block(card, tests):
    lines = [f"<card>\nref: {card['ref']}\ntitle: {card['title']}\nfront: {card['front']}\nback: {card['back']}\nmedia_alt: {card.get('media_alt', '')}\n</card>"]
    for t in tests:
        block = f"<test>\nid: {t['id']}\ntype: {t['type']}\nprompt: {t['prompt']}\n"
        rng = random.Random(t["id"] + ":solve")
        if t["type"] == "multiple_choice":
            block += "choices: " + json.dumps(t["choices"], ensure_ascii=False) + "\n"
        elif t["type"] == "ordering":
            items = list(t["correct_order"])
            rng.shuffle(items)
            block += "items (shuffled): " + json.dumps(items, ensure_ascii=False) + "\n"
        elif t["type"] == "matching":
            right = list(t["match_right"])
            rng.shuffle(right)
            block += ("left: " + json.dumps(t["match_left"], ensure_ascii=False) + "\nright (shuffled): "
                      + json.dumps(right, ensure_ascii=False) + "\n")
        lines.append(block + "</test>")
    return "\n".join(lines)


def quiz_solve(job, cards, prefix, taken, existing=None):
    """Quiz, blind solve and test gates for one group of cards.
    Returns (passing tests by card ref, every test by card ref, {ref: unclear words})."""
    def quiz_values(batch):
        lines = [f"{t['card']} | {t['type']} | {t['prompt']}" for c in batch for t in (existing or {}).get(c["ref"], [])]
        return {"existing_tests": none(lines), "card_count": len(batch),
                "cards": [f"<card>\nref: {c['ref']}\nformat: {c['format']}\ntitle: {c['title']}\nfront: {c['front']}\n"
                          f"back: {c['back']}\nmedia_alt: {c.get('media_alt', '')}\n</card>" for c in batch]}
    tests = []
    for batch, data in job.batches("tests", prefix, cards, job.config["make"]["batch"]["quiz"], "quiz", "quiz", quiz_values):
        tests += convert(job, data, batch, taken)
    by_card = {c["ref"]: [t for t in tests if t["card"] == c["ref"]] for c in cards}
    job.count("quiz", len(cards), len(tests))
    answers, unclear = {}, {}
    for batch, data in job.batches("solved", prefix, cards, job.config["make"]["batch"]["solve"], "solve", "solve",
                                   lambda batch: {"cards_with_tests_without_answers":
                                                  [solve_block(c, by_card[c["ref"]]) for c in batch]}):
        for answer in data["answers"]:
            answers.setdefault(answer["test"], answer)
        refs = {c["ref"] for c in batch}
        for item in data["unclear"]:
            if item["ref"] in refs and item["words"].strip():
                unclear.setdefault(item["ref"], []).append(item["words"].strip())
    passing = {}
    for test in tests:
        answer = answers.get(test["id"])
        problems = ["the blind solver did not answer it"] if answer is None else gates.test_gates(test, answer, job.topics)
        job.gates["tests"][test["id"]] = problems
        if problems:
            job.drop("tests", test, "; ".join(problems))
        else:
            passing.setdefault(test["card"], []).append(test)
    job.count("test_gates", len(tests), sum(map(len, passing.values())))
    return passing, by_card, unclear


def make_cards(job, brief, chosen, existing=()):
    """Steps 7 to 13. Returns (cards, tests by card ref, pass rate)."""
    job.ideas = {i["ref"]: i for i in chosen}
    passed, failed = write_round(job, brief, chosen, "cards", "", list(existing))
    first_passed = len(passed)
    repair, rejected = [], {}
    for idea, card, problem, fix in failed:
        if fix.strip().lower().rstrip(".") == "drop":
            job.drop("cards", card or idea, "the judge says the idea is not in the paragraphs: " + problem)
        else:
            repair.append(idea)
            rejected[idea["ref"]] = (card, problem, fix)
    repaired, failed = write_round(job, brief, repair, "repairs", "", list(existing) + passed, rejected)
    for idea, card, problem, _ in failed:
        job.drop("cards", card or idea, "failed again after repair: " + problem)
    job.count("repair", len(repair), len(repaired))
    pass_rate = (first_passed + len(repaired)) / len(chosen) if chosen else 0.0
    cards = {c["ref"]: c for c in passed + repaired}

    taken = {}
    passing, every, unclear = quiz_solve(job, list(cards.values()), "", taken)
    # Every card the blind reader could not follow gets one repair of its own (SKILL.md step 12).
    again = [i["ref"] for i in chosen if i["ref"] in unclear and i["ref"] in cards]
    if again:
        rejected = {ref: (cards[ref], "A reader who sees only the card could not understand: " + "; ".join(unclear[ref]),
                          "The card already passed the checker: keep its title and every sentence word for word, and change "
                          "only the words named, explaining each in a few words or replacing it with a plainer one. Name a "
                          "person in full with a role such as 'the writer' or 'the researcher'. Explain only with what the "
                          "paragraphs say: if they do not explain a word, use a plainer word or leave that detail out. Add "
                          "no name, place or meaning you know from elsewhere.") for ref in again}
        others = list(existing) + [c for ref, c in cards.items() if ref not in again]
        fixed, failed = write_round(job, brief, [job.ideas[ref] for ref in again], "repairs", "u", others, rejected)
        for idea, card, problem, _ in failed:
            job.drop("cards", card or idea, "failed after the unclear-words repair: " + problem)
        for ref in again:
            cards.pop(ref)
            passing.pop(ref, None)
            every.pop(ref, None)
        more, more_every, still = quiz_solve(job, fixed, "u", taken)
        for card in fixed:
            if card["ref"] in still:
                job.drop("cards", card, "still unclear after repair: " + "; ".join(still[card["ref"]]))
            else:
                cards[card["ref"]] = card
                passing[card["ref"]] = more.get(card["ref"], [])
                every[card["ref"]] = more_every[card["ref"]]
    short = [c for ref, c in cards.items() if len(passing.get(ref, [])) < 2]
    if short:
        more, _, _ = quiz_solve(job, short, "x", taken, existing=every)
        for card in short:
            passing.setdefault(card["ref"], []).extend(more.get(card["ref"], []))
    limit = job.config["make"]["tests_per_card"]
    final, tests = [], {}
    for idea in chosen:
        card = cards.get(idea["ref"])
        if not card:
            continue
        if not passing.get(card["ref"]):
            job.drop("cards", card, "no test passed")
            continue
        final.append(card)
        tests[card["ref"]] = passing[card["ref"]][:limit]
    return final, tests, pass_rate


# ---------------------------------------------------------------- step 14

def pack(job, brief, topics, cards, tests):
    """source/<id>/source.json as in CONTENT_FORMAT.md, checked by upload.validate()."""
    out = job.folder / "source" / job.id
    if (out / "source.json").exists():
        return load(out / "source.json")
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    meta, publish = job.meta, job.config["publish"]
    source = {"id": job.id, "kind": meta["kind"], "title": meta["title"], "authors": meta.get("authors") or [],
              "language": "en", "status": "published" if publish["auto_publish"] else "draft", "topics": topics}
    if meta.get("sample"):
        source["is_sample"] = True
    if re.fullmatch(r"\d{4}-\d\d-\d\d", meta.get("published_on") or ""):
        source["published_on"] = meta["published_on"]
    if meta.get("link"):
        source["link"] = meta["link"]
    description = (brief.get("description") or "").strip()
    credit = licenses.attribution(meta)
    if credit:
        description = (description + ' ' + credit).strip()
    if description:
        source["description"] = description
    allowed = gates.upload.DETAILS.get(meta["kind"], (None, set()))[1]
    details = {k: v for k, v in (meta.get("details") or {}).items() if k in allowed and v}
    if details:
        source[meta["kind"]] = details
    if publish["store_text"]:
        shutil.copy(job.folder / "text.txt", out / "text.txt")
        source["text"] = "text.txt"
    original = next(job.folder.glob("original.*"), None)
    if publish["store_original"] and original and original.stat().st_size < 50_000_000 \
            and original.suffix.lower() in gates.upload.FILES["original"][0]:
        shutil.copy(original, out / ("original" + original.suffix.lower()))
        source["original"] = "original" + original.suffix.lower()
    if meta.get("cover") and (job.folder / meta["cover"]).exists():
        shutil.copy(job.folder / meta["cover"], out / meta["cover"])
        source["cover"] = meta["cover"]
    used, discover, practice = set(), [], []
    for card in cards:
        base = slug(card["title"])
        card_id, n = base, 2
        while card_id in used:
            card_id, n = f"{base}-{n}", n + 1
        used.add(card_id)
        row = {"id": card_id, "format": card["format"], "title": card["title"], "front": card["front"],
               "back": card["back"], "level": card["level"]}
        if card.get("speaker"):
            row["speaker"] = card["speaker"]
        if card.get("location"):
            row["location"] = card["location"]
        if card['format'] == 'image':
            from . import readers
            path = job.folder / card['media']
            extension = readers.image_extension(path.read_bytes())
            row.update(media='image' + extension, media_alt=card['media_alt'])
            shutil.copyfile(path, out / row['media'])
        discover.append(row)
        seen = {}
        for test in tests[card["ref"]]:
            # Numbered from the tests kept: a re-quizzed card's first tests get no "-2".
            base = f"{card_id}-{SUFFIX[test['type']]}"
            seen[base] = seen.get(base, 0) + 1
            practice.append({"id": base if seen[base] == 1 else f"{base}-{seen[base]}",
                             **{k: v for k, v in test.items() if k not in ("id", "card")}, "tests": [card_id]})
    source["discover_cards"], source["practice_cards"] = discover, practice
    try:
        gates.upload.validate([(str(out), source)], job.topics, check_files=True)
    except gates.upload.Invalid as exc:
        raise Stop("failed", "packed folder rejected: " + str(exc)) from exc
    save(out / "source.json", source)
    return source


# ---------------------------------------------------------------- the whole job

def method(job):
    prepare(job)
    if job.meta.get('media'):
        short = True
        brief = make_brief(job, None)
        chosen = [{'ref': 'image:1', 'format': 'image', 'kind': 'concept', 'title': job.meta['title'],
                   'claim': 'Describe the work using only the collection description.', 'support': job.full,
                   'limits': '', 'stance': 'claims', 'quote_text': '', 'speaker': '', 'importance': 1,
                   'paragraphs': list(job.paras), 'level': 'intro'}]
        save(job.folder / 'ideas.json', chosen)
        selection = {'topics': job.meta.get('topics') or [], 'new_topic': ''}
    else:
        summaries = summarize(job)
        short = summaries is None
        brief = make_brief(job, summaries)
        ideas = extract(job, brief, summaries)
        chosen, selection = select(job, brief, ideas, short)
    cards, tests, pass_rate = make_cards(job, brief, chosen)
    job.pass_rate = pass_rate
    job.step = "pack"
    kind = {"other": "article"}.get(job.meta["kind"], job.meta["kind"])
    quality = job.config["quality"]
    wanted = list(dict.fromkeys((selection if short else brief)["topics"]))
    topics = [t for t in wanted if t in job.topics]
    job.final = {"cards": len(cards), "tests": sum(map(len, tests.values()))}
    minimum = 1 if job.meta.get('media') else quality['min_cards'][kind]
    if len(cards) < minimum:
        return "review", f"{len(cards)} cards, {minimum} needed"
    if pass_rate < quality["min_pass_rate"]:
        return "review", f"pass rate {pass_rate:.2f} is below {quality['min_pass_rate']}"
    if not topics:
        suggestion = (selection if short else brief).get("new_topic", "")
        return "review", "no topic fits" + (f" (suggested: {suggestion})" if suggestion else "")
    pack(job, brief, topics, cards, tests)
    return "ready", ""


def update_job(job_id, **fields):
    fields["updated_at"] = now()
    with closing(store.connect()) as db, db:
        db.execute(f"UPDATE jobs SET {', '.join(k + '=?' for k in fields)} WHERE id=?", (*fields.values(), job_id))


def report(job, status, error):
    with closing(store.connect()) as db:
        rows = db.execute("SELECT provider, count(*), sum(ok), sum(tokens_in), sum(tokens_out), sum(seconds) "
                          "FROM calls WHERE job_id=? GROUP BY provider", (job.id,)).fetchall()
    data = {"job": job.id, "status": status, "error": error, "steps": job.counts,
            "pass_rate": round(getattr(job, "pass_rate", 0.0), 3), "final": getattr(job, "final", {}),
            "dropped": job.dropped,
            "calls": {r[0]: {"calls": r[1], "ok": r[2], "tokens_in": r[3], "tokens_out": r[4],
                             "seconds": round(r[5] or 0, 1)} for r in rows}}
    save(job.folder / "report.json", data)
    if hasattr(job, "full"):
        save(job.folder / "gates.json", job.gates)
    return data


def lock(folder, filename="run.lock"):
    """An OS lock on the job folder: two runs on one job would overwrite each other's step files.
    The system releases it when the process ends, so a crashed run leaves nothing to clean up."""
    handle = open(Path(folder) / filename, "a+b")
    try:
        handle.seek(0)
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        raise ValueError(f"job {Path(folder).name} is already being made by another run") from None
    return handle


def run(job_id, deadline=None):
    """Run the method once on a job. Returns its new status."""
    job = Job(job_id, deadline)
    with lock(job.folder):
        return _run(job, job_id)


def _run(job, job_id):
    update_job(job_id, status="making", error="")
    with closing(store.connect()) as db:
        attempts = db.execute("SELECT attempts FROM jobs WHERE id=?", (job_id,)).fetchone()[0] or 0
    try:
        status, error = method(job)
        attempts = 0
    except Stop as stop:
        status, error = stop.status, stop.error
        if status == "waiting" and stop.kind != "limit":
            attempts += 1
            if attempts >= 3:
                status = "failed"
    data = report(job, status, error)
    update_job(job_id, status=status, error=error, step=job.step, attempts=attempts,
               counts=json.dumps({**data["steps"], **data["final"]}))
    return status


# ---------------------------------------------------------------- add

def _taken_online(source_id):
    try:
        return bool(gates.upload.Supabase().select("sources", f"select=id&id=eq.{source_id}"))
    except (OSError, KeyError, SystemExit) as exc:
        raise ValueError(f"cannot check the source id online: {exc}") from exc


def add(path, sample=False, max_chunks=None, kind="book", title=None, author=None):
    """Make (or resume) the job for one file and run the method once. Returns the job id."""
    job_id = create(path, sample, max_chunks, kind, title, author)
    run(job_id)
    return job_id


def create(path, sample=False, max_chunks=None, kind="book", title=None, author=None, origin="file", extra=None, media=None):
    """Make (or find) the queued job for one file without running it. `extra` adds book facts to meta.json.
    Returns the job id."""
    path = Path(path)
    if not path.is_file():
        raise ValueError(f"no such file: {path}")
    config = settings.load()
    sample = bool(sample or config["trial"])
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    facts = text.epub_facts(path) if path.suffix.lower() == ".epub" else {}
    title = title or facts.get("title") or path.stem.replace("_", " ").replace("-", " ")
    authors = ([author] if isinstance(author, str) else list(author)) if author else facts.get("authors", [])
    base = ("trial-" + slug(title, 54)) if sample else slug(title)
    surname = slug(authors[0].split(",")[0].split()[-1]) if authors and authors[0].split() else ""
    options = {"sha256": digest, "kind": kind, "sample": sample, "max_chunks": max_chunks}
    if (extra or {}).get('feed_key'):
        options['feed_key'] = extra['feed_key']
    candidates = [base] + ([f"{base}-{surname}"] if surname else []) + [f"{base}-{n}" for n in range(2, 100)]
    with closing(store.connect()) as db:
        for job_id in candidates:
            row = db.execute("SELECT status FROM jobs WHERE id=?", (job_id,)).fetchone()
            folder = settings.home() / "jobs" / job_id
            if row is None:
                if not sample and _taken_online(job_id):
                    continue
                break
            if row["status"] not in ("uploaded", "done") and (folder / "meta.json").exists() \
                    and all(load(folder / "meta.json").get(k) == v for k, v in options.items()):
                break
    if row is None:
        folder.mkdir(parents=True, exist_ok=True)
        shutil.copy(path, folder / ("original" + path.suffix.lower()))
        if media is not None:
            shutil.copyfile(media, folder / extra['media']['file'])
        save(folder / "meta.json", {"kind": kind, "title": title, "authors": authors, "published_on": "", "link": "",
                                    "license": "", "credit": "", "details": {}, "topics": [], "origin": origin,
                                    "file": path.name, **options, **(extra or {})})
        with closing(store.connect()) as db, db:
            db.execute("INSERT INTO jobs (id, kind, title, origin, status, step, attempts, error, counts, created_at, "
                       "updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                       (job_id, kind, title, origin, "queued", "", 0, "", "{}", now(), now()))
            db.execute("INSERT OR IGNORE INTO seen (key, job_id, at) VALUES (?,?,?)", (digest, job_id, now()))
    return job_id

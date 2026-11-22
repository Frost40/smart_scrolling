"""The code gates of tools/content/cardmaker/SKILL.md. Each returns a list of problems in words; empty = pass."""

import functools
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import upload  # noqa: E402  (the upload tool, used as it is)

TOPICS = Path(__file__).resolve().parents[1] / "topics.json"
OPENERS = re.compile(r"^[\"'“‘(]*(this|that|these|those|he|she|they|such|here)\b", re.I)
PHRASES = ["the author", "the book", "this book", "this chapter", "the chapter", "the passage", "the text",
           "as mentioned", "as we saw", "see above", "the above", "the following"]
# A sentence about what the source leaves out ("the room's size is not given") is about the book, not the idea.
PHRASE = re.compile(r"\b(" + "|".join(re.escape(p) for p in PHRASES)
                    + r"|(?:is|are|was|were) not (?:given|stated|reported)"
                    + r"|no (?:\w+ ){1,2}(?:is|are|was|were) (?:given|stated|reported)" + r")\b")
ENDING = re.compile(r"[.!?…][\"'”’)\]]*$")
NAME = re.compile(r"\b[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)+")
NUMBER = re.compile(r"\d[\d,.]*\d|\d")


def normalise(text):
    """Lowercase, straight quotes, one kind of dash, single spaces."""
    text = (text or "").lower().replace("“", '"').replace("”", '"').replace("‘", "'").replace("’", "'")
    text = re.sub(r"[‐-―−]", "-", text)
    return re.sub(r"\s+", " ", text).strip()


def known_topics():
    return {t["id"] for t in json.loads(TOPICS.read_text(encoding="utf-8"))}


def _refs(idea):
    out = []
    for ref in idea.get("paragraphs", []):
        match = re.fullmatch(r"\s*P?(\d+)\s*", str(ref), re.I)
        out.append(int(match[1]) if match else None)
    return out


def evidence_gate(idea, paragraphs):
    """paragraphs: {number: text} of the part the idea was taken from."""
    refs = _refs(idea)
    if not refs:
        return ["names no paragraph"]
    if any(n not in paragraphs for n in refs):
        return ["names a paragraph outside its part: " + ", ".join(map(str, idea.get("paragraphs", [])))]
    text = normalise(" ".join(paragraphs[n] for n in sorted(set(refs))))
    problems = []
    if not idea.get("evidence_quote") or normalise(idea["evidence_quote"]) not in text:
        problems.append("evidence sentence is not in its paragraphs")
    if idea.get("kind") == "quote":
        quote = normalise(idea.get("quote_text"))
        at = text.find(quote) if quote else -1
        if at < 0:
            problems.append("quote is not in its paragraphs")
        else:
            before = text[:at].rstrip(" \"'(")
            if (before and before[-1] not in ".!?…:") or not ENDING.search(quote):
                problems.append("quote does not start and end with a whole sentence")
    return problems


@functools.lru_cache(maxsize=4)
def _grams(full_text):
    words = re.findall(r"[a-z0-9']+", normalise(full_text))
    return {tuple(words[i:i + 12]) for i in range(len(words) - 11)}


def _words(text):
    return re.findall(r"[a-z0-9']+", normalise(text))


def _side_problems(side, text, para_text, full_norm):
    problems = []
    text = (text or "").strip()
    if not ENDING.search(text):
        problems.append(f"{side} does not end a sentence")
    if text.count("(") != text.count(")") or text.count("[") != text.count("]") \
            or text.count('"') % 2 or text.count("“") != text.count("”"):
        problems.append(f"{side} has unbalanced brackets or quotes")
    if OPENERS.match(text):
        problems.append(f"{side} starts with '{text.split()[0]}'")
    for phrase in sorted(set(PHRASE.findall(normalise(text)))):
        problems.append(f"{side} contains '{phrase}'")
    for number in NUMBER.findall(text):
        digits = number.rstrip(".,").replace(",", "")
        if not re.search(r"(?<![\d])" + re.escape(digits) + r"(?![\d])", para_text):
            problems.append(f"{side} number {number.rstrip('.,')} is not in the paragraphs")
    for sentence in re.split(r"(?<=[.!?…])\s+", text):
        sentence = sentence.lstrip("\"'“‘(")
        for match in NAME.finditer(sentence):
            words = match[0].split()
            if match.start() == 0:
                words = words[1:]
            if len(words) >= 2 and normalise(" ".join(words)) not in full_norm:
                problems.append(f"{side} name '{' '.join(words)}' does not appear in the source")
    return problems


def _validate(source, topics):
    try:
        upload.validate([(source["id"], source)], topics, check_files=False)
        return []
    except upload.Invalid as exc:
        return [str(exc)]


def card_gates(card, idea, paragraphs, full_text, other_cards=(), topics=None, authors=()):
    """paragraphs: the text (or texts) the card was written from; full_text: all of text.txt."""
    topics = known_topics() if topics is None else topics
    para_text = (paragraphs if isinstance(paragraphs, str) else " ".join(paragraphs)).replace(",", "")
    full_norm = normalise(full_text + "\n" + "\n".join(authors))
    problems = []
    for side in ("front", "back"):
        problems += _side_problems(side, card.get(side), para_text, full_norm)
    if card.get('format') == 'image':
        problems += _side_problems('media_alt', card.get('media_alt'), para_text, full_norm)
    for field, limit in (("front", 220), ("back", 420), ("title", 60)):
        if len(card.get(field) or "") > limit:
            problems.append(f"{field} is over {limit} characters")
    if card.get("format") != "quote":
        words = _words((card.get("front") or "") + " " + (card.get("back") or ""))
        grams = _grams(full_text)
        if any(tuple(words[i:i + 12]) in grams for i in range(len(words) - 11)):
            problems.append("copies 12 or more words in a row from the source")
    elif idea is not None and normalise(card.get("front")) != normalise(idea.get("quote_text")):
        problems.append("quote front is not the quote text")
    mine = set(_words(card.get("front")))
    for other in other_cards:
        theirs = set(_words(other.get("front")))
        if mine and len(mine & theirs) / len(mine) > 0.8:
            problems.append(f"front repeats the card '{other.get('title')}'")
            break
    for topic in card.get("topics", []):
        if topic not in topics:
            problems.append(f"unknown topic '{topic}'")
    fields = {k: v for k, v in card.items() if k in upload.CARD_FIELDS or k in ('topics', 'media', 'poster', 'captions')}
    fields["id"] = card['id'] if 'source_id' in card else 'card'
    source = {"id": card.get('source_id', 'gates'), "kind": "news" if card.get("format") == "news" else "book", "title": "gates",
              "discover_cards": [fields]}
    return problems + _validate(source, topics)


def _same(a, b):
    return [normalise(x) for x in a] == [normalise(x) for x in b]


def test_gates(test, solver_answer, topics=None):
    """solver_answer: the blind solver's answer for this test, or None for a test made by hand."""
    problems = []
    kind = test.get("type")
    if solver_answer is not None:
        if not solver_answer.get("answerable"):
            problems.append("the blind solver could not answer it from the card")
        elif kind == "multiple_choice" and solver_answer.get("choice") != test.get("correct_choice"):
            problems.append("the blind solver chose another answer")
        elif kind == "true_false" and solver_answer.get("is_true") != test.get("is_true"):
            problems.append("the blind solver gave the other answer")
        elif kind == "ordering" and not _same(solver_answer.get("order", []), test.get("correct_order", [])):
            problems.append("the blind solver ordered it differently")
        elif kind == "matching" and not _same(solver_answer.get("pairs", []), test.get("match_right", [])):
            problems.append("the blind solver matched it differently")
    if kind == "multiple_choice":
        choices = test.get("choices") or []
        if len(choices) != 4:
            problems.append("multiple choice needs exactly 4 choices")
        if len({normalise(c) for c in choices}) != len(choices):
            problems.append("two choices are the same")
        if any(re.search(r"\b(all|none) of the above\b", normalise(c)) for c in choices):
            problems.append("a choice is 'all of the above' or 'none of the above'")
        right = test.get("correct_choice")
        others = [len(c) for i, c in enumerate(choices) if i != right]
        if isinstance(right, int) and 0 <= right < len(choices) and others \
                and len(choices[right]) > 1.6 * sum(others) / len(others):
            problems.append("the right choice is much longer than the others")
    prompt = (test.get("prompt") or "").strip()
    for phrase in sorted(set(PHRASE.findall(normalise(prompt)))):
        problems.append(f"prompt contains '{phrase}'")
    if not re.search(r"[?.][\"'”’)]*$", prompt):
        problems.append("prompt does not end with '?' or '.'")
    topics = known_topics() if topics is None else topics
    fields = {k: v for k, v in test.items() if k in upload.PRACTICE_FIELDS}
    fields.update(id="test", tests=["card"])
    card = {"id": "card", "format": "concept", "title": "t", "front": "f"}
    source = {"id": "gates", "kind": "book", "title": "gates", "discover_cards": [card], "practice_cards": [fields]}
    return problems + _validate(source, topics)


def check_folder(folder):
    """Run the code gates on a folder made by hand (text.txt and source.json). Returns {id: problems}."""
    folder = Path(folder)
    full = (folder / "text.txt").read_text(encoding="utf-8")
    source = json.loads((folder / "source.json").read_text(encoding="utf-8"))
    topics = known_topics()
    out, done = {}, []
    for card in source.get("discover_cards", []):
        idea = {"quote_text": card.get("front")} if card.get("format") == "quote" else None
        problems = card_gates(card, idea, full, full, done, topics, source.get("authors") or ())
        if idea and normalise(card.get("front")) not in normalise(full):
            problems.append("quote is not in text.txt")
        out[card.get("id")] = problems
        done.append(card)
    for test in source.get("practice_cards", []):
        out[test.get("id")] = test_gates(test, None, topics)
    try:
        upload.validate([(str(folder), source)], topics, check_files=True)
    except upload.Invalid as exc:
        out["source.json"] = str(exc).splitlines()
    return out

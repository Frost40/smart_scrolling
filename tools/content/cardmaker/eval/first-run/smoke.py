"""Smoke test of the card-making prompts on one trap passage, through `claude -p`.
Usage: py -3 smoke.py <cardmaker dir> <writer model> <judge model>
Not pipeline code: a throwaway check that the prompts and schemas behave."""
import json, os, re, subprocess, sys, time

CM = sys.argv[1]
WRITER, JUDGE = sys.argv[2], sys.argv[3]
HERE = os.path.dirname(os.path.abspath(__file__))
SANDBOX = os.path.join(HERE, "sandbox")
os.makedirs(SANDBOX, exist_ok=True)
SCHEMAS = json.load(open(os.path.join(CM, "schemas.json"), encoding="utf-8"))
CALLS = []


def prompt(name, **vars):
    text = open(os.path.join(CM, "prompts", name + ".md"), encoding="utf-8").read()
    system, user = text.split("\n=====\n", 1)
    for k, v in vars.items():
        user = user.replace("{{" + k + "}}", str(v))
    left = re.findall(r"\{\{\w+\}\}", user)
    assert not left, f"{name}: unfilled {left}"
    return system.strip(), user.strip()


def call(model, name, **vars):
    system, user = prompt(name, **vars)
    env = {k: v for k, v in os.environ.items() if k not in ("CLAUDECODE", "ANTHROPIC_API_KEY", "CLAUDE_CODE_ENTRYPOINT")}
    cmd = ["claude", "-p", "--model", model, "--output-format", "json", "--tools", "", "--strict-mcp-config",
           "--disable-slash-commands", "--setting-sources", "", "--no-session-persistence",
           "--system-prompt", system, "--json-schema", json.dumps(SCHEMAS[name])]
    t = time.time()
    out = subprocess.run(cmd, input=user, capture_output=True, text=True, encoding="utf-8", cwd=SANDBOX, env=env, timeout=300)
    reply = json.loads(out.stdout)
    CALLS.append((name, model, round(time.time() - t, 1), reply.get("usage", {}).get("output_tokens")))
    assert "structured_output" in reply, reply.get("result")
    return reply["structured_output"]


def norm(s):
    s = s.lower().replace("“", '"').replace("”", '"').replace("‘", "'").replace("’", "'")
    s = re.sub(r"[‐-―]", "-", s)
    return re.sub(r"\s+", " ", s).strip()


BANNED_START = re.compile(r"^(This|That|These|Those|He|She|They|Such|Here)\b")
BANNED = ["the author", "the book", "this book", "this chapter", "the chapter", "the passage", "the text",
          "as mentioned", "as we saw", "see above", "the above", "the following"]


def card_problems(card, para_text, full_text):
    p = []
    for side in ("front", "back"):
        s = card[side].strip()
        if not s:
            continue
        if not re.search(r"[.!?…][\"')”]?$", s):
            p.append(f"{side} does not end a sentence")
        for sent in re.split(r"(?<=[.!?])\s+", s):
            if BANNED_START.match(sent):
                p.append(f"{side} sentence starts with '{sent.split()[0]}'")
        for b in BANNED:
            if b in s.lower():
                p.append(f"{side} contains '{b}'")
        for n in re.findall(r"\d[\d,.]*\d|\d", s):
            if n.rstrip(".,") not in para_text:
                p.append(f"{side} number {n} not in paragraphs")
    if len(card["front"]) > 220: p.append("front too long")
    if len(card["back"]) > 420: p.append("back too long")
    words = norm(card["front"] + " " + card["back"]).split()
    full = norm(full_text)
    for i in range(len(words) - 11):
        if " ".join(words[i:i + 12]) in full:
            p.append("12 words copied"); break
    return p


text = open(os.path.join(CM, "eval", "trap-attention.txt"), encoding="utf-8").read()
paras = [x.strip() for x in text.split("\n\n") if x.strip()]
heading, paras = paras[0], paras[1:]
P = {f"P{i+1}": t for i, t in enumerate(paras)}
numbered = "\n\n".join(f"[{k}] {v}" for k, v in P.items())
src = dict(title="The Busy Mind (made-up test text)", authors="Test Author", kind="book")
brief = dict(
    thesis="Doing several jobs at once feels productive but makes work slower and less accurate, because each switch between jobs costs time and attention that people do not notice.",
    outline="3. The sleep laboratory: Marta Ruiz's early career at Northfield.\n4. The Myth of the Busy Mind: the experiment that tested multitasking.\n5. The telephone: what a second job does to a conversation.",
    glossary="(none yet)", people="Marta Ruiz: researcher who ran the sleep laboratory at Northfield.")

ideas = call(WRITER, "extract", **src, **brief, chunk_number=4, chunk_count=9, heading=heading,
             previous_tail="(start of chapter)", numbered_chunk_text=numbered)["ideas"]
print("\n=== IDEAS ===")
kept = []
for n, idea in enumerate(ideas):
    ptxt = " ".join(P.get(p, "") for p in idea["paragraphs"])
    ok = norm(idea["evidence_quote"]) in norm(ptxt)
    if idea["kind"] == "quote":
        ok = ok and norm(idea["quote_text"]) in norm(ptxt)
    idea["ref"] = f"04:{n}"
    print(json.dumps({k: idea[k] for k in ("ref", "importance", "stance", "kind", "title", "claim", "support", "limits", "paragraphs", "evidence_quote", "quote_text", "speaker")}, indent=1, ensure_ascii=False))
    print("EVIDENCE GATE:", "pass" if ok else "FAIL")
    if ok: kept.append(idea)

sel = call(WRITER, "select", **src, thesis=brief["thesis"], budget=4, topic_list="psychology: Psychology\nlearning-and-memory: Learning and memory",
           topics_instruction="one to three ids from the topic list that fit the text best.", existing_titles="(none)",
           ideas="\n".join(f'{i["ref"]} | {i["importance"]} | {i["stance"]} | {i["kind"]} | {i["title"]} | {i["claim"]}' for i in kept))
print("\n=== SELECT ===\n", json.dumps(sel, ensure_ascii=False))
by_ref = {i["ref"]: i for i in kept}
chosen = [c for c in sel["chosen"] if c["ref"] in by_ref]


def idea_block(c):
    i = by_ref[c["ref"]]
    nums = sorted({int(p[1:]) for p in i["paragraphs"] if p in P})
    around = range(max(1, nums[0] - 1), min(len(P), nums[-1] + 1) + 1)
    i["_ptxt"] = "\n".join(P[f"P{n}"] for n in around)
    return (f'Idea ref {i["ref"]}\nformat: {c["format"]}\ntitle: {i["title"]}\nclaim: {i["claim"]}\nsupport: {i["support"]}\n'
            f'limits: {i["limits"] or "(none)"}\nstance: {i["stance"]}\nquote_text: {i["quote_text"] or "(none)"}\nspeaker: {i["speaker"] or "(none)"}\n'
            f'<paragraphs>\n{i["_ptxt"]}\n</paragraphs>')


cards = call(WRITER, "write", **src, **{k: brief[k] for k in ("thesis", "glossary", "people")}, repair_block="",
             idea_count=len(chosen), ideas_with_paragraphs="\n\n".join(idea_block(c) for c in chosen))["cards"]
fmt = {c["ref"]: c["format"] for c in chosen}
print("\n=== CARDS ===")
good = []
for c in cards:
    i = by_ref[c["ref"]]
    c["format"] = fmt[c["ref"]]
    if c["format"] == "quote":
        c["front"], c["speaker"] = i["quote_text"], i["speaker"]
    probs = card_problems(c, i["_ptxt"], text)
    print(json.dumps(c, indent=1, ensure_ascii=False), "\nCODE GATES:", probs or "pass")
    if not probs: good.append(c)

verdicts = call(JUDGE, "judge", **src, thesis=brief["thesis"], card_count=len(good), cards_with_paragraphs="\n\n".join(
    f'Card ref {c["ref"]}\nformat: {c["format"]}\ntitle: {c["title"]}\nfront: {c["front"]}\nback: {c["back"]}\n<paragraphs>\n{by_ref[c["ref"]]["_ptxt"]}\n</paragraphs>' for c in good))["verdicts"]
print("\n=== JUDGE ===")
passed = []
for v in verdicts:
    ok = all(v[k] for k in ("supported", "faithful", "standalone", "complete", "one_idea", "worth"))
    print(json.dumps(v, indent=1, ensure_ascii=False), "\nVERDICT:", "pass" if ok else "FAIL")
    if ok: passed += [c for c in good if c["ref"] == v["ref"]]

passed = passed[:3]
tests = call(WRITER, "quiz", card_count=len(passed), existing_tests="(none)", cards="\n\n".join(
    f'<card>\nref: {c["ref"]}\nformat: {c["format"]}\ntitle: {c["title"]}\nfront: {c["front"]}\nback: {c["back"]}\n</card>' for c in passed))["tests"]
for n, t in enumerate(tests): t["id"] = f't{n}'
print("\n=== TESTS ===")
for t in tests: print(json.dumps(t, ensure_ascii=False))


def blind(c):
    out = f'<card>\nref: {c["ref"]}\ntitle: {c["title"]}\nfront: {c["front"]}\nback: {c["back"]}\n</card>\n'
    for t in tests:
        if t["card"] != c["ref"]: continue
        out += f'<test>\nid: {t["id"]}\ntype: {t["type"]}\nprompt: {t["prompt"]}\n'
        if t["type"] == "multiple_choice": out += "choices: " + json.dumps(t["choices"], ensure_ascii=False) + "\n"
        if t["type"] == "ordering": out += "items (shuffled): " + json.dumps(sorted(t["correct_order"]), ensure_ascii=False) + "\n"
        if t["type"] == "matching": out += "left: " + json.dumps(t["match_left"], ensure_ascii=False) + "\nright (shuffled): " + json.dumps(sorted(t["match_right"]), ensure_ascii=False) + "\n"
        out += "</test>\n"
    return out


solved = call(JUDGE, "solve", cards_with_tests_without_answers="\n".join(blind(c) for c in passed))
print("\n=== SOLVE ===\nunclear:", json.dumps(solved["unclear"], ensure_ascii=False))
key = {t["id"]: t for t in tests}
for a in solved["answers"]:
    t = key.get(a["test"])
    if not t: print("unknown test", a); continue
    if t["type"] == "multiple_choice": agree = a["choice"] == t["correct_choice"]
    elif t["type"] == "true_false": agree = a["is_true"] == t["is_true"]
    elif t["type"] == "ordering": agree = a["order"] == t["correct_order"]
    elif t["type"] == "matching": agree = a["pairs"] == t["match_right"]
    else: agree = None
    print(t["id"], t["type"], "answerable:", a["answerable"], "key agrees:", agree, "| flashcard answer:" if agree is None else "", a["text"] if agree is None else "")
print("\nCALLS (step, model, seconds, output tokens):", CALLS)

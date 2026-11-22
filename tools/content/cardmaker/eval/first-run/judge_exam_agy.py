"""Judge exam through Antigravity CLI. Usage: py -3 judge_exam_agy.py <cardmaker dir> <model slug>"""
import json, os, subprocess, sys, time

CM, MODEL = sys.argv[1], sys.argv[2]
AGY = os.path.expanduser("~/.gemini/bin/agy.exe")
SANDBOX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sandbox")
schema = json.load(open(os.path.join(CM, "schemas.json"), encoding="utf-8"))["judge"]
schema_file = os.path.join(SANDBOX, "judge.schema.json")
json.dump(schema, open(schema_file, "w", encoding="utf-8"))
system, user = open(os.path.join(CM, "prompts", "judge.md"), encoding="utf-8").read().split("\n=====\n", 1)
text = open(os.path.join(CM, "eval", "trap-attention.txt"), encoding="utf-8").read()
paras = [x.strip() for x in text.split("\n\n") if x.strip()][1:]
P = {f"P{i+1}": t for i, t in enumerate(paras)}
cases = json.load(open(os.path.join(CM, "eval", "judge-cases.json"), encoding="utf-8"))["cases"]
exp = json.load(open(os.path.join(CM, "eval", "trap-attention.expect.json"), encoding="utf-8"))
KEYS = ("supported", "faithful", "standalone", "complete", "one_idea", "worth")
wrong = bad_passed = 0
for start in range(0, len(cases), 4):
    batch = cases[start:start + 4]
    blocks = "\n\n".join(
        f'Card ref c{start+n}\nformat: {c["card"]["format"]}\ntitle: {c["card"]["title"]}\nfront: {c["card"]["front"]}\nback: {c["card"]["back"]}\n<paragraphs>\n'
        + "\n".join(P[p] for p in c["paragraphs"]) + "\n</paragraphs>" for n, c in enumerate(batch))
    u = (user.replace("{{title}}", exp["source"]["title"]).replace("{{authors}}", "Test Author").replace("{{kind}}", "book")
         .replace("{{thesis}}", exp["brief"]["thesis"]).replace("{{card_count}}", str(len(batch))).replace("{{cards_with_paragraphs}}", blocks))
    prompt = system.strip() + "\n\nDo not use any tool. Answer from the text below only.\n\n" + u.strip()
    cmd = [AGY, "-p=" + prompt, "--model", MODEL, "--output-format", "json", "--json-schema", schema_file,
           "--sandbox", "--disable-slash-commands", "--print-timeout", "240s"]
    t = time.time()
    out = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, encoding="utf-8", cwd=SANDBOX, timeout=300)
    try:
        reply = json.loads(out.stdout)
    except Exception:
        print("NOT JSON:", out.stdout[:300], out.stderr[:300]); continue
    print(f"[call {round(time.time()-t)}s, prompt chars {len(prompt)}, turns {reply.get('num_turns')}, usage {reply.get('usage')}]")
    so = reply.get("structured_output")
    if not so:
        print("no structured_output:", str(reply)[:300]); continue
    for v in so["verdicts"]:
        c = cases[int(v["ref"][1:])]
        ok = all(v[k] for k in KEYS)
        right = ok == (c["expect"] == "pass")
        wrong += not right
        bad_passed += ok and c["expect"] == "fail"
        print(v["ref"], c["card"]["title"], "| expected", c["expect"], "| got", "pass" if ok else "fail " + ",".join(k for k in KEYS if not v[k]), "| RIGHT" if right else "| WRONG: " + v["problem"][:200])
print(f"{MODEL}: {len(cases) - wrong}/{len(cases)} right, bad cards passed: {bad_passed}")

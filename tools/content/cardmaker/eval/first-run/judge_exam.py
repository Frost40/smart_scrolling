"""Run eval/judge-cases.json through one model as the judge. Usage: py -3 judge_exam.py <cardmaker dir> <model>"""
import json, os, re, subprocess, sys

CM, MODEL = sys.argv[1], sys.argv[2]
SANDBOX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sandbox")
schema = json.load(open(os.path.join(CM, "schemas.json"), encoding="utf-8"))["judge"]
system, user = open(os.path.join(CM, "prompts", "judge.md"), encoding="utf-8").read().split("\n=====\n", 1)
text = open(os.path.join(CM, "eval", "trap-attention.txt"), encoding="utf-8").read()
paras = [x.strip() for x in text.split("\n\n") if x.strip()][1:]
P = {f"P{i+1}": t for i, t in enumerate(paras)}
cases = json.load(open(os.path.join(CM, "eval", "judge-cases.json"), encoding="utf-8"))["cases"]
exp = json.load(open(os.path.join(CM, "eval", "trap-attention.expect.json"), encoding="utf-8"))
env = {k: v for k, v in os.environ.items() if k not in ("CLAUDECODE", "ANTHROPIC_API_KEY", "CLAUDE_CODE_ENTRYPOINT")}
wrong = bad_passed = 0
for start in range(0, len(cases), 4):
    batch = cases[start:start + 4]
    blocks = "\n\n".join(
        f'Card ref c{start+n}\nformat: {c["card"]["format"]}\ntitle: {c["card"]["title"]}\nfront: {c["card"]["front"]}\nback: {c["card"]["back"]}\n<paragraphs>\n'
        + "\n".join(P[p] for p in c["paragraphs"]) + "\n</paragraphs>" for n, c in enumerate(batch))
    u = (user.replace("{{title}}", exp["source"]["title"]).replace("{{authors}}", "Test Author").replace("{{kind}}", "book")
         .replace("{{thesis}}", exp["brief"]["thesis"]).replace("{{card_count}}", str(len(batch))).replace("{{cards_with_paragraphs}}", blocks))
    cmd = ["claude", "-p", "--model", MODEL, "--output-format", "json", "--tools", "", "--strict-mcp-config", "--disable-slash-commands",
           "--setting-sources", "", "--no-session-persistence", "--system-prompt", system.strip(), "--json-schema", json.dumps(schema)]
    out = subprocess.run(cmd, input=u.strip(), capture_output=True, text=True, encoding="utf-8", cwd=SANDBOX, env=env, timeout=300)
    for v in json.loads(out.stdout)["structured_output"]["verdicts"]:
        c = cases[int(v["ref"][1:])]
        ok = all(v[k] for k in ("supported", "faithful", "standalone", "complete", "one_idea", "worth"))
        right = ok == (c["expect"] == "pass")
        wrong += not right
        bad_passed += ok and c["expect"] == "fail"
        failed = [k for k in ("supported", "faithful", "standalone", "complete", "one_idea", "worth") if not v[k]]
        print(v["ref"], c["card"]["title"], "| expected", c["expect"], "| got", "pass" if ok else "fail " + ",".join(failed), "| RIGHT" if right else "| WRONG: " + v["problem"])
print(f"{MODEL}: {len(cases) - wrong}/{len(cases)} right, bad cards passed: {bad_passed}")

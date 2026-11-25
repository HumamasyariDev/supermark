import sys, json, subprocess, concurrent.futures as cf
from pathlib import Path
stats = json.loads(Path("reports/bank_stats.json").read_text())
keys = [k for k in stats if k.startswith(sys.argv[1])]
P = "Describe this single short sound effect in under 20 words (what physical or cartoon sound it is). Then, on a new line starting with GUESS:, guess what video game action or event it would accompany. Mention any speech, music, noise or distortion."
def one(k):
    name = "one_" + k.replace("/", "_")
    r = subprocess.run([sys.executable, "tools/listen.py", "../" + stats[k]["file"], name, P], capture_output=True, text=True)
    try:
        t = json.loads(Path(f"reports/listen_{name}.json").read_text())["result"].get("output", "")
    except Exception as e:
        t = "ERROR " + r.stderr[-300:]
    return k, t
with cf.ThreadPoolExecutor(8) as ex:
    for k, t in ex.map(one, keys):
        lines = [l.strip() for l in t.splitlines() if l.strip()]
        desc = " ".join(lines[:3])[:300]
        print(f"{k:28s} | {desc}")

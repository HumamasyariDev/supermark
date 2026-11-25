"""Blind AI listen-check (fal-ai/audio-understanding, not told the intent) of the round-6 NPC greeting takes.
These are short non-verbal voices; the model is used to catch wrong sources (speech, animals, music, noise), and the
pick is made with the measurements in review/r6/stats.json. Usage (from _src): python tools/listen_r6.py"""
import sys, json, subprocess, concurrent.futures as cf
from pathlib import Path
P = ("Describe what you hear in under 25 words: who or what makes the sound (person: age and gender; animal: which), "
     "the emotion, and anything wrong (words, music, clicks, distortion, abrupt cuts, background noise).")
takes = sorted(Path("review/r6").glob("r6_*.ogg"))
def one(f):
    name = f.stem
    subprocess.run([sys.executable, "tools/listen.py", str(f), name, P], capture_output=True, text=True)
    try:
        t = json.loads(Path(f"reports/listen_{name}.json").read_text())["result"].get("output", "")
    except Exception as e:
        t = f"ERROR {e}"
    return name, " ".join(l.strip() for l in t.splitlines() if l.strip())[:300]
out = {}
with cf.ThreadPoolExecutor(8) as ex:
    for k, t in ex.map(one, takes):
        out[k] = t
        print(f"{k:26s} | {t}")
Path("reports/listen_r6_summary.json").write_text(json.dumps(out, indent=1))

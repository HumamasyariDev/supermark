"""Blind AI listen-check (fal-ai/audio-understanding) of round-5 sounds longer than about 1 s and of the five ambience beds.
The model is not told what the sound should be; its description is compared with the intent afterwards. Short SFX are
judged by measurements instead (the model was unreliable on them in round 1). Usage (from _src): python tools/listen_r5.py"""
import sys, json, subprocess, concurrent.futures as cf
from pathlib import Path
P = ("Describe what you hear in under 30 words: the sound sources, whether it is a one-off event or a continuous "
     "background, and anything wrong (speech, music, clicks, distortion, abrupt cuts). Then, on a new line starting with "
     "GUESS:, say what place or video game event it would accompany.")
ITEMS = {
    "amb_w1_bed": "countryside meadow: birds and breeze", "amb_w2_bed": "high-altitude wind and distant wind chimes",
    "amb_w3_bed": "bubbling hot chocolate and candy crunch", "amb_hub_bed": "fireplace crackle and a ticking clock",
    "amb_boss_bed": "storm: wind, rain, thunder", "giant_snore": "a giant snoring", "giant_sneeze": "a giant sneezing",
    "giant_inhale": "a giant's deep inhale", "boss_growl": "a big cartoon wolf growl", "boss_hurt": "a big cartoon wolf yelping in pain",
    "trial_fail": "sad trombone wah-wah", "gummy_melt": "gummy candy melting into goo", "boss_balloon": "balloon inflating then deflating away",
    "great_truffle_appear": "magical golden reveal shimmer", "death": "dizzy faint: slide whistle down and a thud",
    "thunder": "distant rolling thunder", "chimney_smash": "brick chimney bursting apart", "boss_tornado_loop": "swirling tornado wind",
}
def one(k):
    name = "r5_" + k
    subprocess.run([sys.executable, "tools/listen.py", f"../sfx/{k}.ogg", name, P], capture_output=True, text=True)
    try:
        t = json.loads(Path(f"reports/listen_{name}.json").read_text())["result"].get("output", "")
    except Exception as e:
        t = f"ERROR {e}"
    return k, t
out = {}
with cf.ThreadPoolExecutor(8) as ex:
    for k, t in ex.map(one, ITEMS):
        lines = [l.strip() for l in t.splitlines() if l.strip()]
        out[k] = {"intent": ITEMS[k], "heard": " ".join(lines[:3])[:400]}
        print(f"{k:22s} | intent: {ITEMS[k]}\n{'':22s} | heard: {out[k]['heard']}")
Path("reports/listen_r5_summary.json").write_text(json.dumps(out, indent=1))

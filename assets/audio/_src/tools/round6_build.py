"""Round 6: install the picked NPC greeting takes as sfx/npc_greet_<voice>[_n].ogg (trimmed, onset-aligned, mono).
Picks from the spectrogram sheet (Docs/progress/audio/20261017T231641Z__r6_npc_greet_takes_sheet.png), the blind
listen-check (reports/listen_r6_summary.json) and pitch estimates: all three butler takes rejected (formant
transitions of spoken words; the judge heard "Sure, no problem" / "enjoyed"), piglet t2 (a sustained wail), cow t2 (a
human hum), granny t3 (young, f0 394 Hz), boy t1 (0.43 s, too clipped)."""
import sys, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import round5_build as B

PICKS = {"npc_greet_piglet": ["t3", "t1"], "npc_greet_cow": ["t3", "t1"], "npc_greet_boy": ["t2", "t3"],
         "npc_greet_granny": ["t2", "t1"]}
rep = B.SRC / "reports" / "round6_stats.json"
st = {}
for name, takes in PICKS.items():
    for i, t in enumerate(takes):
        out = B.AUD / "sfx" / (f"{name}.ogg" if i == 0 else f"{name}_{i + 1}.ogg")
        r = B.oneshot(B.RAW / f"r6_{name}_{t}.mp3", out)
        r["source"] = f"raw/r6_{name}_{t}.mp3"
        st["sfx/" + out.stem] = r
        print(out.stem, r["duration_s"])
rep.write_text(json.dumps(st, indent=1, default=float))

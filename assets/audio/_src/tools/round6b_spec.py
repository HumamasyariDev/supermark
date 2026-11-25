"""Round 6b: keys that game scripts call but the bank lacked (found by the implementation-stage audit of
call("play_sfx", ...) and wrapper calls): door_slam (hub intro, the wolf slams the library door), sfx_seed_whoosh
(W2 descent: Mak grabs a bean seed and jumps), enemy_flap (crow bandit wing flaps). 3 takes each, ElevenLabs SFX v2."""
import json
from pathlib import Path

SRC = Path(__file__).resolve().parents[1]
PRE = "Cartoon storybook video game sound effect, clean, isolated, no music, no voice: "
P = {
    "door_slam": (PRE + "a heavy old wooden library door slams shut with a deep boom and a short rattle of iron fittings", 1.4),
    "seed_whoosh": (PRE + "a magical upward whoosh with a leafy rustle and a bright sparkle, a big bean seed launching into the sky", 1.5),
    "enemy_flap": (PRE + "two quick strong flaps of a large crow's feathered wings, close", 0.8),
}
jobs = []
for key, (text, dur) in P.items():
    for t in (1, 2, 3):
        jobs.append({"key": f"r6b_{key}_t{t}", "endpoint": "fal-ai/elevenlabs/sound-effects/v2",
                     "input": {"text": text, "duration_seconds": dur, "prompt_influence": 0.6, "output_format": "mp3_44100_192"},
                     "quoted_unit": "second @ $0.002", "quoted_qty": dur, "estimated_usd": round(dur * 0.002, 4),
                     "max_reserved_usd": round(dur * 0.0025, 4)})
(SRC / "jobs" / "round6b_spec.json").write_text(json.dumps({"phase": "night01-audio-impl-round6b-missing-keys", "jobs": jobs}, indent=1))
print(len(jobs), "jobs, est $%.3f" % sum(j["estimated_usd"] for j in jobs))

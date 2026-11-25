"""Round 6 (night 01 implementation stage): per-speaker NPC greeting vocals for object_npc_greet (the greeting was a
generic chime for every NPC). Non-verbal on purpose (no words to mis-transcribe or localise). 3 takes each,
fal-ai/elevenlabs/sound-effects/v2 at $0.002/s. Writes _src/jobs/round6_spec.json; run gen_audio.py on it."""
import json
from pathlib import Path

SRC = Path(__file__).resolve().parents[1]
PRE = "Cartoon storybook video game character voice sound, clean, isolated, close mic, dry, no music, no reverb: "
P = {
    "npc_greet_piglet": (PRE + "a cheerful young piglet gives a happy little two-note 'oink-oink!' greeting with a short giggle", 1.3),
    "npc_greet_cow": (PRE + "a friendly gentle cow gives one short warm cheerful 'mooo' greeting", 1.5),
    "npc_greet_boy": (PRE + "a young boy gasps a happy surprised 'oh!' followed by a tiny delighted laugh, no words", 1.2),
    "npc_greet_granny": (PRE + "a kindly old grandmother gives a warm delighted 'ooh!' hum of welcome, no words", 1.3),
    "npc_greet_butler": (PRE + "an elderly English butler politely clears his throat, one soft dignified 'ahem'", 1.1),
}
jobs = []
for key, (text, dur) in P.items():
    for t in (1, 2, 3):
        jobs.append({"key": f"r6_{key}_t{t}", "endpoint": "fal-ai/elevenlabs/sound-effects/v2",
                     "input": {"text": text, "duration_seconds": dur, "prompt_influence": 0.55, "output_format": "mp3_44100_192"},
                     "quoted_unit": "second @ $0.002", "quoted_qty": dur, "estimated_usd": round(dur * 0.002, 4),
                     "max_reserved_usd": round(dur * 0.0025, 4)})
spec = {"phase": "night01-audio-impl-round6-npc-greets", "jobs": jobs}
(SRC / "jobs" / "round6_spec.json").write_text(json.dumps(spec, indent=1))
print(len(jobs), "jobs, est $%.3f" % sum(j["estimated_usd"] for j in jobs))

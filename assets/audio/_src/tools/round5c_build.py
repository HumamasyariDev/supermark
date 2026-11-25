"""Round 5c: second attempts for the six sounds the blind listen-check rejected (giant_sneeze, giant_inhale, boss_growl,
boss_hurt, boss_balloon, chimney_smash) -> sfx/<name>.ogg and sfx/<name>_2.ogg (takes 1 and 2), plus amb_storm_loop
re-looped with a 0.5 s crossfade (its seam measured 1.04 x the file's p99 step)."""
import sys, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import round5_build as B

st = json.loads(B.REP.read_text())
# takes kept after the second blind listen-check: boss_hurt take 1 was distorted ("NO!" clipped) and boss_balloon take 1
# read as an engine whine, so only take 2 ships for those two
KEEP = {"giant_inhale": (1, 2), "boss_growl": (1, 2), "boss_hurt": (2,), "boss_balloon": (2,), "chimney_smash": (1, 2)}
for n, takes in KEEP.items():
    for i, t in enumerate(takes):
        raw = B.RAW / f"r5c_{n}_t{t}.mp3"
        out = B.AUD / "sfx" / (f"{n}.ogg" if i == 0 else f"{n}_2.ogg")
        r = B.oneshot(raw, out)
        r["source"] = "raw/" + raw.name
        st["sfx/" + out.stem] = r
        print(out.stem, r["duration_s"], r.get("lufs"))
r = B.loop(B.RAW / "sfx_amb_storm_loop.mp3", B.AUD / "sfx" / "amb_storm_loop.ogg", xf_s=0.5, stereo=True, lufs=-22.0)
r["source"] = "raw/sfx_amb_storm_loop.mp3 (0.5 s crossfade)"
st["sfx/amb_storm_loop"] = r
print("amb_storm_loop", r["seam_before"], r["seam_after"])
B.REP.write_text(json.dumps(st, indent=1, default=float))

# Neither sneeze take had a burst (flat 1.5 s level, the listen-check heard a moo and a groan), and two paid attempts is
# the limit, so the sneeze is composed: a giant inhale (rising, faded in) + 80 ms hold + a breath blast.
import numpy as np
import audiolib as A
B.REP.write_text(json.dumps(st, indent=1, default=float))
for out_name, inhale, blast in [("giant_sneeze", "giant_inhale.ogg", "boss_huff_blast.ogg"), ("giant_sneeze_2", "giant_inhale_2.ogg", "wolf_gust.ogg")]:
    a = A.decode(B.AUD / "sfx" / inhale, ch=1)[: int(1.3 * A.SR)].copy()
    a *= (np.linspace(0.15, 1.0, len(a)) ** 1.5)[:, None]          # build-up: "ahh... ahh..."
    a[-int(0.06 * A.SR):] *= np.linspace(1, 0, int(0.06 * A.SR))[:, None]
    b = A.decode(B.AUD / "sfx" / blast, ch=1) * 1.6                  # the "CHOO"
    y = np.concatenate([a, np.zeros((int(0.08 * A.SR), 1), np.float32), b])
    r = B.finish(y, B.AUD / "sfx" / f"{out_name}.ogg")
    r["source"] = f"composed: sfx/{inhale} (first 1.3 s, rising fade) + 80 ms + sfx/{blast}"
    st["sfx/" + out_name] = r
    print(out_name, r["duration_s"])
B.REP.write_text(json.dumps(st, indent=1, default=float))

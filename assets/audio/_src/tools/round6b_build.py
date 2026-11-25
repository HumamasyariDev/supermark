"""Round 6b install: door_slam (t2 boom + rattle, t1), seed_whoosh (t1, t2) from ElevenLabs takes, and enemy_flap made
procedurally: all three generated flap takes carried strong harmonic lines at 0.5/1/2 kHz (a voiced caw, not feathers;
Docs/progress/audio/20261017T233407Z__r6b_missing_keys_takes_sheet.png), so the flaps are band-passed noise bursts with a
low 'whump' body, two or three beats per take. sfx_seed_whoosh (the key w2_descent.gd calls) is an alias in make_index."""
import sys, json
from pathlib import Path
import numpy as np
from scipy.signal import butter, sosfilt
sys.path.insert(0, str(Path(__file__).parent))
import round5_build as B
import audiolib as A

st = {}
for name, takes in {"door_slam": ["t2", "t1"], "seed_whoosh": ["t1", "t2"]}.items():
    for i, t in enumerate(takes):
        out = B.AUD / "sfx" / (f"{name}.ogg" if i == 0 else f"{name}_{i + 1}.ogg")
        r = B.oneshot(B.RAW / f"r6b_{name}_{t}.mp3", out)
        r["source"] = f"raw/r6b_{name}_{t}.mp3"
        st["sfx/" + out.stem] = r
        print(out.stem, r["duration_s"])

SR = A.SR
rng = np.random.default_rng(64)


def flap(times, gains, band=(350, 2600), body=(90, 380), dur=0.62):
    n = int(dur * SR)
    y = np.zeros(n)
    hi = butter(4, band, btype="bandpass", fs=SR, output="sos")
    lo = butter(2, body, btype="bandpass", fs=SR, output="sos")
    for t0, g in zip(times, gains):
        a = int(t0 * SR)
        L = int(0.16 * SR)
        tt = np.arange(L) / SR
        env = np.minimum(1.0, tt / 0.012) * np.exp(-tt / 0.045)
        noise = rng.standard_normal(L + 2048)
        air = sosfilt(hi, noise)[2048:] * env
        whump = sosfilt(lo, rng.standard_normal(L + 2048))[2048:] * np.minimum(1.0, tt / 0.008) * np.exp(-tt / 0.03) * 1.6
        seg = (air + whump) * g
        y[a:a + L] += seg[: max(0, min(L, n - a))]
    y /= np.max(np.abs(y)) + 1e-9
    return (y * 0.5).reshape(-1, 1)


for i, (times, gains, band) in enumerate([([0.0, 0.14], [1.0, 0.8], (350, 2600)), ([0.0, 0.12, 0.25], [0.9, 1.0, 0.7], (300, 2300)),
                                          ([0.0, 0.16], [1.0, 0.9], (420, 3000))]):
    out = B.AUD / "sfx" / ("enemy_flap.ogg" if i == 0 else f"enemy_flap_{i + 1}.ogg")
    r = B.finish(flap(times, gains, band), out)
    r["source"] = "procedural (round6b_build.py flap())"
    st["sfx/" + out.stem] = r
    print(out.stem, r["duration_s"])
(B.SRC / "reports" / "round6b_stats.json").write_text(json.dumps(st, indent=1, default=float))

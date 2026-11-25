"""Round 5b: single-take footsteps per surface (<= 0.30 s) and UI text blips (<= 0.16 s) -> sfx/footstep_<surface>_r<n>.ogg,
sfx/ui_text_blip_<n>.ogg. Round-5 sliced sequences were rejected (a steady 0.8-1 kHz tone ran under every step and slices held 2-3 hits)."""
import sys, json
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A
import round5_build as B

st = json.loads(B.REP.read_text())


# Shaping (added after the first sheet): the raw takes were 0.3 s of sustained noise with no clear transient, so each
# take gets a fast attack and an exponential decay per surface (tau, seconds) plus a band-limit, then the length cap.
SHAPE = {"grass": (0.055, 150, 9000), "wood": (0.035, 90, 7000), "stone": (0.028, 150, 11000), "candy": (0.045, 200, 12000),
         "carpet": (0.040, 70, 3200), "jelly": (0.070, 80, 5000), "metal": (0.050, 200, 14000), "cloud": (0.065, 90, 4000),
         "blip": (0.030, 200, 9000)}


def shape(y, kind):
    import scipy.signal as ss
    tau, hp, lp = SHAPE[kind]
    sos = ss.butter(2, [hp, lp], btype="bandpass", fs=A.SR, output="sos")
    y = ss.sosfilt(sos, y, axis=0).astype(np.float32)
    f, hop = A.frame_rms_db(y, hop_ms=2)
    pk = int(np.argmax(f[: max(1, int(0.08 * A.SR / hop))])) * hop  # loudest moment in the first 80 ms = the plant
    t = np.arange(len(y)) / A.SR
    env = np.where(np.arange(len(y)) < pk, 1.0, np.exp(-(t - pk / A.SR) / tau)).astype(np.float32)
    y = y[: len(env)] * env[:, None]
    keep = min(len(y), pk + int(tau * 5.0 * A.SR))
    return y[:keep]


def cut(raw, out, max_s, fo_s, rel_db=40, kind=None):
    x = A.decode(raw, ch=1)
    y, _ = A.trim(x, rel_db=rel_db, pre_ms=3, post_ms=50, fade_in_ms=2, fade_out_ms=40)
    if kind:
        y = shape(y, kind)
    n = int(max_s * A.SR)
    if len(y) > n:
        y = y[:n].copy()
        fo = int(fo_s * A.SR)
        y[-fo:] *= (np.linspace(1, 0, fo) ** 2)[:, None]
    r = B.finish(y, out)
    r["source"] = "raw/" + Path(raw).name
    st["sfx/" + out.stem] = r
    print(out.stem, r["duration_s"], r["active_rms_dbfs"])


for s in ["grass", "wood", "stone", "candy", "carpet", "jelly", "metal", "cloud"]:
    n = 0
    for t in range(4):
        raw = B.RAW / f"r5b_step_{s}_t{t + 1}.mp3"
        if raw.exists():
            n += 1
            cut(raw, B.AUD / "sfx" / f"footstep_{s}_r{n}.ogg", 0.30, 0.03, kind=s)
for t in range(4):
    raw = B.RAW / f"r5b_ui_blip_t{t + 1}.mp3"
    if raw.exists():
        cut(raw, B.AUD / "sfx" / f"ui_text_blip_{t + 1}.ogg", 0.16, 0.02, kind="blip")
B.REP.write_text(json.dumps(st, indent=1, default=float))

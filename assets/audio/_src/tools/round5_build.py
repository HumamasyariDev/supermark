"""Process round-5 raw generations into runtime .ogg files.
- 'q' sequences (footsteps per surface, UI blips) are sliced into single hits by onset detection; the most consistent
  hits are kept (loudness within 4 dB of the median, no clipped tails), each normalised to the SFX level.
- one-shots: silence trimmed, 2 ms fade-in, short fade-out, active RMS -16 dBFS, peak <= -1 dBFS, mono.
- loops: equal-power crossfade of the tail into the head (120 ms), seam measured before and after.
- ambience beds: both layers made into seamless loops (1.5 s crossfade), layer B mixed at -5 dB under A,
  stereo, normalised to -22 LUFS integrated, true peak <= -3 dBTP.
Writes _src/reports/round5_stats.json. Usage: python _src/tools/round5_build.py [--only name1,name2]
"""
import sys, json, hashlib
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A
import round5_spec as S

SRC = Path(__file__).resolve().parents[1]
AUD = SRC.parent
RAW = SRC / "raw"
TMP = SRC / "review" / "_tmp_r5.wav"
REP = SRC / "reports" / "round5_stats.json"
stats = json.loads(REP.read_text()) if REP.exists() else {}


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def seam_jump(y):
    """Sample jump at the loop seam relative to the 99th percentile sample step (below 1.0 = no click: smaller than the audio's own steps)."""
    d = np.abs(np.diff(y, axis=0)).max(axis=1)
    med = float(np.percentile(d, 99)) + 1e-9
    j = float(np.max(np.abs(y[-1] - y[0])))
    return round(j / med, 2), round(j, 5)


def finish(y, out, target_rms=-16.0, ceiling=-1.0, lufs=None, tp=None):
    if lufs is not None:
        I, _ = A.lufs_array(y, TMP)
        y = y * (10 ** ((lufs - I) / 20))
    else:
        y = y * (10 ** ((target_rms - A.active_rms_db(y)) / 20))
    if A.peak_db(y) > ceiling:
        y = A.limiter(y, ceiling)
    out.parent.mkdir(parents=True, exist_ok=True)
    A.encode_ogg(y, out)
    st = {"file": str(out.relative_to(AUD)).replace("\\", "/"), "duration_s": round(len(y) / A.SR, 3), "channels": int(y.shape[1]),
          "peak_dbfs": round(A.peak_db(y), 2), "active_rms_dbfs": round(A.active_rms_db(y), 2)}
    if len(y) / A.SR >= 0.45:
        I, t = A.lufs_file(out)
        st.update(lufs=I, true_peak=t)
    st["sha256"] = sha(out)
    return st


def onsets(x, hop_ms=5, rise_db=14, min_gap=0.30, rel=32):
    f, hop = A.frame_rms_db(x, hop_ms=hop_ms)
    floor = np.percentile(f, 20)
    thr = max(floor + rise_db, f.max() - rel)
    out = []
    last = -1e9
    for i in range(1, len(f)):
        if f[i] >= thr and f[i - 1] < thr and (i * hop - last) / A.SR >= min_gap:
            out.append(i * hop)
            last = i * hop
    return out


def slice_seq(name, max_len, keep, prefix, **kw):
    x = A.decode(RAW / f"r5_{name}.mp3", ch=1)
    on = onsets(x, **kw)
    hits = []
    for k, s in enumerate(on):
        a = max(0, s - int(0.006 * A.SR))
        b = min(len(x), on[k + 1] - int(0.004 * A.SR) if k + 1 < len(on) else len(x))
        b = min(b, a + int(max_len * A.SR))
        seg = x[a:b].copy()
        seg, _ = A.trim(seg, rel_db=40, pre_ms=3, post_ms=40, fade_in_ms=2, fade_out_ms=int(max_len * 250))
        if len(seg) < int(0.04 * A.SR):
            continue
        hits.append((A.active_rms_db(seg), seg))
    if not hits:
        return {"error": "no onsets", "onsets": len(on)}
    med = float(np.median([h[0] for h in hits]))
    good = [h for h in hits if abs(h[0] - med) <= 4.0]
    good = sorted(good, key=lambda h: abs(h[0] - med))[:keep]
    res = {"onsets": len(on), "hits": len(hits), "kept": len(good), "files": []}
    for i, (_, seg) in enumerate(good):
        out = AUD / "sfx" / f"{prefix}_{i + 1}.ogg"
        st = finish(seg, out)
        st["source"] = f"raw/r5_{name}.mp3 hit {i + 1}"
        stats[f"sfx/{prefix}_{i + 1}"] = st
        res["files"].append(st["file"])
    return res


def align_onset(y, rel_db=24, pre_ms=4):
    """Drop quiet pre-roll: start 4 ms before the first 5 ms frame within 24 dB of the peak frame, so gameplay sounds
    land on the frame of the action (several takes had 50-150 ms of low noise before the hit)."""
    f, hop = A.frame_rms_db(y, hop_ms=5)
    i = int(np.argmax(f >= f.max() - rel_db))
    s = max(0, i * hop - int(pre_ms * A.SR / 1000))
    y = y[s:].copy()
    fi = int(0.002 * A.SR)
    y[:fi] *= np.linspace(0, 1, fi)[:, None]
    return y, s / A.SR


def oneshot(raw, out, footstep=False):
    x = A.decode(raw, ch=1)
    y, _ = A.trim(x, rel_db=48, pre_ms=5, post_ms=90, fade_in_ms=2, fade_out_ms=60)
    y, cut_s = align_onset(y)
    st = finish(y, out)
    st["preroll_cut_s"] = round(cut_s, 3)
    return st


def steady_loop(raw, out, seg_s=1.6, xf_s=0.15):
    """Loop from the steadiest window (lowest level spread) of a take whose level dips (belly slide)."""
    x = A.decode(raw, ch=1)
    f, hop = A.frame_rms_db(x, hop_ms=20)
    w = int(seg_s * A.SR / hop)
    best = min(range(0, len(f) - w), key=lambda i: float(np.std(f[i:i + w])) - 0.05 * float(np.mean(f[i:i + w])))
    a = best * hop
    seg = x[a:a + int((seg_s + xf_s) * A.SR)]
    xf = int(xf_s * A.SR)
    y = A.equal_power_crossfade_loop(seg, len(seg) - xf, xf)
    st = finish(y, out, -20.0)
    st.update(loop=True, window_s=[round(a / A.SR, 2), round(a / A.SR + seg_s, 2)], seam_after=seam_jump(A.decode(out, ch=1)))
    return st


def loop(raw, out, xf_s=0.12, stereo=False, lufs=None):
    x = A.decode(raw, ch=2 if stereo else 1)
    before = seam_jump(x)
    xf = int(xf_s * A.SR)
    y = A.equal_power_crossfade_loop(x, len(x) - xf, xf)
    st = finish(y, out, -20.0, lufs=lufs, ceiling=-3.0 if lufs else -1.0)
    st.update(loop=True, seam_before=before, seam_after=seam_jump(A.decode(out, ch=2 if stereo else 1)))
    return st


def bed(area):
    # W2 layer A was replaced (round 5d): the first take was a steady electronic hum (blind listen-check), take 2 of the
    # re-prompt is broadband wind
    raw_a = RAW / ("r5d_amb_w2_a_t2.mp3" if area == "w2" else f"r5_amb_{area}_a.mp3")
    a = A.decode(raw_a, ch=2)
    b = A.decode(RAW / f"r5_amb_{area}_b.mp3", ch=2)
    xf = int(1.5 * A.SR)
    la = A.equal_power_crossfade_loop(a, len(a) - xf, xf)
    lb = A.equal_power_crossfade_loop(b, len(b) - xf, xf)
    n = min(len(la), len(lb))
    # offset layer B by a third so the two layers' own seams never coincide
    lb = np.roll(lb[:n], n // 3, axis=0)
    la = la[:n]
    ga = 10 ** ((-22 - A.lufs_array(la, TMP)[0]) / 20)
    # layer B level: W2's chimes masked the wind at -5 dB (blind listen-check heard only "chimes and bells"), so -8 there
    gb = 10 ** (({"w2": -30}.get(area, -27) - A.lufs_array(lb, TMP)[0]) / 20)
    y = la * ga + lb * gb
    out = AUD / "sfx" / f"amb_{area}_bed.ogg"
    st = finish(y, out, lufs=-22.0, ceiling=-3.0)
    st.update(loop=True, layers=["raw/" + raw_a.name, f"raw/r5_amb_{area}_b.mp3 (rolled 1/3, {'-8' if area == 'w2' else '-5'} dB)"],
              seam_after=seam_jump(A.decode(out, ch=2)))
    return st


def main():
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    report = {}
    for name, (txt, sec, takes, kind) in S.J.items():
        if only and name not in only:
            continue
        try:
            if kind == "q":
                continue  # rejected after review (steady ~1 kHz tone under every step, 2-3 hits per slice); see round5b_build.py
                if name.startswith("seq_step_"):
                    report[name] = slice_seq(name, 0.26, 6, "footstep_" + name[9:] + "_n")
                else:
                    report[name] = slice_seq(name, 0.14, 6, "ui_text_blip", min_gap=0.09, rise_db=6, rel=45)
            elif kind == "a":
                if name.endswith("_a"):
                    area = name[4:-2]
                    st = bed(area)
                    stats[f"sfx/amb_{area}_bed"] = st
                    report[name] = st
            elif kind == "l" and name == "belly_slide_loop":
                st = steady_loop(RAW / f"r5_{name}.mp3", AUD / "sfx" / f"{name}.ogg")
                st["source"] = f"raw/r5_{name}.mp3"
                stats[f"sfx/{name}"] = st
                report[name] = st
            elif kind == "l":
                st = loop(RAW / f"r5_{name}.mp3", AUD / "sfx" / f"{name}.ogg")
                st["source"] = f"raw/r5_{name}.mp3"
                stats[f"sfx/{name}"] = st
                report[name] = st
            else:
                for t in range(takes):
                    rk = f"r5_{name}" + (f"_t{t + 1}" if takes > 1 else "")
                    out = AUD / "sfx" / (f"{name}.ogg" if t == 0 else f"{name}_{t + 1}.ogg")
                    st = oneshot(RAW / f"{rk}.mp3", out)
                    st["source"] = f"raw/{rk}.mp3"
                    stats["sfx/" + out.stem] = st
                    report[out.stem] = st
        except Exception as e:  # keep going; report the failure
            report[name] = {"error": f"{type(e).__name__}: {e}"}
    REP.write_text(json.dumps(stats, indent=1, default=float))
    for k, v in report.items():
        if "error" in v:
            print("ERR", k, v)
        elif "files" in v:
            print(f"{k:24s} onsets {v['onsets']} hits {v['hits']} kept {v['kept']}")
        else:
            print(f"{k:24s} {v['duration_s']:6.2f}s pk {v['peak_dbfs']:6.1f} rms {v['active_rms_dbfs']:6.1f} lufs {v.get('lufs')}"
                  + (f" seam {v.get('seam_before')}->{v.get('seam_after')}" if v.get("loop") else ""))


if __name__ == "__main__":
    main()

"""Find musically matched loop points (beat grid, 4-bar multiples) and render seamless loops.
Usage: python make_loops.py <raw.mp3> <out.ogg> <min_s> <max_s> [--start-min 2] [--report out.json]"""
import sys, json
import numpy as np, librosa
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A


def find_loop(path, min_s, max_s, start_min=2.0, start_max=24.0, end_guard=10.0):
    y, sr = librosa.load(str(path), sr=22050, mono=True)
    dur = len(y) / sr
    tempo, beats = librosa.beat.beat_track(y=y, sr=sr, trim=False)
    bt = librosa.frames_to_time(beats, sr=sr)
    hop = 512
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=hop)
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=20, hop_length=hop)
    rms = librosa.feature.rms(y=y, hop_length=hop)[0]
    feat = np.vstack([chroma * 2.0, (mfcc - mfcc.mean(1, keepdims=True)) / (mfcc.std(1, keepdims=True) + 1e-6) * 0.5])
    bfeat = librosa.util.sync(feat, beats, aggregate=np.mean)  # per beat interval
    brms = librosa.util.sync(rms[None, :], beats, aggregate=np.mean)[0]
    nb = bfeat.shape[1]
    W = 8
    def win(i):
        return bfeat[:, i:i + W].flatten()
    best = None
    beat_len = float(np.median(np.diff(bt))) if len(bt) > 2 else 0.5
    for i in range(nb - W):
        if not (start_min <= bt[i] <= start_max):
            continue
        for j in range(i + 16, nb - W, 1):
            L = bt[j] - bt[i]
            if L < min_s or L > max_s or bt[j] > dur - end_guard:
                continue
            nbeats = j - i
            a, b = win(i), win(j)
            cos = float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))
            # also the beats before the cut points should resemble each other (approach)
            if i >= 4:
                a2, b2 = bfeat[:, i - 4:i].flatten(), bfeat[:, j - 4:j].flatten()
                cos2 = float(np.dot(a2, b2) / (np.linalg.norm(a2) * np.linalg.norm(b2) + 1e-9))
            else:
                cos2 = cos
            lvl = -abs(20 * np.log10((brms[i] + 1e-6) / (brms[j] + 1e-6))) * 0.05
            bar_bonus = 0.08 if nbeats % 16 == 0 else (0.03 if nbeats % 8 == 0 else (0.0 if nbeats % 4 == 0 else -0.1))
            score = cos + 0.5 * cos2 + lvl + bar_bonus + 0.0005 * L
            if best is None or score > best["score"]:
                best = {"score": score, "start": float(bt[i]), "end": float(bt[j]), "beats": int(nbeats), "cos": cos, "cos_pre": cos2}
    return best, float(np.atleast_1d(tempo)[0]), beat_len, dur


def render(path, out, best, beat_len, target_lufs=-16.0, tmp=None, intro=False):
    # NOTE: intro=True relies on Ogg loop_offset, which misbehaved in Godot 4.7 (see ../../README.md). Not used.
    x = A.decode(path)
    sr = A.SR
    s = int(round(best["start"] * sr)); e = int(round(best["end"] * sr))
    xf = int(sr * float(np.clip(beat_len, 0.4, 1.0)))
    if intro:
        # Intro once, then loop [s, e) via Godot loop_offset = s. The file's last xf samples crossfade into the
        # audio that precedes s, so the jump from e back to s continues naturally (first pass stays untouched).
        loop = x[:e].copy()
        t = np.linspace(0, 1, xf)[:, None]
        loop[e - xf:e] = x[e - xf:e] * np.cos(t * np.pi / 2) + x[s - xf:s] * np.sin(t * np.pi / 2)
    else:
        seg = x[s:e + xf]
        loop = A.equal_power_crossfade_loop(seg, e - s, xf)
    I, tp = A.lufs_array(loop, tmp)
    gain = target_lufs - I
    loop = loop * (10 ** (gain / 20))
    limited = False
    if A.peak_db(loop) > -1.0:
        loop = A.limiter(loop, -1.0)
        limited = True
    A.encode_ogg(loop, out)
    I2, tp2 = A.lufs_file(out)
    # seam check: sample jump and short-window RMS either side of the wrap point
    w = int(0.05 * sr)
    seam_jump = float(np.max(np.abs(loop[0] - loop[-1])))
    rms_end, rms_start = A.rms_db(loop[-w:]), A.rms_db(loop[:w])
    if intro:
        w = int(0.05 * sr)
        seam_jump = float(np.max(np.abs(loop[-1] - loop[s])))
        rms_end, rms_start = A.rms_db(loop[-w:]), A.rms_db(loop[s:s + w])
    return {"intro": intro, "loop_offset_s": (s / sr) if intro else 0.0, "loop_s": (e - s) / sr, "crossfade_s": xf / sr, "measured_input_lufs": I, "gain_db": gain, "limited": limited,
            "out_lufs": I2, "out_true_peak": tp2, "seam_sample_jump": seam_jump, "seam_rms_end_db": rms_end, "seam_rms_start_db": rms_start}


if __name__ == "__main__":
    raw, out, mn, mx = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
    a = sys.argv[5:]
    smin = float(a[a.index("--start-min") + 1]) if "--start-min" in a else 2.0
    smax = float(a[a.index("--start-max") + 1]) if "--start-max" in a else 24.0
    best, tempo, bl, dur = find_loop(raw, mn, mx, start_min=smin, start_max=smax, end_guard=8.0)
    tmp = str(Path(__file__).resolve().parents[1] / "review" / ("_tmp_" + Path(out).stem + ".wav"))
    info = render(raw, out, best, bl, tmp=tmp, intro="--intro" in a)
    Path(tmp).unlink(missing_ok=True)
    rep = {"source": raw, "out": out, "source_duration": dur, "tempo_est": tempo, "loop": best, **info}
    print(json.dumps(rep, indent=1))
    if "--report" in a:
        Path(a[a.index("--report") + 1]).write_text(json.dumps(rep, indent=1))

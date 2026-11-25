"""Fix stage round 1 (critique r1, audio director + QA): offline rebuilds from files already in the bank or in _src/raw.
No paid calls. Every step is idempotent: outputs are rebuilt from sources, never from their own previous output.

  beds     separate ambience layers with co-prime loop lengths (A 20.5 s, B 13.7-17.3 s) so the combined pattern
           no longer repeats every 20.5 s; the hub clock layer is low-passed at 4 kHz and sits 8 dB lower
  scatter  one-shot ambience events sliced from the bed sources (W1 bird phrases, W3 chocolate plops)
  voice    leading silence/breath trimmed: speech onset at 20 ms, 5 ms fade-in (originals kept in _src/r7_orig/)
  steps    footstep sets level-matched to +-1 dB (L100); wood r1 (double thump) retired, wood r4 ring trimmed
  variants offline takes (+-1 to 2 semitones) for the most frequent one-shots
  bellows  bellows_pump rebuilt as a band-passed air stroke with a leather creak (two takes: in and out)
  enemyhit one consistent cloth-and-fur thwap with a small pop (4 takes); the metallic take kept as enemy_hit_metal
  slide    belly_slide_loop rebuilt as a 5 s friction loop without the periodic pulse
  estep    enemy_step: soft low-passed grass steps so enemy feet stop sounding like Mak's grass in every world
  heavy    land_heavy soft-clipped so its group gain fits under the peak cap
  choc     hot_choc_bubble_loop extended to 8 s with a 150 ms crossfaded wrap
Usage: python r7_fix_build.py [step ...]   (no args = all)
"""
import sys, json, shutil, hashlib
from pathlib import Path
import numpy as np
from scipy.signal import butter, sosfilt, sosfiltfilt, resample, lfilter
sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A

SRC = Path(__file__).resolve().parents[1]
AUD = SRC.parent
RAW = SRC / "raw"
ORIG = SRC / "r7_orig"
TMP = SRC / "review" / "_tmp_r7.wav"
REP = SRC / "reports" / "r7_fix_build.json"
SR = A.SR
rep = json.loads(REP.read_text()) if REP.exists() else {}
rng = np.random.default_rng(7)


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()[:16]


def keep_orig(rel):
    """Copy a bank file to _src/r7_orig once, and return the original path (the source for every rebuild)."""
    src = AUD / rel
    dst = ORIG / rel
    if not dst.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    return dst


# ---------------------------------------------------------------- loudness helpers
B1, A1 = [1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585]
B2, A2 = [1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621]


def l100(x):
    """Max 100 ms K-weighted loudness (coefficients are the 48 kHz set; within 0.1 dB at 44.1 kHz)."""
    y = lfilter(B2, A2, lfilter(B1, A1, x, axis=0), axis=0)
    p = (y ** 2).sum(axis=1)
    w, hop = int(0.1 * SR), int(0.01 * SR)
    if len(p) < w:
        p = np.pad(p, (0, w - len(p)))
    c = np.concatenate([[0.0], np.cumsum(p)])
    m = (c[w::hop][: (len(p) - w) // hop + 1] - c[0:len(p) - w + 1:hop]) / w
    return float(-0.691 + 10 * np.log10(m.max() + 1e-12))


def to_l100(x, target=-16.0, ceiling=-1.0):
    y = x * 10 ** ((target - l100(x)) / 20)
    if A.peak_db(y) > ceiling:
        y = A.limiter(y, ceiling)
    return y


def bp(x, lo, hi, order=4):
    sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfiltfilt(sos, x, axis=0)


def lp(x, hz, order=4):
    return sosfiltfilt(butter(order, hz, btype="low", fs=SR, output="sos"), x, axis=0)


def hp(x, hz, order=2):
    return sosfiltfilt(butter(order, hz, btype="high", fs=SR, output="sos"), x, axis=0)


def fades(y, fi_ms=3, fo_ms=30):
    y = y.copy()
    fi, fo = int(SR * fi_ms / 1000), int(SR * fo_ms / 1000)
    if fi:
        y[:fi] *= np.linspace(0, 1, fi)[:, None]
    if fo:
        y[-fo:] *= (np.linspace(1, 0, fo) ** 2)[:, None]
    return y


def pitch(x, semis):
    """Varispeed pitch shift (length changes with pitch, like a tape take)."""
    r = 2 ** (semis / 12)
    n = max(8, int(round(len(x) / r)))
    return resample(x, n, axis=0).astype(np.float32)


def write(y, rel, note):
    out = AUD / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    A.encode_ogg(y, out)
    rep[rel] = {"note": note, "dur_s": round(len(y) / SR, 3), "peak_db": round(A.peak_db(y), 2), "l100": round(l100(y), 2), "sha": sha(out)}
    print(f"  {rel:42s} {len(y)/SR:6.2f}s  L100 {l100(y):6.1f}  pk {A.peak_db(y):5.1f}  {note}")


def seam_loop(x, loop_len_s, xf_s=1.5, start_s=0.0):
    s = int(start_s * SR)
    L = int(loop_len_s * SR)
    xf = int(xf_s * SR)
    seg = x[s:s + L + xf]
    assert len(seg) == L + xf, (len(x) / SR, start_s, loop_len_s)
    return A.equal_power_crossfade_loop(seg, L, xf)


def norm_lufs(y, target, ceiling=-3.0, limit=True):
    I, _ = A.lufs_array(y, TMP)
    y = y * 10 ** ((target - I) / 20)
    if A.peak_db(y) > ceiling:
        y = A.limiter(y, ceiling) if limit else y * 10 ** ((ceiling - A.peak_db(y)) / 20)
    return y


def _level_jump_ok(y):
    """seam_check.py's level rule: the 50 ms level change across the wrap within the file's own 95th percentile."""
    w = int(0.05 * SR)
    jump = abs(A.rms_db(y[:w]) - A.rms_db(y[-w:]))
    r = np.random.default_rng(0)
    pos = r.integers(w, len(y) - w, 300)
    nat = np.array([abs(A.rms_db(y[p:p + w]) - A.rms_db(y[p - w:p])) for p in pos])
    return jump <= float(np.percentile(nat, 95)) * 0.8, jump


def _best_loop(x, cands):
    best = None
    for L, st in cands:
        y = seam_loop(x, L, start_s=st)
        ok, j = _level_jump_ok(y)
        if ok:
            return y
        if best is None or j < best[0]:
            best = (j, y)
    return best[1]


# ---------------------------------------------------------------- steps
def beds():
    # layer B loop lengths are chosen so that with A (20.5 s) and the old single loops (6, 8, 5.88, 7.5 s) the
    # combined pattern takes many minutes to come round again
    blen = {"hub": 13.7, "w1": 15.1, "w2": 16.9, "w3": 14.3, "boss": 17.3}
    for area in ["hub", "w1", "w2", "w3", "boss"]:
        raw_a = RAW / ("r5d_amb_w2_a_t2.mp3" if area == "w2" else f"r5_amb_{area}_a.mp3")
        a = hp(A.decode(raw_a, ch=2), 25)
        b = hp(A.decode(RAW / f"r5_amb_{area}_b.mp3", ch=2), 25)
        if area == "hub":
            # critique r1: the clock read as a horror countdown. Distant grandfather clock: low-passed at 4 kHz and
            # softened transients (a 2.5 ms smoothing window); the level drop (-8 dB) is in juice_sfx.json.
            # Filtered before looping so the filters' edges never land on the wrap.
            b = lp(b, 4000.0, order=4)
            k = int(0.0025 * SR)
            b = np.apply_along_axis(lambda c: np.convolve(c, np.ones(k) / k, mode="same"), 0, b)
        la = _best_loop(a, [(20.5, 0.0)] + [(L, st) for L in (20.3, 20.0, 19.7, 19.3) for st in (0.0, 0.3, 0.6, 1.0) if L + st <= 20.5])
        lb = _best_loop(b, [(blen[area], st) for st in (2.0, 1.0, 3.0, 4.0, 0.5)])
        # no limiter on loops: a limiter's gain differs at the end and the start, which shows as a level step at the
        # wrap. Loudness only needs to be roughly right (the index sets each key's level); the peak stays <= -1 dBFS.
        write(norm_lufs(la, -22.0, limit=False), f"sfx/amb_{area}_la.ogg", f"bed layer A {raw_a.name}, 20.5 s loop")
        write(norm_lufs(lb, -22.0, limit=False), f"sfx/amb_{area}_lb.ogg", f"bed layer B r5_amb_{area}_b.mp3, {blen[area]} s loop")


def _events(x, lo, hi, n, win_s, min_gap_s, offset_s=0.25):
    """Pick n distinct high-energy moments in a band; return (start, end) sample windows."""
    band = bp(x.mean(axis=1, keepdims=True), lo, hi)[:, 0]
    hop = int(0.01 * SR)
    e = np.sqrt(np.convolve(band ** 2, np.ones(hop * 5) / (hop * 5), mode="same"))[::hop]
    order = np.argsort(e)[::-1]
    picks = []
    for i in order:
        t = i * hop
        if t - offset_s * SR < 0 or t + (win_s - offset_s) * SR > len(x):
            continue
        if all(abs(t - p) > min_gap_s * SR for p in picks):
            picks.append(t)
        if len(picks) >= n:
            break
    return [(int(t - offset_s * SR), int(t + (win_s - offset_s) * SR)) for t in sorted(picks)]


def scatter():
    w1 = A.decode(RAW / "r5_amb_w1_a.mp3", ch=2)
    for i, (s, e) in enumerate(_events(w1, 2500, 7000, 6, 1.4, 2.2, 0.3)):
        y = fades(hp(w1[s:e].mean(axis=1, keepdims=True), 1200), 60, 400)
        write(to_l100(y, -16.0), f"sfx/amb_bird{'' if i == 0 else '_' + str(i + 1)}.ogg", f"W1 bird phrase from r5_amb_w1_a.mp3 at {s/SR:.2f}s")
    w3 = A.decode(RAW / "r5_amb_w3_a.mp3", ch=2)
    for i, (s, e) in enumerate(_events(w3, 120, 900, 5, 0.7, 1.5, 0.12)):
        y = fades(lp(w3[s:e].mean(axis=1, keepdims=True), 3500), 10, 250)
        write(to_l100(y, -16.0), f"sfx/amb_plop{'' if i == 0 else '_' + str(i + 1)}.ogg", f"W3 chocolate plop from r5_amb_w3_a.mp3 at {s/SR:.2f}s")


def voice():
    out = {}
    for f in sorted((AUD / "voice").glob("*.ogg")):
        rel = f"voice/{f.name}"
        x = A.decode(keep_orig(rel), ch=1)
        fr, hop = A.frame_rms_db(x)
        # speech onset = first 5 ms frame within 30 dB of the peak (a quieter breath or click before it is cut);
        # 20 ms is kept ahead of it so soft consonants keep their attack, and a 5 ms fade-in removes any step
        thr = max(-55.0, fr.max() - 30.0)
        first = int(np.argmax(fr > thr)) * hop
        cut = max(0, first - int(0.020 * SR))
        lead_ms = first / SR * 1000
        out[rel] = round(lead_ms, 1)
        if lead_ms <= 35.0:
            continue
        y = x[cut:].copy()
        fi = int(0.005 * SR)
        y[:fi] *= np.linspace(0, 1, fi)[:, None]
        write(y, rel, f"onset {lead_ms:.0f} ms -> 20 ms")
    rep["_voice_preroll_ms_before"] = out


def steps():
    retired = SRC / "r7_retired"
    retired.mkdir(exist_ok=True)
    for name in ["footstep_wood_r1.ogg"]:
        p = AUD / "sfx" / name
        if p.exists():
            keep_orig(f"sfx/{name}")
            shutil.move(str(p), str(retired / name))
            imp = AUD / "sfx" / (name + ".import")
            if imp.exists():
                shutil.move(str(imp), str(retired / (name + ".import")))
            print("  retired", name, "(double thump at 30 and 100 ms)")
    for surf in ["grass", "wood", "stone", "candy", "carpet", "jelly", "metal", "cloud"]:
        files = sorted((AUD / "sfx").glob(f"footstep_{surf}_r*.ogg")) + sorted((AUD / "sfx").glob(f"footstep_{surf}_[0-9].ogg"))
        xs = {}
        for f in files:
            rel = f"sfx/{f.name}"
            x = A.decode(keep_orig(rel), ch=1)
            if rel == "sfx/footstep_wood_r4.ogg":
                # ring to 0.16 s: fade from 85 ms to 125 ms
                n0, n1 = int(0.085 * SR), int(0.125 * SR)
                g = np.ones(len(x))
                g[n0:n1] = np.linspace(1, 0, n1 - n0) ** 2
                g[n1:] = 0.0
                x = (x[:, 0] * g)[:n1 + 10, None]
            xs[rel] = x
        if not xs:
            continue
        ls = {k: l100(v) for k, v in xs.items()}
        med = float(np.median(list(ls.values())))
        for k, x in xs.items():
            d = med - ls[k]
            if abs(d) <= 0.6 and k != "sfx/footstep_wood_r4.ogg":
                continue
            write(to_l100(x, med), k, f"step set {surf}: {ls[k]:.1f} -> {med:.1f} L100")
        rep[f"_steps_{surf}"] = {"before": {k: round(v, 2) for k, v in ls.items()}, "median": round(med, 2)}


VARIANTS = {  # stem: [(source file, semitones, new suffix)]
    "jump_1": [("jump_1", 1.5, 5), ("jump_1_3", -1.2, 6)],
    "jump_2": [("jump_2", -1.3, 5)],
    "punch": [("punch", 1.4, 3), ("punch_2", -1.5, 4)],
    "swish": [("swish", -1.6, 3), ("swish_2", 1.3, 4)],
    "spin_kick": [("spin_kick", 1.2, 3), ("spin_kick_2", -1.4, 4)],
    "kick": [("kick", -1.3, 3)],
    "dive": [("dive", 1.3, 2), ("dive", -1.5, 3)],
    "skid": [("skid", 1.2, 2), ("skid", -1.4, 3)],
    "ledge_grab": [("ledge_grab", 1.5, 2), ("ledge_grab", -1.2, 3)],
    "gumdrop_bounce": [("gumdrop_bounce", 1.3, 2), ("gumdrop_bounce", -1.5, 3)],
    "crate_break": [("crate_break", -1.3, 2), ("crate_break", 1.1, 3)],
    "ham_slam": [("ham_slam", -1.0, 2)],
}


def variants():
    for stem, lst in VARIANTS.items():
        for src, semis, n in lst:
            rel_src = f"sfx/{src}.ogg"
            x = A.decode(keep_orig(rel_src), ch=1)
            y = fades(pitch(x, semis), 2, 20)
            write(to_l100(y, l100(x)), f"sfx/{stem}_{n}.ogg", f"variant of {src} ({semis:+.1f} st)")
    # voice: the triple-jump call had one take at chance 0.9
    x = A.decode(keep_orig("voice/mak_jump3.ogg"), ch=1)
    for semis, n in [(1.0, "b"), (-0.8, "c")]:
        y = fades(pitch(x, semis), 2, 20)
        write(to_l100(y, l100(x)), f"voice/mak_jump3{n}.ogg", f"variant of mak_jump3 ({semis:+.1f} st)")


def bellows():
    keep_orig("sfx/bellows_pump.ogg")  # (restored from git HEAD once: the first run kept it too late)
    for i, (dur, rise, fall, lo, hi, creak_hz) in enumerate([(0.55, 0.12, 0.25, 300, 2500, 92), (0.5, 0.10, 0.28, 380, 2900, 118)]):
        n = int(dur * SR)
        noise = rng.standard_normal((n, 1)).astype(np.float32)
        air = bp(noise, lo, hi, order=4)  # 300-2900 Hz band: air, not broadband static
        t = np.arange(n) / SR
        env = np.clip(t / rise, 0, 1) ** 1.5 * np.clip((dur - t) / fall, 0, 1) ** 1.2
        # slow breathy wobble so it is not a static noise block
        wob = 1.0 + 0.18 * np.sin(2 * np.pi * (5.5 + i) * t + i)
        air = air[:, 0] * env * wob
        # sweep: the band centre rises during the stroke
        air2 = bp((air[:, None]), lo * 1.4, hi * 1.1, order=2)[:, 0] * np.linspace(0.3, 1.0, n)
        # leather creak: a short train of uneven low pulses at the start of the stroke
        creak = np.zeros(n)
        k = 0.0
        while k < 0.16:
            idx = int((0.02 + k) * SR)
            if idx < n - 400:
                pulse = np.exp(-np.arange(400) / 60.0) * np.sin(2 * np.pi * (creak_hz * 4) * np.arange(400) / SR)
                creak[idx:idx + 400] += pulse * (1.0 - k / 0.2)
            k += 1.0 / creak_hz * (1.0 + 0.35 * rng.random())
        creak = lp(creak[:, None], 1800)[:, 0]
        y = lp((air + 0.6 * air2 + 0.5 * creak)[:, None], 4000.0, order=4)
        y = fades(y, 4, 60)
        write(to_l100(y, -16.0), f"sfx/bellows_pump{'' if i == 0 else '_2'}.ogg", "synth air stroke 300-2900 Hz + leather creak (critique r1)")


def enemyhit():
    metal = AUD / "sfx" / "enemy_hit_metal.ogg"
    if not metal.exists():
        shutil.copy2(keep_orig("sfx/enemy_hit_3.ogg"), metal)
        print("  kept the metallic take as sfx/enemy_hit_metal.ogg (gingerbread)")
    keep_orig("sfx/enemy_hit.ogg"); keep_orig("sfx/enemy_hit_2.ogg")
    punch = [A.decode(keep_orig(f"sfx/{p}.ogg"), ch=1) for p in ["punch", "punch_2"]]
    pop = [A.decode(keep_orig(f"sfx/{p}.ogg"), ch=1) for p in ["pop", "pop_2"]]
    takes = [(0, 0, -0.8, 1.0, 0.0), (1, 1, 0.6, 1.08, -1.0), (0, 1, 1.2, 0.95, 0.5), (1, 0, -1.4, 1.03, -0.5)]
    for i, (pi, oi, semis, pop_pitch, pop_db) in enumerate(takes):
        th = lp(pitch(punch[pi], semis - 2.0), 3200)  # duller, rounder: cloth and fur, not a slap
        thump = lp(th, 300) * 0.8  # a little body
        po = pitch(pop[oi], 12 * np.log2(pop_pitch) + 3.0)
        po = hp(po, 700) * 10 ** ((-9.0 + pop_db) / 20)
        n = max(len(th), int(0.035 * SR) + len(po))
        y = np.zeros((n, 1), np.float32)
        y[:len(th)] += th + thump
        d = int(0.035 * SR)
        y[d:d + len(po)] += po[: n - d]
        y = fades(y, 2, 40)
        write(to_l100(y, -16.0), f"sfx/enemy_hit{'' if i == 0 else '_' + str(i + 1)}.ogg", "cloth-and-fur thwap + small pop (critique r1)")


def slide():
    keep_orig("sfx/belly_slide_loop.ogg")
    L = 5.0
    n = int((L + 0.5) * SR)
    noise = rng.standard_normal((n, 2)).astype(np.float32)
    fric = lp(bp(noise, 350, 2600, order=2), 4500.0, order=4)  # a soft "shhh", not hiss
    body = bp(noise[:, :1], 70, 220, order=2) * 0.5
    t = np.arange(n) / SR
    # smooth random amplitude drift (0.3-1.5 Hz content), +-2.5 dB: texture without a regular pulse
    drift = lp(rng.standard_normal((n, 1)), 1.5, order=2)
    drift = drift / (np.abs(drift).max() + 1e-9)
    g = 10 ** ((2.5 * drift) / 20)
    grit = lp(rng.standard_normal((n, 1)) * (rng.random((n, 1)) > 0.9985), 2500) * 4.0  # sparse fine grit
    y = (fric * g + body * g + grit) * 0.5
    y = A.equal_power_crossfade_loop(y, int(L * SR), int(0.5 * SR))
    I, _ = A.lufs_array(y, TMP)
    y = y * 10 ** ((-24.0 - I) / 20)
    write(y, "sfx/belly_slide_loop.ogg", "5 s friction loop, no periodic pulse (critique r1)")


def estep():
    srcs = sorted((AUD / "sfx").glob("footstep_grass_r*.ogg"))
    for i, f in enumerate(srcs):
        x = A.decode(keep_orig(f"sfx/{f.name}"), ch=1)
        y = fades(lp(x, 900, order=2), 1, 30)
        write(to_l100(y, -16.0), f"sfx/enemy_step{'' if i == 0 else '_' + str(i + 1)}.ogg", f"soft low-passed step from {f.name}")


def heavy():
    for f in ["land_heavy", "land_heavy_2", "land_heavy_3"]:
        x = A.decode(keep_orig(f"sfx/{f}.ogg"), ch=1)
        pk = np.abs(x).max()
        drive = 2.4
        y = np.tanh(drive * x / pk) / np.tanh(drive) * pk
        write(to_l100(y, -16.0), f"sfx/{f}.ogg", "soft-clipped (tanh x2.4) so it reaches its group level under the peak cap")


def choc():
    keep_orig("sfx/hot_choc_bubble_loop.ogg")
    x = A.decode(RAW / "sfx_hot_choc_bubble_loop.mp3", ch=1)
    # two passes of the 4 s source at different offsets, crossfaded, then a 150 ms equal-power wrap
    a = x[: int(3.9 * SR)]
    b = np.roll(x, int(1.7 * SR), axis=0)[: int(4.4 * SR)]
    xf = int(0.3 * SR)
    t = np.linspace(0, 1, xf)[:, None]
    y = np.concatenate([a[:-xf], a[-xf:] * np.cos(t * np.pi / 2) + b[:xf] * np.sin(t * np.pi / 2), b[xf:]])
    L = int(8.0 * SR)
    wrap = int(0.15 * SR)
    y = np.concatenate([y, y[: max(0, L + wrap - len(y))]])[: L + wrap]
    y = A.equal_power_crossfade_loop(y, L, wrap)
    I, _ = A.lufs_array(y, TMP)
    y = y * 10 ** ((-24.0 - I) / 20)
    if A.peak_db(y) > -1.0:
        y = A.limiter(y, -1.0)
    write(y, "sfx/hot_choc_bubble_loop.ogg", "8 s loop, 150 ms crossfaded wrap (critique r1)")


STEPS = {"beds": beds, "scatter": scatter, "voice": voice, "steps": steps, "variants": variants, "bellows": bellows,
         "enemyhit": enemyhit, "slide": slide, "estep": estep, "heavy": heavy, "choc": choc}

if __name__ == "__main__":
    want = sys.argv[1:] or list(STEPS)
    for s in want:
        print("==", s)
        STEPS[s]()
    REP.write_text(json.dumps(rep, indent=1))

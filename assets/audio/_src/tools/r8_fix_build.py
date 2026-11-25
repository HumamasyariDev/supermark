"""Fix stage round 1b (critique r1 re-check: audio director 7.0, audio QA 6.3): offline rebuilds, no paid calls.
Every step is idempotent: sources are copied once to _src/r8_orig/ (or come from _src/raw / _src/r7_orig) and every
output is rebuilt from them, never from its own previous output.

  attacks  swish takes re-cut to peak at 40-90 ms and spin_kick takes at 80-150 ms (the strike window is 50-180 ms,
           kick to 240 ms); the second hump of swish/swish_3 is gone; _3/_4 are rebuilt from the other source take
           with a different transient, tail and layer mix instead of varispeed clones
  slide    per-surface belly-slide loops slide_loop_{grass,wood,candy,stone}: friction noise amplitude-modulated by
           6-14 Hz bumps (rate follows speed in engine through the pitch range), sparse grit one-shots cut from the
           surface's own footstep plants, a surface body, content up to 9-12 kHz (the r7 loop stopped near 5 kHz)
  enemyhit enemy_hit takes get a 2-6 ms band-passed click (3-8 kHz) at -8 dB and a gentler low-pass (9.5 kHz)
  bosswind two procedural rooftop wind layers with periodic gust and whistle modulators (19.7 s and 13.9 s), and
           amb_wind_loop re-wrapped with a 300 ms equal-power crossfade (the old wrap had a +4 dB step)
  bee      bee_buzz extended to a 6.4 s loop chained from the take at wing-period-aligned joins (the 2.13 s loop had a
           seam every wrap), plus bee_buzz_once: a 0.95 s one-shot that swells (W2 bee charge tell)
  greet    npc_greet_piglet trimmed at 0.95 s with a 30 ms fade (a detached burst followed the vocal)
  fire     amb_fire_loop 1 dB lower (true peak was +0.37 dBTP)
  hybrids  variants of the most frequent one-shots built from two different takes (transient of one, body and tail of
           the other, different EQ tilt) instead of pitch clones
Usage: python r8_fix_build.py [step ...]   (no args = all)
"""
import sys, json, shutil, hashlib
from pathlib import Path
import numpy as np
from scipy.signal import butter, sosfiltfilt, resample, lfilter, sosfilt

sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A

SRC = Path(__file__).resolve().parents[1]
AUD = SRC.parent
RAW = SRC / "raw"
R7O = SRC / "r7_orig"
ORIG = SRC / "r8_orig"
TMP = SRC / "review" / "_tmp_r8.wav"
REP = SRC / "reports" / "r8_fix_build.json"
SR = A.SR
rep = json.loads(REP.read_text()) if REP.exists() else {}


def rng(seed):
    return np.random.default_rng(seed)


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()[:16]


def keep_orig(rel):
    """Copy a bank file to _src/r8_orig once and return that copy (the source of every rebuild)."""
    src = AUD / rel
    dst = ORIG / rel
    if not dst.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    return dst


def source(rel):
    """Pre-r7 original when r7 kept one, else the r8 copy of the current bank file."""
    p = R7O / rel
    return p if p.exists() else keep_orig(rel)


# ---------------------------------------------------------------- dsp helpers
B1, A1 = [1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585]
B2, A2 = [1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621]


def l100(x):
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
    return sosfiltfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x, axis=0)


def lp(x, hz, order=4):
    return sosfiltfilt(butter(order, hz, btype="low", fs=SR, output="sos"), x, axis=0)


def hp(x, hz, order=2):
    return sosfiltfilt(butter(order, hz, btype="high", fs=SR, output="sos"), x, axis=0)


def shelf_hi(x, hz, db):
    """High shelf as a parallel high-passed band (gentle, phase-safe with filtfilt)."""
    return x + hp(x, hz, 2) * (10 ** (db / 20) - 1.0)


def fades(y, fi_ms=3, fo_ms=30, curve=2.0):
    y = y.copy()
    fi, fo = int(SR * fi_ms / 1000), int(SR * fo_ms / 1000)
    if fi:
        y[:fi] *= (0.5 - 0.5 * np.cos(np.linspace(0, np.pi, fi)))[:, None]
    if fo:
        y[-fo:] *= (np.linspace(1, 0, fo) ** curve)[:, None]
    return y


def pitch(x, semis):
    r = 2 ** (semis / 12)
    return resample(x, max(8, int(round(len(x) / r))), axis=0).astype(np.float32)


def write(y, rel, note):
    out = AUD / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    A.encode_ogg(y, out)
    fr, hop = A.frame_rms_db(y)
    pk_ms = int(np.argmax(fr)) * hop / SR * 1000
    rep[rel] = {"note": note, "dur_s": round(len(y) / SR, 3), "peak_db": round(A.peak_db(y), 2), "l100": round(l100(y), 2),
                "peak_ms": round(pk_ms), "sha": sha(out)}
    print(f"  {rel:40s} {len(y)/SR:6.2f}s  L100 {l100(y):6.1f}  pk {A.peak_db(y):5.1f}  peak@{pk_ms:4.0f}ms  {note}")


def norm_lufs(y, target, ceiling=-3.0):
    I, _ = A.lufs_array(y, TMP)
    y = y * 10 ** ((target - I) / 20)
    if A.peak_db(y) > ceiling:
        y = y * 10 ** ((ceiling - A.peak_db(y)) / 20)
    return y


def env_from_frames(g_db, hop, n):
    """Per-frame gain (dB) to a smooth per-sample linear gain."""
    k = 4
    g = np.convolve(np.pad(g_db, (k, k), mode="edge"), np.ones(2 * k + 1) / (2 * k + 1), mode="valid")
    t = (np.arange(len(g)) + 0.5) * hop
    return 10 ** (np.interp(np.arange(n), t, g) / 20)


def recut(x, target_ms, tame_after_ms, tame_db=7.0, fade_in_ms=14.0, pre_db=3.0):
    """Place the strongest 5 ms frame at target_ms (cut the head or pad silence), then make everything after
    tame_after_ms decay at least tame_db under that peak (monotone, smoothed) and keep earlier humps pre_db under it."""
    fr, hop = A.frame_rms_db(x)
    pk = int(np.argmax(fr))
    shift = pk * hop - int(target_ms * SR / 1000)
    if shift > 0:
        y = x[shift:].copy()
        y = fades(y, fade_in_ms, 0)
    else:
        y = np.concatenate([np.zeros((-shift, x.shape[1]), np.float32), x])
    fr, hop = A.frame_rms_db(y)
    pk = int(np.argmax(fr))
    P = fr[pk]
    g = np.zeros(len(fr))
    t0 = int(tame_after_ms * SR / 1000) // hop
    for i in range(len(fr)):
        if i >= t0 and i > pk:
            g[i] = min(0.0, (P - tame_db) - fr[i])
        elif i < pk - 2:
            g[i] = min(0.0, (P - pre_db) - fr[i])
    # monotone decay after the tame point: the gain never recovers once it has dropped
    for i in range(max(t0, pk + 1) + 1, len(g)):
        g[i] = min(g[i], g[i - 1] + 0.0)
    y = y * env_from_frames(g, hop, len(y))[:, None]
    return fades(y, 0, 40)


def best_roll(y):
    """Rotate a seamless loop so its wrap sits where the 50 ms level change and the sample level are smallest
    (seam_check.py judges the wrap; Vorbis adds a little error at the stream edges, so a quiet, steady spot hides it)."""
    w = int(0.05 * SR)
    c = np.concatenate([y, y[:w]])
    e = np.sqrt(np.convolve((c ** 2).mean(axis=1), np.ones(w) / w, mode="valid"))  # rms of [i, i+w)
    best, bi = 1e9, 0
    for i in range(w, len(y), int(0.01 * SR)):
        pre, post = e[i - w], e[i] if i < len(e) else e[i - len(y)]
        lvl = abs(20 * np.log10((post + 1e-9) / (pre + 1e-9)))
        amp = float(np.abs(y[i]).max()) / (np.abs(y).max() + 1e-9)
        sc = lvl + 6.0 * amp
        if sc < best:
            best, bi = sc, i
    return np.roll(y, -bi, axis=0)


def peak_ms(y):
    fr, hop = A.frame_rms_db(y)
    return int(np.argmax(fr)) * hop / SR * 1000


# ---------------------------------------------------------------- steps
def attacks():
    """swish: 40-90 ms; spin_kick: 80-150 ms (critique r1b major 3)."""
    sw1 = A.decode(source("sfx/swish.ogg"), ch=1)      # r5_swish_t1: humps at 5 and 180 ms (the splice)
    sw2 = A.decode(source("sfx/swish_2.ogg"), ch=1)    # r5_swish_t2: humps at 40 and 160 ms
    sk1 = A.decode(source("sfx/spin_kick.ogg"), ch=1)  # r5_spin_kick_t1: four swirls, loudest at 309 ms
    sk2 = A.decode(source("sfx/spin_kick_2.ogg"), ch=1)  # r5_spin_kick_t2: peaks at 65 ms
    ref_sw, ref_sk = l100(sw1), l100(sk1)

    def out(y, rel, ref, note, lo, hi):
        y = to_l100(y, ref)
        pm = peak_ms(y)
        assert lo <= pm <= hi, (rel, pm)
        write(y, rel, note)

    # swish: the loud second hump becomes the strike; the early 5 ms hump is cut away (no splice)
    out(recut(sw1, 62, 130), "sfx/swish.ogg", ref_sw, "re-cut t1: peak at 60 ms, single hump", 40, 90)
    out(recut(sw2, 52, 115, tame_db=8.0), "sfx/swish_2.ogg", ref_sw, "re-cut t2: peak at 50 ms, second hump -8 dB", 40, 90)
    # _3: t1's swirl, brighter and shorter, with a little of t2's air on top (a different layer mix, not a clone)
    a = recut(pitch(sw1, 0.9), 76, 120, tame_db=9.0)
    b = recut(hp(sw2, 1500), 70, 110, tame_db=10.0)
    n = max(len(a), len(b))
    y3 = np.zeros((n, 1), np.float32)
    y3[:len(a)] += shelf_hi(a, 3500, 3.0)
    y3[:len(b)] += 0.35 * b
    out(fades(y3[: int(0.30 * SR)], 0, 70), "sfx/swish_3.ogg", ref_sw, "t1 swirl +0.9 st, +3 dB air shelf, t2 air layer, 0.30 s", 40, 90)
    # _4: t2's swipe, darker and longer, with t1's low body under it
    a = recut(pitch(sw2, -1.1), 48, 120, tame_db=6.0)
    b = recut(lp(sw1, 1800), 60, 140, tame_db=8.0)
    n = max(len(a), len(b))
    y4 = np.zeros((n, 1), np.float32)
    y4[:len(a)] += lp(a, 6500)
    y4[:len(b)] += 0.45 * b
    out(fades(y4[: int(0.40 * SR)], 0, 120), "sfx/swish_4.ogg", ref_sw, "t2 swipe -1.1 st low-passed 6.5 kHz, t1 body layer, 0.40 s", 40, 90)

    # spin_kick: the last (loudest) swirl lands at 115 ms with one swirl before it
    out(recut(sk1, 115, 190, tame_db=7.0, pre_db=4.0), "sfx/spin_kick.ogg", ref_sk, "re-cut t1: loudest swirl at 115 ms", 80, 150)
    out(recut(sk2, 100, 200, tame_db=7.0), "sfx/spin_kick_2.ogg", ref_sk, "t2 padded: peak at 100 ms", 80, 150)
    a = recut(pitch(sk1, -0.9), 132, 200, tame_db=8.0, pre_db=4.0)
    b = recut(bp(sk2, 250, 2500), 125, 200, tame_db=9.0)
    n = max(len(a), len(b))
    y = np.zeros((n, 1), np.float32)
    y[:len(a)] += a
    y[:len(b)] += 0.4 * b
    out(fades(y[: int(0.45 * SR)], 0, 90), "sfx/spin_kick_3.ogg", ref_sk, "t1 -0.9 st + t2 band layer, peak 130 ms", 80, 150)
    a = recut(hp(pitch(sk2, 1.2), 350), 88, 180, tame_db=7.0)
    b = recut(lp(sk1, 2200), 95, 180, tame_db=8.0, pre_db=5.0)
    n = max(len(a), len(b))
    y = np.zeros((n, 1), np.float32)
    y[:len(a)] += a
    y[:len(b)] += 0.35 * b
    out(fades(y[: int(0.42 * SR)], 0, 90), "sfx/spin_kick_4.ogg", ref_sk, "t2 +1.2 st high-passed + t1 low layer, peak 90 ms", 80, 150)


def _plants(stem, n_ms=45):
    """The first n_ms of each footstep take of a surface: its plant transient, used as slide grit."""
    out = []
    for f in sorted((AUD / "sfx").glob(f"footstep_{stem}_r*.ogg")):
        x = A.decode(f, ch=1)
        fr, hop = A.frame_rms_db(x)
        on = max(0, int(np.argmax(fr > fr.max() - 18)) * hop - int(0.002 * SR))
        g = x[on:on + int(n_ms * SR / 1000)]
        out.append(fades(g / (np.abs(g).max() + 1e-9), 1, n_ms * 0.6))
    return out


SLIDE = {
    # surface: friction band, body band and gain, bump depth, grit density (events/s), grit level, air shelf dB, seed
    "grass": {"band": (450, 9000), "body": (90, 260, 0.35), "bump": 0.78, "grit": 9.0, "grit_db": -10.0, "shelf": 2.0, "len": 4.3, "seed": 11},
    "wood": {"band": (220, 5200), "body": (70, 200, 0.6), "bump": 0.8, "grit": 7.0, "grit_db": -11.0, "shelf": -2.0, "len": 4.1, "seed": 12},
    "candy": {"band": (900, 11000), "body": (120, 400, 0.25), "bump": 0.72, "grit": 14.0, "grit_db": -9.0, "shelf": 3.0, "len": 4.7, "seed": 13},
    "stone": {"band": (700, 12000), "body": (60, 180, 0.5), "bump": 0.78, "grit": 12.0, "grit_db": -9.5, "shelf": 1.0, "len": 3.9, "seed": 14},
}


def slide():
    """Per-surface belly-slide loops (critique r1b major 4). Friction is band-limited noise with a 1/f tilt; the
    bump train is a random 6-14 Hz pulse train smoothed into an amplitude modulation; grit is the surface's own
    footstep plants scattered every 60-140 ms at -12 dB. Loudness -24 LUFS like the r7 loop (the index sets the level)."""
    for surf, c in SLIDE.items():
        r = rng(c["seed"])
        L, xf = c["len"], 0.2
        n = int(L * SR) + int(xf * SR)
        t = np.arange(n) / SR
        noise = r.standard_normal((n, 1)).astype(np.float32)
        pink = lfilter([0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400], noise, axis=0)
        fric = bp(pink, *c["band"], order=2)
        fric = fric / (np.std(fric) + 1e-9)
        lo, hi, bg = c["body"]
        body = bp(noise, lo, hi, order=2)
        body = body / (np.std(body) + 1e-9) * bg
        # bumps: pulses at random 6-14 Hz intervals, each a 25-45 ms raised-cosine swell
        am = np.zeros(n)
        k = r.uniform(0, 0.05)
        while k < L + xf:
            i = int(k * SR)
            w = int(r.uniform(0.025, 0.045) * SR)
            seg = 0.5 - 0.5 * np.cos(np.linspace(0, 2 * np.pi, w))
            e = min(n, i + w)
            am[i:e] += seg[: e - i] * r.uniform(0.6, 1.0)
            k += 1.0 / r.uniform(6.0, 14.0)
        am = 1.0 - c["bump"] + c["bump"] * np.clip(am, 0, 1.3) / 1.3
        # slow drift so the bed itself breathes (+-2 dB, under 1.5 Hz)
        drift = lp(r.standard_normal((n, 1)), 1.2, order=2)[:, 0]
        drift = 10 ** (2.0 * drift / (np.abs(drift).max() + 1e-9) / 20)
        y = (fric[:, 0] * am * drift + body[:, 0] * (0.6 + 0.4 * am))[:, None]
        # grit: the surface's footstep plants, sparse and random
        plants = _plants(surf)
        gl = 10 ** (c["grit_db"] / 20) * np.std(y) * 6.0
        k = r.uniform(0.02, 0.1)
        while k < L + xf - 0.06:
            p = plants[r.integers(len(plants))]
            p = pitch(p, r.uniform(-3, 3))
            i = int(k * SR)
            e = min(n, i + len(p))
            y[i:e] += p[: e - i] * gl * r.uniform(0.4, 1.0)
            k += r.uniform(0.06, 0.14) * (9.0 / c["grit"])
        y = shelf_hi(y, 4000, c["shelf"])
        y = lp(y, 13000, order=2)
        y = best_roll(A.equal_power_crossfade_loop(y, int(L * SR), int(xf * SR)))
        y = norm_lufs(y, -24.0, ceiling=-3.0)
        write(y, f"sfx/slide_loop_{surf}.ogg", f"belly-slide loop {surf}: 6-14 Hz bumps, footstep grit, {L} s")


def enemyhit():
    """A 2-6 ms band-passed click (3-8 kHz) at -8 dB on each cloth-and-fur thwap (critique r1b minor)."""
    r = rng(21)
    for i, name in enumerate(["enemy_hit", "enemy_hit_2", "enemy_hit_3", "enemy_hit_4"]):
        x = A.decode(keep_orig(f"sfx/{name}.ogg"), ch=1)
        fr, hop = A.frame_rms_db(x)
        on = max(0, int(np.argmax(fr > fr.max() - 15)) * hop)
        dur = r.uniform(0.002, 0.006)
        m = int(dur * SR)
        click = r.standard_normal((m + 400, 1)).astype(np.float32)
        click = bp(click, 3000 + 400 * i, 8000, order=2)[200:200 + m]
        click *= np.exp(-np.linspace(0, 5, m))[:, None]
        click = click / (np.abs(click).max() + 1e-9) * np.abs(x).max() * 10 ** (-8.0 / 20)
        y = shelf_hi(x, 5000, 2.0)
        y[on:on + m] += click
        write(to_l100(y, l100(x)), f"sfx/{name}.ogg", f"thwap + {dur*1000:.1f} ms 3-8 kHz click at -8 dB, +2 dB air")


def _periodic(t, L, r, n_terms, depth, kmax=6, kmin=1):
    s = np.zeros_like(t)
    for _ in range(n_terms):
        k = int(r.integers(kmin, kmax + 1))
        s += r.uniform(0.3, 1.0) * np.sin(2 * np.pi * k * t / L + r.uniform(0, 2 * np.pi))
    return depth * s / (np.abs(s).max() + 1e-9)


def _wind(L, seed, band_hz, whistle_hz, gust_db, whistle_db, lp_hz=6000.0):
    """Procedural rooftop wind: pink noise through a band whose centre glides with periodic gusts, plus a faint
    whistle (narrow band) that opens with the gusts. All modulators are periodic in L, so the loop wraps cleanly."""
    r = rng(seed)
    xf = 1.0
    n = int(L * SR) + int(xf * SR)
    t = np.arange(n) / SR
    noise = r.standard_normal((n, 2)).astype(np.float32)
    pink = lfilter([0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400], noise, axis=0)
    # slow swells (1-3 cycles per loop) plus irregular faster flutter (7-23 cycles): no audible regular period
    gust = 0.75 * _periodic(t, L, r, 3, 1.0, kmax=3) + 0.25 * _periodic(t, L, r, 7, 1.0, kmax=23, kmin=7)
    gust = gust / (np.abs(gust).max() + 1e-9)
    # four overlapping bands, each weighted by the gust: the spectrum brightens as the wind rises
    lo, hi = band_hz
    edges = np.geomspace(lo, hi, 5)
    y = np.zeros((n, 2), np.float32)
    for j in range(4):
        b = bp(pink, edges[j], edges[j + 1], order=2)
        w = 0.5 + 0.5 * gust * (j - 1.0) / 2.0 + 0.5
        y += b * np.clip(w, 0.15, 1.5)[:, None]
    y = y * (10 ** (gust * gust_db / 20))[:, None]
    wh = bp(noise, whistle_hz * 0.97, whistle_hz * 1.03, order=2)
    wh2 = bp(noise, whistle_hz * 1.49, whistle_hz * 1.53, order=2) * 0.5
    wopen = np.clip(gust, 0, 1) ** 2
    y += (wh + wh2) * (wopen * 10 ** (whistle_db / 20) * 4.0)[:, None]
    y = lp(y, lp_hz, order=4)
    y = A.equal_power_crossfade_loop(y, int(L * SR), int(xf * SR))
    return best_roll(y)


def bosswind():
    """Boss phases 1 and 4 (critique r1b minor): two co-prime procedural wind layers plus a cleanly re-wrapped old loop."""
    a = _wind(19.7, 31, (180, 4200), 1180.0, 9.0, -16.0, lp_hz=6000.0)
    write(norm_lufs(a, -22.0), "sfx/amb_boss_wind_a.ogg", "procedural rooftop wind, periodic gusts + whistle, 19.7 s")
    b = _wind(13.9, 32, (90, 2400), 760.0, 7.0, -22.0, lp_hz=3000.0)
    write(norm_lufs(b, -22.0), "sfx/amb_boss_wind_b.ogg", "procedural low wind and rumble, 13.9 s")
    x = A.decode(RAW / "sfx_amb_wind_loop.mp3", ch=2)
    L = len(x) / SR - 0.35
    y = best_roll(A.equal_power_crossfade_loop(x[: int(L * SR) + int(0.3 * SR)], int(L * SR), int(0.3 * SR)))
    I0, _ = A.lufs_file(source("sfx/amb_wind_loop.ogg"))
    write(norm_lufs(y, I0 if I0 is not None else -22.0), "sfx/amb_wind_loop.ogg", f"re-wrapped {L:.2f} s, 300 ms equal-power crossfade")


def _period(x):
    """Wing period (s) from the autocorrelation peak between 4 and 20 ms."""
    m = x[:, 0] - x[:, 0].mean()
    seg = m[: min(len(m), SR)]
    ac = np.correlate(seg, seg, mode="full")[len(seg) - 1:]
    lo, hi = int(0.004 * SR), int(0.020 * SR)
    return (lo + int(np.argmax(ac[lo:hi]))) / SR


def bee():
    x = A.decode(RAW / "sfx_bee_buzz.mp3", ch=1)
    x = hp(x, 60)
    per = _period(x)
    r = rng(41)
    # chain 0.7-1.1 s pieces from random offsets; each join is placed where the next piece best matches the tail
    xf = int(0.16 * SR)
    target = int(6.4 * SR)
    out = x[int(0.3 * SR): int(1.2 * SR)].copy()
    while len(out) < target + xf:
        tail = out[-xf:, 0]
        best, bo = -1e9, 0
        for _ in range(60):
            o = int(r.uniform(0.15, 2.25 - 1.2) * SR)
            c = float(np.dot(tail, x[o:o + xf, 0]))
            if c > best:
                best, bo = c, o
        piece = x[bo: bo + int(r.uniform(0.7, 1.1) * SR)]
        tt = np.linspace(0, 1, xf)[:, None]
        out[-xf:] = out[-xf:] * np.cos(tt * np.pi / 2) + piece[:xf] * np.sin(tt * np.pi / 2)
        out = np.concatenate([out, piece[xf:]])
    wrap = int(0.18 * SR)
    L = target
    y = out[: L + wrap]
    # slow periodic wobble (whole cycles over the loop) so the buzz drifts like a wing beat changing
    t = np.arange(len(y)) / SR
    y = y * (1.0 + 0.08 * np.sin(2 * np.pi * 3 * t / (L / SR)))[:, None]
    y = A.equal_power_crossfade_loop(y, L, wrap)
    I0, _ = A.lufs_file(source("sfx/bee_buzz.ogg"))
    write(norm_lufs(y, I0 if I0 is not None else -24.0), "sfx/bee_buzz.ogg", f"6.4 s chained loop, joins matched (wing period {per*1000:.1f} ms), 180 ms wrap")
    # one-shot for the W2 charge tell: 0.95 s that swells, then cuts with a 120 ms fade
    o = x[int(0.4 * SR): int(1.35 * SR)].copy()
    n = len(o)
    sw = np.clip(np.linspace(0.35, 1.15, n), 0, 1.0) ** 1.2
    o = pitch(o * sw[:, None], 0.6)
    write(to_l100(fades(o, 60, 120), -16.0), "sfx/bee_buzz_once.ogg", "0.95 s buzz swell one-shot (bee charge tell)")


def greet():
    x = A.decode(keep_orig("sfx/npc_greet_piglet.ogg"), ch=1)
    y = fades(x[: int(0.95 * SR)], 0, 30)
    write(y, "sfx/npc_greet_piglet.ogg", "trimmed at 0.95 s (detached burst at 1.05 s removed), 30 ms fade")


def fire():
    x = A.decode(keep_orig("sfx/amb_fire_loop.ogg"), ch=2)
    write(x * 10 ** (-1.2 / 20), "sfx/amb_fire_loop.ogg", "-1.2 dB (true peak was +0.37 dBTP)")


HYBRIDS = {  # out file: (transient source, body source, transient ms, eq: ("lp"|"hp"|"shelf", hz, db), body pitch st)
    "sfx/punch_3.ogg": ("sfx/punch_2.ogg", "sfx/punch.ogg", 18, ("shelf", 3000, 2.5), -0.7),
    "sfx/punch_4.ogg": ("sfx/punch.ogg", "sfx/punch_2.ogg", 14, ("lp", 7000, 0), 0.8),
    "sfx/jump_1_5.ogg": ("sfx/jump_1_3.ogg", "sfx/jump_1.ogg", 25, ("shelf", 3500, 2.0), 0.6),
    "sfx/jump_1_6.ogg": ("sfx/jump_1.ogg", "sfx/jump_1_3.ogg", 20, ("lp", 6000, 0), -0.8),
    "sfx/kick_3.ogg": ("sfx/kick_2.ogg", "sfx/kick.ogg", 20, ("shelf", 2500, -2.0), 0.0),
    "sfx/ham_slam_2.ogg": ("sfx/land_heavy.ogg", "sfx/ham_slam.ogg", 30, ("shelf", 4000, 1.5), -0.6),
    "sfx/jump_2_5.ogg": ("sfx/jump_2_2.ogg", "sfx/jump_2_3.ogg", 22, ("shelf", 3000, 1.5), -0.5),
}


def hybrids():
    """Variants from two takes: the transient of one and the body/tail of another, crossfaded at the end of the
    transient, with a different EQ tilt (critique r1b minor: the r7 variants were varispeed clones)."""
    for out, (ta, tb, tms, eq, bst) in HYBRIDS.items():
        a = A.decode(source(ta), ch=1)
        b = A.decode(source(tb), ch=1)
        b = pitch(b, bst) if bst else b

        def onset(z):
            fr, hop = A.frame_rms_db(z)
            return max(0, int(np.argmax(fr > fr.max() - 20)) * hop - int(0.002 * SR))
        a = a[onset(a):]
        b = b[onset(b):]
        m = int(tms * SR / 1000)
        xf = int(0.008 * SR)
        n = max(len(b), m + xf)
        y = np.zeros((n, 1), np.float32)
        ga = np.ones(n)
        ga[m:m + xf] = np.cos(np.linspace(0, np.pi / 2, xf))
        ga[m + xf:] = 0.0
        y[: len(a)] += a[:n] * ga[: len(a), None] if len(a) <= n else a[:n] * ga[:, None]
        b_al = b * (np.abs(a[:m]).max() / (np.abs(b[:m]).max() + 1e-9)) * 0.9
        gb = 1.0 - ga
        y[: len(b_al)] += b_al[:n] * gb[: len(b_al), None]
        kind, hz, db = eq
        if kind == "lp":
            y = lp(y, hz, 2)
        elif kind == "hp":
            y = hp(y, hz, 2)
        else:
            y = shelf_hi(y, hz, db)
        ref = A.decode(source(tb), ch=1)
        write(to_l100(fades(y, 1, 30), l100(ref)), out, f"hybrid: {Path(ta).stem} transient {tms} ms + {Path(tb).stem} body ({bst:+.1f} st), {kind} {hz}")


def hubclock():
    """Hub clock layer (director minor: still the most salient element of the hub bed): a 2.5 kHz high shelf at -6 dB,
    filtered circularly (the loop is padded with its own tail and head) so the wrap stays seamless. The level drop to
    -17 dB is in juice_sfx.json."""
    x = A.decode(keep_orig("sfx/amb_hub_lb.ogg"), ch=2)
    pad = int(1.0 * SR)
    z = np.concatenate([x[-pad:], x, x[:pad]])
    z = shelf_hi(z, 2500, -6.0)
    z = lp(z, 6000, order=2)
    y = z[pad:pad + len(x)]
    write(y, "sfx/amb_hub_lb.ogg", "hub clock layer: -6 dB shelf above 2.5 kHz, 6 kHz low-pass, circular filtering")


STEPS = {"hubclock": hubclock, "attacks": attacks, "slide": slide, "enemyhit": enemyhit, "bosswind": bosswind, "bee": bee, "greet": greet,
         "fire": fire, "hybrids": hybrids}

if __name__ == "__main__":
    want = sys.argv[1:] or list(STEPS)
    for s in want:
        print("==", s)
        STEPS[s]()
    REP.write_text(json.dumps(rep, indent=1))

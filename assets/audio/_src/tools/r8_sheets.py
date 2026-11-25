"""Review sheets for the r8 fix stage (before = _src/r8_orig, after = the bank).
  attacks  5 ms RMS envelopes of every swish / spin_kick take before and after, with the strike window shaded
  wraps    3x-concatenated spectrograms of re-looped files (a seam shows as a vertical streak every wrap)
Usage: python r8_sheets.py attacks <out.png> | wraps <out.png> <rel> [<rel> ...]"""
import sys
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A

AUD = Path(__file__).resolve().parents[2]
ORIG = AUD / "_src" / "r8_orig"
BG, FG = "#14161c", "#e8e6df"


def env(path):
    x = A.decode(path, ch=1)
    fr, hop = A.frame_rms_db(x)
    t = np.arange(len(fr)) * hop / A.SR * 1000
    return t, fr - fr.max()


def attacks(out):
    names = ["swish", "swish_2", "swish_3", "swish_4", "spin_kick", "spin_kick_2", "spin_kick_3", "spin_kick_4"]
    fig, axes = plt.subplots(2, 4, figsize=(17, 6.4), squeeze=False)
    fig.patch.set_facecolor(BG)
    for i, n in enumerate(names):
        ax = axes.flat[i]
        ax.set_facecolor(BG)
        hi = 240 if "spin" in n else 180
        ax.axvspan(50, hi, color="#3a6ea5", alpha=0.25, label="strike active")
        lo_t, hi_t = (80, 150) if "spin" in n else (40, 90)
        ax.axvspan(lo_t, hi_t, color="#5fae5f", alpha=0.25, label="target peak")
        for p, c, lab in [(ORIG / "sfx" / f"{n}.ogg", "#d9534f", "before (r7)"), (AUD / "sfx" / f"{n}.ogg", "#f0d264", "after (r8)")]:
            if p.exists():
                t, e = env(p)
                ax.plot(t, e, color=c, lw=1.4, label=lab)
                ax.plot(t[int(np.argmax(e))], 0, "o", color=c, ms=5)
        ax.set_xlim(0, 650)
        ax.set_ylim(-45, 3)
        ax.set_title(n, color=FG, fontsize=10)
        ax.tick_params(colors=FG, labelsize=7)
        for s in ax.spines.values():
            s.set_color("#555")
        ax.set_xlabel("ms after the strike starts", color=FG, fontsize=7)
        if i == 0:
            ax.legend(fontsize=7, facecolor=BG, labelcolor=FG, loc="lower right")
    fig.suptitle("Attack whooshes: 5 ms RMS envelope (dB re peak) before/after the r8 re-cut; dots = loudest frame", color=FG)
    fig.tight_layout()
    fig.savefig(out, dpi=110, facecolor=BG)


def spec(x, nfft=1024, hop=256):
    win = np.hanning(nfft)
    frames = 1 + (len(x) - nfft) // hop
    S = np.stack([np.abs(np.fft.rfft(win * x[k * hop:k * hop + nfft])) for k in range(frames)], axis=1)
    return 20 * np.log10(S + 1e-7)


def wraps(out, rels):
    rows = []
    for r in rels:
        for p, tag in [(ORIG / r, "before"), (AUD / r, "after")]:
            if p.exists():
                rows.append((p, f"{Path(r).stem} {tag}"))
    fig, axes = plt.subplots(len(rows), 1, figsize=(15, 1.9 * len(rows)), squeeze=False)
    fig.patch.set_facecolor(BG)
    for ax, (p, lab) in zip(axes[:, 0], rows):
        x = A.decode(p, ch=1)[:, 0]
        L = len(x) / A.SR
        y = np.concatenate([x, x, x])
        S = spec(y)
        f = np.fft.rfftfreq(1024, 1 / A.SR)
        ax.imshow(S, origin="lower", aspect="auto", cmap="magma", vmin=S.max() - 80, vmax=S.max(),
                  extent=[0, 3 * L, 0, f[-1] / 1000])
        for k in (1, 2):
            ax.axvline(k * L, color="#5fd0ff", lw=0.8, ls="--")
        ax.set_ylim(0, 16)
        ax.set_title(f"{lab}: {L:.2f} s loop x3 (dashed = wrap)", color=FG, fontsize=9)
        ax.tick_params(colors=FG, labelsize=7)
        ax.set_ylabel("kHz", color=FG, fontsize=7)
    fig.tight_layout()
    fig.savefig(out, dpi=100, facecolor=BG)


if __name__ == "__main__":
    if sys.argv[1] == "attacks":
        attacks(sys.argv[2])
    else:
        wraps(sys.argv[2], sys.argv[3:])

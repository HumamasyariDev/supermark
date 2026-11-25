"""Render a contact sheet (waveform envelope over a log-frequency spectrogram) for a list of runtime audio files.
Usage: python contact_sheet.py <out.png> <title> <file-or-glob> [...]   (paths relative to game/assets/audio/)"""
import sys, glob
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A

AUD = Path(__file__).resolve().parents[2]


def main():
    out, title, pats = sys.argv[1], sys.argv[2], sys.argv[3:]
    files = []
    for p in pats:
        files += sorted(glob.glob(str(AUD / p)))
    files = [Path(f) for f in files if f.endswith(".ogg")]
    n = len(files)
    cols = 4 if n > 6 else max(1, n)
    rows = int(np.ceil(n / cols))
    fig, axes = plt.subplots(rows, cols, figsize=(4.2 * cols, 2.1 * rows), squeeze=False)
    fig.patch.set_facecolor("#14161c")
    for ax in axes.flat:
        ax.axis("off")
    for i, f in enumerate(files):
        ax = axes.flat[i]
        ax.axis("on")
        x = A.decode(f, ch=1)[:, 0]
        dur = len(x) / A.SR
        nfft = 1024
        hop = 256
        if len(x) < nfft:
            x = np.pad(x, (0, nfft - len(x)))
        win = np.hanning(nfft)
        frames = 1 + (len(x) - nfft) // hop
        S = np.stack([np.abs(np.fft.rfft(win * x[k * hop:k * hop + nfft])) for k in range(frames)], axis=1)
        S = 20 * np.log10(S + 1e-7)
        freqs = np.fft.rfftfreq(nfft, 1 / A.SR)
        ax.imshow(S[1:], origin="lower", aspect="auto", cmap="magma", vmin=S.max() - 80, vmax=S.max(),
                  extent=[0, dur, 1, len(freqs) - 1])
        # log-frequency ticks
        ax.set_yscale("log")
        ax.set_ylim(2, len(freqs) - 1)
        ticks = [100, 1000, 5000, 15000]
        ax.set_yticks([t / (A.SR / nfft) for t in ticks])
        ax.set_yticklabels(["100", "1k", "5k", "15k"], fontsize=6, color="#aaa")
        env = np.sqrt(np.convolve(x ** 2, np.ones(441) / 441, mode="same"))
        t = np.arange(len(env)) / A.SR
        ax2 = ax.twinx()
        ax2.plot(t, 20 * np.log10(env + 1e-6), color="#7fe0ff", lw=0.8)
        ax2.set_ylim(-60, 0)
        ax2.set_yticks([])
        ax.set_xlim(0, dur)
        ax.tick_params(axis="x", labelsize=6, colors="#aaa")
        rms = A.active_rms_db(A.decode(f, ch=1))
        ax.set_title(f"{f.stem}  {dur:.2f}s  act {rms:.1f} dB", fontsize=7, color="#eee")
    fig.suptitle(title, color="#fff", fontsize=10)
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=90, facecolor=fig.get_facecolor())
    print(out, n, "files")


if __name__ == "__main__":
    main()

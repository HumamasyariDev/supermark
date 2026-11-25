"""Review sheet for a real-play clip: 4 frames, the soundtrack's spectrogram, short-term (3 s) and momentary (400 ms)
loudness, and a count of JuiceSfx plays per event from the --juice-sfx-log stdout.
Usage: python clip_sheet.py <clip.mp4> <stdout.log or -> <out.png> <title>"""
import sys, re, subprocess, tempfile, collections
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A

BG, FG = "#14161c", "#e8e6df"


def frames(clip, times, tmp):
    out = []
    for i, t in enumerate(times):
        p = Path(tmp) / f"f{i}.png"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{t:.2f}", "-i", str(clip), "-frames:v", "1", str(p)], check=True)
        out.append(plt.imread(str(p)))
    return out


def loud(clip):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(clip), "-af", "ebur128", "-f", "null", "-"], capture_output=True, text=True)
    rows = re.findall(r"t:\s*([\d.]+)\s+TARGET:.*?M:\s*(-?[\d.]+)\s+S:\s*(-?[\d.]+)", r.stderr)
    t = np.array([float(a) for a, _, _ in rows])
    return t, np.array([float(b) for _, b, _ in rows]), np.array([float(c) for _, _, c in rows])


def main():
    clip, log, out, title = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
    x = A.decode(clip, ch=1)[:, 0]
    dur = len(x) / A.SR
    with tempfile.TemporaryDirectory() as tmp:
        fr = frames(clip, [dur * f for f in (0.12, 0.38, 0.62, 0.88)], tmp)
    counts = collections.Counter()
    if log != "-" and Path(log).exists():
        for line in Path(log).read_text(encoding="utf-8", errors="ignore").splitlines():
            m = re.match(r"\[JuiceSfx\] [\d.]+ (\S+) -> (\S+)", line)
            if m:
                counts[m.group(1)] += 1
    fig = plt.figure(figsize=(16, 11))
    fig.patch.set_facecolor(BG)
    gs = fig.add_gridspec(4, 4, height_ratios=[1.25, 1.2, 0.8, 0.9])
    for i, im in enumerate(fr):
        ax = fig.add_subplot(gs[0, i])
        ax.imshow(im)
        ax.axis("off")
        ax.set_title(f"{dur * (0.12, 0.38, 0.62, 0.88)[i]:.1f} s", color=FG, fontsize=9)
    ax = fig.add_subplot(gs[1, :])
    nfft, hop = 2048, 1024
    win = np.hanning(nfft)
    n = 1 + (len(x) - nfft) // hop
    S = np.stack([np.abs(np.fft.rfft(win * x[k * hop:k * hop + nfft])) for k in range(n)], axis=1)
    S = 20 * np.log10(S + 1e-7)
    ax.imshow(S, origin="lower", aspect="auto", cmap="magma", vmin=S.max() - 85, vmax=S.max(), extent=[0, dur, 0, A.SR / 2000])
    ax.set_ylim(0, 14)
    ax.set_ylabel("kHz", color=FG)
    ax.tick_params(colors=FG)
    ax.set_title("soundtrack spectrogram (game mix as rendered by Movie Maker)", color=FG, fontsize=10)
    ax2 = fig.add_subplot(gs[2, :])
    t, M, Sx = loud(clip)
    ax2.set_facecolor(BG)
    ax2.plot(t, M, color="#5fd0ff", lw=0.8, label="momentary (400 ms)")
    ax2.plot(t, Sx, color="#f0d264", lw=1.6, label="short-term (3 s)")
    ax2.set_xlim(0, dur)
    ax2.set_ylim(-50, -5)
    ax2.set_ylabel("LUFS", color=FG)
    ax2.tick_params(colors=FG)
    ax2.legend(fontsize=8, facecolor=BG, labelcolor=FG, loc="lower right")
    ax3 = fig.add_subplot(gs[3, :])
    ax3.set_facecolor(BG)
    top = counts.most_common(18)
    if top:
        ax3.bar(range(len(top)), [c for _, c in top], color="#7fbf7f")
        ax3.set_xticks(range(len(top)))
        ax3.set_xticklabels([k for k, _ in top], rotation=35, ha="right", fontsize=7, color=FG)
    ax3.tick_params(colors=FG)
    ax3.set_title(f"JuiceSfx plays per event ({sum(counts.values())} total, --juice-sfx-log)", color=FG, fontsize=10)
    fig.suptitle(title, color=FG, fontsize=12)
    fig.tight_layout()
    fig.savefig(out, dpi=95, facecolor=BG)


if __name__ == "__main__":
    main()

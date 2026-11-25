"""Critic spectrogram sheets (librosa mel, linear-in-mel axis, no log-scale rendering artefacts).
usage: spectro_sheet.py out.png title "file[:loops]" ..."""
import sys, subprocess, numpy as np, librosa, librosa.display, matplotlib
matplotlib.use('Agg'); import matplotlib.pyplot as plt
out, title, items = sys.argv[1], sys.argv[2], sys.argv[3:]
fig, axs = plt.subplots(len(items), 1, figsize=(16, 2.6*len(items)), squeeze=False)
for ax, it in zip(axs[:, 0], items):
    f, _, n = it.rpartition(':')
    if not n.isdigit(): f, n = it, '1'
    n = int(n)
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', f, '-f', 'f32le', '-ac', '1', '-ar', '32000', '-'], capture_output=True).stdout
    y = np.tile(np.frombuffer(raw, np.float32), n)
    S = librosa.power_to_db(librosa.feature.melspectrogram(y=y, sr=32000, n_fft=2048, hop_length=256, n_mels=128, fmax=14000), ref=np.max)
    librosa.display.specshow(S, sr=32000, hop_length=256, x_axis='time', y_axis='mel', fmax=14000, ax=ax, vmin=-80, vmax=0, cmap='magma')
    L = len(y)/32000/n
    for k in range(1, n): ax.axvline(k*L, color='cyan', lw=1, ls='--')
    ax.set_title(f.split('/')[-1] + (f'  (looped {n}x, cyan = loop point)' if n > 1 else ''), fontsize=9, loc='left')
fig.suptitle(title, fontsize=11); fig.tight_layout(); fig.savefig(out, dpi=80)

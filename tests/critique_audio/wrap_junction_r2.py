"""Critic r2 (audio director): loop-wrap junction test, as the engine plays it. For every looping file in the
index, splice [last 3 s][first 3 s] (what the player hears at the wrap) and measure, AT the junction only:
  - onset z: spectral-flux onset strength at the junction vs the distribution of the same file's interior
    (computed on a padded-free interior so file-start padding does not fake an onset),
  - flux percentile: log-mel spectral flux across the junction vs every interior hop,
  - rms step dB (10 ms windows) vs the interior p99 step.
A junction is SUSPECT when onset z > 3 or flux percentile > 97 or rms step > interior p99 + 3 dB.
Writes JSON, and a spectrogram sheet of the worst junctions (+-1.5 s around the wrap).
usage: wrap_junction_r2.py out.json sheet.png"""
import json, pathlib, subprocess, sys
import numpy as np, librosa
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

G = pathlib.Path(__file__).resolve().parents[2]
A = G / 'assets/audio'
SR = 32000
HOP = 256


def dec(p):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(p), '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def flux(y):
    S = librosa.power_to_db(librosa.feature.melspectrogram(y=y.astype(np.float32), sr=SR, n_fft=1024, hop_length=HOP,
                                                           n_mels=64, center=False))
    d = np.diff(S, axis=1)
    return np.maximum(d, 0).mean(axis=0)  # half-wave rectified flux per hop


idx = json.load(open(A / 'audio_index.json'))['entries']
keys_for = {}
for e in idx:
    if e.get('loop'):
        for f in (e.get('files') or [e['file']]):
            keys_for.setdefault(f, []).append(e['key'])
rows = []
for f, keys in sorted(keys_for.items()):
    x = dec(A / f)
    if len(x) < SR * 1.0:
        continue
    seg = min(3.0, len(x) / SR / 2.2)
    n = int(seg * SR)
    j = np.concatenate([x[-n:], x[:n]])
    fj = flux(j)
    jh = (n - 1024) // HOP  # hop index whose window straddles the junction
    win = fj[max(0, jh - 2): jh + 4]
    fx_j = float(win.max())
    fi = flux(x)
    fi = fi[4:-4]
    fi = np.lib.stride_tricks.sliding_window_view(fi, len(win)).max(axis=1)  # same 6-hop max as the junction window
    pct = float((fi < fx_j).mean() * 100)
    z = float((fx_j - fi.mean()) / (fi.std() + 1e-9))
    w = int(0.01 * SR)
    rms = lambda s: 20 * np.log10(np.sqrt(np.mean(s ** 2)) + 1e-9)
    rstep = abs(rms(x[-w:]) - rms(x[:w]))
    r = 20 * np.log10(np.sqrt(np.convolve(x ** 2, np.ones(w) / w, 'valid'))[::w] + 1e-9)
    p99 = float(np.percentile(np.abs(np.diff(r)), 99))
    suspect = z > 3.0 or pct > 97.0 or rstep > p99 + 3.0
    rows.append(dict(file=f, keys=keys, dur=round(len(x) / SR, 2), junction_onset_z=round(z, 2), junction_flux_pct=round(pct, 1),
                     junction_rms_step_db=round(float(rstep), 2), interior_p99_rms_step_db=round(p99, 2), suspect=bool(suspect)))
rows.sort(key=lambda r: -r['junction_onset_z'])
json.dump(rows, open(sys.argv[1], 'w'), indent=1)
for r in rows:
    print(('SUSPECT ' if r['suspect'] else '        ') + json.dumps(r))
worst = [r for r in rows][:8]
fig, axs = plt.subplots(len(worst), 1, figsize=(12, 1.7 * len(worst)))
for ax, r in zip(axs, worst):
    x = dec(A / r['file'])
    n = int(min(1.5, len(x) / SR / 2.2) * SR)
    j = np.concatenate([x[-n:], x[:n]])
    S = librosa.power_to_db(np.abs(librosa.stft(j.astype(np.float32), n_fft=1024, hop_length=128)) ** 2, ref=np.max)
    ax.imshow(S[:400], origin='lower', aspect='auto', cmap='magma', vmin=-80, vmax=0,
              extent=[-n / SR, n / SR, 0, 400 * SR / 1024 / 1000])
    ax.axvline(0, color='cyan', lw=0.8, ls='--')
    ax.set_ylabel('kHz', fontsize=7)
    ax.set_title(f"{r['file']}  z={r['junction_onset_z']}  flux pct={r['junction_flux_pct']}  rms step={r['junction_rms_step_db']} dB"
                 f"{'  SUSPECT' if r['suspect'] else ''}", fontsize=8)
    ax.tick_params(labelsize=6)
fig.suptitle('Loop wrap junctions as played (tail | head), dashed = wrap point. Critic r2 audio director', fontsize=10)
fig.tight_layout()
fig.savefig(sys.argv[2], dpi=80)


# ---- two-sided band check (added after the first sheet: half-wave flux misses a band that DROPS at the wrap)
def bands(y):
    S = np.abs(librosa.stft(y.astype(np.float32), n_fft=2048, hop_length=2048, center=False)) ** 2
    fr = librosa.fft_frequencies(sr=SR, n_fft=2048)
    lo = 10 * np.log10(S[fr < 1000].sum(axis=0) + 1e-12)
    hi = 10 * np.log10(S[fr >= 2000].sum(axis=0) + 1e-12)
    return lo, hi


band_rows = []
for r in rows:
    x = dec(A / r['file'])
    k = 4  # 4 x 64 ms = 256 ms each side
    lo, hi = bands(x)
    nfr = len(hi)
    if nfr < 4 * k:
        continue
    def stepdist(v):
        s = [abs(v[i - k:i].mean() - v[i:i + k].mean()) for i in range(k, nfr - k)]
        return np.array(s)
    w = 2048 * k
    j = np.concatenate([x[-w:], x[:w]])
    jlo, jhi = bands(j)
    out = {}
    for name, v, jv in (('low', lo, jlo), ('high', hi, jhi)):
        d = stepdist(v)
        js = abs(jv[:k].mean() - jv[k:2 * k].mean())
        out[name] = (round(float(js), 2), round(float((d < js).mean() * 100), 1), round(float(np.percentile(d, 99)), 2))
    r['band_step_db_pct_p99'] = out
    if out['high'][1] > 98 or out['low'][1] > 98:
        r['suspect_band'] = True
    band_rows.append(r)
json.dump(rows, open(sys.argv[1], 'w'), indent=1)
print('---- band steps across the wrap (dB, percentile vs interior 256 ms steps, interior p99)')
for r in sorted(band_rows, key=lambda r: -max(r['band_step_db_pct_p99']['high'][1], r['band_step_db_pct_p99']['low'][1])):
    print(('BAND-SUSPECT ' if r.get('suspect_band') else '             ') + r['file'], r['band_step_db_pct_p99'])

"""Critic loudness/timing audit (audio director r1). Read-only. Independent of the track's tools:
own K-weighting (BS.1770 filters re-derived for any sample rate), L100 (loudest 100 ms), integrated
loudness via ffmpeg ebur128 for files > 3 s, sample peak and 4x-oversampled true peak, onset delay
(first 5 ms frame within 30 dB of the file's loudest frame), tail, DC offset, effective level =
measure + index volume_db, compared with the README group targets."""
import json, pathlib, subprocess, re, sys, math
import numpy as np
from scipy import signal
G = pathlib.Path(__file__).resolve().parents[2]
A = G/'assets/audio'
SR = 48000
TARGET_L100 = {'voice': -16, 'impact': -14, 'reward': -15, 'boss': -15, 'boss_voice': -15, 'pickup': -17,
               'world_big': -17, 'enemy': -18, 'action': -19, 'world': -19, 'ui': -21, 'foley': -24, 'footstep': -25.5}
TARGET_I = {'music': -24, 'jingle': -19, 'ambience': -30, 'loop': -29}

def decode(p):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(p), '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)

def kfilter(fs):
    # BS.1770 stage 1 (high shelf) and stage 2 (high pass), re-derived for fs (pyloudnorm formulation)
    G_, Q, fc = 3.99984385397, 0.7071752369554193, 1681.9744509555319
    A_ = 10 ** (G_ / 40.0); w0 = 2 * math.pi * fc / fs; al = math.sin(w0) / (2 * Q)
    b = [A_*((A_+1)+(A_-1)*math.cos(w0)+2*math.sqrt(A_)*al), -2*A_*((A_-1)+(A_+1)*math.cos(w0)), A_*((A_+1)+(A_-1)*math.cos(w0)-2*math.sqrt(A_)*al)]
    a = [(A_+1)-(A_-1)*math.cos(w0)+2*math.sqrt(A_)*al, 2*((A_-1)-(A_+1)*math.cos(w0)), (A_+1)-(A_-1)*math.cos(w0)-2*math.sqrt(A_)*al]
    # the shelf above is the RBJ high shelf; BS.1770 uses that exact form
    Q2, fc2 = 0.5003270373253953, 38.13547087613982
    w2 = 2*math.pi*fc2/fs; al2 = math.sin(w2)/(2*Q2)
    b2 = [(1+math.cos(w2))/2, -(1+math.cos(w2)), (1+math.cos(w2))/2]
    a2 = [1+al2, -2*math.cos(w2), 1-al2]
    return (np.array(b)/a[0], np.array(a)/a[0]), (np.array(b2)/a2[0], np.array(a2)/a2[0])
(B1, A1), (B2, A2) = kfilter(SR)

def kw(x):
    return signal.lfilter(B2, A2, signal.lfilter(B1, A1, x, axis=0), axis=0)

def l100(x):
    y = kw(x); ms = np.sum(y ** 2, axis=1)  # sum of channel mean squares (L+R weights 1.0)
    n = int(0.1 * SR)
    if len(ms) < n:
        ms = np.pad(ms, (0, n - len(ms)))
    c = np.convolve(ms, np.ones(n) / n, mode='valid')
    return -0.691 + 10 * np.log10(max(c.max(), 1e-12))

def integrated(p):
    r = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', str(p), '-af', 'ebur128=peak=true', '-f', 'null', '-'],
                       capture_output=True, text=True)
    m = re.search(r'Integrated loudness:\s+I:\s+(-?[\d.]+) LUFS', r.stderr)
    lra = re.search(r'LRA:\s+(-?[\d.]+) LU', r.stderr)
    return (float(m.group(1)) if m else None), (float(lra.group(1)) if lra else None)

def frames_db(x, ms=5):
    n = int(SR * ms / 1000); m = len(x) // n
    if m == 0: return np.array([-120.0])
    e = np.mean((x[:m*n] ** 2).reshape(m, n, 2), axis=(1, 2))
    return 10 * np.log10(e + 1e-12)

idx = json.load(open(A/'audio_index.json'))['entries']
rows = []; seen = {}
for e in idx:
    files = e.get('files') or [e['file']]
    for f in files:
        if f not in seen:
            p = A/f; x = decode(p)
            fd = frames_db(x); pk_frame = fd.max()
            on = int(np.argmax(fd > pk_frame - 30)) * 5
            last = len(fd) - 1 - int(np.argmax(fd[::-1] > pk_frame - 45))
            tp = 20*np.log10(np.abs(signal.resample_poly(x, 4, 1, axis=0)).max() + 1e-12)
            d = len(x) / SR
            I, LRA = integrated(p) if d > 3 else (None, None)
            seen[f] = dict(file=f, dur=round(d, 3), l100=round(l100(x), 2), I=I, lra=LRA,
                           peak=round(20*np.log10(np.abs(x).max()+1e-12), 2), tp=round(tp, 2), onset_ms=on,
                           tail_ms=round((len(fd) - 1 - last) * 5), dc=round(float(np.abs(x.mean(axis=0)).max()), 5))
    m = [seen[f] for f in files]
    g = e.get('group', '')
    l = [r['l100'] for r in m]
    row = dict(key=e['key'], group=g, bus=e.get('bus'), vol=e.get('volume_db', 0.0), loop=e.get('loop', False), n=len(files),
               files=files, l100_mean=round(float(np.mean(l)), 2), l100_spread=round(max(l) - min(l), 2),
               eff_l100=round(float(np.mean(l)) + e.get('volume_db', 0.0), 2), onset_max=max(r['onset_ms'] for r in m),
               dur_max=max(r['dur'] for r in m), tp_max=max(r['tp'] for r in m))
    if all(r['I'] is not None for r in m):
        row['I_mean'] = round(float(np.mean([r['I'] for r in m])), 2)
        row['eff_I'] = round(row['I_mean'] + e.get('volume_db', 0.0), 2)
    t = TARGET_L100.get(g)
    if t is not None: row['dev_l100'] = round(row['eff_l100'] - t, 2)
    t = TARGET_I.get(g)
    if t is not None and 'eff_I' in row: row['dev_I'] = round(row['eff_I'] - t, 2)
    rows.append(row)
out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else G/'tests/critique_audio/loudness_audit.json'
json.dump(dict(files=list(seen.values()), keys=rows), open(out, 'w'), indent=1)
print('files', len(seen), 'keys', len(rows), '->', out)

"""Critic loop-seam audit, independent of _src/tools/seam_check.py. For every looping file:
wrap sample jump vs the file's own p99/p999 step, 20 ms RMS step across the wrap vs the distribution of
20 ms RMS steps everywhere, spectral (log-mel) distance across the wrap vs random adjacent windows (percentile),
and for beds: the loudest transients (they repeat once per file length). Read-only."""
import json, pathlib, subprocess, sys
import numpy as np, librosa
G = pathlib.Path(__file__).resolve().parents[2]; A = G/'assets/audio'; SR = 48000
def dec(p):
    raw = subprocess.run(['ffmpeg','-v','error','-i',str(p),'-f','f32le','-ac','2','-ar',str(SR),'-'],capture_output=True,check=True).stdout
    return np.frombuffer(raw,np.float32).reshape(-1,2).astype(np.float64)
idx = json.load(open(A/'audio_index.json'))['entries']
loops = sorted({f for e in idx if e.get('loop') for f in (e.get('files') or [e['file']])})
out = []
rng = np.random.default_rng(1)
for f in loops:
    x = dec(A/f); m = x.mean(axis=1)
    steps = np.abs(np.diff(m)); wrap = abs(m[0] - m[-1])
    n = int(0.02*SR); r = np.sqrt(np.convolve(m**2, np.ones(n)/n, 'valid'))
    rdb = 20*np.log10(r+1e-9); hop = n
    rs = rdb[::hop]; dsteps = np.abs(np.diff(rs))
    wr = abs(20*np.log10(np.sqrt(np.mean(m[-n:]**2))+1e-9) - 20*np.log10(np.sqrt(np.mean(m[:n]**2))+1e-9))
    # spectral distance across the wrap (93 ms windows)
    w = 4096
    def mel(seg): return librosa.power_to_db(librosa.feature.melspectrogram(y=seg, sr=SR, n_fft=w, hop_length=w, n_mels=40, center=False)).mean(axis=1)
    sd_wrap = np.linalg.norm(mel(m[-w:]) - mel(m[:w]))
    rand = []
    for _ in range(60):
        i = rng.integers(w, len(m)-w); rand.append(np.linalg.norm(mel(m[i-w:i]) - mel(m[i:i+w])))
    pct = float((np.array(rand) < sd_wrap).mean()*100)
    row = dict(file=f, dur=round(len(m)/SR,2), wrap_jump=round(float(wrap),4), p99_step=round(float(np.percentile(steps,99)),4),
               p999_step=round(float(np.percentile(steps,99.9)),4), wrap_rms_db=round(float(wr),2),
               p95_rms_step_db=round(float(np.percentile(dsteps,95)),2), spec_wrap=round(float(sd_wrap),2),
               spec_wrap_percentile=round(pct,1))
    if 'bed' in f or 'amb_' in f or 'loop' in f:
        o = librosa.onset.onset_strength(y=m.astype(np.float32), sr=SR, hop_length=512)
        t = librosa.frames_to_time(np.argsort(o)[-5:][::-1], sr=SR, hop_length=512)
        z = (o - o.mean())/ (o.std()+1e-9)
        row['top_onsets_s'] = [round(float(v),2) for v in t]
        row['top_onset_z'] = [round(float(v),1) for v in np.sort(z)[-5:][::-1]]
    out.append(row)
    print(row)
json.dump(out, open(sys.argv[1] if len(sys.argv)>1 else G/'tests/critique_audio/seam_audit.json','w'), indent=1)

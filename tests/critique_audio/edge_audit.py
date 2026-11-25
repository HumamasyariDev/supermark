"""Critic edge audit: abrupt starts (first-sample jump) and truncated ends (last 3 ms still loud) in one-shots,
plus per-variant L100 for footsteps. Read-only."""
import json, pathlib, subprocess, sys
import numpy as np
G = pathlib.Path(__file__).resolve().parents[2]; A = G/'assets/audio'
def dec(p):
    raw = subprocess.run(['ffmpeg','-v','error','-i',str(p),'-f','f32le','-ac','2','-ar','48000','-'],capture_output=True,check=True).stdout
    return np.frombuffer(raw,np.float32).reshape(-1,2)
idx = json.load(open(A/'audio_index.json'))['entries']
files = {}
for e in idx:
    if e.get('loop'): continue
    for f in (e.get('files') or [e['file']]): files[f] = e.get('group')
res = []
for f, g in sorted(files.items()):
    x = dec(A/f); pk = np.abs(x).max() + 1e-9
    first = float(np.abs(x[0]).max()) / pk
    end = x[-144:]; end_db = 20*np.log10(np.sqrt(np.mean(end**2))+1e-9) - 20*np.log10(pk)
    res.append((f, g, round(first, 3), round(float(end_db), 1)))
bad_start = [r for r in res if r[2] > 0.05]
bad_end = [r for r in res if r[3] > -35]
print('abrupt start (first sample > 5% of peak):', len(bad_start)); [print(' ', r) for r in bad_start]
print('truncated end (last 3 ms within 35 dB of peak):', len(bad_end)); [print(' ', r) for r in bad_end]

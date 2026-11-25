"""Short-window loudness (L100): max over 100 ms windows (10 ms hop) of ITU-R BS.1770 K-weighted loudness, for one-shots
whose length is near or under the 400 ms momentary window (ebur128 M underestimates them). Adds 'L100' to loudness.json."""
import json, subprocess
from pathlib import Path
import numpy as np
from scipy.signal import lfilter
from concurrent.futures import ThreadPoolExecutor

AUD = Path(__file__).resolve().parents[2]
REP = AUD / "_src" / "reports" / "loudness.json"
# BS.1770 K-weighting at 48 kHz
B1, A1 = [1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585]
B2, A2 = [1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621]


def l100(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(AUD / path), "-f", "f32le", "-ar", "48000", "-"], capture_output=True).stdout
    ch = 2 if path.startswith("music") or "amb_" in path else 1
    x = np.frombuffer(raw, np.float32)
    try:
        x = x.reshape(-1, ch)
    except ValueError:
        x = x.reshape(-1, 1)
    y = lfilter(B2, A2, lfilter(B1, A1, x, axis=0), axis=0)
    p = (y ** 2).sum(axis=1)
    w, hop = 4800, 480
    if len(p) < w:
        p = np.pad(p, (0, w - len(p)))
    c = np.concatenate([[0.0], np.cumsum(p)])
    m = (c[w::hop][: (len(p) - w) // hop + 1] - c[0:len(p) - w + 1:hop]) / w
    return path, round(float(-0.691 + 10 * np.log10(m.max() + 1e-12)), 2)


d = json.loads(REP.read_text())
with ThreadPoolExecutor(12) as ex:
    for k, v in ex.map(l100, list(d)):
        d[k]["L100"] = v
REP.write_text(json.dumps(d, indent=1))
print("L100 added to", len(d))

"""Numeric seam check of every looping file in the index: decode the runtime .ogg, then compare the wrap (last sample ->
first sample) with the file's own sample-to-sample steps, and the RMS of the 50 ms before/after the wrap.
seam_ratio = |x[0] - x[-1]| / p99(|diff|)  (< 1: the wrap is smaller than 99 % of the file's own steps, i.e. no click)
rms_jump_db = level change across the wrap (50 ms windows), judged against the same measure at 400 random points. Writes _src/reports/seam_check.json."""
import json, sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A

AUD = Path(__file__).resolve().parents[2]
idx = json.loads((AUD / "audio_index.json").read_text())
files = sorted({f for e in idx["entries"] if e.get("loop") for f in (e.get("files") or [e["file"]])})
res = {}
for f in files:
    x = A.decode(AUD / f, ch=2)
    d = np.abs(np.diff(x, axis=0)).max(axis=1)
    p99 = float(np.percentile(d, 99)) + 1e-9
    jump = float(np.max(np.abs(x[0] - x[-1])))
    w = int(0.05 * A.SR)
    pre, post = A.rms_db(x[-w:]), A.rms_db(x[:w])
    # the same level change measured at 400 random cut points inside the file: a seam is natural when its jump is
    # no larger than the 95th percentile of the file's own 50 ms level changes
    rng = np.random.default_rng(0)
    pos = rng.integers(w, len(x) - w, 400)
    nat = np.array([abs(A.rms_db(x[p:p + w]) - A.rms_db(x[p - w:p])) for p in pos])
    p95 = float(np.percentile(nat, 95))
    pct = float((nat < abs(post - pre)).mean() * 100)
    res[f] = {"dur_s": round(len(x) / A.SR, 3), "seam_ratio": round(jump / p99, 3), "rms_jump_db": round(post - pre, 2),
              "natural_p95_db": round(p95, 2), "jump_percentile": round(pct, 1),
              "pass": bool(jump / p99 < 1.0 and abs(post - pre) <= p95)}
(AUD / "_src" / "reports" / "seam_check.json").write_text(json.dumps(res, indent=1))
for f, r in res.items():
    print(f"{'PASS' if r['pass'] else 'FAIL'} {f:42s} {r['dur_s']:7.2f}s seam {r['seam_ratio']:.3f} level {r['rms_jump_db']:+.2f} dB (file's own p95 {r['natural_p95_db']:.2f}, pct {r['jump_percentile']:.0f})")
print(sum(r["pass"] for r in res.values()), "/", len(res))

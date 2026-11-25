"""Level-match one-shot SFX and voice files to L100 = -16 LUFS (100 ms K-weighted max) so random variants of a key sit
within about 1.5 dB of each other. Gain is capped so true peak stays <= -1 dBFS; a gentle limiter allows up to 3 dB more
on transient-heavy files. Files within 1.5 dB are left untouched (no re-encode). Loops, ambience and music are skipped.
Files that need gain but have no peak headroom left are skipped (re-running must not ratchet the limiter;
fixed in the night-01 implementation stage). Writes _src/reports/level_match.json. Run short_loudness.py first, then mix_analyze.py + short_loudness.py again."""
import json, sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A

AUD = Path(__file__).resolve().parents[2]
L = json.loads((AUD / "_src" / "reports" / "loudness.json").read_text())
log = {}
for f, v in L.items():
    if f.startswith("music/") or "amb_" in f or "_loop" in f or f.endswith("bee_buzz.ogg") or v.get("L100") is None:
        continue
    want = -16.0 - v["L100"]
    if abs(want) <= 1.5:
        continue
    head = -1.0 - v["tp"]
    if want > 0 and head < 0.5:
        continue  # already peak-bound (limited by an earlier pass): another pass would only re-limit and re-encode it
    g = min(want, head + 3.0)
    if abs(g) < 0.5:
        continue
    x = A.decode(AUD / f, ch=1)
    y = x * (10 ** (g / 20))
    if A.peak_db(y) > -1.0:
        y = A.limiter(y, -1.0)
    A.encode_ogg(y, AUD / f)
    log[f] = {"L100_before": v["L100"], "gain_db": round(g, 2), "limited": g > head}
(AUD / "_src" / "reports" / "level_match.json").write_text(json.dumps(log, indent=1))
print(len(log), "files re-levelled")

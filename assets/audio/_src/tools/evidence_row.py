"""Append one row to data/evidence.jsonl for the audio track.
Usage: python evidence_row.py <feature> <capture_type> <file relative to the entity> <caption> <observed>"""
import sys, json, hashlib, datetime
from pathlib import Path

ENT = Path(__file__).resolve().parents[5]
feature, ctype, rel, caption, observed = sys.argv[1:6]
f = ENT / rel
row = {"utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "timezone": "Asia/Bangkok", "run": "night01",
       "feature": feature, "milestone": "M3", "capture_type": ctype, "file": rel,
       "sha256": hashlib.sha256(f.read_bytes()).hexdigest(), "caption": caption, "observed": observed, "reviewed": True}
with open(ENT / "data" / "evidence.jsonl", "a", encoding="utf-8") as fh:
    fh.write(json.dumps(row) + "\n")
print("evidence row:", rel)

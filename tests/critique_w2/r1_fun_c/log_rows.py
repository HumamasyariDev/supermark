"""Append evidence rows for the W2 r1 fun pass C files given on the command line as path::caption."""
import datetime, hashlib, json, os, sys
ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
out = open(os.path.join(ENT, "data", "evidence.jsonl"), "a", encoding="utf-8")
for arg in sys.argv[1:]:
    rel, cap = arg.split("::", 1)
    p = os.path.join(ENT, rel)
    if not os.path.exists(p):
        print("missing", rel); continue
    ext = os.path.splitext(rel)[1].lower()
    ctype = {".mp4": "native_gameplay_movie", ".png": "native_gameplay_still", ".log": "log"}.get(ext, "file")
    row = {"utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "timezone": "Asia/Bangkok", "run": "night02",
           "feature": "critique-w2-r1-fun", "milestone": "critic-r1", "capture_type": ctype, "file": rel.replace("\\", "/"),
           "sha256": hashlib.sha256(open(p, "rb").read()).hexdigest(), "caption": cap, "reviewed": True}
    out.write(json.dumps(row) + "\n"); print("ok", rel)

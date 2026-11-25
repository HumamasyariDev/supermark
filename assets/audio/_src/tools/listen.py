"""AI listen-check through fal-ai/audio-understanding ($0.01 per 5 s). Logs cost before submission.
Usage: python listen.py <audio> <name> "<prompt>" """
import sys, json, os, re, subprocess
from pathlib import Path
from datetime import datetime, timezone
sys.path.insert(0, str(Path(__file__).parent))
import gen_audio as G
import fal_client

audio, name, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
SRC = Path(__file__).resolve().parents[1]
out = SRC / "reports" / f"listen_{name}.json"
if out.exists():
    print(out.read_text()); sys.exit(0)
dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", audio], capture_output=True, text=True).stdout)
est = round(-(-dur // 5) * 0.01, 3)
G.log_cost({"utc": G.now(), "phase": "night01-audio-review", "provider": "fal.ai", "model": "fal-ai/audio-understanding", "job_id": None,
            "asset_key": f"listen_{name}", "quoted_unit": "5 seconds @ $0.01", "quoted_qty": round(dur / 5, 2), "max_reserved_usd": est + 0.01,
            "billed_usd": None, "state": "reserved_before_submit", "workstream": "audio"})
url = fal_client.upload_file(audio)
h = fal_client.submit("fal-ai/audio-understanding", arguments={"audio_url": url, "prompt": prompt, "detailed_analysis": True})
res = h.get()
G.log_cost({"utc": G.now(), "phase": "night01-audio-review", "provider": "fal.ai", "model": "fal-ai/audio-understanding", "job_id": h.request_id,
            "asset_key": f"listen_{name}", "estimated_usd": est, "billed_usd": None, "state": "completed", "workstream": "audio"})
rec = {"utc": G.now(), "audio": str(audio), "duration_s": dur, "prompt": prompt, "request_id": h.request_id, "result": res}
out.write_text(json.dumps(rec, indent=1), encoding="utf-8")
print(json.dumps(res, indent=1)[:4000])

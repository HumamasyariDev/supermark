"""Run fal.ai audio jobs for Super Mak 64 with cost logging before submission.

Usage: python gen_audio.py <spec.json> [--only key1,key2] [--workers 6]
spec.json: {"phase": "...", "jobs": [{"key": "...", "endpoint": "...", "input": {...},
             "quoted_unit": "...", "quoted_qty": n, "max_reserved_usd": x}]}
Receipts: _src/jobs/<key>.json (an existing receipt with a request id blocks resubmission).
Downloads: _src/raw/<key>.<ext>
"""
import json, os, re, sys, time, urllib.request, concurrent.futures as cf
from datetime import datetime, timezone
from pathlib import Path
from dotenv import dotenv_values

SRC = Path(__file__).resolve().parents[1]
ENTITY = SRC.parents[3]
COSTS = ENTITY / "data" / "costs.jsonl"
v = dotenv_values(r"C:/GIT/mr-mak/.env")
os.environ["FAL_KEY"] = re.sub(r"^(Bearer|Key)\s+", "", (v.get("FALAI_KEY") or "").strip(), flags=re.I)
import fal_client  # noqa: E402


def now():
    return datetime.now(timezone.utc).isoformat()


def log_cost(row):
    with open(COSTS, "a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def find_urls(obj):
    out = []
    if isinstance(obj, dict):
        for k, val in obj.items():
            if k == "url" and isinstance(val, str) and val.startswith("http"):
                out.append(val)
            else:
                out += find_urls(val)
    elif isinstance(obj, list):
        for x in obj:
            out += find_urls(x)
    return out


def run(job, phase):
    key = job["key"]
    rec_path = SRC / "jobs" / f"{key}.json"
    rec = json.loads(rec_path.read_text(encoding="utf-8")) if rec_path.exists() else None
    if rec and rec.get("status") == "downloaded":
        return key, "already downloaded"
    if not rec or not rec.get("request_id"):
        if rec and rec.get("status") == "submission_unknown":
            return key, "submission_unknown: inspect history before retrying"
        log_cost({"utc": now(), "phase": phase, "provider": "fal.ai", "model": job["endpoint"],
                  "job_id": None, "asset_key": key, "quoted_unit": job.get("quoted_unit"),
                  "quoted_qty": job.get("quoted_qty"), "max_reserved_usd": job.get("max_reserved_usd"),
                  "billed_usd": None, "state": "reserved_before_submit", "workstream": "audio"})
        rec = {"key": key, "endpoint": job["endpoint"], "input": job["input"], "created": now(),
               "status": "submission_pending"}
        rec_path.write_text(json.dumps(rec, indent=1), encoding="utf-8")
        try:
            h = fal_client.submit(job["endpoint"], arguments=job["input"])
            rec.update(request_id=h.request_id, status="submitted")
        except Exception as e:
            rec.update(status="submit_failed", error=f"{type(e).__name__}: {str(e)[:400]}")
            rec_path.write_text(json.dumps(rec, indent=1), encoding="utf-8")
            log_cost({"utc": now(), "phase": phase, "provider": "fal.ai", "model": job["endpoint"], "job_id": None,
                      "asset_key": key, "billed_usd": None, "state": "submit_failed_not_billed_expected", "workstream": "audio"})
            return key, rec["error"]
        rec_path.write_text(json.dumps(rec, indent=1), encoding="utf-8")
    rid = rec["request_id"]
    t0 = time.time()
    while True:
        try:
            st = fal_client.status(rec["endpoint"], rid, with_logs=False)
        except Exception as e:
            st = None
        name = type(st).__name__ if st else "unknown"
        if name == "Completed":
            break
        if time.time() - t0 > 900:
            rec["status"] = "timeout_waiting"
            rec_path.write_text(json.dumps(rec, indent=1), encoding="utf-8")
            return key, "timeout (resume later)"
        time.sleep(4)
    try:
        res = fal_client.result(rec["endpoint"], rid)
    except Exception as e:
        rec.update(status="failed", error=f"{type(e).__name__}: {str(e)[:400]}")
        rec_path.write_text(json.dumps(rec, indent=1), encoding="utf-8")
        log_cost({"utc": now(), "phase": phase, "provider": "fal.ai", "model": rec["endpoint"], "job_id": rid,
                  "asset_key": key, "billed_usd": None, "state": "failed_result", "workstream": "audio"})
        return key, rec["error"]
    rec["result"] = res
    urls = find_urls(res)
    files = []
    for i, u in enumerate(urls):
        ext = Path(u.split("?")[0]).suffix or ".bin"
        dst = SRC / "raw" / (f"{key}{ext}" if i == 0 else f"{key}_{i}{ext}")
        with urllib.request.urlopen(u, timeout=120) as r:
            dst.write_bytes(r.read())
        files.append(str(dst.relative_to(SRC)).replace("\\", "/"))
    rec.update(status="downloaded", files=files, completed=now())
    rec_path.write_text(json.dumps(rec, indent=1), encoding="utf-8")
    log_cost({"utc": now(), "phase": phase, "provider": "fal.ai", "model": rec["endpoint"], "job_id": rid,
              "asset_key": key, "quoted_unit": job.get("quoted_unit"), "quoted_qty": job.get("quoted_qty"),
              "estimated_usd": job.get("estimated_usd", job.get("max_reserved_usd")), "billed_usd": None,
              "state": "completed", "workstream": "audio"})
    return key, f"ok {files}"


if __name__ == "__main__":
    spec = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    only = None
    workers = 6
    a = sys.argv[2:]
    if "--only" in a:
        only = set(a[a.index("--only") + 1].split(","))
    if "--workers" in a:
        workers = int(a[a.index("--workers") + 1])
    jobs = [j for j in spec["jobs"] if not only or j["key"] in only]
    with cf.ThreadPoolExecutor(workers) as ex:
        futs = [ex.submit(run, j, spec["phase"]) for j in jobs]
        for f in cf.as_completed(futs):
            try:
                print(*f.result(), flush=True)
            except Exception as e:
                print("ERROR", e, flush=True)

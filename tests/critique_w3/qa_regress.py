"""W3 critique round 1 (QA AND TECHNICAL lens): re-run every builder truffle bot on the CURRENT code, one Godot
process at a time, on fresh critic save profiles, and summarise result, truffle, errors and warnings per plan.

Reads the builder's replay configs in Docs/progress/w3/replays/<name>.json (read-only) and writes only to
Docs/progress/critique/w3/r1_qa/bots/. Traces are summarised (death count, min y, damage) and then deleted to save disk.

    python game/tests/critique_w3/qa_regress.py [plan ...]     (default: all plans)
"""
import json, os, re, subprocess, sys, time
from pathlib import Path

ENT = Path(__file__).resolve().parents[3]
SRC = ENT / "Docs" / "progress" / "w3" / "replays"
OUT = ENT / "Docs" / "progress" / "critique" / "w3" / "r1_qa" / "bots"
PLANS = ["w31bot", "w32bot", "w33bot", "w34bot", "w34clean", "w35bot", "w36bot", "w37bot", "w38bot", "w38neg", "w3100bot"]


def run(name):
    rep = json.loads((SRC / f"{name}.json").read_text())
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    OUT.mkdir(parents=True, exist_ok=True)
    rp = OUT / f"{name}_{stamp}.replay.json"
    rp.write_text(json.dumps(rep))
    trace = OUT / f"{name}_{stamp}.jsonl"
    prof = f"critic_w3_qa_{name}_{stamp}"
    secs = max(20, int(rep.get("end_frame", 600) / 60) + 25)
    cmd = [sys.executable, str(ENT / "tools" / "godot.py"), "run", "res://scenes/worlds/w3/W3.tscn", "--seconds", str(secs), "--",
           f"--replay={rp}", f"--trace={trace}", f"--profile={prof}"] + rep.get("args", [])
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=ENT)
    out = (p.stdout or "") + (p.stderr or "")
    (OUT / f"{name}_{stamp}.log").write_text(out, encoding="utf-8")
    res = [l for l in out.splitlines() if "RESULT" in l and "W3 bot" in l]
    tru = [l for l in out.splitlines() if "[Game] truffle" in l]
    errs = [l for l in out.splitlines() if re.search(r"SCRIPT ERROR|ERROR:|Parse Error", l)]
    warns = [l for l in out.splitlines() if "WARNING:" in l and "UID duplicate" not in l]
    fps = [l for l in out.splitlines() if "fps" in l.lower() and "W3" in l][-1:]
    summ = {"plan": name, "utc": stamp, "exit": p.returncode, "wall_s": round(time.time() - t0, 1), "result": res[-1:] , "truffles": tru,
            "errors": sorted(set(errs))[:40], "error_count": len(errs), "warnings": sorted(set(warns))[:40], "warning_count": len(warns)}
    if trace.exists():
        rows = []
        for line in trace.read_text().splitlines():
            try:
                r = json.loads(line)
            except Exception:
                continue
            if not r.get("meta"):
                rows.append(r)
        if rows:
            ys = [r["p"][1] for r in rows]
            states = {}
            for r in rows:
                states[r["s"]] = states.get(r["s"], 0) + 1
            summ["frames"] = len(rows)
            summ["min_y"] = round(min(ys), 2)
            summ["end_pos"] = rows[-1]["p"]
            summ["states"] = states
        trace.unlink()
    (OUT / f"{name}_{stamp}.summary.json").write_text(json.dumps(summ, indent=1))
    print(json.dumps({k: summ[k] for k in ("plan", "exit", "result", "truffles", "error_count", "warning_count")}), flush=True)
    return summ


if __name__ == "__main__":
    names = sys.argv[1:] or PLANS
    allres = [run(n) for n in names]
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    (OUT / f"_regress_{stamp}.json").write_text(json.dumps(allres, indent=1))

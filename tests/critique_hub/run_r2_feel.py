"""HUB critique round 2 (GAME FEEL, MOVEMENT AND CAMERA): runs FeelHubR2 (real MakPlayer, real input) in Hub.tscn.
Read-only. From the entity folder:
    python game/tests/critique_hub/run_r2_feel.py <label> <task,task,...> [extra godot args]
Output: Docs/progress/critique/hub/r2_feel/runs/<label>/ (cam.jsonl, results.json, godot.log, PNG shots).
"""
import os, subprocess, sys, time

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ENT, "Docs", "progress", "critique", "hub", "r2_feel", "runs")
PROBE = "res://tests/critique_hub/FeelHubR2.tscn"


def run(label, tasks, extra):
    d = os.path.join(OUT, label)
    os.makedirs(d, exist_ok=True)
    cmd = [sys.executable, os.path.join(ENT, "tools", "godot.py"), "run", PROBE, "--seconds", "900", "--",
           "--profile=crit-hub-feel2-%s-%d" % (label, int(time.time())), "--spawn=HUB-1", "--unlock-all",
           "--tasks=" + tasks, "--cam-out=" + os.path.join(d, "cam.jsonl").replace("\\", "/"),
           "--res-out=" + os.path.join(d, "results.json").replace("\\", "/"),
           "--shot-dir=" + d.replace("\\", "/")] + extra
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=ENT)
    log = (p.stdout or "") + (p.stderr or "")
    open(os.path.join(d, "godot.log"), "w", encoding="utf-8").write(log)
    print(label, "done in %.0f s, exit %s" % (time.time() - t0, p.returncode))
    for line in log.splitlines():
        if "[FeelHub]" in line or "SCRIPT ERROR" in line or "Parse Error" in line or "ERROR" in line[:12]:
            print(line[:500])


if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2], sys.argv[3:])

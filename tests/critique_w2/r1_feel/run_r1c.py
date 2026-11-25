"""W2 critique round 1 (feel lens), relaunch r1c: re-runs the r1 station replays on the current build with the
extended probe (floor body, platform velocity, bell, other cameras) and adds new cases. Output:
Docs/progress/critique/w2/r1_feel/runs_r1c/<case>/. Run from the entity folder:
    python game/tests/critique_w2/r1_feel/run_r1c.py [case ...]
Read-only: nothing in W2's files is changed.
"""
import json, os, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("CRIT_RUNS", "runs_r1c")
import run_r1_feel as R  # noqa: E402

PROBE = "res://tests/critique_w2/r1_feel/FeelW2ProbeR1c.tscn"
OUT = R.OUT
top, stick, yaw_to, PLAT = R.top, R.stick, R.yaw_to, R.PLAT


def spawn_idle():
    """No teleport: the real Default spawn, stick neutral for 25 s (integration blocker: hit at the spawn)."""
    ev = [{"f": f, "stick": [0, 0]} for f in range(2, 1500, 30)]
    return {"fps": 60, "steer": "world", "end_frame": 1500, "events": ev}


def bell_ride():
    """Placed on the crown plate at the east extreme (probe --ride-bell), stick neutral for 9 s (two full swings)."""
    ev = [{"f": 2, "teleport": top("T3"), "yaw_deg": 90}] + [{"f": f, "stick": [0, 0]} for f in range(3, 700, 30)]
    return {"fps": 60, "steer": "world", "end_frame": 700, "events": ev}


def bell_hop():
    """T3 -> run-hop west onto the bell (three tries at different phases), then a ham slam on landing."""
    s = top("T3")
    ev = []
    for i, f0 in enumerate([2, 302, 602, 902]):
        ev += [{"f": f0, "teleport": s, "yaw_deg": 90}, {"f": f0 + 1, "stick": [0, 0]},
               {"f": f0 + 30 + 30 * i, "stick": [-1, 0]}, {"f": f0 + 36 + 30 * i, "hold": "jump", "frames": 18}]
    return {"fps": 60, "steer": "world", "end_frame": 1200, "events": ev}


def bell_gallery():
    """Placed on the plate at the east extreme (probe), wait for the west extreme (~2 s later), then run west and
    double-jump toward BELL_GALLERY (gap 0.3, rise 2.2)."""
    ev = [{"f": 2, "teleport": top("T3"), "yaw_deg": 90}, {"f": 3, "stick": [0, 0]},
          {"on": "land", "nth": 1, "delay": 112, "stick": [-0.8, -0.35]},
          {"on": "land", "nth": 1, "delay": 118, "hold": "jump", "frames": 18},
          {"on": "land", "nth": 2, "delay": 1, "hold": "jump", "frames": 20}]
    return {"fps": 60, "steer": "world", "end_frame": 700, "events": ev}


def descent():
    """--w2-descent: the seed-parachute ride (other-camera clipping and occlusion are logged)."""
    return {"fps": 60, "steer": "world", "end_frame": 1080, "events": [{"f": f, "stick": [0, 0]} for f in range(2, 1080, 60)]}


def runner_bee():
    """U01 -> U02 (swaying) -> stand 3 s on U02 (E13 aggro zone) -> U03 -> stand 3 s -> U04."""
    pts = {k: PLAT[k]["pos"] for k in ("U01", "U02", "U03", "U04")}
    s = top("U01")
    ev = [{"f": 2, "teleport": s, "yaw_deg": yaw_to(s, pts["U02"])}, {"f": 3, "stick": [0, 0]},
          {"f": 40, "stick": stick(pts["U01"], pts["U02"])}, {"f": 44, "hold": "jump", "frames": 18},
          {"on": "land", "nth": 1, "delay": 0, "stick": [0, 0]},
          {"on": "land", "nth": 1, "delay": 180, "stick": stick(pts["U02"], pts["U03"])},
          {"on": "land", "nth": 1, "delay": 184, "hold": "jump", "frames": 18},
          {"on": "land", "nth": 2, "delay": 0, "stick": [0, 0]},
          {"on": "land", "nth": 2, "delay": 180, "stick": stick(pts["U03"], pts["U04"])},
          {"on": "land", "nth": 2, "delay": 184, "hold": "jump", "frames": 18},
          {"on": "land", "nth": 3, "delay": 2, "stick": [0, 0]}]
    return {"fps": 60, "steer": "world", "end_frame": 900, "events": ev}


def k1_backflip():
    """The plan's K1 shortcut: stand on L03's outer tip with the back to the trunk and backflip (crouch + jump)."""
    p = PLAT["L03"]["pos"]
    ax = [0.55, 0, -0.55]
    dx, dz = p[0] - ax[0], p[2] - ax[2]
    import math
    n = math.hypot(dx, dz)
    tip = [ax[0] + dx / n * 5.2, p[1] + 0.05, ax[2] + dz / n * 5.2]
    face_out = R.yaw_to(tip, [tip[0] + dx, 0, tip[2] + dz])
    return {"fps": 60, "steer": "world", "end_frame": 300, "events": [
        {"f": 2, "teleport": tip, "yaw_deg": face_out}, {"f": 3, "stick": [0, 0]},
        {"f": 40, "press": "crouch"}, {"f": 50, "hold": "jump", "frames": 20}, {"f": 75, "release": "crouch"}]}


CASES = dict(R.CASES)
for k in list(CASES):
    if k.endswith("_fixed"):
        del CASES[k]
CASES.update({"spawn_idle": spawn_idle, "bell_ride": bell_ride, "bell_hop": bell_hop, "bell_gallery": bell_gallery,
              "descent": descent, "runner_bee": runner_bee, "k1_backflip": k1_backflip})
EXTRA = {"bell_ride": ["--ride-bell=20"], "bell_gallery": ["--ride-bell=20"], "descent": ["--w2-descent"]}


def run_case(name):
    res = CASES[name]()
    shots, labels = [], []
    if isinstance(res, tuple):
        rep, shots, labels = res
    else:
        rep = res
        shots = list(range(60, rep["end_frame"], 60))
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    rp = os.path.join(d, "replay.json")
    cp = os.path.join(d, "cam.jsonl")
    xp = os.path.join(d, "extra.jsonl")
    json.dump(rep, open(rp, "w"), indent=1)
    for f in (cp, xp):
        if os.path.exists(f):
            os.remove(f)
    secs = rep["end_frame"] / 60.0 + 600
    cmd = [sys.executable, os.path.join(R.ENT, "tools", "godot.py"), "run", PROBE, "--seconds", str(int(secs)), "--",
           "--profile=crit-w2-feel-r1c-%s-%d" % (name, int(time.time())), "--replay=" + rp.replace("\\", "/"),
           "--cam-out=" + cp.replace("\\", "/"), "--extra-out=" + xp.replace("\\", "/"), "--shot-dir=" + d.replace("\\", "/"),
           "--label=" + name, "--shots=" + ",".join(str(s) for s in shots), "--quit-pf=%d" % rep["end_frame"],
           "--audit=" + os.path.join(d, "audit.json").replace("\\", "/")] + EXTRA.get(name, [])
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=R.ENT)
    open(os.path.join(d, "godot.log"), "w", encoding="utf-8").write((p.stdout or "") + (p.stderr or ""))
    if labels:
        json.dump(dict(zip([str(s) for s in shots], labels)), open(os.path.join(d, "shot_labels.json"), "w"), indent=1)
    print(name, "done in %.0f s, exit %s, rows %d" % (time.time() - t0, p.returncode,
          sum(1 for _ in open(cp)) if os.path.exists(cp) else 0), flush=True)


if __name__ == "__main__":
    for n in sys.argv[1:] or list(CASES):
        run_case(n)

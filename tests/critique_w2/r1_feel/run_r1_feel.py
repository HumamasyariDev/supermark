"""W2 critique round 1 (GAME FEEL, MOVEMENT AND CAMERA): station replays on the real controller in W2.

Each case writes a replay (game/tests/README.md format, world steering), runs FeelW2Probe through tools/godot.py
(one Godot process at a time), and writes the per-frame camera/feel log plus native shots to
Docs/progress/critique/w2/r1_feel/runs/<case>/. Run from the entity folder:
    python game/tests/critique_w2/r1_feel/run_r1_feel.py [case ...]
Read-only: nothing in W2's files is changed.
"""
import json, math, os, subprocess, sys, time

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
OUT = os.path.join(ENT, "Docs", "progress", "critique", "w2", "r1_feel", os.environ.get("CRIT_RUNS", "runs"))
LEVEL = json.load(open(os.path.join(ENT, "game", "assets", "environment", "w2", "w2_level.json"), encoding="utf-8"))
PLAT = {p["id"]: p for p in LEVEL["platforms"]}
PROBE = "res://tests/critique_w2/r1_feel/FeelW2Probe.tscn"


def top(pid, dy=0.05):
    p = PLAT[pid]["pos"]
    return [p[0], p[1] + dy, p[2]]


def yaw_to(a, b):
    """Godot yaw (deg) that faces from a toward b (yaw 0 faces -Z, yaw -90 faces +X)."""
    return round(math.degrees(math.atan2(-(b[0] - a[0]), -(b[2] - a[2]))), 1)


def stick(a, b, s=1.0):
    dx, dz = b[0] - a[0], b[2] - a[2]
    n = math.hypot(dx, dz) or 1.0
    return [round(s * dx / n, 3), round(-s * dz / n, 3)]


# ------------------------------------------------------------------ static views (gameplay camera after a teleport)
VIEWS = [
    ("spawn", [0, 0.05, 35], [0, 0, 0]),
    ("L03", top("L03"), PLAT["L04"]["pos"]),
    ("L05", top("L05"), PLAT["L06"]["pos"]),
    ("L08", top("L08"), PLAT["V1"]["pos"]),
    ("L09", top("L09"), PLAT["BL1"]["pos"]),
    ("sunleaf", top("L11"), PLAT["L12"]["pos"]),
    ("M05", top("M05"), PLAT["M06"]["pos"]),
    ("M08", top("M08"), PLAT["BL2"]["pos"]),
    ("UC_west", [-18.5, 44.05, -10.0], PLAT["LB1"]["pos"]),
    ("U01", top("U01"), PLAT["U02"]["pos"]),
    ("chair", [3.4, 54.45, -34.0], [-10, 55, -34]),
    ("table", [-2.8, 55.65, -34.0], [-10, 55, -34]),
    ("CP7", [-7.0, 50.05, -18.2], PLAT["V3"]["pos"]),
    ("T3", top("T3"), [-13.0, 63.5, -16.0]),
    ("gallery", top("BELL_GALLERY"), [-18, 68, -24]),
    ("wallwalk_S1", [11.0, 58.05, -25.0], [14, 61, -25.4]),
    ("courtyard", [12.5, 50.05, -27.5], [12.5, 50, -40]),
    ("shelfA", [-5.0, 52.05, -41.2], [0, 54, -41.2]),
    ("ISLET", top("ISLET"), PLAT["LB5"]["pos"]),
]


def static_views():
    ev, shots, f = [], [], 4
    for name, pos, look in VIEWS:
        ev.append({"f": f, "teleport": pos, "yaw_deg": yaw_to(pos, look)})
        ev.append({"f": f, "mark": name})
        shots.append(f + 80)
        f += 100
    return {"fps": 60, "steer": "world", "end_frame": f + 10, "events": ev}, shots, [v[0] for v in VIEWS]


def hop_chain(start, ids, delay=10, hold=18, first_delay=12, end_pad=240, yaw_target=None):
    """Teleport to `start`, then hop along `ids`: on each landing, steer at the next platform centre, wait `delay`
    frames and jump (held `hold` frames). The stick stays on the next target through the air, as a player would."""
    pts = [PLAT[i]["pos"] for i in ids]
    ev = [{"f": 2, "teleport": start, "yaw_deg": yaw_to(start, pts[0])},
          {"f": 3, "stick": stick(start, pts[0])},
          {"f": 3 + first_delay, "hold": "jump", "frames": hold}]
    for k in range(1, len(pts)):
        ev.append({"on": "land", "nth": k, "delay": 0, "stick": stick(pts[k - 1], pts[k])})
        ev.append({"on": "land", "nth": k, "delay": delay, "hold": "jump", "frames": hold})
    ev.append({"on": "land", "nth": len(pts), "delay": 2, "stick": [0, 0]})
    return {"fps": 60, "steer": "world", "end_frame": 60 * (2 + 2 * len(ids)) + end_pad, "events": ev}


def leaf_bouncer():
    """Run across the Upper Cloudbank and jump for LB1, then on every pad landing steer at the next pad's mean
    position (a first-time player's aim). Bounces are automatic."""
    start = [-15.5, 44.05, -9.0]
    lb = ["LB1", "LB2", "LB3", "LB4", "LB5", "ISLET"]
    pts = [PLAT[i]["pos"] for i in lb]
    ev = [{"f": 2, "teleport": start, "yaw_deg": yaw_to(start, pts[0])},
          {"f": 30, "stick": stick(start, pts[0])},
          {"f": 30 + 46, "hold": "jump", "frames": 20}]
    for k in range(1, len(pts)):
        ev.append({"on": "land", "nth": k, "delay": 0, "stick": stick(pts[k - 1], pts[k])})
    return {"fps": 60, "steer": "world", "end_frame": 900, "events": ev}


def leaf_bouncer_hold():
    """Control: bounce in place on LB1 with the stick neutral for 8 s (does the crosswind blow Mak off a pad?)."""
    p = PLAT["LB1"]["pos"]
    return {"fps": 60, "steer": "world", "end_frame": 600, "events": [
        {"f": 2, "teleport": [p[0], p[1] + 1.5, p[2]], "yaw_deg": -45}, {"f": 3, "stick": [0, 0]}]}


def kitchen_blast():
    """Stand idle in the open on the table (north of the watch, east of the teacup) for 11 s: two breath cycles."""
    return {"fps": 60, "steer": "world", "end_frame": 700, "events": [
        {"f": 2, "teleport": [-2.6, 55.65, -33.6], "yaw_deg": 90}, {"f": 3, "stick": [0, 0]}]}


def bell_vine():
    """CP7 rim -> jump onto V3 -> climb (stick up) to the top -> jump; camera log near the stalk tip and belfry."""
    s = [-7.4, 50.05, -17.4]
    return {"fps": 60, "steer": "world", "end_frame": 840, "events": [
        {"f": 2, "teleport": s, "yaw_deg": 180}, {"f": 30, "stick": [0, -0.6]}, {"f": 40, "hold": "jump", "frames": 14},
        {"on": "state:pole_climb", "nth": 1, "delay": 1, "stick": [0, 1]},
        {"on": "state:pole_climb", "nth": 1, "delay": 420, "stick": [-0.8, 0.4]},
        {"on": "state:pole_climb", "nth": 1, "delay": 440, "hold": "jump", "frames": 18},
    ]}


def bell_board():
    """T3 -> hop west toward the bell plate's rest position at three different times (three attempts)."""
    s = top("T3")
    ev = []
    for i, f0 in enumerate([2, 302, 602]):
        ev += [{"f": f0, "teleport": s, "yaw_deg": 90}, {"f": f0 + 1, "stick": [0, 0]},
               {"f": f0 + 40 + 37 * i, "stick": [-1, 0]}, {"f": f0 + 48 + 37 * i, "hold": "jump", "frames": 18}]
    return {"fps": 60, "steer": "world", "end_frame": 900, "events": ev}


def puff_chain():
    """PUFF04 -> 05 -> 06 -> PUFF07 with jump, double, triple through R3 (the chain window is the vanish window)."""
    s = top("PUFF04")
    a, b, c, d = (PLAT[i]["pos"] for i in ("PUFF04", "PUFF05", "PUFF06", "PUFF07"))
    return {"fps": 60, "steer": "world", "end_frame": 360, "events": [
        {"f": 2, "teleport": s, "yaw_deg": yaw_to(a, b)}, {"f": 3, "stick": stick(a, b)},
        {"f": 6, "hold": "jump", "frames": 20},
        {"on": "land", "nth": 1, "delay": 0, "stick": stick(b, c)}, {"on": "land", "nth": 1, "delay": 1, "hold": "jump", "frames": 20},
        {"on": "land", "nth": 2, "delay": 0, "stick": stick(c, d)}, {"on": "land", "nth": 2, "delay": 1, "hold": "jump", "frames": 20},
        {"on": "land", "nth": 3, "delay": 2, "stick": [0, 0]},
    ]}


CPS = [("CP0", [-3.6, 0.1, 32.2], 0), ("CP1", [5.44, 20.45, -6.22], 90), ("CP2", [-4, 24.05, -12], 90),
       ("CP2b", [1.68, 33.25, -3.76], -14), ("CP3", [13.0, 24.05, 0.5], -90), ("CP4", [-12.5, 44.05, -8.5], -90),
       ("CP5", [8, 50.05, -19.5], -53), ("CP6", [2.4, 54.45, -35.4], 90), ("CP7", [-6, 50.05, -19.5], 90)]
# r1b (11:05 Bangkok): positions and respawn yaws mirror w2_play.gd _checkpoints() after fix round 1.


def checkpoints():
    """Respawn view and safety: teleport to each checkpoint with its respawn facing and idle 6 s (hits are logged)."""
    ev, shots, f = [], [], 4
    for name, pos, yaw in CPS:
        ev += [{"f": f, "teleport": pos, "yaw_deg": yaw}, {"f": f + 1, "stick": [0, 0]}]
        shots.append(f + 45)
        f += 360
    return {"fps": 60, "steer": "world", "end_frame": f + 10, "events": ev}, shots, [c[0] for c in CPS]


def leaf_bouncer_v2():
    """Run 4 m to the Upper Cloudbank's west rim (about 6 m/s) and jump at the rim for LB1, steering at the next pad
    on every landing; then (from frame 700) a control: drop onto LB1 with the stick neutral and bounce in place."""
    lb = ["LB1", "LB2", "LB3", "LB4", "LB5", "ISLET"]
    pts = [PLAT[i]["pos"] for i in lb]
    start = [-15.06, 44.05, -9.17]
    ev = [{"f": 2, "teleport": start, "yaw_deg": yaw_to(start, pts[0])},
          {"f": 20, "stick": stick(start, pts[0])},
          {"f": 20 + 66, "hold": "jump", "frames": 20}]
    for k in range(1, len(pts)):
        ev.append({"on": "land", "nth": k, "delay": 0, "stick": stick(pts[k - 1], pts[k])})
    p1 = PLAT["LB1"]["pos"]
    ev.append({"f": 700, "teleport": [p1[0], p1[1] + 1.0, p1[2]], "yaw_deg": -45})
    for f in range(701, 1300, 20):
        ev.append({"f": f, "stick": [0, 0]})
    return {"fps": 60, "steer": "world", "end_frame": 1300, "events": ev}


CASES = {
    "leaf_bouncer_v2_fixed": leaf_bouncer_v2,
    "leaf_bouncer_v2": leaf_bouncer_v2,
    "static_views": static_views,
    "checkpoints": checkpoints,
    "lower_spiral": lambda: hop_chain([3.2, 0.05, 7.4], ["L01", "L02", "L03", "L04", "L05", "L06", "L07", "L08"]),
    "middle_stalk": lambda: hop_chain(top("M04"), ["M05", "M06", "M07", "M08", "BL2", "UC"], delay=8),
    "upper_runner": lambda: hop_chain(top("U01"), ["U02", "U03", "U04", "BANK"], delay=8),
    "leaf_bouncer": leaf_bouncer,
    "leaf_bouncer_hold": leaf_bouncer_hold,
    "kitchen_blast": kitchen_blast,
    "bell_vine": bell_vine,
    "bell_board": bell_board,
    "puff_chain": puff_chain,
    # Test-only runtime patch of the origin bug (see feel_w2_probe.gd _patch_origin_bodies): the intended design.
    "leaf_bouncer_fixed": leaf_bouncer,
    "leaf_bouncer_hold_fixed": leaf_bouncer_hold,
    "droop_fixed": lambda: hop_chain(top("L05"), ["L06", "L07", "L08"], delay=10),
}
CASE_ARGS = {k: ["--fix-origin=1"] for k in CASES if k.endswith("_fixed")}


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
    json.dump(rep, open(rp, "w"), indent=1)
    if os.path.exists(cp):
        os.remove(cp)
    secs = rep["end_frame"] / 60.0 + 900
    cmd = [sys.executable, os.path.join(ENT, "tools", "godot.py"), "run", PROBE, "--seconds", str(int(secs)), "--",
           "--profile=crit-w2-feel-%s-%d" % (name, int(time.time())), "--replay=" + rp.replace("\\", "/"),
           "--cam-out=" + cp.replace("\\", "/"), "--shot-dir=" + d.replace("\\", "/"), "--label=" + name,
           "--shots=" + ",".join(str(s) for s in shots), "--quit-pf=%d" % rep["end_frame"],
           "--audit=" + os.path.join(d, "audit.json").replace("\\", "/")] + CASE_ARGS.get(name, [])
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=ENT)
    log = (p.stdout or "") + (p.stderr or "")
    open(os.path.join(d, "godot.log"), "w", encoding="utf-8").write(log)
    if labels:
        json.dump(dict(zip([str(s) for s in shots], labels)), open(os.path.join(d, "shot_labels.json"), "w"), indent=1)
    print(name, "done in %.0f s, exit %s" % (time.time() - t0, p.returncode), flush=True)


if __name__ == "__main__":
    for n in sys.argv[1:] or list(CASES):
        run_case(n)

"""W2 builder tool: scripted-input route tests for Beanstalk Skyway.

Each case writes a replay (game/tests/README.md format, world steering) to the scratch folder, runs W2 through
tools/godot.py with --replay/--trace, then reports the highest point, the last grounded position, the states
seen and any truffle collected. Run from the entity folder:
    python game/assets/environment/w2/tools/w2_route_tests.py [case ...]
"""
import json, math, os, subprocess, sys, time

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".."))
OUT = os.environ.get("W2_TEST_DIR", os.path.join(ENT, "Docs", "progress", "w2", "route_tests"))
LEVEL = json.load(open(os.path.join(ENT, "game", "assets", "environment", "w2", "w2_level.json"), encoding="utf-8"))
PLAT = {p["id"]: p for p in LEVEL["platforms"]}


SPEED = [1.0]


def stick_to(a, b):
    dx, dz = b[0] - a[0], b[2] - a[2]
    n = (math.hypot(dx, dz) or 1.0) / SPEED[0]
    return [round(dx / n, 3), round(-dz / n, 3)]


def hop_chain(start, ids, jump_frames=16, first_jump=10, end_frame=900, kind="land", speed=1.0):
    """Teleport just above `start` (that landing is land #1), run at the first platform and jump on each
    landing toward the next one."""
    SPEED[0] = speed
    pts = [PLAT[i]["pos"] for i in ids]
    s0 = [start[0], start[1] + 0.3, start[2]]
    ev = [{"f": 2, "teleport": s0, "yaw_deg": 0},
          {"on": kind, "nth": 1, "delay": 1, "stick": stick_to(start, pts[0])},
          {"on": kind, "nth": 1, "delay": first_jump, "hold": "jump", "frames": jump_frames}]
    for k in range(1, len(pts)):
        ev.append({"on": kind, "nth": k + 1, "delay": 0, "stick": stick_to(pts[k - 1], pts[k])})
        # Wait past the 0.2 s chain window so every hop is a plain single jump (and gets a short run-up).
        ev.append({"on": kind, "nth": k + 1, "delay": 14, "hold": "jump", "frames": jump_frames})
    ev.append({"on": kind, "nth": len(pts) + 1, "delay": 0, "stick": [0, 0]})
    return {"fps": 60, "steer": "world", "end_frame": end_frame, "events": ev}


def k1_backflip():
    """Round 1 shortcut: stand on L03's outer tip, back to the trunk, backflip onto the Knot Shelf K1."""
    return {"fps": 60, "steer": "world", "end_frame": 360, "events": [
        {"f": 2, "teleport": [5.31, 3.5, -1.53], "yaw_deg": -76},
        {"f": 50, "hold": "crouch", "frames": 30},
        {"f": 58, "hold": "jump", "frames": 18},
    ]}


CASES = {
    "k1_backflip": k1_backflip,
    # Garden -> L01..L08 (main route, single jumps only).
    "leaf_spiral": lambda: hop_chain([3.2, 0.05, 7.4], ["L01", "L02", "L03", "L04", "L05", "L06", "L07", "L08"]),
    # Sunleaf -> L12 -> L13 -> Cloud Landing.
    "sunleaf_to_landing": lambda: hop_chain([5.44, 20.45, -6.22], ["L12", "L13", "C1"], first_jump=6),
    # Cloud Landing -> M01..M03 (middle stalk entry).
    "landing_to_m03": lambda: hop_chain([-3.0, 24.05, -9.0], ["M01", "M02", "M03"], first_jump=4),
    # M04 -> M05 -> M06 -> M07 (pod) -> M08 -> BL2 (bounce) toward UC.
    "middle_leaves": lambda: hop_chain([1.68, 33.25, -3.76], ["M05", "M06", "M07", "M08", "BL2"], first_jump=3),
    # Upper Cloudbank -> U01..U04 -> castle bank.
    "upper_runner": lambda: hop_chain([-9.0, 44.05, -6.5], ["U01", "U02", "U03", "U04", "BANK"], first_jump=8),
    # Pantry steps to the Giant's chair and table (W2-3 approach).
    # Lower spiral from leaf centres (the straight-line bot aims centre to centre).
    "spiral_a": lambda: hop_chain([1.59, 1.05, 4.05], ["L02", "L03", "L04", "L05"], first_jump=4),
    "spiral_b": lambda: hop_chain([-0.16, 5.45, -4.81], ["L06", "L07", "L08"], first_jump=4),
    # M08 -> Bouncy Leaf 2 -> Upper Cloudbank (main route).
    "bl2_to_uc": lambda: hop_chain([-4.9, 38.05, -13.18], ["BL2", "UC"], first_jump=4),
    # Chair (moved 0.6 m toward the table in the build) -> table top.
    "chair_to_table": lambda: hop_chain([3.4, 54.45, -34.0], ["TABLE"], first_jump=4),
    "pantry_to_table": lambda: hop_chain([-2.6, 50.05, -28.4], ["SACK", "CRATE", "BOOKS", "CHAIR", "TABLE"], first_jump=6),
}


def run_case(name):
    os.makedirs(OUT, exist_ok=True)
    rep = CASES[name]()
    rp = os.path.join(OUT, name + ".replay.json")
    tp = os.path.join(OUT, name + ".trace.jsonl")
    json.dump(rep, open(rp, "w"), indent=1)
    if os.path.exists(tp):
        os.remove(tp)
    secs = rep["end_frame"] / 60.0 + 12
    cmd = [sys.executable, os.path.join(ENT, "tools", "godot.py"), "run", "res://scenes/worlds/w2/W2.tscn", "--seconds", str(int(secs)), "--",
           "--profile=w2route_%s_%d" % (name, int(time.time())), "--replay=" + rp.replace("\\", "/"), "--trace=" + tp.replace("\\", "/"), "--replay-hold"]
    log = subprocess.run(cmd, capture_output=True, text=True, cwd=ENT).stdout
    rows = []
    if os.path.exists(tp):
        for line in open(tp):
            try:
                r = json.loads(line)
            except Exception:
                continue
            if not r.get("meta"):
                rows.append(r)
    lands = []
    prev_g = True
    for r in rows:
        if r.get("g") and not prev_g:
            lands.append([round(c, 2) for c in r["p"]])
        prev_g = r.get("g")
    top = max((r["p"][1] for r in rows), default=None)
    last = rows[-1]["p"] if rows else None
    states = sorted({r.get("s") for r in rows})
    truffles = [l for l in log.splitlines() if "TRUFFLE COLLECTED" in l]
    errors = [l for l in log.splitlines() if "SCRIPT ERROR" in l]
    res = {"case": name, "frames": len(rows), "max_y": top, "last": last, "landings": lands, "states": states, "truffles": truffles, "errors": errors[:5]}
    json.dump(res, open(os.path.join(OUT, name + ".result.json"), "w"), indent=1)
    return res


if __name__ == "__main__":
    names = sys.argv[1:] or list(CASES)
    for n in names:
        r = run_case(n)
        print(json.dumps({k: r[k] for k in ("case", "frames", "max_y", "last", "landings", "truffles", "errors")}))

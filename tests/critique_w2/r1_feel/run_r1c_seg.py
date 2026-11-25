"""W2 critique r1 (feel lens) relaunch r1c: chains many station replays into ONE Godot run (FeelW2ProbeSeg), because
the machine's two shared run slots queue every separate run for 10-25 minutes. Each segment's timed events are
shifted to its start frame; its reactive ("on") events go to a sidecar file that the probe installs per segment.
    python game/tests/critique_w2/r1_feel/run_r1c_seg.py <batch-name> case [case ...]
Output: Docs/progress/critique/w2/r1_feel/runs_r1c/<batch-name>/ (cam.jsonl, extra.jsonl, segments.json, PNGs).
"""
import json, os, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("CRIT_RUNS", "runs_r1c")
import run_r1c as C  # noqa: E402

PROBE = "res://tests/critique_w2/r1_feel/FeelW2ProbeSeg.tscn"
NEW_PUFF07 = [-35.38, 32.5, -5.76]  # w2_fix2.gd patch_data moves PUFF07


def puff_chain_r1c():
    rep = C.CASES["puff_chain"]()
    a, b, c = (C.PLAT[i]["pos"] for i in ("PUFF04", "PUFF05", "PUFF06"))
    for e in rep["events"]:
        if e.get("on") == "land" and e.get("nth") == 2 and "stick" in e:
            e["stick"] = C.stick(c, NEW_PUFF07)
    return rep


def descent_seg():
    return {"fps": 60, "steer": "world", "end_frame": 900, "events": [{"f": 2, "stick": [0, 0]}]}


def hop_slow(start, ids):
    """A deliberate player: on each landing steer at the next leaf, wait 18 frames (0.3 s, past the 0.25 s chain
    window, so every hop is a single jump) and jump (held 18 frames)."""
    return C.R.hop_chain(start, ids, delay=18, hold=18, first_delay=20)


def bell_gallery2():
    """Placed on the plate at the east extreme (probe notifies 'ridebell'); ride to the west extreme (~2.0 s), then
    hold the stick at BELL_GALLERY (north-west) and jump; jump again on any landing (ledge grab or top)."""
    st = [-14.27, 0, -16.0]
    g = [-15.2, 0, -17.95]
    return {"fps": 60, "steer": "world", "end_frame": 600, "events": [
        {"f": 2, "teleport": C.top("T3"), "yaw_deg": 90}, {"f": 3, "stick": [0, 0]},
        {"on": "ridebell", "nth": 1, "delay": 105, "stick": C.stick(st, g, 0.6)},
        {"on": "ridebell", "nth": 1, "delay": 112, "hold": "jump", "frames": 20},
        {"on": "state:ledge_hang", "nth": 1, "delay": 22, "tap": "jump"}]}


def bell_slam():
    """Placed on the plate at the east extreme; jump and ham-slam on the moving plate (BONG check)."""
    return {"fps": 60, "steer": "world", "end_frame": 420, "events": [
        {"f": 2, "teleport": C.top("T3"), "yaw_deg": 90}, {"f": 3, "stick": [0, 0]},
        {"on": "ridebell", "nth": 1, "delay": 20, "hold": "jump", "frames": 12},
        {"on": "ridebell", "nth": 1, "delay": 36, "tap": "crouch"}]}


def leaf_tap():
    """Leaf Bouncer, a player who aims and lets go: run off the UC rim for LB1; on each pad landing push the stick at
    the next pad for 8 frames, then release (the aim assist decides the arc)."""
    lb = ["LB1", "LB2", "LB3", "LB4", "LB5", "ISLET"]
    pts = [C.PLAT[i]["pos"] for i in lb]
    start = [-15.06, 44.05, -9.17]
    ev = [{"f": 2, "teleport": start, "yaw_deg": C.yaw_to(start, pts[0])},
          {"f": 20, "stick": C.stick(start, pts[0])}, {"f": 86, "hold": "jump", "frames": 20},
          {"f": 120, "stick": [0, 0]}]
    for k in range(1, len(pts)):
        ev.append({"on": "land", "nth": k, "delay": 0, "stick": C.stick(pts[k - 1], pts[k])})
        ev.append({"on": "land", "nth": k, "delay": 8, "stick": [0, 0]})
    return {"fps": 60, "steer": "world", "end_frame": 700, "events": ev}


def runner_runup():
    """U01 -> U02 with a run-up from U01's back edge (a fair start), then stand on U02 for 3 s (E13 aggro)."""
    u1, u2 = C.PLAT["U01"]["pos"], C.PLAT["U02"]["pos"]
    import math
    dx, dz = u2[0] - u1[0], u2[2] - u1[2]
    n = math.hypot(dx, dz)
    s = [u1[0] - dx / n * 1.3, u1[1] + 0.05, u1[2] - dz / n * 1.3]
    return {"fps": 60, "steer": "world", "end_frame": 600, "events": [
        {"f": 2, "teleport": s, "yaw_deg": C.yaw_to(s, u2)}, {"f": 3, "stick": [0, 0]},
        {"f": 30, "stick": C.stick(s, u2)}, {"f": 50, "hold": "jump", "frames": 18},
        {"on": "land", "nth": 1, "delay": 0, "stick": [0, 0]}]}


def leaf_preaim(release=True):
    """Leaf Bouncer as a careful human plays it: during each arc (40 frames after a pad landing) the stick is
    already pointed at the pad AFTER the one Mak is about to land on, so the stick is right on the landing frame
    (the aim assist and the re-aim read it then); optionally released 6 frames after each landing."""
    lb = ["LB1", "LB2", "LB3", "LB4", "LB5", "ISLET"]
    pts = [C.PLAT[i]["pos"] for i in lb]
    start = [-15.06, 44.05, -9.17]
    ev = [{"f": 2, "teleport": start, "yaw_deg": C.yaw_to(start, pts[0])},
          {"f": 20, "stick": C.stick(start, pts[0])}, {"f": 86, "hold": "jump", "frames": 20},
          {"f": 120, "stick": C.stick(pts[0], pts[1])}]
    for k in range(1, len(pts) - 1):
        if release:
            ev.append({"on": "land", "nth": k, "delay": 6, "stick": [0, 0]})
        ev.append({"on": "land", "nth": k, "delay": 40, "stick": C.stick(pts[k], pts[k + 1])})
    return {"fps": 60, "steer": "world", "end_frame": 720, "events": ev}


def bell_gallery3():
    """From the plate at the west extreme: walk north to the plate edge under BELL_GALLERY (full stick), jump at the
    wall (held), and jump again from a ledge hang."""
    return {"fps": 60, "steer": "world", "end_frame": 600, "events": [
        {"f": 2, "teleport": C.top("T3"), "yaw_deg": 90}, {"f": 3, "stick": [0, 0]},
        {"on": "ridebell", "nth": 1, "delay": 100, "stick": [-0.35, 1.0]},
        {"on": "ridebell", "nth": 1, "delay": 118, "hold": "jump", "frames": 20},
        {"on": "state:ledge_hang", "nth": 1, "delay": 22, "tap": "jump"}]}


EXTRA_CASES = {"leaf_preaim": leaf_preaim, "leaf_preaim_hold": lambda: leaf_preaim(False), "bell_gallery3": bell_gallery3, "puff_chain_r1c": puff_chain_r1c, "descent_seg": descent_seg, "bell_gallery2": bell_gallery2,
               "bell_slam": bell_slam, "leaf_tap": leaf_tap, "runner_runup": runner_runup,
               "lower_slow": lambda: hop_slow([3.2, 0.05, 7.4], ["L01", "L02", "L03", "L04", "L05", "L06", "L07", "L08"]),
               "middle_slow": lambda: hop_slow(C.top("M04"), ["M05", "M06", "M07", "M08", "BL2", "UC"])}


def main():
    name, cases = sys.argv[1], sys.argv[2:]
    d = os.path.join(C.OUT, name)
    os.makedirs(d, exist_ok=True)
    events, segs, shots, f0 = [], [], [], 0
    for cn in cases:
        res = (EXTRA_CASES.get(cn) or C.CASES[cn])()
        rep = res[0] if isinstance(res, tuple) else res
        seg = {"label": cn, "start": f0, "end": f0 + rep["end_frame"], "reactive": [],
               "ride_bell": cn in ("bell_ride", "bell_gallery", "bell_gallery2", "bell_gallery3", "bell_slam"), "descent": cn == "descent_seg"}
        events.append({"f": f0 + 1, "stick": [0, 0]})
        events.append({"f": f0 + 1, "mark": cn})
        for e in rep["events"]:
            e = dict(e)
            if "on" in e:
                seg["reactive"].append(e)
            else:
                e["f"] = f0 + int(e["f"])
                events.append(e)
        segs.append(seg)
        shots += list(range(f0 + 60, f0 + rep["end_frame"], 150))
        f0 += rep["end_frame"] + 20
    events.sort(key=lambda e: e["f"])
    rep = {"fps": 60, "steer": "world", "end_frame": f0, "events": events}
    rp, sp = os.path.join(d, "replay.json"), os.path.join(d, "segments.json")
    cp, xp = os.path.join(d, "cam.jsonl"), os.path.join(d, "extra.jsonl")
    json.dump(rep, open(rp, "w"), indent=0)
    json.dump(segs, open(sp, "w"), indent=1)
    for f in (cp, xp):
        if os.path.exists(f):
            os.remove(f)
    fw = lambda p: p.replace("\\", "/")
    cmd = [sys.executable, os.path.join(C.R.ENT, "tools", "godot.py"), "run", PROBE, "--seconds", str(int(f0 / 60 + 900)), "--",
           "--profile=crit-w2-feel-r1c-%s-%d" % (name, int(time.time())), "--replay=" + fw(rp), "--segments=" + fw(sp),
           "--cam-out=" + fw(cp), "--extra-out=" + fw(xp), "--shot-dir=" + fw(d), "--label=" + name,
           "--shots=" + ",".join(str(s) for s in shots), "--quit-pf=%d" % f0, "--audit=" + fw(os.path.join(d, "audit.json"))]
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=C.R.ENT)
    open(os.path.join(d, "godot.log"), "w", encoding="utf-8").write((p.stdout or "") + (p.stderr or ""))
    print(name, "done in %.0f s, exit %s, rows %d, frames %d" % (time.time() - t0, p.returncode,
          sum(1 for _ in open(cp)) if os.path.exists(cp) else 0, f0), flush=True)


if __name__ == "__main__":
    main()

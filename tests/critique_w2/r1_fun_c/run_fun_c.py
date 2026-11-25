"""W2 critique round 1 pass C (FUN lens, 2026-10-18 evening, post fix2 build). Copy of ../run_fun_r1.py with new cases.
W2 critique round 1 (FUN AND GAME DESIGN lens): scripted-input play sessions on the real player.

Each case writes a replay (game/tests/README.md format, world steering), runs W2 through tools/godot.py
(Movie Maker at normal speed, 60 fps, plus a per-frame trace), converts the AVI to MP4, deletes the AVI and
writes a contact sheet. Outputs go to Docs/progress/critique/w2/r1_fun/. Run from the entity folder:

    python game/tests/critique_w2/run_fun_r1.py <case> [case ...]

These are offline deterministic captures (Movie Maker), not real-time play.
"""
import json, math, os, subprocess, sys, time

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
OUT = os.path.join(ENT, "Docs", "progress", "critique", "w2", "r1_fun", "c")
SCENE = "res://scenes/worlds/w2/W2.tscn"


def toward(a, b, mag=1.0):
    dx, dz = b[0] - a[0], b[2] - a[2]
    n = math.hypot(dx, dz) or 1.0
    return [round(dx / n * mag, 3), round(-dz / n * mag, 3)]


def slam_at(f, pos, yaw=0):
    """Teleport just above pos, then jump and Ham Slam onto it."""
    return [{"f": f, "teleport": [pos[0], pos[1] + 0.3, pos[2]], "yaw_deg": yaw},
            {"f": f + 40, "hold": "jump", "frames": 8},
            {"f": f + 58, "tap": "crouch"}]


def case_intro():
    # No replay: the world-entry crane intro must play on a fresh save, then the gameplay camera at Default.
    return None, 720, []


def case_giant():
    # On the Giant's table in the loaf's blast lee (H3), watch two breath cycles, then walk west at the head
    # with no timing at all (what a first-time player does).
    ev = [{"f": 2, "teleport": [-3.6, 55.9, -33.0], "yaw_deg": 90},
          {"f": 420, "stick": [-1, 0]},
          {"f": 720, "stick": [0, 0]},
          {"f": 900, "stick": [-1, 0.15]},
          {"f": 1100, "stick": [0, 0]}]
    return {"fps": 60, "steer": "world", "end_frame": 1300, "events": ev}, 1300, []


def case_goose():
    ev = []
    ev += slam_at(2, (14.0, 61.4, -25.4))          # S1 gatehouse roof
    ev += slam_at(150, (-4.0, 56.0, -41.2))        # S2 dresser shelf C
    ev += slam_at(300, (22.0, 62.0, -44.0))        # S3 NE turret top
    ev += [{"f": 420, "teleport": [13.0, 50.4, -26.5], "yaw_deg": 0}]
    # Fight like a player who has read the hint: face the wolf's start and attack whenever it is close.
    for k in range(16):
        f = 600 + k * 50
        ev.append({"f": f, "stick": [0, 1] if k % 4 < 2 else [0, -1]})
        ev.append({"f": f + 20, "stick": [0, 0]})
        ev.append({"f": f + 25, "tap": "attack"})
    return {"fps": 60, "steer": "world", "end_frame": 1500, "events": ev}, 1500, []


def case_caw():
    # Near TAUNT so Caw flies to PERCH1 over LB2; bounce in place on LB2 and jump-kick near the apex.
    ev = [{"f": 2, "teleport": [-19.2, 44.35, -10.2], "yaw_deg": 125},
          {"f": 120, "teleport": [-29.5, 44.7, -16.5], "yaw_deg": 135}]
    for k, d in enumerate([30, 33, 36, 27]):
        ev.append({"on": "state:bounce", "nth": k + 1, "delay": d, "tap": "attack"})
    ev += [{"f": 560, "teleport": [-38.0, 45.7, -26.0], "yaw_deg": 135}]
    for k, d in enumerate([30, 33, 36, 27]):
        ev.append({"on": "state:bounce", "nth": k + 5, "delay": d, "tap": "attack"})
    ev += [{"f": 1000, "teleport": [-40.8, 46.4, -38.2], "yaw_deg": 135},
           {"f": 1040, "hold": "jump", "frames": 8},
           {"f": 1058, "tap": "crouch"}]
    for k in range(6):
        ev.append({"f": 1110 + k * 20, "tap": "attack"})
    return {"fps": 60, "steer": "world", "end_frame": 1400, "events": ev}, 1400, []


def case_pods():
    a = (14.5, 24.05, -3.0)
    ev = [{"f": 2, "teleport": [a[0], 24.35, a[2]], "yaw_deg": -90},
          {"f": 30, "stick": toward(a, (18.6, 0, -7.9))},
          {"f": 75, "stick": [0, 0]},
          {"f": 80, "hold": "jump", "frames": 8},
          {"f": 98, "tap": "crouch"},
          {"f": 150, "tap": "attack"},
          {"f": 175, "tap": "attack"},
          {"f": 200, "stick": toward((18.6, 0, -7.9), (19.0, 0, -12.8))},
          {"f": 235, "stick": [0, 0]},
          {"f": 240, "hold": "jump", "frames": 8},
          {"f": 258, "tap": "crouch"},
          {"f": 300, "stick": [1, 0]},
          {"f": 330, "hold": "crouch", "frames": 30},
          {"f": 332, "tap": "attack"},
          {"f": 420, "stick": toward((22, 0, -13), (21.2, 0, 1.5))},
          {"f": 560, "stick": [0, 0]},
          {"f": 565, "tap": "attack"},
          {"f": 600, "tap": "attack"}]
    return {"fps": 60, "steer": "world", "end_frame": 900, "events": ev}, 900, []


def case_bell():
    # Teleport onto the bell's crown plate near its east extreme (t = 5 s), then Ham Slam it.
    ev = [{"f": 2, "teleport": [-7.4, 51.0, -18.0], "yaw_deg": -90},
          {"f": 292, "teleport": [-11.73, 64.3, -16.0], "yaw_deg": -90},
          {"f": 330, "hold": "jump", "frames": 6},
          {"f": 346, "tap": "crouch"},
          {"f": 700, "stick": [-1, 0]},
          {"f": 760, "stick": [0, 0]}]
    return {"fps": 60, "steer": "world", "end_frame": 900, "events": ev}, 900, []


def case_bell2():
    # Best case: drop onto the plate at the swing's east extreme and Ham Slam on the way down (no jump off it).
    ev = [{"f": 2, "teleport": [-7.4, 51.0, -18.0], "yaw_deg": -90},
          {"f": 292, "teleport": [-11.73, 65.3, -16.0], "yaw_deg": -90},
          {"f": 298, "tap": "crouch"}]
    return {"fps": 60, "steer": "world", "end_frame": 780, "events": ev}, 780, []


def case_descent():
    return None, 960, ["--w2-descent"]


def case_bee():
    m05 = (2.54, 34.45, -7.22)
    ev = [{"f": 2, "teleport": [m05[0] - 0.4, 34.75, m05[2]], "yaw_deg": -90},
          {"f": 300, "hold": "jump", "frames": 8},
          {"f": 300, "stick": [0, 0.6]},
          {"f": 330, "stick": [0, 0]},
          {"f": 480, "hold": "jump", "frames": 8},
          {"f": 480, "stick": [0, -0.6]},
          {"f": 510, "stick": [0, 0]}]
    return {"fps": 60, "steer": "world", "end_frame": 900, "events": ev}, 900, []


def case_hopper():
    # Start the Cloud Hopper and bounce PUFF01 -> PUFF02 -> PUFF03 steering at the next puff in the air.
    hs = (-14.6, 24.4, -11.4)
    p = {1: (-18.1, 25.2, -10.9), 2: (-19.5, 27.8, -14.6), 3: (-21.6, 30.4, -17.8), 4: (-25.0, 31.5, -19.6)}
    ev = [{"f": 2, "teleport": [-12.6, 24.35, -11.6], "yaw_deg": 90},
          {"f": 30, "stick": toward((-12.6, 0, -11.6), hs)},
          {"f": 50, "stick": toward(hs, p[1], 0.8)},
          {"f": 62, "hold": "jump", "frames": 14}]
    for k in (1, 2, 3):
        ev.append({"on": "state:bounce", "nth": k, "delay": 0, "stick": toward(p[k], p[k + 1], 0.55)})
    ev.append({"on": "land", "nth": 3, "delay": 0, "stick": [0, 0]})
    return {"fps": 60, "steer": "world", "end_frame": 600, "events": ev}, 600, []


def case_spawnwalk():
    # Default spawn: walk the dirt path to the stalk as a new player would (no intro: replay mode).
    ev = [{"f": 10, "stick": [0, 1]},
          {"f": 200, "stick": [0.15, 1]},
          {"f": 420, "stick": [0, 0]}]
    return {"fps": 60, "steer": "world", "end_frame": 600, "events": ev}, 600, []


def case_l05gap():
    # Stand on L05 (the last leaf a first-time player can see) and look along the spiral for L06.
    ev = [{"f": 2, "teleport": [-0.16, 5.7, -4.81], "yaw_deg": 120},
          {"f": 60, "stick": [-0.5, 0.15]},
          {"f": 66, "stick": [0, 0]},
          {"f": 120, "hold": "jump", "frames": 14},
          {"f": 120, "stick": toward((-0.16, 0, -4.81), (-2.83, 0, -3.37))},
          {"f": 170, "stick": [0, 0]}]
    return {"fps": 60, "steer": "world", "end_frame": 420, "events": ev}, 420, []


def case_k1route():
    # The only way past the missing droopy leaves: L04 running double jump onto the Knot Shelf, then Vine 1.
    a, k = (2.82, 0, -4.01), (3.46, 0, -1.61)
    ev = [{"f": 2, "teleport": [3.0, 4.6, -4.6], "yaw_deg": 180},
          {"f": 30, "stick": toward((3.0, 0, -4.6), k)},
          {"f": 44, "hold": "jump", "frames": 12},
          {"on": "land", "nth": 2, "delay": 1, "hold": "jump", "frames": 14},
          {"f": 120, "stick": [0, 0]}]
    return {"fps": 60, "steer": "world", "end_frame": 360, "events": ev}, 360, []


def case_goosechase():
    # Real-input chase driver (r1_fun_b) under Movie Maker: reveal, then a steering bot dives at the goose-wolf.
    return None, 1700, ["--w2-nointro"], "res://tests/critique_w2/r1_fun_b/FunW2b.tscn"


def case_podstrike():
    # Human attempt at SPARE/STRIKE in lane R1 (z -13.5; three pods after fix2): slam 1 m west of PM01,
    # then run east along the lane and dive into a belly slide inside the 2.5 s stun.
    ev = [{"f": 2, "teleport": [15.4, 24.6, -13.5], "yaw_deg": -90},
          {"f": 40, "hold": "jump", "frames": 8},
          {"f": 58, "tap": "crouch"},
          {"f": 110, "stick": [1, 0]},
          {"f": 150, "tap": "attack"},
          {"f": 260, "stick": [0, 0]},
          {"f": 420, "teleport": [15.4, 24.6, 1.5], "yaw_deg": -90},
          {"f": 460, "hold": "jump", "frames": 8},
          {"f": 478, "tap": "crouch"},
          {"f": 530, "stick": [1, 0]},
          {"f": 570, "tap": "attack"},
          {"f": 680, "stick": [0, 0]}]
    return {"fps": 60, "steer": "world", "end_frame": 960, "events": ev}, 960, ["--w2-nointro"]


def case_intro2():
    return None, 840, []


def case_sneeze():
    # First-timer on the table: walk straight at the Giant's nose during the breath cycle (expect the sneeze cannon).
    ev = [{"f": 2, "teleport": [-5.0, 55.9, -34.0], "yaw_deg": 90},
          {"f": 60, "stick": [-1, 0]},
          {"f": 600, "stick": [0, 0]}]
    return {"fps": 60, "steer": "world", "end_frame": 900, "events": ev}, 900, ["--w2-nointro"]


CASES = {k[5:]: v for k, v in globals().items() if k.startswith("case_")}


def ts():
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())


def run(name, size="960x540"):
    os.makedirs(OUT, exist_ok=True)
    rv = CASES[name]()
    rep, frames, extra = rv[0], rv[1], rv[2]
    scene = rv[3] if len(rv) > 3 else SCENE
    stamp = ts()
    base = os.path.join(OUT, "%s__%s" % (stamp, name))
    args = ["--profile=critw2funC_%s_%d" % (name, int(time.time()))]
    trace = None
    if rep is not None:
        rp = base + ".replay.json"
        json.dump(rep, open(rp, "w"), indent=1)
        trace = base + ".trace.jsonl"
        args += ["--replay=" + rp.replace("\\", "/"), "--trace=" + trace.replace("\\", "/"), "--replay-hold"]
    args += extra
    avi = base + ".avi"
    cmd = [sys.executable, os.path.join(ENT, "tools", "godot.py"), "movie", scene, avi, "--frames", str(frames + 60),
           "--size", size, "--no-import", "--"] + args
    if NOMOVIE:
        # Trace-only run (no AVI): used when C: is short of space.
        cmd = [sys.executable, os.path.join(ENT, "tools", "godot.py"), "run", scene, "--seconds", str(int(frames / 60 + 15)),
               "--no-import", "--"] + args
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=ENT)
    open(base + ".log", "w", encoding="utf-8").write(proc.stdout + proc.stderr)
    mp4 = base + ".mp4"
    if os.path.exists(avi):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", avi, "-c:v", "libx264", "-crf", "26", "-preset", "veryfast",
                        "-pix_fmt", "yuv420p", "-an", mp4])
        os.remove(avi)
        # Contact sheet: one frame every 0.5 s, 6 columns.
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp4, "-vf", "fps=2,scale=480:-1,tile=6x%d" % max(1, math.ceil(frames / 60.0 * 2 / 6)),
                        "-frames:v", "1", base + "__sheet.png"])
    res = {"case": name, "mp4": mp4 if os.path.exists(mp4) else None, "log": base + ".log"}
    if trace and os.path.exists(trace):
        rows = [json.loads(l) for l in open(trace) if l.strip()]
        rows = [r for r in rows if not r.get("meta")]
        seq, prev = [], None
        for r in rows:
            key = (r.get("s"), r.get("g"))
            if key != prev:
                seq.append([r["f"], r.get("s"), int(bool(r.get("g"))), [round(c, 2) for c in r["p"]]])
                prev = key
        res["states"] = seq
        json.dump(res, open(base + ".result.json", "w"), indent=1)
    errs = [l for l in (proc.stdout + proc.stderr).splitlines() if "SCRIPT ERROR" in l or "ERROR:" in l]
    res["errors"] = errs[:8]
    return res


NOMOVIE = "--nomovie" in sys.argv

if __name__ == "__main__":
    for n in [a for a in sys.argv[1:] if not a.startswith("--")]:
        r = run(n)
        print(json.dumps({"case": n, "mp4": r.get("mp4"), "n_states": len(r.get("states", [])), "errors": r["errors"][:4]}))

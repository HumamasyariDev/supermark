"""W3 critique round 1 (FUN AND GAME DESIGN lens): watch-the-mission play sessions on the real player.

Two kinds of case:
  * bot cases reuse the builder's closed-loop truffle bots (`--w3-bot=<plan>`, defined in w3_level.gd) so the
    critic can WATCH each mission being played at normal speed through the gameplay camera;
  * naive cases are plain replay events (stick / tap / hold, world steering), written the way a first-time
    player would act, to see what the level does to someone who has not read the design.

Each case runs W3 through tools/godot.py movie (Movie Maker, 60 fps, offline deterministic capture), converts the
AVI to MP4 at once (the AVI is deleted), writes a 1 fps contact sheet and a per-frame trace summary.
Outputs: Docs/progress/critique/w3/r1_fun/. Run from the entity folder:

    python game/tests/critique_w3/run_fun_r1.py <case> [case ...]
"""
import json, math, os, subprocess, sys, time

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ENT, "Docs", "progress", "critique", "w3", "r1_fun")
SCENE = "res://scenes/worlds/w3/W3.tscn"


def bot(plan, frames):
    return lambda: ({"fps": 60, "steer": "world", "end_frame": frames, "events": []}, frames, ["--w3-bot=" + plan])


CRIT_SCENE = "res://tests/critique_w3/CritW3.tscn"


def crit(plan, frames):
    return lambda: ({"fps": 60, "steer": "world", "end_frame": frames, "events": []}, frames, ["--crit-plan=" + plan], CRIT_SCENE)


def case_intro_walk():
    # First entry: forced intro cameo, then a first-time player holds north through the gate to the bridge and
    # mashes attack when the bridge grenadiers are near.
    ev = [{"f": 360, "stick": [0, 1]}]
    for k in range(14):
        ev.append({"f": 880 + k * 25, "tap": "attack"})
    ev.append({"f": 1250, "stick": [0, 0]})
    return {"fps": 60, "steer": "world", "end_frame": 1400, "events": ev}, 1400, ["--w3-intro"]


def case_fort_idle():
    # Walk into the fort yard and simply stand there for 12 s: does the squad threaten a passive player?
    ev = [{"f": 2, "teleport": [33.0, 2.1, 43.0], "yaw_deg": -90}, {"f": 40, "stick": [1, 0]}, {"f": 140, "stick": [0, 0]}]
    return {"fps": 60, "steer": "world", "end_frame": 900, "events": ev}, 900, []


def case_fort_punch():
    # A player who ignores the drum and the banner and just punches the squad from the front.
    ev = [{"f": 2, "teleport": [39.5, 2.1, 43.0], "yaw_deg": -90}, {"f": 30, "stick": [1, 0]}, {"f": 70, "stick": [0, 0]}]
    for k in range(30):
        f = 90 + k * 30
        ev.append({"f": f, "stick": [1, 0.2 if k % 2 else -0.2]})
        ev.append({"f": f + 10, "stick": [0, 0]})
        ev.append({"f": f + 12, "tap": "attack"})
    return {"fps": 60, "steer": "world", "end_frame": 1100, "events": ev}, 1100, []


CASES = {
    "intro_walk": case_intro_walk,
    "fort_idle": case_fort_idle,
    "fort_punch": case_fort_punch,
    "w31": bot("w31", 1000),
    "w32": bot("w32", 1250),
    "w33": bot("w33", 1350),
    "w34": bot("w34", 560),
    "w34clean": bot("w34clean", 700),
    "w35lj": bot("w35lj", 700),
    "w35p3": bot("w35p3", 450),
    "w36": bot("w36", 1250),
    "w37": bot("w37", 800),
    "w38": bot("w38", 1350),
    "climb": crit("climb", 1500),
    "candles": crit("candles", 700),
    "maze_walk": crit("maze_walk", 1300),
    # pass r1c (20:55 Bangkok resume): the fix-round features
    "w32phases": bot("w32phases", 4200),
    "w31nest": bot("w31nest", 3300),
    "w34clean": bot("w34clean", 900),
    "maze_naive": crit("maze_naive", 2400),
    "nest_naive": crit("nest_naive", 1800),
    "fort_naive": crit("fort_naive", 2400),
    "nest_bot": crit("nest_bot", 3000),
}


def ts():
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())


def run(name, size="960x540"):
    os.makedirs(OUT, exist_ok=True)
    spec = CASES[name]()
    rep, frames, extra = spec[0], spec[1], spec[2]
    scene = spec[3] if len(spec) > 3 else SCENE
    stamp = ts()
    base = os.path.join(OUT, "%s__%s" % (stamp, name))
    args = ["--profile=critw3fun_%s_%d" % (name, int(time.time()))]
    trace = None
    if rep is not None:
        rp = base + ".replay.json"
        json.dump(rep, open(rp, "w"), indent=1)
        trace = base + ".trace.jsonl"
        args += ["--replay=" + rp.replace("\\", "/"), "--trace=" + trace.replace("\\", "/")]
    args += extra
    avi = base + ".avi"
    cmd = [sys.executable, os.path.join(ENT, "tools", "godot.py"), "movie", scene, avi, "--frames", str(frames + 30),
           "--size", size, "--no-import", "--"] + args
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=ENT)
    open(base + ".log", "w", encoding="utf-8").write(proc.stdout + proc.stderr)
    mp4 = base + ".mp4"
    if os.path.exists(avi):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", avi, "-c:v", "libx264", "-crf", "27", "-preset", "veryfast",
                        "-pix_fmt", "yuv420p", "-an", mp4])
        os.remove(avi)
        rows = max(1, math.ceil(frames / 60.0 / 6))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp4, "-vf", "fps=1,scale=320:-1,tile=6x%d" % rows,
                        "-frames:v", "1", base + "__sheet.png"])
    res = {"case": name, "mp4": mp4 if os.path.exists(mp4) else None, "log": base + ".log"}
    if trace and os.path.exists(trace):
        rows = []
        for l in open(trace):
            try:
                r = json.loads(l)
            except Exception:
                continue
            if not r.get("meta"):
                rows.append(r)
        seq, prev = [], None
        for r in rows:
            key = (r.get("s"), r.get("g"))
            if key != prev:
                seq.append([r["f"], r.get("s"), int(bool(r.get("g"))), [round(c, 2) for c in r["p"]]])
                prev = key
        res["states"] = seq
    out = proc.stdout + proc.stderr
    res["events"] = [l for l in out.splitlines() if ("[W3" in l or "[Game]" in l or "[CRIT]" in l or "damage" in l.lower()) and "breadcrumbs=" not in l][:400]
    res["errors"] = [l for l in out.splitlines() if "SCRIPT ERROR" in l or "ERROR:" in l][:12]
    json.dump(res, open(base + ".result.json", "w"), indent=1)
    if os.path.exists(base + ".trace.jsonl"):
        os.remove(base + ".trace.jsonl")
    return res


if __name__ == "__main__":
    for n in sys.argv[1:]:
        t0 = time.time()
        r = run(n)
        print(json.dumps({"case": n, "secs": round(time.time() - t0), "mp4": r.get("mp4"), "n_events": len(r["events"]), "errors": r["errors"][:4]}), flush=True)

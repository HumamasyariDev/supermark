"""W1 critique round 1 (FUN AND GAME DESIGN lens): play sessions on the real player.

Two kinds of case:
  * driver cases (walk, siege, hay, probe) run FunQA.tscn headful through tools/godot.py run and write a JSON result;
  * clip cases record a Movie Maker clip at normal speed (60 fps, offline deterministic capture) of a set piece driven
    by the builder's real-input bot (--w1bot=<test>), the forced intro (--w1-intro), the punchline (--w1-punchline),
    or this folder's driver. Each AVI is converted to MP4 at once and deleted; a contact sheet is written.

Outputs: Docs/progress/critique/w1/r1_fun/. Run from the entity folder:
    python game/tests/critique_w1/run_fun_r1.py <case> [case ...]
"""
import json, math, os, subprocess, sys, time

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ENT, "Docs", "progress", "critique", "w1", "r1_fun")
W1 = "res://scenes/worlds/w1/W1.tscn"
QA = "res://tests/critique_w1/FunQA.tscn"

# name: (scene, frames, extra args, size)
CLIPS = {
    "intro": (W1, 540, ["--w1-intro"], "960x540"),
    "siege_bot": (W1, 900, ["--w1bot=w1-1"], "960x540"),
    "windmill": (W1, 1800, ["--w1bot=w1-2"], "960x540"),
    "scaffold": (W1, 1500, ["--w1bot=w1-3"], "960x540"),
    "chimney": (W1, 1500, ["--w1bot=w1-6"], "960x540"),
    "bellows": (W1, 2400, ["--w1bot=w1-4"], "960x540"),
    "pages": (W1, 3000, ["--w1bot=w1-5"], "960x540"),
    "treasure": (W1, 1500, ["--w1bot=w1-8"], "960x540"),
    "punchline": (W1, 660, ["--w1-punchline", "--spawn=W1-7"], "960x540"),
    "hay_clip": (QA, 5400, ["--w1fun=hay", "--spawn=W1-7"], "640x360"),
    "siege_clip": (QA, 3600, ["--w1fun=siege", "--spawn=W1-1"], "640x360"),
    "walk_clip": (QA, 3600, ["--w1fun=walk", "--spawn=Default"], "640x360"),
    "puff_clip": (QA, 1500, ["--w1fun=puff", "--spawn=W1-1"], "960x540"),
}
DRIVER = {
    "walk": (["--spawn=Default"], 600),
    "siege": (["--spawn=W1-1"], 420),
    "hay": (["--spawn=W1-7"], 420),
    "probe": ([], 120),
}


def ts():
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())


def godot(args, log):
    proc = subprocess.run([sys.executable, os.path.join(ENT, "tools", "godot.py")] + args, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", cwd=ENT)
    open(log, "w", encoding="utf-8").write(proc.stdout + proc.stderr)
    errs = [l for l in (proc.stdout + proc.stderr).splitlines() if "SCRIPT ERROR" in l or "ERROR:" in l]
    return proc, errs


def run_clip(name):
    scene, frames, extra, size = CLIPS[name]
    stamp = ts()
    base = os.path.join(OUT, "%s__%s" % (stamp, name))
    args = ["--profile=critw1fun_%s_%d" % (name, int(time.time()))] + extra
    if scene == QA:
        args.append("--w1fun-out=" + (base + ".json").replace("\\", "/"))
    if any(a.startswith("--w1bot") for a in extra):
        args.append("--w1bot-out=" + (base + ".bot.json").replace("\\", "/"))
    avi = base + ".avi"
    proc, errs = godot(["movie", scene, avi, "--frames", str(frames), "--size", size, "--no-import", "--"] + args, base + ".log")
    mp4 = base + ".mp4"
    if os.path.exists(avi):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", avi, "-c:v", "libx264", "-crf", "27", "-preset", "veryfast",
                        "-pix_fmt", "yuv420p", "-an", mp4])
        os.remove(avi)
        rows = max(1, math.ceil(frames / 60.0 / 6))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp4, "-vf", "fps=1,scale=480:-1,tile=6x%d" % rows,
                        "-frames:v", "1", base + "__sheet.png"])
    return {"case": name, "mp4": mp4 if os.path.exists(mp4) else None, "errors": errs[:6]}


def run_driver(name):
    extra, secs = DRIVER[name]
    stamp = ts()
    base = os.path.join(OUT, "%s__drv_%s" % (stamp, name))
    args = ["--profile=critw1fun_%s_%d" % (name, int(time.time())), "--w1fun=" + name,
            "--w1fun-out=" + (base + ".json").replace("\\", "/")] + extra
    proc, errs = godot(["run", QA, "--seconds", str(secs), "--no-import", "--"] + args, base + ".log")
    res = None
    if os.path.exists(base + ".json"):
        res = json.load(open(base + ".json"))
    return {"case": name, "json": base + ".json" if res else None, "result": res.get("result") if res else None, "errors": errs[:6]}


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for n in sys.argv[1:]:
        r = run_clip(n) if n in CLIPS else run_driver(n)
        print(json.dumps(r)[:3000], flush=True)

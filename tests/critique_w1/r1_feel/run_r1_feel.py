"""W1 critique round 1 (GAME FEEL, MOVEMENT AND CAMERA): probes on the real controller in W1.

Run from the entity folder (one Godot process at a time, through tools/godot.py):
    python game/tests/critique_w1/r1_feel/run_r1_feel.py feel      # own scenarios: views + orbit sweeps, gusts, hops
    python game/tests/critique_w1/r1_feel/run_r1_feel.py bot       # builder's bot routes (w1-3,w1-2,w1-6,w1-5,chute) watched
    python game/tests/critique_w1/r1_feel/run_r1_feel.py analyse <run_dir>
Outputs: Docs/progress/critique/w1/r1_feel/runs/<case>/ (cam.jsonl, results.json, shots/). Read-only for W1.
"""
import json, math, os, subprocess, sys, time

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
OUT = os.environ.get("FEEL_OUT") or os.path.join(ENT, "Docs", "progress", "critique", "w1", "r1_feel", "runs")
PROBE = "res://tests/critique_w1/r1_feel/FeelW1Probe.tscn"
_GP = os.path.join(OUT, "dump", "geometry.json")
if not os.path.exists(_GP):
    _GP = os.path.join(ENT, "Docs", "progress", "critique", "w1", "r1_feel", "runs", "dump", "geometry.json")
GEO = json.load(open(_GP, encoding="utf-8"))
PL = GEO["plat"]


def top(pid, dy=0.05):
    p = PL[pid]["top"]
    return [p[0], p[1] + dy, p[2]]


def yaw_to(a, b):
    return round(math.degrees(math.atan2(-(b[0] - a[0]), -(b[2] - a[2]))), 1)


def bridge(t):
    x = -43 + (35.5 - 1.0) * t  # -43 -> -8.5
    y = 16.0 + (12.3 - 16.0) * t - 1.2 * math.sin(math.pi * t)
    return [round(x, 3), round(y + 0.1, 3), -31.5]


def view(name, pos, look, orbit=True, shots=True):
    return {"kind": "view", "name": name, "pos": pos, "yaw": yaw_to(pos, look), "orbit": orbit, "orbit_shots": shots}


def hop(name, frm, to, run=0.0, **kw):
    """Stand `run` m behind the take-off edge of `frm` toward `to`; take off 0.25 m inside the edge."""
    a, b = top(frm) if isinstance(frm, str) else frm, top(to, 0.0) if isinstance(to, str) else to
    dx, dz = b[0] - a[0], b[2] - a[2]
    n = math.hypot(dx, dz)
    ux, uz = dx / n, dz / n
    half = 0.0
    if isinstance(frm, str):
        sx, _, sz = PL[frm]["size"]
        half = min(sx, sz) / 2 - 0.25
    take = [a[0] + ux * half, a[1], a[2] + uz * half]
    start = [take[0] - ux * run, a[1], take[2] - uz * run] if run > 0 else [a[0] - ux * 0.0, a[1], a[2]]
    d = {"kind": "hop", "name": name, "pos": start, "yaw": yaw_to(start, b), "takeoff": take, "target": b}
    d.update(kw)
    return d


def stand(name, pos, seconds=8.0, stick=(0, 0), jump_every=0, shot=True):
    return {"kind": "stand", "name": name, "pos": pos, "seconds": seconds, "stick": list(stick), "jump_every": jump_every, "shot": shot}


def scenarios_r2():
    """Second pass (the first feel run was killed by the disk watchdog at chimney_ledge)."""
    allv = scenarios()
    names = [x["name"] for x in allv]
    rest = allv[names.index("chimney_ledge"):]
    for x in rest:
        if x["kind"] == "view":
            x["orbit_shots"] = x["name"] in ("mill_stage", "hollow_log", "kick_cleft", "hayyard", "vane_deck")
    kicks = [{"kind": "kicks", "name": "chimney_kicks_hold14", "pos": [12.3, 12.1, -36.0], "yaw": 90.0, "hold": 14, "seconds": 14, "top_y": 26.0},
             {"kind": "kicks", "name": "cleft_kicks_hold14", "pos": [-54.0, 1.5, -7.75], "yaw": 90.0, "hold": 14, "seconds": 10, "top_y": 10.5, "mid_x": -54.0}]
    return rest + kicks


def scenarios():
    S = []
    # --- gameplay camera views with 360-degree orbit sweeps
    S += [
        view("spawn", [0, 0.5, 46.5], [0, 0, 0]),
        view("ford_stone2", top("ford_stone_2"), PL["ford_rock"]["top"]),
        view("sc3", top("scaffold_sc3"), PL["scaffold_sc4"]["top"]),
        view("sc6", top("scaffold_sc6"), PL["scaffold_sc7"]["top"]),
        view("sc9", top("scaffold_sc9"), PL["treehouse_deck"]["top"]),
        view("treehouse_deck", [-44.5, 16.05, -29.0], [-30, 14, -31.5]),
        view("crows_nest", top("crows_nest_top"), [-30, 14, -31.5]),
        view("rope_gap", bridge(0.42), bridge(0.6)),
        view("woodshed_roof", top("brick_woodshed_roof"), PL["brick_plank_shelf"]["top"]),
        view("window_box", top("brick_window_box"), PL["brick_dormer_plank"]["top"]),
        view("roof_walk", top("brick_roof_walk"), [11.3, 21, -36]),
        view("chimney_floor", [11.3, 12.1, -36.0], [9.8, 14, -36.0]),
        view("chimney_ledge", top("chimney_soot_ledge"), [9.8, 20, -35.5]),
        view("b3_apron", [10.0, 12.1, -28.0], [16, 12, -27]),
        view("chute_rim", [9.0, 12.1, -22.5], [4.4, 0.5, -6.6]),
        view("mill_stage", [40, 17.05, -38.4], [40, 18, -45]),
        view("vane_deck", [40.6, 28.15, -45.4], [40, 28, -40]),
        view("tor_rock3", top("tor_rock_3"), PL["tor_rock_4"]["top"]),
        view("stone_finger", top("stone_finger_top"), [34, 7, 3]),
        view("hollow_log", [-15.5, 0.75, 1.5], [-20, 0.4, 1.5]),
        view("kick_cleft", [-54.0, 1.5, -7.75], [-54, 8, -7.75]),
        view("hayyard", [-43.0, 1.2, -43.5], [-43, 1, -48.5]),
        view("bale_tier2", top("straw_bale_tier_2"), [-20, 6, 26]),
        view("page_gate_top", top("page_gate_top"), [0, 0, 40]),
        view("book_step3", top("book_step_3"), PL["book_step_4"]["top"]),
    ]
    # --- gusts: stand still, and hop in place, inside each bellows lane
    S += [
        stand("gust_B1_idle", [-16.0, 0.6, 26.0], 8.0),
        stand("gust_B1_hops", [-16.0, 0.6, 26.0], 8.0, jump_every=50),
        stand("gust_B2_idle", [-34.0, 4.1, -16.0], 8.0),
        stand("gust_B2_hops", [-34.0, 4.1, -16.0], 8.0, jump_every=50),
        stand("gust_B3_idle", [9.0, 12.1, -28.0], 12.0),
        stand("gust_B3_hops", [9.0, 12.1, -28.0], 12.0, jump_every=50),
        stand("gust_B3_cross_run", [8.0, 12.1, -33.5], 3.0, stick=(0, -1)),
        stand("gust_B1_bale_tier", top("straw_bale_tier_1"), 8.0),
    ]
    # --- hops measured on the controller (standing take-off near the edge; run=0)
    S += [
        hop("rope_gap_jump", bridge(0.40), bridge(0.535), run=0.0, takeoff=bridge(0.445)),
        hop("sc4_to_sc5", "scaffold_sc4", "scaffold_sc5"),
        hop("sc6_to_sc7", "scaffold_sc6", "scaffold_sc7"),
        hop("sc9_to_deck", "scaffold_sc9", [-42.9, 16.0, -27.0]),
        hop("tor4_to_tor5", "tor_rock_4", "tor_rock_5"),
        hop("tor4_to_tor5_run1", "tor_rock_4", "tor_rock_5", run=1.4),
        hop("woodshed_to_shelf", "brick_woodshed_roof", "brick_plank_shelf"),
        hop("shelf_to_balcony", "brick_plank_shelf", "brick_balcony"),
        hop("balcony_to_windowbox", "brick_balcony", "brick_window_box"),
        hop("windowbox_to_dormer", "brick_window_box", "brick_dormer_plank"),
        hop("dormer_to_roofwalk", "brick_dormer_plank", "brick_roof_walk"),
        hop("haycart_to_tier1", "straw_haycart", "straw_bale_tier_1"),
        hop("tier1_to_tier2", "straw_bale_tier_1", "straw_bale_tier_2"),
        hop("book3_to_book4", "book_step_3", "book_step_4"),
        hop("book4_to_book5", "book_step_4", "book_step_5"),
        hop("ford_s2_to_rock", "ford_stone_2", "ford_rock"),
    ]
    return S


def run(case, args, seconds):
    d = os.path.join(OUT, case)
    os.makedirs(os.path.join(d, "shots"), exist_ok=True)
    cmd = [sys.executable, os.path.join(ENT, "tools", "godot.py"), "run", PROBE, "--seconds", str(seconds), "--no-import", "--",
           f"--profile=crit-w1-feel-{case}-{int(time.time())}", f"--cam-out={d}/cam.jsonl".replace("\\", "/"),
           f"--shot-dir={d}/shots".replace("\\", "/"), f"--label={case}"] + args
    t0 = time.time()
    p = subprocess.run(cmd, cwd=ENT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    open(os.path.join(d, "godot.log"), "w", encoding="utf-8").write(p.stdout + "\n" + p.stderr)
    print(case, "exit", p.returncode, "%.0fs" % (time.time() - t0))
    for line in (p.stdout + p.stderr).splitlines():
        if "[W1 bot]" in line or "SCRIPT ERROR" in line or "[FeelW1]" in line[:10]:
            print("  ", line[:300])


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "feel"
    if what == "feel":
        d = os.path.join(OUT, "feel")
        os.makedirs(d, exist_ok=True)
        f = os.path.join(d, "scenarios.json")
        json.dump(scenarios(), open(f, "w"), indent=1)
        run("feel", [f"--feel={f}".replace("\\", "/"), f"--res-out={d}/results.json".replace("\\", "/"), "--max-auto=10"], 900)
    elif what == "feel2":
        d = os.path.join(OUT, "feel2")
        os.makedirs(d, exist_ok=True)
        f = os.path.join(d, "scenarios.json")
        json.dump(scenarios_r2(), open(f, "w"), indent=1)
        run("feel2", [f"--feel={f}".replace("\\", "/"), f"--res-out={d}/results.json".replace("\\", "/"), "--max-auto=8"], 900)
    elif what == "bot":
        tests = sys.argv[2] if len(sys.argv) > 2 else "w1-3,w1-2,w1-6,w1-5,chute"
        run("bot", [f"--w1bot={tests}", f"--w1bot-out={OUT}/bot/bot.json".replace("\\", "/"), "--ctx-shots", "--max-auto=30"], 900)


if __name__ == "__main__":
    main()

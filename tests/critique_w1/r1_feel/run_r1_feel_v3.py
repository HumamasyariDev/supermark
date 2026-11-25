"""W1 critique round 1, GAME FEEL lens, third pass (20:55 Bangkok, after W1 fix round 2): one combined run on the
current build, because the machine only gives 2 Godot slots. Reuses FeelW1Probe.tscn (read-only for W1).

    python game/tests/critique_w1/r1_feel/run_r1_feel_v3.py all      # views + kicks + gusts + hops in one process
    python game/tests/critique_w1/r1_feel/run_r1_feel_v3.py bot      # builder's bot routes, watched by the probe
Outputs: Docs/progress/critique/w1/r1_feel/runs_2100/<case>/.
"""
import json, math, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ENT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
OUT = os.path.join(ENT, "Docs", "progress", "critique", "w1", "r1_feel", "runs_2100")
os.environ["FEEL_OUT"] = OUT
import run_r1_feel as R  # noqa: E402  (loads runs_2100/dump/geometry.json through FEEL_OUT)

PL = R.PL
top, view, hop, stand, bridge = R.top, R.view, R.hop, R.stand, R.bridge


def has(pid):
    return pid in PL


def scenarios():
    S = []
    V = [
        ("spawn", [0, 0.5, 46.5], [0, 0, 0]),
        ("sc3", top("scaffold_sc3"), PL["scaffold_pole"]["top"]) if has("scaffold_pole") else None,
        ("pole_top", [PL["scaffold_pole"]["top"][0] + 0.3, 9.6, PL["scaffold_pole"]["top"][2] + 0.3], PL["scaffold_sc7"]["top"]) if has("scaffold_pole") else None,
        ("sc7", top("scaffold_sc7"), PL["scaffold_sc8"]["top"]) if has("scaffold_sc7") else None,
        ("sc9", top("scaffold_sc9"), PL["treehouse_deck"]["top"]) if has("scaffold_sc9") else None,
        ("treehouse_deck", [-44.5, 16.05, -29.0], [-30, 14, -31.5]),
        ("hut_roof_p3", [-47.5, 19.4, -28.6], [-47.5, 22.6, -31.5]),
        ("crows_nest", top("crows_nest_top"), [-30, 14, -31.5]),
        ("rope_gap", bridge(0.42), bridge(0.6)),
        ("woodshed_roof", top("brick_woodshed_roof"), PL["brick_plank_shelf"]["top"]) if has("brick_plank_shelf") else None,
        ("window_box", top("brick_window_box"), PL["brick_dormer_plank"]["top"]) if has("brick_window_box") else None,
        ("roof_walk", top("brick_roof_walk"), [11.3, 21, -36]) if has("brick_roof_walk") else None,
        ("chimney_floor", [11.3, 12.1, -36.0], [9.8, 14, -36.0]),
        ("chimney_ledge", top("chimney_soot_ledge"), [9.8, 20, -35.5]),
        ("soot_door_outside", [14.6, 12.1, -36.0], [11.3, 12.5, -36.0]),
        ("b3_apron", [10.0, 12.1, -28.0], [16, 12, -27]),
        ("chute_rim", [9.0, 12.1, -22.5], [4.4, 0.5, -6.6]),
        ("mill_stage", [40, 17.05, -38.4], [40, 18, -45]),
        ("vane_deck", [40.6, 28.15, -45.4], [40, 28, -40]),
        ("tor_rock3", top("tor_rock_3"), PL["tor_rock_4"]["top"]),
        ("tor_top_east_rim", [38.4, 7.1, 3.0], [50.75, 6.0, 3.0]),
        ("stone_finger", top("stone_finger_top"), [34, 7, 3]),
        ("hollow_log", [-15.5, 0.75, 1.5], [-20, 0.4, 1.5]),
        ("kick_cleft", [-54.0, 1.5, -7.75], [-54, 8, -7.75]),
        ("cleft_top_p4", [-51.4, 7.1, -7.75], [-54, 0, -12]),
        ("hayyard", [-43.0, 1.2, -43.5], [-43, 1, -48.5]),
        ("bale_tier2", top("straw_bale_tier_2"), [-20, 6, 26]) if has("straw_bale_tier_2") else None,
        ("scarecrow_boater", top("scarecrow_boater"), [-4, 0.5, 21]) if has("scarecrow_boater") else None,
        ("page_gate_top", top("page_gate_top"), [0, 0, 40]),
        ("gravel_bar", top("gravel_bar"), PL["ford_rock"]["top"]) if has("gravel_bar") else None,
    ]
    shots = {"pole_top", "hut_roof_p3", "crows_nest", "kick_cleft", "hollow_log", "chimney_floor", "chimney_ledge", "mill_stage",
             "vane_deck", "rope_gap", "roof_walk", "hayyard", "soot_door_outside", "cleft_top_p4"}
    for v in V:
        if v is None:
            continue
        S.append(view(v[0], v[1], v[2], orbit=True, shots=v[0] in shots))
    S += [
        {"kind": "kicks", "name": "chimney_kicks_hold14", "pos": [12.3, 12.1, -36.0], "yaw": 90.0, "hold": 14, "seconds": 14, "top_y": 26.0},
        {"kind": "kicks", "name": "chimney_kicks_tap4", "pos": [12.3, 12.1, -36.0], "yaw": 90.0, "hold": 4, "seconds": 20, "top_y": 26.0},
        {"kind": "kicks", "name": "cleft_kicks_hold14", "pos": [-54.0, 1.5, -7.75], "yaw": 90.0, "hold": 14, "seconds": 10, "top_y": 7.2, "mid_x": -54.0},
    ]
    S += [
        stand("gust_B1_idle", [-16.0, 0.6, 26.0], 8.0),
        stand("gust_B1_hops", [-16.0, 0.6, 26.0], 8.0, jump_every=50),
        stand("gust_B2_idle", [-34.0, 4.1, -16.0], 8.0),
        stand("gust_B3_idle", [9.0, 12.1, -28.0], 12.0),
        stand("gust_B3_hops", [9.0, 12.1, -28.0], 12.0, jump_every=50),
        stand("gust_B1_bale_tier", top("straw_bale_tier_1"), 8.0) if has("straw_bale_tier_1") else None,
        stand("stream_idle", [-6.0, -0.4, 9.6], 6.0),
    ]
    S = [x for x in S if x is not None]
    H = [
        hop("rope_gap_jump", bridge(0.40), bridge(0.535), run=0.0, takeoff=bridge(0.445)),
        hop("sc9_to_deck", "scaffold_sc9", [-42.9, 16.0, -27.0]) if has("scaffold_sc9") else None,
        hop("sc1_to_sc2", "scaffold_sc1", "scaffold_sc2") if has("scaffold_sc2") else None,
        hop("sc2_to_sc3", "scaffold_sc2", "scaffold_sc3") if has("scaffold_sc3") else None,
        hop("sc7_to_sc8", "scaffold_sc7", "scaffold_sc8") if has("scaffold_sc8") else None,
        hop("tor4_to_tor5", "tor_rock_4", "tor_rock_5"),
        hop("woodshed_to_shelf", "brick_woodshed_roof", "brick_plank_shelf") if has("brick_plank_shelf") else None,
        hop("windowbox_to_dormer", "brick_window_box", "brick_dormer_plank") if has("brick_window_box") else None,
        hop("haycart_to_tier1", "straw_haycart", "straw_bale_tier_1") if has("straw_bale_tier_1") else None,
        hop("tier1_to_tier2", "straw_bale_tier_1", "straw_bale_tier_2") if has("straw_bale_tier_2") else None,
        hop("book3_to_book4", "book_step_3", "book_step_4"),
        hop("ford_s2_to_rock", "ford_stone_2", "ford_rock"),
        hop("rock_to_gravel", "ford_rock", "gravel_bar") if has("gravel_bar") else None,
        hop("hayyard_stack_single", [-43.0, 0.35, -55.0], "HS1", run=3.0) if has("HS1") else None,
    ]
    S += [x for x in H if x is not None]
    return S


def scenarios_extra():
    S = [
        {"kind": "kicks", "name": "chimney_kicks_tap8", "pos": [12.3, 12.1, -36.0], "yaw": 90.0, "hold": 8, "seconds": 20, "top_y": 26.0},
        {"kind": "kicks", "name": "chimney_kicks_tap6", "pos": [12.3, 12.1, -36.0], "yaw": 90.0, "hold": 6, "seconds": 20, "top_y": 26.0},
        {"kind": "kicks", "name": "cleft_kicks_tap8", "pos": [-54.0, 1.5, -7.75], "yaw": 90.0, "hold": 8, "seconds": 12, "top_y": 7.2, "mid_x": -54.0},
    ]
    for a, b in [("scaffold_sc1", "scaffold_sc2"), ("scaffold_sc2", "scaffold_sc3"), ("scaffold_sc7", "scaffold_sc8"), ("scaffold_sc8", "scaffold_sc9")]:
        if has(a) and has(b):
            S.append(hop(a[-3:] + "_to_" + b[-3:] + "_release", a, b, release=True, release_after=8))
            S.append(hop(a[-3:] + "_to_" + b[-3:] + "_run1", a, b, run=1.2, release=True, release_after=8))
    for rs in (1.5, 1.75, 1.95):
        S.append({"kind": "longjump", "name": "p2_longjump_run%.2f" % rs, "pos": [29.6, 7.2, 3.0], "yaw": -90.0, "target": [50.75, 6.0, 3.0], "run_s": rs})
    S += [
        hop("b2_plate_from_yard_run4", [-34.2, 4.05, -16.0], "bellows_B2_plate", takeoff=[-30.0, 4.05, -16.0]),
        hop("b2_plate_from_behind_run3", [-21.6, 4.05, -16.0], "bellows_B2_plate", takeoff=[-24.8, 4.05, -16.0]),
        hop("b3_plate_from_behind_run3", [20.4, 12.05, -22.6], "bellows_B3_plate", takeoff=[18.3, 12.05, -24.6]),
        hop("hs1_from_centre_walk", [-43.0, 0.4, -48.0], "HS1", takeoff=[-43.0, 0.4, -50.4]),
        hop("b1_crate_to_plate", "bellows_B1_crate", "bellows_B1_plate"),
    ]
    return S


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    if what == "all":
        d = os.path.join(OUT, "all")
        os.makedirs(d, exist_ok=True)
        f = os.path.join(d, "scenarios.json")
        json.dump(scenarios(), open(f, "w"), indent=1)
        R.run("all", [f"--feel={f}".replace("\\", "/"), f"--res-out={d}/results.json".replace("\\", "/"), "--max-auto=10"], 1500)
    elif what == "extra":
        d = os.path.join(OUT, "extra")
        os.makedirs(d, exist_ok=True)
        f = os.path.join(d, "scenarios.json")
        json.dump(scenarios_extra(), open(f, "w"), indent=1)
        R.run("extra", [f"--feel={f}".replace("\\", "/"), f"--res-out={d}/results.json".replace("\\", "/"), "--max-auto=6"], 900)
    elif what == "bot":
        tests = sys.argv[2] if len(sys.argv) > 2 else "w1-3,w1-2,w1-6,w1-5,chute"
        # The shipped w1_bot.gd fails to parse (since 11:54), so the probe runs a fixed copy through --w1bot2.
        R.run("bot2", [f"--w1bot2={tests}", f"--w1bot2-out={OUT}/bot2/bot.json".replace("\\", "/"), "--spawn=Default", "--ctx-shots", "--max-auto=30"], 1500)


if __name__ == "__main__":
    main()

"""W2 fix round 1 verification: re-runs the round-1 feel critic's station replays (real MakPlayer controller,
reactive inputs, no teleports after the start) on the fixed world, without the critic's --fix-origin patch.
Outputs go to Docs/progress/w2/fix1_runs/<case>/. Run from the entity folder:
    python game/assets/environment/w2/tools/w2_fix1_verify.py [case ...]
"""
import importlib.util, os, sys

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".."))
spec = importlib.util.spec_from_file_location("feel", os.path.join(ENT, "game", "tests", "critique_w2", "r1_feel", "run_r1_feel.py"))
feel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feel)
feel.OUT = os.path.join(ENT, "Docs", "progress", "w2", "fix1_runs")
feel.CASE_ARGS = {}
PLAT = feel.PLAT


def full_climb():
    # Garden floor -> L01..L08 with single hops only (no K1 backflip), the W2-1 round-1 pass route start.
    return feel.hop_chain([3.2, 0.05, 7.4], ["L01", "L02", "L03", "L04", "L05", "L06", "L07", "L08"], delay=10)


def bell_board_r():
    # Running hop from T3 toward the bell at eight different swing phases.
    s = feel.top("T3")
    ev = []
    for i in range(8):
        f0 = 2 + i * 240
        ev += [{"f": f0, "teleport": s, "yaw_deg": 90}, {"f": f0 + 1, "stick": [0, 0]},
               {"f": f0 + 30 + 31 * i, "stick": [-1, 0]}, {"f": f0 + 36 + 31 * i, "hold": "jump", "frames": 18},
               {"f": f0 + 150 + 31 * i, "stick": [0, 0]}]
    return {"fps": 60, "steer": "world", "end_frame": 2 + 8 * 240, "events": ev}


feel.CASES["full_climb"] = full_climb
feel.CASES["bell_board_r"] = bell_board_r

if __name__ == "__main__":
    os.makedirs(feel.OUT, exist_ok=True)
    for n in sys.argv[1:] or ["static_views", "full_climb", "leaf_bouncer", "checkpoints", "bell_board_r"]:
        feel.run_case(n)

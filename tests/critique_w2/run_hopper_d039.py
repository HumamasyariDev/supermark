"""D039 check in the real Cloud Hopper (W2-7): a first-timer bot that reacts late and steers at the next puff,
then lands on the flat PUFF04 with the stick released and must stay on it. Reuses run_fun_r1.run (Movie Maker + trace).
Outputs go to Docs/progress/finish/movement_feel/. Run from the entity folder:

    python game/tests/critique_w2/run_hopper_d039.py [--nomovie]
"""
import json, math, os, sys

sys.path.insert(0, os.path.dirname(__file__))
import run_fun_r1 as R  # noqa: E402

R.OUT = os.path.join(R.ENT, "Docs", "progress", "finish", "movement_feel")
R.NOMOVIE = "--nomovie" in sys.argv
PUFF = {1: (-18.1, 25.2, -10.9), 2: (-19.5, 27.8, -14.6), 3: (-21.6, 30.4, -17.8), 4: (-25.0, 31.5, -19.6)}


def case_hopper_d039():
    hs = (-14.6, 24.4, -11.4)
    # Start on the start pad itself (the r1 teleport east of it now ends in a ledge hang on the Cloud Landing rim).
    ev = [{"f": 2, "teleport": [hs[0], hs[1] + 0.1, hs[2]], "yaw_deg": 90},
          {"f": 30, "stick": R.toward(hs, PUFF[1], 1.0)},
          {"f": 46, "hold": "jump", "frames": 14},
          {"f": 64, "stick": [0, 0]}]   # lets go mid-air once the puff is in reach
    for k in (1, 2, 3):
        # A first-timer: no input for the first 10 frames of each bounce, then a partial push at the next puff.
        ev.append({"on": "state:bounce", "nth": k, "delay": 0, "stick": [0, 0]})
        ev.append({"on": "state:bounce", "nth": k, "delay": 10, "stick": R.toward(PUFF[k], PUFF[k + 1], 1.0)})
    ev.append({"on": "land", "nth": 4, "delay": 0, "stick": [0, 0]})
    return {"fps": 60, "steer": "world", "end_frame": 420, "events": ev}, 420, []


R.CASES["hopper_d039"] = case_hopper_d039

if __name__ == "__main__":
    r = R.run("hopper_d039")
    out = {"case": "hopper_d039", "mp4": r.get("mp4"), "errors": r.get("errors", [])[:4]}
    trace = r["log"].replace(".log", ".trace.jsonl")
    if os.path.exists(trace):
        rows = [json.loads(l) for l in open(trace) if l.strip()]
        rows = [x for x in rows if not x.get("meta") and "p" in x]
        bounces = [i for i in range(1, len(rows)) if rows[i].get("s") == "bounce" and rows[i - 1].get("s") != "bounce"]
        out["bounces"] = len(bounces)
        # The landing on PUFF04: first grounded non-bounce row after the third bounce.
        land = None
        if len(bounces) >= 3:
            for i in range(bounces[2], len(rows)):
                if rows[i].get("g") and rows[i].get("s") != "bounce":
                    land = i
                    break
        if land is not None:
            def rad(x):
                return math.hypot(x["p"][0] - PUFF[4][0], x["p"][2] - PUFF[4][2])
            after = rows[min(land + 12, len(rows) - 1)]   # 0.2 s later, before the 0.25 s vanish
            stop = next((i for i in range(land, len(rows)) if math.hypot(rows[i]["v"][0], rows[i]["v"][2]) < 0.01), None)
            out.update({"land_frame": rows[land]["f"], "land_pos": [round(c, 2) for c in rows[land]["p"]],
                        "land_r_from_puff04_m": round(rad(rows[land]), 3), "r_after_0p2s_m": round(rad(after), 3),
                        "grounded_after_0p2s": bool(after.get("g")), "state_after_0p2s": after.get("s"),
                        "slide_to_stop_m": round(math.hypot(rows[stop]["p"][0] - rows[land]["p"][0], rows[stop]["p"][2] - rows[land]["p"][2]), 3) if stop is not None else None,
                        "pass": rad(after) <= 1.4 and bool(after.get("g")) and abs(rows[land]["p"][1] - 31.5) < 1.0})
        else:
            out["pass"] = False
            out["states"] = r.get("states", [])[:40]
    json.dump(out, open(os.path.join(R.OUT, "hopper_d039_summary.json"), "w"), indent=1)
    print(json.dumps(out))

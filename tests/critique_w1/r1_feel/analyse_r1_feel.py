"""Summarise a FeelW1Probe camera log (cam.jsonl) per context segment (bot note or feel scenario).

    python game/tests/critique_w1/r1_feel/analyse_r1_feel.py <run_dir>   -> <run_dir>/summary.json and a table on stdout

Per segment: frames, gameplay-camera share, chest occluded %, head occluded %, camera sphere inside geometry %,
min/median camera distance, airborne frames with the landing spot outside the frustum or occluded %, camera pops
(> 0.8 m camera move in one rendered frame while the player moved < 0.3 m), chest off-screen or within 8 % of an edge %,
top occluders.
"""
import json, os, statistics, sys
from collections import Counter, OrderedDict


def main(run_dir):
    rows = []
    for l in open(os.path.join(run_dir, "cam.jsonl"), encoding="utf-8"):
        try:
            rows.append(json.loads(l))
        except ValueError:
            pass  # a truncated last line (killed run)
    segs = OrderedDict()
    prev = None
    for r in rows:
        key = r.get("ctx", "") or "(start)"
        s = segs.setdefault(key, {"n": 0, "game": 0, "occ": 0, "occh": 0, "ins": 0, "d": [], "air": 0, "land_out": 0, "land_occ": 0,
                                  "pops": 0, "edge": 0, "by": Counter(), "states": Counter(), "first_rf": r["rf"]})
        s["n"] += 1
        s["states"][r["s"]] += 1
        if r.get("gamecam"):
            s["game"] += 1
            s["occ"] += r["occ_chest"]
            s["occh"] += r["occ_head"]
            s["ins"] += r["inside"]
            s["d"].append(r["dist"])
            if r["occ_chest"] and r.get("occ_by"):
                s["by"][r["occ_by"]] += 1
            sx, sy = r["scr"]
            if sx < 0.08 or sx > 0.92 or sy < 0.08 or sy > 0.92:
                s["edge"] += 1
            if not r["g"] and r.get("land", {}).get("y") is not None:
                s["air"] += 1
                s["land_out"] += not r["land"]["fr"]
                s["land_occ"] += r["land"]["occ"]
            if prev is not None and prev.get("gamecam"):
                dc = sum((a - b) ** 2 for a, b in zip(r["c"], prev["c"])) ** 0.5
                dp = sum((a - b) ** 2 for a, b in zip(r["p"], prev["p"])) ** 0.5
                if dc > 0.8 and dp < 0.3:
                    s["pops"] += 1
        prev = r
    out = []
    for k, s in segs.items():
        g = max(s["game"], 1)
        a = max(s["air"], 1)
        row = {"ctx": k, "first_rf": s["first_rf"], "frames": s["n"], "gamecam_pct": round(100 * s["game"] / s["n"]),
               "occ_chest_pct": round(100 * s["occ"] / g, 1), "occ_head_pct": round(100 * s["occh"] / g, 1),
               "inside_pct": round(100 * s["ins"] / g, 1), "min_dist": min(s["d"]) if s["d"] else None,
               "med_dist": round(statistics.median(s["d"]), 2) if s["d"] else None, "air": s["air"],
               "land_out_pct": round(100 * s["land_out"] / a, 1), "land_occ_pct": round(100 * s["land_occ"] / a, 1),
               "pops": s["pops"], "edge_pct": round(100 * s["edge"] / g, 1), "top_occluders": s["by"].most_common(3),
               "states": dict(s["states"].most_common(4))}
        out.append(row)
    json.dump(out, open(os.path.join(run_dir, "summary.json"), "w"), indent=1)
    print("%-48s %6s %5s %5s %5s %5s %5s %5s %5s %4s %s" % ("ctx", "frames", "occ%", "head%", "ins%", "minD", "medD", "lOut%", "lOcc%", "pops", "occluders"))
    for r in out:
        print("%-48s %6d %5.1f %5.1f %5.1f %5s %5s %5.1f %5.1f %4d %s" % (r["ctx"][:48], r["frames"], r["occ_chest_pct"], r["occ_head_pct"], r["inside_pct"],
              r["min_dist"], r["med_dist"], r["land_out_pct"], r["land_occ_pct"], r["pops"], r["top_occluders"][:2]))


if __name__ == "__main__":
    main(sys.argv[1])

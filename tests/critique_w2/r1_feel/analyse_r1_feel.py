"""Summarise FeelW2Probe logs (W2 critique round 1, feel lens). Usage: python analyse_r1_feel.py <case> [--rows]"""
import json, math, os, sys

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
RUNS = os.path.join(ENT, "Docs", "progress", "critique", "w2", "r1_feel", os.environ.get("CRIT_RUNS", "runs"))


def load(case):
    rows = []
    for line in open(os.path.join(RUNS, case, "cam.jsonl"), encoding="utf-8"):
        try:
            rows.append(json.loads(line))
        except Exception:
            pass
    return rows


def summary(rows, label=""):
    gc = [r for r in rows if r.get("gamecam")]
    n = len(gc) or 1
    air = [r for r in gc if not r["g"]]
    land = [r for r in air if r.get("land", {}).get("y") is not None]
    occ_by = {}
    for r in gc:
        if r["occ_chest"] and r.get("occ_by"):
            occ_by[r["occ_by"]] = occ_by.get(r["occ_by"], 0) + 1
    out = {
        "label": label, "frames": len(rows), "gamecam_frames": len(gc),
        "occ_chest_pct": round(100 * sum(r["occ_chest"] for r in gc) / n, 1),
        "occ_head_pct": round(100 * sum(r["occ_head"] for r in gc) / n, 1),
        "cam_inside_pct": round(100 * sum(r["inside"] for r in gc) / n, 1),
        "min_dist": round(min((r["dist"] for r in gc), default=0), 2),
        "mean_dist": round(sum(r["dist"] for r in gc) / n, 2),
        "air_frames": len(air),
        "landing_in_frustum_pct": round(100 * sum(1 for r in land if r["land"]["fr"]) / (len(land) or 1), 1),
        "landing_occluded_pct": round(100 * sum(1 for r in land if r["land"]["occ"]) / (len(land) or 1), 1),
        "air_over_void_pct": round(100 * sum(1 for r in air if r.get("land", {}).get("y") is None) / (len(air) or 1), 1),
        "states": sorted({r["s"] for r in rows}),
        "zones": sorted({r.get("zone", "") for r in rows}),
        "occluders": sorted(occ_by.items(), key=lambda kv: -kv[1])[:6],
        "hp_min": min((r.get("hp", 6) for r in rows), default=None),
    }
    return out


def landings(rows):
    out, prev = [], True
    for r in rows:
        if r["g"] and not prev:
            out.append({"pf": r["pf"], "p": [round(c, 2) for c in r["p"]], "s": r["s"]})
        prev = r["g"]
    return out


if __name__ == "__main__":
    case = sys.argv[1]
    rows = load(case)
    lab_path = os.path.join(RUNS, case, "shot_labels.json")
    if os.path.exists(lab_path):
        labels = json.load(open(lab_path))
        shots = sorted(int(k) for k in labels)
        rep = json.load(open(os.path.join(RUNS, case, "replay.json")))
        tps = sorted(e["f"] for e in rep["events"] if "teleport" in e) + [10 ** 9]
        for i, s in enumerate(shots):
            seg = [r for r in rows if tps[i] + 2 <= r["pf"] < tps[i + 1]]
            sm = summary(seg, labels[str(s)])
            hurt = sum(1 for a, b2 in zip(seg, seg[1:]) if b2["s"] in ("hurt_air", "hurt_land") and a["s"] not in ("hurt_air", "hurt_land"))
            sm["hits"] = hurt
            sm["end_p"] = seg[-1]["p"] if seg else None
            print(json.dumps(sm))
            shot = [r for r in rows if r["pf"] >= s][:1]
            if shot:
                r = shot[0]
                print("   at shot: dist %.2f pitch %.1f yaw %.1f inside %s occ %s by %s scr %s p %s" % (r["dist"], r["cpitch"], r["cyaw"], r["inside"], r["occ_chest"], r.get("occ_by"), r["scr"], r["p"]))
    else:
        print(json.dumps(summary(rows, case), indent=0))
        print("landings:", json.dumps(landings(rows)))
        if "--rows" in sys.argv:
            for r in rows[::6]:
                print(r["pf"], r["s"], r["g"], r["p"], "v", r["v"], "wind", r["wind"], "d", r["dist"], "occ", r["occ_chest"], r.get("occ_by"), "in", r["inside"], "land", r.get("land"))

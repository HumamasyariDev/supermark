"""Per-segment summary of a run_r1c_seg.py batch. Usage: python analyse_seg.py <batch> [segment --rows N]"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("CRIT_RUNS", "runs_r1c")
import analyse_r1_feel as A  # noqa: E402

d = os.path.join(A.RUNS, sys.argv[1])
rows = [json.loads(l) for l in open(os.path.join(d, "cam.jsonl"), encoding="utf-8") if l.strip()]
ex = {}
if os.path.exists(os.path.join(d, "extra.jsonl")):
    for l in open(os.path.join(d, "extra.jsonl"), encoding="utf-8"):
        try:
            r = json.loads(l)
            ex[r["pf"]] = r
        except Exception:
            pass
segs = json.load(open(os.path.join(d, "segments.json")))
only = sys.argv[2] if len(sys.argv) > 2 else None
for s in segs:
    if only and s["label"] != only:
        continue
    seg = [r for r in rows if s["start"] + 3 <= r["pf"] < s["end"]]
    if not seg:
        print(s["label"], "NO ROWS")
        continue
    sm = A.summary(seg, s["label"])
    sm["hits"] = sum(1 for a, b in zip(seg, seg[1:]) if b["s"].startswith("hurt") and not a["s"].startswith("hurt"))
    sm["hp_end"] = seg[-1].get("hp")
    sm["end_p"] = seg[-1]["p"]
    sm["landings"] = [(l["pf"] - s["start"], l["p"], l["s"]) for l in A.landings(seg)]
    floors = []
    for r in seg:
        f = ex.get(r["pf"], {}).get("floor", "")
        if f and (not floors or floors[-1] != f):
            floors.append(f)
    sm["floors"] = floors
    oc = [ex[r["pf"]]["other_cam"] for r in seg if r["pf"] in ex and "other_cam" in ex[r["pf"]]]
    if oc:
        sm["other_cam"] = {"frames": len(oc), "inside_pct": round(100 * sum(o["inside"] for o in oc) / len(oc), 1),
                           "occ_pct": round(100 * sum(o["occ"] for o in oc) / len(oc), 1),
                           "dist_min": min(o["dist"] for o in oc), "dist_max": max(o["dist"] for o in oc)}
    print(json.dumps(sm))
    if "--rows" in sys.argv:
        n = int(sys.argv[sys.argv.index("--rows") + 1])
        for r in seg[::n]:
            e = ex.get(r["pf"], {})
            print(" ", r["pf"] - s["start"], r["s"], int(r["g"]), r["p"], "v", r["v"], "w", r["wind"], "d", r["dist"], "pit", r["cpitch"],
                  "occ", int(r["occ_chest"]), r.get("occ_by", ""), "in", int(r["inside"]), r["zone"], "land", r.get("land"), "fl", e.get("floor"), r.get("mark", ""))

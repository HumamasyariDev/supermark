"""Summarise an AnimCritiqueR1c per-frame log (jsonl): per family and state, durations, squash range,
lowest leg/foot joint height above the floor (ground contact proxy), turn rates and moonwalk frames
(moving faster than 0.5 m/s while facing more than 45 degrees away from the velocity heading).
Usage: python analyse_r1c.py <log.jsonl> [<out.json>]"""
import json
import sys
from collections import OrderedDict, defaultdict


def angdiff(a, b):
    d = (a - b + 180.0) % 360.0 - 180.0
    return abs(d)


def main():
    rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
    out = OrderedDict()
    by_fam = defaultdict(list)
    for r in rows:
        by_fam[r["fam"]].append(r)
    for fam, rs in by_fam.items():
        fs = OrderedDict()
        # State segments in order.
        segs = []
        cur = None
        for r in rs:
            if cur is None or r["state"] != cur["state"]:
                cur = {"state": r["state"], "t0": r["t"], "t1": r["t"], "rows": []}
                segs.append(cur)
            cur["t1"] = r["t"]
            cur["rows"].append(r)
        fs["sequence"] = [f'{s["state"]}@{s["t0"]:.2f}({s["t1"]-s["t0"]:.2f}s)' for s in segs]
        per = OrderedDict()
        for s in segs:
            st = per.setdefault(s["state"], {"time": 0.0, "sy": [], "sx": [], "clear": [], "yaw_rate": [], "moon": 0, "moving": 0, "rig_y": []})
            st["time"] += s["t1"] - s["t0"]
            for r in s["rows"]:
                if r["rig_scale"]:
                    st["sx"].append(r["rig_scale"][0])
                    st["sy"].append(r["rig_scale"][1])
                st["rig_y"].append(r["rig_y"])
                if r.get("low_leg_y") is not None and r.get("floor_y") is not None and r["floor_y"] == r["floor_y"]:
                    st["clear"].append(r["low_leg_y"] - r["floor_y"])
                st["yaw_rate"].append(abs(r["yaw_rate"]))
                if r["vel_h"] > 0.5:
                    st["moving"] += 1
                    if angdiff(r["yaw"], r["vel_heading"]) > 45.0:
                        st["moon"] += 1
        summ = OrderedDict()
        for k, st in per.items():
            def rng(a):
                return [round(min(a), 3), round(sorted(a)[len(a) // 2], 3), round(max(a), 3)] if a else None
            summ[k] = {
                "time_s": round(st["time"], 2),
                "scale_y_min_med_max": rng(st["sy"]),
                "scale_x_min_med_max": rng(st["sx"]),
                "rig_y_min_med_max": rng(st["rig_y"]),
                "leg_joint_above_floor_min_med_max": rng(st["clear"]),
                "yaw_rate_max_deg_s": round(max(st["yaw_rate"]), 1) if st["yaw_rate"] else None,
                "moving_frames": st["moving"],
                "moonwalk_frames": st["moon"],
            }
        fs["states"] = summ
        out[fam] = fs
    txt = json.dumps(out, indent=1)
    if len(sys.argv) > 2:
        open(sys.argv[2], "w", encoding="utf-8").write(txt)
    print(txt)


if __name__ == "__main__":
    main()

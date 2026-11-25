"""Summarise FeelHubProbe camera logs per task mark: frames, camera inside layer-1 geometry, chest occluded,
camera closer than 2 m, one-frame camera jumps (> 0.6 m), airborne frames whose landing spot is off-frustum or
occluded, and chest off-screen. Usage: python game/tests/critique_hub/analyse_r1_feel.py <run dir> [...]"""
import json, math, sys, collections


def main(dirs):
    for d in dirs:
        stats = collections.OrderedDict()
        prev = None
        for line in open(d + "/cam.jsonl", encoding="utf-8"):
            r = json.loads(line)
            m = r["m"].split("@")[0] if r["m"].startswith("cornice") else r["m"]
            if m.startswith("view:"):
                m = "views"
            s = stats.setdefault(m, collections.Counter())
            s["frames"] += 1
            if not r["gamecam"]:
                s["not_gamecam"] += 1
                prev = r
                continue
            s["inside"] += r["inside"]
            s["occ_chest"] += bool(r["occ_chest"])
            s["close_lt2"] += r["dist"] < 2.0
            if prev is not None and prev["m"] == r["m"]:
                jump = math.dist(prev["c"], r["c"])
                pjump = math.dist(prev["p"], r["p"])
                if jump - pjump > 0.6:
                    s["cam_pop"] += 1
            sx, sy = r["scr"]
            if sx < 0.05 or sx > 0.95 or sy < 0.05 or sy > 0.95:
                s["offscreen"] += 1
            if not r["g"] and "land" in r and r["land"].get("y") is not None:
                s["air"] += 1
                if not r["land"]["fr"]:
                    s["land_off_frustum"] += 1
                elif r["land"]["occ"]:
                    s["land_occluded"] += 1
            prev = r
        print("==", d)
        for m, s in stats.items():
            print("  %-28s %s" % (m[:28], dict(s)))


if __name__ == "__main__":
    main(sys.argv[1:])

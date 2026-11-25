"""Compare the critic's real Router flow runs (before) with the fix-stage run (after), from AudioFlowQA output:
- ambience: share of in-world, idle-Router timeline rows (10 Hz) whose Ambience bus peak is below -60 dB (bed dead)
- doubles: cake_slice_* starts within 0.2 s of hurt/heal, same file started twice within 60 ms
- 3D starts beyond 70 m from the listener
Writes a JSON summary and a timeline plot. Usage: python r7_flow_compare.py <out_prefix> <label>=<dir> [...]"""
import json, sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

WORLDS = {"HUB", "W1", "W2", "W3", "BOSS"}


def analyse(d):
    d = Path(d)
    tl = json.loads((d / "timeline.json").read_text())
    st = json.loads((d / "starts.json").read_text())
    rows = [r for r in tl if r.get("scene") in WORLDS and not r.get("busy") and not r.get("paused")]
    dead = [r for r in rows if r.get("peak", {}).get("Ambience", -99) < -60]
    per = {}
    for w in WORLDS:
        rw = [r for r in rows if r["scene"] == w]
        if rw:
            per[w] = {"rows": len(rw), "dead_pct": round(100 * sum(1 for r in rw if r["peak"].get("Ambience", -99) < -60) / len(rw), 1)}
    cake = [s for s in st if "cake_slice" in s.get("file", "")]
    hurt = [s for s in st if s.get("file", "").startswith(("hurt", "heal"))]
    cake_dbl = sum(1 for c in cake if any(abs(c["t"] - h["t"]) < 0.2 for h in hurt))
    dup = 0
    last = {}
    for s in sorted(st, key=lambda s: s["t"]):
        f = s.get("file", "")
        if f in last and s["t"] - last[f] < 0.06 and "blip" not in f and not f.startswith("footstep"):
            dup += 1
        last[f] = s["t"]
    far = sum(1 for s in st if s.get("3d") and (s.get("dist") or 0) > 70)
    return {"world_rows": len(rows), "ambience_dead_pct": round(100 * len(dead) / max(1, len(rows)), 1), "per_world": per,
            "starts": len(st), "cake_with_hurt_or_heal": cake_dbl, "same_file_within_60ms": dup, "3d_starts_beyond_70m": far}, tl


def main():
    out = sys.argv[1]
    runs = [a.split("=", 1) for a in sys.argv[2:]]
    res = {}
    fig, axes = plt.subplots(len(runs), 1, figsize=(14, 2.6 * len(runs)), squeeze=False)
    fig.patch.set_facecolor("white")
    for ax, (label, d) in zip(axes[:, 0], runs):
        r, tl = analyse(d)
        res[label] = r
        t = [x["t"] for x in tl]
        ax.plot(t, [x.get("peak", {}).get("Ambience", -99) for x in tl], lw=0.8, color="#2a7", label="Ambience bus peak")
        ax.plot(t, [x.get("peak", {}).get("Music", -99) for x in tl], lw=0.6, color="#57c", alpha=0.7, label="Music bus peak")
        prev = None
        for x in tl:
            if x["scene"] != prev:
                ax.axvline(x["t"], color="#999", lw=0.5)
                ax.text(x["t"], -5, x["scene"][:8], fontsize=7, rotation=90, va="top")
                prev = x["scene"]
        ax.set_ylim(-100, 0)
        ax.set_title(f"{label}: bed dead in {r['ambience_dead_pct']}% of in-world rows; cake doubles {r['cake_with_hurt_or_heal']}; "
                     f"same file <60 ms {r['same_file_within_60ms']}; 3D starts >70 m {r['3d_starts_beyond_70m']}", fontsize=9)
        ax.legend(loc="lower right", fontsize=7)
    fig.tight_layout()
    fig.savefig(out + ".png", dpi=110)
    Path(out + ".json").write_text(json.dumps(res, indent=1))
    print(json.dumps(res, indent=1))


main()

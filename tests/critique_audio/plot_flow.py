"""Critique audio r1: plots an AudioFlowQA run (timeline.json, starts.json, marks.json) into a PNG.

python game/tests/critique_audio/plot_flow.py <run_dir> <out.png> [title]
Top: music players A/B and the ambience player volume (dB, -60 when stopped) with scene bands and Router busy.
Middle: sound starts per 0.5 s (2D vs 3D) and 3D starts beyond 70 m.  Bottom: concurrent SFX voices.
"""
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

run = Path(sys.argv[1])
out = Path(sys.argv[2])
title = sys.argv[3] if len(sys.argv) > 3 else run.name
T = json.loads((run / "timeline.json").read_text())
S = json.loads((run / "starts.json").read_text())
M = json.loads((run / "marks.json").read_text())

t = [r["t"] for r in T]


def vol(r, k):
    p = r.get(k) or {}
    return p.get("vol", -60) if p.get("on") else -62


fig, ax = plt.subplots(3, 1, figsize=(18, 10), sharex=True, gridspec_kw={"height_ratios": [3, 2, 1.4]})
cols = {"HUB": "#e9d8c0", "W1": "#d6ecc8", "W2": "#d8e6f5", "W3": "#f6d9e6", "BOSS": "#e2d6ef", "TitleScreen": "#eeeeee"}
start = 0
for i in range(1, len(T) + 1):
    if i == len(T) or T[i]["scene"] != T[start]["scene"]:
        sc = T[start]["scene"]
        for a in ax:
            a.axvspan(T[start]["t"], T[i - 1]["t"], color=cols.get(sc, "#ffffff"), lw=0)
        ax[0].text((T[start]["t"] + T[i - 1]["t"]) / 2, 2, sc, ha="center", fontsize=9)
        start = i
ax[0].plot(t, [vol(r, "mA") for r in T], label="music player A", color="#7a1f2b")
ax[0].plot(t, [vol(r, "mB") for r in T], label="music player B", color="#c9a24a")
ax[0].plot(t, [vol(r, "amb") for r in T], label="ambience player", color="#2b6f3e", lw=2)
ax[0].fill_between(t, -64, [-58 if r["busy"] else -64 for r in T], color="#888", alpha=0.5, label="Router busy (page turn)")
silent = [r["t"] for r in T if r["scene"] in ("HUB", "W1", "W2", "W3", "BOSS") and not (r.get("amb") or {}).get("on") and not r["busy"]]
if silent:
    ax[0].scatter(silent, [-56] * len(silent), color="red", s=6, label="world without ambience bed")
ax[0].set_ylim(-64, 6)
ax[0].set_ylabel("player volume_db")
ax[0].legend(loc="lower right", fontsize=8, ncol=3)
ax[0].set_title(title)
bins = {}
for s in S:
    b = int(s["t"] * 2) / 2
    d = bins.setdefault(b, [0, 0, 0])
    if s["3d"]:
        d[1] += 1
        if s.get("dist", 0) > 70:
            d[2] += 1
    else:
        d[0] += 1
xs = sorted(bins)
ax[1].bar(xs, [bins[x][0] for x in xs], width=0.5, color="#4a6fa5", label="2D starts / 0.5 s")
ax[1].bar(xs, [bins[x][1] for x in xs], width=0.5, bottom=[bins[x][0] for x in xs], color="#e08a3c", label="3D starts / 0.5 s")
ax[1].bar(xs, [bins[x][2] for x in xs], width=0.5, bottom=[bins[x][0] + bins[x][1] - bins[x][2] for x in xs], color="#b00020", label="3D starts > 70 m away")
st = [s["t"] for s in S if "steal_of" in s and not s["loop"]]
ax[1].scatter(st, [0.5] * len(st), marker="x", color="black", label="voice stolen while audible")
ax[1].set_ylabel("starts")
ax[1].legend(loc="upper left", fontsize=8)
# concurrency recomputed from starts is approximate; use durations
ev = []
for s in S:
    if s["bus"] in ("SFX", "Voice") and not s["loop"]:
        ev.append((s["t"], 1))
        ev.append((s["t"] + max(0.05, s["len"] / max(0.05, s.get("pitch", 1.0))), -1))
ev.sort()
cur = 0
cx, cy = [], []
for x, d in ev:
    cur += d
    cx.append(x)
    cy.append(cur)
ax[2].step(cx, cy, where="post", color="#333")
ax[2].axhline(24, color="red", ls="--", lw=1)
ax[2].text(t[0], 24.5, "3D pool size 24", color="red", fontsize=8)
ax[2].set_ylabel("SFX+Voice voices")
ax[2].set_xlabel("seconds since test start")
for m in M:
    if m["mark"].startswith("step") and any(k in m["mark"] for k in ("reload", "truffle", "die", "world", "hub", "title")):
        ax[0].axvline(m["t"], color="#555", lw=0.6, ls=":")
        ax[0].text(m["t"], -46, m["mark"].split(" ", 2)[-1], rotation=90, fontsize=7, va="bottom")
plt.tight_layout()
out.parent.mkdir(parents=True, exist_ok=True)
plt.savefig(out, dpi=90)
print("wrote", out)

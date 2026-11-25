#!/usr/bin/env python3
"""Evidence charts for HERO r1 feel (post-fix re-run). Writes PNGs into Docs/progress/critique/hero/r1_feel/."""
import math, sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import feel_r1  # noqa
E = HERE.parents[2]
OUTD = E / 'Docs/progress/critique/hero/r1_feel'
stamp = sys.argv[1]

def rel_steps(cp):
    c = feel_r1.read_jsonl(cp)
    xs, ys, td = [], [], []
    for a, b in zip(c, c[1:]):
        if not (a.get('c') and b.get('c') and a.get('p') and b.get('p')):
            continue
        n = max(1, b['pf'] - a['pf'])
        d = math.dist([b['c'][i] - a['c'][i] for i in range(3)], [b['p'][i] - a['p'][i] for i in range(3)]) / n
        xs.append(b['pf']); ys.append(d)
        if a.get('g') is False and b.get('g') is True:
            td.append((b['pf'], d))
    return xs, ys, td

fig, axs = plt.subplots(2, 1, figsize=(13, 7), sharex=True)
for ax, (lab, p) in zip(axs, [('BEFORE (r1 critic, 00:00Z build)', E / 'Docs/progress/critique/hero/r1_feel/data/chain_sweep.cam.jsonl'),
                              ('AFTER (this re-run, current build)', E / 'Docs/progress/critique/hero/r1_feel/post/chain_sweep.cam.jsonl')]):
    xs, ys, td = rel_steps(p)
    ax.plot(xs, ys, lw=0.8, color='#555')
    ax.scatter([t[0] for t in td], [t[1] for t in td], color='#d33', s=22, zorder=3, label='touchdown frame')
    med = sorted(t[1] for t in td)[len(td) // 2]
    ax.set_title('%s: camera motion relative to Mak per physics tick, chain sweep. Touchdown median %.3f m, max %.3f m' % (lab, med, max(t[1] for t in td)), fontsize=10)
    ax.set_ylim(0, 1.1); ax.set_ylabel('m / tick'); ax.legend(loc='upper right')
axs[1].set_xlabel('physics frame')
fig.tight_layout(); fig.savefig(OUTD / ('%s__camera-touchdown-pop-before-after-chain-sweep.png' % stamp), dpi=110)

# Ledge dead band: lip_h1.0_j70 from the fix stage trace (current code).
t = feel_r1.read_jsonl(E / 'Docs/progress/hero/fix_r1/feel/lip_sweep.trace.jsonl')
on, rows = False, []
for r in t:
    if r.get('mark') == 'lip_h1.0_j70': on = True
    elif r.get('mark', '').startswith('lip_') and on: break
    if on: rows.append(r)
fig, ax = plt.subplots(figsize=(11, 5))
z = [-r['p'][2] for r in rows]; y = [r['p'][1] for r in rows]
cols = {'wall_slide': '#d33', 'jump': '#36c', 'walk': '#999', 'idle': '#999'}
ax.scatter(z, y, c=[cols.get(r['s'], '#000') for r in rows], s=8)
face = 5.649
ax.add_patch(plt.Rectangle((face + 0.35, 0), 3, 1.0, color='#c8a070', alpha=0.6))
ax.axhspan(1.0 - 0.5, 1.0, xmin=0, xmax=1, color='#6c6', alpha=0.15)
ax.axhspan(1.0 - 1.25, 1.0 - 0.78, color='#69c', alpha=0.15)
ax.axhspan(1.0 - 0.78, 1.0 - 0.5, color='#d33', alpha=0.18)
ax.text(1.0, 0.55, 'feet in 0.50-0.78 m under the lip: no vault, no grab -> wall_slide on a 1 m wall, drop', color='#a00', fontsize=9)
ax.text(1.0, 0.82, 'vault band (feet <= 0.5 m under the lip)', color='#383', fontsize=9)
ax.text(1.0, 0.0, 'grab band (0.78-1.25 m)', color='#247', fontsize=9)
ax.set_xlim(0, face + 3); ax.set_ylim(-0.3, 2.7)
ax.set_xlabel('distance along the run (m)'); ax.set_ylabel('feet height (m)')
ax.set_title('1.0 m ledge, jump at frame 70 (current build): blue = jump, red = wall_slide, grey = walk. Mak lands back on the ground.', fontsize=10)
fig.tight_layout(); fig.savefig(OUTD / ('%s__ledge-dead-band-1m-lip-wallslide-drop.png' % stamp), dpi=110)
print('ok')

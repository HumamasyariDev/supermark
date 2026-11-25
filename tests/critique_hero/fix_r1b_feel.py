#!/usr/bin/env python3
"""HERO fix stage round 1b: re-run the round 1 GAME FEEL probes on the fixed controller and camera.

Reuses the critic's replays from feel_r1.py unchanged (so before and after compare like for like) but writes the
traces to Docs/progress/hero/fix_r1b/feel/ instead of the critic's folder, then prints the numbers the critic used:
lip contacts (vault / hang / slide), wall-kick exit yaw per approach angle, camera motion at touchdown, chain kinds.

Usage: python game/tests/critique_hero/fix_r1b_feel.py [lip_sweep wallkick_angles cam_tour chain_sweep ...]
"""
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import feel_r1  # noqa: E402
import feel_r1_post  # noqa: E402,F401  (adds the 'circle' case)

ENTITY = HERE.parents[2]
OUT = ENTITY / 'Docs' / 'progress' / 'hero' / 'fix_r1b' / 'feel'
feel_r1.OUT = OUT


def rows_of(p):
    return feel_r1.read_jsonl(p)


def summarize_lip(tp):
    rows = rows_of(tp)
    out = {}
    cur = None
    for r in rows:
        m = r.get('mark')
        if m and m.startswith('lip_'):
            cur = m
            out[cur] = []
        if cur is not None:
            s = r['s']
            if not out[cur] or out[cur][-1] != s:
                out[cur].append(s)
    for k, v in out.items():
        print('  %-14s %s' % (k, ' > '.join(v[:9])))
    return out


def summarize_kicks(tp):
    rows = rows_of(tp)
    cur = None
    res = {}
    prev_s = None
    for r in rows:
        m = r.get('mark')
        if m and m.startswith('angle_'):
            cur = m
        if cur and r['s'] == 'wall_kick' and prev_s != 'wall_kick':
            res[cur] = {'yaw': r['yaw'], 'v': r['v']}
        prev_s = r['s']
    for k, v in res.items():
        print('  %-10s exit yaw %.1f  v %s' % (k, v['yaw'], [round(x, 2) for x in v['v']]))
    return res


def summarize_cam(cp, tp):
    cams = rows_of(cp)
    jumps, normal = [], []
    for a, b in zip(cams, cams[1:]):
        if b.get('rf') is None or a.get('c') is None or b.get('c') is None:
            continue
        d = math.dist(a['c'], b['c'])
        if a.get('g') is False and b.get('g') is True:
            jumps.append(round(d, 3))
        elif a.get('g') and b.get('g'):
            normal.append(d)
    print('  camera move on touchdown frames (m):', jumps[:30])
    if jumps:
        print('  touchdown max %.3f  median %.3f' % (max(jumps), sorted(jumps)[len(jumps) // 2]))
    if normal:
        print('  grounded frame median %.3f' % sorted(normal)[len(normal) // 2])
    scr = [c['scr'][1] for c in cams if c.get('scr') and not c.get('g')]
    if scr:
        print('  airborne frames with head above the top 12%%: %d of %d' % (sum(1 for y in scr if y < 0.12), len(scr)))
    return jumps


def main():
    names = sys.argv[1:] or ['lip_sweep', 'wallkick_angles', 'chain_sweep', 'cam_tour']
    for n in names:
        fn, scene = feel_r1.CASES[n]
        tp, cp, errs = feel_r1.run(n, fn(), scene)
        print(n, 'trace' if tp.exists() else 'NO TRACE', errs[:3], flush=True)
        if not tp.exists():
            continue
        if n == 'lip_sweep':
            summarize_lip(tp)
        elif n == 'wallkick_angles':
            summarize_kicks(tp)
        if cp.exists():
            summarize_cam(cp, tp)


if __name__ == '__main__':
    main()

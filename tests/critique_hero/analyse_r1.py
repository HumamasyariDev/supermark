#!/usr/bin/env python3
"""HERO critique r1: analyse the per-frame bone traces written by HeroAnimCritR1 (--bones-out).

    python game/tests/critique_hero/analyse_r1.py <trace.jsonl> [...]
Prints, per locomotion speed band: steps per second (foot-height minima), frames per step at 60 fps, the foot's
height above the ground reference (idle median), and the planted-foot horizontal speed (strict: foot within 1 cm of
its idle height). Prints per state: frame count, and min/max foot height (float / penetration) on grounded frames.
"""
import json, sys, statistics as st
from collections import defaultdict

BANDS = [(0.3, 1.5), (1.5, 3.0), (3.0, 5.0), (5.0, 6.5), (6.5, 9.0)]


def band(hs):
    for i, (a, b) in enumerate(BANDS):
        if a <= hs < b:
            return i
    return -1


def main(paths):
    rows = []
    for p in paths:
        seg = [json.loads(l) for l in open(p, encoding='utf-8') if l.strip()]
        for r in seg:
            # Bone positions are not physics-interpolated: compare them with the raw body origin when the trace has it.
            if 'pr' in r:
                r['p'] = r['pr']
        rows.append(seg)
    # Ground reference: ankle bone height above the body origin while idle and grounded.
    idle_h = [r[f][1] - r['p'][1] for seg in rows for r in seg if r['s'] == 'idle' and r['g'] for f in ('foot_l', 'foot_r') if f in r]
    ref = st.median(idle_h) if idle_h else 0.0
    print(f'ankle idle height ref {ref:.4f} m (n={len(idle_h)})')
    steps = defaultdict(list)
    slip = defaultdict(list)
    lift = defaultdict(list)
    stance = defaultdict(lambda: [0, 0])
    st_h = defaultdict(list)
    for seg in rows:
        for i in range(1, len(seg) - 1):
            a, r, c = seg[i - 1], seg[i], seg[i + 1]
            if 'foot_l' not in r:
                continue
            for f in ('foot_l', 'foot_r'):
                h = r[f][1] - r['p'][1] - ref
                if r['g']:
                    st_h[r['s']].append(h)
            if r['s'] not in ('walk', 'run') or not r['g']:
                continue
            b = band(r['hs'])
            if b < 0:
                continue
            for f in ('foot_l', 'foot_r'):
                hp, h, hn = (x[f][1] - x['p'][1] for x in (a, r, c))
                if h < hp and h <= hn:
                    steps[b].append((r['t'], f))
                hh = h - ref
                lift[b].append(hh)
                stance[b][1] += 1
                if hh < 0.01 and f in a and a['g'] and abs(a['t'] - r['t']) < 0.05:
                    stance[b][0] += 1
                    dx = r[f][0] - a[f][0]
                    dz = r[f][2] - a[f][2]
                    dt = r['t'] - a['t']
                    if dt > 0:
                        slip[b].append(((dx * dx + dz * dz) ** 0.5) / dt)
    for b, (lo, hi) in enumerate(BANDS):
        frames = [x for x in stance[b:b + 1]]
        n = stance[b][1] // 2
        if n == 0:
            continue
        secs = n / 60.0
        nsteps = len(steps[b])
        sps = nsteps / secs if secs else 0
        sl = sorted(slip[b])
        pf = stance[b][0] / max(stance[b][1], 1)
        print(f'band {lo}-{hi} m/s: {secs:.2f}s, steps/s {sps:.1f} (frames per step {60 / sps if sps else 0:.1f}), '
              f'foot-on-ground fraction {pf:.2f}, max lift {max(lift[b]):.3f} m, '
              f'planted slip median {st.median(sl) if sl else 0:.2f} p90 {sl[int(len(sl) * 0.9)] if sl else 0:.2f} m/s (n={len(sl)})')
    print('grounded foot height vs idle ref by state (min / median / max, m):')
    for s, hs in sorted(st_h.items()):
        print(f'  {s:14s} n={len(hs):5d}  {min(hs):+.3f} / {st.median(hs):+.3f} / {max(hs):+.3f}')


if __name__ == '__main__':
    main(sys.argv[1:])

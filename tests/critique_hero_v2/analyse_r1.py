#!/usr/bin/env python3
"""Analyse hero v2 critique bone traces: foot slip per speed band, blinks, hat/pack/ear motion, squash, per-state summaries.
    python analyse_r1.py <bones dir> [view]
"""
import json, math, sys, statistics as st
from pathlib import Path
from collections import defaultdict

d = Path(sys.argv[1]); view = sys.argv[2] if len(sys.argv) > 2 else 'side'
rows = []
for f in sorted(d.glob(f'{view}_part*.jsonl'), key=lambda p: int(p.stem.split('part')[1])):
    part = [json.loads(l) for l in open(f, encoding='utf-8')]
    for r in part:
        r['part'] = f.stem
    rows.append(part)

def hspeed(a, b):
    return math.hypot(b[0] - a[0], b[2] - a[2]) * 60.0

res = {}
# Foot slip: planted = grounded walk, foot within 1.5 cm of its local floor (player feet y), measured on consecutive frames.
bands = [(0.3, 1.5), (1.5, 3.0), (3.0, 5.0), (5.0, 6.5), (6.5, 8.0)]
slip = defaultdict(list); plant_frames = defaultdict(int); walk_frames = defaultdict(int)
for part in rows:
    for a, b in zip(part, part[1:]):
        if b['f'] - a['f'] != 1 or b['s'] != 'walk' or not b['g'] or not a['g']:
            continue
        hs = b['hs']
        band = next((x for x in bands if x[0] <= hs < x[1]), None)
        if band is None:
            continue
        walk_frames[band] += 1
        for ft in ('foot_l', 'foot_r'):
            if b[ft][1] - b['p'][1] < 0.048 and a[ft][1] - a['p'][1] < 0.048 and abs(b[ft][1] - a[ft][1]) * 60 < 0.25:
                slip[band].append(hspeed(a[ft], b[ft]))
                plant_frames[band] += 1
res['foot_slip'] = {f'{x[0]}-{x[1]} m/s': {'walk_frames': walk_frames[x], 'planted_foot_frames': plant_frames[x],
    'p50': round(st.median(slip[x]), 3) if slip[x] else None,
    'p90': round(sorted(slip[x])[int(0.9 * len(slip[x])) - 1], 3) if len(slip[x]) > 9 else None,
    'share_over_0.3': round(sum(1 for v in slip[x] if v > 0.3) / len(slip[x]), 2) if slip[x] else None} for x in bands}
# Foot height under ground (penetration) and floating while grounded idle
pen = []; flo = []
for part in rows:
    for r in part:
        if r['g']:
            for ft in ('foot_l', 'foot_r'):
                h = r[ft][1] - r['p'][1]
                pen.append(h)
            if r['s'] == 'idle':
                flo.append(min(r['foot_l'][1], r['foot_r'][1]) - r['p'][1])
res['foot_bone_height_grounded'] = {'min': round(min(pen), 3), 'p10': round(sorted(pen)[len(pen) // 10], 3), 'median': round(st.median(pen), 3)}
res['idle_lowest_foot_bone'] = {'min': round(min(flo), 3), 'max': round(max(flo), 3)} if flo else None
# Blinks: lid angle > 1.2 rad counts as closed
blinks = []; idle_frames = 0
for part in rows:
    closed = False
    for r in part:
        if r['s'] == 'idle':
            idle_frames += 1
        lid = r.get('lid', 0.0)
        if lid > 1.2 and not closed:
            closed = True; blinks.append((r['part'], r['f'], r['s']))
        elif lid < 0.6:
            closed = False
res['blinks'] = {'count': len(blinks), 'idle_seconds': round(idle_frames / 60, 1), 'at': blinks[:40]}
# Hat relative tilt and pack swing per state
per = defaultdict(lambda: defaultdict(list))
for part in rows:
    for r in part:
        s = r['s']
        per[s]['hat_rel_deg'].append(math.degrees(r.get('hat_rel', 0.0)))
        per[s]['pack_minus_chest_y'].append(r['backpack_socket'][1] - r['chest'][1])
        hr = r.get('head_rot', [0, 0, 0])
        per[s]['head_pitch_deg'].append(math.degrees(hr[0]))
        per[s]['hips_sy'].append(r.get('hips_s', [1, 1, 1])[1])
        per[s]['ear_tip_minus_head_y'].append(((r['ear_l_2'][1] + r['ear_r_2'][1]) / 2) - r['head'][1])
res['per_state'] = {}
for s, ch in per.items():
    res['per_state'][s] = {'frames': len(ch['hat_rel_deg'])}
    for k, v in ch.items():
        res['per_state'][s][k] = [round(min(v), 3), round(max(v), 3)]
print(json.dumps(res, indent=1))

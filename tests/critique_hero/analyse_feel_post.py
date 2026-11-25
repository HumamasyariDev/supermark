#!/usr/bin/env python3
"""Analyse the HERO r1 feel probes for a data folder (default: r1_feel/post). Prints a JSON summary.
Usage: python game/tests/critique_hero/analyse_feel_post.py [folder]"""
import json, math, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import feel_r1, fix_r1_feel  # noqa
D = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parents[2] / 'Docs/progress/critique/hero/r1_feel/post'
def _read(p):
    rows = []
    for line in p.read_text(encoding='utf-8').splitlines():
        try:
            r = json.loads(line)
        except ValueError:
            continue  # a run killed mid-write leaves a partial last line
        if not r.get('meta'):
            rows.append(r)
    return rows
R = lambda n: _read(D / n) if (D / n).exists() else None
out = {}

def seg_by_mark(rows, prefix):
    segs, cur = {}, None
    for r in rows:
        m = r.get('mark')
        if m and m.startswith(prefix):
            cur = m; segs[cur] = []
        if cur: segs[cur].append(r)
    return segs

t = R('chain_sweep.trace.jsonl')
if t:
    res = {}
    for k, rows in seg_by_mark(t, 'press_d').items():
        kinds = [r.get('jk') or r['s'] for r in rows]
        st = []
        for r in rows:
            if not st or st[-1] != r['s']: st.append(r['s'])
        res[k] = '>'.join(st[:6])
    out['chain'] = res
t = R('lip_sweep.trace.jsonl')
if t:
    res = {}
    for k, rows in seg_by_mark(t, 'lip_').items():
        st = []
        for r in rows:
            if not st or st[-1] != r['s']: st.append(r['s'])
        top = max(r['p'][1] for r in rows)
        endy = rows[-1]['p'][1]
        h = float(k.split('_h')[1].split('_')[0])
        on = [r for r in rows if r['g'] and r['p'][1] > h - 0.05]
        t0 = next((i for i, r in enumerate(rows) if r['s'] == 'jump'), None)
        t1 = next((i for i, r in enumerate(rows) if r['g'] and r['p'][1] > h - 0.05 and r['s'] in ('walk', 'idle', 'run')), None)
        res[k] = {'states': '>'.join(st[:10]), 'on_top': bool(on),
                  'jump_to_control_s': round((t1 - t0) / 60, 2) if (t0 is not None and t1 is not None) else None}
    out['lip'] = res
t = R('wallkick_angles.trace.jsonl')
if t:
    res, cur, prev = {}, None, None
    for r in t:
        m = r.get('mark')
        if m and m.startswith('angle_'): cur = m; res[cur] = {'kick': False, 'states': []}
        if cur:
            if not res[cur]['states'] or res[cur]['states'][-1] != r['s']: res[cur]['states'].append(r['s'])
            if r['s'] == 'wall_kick' and prev != 'wall_kick': res[cur].update(kick=True, yaw=r['yaw'], v=[round(x, 2) for x in r['v']])
        prev = r['s']
    for v in res.values(): v['states'] = '>'.join(v['states'][:8])
    out['wallkick_angles'] = res
for name in ['cam_tour', 'w1_movie', 'response', 'circle', 'lip_sweep', 'chain_sweep']:
    c = R(name + '.cam.jsonl')
    if not c: continue
    td, gr, occ, ins, top, yawrate = [], [], 0, 0, 0, []
    for a, b in zip(c, c[1:]):
        if a.get('c') is None or b.get('c') is None: continue
        # camera motion relative to Mak (headless render frames can span several physics ticks under load)
        d = math.dist([b['c'][i] - a['c'][i] for i in range(3)], [b['p'][i] - a['p'][i] for i in range(3)]) if a.get('p') and b.get('p') else math.dist(a['c'], b['c'])
        if b.get('pf', 0) - a.get('pf', 0) > 1:
            d /= (b['pf'] - a['pf'])
        if a.get('g') is False and b.get('g') is True: td.append(round(d, 3))
        elif a.get('g') and b.get('g'): gr.append(d)
        dy = (b['cyaw'] - a['cyaw'] + 180) % 360 - 180
        yawrate.append(abs(dy) * 60)
    for r in c:
        occ += bool(r.get('occ_head') and r.get('occ_chest'))
        ins += bool(r.get('inside'))
        if r.get('scr') and (r['scr'][1] < 0.08 or r['scr'][1] > 0.95 or r['scr'][0] < 0.05 or r['scr'][0] > 0.95): top += 1
    out['cam_' + name] = {'frames': len(c), 'touchdown_jump_max': max(td) if td else None,
                          'touchdown_median': sorted(td)[len(td)//2] if td else None, 'n_touchdowns': len(td),
                          'grounded_median_step': round(sorted(gr)[len(gr)//2], 3) if gr else None,
                          'occluded_frames': occ, 'inside_geometry_frames': ins, 'mak_near_frame_edge': top,
                          'yaw_rate_p95_degps': round(sorted(yawrate)[int(len(yawrate)*.95)], 1) if yawrate else None,
                          'dist_min': min(r['dist'] for r in c if 'dist' in r), 'dist_max': max(r['dist'] for r in c if 'dist' in r)}
t = R('circle.trace.jsonl')
if t:
    res = {}
    for k, rows in seg_by_mark(t, 'hold_').items():
        mv = [r for r in rows if math.hypot(r['v'][0], r['v'][2]) > 6.0]
        if len(mv) > 20:
            yaws = [r['yaw'] for r in mv]
            drift = (yaws[-1] - yaws[0] + 180) % 360 - 180
            p0, p1 = mv[0]['p'], mv[-1]['p']
            path = sum(math.dist(a['p'], b['p']) for a, b in zip(mv, mv[1:]))
            res[k] = {'heading_drift_deg': round(drift, 1), 'straightness': round(math.dist(p0, p1) / path, 3), 'secs': round(len(mv)/60, 2)}
    out['circle'] = res
print(json.dumps(out, indent=1))

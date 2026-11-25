#!/usr/bin/env python3
"""Analyse FeelProbeV2 logs (hero v2 critique r1, feel lens).

python game/tests/critique_hero_v2/analyse_v2.py <case> [<case>__night]
Prints per-state visual statistics: on-screen height, hat top and head heights, foot-contact error while grounded,
head lag on takeoff/landing, and camera framing (screen y of the chest, landing spot visibility).
"""
import json
import statistics as st
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parents[3] / 'Docs' / 'progress' / 'critique' / 'hero_v2' / 'r1_feel' / 'data'
_DD = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--data=')), '')
if _DD:
    DATA = Path(_DD).resolve()


def load(tag):
    rows = [json.loads(l) for l in (DATA / (tag + '.cam.jsonl')).read_text(encoding='utf-8').splitlines() if l.strip()]
    tr = [json.loads(l) for l in (DATA / (tag + '.trace.jsonl')).read_text(encoding='utf-8').splitlines() if l.strip()]
    return rows, [t for t in tr if not t.get('meta')]


def pct(xs, q):
    xs = sorted(xs)
    if not xs:
        return None
    return xs[min(len(xs) - 1, int(q * (len(xs) - 1) + 0.5))]


def by_pf(rows):
    d = {}
    for r in rows:
        d[r['pf']] = r   # last rendered frame of each physics frame
    return d


def summary(tag):
    rows, tr = load(tag)
    out = {'tag': tag, 'rows': len(rows)}
    rb = [r for r in rows if 'b' in r]
    out['rows_with_bones'] = len(rb)
    idle = [r for r in rb if r['s'] == 'idle' and r['g']]
    if idle:
        out['idle_h_scr_p50'] = pct([r.get('h_scr', 0) for r in idle], 0.5)
        out['idle_h_body_p50'] = pct([r.get('h_body', 0) for r in idle], 0.5)
        out['idle_hat_top_y_p50'] = pct([r['b'].get('hat_top', [0, 0, 0])[1] for r in idle], 0.5)
        out['idle_head_y_p50'] = pct([r['b']['head'][1] for r in idle], 0.5)
        out['idle_hips_y_p50'] = pct([r['b']['hips'][1] for r in idle], 0.5)
        out['idle_foot_y_p50'] = pct([min(r['b']['foot_l'][1], r['b']['foot_r'][1]) for r in idle], 0.5)
        out['idle_chest_scr_y_p50'] = pct([r['scr'][1] for r in idle], 0.5)
    foot0 = out.get('idle_foot_y_p50', 0.0)
    states = {}
    for r in rb:
        s = states.setdefault(r['s'], {'n': 0, 'h': [], 'hat': [], 'foot': [], 'headrel': []})
        s['n'] += 1
        s['h'].append(r.get('h_scr', 0))
        if 'hat_top' in r['b']:
            s['hat'].append(r['b']['hat_top'][1])
        if r['g']:
            s['foot'].append(min(r['b']['foot_l'][1], r['b']['foot_r'][1]) - foot0)
        s['headrel'].append(r['b']['head'][1] - r['b']['hips'][1])
    out['states'] = {}
    for k, s in sorted(states.items()):
        out['states'][k] = {
            'n': s['n'], 'h_scr_p50': pct(s['h'], 0.5), 'h_scr_min': min(s['h']) if s['h'] else None,
            'hat_top_max': max(s['hat']) if s['hat'] else None,
            'grounded_foot_err_p05': round(pct(s['foot'], 0.05), 3) if s['foot'] else None,
            'grounded_foot_err_p95': round(pct(s['foot'], 0.95), 3) if s['foot'] else None,
            'head_minus_hips_range': [round(min(s['headrel']), 3), round(max(s['headrel']), 3)]}
    # Takeoffs: physics frames where the state changes into a jump kind; look at the head-to-hips distance and the
    # head height relative to the body origin over the next 10 physics frames (does the visual follow the body at once?).
    pf = by_pf(rb)
    jumps = ['jump', 'double_jump', 'triple_jump', 'long_jump', 'backflip', 'side_flip', 'wall_kick']
    ev = []
    prev = None
    for t in tr:
        if prev is not None and t['s'] != prev['s'] and t['s'] in jumps:
            f = t['f']
            seq = []
            for k in range(-1, 12):
                r = pf.get(f + k)
                if r is not None:
                    seq.append((k, r['b']['hips'][1], r['b']['head'][1], r['b'].get('hat_top', [0, 0, 0])[1]))
            ev.append({'kind': t['s'], 'pf': f, 'hips_head_hat_rel': seq})
        prev = t
    out['takeoffs'] = ev
    # Landings: grounded after airborne. Squash depth (hips y drop vs idle) and duration below 90 % of idle hips height.
    lands = []
    prev = None
    hips0 = out.get('idle_hips_y_p50', None)
    for t in tr:
        if prev is not None and t['g'] and not prev['g'] and hips0:
            f = t['f']
            hs = []
            for k in range(0, 30):
                r = pf.get(f + k)
                if r is not None:
                    hs.append((k, r['b']['hips'][1], r['s']))
            mn = min(hs, key=lambda x: x[1]) if hs else None
            low = [k for k, h, _ in hs if h < 0.9 * hips0]
            lands.append({'pf': f, 'from': prev['s'], 'impact_vy': prev['v'][1], 'hips_min': mn[1] if mn else None,
                          'min_at': mn[0] if mn else None, 'frames_below_90pct': len(low),
                          'state_after': hs[-1][2] if hs else None})
        prev = t
    out['landings'] = lands
    # Camera: airborne landing-spot visibility and chest screen y.
    air = [r for r in rows if 'land' in r]
    if air:
        out['air_rows'] = len(air)
        out['land_in_frustum'] = round(sum(1 for r in air if r['land']['fr']) / len(air), 3)
        out['land_occluded'] = round(sum(1 for r in air if r['land']['occ']) / len(air), 3)
        out['land_scr_y_p95'] = pct([r['land']['scr'][1] for r in air], 0.95)
    out['chest_scr_y'] = [pct([r['scr'][1] for r in rows], q) for q in (0.05, 0.5, 0.95)]
    out['occ_head'] = round(sum(1 for r in rows if r['occ_head']) / len(rows), 3)
    return out


if __name__ == '__main__':
    for tag in [a for a in sys.argv[1:] if not a.startswith('--')]:
        s = summary(tag)
        full = DATA.parent / ('analysis_' + tag + '.json')
        full.write_text(json.dumps(s, indent=1), encoding='utf-8')
        brief = {k: v for k, v in s.items() if k not in ('takeoffs', 'landings', 'states')}
        print(json.dumps(brief, indent=1))
        for k, v in s['states'].items():
            print('  ', k, v)
        for l in s['landings']:
            print('  LAND', l)

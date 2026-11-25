#!/usr/bin/env python3
"""Movement tests for Super Mak 64 (player workstream).

Runs replays through the real controller in MoveLab, headless, via tools/godot.py, then measures
the traces. Expectations come from the movement profile's own arithmetic (discrete 60 Hz
integration identical to the controller), so a pass means "the controller does what the profile
says". Reference parity is a separate question (Docs/MOVEMENT_REFERENCE.md).

Usage (from the entity folder or anywhere):
    python game/tests/run_movement_tests.py [case ...] [--workers 6]
Output: game/tests/results/movement_<UTC>.json and game/tests/results/latest.json
"""
import concurrent.futures as cf
import datetime as _dt
import json
import math
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAME = HERE.parent
ENTITY = GAME.parent
REPLAYS = HERE / 'replays'
RESULTS = HERE / 'results'
TRACES = RESULTS / 'traces'
GODOT_PY = ENTITY / 'tools' / 'godot.py'
SCENE = 'res://scenes/tests/MoveLab.tscn'
DT = 1.0 / 60.0


def load_profile():
    txt = (GAME / 'scenes' / 'player' / 'mak_profile.tres').read_text(encoding='utf-8')
    out = {}
    for k, v in re.findall(r'^(\w+) = ([-0-9.]+)$', txt, re.M):
        out[k] = float(v)
    return out


P = load_profile()
G = P['gravity']


# ------------------------------------------------------------------ discrete expectations

def sim_jump(v0, cut_after=None, g=None):
    """Apex of a jump as the controller integrates it: the takeoff frame moves v0*dt, then each
    frame vy -= g*dt and y += vy*dt. From frame cut_after on (jump released), while vy is above
    jump_cut_min_velocity the tick multiplies vy by jump_cut_factor instead of applying gravity."""
    g = G if g is None else g
    y, vy, apex, f = v0 * DT, v0, v0 * DT, 1
    while vy > 0 or f < 3:
        if cut_after is not None and f >= cut_after and vy > P['jump_cut_min_velocity']:
            vy *= P['jump_cut_factor']
        else:
            vy = max(vy - g * DT, -P['terminal_velocity'])
        y += vy * DT
        apex = max(apex, y)
        f += 1
        if f > 600:
            break
    return apex


def sim_airtime(v0, drop=0.0):
    y, vy, f = v0 * DT, v0, 1
    while y > -drop or vy > 0:
        vy = max(vy - G * DT, -P['terminal_velocity'])
        y += vy * DT
        f += 1
        if f > 900:
            break
    return f * DT


def sim_run():
    """Time to 90 % of top speed and the stopping distance from top speed."""
    v, t, t90 = 0.0, 0.0, None
    top = P['run_top_speed']
    while v < top - 1e-6 and t < 10:
        a = P['walk_accel'] * (1.0 - P['accel_taper'] * min(max(v / top, 0), 1))
        v = min(v + a * DT, top)
        t += DT
        if t90 is None and v >= 0.9 * top:
            t90 = t
    d = 0.0
    v = top
    while v > 0:
        v = max(v - (P['brake_decel'] if top >= P['brake_min_speed'] else P['stop_decel']) * DT, 0.0)
        d += v * DT
    return t90, t, d


# Reference facts from Docs/MOVEMENT_REFERENCE.md (REA, derived 30 Hz simulation of measured rules).
REF = {'time_to_90pct_s': 1.33, 'time_to_top_s': 1.6, 'stop_distance_m': 0.875, 'apex_single_standing_m': 1.89,
       'apex_single_run_m': 2.64, 'apex_tap_m': 0.48, 'apex_double_run_m': 3.75, 'apex_triple_m': 4.92,
       'apex_backflip_m': 4.0, 'apex_long_jump_m': 1.88, 'long_jump_distance_m': 12.2, 'slam_hover_s': 0.5,
       'slam_drop_start_mps': 11.72, 'top_speed_mps': 7.5}
# Night 02 additions (REA round 2), same file, section "Night 02 additions".
REF.update({'knockback_speed_mps': 3.75, 'hurt_soft_s': 0.8, 'post_hurt_invuln_s': 1.0, 'knockback_ground_keep': 0.9,
            'punch_lunge_m': 0.227, 'jab_strike_s': 0.133, 'jab_total_s': 0.467, 'slide_jump_delay_s': 0.167,
            'slide_threshold_deg': 38.0})


def ref_check(name, measured, key, tol=0.06):
    c = check('reference parity: ' + name, measured, REF[key], tol)
    c['reference'] = 'Docs/MOVEMENT_REFERENCE.md'
    return c


# ------------------------------------------------------------------ trace helpers

def read_trace(path):
    lines = Path(path).read_text(encoding='utf-8').splitlines()
    meta = json.loads(lines[0]) if lines else {}
    rows = [json.loads(l) for l in lines[1:] if l.strip()]
    return meta, rows


def hs(r):
    return math.hypot(r['v'][0], r['v'][2])


def states(rows):
    seq = []
    for r in rows:
        if not seq or seq[-1] != r['s']:
            seq.append(r['s'])
    return seq


def first_idx(rows, pred, start=0):
    for i in range(start, len(rows)):
        if pred(rows[i]):
            return i
    return None


def air_segment(rows, kind, start=0):
    """(takeoff index, landing index) of the first air phase whose state is `kind`."""
    i = first_idx(rows, lambda r: r['s'] == kind, start)
    if i is None:
        return None, None
    j = first_idx(rows, lambda r: r['g'], i)
    return i, j


def check(name, measured, expected, tol, rel=True):
    if measured is None or expected is None:
        return {'name': name, 'measured': measured, 'expected': expected, 'pass': False}
    lim = abs(expected) * tol if rel else tol
    ok = abs(measured - expected) <= lim
    return {'name': name, 'measured': round(measured, 4), 'expected': round(expected, 4),
            'tolerance': ('%g%%' % (tol * 100)) if rel else tol, 'pass': ok}


def flag(name, ok, detail=''):
    return {'name': name, 'pass': bool(ok), 'detail': detail}


# ------------------------------------------------------------------ cases

OPEN = [-20.0, 0.0, 20.0]       # open flat ground facing +X (yaw -90)


def case_run_accel_stop():
    rep = {'start': {'pos': OPEN, 'yaw_deg': -90}, 'end_frame': 260,
           'events': [{'f': 0, 'stick': [1, 0]}, {'f': 150, 'stick': [0, 0]}]}

    def an(rows, out):
        t90_exp, ttop_exp, stop_exp = sim_run()
        pre = [r for r in rows if r['f'] < 150]
        top = max(hs(r) for r in pre)
        i90 = first_idx(rows, lambda r: hs(r) >= 0.9 * P['run_top_speed'])
        t90 = (rows[i90]['f'] + 1) * DT if i90 is not None else None
        rel = first_idx(rows, lambda r: r['f'] >= 150)
        stop = first_idx(rows, lambda r: hs(r) < 0.01, rel)
        dist = abs(rows[stop]['p'][0] - rows[rel - 1]['p'][0]) if stop is not None else None
        out['metrics'] = {'top_speed': top, 'time_to_90pct_s': t90, 'stopping_distance_m': dist,
                          'stop_time_s': (rows[stop]['f'] - rows[rel]['f']) * DT if stop else None}
        return [check('top speed (m/s)', top, P['run_top_speed'], 0.01),
                check('time to 90% (s)', t90, t90_exp, 0.05),
                check('stopping distance (m)', dist, stop_exp, 0.1),
                ref_check('time to 90% (s)', t90, 'time_to_90pct_s', 0.06),
                ref_check('stopping distance (m)', dist, 'stop_distance_m', 0.15)]
    return rep, an


def _apex_case(events, kind, v0_fn, tol=0.03, end=200, start=None, ref=None, g=None):
    rep = {'start': {'pos': start or OPEN, 'yaw_deg': -90}, 'end_frame': end, 'events': events}

    def an(rows, out):
        i, j = air_segment(rows, kind)
        if i is None:
            out['metrics'] = {'states': states(rows)}
            return [flag('%s happened' % kind, False, ' > '.join(states(rows)))]
        y0 = rows[i - 1]['p'][1]
        seg = rows[i:j + 1] if j else rows[i:]
        apex = max(r['p'][1] for r in seg) - y0
        fs = rows[i - 1]['fs']
        v0, cut_after = v0_fn(fs)
        exp = sim_jump(v0, cut_after, g)
        dist = math.hypot(rows[j]['p'][0] - rows[i - 1]['p'][0], rows[j]['p'][2] - rows[i - 1]['p'][2]) if j else None
        air = (rows[j]['f'] - rows[i]['f'] + 1) * DT if j else None
        out['metrics'] = {'apex_m': apex, 'takeoff_speed': fs, 'distance_m': dist, 'airtime_s': air,
                          'apex_over_capsule': apex / 1.25}
        res = [check('%s apex (m)' % kind, apex, exp, tol)]
        if ref:
            res.append(ref_check('%s apex (m)' % kind, apex, ref, 0.05))
        return res
    return rep, an


def case_jump_stand_full():
    return _apex_case([{'f': 10, 'press': 'jump'}, {'f': 70, 'release': 'jump'}], 'jump',
                      lambda fs: (P['jump_velocity'] + P['jump_speed_bonus'] * max(fs, 0), None), ref='apex_single_standing_m')


def case_jump_stand_tap():
    return _apex_case([{'f': 10, 'tap': 'jump'}], 'jump',
                      lambda fs: (P['jump_velocity'] + P['jump_speed_bonus'] * max(fs, 0), 2), tol=0.06)  # fix r1: one full-rise tick before the cut


def case_jump_run_full():
    return _apex_case([{'f': 0, 'stick': [1, 0]}, {'f': 90, 'press': 'jump'}, {'f': 140, 'release': 'jump'}],
                      'jump', lambda fs: (P['jump_velocity'] + P['jump_speed_bonus'] * max(fs, 0), None), end=220, ref='apex_single_run_m')


def case_double_jump():
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 90, 'hold': 'jump', 'frames': 40},
          {'on': 'land', 'nth': 1, 'delay': 0, 'hold': 'jump', 'frames': 40}]
    return _apex_case(ev, 'double_jump', lambda fs: (P['double_jump_velocity'] + P['jump_speed_bonus'] * max(fs, 0), None), end=260)


def case_triple_jump():
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 90, 'hold': 'jump', 'frames': 40},
          {'on': 'land', 'nth': 1, 'delay': 0, 'hold': 'jump', 'frames': 50},
          {'on': 'land', 'nth': 2, 'delay': 0, 'hold': 'jump', 'frames': 60}]
    return _apex_case(ev, 'triple_jump', lambda fs: (P['triple_jump_velocity'], None), end=340, ref='apex_triple_m')


def case_chain_late():
    """A second jump pressed 0.35 s after landing must be a plain single jump (window 0.2 s)."""
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 90, 'hold': 'jump', 'frames': 40},
          {'on': 'land', 'nth': 1, 'delay': 21, 'hold': 'jump', 'frames': 40}]
    rep = {'start': {'pos': OPEN, 'yaw_deg': -90}, 'end_frame': 260, 'events': ev}

    def an(rows, out):
        seq = states(rows)
        out['metrics'] = {'states': seq}
        return [flag('late press gives no double jump', 'double_jump' not in seq and seq.count('jump') >= 2, ' > '.join(seq))]
    return rep, an


def case_long_jump():
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 90, 'hold': 'crouch', 'frames': 6}, {'f': 91, 'hold': 'jump', 'frames': 30}]
    rep, an0 = _apex_case(ev, 'long_jump', lambda fs: (P['long_jump_velocity'], None), end=200, ref='apex_long_jump_m', g=P['long_jump_gravity'])

    def an(rows, out):
        res = an0(rows, out)
        m = out.get('metrics', {})
        i, _ = air_segment(rows, 'long_jump')
        if i is not None:
            exp_fs = min(rows[i - 1]['fs'] * P['long_jump_speed_mult'], P['long_jump_max_speed'])
            res.append(check('long jump launch speed (m/s)', rows[i]['fs'], exp_fs, 0.03))
            m['launch_speed'] = rows[i]['fs']
            if m.get('distance_m') is not None and rows[i - 1]['fs'] >= 7.4:
                res.append(ref_check('long jump distance from full run (m)', m['distance_m'], 'long_jump_distance_m', 0.08))
        return res
    return rep, an


def case_backflip():
    ev = [{'f': 10, 'hold': 'crouch', 'frames': 40}, {'f': 20, 'hold': 'jump', 'frames': 40}]
    rep, an0 = _apex_case(ev, 'backflip', lambda fs: (P['backflip_velocity'], None), ref='apex_backflip_m')

    def an(rows, out):
        res = an0(rows, out)
        i, j = air_segment(rows, 'backflip')
        if i is not None and j is not None:
            back = rows[j]['p'][0] - rows[i - 1]['p'][0]   # facing +X, so backwards is -X
            out['metrics']['backward_distance_m'] = -back
            res.append(flag('backflip moves backwards', back < -0.5, '%.2f m' % back))
        return res
    return rep, an


def case_side_flip():
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 90, 'stick': [-1, 0]}, {'f': 93, 'tap': 'jump'}]
    rep, an0 = _apex_case(ev, 'side_flip', lambda fs: (P['side_flip_velocity'], None), end=200)

    def an(rows, out):
        res = an0(rows, out)
        res.append(flag('skid before side flip', 'skid' in states(rows), ' > '.join(states(rows))))
        return res
    return rep, an


def case_wall_kick():
    ev = [{'f': 0, 'stick': [-1, 0]}, {'f': 4, 'hold': 'jump', 'frames': 14}]
    for k in range(1, 7):
        ev.append({'on': 'state:wall_slide', 'nth': k, 'delay': 1, 'hold': 'jump', 'frames': 14})
        ev.append({'on': 'jump:wall_kick', 'nth': k, 'delay': 0, 'stick': [1, 0] if k % 2 else [-1, 0]})
    rep = {'start': {'pos': [-19.75, 0.0, -12.0], 'yaw_deg': 90}, 'end_frame': 330, 'events': ev}

    def an(rows, out):
        kicks = [i for i in range(1, len(rows)) if rows[i]['s'] == 'wall_kick' and rows[i - 1]['s'] != 'wall_kick']
        heights = [rows[i - 1]['p'][1] for i in kicks]
        apexes = []
        for n, i in enumerate(kicks):
            end = kicks[n + 1] if n + 1 < len(kicks) else len(rows)
            apexes.append(max(r['p'][1] for r in rows[i:end]))
        gains = [apexes[n] - heights[n] for n in range(len(kicks))]
        top_i = max(range(len(rows)), key=lambda i: rows[i]['p'][1])
        xin = [r['p'][0] for r in rows[:top_i] if r['p'][1] < 13.5 and -14.0 < r['p'][2] < -10.0]
        minx, maxx = (min(xin), max(xin)) if xin else (None, None)
        out['metrics'] = {'kicks': len(kicks), 'kick_heights_m': [round(h, 3) for h in heights],
                          'apex_after_kick_m': [round(a, 3) for a in apexes], 'gain_per_kick_m': [round(g, 3) for g in gains],
                          'max_height_m': max(r['p'][1] for r in rows), 'x_range_inside': [minx, maxx]}
        res = [flag('at least 4 chained wall kicks', len(kicks) >= 4, '%d kicks' % len(kicks))]
        if gains:
            exp = sim_jump(P['wall_kick_velocity'])
            res.append(check('rise after a kick (m), free apex bound', max(gains), exp, 0.35))
        if minx is not None:
            res.append(flag('no wall penetration', minx >= -21.0 + 0.30 and maxx <= -18.5 - 0.30, 'x %.3f..%.3f' % (minx, maxx)))
        return res
    return rep, an


def case_ham_slam():
    ev = [{'f': 10, 'hold': 'jump', 'frames': 40}, {'on': 'jump:jump', 'nth': 1, 'delay': 18, 'tap': 'crouch'}]
    rep = {'start': {'pos': OPEN, 'yaw_deg': -90}, 'end_frame': 160, 'events': ev}

    def an(rows, out):
        seg = [r for r in rows if r['s'] == 'ham_slam']
        hover = sum(1 for r in seg if r['v'][1] >= -1e-3) * DT
        drops = [-r['v'][1] for r in seg if r['v'][1] < -1e-3]
        first_drop = drops[0] if drops else None
        rise = (max(r['p'][1] for r in seg) - seg[0]['p'][1]) if seg else None
        seq = states(rows)
        out['metrics'] = {'hover_s': hover, 'rise_m': rise, 'first_drop_speed': first_drop, 'max_drop_speed': max(drops) if drops else None, 'states': seq}
        return [check('slam hover (s)', hover, P['slam_spin_time'], 0.08), check('slam first drop speed (m/s)', first_drop, P['slam_drop_speed'], 0.05),
                ref_check('slam hover (s)', hover, 'slam_hover_s', 0.08), check('slam hover rise (m)', rise, 0.86, 0.12),
                flag('slam lands into slam_land', 'slam_land' in seq, ' > '.join(seq))]
    return rep, an


def case_dive_slide():
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 90, 'tap': 'attack'}, {'on': 'state:belly_slide', 'nth': 1, 'delay': 30, 'tap': 'jump'}]
    rep = {'start': {'pos': OPEN, 'yaw_deg': -90}, 'end_frame': 220, 'events': ev}

    def an(rows, out):
        i = first_idx(rows, lambda r: r['s'] == 'dive')
        seq = states(rows)
        fs = rows[i]['fs'] if i is not None else None
        exp = min(rows[i - 1]['fs'] + P['dive_boost'], P['dive_max_speed']) if i else None
        out['metrics'] = {'dive_speed': fs, 'states': seq}
        return [check('dive speed (m/s)', fs, exp, 0.02),
                flag('dive > belly_slide > rollout', 'belly_slide' in seq and 'rollout' in seq, ' > '.join(seq))]
    return rep, an


def _end_y_case(start, yaw, stick, frames, exp_y, tol, name, forbid=(), release=None):
    ev = [{'f': 0, 'stick': stick}]
    if release:
        ev.append({'f': release, 'stick': [0, 0]})
    rep = {'start': {'pos': start, 'yaw_deg': yaw}, 'end_frame': frames, 'events': ev}

    def an(rows, out):
        y = rows[-1]['p'][1]
        seq = states(rows)
        flips = sum(1 for a, b in zip(rows, rows[1:]) if a['g'] != b['g'])
        out['metrics'] = {'end_y': y, 'max_y': max(r['p'][1] for r in rows), 'ground_flips': flips, 'states': seq}
        res = [check(name, y, exp_y, tol, rel=False)]
        for s in forbid:
            res.append(flag('no %s' % s, s not in seq, ' > '.join(seq)))
        return res
    return rep, an


def case_step_03():
    return _end_y_case([13.25, 0.0, -3.0], 0, [0, 1], 110, 0.3, 0.03, 'auto step-up onto 0.3 m (end y)', ('jump', 'fall'), release=62)


def case_step_06_blocked():
    return _end_y_case([16.25, 0.0, -3.0], 0, [0, 1], 110, 0.0, 0.03, '0.6 m block is not auto-stepped (end y)', release=62)


def case_stairs():
    rep, an0 = _end_y_case([14.0, 0.0, -11.0], 0, [0, 0.77], 230, 2.5, 0.05, 'stairs climbed (end y)', ('jump', 'fall'), release=165)

    def an(rows, out):
        res = an0(rows, out)
        res.append(flag('no ground flicker on stairs', out['metrics']['ground_flips'] <= 2, '%d flips' % out['metrics']['ground_flips']))
        return res
    return rep, an


def case_slope_30():
    rep = {'start': {'pos': [29.0, 0.0, -11.0], 'yaw_deg': 0}, 'end_frame': 200, 'events': [{'f': 0, 'stick': [0, 1]}]}

    def an(rows, out):
        top = first_idx(rows, lambda r: r['p'][1] >= 2.95)
        before = rows[:top] if top is not None else rows
        seq = states(before)
        out['metrics'] = {'reached_top_frame': top, 'states_until_top': seq}
        return [flag('walks up the 30 deg slope to the 3 m top', top is not None and seq == ['walk'], ' > '.join(seq))]
    return rep, an


def case_slope_50():
    rep = {'start': {'pos': [36.0, 0.0, -11.0], 'yaw_deg': 0}, 'end_frame': 200, 'events': [{'f': 0, 'stick': [0, 1]}]}

    def an(rows, out):
        seq = states(rows)
        my = max(r['p'][1] for r in rows)
        out['metrics'] = {'max_y': my, 'states': seq}
        return [flag('50 deg slope not climbable', my < 2.0, 'max y %.2f' % my), flag('slides on 50 deg', 'slope_slide' in seq, ' > '.join(seq))]
    return rep, an


def case_ledge_grab_climb():
    ev = [{'f': 0, 'stick': [0, 1]}, {'f': 12, 'hold': 'jump', 'frames': 30}, {'on': 'state:ledge_climb', 'nth': 1, 'delay': 0, 'stick': [0, 0]}]
    rep = {'start': {'pos': [25.25, 0.0, -3.4], 'yaw_deg': 0}, 'end_frame': 200, 'events': ev}

    def an(rows, out):
        seq = states(rows)
        y = rows[-1]['p'][1]
        out['metrics'] = {'end_y': y, 'states': seq}
        after = seq[seq.index('ledge_climb') + 1:] if 'ledge_climb' in seq else []
        return [flag('ledge grabbed', 'ledge_hang' in seq, ' > '.join(seq)), flag('climbed', 'ledge_climb' in seq),
                check('stands on the 2.0 m ledge (end y)', y, 2.0, 0.05, rel=False),
                flag('no fall state after the climb (fix r1)', 'fall' not in after[:2], ' > '.join(after[:3]))]
    return rep, an


def case_ledge_blocked():
    ev = [{'f': 0, 'stick': [0, 1]}, {'f': 12, 'hold': 'jump', 'frames': 30}]
    rep = {'start': {'pos': [44.0, 0.0, -3.4], 'yaw_deg': 0}, 'end_frame': 150, 'events': ev}

    def an(rows, out):
        seq = states(rows)
        out['metrics'] = {'states': seq}
        return [flag('no grab under blocked headroom', 'ledge_hang' not in seq, ' > '.join(seq))]
    return rep, an


def case_low_ceiling():
    ev = [{'f': 5, 'hold': 'jump', 'frames': 30}]
    rep = {'start': {'pos': [-4.5, 0.0, -8.0], 'yaw_deg': 0}, 'end_frame': 90, 'events': ev}

    def an(rows, out):
        my = max(r['p'][1] for r in rows)
        out['metrics'] = {'max_y': my}
        return [flag('head bonks the 2.0 m ceiling', my <= 2.0 - 1.25 + 0.03, 'max feet y %.3f' % my)]
    return rep, an


def case_crawl():
    ev = [{'f': 2, 'press': 'crouch'}, {'f': 8, 'stick': [0, 1]}, {'f': 230, 'release': 'crouch'}]
    rep = {'start': {'pos': [-4.5, 0.0, -8.6], 'yaw_deg': 0}, 'end_frame': 300, 'events': ev}

    def an(rows, out):
        z = rows[-1]['p'][2]
        seq = states(rows)
        out['metrics'] = {'end_z': z, 'states': seq}
        return [flag('crawls through the 1.0 m tunnel', z < -14.3, 'end z %.2f' % z), flag('stands up after', rows[-1]['s'] in ('walk', 'idle'), rows[-1]['s'])]
    return rep, an


def case_pole():
    ev = [{'f': 0, 'stick': [0, 1]}, {'f': 6, 'hold': 'jump', 'frames': 20}, {'on': 'state:pole_climb', 'nth': 1, 'delay': 100, 'tap': 'jump'}]
    rep = {'start': {'pos': [48.0, 0.0, 6.6], 'yaw_deg': 0}, 'end_frame': 220, 'events': ev}

    def an(rows, out):
        seq = states(rows)
        seg = [r for r in rows if r['s'] == 'pole_climb']
        climbed = (max(r['p'][1] for r in seg) - seg[0]['p'][1]) if seg else None
        out['metrics'] = {'climbed_m': climbed, 'states': seq}
        return [flag('grabs the pole', bool(seg), ' > '.join(seq)), check('climb speed x time (m)', climbed, P['climb_up_speed'] * 100 * DT, 0.15),
                flag('jumps off the pole', 'jump' in seq[seq.index('pole_climb'):] if 'pole_climb' in seq else False)]
    return rep, an


def case_bounce_pad():
    ev = [{'f': 0, 'stick': [0, 1]}, {'f': 4, 'hold': 'jump', 'frames': 15}, {'f': 30, 'stick': [0, 0]}]
    rep = {'start': {'pos': [56.0, 0.0, 8.0], 'yaw_deg': 0}, 'end_frame': 200, 'events': ev}

    def an(rows, out):
        i = first_idx(rows, lambda r: r['s'] == 'bounce')
        seq = states(rows)
        if i is None:
            out['metrics'] = {'states': seq}
            return [flag('bounced', False, ' > '.join(seq))]
        y0 = rows[i - 1]['p'][1]
        apex = max(r['p'][1] for r in rows[i:]) - y0
        out['metrics'] = {'bounce_apex_m': apex, 'states': seq}
        return [check('bounce apex (m)', apex, sim_jump(17.0), 0.04)]
    return rep, an


def case_punch_combo():
    ev = [{'f': 10, 'tap': 'attack'}, {'f': 20, 'tap': 'attack'}, {'f': 30, 'tap': 'attack'}]
    rep = {'start': {'pos': [-6.0, 0.0, 4.6], 'yaw_deg': 0}, 'end_frame': 90, 'events': ev}

    def an(rows, out, log=''):
        hits = re.findall(r'dummy DummyA hit by (\w+)', log)
        out['metrics'] = {'hits': hits}
        return [flag('jab, jab, kick hit the dummy', hits[:3] == ['punch', 'punch', 'kick'], ','.join(hits))]
    return rep, an


def case_stomp():
    rep = {'start': {'pos': [-6.0, 3.0, 3.0], 'yaw_deg': 0}, 'end_frame': 90, 'events': []}

    def an(rows, out, log=''):
        hits = re.findall(r'dummy DummyA hit by (\w+)', log)
        seq = states(rows)
        out['metrics'] = {'hits': hits, 'states': seq}
        return [flag('stomp calls hit_by_player("stomp")', 'stomp' in hits, ','.join(hits)), flag('stomp bounces', 'bounce' in seq, ' > '.join(seq))]
    return rep, an


def case_slam_dummy():
    rep = {'start': {'pos': [-8.0, 3.5, 3.0], 'yaw_deg': 0}, 'end_frame': 100, 'events': [{'f': 4, 'tap': 'crouch'}]}

    def an(rows, out, log=''):
        hits = re.findall(r'dummy DummyB hit by (\w+)', log)
        out['metrics'] = {'hits': hits}
        return [flag('Ham Slam hits as "slam"', 'slam' in hits, ','.join(hits))]
    return rep, an


def case_kill_plane():
    rep = {'start': {'pos': [68.0, 0.0, 20.0], 'yaw_deg': -90}, 'end_frame': 300, 'events': [{'f': 0, 'stick': [1, 0]}, {'f': 80, 'stick': [0, 0]}]}

    def an(rows, out):
        seq = states(rows)
        out['metrics'] = {'states': seq, 'end_pos': rows[-1]['p']}
        miny = min(r['p'][1] for r in rows)
        out['metrics']['min_y'] = miny
        return [flag('falls below kill_y and is respawned', miny < -20.0 and rows[-1]['p'][1] > -1.0 and rows[-1]['g'], 'min y %.1f, end %s' % (miny, rows[-1]['p']))]
    return rep, an


def case_moving_platform():
    rep = {'start': {'pos': [53.0, 2.4, -8.0], 'yaw_deg': 0}, 'end_frame': 300, 'events': []}

    def an(rows, out):
        ride = rows[40:]
        xs = [r['p'][0] for r in ride]
        ys = [r['p'][1] for r in ride]
        seq = states(ride)
        out['metrics'] = {'x_span_m': max(xs) - min(xs), 'y_range': [min(ys), max(ys)], 'states': seq}
        return [flag('rides the moving platform (x span > 6 m)', max(xs) - min(xs) > 6.0, '%.2f m' % (max(xs) - min(xs))),
                flag('stays on it, no fall or flicker', min(ys) > 1.7 and seq == ['idle'], 'y %.3f..%.3f, %s' % (min(ys), max(ys), ' > '.join(seq)))]
    return rep, an


def case_rotating_platform():
    rep = {'start': {'pos': [54.5, 1.6, -21.0], 'yaw_deg': 0}, 'end_frame': 300, 'events': []}

    def an(rows, out):
        ride = rows[40:]
        ang = [math.degrees(math.atan2(r['p'][2] + 21.0, r['p'][0] - 52.0)) for r in ride]
        rad = [math.hypot(r['p'][0] - 52.0, r['p'][2] + 21.0) for r in ride]
        turned = abs(ang[-1] - ang[0])
        seq = states(ride)
        out['metrics'] = {'turned_deg': turned, 'radius_range': [min(rad), max(rad)], 'states': seq}
        exp = 35.0 * (len(ride)) / 60.0
        return [check('carried around by the disc (deg)', turned, exp, 0.1),
                flag('stays on the disc without drift', max(rad) - min(rad) < 0.15 and seq == ['idle'], 'r %.3f..%.3f, %s' % (min(rad), max(rad), ' > '.join(seq)))]
    return rep, an


def case_consistency():
    return case_jump_run_full()


def case_wall_bonk():
    # Long jump at full speed into the BonkWall: head-on contact above wall_bonk_speed knocks Mak back.
    ev = [{'f': 0, 'stick': [0, -1]}, {'f': 95, 'hold': 'crouch', 'frames': 6}, {'f': 96, 'hold': 'jump', 'frames': 30}]
    rep = {'start': {'pos': [-14.0, 0.0, 13.0], 'yaw_deg': 180}, 'end_frame': 240, 'events': ev}

    def an(rows, out):
        seq = states(rows)
        maxz = max(r['p'][2] for r in rows)
        out['metrics'] = {'states': seq, 'max_z': maxz}
        return [flag('long jump into the wall bonks', 'bonk' in seq, ' > '.join(seq)),
                flag('knocked down after the bonk', 'hurt_land' in seq),
                flag('no wall penetration', maxz <= 26.5 - 0.35 + 0.02, 'max z %.3f' % maxz)]
    return rep, an


def case_ledge_opt_out():
    # The ledge_grab_climb jump, but every lab body is in group no_ledge_grab (builders' opt-out): no hang.
    rep, _ = case_ledge_grab_climb()
    rep = dict(rep, end_frame=150, args=['--lab-no-ledge-grab'])

    def an(rows, out):
        seq = states(rows)
        out['metrics'] = {'states': seq}
        return [flag('no grab on a no_ledge_grab body', 'ledge_hang' not in seq, ' > '.join(seq))]
    return rep, an


def case_cocoa_splash():
    # Running into a hot-chocolate HazardVolume: one cocoa splash feedback event on entry (plus the hazard hurt).
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 150, 'stick': [0, 0]}]
    rep = {'start': {'pos': [-20.0, 0.0, 20.0], 'yaw_deg': -90}, 'end_frame': 170, 'events': ev,
           'args': ['--lab-cocoa', '--fb-log']}

    def an(rows, out, log):
        seq = states(rows)
        n = log.count('feedback world_cocoa_splash')
        out['metrics'] = {'states': seq, 'cocoa_splash_events': n}
        return [flag('cocoa splash on entering hot chocolate', n >= 1, 'events %d' % n),
                flag('hurt by the hot chocolate', 'hurt_air' in seq, ' > '.join(seq))]
    return rep, an


def case_crate_no_ground_hang():
    # Spawned 0.6 m from a 1 m crate: a jump forward lands on top, never a ground-level ledge hang.
    ev = [{'f': 0, 'stick': [0, 1]}, {'f': 2, 'hold': 'jump', 'frames': 30}, {'on': 'land', 'nth': 1, 'delay': 0, 'stick': [0, 0]}]
    rep = {'start': {'pos': [19.25, 0.0, -5.4], 'yaw_deg': 0}, 'end_frame': 120, 'events': ev}

    def an(rows, out):
        seq = states(rows)
        y = rows[-1]['p'][1]
        out['metrics'] = {'states': seq, 'end_y': y}
        return [flag('no ledge hang on a 1 m crate from the ground', 'ledge_hang' not in seq, ' > '.join(seq)),
                check('ends on top of the crate (end y)', y, 1.0, 0.05, rel=False)]
    return rep, an


def _hurt_case(start_x, yaw, behind):
    # REA round 2: Mak starts inside the lab hot chocolate (centre x -12) with the centre in front of him (front
    # hit) or behind him (back hit) and no stick input.
    rep = {'start': {'pos': [start_x, 0.0, 20.0], 'yaw_deg': yaw}, 'end_frame': 150, 'events': [], 'args': ['--lab-cocoa']}

    def an(rows, out):
        seq = states(rows)
        i = first_idx(rows, lambda r: r['s'] == 'hurt_air')
        if i is None:
            return [flag('hurt by the hot chocolate', False, ' > '.join(seq))]
        land = first_idx(rows, lambda r: r['s'] == 'hurt_land', i)
        end = first_idx(rows, lambda r: r['s'] not in ('hurt_air', 'hurt_land'), i)
        air = [hs(r) for r in rows[i + 1:land]] if land else []
        away = rows[i + 1]['v'][0] - 0.0
        res = []
        if behind:
            res.append(flag('hit from behind: thrown forwards, away from the source', rows[i]['fs'] > 0 and away < -1.0,
                            'fs %.2f vx %.2f' % (rows[i]['fs'], away)))
        else:
            res.append(flag('hit from the front: thrown backwards, away from the source', rows[i]['fs'] < 0 and away > 1.0,
                            'fs %.2f vx %.2f' % (rows[i]['fs'], away)))
        res.append(ref_check('air knockback speed held (m/s)', sum(air) / max(len(air), 1), 'knockback_speed_mps', 0.02))
        res.append(flag('air knockback speed constant', bool(air) and max(air) - min(air) < 0.05,
                        '%.3f..%.3f' % (min(air), max(air)) if air else 'no air rows'))
        if land is not None and land + 2 < len(rows) and abs(rows[land]['fs']) > 0.5:
            ratio = abs(rows[land + 2]['fs']) / abs(rows[land]['fs'])
            res.append(ref_check('ground knockback keeps per reference frame', ratio, 'knockback_ground_keep', 0.01))
        if end is not None and land is not None:
            t_air = (land - i) * DT
            dur = (end - i) * DT
            exp = max(P['hurt_time_soft'], t_air + 0.2)
            res.append(check('hurt state, hit to standing (s)', dur, exp, 2.5 * DT, rel=False))
            res.append(ref_check('invulnerable after the hurt state (s)', rows[end]['inv'], 'post_hurt_invuln_s', 0.03))
        out['metrics'] = {'states': seq, 'air_speed': air[:3], 'hurt_rows': (i, land, end)}
        res.append(flag('only one hit while invulnerable', seq.count('hurt_air') == 1, ' > '.join(seq)))
        return res
    return rep, an


def case_hurt_front():
    return _hurt_case(-11.4, 90, False)


def case_hurt_back():
    return _hurt_case(-12.6, 90, True)


def case_punch_windows():
    # REA round 2: one jab in the open (lunge and length), then a buffered second press inside the strike phase.
    ev = [{'f': 10, 'tap': 'attack'}, {'f': 80, 'tap': 'attack'}, {'f': 84, 'tap': 'attack'}]
    rep = {'start': {'pos': OPEN, 'yaw_deg': -90}, 'end_frame': 150, 'events': ev}

    def an(rows, out):
        i0 = first_idx(rows, lambda r: r['s'] == 'punch')
        e0 = first_idx(rows, lambda r: r['s'] != 'punch', i0) if i0 is not None else None
        if i0 is None or e0 is None:
            return [flag('jab happened', False, ' > '.join(states(rows)))]
        lunge = math.hypot(rows[e0]['p'][0] - rows[i0 - 1]['p'][0], rows[e0]['p'][2] - rows[i0 - 1]['p'][2])
        i1 = first_idx(rows, lambda r: r['s'] == 'punch', e0)
        rise = None
        if i1 is not None:
            for k in range(i1 + 1, min(i1 + 40, len(rows))):
                if rows[k]['fs'] > 2.0 and rows[k - 1]['fs'] < 1.0:
                    rise = k
                    break
        out['metrics'] = {'jab_rows': e0 - i0, 'lunge_m': lunge, 'second_strike_after_rows': (rise - i1) if rise else None}
        return [ref_check('jab alone, length (s)', (e0 - i0) * DT, 'jab_total_s', 0.05),
                ref_check('jab lunge distance (m)', lunge, 'punch_lunge_m', 0.08),
                ref_check('buffered second jab starts after the strike phase (s)', (rise - i1) * DT if rise else None,
                          'jab_strike_s', 0.13)]
    return rep, an


def case_slope_slide_jump():
    # REA round 2: a jump pressed 2 frames into a slope slide is held until the slide is 5 reference frames old.
    ev = [{'f': 0, 'stick': [0, 1]}, {'on': 'state:slope_slide', 'nth': 1, 'delay': 2, 'tap': 'jump'}]
    rep = {'start': {'pos': [36.0, 0.0, -11.0], 'yaw_deg': 0}, 'end_frame': 200, 'events': ev}

    def an(rows, out):
        i = first_idx(rows, lambda r: r['s'] == 'slope_slide')
        j = first_idx(rows, lambda r: r['s'] == 'jump', i) if i is not None else None
        out['metrics'] = {'slide_row': i, 'jump_row': j, 'states': states(rows)}
        return [ref_check('slide jump delay (s)', (j - i) * DT if j is not None else None, 'slide_jump_delay_s', 0.12),
                ref_check('slide threshold in the profile (deg)', P['steep_slope_angle'], 'slide_threshold_deg', 0.001)]
    return rep, an


# ------------------------------------------------------------------ D039 air control and landing stop (owner request)
# Start facing +X (yaw -90); world steering: stick [1, 0] = +X (forward), [0, 1] = sideways (-Z).

def _land_slide(rows, kind):
    """(slide distance after touchdown, final state, landing index) for the first `kind` air phase."""
    i, j = air_segment(rows, kind)
    if j is None:
        return None, None, None
    stop = first_idx(rows, lambda r: hs(r) < 0.01, j)
    end = rows[stop] if stop is not None else rows[-1]
    d = math.hypot(end['p'][0] - rows[j]['p'][0], end['p'][2] - rows[j]['p'][2])
    return d, end['s'], j


def case_air_strafe_stand():
    """Standing jump with the stick pushed sideways after takeoff: lateral correction over one normal jump."""
    ev = [{'f': 10, 'press': 'jump'}, {'f': 12, 'stick': [0, 1]}, {'f': 70, 'release': 'jump'},
          {'on': 'land', 'nth': 1, 'delay': 0, 'stick': [0, 0]}]
    rep = {'start': {'pos': OPEN, 'yaw_deg': -90}, 'end_frame': 140, 'events': ev}

    def an(rows, out):
        i, j = air_segment(rows, 'jump')
        if j is None:
            return [flag('jump landed', False, ' > '.join(states(rows)))]
        lat = abs(rows[j]['p'][2] - rows[i - 1]['p'][2])
        fwd = abs(rows[j]['p'][0] - rows[i - 1]['p'][0])
        lv = [abs(r['v'][2]) for r in rows[i:j]]
        slide, end_s, _ = _land_slide(rows, 'jump')
        out['metrics'] = {'lateral_m': lat, 'forward_m': fwd, 'airtime_s': (j - i + 1) * DT,
                          'lateral_speed_first': lv[:4], 'lateral_speed_max': max(lv), 'slide_after_land_m': slide}
        return [flag('D039: full side stick corrects a standing jump by at least 1.0 m', lat >= 1.0, '%.3f m' % lat),
                flag('D039: no landing slide with the stick released', slide is not None and slide <= 0.1, '%s m, %s' % (slide, end_s))]
    return rep, an


def case_air_pullback_run():
    """Running jump, stick pulled back right after takeoff: air braking."""
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 90, 'press': 'jump'}, {'f': 93, 'stick': [-1, 0]}, {'f': 140, 'release': 'jump'},
          {'on': 'land', 'nth': 1, 'delay': 0, 'stick': [0, 0]}]
    rep = {'start': {'pos': OPEN, 'yaw_deg': -90}, 'end_frame': 220, 'events': ev}

    def an(rows, out):
        i, j = air_segment(rows, 'jump')
        if j is None:
            return [flag('jump landed', False, ' > '.join(states(rows)))]
        dist = rows[j]['p'][0] - rows[i - 1]['p'][0]
        fs = [round(r['fs'], 3) for r in rows[i:j]]
        slide, end_s, _ = _land_slide(rows, 'jump')
        out['metrics'] = {'distance_m': dist, 'fs_first': fs[:8], 'fs_land': fs[-1] if fs else None, 'slide_after_land_m': slide}
        return [flag('pulling back shortens a 6 m/s running jump below 2.5 m', dist < 2.5, '%.3f m' % dist),
                flag('D039: no landing slide with the stick released', slide is not None and slide <= 0.1, '%s m, %s' % (slide, end_s))]
    return rep, an


def case_land_stop_run():
    """Full-speed running jump, stick released in the air: Mak stops on touchdown (owner: no slide after landing)."""
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 90, 'press': 'jump'}, {'f': 100, 'stick': [0, 0]}, {'f': 140, 'release': 'jump'}]
    rep = {'start': {'pos': OPEN, 'yaw_deg': -90}, 'end_frame': 220, 'events': ev}

    def an(rows, out):
        slide, end_s, j = _land_slide(rows, 'jump')
        out['metrics'] = {'slide_after_land_m': slide, 'end_state': end_s,
                          'land_speed': hs(rows[j - 1]) if j else None}
        return [flag('D039: slide after a running-jump landing with no stick <= 0.35 m', slide is not None and slide <= 0.35,
                     '%s m' % (None if slide is None else round(slide, 3))),
                flag('ends standing', end_s == 'idle', str(end_s))]
    return rep, an


def case_land_stop_long():
    """Full-speed long jump, stick released in the air: a short skid only."""
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 90, 'hold': 'crouch', 'frames': 6}, {'f': 91, 'hold': 'jump', 'frames': 30},
          {'f': 100, 'stick': [0, 0]}]
    rep = {'start': {'pos': OPEN, 'yaw_deg': -90}, 'end_frame': 240, 'events': ev}

    def an(rows, out):
        slide, end_s, j = _land_slide(rows, 'long_jump')
        out['metrics'] = {'slide_after_land_m': slide, 'end_state': end_s,
                          'land_speed': hs(rows[j - 1]) if j else None}
        return [flag('D039: long-jump landing skid with no stick <= 1.5 m', slide is not None and slide <= 1.5,
                     '%s m' % (None if slide is None else round(slide, 3)))]
    return rep, an


CASES = {
    'air_strafe_stand': case_air_strafe_stand,
    'air_pullback_run': case_air_pullback_run,
    'land_stop_run': case_land_stop_run,
    'land_stop_long': case_land_stop_long,
    'wall_bonk': case_wall_bonk,
    'hurt_front': case_hurt_front,
    'hurt_back': case_hurt_back,
    'punch_windows': case_punch_windows,
    'slope_slide_jump': case_slope_slide_jump,
    'crate_no_ground_hang': case_crate_no_ground_hang,
    'run_accel_stop': case_run_accel_stop,
    'jump_stand_full': case_jump_stand_full,
    'jump_stand_tap': case_jump_stand_tap,
    'jump_run_full': case_jump_run_full,
    'double_jump': case_double_jump,
    'triple_jump': case_triple_jump,
    'chain_late': case_chain_late,
    'long_jump': case_long_jump,
    'backflip': case_backflip,
    'side_flip': case_side_flip,
    'wall_kick': case_wall_kick,
    'ham_slam': case_ham_slam,
    'dive_slide': case_dive_slide,
    'step_03': case_step_03,
    'step_06_blocked': case_step_06_blocked,
    'stairs': case_stairs,
    'slope_30': case_slope_30,
    'slope_50': case_slope_50,
    'ledge_grab_climb': case_ledge_grab_climb,
    'ledge_blocked': case_ledge_blocked,
    'ledge_opt_out': case_ledge_opt_out,
    'cocoa_splash': case_cocoa_splash,
    'low_ceiling': case_low_ceiling,
    'crawl': case_crawl,
    'pole': case_pole,
    'bounce_pad': case_bounce_pad,
    'punch_combo': case_punch_combo,
    'stomp': case_stomp,
    'slam_dummy': case_slam_dummy,
    'kill_plane': case_kill_plane,
    'moving_platform': case_moving_platform,
    'rotating_platform': case_rotating_platform,
}
# Run-to-run and render-rate consistency: the same replay at 30/60/120 render fps and twice at 60.
CONSISTENCY = [('jump_run_full', 30), ('jump_run_full', 120), ('jump_run_full', 60), ('run_accel_stop', 30)]


def run_case(name, fps=60, tag=''):
    rep, an = CASES[name]()
    rep = dict(rep)
    rep['fps'] = 60
    rep.setdefault('steer', 'world')
    key = name + (tag or '')
    rp = REPLAYS / (key + '.json')
    tp = TRACES / (key + '.jsonl')
    rp.write_text(json.dumps(rep, indent=1), encoding='utf-8')
    if tp.exists():
        tp.unlink()
    secs = rep['end_frame'] / 60.0 * (60.0 / fps) + 25
    cmd = [sys.executable, str(GODOT_PY), 'run', SCENE, '--seconds', str(round(secs, 1)), '--headless', '--no-import', '--',
           '--replay=' + rp.as_posix(), '--trace=' + tp.as_posix(), '--profile=player-tests', '--render-fps=%d' % fps]         + list(rep.pop('args', []))
    log = ''
    for attempt in range(2):   # a parallel cold start occasionally dies before the scene loads; retry once
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=secs + 900)  # includes waiting for a shared Godot slot (tools/godot.py caps 3 runs)
        log = proc.stdout + proc.stderr
        if tp.exists():
            break
    out = {'case': key, 'render_fps': fps, 'replay': rp.relative_to(ENTITY).as_posix(), 'trace': tp.relative_to(ENTITY).as_posix()}
    errs = [l for l in log.splitlines() if 'SCRIPT ERROR' in l or 'Parse Error' in l]
    if errs:
        out['script_errors'] = errs[:10]
    if not tp.exists():
        out['checks'] = [flag('trace written', False, log[-800:])]
        return out
    meta, rows = read_trace(tp)
    if not rows:
        out['checks'] = [flag('trace has rows', False)]
        return out
    try:
        if an.__code__.co_argcount == 3:
            out['checks'] = an(rows, out, log)
        else:
            out['checks'] = an(rows, out)
    except Exception as e:  # analysis bug: report, do not hide
        out['checks'] = [flag('analysis ran', False, repr(e))]
    out['rows'] = len(rows)
    return out


def compare_traces(a, b):
    _, ra = read_trace(ENTITY / a)
    _, rb = read_trace(ENTITY / b)
    n = min(len(ra), len(rb))
    md = 0.0
    for i in range(n):
        for k in range(3):
            md = max(md, abs(ra[i]['p'][k] - rb[i]['p'][k]))
    same_states = all(ra[i]['s'] == rb[i]['s'] for i in range(n))
    return md, same_states, n


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    workers = 1   # TECH_CONTRACT "Machine limits": never launch several Godot processes in parallel from a script
    if '--workers' in sys.argv:
        workers = int(sys.argv[sys.argv.index('--workers') + 1])
        if str(workers) in args:
            args.remove(str(workers))
    names = args or list(CASES)
    for d in (REPLAYS, RESULTS, TRACES):
        d.mkdir(parents=True, exist_ok=True)
    jobs = [(n, 60, '') for n in names]
    if not args:
        jobs += [(n, f, '__fps%d_%d' % (f, i)) for i, (n, f) in enumerate(CONSISTENCY)]
    started = _dt.datetime.now(_dt.timezone.utc)
    results = []
    with cf.ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {ex.submit(run_case, n, f, t): (n, f, t) for n, f, t in jobs}
        for fut in cf.as_completed(futs):
            r = fut.result()
            results.append(r)
            ok = all(c['pass'] for c in r.get('checks', []))
            print('%-34s %s' % (r['case'], 'PASS' if ok else 'FAIL'), flush=True)
    results.sort(key=lambda r: r['case'])
    consistency = []
    if not args:
        base = {'jump_run_full': 'game/tests/results/traces/jump_run_full.jsonl', 'run_accel_stop': 'game/tests/results/traces/run_accel_stop.jsonl'}
        for i, (n, f) in enumerate(CONSISTENCY):
            other = 'game/tests/results/traces/%s__fps%d_%d.jsonl' % (n, f, i)
            try:
                md, same, cnt = compare_traces(base[n], other)
                consistency.append({'case': n, 'render_fps': f, 'frames': cnt, 'max_position_diff_m': md, 'same_states': same,
                                    'pass': md < 0.002 and same})
            except Exception as e:
                consistency.append({'case': n, 'render_fps': f, 'error': repr(e), 'pass': False})
    total = sum(len(r.get('checks', [])) for r in results)
    passed = sum(1 for r in results for c in r.get('checks', []) if c['pass'])
    report = {'generated_utc': started.strftime('%Y-%m-%dT%H:%M:%SZ'), 'engine': 'Godot 4.7 (headless, 60 Hz physics)',
              'profile_file': 'game/scenes/player/mak_profile.tres', 'profile': P,
              'expectations': {'standing_apex_m': sim_jump(P['jump_velocity']),
                               'running_apex_m': sim_jump(P['jump_velocity'] + P['jump_speed_bonus'] * P['run_top_speed']),
                               'double_running_apex_m': sim_jump(P['double_jump_velocity'] + P['jump_speed_bonus'] * P['run_top_speed']),
                               'triple_apex_m': sim_jump(P['triple_jump_velocity']), 'backflip_apex_m': sim_jump(P['backflip_velocity']),
                               'long_jump_apex_m': sim_jump(P['long_jump_velocity']), 'wall_kick_apex_m': sim_jump(P['wall_kick_velocity']),
                               'time_to_90pct_s': sim_run()[0], 'time_to_top_s': sim_run()[1], 'stopping_distance_m': sim_run()[2]},
              'summary': {'checks': total, 'passed': passed, 'cases': len(results)},
              'consistency': consistency, 'results': results}
    stamp = started.strftime('%Y%m%dT%H%M%SZ')
    (RESULTS / ('movement_%s.json' % stamp)).write_text(json.dumps(report, indent=1), encoding='utf-8')
    (RESULTS / 'latest.json').write_text(json.dumps(report, indent=1), encoding='utf-8')
    print('\n%d/%d checks passed across %d cases' % (passed, total, len(results)))
    for c in consistency:
        print('consistency %-16s fps %3s  max diff %s m  same states %s  %s' % (c['case'], c['render_fps'], c.get('max_position_diff_m'), c.get('same_states'), 'PASS' if c['pass'] else 'FAIL'))
    for r in results:
        for c in r.get('checks', []):
            if not c['pass']:
                print('  FAIL %-20s %s  measured=%s expected=%s %s' % (r['case'], c['name'], c.get('measured'), c.get('expected'), c.get('detail', '')[:300]))
    print('results:', (RESULTS / ('movement_%s.json' % stamp)).relative_to(ENTITY).as_posix())


if __name__ == '__main__':
    main()

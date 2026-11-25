#!/usr/bin/env python3
"""Hero v2 fix r1: before/after numbers on FeelProbeV2 logs (critic r1 data vs the fix-round data).

python game/tests/critique_hero_v2/fix_r1_compare.py <case> [<case> ...]
Per state: landing spot on screen (in frustum and screen y < 0.9) during airborne frames, and the share of idle/walk
frames where Mak shows his back to the camera (camera-relative yaw of the visual over 100 degrees).
"""
import json, math, sys
from pathlib import Path
E = Path(__file__).resolve().parents[2].parent
BEFORE = E / 'Docs/progress/critique/hero_v2/r1_feel/data'
AFTER = E / ('Docs/progress/hero_v2_fix_r1/feel/' + next((a.split('=',1)[1] for a in sys.argv if a.startswith('--after=')), 'data'))


def load(d, t):
    p = d / (t + '.cam.jsonl')
    return [json.loads(l) for l in p.read_text(encoding='utf-8').splitlines() if l.strip()] if p.exists() else []


def stats(rows):
    out = {}
    for st in ('triple_jump', 'side_flip', 'backflip', 'wall_kick', 'jump', 'double_jump', 'long_jump', 'fall'):
        rs = [r for r in rows if r['s'] == st and 'land' in r]
        if rs:
            ok = sum(1 for r in rs if r['land']['fr'] and r['land']['scr'][1] < 0.9)
            out['land_ok_' + st] = f'{ok}/{len(rs)}'
    for st in ('idle', 'walk'):
        rs = [r for r in rows if r['s'] == st and 'pyaw' in r and 'cyaw' in r]
        if rs:
            back = 0
            for r in rs:
                # Visual facing from the ear tips (right = ear_r - ear_l, forward = up x right), against the camera's
                # yaw: the camera behind him looks along his facing. Includes the idle turn toward the camera.
                el, er = r['b']['ear_l_2'], r['b']['ear_r_2']
                rx, rz = er[0] - el[0], er[2] - el[2]
                fx, fz = rz, -rx            # up x right = (rz, 0, -rx)
                vyaw = math.atan2(-fx, -fz)
                d = math.degrees(abs((vyaw - math.radians(r['cyaw']) + math.pi) % (2 * math.pi) - math.pi))
                back += d < 80.0
            out['back_to_cam_' + st] = round(back / len(rs), 3)
    return out


if __name__ == '__main__':
    for t in [a for a in sys.argv[1:] if not a.startswith('--')]:
        b, a = stats(load(BEFORE, t)), stats(load(AFTER, t))
        print(t)
        for k in sorted(set(b) | set(a)):
            print(f'  {k:28s} before {b.get(k)!s:>10}  after {a.get(k)!s:>10}')

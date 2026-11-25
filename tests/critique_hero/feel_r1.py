#!/usr/bin/env python3
"""HERO critique round 1, lens GAME FEEL AND CAMERA.

Drives the real MakPlayer (Player.tscn) with replays through FeelCamProbeR1 (which instances MoveLab or a world and
logs the gameplay camera) and measures what a player feels: input windows (chain, buffer, wall kick), latency, turn
response, moving platforms, ledge climbs, camera occlusion, camera clipping, landing-spot visibility and camera motion.
Read-only with respect to the HERO track: replays, traces and results go to Docs/progress/critique/hero/r1_feel/data/.

Usage (from anywhere): python game/tests/critique_hero/feel_r1.py [case ...]
"""
import json
import math
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAME = HERE.parent.parent
ENTITY = GAME.parent
OUT = ENTITY / 'Docs' / 'progress' / 'critique' / 'hero' / 'r1_feel' / 'data'
GODOT_PY = ENTITY / 'tools' / 'godot.py'
PROBE = 'res://tests/critique_hero/FeelCamProbeR1.tscn'
LAB = 'res://scenes/tests/MoveLab.tscn'

WALL_FACE_Z = 26.5     # MoveLab BonkWall south face (box centre z 27, depth 1)


def read_jsonl(p, skip_meta=True):
    rows = []
    for line in Path(p).read_text(encoding='utf-8').splitlines():
        if not line.strip():
            continue
        r = json.loads(line)
        if skip_meta and r.get('meta'):
            continue
        rows.append(r)
    return rows


def runs_of(rows, key='s'):
    out = []
    for i, r in enumerate(rows):
        if not out or out[-1][0] != r[key]:
            out.append([r[key], i, i])
        else:
            out[-1][2] = i
    return out


# ------------------------------------------------------------------ replays

def rep_chain_sweep():
    """Single jump, then a second jump pressed d frames after the landing notification. Teleport between cycles."""
    delays = [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 18, 20]
    start = [-5.0, 0.0, 20.0]
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 30, 'hold': 'jump', 'frames': 14}]
    for i, d in enumerate(delays):
        ev.append({'on': 'land', 'nth': 2 * i + 1, 'delay': d, 'hold': 'jump', 'frames': 14, 'mark': 'press_d%d' % d})
        ev.append({'on': 'land', 'nth': 2 * i + 2, 'delay': 20, 'teleport': start, 'yaw_deg': -90})
        if i + 1 < len(delays):
            ev.append({'on': 'land', 'nth': 2 * i + 2, 'delay': 50, 'hold': 'jump', 'frames': 14})
    return {'fps': 60, 'steer': 'world', 'start': {'pos': start, 'yaw_deg': -90}, 'end_frame': 150 * len(delays) + 120,
            'events': ev, '_delays': delays}


def rep_buffer_sweep(airtime_frames):
    """Second jump pressed k frames BEFORE the first jump lands (k = 1..12); the press is held 10 frames."""
    ks = list(range(1, 13))
    start = [-5.0, 0.0, 20.0]
    ev = [{'f': 0, 'stick': [1, 0]}, {'f': 30, 'hold': 'jump', 'frames': 14}]
    for i, k in enumerate(ks):
        ev.append({'on': 'jump:jump', 'nth': i + 1, 'delay': airtime_frames - k, 'hold': 'jump', 'frames': 10,
                   'mark': 'pre_k%d' % k})
        ev.append({'on': 'land', 'nth': None, 'delay': 0})  # placeholder removed below
    ev = [e for e in ev if e.get('nth', 1) is not None]
    # Teleport 70 frames after each first jump's takeoff + airtime (landing count varies by success, so time it from
    # the first jump instead).
    for i, k in enumerate(ks):
        ev.append({'on': 'jump:jump', 'nth': i + 1, 'delay': airtime_frames + 75, 'teleport': start, 'yaw_deg': -90})
        if i + 1 < len(ks):
            ev.append({'on': 'jump:jump', 'nth': i + 1, 'delay': airtime_frames + 105, 'hold': 'jump', 'frames': 14})
    return {'fps': 60, 'steer': 'world', 'start': {'pos': start, 'yaw_deg': -90}, 'end_frame': 190 * len(ks) + 100,
            'events': ev, '_ks': ks}


def rep_wallkick_sweep():
    """Run at the BonkWall, jump, then press jump d frames after entering wall_slide."""
    delays = [0, 1, 2, 3, 4, 6, 8, 10, 12, 13, 14, 15, 16, 18]
    start = [-14.0, 0.0, 20.2]
    ev = [{'f': 0, 'stick': [0, -1]}, {'f': 60, 'hold': 'jump', 'frames': 20}]
    for i, d in enumerate(delays):
        ev.append({'on': 'state:wall_slide', 'nth': i + 1, 'delay': d, 'hold': 'jump', 'frames': 12, 'mark': 'kick_d%d' % d})
        ev.append({'on': 'land', 'nth': i + 1, 'delay': 20, 'teleport': start, 'yaw_deg': 180})
        if i + 1 < len(delays):
            ev.append({'on': 'land', 'nth': i + 1, 'delay': 80, 'hold': 'jump', 'frames': 20})
    return {'fps': 60, 'steer': 'world', 'start': {'pos': start, 'yaw_deg': 180}, 'end_frame': 190 * len(delays) + 100,
            'events': ev, '_delays': delays}


def rep_wallkick_angles():
    """Approach the BonkWall at 20, 35, 44 and 55 degrees off head-on; press jump 2 frames after any wall_slide."""
    cfg = [(20, -15.4, 22.0), (35, -15.8, 23.0), (44, -15.9, 23.6), (55, -15.95, 24.4)]
    ev = []
    f = 0
    for i, (a, x, z) in enumerate(cfg):
        st = [math.sin(math.radians(a)), -math.cos(math.radians(a))]
        yaw = 180.0 + a   # facing yaw: 180 faces +Z, -90 faces +X
        ev.append({'f': f, 'teleport': [x, 0.0, z], 'yaw_deg': yaw, 'mark': 'angle_%d' % a})
        ev.append({'f': f + 1, 'stick': [round(st[0], 4), round(st[1], 4)]})
        ev.append({'f': f + 45, 'hold': 'jump', 'frames': 20})
        ev.append({'f': f + 150, 'stick': [0, 0]})
        f += 190
    for k in range(1, 5):
        ev.append({'on': 'state:wall_slide', 'nth': k, 'delay': 2, 'hold': 'jump', 'frames': 10})
    return {'fps': 60, 'steer': 'world', 'end_frame': f + 20, 'events': ev, '_angles': [c[0] for c in cfg]}


def rep_platforms():
    """Elevator ride (8 s), then MoverX: stand, jump straight up twice at different phases, walk off the end."""
    ev = [{'f': 0, 'mark': 'elevator'},
          {'f': 520, 'teleport': [53.0, 1.76, -8.0], 'yaw_deg': 0, 'mark': 'mover'},
          {'f': 600, 'hold': 'jump', 'frames': 25, 'mark': 'mover_jump_a'},
          {'f': 760, 'hold': 'jump', 'frames': 25, 'mark': 'mover_jump_b'},
          {'f': 900, 'stick': [0, 1], 'mark': 'mover_walk'},
          {'f': 960, 'stick': [0, 0]}]
    return {'fps': 60, 'steer': 'world', 'start': {'pos': [60.0, 3.51, -16.0], 'yaw_deg': 0}, 'end_frame': 1050, 'events': ev}


def rep_response():
    """Latency and turning: stand, tap jump; start running; 90-degree turn at full speed; 180 reversal (skid);
    release at full speed (brake); ledge grab + climb (1.5 m ledge) with stick held."""
    ev = [{'f': 20, 'tap': 'jump', 'mark': 'tap_jump'},
          {'f': 80, 'stick': [0, 1], 'mark': 'stick_on'},
          {'f': 200, 'stick': [1, 0], 'mark': 'turn90'},
          {'f': 300, 'stick': [-1, 0], 'mark': 'reverse'},
          {'f': 420, 'stick': [0, 0], 'mark': 'release'},
          {'f': 480, 'teleport': [22.25, 0.0, -3.4], 'yaw_deg': 0, 'mark': 'ledge'},
          {'f': 481, 'stick': [0, 1]},
          {'f': 493, 'hold': 'jump', 'frames': 30},
          {'f': 640, 'stick': [0, 0]}]
    return {'fps': 60, 'steer': 'world', 'start': {'pos': [-5.0, 0.0, 30.0], 'yaw_deg': 0}, 'end_frame': 700, 'events': ev}


def rep_cam_tour():
    """Camera tour in MoveLab with camera-relative steering: run, wide turns, run toward the camera, jumps,
    chimney wall kicks (camera zone), ledge climb, backflip, long jump."""
    ev = [{'f': 10, 'stick': [0, 1], 'mark': 'run_away'},
          {'f': 100, 'stick': [1, 0.3], 'mark': 'curve_right'},
          {'f': 220, 'stick': [0, -1], 'mark': 'run_toward_cam'},
          {'f': 330, 'stick': [0, 1]},
          {'f': 360, 'hold': 'jump', 'frames': 20, 'mark': 'jumps'},
          {'on': 'land', 'nth': 1, 'delay': 0, 'hold': 'jump', 'frames': 20},
          {'on': 'land', 'nth': 2, 'delay': 0, 'hold': 'jump', 'frames': 20},
          {'on': 'land', 'nth': 3, 'delay': 30, 'stick': [0, 0]},
          {'f': 640, 'teleport': [-19.75, 0.0, -9.0], 'yaw_deg': 0, 'mark': 'chimney'},
          {'f': 641, 'stick': [0, 0]},
          {'f': 660, 'teleport': [-19.75, 0.0, -12.0], 'yaw_deg': 90},
          {'f': 661, 'stick': [-1, 0], 'cam': [0, 0]},
          {'f': 665, 'hold': 'jump', 'frames': 14},
          {'on': 'state:wall_slide', 'nth': 1, 'delay': 1, 'hold': 'jump', 'frames': 14},
          {'on': 'jump:wall_kick', 'nth': 1, 'delay': 0, 'stick': [1, 0]},
          {'on': 'state:wall_slide', 'nth': 2, 'delay': 1, 'hold': 'jump', 'frames': 14},
          {'on': 'jump:wall_kick', 'nth': 2, 'delay': 0, 'stick': [-1, 0]},
          {'on': 'state:wall_slide', 'nth': 3, 'delay': 1, 'hold': 'jump', 'frames': 14},
          {'on': 'jump:wall_kick', 'nth': 3, 'delay': 0, 'stick': [1, 0]},
          {'on': 'jump:wall_kick', 'nth': 3, 'delay': 20, 'stick': [0, 0]},
          {'f': 1000, 'teleport': [25.25, 0.0, -2.0], 'yaw_deg': 0, 'mark': 'ledge2'},
          {'f': 1020, 'stick': [0, 1]},
          {'f': 1040, 'hold': 'jump', 'frames': 30},
          {'f': 1200, 'stick': [0, 0]},
          {'f': 1240, 'teleport': [0.0, 0.0, 0.0], 'yaw_deg': 0, 'mark': 'backflip'},
          {'f': 1260, 'hold': 'crouch', 'frames': 40},
          {'f': 1270, 'hold': 'jump', 'frames': 30},
          {'f': 1380, 'stick': [0, 1], 'mark': 'long_jump'},
          {'f': 1470, 'hold': 'crouch', 'frames': 6},
          {'f': 1471, 'hold': 'jump', 'frames': 30},
          {'f': 1600, 'stick': [0, 0]}]
    return {'fps': 60, 'steer': 'camera', 'start': {'pos': [0.0, 0.0, 30.0], 'yaw_deg': 0}, 'end_frame': 1700, 'events': ev}


CASES = {
    'chain_sweep': (rep_chain_sweep, LAB),
    'wallkick_sweep': (rep_wallkick_sweep, LAB),
    'wallkick_angles': (rep_wallkick_angles, LAB),
    'platforms': (rep_platforms, LAB),
    'response': (rep_response, LAB),
    'cam_tour': (rep_cam_tour, LAB),
}


def rep_lip_sweep():
    """Run at the 1.0 / 1.5 / 2.0 m MoveLab ledges from 10 m and jump at different frames: how often does a jump
    that nearly clears the lip land on top, hang, or stick to the wall face and drop?"""
    ev = []
    f = 0
    cfg = []
    for x, h in [(19.25, 1.0), (22.25, 1.5), (25.25, 2.0)]:
        for j in [46, 52, 58, 64, 70, 76, 82]:
            ev.append({'f': f, 'teleport': [x, 0.0, 4.0], 'yaw_deg': 0, 'mark': 'lip_h%.1f_j%d' % (h, j)})
            ev.append({'f': f + 1, 'stick': [0, 1]})
            ev.append({'f': f + j, 'hold': 'jump', 'frames': 20})
            ev.append({'f': f + 170, 'stick': [0, 0]})
            cfg.append((h, j))
            f += 200
    return {'fps': 60, 'steer': 'world', 'end_frame': f + 10, 'events': ev, '_cfg': cfg}


CASES['lip_sweep'] = (rep_lip_sweep, LAB)


def run(name, rep, scene, extra=()):
    OUT.mkdir(parents=True, exist_ok=True)
    rep = {k: v for k, v in rep.items() if not k.startswith('_')}
    rp = OUT / (name + '.replay.json')
    tp = OUT / (name + '.trace.jsonl')
    cp = OUT / (name + '.cam.jsonl')
    rp.write_text(json.dumps(rep, indent=1), encoding='utf-8')
    for p in (tp, cp):
        if p.exists():
            p.unlink()
    secs = rep['end_frame'] / 60.0 + 40
    cmd = [sys.executable, str(GODOT_PY), 'run', PROBE, '--seconds', str(round(secs)), '--headless', '--',
           '--replay=' + rp.as_posix(), '--trace=' + tp.as_posix(), '--cam-out=' + cp.as_posix(),
           '--profile=crit-hero-feel', '--scene=' + scene] + list(extra)
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=secs + 1500)
    log = proc.stdout + proc.stderr
    (OUT / (name + '.log.txt')).write_text(log[-20000:], encoding='utf-8')
    errs = [l for l in log.splitlines() if 'SCRIPT ERROR' in l or 'Parse Error' in l]
    return tp, cp, errs


def main():
    names = sys.argv[1:] or list(CASES)
    for n in names:
        if n == 'buffer_sweep':
            continue
        fn, scene = CASES[n]
        tp, cp, errs = run(n, fn(), scene)
        print(n, 'trace' if tp.exists() else 'NO TRACE', 'cam' if cp.exists() else 'NO CAM', errs[:3], flush=True)
    if 'buffer_sweep' in names:
        air = int(sys.argv[sys.argv.index('buffer_sweep') + 1]) if False else None
        air = json.loads((OUT / 'calib.json').read_text())['airtime_frames']
        tp, cp, errs = run('buffer_sweep', rep_buffer_sweep(air), LAB)
        print('buffer_sweep', tp.exists(), errs[:3])


if __name__ == '__main__':
    main()

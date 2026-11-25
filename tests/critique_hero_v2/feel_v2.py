#!/usr/bin/env python3
"""HERO V2 critique round 1, lens GAME FEEL AND CAMERA.

Runs the real MakPlayer through FeelProbeV2 (MoveLab or a world) with replays from the hero r1 feel critique
(game/tests/critique_hero/feel_r1.py, unchanged, like-for-like) plus a world tour, logging the camera and the hero's
skeleton every rendered frame. Optional A/B against the rejected night hero (--night-hero) on the same replay.
Outputs: Docs/progress/critique/hero_v2/r1_feel/data/<case>[__night].{replay.json,trace.jsonl,cam.jsonl,log.txt}

Usage: python game/tests/critique_hero_v2/feel_v2.py <case> [--night] [--windowed] [--shots=rf,rf,...]
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENTITY = HERE.parents[2]
sys.path.insert(0, str(HERE.parent / 'critique_hero'))
import feel_r1  # noqa: E402

OUT = ENTITY / 'Docs' / 'progress' / 'critique' / 'hero_v2' / 'r1_feel' / 'data'
_OD = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--outdir=')), '')
if _OD:
    OUT = Path(_OD).resolve()
GODOT_PY = ENTITY / 'tools' / 'godot.py'
PROBE = 'res://tests/critique_hero_v2/FeelProbeV2.tscn'
LAB = 'res://scenes/tests/MoveLab.tscn'
SUFFIX = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--suffix=')), '')


def rep_moves():
    """Every hero move once, from the gameplay camera, standing start: tap jump, run, triple jump chain, skid,
    side somersault, long jump, backflip, Ham Slam, dive + belly slide, jab combo, ledge climb, wall kicks."""
    ev = [{'f': 30, 'tap': 'jump', 'mark': 'tap_jump'},
          {'f': 100, 'stick': [0, 1], 'mark': 'run'},
          {'f': 180, 'hold': 'jump', 'frames': 14, 'mark': 'triple'},
          {'on': 'land', 'nth': 2, 'delay': 1, 'hold': 'jump', 'frames': 14},
          {'on': 'land', 'nth': 3, 'delay': 1, 'hold': 'jump', 'frames': 20},
          {'f': 420, 'stick': [0, -1], 'mark': 'skid'},
          {'f': 428, 'hold': 'jump', 'frames': 16, 'mark': 'side_flip'},
          {'f': 520, 'stick': [0, 0]},
          {'f': 560, 'teleport': [0.0, 0.0, 30.0], 'yaw_deg': 0, 'mark': 'long_jump'},
          {'f': 561, 'stick': [0, 1]},
          {'f': 640, 'hold': 'crouch', 'frames': 6},
          {'f': 641, 'hold': 'jump', 'frames': 20},
          {'f': 740, 'stick': [0, 0]},
          {'f': 780, 'teleport': [0.0, 0.0, 18.0], 'yaw_deg': 0, 'mark': 'backflip'},
          {'f': 800, 'hold': 'crouch', 'frames': 30},
          {'f': 810, 'hold': 'jump', 'frames': 20},
          {'f': 900, 'hold': 'jump', 'frames': 14, 'mark': 'ham_slam'},
          {'f': 925, 'hold': 'crouch', 'frames': 10},
          {'f': 1010, 'stick': [0, 1], 'mark': 'dive'},
          {'f': 1080, 'tap': 'attack'},
          {'f': 1130, 'tap': 'jump'},
          {'f': 1150, 'stick': [0, 0]},
          {'f': 1190, 'tap': 'attack', 'mark': 'combo'},
          {'f': 1202, 'tap': 'attack'},
          {'f': 1214, 'tap': 'attack'},
          {'f': 1280, 'teleport': [22.25, 0.0, -3.4], 'yaw_deg': 0, 'mark': 'ledge'},
          {'f': 1281, 'stick': [0, 1]},
          {'f': 1293, 'hold': 'jump', 'frames': 30},
          {'f': 1440, 'stick': [0, 0]},
          {'f': 1480, 'teleport': [-14.0, 0.0, 20.2], 'yaw_deg': 180, 'mark': 'wall_kick'},
          {'f': 1481, 'stick': [0, -1]},
          {'f': 1540, 'hold': 'jump', 'frames': 20},
          {'on': 'state:wall_slide', 'nth': 1, 'delay': 2, 'hold': 'jump', 'frames': 12},
          {'f': 1700, 'stick': [0, 0]}]
    # MoveLab world steering; the run lane is +Z -> -Z from z=30.
    return {'fps': 60, 'steer': 'world', 'start': {'pos': [0.0, 0.0, 30.0], 'yaw_deg': 0}, 'end_frame': 1760, 'events': ev}


def rep_world_tour():
    """Camera-relative play in a world from the Default spawn: run, turn, triple jump, long jump, run toward the
    camera, backflip, Ham Slam. No camera input, so the auto camera is what the player sees."""
    ev = [{'f': 60, 'stick': [0, 1], 'mark': 'run'},
          {'f': 150, 'stick': [0.8, 0.6], 'mark': 'curve'},
          {'f': 230, 'stick': [0, 1]},
          {'f': 250, 'hold': 'jump', 'frames': 14, 'mark': 'triple'},
          {'on': 'land', 'nth': 1, 'delay': 1, 'hold': 'jump', 'frames': 14},
          {'on': 'land', 'nth': 2, 'delay': 1, 'hold': 'jump', 'frames': 20},
          {'f': 460, 'stick': [-0.6, 0.8], 'mark': 'long_jump'},
          {'f': 500, 'hold': 'crouch', 'frames': 6},
          {'f': 501, 'hold': 'jump', 'frames': 20},
          {'f': 600, 'stick': [0, -1], 'mark': 'toward_cam'},
          {'f': 700, 'stick': [0, 0]},
          {'f': 730, 'hold': 'crouch', 'frames': 30, 'mark': 'backflip'},
          {'f': 740, 'hold': 'jump', 'frames': 20},
          {'f': 820, 'hold': 'jump', 'frames': 14, 'mark': 'ham_slam'},
          {'f': 845, 'hold': 'crouch', 'frames': 10},
          {'f': 930, 'end': True}]
    return {'fps': 60, 'steer': 'camera', 'end_frame': 940, 'events': ev}


CASES = {
    'moves': (rep_moves, LAB),
    'response': (feel_r1.rep_response, LAB),
    'chain_sweep': (feel_r1.rep_chain_sweep, LAB),
    'lip_sweep': (feel_r1.rep_lip_sweep, LAB),
    'cam_tour': (feel_r1.rep_cam_tour, LAB),
    'tour_w1': (rep_world_tour, 'res://scenes/worlds/w1/W1.tscn'),
    'tour_w2': (rep_world_tour, 'res://scenes/worlds/w2/W2.tscn'),
    'tour_w3': (rep_world_tour, 'res://scenes/worlds/w3/W3.tscn'),
    'tour_hub': (rep_world_tour, 'res://scenes/hub/Hub.tscn'),
}


def run(name, night=False, windowed=False, shots='', extra=()):
    OUT.mkdir(parents=True, exist_ok=True)
    fn, scene = CASES[name]
    rep = {k: v for k, v in fn().items() if not k.startswith('_')}
    tag = name + ('__night' if night else '') + SUFFIX
    rp, tp, cp = OUT / (tag + '.replay.json'), OUT / (tag + '.trace.jsonl'), OUT / (tag + '.cam.jsonl')
    rp.write_text(json.dumps(rep, indent=1), encoding='utf-8')
    for p in (tp, cp):
        if p.exists():
            p.unlink()
    secs = rep['end_frame'] / 60.0 + (90 if scene != LAB else 40)
    cmd = [sys.executable, str(GODOT_PY), 'run', PROBE, '--seconds', str(round(secs)), '--no-import']
    if not windowed:
        cmd.append('--headless')
    cmd += ['--', '--replay=' + rp.as_posix(), '--trace=' + tp.as_posix(), '--cam-out=' + cp.as_posix(),
            '--profile=crit-hero-v2-feel', '--scene=' + scene, '--hide-hud']
    if night:
        cmd.append('--night-hero')
    if shots and shots.startswith('pf:'):
        cmd += ['--shots-pf=' + shots[3:], '--shot-dir=' + (OUT.parent / 'shots' / tag).as_posix()]
    elif shots:
        cmd += ['--shots=' + shots, '--shot-dir=' + (OUT.parent / 'shots' / tag).as_posix()]
    cmd += list(extra)
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=secs + 2400)
    log = proc.stdout + proc.stderr
    (OUT / (tag + '.log.txt')).write_text(log[-30000:], encoding='utf-8')
    errs = [l for l in log.splitlines() if 'SCRIPT ERROR' in l or 'Parse Error' in l]
    print(tag, 'trace' if tp.exists() else 'NO TRACE', 'cam' if cp.exists() else 'NO CAM', errs[:4], flush=True)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    night = '--night' in sys.argv
    windowed = '--windowed' in sys.argv
    shots = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--shots=')), '')
    extra = [a.split('=', 1)[1] for a in sys.argv if a.startswith('--extra=')]
    for n in args:
        run(n, night=night, windowed=windowed, shots=shots, extra=extra)

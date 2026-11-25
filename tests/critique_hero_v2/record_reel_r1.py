#!/usr/bin/env python3
"""HERO V2 critique r1: PoseLab clip reels (every move, in place) for one or more views, via Movie Maker.

    python game/tests/critique_hero_v2/record_reel_r1.py --views side 3q [--set a|b] [--size 1280x720]
Writes Docs/progress/critique/hero_v2/r1_animation/clips/<UTC>__reel_<set>_<view>.mp4 and a JSON index of clip start frames.
"""
import argparse, datetime as dt, json, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENTITY = HERE.parents[2]
OUT = ENTITY / 'Docs' / 'progress' / 'critique' / 'hero_v2' / 'r1_animation' / 'clips'

# name, seconds, cycle (0 = continuous)
SETS = {
    'a': [  # idle life and locomotion
        ('idle', 5, 0), ('idle_look', 3, 0), ('idle_yawn', 3.2, 0), ('idle_sniffair', 3, 0), ('idle_hop', 2, 0),
        ('idle_hattip', 3.2, 0), ('idle_tilt', 3, 0), ('walk_a', 3, 0), ('run_a', 3, 0), ('brake', 1.2, 1.2), ('skid', 1.2, 0.6),
        ('crouch', 1.5, 0), ('crawl', 2.5, 0), ('crouch_slide', 1.2, 0), ('sniff', 2, 0), ('sniff_walk', 2.5, 0),
        ('celebrate', 3, 3.0), ('hurt_land', 1.6, 1.6), ('slope_slide', 1.5, 0),
    ],
    'b': [  # air and combat
        ('jump_rise', 1.4, 1.4), ('double_jump', 1.4, 1.4), ('triple_a', 1.8, 0.9), ('backflip', 1.6, 0.8), ('side_flip', 1.6, 0.8),
        ('long_jump', 1.6, 0.8), ('wall_slide', 1.5, 0), ('wall_kick', 1.2, 0.6), ('ham_tuck', 2.0, 1.0), ('slam_land', 1.6, 0.8),
        ('dive', 1.4, 0.7), ('belly_slide', 1.5, 0), ('rollout', 1.2, 0.6), ('jab1', 1.2, 0.4), ('jab2', 1.2, 0.4), ('kick', 1.6, 0.8),
        ('jump_kick', 1.4, 0.7), ('ledge_hang', 1.5, 0), ('ledge_climb', 1.4, 0.7), ('pole', 2.0, 0), ('hurt_air', 1.4, 0.7),
        ('fallout', 1.5, 0), ('blink', 1.0, 0),
    ],
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--views', nargs='+', default=['side', '3q'])
    ap.add_argument('--set', default='a')
    ap.add_argument('--size', default='1280x720')
    ap.add_argument('--no-import', action='store_true')
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix='herov2_reel_'))
    clips = SETS[a.set]
    for view in a.views:
        spec = ','.join(f'{n}:{s}:{c}:{view}' for n, s, c in clips)
        frames = int(sum(s for _, s, _ in clips) * 60) + 30
        avi = tmp / f'reel_{a.set}_{view}.avi'
        cmd = [sys.executable, str(ENTITY / 'tools' / 'godot.py'), 'movie', 'res://scenes/tests/PoseLab.tscn', str(avi),
               '--frames', str(frames), '--size', a.size] + (['--no-import'] if a.no_import else []) + \
              ['--', '--profile=hero-v2-crit-reel', '--clips=' + spec]
        print('>>', view, frames, flush=True)
        subprocess.run(cmd, cwd=ENTITY)
        if not avi.exists():
            print('missing', avi, flush=True)
            continue
        utc = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        mp4 = OUT / f'{utc}__reel_{a.set}_{view}.mp4'
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(avi), '-c:v', 'libx264', '-crf', '18', '-preset', 'medium',
                        '-pix_fmt', 'yuv420p', '-an', str(mp4)], check=True)
        avi.unlink()
        idx, f = [], 0
        for n, s, c in clips:
            idx.append({'clip': n, 'start_frame': f, 'frames': int(s * 60), 'cycle_s': c})
            f += int(s * 60)
        mp4.with_suffix('.json').write_text(json.dumps(idx, indent=1), encoding='utf-8')
        print('wrote', mp4, flush=True)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""HERO V2 critique r1 (animation director lens): record the hero v2 showcase replay with a close critique camera.

    python game/tests/critique_hero_v2/record_r1.py --view side [--chunk 900] [--only 0 1] [--name tag] [-- extra]
Writes Docs/progress/critique/hero_v2/r1_animation/clips/<UTC>__showcase_<view>.mp4 (offline deterministic Movie Maker)
and per-chunk bone traces to .../bones/<view>_partN.jsonl.
"""
import argparse, datetime as dt, json, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENTITY = HERE.parents[2]
sys.path.insert(0, str(ENTITY / 'game' / 'tests'))
from record_showcase import chunks  # noqa: E402

REPLAY = ENTITY / 'game' / 'tests' / 'replays' / 'showcase_hero_v2.json'
OUT = ENTITY / 'Docs' / 'progress' / 'critique' / 'hero_v2' / 'r1_animation'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--view', default='side')
    ap.add_argument('--chunk', type=int, default=900)
    ap.add_argument('--replay', default=str(REPLAY))
    ap.add_argument('--only', type=int, nargs='*')
    ap.add_argument('--name', default='')
    ap.add_argument('--dist', default='3.2')
    ap.add_argument('--no-import', action='store_true')
    ap.add_argument('--outdir', default='', help='output folder (default: the r1 critique folder)')
    ap.add_argument('extra', nargs='*')
    a = ap.parse_args()
    global OUT
    if a.outdir:
        OUT = Path(a.outdir).resolve()
    rep = json.loads(Path(a.replay).read_text(encoding='utf-8'))
    parts = chunks(rep, a.chunk)
    tmp = Path(tempfile.mkdtemp(prefix='herov2_crit_'))
    (OUT / 'bones').mkdir(parents=True, exist_ok=True)
    (OUT / 'clips').mkdir(parents=True, exist_ok=True)
    print('chunks', [p['end_frame'] - 5 for p in parts], flush=True)
    for i, part in enumerate(parts):
        if a.only is not None and i not in a.only:
            continue
        rp = tmp / f'part{i}.json'
        rp.write_text(json.dumps(part), encoding='utf-8')
        avi = tmp / f'part{i}.avi'
        frames = part['end_frame'] - 5
        bones = OUT / 'bones' / f'{a.view}{a.name}_part{i}.jsonl'
        cmd = [sys.executable, str(ENTITY / 'tools' / 'godot.py'), 'movie', 'res://tests/critique_hero_v2/HeroV2AnimCritR1.tscn', str(avi),
               '--frames', str(frames), '--size', '1280x720'] + (['--no-import'] if a.no_import else []) + \
              ['--', '--profile=hero-v2-crit-anim', '--replay=' + rp.as_posix(), '--hide-hud',
               '--replay-hold', '--view=' + a.view, '--dist=' + a.dist, '--bones-out=' + bones.as_posix()] + a.extra
        print('>>', i, frames, 'frames', flush=True)
        subprocess.run(cmd, cwd=ENTITY)
        if not avi.exists():
            print('missing', avi, flush=True)
            continue
        utc = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        mp4 = OUT / 'clips' / f'{utc}__showcase_{a.view}{a.name}_part{i}.mp4'
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(avi), '-c:v', 'libx264', '-crf', '18', '-preset', 'medium',
                        '-pix_fmt', 'yuv420p', '-an', str(mp4)], check=True)
        avi.unlink()
        print('wrote', mp4, flush=True)


if __name__ == '__main__':
    main()

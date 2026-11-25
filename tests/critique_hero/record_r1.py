#!/usr/bin/env python3
"""HERO critique r1 (animation lens): record the showcase moveset replay with the close critique camera.

    python game/tests/critique_hero/record_r1.py --view side [--chunk 1000] [--only 0 1] [--name tag] [-- extra]
Writes Recordings/night01/M3/<UTC>__hero-crit-r1-anim-<view>.mp4 and per-chunk bone traces to
Docs/progress/critique/hero/r1_animation/bones/<view>_partN.jsonl.
"""
import argparse, datetime as dt, json, subprocess, sys, tempfile, shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENTITY = HERE.parents[2]
sys.path.insert(0, str(ENTITY / 'game' / 'tests'))
from record_showcase import chunks, REPLAY  # noqa: E402

OUT = ENTITY / 'Docs' / 'progress' / 'critique' / 'hero' / 'r1_animation'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--view', default='side')
    ap.add_argument('--chunk', type=int, default=1000)
    ap.add_argument('--replay', default=str(REPLAY))
    ap.add_argument('--only', type=int, nargs='*')
    ap.add_argument('--name', default='')
    ap.add_argument('--trim', type=float, default=1.5)
    ap.add_argument('extra', nargs='*')
    a = ap.parse_args()
    rep = json.loads(Path(a.replay).read_text(encoding='utf-8'))
    parts = chunks(rep, a.chunk)
    tmp = Path(tempfile.mkdtemp(prefix='hero_crit_'))
    (OUT / 'bones').mkdir(parents=True, exist_ok=True)
    mp4s = []
    print('chunks', [p['end_frame'] - 5 for p in parts], flush=True)
    for i, part in enumerate(parts):
        if a.only is not None and i not in a.only:
            continue
        rp = tmp / f'part{i}.json'
        rp.write_text(json.dumps(part), encoding='utf-8')
        avi = tmp / f'part{i}.avi'
        frames = part['end_frame'] - 5
        bones = OUT / 'bones' / f'{a.view}{a.name}_part{i}.jsonl'
        cmd = [sys.executable, str(ENTITY / 'tools' / 'godot.py'), 'movie', 'res://tests/critique_hero/HeroAnimCritR1.tscn', str(avi),
               '--frames', str(frames), '--size', '1280x720', '--', '--profile=hero-crit-anim', '--replay=' + rp.as_posix(),
               '--replay-hold', '--view=' + a.view, '--bones-out=' + bones.as_posix()] + a.extra
        print('>>', i, frames, 'frames', flush=True)
        subprocess.run(cmd, cwd=ENTITY)
        if not avi.exists():
            print('missing', avi, flush=True)
            continue
        mp4 = tmp / f'part{i}.mp4'
        trim = ['-ss', str(a.trim)] if i == 0 and a.trim > 0 else []
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(avi)] + trim + ['-c:v', 'libx264', '-crf', '18', '-preset', 'medium',
                        '-pix_fmt', 'yuv420p', '-an', str(mp4)], check=True)
        avi.unlink()
        mp4s.append(mp4)
    if not mp4s:
        return
    utc = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    dst = ENTITY / 'Recordings' / 'night01' / 'M3' / f'{utc}__hero-crit-r1-anim-{a.view}{a.name}.mp4'
    lst = tmp / 'list.txt'
    lst.write_text(''.join(f"file '{m.as_posix()}'\n" for m in mp4s), encoding='utf-8')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', str(lst), '-c', 'copy', str(dst)], check=True)
    print('parts kept in', tmp, flush=True)
    print('wrote', dst, flush=True)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Record the hero moveset showcase (Movie Maker, offline deterministic) in disk-friendly chunks.

The replay game/tests/replays/showcase_moveset.json is cut at its segment teleports into chunks; each chunk is
recorded to an AVI in a temp folder, converted to MP4 right away (the AVI is deleted), and the MP4s are
concatenated into Recordings/night01/M3/<UTC>__<name>.mp4.

    python game/tests/record_showcase.py [--name hero-moveset-showcase] [--chunk 1000] [-- extra godot args]
"""
import argparse
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENTITY = HERE.parents[1]
REPLAY = HERE / 'replays' / 'showcase_moveset.json'


def chunks(rep, max_len):
    tele = sorted({e['f'] for e in rep['events'] if 'teleport' in e})
    end = rep['end_frame']
    cuts = [0]
    prev = 0
    for t in tele[1:] + [end]:
        if t - cuts[-1] > max_len:
            cuts.append(prev if prev > cuts[-1] else t)
        prev = t
    if cuts[-1] != end:
        cuts.append(end)
    out = []
    for a, b in zip(cuts, cuts[1:]):
        ev = [dict(e, f=e['f'] - a) for e in rep['events'] if a <= e['f'] < b]
        first = next((e for e in ev if 'teleport' in e and e['f'] == 0), None)
        start = {'pos': first['teleport'], 'yaw_deg': first.get('yaw_deg', 0)} if first else rep.get('start')
        out.append({'fps': 60, 'steer': rep.get('steer', 'world'), 'start': start, 'end_frame': b - a + 5, 'events': ev})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--name', default='hero-moveset-showcase')
    ap.add_argument('--chunk', type=int, default=1000)
    ap.add_argument('--replay', default=str(REPLAY))
    ap.add_argument('--only', type=int, nargs='*', help='record only these chunk indices')
    ap.add_argument('--trim', type=float, default=1.5, help='seconds cut from the start (pre-roll)')
    ap.add_argument('--outdir', default='Recordings/night01/M3', help='output folder relative to the entity')
    ap.add_argument('extra', nargs='*')
    a = ap.parse_args()
    rep = json.loads(Path(a.replay).read_text(encoding='utf-8'))
    parts = chunks(rep, a.chunk)
    tmp = Path(tempfile.mkdtemp(prefix='hero_showcase_'))
    mp4s = []
    print('chunks', [p['end_frame'] - 5 for p in parts])
    for i, part in enumerate(parts):
        if a.only is not None and i not in a.only:
            continue
        rp = tmp / f'part{i}.json'
        rp.write_text(json.dumps(part), encoding='utf-8')
        avi = tmp / f'part{i}.avi'
        frames = part['end_frame'] - 5
        cmd = [sys.executable, str(ENTITY / 'tools' / 'godot.py'), 'movie', 'res://scenes/tests/MoveLab.tscn', str(avi),
               '--frames', str(frames), '--size', '1280x720', '--',
               '--profile=hero-movie', '--replay=' + rp.as_posix(), '--replay-hold'] + a.extra
        print('>>', i, frames, 'frames', flush=True)
        subprocess.run(cmd, cwd=ENTITY)
        if not avi.exists():
            print('missing', avi)
            continue
        mp4 = tmp / f'part{i}.mp4'
        trim = ['-ss', str(a.trim)] if i == 0 and a.trim > 0 else []
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(avi)] + trim + ['-c:v', 'libx264', '-crf', '20', '-preset', 'medium',
                        '-pix_fmt', 'yuv420p', '-an', str(mp4)], check=True)
        avi.unlink()
        mp4s.append(mp4)
    utc = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    out = ENTITY / a.outdir / f'{utc}__{a.name}.mp4'
    out.parent.mkdir(parents=True, exist_ok=True)
    lst = tmp / 'list.txt'
    lst.write_text(''.join(f"file '{m.as_posix()}'\n" for m in mp4s), encoding='utf-8')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', str(lst), '-c', 'copy', str(out)], check=True)
    shutil.rmtree(tmp, ignore_errors=True)
    print('showcase', out)


if __name__ == '__main__':
    main()

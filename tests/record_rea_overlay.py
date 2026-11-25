#!/usr/bin/env python3
"""Record the REA reference overlay clip (Movie Maker, offline deterministic) for the making-of video.

Plays four existing movement-test replays in MoveLab with `--rea-overlay` (standing single jump; single, double and
triple from a run; long jump; backflip), one Godot run per replay, converts each AVI to MP4 at once (the AVI is
deleted) and concatenates them into Recordings/night02/rea/<UTC>__rea-overlay-jumps.mp4.

    python game/tests/record_rea_overlay.py
"""
import datetime as dt
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENTITY = HERE.parents[1]
PARTS = [('jump_stand_full', 170), ('triple_jump', 345), ('long_jump', 200), ('backflip', 170)]


def main():
    tmp = Path(tempfile.mkdtemp(prefix='rea_overlay_'))
    mp4s = []
    for name, frames in PARTS:
        rp = HERE / 'replays' / (name + '.json')
        rep = json.loads(rp.read_text(encoding='utf-8'))
        rep['end_frame'] = frames + 5
        part = tmp / (name + '.json')
        part.write_text(json.dumps(rep), encoding='utf-8')
        avi = tmp / (name + '.avi')
        cmd = [sys.executable, str(ENTITY / 'tools' / 'godot.py'), 'movie', 'res://scenes/tests/MoveLab.tscn', str(avi),
               '--frames', str(frames), '--size', '1280x720', '--',
               '--profile=hero-movie', '--replay=' + part.as_posix(), '--replay-hold', '--rea-overlay']
        print('>>', name, frames, 'frames', flush=True)
        subprocess.run(cmd, cwd=ENTITY)
        if not avi.exists():
            print('missing', avi)
            continue
        mp4 = tmp / (name + '.mp4')
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(avi), '-c:v', 'libx264', '-crf', '20', '-preset', 'medium',
                        '-pix_fmt', 'yuv420p', '-an', str(mp4)], check=True)
        avi.unlink()
        mp4s.append(mp4)
    utc = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    out = ENTITY / 'Recordings' / 'night02' / 'rea' / f'{utc}__rea-overlay-jumps.mp4'
    out.parent.mkdir(parents=True, exist_ok=True)
    lst = tmp / 'list.txt'
    lst.write_text(''.join(f"file '{m.as_posix()}'\n" for m in mp4s), encoding='utf-8')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', str(lst), '-c', 'copy', str(out)], check=True)
    shutil.rmtree(tmp, ignore_errors=True)
    print('clip', out)


if __name__ == '__main__':
    main()

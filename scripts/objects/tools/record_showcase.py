"""Record ObjectsShowcase station demos with Movie Maker (offline deterministic), convert to MP4, delete the AVI,
and build a frame sheet for review.
Usage (from anywhere):
  python game/scripts/objects/tools/record_showcase.py <station> <Cam_Name> [--seconds 8] [--size 1280x720] [--sheet-every 0.5]
Outputs: Recordings/night01/M3/<UTC>__objects_<station>_<cam>.mp4 and a sheet PNG next to it in Docs/progress/objects/.
"""
import argparse
import datetime as dt
import subprocess
import sys
from pathlib import Path

ENTITY = Path(__file__).resolve().parents[4]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('station')
    ap.add_argument('cam')
    ap.add_argument('--seconds', type=float, default=8.0)
    ap.add_argument('--size', default='854x480')
    ap.add_argument('--sheet-every', type=float, default=0.5)
    ap.add_argument('--env', default='W1')
    ap.add_argument('--tag', default='')
    ap.add_argument('--extra', default='', help='extra game args, space separated (e.g. --mak=res://...glb)')
    a = ap.parse_args()
    ts = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    slug = f'objects_{a.station}_{a.cam.lower()}{("_" + a.tag) if a.tag else ""}'
    out_dir = ENTITY / 'Recordings' / 'night01' / 'M3'
    out_dir.mkdir(parents=True, exist_ok=True)
    avi = out_dir / f'{ts}__{slug}.avi'
    mp4 = out_dir / f'{ts}__{slug}.mp4'
    frames = int(a.seconds * 60)
    cmd = [sys.executable, str(ENTITY / 'tools' / 'godot.py'), 'movie', 'res://scenes/objects/ObjectsShowcase.tscn', str(avi),
           '--no-import', '--frames', str(frames), '--fps', '60', '--size', a.size, '--',
           f'--profile=objects_show_{ts}', f'--demo={a.station}', f'--cam={a.cam}', '--hide-hud', f'--env={a.env}'] + a.extra.split()
    r = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', cwd=ENTITY)
    errs = [l for l in (r.stdout + r.stderr).splitlines() if 'SCRIPT ERROR' in l or 'Parse Error' in l]
    for e in errs[:8]:
        print('  ', e)
    if not avi.exists():
        print('no AVI produced'); print(r.stdout[-2000:]); print(r.stderr[-2000:]); sys.exit(1)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(avi), '-c:v', 'libx264', '-crf', '20', '-pix_fmt', 'yuv420p',
                    '-movflags', '+faststart', str(mp4)], check=True)
    avi.unlink()
    sheet = ENTITY / 'Docs' / 'progress' / 'objects' / f'{ts}__{slug}_frames.png'
    n = int(a.seconds / a.sheet_every)
    cols = 4
    rows = (n + cols - 1) // cols
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(mp4), '-vf',
                    f'fps={1.0 / a.sheet_every},scale=480:-1,tile={cols}x{rows}', '-frames:v', '1', str(sheet)], check=True)
    print('mp4', mp4.relative_to(ENTITY))
    print('sheet', sheet.relative_to(ENTITY))
    print('script errors', len(errs))


if __name__ == '__main__':
    main()

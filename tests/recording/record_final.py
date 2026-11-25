#!/usr/bin/env python3
"""Final footage recorder for the making-of video (Godot Movie Maker, offline, fixed 60 fps, 1920x1080, game audio).

    python game/tests/recording/record_final.py take <take_id> <res://scene.tscn> --frames N [-- <dev args>]
        One Movie Maker launch through tools/godot.py into a scratch AVI, converted at once to a near-lossless
        mezzanine MP4 (H.264 CRF 12, PCM->AAC 256k) in the scratch folder; the AVI is deleted. A 12-frame review
        sheet is written next to it.
    python game/tests/recording/record_final.py cut <shot> <take_id>@<start_s>-<end_s> [...]
        Cuts and joins mezzanine segments (hard cuts) into Recordings/final/<UTC>__<shot>.mp4 (H.264 CRF 18, AAC 160k,
        faststart) and writes the 12-frame contact sheet to Docs/progress/final/<UTC>__<shot>__sheet.webp.

The 1920x1080 window comes from a temporary game/override.cfg (Godot 4.7 Movie Maker ignores --resolution and
uses the project's 1600x900 window override); the recording agent creates and deletes it.
"""
import datetime as dt
import io
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENTITY = HERE.parents[2]
SCRATCH = Path(os.environ.get('REC_SCRATCH', str(ENTITY / 'Recordings' / '_scratch')))
FINAL = ENTITY / 'Recordings' / 'final'
SHEETS = ENTITY / 'Docs' / 'progress' / 'final'


def dur(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', str(path)],
                         capture_output=True, text=True).stdout
    return float(json.loads(out)['format']['duration'])


def sheet(video, out, n=12, a=0.0, b=None):
    from PIL import Image, ImageDraw
    d = dur(video)
    b = d if b is None else b
    tw, th = 480, 270
    img = Image.new('RGB', (tw * 4, (th + 18) * ((n + 3) // 4)), (20, 20, 20))
    dr = ImageDraw.Draw(img)
    for i in range(n):
        t = a + (b - a) * (i + 0.5) / n
        png = subprocess.run(['ffmpeg', '-v', 'error', '-ss', f'{t:.3f}', '-i', str(video), '-frames:v', '1', '-vf',
                              f'scale={tw}:{th}', '-f', 'image2pipe', '-vcodec', 'png', '-'], capture_output=True).stdout
        if not png:
            continue
        im = Image.open(io.BytesIO(png)).convert('RGB')
        x, y = (i % 4) * tw, (i // 4) * (th + 18)
        img.paste(im, (x, y + 18))
        dr.text((x + 4, y + 3), f'{t:6.2f}s', fill=(255, 255, 0))
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    img.save(out, 'WEBP', quality=80)
    return out


def take(argv):
    extra = []
    if '--' in argv:
        i = argv.index('--')
        argv, extra = argv[:i], argv[i + 1:]
    tid, scene = argv[0], argv[1]
    frames = int(argv[argv.index('--frames') + 1]) if '--frames' in argv else 1800
    SCRATCH.mkdir(parents=True, exist_ok=True)
    avi = SCRATCH / f'{tid}.avi'
    log = SCRATCH / f'{tid}.log'
    cmd = [sys.executable, str(ENTITY / 'tools' / 'godot.py'), 'movie', scene, str(avi), '--frames', str(frames),
           '--size', '1920x1080', '--no-import', '--'] + extra
    t0 = dt.datetime.now(dt.timezone.utc)
    with open(log, 'w', encoding='utf-8') as lf:
        lf.write('cmd: ' + ' '.join(cmd) + '\nstart_utc: ' + t0.isoformat() + '\n')
        lf.flush()
        subprocess.run(cmd, cwd=ENTITY, stdout=lf, stderr=subprocess.STDOUT)
    if not avi.exists():
        print('NO AVI', tid)
        return 1
    mez = SCRATCH / f'{tid}.mp4'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(avi), '-c:v', 'libx264', '-crf', '12', '-preset', 'fast',
                    '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '256k', str(mez)], check=True)
    avi.unlink()
    sheet(mez, SCRATCH / f'{tid}__review.webp')
    print('take', tid, f'{dur(mez):.2f}s', mez)
    return 0


def cut(argv):
    shot, segs = argv[0], argv[1:]
    utc = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    FINAL.mkdir(parents=True, exist_ok=True)
    out = FINAL / f'{utc}__{shot}.mp4'
    inputs, parts = [], []
    total = 0.0
    for k, s in enumerate(segs):
        tid, rng = s.split('@') if '@' in s else (s, '')
        a, b = (rng.split('-') + [''])[:2] if rng else ('', '')
        src = SCRATCH / f'{tid}.mp4'
        total += (float(b) if b else dur(src)) - (float(a) if a else 0.0)
        inputs += (['-ss', a] if a else []) + (['-to', b] if b else []) + ['-i', str(src)]
        parts.append(f'[{k}:v][{k}:a]')
    # CRF 18, capped so every final clip stays under ~280 MB (1080p60 retro textures run 20-25 Mbit/s at plain CRF 18).
    cap = min(20.0, 280 * 8 / max(total, 1.0))
    fc = ''.join(parts) + f'concat=n={len(segs)}:v=1:a=1[v][a]'
    subprocess.run(['ffmpeg', '-v', 'error', '-y'] + inputs + ['-filter_complex', fc, '-map', '[v]', '-map', '[a]',
                    '-c:v', 'libx264', '-crf', '18', '-maxrate', f'{cap:.1f}M', '-bufsize', f'{2 * cap:.1f}M', '-preset', 'medium', '-pix_fmt', 'yuv420p', '-r', '60',
                    '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart', str(out)], check=True)
    sh = sheet(out, SHEETS / f'{utc}__{shot}__sheet.webp')
    print('final', out, f'{dur(out):.2f}s', f'{out.stat().st_size / 1e6:.1f} MB', sh)
    return 0


if __name__ == '__main__':
    cmd = sys.argv[1]
    sys.exit(take(sys.argv[2:]) if cmd == 'take' else cut(sys.argv[2:]))

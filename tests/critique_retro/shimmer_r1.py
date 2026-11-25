"""Critique RETRO r1 (image cleanliness): temporal shimmer metric for the CleanR1 movie (W1 scripted dolly, look off then on).

Usage: python shimmer_r1.py <movie.avi|mp4> <movie_marks.json> <out_dir> <stamp> [label]

The camera moves slowly at constant speed, so smooth content changes almost linearly from frame to frame. Aliasing (texel
crawl, dither sparkle, outline/rim flicker on small pickups) shows up as a large second temporal difference
|f(t+1) - 2 f(t) + f(t-1)| on luma. Reports the mean and the 99th percentile per screen band (far = top half below the sky
line, near = bottom third) for the off and on passes, plus a magnified 6-frame strip of a far-field crop for both passes.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


def frames(path, start, count, tmp):
    tmp.mkdir(parents=True, exist_ok=True)
    for f in tmp.glob('*.png'):
        f.unlink()
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(path), '-vf', f'select=between(n\\,{start}\\,{start + count - 1})',
                    '-vsync', '0', str(tmp / 'f_%04d.png')], check=True)
    return [np.asarray(Image.open(p).convert('RGB')) for p in sorted(tmp.glob('*.png'))]


def luma(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def metric(fs):
    L = [luma(f.astype(np.float32)) for f in fs]
    h = L[0].shape[0]
    bands = {'far': (int(h * 0.40), int(h * 0.62)), 'mid': (int(h * 0.62), int(h * 0.80)), 'near': (int(h * 0.80), h)}
    out = {}
    for name, (y0, y1) in bands.items():
        vals = []
        for t in range(1, len(L) - 1):
            d2 = np.abs(L[t + 1][y0:y1] - 2 * L[t][y0:y1] + L[t - 1][y0:y1])
            vals.append(d2)
        v = np.stack(vals)
        out[name] = {'mean': round(float(v.mean()), 3), 'p99': round(float(np.percentile(v, 99)), 2),
                     'frac_gt24': round(float((v > 24).mean()) * 100, 3)}
    return out


def main():
    movie, marks_p, out_dir, stamp = sys.argv[1:5]
    label = sys.argv[5] if len(sys.argv) > 5 else 'w1'
    marks = json.loads(Path(marks_p).read_text())['marks']
    out = Path(out_dir)
    tmp = out / '_tmp_frames'
    res = {}
    strips = []
    first = None
    for on in (0, 1):
        s = int(marks[f'retro{on}_start']) + 20
        fs = frames(movie, s, 120, tmp)
        res[f'retro{on}'] = metric(fs)
        h, w = fs[0].shape[:2]
        if first is None:
            first = (w, h)
        # 6 consecutive frames of a far-field crop, x4 nearest.
        cx, cy, cw, ch = int(w * 0.40), int(h * 0.46), 160, 90
        row = Image.new('RGB', (cw * 4 * 3, ch * 4 * 2))
        for k in range(6):
            c = Image.fromarray(fs[40 + k][cy:cy + ch, cx:cx + cw]).resize((cw * 4, ch * 4), Image.NEAREST)
            row.paste(c, ((k % 3) * cw * 4, (k // 3) * ch * 4))
        d = ImageDraw.Draw(row)
        d.rectangle([0, 0, 420, 18], fill=(0, 0, 0))
        d.text((4, 4), f'retro{on}: 6 consecutive frames, far-field crop x4 (frames {s + 40}-{s + 45})', fill=(255, 255, 0))
        strips.append(row)
    sheet = Image.new('RGB', (strips[0].width, strips[0].height * 2 + 8), (20, 20, 20))
    sheet.paste(strips[0], (0, 0))
    sheet.paste(strips[1], (0, strips[0].height + 8))
    sheet.save(out / f'{stamp}__clean_movie_{label}_farfield_strip_retro0_vs_retro1.png')
    for f in tmp.glob('*.png'):
        f.unlink()
    tmp.rmdir()
    res['size'] = first
    (out / f'{stamp}__clean_shimmer_metric_{label}.json').write_text(json.dumps(res, indent=2))
    print(json.dumps(res, indent=2))


if __name__ == '__main__':
    main()

"""Contact sheets and plots for the camera probe (finish pass).

  python game/tests/camera_probe/cam_sheets.py sheet <in.avi|mp4> <out.webp> <t0> <t1> <n> [label]
  python game/tests/camera_probe/cam_sheets.py plot <out.webp> <title> <before.jsonl> <after.jsonl>
  python game/tests/camera_probe/cam_sheets.py mp4 <in.avi> <out.mp4>
"""
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def _font(sz):
    for f in ('C:/Windows/Fonts/segoeui.ttf', 'C:/Windows/Fonts/arial.ttf'):
        try:
            return ImageFont.truetype(f, sz)
        except Exception:
            pass
    return ImageFont.load_default()


def sheet(src, out, t0, t1, n, label=''):
    t0, t1, n = float(t0), float(t1), int(n)
    tiles = []
    with tempfile.TemporaryDirectory() as td:
        for i in range(n):
            t = t0 + (t1 - t0) * i / max(n - 1, 1)
            fp = Path(td) / f'{i:03d}.png'
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', f'{t:.3f}', '-i', str(src), '-frames:v', '1',
                            '-vf', 'scale=480:-2', str(fp)], check=True)
            im = Image.open(fp).convert('RGB')
            d = ImageDraw.Draw(im)
            d.rectangle([0, 0, 92, 26], fill=(0, 0, 0))
            d.text((6, 3), f'{t:5.2f} s', fill=(255, 255, 255), font=_font(18))
            tiles.append(im)
    cols = 4
    rows = math.ceil(len(tiles) / cols)
    w, h = tiles[0].size
    top = 40 if label else 0
    sh = Image.new('RGB', (w * cols, h * rows + top), (24, 24, 24))
    if label:
        ImageDraw.Draw(sh).text((10, 8), label, fill=(240, 240, 240), font=_font(22))
    for i, im in enumerate(tiles):
        sh.paste(im, ((i % cols) * w, top + (i // cols) * h))
    sh.save(out, 'WEBP', quality=82)
    print('sheet', out, sh.size)


def _rows(p):
    return [json.loads(l) for l in Path(p).read_text(encoding='utf-8').splitlines() if l.strip()]


def plot(out, title, before, after):
    """Three stacked panels per run: per-frame camera offset change (m, 60 fps normalised), boom length (m), pitch (deg)."""
    W, H = 1500, 900
    im = Image.new('RGB', (W, H), (250, 248, 242))
    d = ImageDraw.Draw(im)
    d.text((20, 10), title, fill=(30, 30, 30), font=_font(24))
    series = [('before', _rows(before), (200, 70, 50)), ('after', _rows(after), (40, 110, 190))]
    panels = [('camera offset change per frame (m, 60 fps)', 'jump', 0.0, None),
              ('boom length (m)', 'boom', 0.0, 5.5), ('pitch (deg)', 'pitch', -45.0, 45.0)]
    tmax = max(r['t'] for _, rs, _ in series for r in rs)
    for k, (name, rs, col) in enumerate(series):
        for a, b in zip(rs, rs[1:]):
            oa = [c - p for c, p in zip(a['cam'], a['pl'])]
            ob = [c - p for c, p in zip(b['cam'], b['pl'])]
            b['jump'] = math.dist(oa, ob) / max(b['dt'], 1e-4) / 60.0
        rs[0]['jump'] = 0.0
    jmax = max(0.2, max(r['jump'] for _, rs, _ in series for r in rs if r['t'] > 1.0))
    for pi, (pname, key, lo, hi) in enumerate(panels):
        y0 = 60 + pi * 280
        y1 = y0 + 240
        if hi is None:
            hi = jmax * 1.05
        d.rectangle([60, y0, W - 20, y1], outline=(160, 160, 160))
        d.text((66, y0 + 4), f'{pname}  [{lo:g} .. {hi:.2f}]', fill=(60, 60, 60), font=_font(16))
        for name, rs, col in series:
            pts = []
            for r in rs:
                if r['t'] < 1.0:
                    continue
                x = 60 + (r['t'] / tmax) * (W - 80)
                v = min(max(r[key], lo), hi)
                y = y1 - (v - lo) / (hi - lo) * (y1 - y0)
                pts.append((x, y))
            if len(pts) > 1:
                d.line(pts, fill=col, width=2)
    d.text((W - 360, 14), 'before', fill=series[0][2], font=_font(20))
    d.text((W - 260, 14), 'after', fill=series[1][2], font=_font(20))
    d.text((W - 180, 14), f'0..{tmax:.0f} s', fill=(60, 60, 60), font=_font(18))
    im.save(out, 'WEBP', quality=90)
    print('plot', out)


def mp4(src, out):
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(src), '-c:v', 'libx264', '-crf', '20', '-preset', 'veryfast',
                    '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart', str(out)], check=True)
    print('mp4', out)


if __name__ == '__main__':
    c = sys.argv[1]
    if c == 'sheet':
        sheet(*sys.argv[2:])
    elif c == 'plot':
        plot(*sys.argv[2:])
    elif c == 'mp4':
        mp4(*sys.argv[2:])

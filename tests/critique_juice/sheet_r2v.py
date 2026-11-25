"""Critique JUICE round 2, VFX art director lens: sheets from JuiceLab --shots and JuiceWorldProbe frames.

    python game/tests/critique_juice/sheet_r2v.py strip <shots_dir> <out.png> [--tile=400] [--only=03,05] [--crop=x0,y0,x1,y1]
        One row per station, one column per frame lead. --crop takes fractions of the frame (0-1) so every tile is a
        full-resolution crop of the same region (gameplay-distance effects are small in a 1920 frame).
    python game/tests/critique_juice/sheet_r2v.py grid <out.png> <img> [<img> ...] [--cols=3] [--tile=640] [--crop=...]
        Labelled grid of arbitrary frames (world probe shots).
    python game/tests/critique_juice/sheet_r2v.py grey <in.png> <out.png>
        Side-by-side colour and greyscale (D034 hierarchy check: does the effect separate in value?).
Test/evidence tool only; reads frames, never touches game files.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


def _font(size=15):
    try:
        return ImageFont.truetype('arial.ttf', size)
    except OSError:
        return ImageFont.load_default()


def _crop(im, spec):
    if not spec:
        return im
    x0, y0, x1, y1 = [float(v) for v in spec.split(',')]
    w, h = im.size
    return im.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))


def strip(args, opts):
    src, out = Path(args[0]), Path(args[1])
    tw = int(opts.get('tile', '400'))
    only = set(opts['only'].split(',')) if 'only' in opts else None
    rows = defaultdict(dict)
    pat = re.compile(r'^(.*)_(\d\d)_(.+)_f(\d+)\.png$')
    for p in sorted(src.glob('*.png')):
        m = pat.match(p.name)
        if not m or (only and m.group(2) not in only):
            continue
        rows[(m.group(2), m.group(3))][int(m.group(4))] = p
    if not rows:
        print('no shots in', src)
        return
    leads = sorted({l for r in rows.values() for l in r})
    first = _crop(Image.open(next(iter(next(iter(rows.values())).values()))), opts.get('crop'))
    th = int(tw * first.height / first.width)
    lw = 180
    sheet = Image.new('RGB', (lw + tw * len(leads), 24 + th * len(rows)), (30, 26, 24))
    d = ImageDraw.Draw(sheet)
    f = _font()
    for j, l in enumerate(leads):
        d.text((lw + j * tw + 6, 4), f'+{l} f ({l / 60 * 1000:.0f} ms)', fill=(240, 230, 210), font=f)
    for i, key in enumerate(sorted(rows)):
        y = 24 + i * th
        d.text((6, y + 6), f'{key[0]} {key[1]}'[:24], fill=(240, 230, 210), font=f)
        for j, l in enumerate(leads):
            p = rows[key].get(l)
            if p:
                im = _crop(Image.open(p).convert('RGB'), opts.get('crop')).resize((tw, th), Image.LANCZOS)
                sheet.paste(im, (lw + j * tw, y))
    sheet.save(out)
    print('wrote', out, sheet.size)


def grid(args, opts):
    out = Path(args[0])
    files = [Path(a) for a in args[1:]]
    cols = int(opts.get('cols', '3'))
    tw = int(opts.get('tile', '640'))
    ims = [_crop(Image.open(p).convert('RGB'), opts.get('crop')) for p in files]
    th = int(tw * ims[0].height / ims[0].width)
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * tw, rows * (th + 22)), (30, 26, 24))
    d = ImageDraw.Draw(sheet)
    f = _font()
    for i, (p, im) in enumerate(zip(files, ims)):
        x, y = (i % cols) * tw, (i // cols) * (th + 22)
        d.text((x + 4, y + 3), p.stem[:70], fill=(240, 230, 210), font=f)
        sheet.paste(im.resize((tw, th), Image.LANCZOS), (x, y + 22))
    sheet.save(out)
    print('wrote', out, sheet.size)


def grey(args, opts):
    im = Image.open(args[0]).convert('RGB')
    g = ImageOps.grayscale(im).convert('RGB')
    sheet = Image.new('RGB', (im.width * 2, im.height))
    sheet.paste(im, (0, 0))
    sheet.paste(g, (im.width, 0))
    sheet.save(args[1])
    print('wrote', args[1])


def main():
    mode = sys.argv[1]
    args = [a for a in sys.argv[2:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) for a in sys.argv[2:] if a.startswith('--') and '=' in a)
    {'strip': strip, 'grid': grid, 'grey': grey}[mode](args, opts)


if __name__ == '__main__':
    main()

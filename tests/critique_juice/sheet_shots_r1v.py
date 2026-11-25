"""Timing-strip sheet from JuiceLab --shots output (critique JUICE r1, VFX art lens, second pass).

    python game/tests/critique_juice/sheet_shots_r1v.py <shots_dir> <out.png> [--tile=360] [--only=03,05]

Files are <group>_<nn>_<event>_f<lead>.png. One row per station, one column per lead (frames after the event).
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--') and '=' in a)
    src, out = Path(args[0]), Path(args[1])
    tw = int(opts.get('tile', '360'))
    only = set(opts['only'].split(',')) if 'only' in opts else None
    rows = defaultdict(dict)
    pat = re.compile(r'^(.*)_(\d\d)_(.+)_f(\d+)\.png$')
    for p in sorted(src.glob('*.png')):
        m = pat.match(p.name)
        if not m:
            continue
        if only and m.group(2) not in only:
            continue
        rows[(m.group(2), m.group(3))][int(m.group(4))] = p
    leads = sorted({l for r in rows.values() for l in r})
    if not rows:
        print('no shots in', src)
        return
    first = Image.open(next(iter(next(iter(rows.values())).values())))
    th = int(tw * first.height / first.width)
    lw = 170
    sheet = Image.new('RGB', (lw + tw * len(leads), 24 + th * len(rows)), (30, 26, 24))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype('arial.ttf', 15)
    except OSError:
        font = ImageFont.load_default()
    for j, l in enumerate(leads):
        d.text((lw + j * tw + 6, 4), f'+{l} f ({l / 60 * 1000:.0f} ms)', fill=(240, 230, 210), font=font)
    for i, key in enumerate(sorted(rows)):
        y = 24 + i * th
        d.text((6, y + 6), f'{key[0]} {key[1]}'[:22], fill=(240, 230, 210), font=font)
        for j, l in enumerate(leads):
            p = rows[key].get(l)
            if p:
                im = Image.open(p).convert('RGB').resize((tw, th))
                sheet.paste(im, (lw + j * tw, y))
    sheet.save(out)
    print('wrote', out, sheet.size)


if __name__ == '__main__':
    main()

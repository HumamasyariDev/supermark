"""Critique JUICE r2 perf: labelled contact sheets of the probe frames, r1 vs r2.

    python game/tests/critique_juice/sheet_r2.py <out png> <world> [<world> ...]

Rows per world: r1 burst / overdraw idle / overdraw burst / overdraw close-up, then the same for r2.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ENTITY = Path(__file__).resolve().parents[3]
R1 = ENTITY / 'Docs/progress/critique/juice/r1_perf/raw'
R2 = ENTITY / 'Docs/progress/critique/juice/r2_perf/raw'
SHOTS = ['burst_normal', 'overdraw_idle', 'overdraw_burst', 'overdraw_burst_closeup']
W, H = 640, 360


def font(sz):
    for f in ('C:/Windows/Fonts/segoeuib.ttf', 'C:/Windows/Fonts/arial.ttf'):
        try:
            return ImageFont.truetype(f, sz)
        except OSError:
            pass
    return ImageFont.load_default()


def main():
    out = Path(sys.argv[1])
    worlds = sys.argv[2:] or ['W1']
    rows = []
    for w in worlds:
        for tag, d in (('r1', R1), ('r2', R2)):
            rows.append((w, tag, [d / f'{w}_{s}.png' for s in SHOTS]))
    sheet = Image.new('RGB', (W * len(SHOTS), (H + 26) * len(rows) + 40), (24, 22, 28))
    dr = ImageDraw.Draw(sheet)
    dr.text((10, 8), 'JUICE critique r2, performance: 12-heavy burst, normal and Godot overdraw view (r1 = 01:00 UTC build, r2 = 16:20 UTC build)',
            fill=(240, 236, 220), font=font(20))
    y = 40
    for w, tag, files in rows:
        for i, f in enumerate(files):
            x = i * W
            if f.exists():
                im = Image.open(f).convert('RGB').resize((W, H))
                sheet.paste(im, (x, y + 26))
            else:
                dr.rectangle([x, y + 26, x + W - 1, y + 26 + H - 1], outline=(90, 90, 90))
                dr.text((x + 20, y + 180), 'missing', fill=(160, 160, 160), font=font(18))
            dr.text((x + 6, y + 3), f'{w} {tag}: {SHOTS[i].replace("_", " ")}', fill=(255, 214, 120) if tag == 'r2' else (190, 180, 220), font=font(17))
        y += H + 26
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print('wrote', out)


if __name__ == '__main__':
    main()

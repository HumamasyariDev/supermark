"""Tile JuiceLab close-up shots into one review sheet.
python game/scripts/fx/tools/contact_sheet.py <shots_dir> <out.png> [--cols N] [--width 480]
Rows = events (sorted by station index), columns = the lead frames."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

src = Path(sys.argv[1])
out = Path(sys.argv[2])
w = 480
if '--width' in sys.argv:
    w = int(sys.argv[sys.argv.index('--width') + 1])
files = sorted(src.glob('*.png'))
rows = {}
for f in files:
    stem = f.stem
    key, lead = stem.rsplit('_f', 1)
    rows.setdefault(key, []).append((int(lead), f))
keys = sorted(rows)
ncol = max(len(v) for v in rows.values())
h = int(w * 9 / 16)
sheet = Image.new('RGB', (w * ncol, (h + 4) * len(keys)), (30, 24, 20))
d = ImageDraw.Draw(sheet)
for r, k in enumerate(keys):
    for c, (lead, f) in enumerate(sorted(rows[k])):
        im = Image.open(f).convert('RGB').resize((w, h))
        sheet.paste(im, (c * w, r * (h + 4)))
        d.text((c * w + 8, r * (h + 4) + h - 18), '%s  +%d frames' % (k.split('_', 2)[-1], lead), fill=(255, 240, 200))
out.parent.mkdir(parents=True, exist_ok=True)
sheet.save(out)
print('sheet', out, sheet.size, len(keys), 'rows')

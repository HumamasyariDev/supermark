"""Before/after board for the making-of: one row per pair, BEFORE on the left, AFTER on the right.
python game/scripts/fx/tools/before_after.py <out.png> "<caption>|<before.png[@x,y,w,h]>|<after.png[@x,y,w,h]>" [...] [--width 640]
  [--labels "BEFORE (juice fix r2)|AFTER (juice fix r3)"]"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

labels = ['BEFORE (critic r1)', 'AFTER (juice fix r1)']
argv = sys.argv[1:]
if '--labels' in argv:
    i = argv.index('--labels')
    labels = argv[i + 1].split('|')
    del argv[i:i + 2]
if '--width' in argv:
    i = argv.index('--width')
    del argv[i:i + 2]
args = [a for a in argv if not a.startswith('--')]
w = 640
if '--width' in sys.argv:
    w = int(sys.argv[sys.argv.index('--width') + 1])
out = Path(args[0])
rows = [a.split('|') for a in args[1:]]
h = int(w * 9 / 16)
pad = 34
sheet = Image.new('RGB', (w * 2 + 12, (h + pad) * len(rows)), (30, 24, 20))
d = ImageDraw.Draw(sheet)
for r, (cap, before, after) in enumerate(rows):
    y = r * (h + pad)
    d.text((8, y + 8), cap, fill=(255, 240, 200))
    for c, (lab, f) in enumerate([(labels[0], before), (labels[1], after)]):
        crop = None
        if '@' in f:
            f, cs = f.split('@', 1)
            crop = [int(v) for v in cs.split(',')]
        im = Image.open(f).convert('RGB')
        if crop:
            im = im.crop((crop[0], crop[1], crop[0] + crop[2], crop[1] + crop[3]))
        im = im.resize((w, int(w * im.height / im.width)))
        if im.height > h:
            top = (im.height - h) // 2
            im = im.crop((0, top, w, top + h))
        x = c * (w + 12)
        sheet.paste(im, (x, y + pad))
        d.rectangle([x, y + pad, x + 230, y + pad + 20], fill=(30, 24, 20))
        d.text((x + 6, y + pad + 4), lab, fill=(255, 220, 150) if c else (200, 200, 200))
out.parent.mkdir(parents=True, exist_ok=True)
sheet.save(out)
print('board', out, sheet.size)

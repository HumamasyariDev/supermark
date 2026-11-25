"""Contact sheet: python sheet.py out.png cols width img1 img2 ... (labels = camera names)"""
import sys, os
from PIL import Image, ImageDraw
out, cols, w = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
ims = sys.argv[4:]
tiles = []
for p in ims:
    im = Image.open(p).convert("RGB")
    h = int(im.height * w / im.width)
    im = im.resize((w, h), Image.LANCZOS)
    d = ImageDraw.Draw(im)
    lab = os.path.basename(p).split("__")[-1].replace(".png", "")
    d.rectangle([0, 0, 8 * len(lab) + 8, 16], fill=(0, 0, 0))
    d.text((4, 2), lab, fill=(255, 255, 255))
    tiles.append(im)
rows = (len(tiles) + cols - 1) // cols
th = max(t.height for t in tiles)
S = Image.new("RGB", (cols * w, rows * th), (30, 30, 30))
for i, t in enumerate(tiles):
    S.paste(t, ((i % cols) * w, (i // cols) * th))
S.save(out)
print(out, S.size)

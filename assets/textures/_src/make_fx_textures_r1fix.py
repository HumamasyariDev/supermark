"""Juice fix round 1 (night 01): procedural inked particle sprites of our own, replacing borrowed five-point stars on
pickups and celebrations and the grey ruled page cards. All are white/neutral fills with a dark ink outline (#3B2416)
so the particle colour tints them (gold glints, surface-coloured splats). Run from this folder:
    python make_fx_textures_r1fix.py
Writes ../fx/<name>.webp (lossless, 256 px, straight alpha)."""
import math
import random
from PIL import Image, ImageDraw, ImageFilter

OUT = '../fx/'
S = 256
K = 4  # supersample
INK = (59, 36, 22)


def canvas():
    return Image.new('L', (S * K, S * K), 0)


def down(im):
    return im.resize((S, S), Image.LANCZOS)


def grow(mask, px):
    # Dilate a mask by px (final pixels) for the ink outline.
    return mask.filter(ImageFilter.MaxFilter(px * 2 + 1)) if px > 0 else mask


def compose(fill_mask, outline_px, fill_rgb=(255, 255, 255), hi_mask=None, inner_lines=None, outline_rgb=INK):
    """fill_mask: L at final size. Outline = dilated mask in ink, fill on top."""
    outer = grow(fill_mask, outline_px)
    rgb = Image.new('RGB', (S, S), outline_rgb)
    rgb.paste(Image.new('RGB', (S, S), fill_rgb), (0, 0), fill_mask)
    if inner_lines is not None:
        rgb.paste(Image.new('RGB', (S, S), outline_rgb), (0, 0), inner_lines)
    if hi_mask is not None:
        rgb.paste(Image.new('RGB', (S, S), (255, 255, 255)), (0, 0), hi_mask)
    r, g, b = rgb.split()
    return Image.merge('RGBA', (r, g, b, outer))


def save(im, name):
    im.save(OUT + name + '.webp', 'WEBP', lossless=True)
    print('wrote', name)


# 1. glint_ink: bold four-point glint with concave sides, ink outline, warm-white core.
def glint_mask(r_long=100, r_short=100, waist=2.2):
    # Concave four-point glint (super-ellipse astroid): sharp tips, curved sides.
    im = canvas()
    d = ImageDraw.Draw(im)
    c = S * K / 2
    pts = []
    n = 200
    for i in range(n):
        t = i / n * math.tau
        ct, st = math.cos(t), math.sin(t)
        x = math.copysign(abs(ct) ** waist, ct) * r_long
        y = math.copysign(abs(st) ** waist, st) * r_short
        pts.append((c + x * K, c + y * K))
    d.polygon(pts, fill=255)
    return down(im)


m = glint_mask(104, 104, 3.2)
hi = Image.new('L', (S, S), 0)
ImageDraw.Draw(hi).ellipse([116, 116, 140, 140], fill=255)
hi = hi.filter(ImageFilter.GaussianBlur(5))
save(compose(m, 6, (255, 250, 236), hi_mask=hi), 'glint_ink')

# 2. truffle_mini: a tiny truffle silhouette (bumpy round body plus a two-leaf sprout), inked.
im = canvas()
d = ImageDraw.Draw(im)
c = S * K / 2
random.seed(7)
body_r = 78 * K
cy = c + 22 * K
pts = []
for i in range(48):
    a = i / 48 * math.tau
    bump = 1.0 + 0.06 * math.sin(a * 7 + 0.4) + 0.03 * math.sin(a * 13)
    pts.append((c + math.cos(a) * body_r * bump, cy + math.sin(a) * body_r * 0.92 * bump))
d.polygon(pts, fill=255)
# sprout stem and leaves
d.rectangle([c - 6 * K, cy - body_r - 26 * K, c + 6 * K, cy - body_r + 10 * K], fill=255)
d.ellipse([c - 62 * K, cy - body_r - 60 * K, c - 4 * K, cy - body_r - 22 * K], fill=255)
d.ellipse([c + 4 * K, cy - body_r - 66 * K, c + 66 * K, cy - body_r - 26 * K], fill=255)
mask = down(im)
# bumps drawn as small ink arcs
lines = canvas()
ld = ImageDraw.Draw(lines)
for (bx, by) in [(-30, -10), (18, -24), (34, 18), (-14, 30), (-44, 26), (6, 2)]:
    x, y = c + bx * K, cy + by * K
    ld.arc([x - 14 * K, y - 12 * K, x + 14 * K, y + 12 * K], 200, 340, fill=255, width=5 * K)
lines = down(lines)
hi = Image.new('L', (S, S), 0)
ImageDraw.Draw(hi).ellipse([84, 104, 112, 128], fill=255)
hi = hi.filter(ImageFilter.GaussianBlur(4))
save(compose(mask, 7, (255, 246, 222), hi_mask=hi, inner_lines=lines), 'truffle_mini')

# 3. gold_leaf: a curled gold-leaf flake / page corner (irregular quad with a folded corner line).
im = canvas()
d = ImageDraw.Draw(im)
pts = [(54, 70), (196, 44), (214, 170), (120, 214), (42, 168)]
d.polygon([(x * K, y * K) for x, y in pts], fill=255)
mask = down(im)
lines = canvas()
ImageDraw.Draw(lines).line([(150 * K, 52 * K), (206 * K, 120 * K)], fill=255, width=6 * K)
lines = down(lines)
hi = Image.new('L', (S, S), 0)
ImageDraw.Draw(hi).polygon([(70, 82), (150, 64), (100, 120)], fill=200)
hi = hi.filter(ImageFilter.GaussianBlur(10))
save(compose(mask, 6, (255, 240, 200), hi_mask=hi, inner_lines=lines), 'gold_leaf')

# 4. page: parchment (#EAD8B0) storybook page with a warm darker edge and two faint text lines (no grey ruling).
im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
d.rounded_rectangle([40, 22, 216, 234], radius=10, fill=(196, 160, 104, 255))       # warm edge
d.rounded_rectangle([48, 30, 208, 226], radius=7, fill=(240, 226, 192, 255))        # parchment body
for y in range(64, 206, 22):
    d.line([(66, y), (190 - (y % 3) * 14, y)], fill=(176, 140, 96, 255), width=3)    # ink text strokes, warm
d.polygon([(176, 226), (208, 194), (208, 226)], fill=(214, 190, 140, 255))          # dog-ear
im.save(OUT + 'page.webp', 'WEBP', lossless=True)
print('wrote page')

# 5. splat_ink: radial inked impact splat (ground decal for the Ham Slam) with crack lines.
im = canvas()
d = ImageDraw.Draw(im)
c = S * K / 2
random.seed(3)
pts = []
n = 22
for i in range(n * 2):
    a = i / (n * 2) * math.tau
    r = (104 if i % 2 == 0 else 62 + random.uniform(-6, 8)) * K
    if i % 2 == 0:
        r *= random.uniform(0.78, 1.0)
    pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
d.polygon(pts, fill=255)
hole = canvas()
ImageDraw.Draw(hole).ellipse([c - 30 * K, c - 30 * K, c + 30 * K, c + 30 * K], fill=255)
mask = down(im)
cracks = canvas()
cd = ImageDraw.Draw(cracks)
for i in range(7):
    a = i / 7 * math.tau + 0.3
    x0, y0 = c + math.cos(a) * 34 * K, c + math.sin(a) * 34 * K
    xm, ym = c + math.cos(a + 0.12) * 64 * K, c + math.sin(a + 0.12) * 64 * K
    x1, y1 = c + math.cos(a - 0.05) * 92 * K, c + math.sin(a - 0.05) * 92 * K
    cd.line([(x0, y0), (xm, ym), (x1, y1)], fill=255, width=5 * K)
cracks = down(cracks)
splat = compose(mask, 5, (255, 255, 255), inner_lines=cracks)
# Soft centre hole so the slam point reads as pressed in.
save(splat, 'splat_ink')

# 6. wind_curl: a spiral wind curl stroke (style image 05): cream stroke with a soft ink edge, tapering tail.
im = canvas()
d = ImageDraw.Draw(im)
c = S * K / 2
prev = None
steps = 220
for i in range(steps):
    t = i / steps
    ang = t * math.tau * 1.35
    rad = (14 + 92 * t) * K
    x = c - 40 * K + math.cos(ang) * rad * 0.9 + t * 60 * K
    y = c + math.sin(ang) * rad * 0.7
    w = (4 + 16 * math.sin(math.pi * min(t * 1.1, 1.0))) * K
    if prev:
        d.line([prev, (x, y)], fill=255, width=int(w))
    d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=255)
    prev = (x, y)
mask = down(im)
save(compose(mask, 4, (255, 255, 255), outline_rgb=(120, 130, 150)), 'wind_curl')

# 7. tuft: small fluffy wool tuft (three lobes) with ink outline.
im = canvas()
d = ImageDraw.Draw(im)
for (x, y, r) in [(-40, 10, 56), (36, 14, 54), (0, -30, 62), (-6, 34, 50)]:
    d.ellipse([c + (x - r) * K, c + (y - r) * K, c + (x + r) * K, c + (y + r) * K], fill=255)
mask = down(im)
lines = canvas()
ld = ImageDraw.Draw(lines)
ld.arc([c - 70 * K, c - 40 * K, c - 10 * K, c + 30 * K], 290, 360, fill=255, width=5 * K)
ld.arc([c + 4 * K, c - 30 * K, c + 64 * K, c + 30 * K], 200, 260, fill=255, width=5 * K)
lines = down(lines)
save(compose(mask, 6, (255, 252, 244), inner_lines=lines), 'tuft')

# 8. cake_slice: pink-frosted cake slice (heal), inked.
im = canvas()
d = ImageDraw.Draw(im)
tri = [(40, 170), (216, 120), (216, 196), (40, 210)]
d.polygon([(x * K, y * K) for x, y in tri], fill=255)
d.polygon([(40 * K, 170 * K), (216 * K, 120 * K), (196 * K, 92 * K), (52 * K, 150 * K)], fill=255)
mask = down(im)
# Two-tone: frosting top pink, sponge cream, cherry red.
outer = grow(mask, 6)
rgb = Image.new('RGB', (S, S), INK)
rgb.paste(Image.new('RGB', (S, S), (250, 232, 196)), (0, 0), mask)
top = canvas()
ImageDraw.Draw(top).polygon([(40 * K, 170 * K), (216 * K, 120 * K), (196 * K, 92 * K), (52 * K, 150 * K)], fill=255)
ImageDraw.Draw(top).polygon([(40 * K, 170 * K), (216 * K, 120 * K), (216 * K, 140 * K), (40 * K, 186 * K)], fill=255)
rgb.paste(Image.new('RGB', (S, S), (242, 154, 163)), (0, 0), down(top))
cher = canvas()
ImageDraw.Draw(cher).ellipse([150 * K, 60 * K, 196 * K, 106 * K], fill=255)
cm = down(cher)
outer = Image.composite(Image.new('L', (S, S), 255), outer, grow(cm, 6))
rgb.paste(Image.new('RGB', (S, S), INK), (0, 0), grow(cm, 5))
rgb.paste(Image.new('RGB', (S, S), (216, 58, 52)), (0, 0), cm)
r, g, b = rgb.split()
save(Image.merge('RGBA', (r, g, b, outer)), 'cake_slice')

# 9. speed_line: a single inked speed streak (vertical), white core, ink sides, tapered ends.
im = canvas()
d = ImageDraw.Draw(im)
d.polygon([(c, 8 * K), (c + 14 * K, 60 * K), (c + 10 * K, 230 * K), (c, 250 * K), (c - 10 * K, 230 * K), (c - 14 * K, 60 * K)], fill=255)
mask = down(im)
save(compose(mask, 4, (255, 255, 255)), 'speed_line')

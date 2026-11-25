"""Juice fix round 4 (night 02, after JUICE critique round 2): one inked sprite family for every effect.

The VFX art critic found two incompatible style families in the effect library: inked flat cards (impact_star,
glint_ink, splat_ink, page, ...) and airbrushed or photo-soft sprites (puff, sparkle, sparkle_ink, star). This script
authors the missing inked set in the same flat-fill style as impact_star: a flat fill, at most one flat shade band and an
ink #3B2416 rim. White fills are tinted by the particle colour.

  puff_ink, puff_ink_b, puff_ink_c  3-5 round lobes, cream-white fill, one flat shade band, thin ink rim (erodes in fx_inked)
  sparkle_ink   a real inked four-point glint (slim arms, white fill, ink rim); replaces the airbrushed sparkle
  star_ink      a rounded cream five-point star with an ink rim (hurt, bonk and dizzy only)
  tuft          a 6-lobe fleece cloud, white with a lavender-grey shade band, ink rim, NO interior strokes (they read as eyes)
  splat_ink     a cartoon splash of 8 rounded lobes plus droplets (was 16 saw-tooth spikes: a dirt sun)
  gold_leaf     a rounded, curled leaf flake with a light band (was a hexagon that read as a gem)
  sprinkle      a rounded sugar sprinkle (W3 ambient; never the four-point pickup glint)
  glove         the bumble bruiser's boxing glove (red, white cuff, ink rim) for its defeat
  crumb         a gingerbread crumb with a white icing edge and an ink rim (baked colour, not tinted)
  jelly         a squashed translucent jelly blob with a highlight and an ink rim (gummy defeat)
  sunburst      9 tapered gold card rays around an empty centre, gold-orange core, ink edges (TRUFFLE GET; 512 px)
Run from this folder:  python make_fx_textures_r4.py   Writes ../fx/<name>.webp (lossless, straight alpha)."""
import math
import random
from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT = '../fx/'
S = 256
K = 4
INK = (59, 36, 22)


def canvas(s=S):
    return Image.new('L', (s * K, s * K), 0)


def down(im, s=S):
    return im.resize((s, s), Image.LANCZOS)


def grow(mask, px):
    return mask.filter(ImageFilter.MaxFilter(px * 2 + 1)) if px > 0 else mask


def shrink(mask, px):
    return mask.filter(ImageFilter.MinFilter(px * 2 + 1)) if px > 0 else mask


def round_mask(mask, px):
    """Morphological rounding: close the corners so no razor edges remain (ART_V2: chunky and rounded)."""
    m = mask.filter(ImageFilter.GaussianBlur(px))
    return m.point(lambda v: 255 if v > 127 else 0).filter(ImageFilter.GaussianBlur(0.7))


def save(im, name):
    im.save(OUT + name + '.webp', 'WEBP', lossless=True)
    print('wrote', name)


def inked(fill_mask, fill_rgb, rim_px, s=S, extra=None):
    """fill_mask: L mask of the fill (at size s). Returns RGBA with an ink rim of rim_px outside the fill."""
    outer = grow(fill_mask, rim_px).filter(ImageFilter.GaussianBlur(0.8))
    rgb = Image.new('RGB', (s, s), INK)
    rgb.paste(Image.new('RGB', (s, s), fill_rgb), (0, 0), fill_mask)
    if extra:
        for col, m in extra:
            rgb.paste(Image.new('RGB', (s, s), col), (0, 0), ImageChops.multiply(m, fill_mask))
    r, g, b = rgb.split()
    return Image.merge('RGBA', (r, g, b, outer))


def ellipse(d, cx, cy, rx, ry, fill=255):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill)


# 1. puff_ink x3: lobed cartoon puffs, cream-white fill, one flat lower shade band, thin ink rim.
for name, seed, lobes in (('puff_ink', 3, 5), ('puff_ink_b', 7, 4), ('puff_ink_c', 12, 3)):
    random.seed(seed)
    im = canvas()
    d = ImageDraw.Draw(im)
    c = S * K / 2
    ellipse(d, c, c + 8 * K, 62 * K, 56 * K)
    for i in range(lobes):
        a = i / lobes * math.tau + random.uniform(-0.25, 0.25) - math.pi / 2
        rr = random.uniform(40, 52)
        dist = random.uniform(44, 54)
        ellipse(d, c + math.cos(a) * dist * K, c + 6 * K + math.sin(a) * dist * 0.85 * K, rr * K, rr * K)
    fill = round_mask(down(im), 2)
    fill = shrink(fill, 7)
    # One flat shade band: the lower third of the puff, its top edge itself a gentle lobed curve.
    band = canvas()
    bd = ImageDraw.Draw(band)
    for x in range(-2, 7):
        ellipse(bd, x * 40 * K, (S * 0.98) * K, 46 * K, 70 * K)
    bd.rectangle([0, int(S * 0.9) * K, S * K, S * K], fill=255)
    band = down(band).filter(ImageFilter.GaussianBlur(0.6))
    save(inked(fill, (252, 249, 242), 6, extra=[((226, 214, 198), band)]), name)

# 2. sparkle_ink: slim inked four-point glint (concave sides), white fill.
im = canvas()
d = ImageDraw.Draw(im)
c = S * K / 2
pts = []
for i in range(64):
    t = i / 64 * math.tau
    # astroid-like four-point star: r = R * (|cos|^p + |sin|^p)^(-1/p) with p < 1 gives concave sides
    p = 0.62
    cs, sn = math.cos(t), math.sin(t)
    r = 104 / (abs(cs) ** p + abs(sn) ** p) ** (1 / p)
    pts.append((c + cs * r * K, c + sn * r * K))
d.polygon(pts, fill=255)
fill = shrink(down(im).filter(ImageFilter.GaussianBlur(0.6)), 6)
hi = Image.new('L', (S, S), 0)
ellipse(ImageDraw.Draw(hi), 116, 116, 10, 10, 255)
save(inked(fill, (255, 252, 244), 6), 'sparkle_ink')

# 3. star_ink: rounded cream five-point star with an ink rim.
im = canvas()
d = ImageDraw.Draw(im)
pts = []
for i in range(10):
    a = i / 10 * math.tau - math.pi / 2
    r = (100 if i % 2 == 0 else 50) * K
    pts.append((c + math.cos(a) * r, c + 8 * K + math.sin(a) * r))
d.polygon(pts, fill=255)
fill = shrink(round_mask(down(im), 5), 6)
band = Image.new('L', (S, S), 0)
ImageDraw.Draw(band).rectangle([0, 160, S, S], fill=255)
save(inked(fill, (255, 248, 230), 7, extra=[((236, 222, 196), band)]), 'star_ink')

# 4. tuft: 6-lobe fleece cloud, white with a lavender-grey shade band, ink rim, no interior strokes.
random.seed(21)
im = canvas()
d = ImageDraw.Draw(im)
ellipse(d, c, c + 6 * K, 58 * K, 50 * K)
for i in range(6):
    a = i / 6 * math.tau + random.uniform(-0.15, 0.15)
    ellipse(d, c + math.cos(a) * 52 * K, c + 6 * K + math.sin(a) * 44 * K, random.uniform(34, 42) * K, random.uniform(32, 40) * K)
fill = shrink(round_mask(down(im), 2), 7)
band = canvas()
bd = ImageDraw.Draw(band)
for x in range(-2, 8):
    ellipse(bd, x * 34 * K, (S * 0.95) * K, 36 * K, 64 * K)
band = down(band).filter(ImageFilter.GaussianBlur(0.6))
save(inked(fill, (252, 251, 248), 6, extra=[((206, 200, 222), band)]), 'tuft')

# 5. splat_ink: a cartoon splash, 8 rounded lobes and a few droplets (white fill tinted by the ring colour).
random.seed(5)
im = canvas()
d = ImageDraw.Draw(im)
ellipse(d, c, c, 58 * K, 58 * K)
n = 8
for i in range(n):
    a = i / n * math.tau + random.uniform(-0.14, 0.14)
    length = random.uniform(78, 100)
    w = random.uniform(15, 21)
    # a rounded finger: a thick line ending in a ball
    x1, y1 = c + math.cos(a) * length * K, c + math.sin(a) * length * K
    d.line([c, c, x1, y1], fill=255, width=int(w * 2 * K * 0.8))
    ellipse(d, x1, y1, w * K, w * K)
    if random.random() < 0.7:
        a2 = a + math.tau / n / 2
        dd = random.uniform(104, 116)
        rr = random.uniform(7, 10)
        ellipse(d, c + math.cos(a2) * dd * K, c + math.sin(a2) * dd * K, rr * K, rr * K)
fill = shrink(round_mask(down(im), 3), 5)
save(inked(fill, (250, 246, 238), 5), 'splat_ink')

# 6. gold_leaf: a rounded leaf flake (vesica of two circles, curled tip), cream fill tinted gold, a light band.
ia = canvas()
ib = canvas()
ellipse(ImageDraw.Draw(ia), c - 64 * K, c, 118 * K, 118 * K)
ellipse(ImageDraw.Draw(ib), c + 64 * K, c, 118 * K, 118 * K)
im = ImageChops.multiply(ia, ib)
fill = down(im).rotate(28, resample=Image.BICUBIC)
fill = shrink(round_mask(fill, 5), 6)
band = Image.new('L', (S, S), 0)
ImageDraw.Draw(band).ellipse([96, 36, 136, 220], fill=255)
band = band.rotate(28, resample=Image.BICUBIC).filter(ImageFilter.GaussianBlur(1.0))
save(inked(fill, (246, 224, 170), 6, extra=[((255, 246, 214), band)]), 'gold_leaf')

# 7. sprinkle: a rounded sugar sprinkle (capsule), white fill with a flat highlight; no ink (ambient, tiny).
im = canvas()
d = ImageDraw.Draw(im)
d.rounded_rectangle([c - 34 * K, c - 92 * K, c + 34 * K, c + 92 * K], radius=34 * K, fill=255)
fill = down(im).filter(ImageFilter.GaussianBlur(0.8))
fill = fill.rotate(30, resample=Image.BICUBIC)
hi = Image.new('L', (S, S), 0)
ImageDraw.Draw(hi).rounded_rectangle([108, 52, 124, 150], radius=8, fill=255)
hi = hi.rotate(30, resample=Image.BICUBIC).filter(ImageFilter.GaussianBlur(1.0))
rgb = Image.new('RGB', (S, S), (236, 230, 226))
rgb.paste(Image.new('RGB', (S, S), (255, 255, 255)), (0, 0), hi)
r, g, b = rgb.split()
save(Image.merge('RGBA', (r, g, b, fill)), 'sprinkle')

# 8. glove: a red boxing glove with a white cuff (bumble bruiser defeat bits).
im = canvas()
d = ImageDraw.Draw(im)
ellipse(d, c + 22 * K, c + 4 * K, 74 * K, 60 * K)          # fist (side view, knuckles to the right)
ellipse(d, c - 2 * K, c - 50 * K, 34 * K, 24 * K)          # thumb over the top
d.rounded_rectangle([c - 100 * K, c - 38 * K, c - 34 * K, c + 46 * K], radius=14 * K, fill=255)   # cuff on the left
fill = shrink(round_mask(down(im), 3), 6)
cuff = Image.new('L', (S, S), 0)
ImageDraw.Draw(cuff).rectangle([0, 0, 96, S], fill=255)
hi = Image.new('L', (S, S), 0)
ImageDraw.Draw(hi).ellipse([150, 92, 196, 116], fill=255)
save(inked(fill, (214, 52, 46), 7, extra=[((250, 246, 236), cuff), ((246, 120, 104), hi)]), 'glove')

# 9. crumb: gingerbread crumb with a white icing edge and an ink rim (baked colours).
random.seed(9)
im = canvas()
d = ImageDraw.Draw(im)
pts = []
for i in range(9):
    a = i / 9 * math.tau
    r = random.uniform(70, 100)
    pts.append((c + math.cos(a) * r * K, c + 10 * K + math.sin(a) * r * 0.8 * K))
d.polygon(pts, fill=255)
fill = shrink(round_mask(down(im), 6), 6)
icing = Image.new('L', (S, S), 0)
idr = ImageDraw.Draw(icing)
for x in range(30, 230, 26):
    ellipse(idr, x, 72 + (x % 3) * 4, 18, 14, 255)
idr.rectangle([0, 0, S, 66], fill=255)
icing = ImageChops.subtract(fill, shrink(fill, 0)).point(lambda v: 0)  # placeholder (keeps types aligned)
icing_top = Image.new('L', (S, S), 0)
it = ImageDraw.Draw(icing_top)
for x in range(20, 240, 24):
    ellipse(it, x, 88 + 6 * math.sin(x * 0.2), 16, 13, 255)
it.rectangle([0, 0, S, 84], fill=255)
edge = ImageChops.subtract(fill, shrink(fill, 14))
icing = ImageChops.multiply(edge, icing_top)
dots = Image.new('L', (S, S), 0)
for (x, y) in ((110, 150), (150, 170), (96, 186)):
    ellipse(ImageDraw.Draw(dots), x, y, 6, 6, 255)
save(inked(fill, (178, 108, 54), 6, extra=[((252, 248, 240), icing), ((120, 66, 32), dots)]), 'crumb')

# 10. jelly: squashed translucent jelly blob, highlight, ink rim (tinted by the particle colour; white body at 0.8).
im = canvas()
d = ImageDraw.Draw(im)
ellipse(d, c, c + 14 * K, 98 * K, 74 * K)
ellipse(d, c - 30 * K, c - 22 * K, 46 * K, 40 * K)
ellipse(d, c + 34 * K, c - 16 * K, 42 * K, 38 * K)
fill = shrink(round_mask(down(im), 3), 7)
outer = grow(fill, 6).filter(ImageFilter.GaussianBlur(0.8))
rgb = Image.new('RGB', (S, S), INK)
rgb.paste(Image.new('RGB', (S, S), (250, 236, 240)), (0, 0), fill)
core = shrink(fill, 18).filter(ImageFilter.GaussianBlur(6))
rgb.paste(Image.new('RGB', (S, S), (214, 196, 204)), (0, 0), core)
hi = Image.new('L', (S, S), 0)
ImageDraw.Draw(hi).ellipse([74, 66, 120, 92], fill=255)
rgb.paste(Image.new('RGB', (S, S), (255, 255, 255)), (0, 0), hi.filter(ImageFilter.GaussianBlur(1.2)))
alpha = Image.eval(outer, lambda v: v)
body_a = Image.eval(fill, lambda v: int(v * 0.22))   # body at 78 % opacity, rim and highlight solid
alpha = ImageChops.subtract(alpha, body_a)
alpha = ImageChops.lighter(alpha, hi.filter(ImageFilter.GaussianBlur(1.2)))
r, g, b = rgb.split()
save(Image.merge('RGBA', (r, g, b, alpha)), 'jelly')

# 11. sunburst (512 px): 9 tapered gold card rays around an empty centre (radius 0.34), gold-orange core, ink edges.
S2 = 512
im = Image.new('L', (S2 * 2, S2 * 2), 0)
core_im = Image.new('L', (S2 * 2, S2 * 2), 0)
d = ImageDraw.Draw(im)
dc = ImageDraw.Draw(core_im)
c2 = S2
n = 9
random.seed(4)
for i in range(n):
    a = i / n * math.tau + random.uniform(-0.05, 0.05)
    r0, r1 = 0.36 * S2, random.uniform(0.86, 0.97) * S2
    w0, w1 = 0.27, 0.09
    left = (c2 + math.cos(a - w0) * r0, c2 + math.sin(a - w0) * r0)
    right = (c2 + math.cos(a + w0) * r0, c2 + math.sin(a + w0) * r0)
    tipl = (c2 + math.cos(a - w1) * r1, c2 + math.sin(a - w1) * r1)
    tipr = (c2 + math.cos(a + w1) * r1, c2 + math.sin(a + w1) * r1)
    d.polygon([left, tipl, tipr, right], fill=255)
    rc = (r0 + r1) * 0.5
    dc.polygon([(c2 + math.cos(a - w0 * 0.4) * r0, c2 + math.sin(a - w0 * 0.4) * r0), (c2 + math.cos(a) * r1 * 0.9, c2 + math.sin(a) * r1 * 0.9),
                (c2 + math.cos(a + w0 * 0.4) * r0, c2 + math.sin(a + w0 * 0.4) * r0)], fill=255)
fill = im.resize((S2, S2), Image.LANCZOS)
fill = shrink(round_mask(fill, 3), 5)
core_m = core_im.resize((S2, S2), Image.LANCZOS).filter(ImageFilter.GaussianBlur(2))
save(inked(fill, (255, 201, 60), 7, s=S2, extra=[((201, 130, 42), core_m)]), 'sunburst')

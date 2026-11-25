"""Juice fix round 2 (night 01): more procedural inked particle sprites of our own.
  impact_star   hit impact: 7 irregular spikes, white fill, gold inner rim, ink outline (fx_inked.gdshader erodes it hollow)
  dust_crescent ground dust: a flat-bottomed, three-lobed dust bank with a soft warm ink edge (tinted by the particle colour)
  cocoa_drop    hot-chocolate droplet: baked cocoa brown with a cream highlight and an ink outline (no meatballs)
  top_hat       the wolf's top hat for the boss-defeat punchline (charcoal with a plum band, inked)
Run from this folder:  python make_fx_textures_r2.py   Writes ../fx/<name>.webp (lossless, 256 px, straight alpha)."""
import math
import random
from PIL import Image, ImageDraw, ImageFilter

OUT = '../fx/'
S = 256
K = 4
INK = (59, 36, 22)


def canvas():
    return Image.new('L', (S * K, S * K), 0)


def down(im):
    return im.resize((S, S), Image.LANCZOS)


def grow(mask, px):
    return mask.filter(ImageFilter.MaxFilter(px * 2 + 1)) if px > 0 else mask


def shrink(mask, px):
    return mask.filter(ImageFilter.MinFilter(px * 2 + 1)) if px > 0 else mask


def save(im, name):
    im.save(OUT + name + '.webp', 'WEBP', lossless=True)
    print('wrote', name)


c = S * K / 2

# 1. impact_star: 7 irregular spikes (long/short alternation jittered), white fill, gold inner rim, ink outline.
random.seed(11)
im = canvas()
d = ImageDraw.Draw(im)
pts = []
n = 7
for i in range(n * 2):
    a = i / (n * 2) * math.tau + random.uniform(-0.09, 0.09) - math.pi / 2
    if i % 2 == 0:
        r = random.uniform(0.78, 1.0) * 108
    else:
        r = random.uniform(0.40, 0.50) * 108
    pts.append((c + math.cos(a) * r * K, c + math.sin(a) * r * K))
d.polygon(pts, fill=255)
mask = down(im)
outer = grow(mask, 6)
rim = Image.eval(mask, lambda v: v)  # gold band = mask minus its eroded core
core = shrink(mask, 9).filter(ImageFilter.GaussianBlur(1.5))
rgb = Image.new('RGB', (S, S), INK)
rgb.paste(Image.new('RGB', (S, S), (255, 205, 92)), (0, 0), rim)       # gold rim
rgb.paste(Image.new('RGB', (S, S), (255, 252, 242)), (0, 0), core)     # white fill
r, g, b = rgb.split()
save(Image.merge('RGBA', (r, g, b, outer)), 'impact_star')

# 2. dust_crescent: flat-bottomed dust bank of three lobes; white fill (tinted), warm soft ink edge, a light top highlight.
im = canvas()
d = ImageDraw.Draw(im)
base_y = 176
for (x, y, rr) in [(-62, 150, 46), (0, 128, 62), (60, 148, 48), (-96, 166, 26), (96, 166, 26)]:
    d.ellipse([c + (x - rr) * K, (y - rr) * K, c + (x + rr) * K, (y + rr) * K], fill=255)
d.rectangle([c - 100 * K, 150 * K, c + 100 * K, base_y * K], fill=255)
# crescent: carve the bottom into a gentle smile so the bank reads as a rolling crescent, not a box
d.ellipse([c - 150 * K, base_y * K - 18 * K, c + 150 * K, base_y * K + 60 * K], fill=0)
mask = down(im).filter(ImageFilter.GaussianBlur(0.8))
outer = grow(mask, 4).filter(ImageFilter.GaussianBlur(1.2))
rgb = Image.new('RGB', (S, S), (196, 166, 132))                         # soft warm edge (tinted; darker read as pebbles)
rgb.paste(Image.new('RGB', (S, S), (238, 230, 216)), (0, 0), mask)      # body
hi = Image.new('L', (S, S), 0)
ImageDraw.Draw(hi).ellipse([96, 74, 150, 104], fill=230)
hi = hi.filter(ImageFilter.GaussianBlur(9))
rgb.paste(Image.new('RGB', (S, S), (255, 255, 255)), (0, 0), hi)
r, g, b = rgb.split()
save(Image.merge('RGBA', (r, g, b, outer)), 'dust_crescent')

# 3. cocoa_drop: teardrop, cocoa brown body, darker lower shade, cream highlight, ink outline (baked colour; tint white).
im = canvas()
d = ImageDraw.Draw(im)
pts = []
for i in range(120):
    t = i / 120 * math.tau
    # teardrop: point at the top
    x = math.sin(t) * (1 - math.cos(t)) * 0.5
    y = -math.cos(t)
    pts.append((c + x * 120 * K, c + 10 * K + y * 104 * K))
d.polygon(pts, fill=255)
mask = down(im)
outer = grow(mask, 6)
rgb = Image.new('RGB', (S, S), INK)
rgb.paste(Image.new('RGB', (S, S), (122, 66, 34)), (0, 0), mask)
shade = Image.new('L', (S, S), 0)
ImageDraw.Draw(shade).ellipse([60, 150, 230, 260], fill=200)
shade = Image.composite(shade.filter(ImageFilter.GaussianBlur(14)), Image.new('L', (S, S), 0), mask)
rgb.paste(Image.new('RGB', (S, S), (86, 44, 22)), (0, 0), shade)
hi = Image.new('L', (S, S), 0)
ImageDraw.Draw(hi).ellipse([96, 120, 124, 166], fill=255)
hi = hi.filter(ImageFilter.GaussianBlur(3))
rgb.paste(Image.new('RGB', (S, S), (255, 240, 214)), (0, 0), hi)
r, g, b = rgb.split()
save(Image.merge('RGBA', (r, g, b, outer)), 'cocoa_drop')

# 4. top_hat: charcoal crown, plum band, brim, ink outline, a soft sheen stripe.
im = canvas()
d = ImageDraw.Draw(im)
d.rounded_rectangle([c - 58 * K, 40 * K, c + 58 * K, 176 * K], radius=10 * K, fill=255)       # crown
d.ellipse([c - 108 * K, 160 * K, c + 108 * K, 204 * K], fill=255)                            # brim
mask = down(im)
outer = grow(mask, 6)
rgb = Image.new('RGB', (S, S), INK)
rgb.paste(Image.new('RGB', (S, S), (58, 54, 66)), (0, 0), mask)
band = canvas()
ImageDraw.Draw(band).rectangle([c - 58 * K, 134 * K, c + 58 * K, 162 * K], fill=255)
rgb.paste(Image.new('RGB', (S, S), (142, 52, 92)), (0, 0), Image.composite(down(band), Image.new('L', (S, S), 0), mask))
sheen = Image.new('L', (S, S), 0)
ImageDraw.Draw(sheen).rectangle([96, 52, 108, 128], fill=150)
sheen = sheen.filter(ImageFilter.GaussianBlur(3))
rgb.paste(Image.new('RGB', (S, S), (150, 146, 168)), (0, 0), sheen)
r, g, b = rgb.split()
save(Image.merge('RGBA', (r, g, b, outer)), 'top_hat')

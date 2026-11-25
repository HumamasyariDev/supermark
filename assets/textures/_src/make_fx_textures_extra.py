"""Extra procedural particle sprites (juice track, night 01 implementation stage).
exclaim: a bold storybook '!' (white fill, dark ink outline) for enemy_notice; tinted by particle colour."""
import math
from PIL import Image, ImageDraw, ImageFilter
OUT = '../fx/'
S = 256
K = 4  # supersample


def bang_mask(grow=0):
    im = Image.new('L', (S * K, S * K), 0)
    d = ImageDraw.Draw(im)
    g = grow * K
    # Tapered bar: wide rounded top, narrow bottom.
    top_w, bot_w = 70 * K, 36 * K
    cx = S * K / 2
    y0, y1 = 48 * K, 166 * K
    pts = [(cx - top_w / 2 - g, y0 - g), (cx + top_w / 2 + g, y0 - g), (cx + bot_w / 2 + g, y1 + g), (cx - bot_w / 2 - g, y1 + g)]
    d.polygon(pts, fill=255)
    d.ellipse([cx - top_w / 2 - g, y0 - 30 * K - g, cx + top_w / 2 + g, y0 + 30 * K + g], fill=255)
    d.ellipse([cx - bot_w / 2 - g, y1 - 20 * K - g, cx + bot_w / 2 + g, y1 + 20 * K + g], fill=255)
    # Dot.
    r = 24 * K + g
    dy = 214 * K
    d.ellipse([cx - r, dy - r, cx + r, dy + r], fill=255)
    return im.resize((S, S), Image.LANCZOS)


outer = bang_mask(9)
inner = bang_mask(0)
# Slight jaunty tilt for the storybook look.
outer = outer.rotate(-8, resample=Image.BICUBIC)
inner = inner.rotate(-8, resample=Image.BICUBIC)
hi = Image.new('L', (S, S), 0)
hd = ImageDraw.Draw(hi)
hd.ellipse([108, 32, 128, 96], fill=255)  # glossy highlight on the bar
hi = hi.rotate(-8, resample=Image.BICUBIC).filter(ImageFilter.GaussianBlur(3))
rgb = Image.new('L', (S, S), 38)
fill = Image.new('L', (S, S), 238)
rgb.paste(fill, (0, 0), inner)
rgb.paste(Image.new('L', (S, S), 255), (0, 0), hi.point(lambda v: v * 0.8))
im = Image.merge('RGBA', (rgb, rgb, rgb, outer))
im.save(OUT + 'exclaim.webp', 'WEBP', lossless=True)
print('done')

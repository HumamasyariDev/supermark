"""Procedural particle sprites for Super Mak 64 VFX (white/grey with alpha, tinted by particle colour)."""
import numpy as np, math
from PIL import Image, ImageDraw, ImageFilter
OUT = '../fx/'
S = 256
yy, xx = np.mgrid[0:S, 0:S].astype(float)
cx = cy = (S - 1) / 2

def save(rgb, a, name):
    rgb = np.clip(rgb, 0, 255).astype(np.uint8); a = np.clip(a, 0, 255).astype(np.uint8)
    im = np.dstack([rgb, rgb, rgb, a]) if rgb.ndim == 2 else np.dstack([rgb, a])
    Image.fromarray(im, 'RGBA').save(OUT + name + '.webp', 'WEBP', lossless=True)

r = np.hypot(xx - cx, yy - cy) / (S / 2)
# soft dot
save(np.full((S, S), 255.), (np.clip(1 - r, 0, 1) ** 1.8) * 255, 'soft_dot')
# puff: union of circles, shaded light top-left, darker bottom, crisp-soft edge
rng = np.random.default_rng(4)
mask = np.zeros((S, S)); shade = np.zeros((S, S))
blobs = [(0, 0.1, 0.55)] + [(math.cos(a) * 0.38, math.sin(a) * 0.3 + 0.05, 0.36 + rng.random() * 0.1) for a in np.linspace(0, 2 * math.pi, 7, endpoint=False)]
for bx, by, br in blobs:
    px, py = cx + bx * S / 2, cy + by * S / 2
    d = np.hypot(xx - px, yy - py) / (br * S / 2)
    m = np.clip((1 - d) * 6, 0, 1)
    sh = np.clip(1 - np.hypot(xx - (px - br * 30), yy - (py - br * 40)) / (br * S / 2 * 1.4), 0, 1)
    mask = np.maximum(mask, m); shade = np.maximum(shade, sh * m)
mask *= np.clip((0.97 - r) * 8, 0, 1)
# Volume: bright top-left lobes, a cool darker underside, painted rim.
under = np.clip((yy - cy) / (S * 0.45), 0, 1)
rgb = 150 + 105 * np.clip(shade * 1.5, 0, 1) - 35 * under
save(rgb, mask * 255, 'puff')
# star (5 point, rounded)
def star_mask(points=5, inner=0.45, rot=-math.pi / 2):
    im = Image.new('L', (S * 4, S * 4), 0); d = ImageDraw.Draw(im)
    pts = []
    for i in range(points * 2):
        ang = rot + i * math.pi / points
        rad = (0.92 if i % 2 == 0 else 0.92 * inner) * S * 2
        pts.append((S * 2 + math.cos(ang) * rad, S * 2 + math.sin(ang) * rad))
    d.polygon(pts, fill=255)
    im = im.filter(ImageFilter.GaussianBlur(10)).point(lambda v: 255 if v > 110 else int(v * 2.3))
    return np.asarray(im.resize((S, S), Image.LANCZOS)).astype(float)
st = star_mask()
# Outlined star: a slightly bigger dark silhouette behind a bright, softly shaded fill.
big = np.asarray(Image.fromarray(st.astype(np.uint8)).filter(ImageFilter.MaxFilter(15))).astype(float)
inner_shade = 205 + 50 * np.clip(1 - np.hypot(xx - cx + 20, yy - cy + 25) / (S * 0.55), 0, 1)
star_rgb = np.where(st > 128, inner_shade, 95.0)
save(star_rgb, np.maximum(st, big), 'star')
# sparkle: 4-point twinkle with glow
ax = np.abs(xx - cx) / (S / 2); ay = np.abs(yy - cy) / (S / 2)
tw = np.clip(1 - (ax ** 0.5 + ay ** 0.5) / 1.0, 0, 1) ** 1.2
glow = np.clip(1 - r, 0, 1) ** 4
save(np.full((S, S), 255.), np.clip(tw * 1.6 + glow * 0.6, 0, 1) * 255, 'sparkle')
# Sparkle with a thin darker rim, readable when mix-blended on bright ground.
tw_core = np.clip(tw * 1.8, 0, 1)
tw_big = np.clip(np.clip(1 - (ax ** 0.5 + ay ** 0.5) / 1.12, 0, 1) ** 1.1 * 2.2, 0, 1)
save(np.where(tw_core > 0.35, 255.0, 150.0), np.maximum(tw_core, tw_big) * 255, 'sparkle_ink')
# ring
ring = np.clip(1 - np.abs(r - 0.82) / 0.1, 0, 1) ** 1.5
inner = np.clip(1 - np.abs(r - 0.82) / 0.25, 0, 1) * 0.25 * (r < 0.82)
save(np.full((S, S), 255.), np.clip(ring + inner, 0, 1) * 255, 'ring')
# leaf: almond shape with midrib
u = (xx - cx) / (S / 2); v = (yy - cy) / (S / 2)
leaf = (np.abs(u) < 0.55 * (1 - v ** 2) ** 0.8) & (np.abs(v) < 0.95)
lm = Image.fromarray((leaf * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))
lrgb = 205 + 50 * (u > 0) - 60 * (np.abs(u) < 0.03) + 20 * (1 - np.abs(v))
save(lrgb, np.asarray(lm).astype(float), 'leaf')
# feather: long curved vane
fe = np.zeros((S, S))
for i in range(S):
    t = i / S
    w = 0.32 * math.sin(math.pi * min(t * 1.1, 1)) * S / 2
    c = cx + math.sin(t * 2.5) * 18
    fe[i] = np.clip((w - np.abs(np.arange(S) - c)) / 2, 0, 1) if t < 0.92 else 0
fe[:, :] = np.maximum(fe, ((np.abs(xx - (cx + np.sin(yy / S * 2.5) * 18)) < 2.5) & (yy > S * 0.1)) * 1.0)
barbs = 0.85 + 0.15 * np.sin((yy + np.abs(xx - cx) * 1.2) * 0.45)
save(235 * barbs, fe * 255, 'feather')
# page: paper rectangle with lines
pg = np.zeros((S, S)); prgb = np.full((S, S), 245.)
x0, x1, y0, y1 = 40, 216, 20, 236
pg[y0:y1, x0:x1] = 255
for ly in range(50, 220, 16):
    prgb[ly:ly + 3, 60:196] = 170
prgb[y0:y1, x0:x0 + 6] = 215
save(prgb, pg, 'page')
# butterfly: two wings on a quad, left and right halves (shader folds along x centre)
bw = np.zeros((S, S))
for sx in (-1, 1):
    for (oy, rr, sc) in ((-0.22, 0.5, 1.0), (0.3, 0.36, 0.85)):
        px = cx + sx * 0.42 * S / 2; py = cy + oy * S / 2
        d = np.hypot((xx - px) / (rr * S / 2), (yy - py) / (rr * S / 2 * sc))
        bw = np.maximum(bw, np.clip((1 - d) * 8, 0, 1))
bw[np.abs(xx - cx) < 4] = 0
body = (np.abs(xx - cx) < 7) & (np.abs(yy - cy) < S * 0.33)
spots = np.zeros((S, S))
for sx in (-1, 1):
    d = np.hypot(xx - (cx + sx * 0.5 * S / 2), yy - (cy - 0.25 * S / 2)) / 16
    spots = np.maximum(spots, d < 1)
brgb = np.where(body, 60, np.where(spots, 255, 225 - 50 * np.clip(np.hypot(xx - cx, yy - cy) / (S / 2), 0, 1)))
save(brgb, np.maximum(bw, body) * 255, 'butterfly')
# wind streak: horizontal tapered line
wl = np.clip(1 - np.abs(yy - cy) / 9, 0, 1) * np.clip(np.sin(np.clip(xx / S, 0, 1) * math.pi), 0, 1) ** 0.7
save(np.full((S, S), 255.), wl * 255, 'streak')
# confetti: rounded rect
cf = np.zeros((S, S)); cf[64:192, 32:224] = 1
cfm = np.asarray(Image.fromarray((cf * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))).astype(float)
save(np.full((S, S), 255.) - 25 * (yy > cy), cfm, 'confetti')
print('done')

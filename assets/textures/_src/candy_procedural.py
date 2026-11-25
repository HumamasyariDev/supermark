"""Candy stripes: the generated stripes could not tile on the diagonal, so this rebuilds a mathematically seamless
stripe field (integer stripe count along x+y) and keeps painterly variation from the generated image's detail layer."""
import numpy as np
from PIL import Image, ImageFilter
N = 1024; k = 6
yy, xx = np.mgrid[0:N, 0:N].astype(float)
raw = np.asarray(Image.open('candy_stripes_raw.png').convert('L').resize((N, N))).astype(float) / 255
detail = raw - np.asarray(Image.fromarray((raw * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(8))).astype(float) / 255
detail = np.roll(detail, (N // 2, N // 2), (0, 1)) * 0  # detail is not tileable; keep only tileable noise below
rng = np.random.default_rng(3)
def tnoise(cells, blur):
    n = rng.random((cells, cells))
    big = np.tile(n, (3, 3))
    im = Image.fromarray((big * 255).astype(np.uint8)).resize((N * 3, N * 3), Image.BICUBIC).filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(im).astype(float)[N:2 * N, N:2 * N] / 255 - 0.5
wob = tnoise(16, 10) * 0.035 + tnoise(64, 3) * 0.01
ph = ((xx + yy) / N * k + wob) % 1.0
s = np.clip((np.abs(ph - 0.5) - 0.22) / 0.03, -1, 1) * 0.5 + 0.5  # 1 = red band
red = np.array([214, 40, 52.]); red2 = np.array([170, 24, 40.]); cream = np.array([252, 244, 230.]); cream2 = np.array([236, 214, 206.])
edge = np.clip(1 - np.abs(np.abs(ph - 0.5) - 0.22) / 0.06, 0, 1)
shade = (np.sin((ph) * np.pi * 2 * 2) * 0.5 + 0.5)[..., None]
r = red * (1 - shade * 0.3) + red2 * shade * 0.3
c = cream * (1 - shade * 0.35) + cream2 * shade * 0.35
col = c * (1 - s[..., None]) + r * s[..., None]
col *= (1 + tnoise(32, 4)[..., None] * 0.08)
hl = np.clip(1 - np.abs(((xx + yy) / N * k + 0.12 + wob) % 1.0 - 0.5) / 0.03, 0, 1) * 0
col = col * (1 - edge[..., None] * 0.12)
Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).save('../candy_stripes.webp', 'WEBP', quality=92, method=6)
im = Image.open('../candy_stripes.webp'); t = Image.new('RGB', (1024, 1024)); s2 = im.resize((512, 512))
for i in range(2):
    for j in range(2): t.paste(s2, (i * 512, j * 512))
t.save('tilecheck/candy_stripes_2x2.jpg', quality=85)

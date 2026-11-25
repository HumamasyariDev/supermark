"""Seam fix for generated textures. Organic textures: offset-by-half + noise-mask blend.
Structured textures (rows/grids): short mirrored edge cross-fade so feature rows are not ghosted.
Writes ../<name>.webp (1024 px) and a 2x2 tiling check into _src/tilecheck/."""
import numpy as np, glob, os, json, hashlib
from PIL import Image, ImageFilter
STRUCT = {'brick', 'candy_stripes', 'chocolate', 'wood_planks', 'bookshelf_wood', 'straw_thatch', 'bark', 'cliff_rock',
          'roof_tiles', 'library_carpet', 'damask_wallpaper', 'beanstalk_skin', 'castle_stone', 'roof_shingles_slate'}
import sys
os.makedirs('tilecheck', exist_ok=True)
rng = np.random.default_rng(7)

def edge_fade(a, b=40):
    a = a.copy()
    for axis in (0, 1):
        src = a.copy()
        n = a.shape[axis]
        for i in range(b):
            w = 0.5 * (1 - i / b) ** 1.5
            if axis == 1:
                a[:, i] = (1 - w) * src[:, i] + w * src[:, n - 1 - i]
                a[:, n - 1 - i] = (1 - w) * src[:, n - 1 - i] + w * src[:, i]
            else:
                a[i] = (1 - w) * src[i] + w * src[n - 1 - i]
                a[n - 1 - i] = (1 - w) * src[n - 1 - i] + w * src[i]
    return a

def offset_blend(a, band=150):
    h, w, _ = a.shape
    r = np.roll(a, (h // 2, w // 2), (0, 1))  # seams now at centre cross
    yy, xx = np.mgrid[0:h, 0:w]
    noise = Image.fromarray((rng.random((h // 16, w // 16)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    noise = np.asarray(noise.filter(ImageFilter.GaussianBlur(6))).astype(float) / 255 - 0.5
    dx = np.abs(xx - w / 2) / band + noise * 0.8
    dy = np.abs(yy - h / 2) / band + noise * 0.8
    m = np.clip(1 - np.minimum(dx, dy), 0, 1)
    m = m * m * (3 - 2 * m)
    # m=1 where r has its seam: use the original (continuous there).
    return r * (1 - m[..., None]) + a * m[..., None]

out = json.load(open('seamless_report.json')) if os.path.exists('seamless_report.json') else {}
only = set(sys.argv[1:])
for f in sorted(glob.glob('*_raw.png')):
    name = f[:-8]
    if only and name not in only:
        continue
    rng = np.random.default_rng(abs(hash(name)) % 1000)
    a = np.asarray(Image.open(f).convert('RGB').resize((1024, 1024), Image.LANCZOS)).astype(float)
    b = edge_fade(a) if name in STRUCT else offset_blend(a)
    im = Image.fromarray(np.clip(b, 0, 255).astype(np.uint8))
    dst = f'../{name}.webp'
    im.save(dst, 'WEBP', quality=92, method=6)
    t = Image.new('RGB', (1024, 1024)); s = im.resize((512, 512))
    for i in range(2):
        for j in range(2): t.paste(s, (i * 512, j * 512))
    t.save(f'tilecheck/{name}_2x2.jpg', quality=85)
    c = np.asarray(im).astype(float)
    out[name] = {'wrap_err': round(float(np.abs(c[:, 0] - c[:, -1]).mean() + np.abs(c[0] - c[-1]).mean()), 2),
                 'method': 'edge_fade' if name in STRUCT else 'offset_blend',
                 'sha256': hashlib.sha256(open(dst, 'rb').read()).hexdigest()}
    print(name, out[name])
json.dump(out, open('seamless_report.json', 'w'), indent=2)

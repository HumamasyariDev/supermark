"""W1 Huff & Puff Hollow terrain generator (deterministic).

Ports the reference height function from Docs/levels/W1.md section 4 (numbers from data/levels/W1.json)
and writes, next to this folder:
  ../w1_terrain.bin   header 'W1T1', int32 n, float32 x0, z0, step, then n*n float32 heights (row-major, z then x),
                      then n*n*4 uint8 masks (R dirt/cobble path, G cobble, B stream bank/wet, A rock hint)
  ../w1_level.json    copy of data/levels/W1.json plus "_derived" (sampled splines) for the Godot builder
Run from anywhere:  python game/assets/environment/w1/tools/w1_terrain.py
"""
import json
import struct
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
OUT = HERE.parent
ENTITY = HERE.parents[4]
SRC = ENTITY / 'data' / 'levels' / 'W1.json'

N = 241
X0 = -60.0
STEP = 0.5


def smoothstep(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def catmull(points, samples=8):
    p = [np.array(q, dtype=float) for q in points]
    pts = [p[0] - (p[1] - p[0])] + p + [p[-1] + (p[-1] - p[-2])]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(samples):
            t = s / samples
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(p[-1])
    return np.array(out)


def dist_and_y(x, z, samples):
    """samples: (m, 3) as x, y, z  or (m, 2) as x, z. Returns min distance and y interpolated on the nearest segment."""
    if samples.shape[1] == 2:
        sx, sz = samples[:, 0], samples[:, 1]
        sy = np.zeros(len(samples))
    else:
        sx, sy, sz = samples[:, 0], samples[:, 1], samples[:, 2]
    best_d = np.full(x.shape, 1e9)
    best_y = np.zeros(x.shape)
    for i in range(len(samples) - 1):
        ax, az, bx, bz = sx[i], sz[i], sx[i + 1], sz[i + 1]
        dx, dz = bx - ax, bz - az
        L2 = dx * dx + dz * dz
        if L2 < 1e-12:
            continue
        t = np.clip(((x - ax) * dx + (z - az) * dz) / L2, 0, 1)
        px, pz = ax + t * dx, az + t * dz
        d = np.hypot(x - px, z - pz)
        y = sy[i] + t * (sy[i + 1] - sy[i])
        m = d < best_d
        best_d = np.where(m, d, best_d)
        best_y = np.where(m, y, best_y)
    return best_d, best_y


def plateau(x, z, cx, cz, rx, rz, top, skirt, **_):
    d = np.sqrt(((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2)
    out = (d - 1.0) * min(rx, rz)
    return np.where(d <= 1, top, top * smoothstep(1 - out / skirt))


def build(level, x, z):
    t = level['terrain']
    nz = t['noise']
    h = nz['base'] + nz['a1'] * np.sin(nz['kx1'] * x) * np.cos(nz['kz1'] * z) + nz['a2'] * np.sin(nz['k2'] * (x + z))
    for f in t['plateaus']:
        h = np.maximum(h, plateau(x, z, **f))
    b = t['berm']
    m = np.maximum(abs(x), abs(z))
    h = h + b['height'] * smoothstep((m - b['start']) / b['width'])
    path_mask = np.zeros(x.shape)
    cobble = np.zeros(x.shape)
    for p in level['splines']['paths']:
        s = catmull(p['points'])
        d, py = dist_and_y(x, z, s)
        k = smoothstep((d - p['width'] / 2) / p['shoulder'])
        h = py * (1 - k) + h * k
        # Visible lane surface: full inside the half width, soft 0.6 m edge.
        w = 1 - smoothstep((d - p['width'] / 2 + 0.3) / 0.9)
        if p.get('surface') == 'grass_track':
            w = w * 0.55
        path_mask = np.maximum(path_mask, w)
        if p.get('surface') == 'cobble':
            cobble = np.maximum(cobble, w)
    for pad in t['pads']:
        k = smoothstep((np.hypot(x - pad['cx'], z - pad['cz']) - pad['r']) / pad['blend'])
        h = pad['y'] * (1 - k) + h * k
    st = t['stream']
    s = catmull(st['points'])
    d, _ = dist_and_y(x, z, s)
    w = st['width'] / 2
    bed = st['bed_y'] + (st['water_y'] - st['bed_y']) * (d / w) ** 2
    k = smoothstep((d - w) / st['bank'])
    bank = st['water_y'] * (1 - k) + h * k
    h = np.minimum(h, np.where(d < w, bed, bank))
    wet = 1 - smoothstep((d - w) / 2.5)
    return h, path_mask, cobble, wet


def main():
    level = json.loads(SRC.read_text(encoding='utf-8'))
    xs = X0 + STEP * np.arange(N)
    X, Z = np.meshgrid(xs, xs)  # rows = z, cols = x
    h, path, cobble, wet = build(level, X, Z)
    # Rock hint: slope steeper than about 40 degrees.
    gz, gx = np.gradient(h, STEP)
    slope = np.degrees(np.arctan(np.hypot(gx, gz)))
    rock = smoothstep((slope - 34) / 12)
    masks = np.stack([path, cobble, wet, rock], axis=-1)
    masks = (np.clip(masks, 0, 1) * 255 + 0.5).astype(np.uint8)
    with open(OUT / 'w1_terrain.bin', 'wb') as f:
        f.write(b'W1T1')
        f.write(struct.pack('<ifff', N, X0, X0, STEP))
        f.write(h.astype('<f4').tobytes())
        f.write(masks.tobytes())
    derived = {
        'stream_samples': catmull(level['splines']['stream']['points']).round(4).tolist(),
        'path_samples': {p['id']: catmull(p['points']).round(4).tolist() for p in level['splines']['paths']},
        'grid': {'n': N, 'x0': X0, 'step': STEP},
    }
    level['_derived'] = derived
    (OUT / 'w1_level.json').write_text(json.dumps(level, indent=1), encoding='utf-8')

    def ground(px, pz):
        hh, *_ = build(level, np.array([px]), np.array([pz]))
        return float(hh[0])
    # Check: spawn, checkpoint and landmark heights against the plan.
    worst = 0.0
    rows = []
    for grp in ('spawns', 'checkpoints'):
        for s in level[grp]:
            g = ground(s['pos'][0], s['pos'][2])
            err = g - s['pos'][1]
            worst = max(worst, abs(err))
            rows.append(f"{grp[:-1]:10s} {s['id']:14s} plan {s['pos'][1]:6.2f} ground {g:6.2f} err {err:+.3f}")
    print('\n'.join(rows))
    print(f'heights {h.min():.2f}..{h.max():.2f}; worst spawn/checkpoint error {worst:.3f} m')


if __name__ == '__main__':
    main()

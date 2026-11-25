"""Enemy-visuals critique r1: measure readability of every enemy shot made by CritEnemyVisualR1.

For each (color, mask) pair: enemy pixel height, mean colour vs. the surrounding ring (CIELAB dE76),
WCAG luminance contrast, and the 'camouflage' share of the boundary ring whose colour is within dE 15 of
the enemy's own mean. Writes metrics.json/metrics.csv plus per-world sheets:
  <tag>_context_sheet.png  (crops at gameplay distance, labelled)
  <tag>_silhouette64.png   (each mask scaled to 64 px tall, black on white: the ART_V2 silhouette rule)
Usage: python analyse_r1.py <raw dir> <out dir>
"""
import csv
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont


def srgb_to_lin(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lab(rgb):
    arr = np.asarray(rgb, dtype=np.uint8).reshape(-1, 1, 3)
    return cv2.cvtColor(arr, cv2.COLOR_RGB2LAB).reshape(-1, 3).astype(np.float32) * np.array([100 / 255, 1, 1]) - np.array([0, 128, 128])


def rel_lum(rgb_mean):
    l = srgb_to_lin(np.asarray(rgb_mean, dtype=np.float64))
    return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]


def font(sz):
    for f in ("C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"):
        try:
            return ImageFont.truetype(f, sz)
        except OSError:
            pass
    return ImageFont.load_default()


def analyse(shot):
    col = np.array(Image.open(shot["color"]).convert("RGB"))
    m = np.array(Image.open(shot["mask"]).convert("L")) > 100
    if m.sum() == 0 or m.mean() > 0.6:
        return None
    bgp = shot.get("bg")
    bg = np.array(Image.open(bgp).convert("RGB")) if bgp and Path(bgp).exists() else None
    k = np.ones((3, 3), np.uint8)
    mask = m.astype(np.uint8)
    full_px = int(mask.sum())
    if bg is not None:
        diff = np.abs(col.astype(np.int16) - bg.astype(np.int16)).max(axis=2)
        vis = ((diff > 14) & m).astype(np.uint8)
        vis = cv2.morphologyEx(vis, cv2.MORPH_CLOSE, k) & mask
    else:
        vis = mask
    vis_frac = float(vis.sum()) / max(full_px, 1)
    ys, xs = np.nonzero(mask)
    if vis.sum() < 30:
        e_px = col[mask.astype(bool)]
    else:
        e_px = col[vis.astype(bool)]
    ref = bg if bg is not None else col
    ring = cv2.dilate(mask, k, iterations=10) & (1 - cv2.dilate(mask, k, iterations=3))
    r_px = ref[ring.astype(bool)]
    e_lab = lab(e_px)
    r_lab = lab(r_px)
    e_mean = e_lab.mean(0)
    r_mean = r_lab.mean(0)
    de = float(np.linalg.norm(e_mean - r_mean))
    # Per-pixel: enemy colour vs. what is behind it (bg pass), the honest 'does it pop' number.
    if bg is not None and vis.sum() >= 30:
        a = lab(col[vis.astype(bool)])
        b = lab(bg[vis.astype(bool)])
        dpp = np.linalg.norm(a - b, axis=1)
        camo = float((dpp < 15).mean())
        # Silhouette edge: 2 px inner band of the visible mask vs. the background at the same pixels.
        inner = vis & (1 - cv2.erode(vis, k, iterations=2))
        ia = lab(col[inner.astype(bool)])
        ib = lab(bg[inner.astype(bool)])
        edge = float(np.median(np.linalg.norm(ia - ib, axis=1)))
    else:
        camo, edge = 1.0, 0.0
    l1, l2 = rel_lum(e_px.mean(0)), rel_lum(r_px.mean(0))
    wcag = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    e_ch = float(np.hypot(e_mean[1], e_mean[2]))
    r_ch = float(np.hypot(r_mean[1], r_mean[2]))
    dh = float(abs((np.degrees(np.arctan2(e_mean[2], e_mean[1])) - np.degrees(np.arctan2(r_mean[2], r_mean[1])) + 180) % 360 - 180))
    return {
        "name": shot["name"], "family": shot.get("family"), "gap": shot.get("gap"), "lineup": bool(shot.get("lineup", False)),
        "cam_dist_m": round(shot.get("cam_dist", 0), 1), "model_h_m": round(shot.get("height", 0), 2),
        "px_h": int(ys.max() - ys.min() + 1), "px_area": full_px, "visible_frac": round(vis_frac, 2), "frame_h": col.shape[0],
        "dE_mean": round(de, 1), "dE_edge": round(edge, 1), "wcag": round(wcag, 2), "camo_share": round(camo, 2),
        "enemy_L": round(float(e_mean[0]), 1), "ring_L": round(float(r_mean[0]), 1), "enemy_chroma": round(e_ch, 1),
        "ring_chroma": round(r_ch, 1), "hue_diff": round(dh, 0),
        "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
        "color": shot["color"], "mask": shot["mask"],
    }


def grade(r):
    # Readability verdict at gameplay distance (heuristic, tuned on the night-01 captures):
    if r.get("visible_frac", 1) < 0.35:
        return "occluded"
    if r["dE_edge"] >= 25 and r["camo_share"] <= 0.25:
        return "clear"
    if r["dE_edge"] >= 15 and r["camo_share"] <= 0.45:
        return "ok"
    return "weak"


def sheets(tag, rows, out):
    f = font(18)
    fs = font(14)
    cells = []
    for r in rows:
        col = Image.open(r["color"]).convert("RGB")
        x0, y0, x1, y1 = r["bbox"]
        h = max(y1 - y0, 20)
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        half = int(h * 1.6) + 30
        box = (max(cx - half, 0), max(cy - half, 0), min(cx + half, col.width), min(cy + half, col.height))
        crop = col.crop(box).resize((300, 300), Image.LANCZOS)
        cell = Image.new("RGB", (300, 360), (243, 230, 196))
        cell.paste(crop, (0, 0))
        d = ImageDraw.Draw(cell)
        g = grade(r)
        colr = {"clear": (40, 120, 40), "ok": (150, 110, 20), "weak": (190, 40, 30), "occluded": (90, 90, 90)}[g]
        lab_ = r["name"].replace(tag + "_", "")[:34]
        d.text((6, 302), lab_, fill=(59, 36, 22), font=fs)
        d.text((6, 320), f"{r['px_h']}px @ {r['cam_dist_m']}m  dE {r['dE_mean']}/{r['dE_edge']}", fill=(59, 36, 22), font=fs)
        d.text((6, 338), f"camo {r['camo_share']:.2f} vis {r['visible_frac']:.2f}  {g.upper()}", fill=colr, font=fs)
        cells.append(cell)
    if not cells:
        return None
    cols = 6
    rows_n = (len(cells) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 304, rows_n * 364 + 40), (59, 36, 22))
    ImageDraw.Draw(sheet).text((8, 8), f"{tag}: enemies from the gameplay camera rig (orbit 5.4 m, pitch -17, FOV 62), crop 3.2x enemy height", fill=(243, 230, 196), font=f)
    for i, c in enumerate(cells):
        sheet.paste(c, ((i % cols) * 304 + 2, (i // cols) * 364 + 40))
    p = out / f"{tag}_context_sheet.png"
    sheet.save(p)
    # 64 px silhouettes
    sil = []
    for r in rows:
        m = Image.open(r["mask"]).convert("L")
        x0, y0, x1, y1 = r["bbox"]
        c = m.crop((x0, y0, x1 + 1, y1 + 1))
        w = max(1, round(c.width * 64 / c.height))
        c = c.resize((w, 64), Image.LANCZOS)
        cell = Image.new("L", (max(w, 64) + 16, 100), 255)
        inv = Image.eval(c, lambda v: 255 - v)
        cell.paste(inv, (8, 8))
        ImageDraw.Draw(cell).text((4, 78), (r["family"] or "")[:12], fill=0, font=font(11))
        sil.append(cell)
    W = sum(c.width for c in sil) + 8
    s = Image.new("L", (W, 100), 255)
    x = 4
    for c in sil:
        s.paste(c, (x, 0))
        x += c.width
    ps = out / f"{tag}_silhouette64.png"
    s.save(ps)
    return p, ps


def main():
    raw = Path(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    allrows = []
    for rep in sorted(raw.glob("*/*_report.json")):
        R = json.loads(rep.read_text(encoding="utf-8"))
        rows = []
        for s in R["shots"]:
            if s.get("family") == "mak":
                continue
            r = analyse(s)
            if r is None:
                continue
            r["world"] = R["tag"]
            r["grade"] = grade(r)
            rows.append(r)
        allrows += rows
        res = sheets(R["tag"], rows, out)
        print(R["tag"], len(rows), "shots", res)
    (out / "metrics.json").write_text(json.dumps(allrows, indent=1), encoding="utf-8")
    keys = ["world", "name", "family", "gap", "lineup", "cam_dist_m", "model_h_m", "px_h", "dE_mean", "dE_edge", "wcag",
            "camo_share", "visible_frac", "enemy_L", "ring_L", "enemy_chroma", "ring_chroma", "hue_diff", "grade"]
    with open(out / "metrics.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=keys, extrasaction="ignore")
        w.writeheader()
        for r in allrows:
            w.writerow(r)
    for r in allrows:
        print(f"{r['world']:5} {r['name'][:44]:44} px_h={r['px_h']:4} dE={r['dE_mean']:5}/{r['dE_edge']:5} camo={r['camo_share']:.2f} vis={r['visible_frac']:.2f} wcag={r['wcag']:5} L={r['enemy_L']}/{r['ring_L']} {r['grade']}")


if __name__ == "__main__":
    main()

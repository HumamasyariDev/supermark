#!/usr/bin/env python3
"""Contact sheet of FeelProbeV2 shots with state labels: python sheet_v2.py <tag> <out.png> [cols] [crop]
crop: 'hero' crops a 640x360 window centred on Mak's chest screen position (from the cam log) and scales it x1."""
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3] / 'Docs' / 'progress' / 'critique' / 'hero_v2' / 'r1_feel'


def main():
    tag, out = sys.argv[1], Path(sys.argv[2])
    cols = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    crop = len(sys.argv) > 4 and sys.argv[4] == 'hero'
    rows = {}
    for l in (ROOT / 'data' / (tag + '.cam.jsonl')).read_text(encoding='utf-8').splitlines():
        if l.strip():
            r = json.loads(l)
            rows[r['rf']] = r
    shots = sorted((ROOT / 'shots' / tag).glob('*.[pj][np]g'))
    tiles = []
    for p in shots:
        im = Image.open(p).convert('RGB')
        rf = int(p.stem[2:]) if p.stem.startswith('rf') else -1
        r = rows.get(rf, {})
        if crop and r.get('scr') and r['scr'][0] >= 0:
            cx, cy = r['scr'][0] * im.width, r['scr'][1] * im.height
            w, h = im.width // 3, im.height // 3
            x0 = int(min(max(cx - w / 2, 0), im.width - w))
            y0 = int(min(max(cy - h / 2, 0), im.height - h))
            im = im.crop((x0, y0, x0 + w, y0 + h)).resize((w * 2, h * 2), Image.LANCZOS)
        else:
            im = im.resize((im.width * 2 // 3, im.height * 2 // 3), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        lab = '%s rf%d pf%s %s h=%.0f%%' % (tag, rf, r.get('pf', '?'), r.get('s', '?'), 100 * r.get('h_scr', 0))
        d.rectangle((0, 0, 8 * len(lab) + 8, 18), fill=(0, 0, 0))
        d.text((4, 3), lab, fill=(255, 255, 255))
        tiles.append(im)
    if not tiles:
        print('no shots')
        return
    tw, th = tiles[0].size
    n = len(tiles)
    sheet = Image.new('RGB', (tw * cols, th * ((n + cols - 1) // cols)), (20, 20, 20))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * tw, (i // cols) * th))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(out, sheet.size)


if __name__ == '__main__':
    main()

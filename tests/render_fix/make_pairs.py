"""Render-fix evidence: before/after pairs of native 1600x900 captures from render_shots.gd -> WebP.

python game/tests/render_fix/make_pairs.py <before dir> <after dir> <utc stamp> <shot> [<shot> ...]
<shot> is "<area>_<spot>" (files before_<shot>.png / after_<shot>.png). Writes
Docs/progress/finish/render_fix/<utc>__<shot>_before_after.webp (before left, after right) and <utc>__<shot>_after.webp.
A shot named "<x>@<suffix>" reads after_<x>_<suffix>.png for the right side (same spot, other setting).
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ENTITY = Path(__file__).resolve().parents[3]
OUT = ENTITY / 'Docs' / 'progress' / 'finish' / 'render_fix'


def main():
    bdir, adir, utc = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    OUT.mkdir(parents=True, exist_ok=True)
    for name in sys.argv[4:]:
        b = Image.open(bdir / f'before_{name}.png').convert('RGB')
        a = Image.open(adir / f'after_{name}.png').convert('RGB')
        w, h = 1200, 675
        pair = Image.new('RGB', (w * 2 + 8, h), (20, 20, 20))
        pair.paste(b.resize((w, h), Image.LANCZOS), (0, 0))
        pair.paste(a.resize((w, h), Image.LANCZOS), (w + 8, 0))
        d = ImageDraw.Draw(pair)
        for x, label in ((12, 'BEFORE'), (w + 20, 'AFTER')):
            d.rectangle((x - 4, 8, x + 64, 30), fill=(0, 0, 0))
            d.text((x, 12), label, fill=(255, 255, 255))
        p1 = OUT / f'{utc}__{name}_before_after.webp'
        pair.save(p1, 'WEBP', quality=86, method=6)
        p2 = OUT / f'{utc}__{name}_after.webp'
        a.save(p2, 'WEBP', quality=88, method=6)
        print(p1.relative_to(ENTITY).as_posix())
        print(p2.relative_to(ENTITY).as_posix())


if __name__ == '__main__':
    main()

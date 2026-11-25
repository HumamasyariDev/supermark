"""Look-polish evidence: before/after pairs (native 1920x1080 gameplay-camera PNGs from look_shots.gd) -> WebP.

python game/tests/look_polish/make_pairs.py <shots dir> <name> [<name> ...]
Writes Docs/progress/finish/look_polish/<utc>__<name>_before_after.webp (before left, after right, 1280x720 each) and
<utc>__<name>_after.webp (full 1920x1080). Prints the written paths.
"""
import datetime as dt
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ENTITY = Path(__file__).resolve().parents[3]
OUT = ENTITY / 'Docs' / 'progress' / 'finish' / 'look_polish'


def main():
    shots = Path(sys.argv[1])
    utc = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    OUT.mkdir(parents=True, exist_ok=True)
    for name in sys.argv[2:]:
        b = Image.open(shots / f'before_{name}.png').convert('RGB')
        a = Image.open(shots / f'after_{name}.png').convert('RGB')
        w, h = 1280, 720
        pair = Image.new('RGB', (w * 2 + 8, h), (20, 20, 20))
        pair.paste(b.resize((w, h), Image.LANCZOS), (0, 0))
        pair.paste(a.resize((w, h), Image.LANCZOS), (w + 8, 0))
        d = ImageDraw.Draw(pair)
        for x, label in ((12, 'BEFORE'), (w + 20, 'AFTER')):
            d.rectangle((x - 4, 8, x + 64, 30), fill=(0, 0, 0))
            d.text((x, 12), label, fill=(255, 255, 255))
        p1 = OUT / f'{utc}__{name}_before_after.webp'
        pair.save(p1, 'WEBP', quality=88, method=6)
        p2 = OUT / f'{utc}__{name}_after.webp'
        a.save(p2, 'WEBP', quality=90, method=6)
        print(p1.relative_to(ENTITY).as_posix())
        print(p2.relative_to(ENTITY).as_posix())


if __name__ == '__main__':
    main()

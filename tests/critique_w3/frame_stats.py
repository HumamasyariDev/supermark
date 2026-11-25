"""W3 visual critique helper (critic round 1, visual polish lens).

Measures colour statistics of captures against the W3 key art so "washed out" and "low contrast" are numbers, not opinions.
Usage: python game/tests/critique_w3/frame_stats.py <png> [<png> ...]
Prints mean HSV saturation, mean value, value standard deviation (a contrast proxy) and the top-band sky colour.
The key art concepts/v2/style/07_w3_grove.png is always measured first as the reference row.
"""
import colorsys
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
KEY = os.path.join(ROOT, "concepts", "v2", "style", "07_w3_grove.png")


def stats(path: str) -> str:
    im = Image.open(path).convert("RGB")
    small = im.resize((192, 108))
    px = list(small.getdata())
    hsv = [colorsys.rgb_to_hsv(r / 255, g / 255, b / 255) for r, g, b in px]
    n = len(hsv)
    sat = sum(h[1] for h in hsv) / n
    val = sum(h[2] for h in hsv) / n
    vstd = (sum((h[2] - val) ** 2 for h in hsv) / n) ** 0.5
    top = im.crop((0, 0, im.width, max(1, im.height // 20))).resize((1, 1)).getpixel((0, 0))
    return "%-60s sat %.3f  val %.3f  val_std %.3f  top #%02X%02X%02X" % (os.path.basename(path)[:60], sat, val, vstd, *top)


if __name__ == "__main__":
    print(stats(KEY) + "   <- key art")
    for p in sys.argv[1:]:
        print(stats(p))

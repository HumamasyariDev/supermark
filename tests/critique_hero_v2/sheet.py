#!/usr/bin/env python3
"""Contact sheet from a clip: python sheet.py <mp4> <out.png> <first> <last> <step> [--crop x,y,w,h] [--cols N] [--w 300]"""
import argparse, subprocess, tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ap = argparse.ArgumentParser()
ap.add_argument('mp4'); ap.add_argument('out'); ap.add_argument('first', type=int); ap.add_argument('last', type=int); ap.add_argument('step', type=int)
ap.add_argument('--crop', default=''); ap.add_argument('--cols', type=int, default=8); ap.add_argument('--w', type=int, default=300)
ap.add_argument('--title', default='')
a = ap.parse_args()
tmp = Path(tempfile.mkdtemp(prefix='sheet_'))
vf = rf"select='between(n\,{a.first}\,{a.last})*not(mod(n-{a.first}\,{a.step}))'"
if a.crop:
    x, y, w, h = a.crop.split(',')
    vf += f',crop={w}:{h}:{x}:{y}'
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', a.mp4, '-vf', vf, '-vsync', '0', str(tmp / 'f_%04d.png')], check=True)
files = sorted(tmp.glob('f_*.png'))
ims = [Image.open(f).convert('RGB') for f in files]
w = a.w; h = int(ims[0].height * w / ims[0].width)
cols = a.cols; rows = (len(ims) + cols - 1) // cols
top = 28 if a.title else 0
sheet = Image.new('RGB', (cols * w, rows * h + top), (20, 20, 20))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype('arial.ttf', 16); tfont = ImageFont.truetype('arial.ttf', 20)
except Exception:
    font = tfont = ImageFont.load_default()
if a.title:
    d.text((6, 3), a.title, fill=(255, 255, 255), font=tfont)
for i, im in enumerate(ims):
    im = im.resize((w, h), Image.LANCZOS)
    x, y = (i % cols) * w, (i // cols) * h + top
    sheet.paste(im, (x, y))
    d.rectangle([x, y, x + 46, y + 18], fill=(0, 0, 0))
    d.text((x + 3, y + 1), str(a.first + i * a.step), fill=(255, 255, 0), font=font)
Path(a.out).parent.mkdir(parents=True, exist_ok=True)
sheet.save(a.out)
for f in files: f.unlink()
print('sheet', a.out, len(ims), 'frames')

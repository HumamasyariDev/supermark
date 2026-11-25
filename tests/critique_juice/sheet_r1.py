"""Contact sheet of event moments from a Movie Maker MP4 (critique JUICE r1).

    python game/tests/critique_juice/sheet_r1.py <video.mp4> <out.png> --offsets=-2,0,2,5,10,20 label:frame [label:frame ...]

One row per event, one column per frame offset (rendered frames at 60 fps). Optional --crop=x,y,w,h (source pixels)
crops around the action before scaling; --tile=480 sets the tile width.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--') and '=' in a)
    video, out = args[0], Path(args[1])
    items = [(s.rsplit(':', 1)[0], int(s.rsplit(':', 1)[1])) for s in args[2:]]
    offs = [int(x) for x in opts.get('offsets', '-2,0,2,5,10,20').split(',')]
    tw = int(opts.get('tile', '480'))
    crop = [int(x) for x in opts['crop'].split(',')] if 'crop' in opts else None
    frames = sorted({max(0, f + o) for _, f in items for o in offs})
    tmp = Path(tempfile.mkdtemp(prefix='cj_sheet_'))
    sel = '+'.join(f'eq(n\\,{f})' for f in frames)
    vf = f"select='{sel}'"
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', video, '-vf', vf, '-vsync', '0', str(tmp / 'f_%05d.png')], check=True)
    got = sorted(tmp.glob('f_*.png'))
    fmap = {f: p for f, p in zip(frames, got)}
    with Image.open(got[0]) as _im:
        first = _im.copy()
    if crop:
        first = first.crop((crop[0], crop[1], crop[0] + crop[2], crop[1] + crop[3]))
    th = int(tw * first.height / first.width)
    lab_w = 0
    sheet = Image.new('RGB', (lab_w + tw * len(offs), (th + 22) * len(items) + 24), (20, 20, 24))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype('arial.ttf', 15)
    except OSError:
        font = ImageFont.load_default()
    for ci, o in enumerate(offs):
        d.text((ci * tw + 6, 4), f'event {o:+d} fr ({o * 1000 / 60:+.0f} ms)', fill=(230, 230, 230), font=font)
    for ri, (label, f) in enumerate(items):
        y = 24 + ri * (th + 22)
        d.text((6, y + 2), f'{label}  (frame {f})', fill=(255, 220, 120), font=font)
        for ci, o in enumerate(offs):
            p = fmap.get(max(0, f + o))
            if p is None:
                continue
            with Image.open(p) as _im:
                im = _im.convert('RGB')
            if crop:
                im = im.crop((crop[0], crop[1], crop[0] + crop[2], crop[1] + crop[3]))
            sheet.paste(im.resize((tw, th), Image.LANCZOS), (ci * tw, y + 20))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    for p in got:
        try:
            p.unlink()
        except OSError:
            pass
    try:
        tmp.rmdir()
    except OSError:
        pass
    print('sheet', out, sheet.size)


if __name__ == '__main__':
    main()

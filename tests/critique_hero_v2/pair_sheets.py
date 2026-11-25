#!/usr/bin/env python3
"""Hero v2 fix r1: before/after frame-sheet pairs from the same deterministic showcase replay (critic r1 clips vs fix clips).

python game/tests/critique_hero_v2/pair_sheets.py <view> <outdir>
"""
import subprocess, sys, glob
from pathlib import Path
from PIL import Image, ImageDraw
E = Path(__file__).resolve().parents[3]
view, outdir = sys.argv[1], Path(sys.argv[2])
B = E / 'Docs/progress/critique/hero_v2/r1_animation/clips'
A = E / 'Docs/progress/hero_v2_fix_r1/anim/clips'
SETS = {'side': [('walk_slow', 0, 520, 600, 4), ('run_brake', 0, 680, 748, 3), ('triple_land', 1, 440, 500, 3),
                 ('wallkick_slam', 2, 400, 480, 4), ('punch_combo', 2, 764, 820, 2), ('ledge', 3, 150, 200, 2),
                 ('hurt', 4, 296, 356, 3), ('pole', 3, 352, 452, 5)],
        '3q': [('walk_run', 0, 520, 748, 8), ('flips', 1, 120, 480, 12), ('slam_punch', 2, 400, 820, 14)]}
CROP = {'side': '560,180,640,640', '3q': '520,150,700,700'}
outdir.mkdir(parents=True, exist_ok=True)
sheet = E / 'game/tests/critique_hero_v2/sheet.py'
for name, part, a, b, step in SETS[view]:
    ims = []
    for tag, d in (('BEFORE (critic r1)', B), ('AFTER (fix r1)', A)):
        c = sorted(glob.glob(str(d / f'*__showcase_{view}_part{part}.mp4')))
        if not c:
            print('missing', d, part); break
        tmp = outdir / f'_{name}.png'
        subprocess.run([sys.executable, str(sheet), c[-1], str(tmp), str(a), str(b), str(step), '--crop', CROP[view], '--w', '200',
                        '--cols', '14', '--title', f'{tag}: {view} {name} frames {a}-{b} every {step}f (offline Movie Maker)'], check=True)
        ims.append(Image.open(tmp).convert('RGB')); tmp.unlink()
    if len(ims) == 2:
        W = max(i.width for i in ims); o = Image.new('RGB', (W, ims[0].height + ims[1].height + 6), (255, 255, 255))
        o.paste(ims[0], (0, 0)); o.paste(ims[1], (0, ims[0].height + 6))
        o.save(outdir / f'pair_{view}_{name}.png'); print('pair', name)

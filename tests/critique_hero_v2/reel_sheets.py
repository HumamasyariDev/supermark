#!/usr/bin/env python3
"""Per-clip contact sheets of a PoseLab reel: python reel_sheets.py <reel.mp4> [--frames 16] [--only a,b]"""
import argparse, json, subprocess, sys
from pathlib import Path
ap = argparse.ArgumentParser(); ap.add_argument('mp4'); ap.add_argument('--frames', type=int, default=16); ap.add_argument('--only', default='')
ap.add_argument('--crop', default='350,0,900,900'); ap.add_argument('--offset', type=int, default=2)
a = ap.parse_args()
mp4 = Path(a.mp4); idx = json.loads(mp4.with_suffix('.json').read_text())
out = mp4.parent.parent / 'sheets' / 'reels'
only = set(a.only.split(',')) if a.only else None
tag = mp4.stem.split('__')[1]
for c in idx:
    if only and c['clip'] not in only:
        continue
    first = c['start_frame'] + a.offset; last = first + c['frames'] - 1
    step = max(1, c['frames'] // a.frames)
    subprocess.run([sys.executable, str(Path(__file__).parent / 'sheet.py'), str(mp4), str(out / f"{tag}__{c['clip']}.png"), str(first), str(last), str(step),
                    '--crop', a.crop, '--cols', '8', '--w', '220', '--title', f"{tag}: {c['clip']} ({c['frames']} f, every {step} f, cycle {c['cycle_s']} s)"], check=True)

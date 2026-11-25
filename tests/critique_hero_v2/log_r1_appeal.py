#!/usr/bin/env python3
"""Append evidence rows for HERO V2 critique round 1 (APPEAL AND IDENTITY lens) through game/tests/log_evidence.py."""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import log_evidence as le  # noqa: E402

D = 'Docs/progress/critique/hero_v2/r1_appeal/'
ENT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
ROWS = [
    ('20261018T1549Z__r1-side-by-side-reference-vs-ingame-full.png', 'concept',
     'Owner reference vs in-game hero v2 (W1 top hat, W1 beanie, MoveLab top hat), full body 3/4',
     'Unmistakably the same character: head about 46% of height, patch eye, pink-lined ears, cream body, brown hooves, pack. '
     'Warmer and smoother toon shading in W1; facets survive mainly on snout, ears and silhouette. Pack reads orange-tan, darker brown in reference.'),
    ('20261018T1549Z__r1-side-by-side-reference-vs-ingame-face.png', 'concept',
     'Owner reference face vs in-game face (front, 3/4 both sides, beanie)',
     'Eyes comparable in size with highlights and arched brows; front and patch-side 3/4 are very close to the reference and cute. '
     'Nostrils read red-pink, reference nostrils are dark. From the non-patch side the long snout hides the patch eye.'),
    ('20261018T1549Z__r1-w1-yaw-sweep-sheet.png', 'concept',
     'Face yaw sweep -35..+35 deg in W1 (top hat)',
     'Patch-side angles (negative yaw) show both eyes and look like the reference. On the non-patch side (the reference camera side) '
     'the snout covers the patch eye from about +18 deg on; at the reference angle (~25 deg) only the brown patch edge shows.'),
]
for pat, cap in [('*__r1-w1-tophat-gameplay-spawn.png', 'W1 gameplay camera at spawn, top hat (default)'),
                 ('*__r1-w1-tophat-gameplay-running.png', 'W1 gameplay camera running, top hat'),
                 ('*__r1-w1-beanie-gameplay-running.png', 'W1 gameplay camera running, beanie'),
                 ('*__r1-w1-tophat-face-front.png', 'W1 face front, top hat'),
                 ('*__r1-w1-tophat-face-3q-a.png', 'W1 face 3/4 non-patch side, top hat'),
                 ('*__r1-w1-tophat-face-3q-b.png', 'W1 face 3/4 patch side, top hat'),
                 ('*__r1-w1-beanie-face-3q-b.png', 'W1 face 3/4, beanie'),
                 ('*__r1-lab-tophat-full-3q-a.png', 'MoveLab full body 3/4, top hat'),
                 ('*__r1-lab-tophat-face-front.png', 'MoveLab face front, top hat'),
                 ('*__r1-lab-tophat-gameplay-before-run.png', 'MoveLab gameplay camera (5.4 m, fov 62), top hat'),
                 ('*__r1-lab-beanie-full-3q-b.png', 'MoveLab full body 3/4, beanie')]:
    f = sorted(glob.glob(os.path.join(ENT, D, pat)))[-1]
    ROWS.append((os.path.basename(f), 'native_viewport', cap, 'Opened and assessed for the appeal/identity lens; see REPORT.md.'))
out = []
for name, ctype, cap, obs in ROWS:
    out.append(le.row(D + name, ctype, cap, obs, milestone='hero-v2', feature='critique-hero-v2-r1-appeal'))
le.append(out)
print(len(out), 'rows appended')

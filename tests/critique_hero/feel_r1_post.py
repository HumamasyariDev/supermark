#!/usr/bin/env python3
"""HERO critique round 1 (re-run on the post-fix build), lens GAME FEEL AND CAMERA.

Reuses feel_r1.py replays unchanged (like-for-like with the first pass) and writes to
Docs/progress/critique/hero/r1_feel/post/. Extra case 'circle': camera-relative steering, stick held
hard right (then diagonal) for about 3 s each, no camera input, to measure whether auto-follow bends the path.
Usage: python game/tests/critique_hero/feel_r1_post.py case ...
"""
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import feel_r1  # noqa: E402
feel_r1.OUT = HERE.parents[2] / 'Docs' / 'progress' / 'critique' / 'hero' / 'r1_feel' / 'post'


def rep_circle():
    ev = [{'f': 10, 'stick': [1, 0], 'mark': 'hold_right'},
          {'f': 200, 'stick': [0, 0]},
          {'f': 260, 'teleport': [0.0, 0.0, 30.0], 'yaw_deg': 0, 'mark': 'reset'},
          {'f': 340, 'stick': [-0.7071, 0.7071], 'mark': 'hold_diag'},
          {'f': 530, 'stick': [0, 0]}]
    return {'fps': 60, 'steer': 'camera', 'start': {'pos': [0.0, 0.0, 30.0], 'yaw_deg': 0}, 'end_frame': 600, 'events': ev}


feel_r1.CASES['circle'] = (rep_circle, feel_r1.LAB)
if __name__ == '__main__':
    feel_r1.main()

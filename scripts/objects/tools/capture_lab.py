"""Capture ObjectsLab story cameras and append evidence rows (reviewed=false until looked at).
Usage (from the entity folder):
  python game/scripts/objects/tools/capture_lab.py --milestone objects-lab StoryCam_B:caption StoryCam_F_books:caption
  python game/scripts/objects/tools/capture_lab.py --review <file> --observed "what was seen"   (appends a reviewed row)
"""
import argparse
import datetime as dt
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ENTITY = Path(__file__).resolve().parents[4]
EVIDENCE = ENTITY / 'data' / 'evidence.jsonl'


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def row(file_rel, caption, observed, milestone, reviewed, capture_type='native_viewport'):
    return {'utc': dt.datetime.now(dt.timezone.utc).isoformat(), 'timezone': 'Asia/Bangkok', 'run': 'night01',
            'milestone': milestone, 'feature': 'objects', 'capture_type': capture_type, 'file': file_rel,
            'sha256': sha(ENTITY / file_rel), 'caption': caption, 'observed': observed, 'reviewed': reviewed}


def append(r):
    with EVIDENCE.open('a', encoding='utf-8') as f:
        f.write(json.dumps(r) + '\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('shots', nargs='*')
    ap.add_argument('--milestone', default='objects-lab')
    ap.add_argument('--scene', default='res://scenes/objects/ObjectsLab.tscn')
    ap.add_argument('--wait', type=int, default=150)
    ap.add_argument('--review')
    ap.add_argument('--observed', default='')
    ap.add_argument('--caption', default='')
    ap.add_argument('--capture-type', default='native_viewport')
    a = ap.parse_args()
    if a.review:
        append(row(a.review, a.caption or Path(a.review).stem.split('__', 1)[-1], a.observed, a.milestone, True, a.capture_type))
        print('reviewed row appended', a.review)
        return
    for shot in a.shots:
        cam, _, caption = shot.partition(':')
        ts = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        slug = (caption or cam).lower().replace(' ', '-').replace('/', '-')[:60]
        rel = f'Docs/progress/objects/{ts}__{slug}.png'
        cmd = [sys.executable, str(ENTITY / 'tools' / 'godot.py'), 'capture', a.scene, rel, '--no-import', '--wait', str(a.wait),
               '--cam', cam, '--hide-hud', '--', '--profile=objects_lab']
        out = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', cwd=ENTITY)
        errs = [l for l in out.stdout.splitlines() if 'SCRIPT ERROR' in l]
        if (ENTITY / rel).exists():
            print('captured', rel, 'script errors:', len(errs))
            for e in errs[:5]:
                print('  ', e)
        else:
            print('FAILED', rel)
            print(out.stdout[-2000:])


if __name__ == '__main__':
    main()

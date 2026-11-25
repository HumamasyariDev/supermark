"""Append evidence rows for the camera finish pass (Docs/progress/finish/camera) to data/evidence.jsonl.

  python game/tests/camera_probe/cam_evidence.py <file> <capture_type> <caption> <observed> [...more quadruples]
"""
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ENTITY = Path(__file__).resolve().parents[3]


def row(rel, ctype, caption, observed):
    p = ENTITY / rel
    r = {'utc': datetime.now(timezone.utc).isoformat(), 'timezone': 'Asia/Bangkok', 'run': 'camera-fix-2026-10-19',
         'milestone': 'owner-fixes', 'feature': 'owner-fix:camera-floor-slide-npc-hitch', 'capture_type': ctype,
         'file': rel, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
    if p.suffix.lower() in ('.webp', '.png', '.jpg'):
        from PIL import Image
        with Image.open(p) as im:
            r['width'], r['height'] = im.size
    r['caption'] = caption
    r['observed'] = observed
    r['reviewed'] = True
    return r


if __name__ == '__main__':
    a = sys.argv[1:]
    rows = [row(*a[i:i + 4]) for i in range(0, len(a), 4)]
    with open(ENTITY / 'data' / 'evidence.jsonl', 'a', encoding='utf-8') as f:
        for r in rows:
            f.write(json.dumps(r) + '\n')
    print(len(rows), 'rows')

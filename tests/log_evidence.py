#!/usr/bin/env python3
"""Append evidence rows to data/evidence.jsonl (shared, append-only) for player-workstream captures.

Usage:
    python game/tests/log_evidence.py --file Docs/progress/movement/<utc>__x.png --type native_viewport \
        --caption "..." --observed "..." [--utc 2026-10-17T19:21:42Z] [--milestone M1] [--feature movement]
The file path is relative to the entity folder. sha256 is computed here. reviewed=true means the
capture was opened and assessed before logging.
"""
import argparse
import datetime as dt
import hashlib
import json
import re
from pathlib import Path

ENTITY = Path(__file__).resolve().parents[2]
LOG = ENTITY / 'data' / 'evidence.jsonl'


def row(file, ctype, caption, observed, utc=None, milestone='M1', feature='movement', reviewed=True):
    p = ENTITY / file
    h = hashlib.sha256(p.read_bytes()).hexdigest()
    if not utc:
        m = re.search(r'(\d{8}T\d{6}Z)', p.name)
        utc = dt.datetime.strptime(m.group(1), '%Y%m%dT%H%M%SZ').strftime('%Y-%m-%dT%H:%M:%SZ') if m else \
            dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    return {'utc': utc, 'timezone': 'Asia/Bangkok', 'run': 'night01', 'milestone': milestone, 'feature': feature,
            'capture_type': ctype, 'file': file.replace('\\', '/'), 'sha256': h, 'caption': caption,
            'observed': observed, 'reviewed': reviewed}


def append(rows):
    with LOG.open('a', encoding='utf-8') as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--file', required=True)
    ap.add_argument('--type', required=True, choices=['native_viewport', 'actual_window_screen', 'movie_maker', 'concept'])
    ap.add_argument('--caption', required=True)
    ap.add_argument('--observed', required=True)
    ap.add_argument('--utc')
    ap.add_argument('--milestone', default='M1')
    ap.add_argument('--feature', default='movement')
    ap.add_argument('--unreviewed', action='store_true')
    a = ap.parse_args()
    r = row(a.file, a.type, a.caption, a.observed, a.utc, a.milestone, a.feature, not a.unreviewed)
    append([r])
    print(json.dumps(r))


if __name__ == '__main__':
    main()

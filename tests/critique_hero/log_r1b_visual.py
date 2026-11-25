#!/usr/bin/env python3
"""Append evidence rows for HERO critique r1 (character visuals, re-run 'r1b' on the current build). Read-only critic tool.
Usage: python game/tests/critique_hero/log_r1b_visual.py <json file with [{file, caption, observed, type}]>"""
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from log_evidence import row, LOG  # noqa: E402

items = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
with LOG.open('a', encoding='utf-8') as f:
    for it in items:
        r = row(it['file'], it.get('type', 'native_viewport'), it['caption'], it['observed'],
                milestone='night', feature='critique-hero-r1-visual')
        f.write(json.dumps(r) + '\n')
print('appended', len(items))

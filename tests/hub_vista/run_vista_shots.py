"""Hub window vista evidence runner (2026-10-19). One Godot launch per window view, through tools/godot.py.

Usage: python game/tests/hub_vista/run_vista_shots.py <label> [extra user args...]
Writes Docs/progress/finish/hub_vista/<label>/<stamp>__<view>_t*.png (gameplay camera) and story cams.
"""
import subprocess, sys
from pathlib import Path

ENTITY = Path(__file__).resolve().parents[3]
OUT = ENTITY / 'Docs/progress/finish/hub_vista'
VIEWS = [
    ('winWSW', 'View_WinWSW', 'StoryCam_D,ReviewCam_West,TitleCam'),
    ('winWNW', 'View_WinWNW', ''),
    ('balcony', 'Balcony', ''),
    ('entrance', 'View_Entrance', ''),
]


def main():
    label = sys.argv[1]
    extra = sys.argv[2:]
    only = [a.split('=', 1)[1] for a in extra if a.startswith('--only=')]
    extra = [a for a in extra if not a.startswith('--only=')]
    out = OUT / label
    out.mkdir(parents=True, exist_ok=True)
    for tag, spawn, cams in VIEWS:
        if only and tag not in only[0].split(','):
            continue
        args = [sys.executable, str(ENTITY / 'tools/godot.py'), 'capture', 'res://scenes/hub/Hub.tscn',
                str(out / f'{tag}_final.png'), '--wait', '6000', '--hide-hud', '--no-import', '--',
                f'--profile=vista_{label}_{tag}', f'--spawn={spawn}', '--hv-shots=4,7', f'--hv-tag={tag}',
                f'--hv-out={out.as_posix()}', f'--hv-stamp={label}', '--hv-wait=9']
        if cams:
            args.append(f'--hv-cams={cams}')
        args += extra
        print('==', tag, flush=True)
        subprocess.run(args, cwd=str(ENTITY))


if __name__ == '__main__':
    main()

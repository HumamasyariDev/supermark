"""Camera probe (finish pass, camera floor slide and NPC hitch).

Runs the real game scenes through tools/godot.py with a replay (walking) plus the MakCameraRig probe arguments
(--cam-trace, --cam-mouse, --cam-interact) and summarises the per-frame camera trace.

  python game/tests/camera_probe/cam_probe.py run <case> <tag> [--movie out.avi --frames N]
  python game/tests/camera_probe/cam_probe.py stats <trace.jsonl> [...]

Cases: pitch_flat (hub floor), pitch_slope (W1 hillside), npc_hub (walk up to Bramwell, talk, circle him),
npc_w1 (walk up to Cousin Pip, talk). Traces go to Docs/progress/finish/camera/traces/<case>_<tag>.jsonl.
"""
import json
import math
import subprocess
import sys
from pathlib import Path

ENTITY = Path(__file__).resolve().parents[3]
GODOT_PY = ENTITY / 'tools' / 'godot.py'
OUT = ENTITY / 'Docs' / 'progress' / 'finish' / 'camera'
HUB = 'res://scenes/hub/Hub.tscn'
W1 = 'res://scenes/worlds/w1/W1.tscn'

# Mouse: up (negative dy) raises the pitch, so the camera drops below Mak and looks up at him.
SWEEP = '/'.join([
    '1.5,2.5,0,-420',     # pitch up fast into the floor and past it
    '5.0,6.0,0,420',      # back down
    '6.0,7.2,0,-300',     # up again, slower
    '7.2,10.2,320,-40',   # orbit sideways while low (floor contact on all sides)
    '10.2,11.2,0,400',    # back to a normal view
])


def _tp(pos, yaw):
    return {'f': 0, 'teleport': pos, 'yaw_deg': yaw}


def _case(name):
    # The replay "start" key is MoveLab-only; worlds need a frame-0 teleport event.
    if name == 'pitch_flat':
        return HUB, {'fps': 60, 'steer': 'world', 'end_frame': 760,
                     'events': [_tp([-0.4, 0.3, 9.0], 0), {'f': 0, 'stick': [0, 0]}]}, SWEEP, ''
    if name == 'pitch_slope':
        return W1, {'fps': 60, 'steer': 'world', 'end_frame': 760,
                    'events': [_tp([-17.0, 6.8, -22.0], 160), {'f': 0, 'stick': [0, 0]}]}, SWEEP, ''
    if name == 'npc_hub':
        # Bramwell stands at (3.2, 0, 7.6). Walk straight into him (players stop against his body, so the talk eases Mak
        # back), talk through both lines, then walk round him so he passes between the camera and Mak.
        d = (0.737, -0.677)
        return HUB, {'fps': 60, 'steer': 'world', 'end_frame': 900, 'events': [
            _tp([-0.5, 0.2, 11.0], -47.4), {'f': 0, 'stick': [0, 0]},
            {'f': 40, 'stick': [d[0] * 0.65, -d[1] * 0.65]},
            {'f': 230, 'stick': [0, 0]},
            {'f': 600, 'stick': [0.7, 0.0]},
            {'f': 680, 'stick': [0.0, 0.7]},
            {'f': 760, 'stick': [-0.7, 0.0]},
            {'f': 820, 'stick': [0, 0]},
        ]}, '', '4.4,6.6,7.8,9.0'
    if name == 'npc_w1':
        d = (-0.806, -0.591)
        return W1, {'fps': 60, 'steer': 'world', 'end_frame': 900, 'events': [
            _tp([-13.0, 1.2, 35.0], 53.7), {'f': 0, 'stick': [0, 0]},
            {'f': 40, 'stick': [d[0] * 0.65, -d[1] * 0.65]},
            {'f': 260, 'stick': [0, 0]},
            {'f': 620, 'stick': [0.7, 0.0]},
            {'f': 700, 'stick': [0.0, 0.7]},
            {'f': 780, 'stick': [0, 0]},
        ]}, '', '4.8,7.0,8.2,9.4'
    if name == 'telescope':
        # Owner report: the balcony telescope (hub_level._telescope at (3.0, 4.5, 21.0), against the outdoor balcony's
        # balustrade (centre (0, 4.5, 17), rail r 5.3); its "Look" sign at about (2.1, 4.5, 21.4), talk radius 1.8).
        # Step out of the French doors, walk to the sign with the castle wall behind the camera, shuffle, talk.
        return HUB, {'fps': 60, 'steer': 'world', 'end_frame': 1000, 'events': [
            _tp([0.0, 4.8, 17.4], 180), {'f': 0, 'stick': [0, 0]},
            {'f': 40, 'stick': [0.447 * 0.5, -0.894 * 0.5]}, {'f': 280, 'stick': [0.0, 0.0]},
            {'f': 300, 'stick': [0.3, 0.0]}, {'f': 330, 'stick': [-0.3, 0.0]}, {'f': 370, 'stick': [0.0, 0.0]},
            {'f': 800, 'stick': [-0.4, 0.2]}, {'f': 880, 'stick': [0.0, 0.0]},
        ]}, '', '7.0,9.4,11.4'
    raise SystemExit('unknown case ' + name)


def run(name, tag, movie=None, frames=0):
    scene, replay, mouse, inter = _case(name)
    (OUT / 'traces').mkdir(parents=True, exist_ok=True)
    rp = OUT / 'traces' / f'{name}_replay.json'
    rp.write_text(json.dumps(replay, indent=1), encoding='utf-8')
    tr = OUT / 'traces' / f'{name}_{tag}.jsonl'
    extra = ['--', f'--replay={rp.as_posix()}', f'--cam-trace={tr.as_posix()}', f'--profile=camprobe_{name}']
    if movie:
        extra.append('--replay-hold')
    if mouse:
        extra.append(f'--cam-mouse={mouse}')
    if inter:
        extra.append(f'--cam-interact={inter}')
    if movie:
        cmd = [sys.executable, str(GODOT_PY), 'movie', scene, str(movie), '--frames', str(frames), '--no-import'] + extra
    else:
        cmd = [sys.executable, str(GODOT_PY), 'run', scene, '--seconds', '40', '--no-import'] + extra
    print(' '.join(cmd), flush=True)
    p = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
    out = (p.stdout or '') + (p.stderr or '')
    errs = [l for l in out.splitlines() if 'SCRIPT ERROR' in l or 'Parse Error' in l]
    print('\n'.join(out.splitlines()[-25:]))
    print('script errors:', len(errs))
    for e in errs[:10]:
        print('  ', e)
    print(stats(tr))


def _load(path):
    rows = []
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        try:
            rows.append(json.loads(line))
        except Exception:
            pass
    return rows


def _ang(a, b):
    d = max(-1.0, min(1.0, sum(x * y for x, y in zip(a, b)) / (math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)) + 1e-9)))
    return math.degrees(math.acos(d))


def stats(path, t0=1.0):
    """Per-frame camera jumps. 'rel' is the change of the camera's offset from Mak (removes plain follow motion);
    'ang' is the change of view direction; both per frame and normalised to a 60 fps frame (value / dt / 60).
    A 'pop' is a frame whose normalised offset change is over 3x the median of its 10 neighbours and over 0.05 m."""
    rows = [r for r in _load(path) if r['t'] >= t0]
    if len(rows) < 3:
        return {'trace': str(path), 'rows': len(rows)}
    rel, ang, n60, boom_d, dts = [], [], [], [], []
    for a, b in zip(rows, rows[1:]):
        oa = [c - p for c, p in zip(a['cam'], a['pl'])]
        ob = [c - p for c, p in zip(b['cam'], b['pl'])]
        d = math.dist(oa, ob)
        g = _ang(a['fwd'], b['fwd'])
        dt = max(b['dt'], 1e-4)
        rel.append(d)
        ang.append(g)
        n60.append((d / dt / 60.0, g / dt / 60.0, b['f'], b['t'], b['vcam']))
        boom_d.append(abs(b['boom'] - a['boom']))
        dts.append(b['dt'])
    pops = []
    for i, (dn, gn, f, t, vc) in enumerate(n60):
        nb = sorted(x[0] for x in n60[max(0, i - 5):i] + n60[i + 1:i + 6])
        med = nb[len(nb) // 2] if nb else 0.0
        if dn > 0.05 and dn > 3.0 * max(med, 0.004):
            pops.append({'f': f, 't': round(t, 3), 'd60': round(dn, 3), 'med': round(med, 3), 'vcam': vc})
    worst = max(n60, key=lambda x: x[0])
    worst_a = max(n60, key=lambda x: x[1])
    pitches = [r['pitch'] for r in rows]
    ys = [r['cam'][1] - r['pl'][1] for r in rows]
    vcams = sorted({r['vcam'] for r in rows})
    return {
        'trace': Path(path).name, 'frames': len(rows),
        'dt_ms_max': round(max(dts) * 1000, 1), 'dt_ms_p50': round(sorted(dts)[len(dts) // 2] * 1000, 2),
        'frames_over_33ms': sum(1 for d in dts if d > 0.0334),
        'max_rel_jump_m': round(max(rel), 4), 'max_rel_jump_m_60fps': round(worst[0], 4), 'at': [worst[2], round(worst[3], 3), worst[4]],
        'max_ang_jump_deg': round(max(ang), 3), 'max_ang_jump_deg_60fps': round(worst_a[1], 3), 'ang_at': [worst_a[2], round(worst_a[3], 3)],
        'max_boom_step_m': round(max(boom_d), 4),
        'pitch_range': [min(pitches), max(pitches)], 'cam_height_over_mak': [round(min(ys), 3), round(max(ys), 3)],
        'max_lift': round(max(r['lift'] for r in rows), 3), 'max_head_bias': round(max(r['head'] for r in rows), 3),
        'cameras': vcams, 'pops': pops[:12], 'pop_count': len(pops),
    }


if __name__ == '__main__':
    if sys.argv[1] == 'run':
        mv = None
        fr = 0
        if '--movie' in sys.argv:
            mv = sys.argv[sys.argv.index('--movie') + 1]
            fr = int(sys.argv[sys.argv.index('--frames') + 1])
        run(sys.argv[2], sys.argv[3], mv, fr)
    else:
        for p in sys.argv[2:]:
            print(json.dumps(stats(p), indent=1))

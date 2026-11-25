"""Critique JUICE r2, GAME FEEL lens: per-event feel table from the CritJuiceR2 logs (what reaches the screen).

    python game/tests/critique_juice/feel_r2_analyse.py <data dir> <tag> [<tag> ...]

Per fired event (rendered frames; Movie Maker = deterministic 60 fps):
  hs        frames with Engine.time_scale < 0.5 starting within 2 frames / catalogue ms as frames
  hsCam     mean per-frame camera screen motion during the freeze (global position + h/v offset deltas), mm
  shake     mak_camera _shake_amp taken after the event / catalogue strength
  fov       max |fov - fov at the event frame| over 30 frames / catalogue degrees (the FOV punch on screen)
  sq        peak |MakAnimator._sq| in 20 frames (player events)
  vfx       events whose Juice.stats.vfx rose on the event frame
  sfx       frame offset of the first JuiceSfx play for the event (min over occurrences)
  off%      share of occurrences whose position was outside the view
Writes <tag>_feel.json. (Named feel_r2_* because the performance critic owns analyse_r2.py.)
"""
import json
import sys
from bisect import bisect_right
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAME = HERE.parents[1]


def load_jsonl(p):
    out = []
    if not p.exists():
        return out
    for line in p.read_text(encoding='utf-8', errors='replace').splitlines():
        line = line.strip()
        if line:
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return out


def main():
    data = Path(sys.argv[1])
    tags = sys.argv[2:] or ['lab']
    cat = json.loads((GAME / 'scripts/fx/juice_vfx.json').read_text(encoding='utf-8'))
    ve, al = cat['events'], cat.get('aliases', {})

    def canon(name, params):
        if name in ve:
            return name
        k = params.get('kind')
        if k is not None:
            alt = f'{name}_{k}'
            if alt in ve:
                return alt
            if alt in al:
                return al[alt]
        return al.get(name, name)

    for tag in tags:
        frames = load_jsonl(data / f'{tag}_frames.jsonl')
        allev = load_jsonl(data / f'{tag}_events.jsonl')
        events = [e for e in allev if 'name' in e]
        sp = data / f'{tag}_sfx.json'
        sfx = json.loads(sp.read_text(encoding='utf-8')) if sp.exists() else {'played': []}
        byf = {r['f']: r for r in frames}
        fms = [r['ms'] for r in frames]

        def frame_at_ms(ms):
            i = bisect_right(fms, ms) - 1
            return frames[max(i, 0)]['f'] if frames else 0

        plays_by_event = defaultdict(list)
        for p in sfx.get('played', []) or []:
            plays_by_event[p.get('event', '')].append(dict(p, f=frame_at_ms(p['t'] * 1000.0)))

        def campos(r):
            return (r.get('cx', 0.0), r.get('cy', 0.0), r.get('cz', 0.0), r.get('ho', 0.0), r.get('vo', 0.0))

        rows = []
        for e in events:
            f = e['f']
            name = e['name']
            c = canon(name, e.get('params', {}))
            spec = ve.get(c, {})
            hs = 0
            motion = []
            start = None
            for d in range(0, 3):
                r = byf.get(f + d)
                if r and r.get('ts', 1) < 0.5:
                    start = f + d
                    break
            if start is not None:
                g = start
                while byf.get(g) and byf[g].get('ts', 1) < 0.5:
                    hs += 1
                    a, b = byf.get(g - 1), byf[g]
                    if a and 'cx' in a and 'cx' in b and a.get('cam') == b.get('cam'):
                        pa, pb = campos(a), campos(b)
                        dpos = sum((pa[i] - pb[i]) ** 2 for i in range(3)) ** 0.5
                        doff = ((pa[3] - pb[3]) ** 2 + (pa[4] - pb[4]) ** 2) ** 0.5
                        motion.append(dpos + doff)
                    g += 1
            shake = 0.0
            for d in range(0, 4):
                r = byf.get(f + d)
                if r and r.get('sh_t', 0) > 0:
                    shake = max(shake, r.get('sh_amp', 0.0))
            base = byf.get(f, {})
            fov0 = base.get('fov')
            fov_dev = 0.0
            if fov0 is not None:
                for d in range(1, 31):
                    r = byf.get(f + d)
                    if r and r.get('fov') is not None and r.get('cam') == base.get('cam'):
                        fov_dev = max(fov_dev, abs(r['fov'] - fov0))
            sq = 0.0
            if name.startswith('player_'):
                for d in range(0, 21):
                    r = byf.get(f + d)
                    if r and 'sq' in r:
                        sq = max(sq, abs(r['sq']))
            r0, r1 = byf.get(f - 1), byf.get(f + 1)
            vfx = (r1.get('vfx', 0) - r0.get('vfx', 0)) if r0 and r1 else None
            plays = [p for p in plays_by_event.get(name, []) if f - 2 <= p['f'] <= f + 90]
            first = min((p['f'] - f for p in plays), default=None)
            exp_hs = spec.get('hitstop_ms', 0)
            rows.append({
                'f': f, 'name': name, 'canon': c, 'cam_dist': e.get('cam_dist'), 'onscreen': e.get('onscreen'),
                'hs_frames': hs, 'hs_expect_frames': round(exp_hs * 60 / 1000.0, 1) if exp_hs else 0,
                'hs_cam_mm': round(1000 * sum(motion) / len(motion), 1) if motion else None,
                'shake': round(shake, 3), 'shake_cat': (spec.get('shake') or [0])[0],
                'fov_dev': round(fov_dev, 2), 'fov_cat': (spec.get('fov') or [0])[0],
                'squash': round(sq, 3), 'vfx': vfx, 'sfx_n': len(plays), 'sfx_first': first,
                'pstate': e.get('pstate'), 'params': e.get('params'),
            })
        (data / f'{tag}_feel.json').write_text(json.dumps(rows, indent=1), encoding='utf-8')
        agg = defaultdict(list)
        for r in rows:
            agg[r['canon']].append(r)
        print(f'== {tag}: {len(rows)} events, {len(agg)} distinct, {len(frames)} frames')
        print(f"{'event':28s} {'n':>3s} {'hs':>9s} {'hsCam':>6s} {'shake':>11s} {'fov':>9s} {'sq':>5s} {'vfx':>4s} {'sfx':>5s} {'off%':>4s} {'dist':>5s}")
        for k in sorted(agg):
            L = agg[k]
            hsv = [r['hs_frames'] for r in L]
            hsc = [r['hs_cam_mm'] for r in L if r['hs_cam_mm'] is not None]
            sh = max(r['shake'] for r in L)
            fv = max(r['fov_dev'] for r in L)
            sq = max(r['squash'] for r in L)
            vf = sum(1 for r in L if r['vfx'])
            sf = [r['sfx_first'] for r in L if r['sfx_first'] is not None]
            off = sum(1 for r in L if r['onscreen'] is False)
            dist = [r['cam_dist'] for r in L if r['cam_dist'] and r['cam_dist'] > 0]
            print(f"{k:28s} {len(L):3d} {min(hsv):2d}-{max(hsv):2d}/{L[0]['hs_expect_frames']:<4} "
                  f"{(sum(hsc) / len(hsc) if hsc else 0):6.1f} {sh:5.2f}/{L[0]['shake_cat']:<5} {fv:4.1f}/{L[0]['fov_cat']:<4} "
                  f"{sq:5.2f} {vf:4d} {(str(min(sf)) if sf else '-'):>5s} {100 * off // len(L):4d} {(sum(dist) / len(dist) if dist else 0):5.1f}")


if __name__ == '__main__':
    main()

"""Critique JUICE r1: turns the CritJuiceR1 logs into a per-event feel table.

    python game/tests/critique_juice/analyse_r1.py <data dir> <tag> [<tag> ...]

For every Juice event fired during the run it measures, in rendered frames (Movie Maker: 60 fps, deterministic):
  hitstop  frames with Engine.time_scale < 0.5 starting within 2 frames of the event (vs the catalogue's ms)
  shake    camera shake amplitude started within 3 frames (mak_camera._shake_amp, 1.0 = 0.4 m)
  squash   peak |MakAnimator._sq| in the 20 frames after (Mak's squash-and-stretch spring; player events only)
  vfx      Juice.stats.vfx delta over the event frame (effects actually spawned)
  sfx      JuiceSfx plays logged for that event, and the frame offset of the first play
Writes <tag>_feel.json and prints a table. Catalogue: game/scripts/fx/juice_vfx.json.
"""
import json
import sys
from bisect import bisect_right
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
    sfxcat = json.loads((GAME / 'assets/audio/juice_sfx.json').read_text(encoding='utf-8'))
    sev, sal = sfxcat['events'], sfxcat.get('aliases', {})

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
        events = [e for e in load_jsonl(data / f'{tag}_events.jsonl') if 'name' in e]
        marks = [e for e in load_jsonl(data / f'{tag}_events.jsonl') if 'mark' in e]
        sfx = json.loads((data / f'{tag}_sfx.json').read_text(encoding='utf-8')) if (data / f'{tag}_sfx.json').exists() else {'played': []}
        byf = {r['f']: r for r in frames}
        fms = [r['ms'] for r in frames]

        def frame_at_ms(ms):
            i = bisect_right(fms, ms) - 1
            return frames[max(i, 0)]['f'] if frames else 0

        plays = []
        for p in sfx.get('played', []) or []:
            plays.append(dict(p, f=frame_at_ms(p['t'] * 1000.0)))
        rows = []
        for e in events:
            f = e['f']
            name = e['name']
            c = canon(name, e.get('params', {}))
            spec = ve.get(c, {})
            # hitstop
            hs = 0
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
                    g += 1
            # shake: a new shake starts when sh_t jumps up to about sh_d
            sh = 0.0
            prev = byf.get(f - 1, {})
            for d in range(0, 4):
                r = byf.get(f + d)
                if not r:
                    continue
                if r.get('sh_t', 0) > prev.get('sh_t', 0) + 0.01 or (r.get('sh_amp', 0) > prev.get('sh_amp', 0) + 0.005):
                    sh = max(sh, r.get('sh_amp', 0))
                prev = r
            sq = 0.0
            for d in range(0, 21):
                r = byf.get(f + d)
                if r and 'sq' in r:
                    sq = max(sq, abs(r['sq']))
            v0 = byf.get(f - 1, {}).get('vfx')
            v1 = byf.get(f + 1, {}).get('vfx')
            vfx = (v1 - v0) if (v0 is not None and v1 is not None) else None
            names = {name, c}
            names |= {k for k, t in sal.items() if t in names}
            mine = [p for p in plays if p['event'] in names and -1 <= p['f'] - f <= 40]
            rows.append({
                'f': f, 'name': name, 'canon': c, 'pstate': e.get('pstate', ''), 'cam_dist': e.get('cam_dist'),
                'params': e.get('params', {}),
                'exp_shake': spec.get('shake'), 'exp_hitstop_ms': spec.get('hitstop_ms'),
                'exp_vfx': len(spec.get('vfx', [])) + (1 if spec.get('by_param') or spec.get('tiers') else 0),
                'hitstop_frames': hs, 'shake_amp': round(sh, 3), 'squash_peak': round(sq, 3), 'vfx_spawned': vfx,
                'sfx_keys': [p['key'] for p in mine], 'sfx_first_df': (min(p['f'] for p in mine) - f) if mine else None,
            })
        # aggregate per canonical event
        agg = {}
        for r in rows:
            a = agg.setdefault(r['canon'], {'n': 0, 'hs': [], 'sh': [], 'sq': [], 'vfx': [], 'sfx_n': 0, 'sfx_df': [], 'keys': set(),
                                            'exp_shake': r['exp_shake'], 'exp_hs': r['exp_hitstop_ms'], 'dist': []})
            a['n'] += 1
            a['hs'].append(r['hitstop_frames'])
            a['sh'].append(r['shake_amp'])
            a['sq'].append(r['squash_peak'])
            if r['vfx_spawned'] is not None:
                a['vfx'].append(r['vfx_spawned'])
            if r['sfx_keys']:
                a['sfx_n'] += 1
                a['sfx_df'].append(r['sfx_first_df'])
                a['keys'] |= set(r['sfx_keys'])
            if r['cam_dist'] is not None and r['cam_dist'] >= 0:
                a['dist'].append(r['cam_dist'])
        table = []
        print(f'\n== {tag}: {len(rows)} events, {len(agg)} distinct, {len(plays)} sfx plays, {len(frames)} frames ==')
        print(f"{'event':28} {'n':>3} {'hs exp/got(fr)':>15} {'shake exp/got':>16} {'sq':>5} {'vfx':>5} {'sfx':>6} {'dF':>4}  keys")
        for k, a in sorted(agg.items(), key=lambda kv: kv[0]):
            mx = lambda xs: max(xs) if xs else 0
            exp_hs = a['exp_hs'] or 0
            exp_sh = a['exp_shake'][0] if a['exp_shake'] else 0
            line = {
                'event': k, 'n': a['n'], 'exp_hitstop_ms': exp_hs, 'hitstop_frames_max': mx(a['hs']),
                'exp_shake': exp_sh, 'shake_amp_max': round(mx(a['sh']), 3), 'squash_max': round(mx(a['sq']), 3),
                'vfx_mean': round(sum(a['vfx']) / len(a['vfx']), 2) if a['vfx'] else None,
                'sfx_events_with_sound': a['sfx_n'], 'sfx_df_min': min(a['sfx_df']) if a['sfx_df'] else None,
                'sfx_keys': sorted(a['keys']), 'cam_dist_mean': round(sum(a['dist']) / len(a['dist']), 1) if a['dist'] else None,
            }
            table.append(line)
            print(f"{k:28} {a['n']:>3} {exp_hs:>6.0f}/{mx(a['hs']):<3}      {exp_sh:>6.2f}/{mx(a['sh']):<6.3f}  {mx(a['sq']):>5.2f} "
                  f"{(line['vfx_mean'] if line['vfx_mean'] is not None else -1):>5} {a['sfx_n']:>3}/{a['n']:<2} {str(line['sfx_df_min']):>4}  "
                  f"{','.join(sorted(a['keys']))[:60]}")
        out = {'tag': tag, 'rows': rows, 'table': table, 'marks': marks, 'unknown_stat': frames[-1].get('unk') if frames else None,
               'dropped': frames[-1].get('drop') if frames else None, 'culled': frames[-1].get('cull') if frames else None}
        (data / f'{tag}_feel.json').write_text(json.dumps(out, indent=1), encoding='utf-8')
        print('dropped', out['dropped'], 'culled', out['culled'], 'unknown', out['unknown_stat'])


if __name__ == '__main__':
    main()

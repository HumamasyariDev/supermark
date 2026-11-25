"""Critique JUICE r2, PERFORMANCE lens: charts and a summary table from the PerfProbeR2 JSON files.

    python game/tests/critique_juice/analyse_r2.py <r2 raw dir> <out png> [W1 W3 BOSS ...]

Reads <raw>/<world>_perf.json (r2) and, when present, Docs/progress/critique/juice/r1_perf/raw/<world>_perf.json (r1)
for a before/after comparison. Prints a summary and writes one PNG with four panels:
  1. frame-time p50/p99 per phase (r1 vs r2) for the burst phases
  2. GPU p50/p99 per phase
  3. burst CPU split: Juice.event() calls ms, full vs silent (VFX only) vs sfx_only
  4. per-frame trace after the 12-heavy spike (frame ms, GPU ms, visible pooled fx)
"""
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

HERE = Path(__file__).resolve().parent
ENTITY = HERE.parents[2]
R1 = ENTITY / 'Docs/progress/critique/juice/r1_perf/raw'
PHASES = ['idle_world', 'idle_ambient', 'combat_mix', 'combat_mix_hitstop_on', 'stress_3_per_frame', 'spike_12_heavy',
          'normal_burst_gpu', 'closeup_burst_gpu']


ABBR = {'idle_world': 'idle', 'idle_ambient': 'ambient', 'combat_mix': 'combat', 'combat_mix_hitstop_on': 'combat+hitstop',
        'stress_3_per_frame': 'stress 3/frame', 'spike_12_heavy': 'spike 12 heavy', 'normal_burst_gpu': 'burst', 'closeup_burst_gpu': 'burst close-up'}


def load(p):
    try:
        return json.loads(Path(p).read_text(encoding='utf-8'))
    except Exception:
        return None


def main():
    raw = Path(sys.argv[1])
    out = Path(sys.argv[2])
    worlds = sys.argv[3:] or ['W1']
    data = {w: load(raw / f'{w}_perf.json') for w in worlds}
    old = {w: load(R1 / f'{w}_perf.json') for w in worlds}
    data = {w: d for w, d in data.items() if d}
    if not data:
        print('no r2 data')
        return
    fig, axes = plt.subplots(2, 2, figsize=(19, 13))
    ax1, ax2, ax3, ax4 = axes[0][0], axes[0][1], axes[1][0], axes[1][1]
    labels, r1v, r2v, r1g, r2g = [], [], [], [], []
    for w, d in data.items():
        o = old.get(w) or {}
        for ph in PHASES:
            if ph not in d:
                continue
            labels.append(f'{w}\n{ph.replace("_", " ")}')
            r2v.append((d[ph]['frame_ms']['p50'], d[ph]['frame_ms']['p99']))
            r2g.append((d[ph]['gpu_ms']['p50'], d[ph]['gpu_ms']['p99']))
            oo = o.get(ph)
            r1v.append((oo['frame_ms']['p50'], oo['frame_ms']['p99']) if oo else (0, 0))
            r1g.append((oo['gpu_ms']['p50'], oo['gpu_ms']['p99']) if oo else (0, 0))
            print(f'{w:5} {ph:28} frame p50 {d[ph]["frame_ms"]["p50"]:6.2f} p95 {d[ph]["frame_ms"]["p95"]:6.2f} p99 {d[ph]["frame_ms"]["p99"]:6.2f} '
                  f'max {d[ph]["frame_ms"]["max"]:6.2f} >16.7 {d[ph]["frame_ms"]["over_16_7ms"]:4d} | gpu p50 {d[ph]["gpu_ms"]["p50"]:6.2f} '
                  f'p99 {d[ph]["gpu_ms"]["p99"]:6.2f} max {d[ph]["gpu_ms"]["max"]:6.2f} | draws {d[ph]["draw_calls"]["mean"]:.0f}/{d[ph]["draw_calls"]["max"]:.0f}'
                  + (f' | r1 frame p99 {oo["frame_ms"]["p99"]:.2f} gpu p99 {oo["gpu_ms"]["p99"]:.2f}' if oo else ''))
    x = range(len(labels))
    wdt = 0.2
    for ax, a, b, title in ((ax1, r1v, r2v, 'Frame time ms (vsync off): p50 solid, p99 hatched'), (ax2, r1g, r2g, 'GPU ms: p50 solid, p99 hatched')):
        ax.bar([i - 1.5 * wdt for i in x], [v[0] for v in a], wdt, color='#b9a7d6', label='r1 p50')
        ax.bar([i - 0.5 * wdt for i in x], [v[1] for v in a], wdt, color='#b9a7d6', hatch='//', edgecolor='#5a4a7a', label='r1 p99')
        ax.bar([i + 0.5 * wdt for i in x], [v[0] for v in b], wdt, color='#3d8fd1', label='r2 p50')
        ax.bar([i + 1.5 * wdt for i in x], [v[1] for v in b], wdt, color='#3d8fd1', hatch='//', edgecolor='#1c4e78', label='r2 p99')
        ax.axhline(16.7, color='#d14b3d', lw=1, ls='--')
        ax.text(len(labels) - 0.5, 17.2, '16.7 ms (60 fps)', color='#d14b3d', ha='right', fontsize=8)
        ax.set_xticks(list(x))
        ax.set_xticklabels(labels, fontsize=7.5, rotation=70, ha='right')
        ax.set_title(title)
        ax.legend(fontsize=8)
    # burst split
    bl, full, silent, sfx = [], [], [], []
    for w, d in data.items():
        b = d.get('bursts', {})
        for k in ('slam_group_8', 'heavy_12'):
            if k in b:
                bl.append(f'{w} {k}')
                full.append(b[k]['calls_ms_median'])
                silent.append(b.get(k + '_silent', {}).get('calls_ms_median', 0))
                sfx.append(b.get(k + '_sfx_only', {}).get('calls_ms_median', 0))
                print(f'{w:5} burst {k:14} calls full {full[-1]:.2f} ms | silent (VFX side) {silent[-1]:.2f} | sfx only {sfx[-1]:.2f} | '
                      f'burst frame excess full {b[k]["burst_frame_excess_ms_median"]:.2f} silent {b.get(k + "_silent", {}).get("burst_frame_excess_ms_median", 0):.2f} '
                      f'sfx {b.get(k + "_sfx_only", {}).get("burst_frame_excess_ms_median", 0):.2f}')
        c = d.get('cold', {})
        for k, v in c.items():
            print(f'{w:5} cold {k:22} calls {v["calls_ms"]:.2f} ms post max {v["post_max_ms"]:.2f} first frames {v["post_frames_ms"][:4]} per event {v["per_event_us"]}')
    xb = range(len(bl))
    ax3.bar([i - 0.27 for i in xb], full, 0.27, color='#d14b3d', label='full (VFX + JuiceSfx)')
    ax3.bar([i for i in xb], silent, 0.27, color='#3d8fd1', label='silent (Juice VFX side)')
    ax3.bar([i + 0.27 for i in xb], sfx, 0.27, color='#e3a33b', label='sfx only (no_vfx)')
    for i, v in enumerate(full):
        ax3.text(i - 0.27, v + 0.2, f'{v:.1f}', ha='center', fontsize=8)
    ax3.tick_params(axis='x', labelrotation=30)
    ax3.set_xticks(list(xb))
    ax3.set_xticklabels(bl, fontsize=8)
    ax3.set_ylabel('ms of main-thread script time in the Juice.event() calls (median of 6)')
    ax3.set_title('Burst CPU split: who pays for a burst')
    ax3.legend(fontsize=8)
    for w, d in data.items():
        tr = d.get('spike_12_heavy', {}).get('trace') or []
        if tr:
            fr = [t[0] - 10 for t in tr]
            ax4.plot(fr, [t[1] for t in tr], label=f'{w} frame ms')
            ax4.plot(fr, [t[2] for t in tr], ls='--', label=f'{w} GPU ms')
    ax4.axhline(16.7, color='#d14b3d', lw=1, ls='--')
    ax4.axvline(0, color='#555', lw=0.8)
    ax4.set_xlabel('frames after the 12-heavy burst (burst fired at 0; second beats at 0.18/0.42/0.60/0.90 s)')
    ax4.set_title('Per-frame trace after the 12-heavy spike')
    ax4.legend(fontsize=8)
    fig.suptitle('Super Mak 64 - JUICE critique r2, performance lens (PerfProbeR2, real worlds, vsync off, RTX 4070 SUPER, shared machine)')
    fig.tight_layout()
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=110)
    print('wrote', out)
    for w, d in data.items():
        for k in ('attach_leak', 'loops_leak'):
            if k in d:
                print(w, k, json.dumps(d[k])[:900])
        if 'combat_mix_hitstop_on' in d:
            c = d['combat_mix_hitstop_on']
            print(w, 'combat_hs cam before', c.get('cam_offset_before'), 'after', c.get('cam_offset_after'), 'time_scale', c.get('time_scale_after'))
        for r in d.get('reload', []):
            print(w, 'reload', r.get('load'), 'nodes', r.get('nodes'), 'objects', r.get('objects'), 'res', r.get('resources'), 'static', r.get('static_mb'),
                  'video', r.get('video_mb'), 'pool', r.get('pool_nodes'), 'attached', r.get('attached_counter'), 'before change', r.get('attached_counter_before_change'),
                  'top5', r.get('load_top5'))
        soak = d.get('soak', [])
        if soak:
            print(w, 'soak nodes', [s.get('nodes') for s in soak], 'static', [s.get('static_mb') for s in soak], 'pool', [s.get('pool_nodes') for s in soak],
                  'attached', [s.get('attached_counter') for s in soak])
        ld = d.get('load', {})
        print(w, 'load first', ld.get('first_frame_ms'), 'prewarm frame', ld.get('prewarm_frame'), 'window', ld.get('prewarm_window_ms'), 'top', ld.get('top10'))


if __name__ == '__main__':
    main()

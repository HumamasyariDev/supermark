"""Critique audio r1 QA (rerun after the implementation stage): read an AudioFlowQA output dir and print
warnings/errors, missing keys, spam (same file restarted within 60 ms / >N per second), concurrency, music and
ambience state around every scene mark, music overlap/gap windows, and JuiceSfx events fired vs the table.
Usage: python -I analyze_run.py <run_dir> [juice_sfx.json]"""
import json, sys, re, collections, pathlib

d = pathlib.Path(sys.argv[1])
G = pathlib.Path(__file__).resolve().parents[2]
J = json.load(open(sys.argv[2] if len(sys.argv) > 2 else G / 'assets/audio/juice_sfx.json'))
L = lambda n: json.load(open(d / (n + '.json'))) if (d / (n + '.json')).exists() else []
starts, tl, marks, log = L('starts'), L('timeline'), L('marks'), L('log')
summ = json.load(open(d / 'summary.json')) if (d / 'summary.json').exists() else {}
out = []
P = lambda *a: out.append(' '.join(str(x) for x in a))

P('== summary', json.dumps({k: summ.get(k) for k in ('t', 'starts', 'log_rows', 'marks', 'timeline_rows', 'blocked_time')}))
P('== marks')
for m in marks:
    P(f"  {m['t']:7.2f} {m['scene']:12s} {m['mark']}")

P('== warnings / errors (dedup)')
seen = collections.Counter()
first = {}
for r in log:
    if r.get('type') == 'msg' and not re.search(r'(?i)warn|error|missing|cannot|failed', r['msg']):
        continue
    k = re.sub(r'\d+\.\d+', '#', r['msg'])[:200]
    seen[(r.get('type'), r['scene'], k)] += 1
    first.setdefault((r.get('type'), r['scene'], k), r['t'])
for (ty, sc, k), n in sorted(seen.items(), key=lambda x: first[x[0]]):
    P(f"  [{ty}] {sc:12s} x{n:<4d} t={first[(ty, sc, k)]:.1f} {k}")

P('== JuiceSfx plays by event (from --juice-sfx-log)')
ev = collections.Counter(); evkeys = collections.defaultdict(collections.Counter); ev_scene = collections.defaultdict(set)
for r in log:
    m = re.match(r'\[JuiceSfx\] [\d.]+ (\S+) -> (\S+)', r['msg'])
    if m:
        ev[m.group(1)] += 1; evkeys[m.group(1)][m.group(2)] += 1; ev_scene[m.group(1)].add(r['scene'])
for e, n in ev.most_common():
    P(f"  {e:32s} {n:4d} {dict(evkeys[e].most_common(6))} {sorted(ev_scene[e])}")
table = set(J['events'].keys())
P('  table events fired:', len(set(ev) & table), '/', len(table))
P('  fired but not in table:', sorted(set(ev) - table))

P('== starts per bus/scene, top files')
by = collections.Counter((s['scene'], s['bus']) for s in starts)
for k, n in sorted(by.items()):
    P('  ', k, n)
files = collections.Counter((s['scene'], s['file']) for s in starts if s['bus'] in ('SFX', 'Voice'))
for (sc, f), n in files.most_common(30):
    P(f"   {sc:12s} {f:40s} {n}")

P('== spam: same file restarted <60 ms; >6 starts of one file in any 1 s window')
by_f = collections.defaultdict(list)
for s in starts:
    by_f[s['file']].append(s)
dup = collections.Counter(); burst = {}
for f, arr in by_f.items():
    ts = [a['t'] for a in arr]
    for i in range(1, len(ts)):
        if ts[i] - ts[i - 1] < 0.06:
            dup[(arr[i]['scene'], f)] += 1
    j = 0
    for i in range(len(ts)):
        while ts[i] - ts[j] > 1.0:
            j += 1
        if i - j + 1 > 6:
            cand = (i - j + 1, ts[i], arr[i]['scene'])
            if cand[0] > burst.get(f, (0, 0, ''))[0]:
                burst[f] = cand
for (sc, f), n in dup.most_common(20):
    P(f"  dup<60ms {sc:12s} {f:40s} x{n}")
for f, v in sorted(burst.items(), key=lambda x: -x[1][0]):
    P(f"  burst {f:40s} {v[0]}/s at t={v[1]:.1f} ({v[2]})")

P('== voice: overlapping Voice-bus starts (<0.25 s apart)')
vs = [s for s in starts if s['bus'] == 'Voice']
for a, b in zip(vs, vs[1:]):
    if b['t'] - a['t'] < 0.25:
        P(f"  {a['t']:.2f} {a['file']} -> {b['t']:.2f} {b['file']} ({b['scene']})")

P('== music/ambience state per mark (+0.5 s, +3 s, +6 s)')
def at(t):
    best = None
    for r in tl:
        if r['t'] >= t:
            return r
        best = r
    return best
def mus(r):
    s = []
    for k in ('mA', 'mB', 'jin', 'amb'):
        v = r.get(k, {})
        if v.get('on'):
            s.append(f"{k}:{v['file']}@{v['vol']}")
    jl = r.get('jloops', [])
    if jl:
        s.append('jloops:' + ','.join(f"{x.get('file','?')}@{x.get('vol','?')}" if isinstance(x, dict) else str(x) for x in jl))
    pk = r.get('peak', {})
    s.append('peak M%.0f A%.0f S%.0f' % (pk.get('Music', -99), pk.get('Ambience', -99), pk.get('SFX', -99)))
    return ' | '.join(s)
for m in marks:
    if m['mark'] != 'arrived' and not m['mark'].startswith('step'):
        continue
    for dt in (0.5, 3.0, 6.0):
        r = at(m['t'] + dt)
        if r:
            P(f"  {m['t']+dt:7.2f} {r['scene']:12s} {m['mark'][:18]:18s} {mus(r)}")

P('== windows: two music players audible (> -30 dB) together > 2.5 s; no audible music (> -40 dB) > 1.5 s outside title/loading')
def runs(pred):
    res = []; st = None; sc = None
    for r in tl:
        if pred(r):
            if st is None:
                st = r['t']; sc = r['scene']
        elif st is not None:
            res.append((st, r['t'], sc)); st = None
    return res
both = runs(lambda r: r['mA'].get('on') and r['mB'].get('on') and r['mA']['vol'] > -30 and r['mB']['vol'] > -30)
for a, b, sc in both:
    if b - a > 2.5:
        P(f"  OVERLAP {a:.1f}-{b:.1f} ({b-a:.1f}s) {sc}")
quiet = runs(lambda r: not r.get('paused') and not ((r['mA'].get('on') and r['mA']['vol'] > -40) or (r['mB'].get('on') and r['mB']['vol'] > -40) or r['jin'].get('on')))
for a, b, sc in quiet:
    if b - a > 1.5:
        P(f"  NO-MUSIC {a:.1f}-{b:.1f} ({b-a:.1f}s) {sc}")
noamb = runs(lambda r: r['scene'] in ('HUB', 'W1', 'W2', 'W3', 'BOSS') and not r['amb'].get('on') and not any((x.get('on', True) if isinstance(x, dict) else True) for x in r.get('jloops', [])))
for a, b, sc in noamb:
    if b - a > 1.5:
        P(f"  NO-AMBIENCE {a:.1f}-{b:.1f} ({b-a:.1f}s) {sc}")
P('== conc_max', json.dumps(summ.get('conc_max', {})))
txt = '\n'.join(out)
print(txt)
(d / 'analysis.txt').write_text(txt, encoding='utf-8')

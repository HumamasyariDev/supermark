"""Critique audio r2 (QA lens). Extra analysis on top of analyze_run.py for one AudioFlowQA output dir:
  - transitions: for every scene change, the music hole (no music player > -40 dB), the full-mix silence
    (Master bus peak < -60 dB), the ambience-bus hole (< -60 dB) and how long the old music took to fade
  - steals: audible sounds cut by the round-robin pools (steal_of with > 0.15 s left), by scene and stolen file
  - spam: same file restarted < 60 ms, worst 1 s burst per file, 3D starts beyond 60 m / 70 m
  - per-key start rate per scene (starts per minute) for the top keys
  - warnings/errors from the Logger capture (dedup) and JuiceSfx 'missing'/'unknown' lines
Usage: python r2_analyze.py <run_dir>   (writes <run_dir>/r2_analysis.txt and r2_analysis.json)"""
import json, sys, re, collections, pathlib

d = pathlib.Path(sys.argv[1])
L = lambda n: json.load(open(d / (n + '.json'))) if (d / (n + '.json')).exists() else []
starts, tl, marks, log = L('starts'), L('timeline'), L('marks'), L('log')
out, J = [], {}
P = lambda *a: out.append(' '.join(str(x) for x in a))

# ---------------------------------------------------------------- transitions
P('== transitions (scene change in the timeline)')
P('   t_change  from -> to        music_hole  master_silence  amb_hole  old_fade')
J['transitions'] = []
def music_on(r):
    return any(r[k].get('on') and r[k]['vol'] > -40 for k in ('mA', 'mB')) or r['jin'].get('on')
for i in range(1, len(tl)):
    a, b = tl[i - 1], tl[i]
    if a['scene'] == b['scene']:
        continue
    # window: 4 s before .. 6 s after
    w = [r for r in tl if b['t'] - 4.0 <= r['t'] <= b['t'] + 6.0]
    def hole(pred):
        best, st = 0.0, None
        for r in w:
            if pred(r):
                st = r['t'] if st is None else st
                best = max(best, r['t'] - st)
            else:
                st = None
        return round(best, 2)
    mh = hole(lambda r: not music_on(r) and r['peak'].get('Music', -99) < -40)
    ms = hole(lambda r: r['peak'].get('Master', -99) < -60)
    ah = hole(lambda r: r['peak'].get('Ambience', -99) < -60) if b['scene'] not in ('TitleScreen', '(none)') else None
    row = {'t': b['t'], 'from': a['scene'], 'to': b['scene'], 'music_hole_s': mh, 'master_silence_s': ms, 'amb_hole_s': ah}
    J['transitions'].append(row)
    P(f"  {b['t']:8.2f}  {a['scene']:>10s} -> {b['scene']:<10s} {mh:6.2f}      {ms:6.2f}        {ah if ah is not None else '-':>5}")

# ---------------------------------------------------------------- steals
P('== audible steals (round-robin pool cut a sound with > 0.15 s left)')
st = [s for s in starts if s.get('steal_of') and s.get('steal_left', 0) > 0.15]
c = collections.Counter((s['scene'], s['steal_of']) for s in st)
J['steals_total'] = len(st)
for (sc, f), n in c.most_common(25):
    P(f"  {sc:10s} {f:34s} x{n}")
P(f"  total {len(st)}")

# ---------------------------------------------------------------- spam
P('== spam')
byfile = collections.defaultdict(list)
for s in starts:
    byfile[(s['scene'], s['file'])].append(s['t'])
spam = []
for (sc, f), ts in byfile.items():
    ts.sort()
    dup = sum(1 for x, y in zip(ts, ts[1:]) if y - x < 0.06)
    burst = max((sum(1 for y in ts if x <= y < x + 1.0) for x in ts), default=0)
    if dup or burst >= 5:
        spam.append((sc, f, dup, burst, len(ts)))
for sc, f, dup, burst, n in sorted(spam, key=lambda x: (-x[3], -x[2])):
    P(f"  {sc:10s} {f:34s} dup<60ms={dup:<3d} worst_1s={burst:<3d} total={n}")
J['spam'] = [dict(zip(('scene', 'file', 'dup60', 'burst1s', 'total'), x)) for x in spam]
far = collections.Counter((s['scene'], s['file']) for s in starts if s.get('3d') and s.get('dist', 0) > 60)
P('== 3D starts beyond 60 m of the camera (scene, file: count)')
for (sc, f), n in far.most_common(15):
    P(f"  {sc:10s} {f:34s} x{n}")
J['far60'] = sum(far.values())

# ---------------------------------------------------------------- rate per scene
P('== starts per minute by scene (scene time from timeline rows)')
scene_t = collections.Counter()
for a, b in zip(tl, tl[1:]):
    scene_t[a['scene']] += b['t'] - a['t']
bysc = collections.defaultdict(collections.Counter)
for s in starts:
    bysc[s['scene']][s['file']] += 1
for sc, cnt in bysc.items():
    secs = max(scene_t.get(sc, 1.0), 1.0)
    tot = sum(cnt.values())
    top = ', '.join(f"{f} {n * 60 / secs:.0f}/min" for f, n in cnt.most_common(5))
    P(f"  {sc:12s} {secs:6.1f}s {tot:4d} starts ({tot * 60 / secs:5.0f}/min)  top: {top}")

# ---------------------------------------------------------------- log
P('== warnings / errors / missing (dedup)')
seen, first = collections.Counter(), {}
for r in log:
    msg = r.get('msg', '')
    if r.get('type') == 'msg' and not re.search(r'(?i)warn|error|missing|cannot|failed|unknown|no key', msg):
        continue
    k = re.sub(r'\d+(\.\d+)?', '#', msg)[:180]
    seen[(r.get('type'), r.get('scene'), k)] += 1
    first.setdefault((r.get('type'), r.get('scene'), k), r.get('t', 0))
for (ty, sc, k), n in sorted(seen.items(), key=lambda x: first[x[0]]):
    P(f"  [{ty}] {sc:12s} x{n:<4d} t={first[(ty, sc, k)]:.1f} {k}")
J['log_issues'] = len(seen)

txt = '\n'.join(out)
print(txt)
(d / 'r2_analysis.txt').write_text(txt, encoding='utf-8')
(d / 'r2_analysis.json').write_text(json.dumps(J, indent=1), encoding='utf-8')

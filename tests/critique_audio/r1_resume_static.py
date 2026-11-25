"""Critic audio QA (resumed production, round 1): read-only static audit.
- every key referenced anywhere in juice_sfx.json (layers, cases, templates, fallbacks, ambience, scatter, stings,
  states, proximity, mix) resolves in audio_index.json;
- every audio_index.json file exists on disk and has a .import sidecar (a missing .import = load error in export);
- every literal Juice.event / _fb / feedback name in game/ code (scripts, scenes, assets; tests excluded) is a
  JuiceSfx event or alias, and every JuiceSfx event is emitted by some code (dead rows = sounds that never fire);
- every literal play_sfx/play_voice/play_jingle/play_music/play_ambience key in game/ code resolves.
Usage: python -I r1_resume_static.py
"""
import json, re, pathlib, collections

G = pathlib.Path(__file__).resolve().parents[2]
A = G / 'assets/audio'
J = json.load(open(A / 'juice_sfx.json', encoding='utf-8'))
I = json.load(open(A / 'audio_index.json', encoding='utf-8'))
keys = {e['key']: e for e in I['entries']}
SURF = ['grass', 'wood', 'stone', 'candy', 'carpet', 'jelly', 'metal', 'cloud']

out = []
P = lambda *a: out.append(' '.join(str(x) for x in a))

# ---- 1. keys referenced by juice_sfx.json
refs = collections.defaultdict(set)


def walk(o, path):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ('key', 'loop_key', 'sting', 'stop_key') and isinstance(v, str):
                refs[v].add(path)
            elif k in ('keys', 'fallback') and isinstance(v, list):
                for x in v:
                    if isinstance(x, str):
                        refs[x].add(path)
            elif k == 'beds' and isinstance(v, dict):
                for x in v.values():
                    refs[x].add(path + '/beds')
            walk(v, path + '/' + str(k))
    elif isinstance(o, list):
        for i, v in enumerate(o):
            walk(v, path)


walk(J, '')
missing = {}
for k, where in refs.items():
    cands = [k]
    if '{' in k:
        cands = [re.sub(r'\{[a-z_]+\}', s, k) for s in SURF]
        bad = [c for c in cands if c not in keys]
        if bad:
            missing[k + ' -> ' + ','.join(bad)] = where
        continue
    if k not in keys:
        missing[k] = where
P('== 1. juice_sfx.json keys:', len(refs), 'referenced;', len(missing), 'missing')
for k, w in sorted(missing.items()):
    P('  MISSING', k, sorted(w)[:3])

# ---- 2. files on disk
nofile, noimp = [], []
nfiles = 0
for k, e in keys.items():
    fs = e.get('files') or ([e['file']] if 'file' in e else [])
    for f in fs:
        f = f['file'] if isinstance(f, dict) else f
        nfiles += 1
        p = A / f if not f.startswith('res://') else G / f[6:]
        if not p.exists():
            nofile.append((k, f))
        elif not pathlib.Path(str(p) + '.import').exists():
            noimp.append((k, f))
P('== 2. index files:', nfiles, 'refs;', len(nofile), 'missing on disk;', len(noimp), 'without .import')
for x in nofile[:40]:
    P('  NOFILE', x)
for x in noimp[:40]:
    P('  NOIMPORT', x)

# ---- 3. events emitted by code vs table
events = J['events']
aliases = J.get('aliases', {})
pat_ev = re.compile(r'(?:Juice\.event|\b_fb|feedback|juice_event|_juice|emit_juice|_jev|_event)\(\s*"([a-z0-9_]+)"')
pat_key = re.compile(r'(?:play_sfx|play_voice|play_jingle|play_ambience|play_music|play_ui|\.sfx|_sfx|play_key)\(\s*"([a-z0-9_]+)"')
pat_call = re.compile(r'call\(\s*"play_(?:sfx|voice|jingle|music|ambience|ui)"\s*,\s*"([a-z0-9_]+)"')
emitted = collections.defaultdict(set)
called = collections.defaultdict(set)
for p in G.rglob('*.gd'):
    rel = str(p.relative_to(G)).replace('\\', '/')
    if rel.startswith('.godot') or '/tests/' in '/' + rel or rel.startswith('tests'):
        continue
    t = p.read_text(encoding='utf-8', errors='ignore')
    for m in pat_ev.finditer(t):
        emitted[m.group(1)].add(rel)
    for m in pat_key.finditer(t):
        called[m.group(1)].add(rel)
    for m in pat_call.finditer(t):
        called[m.group(1)].add(rel)
juice_names = set(events) | set(aliases)
unknown_ev = {e: w for e, w in emitted.items() if e not in juice_names and e not in keys}
P('== 3. events emitted in code:', len(emitted), '; not in juice_sfx events/aliases (and not a raw key):', len(unknown_ev))
for e, w in sorted(unknown_ev.items()):
    P('  NOEVENT', e, sorted(w)[:3])
alias_targets = collections.defaultdict(set)
for a, t in aliases.items():
    alias_targets[t if isinstance(t, str) else str(t)].add(a)
dead = []
for e in events:
    names = {e} | alias_targets.get(e, set())
    if not any(n in emitted for n in names):
        dead.append(e)
P('== 3b. juice_sfx events with no literal emitter in code (may be emitted by computed names):', len(dead))
for e in dead:
    P('  NOEMITTER', e)

# ---- 4. direct keys
miss_k = {k: w for k, w in called.items() if k not in keys and not k.startswith('jingle_') and ('jingle_' + k) not in keys}
P('== 4. literal direct keys:', len(called), '; missing:', len(miss_k))
for k, w in sorted(miss_k.items()):
    P('  NOKEY', k, sorted(w)[:3])

# ---- 5. index keys referenced by nothing (bank bloat / forgotten wiring)
used = set(refs) | set(called) | set(emitted)
for k in list(refs):
    if '{' in k:
        used |= {re.sub(r'\{[a-z_]+\}', s, k) for s in SURF}
src = ''.join(p.read_text(encoding='utf-8', errors='ignore') for p in G.rglob('*.gd') if '.godot' not in str(p))
src += ''.join(p.read_text(encoding='utf-8', errors='ignore') for p in G.rglob('*.tscn') if '.godot' not in str(p))
unused = [k for k in keys if k not in used and ('"%s"' % k) not in src]
P('== 5. index keys never referenced by code or juice_sfx.json:', len(unused))
P('  ', ' '.join(sorted(unused)))
print('\n'.join(out))

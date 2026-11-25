"""Critic coverage audit (audio director r1). Read-only: greps game/scripts for event names and sfx keys
and compares them with juice_sfx.json and audio_index.json."""
import json, re, pathlib, sys, collections
G = pathlib.Path(__file__).resolve().parents[2]
J = json.load(open(G/'assets/audio/juice_sfx.json'))
IDX = json.load(open(G/'assets/audio/audio_index.json'))
keys = {e['key']: e for e in IDX['entries']}
events = J['events']; aliases = J.get('aliases', {})
pat_ev = re.compile(r'(?:Juice\.event|_fb|feedback|juice_event|_juice|emit_juice)\(\s*"([a-z0-9_]+)"')
pat_key = re.compile(r'(?:play_sfx|play_voice|play_jingle|play_ambience|play_music|\.sfx|_sfx|play_key)\(\s*"([a-z0-9_]+)"')
pat_call = re.compile(r'call\(\s*"play_(?:sfx|voice)"\s*,\s*"([a-z0-9_]+)"')
found_ev = collections.defaultdict(set); found_key = collections.defaultdict(set)
for p in (G/'scripts').rglob('*.gd'):
    t = p.read_text(encoding='utf-8', errors='ignore')
    rel = str(p.relative_to(G))
    for m in pat_ev.finditer(t): found_ev[m.group(1)].add(rel)
    for m in pat_key.finditer(t): found_key[m.group(1)].add(rel)
    for m in pat_call.finditer(t): found_key[m.group(1)].add(rel)
def has_key(k):
    return k in keys
miss_ev = {e: sorted(f) for e, f in found_ev.items() if e not in events and e not in aliases and not has_key(e)}
miss_key = {k: sorted(f) for k, f in found_key.items() if not has_key(k) and k not in events and k not in aliases}
# events in table never emitted
unused = [e for e in events if e not in found_ev]
# keys referenced by table but missing from index
tbl_keys=set()
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ('key','keys','fallback') and isinstance(v,str): tbl_keys.add(v)
            elif k in ('key','keys') and isinstance(v,list):
                [tbl_keys.add(x) for x in v if isinstance(x,str)]
            else: walk(v)
    elif isinstance(o, list): [walk(x) for x in o]
walk(events)
bad_tbl = sorted(k for k in tbl_keys if '{' not in k and not has_key(k))
out = dict(emitted_events=len(found_ev), table_events=len(events), missing_events=miss_ev,
           direct_keys=len(found_key), missing_keys=miss_key, table_events_never_emitted=unused,
           table_keys_missing_from_index=bad_tbl)
print(json.dumps(out, indent=1))

# Second pass: any quoted literal of a table event anywhere in gameplay scripts (labs/probes excluded),
# which catches EnemyKit.juice(self, "enemy_x"), UIFx.event("ui_x") and lookup dicts.
SKIP = ('juice_lab', 'juice_world_probe', 'ui_showcase', '_lab', '_test', 'probe')
lit = collections.defaultdict(set)
for p in (G/'scripts').rglob('*.gd'):
    if any(s in p.name for s in SKIP):
        continue
    t = p.read_text(encoding='utf-8', errors='ignore')
    for e in events:
        if '"%s"' % e in t:
            lit[e].add(p.name)
never = [e for e in events if e not in lit]
print('TABLE EVENTS WITH NO LITERAL IN GAMEPLAY SCRIPTS (%d):' % len(never))
print(json.dumps(never))

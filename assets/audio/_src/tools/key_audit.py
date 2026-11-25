"""Bank audit added in fix stage r1b (critique r1: missing keys hid behind wrapper calls; a loop key was played as a
one-shot; attack whooshes peaked after the strike).

1. Script keys: every string literal passed to Audio.play_sfx / play_ui / play_voice / play_music / play_jingle /
   play_ambience, to call("play_sfx", ...), and to the wrappers the world, object and enemy scripts use
   (_sfx(, sfx(, _play(, EnemyKit.sfx(self, ...)) must exist in audio_index.json (EnemyKit aliases count as resolved).
2. Loop keys: no key with loop:true may be called through a one-shot path (play_sfx, play_ui, the wrappers).
3. Peak timing: the attack whooshes must peak inside the strike window (swish 40-90 ms, spin_kick 80-150 ms,
   jump_kick 60-160 ms), measured on 5 ms RMS frames.
Writes _src/reports/key_audit.json and exits 1 on any failure. Usage: python key_audit.py"""
import json, re, sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A

AUD = Path(__file__).resolve().parents[2]
GAME = AUD.parents[1]
import os
idx = {e["key"]: e for e in json.loads(Path(os.environ.get("AUDIT_INDEX", AUD / "audio_index.json")).read_text())["entries"]}

ONE_SHOT = r"(?:play_sfx|play_ui|(?<![\w])_sfx|EnemyKit\.sfx|(?<![\w.])sfx|_play_sfx|(?<![\w])_snd)"
PATTERNS = [
    (re.compile(ONE_SHOT + r"\(\s*(?:self\s*,\s*)?\"([a-z0-9_]+)\""), "oneshot"),
    (re.compile(r"call\(\s*\"play_sfx\"\s*,\s*\"([a-z0-9_]+)\""), "oneshot"),
    (re.compile(r"moment_sfx\(\s*\"[a-z0-9_]+\"\s*,\s*\"([a-z0-9_]+)\""), "oneshot"),  # (juice event, fallback key)
    (re.compile(r"(?:play_voice|play_music|play_jingle|play_ambience)\(\s*\"([a-z0-9_]+)\""), "other"),
    (re.compile(r"call\(\s*\"(?:play_voice|play_music|play_jingle|play_ambience)\"\s*,\s*\"([a-z0-9_]+)\""), "other"),
]
# EnemyKit resolves its own aliases before calling Audio (enemy_kit.gd SFX_ALIASES)
kit = (GAME / "scripts" / "enemies" / "enemy_kit.gd").read_text(encoding="utf-8", errors="ignore")
kit_alias = {}
for m in re.finditer(r"\"([a-z0-9_]+)\":\s*\[(\[.*?\])\],?\n", kit):
    kit_alias[m.group(1)] = re.findall(r"\[\"([a-z0-9_]+)\"", m.group(2))

calls = {}
for p in sorted((GAME / "scripts").rglob("*.gd")):
    rel = p.relative_to(GAME).as_posix()
    if "/test" in rel or rel.endswith("_lab.gd") or "/tests/" in rel or rel.endswith("_showcase.gd"):
        continue
    txt = p.read_text(encoding="utf-8", errors="ignore")
    for i, line in enumerate(txt.splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        for rx, kind in PATTERNS:
            for m in rx.finditer(line):
                if m.group(1).endswith("_"):
                    continue  # a prefix joined at run time ("footstep_" + surface)
                calls.setdefault(m.group(1), []).append((f"{rel}:{i}", kind))

missing, loop_misuse = {}, {}
for k, where in sorted(calls.items()):
    cands = [k] + kit_alias.get(k, [])
    hit = next((c for c in cands if c in idx), None)
    if hit is None:
        missing[k] = [w for w, _ in where]
        continue
    if idx[hit].get("loop") and any(kind == "oneshot" for _, kind in where):
        loop_misuse[k] = [w for w, kind in where if kind == "oneshot"]

WINDOWS = {"swish": (40, 90), "spin_kick": (80, 150), "jump_kick": (60, 160)}
timing = {}
for key, (lo, hi) in WINDOWS.items():
    e = idx[key]
    for f in e.get("files") or [e["file"]]:
        x = A.decode(AUD / f, ch=1)
        fr, hop = A.frame_rms_db(x)
        pk = int(np.argmax(fr)) * hop / A.SR * 1000
        timing[f] = {"peak_ms": round(pk), "window": [lo, hi], "pass": lo <= pk <= hi}

bad_t = {f: r for f, r in timing.items() if not r["pass"]}
res = {"script_keys": len(calls), "missing": missing, "loop_keys_called_as_one_shot": loop_misuse, "attack_peaks": timing}
(AUD / "_src" / "reports" / "key_audit.json").write_text(json.dumps(res, indent=1))
print(f"script keys scanned: {len(calls)}")
print("missing:", missing or "none")
print("loop keys called as one-shots:", loop_misuse or "none")
for f, r in timing.items():
    print(f"  {'PASS' if r['pass'] else 'FAIL'} {f:28s} peak {r['peak_ms']:4d} ms (window {r['window'][0]}-{r['window'][1]})")
sys.exit(1 if (missing or loop_misuse or bad_t) else 0)

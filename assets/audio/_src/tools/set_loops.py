"""Set loop flags (and bpm/beat_count for music loops) in Godot .import files; drop the import md5 so Godot reimports."""
import json, re
from pathlib import Path
AUD = Path(__file__).resolve().parents[2]
GAME = AUD.parents[1]
idx = json.loads((AUD / "audio_index.json").read_text())
loop_files = {}
for e in idx["entries"]:
    if e.get("loop"):
        for f in e.get("files") or [e["file"]]:
            loop_files[f] = True
music_meta = {}
for rep in (AUD / "_src" / "reports").glob("loop_*.json"):
    r = json.loads(rep.read_text())
    out = Path(r["out"]).name
    bpm = round(r["loop"]["beats"] * 60.0 / r["loop_s"], 3)
    music_meta["music/" + out] = (bpm, r["loop"]["beats"], round(float(r.get("loop_offset_s", 0.0)), 4))
changed = 0
for f in loop_files:
    imp = AUD / (f + ".import")
    s = imp.read_text()
    s2 = re.sub(r"^loop=\w+", "loop=true", s, flags=re.M)
    if f in music_meta:
        bpm, beats, offset = music_meta[f]
        s2 = re.sub(r"^loop_offset=[\d.]+", f"loop_offset={offset}", s2, flags=re.M)
        s2 = re.sub(r"^bpm=[\d.]+", f"bpm={bpm}", s2, flags=re.M)
        s2 = re.sub(r"^beat_count=\d+", f"beat_count={beats}", s2, flags=re.M)
    if s2 != s:
        imp.write_text(s2)
        changed += 1
        m = re.search(r'path="res://\.godot/imported/([^"]+)\.oggvorbisstr"', s2)
        if m:
            for md5 in (GAME / ".godot" / "imported").glob(m.group(1) + ".md5"):
                md5.unlink()
print("loop files", len(loop_files), "changed", changed)

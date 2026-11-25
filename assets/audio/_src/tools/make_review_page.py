"""Write _src/review/index.html: a local listening page for every runtime file (open it in a browser from disk)."""
import json, html
from pathlib import Path
SRC = Path(__file__).resolve().parents[1]
AUD = SRC.parent
idx = json.loads((AUD / "audio_index.json").read_text())
stats = json.loads((SRC / "reports" / "bank_stats.json").read_text())
loops = {json.loads(p.read_text())["out"].split("/")[-1]: json.loads(p.read_text()) for p in (SRC / "reports").glob("loop_*.json")}
keys_by_file = {}
for e in idx["entries"]:
    for f in e.get("files") or [e["file"]]:
        keys_by_file.setdefault(f, []).append(e["key"])
def row(f):
    keys = ", ".join(sorted(set(keys_by_file.get(f, []))))
    s = stats.get(f.rsplit(".", 1)[0], {})
    lp = loops.get(f.split("/")[-1])
    info = f"{s.get('duration_s', '')} s · LUFS {s.get('lufs')} · peak {s.get('peak_dbfs')} dBFS" if s else ""
    if lp:
        info = f"loop {lp['loop_s']:.1f} s (from {lp['loop']['start']:.1f} s of the source) · {lp['out_lufs']} LUFS · TP {lp['out_true_peak']} dBTP"
    return (f"<tr><td><code>{html.escape(f)}</code><br><small>{html.escape(keys)}</small></td>"
            f"<td><audio controls preload=none src='../../{html.escape(f)}'></audio></td><td><small>{html.escape(info)}</small></td>"
            f"<td><select><option>unrated</option><option>keep</option><option>fix</option><option>replace</option></select></td></tr>")
files = sorted({f for e in idx["entries"] for f in (e.get("files") or [e["file"]])})
sections = [("Music", [f for f in files if f.startswith("music/")]), ("Voice", [f for f in files if f.startswith("voice/")]),
            ("SFX", [f for f in files if f.startswith("sfx/") and not f.startswith("sfx/amb_")]), ("Ambience", [f for f in files if f.startswith("sfx/amb_")])]
body = "".join(f"<h2>{n} ({len(fs)})</h2><table>{''.join(row(f) for f in fs)}</table>" for n, fs in sections)
page = f"""<!doctype html><html lang=en><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>
<title>Super Mak 64 audio</title><style>
:root{{--bg:#f6f0e6;--fg:#2b1d16;--mut:#7a6656;--line:#e2d6c4}}
@media (prefers-color-scheme:dark){{:root{{--bg:#1d1512;--fg:#f3e9dc;--mut:#b9a796;--line:#3a2c25}}}}
body{{background:var(--bg);color:var(--fg);font:15px/1.4 system-ui,sans-serif;margin:0 auto;max-width:1100px;padding:16px}}
table{{width:100%;border-collapse:collapse}}td{{border-bottom:1px solid var(--line);padding:6px 8px;vertical-align:middle}}
small{{color:var(--mut)}}audio{{width:260px;height:32px}}h2{{margin-top:28px}}</style></head><body>
<h1>Super Mak 64: audio bank (night 01)</h1><p>Every runtime file in <code>game/assets/audio/</code>, with the index keys that use it.
The agent could not listen; this page is for the first human listening pass. Ratings in the drop-downs are not saved.</p>{body}</body></html>"""
(SRC / "review" / "index.html").write_text(page, encoding="utf-8")
print(len(files), "files")

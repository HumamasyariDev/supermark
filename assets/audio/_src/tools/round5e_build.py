"""Round 5e: two more takes (same prompts as the accepted round-1 files) for the most frequent single-file sounds, so
random variants stop the machine-gun effect: jump_1..3, land, land_heavy, hurt, enemy_notice, enemy_defeat_poof,
wall_kick, backflip, long_jump, page_collect -> sfx/<name>_<next free index>.ogg."""
import sys, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import round5_build as B

st = json.loads(B.REP.read_text())
DROP = {"r5e_jump_1_t2", "r5e_hurt_t3"}  # rejected on the sheet: jump_1 t2 is a noisy whoosh unlike the boing family; hurt t3 is a 0.1 s blip
for name in ["jump_1", "jump_2", "jump_3", "land", "land_heavy", "hurt", "enemy_notice", "enemy_defeat_poof", "wall_kick",
             "backflip", "long_jump", "page_collect"]:
    for t in (2, 3):
        rk = f"r5e_{name}_t{t}"
        if rk in DROP:
            continue
        n = 2
        while (B.AUD / "sfx" / f"{name}_{n}.ogg").exists() and st.get(f"sfx/{name}_{n}", {}).get("source") != f"raw/{rk}.mp3":
            n += 1
        out = B.AUD / "sfx" / f"{name}_{n}.ogg"
        r = B.oneshot(B.RAW / f"{rk}.mp3", out)
        r["source"] = f"raw/{rk}.mp3"
        st["sfx/" + out.stem] = r
        print(out.stem, r["duration_s"])
B.REP.write_text(json.dumps(st, indent=1, default=float))

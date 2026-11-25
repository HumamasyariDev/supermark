"""Look-polish water splashes (2026-10-19): raw ElevenLabs takes -> trimmed, level-matched runtime .ogg files.

python lookpolish_wade_build.py  -> game/assets/audio/sfx/wade_step_1..3.ogg, wade_land.ogg; prints stats as JSON.
Steps are matched to the grass footstep bank's active RMS, the landing to splash_2.
"""
import hashlib, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import audiolib as A  # noqa: E402

SRC = Path(__file__).resolve().parents[1]
AUD = SRC.parent
MAP = {"lp_wade_step_t1": "wade_step_1", "lp_wade_step_t2": "wade_step_2", "lp_wade_step_t3": "wade_step_3",
       "lp_wade_land_t1": "wade_land"}


def main():
    ref_step = A.active_rms_db(A.decode(AUD / "sfx" / "footstep_grass_r1.ogg"))
    ref_land = A.active_rms_db(A.decode(AUD / "sfx" / "splash_2.ogg"))
    out = {}
    for raw, name in MAP.items():
        y = A.decode(SRC / "raw" / f"{raw}.mp3")
        y, _ = A.trim(y, post_ms=50, fade_out_ms=60)
        target = (ref_land if name == "wade_land" else ref_step + 1.0)
        y = y * (10 ** ((target - A.active_rms_db(y)) / 20))
        if A.peak_db(y) > -1.0:
            y = A.limiter(y, -1.0)
        dst = AUD / "sfx" / f"{name}.ogg"
        A.encode_ogg(y, dst)
        out[name] = {"src": f"raw/{raw}.mp3", "duration_s": round(len(y) / A.SR, 3), "peak_dbfs": round(A.peak_db(y), 2),
                     "active_rms_dbfs": round(A.active_rms_db(y), 2),
                     "sha256": hashlib.sha256(dst.read_bytes()).hexdigest(),
                     "raw_sha256": hashlib.sha256((SRC / "raw" / f"{raw}.mp3").read_bytes()).hexdigest()}
    out["_ref"] = {"footstep_grass_active_rms": round(ref_step, 2), "splash_2_active_rms": round(ref_land, 2)}
    (SRC / "reports" / "lookpolish_wade_stats.json").write_text(json.dumps(out, indent=1, default=float), encoding="utf-8")
    print(json.dumps(out, indent=1, default=float))


if __name__ == "__main__":
    main()

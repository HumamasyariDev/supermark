"""Process raw generations into runtime .ogg files and write audio_index.json + _src/reports/bank_stats.json.
Music loops are rendered separately by make_loops.py (already in music/)."""
import sys, json, subprocess, hashlib
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).parent))
import audiolib as A

SRC = Path(__file__).resolve().parents[1]
AUD = SRC.parent
RAW = SRC / "raw"
TMP = SRC / "review" / "_tmp_bank.wav"
stats = {}


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def finish(y, out, target_rms, ceiling=-1.0, stereo=False, target_lufs=None):
    if target_lufs is not None:
        I, _ = A.lufs_array(y, TMP)
        y = y * (10 ** ((target_lufs - I) / 20))
    else:
        act = A.active_rms_db(y)
        y = y * (10 ** ((target_rms - act) / 20))
    if A.peak_db(y) > ceiling:
        y = A.limiter(y, ceiling)
    out.parent.mkdir(parents=True, exist_ok=True)
    A.encode_ogg(y, out)
    st = {"file": str(out.relative_to(AUD)).replace("\\", "/"), "duration_s": round(len(y) / A.SR, 3), "channels": y.shape[1],
          "peak_dbfs": round(A.peak_db(y), 2), "active_rms_dbfs": round(A.active_rms_db(y), 2)}
    if len(y) / A.SR >= 0.45:
        I, tp = A.lufs_file(out)
        st.update(lufs=I, true_peak=tp)
    st["sha256"] = sha(out)
    return st


def rubber(src, af):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-af", af, str(TMP)], check=True)
    return TMP


# ---------------------------------------------------------------- SFX
RENAME = {"land_b": "land", "footstep_wood_1b": "footstep_wood_1"}  # round-2 replacements (round-1 takes rejected, kept in raw/)
REJECTED = {"land", "footstep_wood_1"}
jobs = json.loads((SRC / "jobs" / "sfx_spec.json").read_text())["jobs"]
jobs = [j for j in jobs if j["key"][4:] not in REJECTED] + json.loads((SRC / "jobs" / "sfx_spec_round2.json").read_text())["jobs"]
jobs += [j for j in json.loads((SRC / "jobs" / "round3_spec.json").read_text())["jobs"] if j["key"].startswith("sfx_")]
jobs += [j for j in json.loads((SRC / "jobs" / "round4_spec.json").read_text())["jobs"] if j["key"].startswith("sfx_")]
for j in jobs:
    key = RENAME.get(j["key"][4:], j["key"][4:])
    raw = RAW / f"{j['key']}.mp3"
    loop = bool(j["input"].get("loop"))
    stereo = key.startswith("amb_")
    x = A.decode(raw, ch=2 if stereo else 1)
    if loop:
        xf = int(0.12 * A.SR)
        seam = float(np.max(np.abs(x[0] - x[-1])))
        y = A.equal_power_crossfade_loop(x, len(x) - xf, xf) if seam > 0.02 else x
        st = finish(y, AUD / "sfx" / f"{key}.ogg", -22.0 if stereo else -20.0)
        st.update(loop=True, raw_seam_jump=round(seam, 4), crossfaded=seam > 0.02)
    else:
        y, _ = A.trim(x, rel_db=42, pre_ms=5, post_ms=70, fade_in_ms=2, fade_out_ms=35)
        if key.startswith("footstep_"):
            n = int(0.26 * A.SR)
            if len(y) > n:
                y = y[:n].copy()
                fo = int(0.07 * A.SR)
                y[-fo:] *= (np.linspace(1, 0, fo) ** 2)[:, None]
        st = finish(y, AUD / "sfx" / f"{key}.ogg", -16.0)
    st["source"] = str(raw.relative_to(SRC)).replace("\\", "/")
    stats["sfx/" + key] = st

# ---------------------------------------------------------------- stings (music bus, non-looping)
for key, mx, fade in [("music_victory", 8.0, 1.0), ("music_truffle_get", 4.0, 0.8), ("music_menu_sting", 2.6, 0.5)]:
    x = A.decode(RAW / f"{key}.mp3", ch=2)
    y, _ = A.trim(x, rel_db=45, pre_ms=5, post_ms=200, fade_in_ms=2, fade_out_ms=200)
    n = int(mx * A.SR)
    if len(y) > n:
        y = y[:n].copy()
        fo = int(fade * A.SR)
        y[-fo:] *= (np.linspace(1, 0, fo) ** 2)[:, None]
    st = finish(y, AUD / "music" / f"{key[6:]}.ogg", -15.0, target_lufs=-14.0)
    st["source"] = f"raw/{key}.mp3"
    stats["music/" + key[6:]] = st

# ---------------------------------------------------------------- voice
def voice_out(y, name, src):
    y, _ = A.trim(y, rel_db=40, pre_ms=15, post_ms=90, fade_in_ms=3, fade_out_ms=40)
    st = finish(y, AUD / "voice" / f"{name}.ogg", -16.0)
    st["source"] = src
    stats["voice/" + name] = st

# Mr. Mak: Qwen3 voice-design batch (and clone-voice extras) split on word timestamps (one consistent designed voice)
def split_batch(raw_name, stt_name, groups, tail=0.25):
    stt = json.loads((SRC / "reports" / stt_name).read_text())
    words = [w for w in stt["words"] if w.get("type", "word") == "word"]
    x = A.decode(RAW / raw_name, ch=1)
    wi = 0
    spans = []
    for name, ws in groups:
        got = [w["text"] for w in words[wi:wi + len(ws)]]
        assert got == ws, (name, got)
        spans.append([name, words[wi]["start"], words[wi + len(ws) - 1]["end"]])
        wi += len(ws)
    for i, (name, s_, e_) in enumerate(spans):
        a = s_ - 0.12 if i == 0 else (spans[i - 1][2] + s_) / 2
        b = e_ + tail if i == len(spans) - 1 else (e_ + spans[i + 1][1]) / 2
        seg = x[int(max(0, a) * A.SR): int(min(len(x) / A.SR, b) * A.SR)]
        voice_out(seg, f"mak_{name}", f"raw/{raw_name} [{a:.2f}-{b:.2f}s]")

split_batch("voiceQW_mak_batch.mp3", "stt_voiceQW_mak_batch.json",
            [("tallyho", ["Tallyho!"]), ("splendid", ["Splendid!"]), ("jollygood", ["Jolly", "good!"]), ("righto", ["Righto!"]),
             ("jump1", ["Hup!"]), ("jump2", ["Huh,"]), ("jump3", ["hoo-ha!"]), ("oof", ["Oof!"]), ("blast", ["Blast."]),
             ("truffle", ["Ooh,", "a", "truffle."]), ("sniff", ["Smells", "like", "truffles"])])
split_batch("voiceQW_mak_extra.mp3", "stt_voiceQW_mak_extra.json",
            [("hamslam", ["Ham", "slam."]), ("wahey", ["Wahey!"]), ("cheerio", ["Cheerio."]), ("ouch", ["Ouch."]),
             ("whoa", ["Whoa,", "whoa,", "whoa."]), ("tophat", ["A", "top", "hat.", "How", "dashing."]), ("gotit", ["Got", "it"])])

for k in ["littlepig", "huffpuff", "curses", "notlast", "laugh", "inhale", "panting", "tail", "blownaway", "delicious", "getback"]:
    voice_out(A.decode(RAW / f"voiceEL_wolf_{k}.mp3", ch=1), f"wolf_{k}", f"raw/voiceEL_wolf_{k}.mp3")
for k in ["welcome", "hint", "truffle", "book2", "book3", "wolfdoor", "tea"]:
    src = RAW / f"voiceEL_butler_{k}.mp3"
    voice_out(A.decode(rubber(src, "rubberband=tempo=0.88:pitch=0.93"), ch=1), f"butler_{k}", f"raw/voiceEL_butler_{k}.mp3 + rubberband tempo 0.88 pitch 0.93")

(SRC / "reports" / "bank_stats.json").write_text(json.dumps(stats, indent=1, default=float))
print(len(stats), "files")
for k, v in stats.items():
    print(f"{k:34s} {v['duration_s']:6.2f}s pk {v['peak_dbfs']:6.1f} rms {v['active_rms_dbfs']:6.1f} lufs {v.get('lufs')}")

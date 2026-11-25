"""Loudness of every runtime file with ffmpeg ebur128: integrated (I), max momentary (M, 400 ms window), max short-term
(S, 3 s), loudness range and true peak. Short files are padded with 0.5 s of silence so the momentary window fits.
Writes _src/reports/loudness.json. Usage: python mix_analyze.py"""
import json, re, subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

AUD = Path(__file__).resolve().parents[2]
OUT = AUD / "_src" / "reports" / "loudness.json"


def analyze(f: Path):
    cmd = ["ffmpeg", "-hide_banner", "-nostats", "-i", str(f), "-af", "apad=pad_dur=0.5,ebur128=peak=true",
           "-f", "null", "-"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    err = r.stderr
    ms = [float(x) for x in re.findall(r" M:\s*(-?[\d.]+)", err)]
    ss = [float(x) for x in re.findall(r" S:\s*(-?[\d.]+)", err)]
    summ = err[err.rfind("Summary:"):]
    def g(p):
        m = re.search(p, summ)
        return float(m.group(1)) if m else None
    dur = None
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", err)
    if m:
        dur = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
    return str(f.relative_to(AUD)).replace("\\", "/"), {
        "I": g(r"I:\s*(-?[\d.]+) LUFS"), "LRA": g(r"LRA:\s*(-?[\d.]+) LU"), "tp": g(r"Peak:\s*(-?[\d.]+) dBFS"),
        "M_max": round(max(ms), 2) if ms else None, "S_max": round(max(ss), 2) if ss else None, "dur": dur}


def main():
    files = sorted(list((AUD / "sfx").glob("*.ogg")) + list((AUD / "music").glob("*.ogg")) + list((AUD / "voice").glob("*.ogg")))
    with ThreadPoolExecutor(12) as ex:
        res = dict(ex.map(analyze, files))
    OUT.write_text(json.dumps(res, indent=1))
    print(len(res), "files ->", OUT)


if __name__ == "__main__":
    main()

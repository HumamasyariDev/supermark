"""Shared audio helpers (decode, encode, loudness, trim, loop) for Super Mak 64 audio processing."""
import json, subprocess, re
import numpy as np

SR = 44100


def decode(path, sr=SR, ch=2):
    cmd = ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-acodec", "pcm_f32le", "-ac", str(ch), "-ar", str(sr), "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, ch).copy()


def encode_ogg(x, path, sr=SR, q=6):
    x = np.ascontiguousarray(np.clip(x, -1, 1).astype(np.float32))
    ch = x.shape[1]
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr), "-ac", str(ch), "-i", "-",
           "-c:a", "libvorbis", "-q:a", str(q), str(path)]
    subprocess.run(cmd, input=x.tobytes(), check=True)


def write_wav(x, path, sr=SR):
    x = np.ascontiguousarray(np.clip(x, -1, 1).astype(np.float32))
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr), "-ac", str(x.shape[1]), "-i", "-", "-c:a", "pcm_s16le", str(path)]
    subprocess.run(cmd, input=x.tobytes(), check=True)


def lufs_file(path):
    """Integrated loudness and true peak via ffmpeg loudnorm analysis."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(path), "-af", "loudnorm=print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True)
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr, re.S)
    if not m:
        return None, None
    d = json.loads(m.group(0))
    def f(v):
        try:
            return float(v)
        except Exception:
            return None
    return f(d["input_i"]), f(d["input_tp"])


def lufs_array(x, tmp, sr=SR):
    write_wav(x, tmp, sr)
    return lufs_file(tmp)


def db(v):
    return 20 * np.log10(max(float(v), 1e-9))


def peak_db(x):
    return db(np.max(np.abs(x))) if len(x) else -180.0


def rms_db(x):
    return db(np.sqrt(np.mean(np.square(x)))) if len(x) else -180.0


def frame_rms_db(x, sr=SR, hop_ms=5):
    mono = x.mean(axis=1)
    hop = int(sr * hop_ms / 1000)
    n = len(mono) // hop
    if n == 0:
        return np.array([-180.0]), hop
    fr = mono[: n * hop].reshape(n, hop)
    r = np.sqrt(np.mean(fr ** 2, axis=1) + 1e-20)
    return 20 * np.log10(r), hop


def trim(x, sr=SR, rel_db=45, floor_db=-60, pre_ms=8, post_ms=60, fade_in_ms=3, fade_out_ms=40):
    f, hop = frame_rms_db(x, sr)
    thr = max(floor_db, f.max() - rel_db)
    idx = np.where(f > thr)[0]
    if len(idx) == 0:
        return x, (0, len(x))
    s = max(0, idx[0] * hop - int(sr * pre_ms / 1000))
    e = min(len(x), (idx[-1] + 1) * hop + int(sr * post_ms / 1000))
    y = x[s:e].copy()
    fi = min(len(y), int(sr * fade_in_ms / 1000))
    fo = min(len(y), int(sr * fade_out_ms / 1000))
    if fi > 0:
        y[:fi] *= np.linspace(0, 1, fi)[:, None]
    if fo > 0:
        y[-fo:] *= np.linspace(1, 0, fo)[:, None] ** 2
    return y, (s, e)


def active_rms_db(x, sr=SR):
    f, hop = frame_rms_db(x, sr)
    thr = f.max() - 30
    act = f[f > thr]
    if len(act) == 0:
        return -180.0
    return 10 * np.log10(np.mean(10 ** (act / 10)))


def limiter(x, ceiling_db=-1.0, sr=SR, look_ms=5, release_ms=80):
    c = 10 ** (ceiling_db / 20)
    a = np.max(np.abs(x), axis=1)
    g = np.minimum(1.0, c / np.maximum(a, 1e-9))
    look = max(1, int(sr * look_ms / 1000))
    # lookahead: min over the next window
    from scipy.ndimage import minimum_filter1d, uniform_filter1d
    g = minimum_filter1d(g, size=2 * look + 1, mode="nearest")
    g = uniform_filter1d(g, size=look, mode="nearest")
    # release smoothing (one-pole on the upward direction)
    rel = np.exp(-1.0 / (sr * release_ms / 1000))
    out = g.copy()
    for i in range(1, len(out)):
        if out[i] > out[i - 1]:
            out[i] = out[i - 1] * rel + out[i] * (1 - rel)
    y = x * out[:, None]
    return np.clip(y, -c, c)


def equal_power_crossfade_loop(seg, loop_len, xf):
    """seg has loop_len + xf samples. Returns loop_len samples whose end flows seamlessly into its start."""
    head = seg[:loop_len].copy()
    tail = seg[loop_len:loop_len + xf]
    t = np.linspace(0, 1, xf)[:, None]
    head[:xf] = head[:xf] * np.sin(t * np.pi / 2) + tail * np.cos(t * np.pi / 2)
    return head

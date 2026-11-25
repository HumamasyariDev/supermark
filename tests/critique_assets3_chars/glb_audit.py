"""ASSETS3_CHARS critique r1 (asset QA): static GLB audit. Read-only. Usage: python glb_audit.py <glb> [<glb> ...] [--json out]"""
import json, struct, sys, hashlib, io
import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

def load(p):
    b = open(p, "rb").read()
    jl = struct.unpack_from("<I", b, 12)[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack_from("<I", b, off)[0]
    return j, b[off + 8: off + 8 + bl]

def acc(j, bin_, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    dt = CT[a["componentType"]]; n = NC[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    isz = np.dtype(dt).itemsize * n
    if stride and stride != isz:
        raw = np.frombuffer(bin_, np.uint8, count=stride * a["count"], offset=start).reshape(a["count"], stride)[:, :isz]
        arr = raw.copy().view(dt).reshape(a["count"], n)
    else:
        arr = np.frombuffer(bin_, dt, count=a["count"] * n, offset=start).reshape(a["count"], n)
    return arr

def tsrc(t):
    if "source" in t: return t["source"]
    for v in t.get("extensions", {}).values():
        if "source" in v: return v["source"]

def img_stats(j, bin_, ii):
    from PIL import Image
    im = j["images"][ii]
    bv = j["bufferViews"][im["bufferView"]]
    data = bin_[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
    I = Image.open(io.BytesIO(data)).convert("RGB")
    a = np.asarray(I).astype(np.float32) / 255
    return {"size": I.size, "mime": im.get("mimeType"), "R": [round(float(a[..., 0].mean()), 3), round(float(np.percentile(a[..., 0], 5)), 3)],
            "G": [round(float(a[..., 1].mean()), 3), round(float(np.percentile(a[..., 1], 5)), 3), round(float(np.percentile(a[..., 1], 95)), 3)],
            "B": [round(float(a[..., 2].mean()), 3), round(float(a[..., 2].max()), 3)], "sha": hashlib.sha1(data).hexdigest()[:10]}

def audit(p):
    j, bin_ = load(p)
    out = {"file": p.split("/characters/")[-1], "materials": [], "meshes": []}
    allpos = []
    for mi, m in enumerate(j.get("meshes", [])):
        for pi, pr in enumerate(m["primitives"]):
            pos = acc(j, bin_, pr["attributes"]["POSITION"]).astype(np.float64)
            nrm = acc(j, bin_, pr["attributes"]["NORMAL"]).astype(np.float64) if "NORMAL" in pr["attributes"] else None
            idx = acc(j, bin_, pr["indices"]).reshape(-1) if "indices" in pr else np.arange(len(pos))
            tris = idx.reshape(-1, 3)
            # split-vertex ratio: unique positions vs vertices (hard edges / UV seams)
            q = np.round(pos, 5)
            uniq = len(np.unique(q, axis=0))
            # hard-edge test: among duplicated positions, how many have differing normals (> 30 deg)
            hard = 0
            if nrm is not None:
                order = np.lexsort(q.T[::-1]); qs = q[order]; ns = nrm[order]
                same = np.all(qs[1:] == qs[:-1], axis=1)
                d = np.einsum("ij,ij->i", ns[1:], ns[:-1])
                hard = int(np.sum(same & (d < 0.866)))
            # degenerate triangles
            v0, v1, v2 = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
            area = 0.5 * np.linalg.norm(np.cross(v1 - v0, v2 - v0), axis=1)
            # winding vs normal consistency
            fn = np.cross(v1 - v0, v2 - v0)
            flip = 0
            if nrm is not None:
                vn = nrm[tris[:, 0]] + nrm[tris[:, 1]] + nrm[tris[:, 2]]
                ok = area > 1e-10
                flip = int(np.sum((np.einsum("ij,ij->i", fn, vn) < 0) & ok))
            wsum = None
            if "WEIGHTS_0" in pr["attributes"]:
                w = acc(j, bin_, pr["attributes"]["WEIGHTS_0"]).astype(np.float64)
                if w.dtype != np.float64 or w.max() > 1.5:
                    pass
                ws = w.sum(1)
                if ws.max() > 2: ws = ws / 255.0
                wsum = [round(float(ws.min()), 3), round(float(ws.max()), 3), int(np.sum(ws < 0.98))]
            mat = pr.get("material")
            out["meshes"].append({"mesh": m.get("name"), "prim": pi, "mat": j["materials"][mat].get("name") if mat is not None else None,
                "verts": len(pos), "tris": len(tris), "uniq_pos": uniq, "hard_edge_dups": hard, "degenerate": int(np.sum(area < 1e-10)),
                "winding_vs_normal_flipped": flip, "weights": wsum,
                "pos_sha": hashlib.sha1(pos.astype(np.float32).tobytes()).hexdigest()[:10]})
            allpos.append(pos)
    P = np.vstack(allpos)
    out["bounds_local"] = [P.min(0).round(3).tolist(), P.max(0).round(3).tolist()]
    for m in j.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        e = {"name": m.get("name"), "rough": pbr.get("roughnessFactor", 1.0), "metal": pbr.get("metallicFactor", 1.0),
             "base": pbr.get("baseColorFactor"), "occl": "occlusionTexture" in m, "normal": "normalTexture" in m,
             "alpha": m.get("alphaMode", "OPAQUE"), "double": m.get("doubleSided", False)}
        mr = pbr.get("metallicRoughnessTexture")
        if mr is not None:
            e["orm"] = img_stats(j, bin_, tsrc(j["textures"][mr["index"]]))
        if "occlusionTexture" in m:
            e["occl_src"] = tsrc(j["textures"][m["occlusionTexture"]["index"]])
            e["mr_src"] = tsrc(j["textures"][mr["index"]]) if mr else None
        out["materials"].append(e)
    sk = j.get("skins", [])
    out["skins"] = [{"joints": len(s["joints"]), "names": [j["nodes"][k].get("name") for k in s["joints"]]} for s in sk]
    out["nodes"] = len(j["nodes"])
    out["anims"] = [a.get("name") for a in j.get("animations", [])]
    out["node_sha"] = hashlib.sha1(json.dumps(j["nodes"], sort_keys=True).encode()).hexdigest()[:10]
    return out

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    res = [audit(a) for a in args]
    if "--json" in sys.argv:
        json.dump(res, open(sys.argv[sys.argv.index("--json") + 1], "w"), indent=1)
    for r in res:
        print("==", r["file"], "bounds", r["bounds_local"], "nodes", r["nodes"], "node_sha", r["node_sha"], "anims", r["anims"])
        for s in r["skins"]:
            print("  skin joints", s["joints"], s["names"])
        for m in r["meshes"]:
            print("  mesh", m)
        for m in r["materials"]:
            print("  mat", m)

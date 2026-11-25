"""TOPUP_WORLDS critique r1 (asset QA): structural audit of delivered GLBs.
blender -b --factory-startup --python audit_glb.py -- <out.json> <glb> [<glb> ...]
Reports per GLB: bounds (glTF axes), tris, mesh objects, loose islands, open (boundary) edges,
non-manifold edges, flat-shaded face share, vertex-colour layers, materials and their textures,
metallic/roughness factors, ORM channel stats (metallic mean overall), base-colour saturation,
and the Y profile of the top surface along Z (for decks / platforms).
"""
import bpy, bmesh, sys, json, os
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:]
out_path, glbs = args[0], args[1:]
report = {}


def img_stats(img):
    if img is None:
        return None
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, img.channels)
    sub = px[::8, ::8, :3]
    return {"size": [w, h], "mean": sub.reshape(-1, 3).mean(0).round(3).tolist(),
            "p95": np.percentile(sub.reshape(-1, 3), 95, axis=0).round(3).tolist(),
            "_arr": sub}


for glb in glbs:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    r = {"objects": [], "empties": []}
    P = []
    tris = 0; islands = 0; boundary = 0; nonman = 0; flat = 0; faces = 0; vcols = []
    for o in bpy.context.scene.objects:
        if o.type == "EMPTY":
            m = o.matrix_world.translation
            r["empties"].append([o.name, [round(m.x, 3), round(m.z, 3), round(-m.y, 3)]])
        if o.type != "MESH":
            continue
        me = o.data
        r["objects"].append(o.name)
        P += [o.matrix_world @ v.co for v in me.vertices]
        vcols += [a.name for a in me.color_attributes]
        bm = bmesh.new(); bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        tris += sum(len(f.verts) - 2 for f in bm.faces)
        faces += len(bm.faces)
        flat += sum(1 for f in bm.faces if not f.smooth)
        boundary += sum(1 for e in bm.edges if e.is_boundary)
        nonman += sum(1 for e in bm.edges if not e.is_manifold)
        # islands
        seen = set()
        for v in bm.verts:
            if v.index in seen:
                continue
            islands += 1
            stack = [v]
            while stack:
                x = stack.pop()
                if x.index in seen:
                    continue
                seen.add(x.index)
                for e in x.link_edges:
                    y = e.other_vert(x)
                    if y.index not in seen:
                        stack.append(y)
        bm.free()
    p = np.array([(v.x, v.z, -v.y) for v in P])
    r["min"] = p.min(0).round(3).tolist(); r["max"] = p.max(0).round(3).tolist()
    r["size"] = (p.max(0) - p.min(0)).round(3).tolist()
    r.update(tris=tris, islands=islands, boundary_edges=boundary, nonmanifold_edges=nonman,
             flat_face_share=round(flat / max(faces, 1), 4), vertex_colour_layers=sorted(set(vcols)))
    # top-surface profile along Z (max Y in central X band, per 1 m slice)
    band = p[np.abs(p[:, 0] - (p[:, 0].min() + p[:, 0].max()) / 2) < 0.6]
    prof = []
    if len(band):
        z0, z1 = band[:, 2].min(), band[:, 2].max()
        for z in np.arange(z0, z1, max((z1 - z0) / 16, 0.05)):
            s = band[(band[:, 2] >= z) & (band[:, 2] < z + (z1 - z0) / 16)]
            if len(s):
                prof.append([round(float(z), 2), round(float(s[:, 1].max()), 2)])
    r["top_profile_center_band"] = prof
    mats = {}
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        info = {}
        if bsdf:
            for k in ("Base Color", "Metallic", "Roughness", "Normal"):
                s = bsdf.inputs[k]
                info[k] = "linked" if s.is_linked else (list(s.default_value)[:3] if hasattr(s.default_value, "__len__") else round(s.default_value, 3))
        imgs = [n.image for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
        info["images"] = []
        bc = None; orm = None
        for im in imgs:
            st = img_stats(im)
            nm = im.name.lower()
            info["images"].append({"name": im.name, "size": st["size"], "mean": st["mean"], "p95": st["p95"]})
            if "color" in nm or "base" in nm:
                bc = st["_arr"]
            if "orm" in nm or "metal" in nm or "rough" in nm:
                orm = st["_arr"]
        if bc is not None:
            mx = bc.max(2); mn = bc.min(2)
            sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
            info["basecolor_mean_saturation"] = round(float(sat.mean()), 3)
            info["basecolor_grey_share(sat<0.08)"] = round(float((sat < 0.08).mean()), 3)
        if orm is not None:
            met = orm[:, :, 2]; rough = orm[:, :, 1]
            info["orm_metallic_mean"] = round(float(met.mean()), 3)
            info["orm_metallic_share>0.5"] = round(float((met > 0.5).mean()), 3)
            info["orm_rough_mean"] = round(float(rough.mean()), 3)
            info["orm_rough_min"] = round(float(rough.min()), 3)
        mats[m.name] = info
    r["materials"] = mats
    report[os.path.basename(glb)] = r
    print("AUDIT", os.path.basename(glb), json.dumps({k: v for k, v in r.items() if k != "top_profile_center_band"}))

with open(out_path, "w") as f:
    json.dump(report, f, indent=1)

"""TOPUP_WORLDS critique r1: island size stats and walk-surface profile.
blender -b --factory-startup --python islands_profile.py -- <glb> [xband]
Prints islands bucketed by bbox diagonal, tiny islands' positions (possible floating crumbs),
and the max-Y profile along Z for |x| < xband (default 0.6), 0.5 m steps.
"""
import bpy, bmesh, sys, json
import numpy as np

a = sys.argv[sys.argv.index("--") + 1:]
glb = a[0]; xband = float(a[1]) if len(a) > 1 else 0.6
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
isl = []
allp = []
for o in bpy.context.scene.objects:
    if o.type != "MESH":
        continue
    bm = bmesh.new(); bm.from_mesh(o.data); bm.transform(o.matrix_world)
    bm.verts.ensure_lookup_table()
    seen = set()
    for v in bm.verts:
        if v.index in seen:
            continue
        comp = []; st = [v]
        while st:
            x = st.pop()
            if x.index in seen:
                continue
            seen.add(x.index); comp.append(x.co.copy())
            st += [e.other_vert(x) for e in x.link_edges if e.other_vert(x).index not in seen]
        c = np.array([(q.x, q.z, -q.y) for q in comp])
        isl.append((c.min(0), c.max(0), len(comp)))
    allp += [(q.co.x, q.co.z, -q.co.y) for q in bm.verts]
    bm.free()
p = np.array(allp)
diag = np.array([np.linalg.norm(mx - mn) for mn, mx, _ in isl])
buckets = {"<2cm": int((diag < 0.02).sum()), "2-5cm": int(((diag >= 0.02) & (diag < 0.05)).sum()),
           "5-20cm": int(((diag >= 0.05) & (diag < 0.2)).sum()), ">=20cm": int((diag >= 0.2).sum())}
# tiny islands that float: min y > 0.05 and no other island bbox overlaps
tiny = [(mn, mx) for (mn, mx, n), d in zip(isl, diag) if d < 0.05]
floating = 0
for mn, mx in tiny:
    hit = False
    for mn2, mx2, _ in isl:
        if np.linalg.norm(mx2 - mn2) < 0.05:
            continue
        if np.all(mx >= mn2 - 0.01) and np.all(mn <= mx2 + 0.01):
            hit = True; break
    if not hit:
        floating += 1
band = p[np.abs(p[:, 0]) < xband]
prof = []
for z in np.arange(p[:, 2].min(), p[:, 2].max(), 0.5):
    s = band[(band[:, 2] >= z) & (band[:, 2] < z + 0.5)]
    if len(s):
        prof.append([round(float(z), 2), round(float(s[:, 1].max()), 2), round(float(s[:, 1].min()), 2)])
print("ISLANDS " + json.dumps({"glb": glb.split("/")[-1], "count": len(isl), "buckets": buckets,
                               "tiny_not_touching_larger": floating, "profile_z_maxy_miny": prof}))

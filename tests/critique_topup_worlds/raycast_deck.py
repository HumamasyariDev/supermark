"""TOPUP_WORLDS critique r1: ray-cast the walk surface of a GLB from above.
blender -b --factory-startup --python raycast_deck.py -- <glb> <axis z|x> <step> <x_or_z_offsets comma>
Prints, for each lane offset, the first-hit height along the span (glTF coords; None = hole).
"""
import bpy, sys, json
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

a = sys.argv[sys.argv.index("--") + 1:]
glb, axis, step = a[0], a[1], float(a[2])
lanes = [float(v) for v in a[3].split(",")]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
dg = bpy.context.evaluated_depsgraph_get()
trees = [BVHTree.FromObject(o, dg) for o in bpy.context.scene.objects if o.type == "MESH"]
mats = [o.matrix_world for o in bpy.context.scene.objects if o.type == "MESH"]
pts = np.array([tuple(m @ v.co) for o, m in zip([o for o in bpy.context.scene.objects if o.type == "MESH"], mats) for v in o.data.vertices])
# glTF: x = bx, y = bz, z = -by
gz0, gz1 = (-pts[:, 1]).min(), (-pts[:, 1]).max()
gx0, gx1 = pts[:, 0].min(), pts[:, 0].max()
out = {}
for lane in lanes:
    row = []
    rng = np.arange(gz0, gz1 + 1e-6, step) if axis == "z" else np.arange(gx0, gx1 + 1e-6, step)
    for t in rng:
        gx, gz = (lane, t) if axis == "z" else (t, lane)
        origin = Vector((gx, -gz, 50.0))
        best = None
        for tr, m in zip(trees, mats):
            mi = m.inverted()
            o2 = mi @ origin; d2 = (mi.to_3x3() @ Vector((0, 0, -1))).normalized()
            hit = tr.ray_cast(o2, d2)
            if hit[0] is not None:
                hy = (m @ hit[0]).z
                best = hy if best is None else max(best, hy)
        row.append([round(float(t), 2), None if best is None else round(best, 2)])
    out[str(lane)] = row
print("RAYCAST " + json.dumps(out))

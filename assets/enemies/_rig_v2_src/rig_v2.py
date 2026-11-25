"""Rig the root-only enemy GLBs (bumble_bruiser, peapod_popper) into skinned _v2 GLBs.

Blender 5.1 background:
    blender -b --factory-startup --python rig_v2.py -- <bee|pea> <src.glb> <out.glb>

Weights are analytic (vertex position plus a base-colour texture sample), so UV-seam duplicates
always get identical weights and nothing tears. Blender axes: Z up, character front = -Y
(glTF +Z), character left = +X. Enemies workstream, night 01.
"""
import bpy, sys
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
kind, src, out = argv[0], argv[1], argv[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
# Bake object transforms into the vertices so bone heads are the real pivots.
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def ss(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def vertex_colors(o):
    """Base-colour texture sample per vertex index (RGB), or {}."""
    mat = o.data.materials[0] if o.data.materials else None
    img = None
    if mat and mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image and 'color' in n.image.name.lower():
                img = n.image
        if img is None:
            for n in mat.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image:
                    img = n.image
                    break
    if img is None:
        return {}
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    uv = o.data.uv_layers.active.data
    cols = {}
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            vi = o.data.loops[li].vertex_index
            if vi in cols:
                continue
            u, v = uv[li].uv
            cols[vi] = px[int((v % 1.0) * (h - 1)), int((u % 1.0) * (w - 1)), :3]
    return cols


arm_data = bpy.data.armatures.new('rig')
arm = bpy.data.objects.new('rig', arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
for o in bpy.context.selected_objects:
    o.select_set(False)
arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
eb = arm_data.edit_bones


def bone(name, head, tail, parent=None):
    b = eb.new(name)
    b.head = Vector(head)
    b.tail = Vector(tail)
    if parent:
        b.parent = eb[parent]
    return b


weights = {}

if kind == 'bee':
    body = bpy.data.objects['body']
    cols = vertex_colors(body)
    vs = [v.co.copy() for v in body.data.vertices]
    red = [i for i, c in cols.items() if c[0] > 0.45 and c[1] < 0.22 and c[2] < 0.22]
    gl = [vs[i] for i in red if vs[i].x > 0.04]
    gr = [vs[i] for i in red if vs[i].x <= 0.04]
    gcl = sum(gl, Vector()) / max(1, len(gl))
    gcr = sum(gr, Vector()) / max(1, len(gr))
    # Drop stray red texels far from either glove (cheek and mouth specks).
    red = [i for i in red if min((vs[i] - gcl).length, (vs[i] - gcr).length) < 0.11]
    gl = [vs[i] for i in red if vs[i].x > 0.04]
    gr = [vs[i] for i in red if vs[i].x <= 0.04]
    gcl = sum(gl, Vector()) / max(1, len(gl))
    gcr = sum(gr, Vector()) / max(1, len(gr))
    print('gloves', len(gl), len(gr), tuple(round(a, 3) for a in gcl), tuple(round(a, 3) for a in gcr))
    sh_l = Vector((max(0.15, gcl.x + 0.03), 0.0, 0.39))
    sh_r = Vector((min(-0.15, gcr.x - 0.03), 0.0, 0.39))
    bone('root', (0, 0, 0), (0, 0, 0.1))
    bone('spine', (0, 0, 0.12), (0, 0, 0.42), 'root')
    bone('head', (0, -0.02, 0.43), (0, -0.02, 0.76), 'spine')
    bone('arm_l', tuple(sh_l), tuple(gcl), 'spine')
    bone('arm_r', tuple(sh_r), tuple(gcr), 'spine')
    bone('leg_l', (0.09, 0.0, 0.13), (0.09, 0.0, 0.0), 'spine')
    bone('leg_r', (-0.09, 0.0, 0.13), (-0.09, 0.0, 0.0), 'spine')
    bone('stinger', (0, 0.07, 0.14), (0, 0.16, 0.0), 'spine')
    wl = bpy.data.objects['wing_l']
    wr = bpy.data.objects['wing_r']

    def wing_root(o):
        vv = [v.co for v in o.data.vertices]
        inner = min(vv, key=lambda c: abs(c.x))
        return Vector((inner.x, sum(c.y for c in vv) / len(vv), sum(c.z for c in vv) / len(vv)))

    rl = wing_root(wl)
    rr = wing_root(wr)
    bone('wing_l', tuple(rl), tuple(rl + Vector((0.25, 0.03, 0.06))), 'spine')
    bone('wing_r', tuple(rr), tuple(rr + Vector((-0.25, 0.03, 0.06))), 'spine')
    W = []
    redset = set(red)
    for i, p in enumerate(vs):
        w = {}
        if i in redset:
            w['arm_l' if p.x > 0.04 else 'arm_r'] = 1.0
            W.append(w)
            continue
        for side, sh, gc in (('arm_l', sh_l, gcl), ('arm_r', sh_r, gcr)):
            aw = 1.0 - ss(0.05, 0.085, seg_dist(p, sh, gc))
            if aw > 0.0 and abs(p.x) > 0.11 and 0.2 < p.z < 0.44:
                w[side] = aw
        sting = ss(0.05, 0.085, p.y) * (1.0 - ss(0.13, 0.17, p.z)) * (1.0 - ss(0.05, 0.08, abs(p.x)))
        leg = (1.0 - ss(0.09, 0.14, p.z)) * (1.0 - sting)
        head = ss(0.405, 0.47, p.z)
        if sting > 0:
            w['stinger'] = sting
        if leg > 0:
            w['leg_l' if p.x > 0 else 'leg_r'] = leg
        rest = max(0.0, 1.0 - sum(w.values()))
        if head > 0 and rest > 0:
            w['head'] = head * rest
        rest = max(0.0, 1.0 - sum(w.values()))
        if rest > 0:
            w['spine'] = rest
        W.append(w)
    weights['body'] = W
    weights['wing_l'] = [{'wing_l': 1.0} for _ in wl.data.vertices]
    weights['wing_r'] = [{'wing_r': 1.0} for _ in wr.data.vertices]

elif kind == 'pea':
    pod = bpy.data.objects['pod']
    bone('root', (0, 0, 0), (0, 0, 0.1))
    # Clamshell hinges along the back seam: rotating each about its own (vertical) axis opens the pod.
    bone('pod_l', (0.0, 0.12, 0.15), (0.0, 0.12, 0.78), 'root')
    bone('pod_r', (0.0, 0.121, 0.15), (0.0, 0.121, 0.78), 'root')
    bone('stem', (0, 0.0, 0.79), (0, 0.0, 0.92), 'root')
    bone('leg_l', (0.07, 0.0, 0.14), (0.07, 0.0, 0.0), 'root')
    bone('leg_r', (-0.07, 0.0, 0.14), (-0.07, 0.0, 0.0), 'root')
    bone('arm_l', (0.16, 0.0, 0.46), (0.21, -0.05, 0.28), 'pod_l')
    bone('arm_r', (-0.16, 0.0, 0.46), (-0.21, -0.05, 0.28), 'pod_r')
    for pn, bn in (('pea_face', 'head'), ('pea_mid', 'pea_mid'), ('pea_low', 'pea_low'), ('pea_tiny', 'pea_tiny')):
        o = bpy.data.objects[pn]
        vv = [v.co for v in o.data.vertices]
        c = sum(vv, Vector()) / len(vv)
        bone(bn, tuple(c), tuple(c + Vector((0, 0, 0.08))), 'root')
        weights[pn] = [{bn: 1.0} for _ in vv]
    W = []
    for v in pod.data.vertices:
        p = v.co
        w = {}
        leg = 1.0 - ss(0.1, 0.16, p.z)
        stem = ss(0.78, 0.84, p.z)
        armw = ss(0.145, 0.175, abs(p.x)) * ss(0.2, 0.25, p.z) * (1.0 - ss(0.47, 0.52, p.z)) * (1.0 - ss(0.08, 0.12, p.y))
        if leg > 0:
            w['leg_l' if p.x > 0 else 'leg_r'] = leg
        if stem > 0:
            w['stem'] = stem
        rest = max(0.0, 1.0 - sum(w.values()))
        if armw > 0 and rest > 0:
            w['arm_l' if p.x > 0 else 'arm_r'] = armw * rest
        rest = max(0.0, 1.0 - sum(w.values()))
        if rest > 0:
            s = ss(-0.04, 0.04, p.x)
            if s > 0:
                w['pod_l'] = rest * s
            if s < 1:
                w['pod_r'] = rest * (1 - s)
        W.append(w)
    weights['pod'] = W

bpy.ops.object.mode_set(mode='OBJECT')
for o in meshes:
    W = weights.get(o.name)
    if W is None:
        continue
    o.vertex_groups.clear()
    groups = {}
    for i, w in enumerate(W):
        for bn, val in w.items():
            if val <= 1e-4:
                continue
            if bn not in groups:
                groups[bn] = o.vertex_groups.new(name=bn)
            groups[bn].add([i], val, 'REPLACE')
    o.parent = arm
    m = o.modifiers.new('Armature', 'ARMATURE')
    m.object = arm

if len(argv) > 3:
    # Test pose render: open the pod / flap the wings, raise arms, turn the head.
    import math
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    pb = arm.pose.bones
    for b in pb:
        b.rotation_mode = 'XYZ'
    if kind == 'pea':
        pb['pod_l'].rotation_euler = (0, math.radians(35), 0)
        pb['pod_r'].rotation_euler = (0, math.radians(-35), 0)
        pb['head'].location = (0, 0, 0.0)
        pb['leg_l'].rotation_euler = (math.radians(30), 0, 0)
    else:
        pb['wing_l'].rotation_euler = (0, 0, math.radians(35))
        pb['wing_r'].rotation_euler = (0, 0, math.radians(-35))
        pb['arm_l'].rotation_euler = (math.radians(50), 0, 0)
        pb['head'].rotation_euler = (0, math.radians(30), 0)
        pb['stinger'].rotation_euler = (math.radians(30), 0, 0)
        pb['leg_r'].rotation_euler = (math.radians(40), 0, 0)
    bpy.ops.object.mode_set(mode='OBJECT')
    import os
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'TEXTURE'
    sc.render.resolution_x = 700
    sc.render.resolution_y = 700
    cd = bpy.data.cameras.new('c')
    cd.type = 'ORTHO'
    cd.ortho_scale = 1.1
    cam = bpy.data.objects.new('c', cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for k, (loc, rot) in {'front': ((0, -3, 0.42), (math.radians(90), 0, 0)),
                          'side': ((3, 0, 0.42), (math.radians(90), 0, math.radians(90))),
                          'top': ((0.0, -1.5, 2.2), (math.radians(35), 0, 0))}.items():
        cam.location = loc
        cam.rotation_euler = rot
        sc.render.filepath = argv[3] + '_' + k + '.png'
        bpy.ops.render.render(write_still=True)
    raise SystemExit(0)

for o in bpy.data.objects:
    o.select_set(o.type in ('MESH', 'ARMATURE'))
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_skins=True,
                          export_animations=False, export_yup=True, export_image_format='WEBP')
print('EXPORTED', out)

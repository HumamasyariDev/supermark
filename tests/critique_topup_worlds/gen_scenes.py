"""TOPUP_WORLDS critique r1 (asset QA): write targeted look-dev scenes for native Godot captures.
python gen_scenes.py  -> game/tests/critique_topup_worlds/Crit*.tscn
Each scene uses that world's real Environment and sun (values copied from the track's own preview generator).
Placements reproduce what the builders' current code does (place_fit scale, collider tops) so float/sink can be judged.
"""
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent
P = "res://assets/props/"
MAK = "res://assets/characters/mak/mak.glb"


def norm(v):
    l = math.sqrt(sum(x * x for x in v)); return [x / l for x in v]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def look(pos, target):
    z = norm([p - t for p, t in zip(pos, target)])
    x = norm(cross([0, 1, 0], z)); y = cross(z, x)
    return x, y, z


def tf(basis=None, o=(0, 0, 0), s=1.0, yaw=0.0):
    if basis is None:
        c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        basis = ([c * s, 0, -sn * s], [0, s, 0], [sn * s, 0, c * s])
    x, y, z = basis
    v = [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]] + list(o)
    return "Transform3D(" + ", ".join(f"{a:.5g}" for a in v) + ")"


W1_SUN = "Transform3D(0.70710677, 0.4353384, -0.55720776, 0, 0.7880108, 0.6156615, 0.70710677, -0.4353384, 0.55720776, 0, 0, 0)"
SCENES = {
    "CritW1": ("W1", None, "Color(1, 0.8862745, 0.6901961, 1)", 1.35, "Color(0.43, 0.75, 0.27, 1)", [
        ("BirchA", "w1/birch_tree_v2/birch_tree_v2.glb", (-4, 0, -6), 1.0, 0),
        ("BirchB", "w1/birch_tree_v2/birch_tree_v2.glb", (1.5, 0, -10), 1.15, 120),
        ("BirchC", "w1/birch_tree_v2/birch_tree_v2.glb", (6, 0, -5), 0.9, 240),
        ("BirchV1", "w1/birch_tree/birch_tree.glb", (10.5, 0, -8), 1.0, 0),
        ("BellowsV2", "w1/bellows_machine_v2/bellows_machine_v2.glb", (-6, 0, 6), 1.0, 0),
        ("Mak", MAK, (0, 0, 4), 1, 0),
    ], {"GameCam": ((0, 4.5, 14), (0, 3.5, -4), 60),
        "BellowsMinusX": ((-12.5, 2.2, 6.5), (-6, 1.4, 6), 45),
        "BellowsBack": ((-6.5, 2.6, -1.5), (-6, 1.5, 6), 50)}),
    "CritBoss": ("BOSS", (-0.38, -1.2), "Color(1, 0.74, 0.52, 1)", 1.25, "Color(0.557, 0.51, 0.588, 1)", [
        ("Teapot", "boss/teapot/teapot.glb", (0, 0, 0), 1.0, 0),
        ("TeapotB", "boss/teapot/teapot.glb", (1.0, 0, -0.4), 1.0, 150),
        ("Chimney", "boss/boss_chimney/boss_chimney.glb", (-4, 0, -4), 1.0, 180),
        ("Trolley", "boss/tea_trolley/tea_trolley.glb", (3.5, 0, -1.5), 1.0, 0),
        ("TrolleyPot", "boss/teapot/teapot.glb", (3.82, 0.72, -1.5), 0.7, 0),
        ("Mak", MAK, (-1.4, 0, 0.6), 1, 0),
    ], {"TeapotClose": ((0.4, 1.3, 2.6), (0.4, 0.3, 0), 40),
        "ChimneyBack": ((-4, 3.0, -13), (-4, 2.6, -4), 45),
        "TrolleyPotCam": ((3.6, 1.6, 1.4), (3.6, 0.85, -1.5), 40)}),
    # W2: reproduce w2_build.gd place_fit: chair fit (4.2, 11, 4.2) yaw -90 -> k 1.05; sugar fit (2.3, 1.45, 2.3) -> k 0.777.
    # Mak stands at the builders' collider tops: chair seat 4.4, sugar cylinder 1.1 (r 1.1).
    "CritW2": ("W2", (-0.558505, -1.178097), "Color(1, 0.886, 0.69, 1)", 1.25, "Color(0.725, 0.478, 0.275, 1)", [
        ("GiantChair", "w2/giant_chair/giant_chair.glb", (-4, 0, -3), 1.05, -90),
        ("MakOnSeat", MAK, (-4.3, 4.4, -3), 1, 30),
        ("SugarBowl", "w2/sugar_bowl/sugar_bowl.glb", (3, 0, 0), 0.777, 0),
        ("MakOnSugarEdge", MAK, (3.0, 1.1, 0.95), 1, 0),
    ], {"SeatCam": ((-1.5, 6.2, 3.5), (-4.2, 4.6, -3), 45),
        "SugarCam": ((5.2, 2.6, 4.0), (3, 0.8, 0.3), 40)}),
    # W3: builder arc ends top 1.3, apex top 2.4 over 16 m. Mak at an end (z -7) on 1.3 and at the apex on 2.4.
    "CritW3": ("W3", None, "Color(1, 0.8901961, 0.6901961, 1)", 1.35, "Color(0.56, 0.89, 0.78, 1)", [
        ("PretzelBridge", "w3/pretzel_bridge/pretzel_bridge.glb", (0, 0, 0), 1.0, 0),
        ("MakEnd", MAK, (0, 1.3, -7.0), 1, 0),
        ("MakApex", MAK, (0, 2.4, 0), 1, 0),
        ("Tower", "w3/gingerbread_tower/gingerbread_tower.glb", (-8, 0, -4), 1, 90),
    ], {"BridgeSide": ((9, 2.0, -1), (0, 1.8, -1), 60),
        "RailClose": ((3.2, 2.6, -3.0), (1.6, 2.2, -4.5), 45),
        "TowerTop": ((-6.0, 7.6, -1.2), (-8, 7.0, -4), 40)}),
}

for name, (env, sunrot, suncol, sune, groundcol, props, cams) in SCENES.items():
    files = sorted({g for _, g, *_r in props})
    idx = {g: i + 2 for i, g in enumerate(files)}
    lines = [f'[gd_scene load_steps={len(files) + 4} format=3]', "",
             f'[ext_resource type="Environment" path="res://assets/shaders/environments/env_{env}.tres" id="1"]']
    for g in files:
        path = g if g.startswith("res://") else P + g
        lines.append(f'[ext_resource type="PackedScene" path="{path}" id="{idx[g]}"]')
    lines += ["", '[sub_resource type="StandardMaterial3D" id="groundmat"]', f"albedo_color = {groundcol}", "roughness = 0.9", "",
              '[sub_resource type="PlaneMesh" id="plane"]', 'material = SubResource("groundmat")', "size = Vector2(160, 160)", "",
              f'[node name="{name}" type="Node3D"]', "",
              '[node name="WorldEnvironment" type="WorldEnvironment" parent="."]', 'environment = ExtResource("1")', "",
              '[node name="Sun" type="DirectionalLight3D" parent="."]']
    lines.append(f"rotation = Vector3({sunrot[0]}, {sunrot[1]}, 0)" if sunrot else f"transform = {W1_SUN}")
    lines += [f"light_color = {suncol}", f"light_energy = {sune}", "shadow_enabled = true", "directional_shadow_max_distance = 140.0", "",
              '[node name="Ground" type="MeshInstance3D" parent="."]', 'mesh = SubResource("plane")', ""]
    first = True
    for cn, (pos, tgt, fov) in cams.items():
        lines += [f'[node name="{cn}" type="Camera3D" parent="."]', f"transform = {tf(look(pos, tgt), pos)}", f"fov = {fov}"]
        if first:
            lines.append("current = true"); first = False
        lines.append("")
    for node, g, pos, s, yaw in props:
        lines += [f'[node name="{node}" parent="." instance=ExtResource("{idx[g]}")]', f"transform = {tf(None, pos, s, yaw)}", ""]
    (OUT / f"{name}.tscn").write_text("\n".join(lines), encoding="utf-8")
    print(OUT / f"{name}.tscn")

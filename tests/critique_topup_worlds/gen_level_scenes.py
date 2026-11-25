"""TOPUP_WORLDS critique r1 (asset QA): wrappers that instance the REAL level scenes (W2, W3, boss rooftop)
with extra fixed cameras and a static Mak at the builders' collider tops, so the delivered props are judged in place.
python gen_level_scenes.py -> game/tests/critique_topup_worlds/CritLevel*.tscn
"""
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent
MAK = "res://assets/characters/mak/mak.glb"


def norm(v):
    l = math.sqrt(sum(x * x for x in v)); return [x / l for x in v]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def cam_tf(pos, tgt):
    z = norm([p - t for p, t in zip(pos, tgt)])
    x = norm(cross([0, 1, 0], z)); y = cross(z, x)
    v = [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]] + list(pos)
    return "Transform3D(" + ", ".join(f"{a:.5g}" for a in v) + ")"


def pos_tf(p, yaw=0.0):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    v = [c, 0, s, 0, 1, 0, -s, 0, c] + list(p)
    return "Transform3D(" + ", ".join(f"{a:.5g}" for a in v) + ")"


SCENES = {
    # W2: SUGAR at (-9.2, 56.8, -36.4) on the table top 55.6; chair seat collider top 54.4 at (3.4, -34).
    "CritLevelW2": ("res://scenes/worlds/w2/W2.tscn", [((2.8, 54.4, -34.0), 90)], {
        "SugarLevelCam": ((-9.6, 61.0, -41.0), (-9.2, 56.6, -36.4), 50),
        "ChairLevelCam": ((-2.5, 57.2, -28.0), (3.6, 55.0, -34.0), 55)}),
    # W3: pretzel bridge x -6, apex collider top 2.4 at z 4.5 (_arch_y); a Mak there and one at z 8.5 (top 2.125).
    "CritLevelW3": ("res://scenes/worlds/w3/W3.tscn", [((-6.0, 2.4, 4.5), 90), ((-6.0, 2.125, 8.5), 90)], {
        "BridgeLevelCam": ((-6.3, 3.0, 15.5), (-6.0, 2.3, 4.5), 45),
        "TowerLevelCam": ((30.0, 6.5, 30.5), (37.6, 4.5, 37.6), 55)}),
    # Boss: C1 at (6.72, 0, -6.72) rotated 45; look at its crown (Tall Tom's procedural extra pot) and the trolley.
    "CritLevelBoss": ("res://scenes/boss/WolfRooftop.tscn", [], {
        "ChimneyLevelCam": ((11.5, 5.2, -1.5), (6.72, 3.6, -6.72), 50),
        "TrolleyLevelCam": ((5.2, 2.6, -11.0), (2.6, 1.6, -15.2), 50)}),
}

for name, (lvl, maks, cams) in SCENES.items():
    lines = [f"[gd_scene load_steps={3 if maks else 2} format=3]", "",
             f'[ext_resource type="PackedScene" path="{lvl}" id="1"]']
    if maks:
        lines.append(f'[ext_resource type="PackedScene" path="{MAK}" id="2"]')
    lines += ["", f'[node name="{name}" type="Node3D"]', "", '[node name="Level" parent="." instance=ExtResource("1")]', ""]
    for cn, (p, t, fov) in cams.items():
        lines += [f'[node name="{cn}" type="Camera3D" parent="."]', f"transform = {cam_tf(p, t)}", f"fov = {fov}", ""]
    for i, (p, yaw) in enumerate(maks):
        lines += [f'[node name="MakAtColliderTop{i}" parent="." instance=ExtResource("2")]', f"transform = {pos_tf(p, yaw)}", ""]
    (OUT / f"{name}.tscn").write_text("\n".join(lines), encoding="utf-8")
    print(OUT / f"{name}.tscn")

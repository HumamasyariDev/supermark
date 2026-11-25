"""W2 builder tool: writes res://scenes/worlds/w2/W2.tscn (contract nodes only) and copies the level JSON.

The heavy content (terrain, beanstalk, clouds, castle, gameplay) is built deterministically at load time
by res://scripts/worlds/w2_world.gd from res://assets/environment/w2/w2_level.json.
Run from the entity folder: python game/assets/environment/w2/tools/w2_gen_scene.py
"""
import json, math, os, shutil

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".."))
SRC = os.path.join(ENT, "data", "levels", "W2.json")
DST_JSON = os.path.join(ENT, "game", "assets", "environment", "w2", "w2_level.json")
DST_TSCN = os.path.join(ENT, "game", "scenes", "worlds", "w2", "W2.tscn")

# Builder overrides of the plan's proposal spawns (the plan's Default sat 1 m from the south rim, so the
# gameplay camera started below the island edge looking at its underside).
SPAWN_OVERRIDES = {
    "Default": ([0.0, 0.0, 29.0], 0.0),
    "W2-1": ([0.0, 0.0, 29.0], 0.0),
    "W2-5": ([0.0, 0.0, 29.0], 0.0),
    # Round-1 W2-8 start sat 2 m from the stalk, so the camera was pinned against the trunk.
    "W2-8": ([-6.5, 50.0, -21.8], 150.0),
}

# Extra cameras added after the first captures (never move a StoryCam; add _v2 instead).
EXTRA_CAMS = [
    # Fix round 1: W2-3 trailer still, 1.5 m south of G_v3 and looking higher so the Giant's head clears the loaf.
    {"name": "StoryCam_G_v4", "pos": [-1.6, 56.2, -29.1], "look_at": [-10.9, 60.2, -34.0], "fov_v": 62.0},
    # Fix round 2: the loaf blocked G_v3/G_v4; higher and further north-east so the loaf sits low-left and the
    # Giant's face, nightcap and candle flame read above it.
    {"name": "StoryCam_G_v5", "pos": [-2.5, 57.2, -28.5], "look_at": [-12.0, 60.5, -35.0], "fov_v": 58.0},
]


def cam_rot(pos, look):
    dx, dy, dz = look[0] - pos[0], look[1] - pos[1], look[2] - pos[2]
    yaw = math.atan2(-dx, -dz)
    pitch = math.atan2(dy, math.hypot(dx, dz))
    return pitch, yaw


def main():
    d = json.load(open(SRC, encoding="utf-8"))
    shutil.copyfile(SRC, DST_JSON)
    L = []
    L.append('[gd_scene load_steps=3 format=3]\n')
    L.append('[ext_resource type="Script" path="res://scripts/worlds/w2_world.gd" id="1_w2"]')
    L.append('[ext_resource type="Environment" path="res://assets/shaders/environments/env_W2.tres" id="2_env"]\n')
    L.append('[node name="W2" type="Node3D"]')
    L.append('script = ExtResource("1_w2")')
    L.append('world_id = "W2"')
    L.append('display_name = "Beanstalk Skyway"')
    L.append('music_key = "w2_beanstalk"')
    L.append('kill_y = %.1f\n' % d["kill_y"])
    L.append('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]')
    L.append('environment = ExtResource("2_env")\n')
    sx, sy, sz = d["lighting"]["sun"]["rotation_degrees"]
    L.append('[node name="Sun" type="DirectionalLight3D" parent="."]')
    L.append('rotation = Vector3(%.6f, %.6f, %.6f)' % (math.radians(sx), math.radians(sy), math.radians(sz)))
    L.append('light_color = Color(1, 0.886, 0.69, 1)')
    L.append('light_energy = 1.25')
    L.append('shadow_enabled = true')
    L.append('directional_shadow_max_distance = 140.0\n')
    L.append('[node name="Spawns" type="Node3D" parent="."]\n')
    for s in d["spawns"]:
        if s["name"] in SPAWN_OVERRIDES:
            s["pos"], s["rot_y"] = SPAWN_OVERRIDES[s["name"]]
        p = s["pos"]
        L.append('[node name="%s" type="Marker3D" parent="Spawns"]' % s["name"])
        L.append('position = Vector3(%.3f, %.3f, %.3f)' % (p[0], p[1] + 0.05, p[2]))
        L.append('rotation = Vector3(0, %.6f, 0)\n' % math.radians(s["rot_y"]))
    L.append('[node name="StoryCams" type="Node3D" parent="."]\n')
    for c in [c for c in d["story_cams"] if "pos" in c and "look_at" in c] + EXTRA_CAMS:
        pitch, yaw = cam_rot(c["pos"], c["look_at"])
        L.append('[node name="%s" type="Camera3D" parent="StoryCams"]' % c["name"])
        L.append('position = Vector3(%.3f, %.3f, %.3f)' % tuple(c["pos"]))
        L.append('rotation = Vector3(%.6f, %.6f, 0)' % (pitch, yaw))
        L.append('fov = %.1f' % c["fov_v"])
        L.append('far = 1500.0\n')
    open(DST_TSCN, "w", encoding="utf-8", newline="\n").write("\n".join(L))
    print("wrote", DST_TSCN)


def rot_y_basis(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    # Godot serialises Transform3D basis as rows: (xx, xy, xz, yx, yy, yz, zx, zy, zz).
    return "%.6f, 0, %.6f, 0, 1, 0, %.6f, 0, %.6f" % (c, s, -s, c)


if __name__ == "__main__":
    main()

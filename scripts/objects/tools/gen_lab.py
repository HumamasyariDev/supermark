"""Generates res://scenes/objects/ObjectsLab.tscn (every object, lighting, four StoryCams).
Usage: python game/scripts/objects/tools/gen_lab.py   (from anywhere)"""
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'scenes' / 'objects' / 'ObjectsLab.tscn'

SCENES = ['Truffle', 'Acorn', 'AcornGroup', 'AcornHundred', 'LostPage', 'LostPageSet', 'Checkpoint', 'StorybookPortal',
          'WolfDoor', 'MovingPlatform', 'RotatingPlatform', 'FallingPlatform', 'BouncePad', 'WindZone', 'BellowsMachine',
          'BellowsSet', 'VanishingCloud', 'HazardVolume', 'KillZone', 'Climbable', 'SignPost', 'NPCTalker', 'TrialRing',
          'TimeTrial', 'BreakableCrate', 'SlamSwitch', 'Cage', 'SniffTarget', 'BuriedTreasure']


def xf(pos, yaw=0.0, pitch=0.0):
    """Transform3D text for a position with yaw (Y) then pitch (X) in degrees."""
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    # Basis = RotY(yaw) * RotX(pitch); columns x, y, z
    bx = (cy, 0.0, -sy)
    by = (sy * sp, cp, cy * sp)
    bz = (sy * cp, -sp, cy * cp)
    # Transform3D(x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z, o.x, o.y, o.z)
    vals = [bx[0], by[0], bz[0], bx[1], by[1], bz[1], bx[2], by[2], bz[2], *pos]
    return 'Transform3D(' + ', '.join(f'{v:.5g}' for v in vals) + ')'


def look_at(eye, target):
    dx, dy, dz = (target[i] - eye[i] for i in range(3))
    yaw = math.degrees(math.atan2(-dx, -dz))
    pitch = math.degrees(math.atan2(dy, math.hypot(dx, dz)))
    return xf(eye, yaw, pitch)


nodes = []


def add(name, scene, pos, yaw=0.0, props=None, parent='.'):
    lines = [f'[node name="{name}" parent="{parent}" instance=ExtResource("{scene}")]', f'transform = {xf(pos, yaw)}']
    for k, v in (props or {}).items():
        lines.append(f'{k} = {v}')
    nodes.append('\n'.join(lines))


def plate(name, text, pos):
    nodes.append('\n'.join([f'[node name="{name}" type="Label3D" parent="Plates"]', f'transform = {xf(pos)}',
                            'pixel_size = 0.008', 'billboard = 1', 'double_sided = true', f'text = "{text}"', 'font_size = 56',
                            'outline_size = 14', 'modulate = Color(1, 0.96, 0.86, 1)', 'outline_modulate = Color(0.25, 0.13, 0.06, 1)']))


def s(v):
    return f'"{v}"'


def v3(x, y, z):
    return f'Vector3({x}, {y}, {z})'


# Row A: collectibles and small interactables (z = 0)
add('TruffleGold', 'Truffle', (-18, 0, 0), props={'truffle_id': s('LAB-1'), 'use_default_mesh': 'false'})
add('TruffleGhost', 'Truffle', (-15.5, 0, 0), props={'truffle_id': s('LAB-GHOST')})
add('AcornRing', 'AcornGroup', (-11.5, 0, 0), props={'shape': 1, 'count': 10, 'radius': 1.4})
add('AcornArc', 'AcornGroup', (-8.5, 0, 1.0), props={'shape': 0, 'count': 6, 'length': 4.0, 'arc_height': 1.2}, yaw=90)
for i in range(3):
    add(f'Page{i + 1}', 'LostPage', (-6.0 + i * 1.6, 0, -0.5 - (i % 2) * 0.8), props={'world_id': s('LAB'), 'page_index': i})
add('PageSet', 'LostPageSet', (-4.0, 0, -3.0), props={'world_id': s('LAB'), 'reward_truffle_id': s('LAB-PAGES')})
add('Checkpoint', 'Checkpoint', (-0.5, 0, -0.5), props={'world_id': s('LAB')})
add('Sign', 'SignPost', (2.5, 0, 0.0), yaw=-10, props={'board_text': s('Objects Lab'), 'lines': 'PackedStringArray("Welcome to the Objects Lab.", "Every toy in the toybox lives here.")'})
add('Bramwell', 'NPCTalker', (5.0, 0, -0.3), yaw=165, props={'speaker': s('Bramwell'), 'lines': 'PackedStringArray("Good afternoon, Master Mak.", "The wolf has made rather a mess of the library.")'})
add('Vine', 'Climbable', (8.0, 0, -1.0), props={'look': 0, 'height': 6.0})
add('Pole', 'Climbable', (9.6, 0, -1.0), props={'look': 1, 'height': 4.5, 'pole_radius': 0.12})
add('Buried', 'BuriedTreasure', (12.5, 0.02, 0.5), props={'truffle_id': s('LAB-BURIED')})
add('Crate1', 'BreakableCrate', (15.5, 0, 0.0), yaw=12)
add('Crate2', 'BreakableCrate', (16.6, 0, -0.6), yaw=-20, props={'size': 0.8})
add('Crate3', 'BreakableCrate', (16.0, 1.0, -0.2), yaw=40, props={'size': 0.7})
add('Switch1', 'SlamSwitch', (19.0, 0, 1.0))
add('Switch2', 'SlamSwitch', (24.0, 0, 1.0), props={'button_color': 'Color(0.3, 0.5, 0.95, 1)'})
add('Cage', 'Cage', (21.5, 0, -1.8), props={'reward_truffle_id': s('LAB-CAGE'), 'switches': 'Array[NodePath]([NodePath("../Switch1"), NodePath("../Switch2")])'})
add('CageTruffle', 'Truffle', (0, 0, 0), parent='Cage/Contents', props={'truffle_id': s('LAB-CAGED')})

# Row B: platforms and bounce (z = -12)
add('PadLeaf', 'BouncePad', (-19, 0, -11), props={'look': 0})
add('PadGumdrop', 'BouncePad', (-15.5, 0, -11), props={'look': 1})
add('PadDrum', 'BouncePad', (-12, 0, -11), props={'look': 2})
add('MoverWood', 'MovingPlatform', (-8, 1.5, -12), props={'travel': v3(5, 0, 0), 'speed': 2.0})
add('MoverBiscuit', 'MovingPlatform', (-8, 3.5, -15), props={'travel': v3(5, 1.5, 0), 'theme': 4, 'size': v3(2.6, 0.4, 2.6), 'mode': 0, 'auto_loop_square': 'true', 'speed': 1.5})
add('Faller1', 'FallingPlatform', (0.5, 2.0, -12))
add('Faller2', 'FallingPlatform', (3.5, 2.5, -12), props={'theme': 1})
add('Cloud1', 'VanishingCloud', (7.5, 3.0, -12))
add('Cloud2', 'VanishingCloud', (10.0, 4.5, -14), props={'size': v3(2.4, 0.8, 2.4)})
add('Windmill', 'RotatingPlatform', (17, 7.5, -16), props={'radius': 5.0, 'degrees_per_second': 18.0})
add('LeafPlatform', 'MovingPlatform', (-19, 3.5, -15), props={'theme': 2, 'travel': v3(0, 2.5, 0), 'speed': 1.0, 'size': v3(2.6, 0.3, 3.0)})

# Row C: portals, door, bellows, hazards (z = -26)
add('BookOpen', 'StorybookPortal', (-16, 0, -26), props={'world_id': s('W1'), 'book_title': s('The Three Little Pigs'), 'required_truffles': 0, 'route_on_enter': 'false'})
add('BookLocked', 'StorybookPortal', (-9, 0, -26), props={'world_id': s('W3'), 'book_title': s('Hansel and Gretel'), 'required_truffles': 7, 'cover_color': 'Color(0.25, 0.45, 0.3, 1)', 'route_on_enter': 'false'})
add('WolfDoor', 'WolfDoor', (-2, 0, -28), props={'required_truffles': 12, 'route_on_enter': 'false'})
add('Wind1', 'WindZone', (6, 1.6, -22.5), props={'size': v3(3, 3, 7), 'direction': v3(0, 0, 1), 'strength': 8.0})
add('Bellows1', 'BellowsMachine', (6, 0, -27.5), yaw=180, props={'group_id': s('lab'), 'wind_zone_path': 'NodePath("../Wind1")'})
add('Bellows2', 'BellowsMachine', (11, 0, -28), yaw=200, props={'group_id': s('lab'), 'start_broken': 'true'})
add('BellowsReward', 'BellowsSet', (8.5, 0, -24), props={'group_id': s('lab'), 'reward_truffle_id': s('LAB-BELLOWS')})
add('Chocolate', 'HazardVolume', (19, -0.35, -25), props={'size': v3(8, 1, 6), 'look': 1})
add('Thorns', 'HazardVolume', (19, 0.4, -30), props={'size': v3(6, 0.8, 1.5), 'look': 2})
add('Trial', 'TimeTrial', (26, 0, -6), yaw=0, props={'reward_truffle_id': s('LAB-TRIAL'), 'time_limit': 20.0})
add('KillFloor', 'KillZone', (0, -30, 0), props={'size': v3(300, 4, 300)})
add('Hundred', 'AcornHundred', (-11.5, 0, -3), props={'required': 100, 'reward_truffle_id': s('LAB-100')})
add('Sniff', 'SniffTarget', (12.5, 0.3, 0.5))
add('TruffleMesh', 'Truffle', (-21, 0, 0), props={'truffle_id': s('LAB-MESH'), 'visual_scene': 'ExtResource("truffle_glb")', 'visual_scale': 1.4})

labels = [('Primitive placeholder', (-18, 2.4, 0)), ('Truffle (generated mesh)', (-21, 2.4, 0)), ('Ghost (owned)', (-15.5, 2.4, 0)), ('Acorns: ring + arc', (-10, 2.4, 0)),
          ('Lost Pages', (-4.4, 2.6, -0.8)), ('Checkpoint bookmark', (-0.5, 3.8, -0.5)), ('Sign', (2.5, 2.9, 0)),
          ('NPC (faces player)', (5.0, 2.9, -0.3)), ('Vine / pole', (8.8, 6.9, -1)), ('Buried treasure', (12.5, 1.5, 0.5)),
          ('Breakable crates', (16, 2.6, -0.3)), ('Slam switches + cage', (21.5, 4.4, -1.0)),
          ('Bounce: leaf, gumdrop, drum', (-15.5, 2.6, -11)), ('Moving platforms', (-6, 5.8, -13)), ('Falling platforms', (2, 4.2, -12)),
          ('Vanishing clouds', (8.7, 6.3, -13)), ('Windmill rotor', (17, 14.2, -16)),
          ('Storybook portal (open)', (-16, 5.6, -26)), ('Locked book (7)', (-9, 5.6, -26)), ('Wolf door (12)', (-2, 5.6, -28)),
          ('Bellows + wind', (8.5, 3.6, -26)), ('Hot chocolate + thorns', (19, 2.2, -27)), ('Time trial', (26, 4.2, -6))]
for i, (t, p) in enumerate(labels):
    plate(f'Plate{i}', t, p)

ext = [f'[ext_resource type="PackedScene" path="res://scenes/objects/{n}.tscn" id="{n}"]' for n in SCENES]
ext.append('[ext_resource type="Script" path="res://scripts/objects/lab_director.gd" id="director"]')
ext.append('[ext_resource type="PackedScene" path="res://assets/props/pickups/golden_truffle/golden_truffle.glb" id="truffle_glb"]')

HEAD = """[gd_scene load_steps=%(steps)d format=3]

%(ext)s

[sub_resource type="ProceduralSkyMaterial" id="sky_mat"]
sky_top_color = Color(0.25, 0.47, 0.88, 1)
sky_horizon_color = Color(0.85, 0.8, 0.76, 1)
sky_curve = 0.12
ground_bottom_color = Color(0.32, 0.36, 0.25, 1)
ground_horizon_color = Color(0.9, 0.84, 0.74, 1)

[sub_resource type="Sky" id="sky"]
sky_material = SubResource("sky_mat")

[sub_resource type="Environment" id="env"]
background_mode = 2
sky = SubResource("sky")
ambient_light_source = 3
ambient_light_energy = 0.55
tonemap_mode = 2
tonemap_exposure = 0.95
tonemap_white = 6.0
ssao_enabled = true
ssao_intensity = 1.4
glow_enabled = true
glow_intensity = 0.7
glow_bloom = 0.08
glow_hdr_threshold = 1.1
fog_enabled = true
fog_light_color = Color(0.78, 0.84, 0.95, 1)
fog_density = 0.0012
fog_aerial_perspective = 0.15
fog_sky_affect = 0.3
adjustment_enabled = true
adjustment_saturation = 1.12

[sub_resource type="StandardMaterial3D" id="ground_mat"]
albedo_color = Color(0.33, 0.55, 0.22, 1)
roughness = 0.95

[sub_resource type="StandardMaterial3D" id="path_mat"]
albedo_color = Color(0.74, 0.6, 0.4, 1)
roughness = 0.9

[sub_resource type="BoxMesh" id="ground_mesh"]
material = SubResource("ground_mat")
size = Vector3(120, 1, 90)

[sub_resource type="BoxShape3D" id="ground_shape"]
size = Vector3(120, 1, 90)

[node name="ObjectsLab" type="Node3D"]

[node name="LabDirector" type="Node3D" parent="."]
script = ExtResource("director")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = %(sun)s
light_color = Color(1, 0.93, 0.8, 1)
light_energy = 1.3
shadow_enabled = true
shadow_blur = 1.5
directional_shadow_max_distance = 120.0

[node name="Fill" type="DirectionalLight3D" parent="."]
transform = %(fill)s
light_color = Color(0.7, 0.8, 1, 1)
light_energy = 0.3

[node name="Ground" type="StaticBody3D" parent="."]
transform = %(ground)s

[node name="Mesh" type="MeshInstance3D" parent="Ground"]
mesh = SubResource("ground_mesh")

[node name="Shape" type="CollisionShape3D" parent="Ground"]
shape = SubResource("ground_shape")

[node name="Paths" type="Node3D" parent="."]

[node name="PathA" type="CSGBox3D" parent="Paths"]
transform = %(pa)s
size = Vector3(52, 0.04, 2.2)
material = SubResource("path_mat")

[node name="PathB" type="CSGBox3D" parent="Paths"]
transform = %(pb)s
size = Vector3(52, 0.04, 2.2)
material = SubResource("path_mat")

[node name="PathC" type="CSGBox3D" parent="Paths"]
transform = %(pc)s
size = Vector3(52, 0.04, 2.2)
material = SubResource("path_mat")

[node name="StoryCams" type="Node3D" parent="."]

[node name="StoryCam_A" type="Camera3D" parent="StoryCams"]
transform = %(ca)s
current = true
fov = 62.0

[node name="StoryCam_B" type="Camera3D" parent="StoryCams"]
transform = %(cb)s
fov = 55.0

[node name="StoryCam_C" type="Camera3D" parent="StoryCams"]
transform = %(cc)s
fov = 60.0

[node name="StoryCam_D" type="Camera3D" parent="StoryCams"]
transform = %(cd)s
fov = 64.0

[node name="StoryCam_E_row_a_right" type="Camera3D" parent="StoryCams"]
transform = %(ce)s
fov = 55.0

[node name="StoryCam_F_books" type="Camera3D" parent="StoryCams"]
transform = %(cf)s
fov = 55.0

[node name="StoryCam_G_bellows_hazards" type="Camera3D" parent="StoryCams"]
transform = %(cg)s
fov = 60.0

[node name="StoryCam_H_truffles_close" type="Camera3D" parent="StoryCams"]
transform = %(ch)s
fov = 50.0

[node name="StoryCam_I_bellows_close" type="Camera3D" parent="StoryCams"]
transform = %(ci)s
fov = 50.0

[node name="StoryCam_J_pages_close" type="Camera3D" parent="StoryCams"]
transform = %(cj)s
fov = 50.0

[node name="Plates" type="Node3D" parent="."]
"""

head = HEAD % {
    'steps': len(ext) + 8, 'ext': '\n'.join(ext),
    'sun': xf((0, 20, 0), 35, -48), 'fill': xf((0, 20, 0), 200, -25), 'ground': xf((0, -0.5, -10)),
    'pa': xf((3, 0.01, 2.6)), 'pb': xf((3, 0.01, -7)), 'pc': xf((3, 0.01, -20)),
    'ca': look_at((2, 24, 26), (2, 0, -12)), 'cb': look_at((-9, 4.2, 10.5), (-9, 0.9, -1)),
    'cc': look_at((-1, 7.5, 6), (2, 3, -13)), 'cd': look_at((3, 7.5, -12), (3, 1.5, -27)),
    'ce': look_at((14, 4.2, 10.5), (14, 1.0, -1)),
    'cf': look_at((-12.5, 4.5, -18.5), (-12.5, 2.4, -26)), 'cg': look_at((13, 4.5, -17), (13, 0.8, -27)),
    'ch': look_at((-18.5, 1.6, 4.0), (-18.5, 0.9, 0)),
    'ci': look_at((10.5, 3.6, -22.5), (6.0, 1.0, -27.5)),
    'cj': look_at((-4.4, 1.9, 3.2), (-4.4, 1.0, -0.9)),
}

OUT.write_text(head + '\n' + '\n\n'.join(nodes) + '\n', encoding='utf-8', newline='\n')
print('wrote', OUT)

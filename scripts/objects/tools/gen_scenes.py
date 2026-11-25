"""Generates the object .tscn files (root + script + empty Visual slot). Re-run after adding objects.
Usage: python game/scripts/objects/tools/gen_scenes.py   (from the entity folder)"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]  # game/
OUT = ROOT / 'scenes' / 'objects'
S = 'res://scripts/objects/'

OBJECTS = [
    # name, root type, script, extra children (tscn text after root/visual), extra ext resources
    ('Truffle', 'Area3D', 'truffle.gd', ''),
    ('Acorn', 'Area3D', 'acorn.gd', ''),
    ('AcornGroup', 'Node3D', 'acorn_group.gd', ''),
    ('AcornHundred', 'Node3D', 'acorn_hundred.gd', 'marker'),
    ('LostPage', 'Area3D', 'lost_page.gd', ''),
    ('LostPageSet', 'Node3D', 'lost_page_set.gd', 'marker'),
    ('Checkpoint', 'Area3D', 'checkpoint.gd', ''),
    ('StorybookPortal', 'StaticBody3D', 'storybook_portal.gd', ''),
    ('WolfDoor', 'Node3D', 'wolf_door.gd', ''),
    ('MovingPlatform', 'Node3D', 'moving_platform.gd', ''),
    ('RotatingPlatform', 'Node3D', 'rotating_platform.gd', ''),
    ('FallingPlatform', 'AnimatableBody3D', 'falling_platform.gd', ''),
    ('BouncePad', 'StaticBody3D', 'bounce_pad.gd', ''),
    ('WindZone', 'Area3D', 'wind_zone.gd', ''),
    ('BellowsMachine', 'StaticBody3D', 'bellows_machine.gd', ''),
    ('BellowsSet', 'Node3D', 'bellows_set.gd', 'marker'),
    ('VanishingCloud', 'AnimatableBody3D', 'vanishing_cloud.gd', ''),
    ('HazardVolume', 'Area3D', 'hazard_volume.gd', ''),
    ('KillZone', 'Area3D', 'kill_zone.gd', ''),
    ('Climbable', 'Area3D', 'climbable.gd', ''),
    ('SignPost', 'StaticBody3D', 'sign_post.gd', ''),
    ('NPCTalker', 'StaticBody3D', 'npc_talker.gd', ''),
    ('TrialRing', 'Area3D', 'ring.gd', ''),
    ('TimeTrial', 'Node3D', 'time_trial.gd', 'trial'),
    ('BreakableCrate', 'StaticBody3D', 'breakable_crate.gd', ''),
    ('SlamSwitch', 'StaticBody3D', 'slam_switch.gd', ''),
    ('Cage', 'Node3D', 'cage.gd', 'cage'),
    ('SniffTarget', 'Node3D', 'sniff_target.gd', ''),
    ('BuriedTreasure', 'Node3D', 'buried_treasure.gd', ''),
]


def scene(name, rtype, script, extra):
    ext = [f'[ext_resource type="Script" path="{S}{script}" id="1_s"]']
    body = [f'[node name="{name}" type="{rtype}"]', 'script = ExtResource("1_s")', '',
            '[node name="Visual" type="Node3D" parent="."]', '']
    if extra == 'marker':
        body += ['[node name="TruffleMarker" type="Marker3D" parent="."]',
                 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -2)', '']
    if extra == 'cage':
        body += ['[node name="Contents" type="Node3D" parent="."]', '',
                 '[node name="TruffleMarker" type="Marker3D" parent="."]', '']
    if extra == 'trial':
        ext.append('[ext_resource type="PackedScene" path="res://scenes/objects/TrialRing.tscn" id="2_r"]')
        body += ['[node name="StartGate" type="Node3D" parent="."]', '',
                 '[node name="Rings" type="Node3D" parent="."]', '']
        for i, (x, y, z) in enumerate([(0, 1.8, -6), (2, 2.4, -11), (0, 1.8, -16)]):
            body += [f'[node name="Ring{i + 1}" parent="Rings" instance=ExtResource("2_r")]',
                     f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, {y}, {z})', '']
        body += ['[node name="FinishGate" type="Node3D" parent="."]',
                 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -21)', '',
                 '[node name="TruffleMarker" type="Marker3D" parent="."]',
                 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 3, 0, -21)', '']
    head = f'[gd_scene load_steps={len(ext) + 1} format=3]'
    return '\n'.join([head, ''] + ext + [''] + body)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, rtype, script, extra in OBJECTS:
        (OUT / f'{name}.tscn').write_text(scene(name, rtype, script, extra), encoding='utf-8', newline='\n')
        print('wrote', name)


if __name__ == '__main__':
    main()

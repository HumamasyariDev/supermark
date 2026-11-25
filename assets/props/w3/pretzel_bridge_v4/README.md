# Pretzel bridge v4 with edge boards over the log ends (W3-M05). Use this file; it replaces `pretzel_bridge_v3`

TOPUP_WORLDS fix round 4 (ASSETS3_WORLDS, night 01, 12:10-12:20 Bangkok), made in Blender 5.1 background mode from `w3/pretzel_bridge_v3/pretzel_bridge_v3.glb` with `assets_src/topup/worlds/tools/fix_r4/fix_bridge_r4.py` (report JSON and Blender renders in `assets_src/topup/worlds/pretzel_bridge/fix_r4/`). No paid calls. Same conventions as v3: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k WebP textures embedded, no vertex colours, no collision embedded, no bones. The older versions stay on disk as backups.

## What changed

The r3 residue: from a low side angle the deck edge still read as a row of rounded log ends ("buns"), with the r3 deck board showing as a beam under them. v4 adds a fascia stringer on each side: a rounded-rectangle beam 0.12 m thick and 0.34 m tall, lofted along the arch on the log-end line (x = +-1.668 m), so it swallows the logs' rounded caps. Its top sits 1 cm under the walk surface (`_arch_y`), so it never rises above the deck, and its ends are capped. It is mapped to the baked crust of the log ends (the colour the side view already showed), so it reads as the bridge's edge board. Everything else is v3: flattened logs on a continuous deck board, rails evened, rail pretzels tilted to the slope. Walk surface ray-cast (lanes x 0, +-0.6, +-0.9, every 0.25 m): 0.001-0.037 m under `_arch_y`, as v3. 13.8k tris (v3 9.9k).

## Use

- Same size (3.54 x 3.65 x 15.86 m), origin and placement as v3: `w3_level.gd` `_build_bridges`, both strings `"res://assets/props/w3/pretzel_bridge/pretzel_bridge.glb"` -> `"res://assets/props/w3/pretzel_bridge_v4/pretzel_bridge_v4.glb"`, and in `glb(..., Vector3(x, -0.15, 4.5), 0.0, 1.0, g)` use y 0.0 (scale 1.0, yaw 0).

## Evidence

Native (`Docs/progress/topup_worlds/fix_r4/`, look-dev scenes `game/assets/props/boss/_preview_v2/FixR4W3.tscn` and `FixR4W3Before.tscn`, same cameras): `*__FixR4W3_EdgeLow.png` / `*__FixR4W3Before_EdgeLow.png`, `*__FixR4W3_BridgeSide.png` / `*__FixR4W3Before_BridgeSide.png`, `*__FixR4W3_DeckLow.png` and the `_before_after` pairs. Blender pairs (v3 left, v4 right): `assets_src/topup/worlds/pretzel_bridge/fix_r4/v3_v4_side_pair.png`, `v3_v4_low_pair.png`.

# Pretzel bridge v3 with a continuous deck and seated rail pretzels (W3-M05). Use this file; it replaces `pretzel_bridge` and `pretzel_bridge_v2`

TOPUP_WORLDS fix round 3 (night 01, 06:30-08:45 Bangkok), made in Blender 5.1 background mode from the accepted asset with the scripts in `assets_src/topup/worlds/tools/fix_r3/` (report JSON and Blender renders in `assets_src/topup/worlds/<asset>/fix_r3/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded (WebP), no vertex colours, no collision embedded, no bones. Sockets are carried over unchanged. Godot captures: `Docs/progress/topup_worlds/fix_r3/` (look-dev scenes `game/assets/props/boss/_preview_v2/FixR3*.tscn`, generator `assets_src/topup/worlds/tools/fix_r3/gen_fix_scenes_r3.py`). The older versions stay on disk as backups. Swap lines for the builders: `Docs/ASSETS_TOPUP.md`, "Swap list for world builders".

## What changed

Source `w3/pretzel_bridge_v2/pretzel_bridge_v2.glb`, script `fix_bridge_r3.py`. This fixes the r2 critique items. (1) The deck read as separate buns with dark gaps: the log tops are flattened (the upper 0.12 m is compressed to 35 %) and lengthened 8 % so neighbours overlap, then re-seated on the arch. A continuous rounded deck board (3.04 m wide, 0.28 m thick, wood texels) now runs 5 cm under the log tops along the whole arch, so the gaps show baked wood, not daylight. (2) The rail pretzels pierced the hand rail: each pretzel is tilted to the local slope about its foot and scaled vertically (0.91-1.01) so its top sits 4 cm under the rail centre line, and the hand rails are evened out to a constant 0.976 m above the arch (it was 0.945-1.088). (3) The log seams at z +-3 sat 0.13-0.15 m low: a Blender ray-cast every 0.25 m on lanes x 0, +-0.6 and +-0.9 (295 hits) now lands between 0.037 m and 0.001 m under `_arch_y`.

## Use

- Size 3.54 x 3.65 x 15.86 m, 9.9k tris. Place at scale 1.0, yaw 0, y 0.0 (not -0.15) at the builder's (x, 0, 4.5).
- Collision stays the builder's 8 deck boxes on `_arch_y`.

## Evidence

Docs/progress/topup_worlds/fix_r3/20261017T234546Z__FixR3W3_BridgeSide.png, _RailClose, _DeckLow, _DeckTop (after); __FixR3W3Before_DeckTop.png, the pairs __FixR3W3_DeckLow_before_after.png, _RailClose_before_after.png, _DeckTop_before_after.png and Docs/progress/topup_worlds/fix_r1/20261017T203912Z__FixW3_BridgeSide.png / _RailClose.png (before); Blender: assets_src/topup/worlds/pretzel_bridge/fix_r3/

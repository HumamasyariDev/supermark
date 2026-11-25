# Birch v4 with barked limbs and dark branch collars (W1-M10). Use this file; it replaces `birch_tree_v3`

TOPUP_WORLDS fix round 3 (night 01, 06:30-08:45 Bangkok), made in Blender 5.1 background mode from the accepted asset with the scripts in `assets_src/topup/worlds/tools/fix_r3/` (report JSON and Blender renders in `assets_src/topup/worlds/<asset>/fix_r3/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded (WebP), no vertex colours, no collision embedded, no bones. Sockets are carried over unchanged. Godot captures: `Docs/progress/topup_worlds/fix_r3/` (look-dev scenes `game/assets/props/boss/_preview_v2/FixR3*.tscn`, generator `assets_src/topup/worlds/tools/fix_r3/gen_fix_scenes_r3.py`). The older versions stay on disk as backups. Swap lines for the builders: `Docs/ASSETS_TOPUP.md`, "Swap list for world builders".

## What changed

Source `w1/birch_tree_v3/birch_tree_v3.glb`, script `fix_birch_r3.py`. The r2 critique found pale smears at the fork joins. Cause: r1 mapped all five procedural limbs into one 0.004-wide speck of trunk texels, so they rendered as plain cream tubes, and each limb base poked out of the trunk as a pale, untextured stub. The atlas was fully packed, so v4 squeezes every existing UV into the left 7/8 (all three textures resampled to match, so the trunk and leaves look the same). The limbs get the freed 232 x 2024 texel strip, with their own cylindrical UVs. That strip is painted as birch bark: the trunk's own cream (0.93, 0.88, 0.75), black lenticel dashes in rows, and the dark birch collar at each limb base, which is what a real birch shows where a branch leaves the trunk. Geometry is identical to v3.

## Use

- Size about 5.0 x 10.3 x 4.1 m, 8.0k tris (as v3).
- Builder: swap `BIRCH_GLB` in w1_dress.gd; randomise the yaw and use a 0.9-1.15 Y scale per instance.

## Evidence

Docs/progress/topup_worlds/fix_r3/20261018T000300Z__FixR3W1Birch_ForkV4.png (after), _ForkV3.png (before), _Fork_before_after.png, _PairCam.png (v3 left, v4 right), _GroveLow.png; Blender: assets_src/topup/worlds/birch_tree_v2/fix_r3/birch_tree_v4_side_fork_crop.png

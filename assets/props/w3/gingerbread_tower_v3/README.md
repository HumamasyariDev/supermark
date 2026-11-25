# Gingerbread fort corner tower v3 with a peppermint finial (W3). Use this file; it replaces `gingerbread_tower` and `gingerbread_tower_v2`

TOPUP_WORLDS fix round 3 (night 01, 06:30-08:45 Bangkok), made in Blender 5.1 background mode from the accepted asset with the scripts in `assets_src/topup/worlds/tools/fix_r3/` (report JSON and Blender renders in `assets_src/topup/worlds/<asset>/fix_r3/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded (WebP), no vertex colours, no collision embedded, no bones. Sockets are carried over unchanged. Godot captures: `Docs/progress/topup_worlds/fix_r3/` (look-dev scenes `game/assets/props/boss/_preview_v2/FixR3*.tscn`, generator `assets_src/topup/worlds/tools/fix_r3/gen_fix_scenes_r3.py`). The older versions stay on disk as backups. Swap lines for the builders: `Docs/ASSETS_TOPUP.md`, "Swap list for world builders".

## What changed

Source `w3/gingerbread_tower/gingerbread_tower.glb`, script `fix_tower_r3.py`. The r1 finial (a thin disc thickened and crossed with a 90-degree copy) read as a plus-sign gift ball (r2 critique). v3 deletes the original finial island and lathes one peppermint lozenge in its place, with the same centre and diameter (0.71 m), facing the tower front. It is 0.26 m thick with a fully rounded rim and has eight alternating red and white wedges that wrap over the rim. Each face takes one flat red or white texel of the old finial's own texture, so the stripes stay crisp. It reads as a round candy from the front and as a striped pill edge-on. The tower body is untouched.

## Use

- Size and origin as v1/v2 (3.4 x 7.6 x 3.4 class), 8.6k tris.
- Builder: swap the `TW` path; vary the yaw by 90 degrees per instance.

## Evidence

Docs/progress/topup_worlds/fix_r3/20261017T234546Z__FixR3W3_TowerTop.png, _TowerEdge, _TowerSide (after); __FixR3W3Before_TowerSide.png, __FixR3W3_TowerSide_before_after.png and Docs/progress/critique/topup_worlds/r2_asset_qa/20261017T231636Z__r2_tower_finial_cross_crop.png (before); Blender: assets_src/topup/worlds/gingerbread_tower/fix_r3/gingerbread_tower_v3_front.png

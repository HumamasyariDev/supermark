# Birch v3 with a forked crown and bark all round (W1-M10). Use this instead of `birch_tree` and `birch_tree_v2`

TOPUP_WORLDS fix pass r1 (night 01), made in Blender 5.1 from the delivered Tripo P2 asset with the scripts in `assets_src/topup/worlds/tools/fix_r1/` (report JSON next to each source in `assets_src/topup/worlds/<asset>/fix_r1*/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded, no vertex colours, no collision embedded, no bones. Sockets are carried over from the source (see its README) unless noted. Godot captures: `Docs/progress/topup_worlds/fix_r1/` (look-dev scenes `game/assets/props/boss/_preview_v2/Fix*.tscn`, generator `assets_src/topup/worlds/tools/fix_r1/gen_fix_scenes.py`).

## What changed

Source `w1/birch_tree_v2/birch_tree_v2.glb`, script `fix_birch.py`. Stub branch pulled into the trunk, root flare reduced, trunk tapered, a procedural fork (four limbs and a leader) on bark texels; the sphere-cluster canopy replaced by four separated drooping lobes; black lenticel dashes painted all round the bark (108k texels); roughness 0.75 on leaves, 0.55 on bark.

## Use

- Size about 5.0 x 10.3 x 4.1 m, 8.0k tris.
- Builder: w1_dress.gd:9 `BIRCH_GLB` still loads v1; switch to `w1/birch_tree_v3/birch_tree_v3.glb`, randomise the yaw and use a 0.9-1.15 Y scale per instance (one mesh, no variants yet).

## Evidence

`Docs/progress/topup_worlds/fix_r1/` 20261017T205410Z__FixW1_GroveLow.png, _GameCam.png

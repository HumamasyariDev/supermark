# Silver teapot v3 (BOSS-M13). Use this file; it replaces `teapot` and `teapot_v2`

TOPUP_WORLDS fix round 3 (night 01, 06:30-08:45 Bangkok), made in Blender 5.1 background mode from the accepted asset with the scripts in `assets_src/topup/worlds/tools/fix_r3/` (report JSON and Blender renders in `assets_src/topup/worlds/<asset>/fix_r3/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded (WebP), no vertex colours, no collision embedded, no bones. Sockets are carried over unchanged. Godot captures: `Docs/progress/topup_worlds/fix_r3/` (look-dev scenes `game/assets/props/boss/_preview_v2/FixR3*.tscn`, generator `assets_src/topup/worlds/tools/fix_r3/gen_fix_scenes_r3.py`). The older versions stay on disk as backups. Swap lines for the builders: `Docs/ASSETS_TOPUP.md`, "Swap list for world builders".

## What changed

Source `boss/teapot/teapot.glb`, script `fix_teapot_r3.py`. Geometry identical to v2 (smoothed handle and spout). New texture pass for the r2 critique's brown blotches on the silver body. Cause: the r1 AO bake used Cycles' default 10 m AO distance (`fixlib.bake_ao` ignored its distance argument), so the handle, spout and lid darkened large soft patches of the belly, and the boss light turned them brown. v3 bakes AO at 6 cm (creases only), blurs it and lets it darken the silver by at most 30 %. It drops the copper-luminance detail term, dilates every island into the atlas background so mip-maps cannot pull dark texels into seams, and uses uniform roughness 0.28 (0.34 in the engraved band), metallic 0.35 and gold trim 0.9. Silver luminance p5/p50/p95 is 0.57/0.78/0.82.

## Use

- Size 0.72 x 0.50 x 0.43 m, 4.1k tris, same origin as v2.
- TeaTempest ring (wolf_boss.gd): swap the path only. On the trolley (wolf_rooftop.gd), use scale 0.55 at the `tea_trolley_v2` `teapot_socket`.

## Evidence

Docs/progress/topup_worlds/fix_r3/20261017T234546Z__FixR3Boss_TeapotClose.png (v2 centre, v3 left and right), __FixR3Boss_TeapotV3Macro.png (after), __FixR3Boss_Teapot_before_after.png, __FixR3Boss_TeapotV2Macro.png (before), __FixR3Boss_TrolleyPotCam.png; Blender: assets_src/topup/worlds/teapot/fix_r3/teapot_v3_*.png

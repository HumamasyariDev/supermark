# Silver teapot v2 (BOSS-M13). Use this instead of `teapot`

TOPUP_WORLDS fix pass r1 (night 01), made in Blender 5.1 from the delivered Tripo P2 asset with the scripts in `assets_src/topup/worlds/tools/fix_r1/` (report JSON next to each source in `assets_src/topup/worlds/<asset>/fix_r1*/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded, no vertex colours, no collision embedded, no bones. Sockets are carried over from the source (see its README) unless noted. Godot captures: `Docs/progress/topup_worlds/fix_r1/` (look-dev scenes `game/assets/props/boss/_preview_v2/Fix*.tscn`, generator `assets_src/topup/worlds/tools/fix_r1/gen_fix_scenes.py`).

## What changed

Source `boss/teapot/teapot.glb`, script `fix_teapot.py --gold-trim`. Handle and spout smoothed (max vertex move 0.049 m), warm-neutral silver base (0.80, 0.82, 0.86) with baked AO, an engraved belly band, gold trim on the foot, handle and knob. Shipped variant: metallic 0.35, roughness 0.30, chosen from four variants (`boss/_preview_v2/variants/`) under the boss light so the storm sky does not tint it.

## Use

- Size 0.72 x 0.50 x 0.43 m, 4.1k tris.
- On the trolley use scale 0.55 at the `tea_trolley_v2` teapot_socket.

## Evidence

`Docs/progress/topup_worlds/fix_r1/` 20261017T203047Z__FixBoss_TeapotClose.png (old copper left, v2 right), 20261017T202945Z__FixBoss_TeapotVariants_VariantCam.png

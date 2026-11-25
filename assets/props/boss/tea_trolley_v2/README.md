# Tea trolley v2 with clean wheels and a moved teapot socket (BOSS-M03). Use this instead of `tea_trolley`

TOPUP_WORLDS fix pass r1 (night 01), made in Blender 5.1 from the delivered Tripo P2 asset with the scripts in `assets_src/topup/worlds/tools/fix_r1/` (report JSON next to each source in `assets_src/topup/worlds/<asset>/fix_r1*/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded, no vertex colours, no collision embedded, no bones. Sockets are carried over from the source (see its README) unless noted. Godot captures: `Docs/progress/topup_worlds/fix_r1/` (look-dev scenes `game/assets/props/boss/_preview_v2/Fix*.tscn`, generator `assets_src/topup/worlds/tools/fix_r1/gen_fix_scenes.py`).

## What changed

Source `boss/tea_trolley/tea_trolley.glb`, script `fix_trolley.py`. The four lumpy gold wheels are replaced by clean lathed wheels (hub dome, recessed face, rolled rim) of the same size and place, UV'd onto the original gold texels.

## Use

- `teapot_socket` moved inboard to (0.22, 0.72, 0.05) glTF so a 0.55-scale teapot sits on the tray, clear of the push handle.

## Evidence

`Docs/progress/topup_worlds/fix_r1/` 20261017T203047Z__FixBoss_TrolleyPotCam.png

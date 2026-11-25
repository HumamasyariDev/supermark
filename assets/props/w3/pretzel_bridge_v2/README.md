# Pretzel bridge v2 with a deck that follows the W3 arch (W3-M05). Use this instead of `pretzel_bridge`

TOPUP_WORLDS fix pass r1 (night 01), made in Blender 5.1 from the delivered Tripo P2 asset with the scripts in `assets_src/topup/worlds/tools/fix_r1/` (report JSON next to each source in `assets_src/topup/worlds/<asset>/fix_r1*/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded, no vertex colours, no collision embedded, no bones. Sockets are carried over from the source (see its README) unless noted. Godot captures: `Docs/progress/topup_worlds/fix_r1/` (look-dev scenes `game/assets/props/boss/_preview_v2/Fix*.tscn`, generator `assets_src/topup/worlds/tools/fix_r1/gen_fix_scenes.py`).

## What changed

Source `w3/pretzel_bridge/pretzel_bridge.glb`, script `fix_bridge.py`. The 22 deck logs are re-seated rigidly on top(z) = 1.3 + 1.1 (1 - (z/8)^2) (w3_level.gd `_arch_y`), tilted to the slope and flattened; rail pretzels move rigidly (no stretch), the hand rails bend, the feet shrink 0.75, everything is smooth-shaded, the streaked log end caps are re-mapped. 7.9k tris.

## Use

- Size 3.54 x 3.63 x 15.85 m: place at scale 1.0 (no non-uniform fit; the old 8.1 m to 16 m stretch is gone).
- Ray-cast (06:03 Bangkok, lanes x 0 and +-0.6): z -7 1.54 (arch 1.56), -4 2.12 (2.13), -2 2.33 (2.33), 0 2.39 (2.40), +4 2.12, +7 1.55. The slices at z +-3 hit a log seam 0.13-0.15 m low and z +5 is 0.06 m low; the rest is within 0.03 m.
- Builder (w3_level.gd:1342-1344, 1422): load the v2 path at scale 1.0 and y 0 (not y -0.15, not the 16 m fit). The 8 deck boxes on `_arch_y` stay as they are.

## Evidence

`Docs/progress/topup_worlds/fix_r1/` 20261017T203912Z__FixW3_BridgeSide.png, _DeckLow.png, _RailClose.png

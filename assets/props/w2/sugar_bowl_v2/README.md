# Open sugar bowl v2 with a flat walkable sugar heap (W2). Use only where a walkable cube heap is wanted

TOPUP_WORLDS fix pass r1 (night 01), made in Blender 5.1 from the delivered Tripo P2 asset with the scripts in `assets_src/topup/worlds/tools/fix_r1/` (report JSON next to each source in `assets_src/topup/worlds/<asset>/fix_r1*/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded, no vertex colours, no collision embedded, no bones. Sockets are carried over from the source (see its README) unless noted. Godot captures: `Docs/progress/topup_worlds/fix_r1/` (look-dev scenes `game/assets/props/boss/_preview_v2/Fix*.tscn`, generator `assets_src/topup/worlds/tools/fix_r1/gen_fix_scenes.py`).

## What changed

Source `w2/sugar_bowl/sugar_bowl.glb`, script `fix_sugar.py`. Cube islands re-seated so their tops lie at 1.10 m (rim) to 1.20 m (centre); a hidden sugar-white filler slab and a second lower cube layer close the gaps.

## Use

- Size 2.96 x 1.2 x 2.2 m (still the round-1 non-uniform fit; the lidded variant undoes it).
- Walkable top 1.10-1.20 m: collider top 1.15 m, radius 1.0, at scale 1.0.
- For W2 SUGAR the spec wants a lidded bowl: use `sugar_bowl_lidded` there.

## Evidence

`Docs/progress/topup_worlds/fix_r1/` 20261017T203426Z__FixW2_SugarCam.png, _SugarTop.png

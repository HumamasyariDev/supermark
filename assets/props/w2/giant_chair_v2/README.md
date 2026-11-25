# Giant chair v2 with a flat cushion (W2 CHAIR). Use this instead of `giant_chair`

TOPUP_WORLDS fix pass r1 (night 01), made in Blender 5.1 from the delivered Tripo P2 asset with the scripts in `assets_src/topup/worlds/tools/fix_r1/` (report JSON next to each source in `assets_src/topup/worlds/<asset>/fix_r1*/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded, no vertex colours, no collision embedded, no bones. Sockets are carried over from the source (see its README) unless noted. Godot captures: `Docs/progress/topup_worlds/fix_r1/` (look-dev scenes `game/assets/props/boss/_preview_v2/Fix*.tscn`, generator `assets_src/topup/worlds/tools/fix_r1/gen_fix_scenes.py`).

## What changed

Source `w2/giant_chair/giant_chair.glb`, script `fix_chair.py`. The domed cushion top is flattened to 4.35-4.40 m (was 4.13-4.41); size unchanged 4.0 x 8.85 x 4.0.

## Use

- Ray-cast at scale 1.0 (re-check 06:03 Bangkok, lanes x 0 and +-0.8, z -1 to 1.5): 4.30-4.40 m, so a seat collider top at 4.40 m matches within 0.02 m in the middle and 0.1 m at the front edge.
- Builder (w2_build.gd:1441-1443): change place_fit to fit Vector3(4.0, 8.85, 4.0) so k = 1.0 (seat collider top 50 + 4.40 = 54.40, as now). Trim the back collider top to 50 + 8.85 = 58.85 (it reaches 61.0 today, an invisible wall).

## Evidence

`Docs/progress/topup_worlds/fix_r1/` 20261017T203426Z__FixW2_SeatCam.png, _SeatLow.png

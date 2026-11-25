# Bellows machine v3 with the wolf emblem on both sides (W1-M05). Use this instead of `bellows_machine` and `bellows_machine_v2`

TOPUP_WORLDS fix pass r1 (night 01), made in Blender 5.1 from the delivered Tripo P2 asset with the scripts in `assets_src/topup/worlds/tools/fix_r1/` (report JSON next to each source in `assets_src/topup/worlds/<asset>/fix_r1*/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded, no vertex colours, no collision embedded, no bones. Sockets are carried over from the source (see its README) unless noted. Godot captures: `Docs/progress/topup_worlds/fix_r1/` (look-dev scenes `game/assets/props/boss/_preview_v2/Fix*.tscn`, generator `assets_src/topup/worlds/tools/fix_r1/gen_fix_scenes.py`).

## What changed

Source `w1/bellows_machine_v2/bellows_machine_v2.glb` (and `_busted`), script `fix_bellows.py`. The +X wolf-head plate (256 faces) is copied, mirrored and seated over the blank -X disc; wheel rims and the nozzle bell are relaxed; wood and wheels get roughness 0.7.

## Use

- Same size, origin and sockets as v2.
- Busted state: `bellows_machine_v3_busted.glb` in this folder (swap on Ham Slam).
- Builder: w1_level.gd:900 `bel_glb` still loads v1 `bellows_machine`; switch to `w1/bellows_machine_v3/bellows_machine_v3.glb` and the busted swap to `bellows_machine_v3_busted.glb`.

## Evidence

`Docs/progress/topup_worlds/fix_r1/` 20261017T205410Z__FixW1_BellowsMinusX.png, _BustedMinusX.png. Before: critique 20261017T201535Z__CritW1_BellowsMinusX.png

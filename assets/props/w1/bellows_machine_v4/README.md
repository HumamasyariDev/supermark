# W1 bellows machine v4 (+ busted) with a full wolf emblem on both sides and a clean brass bell. Use this file; it replaces `bellows_machine_v3`

TOPUP_WORLDS fix round 3 (night 01, 06:30-08:45 Bangkok), made in Blender 5.1 background mode from the accepted asset with the scripts in `assets_src/topup/worlds/tools/fix_r3/` (report JSON and Blender renders in `assets_src/topup/worlds/<asset>/fix_r3/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded (WebP), no vertex colours, no collision embedded, no bones. Sockets are carried over unchanged. Godot captures: `Docs/progress/topup_worlds/fix_r3/` (look-dev scenes `game/assets/props/boss/_preview_v2/FixR3*.tscn`, generator `assets_src/topup/worlds/tools/fix_r3/gen_fix_scenes_r3.py`). The older versions stay on disk as backups. Swap lines for the builders: `Docs/ASSETS_TOPUP.md`, "Swap list for world builders".

## What changed

Source `w1/bellows_machine_v2/bellows_machine_v2.glb` (and `_busted`), script `fix_bellows_r3.py`. The r2 critique found two faults on v3. (1) The -X emblem was a flat grey plate: r1 mirrored only the faces it could classify and pushed them out with a per-vertex test, so leather folds covered half the wolf and the old blank disc stayed visible. v4 finds the +X shield as the largest grey painted area and builds a new 64 x 64 plate by ray-casting it from +X. Every grid point takes the exact UV under it (barycentric), so the whole painted wolf and its rim come across. The plate is mirrored to -X, centred on the old blank disc (which takes leather texels), and follows the -X leather smoothed over a 9 x 9 window, 3 cm proud and never closer than 1.2 cm (median gap 2.8 cm). A 0.14 m skirt sinks its border into the body. (2) The brass nozzle lip had a notch: the Tripo bell past y -1.92 along the nozzle axis is replaced by a lathed 32-segment brass bell with a rolled lip and a hollow mouth (brass texel from the old bell). Kept from r1: wheel rims relaxed, roughness 0.7 on non-metal, softened normals. The busted variant gets the same emblem (centred at z 1.90). Its nozzle is bent down on purpose, so it keeps its own bell.

## Use

- Same size, origin and sockets (`nozzle_socket`, `plate_socket`) as v2/v3. 15.7k tris (busted 14.3k).
- Busted state: `bellows_machine_v4_busted.glb` in this folder; `bellows_machine.gd` finds it from the visual's path.
- Known residue: the mirrored wolf faces the nozzle on -X (a mirror image of the +X side, which is fine for a head with no text). The plate's lower edge picks up a few leather texels where the +X shield meets a strap. A small step where the old nozzle tube meets the new bell reads as a sleeve.

## Evidence

Docs/progress/topup_worlds/fix_r3/20261017T234546Z__FixR3W1_BellowsMinusX.png, _BustedMinusX, _NozzleCam, _BellowsQ34 (after); __FixR3W1Before_NozzleCam.png, __FixR3W1Before_BellowsQ34.png (before), __FixR3W1_Nozzle_before_after.png, __FixR3W1_BellowsQ34_before_after.png; Blender: assets_src/topup/worlds/bellows_machine_v2/fix_r3/bellows_machine_v4_lside.png, _q34l.png

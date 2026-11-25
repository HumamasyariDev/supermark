# Giant chair v3 with clean ribbon bands (W2 CHAIR). Use this file; it replaces `giant_chair` and `giant_chair_v2`

TOPUP_WORLDS fix round 4 (ASSETS3_WORLDS, night 01, 11:05-11:40 Bangkok), made in Blender 5.1 background mode from `w2/giant_chair_v2/giant_chair_v2.glb` with `assets_src/topup/worlds/tools/fix_r4/fix_chair_r4.py` (report JSON and Blender renders in `assets_src/topup/worlds/giant_chair/fix_r4/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded (WebP), no vertex colours, no collision embedded, no bones. The older versions stay on disk as backups. Swap lines for the builders: `Docs/ASSETS_TOPUP.md`, "Swap list for world builders".

## What changed

The r2 critique's open polish defect: the ribbon wrap on each back post had a frayed, saw-toothed top edge (round 3 tried a Laplacian relax and a texture repaint; both were rejected). Cause: the wrap band is its own Tripo shell (96 vertices per post) whose top rim is a row of flaps. v3 deletes the two wrap-band shells (the bow loops and tails are separate shells and stay exactly as they were) and lathes a clean 48-segment ribbon band around each back post: post axis from a PCA of the post shell, inner radius 0.259 m (post radius 0.279 m minus 2 cm, so it grips the post), outer 0.33-0.34 m, height 0.45-0.48 m (it also covers the crimson paint that sat on the post under the old band, so no red teeth stay visible), flat face with rolled hems. UVs are one continuous cylindrical strip in the cleanest crimson block of the albedo (std-weighted pick); the rolled hems use a darker crimson block. Cushion, seat height, size (4.0 x 8.85 x 4.0) and sockets are unchanged; 7.1k tris (was 5.9k).

## Use

- Same bounding box and origin as v2, so it is a path-only swap from v2. Builder (w2_build.gd, chair block): use fit `Vector3(4.0, 8.85, 4.0)` so k = 1.0 and the cushion top meets the 54.40 seat collider (the current `Vector3(4.2, 11.0, 4.2)` gives k 1.05, so the cushion sits 0.22 m above the collider and Mak sinks into it). Trim the back collider top to 58.85 (it reaches 61.0, an invisible wall).

## Limits

- In Godot the seat's back rail top, between the cushion and the posts, reads as a pale grey-blue strip at a grazing angle (WrapCam captures, same on v2). The Blender close-ups (`v3rail__railTop.png`) show plain wood there, so it is sky specular on that flat face, not a texture fault; it is not visible from the gameplay camera.

## Evidence

Native (`Docs/progress/topup_worlds/fix_r4/`, look-dev scenes `game/assets/props/boss/_preview_v2/FixR4W2.tscn` and `FixR4W2Before.tscn`, same cameras): `20261018T043254Z__FixR4W2_WrapCam.png` / `__FixR4W2Before_WrapCam.png`, `__FixR4W2_WrapCamB.png` / `__FixR4W2Before_WrapCamB.png`, `__FixR4W2Before_BackCam.png` / `20261018T041528Z__FixR4W2_BackCam.png`, `__FixR4W2_SeatCam.png`. Blender: `assets_src/topup/worlds/giant_chair/fix_r4/v2_*.png` (before) and `v3_*.png` (after).

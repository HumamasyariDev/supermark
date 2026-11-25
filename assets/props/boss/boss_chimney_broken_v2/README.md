# Boss chimney broken stump v2 with a walkable top (BOSS-M02). Use this instead of `boss_chimney_broken`

TOPUP_WORLDS fix pass r1 (night 01), made in Blender 5.1 from `boss/boss_chimney_broken/boss_chimney_broken.glb` with
`assets_src/topup/worlds/tools/fix_r1/fix_stump.py` (report: `assets_src/topup/worlds/boss_chimney_broken/fix_r1/report.json`).
No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures
embedded, no vertex colours, no collision embedded, no bones, no sockets.

## What changed

- The jagged stump top (2.31-3.00 m) is compressed into 2.20-2.45 m (scale 0.31 above 2.2 m), keeping the broken brick edge.
- Rubble outside the plinth footprint is flattened to 60 % height (ray-cast lanes now 0.13-0.32 m; was up to 0.64 m).

## Use

- Same size and footprint as v1 (4.99 x 4.81 m), top 2.45 m.
- Ray-cast at scale 1.0 (lanes x -0.5 / 0 / +0.5): stump top 2.24-2.45 m, so the builder's stump box collider top 2.4 m
  (boss_chimney.gd:44-45) now matches within 0.05 m on the high side; the inner broken rim dips to 2.24 m.
- Builder: load this path, and drop VIS_SCALE to a uniform 1.0-1.1 (the critique's stretched-brick note applies here too).
  The rubble is still decor without collision; at 0.3 m it no longer swallows Mak's feet.
- Trade-off: the top silhouette is less jagged than v1 (a flatter broken crown). If the phase 2 smash needs more drama,
  add the debris VFX burst rather than tall geometry.

## Evidence

`Docs/progress/topup_worlds/fix_r1/20261017T230537Z__FixBossStump_StumpCam.png` and `_StumpLow.png`: v1 left (Mak waist-deep
at the 2.4 m collider top), v2 right (Mak's feet on the bricks).

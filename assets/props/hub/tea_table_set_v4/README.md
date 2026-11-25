# tea_table_set_v4 (TOPUP_HUB round 4, ASSETS3_HUB, night 01)

**Use this file.** It replaces `../tea_table_set_v2/tea_table_set_v2.glb` (the file `hub_assets.gd` preloads today) and the unreleased
`../tea_table_set_v3/`. Both stay on disk as backups.

- Swap: change the path string only (also in the `hub_assets.gd` preload table). Same root name pattern, the same 8 child nodes
  (`table`, `teapot`, `cup_a`, `saucer_a`, `cup_b`, `saucer_b`, `scone_1`, `scone_2`) with the same node origins as v2, so physics
  and placement code keep working. Footprint 1.18 (x) x 0.70 (H) x 1.16 (z) m, root at the base centre, y = 0, facing glTF +Z.
- 14,710 triangles in total (table 9,036). Materials: the shared Tripo atlas (teapot, cups, saucers, scones) and `tea_disc_wood`
  (1k planar walnut grain, roughness 0.62) on the whole table. No vertex colours. Nothing in the set goes below the floor: lowest
  point at y = +0.001 (the top's rim); two pad feet rest on the floor.
- Collision: unchanged from v2 (static box 1.0 x 0.5 x 1.0 at y 0.25, or a convex hull per piece; keep the teapot frozen until hit).

## What changed since v2 (rounds 3 and 4, no paid calls)

- Top disc (r3): own `tea_disc_wood` material with a straight, unstretched planar grain (the r1c disc used a stretched atlas patch).
- Base (r4, `assets_src/topup/hub/tools/tea_r4.py`): the r3 lathe had followed the Tripo pedestal's own axis (17 degrees off the disc
  normal, 8 cm off-centre) and produced a plain cylinder with flat caps and sausage feet. r4 rebuilds the whole base in the table's
  own frame (disc centre and normal from PCA, height from the old feet): one 40-segment turned column with a designed baluster
  profile (drop finial, urn where the legs spring, neck ring, slender shaft, vase, ring, collar block into the top) and three
  cabriole snake legs at 120 degrees (20-sided swept tubes tapering 31 to 15 mm, turned pad feet). The leg phase is searched so no
  foot goes through the floor and the lowest pads rest on it. Grain runs along the turning axis and along each leg.
- Report and blend: `assets_src/topup/hub/tea_table_set/r4_fix/work/`; Blender renders `assets_src/topup/hub/tea_table_set/r4_fix/r4_*.png`.
  Native before/after (v2 vs v4): `Docs/progress/topup_hub/*__r4fix_Tea_*`.

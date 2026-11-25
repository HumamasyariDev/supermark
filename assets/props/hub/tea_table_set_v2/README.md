# tea_table_set_v2 (Tripo P2, TOPUP_HUB, night 01)

Replacement for `../tea_table_set/tea_table_set.glb` (procedural, kept). **Use this one.**

- Footprint about 1.20 (x) x 0.72 (H) x 1.13 (z) m. Root origin at the base centre, y = 0. Facing glTF +Z (teapot and cups in front,
  the knocked-over table behind them).
- Nodes: root `tea_table_set_v2` > 8 loose pieces, each with its origin at its own bounding-box centre (ready for RigidBody3D):

| node | centre (x, y, z) m | size (x, y, z) m | tris |
| --- | --- | --- | --- |
| `table` (top on its edge, pedestal, three feet) | (0.148, 0.362, -0.230) | 0.90 x 0.72 x 0.67 | 2,520 |
| `teapot` (lying on its side) | (-0.164, 0.176, 0.276) | 0.44 x 0.34 x 0.37 | 2,126 |
| `cup_a` (upright) | (0.132, 0.134, 0.411) | 0.22 x 0.22 x 0.24 | 878 |
| `saucer_a` | (0.123, 0.033, 0.421) | 0.29 x 0.03 x 0.29 | 305 |
| `cup_b` (tipped over) | (-0.469, 0.110, 0.041) | 0.26 x 0.16 x 0.21 | 870 |
| `saucer_b` | (-0.448, 0.034, 0.040) | 0.29 x 0.03 x 0.29 | 304 |
| `scone_1` | (0.389, 0.081, 0.371) | 0.20 x 0.12 x 0.20 | 604 |
| `scone_2` | (0.219, 0.081, 0.191) | 0.20 x 0.12 x 0.20 | 587 |

- 8,194 triangles in total, one shared 2k PBR material. A stray flat board that Tripo generated through the table legs was removed.
- Fix round 1 (critic r1): the root is named exactly `tea_table_set_v2` (was `tea_table_set_v2.006`); the table pedestal and feet are
  smoothed (volume-preserving Laplacian, 6 passes); the teapot base is relaxed; the table wood roughness is at least 0.6 (the 'white
  smear streaks' on the top were sun specular on 0.35-roughness wood, not paint in the albedo). Tool: `assets_src/topup/hub/tools/tea_fix.py`.
- Physics: in a RigidBody drop test (convex hulls) every piece settles within 3.2 cm, except the teapot, which rolls 5 cm and 17 degrees
  (was 8.5 cm and 31 degrees) because it lies on its rounded side. **Keep the teapot frozen (RigidBody3D `freeze = true`) until the
  player hits it**, or spawn it already settled.
- Collision: static use: one `BoxShape3D` 1.0 x 0.5 x 1.0 at y 0.25 (as the hub does now). Physics use: a convex hull or box per piece.
- Paw prints are not included (decal).
- Fix round r1c (critic r1b): the jagged Tripo top is replaced by a clean 64-segment lathe disc with a rounded rim (plane fitted from the
  flat faces, R 0.367 m, 2.1 cm slab; 243 old top faces deleted, including the thicker lumpy rim band), planar-mapped into the largest
  clean-wood square of the albedo (no trim texels); the turned column (top 20 cm) is snapped to a surface of revolution; table wood
  roughness floor 0.7. Tool: `assets_src/topup/hub/tools/tea_fix_r1b.py` (input `assets_src/topup/hub/tea_table_set/r1b_before/`).
  Captures (native, hub light): `Docs/progress/topup_hub/20261017T231108Z__r1fix_Macro_tea_tabletop*.png`, `__r1fix_Tea_*`. Open: the lower
  pedestal and the three feet are still the faceted Tripo shapes.

# grandfather_clock_v3 (TOPUP_HUB round 3, accepted in round 4, night 01)

**Use this file.** It replaces `../grandfather_clock_v2/grandfather_clock_v2.glb` (the file `hub_assets.gd` preloads today), which
stays on disk as a backup.

- Swap: change the path string only (also in the `hub_assets.gd` preload table). Same node hierarchy and names as v2 (`clock_body`,
  `pendulum`, `hand_hour`, `hand_minute`, ... with the same pivots), so `hub_clock.gd` keeps driving the hands and pendulum.
  0.73 (W) x 2.41 (H) x 0.43 (D) m (1 cm taller than v2 because of the centre finial; 2 cm shallower because the back is flat now),
  origin at the base centre, y = 0, dial facing glTF +Z.
- 11,756 triangles, materials as v2 (Tripo atlas, `clock_gold`, `clock_bob_gold`, `clock_dial_enamel`). No vertex colours.

## Round 3 fixes (critic r2 major, no paid calls; `assets_src/topup/hub/tools/clock_r3.py`)

- Warped hood back and plinth back: the barrel-shaped sides and backs are straightened onto clean planes (hood |x| 0.300, plinth
  |x| 0.305, backs y 0.200 / 0.199; 256 vertices). The old custom split normals of the bulging shape, which made the flat back shade
  wavy, are cleared and the case is shaded smooth by angle, so flat panels read flat and mouldings keep crisp edges.
- Lumpy swan-neck finial: the crest (928 faces) is deleted, a beveled top board covers the cornice, and three lathe-turned brass
  finials (ball and spire on an urn, 32 segments) stand on it: 0.16 m in the centre and 0.10 m at the two front corners.
- Verified in round 4: Blender renders `assets_src/topup/hub/grandfather_clock/r3_fix/`, native Godot captures (v2 vs v3)
  `Docs/progress/topup_hub/*__r4fix_Clock_*` (back three-quarter low, finial close-up, full front at 10:10).

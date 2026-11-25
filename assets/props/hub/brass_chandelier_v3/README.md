# brass_chandelier_v3 (TOPUP_HUB round 3, accepted in round 4, night 01)

**Use this file.** It replaces `../brass_chandelier_v2/brass_chandelier_v2.glb` (the file `hub_assets.gd` preloads today), which
stays on disk as a backup.

- Swap: change the path string only (also in the `hub_assets.gd` preload table). Same hierarchy as v2: root (y 0) > `sway_pivot`
  (ceiling cap, y 2.21) > `chandelier_mesh` + `candle_0` to `candle_7` at the same wick-tip positions, so the flame VFX and the sway
  code are unchanged. Size 3.16 x 2.22 x 3.16 m (the rebuilt cups dip 9 mm below y 0); keep the hub's `scl` and chain maths as
  tuned for v2.
- 23,030 triangles (v2 12,144: the rebuilt arms and cups are smooth swept/lathe geometry). Materials as v2 (Tripo atlas and
  `chandelier_ring_brass`). No vertex colours.

## Round 3 fixes (critic r2 minor, no paid calls; `assets_src/topup/hub/tools/chandelier_r3.py`)

- Ring seam at the front arm: the leftover band of the old Tripo ring (a 172-face island hugging the rebuilt torus) is deleted.
- Lumpy S-arms: the eight U-shaped arms are rebuilt as clean 20-sided swept tubes along their own smoothed centrelines
  (radius 66-67 mm), in the brass material.
- Open cup fins: the eight drip cups are rebuilt as closed 48-segment lathe cups (stem, bowl, rolled rim, inner floor).
- Verified in round 4: Blender renders `assets_src/topup/hub/brass_chandelier/r3_fix/`, native Godot captures (v2 vs v3)
  `Docs/progress/topup_hub/*__r4fix_Chandelier_*` (from the floor at scl 1.75, arm close-up).

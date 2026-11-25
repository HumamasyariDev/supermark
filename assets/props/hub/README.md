# Hub props (Mak Manor Grand Library)

Owner: meshes-hub workstream (night 01). All GLBs: metres, Y up, model front = glTF +Z
(wrap in a `Visual` Node3D rotated 180 degrees about Y so it faces Godot -Z), origin at the base centre, bottom at y = 0.
Studio renders: `Docs/progress/assets/hub/<id>_studio_q34.webp`. Provenance: `data/asset_register.csv`, `Docs/LICENSES.md`.

| id | Size (W x D x H m) | Tris | Source | Nodes and notes |
| --- | --- | --- | --- | --- |
| bookshelf_tall | 2.32 x 1.07 x 4.00 | 5,069 | Tripo P2 | One mesh. Slightly curved front; tile it around the round hall. Back is a closed plain panel. |
| book_lectern | 1.76 x 1.32 x 2.60 | 9,799 | Tripo P2 | One mesh. Pages are plain: put the per-world pop-up diorama and the gold glow plane on the open pages at the top (measure the spot in the scene). |
| fireplace | 2.72 x 1.51 x 3.00 | 5,880 | Tripo P2 | One mesh. Firebox open with a dark back for the VFX fire. |
| wolf_door | 2.06 x 0.76 x 3.20 | 9,985 | Tripo P2 | `door_frame` > `door_leaf` > `knocker_ring`. door_leaf pivot is on the hinge edge at the floor (the viewer's left from the front); rotate it about local Y to open. knocker_ring pivot is at the top of the ring; swing it about local X. Hinge knuckles are part of the frame. |
| rolling_ladder | 1.44 x 1.28 x 5.00 | 4,796 | Procedural | One mesh. Leans 9 degrees: the top tilts toward the model's back (away from its front), so set it against a shelf with the front facing the player; the brass hooks curl back over a rail near the top. Climb area: add your own Area3D in group `climbable`. |
| brass_chandelier | 2.16 x 2.16 x 2.21 | 9,464 | Procedural | `brass_chandelier_root` (y 0) > `sway_pivot` (y 2.21, the ceiling cap) > mesh. Rotate `sway_pivot` for a gentle sway. Place the root so the cap meets the ceiling. The 8 candle tips sit about 1.2 m above the root (about 1.0 m below the cap) for flame VFX. |
| wingback_armchair | 1.14 x 0.80 x 1.40 | 8,032 | Procedural | One mesh. |
| tea_table_set | 1.15 x 1.20 x 0.83 | 8,016 | Procedural | Root `tea_table_set` > `table`, `teapot`, `cup_a`, `cup_b`, `saucer_a`, `saucer_b`, `cake_stand`, `scone_1`..`scone_5`; each piece has its own centred origin for RigidBody3D use. Paw prints are a decal (not included). |
| library_globe | 0.88 x 0.85 x 1.40 | 6,452 | Procedural | `library_globe` > `globe_stand`, `globe_axis` (tilted 20 degrees) > `globe_sphere`. Spin `globe_sphere` about its local Y. |
| grandfather_clock | 1.07 x 0.66 x 2.40 | 9,884 | Procedural | `grandfather_clock` > `clock_body`, `clock_glass` (alpha blended), `pendulum` (pivot at its top). Swing the pendulum about its local Z, at most about 12 degrees, or the bob touches the left weight. |

Godot extracts the embedded textures of the Tripo assets next to each GLB on import (`*_Color_*`, `*_NormalGL_*`, `*_ORM_*`). Keep them.
Collision: none is embedded. Author simple box or convex colliders in the hub scene.

## Top-up "use this file" list (TOPUP_HUB round 4, ASSETS3_HUB, 2026-10-18 Bangkok)

| Prop | Use this file | Replaces (kept as backup) | Swap |
| --- | --- | --- | --- |
| Wingback armchair | `wingback_armchair_v4/wingback_armchair_v4.glb` | `wingback_armchair_v2` (loaded by `hub_assets.gd`, `wolf_rooftop.gd`), `wingback_armchair_v3` | path only |
| Tea table set | `tea_table_set_v4/tea_table_set_v4.glb` | `tea_table_set_v2` (preloaded by `hub_assets.gd`), `tea_table_set_v3` | path only, same 8 nodes |
| Grandfather clock | `grandfather_clock_v3/grandfather_clock_v3.glb` | `grandfather_clock_v2` (preloaded by `hub_assets.gd`) | path only, same nodes and pivots |
| Brass chandelier | `brass_chandelier_v3/brass_chandelier_v3.glb` | `brass_chandelier_v2` (preloaded by `hub_assets.gd`) | path only, same nodes and candle markers |

Each folder's README lists the fixes and evidence. Native verification stage: `_topup_v4_fix_r4/TopupFixR4.tscn` (test only).

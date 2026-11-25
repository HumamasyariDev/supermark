# World 1 props (meshes-w1, night 01)

All GLBs: metres, Y up, origin at the base centre with the bottom at y = 0, model front facing **+Z**
(wrap in a `Visual` Node3D rotated 180 degrees about Y if the scene expects -Z). Sizes follow
`Docs/levels/W1.md` / `W1_assets.md` where the level fixes them; collision stays the builder's boxes.
Previews: `Docs/progress/assets/w1/` (studio renders) and a native lineup scene
`res://assets/props/w1/_preview/w1_props_preview.tscn` (capture only, not a level).

| Asset | Size (m, x × y × z) | Tris | Source | Nodes and sockets |
| --- | --- | --- | --- | --- |
| `windmill_body` | 8.0 × 16.0 × 8.5 | 9.1k | Tripo P2 | `hub_socket` at (−0.02, 12.88, 3.26): put `windmill_sails` there (W1.md hub is 13.5 up, 3.0 forward; offset or scale to taste) |
| `windmill_sails` | radius 9.0, 2.3 deep | 10.1k | procedural | origin = hub pivot; spin about local **Z**; visual only (sail steps carry collision) |
| `brick_house` | 9.7 × 10.4 × 7.0 (body 9 × 9 × 7) | 9.6k | Tripo P2 | its own chimney is kept on the east (+X) gable; see the shaft below |
| `brick_chimney_shaft` | 4.0 × 15.0 × 3.7 (stack 3.6 × 14 × 3.2) | 2.4k | procedural | place at **+6.3 m x** from the house origin (stack centre (11.3, 12, −36)), unrotated. Inner 3.0 × 2.6 m open shaft, soot door 1.6 × 1.9 m on the east face, soot ledge top 7.0 m on the south (+Z) inner wall |
| `straw_house` | 8.1 × 6.3 × 7.5 | 7.7k | Tripo P2 | thatch overhang wider than the 7 × 6 wall line |
| `stick_house` | 5.8 × 5.2 × 5.8 | 9.0k | Tripo v2.5 | stick ladders on both long sides |
| `bellows_machine` | 3.2 × 3.2 × 4.0 | 6.0k | Tripo v2.5 | `body`; `paddle` (origin at the front-low hinge (0, 1.50, 0.46), rotate about local X to pump, about −10 to +10 degrees); `nozzle_socket` at (−0.01, 1.66, 2.0), gusts blow along +Z |
| `stone_bridge` | 4.9 × 2.95 × 8.0 | 5.0k | Tripo v2.5 | spans along Z; rotate 90 degrees for an east-west stream crossing |
| `wishing_well` | 2.7 × 3.2 × 2.3 | 4.0k | Tripo v2.5 | |
| `apple_tree` | 4.9 × 5.7 × 4.6 | 4.9k | procedural | `trunk`, `canopy` (apples included) for a sway shader |
| `birch_tree` | 3.6 × 10.0 × 3.3 | 5.4k | procedural | `trunk`, `canopy`; scale 0.9–1.2 and tint for variants |
| `hay_bale` | 1.6 × 1.1 × 1.2 | 2.6k | procedural | |
| `signpost` | 1.8 × 2.4 × 0.8 | 3.4k | procedural | boards are blank for decals |

Godot notes: the procedural props carry baked albedo textures (Godot ignores glTF vertex colours by default).
The Tripo meshes have 1k–2k colour, normal and ORM maps; the v2.5 ones had their roughness floor raised so stone
and leather do not look like plastic.

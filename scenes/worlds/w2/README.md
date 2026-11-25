# W2 Beanstalk Skyway (Jack and the Beanstalk)

Owner: W2 world builder. Scene: `res://scenes/worlds/w2/W2.tscn` (root `w2_world.gd`, extends `WorldRoot`).

## How it is built

`W2.tscn` holds only the contract nodes (WorldEnvironment, Sun, `Spawns/`, `StoryCams/`). It is written by
`game/assets/environment/w2/tools/w2_gen_scene.py`, which also copies `data/levels/W2.json` (plan + round 1 and 2
amendments) to `res://assets/environment/w2/w2_level.json`. Re-run it after the level JSON changes:

    python game/assets/environment/w2/tools/w2_gen_scene.py

At load time (about 3.5 s) the root builds everything deterministically from that JSON:

| Script | Builds |
| --- | --- |
| `scripts/worlds/w2_build.gd` | island heightfield + underside + roots, the three-strand beanstalk (capsule collision stops at y 62.5), leaves (generated `giant_leaf*.glb`), cloud decks and layers (sightline cones kept clear), Allotment, cottage, garden, castle, kitchen, belfry, round 1/2 structures (K1, CC1, gatehouse, screens, boot, fork), backdrop (generated keep and far islet) |
| `scripts/worlds/w2_play.gd` | checkpoints, truffles and mission logic, switches + cage, tea cosy, lost pages, acorns, vines, puff clouds, enemies, wind zones, lifts, Pip, signs, Captain Caw, bluebell bud, Reginald cameo, dev markers |
| `scripts/worlds/w2_descent.gd` | round 3 seed-parachute descent after W2-8 (12 s Catmull-Rom path from the flower to the Default spawn, chase camera, toasts; the player is carried with physics and collision off; jump skips after 1.5 s) |
| `scripts/worlds/w2_life.gd` | lifts, droopy/swaying/swinging leaves, the bell pendulum, the Giant's breath cycle, sneeze, sleep-talk, goose gag, magic bean, colour script by height, goal beacon, blob shadow, intro camera, birds, banners, self-tests |
| `scripts/worlds/w2_wind.gd` | wind zones (snore cycle with lee boxes; gusting crosswind) |
| `scripts/worlds/w2_caw.gd` | Captain Caw (W2-4) on the real `crow_bandit.glb` |
| `scripts/worlds/w2_target.gd` | hittable Area3D (layer 7) for the tea cosy and the bluebell bud |
| `scripts/worlds/w2_mesh.gd` | vertex-coloured procedural mesh batch (sRGB colours converted to linear) |

## Dev arguments

- `--spawn=<marker>`: contract markers plus `dev_W2-1..8`, `dev_W2-100`, `dev_castle`, `dev_kitchen`, `dev_allot`, `dev_sunleaf`, `dev_slot`.
- `--w2-selftest=<truffle id>`: drives a mission's logic (switches, wolf, cosy, pages, poppers, rings, Caw, acorns) and places Mak on the reward; prints `[W2] TRUFFLE COLLECTED`.
- `--w2-descent`: starts the seed descent 2 s after load (capture aid).
- `--w2-fps=<seconds>`: logs mean and minimum fps, then quits. `--w2-nointro` skips the opening camera.
- Route replays: `python game/assets/environment/w2/tools/w2_route_tests.py [case ...]` (results in `Docs/progress/w2/route_tests/`).

## Tools

- `scripts/worlds/w2_tool_parse.gd` (`python tools/godot.py script res://scripts/worlds/w2_tool_parse.gd`): loads every W2 script and prints parse errors with file and line.
- `game/assets/environment/w2/tools/w2_evidence.py`: appends an evidence row.

## Character models

Every acting character is a generated GLB: Jack, Daisy, the Sleeping Giant, the Golden Goose, the wolf scarecrow, Sir Reginald (wolf_boss), Captain Caw and the
swallow loops (crow_bandit.glb; the swallows use it at 0.45 m until a swallow model exists), and the enemy scenes. Still requested: a rigged golden harp
(the current one is a static prop), swallow, butterfly and small ambient bee models, and a Tripo P2 bean-seed parachute (the descent uses a procedural canopy).

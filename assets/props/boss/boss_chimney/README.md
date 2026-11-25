# Boss brick chimney, intact (BOSS-M01)

TOPUP_WORLDS, night 01. Generated: Higgsfield `nano_banana_flash` reference, then fal Tripo P2, then Blender 5.1 cleanup (`assets_src/topup/worlds/`). Studio views: `Docs/progress/assets/topup/`. Godot captures: `Docs/progress/topup_worlds/`.

- **Size:** 2.52 x 5.4 x 2.55 m (W x H x D), 8.2k tris (landmark budget).
- Facing: glTF +Z (wrap in a `Visual` node rotated 180 degrees about Y so it faces Godot -Z, per TECH_CONTRACT). Origin: base centre, metres. Smooth shading, one PBR material, 2k textures embedded in the GLB (Godot extracts them next to it on import); no vertex colours. Visual only: no collision is embedded.
- **Bones:** none (rigid prop).

## Sockets (glTF coordinates, metres)

- `smoke_socket_a` at (0.13, 5.40, 0.38): top of the tall pot.
- `smoke_socket_b` at (-0.245, 5.05, -0.19): top of the short pot.

## Suggested collision

Box plinth 2.5 x 1.2 x 2.5 plus box stack 1.7 x 3.4 x 1.7 at this scale. For the current graybox (`BossChimney.size` 1.9 x 3.6 x 1.9) use a uniform scale of **0.7** and keep the existing box collider.

## Use

Replaces the box stack built in `game/scripts/boss/boss_chimney.gd`. Recipe: in `_ready()` instance this GLB under `_vis` instead of the `EnemyKit.box` calls (scale 0.7) and move the smoke particles to `smoke_socket_a`. In `smash()` hide it and show `boss_chimney_broken` at the same scale instead of the box pile. A working demo that leaves the boss files untouched: `_preview/topup_arena_swap.gd` + `_preview/TopupBossInArena.tscn`. For the four named variants in BOSS_amendments (Tall Tom, Squat Sid, Ivy, Old Crooked), rotate 0/90/180/270 degrees, lean C1 by 4 degrees, and scale C2 0.9 in Y and 1.1 in XZ.

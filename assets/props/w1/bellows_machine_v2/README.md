# Bellows machine v2 with wolf-head emblem (W1-M05). Use this instead of `bellows_machine`

TOPUP_WORLDS, night 01. Generated: Higgsfield `nano_banana_flash` reference, then fal Tripo P2, then Blender 5.1 cleanup (`assets_src/topup/worlds/`). Studio views: `Docs/progress/assets/topup/`. Godot captures: `Docs/progress/topup_worlds/`.

- **Size:** 2.83 x 3.2 x 4.4 m (W x H x D), 8.2k tris. Nozzle along +Z.
- Facing: glTF +Z (wrap in a `Visual` node rotated 180 degrees about Y so it faces Godot -Z, per TECH_CONTRACT). Origin: base centre, metres. Smooth shading, one PBR material, 2k textures embedded in the GLB (Godot extracts them next to it on import); no vertex colours. Visual only: no collision is embedded.
- **Bones:** none (rigid prop).

## Sockets (glTF coordinates, metres)

- `nozzle_socket` at (-0.10, 1.46, 2.18): mouth of the brass nozzle; gusts blow along +Z.
- `plate_socket` at (-0.13, 3.18, -0.45): centre of the top of the spring-mounted slam plate (the Ham Slam target).

## Suggested collision

Box body 2.4 x 2.2 x 3.6 centred at y 1.1, plus the builder's slam-plate box (about 1.3 m across) under `plate_socket`.

## Use

Replaces `bellows_machine` (v1 is kept unchanged). The wolf-head emblem plate (a grinning wolf with a monocle) is on the +X side, so place the machines with that side toward the player's approach. The plate, spring and paddle are fused (there is no `paddle` node as in v1); animate the pump by squashing the whole node in Y (0.94 to 1.0) or with a plate VFX. W1-4 busted state: `bellows_machine_v2_busted.glb` in this folder (same size, origin and texture; made by deforming v2 in Blender with `assets_src/topup/worlds/tools/make_busted.py`): the plate is knocked askew and 0.38 m lower, the bag sags, the nozzle droops 28 degrees. Its sockets moved with the deformation. Swap to it when that machine is Ham Slammed, with a smoke and stuffing VFX burst.

# Wolf's tea trolley (BOSS-M03)

TOPUP_WORLDS, night 01. Generated: Higgsfield `nano_banana_flash` reference, then fal Tripo P2, then Blender 5.1 cleanup (`assets_src/topup/worlds/`). Studio views: `Docs/progress/assets/topup/`. Godot captures: `Docs/progress/topup_worlds/`.

- **Size:** 1.15 x 1.1 x 0.85 m, 7.9k tris. Handle on +X.
- Facing: glTF +Z (wrap in a `Visual` node rotated 180 degrees about Y so it faces Godot -Z, per TECH_CONTRACT). Origin: base centre, metres. Smooth shading, one PBR material, 2k textures embedded in the GLB (Godot extracts them next to it on import); no vertex colours. Visual only: no collision is embedded.
- **Bones:** none (rigid prop).

## Sockets (glTF coordinates, metres)

- `teapot_socket` at (0.32, 0.72, 0.0): empty spot on the top tray for `boss/teapot` (use teapot scale 0.7 there).

## Suggested collision

One box 1.15 x 1.1 x 0.85. At the wolf's scale (3.2 m) scale the trolley by 1.25.

## Use

Replaces the `TeaTrolley` boxes in `wolf_rooftop.gd` (position (12.5, 0, 7.0), yaw 0.6). The cake stand, cups and sugar bowl are fused to the tray; the separate tea debris set (BOSS-M12) is still procedural. This is attempt a2; a1 was rejected for flat-sheet artefacts on the thin brass rails.

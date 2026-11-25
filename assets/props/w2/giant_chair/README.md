# Giant's carved kitchen chair (W2M16)

TOPUP_WORLDS, night 01. Generated: Higgsfield `nano_banana_flash` reference, then fal Tripo P2, then Blender 5.1 cleanup (`assets_src/topup/worlds/`). Studio views: `Docs/progress/assets/topup/`. Godot captures: `Docs/progress/topup_worlds/`.

- **Size:** 4.0 x 8.85 x 4.0 m, 5.9k tris. Seat front on +Z, back on -Z. Cushion top at 4.41 m.
- Facing: glTF +Z (wrap in a `Visual` node rotated 180 degrees about Y so it faces Godot -Z, per TECH_CONTRACT). Origin: base centre, metres. Smooth shading, one PBR material, 2k textures embedded in the GLB (Godot extracts them next to it on import); no vertex colours. Visual only: no collision is embedded.
- **Bones:** none (rigid prop).

## Sockets (glTF coordinates, metres)

None.

## Suggested collision

Box seat 4 x 0.6 x 4 with its top at 4.4; box back 4 x 4.4 x 0.6 on the -Z edge up to 8.85; four leg boxes 0.6 x 3.8 x 0.6.

## Use

Replaces the rounded boxes in `w2_build.gd` (seat x 2..6, z -36..-32, top 54.4 = 4.4 above the floor at 50.0; back on the +X edge): place it at (4, 50.0, -34) rotated -90 degrees about Y so the back goes to +X. The builder's back is 11 m tall; this chair's back stops at 8.85 m.

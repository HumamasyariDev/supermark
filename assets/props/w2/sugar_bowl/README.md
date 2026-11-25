# Giant rose-china sugar bowl (W2M10)

TOPUP_WORLDS, night 01. Generated: Higgsfield `nano_banana_flash` reference, then fal Tripo P2, then Blender 5.1 cleanup (`assets_src/topup/worlds/`). Studio views: `Docs/progress/assets/topup/`. Godot captures: `Docs/progress/topup_worlds/`.

- **Size:** 2.96 x 1.2 x 2.2 m (handles on X), 6.2k tris. Fitted non-uniformly to the SUGAR platform.
- Facing: glTF +Z (wrap in a `Visual` node rotated 180 degrees about Y so it faces Godot -Z, per TECH_CONTRACT). Origin: base centre, metres. Smooth shading, one PBR material, 2k textures embedded in the GLB (Godot extracts them next to it on import); no vertex colours. Visual only: no collision is embedded.
- **Bones:** none (rigid prop).

## Sockets (glTF coordinates, metres)

None.

## Suggested collision

Cylinder r 1.1, height 1.2 (the top of the sugar cubes is the SUGAR platform top, 1.2 m above the table).

## Use

Replaces the vertex-coloured cylinder in `w2_build.gd` (`SUGAR` at (-9.2, 56.8, -36.4), table top 55.6): place it at (x, 55.6, z) with no extra scale. Its roses are pink; the existing teacup has violet flowers.

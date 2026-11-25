# Signature birch tree v2 (W1-M10). Use this instead of `birch_tree`

TOPUP_WORLDS, night 01. Generated: Higgsfield `nano_banana_flash` reference, then fal Tripo P2, then Blender 5.1 cleanup (`assets_src/topup/worlds/`). Studio views: `Docs/progress/assets/topup/`. Godot captures: `Docs/progress/topup_worlds/`.

- **Size:** 4.19 x 10.0 x 4.5 m, 8.6k tris.
- Facing: glTF +Z (wrap in a `Visual` node rotated 180 degrees about Y so it faces Godot -Z, per TECH_CONTRACT). Origin: base centre, metres. Smooth shading, one PBR material, 2k textures embedded in the GLB (Godot extracts them next to it on import); no vertex colours. Visual only: no collision is embedded.
- **Bones:** none (rigid prop).

## Sockets (glTF coordinates, metres)

None.

## Suggested collision

Cylinder r 0.45, height 5 on the trunk (the canopy needs none).

## Use

Replaces the procedural `birch_tree` (v1 is kept). The trunk was thickened x1.6 in Blender for the chunky toy look. Variants: scale 0.9 to 1.2 and rotate; a canopy sway shader can use the vertex height above 5 m as its weight.

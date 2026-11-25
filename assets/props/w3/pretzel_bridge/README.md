# Pretzel bridge (W3-M05)

TOPUP_WORLDS, night 01. Generated: Higgsfield `nano_banana_flash` reference, then fal Tripo P2, then Blender 5.1 cleanup (`assets_src/topup/worlds/`). Studio views: `Docs/progress/assets/topup/`. Godot captures: `Docs/progress/topup_worlds/`.

- **Size:** 3.6 x 3.3 x 16.0 m, 10.6k tris (above the 8k landmark guide). Span along Z.
- Facing: glTF +Z (wrap in a `Visual` node rotated 180 degrees about Y so it faces Godot -Z, per TECH_CONTRACT). Origin: base centre, metres. Smooth shading, one PBR material, 2k textures embedded in the GLB (Godot extracts them next to it on import); no vertex colours. Visual only: no collision is embedded.
- **Bones:** none (rigid prop).

## Sockets (glTF coordinates, metres)

None.

## Suggested collision

Keep the builder's 8 deck boxes along the arc; the railings need thin boxes 0.15 wide and 0.9 high at X = +-1.65.

## Use

Replaces the tubes and boxes in `w3_level.gd` (`PretzelBridge`, ends top 1.3, apex top 2.4). It was fitted non-uniformly from an 8.1 m mesh, so the pretzel loops are about 1.45 times wider than tall. The base colour was hue-shifted to baked brown in Blender. Check the deck height against the builder's arc before shipping: the pier knots raise the deck ends.

# Gingerbread fort corner tower (W3-M04 kit)

TOPUP_WORLDS, night 01. Generated: Higgsfield `nano_banana_flash` reference, then fal Tripo P2, then Blender 5.1 cleanup (`assets_src/topup/worlds/`). Studio views: `Docs/progress/assets/topup/`. Godot captures: `Docs/progress/topup_worlds/`.

- **Size:** 4.3 x 7.6 x 3.95 m incl. the gumdrop ring, 7.7k tris. Door on +Z.
- Facing: glTF +Z (wrap in a `Visual` node rotated 180 degrees about Y so it faces Godot -Z, per TECH_CONTRACT). Origin: base centre, metres. Smooth shading, one PBR material, 2k textures embedded in the GLB (Godot extracts them next to it on import); no vertex colours. Visual only: no collision is embedded.
- **Bones:** none (rigid prop).

## Sockets (glTF coordinates, metres)

None.

## Suggested collision

Cylinder r 1.7, height 4.9 (wall) plus the builder's walkway box; the icing cone and pinwheel need none.

## Use

New prop for the Gingerbread Barracks (`w3_level.gd` `_build_fort`, walls x 37..55, z 36..50): one at each corner and one each side of the west gate. The crenellated top ring starts at about 4.9 m: measure before placing a walk collider. The kit's wall and gate modules stay procedural.

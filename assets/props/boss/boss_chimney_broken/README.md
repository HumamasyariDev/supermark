# Boss chimney, broken stump and rubble (BOSS-M02)

TOPUP_WORLDS, night 01. Generated: Higgsfield `nano_banana_flash` reference, then fal Tripo P2, then Blender 5.1 cleanup (`assets_src/topup/worlds/`). Studio views: `Docs/progress/assets/topup/`. Godot captures: `Docs/progress/topup_worlds/`.

- **Size:** 4.99 x 3.0 x 4.81 m footprint incl. rubble, 8.1k tris; the plinth matches the intact chimney at the same scale.
- Facing: glTF +Z (wrap in a `Visual` node rotated 180 degrees about Y so it faces Godot -Z, per TECH_CONTRACT). Origin: base centre, metres. Smooth shading, one PBR material, 2k textures embedded in the GLB (Godot extracts them next to it on import); no vertex colours. Visual only: no collision is embedded.
- **Bones:** none (rigid prop).

## Sockets (glTF coordinates, metres)

None.

## Suggested collision

Box plinth 2.5 x 1.2 x 2.5 plus box stump 1.7 x 1.8 x 1.7 (the rubble is decor, walkable without collision). At the graybox scale 0.7 the plinth is 1.75 wide and the stump top about 2.1 m.

## Use

Shown when a chimney is smashed in phase 2 (a stump still stops a charge per BOSS_amendments R1). Use the same scale as the intact chimney. Its reference was generated from the intact chimney's reference, so the materials match.

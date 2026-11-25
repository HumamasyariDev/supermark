# Plump silver teapot (BOSS-M13)

TOPUP_WORLDS, night 01. Generated: Higgsfield `nano_banana_flash` reference, then fal Tripo P2, then Blender 5.1 cleanup (`assets_src/topup/worlds/`). Studio views: `Docs/progress/assets/topup/`. Godot captures: `Docs/progress/topup_worlds/`.

- **Size:** 0.72 x 0.5 x 0.44 m, 4.1k tris. Spout toward -X, handle toward +X.
- Facing: glTF +Z (wrap in a `Visual` node rotated 180 degrees about Y so it faces Godot -Z, per TECH_CONTRACT). Origin: base centre, metres. Smooth shading, one PBR material, 2k textures embedded in the GLB (Godot extracts them next to it on import); no vertex colours. Visual only: no collision is embedded.
- **Bones:** none (rigid prop).

## Sockets (glTF coordinates, metres)

None. The pivot is the base centre; for a spinning lob projectile offset the mesh by -0.25 m in Y under a spin node.

## Suggested collision

Sphere r 0.28 (projectile), or none on the trolley.

## Use

The phase 2 teapot lob projectile and the trolley's pot. The base colour was recoloured to silver by luminance with metallic 1 and roughness 0.28-0.4, so it reflects the storm sky (it reads lilac in the arena). Scale 1.0 as a projectile, 0.7 on the trolley.

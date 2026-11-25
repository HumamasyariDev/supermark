# acorn_v2 (Tripo P2, TOPUP_HUB, night 01)

Replacement for the acorn stand-ins: `acorn.gd` currently builds a primitive placeholder when no `visual_scene` is set, and
`../acorn/acorn.glb` is the older procedural model (kept). **Use this one** as the acorn `visual_scene`.

- Size: 0.26 x 0.35 x 0.26 m (x, y, z). Origin at the base centre (the nut tip), bottom at y = 0. Upright: the generated mesh was tilted
  like its reference and was aligned to its principal axis in Blender.
- Facing: glTF +Z (the stem leans slightly to the viewer's right). It spins in play.
- Mesh: one closed manifold node `acorn_v2`, 4,102 triangles, one PBR material (2k WebP Color / ORM / NormalGL). Glossy caramel nut
  (roughness about 0.33), satin cap with chunky diamond scales in the geometry.
- Collision: `SphereShape3D` r 0.15 at y 0.17, or keep the existing r 0.45 pickup sphere.
- Many on screen: share one mesh (`ObjSvc.bake_visual` or a MultiMesh); 4.1k triangles each is fine for a few dozen.

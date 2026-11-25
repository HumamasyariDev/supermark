# golden_truffle_v2 (Tripo P2, TOPUP_HUB, night 01)

Replacement for `../golden_truffle/golden_truffle.glb` (procedural, kept). **Use this one.** Drop-in: same width (0.60 m) and conventions,
so `truffle.gd` can point `DEFAULT_MESH` at `res://assets/props/pickups/golden_truffle_v2/golden_truffle_v2.glb` and keep `DEFAULT_MESH_SCALE`.

- Size: 0.60 (x) x 0.67 (y, sprout included; the gold body is about 0.52 tall) x 0.65 (z) m. Origin at the base centre, bottom at y = 0.
- Facing: glTF +Z (the biggest round bump and the sprout's leaf pair face +Z). It spins in play, so facing hardly matters.
- Mesh: one node `golden_truffle_v2`, 11,999 triangles (fix round 1: one Catmull-Clark level then decimated, so the small bumps and
  plateaus read round; acceptable for the single hero pickup), one PBR material (2k Color / ORM / NormalGL, embedded WebP; Godot
  extracts them next to the GLB).
- Material: the gold body is metallic 1, roughness about 0.2, gold albedo graded toward #E8B030 (hue 42; was amber #F7AC2E); the
  sprout is a non-metal green. The eight four-point 'glints' were flat 6-triangle star islands floating on the surface (they read as
  olive stickers): deleted in fix round 1. Not emissive: the VFX supplies the glow and sparkles.
- Fix round 1 tools: `assets_src/topup/hub/tools/truffle_tex.py`, `truffle_fix.py`. Captures: `Docs/progress/topup_hub/20261017T231108Z__r1fix_Pickups_gameplay8m.png`, `__r1fix_Macro_truffle_face*.png`, `__r1fix_Truffle_top*.png`.
- Fix round r1b (critic r1b): the 8 deleted glint footprints are inpainted in Color and NormalGL (UV mask dilated, 139k texels) and the
  base mesh is relaxed around them and over the top lumps. Tool: `assets_src/topup/hub/tools/truffle_fix_r1b.py`, `truffle_inpaint.py`.
- Collision: `SphereShape3D` r 0.32 at y 0.30, or keep the existing r 0.45 pickup sphere.
- Sockets: none. Sources and scripts: `assets_src/topup/hub/golden_truffle/` and `assets_src/topup/hub/tools/`.

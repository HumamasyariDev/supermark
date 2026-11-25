# Real sheep (W1 C05, SH1-SH7)

Plain fluffy farm sheep: cream cloud-puff fleece, dark chocolate-brown face, ears and legs (recoloured from charcoal in the texture to match the W1 amendment), big friendly eyes, closed smile. Clearly not the Woolly Wolf costume.

## Files

- `real_sheep.glb`

Use: `res://assets/characters/real_sheep/real_sheep.glb`. Rigged: yes (7 bones). Triangles: 8,660.

## Size and facing

0.90 m tall, 0.99 m long, 0.74 m wide (W1 asks 0.9 tall, 1.2 long: scale Z by 1.2 only if the flock must match exactly).

Front renders and the native Godot capture confirm the face looks along glTF +Z.

## Bones and animation

Bones: root, body, head, leg_fl/fr/bl/br. Head and body regions were hand-claimed after bone heat (one ear island had been given to a leg). Tested: graze (head down 35 degrees), look (head turn), walk (diagonal leg swing 25 degrees). Bleat: head lift plus a squash on `body` (no jaw: the mouth is a closed surface). Faint: roll the whole node 180 degrees about Z with the legs stiff, then rotate the legs back up. Instances: give each a random yaw and a 0.9 to 1.05 uniform scale.

## Sockets

None.

## Suggested collision

CapsuleShape3D radius 0.36, height 0.99, lying along Z (rotate 90 degrees about X), centred at y 0.45.

## Conventions

- glTF faces **+Z**; wrap the instance in a `Visual` Node3D rotated 180 degrees about Y so it faces -Z like the body (TECH_CONTRACT).
- Origin at the base centre (between the feet / under the post / at the bottom of the bust). Real-world metres. Y up.
- Model space of the file: +X = the character's **left**, +Z = front. Bone `_l` / `_r` follow the character's own sides.
- One material (Tripo PBR: Color, NormalGL, ORM, 2048 px WebP, embedded). No vertex colours are used (stripped; Godot 4.7 ignores COLOR_0).
  ORM roughness floored at 0.45 so the toy finish reads as soft vinyl, not wet plastic. Smooth shading throughout.
- Skin: max 4 influences, normalised, no unweighted vertices. `root` is a non-deforming parent at the origin.
- The mesh is not watertight: use simple collision shapes, never the visual mesh.
- Look-dev scene (not gameplay): `res://assets/characters/_topup_preview/TopupLineup.tscn` (cameras `Cam_Lineup`, `Cam_Close`, `Cam_Foreman`, `Cam_Big`).
- Sources, rig specs and tests: `assets_src/topup/chars/` (tools in `tools/`, joint specs in `rigspecs/`, test poses in `<id>/work/rig_test.jpg`).

## Round 3 (2026-10-18, TOPUP_CHARS asset fixes): use `real_sheep_v2.glb`

Use this file: `res://assets/characters/real_sheep/real_sheep_v2.glb`. Size 0.894 W x 1.089 H x 1.195 D m, 8660 triangles.
Bones: root, body, head, leg_fl, leg_fr, leg_bl, leg_br.

- **Uniform scale 1.21** (critique: 0.99 m long, the disguised Woolly Wolf C06d needs 1.2 m). Now 1.195 m long, 1.09 m tall, 0.89 m wide. Bones and weights unchanged (scaled with the mesh). Scale any collision by 1.21.
- Every r3 file also carries a Cycles ambient-occlusion bake in ORM.R (self-occlusion, distance about 0.14 x height, strength 0.85, `assets_src/topup/chars/tools/fix_r3/bake_ao.py`) and a glTF occlusionTexture, so Godot 4.7 uses it as `ao_texture` (red channel). ORM.G keeps the round-2 per-zone roughness where it was applied. Textures are lossy WebP q92 (lossless WebP failed to import in Godot 4.7). The previous file is unchanged and stays usable; nothing was overwritten. AO mean (ORM.R) 0.745, roughness mean 0.881.
- Evidence: `Docs/progress/topup_chars/r3_fix/` (Blender renders and native Godot captures, before/after). Look-dev scene: `res://assets/characters/_topup_preview/TopupR3Check.tscn` (`-- --only=snap|scarecrow|cow|sheep|giant|lineup`).

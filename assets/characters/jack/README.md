# Jack (W2 C04)

Small cheerful boy of our own design: tufty bright red hair, green eyes, big freckles, patched brown coat with oversized cuffs and wooden buttons, long green knitted scarf, oatmeal trousers with a knee patch, brown boots, a wooden slingshot handle in his coat pocket.

## Files

- `jack.glb`

Use: `res://assets/characters/jack/jack.glb`. Rigged: yes (14 bones). Triangles: 10,356.

## Size and facing

1.50 m tall (W2 amendment size), 1.12 m wide in the A-pose.

Front renders and the native Godot capture confirm the face looks along glTF +Z.

## Bones and animation

Bones: root, hips, spine, head, arm_l/r, forearm_l/r, hand_l/r, thigh_l/r, shin_l/r. Voxel-proxy weights. Tested: arms up, run, crouch, head turn. Clips: caged sulk, freed cheer, talk idle, point.

## Sockets

Hands: `hand_l` / `hand_r` (pointing hint = hand_r forward). Slingshot: part of the mesh (pocket).

## Suggested collision

CapsuleShape3D radius 0.3, height 1.5, centred at y 0.75. JACK_CAGE (r 0.7, 1.6 tall) is a separate prop: Jack (1.5 m, 1.12 m arm span in the A-pose) fits standing once his arms are lowered to his sides.

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

## Round 3 (2026-10-18, TOPUP_CHARS asset fixes): use `jack_v2.glb`

Use this file: `res://assets/characters/jack/jack_v2.glb`. Size 1.119 W x 1.5 H x 0.515 D m, 10356 triangles.
Bones: root, hips, spine, head, arm_l, forearm_l, hand_l, arm_r, forearm_r, hand_r, thigh_l, shin_l, thigh_r, shin_r.

- AO-only update (no mesh or rig change).
- Every r3 file also carries a Cycles ambient-occlusion bake in ORM.R (self-occlusion, distance about 0.14 x height, strength 0.85, `assets_src/topup/chars/tools/fix_r3/bake_ao.py`) and a glTF occlusionTexture, so Godot 4.7 uses it as `ao_texture` (red channel). ORM.G keeps the round-2 per-zone roughness where it was applied. Textures are lossy WebP q92 (lossless WebP failed to import in Godot 4.7). The previous file is unchanged and stays usable; nothing was overwritten. AO mean (ORM.R) 0.728, roughness mean 0.739.
- Evidence: `Docs/progress/topup_chars/r3_fix/` (Blender renders and native Godot captures, before/after). Look-dev scene: `res://assets/characters/_topup_preview/TopupR3Check.tscn` (`-- --only=snap|scarecrow|cow|sheep|giant|lineup`).

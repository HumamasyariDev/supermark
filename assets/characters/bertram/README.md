# Bertram, the brick-house cousin (W1 C04)

Sensible eldest piglet cousin: brick-red flat cap, round wire spectacles, white shirt with rolled sleeves, mustard waistcoat, tan canvas builder's apron with a big pocket, brown boots. Generated as 'Bertie'; matches the W1 amendment description (flat cap, mustard waistcoat, rolled sleeves) except that the face is kind rather than smug and he holds no trowel (add a trowel prop to `hand` space via `forearm_r` if wanted).

## Files

- `bertram.glb`

Use: `res://assets/characters/bertram/bertram.glb`. Rigged: yes (15 bones). Triangles: 10,309.

## Size and facing

1.0 m tall (W1 amendment size), 0.81 m wide in the A-pose.

Front renders and the native Godot capture confirm the face looks along glTF +Z.

## Bones and animation

Bones: root, hips, spine, head, ear_l/r, arm_l/r, forearm_l/r, thigh_l/r, shin_l/r, tail. Voxel-proxy weights. Tested: arms up, run, crouch, head turn. The spectacles ride on the head bone. Clips: idle, talk, arms-folded smug (arms cross in front: about 70 degrees forward and inward), doorway lean.

## Sockets

Prop in the right hand: `BoneAttachment3D` on `forearm_r`, offset to the bone tail (about 0.11 m along the bone).

## Suggested collision

CapsuleShape3D radius 0.25, height 1.0, centred at y 0.5.

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

## Round 3 (2026-10-18, TOPUP_CHARS asset fixes): use `bertram_v2.glb`

Use this file: `res://assets/characters/bertram/bertram_v2.glb`. Size 0.806 W x 1.0 H x 0.499 D m, 10309 triangles.
Bones: root, hips, spine, head, ear_l, ear_r, arm_l, forearm_l, arm_r, forearm_r, thigh_l, shin_l, thigh_r, shin_r, tail.

- AO-only update (no mesh or rig change). W1 loads `bertram/bertram.glb` by name in `w1_level.gd::_npc`; switching needs the builder to point at this file.
- Every r3 file also carries a Cycles ambient-occlusion bake in ORM.R (self-occlusion, distance about 0.14 x height, strength 0.85, `assets_src/topup/chars/tools/fix_r3/bake_ao.py`) and a glTF occlusionTexture, so Godot 4.7 uses it as `ao_texture` (red channel). ORM.G keeps the round-2 per-zone roughness where it was applied. Textures are lossy WebP q92 (lossless WebP failed to import in Godot 4.7). The previous file is unchanged and stays usable; nothing was overwritten. AO mean (ORM.R) 0.702, roughness mean 0.734.
- Evidence: `Docs/progress/topup_chars/r3_fix/` (Blender renders and native Godot captures, before/after). Look-dev scene: `res://assets/characters/_topup_preview/TopupR3Check.tscn` (`-- --only=snap|scarecrow|cow|sheep|giant|lineup`).

# Hazel, the stick-house cousin (W1 C03)

Small freckled piglet cousin: moss-green knitted jumper with brown elbow patches, brown corduroy shorts with a diagonal satchel strap, green knitted bobble cap with an oak-leaf sprig. Same chibi family proportions as Pip and Bertram. The design was generated as 'Twig' before the W1 amendments named the character Hazel; it follows Hazel's role and palette (green, leaf, twig) but wears a knitted cap with a leaf sprig instead of a bandana and has no stick satchel.

## Files

- `hazel.glb`

Use: `res://assets/characters/hazel/hazel.glb`. Rigged: yes (15 bones). Triangles: 10,482.

## Size and facing

0.95 m tall (W1 amendment size), 0.76 m wide in the A-pose.

Front renders and the native Godot capture confirm the face looks along glTF +Z.

## Bones and animation

Bones: root, hips, spine, head, ear_l/r, arm_l/r, forearm_l/r, thigh_l/r, shin_l/r, tail (hero names). Bone heat weights, no fallback needed. Tested: arms up, run, crouch, head turn with ear flop. Clips: idle, talk, point up, cheer.

## Sockets

Head top for a prop (use `BoneAttachment3D` on `head`, offset about +0.33 m along the bone). Hands: none (pig hooves are part of the forearm bones).

## Suggested collision

CapsuleShape3D radius 0.24, height 0.95, centred at y 0.475.

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

## Round 3 (2026-10-18, TOPUP_CHARS asset fixes): use `hazel_v2.glb`

Use this file: `res://assets/characters/hazel/hazel_v2.glb`. Size 0.757 W x 0.95 H x 0.462 D m, 10482 triangles.
Bones: root, hips, spine, head, ear_l, ear_r, arm_l, forearm_l, arm_r, forearm_r, thigh_l, shin_l, thigh_r, shin_r, tail.

- AO-only update (no mesh or rig change). W1 loads `hazel/hazel.glb` by name in `w1_level.gd::_npc`; switching needs the builder to point at this file.
- Every r3 file also carries a Cycles ambient-occlusion bake in ORM.R (self-occlusion, distance about 0.14 x height, strength 0.85, `assets_src/topup/chars/tools/fix_r3/bake_ao.py`) and a glTF occlusionTexture, so Godot 4.7 uses it as `ao_texture` (red channel). ORM.G keeps the round-2 per-zone roughness where it was applied. Textures are lossy WebP q92 (lossless WebP failed to import in Godot 4.7). The previous file is unchanged and stays usable; nothing was overwritten. AO mean (ORM.R) 0.774, roughness mean 0.717.
- Evidence: `Docs/progress/topup_chars/r3_fix/` (Blender renders and native Godot captures, before/after). Look-dev scene: `res://assets/characters/_topup_preview/TopupR3Check.tscn` (`-- --only=snap|scarecrow|cow|sheep|giant|lineup`).

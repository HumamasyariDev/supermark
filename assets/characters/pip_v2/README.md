# Pip v2, rigged (W1 C02)

The existing cousin Pip mesh (`../pip/pip.glb`, Tripo P2, cheering pose) re-cleaned at the W1 amendment height and **rigged**. No new paid generation: the budget did not cover an A-pose regeneration. `pip/pip.glb` is untouched; use **pip_v2** wherever Pip must move.

## Files

- `pip_v2.glb`

Use: `res://assets/characters/pip_v2/pip_v2.glb`. Rigged: yes (14 bones). Triangles: 12,078.

## Size and facing

0.95 m tall including the raised hands, 0.79 m wide.

Front renders and the native Godot capture confirm the face looks along glTF +Z.

## Bones and animation

Bones: root, hips, spine, head, ear_l/r, arm_l/r, forearm_l/r, thigh_l/r, shin_l/r (no tail: the mesh has none visible). The rest pose is the cheer (arms raised in a V). The head region was given fully to `head` so the raised hands do not drag the cheeks. Limits: lower the arms at most about 60 degrees from rest (at 80+ degrees the cheek sides stretch slightly); wave = keep one arm up and swing the forearm. Clips: cheer (rest), wave, talk (head bob), 'house gone' stunned (arms half down, head tilt), hand-over (one arm forward 45 degrees).

## Sockets

None needed; head top on `head`.

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

## Round 3 (2026-10-18, TOPUP_CHARS asset fixes): use `pip_v3.glb`

Use this file: `res://assets/characters/pip_v2/pip_v3.glb`. Size 0.788 W x 0.95 H x 0.544 D m, 12078 triangles.
Bones: root, hips, spine, head, ear_l, ear_r, arm_l, forearm_l, arm_r, forearm_r, thigh_l, shin_l, thigh_r, shin_r.

- AO-only update of `pip_v2.glb` (no mesh or rig change), named `pip_v3.glb` as the next version. Mesh node names are unchanged (`pip_v2`, `pip_v2_rig`).
- Every r3 file also carries a Cycles ambient-occlusion bake in ORM.R (self-occlusion, distance about 0.14 x height, strength 0.85, `assets_src/topup/chars/tools/fix_r3/bake_ao.py`) and a glTF occlusionTexture, so Godot 4.7 uses it as `ao_texture` (red channel). ORM.G keeps the round-2 per-zone roughness where it was applied. Textures are lossy WebP q92 (lossless WebP failed to import in Godot 4.7). The previous file is unchanged and stays usable; nothing was overwritten. AO mean (ORM.R) 0.672, roughness mean 0.626.
- Evidence: `Docs/progress/topup_chars/r3_fix/` (Blender renders and native Godot captures, before/after). Look-dev scene: `res://assets/characters/_topup_preview/TopupR3Check.tscn` (`-- --only=snap|scarecrow|cow|sheep|giant|lineup`).

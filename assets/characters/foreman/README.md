# The Foreman (W1-7 mini-boss, W1 C08)

`foreman.glb`: big burly wolf henchman in a ram costume: lumpy grey-white fleece suit with stitched patches, fleece hood with big curly golden ram horns, slate-grey wolf face with an underbite and two lower fangs, leather work apron, brass whistle on a red cord, bushy tail. `foreman_underwear.glb`: the same wolf after the costume rips off: slate fur, cream chest and belly, baggy white underpants with red polka dots, the whistle. Two Tripo P2 generations; the second used the first reference as its image input, so face, build and pose match.

## Files

- `foreman.glb`
- `foreman_underwear.glb`

Use: `res://assets/characters/foreman/foreman.glb`. Rigged: yes (17 bones). Triangles: 13,209.

## Size and facing

1.90 m tall each; 1.80 m (costume) / 1.85 m (underwear) wide in the A-pose.

Front renders and the native Godot capture confirm the face looks along glTF +Z.

## Bones and animation

Both files share the **same bone names and hierarchy**: root, hips, spine, chest, head, arm_l/r, forearm_l/r, hand_l/r, thigh_l/r, shin_l/r, tail, tail_2. Joint positions are fitted to each mesh (the underwear wolf's shoulders sit about 7 cm higher), so clips retarget by name; keep animation on rotations (no bone translations except `hips`/`root`). The tail hangs beside the left leg, so the left leg weights were mirrored from the right leg (`tools/mirror_leg_weights.py`). Tested: arms up, run, crouch, head turn, each leg alone, tail flick. No jaw bone: the mouth is a closed sculpt and a test jaw bone opened no readable mouth and its bone-heat weights reached into the neck (rejected, render in `foreman/work/t_pose_roar.png`), so the roar is head-up + chest puff + VFX/SFX. Swap meshes for the 'flee in underwear' beat.

## Sockets

Whistle: part of the mesh (on the chest). Horn hit FX: the horns are on the head bone, about y 1.65-1.85.

## Suggested collision

CapsuleShape3D radius 0.55, height 1.9, centred at y 0.95 (horns outside). Charge hitbox: a box 1.6 x 1.2 x 1.0 m in front of the chest. Rump slam target (W1-7): box 0.9 x 0.5 x 0.6 at the back of the hips, about y 0.75.

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

## Round 3 (2026-10-18, TOPUP_CHARS asset fixes): use `foreman_v2.glb`

Use this file: `res://assets/characters/foreman/foreman_v2.glb`. Size 1.8 W x 1.9 H x 1.267 D m, 13209 triangles.
Bones: root, hips, spine, chest, head, arm_l, forearm_l, hand_l, arm_r, forearm_r, hand_r, tail, tail_2, thigh_l, shin_l, thigh_r, shin_r.

- AO-only update of `foreman.glb` (no mesh or rig change).
- Every r3 file also carries a Cycles ambient-occlusion bake in ORM.R (self-occlusion, distance about 0.14 x height, strength 0.85, `assets_src/topup/chars/tools/fix_r3/bake_ao.py`) and a glTF occlusionTexture, so Godot 4.7 uses it as `ao_texture` (red channel). ORM.G keeps the round-2 per-zone roughness where it was applied. Textures are lossy WebP q92 (lossless WebP failed to import in Godot 4.7). The previous file is unchanged and stays usable; nothing was overwritten. AO mean (ORM.R) 0.761, roughness mean 0.801.
- Evidence: `Docs/progress/topup_chars/r3_fix/` (Blender renders and native Godot captures, before/after). Look-dev scene: `res://assets/characters/_topup_preview/TopupR3Check.tscn` (`-- --only=snap|scarecrow|cow|sheep|giant|lineup`).

## Round 3 (2026-10-18, TOPUP_CHARS asset fixes): use `foreman_underwear_v2.glb`

Use this file: `res://assets/characters/foreman/foreman_underwear_v2.glb`. Size 1.849 W x 1.9 H x 1.412 D m, 13035 triangles.
Bones: root, hips, spine, chest, head, arm_l, forearm_l, hand_l, arm_r, forearm_r, hand_r, tail, tail_2, thigh_l, shin_l, thigh_r, shin_r.

- AO-only update of `foreman_underwear.glb` (no mesh or rig change).
- Every r3 file also carries a Cycles ambient-occlusion bake in ORM.R (self-occlusion, distance about 0.14 x height, strength 0.85, `assets_src/topup/chars/tools/fix_r3/bake_ao.py`) and a glTF occlusionTexture, so Godot 4.7 uses it as `ao_texture` (red channel). ORM.G keeps the round-2 per-zone roughness where it was applied. Textures are lossy WebP q92 (lossless WebP failed to import in Godot 4.7). The previous file is unchanged and stays usable; nothing was overwritten. AO mean (ORM.R) 0.837, roughness mean 0.727.
- Evidence: `Docs/progress/topup_chars/r3_fix/` (Blender renders and native Godot captures, before/after). Look-dev scene: `res://assets/characters/_topup_preview/TopupR3Check.tscn` (`-- --only=snap|scarecrow|cow|sheep|giant|lineup`).

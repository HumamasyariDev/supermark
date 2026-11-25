# Daisy the cow (W2 C05)

Round cuddly dairy cow: cream hide with rounded caramel-brown patches, pink muzzle, long lashes, short cream horns, a daisy behind her ear, red collar with a brass bell, pink udder, tail with a brown tuft. **Deviation:** the W2 amendment asks for black-and-white; a texture recolour to black was tried and rejected (ragged patch edges and a blackened bell, see `assets_src/topup/chars/daisy_cow/work/rc_*.png`), so the clean brown-and-white version ships. Her expression is content, not indignant.

## Files

- `daisy_cow.glb`

Use: `res://assets/characters/daisy_cow/daisy_cow.glb`. Rigged: yes (5 bones). Triangles: 9,120.

## Size and facing

1.60 m tall (horns included), 1.67 m long, 1.22 m wide (W2: 2.2 L x 1.6 H; she is chubbier and shorter in length than the brief).

Front renders and the native Godot capture confirm the face looks along glTF +Z.

## Bones and animation

Bones: root, body, head, tail, tail_2. Tested: graze (head down), head turn, tail flick (two-segment swing). Talk: small head nods and a squash on `head` (no jaw bone: the muzzle is closed).

## Sockets

Bell: on `head` near the collar (it is part of the mesh).

## Suggested collision

CapsuleShape3D radius 0.55, height 1.67, lying along Z, centred at y 0.75.

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

## Round 3 (2026-10-18, TOPUP_CHARS asset fixes): use `daisy_cow_v2.glb`

Use this file: `res://assets/characters/daisy_cow/daisy_cow_v2.glb`. Size 1.218 W x 1.6 H x 2.2 D m, 9120 triangles.
Bones: root, body, head, jaw, tail, tail_2.

- **Length 2.2 m (W2 brief 2.2 L x 1.6 H).** Depth scaled 1.2 everywhere plus a smooth extra stretch of the barrel between the front and hind legs (no kink; legs, head and udder keep their shape). Height unchanged at 1.60 m. Origin re-centred at the base centre. Suggested collision: CapsuleShape3D radius 0.55, height 2.2, lying along Z, centred at y 0.75.
- **New `jaw` bone** (child of `head`) for talk/moo/chew: the lower muzzle and chin are weighted to it with soft blends. Rotate about the model X axis by -5 to -12 degrees (negative opens); beyond about -15 the closed sculpted lip line shows stretching.
- Every r3 file also carries a Cycles ambient-occlusion bake in ORM.R (self-occlusion, distance about 0.14 x height, strength 0.85, `assets_src/topup/chars/tools/fix_r3/bake_ao.py`) and a glTF occlusionTexture, so Godot 4.7 uses it as `ao_texture` (red channel). ORM.G keeps the round-2 per-zone roughness where it was applied. Textures are lossy WebP q92 (lossless WebP failed to import in Godot 4.7). The previous file is unchanged and stays usable; nothing was overwritten. AO mean (ORM.R) 0.82, roughness mean 0.792.
- Evidence: `Docs/progress/topup_chars/r3_fix/` (Blender renders and native Godot captures, before/after). Look-dev scene: `res://assets/characters/_topup_preview/TopupR3Check.tscn` (`-- --only=snap|scarecrow|cow|sheep|giant|lineup`).

## Round 5 (2026-10-19, ASSETS3_CHARS): use `daisy_cow_v3.glb` (the mouth really opens)

Use this file: `res://assets/characters/daisy_cow/daisy_cow_v3.glb`. Same size (1.218 W x 1.6 H x 2.2 D m), origin, bones
(root, body, head, jaw, tail, tail_2) and AO/roughness as v2. 10,558 triangles, three surfaces: the skin, `daisy_mouth`
(dark maroon inward-facing mouth bag, single-sided) and `daisy_tongue`.

- **The jaw opens at POSITIVE angles about the model X axis** (skeleton space, the convention of `npc_life.gd::_rot` and the
  look-dev scenes): +12 is a talk, +20 a big moo, +28 the maximum before the chin meets the collar. Negative angles push the
  lower lip up into the muzzle; that is the "lip-line stretch past -15" reported in rounds 3 and 4. The `npc_life.gd` profile
  `"daisy_cow": {"jaw": -10.0}` therefore closes her mouth while she talks. For v3 use `"jaw": 16.0` (chew at 0.45 of it).
- What changed: the muzzle is cut along the lip line (z 0.884 m in Blender, 25 edges between the mouth corners at x +-0.18 m),
  each lip has a 2.6 cm inner wall, everything below the slit and in front of the cheeks rides `jaw`, the corners stay closed
  (soft r3 blend past them). Behind the slit sits a mouth bag (upper half `head`, lower half `jaw`) and a tongue on `jaw`.
  Closed (jaw 0) it looks like v2 with a fine lip line.
- AO re-baked on the cut skin (ORM.R mean 0.82), ORM.G keeps the round-2 roughness (0.79). Textures lossy WebP.
- Swap: in `scripts/objects/obj_svc.gd` `RIGGED_UPGRADES`, point both `daisy_cow.glb` and `daisy_cow_v2.glb` at `daisy_cow_v3.glb`.
- Evidence: `Docs/progress/topup_chars/r5_fix/` (`*__r5fix_cow_*`, Blender and native), Movie Maker
  `Recordings/night01/M3/20261018T171552Z__topup_chars_r5_cow_moo.mp4`. Look-dev: `_topup_preview/TopupR5Check.tscn -- --only=cow|cow_motion`.
- Tools: `assets_src/topup/chars/tools/fix_r5/fix_cow_r5.py` (slit, then mouth), AO with `fix_r3/bake_ao.py` in between.

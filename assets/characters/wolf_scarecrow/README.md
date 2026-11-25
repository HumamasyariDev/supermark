# Wolf-mask scarecrow (W2-6 talker, W2 C06)

Straw scarecrow on a wooden post and crossbar, patched burgundy tailcoat with long tails and a rope belt, a crude grey paper wolf mask with a painted grin and a monocle, a wide straw hat, two pairs of dented tin cans hanging from the arms, a mound of earth at the base.

## Files

- `wolf_scarecrow.glb`

Use: `res://assets/characters/wolf_scarecrow/wolf_scarecrow.glb`. Rigged: yes (8 bones). Triangles: 12,265 (r1c, 2026-10-18 06:10 Bangkok).

## Size and facing

4.65 m tall to the crown top, 3.8 m wide across the crossbar, hat brim 2.6 m across (W2 brief), brim top at y 4.30.

Front renders and the native Godot capture confirm the face looks along glTF +Z.

## Bones and animation

Bones: root (post base, mound **and the whole hat**: the hat is a static landing disc), body (everything above the post base: arm sway and crossbar flex), sleeve_l / sleeve_r (arms), can_l / can_r (cans swing from the string tops), head (mask only), jaw (**carries no vertices** since r1c: the paper jaw could not be cut cleanly from the 2,000-shell mesh, so it no longer tears).

Animate talk and the 'Reinforcements!' shout as a head bob plus body sway (the mask's painted grin stays closed). Because the hat stays on root, limit head yaw to 12 degrees and pitch to -8 degrees (more slides the mask out from under the crown). A mouth-texture swap (open/closed decal) is a future option.

r1c hat repair (`assets_src/topup/chars/tools/fix_r1c/fix_scarecrow_r1c.py` + `fix_scarecrow_r1c_band.py`): restarted from the r0 rig; the hat islands are levelled with one rigid rotation and scaled uniformly in X/Y about the crown axis to the 2.6 m brim (no per-island flattening); every post face above the brim plane inside the crown is deleted (no stub through the crown); the crown top is capped and a straw band closes the gap between crown and brim.

## Sockets

Hat top (for Lost Page P3): brim top y 4.30 (r 1.3), crown top y 4.65 (r about 0.5), crown axis x 0.0, z 0.10 in file space.

## Suggested collision

Post: CylinderShape3D radius 0.15, height 4.4. Hat ledge: the brim now matches the builder's r 1.3 disc at scale 1.0 (top y 4.30); add a cylinder r 0.5, height 0.35 for the crown on top.

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

## Round 3 (2026-10-18, TOPUP_CHARS asset fixes): use `wolf_scarecrow_v2.glb`

Use this file: `res://assets/characters/wolf_scarecrow/wolf_scarecrow_v2.glb`. Size 3.803 W x 4.702 H x 2.621 D m, 12582 triangles.
Bones: root, body, sleeve_l, can_l, sleeve_r, can_r, head, jaw.

- **Crown rebuilt (r2 major).** All old crown fragments, the r1c band and cap were deleted. A new closed lathed crown (r 0.585 m at the brim, domed top at 4.69 m, slight hand-made wobble) uses UVs borrowed from the brim's own straw texels (each crown face is mapped onto the brim annulus and validated against the straw colour), so it shows woven straw, not a flat texel.
- Brim: the square bites on the outer edge were closed (118 edge vertices pushed out to the local outline) and two holes next to the crown were filled. Seen from above (the W2 hat platform view) there is one clean brim and one crown.
- The whole hat (brim and crown) now rides the `head` bone instead of root, so a head nod or turn carries the hat. Keep the head limits from round 1 (yaw 12, pitch -8): at the brim edge a 12 degree yaw moves the rim visibly but the platform collision stays the builder's static box.
- Every r3 file also carries a Cycles ambient-occlusion bake in ORM.R (self-occlusion, distance about 0.14 x height, strength 0.85, `assets_src/topup/chars/tools/fix_r3/bake_ao.py`) and a glTF occlusionTexture, so Godot 4.7 uses it as `ao_texture` (red channel). ORM.G keeps the round-2 per-zone roughness where it was applied. Textures are lossy WebP q92 (lossless WebP failed to import in Godot 4.7). The previous file is unchanged and stays usable; nothing was overwritten. AO mean (ORM.R) 0.692, roughness mean 0.86.
- Evidence: `Docs/progress/topup_chars/r3_fix/` (Blender renders and native Godot captures, before/after). Look-dev scene: `res://assets/characters/_topup_preview/TopupR3Check.tscn` (`-- --only=snap|scarecrow|cow|sheep|giant|lineup`).

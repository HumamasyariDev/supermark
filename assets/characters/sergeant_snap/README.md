# Sergeant Snap (W3-2 mini-boss)

Big gingerbread sergeant of the Gingerbread Guard: tall red busby with plume, white icing moustache, gold epaulettes, white icing sash, three candy medals, gumdrop buttons, thick 3D biscuit body (0.64 m deep, not paper-thin).

## Files

- `sergeant_snap.glb`
- `snap_sabre.glb`
- `snap_lance.glb`
- `snap_mace.glb`
- `snap_drum.glb`

Use: `res://assets/characters/sergeant_snap/sergeant_snap.glb`. Rigged: yes (14 bones). Triangles: 12,311 (r1c, 2026-10-18 06:05 Bangkok).

## Size and facing

1.80 m tall (busby included, per the W3 amendment), 1.26 m wide in the A-pose, 0.69 m deep. Use at scale 1.0.

Front renders and the native Godot capture confirm the face looks along glTF +Z.

## Bones and animation

Bones: root, hips, spine, head, arm_l/r, forearm_l/r, hand_l/r, thigh_l/r, shin_l/r (grenadier family names plus the hero core). Arms (r1c, `assets_src/topup/chars/tools/fix_r1c/fix_snap_r1c.py`): each arm is a separate doll-joint shell split off the torso along a shoulder seam, both openings capped with gingerbread, 100 % arm/forearm/hand (no torso weight on the arm and no arm weight on the torso); epaulettes, fringe and cuffs ride rigidly on the arm; the arm pivot sits at the shoulder ball centre (|x| 0.38, y 0.87 in Godot space). Documented arm range: **+60 raised / -15 lowered** about the shoulder (+80 is clean too); author the sabre flourish with the forearm. Below -15 the epaulettes lift off the shoulder. Legs and spine keep bone-heat weights. A biscuit should bend stiffly: keep knee and elbow bends under about 50 degrees. The head bone carries the busby (hat wobble = head roll). Clips to author: drum idle, lance flourish (0.6 s tell), charge, stuck after a charge, stomp squash, defeat crumble.

## Sockets

Weapon: `BoneAttachment3D` on `hand_r` (the character's right, -X in the file). Both weapons have their origin at the grip centre with the blade/shaft along their own +Y; rotate them in the attachment so the blade points up and forward (the look-dev uses a global -40 degree X tilt). `snap_sabre.glb` (1.10 m, 3.9k tris, peppermint-striped curved blade, gold D-guard) matches the owner brief's candy-cane sabre; `snap_lance.glb` (2.31 m, 3.2k tris, a long candy cane with the crook at the grip end and a gold spike) matches W3.md's lance-charge wording. Use one per encounter. Added after the W3 amendment (R1.12): `snap_mace.glb` (2.08 m drum-major lance-mace, striped shaft, gold collar, big peppermint pinwheel knob; origin at the grip, +Y up) and `snap_drum.glb` (0.49 m parade snare drum, red shell, gold hoops and zig-zag cords, two drumsticks on top; origin at its centre, drum axis +Y). Wear the drum on `hips` at the character's left hip (look-dev offset (0.30, -0.05, 0.25) in model space, skin up, tilted 15 degrees toward the front, the way a parade snare hangs) or place it on the W3 parade-drum prop.

## Suggested collision

CapsuleShape3D radius 0.42, height 1.45, centred at y 0.73 (the busby above 1.45 m can stay outside the capsule). Stomp hurtbox: a box 0.9 x 0.25 x 0.6 on the busby/head top.

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

## Round 3 (2026-10-18, TOPUP_CHARS asset fixes): use `sergeant_snap_v2.glb`

Use this file: `res://assets/characters/sergeant_snap/sergeant_snap_v2.glb`. Size 1.884 W x 1.8 H x 0.694 D m, 12677 triangles.
Bones: root, hips, spine, head, arm_l, forearm_l, hand_l, arm_r, forearm_r, hand_r, thigh_l, shin_l, thigh_r, shin_r.

- **Rest pose changed (fixes the r2 arms-down blocker).** The old rest hung the arms about 25 degrees from vertical against the round belly, so any further lowering (critic -40, `npc_life` profile 55) drove the arm shells through the torso: epaulettes flipped into paddles, arm shards stuck out at the hips and the arms crossed the gold cord. In v2 the arm shells, cuffs and arm/forearm/hand bones are raised 50 degrees about the shoulder pivot, matching the cast convention (Pip 60, Bertram 62, Hazel 62, Jack 58 are all lowered by `npc_life`).
- Lowered by 40 to 55 degrees (about the model Z axis, the existing `npc_life` `arm_lower: 55.0` works unchanged) the arms rest against the belly with the epaulettes seated. Usable range: arm Z rotation from -60 (arms at the sides) to +40 (raised), plus forward swings (salute, march) about X.
- Epaulettes and fringe ride half way (geometry raised 25 degrees, skinned 50 % spine and 50 % arm), so they stay on the shoulder at every arm angle. The cord, sash and belts carry no arm weight.
- The flat r1c torso caps under the arms were rebuilt (poked, subdivided, projected onto the torso's own radius and relaxed) and the arm shell's inner flap that used to lie on the belly was removed and capped. Known limit: with the arms raised above +40 a slightly lumpy flank shows under the arm.
- Note for scripts that posed the old rest directly (no lowering): the v2 rest is arms half raised; lower the arms by about 50 degrees for the old look.
- Every r3 file also carries a Cycles ambient-occlusion bake in ORM.R (self-occlusion, distance about 0.14 x height, strength 0.85, `assets_src/topup/chars/tools/fix_r3/bake_ao.py`) and a glTF occlusionTexture, so Godot 4.7 uses it as `ao_texture` (red channel). ORM.G keeps the round-2 per-zone roughness where it was applied. Textures are lossy WebP q92 (lossless WebP failed to import in Godot 4.7). The previous file is unchanged and stays usable; nothing was overwritten. AO mean (ORM.R) 0.642, roughness mean 0.67.
- Evidence: `Docs/progress/topup_chars/r3_fix/` (Blender renders and native Godot captures, before/after). Look-dev scene: `res://assets/characters/_topup_preview/TopupR3Check.tscn` (`-- --only=snap|scarecrow|cow|sheep|giant|lineup`).

## Round 4 (2026-10-18, ASSETS3_CHARS): use `sergeant_snap_v3.glb` and the `_v2` props

Use this file: `res://assets/characters/sergeant_snap/sergeant_snap_v3.glb` (replaces v2; v1 and v2 are unchanged and still load).
Same bones, same rest pose and the same arm range as v2 (rest = arms half raised; lower `arm_l`/`arm_r` by about 50 degrees for the
idle, usable -60 to +40 about model Z, plus forward swings about X). 14,511 triangles (v2 12,677), 1.884 W x 1.80 H x 0.694 D m.

- **Shoulder ball joints (the flank / armpit shards).** The arm shells began inside the torso and ended in an open, stretched flap. At
  the v2 rest it lay on the chest as a flat triangle, and lowered or swung forward it showed as pale sawtooth shards at the flank and
  armpit. v3 cuts each shell at the shoulder pivot and adds a smooth ball (radius about 0.10 m), centred on the `arm_<s>` pivot and
  100 % on that bone. It looks the same at every arm angle, like a toy soldier's shoulder. It wears plain gingerbread texels from the
  upper arm.
- **Epaulettes on top of the balls.** Scaled 1.3 about the pivot and lifted 1.5 cm (still 50 % spine / 50 % arm), so the plate rests on
  the ball and the fringe hangs outside it. They are slightly bigger and read better from the gameplay camera.
- **Faceted flank under a raised arm fixed at the cause.** 586 faces (the r1c/r3 torso arm caps and a strip of the gold cord) mapped every
  corner to a single texel. With zero UV area the tangent frame is undefined, so the normal map bent each triangle a different way. They
  now have real UVs, projected into a plain gingerbread or gold patch whose baked AO is at least 0.62. Their custom normals are also
  recomputed from the current surface.
- **Sash fringe and smears.** The Tripo texture's blue-violet fringe around the white sash, and the white r1c repaint streaks on the
  flank, are refilled from the nearest texel of the same UV island (the colour stays inside its island). Afterwards 0 blue texels remain
  (before: 119,724, most of them in the margin). The cap texels' AO is lifted from 0.22 to 0.70.
- ORM: the r3 AO bake (ORM.R) and the r2 roughness (ORM.G) are kept. glTF occlusionTexture is wired, so Godot uses it as `ao_texture`.
  WebP q95 lossy.
- Hand sockets are unchanged: `hand_r` for weapons, `hips` for the drum (offset (0.30, -0.05, 0.25), as in v2). Scripts that lower
  the arms must aim the weapon from the **posed** hand basis, not the rest basis (see Round 3).
- Known limits: with an arm straight overhead, a few soft angular planes remain on the flank behind the arm. The ball is a visible
  round shoulder (on purpose), and from the front the shoulders read about 4 cm broader.

**Props `_v2` (material pass, polish):** `snap_lance_v2.glb`, `snap_sabre_v2.glb`, `snap_mace_v2.glb`, `snap_drum_v2.glb`. They have the
same meshes, textures and origins, and only the material factors change to match Snap's own ORM. His gold trim is painted gold (metal 0,
roughness 0.69), but the props had glTF-default chrome gold (metal 1.0, roughness 0.30) and 0.25-0.28 candy. Now candy is 0.40-0.42,
gold metal 0.45 / roughness 0.45, the drum shell 0.50, the drum skin 0.80 and the grip 0.75.

Tools: `assets_src/topup/chars/tools/fix_r4/` (`snap_tex_r4.py`, `fix_snap_r4_geo.py`, `fix_snap_r4_ball.py`,
`fix_snap_r4_normals.py`, `fix_snap_r4_capuv.py`, `fix_snap_r4_epaulette.py`, `export_rig_glb.py`, `glb_finalize_r4.py`,
`snap_props_r4.py`). Source blend: `assets_src/topup/chars/sergeant_snap/work/r4/sergeant_snap_rig_r4g.blend`.
Look-dev: `TopupR3Check.tscn -- --only=snap4|snap4_back|props4|motion4`. Evidence: `Docs/progress/topup_chars/r4_fix/`.

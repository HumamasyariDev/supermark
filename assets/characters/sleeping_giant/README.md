# The Sleeping Giant (W2-3, W2 C01)

Huge friendly giant, waist-up bust, fast asleep with both forearms folded flat in front of him: bushy ginger beard, round red nose, rosy cheeks, mouth open in a snoring O (real mouth interior), red-and-cream striped nightcap with a white pom-pom by his right ear, patched mustard waistcoat over a cream shirt.

## Files

- `sleeping_giant.glb`

Use: `res://assets/characters/sleeping_giant/sleeping_giant.glb`. Rigged: yes (7 bones). Triangles: 14,305.

## Size and facing

6.0 m tall bust, 6.6 m wide, 6.5 m deep (forearms reach 3.27 m in front of the origin). The base is the flat underside of the folded forearms: put the origin on the table top and the forearms rest on it. W2_assets asked 4.5 W x 6 H x 5 D with a 3.2 m head; a uniform scale of 0.77 to 0.85 fits the 5 m depth (head then about 2.3 m). The lower body is not modelled: hide the back edge behind the table or add a tablecloth.

Front renders and the native Godot capture confirm the face looks along glTF +Z.

## Bones and animation

Bones (analytic region weights, `assets_src/topup/chars/tools/rig_giant.py`): root (forearms, base), chest (shoulders/upper torso, breathing), head (head + beard; lift up to 0.5 m by translating the bone), jaw (lower lip and lower beard; the mouth already shows an open interior, 0-16 degrees opens it wider), nostrils (scale 1.0-1.35 for the inhale flare), cap_tip (nightcap tail and pom-pom bob), hand_l (the visible top hand, the character's left, for the twitch; the W2 brief said right hand, but the right hand is underneath). Tested: snore open (front and side), exhale slump, head roll, hand twitch with nostril flare, plus an in-engine procedural snore cycle (Movie Maker clip).

## Sockets

Snore wind source: the mouth front is at about (0, 3.36, +1.37) in file space (before the 180 degree Visual turn). Nose tip about (0, 4.15, +1.45).

## Suggested collision

Per W2.md: simple boxes. Head + beard box about 3.0 x 2.6 x 2.4 m centred at (0, 3.8, 0.9) in file space; forearms box 5.6 x 1.5 x 1.6 m at (0, 0.75, 2.4); torso box 6.0 x 3.4 x 3.6 m at (0, 2.0, -1.0).

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

## Round 3 (2026-10-18, TOPUP_CHARS asset fixes): use `sleeping_giant_v2.glb`

Use this file: `res://assets/characters/sleeping_giant/sleeping_giant_v2.glb`. Size 6.578 W x 6.0 H x 6.546 D m, 14305 triangles.
Bones: root, chest, head, jaw, cap_tip, nostrils, arms, hand_l, upperarm_l, upperarm_r.

- **Arm bones for the startle sit-up.** The folded forearms are one fused surface (the generator merged the crossed arms), so they cannot unfold separately without a new mesh. They are now one rigid block on `arms` (child of `chest`, pivot behind the forearms) instead of root: a chest sit-up lifts the folded arms off the table with the body, and `arms` can lift or tilt the block on its own (rotate about X up to -20, or translate up). The puffy sleeves get `upperarm_l` / `upperarm_r` (children of `chest`, rotate about the model Z axis up to 15 degrees for a startled shrug); the elbows blend into `arms`. `hand_l` (twitch) is re-parented to `arms`.
- **V-neck:** shirt and skin vertices in front of the chest (everything that is not beard) lost their head share, with the head weights relaxed over the neighbourhood, so a head lift slides the beard over the chest. A 0.45 m lift now shows a short strip instead of the long stretched V; thin creases remain at the beard's lower edge at that extreme, so keep lifts at or below 0.3 m in close shots.
- Bones: root, chest, head, jaw, cap_tip, nostrils, arms, hand_l, upperarm_l, upperarm_r.
- Every r3 file also carries a Cycles ambient-occlusion bake in ORM.R (self-occlusion, distance about 0.14 x height, strength 0.85, `assets_src/topup/chars/tools/fix_r3/bake_ao.py`) and a glTF occlusionTexture, so Godot 4.7 uses it as `ao_texture` (red channel). ORM.G keeps the round-2 per-zone roughness where it was applied. Textures are lossy WebP q92 (lossless WebP failed to import in Godot 4.7). The previous file is unchanged and stays usable; nothing was overwritten. AO mean (ORM.R) 0.759, roughness mean 0.803.
- Evidence: `Docs/progress/topup_chars/r3_fix/` (Blender renders and native Godot captures, before/after). Look-dev scene: `res://assets/characters/_topup_preview/TopupR3Check.tscn` (`-- --only=snap|scarecrow|cow|sheep|giant|lineup`).

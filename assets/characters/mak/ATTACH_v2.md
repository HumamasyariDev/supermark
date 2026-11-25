# Mr. Mak beanie v2 (TOPUP_HUB, night 01)

New files (nothing existing was overwritten):

| File | What |
| --- | --- |
| `mak_beanie_v2.glb` | Grey knitted watch-cap beanie from Tripo P2, fitted to Mr. Mak's head. 5,123 triangles, one 2k PBR material. **Use this one** instead of `mak_beanie.glb`. |
| `mak_v2.glb` | `mak.glb` (default outfit) with the beanie mesh swapped for v2. Same rig (checked in Godot: 27/27 bones, rest delta 1.3e-6) and the same node names (`mak_rig`, `mak_body`, `mak_beanie`, `mak_backpack`), so code that hides `mak_beanie` for the top hat still works. **Point the player and the title diorama at `mak_v2.glb`.** |

Attachment (same convention as the old beanie): origin at the centre of the cuff's lower rim, socket `head_top`,
offset (0, -0.1326, -0.0097), rotation (0, 0, 0). The `mak_beanie` entry in `attach.json` applies unchanged; see `ATTACH.md`.

- Size on the head: 0.54 m wide, 0.50 m deep, top at 1.25 m above the feet (inside the 1.25 m capsule). The rim rides about 2 cm
  higher at the front than at the back.
- Facing: glTF +Z like the body. The ears come out through the sides of the cuff by design (they are part of the head mesh).
- Fit: smoothed crown; every vertex kept at least 12 mm outside the head surface (ear faces excluded). The baked occlusion and the
  blotchy shading in the colour map were softened so the knit reads clean.
- Rib knit: 18 ribs on the dome (fading toward the crown) and 26 on the cuff, baked from a displaced high-poly copy into the 2k
  normal and colour maps. The game mesh itself stays 5,123 triangles.
- Collision: none (cosmetic). Bones: none (rigid on `head_top`).
- Fix round 1 (critic r1 asset QA), `assets_src/topup/hub/tools/beanie_fix_geo.py`, `beanie_fix_tex.py`, `beanie_fix_apply.py`:
  - Edge padding: the rib-bake maps had no padding (23 % pure-black background against the islands; 16,437 normal texels with
    blue < 150, 10,156 of them inside the islands). Every texel outside the UV islands now takes its nearest island texel, and the
    bad normal texels take their nearest valid neighbour (289 marginal texels remain), so no mip level bleeds black: the dark specks
    and the dark lip under the cuff are gone.
  - Colour: graded to the ART_V2 beanie grey #8E949B (outer knit mean now #8D949D; was #7E7E8A, which turned lavender under cool fill).
    Underside and inner faces lifted to at least 62 % of that value (dark grey knit, never black).
  - Ear relief: the cuff rim is raised up to 2 cm in a 4 cm wide notch above each ear root (y about -0.03), so moved ears show
    less cuff underside.
  - Rebuilt `mak_v2.glb` with `build_mak_v2.py` (same rig and node names). The two stale `*_Color_e089...`/`*_NormalGL_e089...`
    WebPs (no longer referenced) were removed from this folder.
- Known limits: the ear bones (`ear_l`, `ear_l_2`, `ear_r`, `ear_r_2`) of the shared rig also pull the brows, eyes and forehead
  (ear forward 55 degrees drops the brow line). That is a weight problem in `mak.glb`/`mak_body.glb` (meshes track): limit the ear
  weights to the ear geometry. A rigid beanie cannot follow a deforming forehead. The grey reads slightly warm under the hub's amber
  sun (as every grey does there).

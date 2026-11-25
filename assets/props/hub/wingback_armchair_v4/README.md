# wingback_armchair_v4 (TOPUP_HUB round 4, ASSETS3_HUB, night 01)

**Use this file.** It replaces `../wingback_armchair_v2/wingback_armchair_v2.glb` (the file the hub and `wolf_rooftop.gd` load today)
and the unreleased `../wingback_armchair_v3/`. Both stay on disk as backups.

- Swap: change the path string only. Same size, origin and facing as v2: 1.17 (W) x 1.41 (H) x 1.10 (D) m, origin at the base centre,
  feet at y = 0, seat facing glTF +Z (wrap in the usual `Visual` node rotated 180 degrees about Y to face Godot -Z).
- Mesh: one node, 15,241 triangles, three materials: the Tripo atlas (upholstery, 2k WebP Color/NormalGL/ORM), `velvet_cushion`
  (512 px tile for the rebuilt seat cushion and apron) and `walnut_legs` (256 px grain). Upholstery is double-sided, roughness at
  least 0.85, metallic 0. No vertex colours.

## What changed since v2 (rounds 3 and 4, no paid calls)

| Defect (critic r2) | Fix | Tool |
| --- | --- | --- |
| Crumpled seat-cushion front with dark tears | Cushion deleted and rebuilt as a beveled box with a crowned top and piped welts; the front apron is a lofted panel tucked into the arm fronts | `armchair_r3.py` |
| Scarlet velvet (about #C82828 under the key) | Atlas and cushion tile regraded to one burgundy hue (r3: 326; r4: 334, saturation x0.92) so the key-lit front and the fill-lit back both read burgundy | `armchair_r3.py`, `armchair_r4.py` |
| Lumpy back, wings and arm rolls | Taubin smoothing (volume preserving) on the tufted back, the wings and the arm rolls (r3), plus 12 extra passes on the arm scroll fronts (r4) | both |
| Grey-blue slivers at the wing/back and button junctions | Diagnosed natively (`diag_` captures in `../_topup_v4_fix_r4/`): they stayed with the normal map off and with culling on and vanished unshaded, so they were pleats in the Tripo shell, faces folded back on themselves. r4 welds the shell, Laplacian-relaxes every pleat neighbourhood (34 pleat faces to 3 zero-area slivers, collapsed) and drops the imported custom normals | `armchair_r4.py` |
| Flat orange legs (one 8 px texel patch) | Separate `walnut_legs` material with a cylindrical UV per leg (r2) | `armchair_legs_r2.py` |

Tools: `assets_src/topup/hub/tools/armchair_r4.py` (input `wingback_armchair_v3.glb`), report and blend in
`assets_src/topup/hub/wingback_armchair/r4_fix/work/`. Blender renders: `assets_src/topup/hub/wingback_armchair/r4_fix/blender_v3_v4.jpg`.
Native before/after (v2 vs v4): `Docs/progress/topup_hub/*__r4fix_Armchair_*`.

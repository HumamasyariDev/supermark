# Sugar bowl with a domed lid, v2 (W2 SUGAR). Use this instead of `sugar_bowl_lidded` (and instead of `sugar_bowl` plus the SugarLid sphere)

TOPUP_WORLDS fix pass r2 (night 01, critic round 2 major). Geometry, size, origin, sockets and conventions are identical to `../sugar_bowl_lidded/` (see its README). Made in Blender 5.1 by `assets_src/topup/worlds/tools/fix_r1/fix_sugar_lidded_r2.py` from `w2/sugar_bowl/sugar_bowl.glb` (report: `assets_src/topup/worlds/sugar_bowl/fix_r2/report.json`). No paid calls.

## What changed

Only the lid UVs. r1b borrowed per-face bowl-wall UVs, which gave a hard-edged rectangular rose patch, grey texel blocks on the dome, a beige strip on the rim band and smeared roses at the back. r2 maps the dome and the rim flange into the cleanest plain-glaze 24x24 block of the albedo (mean #FBEAE3, std 0.006) and the gold lip and knob into the best-matching gold block, each as one continuous cylindrical strip squeezed inside its block, so no island edge, seam or patterned texel can show. The lid now reads as plain white glaze with a gold lip line and a gold knob; the roses stay on the bowl.

## Use

Builder (w2_build.gd, SUGAR): `place_fit("sugar_bowl_lidded_v2/sugar_bowl_lidded_v2.glb", holder, Vector3(sgp.x, top, sgp.z), Vector3(3.3, 2.8, 3.3), 0.0, "SugarBowl")` (k 1.09, lid apex on the 58.0 dome collider top), then delete the `SugarLid` primitive (both spheres). The dome collider stays.

## Evidence

`Docs/progress/topup_worlds/fix_r2/20261017T231858Z__FixW2LidV2_LidCam.png`, `_LidBack.png`, and before/after pairs `__FixW2Lid_LidCam_before_after.png`, `__FixW2Lid_LidBack_before_after.png` (left r1b, right v2). Look-dev scene `game/assets/props/boss/_preview_v2/FixW2LidV2.tscn`.

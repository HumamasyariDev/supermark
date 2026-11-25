# Sugar bowl with a domed rose-garland lid, v3 (W2 SUGAR). Use this file; it replaces `sugar_bowl`, `sugar_bowl_lidded` and `sugar_bowl_lidded_v2` (and the SugarLid primitive)

TOPUP_WORLDS fix round 4 (ASSETS3_WORLDS, night 01, 11:40-12:00 Bangkok). Made in Blender 5.1 background mode from `w2/sugar_bowl_lidded_v2/sugar_bowl_lidded_v2.glb` with `assets_src/topup/worlds/tools/fix_r4/fix_sugar_lid_r4.py` (the bowl unwrap comes from `fix_r4/probe_sugar_unwrap.py`; report JSON, lid texture and Blender renders in `assets_src/topup/worlds/sugar_bowl/fix_r4/`). No paid calls. Geometry, size (2.96 x 2.565 x 2.2 m glTF, handles along X), origin and conventions are identical to v2; no vertex colours, no collision embedded, no bones. The older versions stay on disk as backups.

## What changed

The polish item left open since r2: the v2 lid was plain glaze and looked bare next to the rose-garland bowl. v3 gives the lid dome and rim flange their own small material (`SugarLidGlaze`) with a dedicated 2048 x 1024 texture:

- the bowl's own clean rose garland (its -Y half, theta 180-360 deg) unwrapped texel-exactly from the bowl wall, per triangle with barycentric (theta, z) to UV, so none of the r1b faults (rectangle edge, grey blocks, smears) can come back;
- the garland's cream background is re-balanced to the lid glaze (#FBEAE3) and only painted texels carry over, so there is no lighter box around the band; both ends fade into glaze, so it repeats twice around the lid without a seam;
- U = 2 x angle / 360 deg, V = arc length along the lid profile, about 676 px/m both ways (the same density as the bowl). The garland sits 0.17-0.55 m up the lid side, with a thin gold pinstripe at 0.59 m that echoes the bowl's gold rim line;
- roughness 0.255 and metallic 0 from the bowl glaze ORM (constant, no ORM texture on the lid material). The gold lip and knob keep the main material.

Godot imports the GLB as two surfaces (bowl + gold parts, lid glaze).

## Use

Builder (w2_build.gd, SUGAR): `place_fit("sugar_bowl_lidded_v3/sugar_bowl_lidded_v3.glb", holder, Vector3(sgp.x, top, sgp.z), Vector3(3.3, 2.8, 3.3), 0.0, "SugarBowl")` (k 1.09, lid apex on the 58.0 dome collider top), then delete the `SugarLid` primitive (both `lid.sphere(...)` lines and its `_mi(...)`). Keep the `_dome` collider. If the bowl is turned, keep the handles clear of the cloche.

## Evidence

Native (`Docs/progress/topup_worlds/fix_r4/`, look-dev scenes `game/assets/props/boss/_preview_v2/FixR4W2Lid.tscn` and `FixR4W2LidBefore.tscn`, same cameras): `20261018T043844Z__FixR4W2Lid_LidCam.png` / `__FixR4W2LidBefore_LidCam.png`, `__FixR4W2Lid_LidClose.png` / `__FixR4W2LidBefore_LidClose.png`, `__FixR4W2Lid_LidBack.png`, and the pair `__FixR4W2Lid_LidClose_before_after.png`. Blender: `assets_src/topup/worlds/sugar_bowl/fix_r4/v3__front.png`, `v3__q34.png`, `v3__back.png` (after) and `v2__*.png` (before), `lid_texture.png`.

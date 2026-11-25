# Sugar bowl with a domed lid (W2 SUGAR). Use this instead of `sugar_bowl` plus the SugarLid sphere

TOPUP_WORLDS fix pass r1 (night 01), made in Blender 5.1 from the delivered Tripo P2 asset with the scripts in `assets_src/topup/worlds/tools/fix_r1/` (report JSON next to each source in `assets_src/topup/worlds/<asset>/fix_r1*/`). No paid calls. Same conventions as the source: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k textures embedded, no vertex colours, no collision embedded, no bones. Sockets are carried over from the source (see its README) unless noted. Godot captures: `Docs/progress/topup_worlds/fix_r1/` (look-dev scenes `game/assets/props/boss/_preview_v2/Fix*.tscn`, generator `assets_src/topup/worlds/tools/fix_r1/gen_fix_scenes.py`).

## What changed

Source `w2/sugar_bowl/sugar_bowl.glb`, script `fix_sugar_lidded.py`. The 17 sugar-cube islands are removed (hidden under the lid), the first cleanup's vertical squash is undone (x1.631, Tripo proportions), and a rose-china lid is lathed from the bowl's own rim: gold lip, dome, gold bud knob. Every lid face borrows the UV mapping of the bowl wall at the same angle, so the lid repeats the bowl's gold line, rose garland band and plain china (same texture set).

## Use

- Size at scale 1.0: 2.96 m across the handles (X), about 2.0 m across the body, rim 1.35 m, lid apex 2.20 m, knob top 2.565 m. 8.7k tris.
- Builder (w2_build.gd, SUGAR): `place_fit("sugar_bowl_lidded/sugar_bowl_lidded.glb", holder, Vector3(sgp.x, top, sgp.z), Vector3(3.3, 2.8, 3.3), 0.0, "SugarBowl")` gives k 1.09, so the lid apex lands at 55.6 + 2.40 = 58.0, the top of the existing `_dome(..., 1.15, 58.0 - top)` collider (body radius 1.07 against the collider's 1.15). Then delete the `SugarLid` primitive (both spheres).
- Known residue: the garland band on the lid has a visible hard step where two borrowed wall faces meet (one sector on the +X side), and the lid lip band picks up a few cream texels. It reads fine at gameplay distance; a round-2 texture bake would clean it.

## Evidence

`Docs/progress/topup_worlds/fix_r1/` 20261017T230228Z__FixW2Lid_LidCam.png, _LidBack, _LidSide, _LidTop. Before: Docs/progress/critique/topup_worlds/r1_asset_qa/20261017T211715Z__CritLevelW2_SugarLevelCam_south.png

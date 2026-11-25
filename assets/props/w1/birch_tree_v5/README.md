# Birch v5 with clean trunk bark and trunk-matched limb lenticels (W1-M10). Use this file; it replaces `birch_tree_v4`

TOPUP_WORLDS fix round 4 (ASSETS3_WORLDS, night 01, 12:00-12:15 Bangkok), made in Blender 5.1 background mode from `w1/birch_tree_v4/birch_tree_v4.glb` with `assets_src/topup/worlds/tools/fix_r4/fix_birch_r4.py` (report JSON and Blender renders in `assets_src/topup/worlds/birch_tree_v2/fix_r4/`). No paid calls. Geometry and UVs are identical to v4 (and v3); only the albedo changed. Same conventions: glTF +Z facing, origin at the base centre, metres, one PBR material, 2k WebP textures embedded, no vertex colours, no collision, no bones. The older versions stay on disk as backups.

## What changed

Two residues noted after round 3:

- **Leaf-green texels on the trunk** (under the top lobe and a green triangle on one fork). The trunk faces (the island whose texels are 87 % birch cream) are rasterised into a UV mask, minus every texel any foliage face can sample (plus a 1-texel guard), and the leaf-green texels inside it (57.7k) are repainted with the bark cream (0.94, 0.88, 0.76) with a soft 2-texel edge.
- **Limb lenticels read as a barcode** (finer and denser than the trunk's). The limb strip is repainted with 34 rows instead of 60, dashes 1.5-2.5 cm thick, one or two per row with lengths of 14-34 % of the limb's girth and soft ends, faint grey-buff patches, and the dark collar at each limb base kept.

## Use

- Size about 5.0 x 10.3 x 4.1 m, 8.0k tris (as v4).
- Builder: `w1_dress.gd` `const BIRCH_GLB := "res://assets/props/w1/birch_tree_v5/birch_tree_v5.glb"` (path only, no transform change).

## Limits

- The dark crotch at the main fork is part of the trunk's own paint and was kept (it reads as a birch crotch). The trunk lost a small dark knot that was classed as green.

## Evidence

Native (`Docs/progress/topup_worlds/fix_r4/`, look-dev scene `game/assets/props/boss/_preview_v2/FixR4W1Birch.tscn`, v4 left, v5 right): `__FixR4W1Birch_ForkV5.png` / `__FixR4W1Birch_ForkV4.png`, `__FixR4W1Birch_ForkV5Back.png` / `__FixR4W1Birch_ForkV4Back.png`, `__FixR4W1Birch_PairCam.png`. Blender pairs (v4 left, v5 right): `assets_src/topup/worlds/birch_tree_v2/fix_r4/v4_v5_fork_pair.png`, `v4_v5_forkB_pair.png`, `v4_v5_full_pair.png`.

# Pickup and interactable meshes (meshes-pickups_ui, night 01)

All models are glTF with Y up and metre scale. The origin is at the base centre with the bottom at y = 0. The front faces glTF +Z, so wrap the model in a `Visual` Node3D rotated 180 degrees about Y if it must face -Z. Smooth normals, embedded textures. Build scripts and renders: `assets_src/pickups_ui/` (raw files are local only). Preview scene (not gameplay): `_preview/PickupsPreview.tscn`.

| File | Size (m, x y z) | Tris | Nodes / materials | Notes for objects and VFX agents |
| --- | --- | --- | --- | --- |
| `golden_truffle/golden_truffle.glb` | 0.60 x 0.57 x 0.52 | 6.6k | `GoldenTruffle`; `truffle_gold` (metallic 1, roughness 0.3, AO-tinted gold texture), `truffle_leaf`, `truffle_stem` | Spin and bob in code. The sparkle and the soft warm glow belong to VFX; the mesh is not emissive. Collision: SphereShape3D r 0.3 at y 0.28. |
| `acorn/acorn.glb` | 0.21 x 0.30 x 0.21 | 3.5k | `Acorn`; `acorn_nut` (glossy), `acorn_cap` (colour and normal map), `acorn_stem` | Upright. Collision: SphereShape3D r 0.13 at y 0.14. With many on screen, consider a MultiMesh or a LOD. |
| `bookmark_checkpoint/bookmark_checkpoint.glb` | 1.03 x 1.80 x 0.73 | 9.1k | Nodes `Book`, `Ribbon`, `Clasp`, `Tassel`. Materials `bookmark_ribbon_satin`, `bookmark_gold` (clasp and tassel), `bookmark_cover_leather`, `bookmark_paper`, `bookmark_page_edges`, `bookmark_nostril` | **Activation glow:** set an emission override (gold #FFC93C, energy 1 to 2) on the `Clasp` and `Tassel` meshes. **Sway:** `Ribbon` UV.y runs from 0 at the book to 1 at the tip, so a vertex shader can weight the sway by UV.y. The clasp is on both faces. Collision: CapsuleShape3D r 0.15 h 1.8, or a trigger box. |
| `breakable_crate/breakable_crate.glb` | 1.0 cube | 5.0k | `BreakableCrate`; Tripo frame material plus `crate_panel_wood` | Render-only mesh: the Tripo frame has open seams, so use a BoxShape3D 1 x 1 x 1 centred at y 0.5. |
| `breakable_crate/breakable_crate_pieces.glb` | 1.0 cube assembled | 5.1k | 10 nodes: `FrameQuarter_0..3` (a vertical corner post with its brackets and half beams), `Panel_px`, `Panel_nx`, `Panel_py`, `Panel_ny`, `Panel_pz`, `Panel_nz` (three planks each) | Pre-fractured version for the Ham Slam. Each node's origin is at its own centre, so you can spawn RigidBody3D pieces with outward impulses. Swap it in for the intact crate on break. |
| `lost_page/lost_page.glb` | 0.45 x 0.60 x 0.16 | 0.9k | `LostPage`; `lost_page_parchment` (alpha MASK, double-sided, emissive 0.12) | Flutter with a vertex shader (UV.x 0 is the torn left edge, UV.y 0 is the bottom). The gold outline and halo belong to VFX. Collision: SphereShape3D r 0.3 at y 0.3. |

Godot import: `python tools/godot.py import` exits 0 with no errors for these files (2026-10-18).

## Top-up "use this file" list (TOPUP_HUB round 4, ASSETS3_HUB, 2026-10-18 Bangkok)

| Pickup | Use this file | Replaces (kept) | Swap |
| --- | --- | --- | --- |
| Acorn | `acorn_v3/acorn_v3.glb` | `acorn_v2` (`acorn.gd` `DEFAULT_MESH`, `crow_bandit.gd`) | path only (same mesh and UVs; darker satin cap) |
| Golden truffle | `golden_truffle_v2/golden_truffle_v2.glb` (unchanged; accepted after the r1b fix) | `golden_truffle` | already loaded by `truffle.gd` |

# acorn_v3 (TOPUP_HUB round 4, ASSETS3_HUB, night 01)

**Use this file.** It replaces `../acorn_v2/acorn_v2.glb` (the default mesh in `scripts/objects/acorn.gd` `DEFAULT_MESH` and in
`crow_bandit.gd`), which stays on disk as a backup.

- Swap: change the path string only. Geometry, UVs, size (0.26 x 0.35 x 0.26 m), origin (base centre, nut tip at y = 0), facing and
  triangle count (4,102) are identical to v2. Collision unchanged.
- Change (critic polish item "acorn cap value"): the cap and stem read as the same orange as the nut at gameplay distance, and the cap
  showed a glossy hot spot. The cap texels (faces above the overhanging lip plus the lip underside, 45 % of the atlas) are graded
  toward a toasted brown with the scale crevices kept (cap mean #A45425 to #663F26; the nut stays #C26626), and cap roughness is
  at least 0.72 (satin), metallic 0. Tool: `assets_src/topup/hub/tools/acorn_r4.py`; report `assets_src/topup/hub/acorn/r4_fix/work/`.
- Evidence: Blender `assets_src/topup/hub/acorn/r4_fix/blender_v2_v3.jpg`; native macro pairs `Docs/progress/topup_hub/*__r4fix_Acorn_*`.

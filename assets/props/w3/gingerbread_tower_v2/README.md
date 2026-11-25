# Gingerbread tower v2 with a peppermint finial that reads from every side (W3). Use this instead of `gingerbread_tower`

TOPUP_WORLDS fix pass r1 (night 01), made in Blender 5.1 from `w3/gingerbread_tower/gingerbread_tower.glb` with
`assets_src/topup/worlds/tools/fix_r1/fix_tower.py` (report: `assets_src/topup/worlds/gingerbread_tower/fix_r1/report.json`).
No paid calls. Same size, origin, facing, material, textures and sockets as the source (see its README).

## What changed

- The peppermint finial (0.10 m thick disc, it vanished edge-on) is thickened to 0.16 m and crossed with a copy turned
  90 degrees about the vertical axis, so a red-and-white wheel faces the camera from every side.

## Use

- Builder (w3_level.gd:1762-1768): load this path and vary the yaw by 90 degrees per instance so the five towers do not
  line up identically. Matching the procedural fort walls to the tower's clean orange (or adding icing trim to them) is a
  W3 builder change; the tower texture is unchanged.

## Evidence

`Docs/progress/topup_worlds/fix_r1/20261017T231147Z__FixW3_TowerEdge_towerv2.png` (edge-on view, the case that failed) and
`_TowerTop_towerv2.png`. Before: `Docs/progress/critique/topup_worlds/r1_asset_qa/20261017T201535Z__CritW3_TowerTop.png`.

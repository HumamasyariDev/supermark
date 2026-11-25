# W1 bellows machine v5 (+ busted) with a clean wolf medallion on -X. Use this file; it replaces `bellows_machine_v4`

TOPUP_WORLDS fix round 4 (ASSETS3_WORLDS, night 01, 12:15-12:50 Bangkok), made in Blender 5.1 background mode from `w1/bellows_machine_v2/bellows_machine_v2.glb` (and `_busted`) with `assets_src/topup/worlds/tools/fix_r4/fix_bellows_r4.py` (the r3 pipeline copied, so v4 still reproduces from `fix_r3/fix_bellows_r3.py`). Report JSON and Blender renders: `assets_src/topup/worlds/bellows_machine_v2/fix_r4/`. No paid calls. Same conventions, size, origin and sockets (`nozzle_socket`, `plate_socket`) as v2-v4; one PBR material, 2k WebP textures, no vertex colours, no collision, no bones. The older versions stay on disk as backups.

## What changed

The r3 residue on v4: the mirrored -X emblem plate had a ragged, staircase edge (the 64 x 64 grid outline cut through the copper and leather texels around the +X shield). v5:

- the plate grid now stops inside the +X shield (analytic shield contour at 0.84 of its half-size instead of 1.04), and every border vertex is slid along its radial line onto that contour (bisection, 204 vertices, median move 1.3 cm) and re-samples its UV by a ray-cast, so the outline is a smooth shield shape instead of a staircase;
- a raised metal rim band (159 faces) runs from that outline out to 1.12 of the half-size, 1.6 cm prouder than the plate and mapped to one clean grey texel of the +X shield rim, and the plate's own border ring is lifted to meet it, so it reads as a rolled medallion lip like the +X side. The skirt that sinks into the body now hangs from the rim;
- everything else as v4: lathed brass bell with a rolled lip (intact only; the busted nozzle is bent on purpose), the -X blank disc takes leather texels, relaxed wheel rims, roughness 0.7 on non-metal.

Rejected in this round (code kept behind `--bake-plate`, off): baking the plate into its own 512 x 512 texture with the strap texels in-painted. Without the source normal map and ORM it read pale and blotchy.

## Use

- Path-only swap from v4. `w1_level.gd`: `glb("res://assets/props/w1/bellows_machine_v5/bellows_machine_v5.glb")` (keep v4 as the fallback); `showcase.gd` likewise. `bellows_machine.gd` finds `bellows_machine_v5_busted.glb` from the visual's path.
- 14.4k tris (busted 13.6k).

## Limits

- A few copper texels from the +X strap and its rivets stay inside the medallion's upper-right quarter (visible only in close-ups).
- The medallion's upper-left edge rides over the frame strap instead of tucking under it.
- On the busted variant a small grey wedge of the skirt shows under the medallion's bottom tip, where the crumpled body falls away.
- The mirrored wolf faces the nozzle on -X (a mirror image of the +X side; fine for a head with no text).

## Evidence

Native (`Docs/progress/topup_worlds/fix_r4/`, look-dev scenes `game/assets/props/boss/_preview_v2/FixR4W1.tscn` and `FixR4W1Before.tscn`, same cameras): `20261018T050403Z__FixR4W1_EmblemClose.png` / `__FixR4W1Before_EmblemClose.png`, `__FixR4W1_BellowsQ34.png` / `__FixR4W1Before_BellowsQ34.png`, `__FixR4W1_BustedMinusX.png`, `__FixR4W1_BellowsMinusX.png`, pairs `__FixR4W1_EmblemClose_before_after.png`, `__FixR4W1_BellowsQ34_before_after.png`. Blender pairs (v4 left, v5 right): `assets_src/topup/worlds/bellows_machine_v2/fix_r4/v4_v5_mx_pair.png`, `v4_v5_mxq_pair.png`; `v5_px.png` (the +X side, unchanged), `v5b_mx.png` (busted).

# brass_chandelier_v2 (Tripo P2, TOPUP_HUB, night 01)

Replacement for `../brass_chandelier/brass_chandelier.glb` (procedural, kept). **Use this one.**

- Size: 3.16 x 2.21 x 3.16 m. The height matches the old model (2.21 m), so the chain maths in `hub_level.gd` (`top_y = 8.6 + 2.21 * scl`)
  still meets the cap. It is wider (3.16 m against 2.16 m): at the hub's `scl = 2.3` it spans about 7.3 m. Use `scl` 1.6 to 1.8 if that is too big.
- Hierarchy: `brass_chandelier_v2` (root, y 0) > `sway_pivot` (at the ceiling cap, y 2.21) > `chandelier_mesh` + `candle_0` to `candle_7`.
  Rotate `sway_pivot` for the sway; the candle markers sway with it.
- Candle markers sit on the wick tips (root space, Godot axes, metres, before scaling):
  (-1.365, 0.967, -0.012), (-0.968, 0.998, -0.960), (0.023, 1.015, -1.351), (0.976, 0.965, -0.949),
  (1.348, 0.967, -0.004), (0.960, 0.990, 0.980), (0.003, 0.996, 1.355), (-0.982, 0.998, 0.943).
  Parent the flame VFX to these nodes instead of the old 12-flame ring (radius 0.86, height 0.62): the new model has 8 candles.
- Mesh: 12,144 triangles. The Tripo PBR material (2k WebP; brass is metallic with a roughness floor of 0.3 so the sky no longer
  mirrors as white spots; the candle wax is forced non-metallic, roughness about 0.55) plus `chandelier_ring_brass` (metallic 1,
  roughness 0.34) on the rebuilt ring and the drop finial. Above the 6k prop guide, like the old chandelier (9.5k): one landmark piece.
- Fix round 1 (critic r1): the Tripo ring had a saw-tooth band of triangles on its inner underside, the view from the hub floor. It is
  replaced by a clean 96 x 20 torus with a rounded-square section (same radius 0.85 m and height); a 0.65 m turned drop finial
  hangs under the central hub. Tool: `assets_src/topup/hub/tools/chandelier_fix.py`. Captures: `Docs/progress/topup_hub/20261017T231108Z__r1fix_Chandelier_*.png`.
- Integration note: a short brass chain between the ceiling and the cap (as on the old procedural piece) belongs in `hub_level.gd`.
- Facing: radially symmetric. Collision: none (it hangs out of reach); add a cylinder if the player can reach it.

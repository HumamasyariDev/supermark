# grandfather_clock_v2 (Tripo P2, TOPUP_HUB, night 01)

Replacement for `../grandfather_clock/grandfather_clock.glb` (procedural, kept). **Use this one.**

- Size: 0.73 (W) x 2.40 (H) x 0.48 (D) m, slimmer than the old 1.07 m clock (shrink its collider to about 0.75 x 2.45 x 0.5).
  Origin at the base centre, bottom at y = 0.
- Facing: glTF +Z (the clock face). Wrap in a `Visual` rotated 180 degrees about Y to face Godot -Z.
- Nodes (children of the root, named exactly `grandfather_clock_v2` since fix round 1; 8,656 triangles in total). Materials: the Tripo
  2k PBR case material, `clock_dial_enamel` (ivory enamel, 1k texture with 12 gold pips and a minute track, no hands painted in,
  metallic 0, roughness 0.45), `clock_gold` (bezel, boss and hands; metallic 1, roughness 0.28) and `clock_bob_gold` (pendulum).
  - `clock_body` (7,184 tris): case, door frame, weights, the clean enamel dial disc, a clean gold bezel ring and a smooth centre boss.
    The trunk door is an open frame (no glass sheet). The back is a flat plane (the bulging Tripo back was flattened).
  - `pendulum` (1,080 tris): lathe-built lens bob 0.21 m across and 3 cm thick on a round rod. Pivot at the top of its rod,
    (0, 1.556, -0.011). **Swing it about its local Z at most 4 degrees each way** (both extremes clear the door frame, checked in
    native captures). A 1.6 s period looks right for this size.
  - `hand_hour`, `hand_minute` (196 tris each): clean spade hands, gold. Pivots at the dial centre (0, 1.912, 0.141). Rotate about
    local Z; **negative angles turn clockwise** seen from the front. Zero = both hands at 12. The hands sit 4-10 mm in front of the
    dial and behind the boss, so any time can be shown (no ghost hands). The look-dev uses -0.6 rad/s for the minute hand.
- Collision: `BoxShape3D` 0.75 x 2.45 x 0.5 centred at y 1.22.
- Fix round 1 (critic r1 asset QA): `assets_src/topup/hub/tools/clock_fix.py` + `dial_texture.py`; before/after captures in
  `Docs/progress/topup_hub/20261017T231108Z__r1fix_Clock_*.png`. Earlier verification: pose renders in Blender (`Docs/progress/assets/topup/*grandfather_clock_pose_v2_studio.webp`) and the animated
  look-dev clip `Recordings/night01/M3/*__topup_hub_v2_motion.mp4`.

# wingback_armchair_v2 (Tripo P2, TOPUP_HUB, night 01)

Replacement for `../wingback_armchair/wingback_armchair.glb` (procedural, kept). **Use this one.**

- Size: 1.16 (W) x 1.40 (H) x 1.11 (D) m. Origin at the base centre, bottom at y = 0 (the leg feet).
- Facing: glTF +Z (the seat faces +Z). Wrap in a `Visual` Node3D rotated 180 degrees about Y to face Godot -Z, as for the other hub props.
- Mesh: one node `wingback_armchair_v2`, 7,531 triangles, one PBR material (2k WebP). Button-tufted back, rolled arms, puffy seat
  cushion, walnut cabriole legs, closed upholstered back. Velvet graded to burgundy (hue 352, mean about #67 1B 25 before lighting),
  velvet roughness at least 0.88 and metallic 0, ambient occlusion baked into the ORM.
- Fix round 1 (critic r1): the torn shard at both arm/back junctions is pushed into the backrest; the faceted buttons are smooth domes;
  tiny holes filled. The 'mauve patch' beside the cushion was not in the albedo (every velvet texel was already hue 340-360): it was
  glossy velvet (roughness 0.6 patches) mirroring the purple sky plus a crevice with no occlusion. Tools: `assets_src/topup/hub/tools/
  velvet_grade.py`, `armchair_fix.py`. Captures: `Docs/progress/topup_hub/20261017T231108Z__r1fix_Armchair_*.png` and `__r1fix_Macro_armchair_seat_gap*.png`.
- Collision: a `BoxShape3D` 1.1 x 0.55 x 1.0 at y 0.28 for the seat block plus a box 1.1 x 0.85 x 0.3 at y 0.98, z -0.38 for the back
  (or one convex hull). The seat top is about 0.55 m high, a good perch for Mak.
- Sockets: none. Seat centre for a sitting NPC: about (0, 0.55, 0.1).
- Fix round r1c (critic r1b): the 4 lumpy leg islands are replaced by clean swept cabriole legs (about 470 tris each, walnut texels);
  the cushion is 7 % wider and 0.8 cm lower so its side walls sit inside the arms; the arm front panels (|x| > 0.26, z 0.10-0.64)
  get 12 Taubin passes plus a 20-iteration volume-preserving Laplacian; velvet albedo regraded toward burgundy (mean #72172B).
  Tool: `assets_src/topup/hub/tools/armchair_fix_r1b.py` (env CUSHION_SX=1.07 ARM_X0=0.26 ARM_Y0=-0.26 ARM_Z1=0.64 ARM_LAP=20
  ARM_PASSES=12). Open: a crease remains along the right arm scroll; the cushion's front corners show small dark notches; under the
  hub's amber key the velvet still leans red.

- r2 (2026-10-18 06:2x Bangkok): legs moved to a separate walnut_legs material (tools/armchair_legs_r2.py). Evidence: Docs/progress/topup_hub/20261017T232300Z__r2fix_Armchair_*.

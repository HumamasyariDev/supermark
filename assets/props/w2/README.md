# World 2 (Beanstalk Skyway) props: usage notes

All GLBs: 1 unit = 1 m, origin at the base centre (bottom at y = 0), front faces glTF +Z (wrap in a `Visual`
Node3D rotated 180° about Y if the parent should face -Z). Smooth shaded. Colliders are not included:
author simple shapes (boxes, cylinders, convex hulls) per placement.

| Asset | Size | Tris | Source | Notes |
| --- | --- | --- | --- | --- |
| `beanstalk_segment/beanstalk_segment.glb` | 10 m tall, about 6.8 m wide incl. tendrils | 10.8k | procedural | **Stack at +10 m with no extra rotation.** Three identical stems twist 240°, so the top and bottom cross-sections match. Extra yaw must be a multiple of 120° for a seamless join. Origin on the trunk axis. Flat cut cap on top (light green) for the topmost segment. Known: tiny break in the lime stripe at each seam. Trunk collider: cylinder radius about 1.7 m. |
| `giant_leaf/giant_leaf.glb` | 4 m long, 3.4 m wide | 6.5k | procedural | Heart leaf, tip toward +Z, stem toward -Z. Top is broad and nearly flat (edges rise about 0.2 m). Collider: flattened convex hull or a thin box about 3 × 3 m. |
| `giant_leaf/giant_leaf_bouncy.glb` | same | 6.5k | procedural | Lighter tint (#BDEB7A) for the bouncy variant; squash is procedural (group `bouncy`, meta `bounce_velocity`). |
| `bean_flower/bean_flower.glb` | 1.5 m tall | 4.0k | fal Trellis-2 | Goal marker on top of the castle tower; trumpet opens toward +Z. Add glow as VFX if wanted (centre is texture-only). |
| `jack_cottage/jack_cottage.glb` | 7 m largest dimension, island included | 9.3k | fal Tripo P2 | Door faces +Z. The island and roots are fused into the mesh (not split). Chimney smoke is VFX. |
| `giant_castle/giant_castle.glb` | 30 m largest dimension, cloud included | 12.0k | fal Tripo P2 | Gate faces +Z. The cloud base is fused into the mesh. Exterior only; the interior is built separately. Known artefact: a slanted wall slab behind the central tower. |
| `giant_teacup/giant_teacup.glb` | 4 m saucer, about 1.9 m tall | 8.2k | procedural | Tea surface is about 1.58 m above the base, saucer rim about 0.4 m. Handle on +X. |
| `giant_loaf/giant_loaf.glb` | 5 m long, about 3.4 m tall | 5.0k | fal Trellis-2 | Sliced crumb end on +X. Box collider is fine. |
| `pocket_watch/pocket_watch.glb` | 4 m largest dimension (lid open) | 7.4k | procedural | Nodes `WatchBody`, `HourHand`, `MinuteHand`. **Hands rotate about local +Y at their origin (the dial centre).** They are 7 cm thick slabs; `HourHand` sits just above the dial, `MinuteHand` above it. Make each hand an AnimatableBody3D with a box collider for the rotating-platform mission. Crown/bow at -Z (12 o'clock), lid hinged on -X. |
| `goose_cage/goose_cage.glb` | 2.5 m tall, 2 m base | 7.9k | procedural | Nodes `CageBody` and `CageDoor`. **`CageDoor` pivots about local +Y at its origin, which is the hinge on the door's left edge seen from the front.** About -100° yaw swings it open outward; check the sign in Godot. Padlock is part of the door. Interior floor at about 0.25 m. |
| `golden_harp/golden_harp.glb` | 1.8 m tall | 5.0k | fal Trellis-2 | Side profile (swan neck) faces +Z. Recoloured to polished gold; strings are not emissive (add a glow if wanted). |

Review scenes (asset look-dev only, not gameplay): `_review/W2PropsLineup.tscn`, `_review/W2Landmarks.tscn`,
`_review/W2BeanstalkSeam.tscn`. Sources, scripts and receipts: `assets_src/w2/` (raw files are local only).

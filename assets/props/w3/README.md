# W3 Gingerbread Grove props (meshes-w3, night 01)

All GLBs: metres, Y up, origin at the base centre (bottom at y = 0), front facing glTF +Z
(wrap in a `Visual` Node3D rotated 180 deg about Y to face Godot -Z, per TECH_CONTRACT).
Smooth shaded with angle-based hard edges; textures embedded (Godot extracts them next to the GLB).
Previews: `Docs/progress/assets/w3/`. Sources and scripts: `assets_src/w3/`.

| Folder / file | Size (m, x * z * y) | Tris | Source | Notes |
| --- | --- | --- | --- | --- |
| gingerbread_cottage/gingerbread_cottage.glb | 7.6 * 7.5 * 9.0 | 11.8k | Tripo P2 | Door gable faces +Z; chimney top is the W3-6 goal. Mesh is not watertight: use box/convex colliders for walls and roof slopes. 2k PBR textures. |
| cupcake_tower/cupcake_tower.glb | 5.0 * 5.0 * 8.0 | 9.8k | Tripo P2 | Icing spiral bands read as ledges; cherry perch on top. Author ledge colliders by hand. 2k PBR textures. |
| cauldron/cauldron.glb | 2.2 * 2.2 * 2.0 | 5.9k | Tripo P2 | Rim top y = 2.002, rim outer radius 0.94. Flames fused into the mesh; brew is textured, not emissive: add green glow, bubbles and steam as VFX. |
| cauldron/cauldron_lid.glb | 1.87 * 1.87 * 0.50 | 4.1k | Procedural | Closed position: local y = 1.952 on the cauldron (plug drops 5 cm into the opening). Separate body for the Ham Slam secret (W3-8). |
| lollipop_tree/lollipop_tree{,_mint,_red}.glb | 2.2 * 0.42 * 4.0 | 3.2k | Procedural | Swirl disc faces +-Z. Colour variants are separate files. |
| lollipop_tree/lollipop_tree_grumpy.glb | 2.2 * 0.54 * 4.0 | 5.4k | Procedural | Rare background joke: grumpy eyes, brows and frown on the +Z face. |
| candy_cane/candy_cane.glb | 0.48 * 0.14 * 1.5 | 0.8k | Procedural | Single post, hook toward +X. |
| candy_cane/candy_cane_fence.glb | 2.42 * 0.14 * 1.49 | 2.0k | Procedural | Two posts 1.6 m apart, rails at 0.42 / 0.82 m. Tile every 1.6-2.4 m. |
| gumdrop/gumdrop{,_mint,_violet,_orange}.glb | 2.0 * 2.0 * 1.48 | 2.8k | Procedural | Bouncy platform for W3-7: scale up in scene; squash procedural. |
| biscuit_platform/biscuit_platform.glb | 2.5 * 2.5 * 0.72 | 5.2k | Procedural | Cylinder collider r 1.2, h 0.72. Bob/drift procedural. |
| marshmallow/marshmallow{,_pink,_toasted}.glb | 1.19 * 1.19 * 1.2 | 2.3k | Procedural | Squishy step; cylinder collider. |
| chocolate_bar_bridge/chocolate_bar_bridge.glb | 8.0 * 2.9 * 0.5 | 2.2k | Procedural | Long axis X; bitten end at +X. Box collider 8 * 0.5 * 2.8. |
| candy_rock/candy_rock.glb | 3.0 * 2.5 * 2.8 | 1.9k | Procedural | Broad bevelled facets on purpose; glossy, faint self-glow. Scale freely for cliffs. |

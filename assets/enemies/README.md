# Enemy models (night 01, meshes-enemies)

All GLBs: metres, Y up, origin at the base centre (feet at y = 0), **model faces glTF +Z**
(wrap in a `Visual` Node3D rotated 180° about Y so it faces Godot -Z, per TECH_CONTRACT).
Character left = +X in the file. One PBR material per asset (2k WebP base colour, normal, ORM),
smooth shading. Source: fal Tripo P2 from the accepted refs in `concepts/v2/refs/enemies/`,
cleaned and rigged in Blender 5.1 (`assets_src/enemies/tools/`). Rest pose, no animations: animate
procedurally by bone name (`Skeleton3D.set_bone_pose_rotation`).

| Asset | Height | Tris | Nodes / bones | Notes |
| --- | --- | --- | --- | --- |
| `woolly_wolf` | 1.00 m | 6.6k | Skeleton, 17 bones: root, hips, spine, head, jaw, ear_l/r (floppy sheep-hood ears), arm_l/r, forearm_l/r, thigh_l/r, shin_l/r, tail, tail_2 | Costume is fused into the body, not a separate mesh. Do the "rip costume off" gag as a swap to `woolly_wolf_cub` (same bone names) hidden by a wool-puff burst VFX. |
| `woolly_wolf_cub` | 0.95 m | 6.5k | Same 17 bone names as `woolly_wolf` (ear_l/r are the pointy wolf ears) | Joint positions are fitted to the cub, so copy poses by bone name, not by transform. Underpants with hearts visible for the defeat spin. |
| `crow_bandit` | 0.90 m | 6.5k | 17 bones: root, hips, spine, head, beak, arm_l/r + forearm_l/r + hand_l/r (3 per wing), thigh_l/r, shin_l/r, tail, tail_2 | Loot sack socket: attach a `BoneAttachment3D` to `hand_l` or `hand_r`. The beak is one closed piece: the `beak` bone swings the whole beak (use small angles for the cackle). Legs were thickened x1.7. |
| `peapod_popper` | 0.90 m | 6.2k | No skeleton. MeshInstance3D nodes: `pod`, `pea_face` (top pea with the face and eyes), `pea_mid`, `pea_low`, `pea_tiny` | Pea origins are at their centres, ready to fly out and scatter on defeat. Squash and wobble the whole root for the lob wind-up. |
| `bumble_bruiser` | 0.80 m | 6.3k | No skeleton. Nodes: `body`, `wing_l`, `wing_r` | Wing origins sit at the wing roots: flap by rotating about the local Z axis (about ±35°, fast). The wings are opaque pale blue: override their material with alpha about 0.45 for the translucent look. Gloves are part of `body`. |
| `gingerbread_grenadier` | 1.10 m | 5.9k | 14 bones: root, hips, spine, head, arm_l/r, forearm_l/r, hand_l/r, thigh_l/r, shin_l/r | Lance socket: `BoneAttachment3D` on `hand_r` (the character's right, -X in the file). Cookie body deepened in Blender (about 0.26 m thick). It is a biscuit: keep knee and elbow bends small (stiff march). The busby hat is part of the head. |
| `gummy_brute` | 1.60 m | 6.3k | 15 bones: root, hips, spine, spine_2, head, ear_l/r, arm_l/r, forearm_l/r, thigh_l/r, shin_l/r | Jiggle with scale on hips/spine_2 (squash and stretch). The material is opaque glossy raspberry: for jelly, override with a translucent or rim-lit shader (VFX workstream). Broad flat back is the trampoline surface: author a separate collider. |

Not watertight; use simple collision shapes, not the visual mesh. Studio renders and rig test poses:
`Docs/progress/assets/enemies/`. Licences and hashes: `Docs/LICENSES.md`, `data/asset_register.csv`.

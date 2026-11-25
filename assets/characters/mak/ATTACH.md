# Mr. Mak kit: files, rig and attachments

Owner: meshes workstream (night 01). Sources and scripts: `assets_src/hero/` (raw downloads, renders and blend files stay local).
Studio renders and a native Godot look-dev capture: `Docs/progress/assets/hero/`.

## Files

| File | What | Triangles |
| --- | --- | --- |
| `mak.glb` | **Default outfit in one file**: rigged body + beanie (child of bone `head_top`) + backpack (child of bone `backpack`). Use this when you just need Mr. Mak. | about 23k |
| `mak_body.glb` | Rigged body only (no hat, no backpack) | 12,754 |
| `mak_beanie.glb` | Grey rib-knit beanie, origin at the centre of the cuff's lower rim | 5,280 |
| `mak_tophat.glb` | Black top hat (boss reward), origin at the brim centre | 2,541 |
| `mak_backpack.glb` | Leather backpack + chest straps, origin on the bag's back face between the shoulder blades | 5,107 |
| `attach.json` | Machine-readable offsets (same numbers as below) | |
| `preview/MakLookdev.tscn` | Look-dev stage that assembles the kit at runtime from `attach.json` and poses bones (reference code for attaching) | |

All meshes: metres, Y up, rest pose, **the model faces +Z** (wrap it in a `Visual` Node3D rotated 180 degrees about Y, per TECH_CONTRACT).
Height 1.10 m from the feet (origin between the feet, y = 0) to the ear tips; the beanie adds about 5 cm above the head.
Smooth shaded, 2k WebP PBR textures (body), roughness raised to 0.5 for a soft vinyl look.

## Skeleton (27 bones, rest pose = A-pose)

Contract names: `root, hips, spine, head, ear_l, ear_r, arm_l, forearm_l, arm_r, forearm_r, thigh_l, shin_l, thigh_r, shin_r, tail, backpack`.
Extras: `chest, neck, ear_l_2, ear_r_2, hand_l, hand_r, foot_l, foot_r, tail_2, tail_3, head_top`.

Hierarchy: root > hips > spine > chest > neck > head > (head_top, ear_x > ear_x_2); chest > arm_x > forearm_x > hand_x; chest > backpack;
hips > thigh_x > shin_x > foot_x; hips > tail > tail_2 > tail_3. `_l` is the character's left (model +X).

- `head_top` and `backpack` are non-deforming sockets with an **identity rest rotation in model space**, so the offsets below apply directly.
- Other bones have rolled rest bases (Blender convention: bone +Y runs along the bone). For procedural motion, rotate about **model-space axes**
  through the bone origin. `preview/mak_lookdev.gd::_rot_model()` shows how:
  `local = parent_global.basis.inverse() * Basis(axis, angle) * bone_global.basis`.
  Model axes: +X = character's left, +Y = up, +Z = forward.
  Examples (in model space): raise the left arm = +Z rotation on `arm_l`; raise the right arm = -Z on `arm_r`; turn the head = Y on `head`;
  forward leg swing = -X on `thigh_x`; flop the left ear outward = -Z on `ear_l`.
- Weights: max 4 influences per vertex, normalised; arm and thigh weights fade out at the shoulder and hip lines so limb swings do not drag the belly.
  Squash and stretch: scale `hips` / `chest` non-uniformly (inherit scale is on).
- No blend shapes and no jaw bone. The eyes, brows and mouth are texture on a closed-mouth mesh.
  For blinks or expressions, use a separate eyelid card or a texture swap, or scale-pulse the `head` (cheap, reads well).

## Attachment offsets (model space of `mak_body.glb`, metres)

Socket rest positions: `head_top` = (0, 1.0393, 0.0441), `backpack` = (0, 0.44, -0.2399).

| Attachment | Socket | Position offset | Rotation (degrees, x y z) |
| --- | --- | --- | --- |
| `mak_beanie.glb` | `head_top` | (0, -0.1326, -0.0097) | (0, 0, 0) |
| `mak_tophat.glb` | `head_top` | (0, -0.0825, -0.0100) | (-5, 0, 8): a slight dandy tilt back and to his right |
| `mak_backpack.glb` | `backpack` | (0, 0.1203, 0.0189) | (0, 0, 0) |

Godot:

```gdscript
var ba := BoneAttachment3D.new()
ba.bone_name = "head_top"
skeleton.add_child(ba)
var hat := preload("res://assets/characters/mak/mak_tophat.glb").instantiate()
ba.add_child(hat)
hat.position = Vector3(0, -0.0825, -0.0100)
hat.rotation_degrees = Vector3(-5, 0, 8)
```

- Hat swap (pause menu, after `Game.unlock("top_hat")`): either hide the beanie child under `head_top` in `mak.glb` and attach the top hat as above,
  or use `mak_body.glb` and attach both hats yourself. The top hat sits between the ears without touching them, so no ear pose is needed.
  The ears poke out through the beanie's sides by design (approved September identity).
- The rotation was authored in Blender's XYZ order. Godot's default YXZ order gives the same result here to well under 1 degree.
- Backpack jiggle: give the `backpack` BoneAttachment child a spring-damped rotation about model X (a few degrees on landing). There is no jiggle bone.

## Known limits

- Body: 12,754 triangles, 6% over the 12k hero ceiling (kept to avoid re-rigging). One 2k PBR material.
- In a deep crouch the very short thighs fold into the belly. Use squash on `hips`/`chest` rather than bending the knees far.
- The straps are rigid on the chest bone. With extreme arm-down poses the upper arm can touch the strap near the armpit.
- The beanie is wider (about 0.62 m) than the brief's 0.38 m because Mr. Mak's head is 0.68 m wide. It is built from his own head surface.
- The curly tail is a thin wire. It is weighted to `tail`, `tail_2` and `tail_3`, but use small rotations only.

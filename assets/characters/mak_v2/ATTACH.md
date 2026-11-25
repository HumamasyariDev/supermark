# Mr. Mak v2 (hero v2): attachment and rig notes

Built 2026-10-18 by the hero v2 mesh-and-rig stage from Stefan's look (`references/owner_2026-10-18_mak_look.png`).
Sources and scripts: `assets_src/hero_v2/` (`tools/bl_rig_v2.py`, `tools/bl_kit_v2.py`; run commands in the DEVLOG entry).
The old hero in `characters/mak/` is untouched.

## Files

| File | What | Tris |
| --- | --- | --- |
| `mak_v2_body.glb` | Skinned body with 30 bones, eyelids built in, no hat and no pack | 8,043 |
| `mak_v2_tophat.glb` | **Default hat.** Short faceted top hat with a burgundy band and bow. Origin = `head_top` socket | 264 |
| `mak_v2_beanie.glb` | Alternate hat. Grey cuffed beanie. Origin = `head_top` socket | 420 |
| `mak_v2_backpack.glb` | Tripo P2 leather pack plus two procedural shoulder straps. Origin = `backpack_socket` | 3,607 |
| `mak_v2.glb` | Assembled default outfit: body + top hat + pack, parented to the socket bones. Use it for previews. Gameplay should use the separate parts so the hat can be switched | 11,914 |

Textures are embedded WebP at 1024 px (Color, NormalGL, ORM). The RetroLook autoload downsamples and applies nearest filtering at runtime (D032).
Height is 1.15 m, feet are at the origin, and the model faces +Z (glTF and Godot model space).

## Sockets (model space, Godot Y-up, +Z forward, metres)

| Bone | Position | Rest basis |
| --- | --- | --- |
| `head_top` | (0, 1.0994, 0.0023) | identity |
| `backpack_socket` | (0, 0.4506, -0.172) | identity |

Both socket bones have an identity rest basis in model space, and each part's origin is already at its socket.
**The offset is therefore zero.** Add the part as a child of a `BoneAttachment3D` with an identity transform:

```gdscript
const HAT_TOPHAT := preload("res://assets/characters/mak_v2/mak_v2_tophat.glb")
const HAT_BEANIE := preload("res://assets/characters/mak_v2/mak_v2_beanie.glb")
const PACK := preload("res://assets/characters/mak_v2/mak_v2_backpack.glb")
var hat_scene := HAT_TOPHAT   # one-line switch: HAT_BEANIE for the grey beanie

var head_top := BoneAttachment3D.new(); head_top.bone_name = "head_top"; skeleton.add_child(head_top)
head_top.add_child(hat_scene.instantiate())
var pack_att := BoneAttachment3D.new(); pack_att.bone_name = "backpack_socket"; skeleton.add_child(pack_att)
pack_att.add_child(PACK.instantiate())
```

The hats already include their tilt: the top hat leans 7 degrees toward Mak's left, and the beanie sits 16 degrees back.
Do not add another tilt. Both are fitted to this head: the top hat sits between the ears, and the beanie cuff sits above the brows.
A scale of 1.0 is correct for the whole character. If the player scales the character root, the parts follow.

`game/assets/characters/mak_v2/_preview/mak_v2_lineup.tscn` is a working example (look-dev only).

## Skeleton

Bones: root, hips, spine, chest, neck, head, head_top, ear_l, ear_l_2, ear_r, ear_r_2, eyelid_l, eyelid_r, arm_l, forearm_l,
hand_l, arm_r, forearm_r, hand_r, backpack, backpack_socket, thigh_l, shin_l, foot_l, thigh_r, shin_r, foot_r, tail, tail_2, tail_3.

- It has every hero joint name from the contract. The extra deform bones are `ear_*_2`, `hand_*`, `foot_*` and `tail_2/3`.
  Non-deform bones: root, head_top, backpack and backpack_socket. `_l` means Mak's left, which is model +X.
- There is at most 4 influences per vertex and no unweighted vertex. Squash and stretch work by scaling `hips`, because the whole body is under it.

## Blink

`eyelid_l` and `eyelid_r` each drive one small skin-coloured lid mesh. The patch-eye lid is patch brown, and each lid has a lash strip.
The lid is hidden inside the head at rest (identity pose).
To close the eye, rotate the bone about its local +X: `skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3.RIGHT, deg_to_rad(115)))`.
Use 0 degrees for open, about 115 degrees for closed and about 60 degrees for sleepy.
A typical blink is about 0.12 s: 0.05 s to close, 0.02 s held and 0.05 s to open, every 2.5-5 s at random. Always blink both eyes together, except for a wink.

## Known limits

- The top of the patch-eye lid shows a hairline of eye white in a close-up from 15 degrees off the side. It is not visible at gameplay distance.
- The straps are rigid on the chest bone. If an arm is raised above about 70 degrees, the upper arm can pass through the front of the strap.
- The face is texture only: no mouth bones and no blend shapes. Expressions come from the blink, the ears, the head tilt and squash and stretch.

## v3 parts (hero fix round 1, 2026-10-19) — the game uses these

`assets_src/hero_v2/tools/bl_fix_v3.py` (run on `kit2/kit_v2.blend`, output and renders in `assets_src/hero_v2/fix3/`) made new files
next to the originals. Bones, weights, sockets and origins are unchanged, so the attachment notes above apply as written.

| File | Change |
| --- | --- |
| `mak_v2_body_v3.glb` | Snout pulled back 28 % of its depth (the patch eye shows at the reference 3/4 angle), nostrils painted dark brown, Color map named `face_*` so RetroLook gives it the 512 px face rule |
| `mak_v2_backpack_v3.glb` | Front straps end at the upper chest (they read as suspenders), lighter strap leather, pack 20 % less saturated and darker |
| `mak_v2_beanie_v3.glb` | Alternate hat: a domed crown about 1.7x taller above the cuff |
| `mak_v2_assembled_v3.glb` | Body v3 + top hat + pack v3 (title screen, `scenes/player/MakModel.tscn`) |

`MakPlayer` loads `mak_v2_body_v3.glb`, `mak_v2_beanie_v3.glb` and `mak_v2_backpack_v3.glb`; the top hat is unchanged.

## Face fix (2026-10-19, owner: "closed eyes become sharp triangles", "artifacts on the nose")

`assets_src/hero_v2/tools/bl_fix_v4_face.py` (run on `fix3/fix_v3.blend`, output in `assets_src/hero_v2/fix4/`) re-exported
`mak_v2_body_v3.glb` and `mak_v2_assembled_v3.glb` in place. Bones, node transforms, sockets, scale and weights of the existing
vertices are unchanged; the blink still turns `eyelid_l/r` 0-115 degrees. Old files: `assets_src/hero_v2/backup_v3_pre_facefix/`.

- Lids: the dark two-quad lash wedge is gone (skin material). Each lid has a thin tapered lash line along its lower rim
  (`mak_lash`, soft dark brown), and the closed lids follow the pulled-back snout again (the v3 pull skipped them).
- Nose: the nostril texture paint was reverted; the nostril faces use a new flat material `mak_nostril` (#3a2420), a 5th surface
  on the body mesh. The snout custom normals were recomputed after the v3 pull-back.

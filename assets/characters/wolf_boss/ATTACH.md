# Sir Reginald Huffington III: rig and attachments

Files
- `wolf_boss.glb`: skinned mesh in rest pose (A-pose), 3.2 m tall, origin at the base centre, faces glTF +Z
  (wrap in a `Visual` Node3D rotated 180 degrees about Y so it faces -Z like the body). No animations: animate procedurally.
  About 14.9k body triangles, one Tripo PBR material (2k colour, normal, ORM), plus the monocle (about 1.2k triangles,
  gold ring and translucent lens) skinned 100% to `head`.
- `wolf_cane.glb`: silver-topped cane, separate prop, 1.0 m shaft, about 1k triangles.

Bones (Skeleton3D names)
- `root` (non-deform) > `hips` > `spine` > `spine_2` > `spine_3` > `chest` > `neck` > `head` > `jaw`, `ear_l`, `ear_r`
- `chest` > `arm_l` > `forearm_l` > `hand_l`; same for `_r`. `hand_r` > `cane_socket_r` (non-deform)
- `hips` > `thigh_l` > `shin_l` > `foot_l`; same for `_r`
- `hips` > `tail` > `tail_2` > `tail_3` > `tail_4` (the tail hangs at the character's left side)
- `hips` > `coat_l` > `coat_l_2`, `hips` > `coat_r` > `coat_r_2` (coat tails)
- Hands are mitten paws: no finger bones. Weights were made with bone heat on a voxel proxy and transferred
  (bone heat on the raw mesh left 1.8% of vertices unweighted); max 4 influences.
- Tested poses (arms raised, arms forward, running stride, crouch, head turn with jaw open): no tearing.
  The coat stretches a little at the shoulders when the arms go above about 70 degrees.

Blend shapes (on the body mesh)
- `chest_inflate` 0..1: the Huff inhale, belly and chest balloon to roughly 1.6x width at 1.0 (arms move out with it).
- `cheeks_puff` 0..1: puffed cheeks for the huff blast.
  For the defeat "balloon float", combine `chest_inflate` 1.0 with a uniform scale-up of the Visual node.

Cane
- `wolf_cane.glb` is authored in socket space: origin at the grip, shaft along local +Y.
  The `cane_socket_r` bone points straight down in rest pose, so add a `BoneAttachment3D` with
  `bone_name = "cane_socket_r"` and put the cane under it with an identity transform. The silver knob
  sits inside the paw and the tip reaches the floor in rest pose.

Monocle
- Already in `wolf_boss.glb` (object `wolf_boss_monocle`), over the right eye, follows `head`. No chain: the face is
  so wide that a hanging chain clipped through the cheek, so it was left out.

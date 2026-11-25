class_name MakRigAdapters
extends RefCounted
## Rig adapters for MakAnimator. Pose rotations arrive as character-space bases
## (X right, Y up, -Z forward) for each abstract joint, plus a full root transform.
##   MakRigAdapters.Proxy: the proxy pig's Node3D pivots (identity rest rotations).
##   MakRigAdapters.Skel: a Skeleton3D with bones named like the joints. Rotations are conjugated
##   by each bone's global rest basis, so bone roll and axis conventions do not matter.


class Proxy:
	extends RefCounted
	var nodes := {}
	var rest := {}

	func _init(proxy: Node3D) -> void:
		var j: Variant = proxy.get("joints")
		if j is Dictionary:
			for k in (j as Dictionary):
				var n := (j as Dictionary)[k] as Node3D
				nodes[k] = n
				rest[k] = n.position

	func set_root(xf: Transform3D) -> void:
		var n := nodes.get("root") as Node3D
		if n != null:
			n.transform = xf

	func set_joint(joint: String, b: Basis, offset: Vector3) -> void:
		var n := nodes.get(joint) as Node3D
		if n == null:
			return
		var r: Vector3 = rest[joint]
		n.transform = Transform3D(b, r + offset)


class Skel:
	extends RefCounted
	var skel: Skeleton3D
	var idx := {}
	var rest_local := {}
	var conj := {}
	var parent_conj := {}
	var pre := {}                  ## per-joint rest correction (character space), e.g. A-pose arms -> arms down
	var root_joint := "root"

	func _init(s: Skeleton3D, char_root: Node3D, joint_names: Array) -> void:
		skel = s
		var to_char := (char_root.global_transform.affine_inverse() * s.global_transform).basis.orthonormalized()
		for jn in joint_names:
			var j := str(jn)
			var i := s.find_bone(j)
			if i < 0:
				continue
			idx[j] = i
			rest_local[j] = s.get_bone_rest(i)
			conj[j] = (to_char * s.get_bone_global_rest(i).basis).orthonormalized()
			var pi := s.get_bone_parent(i)
			parent_conj[j] = (to_char * s.get_bone_global_rest(pi).basis).orthonormalized() if pi >= 0 else to_char
		if not idx.has("root"):
			root_joint = "hips"
		# A-pose arms and splayed legs: rotate each limb so that its rest direction hangs straight down,
		# matching the proxy rig the procedural poses were authored on. Forearms and shins follow.
		var limb_pairs := {"arm_l": "forearm_l", "arm_r": "forearm_r", "thigh_l": "shin_l", "thigh_r": "shin_r"}
		for j in limb_pairs:
			var c: String = limb_pairs[j]
			if not idx.has(j) or not idx.has(c):
				continue
			var a := to_char * s.get_bone_global_rest(int(idx[j])).origin
			var b := to_char * s.get_bone_global_rest(int(idx[c])).origin
			var d := (b - a)
			if d.length() < 0.001:
				continue
			d = d.normalized()
			var axis := d.cross(Vector3.DOWN)
			if axis.length() < 0.0001:
				continue
			var ang := d.angle_to(Vector3.DOWN)
			pre[j] = Basis(axis.normalized(), ang)

	func set_root(xf: Transform3D) -> void:
		_apply(root_joint, xf.basis, xf.origin)

	func set_joint(joint: String, b: Basis, offset: Vector3) -> void:
		if joint == root_joint:
			return
		_apply(joint, b, offset)

	func _apply(joint: String, b: Basis, offset: Vector3) -> void:
		if not idx.has(joint):
			return
		var i: int = idx[joint]
		var bb: Basis = conj[joint]
		var sc := b.get_scale()
		var rb := b.orthonormalized()
		if pre.has(joint):
			rb = rb * (pre[joint] as Basis)
		var delta := bb.inverse() * rb * bb
		var r: Transform3D = rest_local[joint]
		skel.set_bone_pose_rotation(i, (r.basis.orthonormalized() * delta).get_rotation_quaternion())
		var pb: Basis = parent_conj[joint]
		skel.set_bone_pose_position(i, r.origin + pb.inverse() * offset)
		if not sc.is_equal_approx(Vector3.ONE):
			skel.set_bone_pose_scale(i, (bb.inverse() * Basis.from_scale(sc) * bb).get_scale())

extends Node
## Rig probe (player workstream diagnostic): loads Player.tscn, forces known joint rotations through
## the skeleton adapter and prints where the limbs actually point in character space.
## Run: python tools/godot.py run res://scenes/tests/RigProbe.tscn --headless --seconds 3 -- --profile=player-probe

var _frames := 0
var _player: Node3D


func _ready() -> void:
	var ps := load("res://scenes/player/Player.tscn") as PackedScene
	_player = ps.instantiate() as Node3D
	add_child(_player)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 2:
		var a0: Node = _player.get_node("Animator")
		var sk0: Skeleton3D = a0.get("skeleton")
		var v0: Node3D = _player.get_node("Visual")
		var t0 := (v0.global_transform.affine_inverse() * sk0.global_transform)
		for bn in ["root", "hips", "spine", "chest", "neck", "head", "head_top", "thigh_r", "shin_r", "foot_r", "arm_r", "forearm_r", "hand_r", "ear_r", "tail", "backpack"]:
			var bi := sk0.find_bone(bn)
			if bi >= 0:
				print("[RigProbe] rest %-10s %s" % [bn, t0 * sk0.get_bone_global_rest(bi).origin])
	if _frames == 3:
		_player.call("celebrate", 3.0)
	if _frames in [20, 30, 40]:
		var anim2: Node = _player.get_node("Animator")
		var sk: Skeleton3D = anim2.get("skeleton")
		var vis2: Node3D = _player.get_node("Visual")
		var tc := (vis2.global_transform.affine_inverse() * sk.global_transform)
		var rot: Dictionary = anim2.get("_rot")
		for pair in [["arm_r", "forearm_r"], ["arm_l", "forearm_l"]]:
			var a := sk.find_bone(pair[0])
			var b := sk.find_bone(pair[1])
			var d := (tc * sk.get_bone_global_pose(b).origin - tc * sk.get_bone_global_pose(a).origin).normalized()
			print("[RigProbe] live f%d state=%s %s target_rot_deg=%s dir=%s" % [_frames, _player.get("state"), pair[0], (rot[pair[0]] as Vector3) * 180.0 / PI, d])
	if _frames != 45:
		return
	var anim: Node = _player.get_node("Animator")
	var skel: Skeleton3D = anim.get("skeleton")
	if skel == null:
		print("[RigProbe] no skeleton (proxy in use)")
		get_tree().quit()
		return
	var adapter: RefCounted = anim.get("adapter")
	anim.set_process(false)
	var vis: Node3D = _player.get_node("Visual")
	var to_char := (vis.global_transform.affine_inverse() * skel.global_transform)
	for test in [["rest", Vector3.ZERO], ["x+90 (forward)", Vector3(90, 0, 0)], ["x+150", Vector3(150, 0, 0)], ["z+60 (out, right arm)", Vector3(0, 0, 60)]]:
		var e: Vector3 = test[1] * PI / 180.0
		for j in ["arm_l", "forearm_l", "arm_r", "forearm_r", "thigh_r", "shin_r"]:
			adapter.call("set_joint", j, Basis.IDENTITY, Vector3.ZERO)
		adapter.call("set_joint", "arm_r", Basis.from_euler(e), Vector3.ZERO)
		adapter.call("set_joint", "thigh_r", Basis.from_euler(e), Vector3.ZERO)
		skel.force_update_all_bone_transforms()
		for pair in [["arm_r", "forearm_r"], ["forearm_r", "hand_r"], ["thigh_r", "shin_r"]]:
			var a := skel.find_bone(pair[0])
			var b := skel.find_bone(pair[1])
			if a < 0 or b < 0:
				continue
			var pa := to_char * skel.get_bone_global_pose(a).origin
			var pb := to_char * skel.get_bone_global_pose(b).origin
			print("[RigProbe] %-22s %-10s dir %s" % [test[0], pair[0], (pb - pa).normalized()])
	get_tree().quit()

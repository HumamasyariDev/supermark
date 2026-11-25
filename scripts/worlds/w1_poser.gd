class_name W1Poser
extends Node
## Fix round 1 (fun critic r1: "the Foreman and the NPCs are rest-pose statues"): a small procedural poser for the
## rigged W1 character GLBs (shared bone names root/hips/spine/chest/head/arm_*/forearm_*/thigh_*/shin_*/tail).
## Rotations are applied in skeleton space around each joint (the same formula as enemy_base.gd), on top of the rest
## pose, so no AnimationPlayer is needed. Modes: idle, talk, whistle, windup, charge, burst, flee, huff, cheer.
## `arm_down_deg` rotates both arms down from the rest pose first (a rig modelled with raised arms gets a relaxed idle).

var skeleton: Skeleton3D
var mode := "idle"
var arm_down_deg := 0.0
var speed := 1.0
var t := 0.0
var _ids: Dictionary = {}
var _rest: Dictionary = {}
var _pb: Dictionary = {}
var _phase := 0.0


static func attach(model_root: Node, arm_down := 0.0) -> W1Poser:
	if model_root == null:
		return null
	var sk := model_root.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return null
	var p := W1Poser.new()
	p.name = "Poser"
	p.arm_down_deg = arm_down
	p.skeleton = sk[0] as Skeleton3D
	model_root.add_child(p)
	p._phase = randf() * TAU
	return p


func _ready() -> void:
	if skeleton == null:
		return
	for pname in ["hips", "spine", "chest", "head", "arm_l", "arm_r", "forearm_l", "forearm_r", "thigh_l", "thigh_r", "shin_l", "shin_r", "tail"]:
		var i := skeleton.find_bone(pname)
		if i < 0:
			continue
		_ids[pname] = i
		_rest[pname] = skeleton.get_bone_rest(i).basis
		var par := skeleton.get_bone_parent(i)
		_pb[pname] = skeleton.get_bone_global_rest(par).basis if par >= 0 else Basis()


func set_mode(m: String) -> void:
	if m != mode:
		mode = m
		t = 0.0


func _rot(pname: String, euler_deg: Vector3) -> void:
	if not _ids.has(pname):
		return
	var r := Basis.from_euler(euler_deg * (PI / 180.0))
	var pb: Basis = _pb[pname]
	var local: Basis = pb.inverse() * r * pb * (_rest[pname] as Basis)
	skeleton.set_bone_pose_rotation(_ids[pname], local.orthonormalized().get_rotation_quaternion())


func _process(delta: float) -> void:
	if skeleton == null or not is_instance_valid(skeleton) or not skeleton.is_visible_in_tree():
		return
	t += delta * speed
	var ph := t + _phase
	var ad := arm_down_deg
	# Defaults: a breathing idle with a slow arm sway (model faces +Z; +X rotation leans toward +Z).
	var spine := Vector3(2.0 * sin(ph * 1.6), 0, 0)
	var head := Vector3(3.0 * sin(ph * 1.6 + 0.6), 6.0 * sin(ph * 0.5), 0)
	var al := Vector3(6.0 * sin(ph * 1.1), 0, -ad - 3.0 * sin(ph * 1.6))
	var ar := Vector3(-6.0 * sin(ph * 1.1), 0, ad + 3.0 * sin(ph * 1.6))
	var fl := Vector3(-8.0, 0, 0)
	var fr := Vector3(-8.0, 0, 0)
	var tl := Vector3.ZERO
	var tr := Vector3.ZERO
	var sl := Vector3.ZERO
	var sr := Vector3.ZERO
	var tail := Vector3(0, 18.0 * sin(ph * 2.4), 0)
	match mode:
		"talk":
			head = Vector3(8.0 * sin(ph * 6.0), 10.0 * sin(ph * 1.3), 0)
			ar = Vector3(-35.0 - 12.0 * sin(ph * 4.0), 0, ad - 20.0)
			fr = Vector3(-40.0, 0, 0)
		"cheer":
			al = Vector3(0, 0, -ad + 95.0 + 10.0 * sin(ph * 9.0))
			ar = Vector3(0, 0, ad - 95.0 - 10.0 * sin(ph * 9.0))
			spine = Vector3(-6.0, 0, 0)
		"whistle":
			al = Vector3(-30.0, 0, -ad + 70.0)
			ar = Vector3(-60.0, 0, ad - 40.0)
			fr = Vector3(-90.0, 0, 0)
			head = Vector3(-14.0, 0, 0)
			spine = Vector3(-8.0, 0, 0)
		"windup":
			spine = Vector3(22.0, 0, 0)
			head = Vector3(-18.0, 0, 0)
			al = Vector3(30.0, 0, -ad)
			ar = Vector3(30.0, 0, ad)
			tr = Vector3(-40.0 * absf(sin(ph * 9.0)), 0, 0)
			sr = Vector3(35.0 * absf(sin(ph * 9.0)), 0, 0)
		"charge", "flee":
			var s := sin(ph * 15.0)
			spine = Vector3(26.0 if mode == "charge" else 10.0, 0, 0)
			head = Vector3(-20.0 if mode == "charge" else -5.0, 0, 0)
			tl = Vector3(40.0 * s, 0, 0)
			tr = Vector3(-40.0 * s, 0, 0)
			sl = Vector3(45.0 * maxf(-s, 0.0), 0, 0)
			sr = Vector3(45.0 * maxf(s, 0.0), 0, 0)
			if mode == "flee":
				al = Vector3(0, 0, -ad + 100.0 + 15.0 * s)
				ar = Vector3(0, 0, ad - 100.0 + 15.0 * s)
			else:
				al = Vector3(-35.0 * s, 0, -ad)
				ar = Vector3(35.0 * s, 0, ad)
			tail = Vector3(0, 35.0 * s, 0)
		"burst":
			al = Vector3(0, 0, -ad + 80.0)
			ar = Vector3(0, 0, ad - 80.0)
			head = Vector3(-20.0, 0, 0)
			spine = Vector3(-12.0, 0, 0)
		"huff":
			var k := clampf(t / 1.2, 0.0, 1.0)
			spine = Vector3(-14.0 * k, 0, 0)
			head = Vector3(-10.0 * k + 4.0 * sin(ph * 20.0), 0, 0)
			al = Vector3(0, 0, -ad + 45.0 * k)
			ar = Vector3(0, 0, ad - 45.0 * k)
	_rot("spine", spine)
	_rot("head", head)
	_rot("arm_l", al)
	_rot("arm_r", ar)
	_rot("forearm_l", fl)
	_rot("forearm_r", fr)
	_rot("thigh_l", tl)
	_rot("thigh_r", tr)
	_rot("shin_l", sl)
	_rot("shin_r", sr)
	_rot("tail", tail)

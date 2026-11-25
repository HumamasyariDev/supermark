extends Node3D
## TOPUP_HUB round 4 motion check (test stage only): mak_v2 (left, shipped) and mak_v4 (right, round 4 beanie) side by side while
## both ears sweep through forward, back and spread poses and a landing squash plays, with a slow camera arc.
## Movie: python tools/godot.py movie res://assets/props/hub/_topup_v4_fix_r4/TopupR4Motion.tscn <out.avi> --frames 300 -- --profile=assets3_hub

const MAK := "res://assets/characters/mak/"
var _t := 0.0
var _maks: Array = []
var _cam: Camera3D

func _ready() -> void:
	var we := WorldEnvironment.new()
	we.environment = load("res://assets/shaders/environments/env_HUB.tres") as Environment
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1, 0.76, 0.48)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-38, 35, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-25, 200, 0)
	add_child(fill)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.23, 0.13)
	var f := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	f.mesh = pm
	f.material_override = fm
	add_child(f)
	var x := -0.55
	for file in ["mak_v2.glb", "mak_v4.glb"]:
		var ps := load(MAK + file) as PackedScene
		if ps == null:
			continue
		var m := ps.instantiate() as Node3D
		add_child(m)
		m.position = Vector3(x, 0, 0)
		var sks := m.find_children("*", "Skeleton3D", true, false)
		_maks.append({"node": m, "sk": sks[0] if sks.size() > 0 else null})
		var lab := Label3D.new()
		lab.text = "v2 (shipped)" if file == "mak_v2.glb" else "v4 (round 4)"
		lab.font_size = 36
		lab.position = Vector3(x, 1.5, 0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(lab)
		x += 1.1
	_cam = Camera3D.new()
	_cam.fov = 32.0
	add_child(_cam)
	_cam.make_current()

func _process(delta: float) -> void:
	_t += delta
	# ear cycle (4 s): forward 40 -> back 25 -> spread 25 -> rest
	var ph := fmod(_t, 4.0) / 4.0
	var fwd := 0.0
	var spread := 0.0
	if ph < 0.25:
		fwd = 40.0 * sin(ph / 0.25 * PI)
	elif ph < 0.5:
		fwd = -25.0 * sin((ph - 0.25) / 0.25 * PI)
	elif ph < 0.75:
		spread = 25.0 * sin((ph - 0.5) / 0.25 * PI)
	var sq := 0.0
	if ph > 0.8:
		sq = sin((ph - 0.8) / 0.2 * PI)
	for e in _maks:
		var sk := e["sk"] as Skeleton3D
		if sk:
			sk.reset_bone_poses()
			_rot(sk, "ear_l", Vector3.RIGHT, fwd)
			_rot(sk, "ear_r", Vector3.RIGHT, fwd)
			_rot(sk, "ear_l", Vector3.BACK, -spread)
			_rot(sk, "ear_r", Vector3.BACK, spread)
		var n := e["node"] as Node3D
		n.scale = Vector3(1.0 + 0.15 * sq, 1.0 - 0.2 * sq, 1.0 + 0.15 * sq)
	var a := deg_to_rad(25.0 + 50.0 * sin(_t * 0.35))
	var target := Vector3(0.0, 1.0, 0.0)
	_cam.look_at_from_position(target + Vector3(sin(a) * 3.0, 0.45, cos(a) * 3.0), target, Vector3.UP)

func _rot(skel: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	if absf(deg) < 0.01:
		return
	var i := skel.find_bone(bone)
	if i < 0:
		return
	var par := skel.get_bone_parent(i)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var g := skel.get_bone_global_pose(i)
	var nb := Basis(axis.normalized(), deg_to_rad(deg)) * g.basis
	skel.set_bone_pose_rotation(i, (pg.basis.inverse() * nb).get_rotation_quaternion())

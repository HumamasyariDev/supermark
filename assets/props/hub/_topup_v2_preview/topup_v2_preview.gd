extends Node3D
## Look-dev stage for the TOPUP_HUB v2 meshes (night 01). Not gameplay, not used by any level.
## Uses the hub's environment (env_HUB.tres) and the hub sun colour. Two identical sets:
## "New" (v2 Tripo P2 models) at the origin and "Before" (the procedural models they replace) 40 m to +X,
## each with the same camera framings, so before/after captures match. The v2 set animates its pivots
## (clock pendulum and hands, chandelier sway, truffle spin) to verify the node setup.

const HUB := "res://assets/props/hub/"
const PICK := "res://assets/props/pickups/"
const MAK := "res://assets/characters/mak/"
const BEFORE_X := 40.0

var _t := 0.0
var _pend: Node3D
var _hh: Node3D
var _hm: Node3D
var _sway: Node3D
var _truffle: Node3D
var _acorn: Node3D

func _ready() -> void:
	_stage()
	var attach: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAK + "attach.json"))
	for set_i in 2:
		var new_set := set_i == 0
		var root := Node3D.new()
		root.name = "New" if new_set else "Before"
		root.position = Vector3(0.0 if new_set else BEFORE_X, 0, 0)
		add_child(root)
		var sfx := "_v2" if new_set else ""
		_spawn(root, HUB + "wingback_armchair%s/wingback_armchair%s.glb" % [sfx, sfx], Vector3(-3.3, 0, 0), 18.0)
		_spawn(root, HUB + "grandfather_clock%s/grandfather_clock%s.glb" % [sfx, sfx], Vector3(-1.5, 0, -0.6), 6.0)
		_spawn(root, HUB + "tea_table_set%s/tea_table_set%s.glb" % [sfx, sfx], Vector3(0.6, 0, 0.2), -10.0)
		var ch := _spawn(root, HUB + "brass_chandelier%s/brass_chandelier%s.glb" % [sfx, sfx], Vector3(3.3, 0.9, -0.8), 0.0)
		var tr := _spawn(root, PICK + "golden_truffle%s/golden_truffle%s.glb" % [sfx, sfx], Vector3(0.55, 0.25, 2.6), -15.0)
		var ac := _spawn(root, PICK + "acorn%s/acorn%s.glb" % [sfx, sfx], Vector3(1.35, 0.2, 2.75), 20.0)
		var body := _spawn(root, MAK + "mak_body.glb", Vector3(-0.75, 0, 2.6), 18.0)
		var skel := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		_attach(skel, "head_top", MAK + ("mak_beanie_v2.glb" if new_set else "mak_beanie.glb"), attach["mak_beanie"])
		_attach(skel, "backpack", MAK + "mak_backpack.glb", attach["mak_backpack"])
		_cam(root, "Cam_Wide", Vector3(0.2, 2.3, 8.2), Vector3(0.0, 1.0, 0.6), 50.0)
		_cam(root, "Cam_Mak", Vector3(-0.35, 1.25, 4.15), Vector3(-0.75, 0.93, 2.6), 32.0)
		_cam(root, "Cam_Pickups", Vector3(0.95, 0.75, 4.0), Vector3(0.95, 0.42, 2.65), 40.0)
		_cam(root, "Cam_Hub", Vector3(0.0, 2.0, 5.6), Vector3(0.0, 1.15, -0.2), 55.0)
		if new_set:
			var clk := root.find_child("grandfather_clock_v2", true, false)
			if clk:
				_pend = clk.find_child("pendulum", true, false) as Node3D
				_hh = clk.find_child("hand_hour", true, false) as Node3D
				_hm = clk.find_child("hand_minute", true, false) as Node3D
			_sway = ch.find_child("sway_pivot", true, false) as Node3D
			_truffle = tr
			_acorn = ac
			if _sway:
				for c in _sway.get_children():
					if c.name.begins_with("candle_"):
						_flame_marker(c as Node3D)
	_compare_rigs()
	# mak_v2.glb (default outfit with the v2 beanie) in a test pose: head turned and tilted, arm up
	var m2 := _spawn(get_node("New") as Node3D, MAK + "mak_v2.glb", Vector3(-2.1, 0, 2.9), 35.0)
	var sk2 := m2.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_rot_model(sk2, "head", Vector3(0, 1, 0), 25.0)
	_rot_model(sk2, "head", Vector3(0, 0, 1), 12.0)
	_rot_model(sk2, "arm_l", Vector3(0, 0, 1), 60.0)
	_cam(get_node("New") as Node3D, "Cam_MakPose", Vector3(-1.5, 1.2, 4.6), Vector3(-2.1, 0.85, 2.9), 34.0)
	print("[TopupPreview] pendulum=", _pend != null, " hands=", _hh != null and _hm != null, " sway=", _sway != null)

func _process(delta: float) -> void:
	_t += delta
	if _pend:
		_pend.rotation.z = deg_to_rad(4.0) * sin(_t * TAU / 1.6)
	if _hm:
		_hm.rotation.z = -_t * 0.6
	if _hh:
		_hh.rotation.z = -_t * 0.05
	if _sway:
		_sway.rotation.z = deg_to_rad(1.5) * sin(_t * TAU / 6.0)
	if _truffle:
		_truffle.rotation.y = _t * 1.6
		_truffle.position.y = 0.25 + 0.06 * sin(_t * 2.4)
	if _acorn:
		_acorn.rotation.y = _t * 2.0

func _spawn(parent: Node3D, path: String, pos: Vector3, yaw: float) -> Node3D:
	var ps := load(path) as PackedScene
	var n := ps.instantiate() as Node3D
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	return n

func _attach(skel: Skeleton3D, bone: String, path: String, a: Dictionary) -> void:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	var p := (load(path) as PackedScene).instantiate() as Node3D
	ba.add_child(p)
	var o: Array = a["offset"]
	p.position = Vector3(o[0], o[1], o[2])

func _cam(parent: Node3D, cam_name: String, pos: Vector3, look: Vector3, fov: float) -> void:
	var c := Camera3D.new()
	c.name = cam_name + ("_v2" if parent.name == "New" else "_before")
	parent.add_child(c)
	c.position = pos
	c.fov = fov
	c.look_at_from_position(parent.position + pos, parent.position + look, Vector3.UP)

func _flame_marker(m: Node3D) -> void:
	# a tiny emissive teardrop at each candle marker: checks the marker positions sit on the wicks
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.11
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.78, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.position = Vector3(0, 0.05, 0)
	m.add_child(mi)

func _stage() -> void:
	var we := WorldEnvironment.new()
	we.environment = load("res://assets/shaders/environments/env_HUB.tres") as Environment
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1, 0.76, 0.48)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-38, 35, 0)
	add_child(sun)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.36, 0.23, 0.13)
	floor_mat.roughness = 0.7
	for x in [0.0, BEFORE_X]:
		var f := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(26, 18)
		f.mesh = pm
		f.material_override = floor_mat
		f.position = Vector3(x, 0, 0)
		add_child(f)
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.78, 0.45)
		o.light_energy = 2.0
		o.omni_range = 9.0
		o.position = Vector3(x + 1.0, 3.2, 3.0)
		add_child(o)

func _compare_rigs() -> void:
	var a := (load(MAK + "mak.glb") as PackedScene).instantiate()
	var b := (load(MAK + "mak_v2.glb") as PackedScene).instantiate()
	var sa := a.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var sb := b.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var worst := 0.0
	var missing := 0
	for i in sa.get_bone_count():
		var j := sb.find_bone(sa.get_bone_name(i))
		if j < 0:
			missing += 1
			continue
		var ta := sa.get_bone_global_rest(i)
		var tb := sb.get_bone_global_rest(j)
		worst = maxf(worst, ta.origin.distance_to(tb.origin))
		worst = maxf(worst, (ta.basis.x - tb.basis.x).length() + (ta.basis.y - tb.basis.y).length())
	var names: Array[String] = []
	for n in b.find_children("*", "MeshInstance3D", true, false):
		names.append(String(n.name))
	print("[TopupPreview] rig compare mak vs mak_v2: bones=", sa.get_bone_count(), "/", sb.get_bone_count(), " missing=", missing, " worst_rest_delta=", worst, " meshes=", names)
	a.free()
	b.free()

## Rotate a bone about a model-space axis through its own origin (same helper as MakLookdev).
func _rot_model(skel: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	var i := skel.find_bone(bone)
	var par := skel.get_bone_parent(i)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var g := skel.get_bone_global_pose(i)
	var nb := Basis(axis.normalized(), deg_to_rad(deg)) * g.basis
	skel.set_bone_pose_rotation(i, (pg.basis.inverse() * nb).get_rotation_quaternion())

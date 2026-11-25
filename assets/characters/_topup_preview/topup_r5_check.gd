extends Node3D
## ASSETS3_CHARS round 5 look-dev check (not gameplay). "-- --only=<group>":
##   cow        Daisy v2 (current) vs v3 (open mouth): v2 at jaw -10 (npc_life talk today), v3 at 0 / +12 / +20 / -10.
##              Cameras Cam_cow (row), Cam_cow_P<i> (close per figure, front 3/4).
##   orm        Bramwell, golden goose: v1 | v2 (AO in ORM.R + roughness floor), sun dimmed. Cam_orm, Cam_orm_Close.
##   wolf       Wolf boss v1 | v2. Cam_wolf, Cam_wolf_Close.
##   cow_motion Daisy v3 moo / chew loop next to v2 for Movie Maker. Cam_cow_motion.
## Left of each pair on screen = before. The cameras look along +Z, so +X is screen left.

const C := "res://assets/characters/"
var _only := "cow"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	_stage()
	match _only:
		"cow": _cow()
		"orm": _orm()
		"wolf": _wolf()
		"cow_motion": _cow_motion()

var _frames := 0
var _anim: Array = []
var _t := 0.0
func _process(d: float) -> void:
	_frames += 1
	_t += d
	for e in _anim:
		var sk: Skeleton3D = e[0]
		sk.reset_bone_poses()
		for b in e[1]:
			_rot_model(sk, b[0], b[1], b[2] + b[3] * sin(TAU * (_t / b[4]) + b[5]))
	if _frames > 20:
		return
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		if not is_ancestor_of(n):
			(n as VisualInstance3D).visible = false

func _cow() -> void:
	var figs := [["daisy_cow/daisy_cow_v2.glb", -10.0, "v2 jaw -10 (today)"], ["daisy_cow/daisy_cow_v3.glb", 0.0, "v3 closed"],
		["daisy_cow/daisy_cow_v3.glb", 12.0, "v3 jaw +12"], ["daisy_cow/daisy_cow_v3.glb", 20.0, "v3 jaw +20"], ["daisy_cow/daisy_cow_v3.glb", -10.0, "v3 jaw -10"]]
	for i in figs.size():
		var x := 3.0 * (2 - i)
		var n := _spawn(C + figs[i][0], Vector3(x, 0, 0), 25.0)
		_apply(n, {"jaw": [Vector3(1, 0, 0), figs[i][1]]})
		_label(figs[i][2], Vector3(x, 1.95, 0))
		var hd := Vector3(x - 0.46, 0.9, -1.0)
		_cam("Cam_cow_P%d" % i, hd + Vector3(-0.15, 0.12, -1.25), hd, 40.0)
	_cam("Cam_cow", Vector3(0, 1.8, -10.5), Vector3(0, 0.9, 0), 50.0)

func _orm() -> void:
	var pairs := [["bramwell/bramwell.glb", "bramwell/bramwell_v2.glb", 0.0], ["golden_goose/golden_goose.glb", "golden_goose/golden_goose_v2.glb", 0.0]]
	var x := 0.0
	for p in pairs:
		_spawn(C + p[0], Vector3(x + 0.7, 0, 0), p[2])
		_spawn(C + p[1], Vector3(x - 0.7, 0, 0), p[2])
		_label("before | after", Vector3(x, 1.85, 0))
		x -= 3.0
	for n in find_children("*", "DirectionalLight3D", true, false):
		(n as DirectionalLight3D).light_energy = 0.45
	_cam("Cam_orm", Vector3(-1.5, 1.2, -4.6), Vector3(-1.5, 0.7, 0), 50.0)
	_cam("Cam_orm_Close", Vector3(0.0, 1.25, -2.4), Vector3(0.0, 0.95, 0), 45.0)

func _wolf() -> void:
	_spawn(C + "wolf_boss/wolf_boss.glb", Vector3(1.6, 0, 0), 0.0)
	_spawn(C + "wolf_boss/wolf_boss_v2.glb", Vector3(-1.6, 0, 0), 0.0)
	_label("before | after", Vector3(0, 4.6, 0))
	for n in find_children("*", "DirectionalLight3D", true, false):
		(n as DirectionalLight3D).light_energy = 0.6
	_cam("Cam_wolf", Vector3(0, 2.6, -9.0), Vector3(0, 2.0, 0), 50.0)
	_cam("Cam_wolf_Close", Vector3(0, 3.4, -4.2), Vector3(0, 3.0, 0), 50.0)

## Moo loop: v3 opens to +22 and closes (1.6 s), with a chew between; v2 next to it doing what npc_life does today (-10).
func _cow_motion() -> void:
	var a := _skel(_spawn(C + "daisy_cow/daisy_cow_v2.glb", Vector3(1.5, 0, 0), 35.0))
	var b := _skel(_spawn(C + "daisy_cow/daisy_cow_v3.glb", Vector3(-1.5, 0, 0), 20.0))
	_anim.append([a, [["jaw", Vector3(1, 0, 0), -5.0, 5.0, 0.8, 0.0], ["head", Vector3(1, 0, 0), -4.0, 4.0, 3.2, 0.0]]])
	_anim.append([b, [["jaw", Vector3(1, 0, 0), 11.0, 11.0, 1.6, -PI * 0.5], ["head", Vector3(1, 0, 0), -6.0, 6.0, 3.2, 0.0]]])
	_label("v2 (today)", Vector3(1.5, 1.95, 0))
	_label("v3 moo", Vector3(-1.5, 1.95, 0))
	_cam("Cam_cow_motion", Vector3(-0.6, 1.25, -4.2), Vector3(-0.3, 0.95, 0), 45.0)

# ---------------------------------------------------------------- helpers (same conventions as the critic scenes)

func _row(path: String, poses: Array, dx: float, x0: float, z: float, scale := 1.0) -> void:
	var i := 0
	for p in poses:
		var yaw := 0.0
		if p.has("_yaw"):
			yaw = p["_yaw"]
		var n := _spawn(C + path, Vector3(x0 + i * dx, 0, z), yaw, scale)
		_apply(n, p)
		i += 1

func _apply(n: Node3D, pose: Dictionary) -> void:
	var s := _skel(n)
	if s == null:
		return
	for bone in pose.keys():
		if String(bone).begins_with("_"):
			continue
		_rot_model(s, bone, pose[bone][0], pose[bone][1])

func _spawn(path: String, pos: Vector3, yaw_deg: float, scale := 1.0) -> Node3D:
	var visual := Node3D.new()
	add_child(visual)
	visual.position = pos
	visual.rotation_degrees = Vector3(0, 180.0 + yaw_deg, 0)
	visual.scale = Vector3.ONE * scale
	var n := (load(path) as PackedScene).instantiate() as Node3D
	visual.add_child(n)
	return n

func _skel(n: Node3D) -> Skeleton3D:
	var s := n.find_children("*", "Skeleton3D", true, false)
	return s[0] as Skeleton3D if s.size() > 0 else null

func _rot_model(skel: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	var i := skel.find_bone(bone)
	if i < 0:
		return
	var par := skel.get_bone_parent(i)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var g := skel.get_bone_global_pose(i)
	var nb := Basis(axis.normalized(), deg_to_rad(deg)) * g.basis
	skel.set_bone_pose_rotation(i, (pg.basis.inverse() * nb).get_rotation_quaternion())

func _label(t: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = t
	l.position = pos
	l.rotation_degrees = Vector3(0, 180, 0)
	l.font_size = 64
	l.pixel_size = 0.004
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)

func _cam(n: String, pos: Vector3, target: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	cam.name = n
	cam.fov = fov
	add_child(cam)
	cam.look_at_from_position(pos, target)

func _stage() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.62, 0.9)
	sm.sky_horizon_color = Color(0.86, 0.88, 0.92)
	sm.ground_horizon_color = Color(0.8, 0.76, 0.7)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 155, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.62, 0.72, 0.52)
	ground.material_override = gm
	add_child(ground)

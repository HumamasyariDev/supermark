extends Node3D
## TOPUP_CHARS critique round 1 (ASSET QA lens). Test scene only, not gameplay.
## One row per character: Mr. Mak for scale, then the model in a battery of skeleton test poses
## (rest, idle arms-down, cheer arms-up, stride, crouch, head turn + elbow bend), then the back and side views.
## Cameras: Cam_<id> (front of the row), Cam_<id>_Back (back side, from +Z), Cam_<id>_Close (face close-up of pose 1).
## Every model is wrapped in a Visual rotated 180 degrees about Y (glTF +Z front -> game -Z), as TECH_CONTRACT asks.

const C := "res://assets/characters/"
const ROW_DZ := 9.0

var _row := 0
var _only := ""

## Pass "-- --only=<id>" (snap, foreman, underwear, jack, hazel, bertram, pip, sheep, cow, giant, scarecrow) to build one row alone.
func _want(id: String) -> bool:
	return _only == "" or _only == id

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	_stage()
	if _only == "sweep":
		_sweep_setup()
		return
	if _want("snap"): _biped("snap", "sergeant_snap/sergeant_snap.glb", 1.6, 1.5)
	if _want("foreman"): _biped("foreman", "foreman/foreman.glb", 1.9, 2.3)
	if _want("underwear"): _biped("underwear", "foreman/foreman_underwear.glb", 1.9, 2.3)
	if _want("jack"): _biped("jack", "jack/jack.glb", 1.5, 1.4)
	if _want("hazel"): _biped("hazel", "hazel/hazel.glb", 0.95, 1.0)
	if _want("bertram"): _biped("bertram", "bertram/bertram.glb", 1.0, 1.0)
	if _want("pip"): _biped("pip", "pip_v2/pip_v2.glb", 0.95, 1.0)
	if _want("sheep"): _quad("sheep", "real_sheep/real_sheep.glb", 0.9, 1.4)
	if _want("cow"): _quad("cow", "daisy_cow/daisy_cow.glb", 1.6, 2.2)
	if _want("giant"): _giant()
	if _want("scarecrow"): _scarecrow()

# ---------------------------------------------------------------- rows

func _biped(id: String, path: String, h: float, dx: float) -> void:
	var z := _row * ROW_DZ
	_row += 1
	_spawn(C + "mak/mak.glb", Vector3(-dx, 0, z), 0.0)
	var poses := [
		{},
		{"arm_l": [Vector3(0, 0, 1), -45.0], "arm_r": [Vector3(0, 0, 1), 45.0]},
		{"arm_l": [Vector3(0, 0, 1), 80.0], "arm_r": [Vector3(0, 0, 1), -80.0]},
		{"thigh_l": [Vector3(1, 0, 0), -40.0], "shin_l": [Vector3(1, 0, 0), 35.0], "thigh_r": [Vector3(1, 0, 0), 30.0], "shin_r": [Vector3(1, 0, 0), 25.0],
			"arm_r": [Vector3(1, 0, 0), -35.0], "arm_l": [Vector3(1, 0, 0), 35.0]},
		{"spine": [Vector3(1, 0, 0), 20.0], "thigh_l": [Vector3(1, 0, 0), -70.0], "shin_l": [Vector3(1, 0, 0), 95.0], "thigh_r": [Vector3(1, 0, 0), -70.0], "shin_r": [Vector3(1, 0, 0), 95.0]},
		{"head": [Vector3(0, 1, 0), 45.0], "spine": [Vector3(0, 1, 0), 15.0], "forearm_l": [Vector3(0, 1, 0), -90.0], "forearm_r": [Vector3(0, 1, 0), 90.0], "tail": [Vector3(0, 0, 1), 35.0]},
	]
	var i := 0
	for p in poses:
		var n := _spawn(C + path, Vector3(i * dx, 0, z), 0.0)
		_apply(n, p)
		i += 1
	# back and side views of the idle pose
	var b := _spawn(C + path, Vector3(i * dx, 0, z), 180.0)
	_apply(b, poses[1])
	var s := _spawn(C + path, Vector3((i + 1) * dx, 0, z), 90.0)
	_apply(s, poses[3])
	var mid := Vector3((poses.size() + 1) * dx * 0.5 - dx * 0.5, h * 0.55, z)
	var width := (poses.size() + 3) * dx
	var dist := width * 0.5 / tan(deg_to_rad(21.0)) * 0.5
	_cam("Cam_" + id, mid + Vector3(0, h * 0.35, -dist), mid, 42.0)
	_cam("Cam_" + id + "_Back", mid + Vector3(0, h * 0.35, dist), mid, 42.0)
	_cam("Cam_" + id + "_Close", Vector3(dx, h * 0.8, z - h * 1.6), Vector3(dx, h * 0.62, z), 40.0)

func _quad(id: String, path: String, h: float, dx: float) -> void:
	var z := _row * ROW_DZ
	_row += 1
	_spawn(C + "mak/mak.glb", Vector3(-dx, 0, z), 0.0)
	var poses := [
		{},
		{"head": [Vector3(1, 0, 0), 40.0]},
		{"head": [Vector3(0, 1, 0), 40.0], "tail": [Vector3(0, 0, 1), 40.0], "tail_2": [Vector3(0, 0, 1), 40.0]},
		{"leg_fl": [Vector3(1, 0, 0), -30.0], "leg_br": [Vector3(1, 0, 0), -30.0], "leg_fr": [Vector3(1, 0, 0), 30.0], "leg_bl": [Vector3(1, 0, 0), 30.0], "body": [Vector3(0, 0, 1), 6.0]},
	]
	var i := 0
	for p in poses:
		_apply(_spawn(C + path, Vector3(i * dx, 0, z), -35.0 if i == 0 else 0.0), p)
		i += 1
	_apply(_spawn(C + path, Vector3(i * dx, 0, z), 180.0), {})
	_apply(_spawn(C + path, Vector3((i + 1) * dx, 0, z), 90.0), poses[1])
	_apply(_spawn(C + path, Vector3((i + 2) * dx, 0, z), -90.0), poses[3])
	var mid := Vector3((poses.size() + 2) * dx * 0.5 - dx * 0.5, h * 0.5, z)
	var width := (poses.size() + 4) * dx
	var dist := width * 0.5 / tan(deg_to_rad(21.0)) * 0.62
	_cam("Cam_" + id, mid + Vector3(0, h * 0.5, -dist), mid, 42.0)
	_cam("Cam_" + id + "_Back", mid + Vector3(0, h * 0.5, dist), mid, 42.0)
	_cam("Cam_" + id + "_Close", Vector3(0, h * 0.8, z - h * 1.4), Vector3(0, h * 0.6, z), 40.0)

func _giant() -> void:
	var z := _row * ROW_DZ + 6.0
	_row += 3
	_spawn(C + "mak/mak.glb", Vector3(-6.5, 0, z - 2.0), 0.0)
	var a := _spawn(C + "sleeping_giant/sleeping_giant.glb", Vector3(-4.0, 0, z), 0.0)
	var b := _spawn(C + "sleeping_giant/sleeping_giant.glb", Vector3(4.0, 0, z), 0.0)
	# b: the W2 "startle sit-up" (chest and head up, head lift) with the jaw open and nostrils flared
	_apply(b, {"jaw": [Vector3(1, 0, 0), 16.0], "chest": [Vector3(1, 0, 0), -12.0], "cap_tip": [Vector3(0, 0, 1), 30.0]})
	var sk := _skel(b)
	if sk:
		var hi := sk.find_bone("head")
		if hi >= 0:
			sk.set_bone_pose_position(hi, sk.get_bone_pose_position(hi) + Vector3(0, 0.5, 0))
		var ni := sk.find_bone("nostrils")
		if ni >= 0:
			sk.set_bone_pose_scale(ni, Vector3.ONE * 1.35)
	var c := _spawn(C + "sleeping_giant/sleeping_giant.glb", Vector3(12.5, 0, z), 180.0)
	var mid := Vector3(4.0, 3.0, z)
	_cam("Cam_giant", mid + Vector3(0, 1.5, -21.0), mid, 42.0)
	_cam("Cam_giant_Back", Vector3(12.5, 5.0, z + 10.0), Vector3(12.5, 2.5, z), 42.0)
	_cam("Cam_giant_Side", Vector3(-14.0, 4.0, z), Vector3(-4.0, 2.5, z), 42.0)
	_cam("Cam_giant_Close", Vector3(4.0, 4.0, z - 7.0), Vector3(4.0, 3.6, z), 40.0)

func _scarecrow() -> void:
	var z := _row * ROW_DZ
	_row += 1
	_spawn(C + "mak/mak.glb", Vector3(-3.5, 0, z), 0.0)
	_spawn(C + "wolf_scarecrow/wolf_scarecrow.glb", Vector3(0, 0, z), 0.0)
	_apply(_spawn(C + "wolf_scarecrow/wolf_scarecrow.glb", Vector3(4.5, 0, z), 0.0),
		{"jaw": [Vector3(1, 0, 0), 25.0], "head": [Vector3(0, 0, 1), 15.0], "body": [Vector3(0, 0, 1), 6.0], "can_l": [Vector3(0, 0, 1), 35.0], "can_r": [Vector3(0, 0, 1), -35.0]})
	_spawn(C + "wolf_scarecrow/wolf_scarecrow.glb", Vector3(9.0, 0, z), 180.0)
	var mid := Vector3(4.5, 2.5, z)
	_cam("Cam_scarecrow", mid + Vector3(0, 1.0, -15.0), mid, 42.0)
	_cam("Cam_scarecrow_Back", mid + Vector3(0, 1.0, 15.0), mid, 42.0)
	_cam("Cam_scarecrow_Close", Vector3(4.5, 3.9, z - 3.2), Vector3(4.5, 3.5, z), 40.0)

# ---------------------------------------------------------------- helpers

func _apply(n: Node3D, pose: Dictionary) -> void:
	var s := _skel(n)
	if s == null:
		return
	for bone in ["hips", "spine", "chest", "body", "head", "arm_l", "arm_r", "forearm_l", "forearm_r", "thigh_l", "thigh_r", "shin_l", "shin_r",
			"leg_fl", "leg_fr", "leg_bl", "leg_br", "tail", "tail_2", "jaw", "cap_tip", "can_l", "can_r"]:
		if pose.has(bone):
			_rot_model(s, bone, pose[bone][0], pose[bone][1])

func _spawn(path: String, pos: Vector3, yaw_deg: float) -> Node3D:
	var visual := Node3D.new()
	add_child(visual)
	visual.position = pos
	visual.rotation_degrees = Vector3(0, 180.0 + yaw_deg, 0)
	var n := (load(path) as PackedScene).instantiate() as Node3D
	visual.add_child(n)
	return n

func _skel(n: Node3D) -> Skeleton3D:
	var s := n.find_children("*", "Skeleton3D", true, false)
	return s[0] as Skeleton3D if s.size() > 0 else null

## Rotate a bone about a model-space axis through its own origin (parents posed first).
func _rot_model(skel: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	var i := skel.find_bone(bone)
	if i < 0:
		return
	var par := skel.get_bone_parent(i)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var g := skel.get_bone_global_pose(i)
	var nb := Basis(axis.normalized(), deg_to_rad(deg)) * g.basis
	skel.set_bone_pose_rotation(i, (pg.basis.inverse() * nb).get_rotation_quaternion())

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
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 155, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-35, -25, 0)
	back.light_color = Color(0.9, 0.92, 1.0)
	back.light_energy = 0.8
	add_child(back)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 160)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.55, 0.72, 0.42)
	fm.roughness = 0.95
	pm.material = fm
	floor.mesh = pm
	floor.position = Vector3(10, 0, 60)
	add_child(floor)
	var cam := Camera3D.new()
	cam.name = "Cam_Default"
	add_child(cam)
	cam.look_at_from_position(Vector3(5, 3, -10), Vector3(5, 1, 0))
	cam.current = true

# ---------------------------------------------------------------- motion sweep (Movie Maker): "-- --only=sweep"
## Sweeps the joints that failed the static test through their range, 4 s per cycle:
## Pip arms from the cheer rest down 0..90 deg, Snap arms up 0..90 deg, the Foreman (underwear) arms up, the scarecrow paper jaw 0..25 deg.

var _sw := {}
var _sw_rest := {}
var _sw_t := 0.0

func _sweep_setup() -> void:
	var items := [["pip", "pip_v2/pip_v2.glb", -2.1], ["snap", "sergeant_snap/sergeant_snap.glb", -0.6], ["fu", "foreman/foreman_underwear.glb", 1.4]]
	for it in items:
		var n := _spawn(C + it[1], Vector3(it[2], 0, 0), 0.0)
		_sw[it[0]] = _skel(n)
	var sc := _spawn(C + "wolf_scarecrow/wolf_scarecrow.glb", Vector3(5.2, -2.2, 1.5), 0.0)
	_sw["sc"] = _skel(sc)
	for k in _sw:
		var s: Skeleton3D = _sw[k]
		_sw_rest[k] = {}
		for i in s.get_bone_count():
			_sw_rest[k][i] = s.get_bone_pose_rotation(i)
	var cam := Camera3D.new()
	cam.name = "Cam_sweep"
	cam.fov = 40.0
	add_child(cam)
	cam.look_at_from_position(Vector3(1.5, 1.3, -6.2), Vector3(1.5, 0.9, 0))
	cam.current = true

func _process(delta: float) -> void:
	if _sw.is_empty():
		return
	_sw_t += delta
	var k := (1.0 - cos(_sw_t * TAU / 4.0)) * 0.5
	_sw_pose("pip", {"arm_l": [Vector3(0, 0, 1), -90.0 * k], "arm_r": [Vector3(0, 0, 1), 90.0 * k]})
	_sw_pose("snap", {"arm_l": [Vector3(0, 0, 1), 90.0 * k], "arm_r": [Vector3(0, 0, 1), -90.0 * k]})
	_sw_pose("fu", {"arm_l": [Vector3(0, 0, 1), 90.0 * k], "arm_r": [Vector3(0, 0, 1), -90.0 * k]})
	_sw_pose("sc", {"jaw": [Vector3(1, 0, 0), 25.0 * k], "body": [Vector3(0, 0, 1), 6.0 * k]})

func _sw_pose(key: String, pose: Dictionary) -> void:
	var s: Skeleton3D = _sw[key]
	for i in s.get_bone_count():
		s.set_bone_pose_rotation(i, _sw_rest[key][i])
	for bone in ["body", "arm_l", "arm_r", "jaw"]:
		if pose.has(bone):
			_rot_model(s, bone, pose[bone][0], pose[bone][1])

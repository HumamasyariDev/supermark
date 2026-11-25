extends Node3D
## TOPUP_CHARS critique round 1, pass B (ASSET QA lens). Test scene only, not gameplay.
## Re-checks the files as they stand after the first r1 fixes (Snap, Pip v2, scarecrow) and adds
## the tests pass A did not run: left/right weight symmetry (same pose mirrored on both sides),
## the scarecrow hat vs head turn, and a gameplay-distance lineup at the amendment sizes.
## "-- --only=<group>": snap, pip, scarecrow, sym, lineup. Cameras are named Cam_<group>[_Close|_Back].

const C := "res://assets/characters/"
var _only := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	_stage()
	match _only:
		"snap": _snap()
		"pip": _pip()
		"scarecrow": _scarecrow()
		"sym": _sym()
		"lineup": _lineup()
		_: _snap()

## Autoloads (dev/juice) can drop their own 3D nodes into the root; hide everything outside this test scene.
var _frames := 0
func _process(_d: float) -> void:
	_frames += 1
	if _frames > 20:
		return
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		if not is_ancestor_of(n):
			(n as VisualInstance3D).visible = false

func _row(path: String, poses: Array, dx: float, z: float, scale := 1.0) -> Array:
	var out := []
	var i := 0
	for p in poses:
		var yaw := 0.0
		if p.has("_yaw"):
			yaw = p["_yaw"]
		var n := _spawn(C + path, Vector3(i * dx, 0, z), yaw, scale)
		_apply(n, p)
		out.append(n)
		i += 1
	return out

func _snap() -> void:
	_spawn(C + "mak/mak.glb", Vector3(-1.5, 0, 0), 0.0)
	var up := {"arm_l": [Vector3(0, 0, 1), 80.0], "arm_r": [Vector3(0, 0, 1), -80.0]}
	var down := {"arm_l": [Vector3(0, 0, 1), -40.0], "arm_r": [Vector3(0, 0, 1), 40.0]}
	var fwd := {"arm_l": [Vector3(1, 0, 0), -70.0], "arm_r": [Vector3(1, 0, 0), -70.0]}
	var stride_r := {"thigh_r": [Vector3(1, 0, 0), -45.0], "shin_r": [Vector3(1, 0, 0), 30.0], "thigh_l": [Vector3(1, 0, 0), 25.0]}
	var stride_l := {"thigh_l": [Vector3(1, 0, 0), -45.0], "shin_l": [Vector3(1, 0, 0), 30.0], "thigh_r": [Vector3(1, 0, 0), 25.0]}
	var back := up.duplicate()
	back["_yaw"] = 180.0
	_row("sergeant_snap/sergeant_snap.glb", [{}, up, down, fwd, stride_r, stride_l, back], 1.5, 0.0)
	var mid := Vector3(4.0, 0.95, 0)
	_cam("Cam_snap", mid + Vector3(0, 0.6, -9.6), mid, 42.0)
	_cam("Cam_snap_Close", Vector3(2.25, 1.25, -3.4), Vector3(2.25, 1.0, 0), 40.0)
	_cam("Cam_snap_Legs", Vector3(6.75, 0.8, -3.2), Vector3(6.75, 0.45, 0), 40.0)
	# side views (profile) of stride R, stride L and arms forward, in a second row
	var sr := stride_r.duplicate(); sr["_yaw"] = 90.0
	var sl := stride_l.duplicate(); sl["_yaw"] = 90.0
	var sf := fwd.duplicate(); sf["_yaw"] = 90.0
	var crouch := {"spine": [Vector3(1, 0, 0), 20.0], "thigh_l": [Vector3(1, 0, 0), -60.0], "shin_l": [Vector3(1, 0, 0), 50.0], "thigh_r": [Vector3(1, 0, 0), -60.0], "shin_r": [Vector3(1, 0, 0), 50.0], "_yaw": 90.0}
	_row("sergeant_snap/sergeant_snap.glb", [sr, sl, sf, crouch], 1.6, 8.0)
	_cam("Cam_snap_Side", Vector3(2.4, 1.2, 1.5), Vector3(2.4, 0.85, 8.0), 44.0)

func _pip() -> void:
	_spawn(C + "mak/mak.glb", Vector3(-1.1, 0, 0), 0.0)
	var d60 := {"arm_l": [Vector3(0, 0, 1), -60.0], "arm_r": [Vector3(0, 0, 1), 60.0]}
	var d90 := {"arm_l": [Vector3(0, 0, 1), -90.0], "arm_r": [Vector3(0, 0, 1), 90.0]}
	var wave := {"arm_l": [Vector3(0, 0, 1), -75.0], "forearm_r": [Vector3(0, 0, 1), -45.0]}
	var hand := {"arm_l": [Vector3(0, 0, 1), -70.0], "arm_r": [Vector3(1, 0, 0), -45.0]}
	var turn := {"head": [Vector3(0, 1, 0), 35.0], "arm_l": [Vector3(0, 0, 1), -60.0], "arm_r": [Vector3(0, 0, 1), 60.0]}
	var back := d60.duplicate()
	back["_yaw"] = 180.0
	_row("pip_v2/pip_v2.glb", [{}, d60, d90, wave, hand, turn, back], 0.95, 0.0)
	var mid := Vector3(2.85, 0.5, 0)
	_cam("Cam_pip", mid + Vector3(0, 0.35, -6.0), mid, 42.0)
	_cam("Cam_pip_Close", Vector3(1.43, 0.75, -2.3), Vector3(1.43, 0.6, 0), 40.0)
	# arms at the sides (idle / talk need ~120-135 deg down from the cheer rest), front and 3/4
	var d120 := {"arm_l": [Vector3(0, 0, 1), -120.0], "arm_r": [Vector3(0, 0, 1), 120.0]}
	var d135 := {"arm_l": [Vector3(0, 0, 1), -135.0], "arm_r": [Vector3(0, 0, 1), 135.0]}
	var d120q := d120.duplicate(); d120q["_yaw"] = 35.0
	_row("pip_v2/pip_v2.glb", [d120, d135, d120q], 0.95, 5.0)
	_cam("Cam_pip_Low", Vector3(0.95, 0.7, 2.6), Vector3(0.95, 0.5, 5.0), 40.0)

func _scarecrow() -> void:
	_spawn(C + "mak/mak.glb", Vector3(-3.0, 0, 0), 0.0)
	var talk := {"jaw": [Vector3(1, 0, 0), 25.0]}
	var turn := {"head": [Vector3(0, 1, 0), 25.0], "jaw": [Vector3(1, 0, 0), 15.0]}
	var shout := {"head": [Vector3(1, 0, 0), -20.0], "jaw": [Vector3(1, 0, 0), 25.0]}
	var sway := {"body": [Vector3(0, 0, 1), 6.0], "can_l": [Vector3(0, 0, 1), 35.0], "can_r": [Vector3(0, 0, 1), -35.0]}
	_row("wolf_scarecrow/wolf_scarecrow.glb", [{}, talk, turn, shout, sway, {"_yaw": 180.0}], 4.4, 0.0)
	var mid := Vector3(11.0, 2.6, 0)
	_cam("Cam_scarecrow", mid + Vector3(0, 2.0, -24.0), mid, 42.0)
	_cam("Cam_scarecrow_Close", Vector3(6.6, 4.4, -4.6), Vector3(6.6, 3.8, 0), 44.0)
	_cam("Cam_scarecrow_Top", Vector3(6.6, 8.0, -3.0), Vector3(6.6, 4.3, 0), 50.0)

## Same pose applied on the left and on the right; a fair rig deforms both identically (mirror).
func _sym() -> void:
	var items := [["jack/jack.glb", 1.5], ["sergeant_snap/sergeant_snap.glb", 1.8], ["foreman/foreman_underwear.glb", 1.9], ["foreman/foreman.glb", 1.9], ["pip_v2/pip_v2.glb", 0.95]]
	var x := 0.0
	for it in items:
		var w: float = it[1] * 0.8
		# left leg forward / right leg forward (mirror pair), then left arm up / right arm up (mirror pair)
		_apply(_spawn(C + it[0], Vector3(x, 0, 0), 0.0), {"thigh_l": [Vector3(1, 0, 0), -60.0], "shin_l": [Vector3(1, 0, 0), 60.0]})
		_apply(_spawn(C + it[0], Vector3(x + w, 0, 0), 0.0), {"thigh_r": [Vector3(1, 0, 0), -60.0], "shin_r": [Vector3(1, 0, 0), 60.0]})
		x += w * 2.0 + 0.4
	var mid := Vector3(x * 0.5 - 0.6, 0.8, 0)
	_cam("Cam_sym", mid + Vector3(0, 0.6, -12.5), mid, 42.0)
	# arms row behind
	x = 0.0
	for it in items:
		var w: float = it[1] * 0.8
		_apply(_spawn(C + it[0], Vector3(x, 0, -6.0), 0.0), {"arm_l": [Vector3(0, 0, 1), 85.0], "forearm_l": [Vector3(0, 0, 1), 30.0]})
		_apply(_spawn(C + it[0], Vector3(x + w, 0, -6.0), 0.0), {"arm_r": [Vector3(0, 0, 1), -85.0], "forearm_r": [Vector3(0, 0, 1), -30.0]})
		x += w * 2.0 + 0.4
	_cam("Cam_sym_Arms", mid + Vector3(0, 1.0, -24.0), mid + Vector3(0, 0.2, -6.0), 42.0)

## Gameplay-distance lineup at the amendment sizes, seen from a typical third-person camera.
func _lineup() -> void:
	var items := [["mak/mak.glb", 1.0], ["pip_v2/pip_v2.glb", 1.0], ["hazel/hazel.glb", 1.0], ["bertram/bertram.glb", 1.0],
		["jack/jack.glb", 1.0], ["sergeant_snap/sergeant_snap.glb", 1.0], ["foreman/foreman.glb", 1.0], ["foreman/foreman_underwear.glb", 1.0],
		["real_sheep/real_sheep.glb", 1.0], ["daisy_cow/daisy_cow.glb", 1.0]]
	var x := 0.0
	for it in items:
		_spawn(C + it[0], Vector3(x, 0, 0), 0.0, it[1])
		x += 1.45
	_spawn(C + "wolf_scarecrow/wolf_scarecrow.glb", Vector3(x + 1.5, 0, 2.0), 0.0)
	_spawn(C + "sleeping_giant/sleeping_giant.glb", Vector3(x + 7.5, 0, 4.0), -20.0, 0.8)
	var mid := Vector3(x * 0.5 + 3.0, 1.2, 1.0)
	_cam("Cam_lineup", mid + Vector3(0, 6.5, -19.0), mid, 45.0)
	_cam("Cam_lineup_Low", Vector3(6.5, 1.4, -6.5), Vector3(6.5, 0.8, 0), 45.0)

# ---------------------------------------------------------------- helpers

func _apply(n: Node3D, pose: Dictionary) -> void:
	var s := _skel(n)
	if s == null:
		return
	for bone in ["hips", "spine", "chest", "body", "head", "arm_l", "arm_r", "forearm_l", "forearm_r", "thigh_l", "thigh_r", "shin_l", "shin_r",
			"leg_fl", "leg_fr", "leg_bl", "leg_br", "tail", "tail_2", "jaw", "cap_tip", "can_l", "can_r"]:
		if pose.has(bone):
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
	pm.size = Vector2(120, 120)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.55, 0.72, 0.42)
	fm.roughness = 0.95
	pm.material = fm
	floor.mesh = pm
	floor.position = Vector3(10, 0, 10)
	add_child(floor)

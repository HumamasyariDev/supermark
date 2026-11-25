extends Node3D
## ASSETS3_CHARS critique round 1 (ASSET QA lens). Test scene only, not gameplay. Read-only on the track's files.
## Loads every character file the track delivered, under the real game lighting (env_<W>.tres, the world's sun,
## RetroLook pop through the "npc" group) and poses the skeletons procedurally by AIMING bones in model space:
## rest, arms down (15 deg off vertical), run contact, crouch (thighs 70 deg, root lowered), head turn 40 deg, back.
## Self-capture: "-- --crit-out=<abs dir> --only=<group> [--env=W1|W2|W3|HUB] [--tag=x]" saves one PNG per camera, then quits.
## Groups: bipeds, pigs, quads, cow, orm, wolf, lineup, snapprops.

const C := "res://assets/characters/"
const SUNS := {
	"W1": [Vector3(-28, -70, 0), Color("ffd49a"), 1.76],
	"W2": [Vector3(-27, -67.5, 0), Color("ffc98a"), 1.7],
	"W3": [Vector3(-38, -45, 0), Color(1.0, 0.9, 0.74), 2.0],
	"HUB": [Vector3(-40, -60, 0), Color("ffe0b8"), 1.4]}

var world_id := "W1"
var _only := "bipeds"
var _out := ""
var _tag := ""
var _cams: Array = []
var _frame := 0
var _shot_i := -1
var _wait_first := 150
var _log: Array = []
var _anim: Array = []
var _t := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
		elif a.begins_with("--env="):
			world_id = a.substr(6)
		elif a.begins_with("--crit-out="):
			_out = a.substr(11)
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
	_stage()
	match _only:
		"bipeds": _bipeds(["jack/jack_v2.glb", "foreman/foreman_v2.glb", "foreman/foreman_underwear_v2.glb", "sergeant_snap/sergeant_snap_v3.glb"], 2.2)
		"pigs": _bipeds(["pip_v2/pip_v3.glb", "hazel/hazel_v2.glb", "bertram/bertram_v2.glb"], 1.3)
		"quads": _quads()
		"cow": _cow()
		"orm": _orm()
		"wolf": _wolf()
		"lineup": _lineup()
		"snapprops": _snapprops()
		"cowmotion": _cow_motion()

func _process(d: float) -> void:
	_frame += 1
	_t += d
	for e in _anim:
		var sk: Skeleton3D = e[0]
		sk.reset_bone_poses()
		for b in e[1]:
			_rot_model(sk, b[0], b[1], b[2] + b[3] * sin(TAU * (_t / b[4]) + b[5]))
	if _frame < 25:
		for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
			if not is_ancestor_of(n):
				(n as VisualInstance3D).visible = false
	if _out == "":
		return
	if _frame == _wait_first:
		_shot_i = 0
		_cams[0].current = true
		return
	if _shot_i >= 0 and _frame > _wait_first and (_frame - _wait_first) % 10 == 0:
		var img := get_viewport().get_texture().get_image()
		var cam: Camera3D = _cams[_shot_i]
		var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "").replace("T", "T") + "Z"
		var fn := "%s/%s__a3c_r1_%s_%s%s.png" % [_out, stamp, _only, cam.name, ("_" + _tag) if _tag != "" else ""]
		img.save_png(fn)
		print("[crit_a3c] saved ", fn)
		_shot_i += 1
		if _shot_i >= _cams.size():
			if _log.size() > 0:
				var f := FileAccess.open("%s/%s__a3c_r1_%s_metrics%s.json" % [_out, stamp, _only, ("_" + _tag) if _tag != "" else ""], FileAccess.WRITE)
				f.store_string(JSON.stringify(_log, " "))
				f.close()
			get_tree().quit()
			return
		_cams[_shot_i].current = true

# ---------------------------------------------------------------- groups

## One row per biped: rest | arms down | run R | run L(side) | crouch(side) | head turn + talk | back (arms down).
func _bipeds(files: Array, dx: float) -> void:
	var z := 0.0
	var mak := _spawn(C + "mak_v2/mak_v2_assembled_v3.glb", Vector3(dx, 0, 0), 0.0)
	for f in files:
		var poses := ["rest", "down", "run", "run_side", "crouch_side", "turn", "back"]
		for i in poses.size():
			var x := -i * dx
			var yaw := 0.0
			if poses[i].ends_with("_side"):
				yaw = -90.0
			elif poses[i] == "back":
				yaw = 180.0
			var n := _spawn(C + f, Vector3(x, 0, z), yaw)
			_pose_biped(n, poses[i].replace("_side", ""), f)
		var id := String(f).get_file().get_basename()
		var h := 1.0 if dx > 2.0 else 0.55
		var mid := Vector3(-3.0 * dx, h, z)
		_cam("Cam_%s" % id, mid + Vector3(0, 0.6 * h, -6.3 * dx), mid, 48.0)
		# close-ups: arms down (front 3/4), run side, crouch side, back
		_cam("Cam_%s_Down" % id, Vector3(-dx - 0.5 * h, h * 1.15, z - 2.6 * h), Vector3(-dx, h * 0.95, z), 42.0)
		_cam("Cam_%s_Run" % id, Vector3(-3 * dx + 0.25 * h, h * 0.9, z - 2.4 * h), Vector3(-3 * dx, h * 0.8, z), 42.0)
		_cam("Cam_%s_Crouch" % id, Vector3(-4 * dx, h * 0.7, z - 2.2 * h), Vector3(-4 * dx, h * 0.55, z), 42.0)
		_cam("Cam_%s_Turn" % id, Vector3(-5 * dx + 0.2, h * 1.6, z - 1.6 * h), Vector3(-5 * dx, h * 1.45, z), 40.0)
		_cam("Cam_%s_Back" % id, Vector3(-6 * dx + 0.4 * h, h * 1.1, z - 2.6 * h), Vector3(-6 * dx, h * 0.9, z), 42.0)
		z += dx * 3.2
	if mak:
		pass

func _pose_biped(n: Node3D, pose: String, f: String) -> void:
	var s := _skel(n)
	if s == null:
		return
	var out := 0.26  # arms 15 deg off vertical
	var rec := {"file": f, "pose": pose}
	match pose:
		"rest":
			pass
		"down", "back":
			_aim(s, "arm_l", Vector3(out, -1, 0.05)); _aim(s, "arm_r", Vector3(-out, -1, 0.05))
			_bend(s, "forearm_l", Vector3(1, 0, 0), -12.0); _bend(s, "forearm_r", Vector3(1, 0, 0), -12.0)
		"run":
			_aim(s, "thigh_r", Vector3(0, -0.75, 0.66)); _aim(s, "shin_r", Vector3(0, -1, -0.15))
			_aim(s, "thigh_l", Vector3(0, -0.9, -0.42)); _aim(s, "shin_l", Vector3(0, -0.55, -0.83))
			_aim(s, "arm_l", Vector3(out * 0.6, -0.8, 0.6)); _aim(s, "arm_r", Vector3(-out * 0.6, -0.85, -0.5))
			_bend(s, "forearm_l", Vector3(1, 0, 0), -55.0); _bend(s, "forearm_r", Vector3(1, 0, 0), -55.0)
			_bend(s, "spine", Vector3(1, 0, 0), 8.0)
		"crouch":
			var foot0 := _ankles(s)
			_aim(s, "thigh_l", Vector3(0.08, -0.35, 0.94)); _aim(s, "thigh_r", Vector3(-0.08, -0.35, 0.94))
			_aim(s, "shin_l", Vector3(0, -0.9, -0.43)); _aim(s, "shin_r", Vector3(0, -0.9, -0.43))
			_bend(s, "spine", Vector3(1, 0, 0), 25.0)
			_aim(s, "arm_l", Vector3(out, -0.7, 0.7)); _aim(s, "arm_r", Vector3(-out, -0.7, 0.7))
			var foot1 := _ankles(s)
			var dy := foot1 - foot0
			var hb := s.find_bone("hips")
			if hb < 0:
				hb = s.find_bone("root")
			if hb >= 0:
				s.set_bone_pose_position(hb, s.get_bone_pose_position(hb) - Vector3(0, dy, 0))
			rec["root_drop"] = dy
		"turn":
			_aim(s, "arm_l", Vector3(out, -1, 0.05)); _aim(s, "arm_r", Vector3(-out * 0.5, -0.3, 0.95))
			_bend(s, "head", Vector3(0, 1, 0), 40.0)
			_bend(s, "head", Vector3(1, 0, 0), -10.0)
	_log.append(rec)

## Ankle height estimate: shin head minus one shin length along the shin direction (shin length := thigh length).
func _ankles(s: Skeleton3D) -> float:
	var ys := []
	for side in ["l", "r"]:
		var t := s.find_bone("thigh_" + side)
		var k := s.find_bone("shin_" + side)
		if t < 0 or k < 0:
			continue
		var tp := s.get_bone_global_pose(t).origin
		var kp := s.get_bone_global_pose(k)
		var len_ := tp.distance_to(kp.origin)
		var rest_dir := (kp.origin - tp).normalized()
		# shin direction = the shin's own Y axis in rest-aligned frame: use the thigh->shin direction rotated by the shin's local rotation
		var dir := (kp.basis * (s.get_bone_global_rest(k).basis.inverse() * rest_dir)).normalized()
		ys.append((kp.origin + dir * len_).y)
	if ys.is_empty():
		return 0.0
	return min(ys[0], ys[ys.size() - 1])

func _quads() -> void:
	# sheep: rest | walk | head turn + graze | back ; scarecrow: rest | jaw 25 + turn | sway + cans | back ; giant: rest | sit-up | back
	var sheep := C + "real_sheep/real_sheep_v2.glb"
	var poses := [{}, {"leg_fl": [Vector3(1, 0, 0), -28.0], "leg_br": [Vector3(1, 0, 0), -24.0], "leg_fr": [Vector3(1, 0, 0), 22.0], "leg_bl": [Vector3(1, 0, 0), 26.0], "_yaw": -90.0},
		{"head": [Vector3(0, 1, 0), 35.0]}, {"head": [Vector3(1, 0, 0), 40.0], "_yaw": -60.0}, {"_yaw": 180.0}]
	for i in poses.size():
		_apply(_spawn(sheep, Vector3(-i * 1.6, 0, 0), poses[i].get("_yaw", 0.0)), poses[i])
	_cam("Cam_sheep", Vector3(-3.2, 1.3, -5.2), Vector3(-3.2, 0.55, 0), 48.0)
	_cam("Cam_sheep_Walk", Vector3(-1.6, 0.7, -2.0), Vector3(-1.6, 0.45, 0), 45.0)
	var sc := C + "wolf_scarecrow/wolf_scarecrow_v2.glb"
	var sp := [{}, {"jaw": [Vector3(1, 0, 0), 25.0], "head": [Vector3(0, 1, 0), 25.0]}, {"body": [Vector3(0, 0, 1), 6.0], "can_l": [Vector3(0, 0, 1), 35.0], "can_r": [Vector3(0, 0, 1), -35.0]}, {"_yaw": 180.0}]
	for i in sp.size():
		_apply(_spawn(sc, Vector3(-i * 4.6, 0, 8.0), sp[i].get("_yaw", 0.0)), sp[i])
	_cam("Cam_scarecrow", Vector3(-6.9, 3.4, -9.0), Vector3(-6.9, 2.4, 8.0), 48.0)
	_cam("Cam_scarecrow_Jaw", Vector3(-4.6, 4.3, 4.6), Vector3(-4.6, 4.0, 8.0), 42.0)
	var gi := C + "sleeping_giant/sleeping_giant_v2.glb"
	var gp := [{}, {"chest": [Vector3(1, 0, 0), -20.0], "head": [Vector3(1, 0, 0), -15.0], "jaw": [Vector3(1, 0, 0), 16.0]}, {"_yaw": 180.0}]
	for i in gp.size():
		_apply(_spawn(gi, Vector3(-i * 7.5, 0, 22.0), gp[i].get("_yaw", 0.0)), gp[i])
	_cam("Cam_giant", Vector3(-7.5, 5.0, 4.0), Vector3(-7.5, 2.6, 22.0), 50.0)
	_cam("Cam_giant_Face", Vector3(-7.5, 4.0, 15.5), Vector3(-7.5, 3.4, 22.0), 42.0)

func _cow() -> void:
	var f := C + "daisy_cow/daisy_cow_v3.glb"
	var figs := [[0.0, 25.0, "v3 jaw 0"], [16.0, 25.0, "+16"], [28.0, 25.0, "+28"], [-10.0, 25.0, "-10 (npc_life today)"], [20.0, 90.0, "+20 profile"], [20.0, -35.0, "+20 other 3/4, head turn"]]
	for i in figs.size():
		var x := -3.0 * i
		var n := _spawn(f, Vector3(x, 0, 0), figs[i][1])
		var p := {"jaw": [Vector3(1, 0, 0), figs[i][0]]}
		if i == 5:
			p["head"] = [Vector3(0, 1, 0), -25.0]
		_apply(n, p)
		var fwd := Vector3(sin(deg_to_rad(180.0 + figs[i][1])), 0, cos(deg_to_rad(180.0 + figs[i][1])))
		# Model +Z is its front; wrapper turned 180+yaw. Head sits ~1.0 m forward of the origin at ~1.0 m height.
		var head := Vector3(x, 0.92, 0) + fwd * 0.9
		_cam("Cam_cow_%d" % i, head + fwd * 1.35 + Vector3(0, 0.12, 0), head, 40.0)
	# low "looking up into the mouth" and high camera for +28
	var x2 := -6.0
	var fwd2 := Vector3(sin(deg_to_rad(205.0)), 0, cos(deg_to_rad(205.0)))
	var head2 := Vector3(x2, 0.88, 0) + fwd2 * 0.9
	_cam("Cam_cow_Low", head2 + fwd2 * 1.0 + Vector3(0, -0.45, 0), head2, 45.0)
	_cam("Cam_cow_Row", Vector3(-7.5, 1.6, -9.0), Vector3(-7.5, 0.9, 0), 55.0)

func _cow_motion() -> void:
	var b := _skel(_spawn(C + "daisy_cow/daisy_cow_v3.glb", Vector3(0, 0, 0), 25.0))
	_anim.append([b, [["jaw", Vector3(1, 0, 0), 12.0, 12.0, 1.2, -PI * 0.5], ["head", Vector3(0, 1, 0), 0.0, 20.0, 2.4, 0.0]]])
	var fwd := Vector3(sin(deg_to_rad(205.0)), 0, cos(deg_to_rad(205.0)))
	var head := Vector3(0, 0.92, 0) + fwd * 0.9
	_cam("Cam_cowmotion", head + fwd * 1.6 + Vector3(0.0, 0.2, 0), head, 42.0)

func _orm() -> void:
	var items := [["bramwell/bramwell.glb", 0.0], ["bramwell/bramwell_v2.glb", 0.0], ["golden_goose/golden_goose.glb", 30.0], ["golden_goose/golden_goose_v2.glb", 30.0]]
	for i in items.size():
		_spawn(C + items[i][0], Vector3(-i * 1.6, 0, 0), items[i][1])
	_spawn(C + "bramwell/bramwell_v2.glb", Vector3(-7.0, 0, 0), 180.0)
	_spawn(C + "bramwell/bramwell_v2.glb", Vector3(-8.6, 0, 0), -90.0)
	_cam("Cam_orm", Vector3(-2.4, 1.2, -4.8), Vector3(-2.4, 0.7, 0), 45.0)
	_cam("Cam_orm_Bram", Vector3(-0.8, 1.15, -2.3), Vector3(-0.8, 0.95, 0), 42.0)
	_cam("Cam_orm_Goose", Vector3(-4.0, 0.75, -1.6), Vector3(-4.0, 0.45, 0), 42.0)
	_cam("Cam_orm_BramBack", Vector3(-7.8, 1.2, -3.2), Vector3(-7.8, 0.75, 0), 42.0)

func _wolf() -> void:
	_spawn(C + "wolf_boss/wolf_boss.glb", Vector3(0, 0, 0), 0.0)
	var w2 := _spawn(C + "wolf_boss/wolf_boss_v2.glb", Vector3(-3.4, 0, 0), 0.0)
	var w3 := _spawn(C + "wolf_boss/wolf_boss_v2.glb", Vector3(-6.8, 0, 0), 180.0)
	var w4 := _spawn(C + "wolf_boss/wolf_boss_v2.glb", Vector3(-10.2, 0, 0), 20.0)
	var s := _skel(w4)
	if s:
		_rot_model(s, "jaw", Vector3(1, 0, 0), 40.0)
		_aim(s, "arm_l", Vector3(0.3, -1, 0.1)); _aim(s, "arm_r", Vector3(-0.3, -1, 0.1))
	var s2 := _skel(w2)
	if s2:
		_aim(s2, "arm_l", Vector3(0.3, -1, 0.1)); _aim(s2, "arm_r", Vector3(-0.3, -1, 0.1))
	_cam("Cam_wolf", Vector3(-5.1, 2.4, -11.5), Vector3(-5.1, 1.7, 0), 48.0)
	_cam("Cam_wolf_Face", Vector3(-1.7, 2.9, -3.6), Vector3(-1.7, 2.6, 0), 45.0)
	_cam("Cam_wolf_Jaw", Vector3(-10.0, 2.85, -2.4), Vector3(-10.2, 2.7, 0), 42.0)
	_cam("Cam_wolf_Back", Vector3(-6.8, 2.2, -5.0), Vector3(-6.8, 1.7, 0), 45.0)

func _snapprops() -> void:
	var props := ["snap_lance_v2.glb", "snap_sabre_v2.glb", "snap_mace_v2.glb", "snap_drum_v2.glb"]
	for i in props.size():
		var n := _spawn(C + "sergeant_snap/" + props[i], Vector3(-i * 0.9, 0.6, 0), 30.0)
		n.get_parent().rotation_degrees.x = 0
	_cam("Cam_snapprops", Vector3(-1.35, 1.2, -2.6), Vector3(-1.35, 0.75, 0), 45.0)

func _lineup() -> void:
	var items := ["mak_v2/mak_v2_assembled_v3.glb", "pip_v2/pip_v3.glb", "hazel/hazel_v2.glb", "bertram/bertram_v2.glb", "jack/jack_v2.glb",
		"sergeant_snap/sergeant_snap_v3.glb", "foreman/foreman_v2.glb", "foreman/foreman_underwear_v2.glb", "bramwell/bramwell_v2.glb",
		"golden_goose/golden_goose_v2.glb", "real_sheep/real_sheep_v2.glb", "daisy_cow/daisy_cow_v3.glb"]
	var x := 0.0
	for it in items:
		var n := _spawn(C + it, Vector3(x, 0, 0), 0.0)
		if it.begins_with("pip") or it.begins_with("hazel") or it.begins_with("bertram") or it.begins_with("jack") or it.begins_with("sergeant") or it.begins_with("foreman"):
			var s := _skel(n)
			if s:
				_aim(s, "arm_l", Vector3(0.26, -1, 0.05)); _aim(s, "arm_r", Vector3(-0.26, -1, 0.05))
		x -= 1.5
	_spawn(C + "wolf_boss/wolf_boss_v2.glb", Vector3(x - 1.0, 0, 1.5), 0.0)
	_spawn(C + "wolf_scarecrow/wolf_scarecrow_v2.glb", Vector3(x - 5.0, 0, 2.5), 0.0)
	var mid := Vector3(x * 0.5 - 1.5, 1.1, 0)
	_cam("Cam_lineup", mid + Vector3(0, 4.5, -17.0), mid, 48.0)
	_cam("Cam_lineup_Game", Vector3(-4.0, 3.2, -7.5), Vector3(-4.0, 0.8, 0), 55.0)

# ---------------------------------------------------------------- helpers

## Aims a bone (its head -> first child head direction, or its local +Y if it has no child) at a model-space direction.
func _aim(s: Skeleton3D, bone: String, target: Vector3) -> void:
	var i := s.find_bone(bone)
	if i < 0:
		return
	var g := s.get_bone_global_pose(i)
	var kids := s.get_bone_children(i)
	var d: Vector3
	if kids.size() > 0:
		d = s.get_bone_global_pose(kids[0]).origin - g.origin
	else:
		d = g.basis.y
	if d.length() < 1e-5:
		return
	d = d.normalized()
	var t := target.normalized()
	var ax := d.cross(t)
	var ang := d.angle_to(t)
	if ax.length() < 1e-6:
		return
	var nb := Basis(ax.normalized(), ang) * g.basis
	var par := s.get_bone_parent(i)
	var pg := s.get_bone_global_pose(par) if par >= 0 else Transform3D()
	s.set_bone_pose_rotation(i, (pg.basis.inverse() * nb).get_rotation_quaternion())

func _bend(s: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	_rot_model(s, bone, axis, deg)

func _apply(n: Node3D, pose: Dictionary) -> void:
	var s := _skel(n)
	if s == null:
		return
	for bone in pose.keys():
		if String(bone).begins_with("_"):
			continue
		_rot_model(s, bone, pose[bone][0], pose[bone][1])

func _spawn(path: String, pos: Vector3, yaw_deg: float, scale := 1.0) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("missing " + path)
		return null
	var visual := Node3D.new()
	visual.name = String(path).get_file().get_basename()
	add_child(visual)
	visual.add_to_group("npc")
	visual.position = pos
	visual.rotation_degrees = Vector3(0, 180.0 + yaw_deg, 0)
	visual.scale = Vector3.ONE * scale
	var n := (load(path) as PackedScene).instantiate() as Node3D
	visual.add_child(n)
	return n

func _skel(n: Node3D) -> Skeleton3D:
	if n == null:
		return null
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
	_cams.append(cam)

func _stage() -> void:
	var envp := "res://assets/shaders/environments/env_%s.tres" % world_id
	var we := WorldEnvironment.new()
	we.environment = (load(envp) as Environment).duplicate() if ResourceLoader.exists(envp) else Environment.new()
	add_child(we)
	var sp: Array = SUNS.get(world_id, SUNS["W1"])
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = sp[0]
	sun.light_color = sp[1]
	sun.light_energy = sp[2]
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.62, 0.4)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position = Vector3(-10, 0, 10)
	add_child(ground)

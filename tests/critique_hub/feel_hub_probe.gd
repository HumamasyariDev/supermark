extends Node
## HUB critique round 1, lens GAME FEEL, MOVEMENT AND CAMERA. Read-only probe: it changes nothing in the hub's files.
## The harness (FeelHubProbe.tscn) adds this node under /root and loads Hub.tscn as the current scene. The probe then
## drives the real MakPlayer with real input actions (Input.action_press, camera-relative like a person) through the
## tasks named in --tasks=<a,b,...>, logs one JSON row per rendered frame to --cam-out (state, feet, velocity, camera
## position, distance, whether the camera sphere is inside layer-1 geometry, chest/head occlusion, chest screen pos,
## active camera zone, landing spot visibility while airborne) and writes per-attempt results to --res-out.
## Shots (native PNG) go to --shot-dir.
## Run: python tools/godot.py run res://tests/critique_hub/FeelHubProbe.tscn --seconds 400 -- --profile=crit-hub-feel \
##        --spawn=HUB-1 --unlock-all --tasks=views,cornice --cam-out=<abs> --res-out=<abs> --shot-dir=<abs>

var _player: Node3D
var _rig: Node3D
var _cam: Camera3D
var _out: FileAccess
var _shot_dir := ""
var _res_out := ""
var _tasks: PackedStringArray = []
var _mark := ""
var _results: Array = []
var _frames := 0
var _shot_req := ""


func _ready() -> void:
	process_priority = 1000
	process_physics_priority = -200
	var dev := get_tree().root.get_node_or_null("Dev")
	if dev != null:
		var cp := str(dev.call("arg", "cam-out", ""))
		if cp != "":
			DirAccess.make_dir_recursive_absolute(cp.get_base_dir())
			_out = FileAccess.open(cp, FileAccess.WRITE)
		_shot_dir = str(dev.call("arg", "shot-dir", ""))
		_res_out = str(dev.call("arg", "res-out", ""))
		_tasks = str(dev.call("arg", "tasks", "views")).split(",", false)
	_main.call_deferred()


# ------------------------------------------------------------------ helpers

static func pp(r: float, th: float, y: float) -> Vector3:
	var t := deg_to_rad(th)
	return Vector3(r * sin(t), y, -r * cos(t))


static func theta_of(p: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(p.x, -p.z)), 360.0)


static func yaw_for(dir: Vector3) -> float:
	return rad_to_deg(atan2(-dir.x, -dir.z))


static func tangent(th: float) -> Vector3:
	var t := deg_to_rad(th)
	return Vector3(cos(t), 0, sin(t))


func _state() -> String:
	return str(_player.call("get_state_name"))


func _grounded() -> bool:
	return bool(_player.get("grounded"))


func _pf() -> void:
	await get_tree().physics_frame


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _teleport(pos: Vector3, yaw_deg: float) -> void:
	_release_all()
	_player.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))


func _steer(dir: Vector3) -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)
	if dir.length() < 0.01:
		return
	var yaw := float(_player.call("_camera_yaw"))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var sx := dir.dot(right)
	var sy := dir.dot(fwd)
	if sx > 0.0:
		Input.action_press("move_right", minf(sx, 1.0))
	elif sx < 0.0:
		Input.action_press("move_left", minf(-sx, 1.0))
	if sy > 0.0:
		Input.action_press("move_forward", minf(sy, 1.0))
	elif sy < 0.0:
		Input.action_press("move_back", minf(-sy, 1.0))


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "jump", "crouch", "attack"]:
		Input.action_release(a)


func _shot(label: String) -> void:
	if _shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		img.save_png(_shot_dir.path_join(label + ".png"))


func _excl() -> Array[RID]:
	var ex: Array[RID] = []
	if _player is CollisionObject3D:
		ex.append((_player as CollisionObject3D).get_rid())
	return ex


func _ray_hit(from: Vector3, to: Vector3, mask := 1) -> String:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, _excl())
	q.collide_with_areas = false
	var hit := _cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return ""
	var c: Object = hit.get("collider")
	if c is Node:
		var n := c as Node
		var par := n.get_parent()
		return str(n.name) + ("<" + str(par.name) if par != null else "")
	return "?"


func _cam_inside() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.1
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, _cam.global_position)
	q.collision_mask = 1
	return not _cam.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _screen(p: Vector3) -> Array:
	var vp := get_viewport().get_visible_rect().size
	if _cam.is_position_behind(p):
		return [-1.0, -1.0]
	var s := _cam.unproject_position(p)
	return [snappedf(s.x / vp.x, 0.001), snappedf(s.y / vp.y, 0.001)]


static func _v(p: Vector3, d := 0.001) -> Array:
	return [snappedf(p.x, d), snappedf(p.y, d), snappedf(p.z, d)]


func _floor_name() -> String:
	var p := _player.global_position
	return _ray_hit(p + Vector3.UP * 0.3, p + Vector3.DOWN * 40.0)


# ------------------------------------------------------------------ per-frame camera log

func _process(_delta: float) -> void:
	_frames += 1
	if _player == null or _cam == null or _out == null:
		return
	var pp0 := _player.get_global_transform_interpolated().origin
	var chest := pp0 + Vector3.UP * 0.6
	var head := pp0 + Vector3.UP * 1.1
	var cpos := _cam.global_position
	var z: Variant = _rig.get("zone")
	var grounded := _grounded()
	var row := {
		"rf": _frames, "pf": int(_player.get("physics_frame")), "m": _mark, "s": _state(), "g": grounded,
		"p": _v(pp0), "v": _v(_player.get("velocity") as Vector3, 0.01), "th": snappedf(theta_of(pp0), 0.01),
		"c": _v(cpos), "cyaw": snappedf(rad_to_deg(float(_rig.get("yaw"))), 0.1),
		"cpitch": snappedf(rad_to_deg(float(_rig.get("pitch"))), 0.1),
		"dist": snappedf(cpos.distance_to(chest), 0.01), "inside": _cam_inside(),
		"occ_chest": _ray_hit(cpos, chest), "occ_head": _ray_hit(cpos, head),
		"scr": _screen(chest), "zone": (str((z as Node).name) if z is Node else ""),
		"gamecam": get_viewport().get_camera_3d() == _cam,
		"hp": int(get_tree().root.get_node("Game").get("health")) if get_tree().root.has_node("Game") else -1,
	}
	if not grounded:
		var hit := _cam.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(pp0 + Vector3.UP * 0.1, pp0 + Vector3.DOWN * 60.0, 1, _excl()))
		if not hit.is_empty():
			var lp: Vector3 = hit["position"]
			row["land"] = {"y": snappedf(lp.y, 0.01), "fr": _cam.is_position_in_frustum(lp),
				"occ": _ray_hit(cpos, lp + Vector3.UP * 0.05) != "", "scr": _screen(lp)}
	_out.store_line(JSON.stringify(row))


# ------------------------------------------------------------------ main

func _main() -> void:
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
	for i in 600:
		await get_tree().physics_frame
		_player = get_tree().get_first_node_in_group("player") as Node3D
		_rig = get_tree().get_first_node_in_group("game_camera") as Node3D
		if _player != null and _rig != null and i > 90:
			break
	if _player == null or _rig == null:
		push_error("[FeelHub] no player or camera")
		get_tree().quit(3)
		return
	_cam = _rig.get_node_or_null("Camera3D") as Camera3D
	print("[FeelHub] start tasks ", _tasks)
	for t in _tasks:
		print("[FeelHub] task ", t)
		match t:
			"views": await task_views()
			"cornice": await task_cornice()
			"spiral_stand": await task_spiral_stand()
			"faller_chain": await task_faller_chain()
			"rim_slam": await task_rim_slam()
			"nook": await task_nook()
			"longjump_lane": await task_longjump_lane()
			"updraft": await task_updraft()
			"gap_audit": await task_gap_audit()
			"cap_walk": await task_cap_walk()
			"wedge": await task_wedge()
			"wedge2": await task_wedge2()
			"rhythm": await task_rhythm()
			"chimney": await task_chimney()
			"stick_right": await task_stick_right()
			"ladder": await task_ladder()
			_: push_warning("[FeelHub] unknown task " + t)
	_mark = "end"
	_release_all()
	if _res_out != "":
		var f := FileAccess.open(_res_out, FileAccess.WRITE)
		f.store_string(JSON.stringify(_results, " "))
		f.close()
	if _out != null:
		_out.flush()
	print("[FeelHub] done ", _results.size(), " results")
	await _wait(10)
	get_tree().quit()


func _record(d: Dictionary) -> void:
	print("[FeelHub] RESULT ", JSON.stringify(d))
	_results.append(d)


# ------------------------------------------------------------------ task: static views

func _views() -> Array:
	var bk := HubSpiral.BOOKS
	var v := [
		["intro_mark", Vector3(-0.4, 0.02, 9.0), 0.0],
		["nook_mouth_w", Vector3(-3.0, 0.02, -10.6), -90.0],
		["nook_board_n", Vector3(0.0, 0.02, -11.6), 0.0],
		["nook_board_s", Vector3(0.0, 0.02, -11.6), 180.0],
		["under_landing", Vector3(1.5, 0.02, -8.6), 0.0],
		["shelf_ground_in", pp(14.6, 300.0, 0.02), yaw_for(-pp(1, 300.0, 0))],
		["gallery_wall_in", pp(15.0, 300.0, 4.52), yaw_for(-pp(1, 300.0, 0))],
		["gallery_rail_out", pp(13.0, 300.0, 4.52), yaw_for(pp(1, 300.0, 0))],
		["gallery_wall_tan", pp(15.4, 160.0, 4.52), yaw_for(tangent(160.0))],
		["L2_exit", Vector3(14.28, 8.52, 5.2), yaw_for(tangent(110.0))],
		["cornice_A_110", pp(15.2, 110.0, 8.52), yaw_for(tangent(110.0))],
		["cornice_lintel_126", pp(15.2, 126.0, 8.52), yaw_for(tangent(126.0))],
		["cornice_B_152", pp(15.2, 152.0, 8.52), yaw_for(tangent(152.0))],
		["cornice_B_back", pp(15.2, 152.0, 8.52), yaw_for(-tangent(152.0))],
		["top_balcony_180", pp(14.8, 180.0, 9.72), yaw_for(tangent(180.0))],
		["top_balcony_jar", pp(14.6, 186.0, 9.72), yaw_for(tangent(186.0))],
		["chimney_foot", pp(14.5, 211.4, 4.52), yaw_for(tangent(211.4))],
		["chimney_mid", pp(14.5, 211.4, 7.5), yaw_for(tangent(211.4))],
		["book3_bay", Vector3(8.6, 4.92, 0.0), 90.0],
		["stair_head", Vector3(0.0, 4.52, -13.6), 0.0],
		["mantel_out", Vector3(-14.3, 2.02, 0.0), -90.0],
		["hearth_in", Vector3(-13.4, 0.02, 1.6), 90.0],
		["armchair_s", Vector3(-12.3, 0.02, 4.6), 0.0],
		["updraft_landing", Vector3(-11.4, 4.52, 7.97), yaw_for(-pp(1, 235.0, 0))],
		["balcony", Vector3(0.0, 4.52, 18.4), 180.0],
		["spiral_gate", Vector3(8.68, 4.52, -10.34), 140.0],
	]
	for i in bk.size():
		var b: Array = bk[i]
		var top: Vector3 = b[2]
		var nxt: Vector3 = (bk[i + 1][2] if i + 1 < bk.size() else Vector3(0, 9.1, 0))
		var d := nxt - top
		d.y = 0
		v.append(["spiral_" + str(b[0]), top + Vector3(0, 0.15, 0), yaw_for(d.normalized())])
	v.append(["rim_cross", Vector3(0, 9.2, 2.6), 0.0])
	return v


func task_views() -> void:
	for v in _views():
		_mark = "view:" + str(v[0])
		_teleport(v[1], float(v[2]))
		await _wait(80)
		var chest := _player.global_position + Vector3.UP * 0.6
		var row := {"task": "view", "name": v[0], "pos": _v(_player.global_position), "state": _state(),
			"floor": _floor_name(), "cam": _v(_cam.global_position), "dist": snappedf(_cam.global_position.distance_to(chest), 0.01),
			"inside": _cam_inside(), "occ_chest": _ray_hit(_cam.global_position, chest),
			"zone": (str((_rig.get("zone") as Node).name) if _rig.get("zone") is Node else ""), "scr": _screen(chest)}
		_record(row)
		await _shot("view_" + str(v[0]))


# ------------------------------------------------------------------ task: cornice gap (HJ2) attempts

func _cornice_attempt(kind: String, th_jump: float, start_th := 101.0) -> void:
	_mark = "cornice:%s@%.1f" % [kind, th_jump]
	_teleport(pp(15.2, start_th, 8.55), yaw_for(tangent(start_th)))
	await _wait(45)
	var fired := false
	var f_since := -1
	var launch := {}
	var states: Array[String] = []
	var max_th := 0.0
	var max_y := -100.0
	var min_y_after := 100.0
	var result := "timeout"
	for i in 480:
		var p := _player.global_position
		var th := theta_of(p)
		var r := Vector2(p.x, p.z).length()
		var st := _state()
		if states.is_empty() or states[-1] != st:
			states.append(st)
		var dir := tangent(th) + pp(1, th, 0) * clampf((15.15 - r) * 1.2, -0.6, 0.6)
		_steer(dir.normalized())
		if not fired and th >= th_jump and _grounded():
			fired = true
			f_since = 0
			launch = {"th": snappedf(th, 0.1), "r": snappedf(r, 0.01), "speed": snappedf((_player.call("get_horizontal_velocity") as Vector3).length(), 0.01)}
		if fired:
			match kind:
				"single":
					if f_since == 0: Input.action_press("jump")
					if f_since == 18: Input.action_release("jump")
				"tap":
					if f_since == 0: Input.action_press("jump")
					if f_since == 2: Input.action_release("jump")
				"long":
					if f_since == 0: Input.action_press("crouch")
					if f_since == 2: Input.action_press("jump")
					if f_since == 6: Input.action_release("crouch")
					if f_since == 16: Input.action_release("jump")
				"dive":
					if f_since == 0: Input.action_press("attack")
					if f_since == 2: Input.action_release("attack")
				"hopdive":
					if f_since == 0: Input.action_press("jump")
					if f_since == 3: Input.action_release("jump")
					if f_since == 9: Input.action_press("attack")
					if f_since == 11: Input.action_release("attack")
				"jumpdive":
					if f_since == 0: Input.action_press("jump")
					if f_since == 18: Input.action_release("jump")
					if f_since == 14: Input.action_press("attack")
					if f_since == 16: Input.action_release("attack")
				"sideflip":
					pass
			if f_since == 1:
				launch["state"] = st
			f_since += 1
			max_th = maxf(max_th, th)
			max_y = maxf(max_y, p.y)
			min_y_after = minf(min_y_after, p.y)
			if st == "ledge_hang":
				result = "ledge_hang"
			if f_since > 20 and _grounded():
				if p.y > 8.3 and th > 147.0:
					result = "crossed" if result != "ledge_hang" else "crossed_via_ledge"
				elif p.y > 8.3 and th < 129.0:
					result = "stayed_on_A"
				else:
					result = "fell"
				break
		await _pf()
	_release_all()
	var p2 := _player.global_position
	_record({"task": "cornice", "kind": kind, "th_jump": th_jump, "launch": launch, "states": states,
		"max_th": snappedf(max_th, 0.1), "max_y": snappedf(max_y, 0.01), "end": _v(p2), "end_th": snappedf(theta_of(p2), 0.1),
		"floor": _floor_name(), "result": result, "hp": int(get_tree().root.get_node("Game").get("health"))})
	await _wait(20)


func task_cornice() -> void:
	for th in [116.0, 120.0, 124.0, 127.0]:
		await _cornice_attempt("single", th)
	for th in [124.0, 127.0]:
		await _cornice_attempt("tap", th)
	for th in [122.0, 126.0]:
		await _cornice_attempt("long", th)
	for th in [123.0, 126.0, 127.5]:
		await _cornice_attempt("dive", th)
	for th in [124.0, 127.0]:
		await _cornice_attempt("hopdive", th)
	for th in [112.0, 126.0]:
		await _cornice_attempt("jumpdive", th)


# ------------------------------------------------------------------ task: spiral platforms behaviour (stand still)

func _spiral() -> Node:
	return get_tree().current_scene.find_child("HG_Catalogue_Spiral", true, false)


func _stand_test(label: String, pos: Vector3, frames: int) -> void:
	_mark = "stand:" + label
	_teleport(pos, 0.0)
	var sp := _spiral()
	var t0 := float(sp.get("_t")) if sp else -1.0
	var start := pos
	var min_y := 100.0
	var max_h := 0.0
	var states: Array[String] = []
	var fell_f := -1
	for i in frames:
		var p := _player.global_position
		min_y = minf(min_y, p.y)
		max_h = maxf(max_h, Vector2(p.x - start.x, p.z - start.z).length())
		var st := _state()
		if states.is_empty() or states[-1] != st:
			states.append(st)
		if fell_f < 0 and p.y < pos.y - 0.8:
			fell_f = i
		await _pf()
	_record({"task": "stand", "label": label, "start": _v(pos), "t0": snappedf(t0, 0.01), "min_y": snappedf(min_y, 0.01),
		"max_horizontal_drift": snappedf(max_h, 0.01), "fell_at_frame": fell_f, "states": states, "end": _v(_player.global_position)})


func task_spiral_stand() -> void:
	var bk := HubSpiral.BOOKS
	# SP02 and SP09 wing books: stand at the centre and at the outer half for two full 3 s cycles.
	for idx in [1, 8]:
		var b: Array = bk[idx]
		var top: Vector3 = b[2]
		var out := Vector3(top.x, 0, top.z).normalized()
		await _stand_test(str(b[0]) + "_centre", top + Vector3(0, 0.1, 0), 400)
		await _stand_test(str(b[0]) + "_outer", top + out * 0.45 + Vector3(0, 0.1, 0), 400)
		await _stand_test(str(b[0]) + "_inner", top - out * 0.45 + Vector3(0, 0.1, 0), 400)
	# SP08 atlas: off-centre rider.
	var at: Vector3 = bk[7][2]
	await _stand_test("SP08_centre", at + Vector3(0, 0.1, 0), 360)
	await _stand_test("SP08_edge0.9", at + Vector3(0.9, 0.1, 0), 360)
	# SP05 faller.
	await _stand_test("SP05_centre", (bk[4][2] as Vector3) + Vector3(0, 0.1, 0), 150)


# ------------------------------------------------------------------ task: faller chain timing

func _hop(target: Vector3, delay: int, hold := 18, stick_air := 1.0) -> Dictionary:
	# On the ground: steer at target, wait `delay` frames, jump; steer at target through the air until landing.
	var f := 0
	var jumped := false
	var kind := ""
	var lp := Vector3.ZERO
	for i in 200:
		var p := _player.global_position
		var d := target - p
		d.y = 0
		var st := _state()
		if not jumped:
			_steer(d.normalized())
			if f >= delay and _grounded():
				Input.action_press("jump")
				jumped = true
				f = 0
				lp = p
		else:
			if f == 1:
				kind = st
			if f == hold:
				Input.action_release("jump")
			_steer(d.normalized() * (stick_air if d.length() > 0.3 else 0.0))
			if f > 6 and _grounded():
				break
			if p.y < target.y - 2.5:
				break
		f += 1
		await _pf()
	Input.action_release("jump")
	var e := _player.global_position
	return {"kind": kind, "from": _v(lp, 0.01), "land": _v(e, 0.01), "miss_xz": snappedf(Vector2(e.x - target.x, e.z - target.z).length(), 0.01),
		"on": e.y > target.y - 0.4, "floor": _floor_name()}


func task_faller_chain() -> void:
	var bk := HubSpiral.BOOKS
	var sp04: Vector3 = bk[3][2]
	var sp05: Vector3 = bk[4][2]
	var sp06: Vector3 = bk[5][2]
	var sp07: Vector3 = bk[6][2]
	var sp08: Vector3 = bk[7][2]
	for delay in [2, 8, 14, 20, 26]:
		_mark = "faller_chain:d%d" % delay
		var d0 := sp05 - sp04
		d0.y = 0
		_teleport(sp04 + Vector3(0, 0.12, 0), yaw_for(d0.normalized()))
		await _wait(30)
		var hops := []
		var h1: Dictionary = await _hop(sp05, 4)
		hops.append(h1)
		if h1["on"]:
			var h2: Dictionary = await _hop(sp06, delay)
			hops.append(h2)
			if h2["on"]:
				var h3: Dictionary = await _hop(sp07, delay)
				hops.append(h3)
				if h3["on"]:
					hops.append(await _hop(sp08, delay))
		_release_all()
		_record({"task": "faller_chain", "delay_frames": delay, "hops": hops})
		await _wait(30)


# ------------------------------------------------------------------ task: rim drop + slam (HJ17)

func task_rim_slam() -> void:
	for variant in [["hop_fwd", 1.0, 14], ["hop_apex", 1.0, 22], ["hop_late", 1.0, 30], ["step_off", 1.0, -1]]:
		_mark = "rim_slam:" + str(variant[0])
		_teleport(Vector3(0, 9.2, 2.6), 0.0)
		await _wait(40)
		var f := 0
		var slammed := false
		var land := Vector3.ZERO
		var states: Array[String] = []
		for i in 240:
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
			var p := _player.global_position
			if int(variant[2]) > 0:
				if f == 0:
					Input.action_press("jump")
				if f == 6:
					Input.action_release("jump")
			_steer(Vector3(0, 0, -1) * float(variant[1]) if not slammed else Vector3.ZERO)
			if not slammed and ((int(variant[2]) > 0 and f >= int(variant[2])) or (int(variant[2]) < 0 and p.z < 1.6 and not _grounded())):
				Input.action_press("crouch")
				slammed = true
			if slammed and f > 2 and _grounded() and p.y < 8.5:
				land = p
				break
			f += 1
			await _pf()
		_release_all()
		_record({"task": "rim_slam", "variant": variant[0], "states": states, "land": _v(land),
			"from_dome_axis": snappedf(Vector2(land.x, land.z - 1.0).length(), 0.01), "floor": _floor_name(),
			"hp": int(get_tree().root.get_node("Game").get("health"))})
		await _shot("rim_slam_" + str(variant[0]))
		await _wait(30)


# ------------------------------------------------------------------ task: nook slam (HJ8) with the real camera

func task_nook() -> void:
	_mark = "nook"
	_teleport(Vector3(-5.2, 0.02, -10.6), -90.0)
	await _wait(30)
	var target := Vector3(0, 0, -11.8)
	var states: Array[String] = []
	var max_y := 0.0
	for i in 400:
		var p := _player.global_position
		var d := target - p
		d.y = 0
		if d.length() > 0.15:
			_steer(d.normalized() * (1.0 if d.length() > 1.0 else 0.35))
		else:
			break
		await _pf()
	_release_all()
	await _wait(20)
	await _shot("nook_before_slam")
	Input.action_press("jump")
	for i in 60:
		var st := _state()
		if states.is_empty() or states[-1] != st:
			states.append(st)
		max_y = maxf(max_y, _player.global_position.y)
		if i == 10:
			Input.action_release("jump")
		if i == 20:
			Input.action_press("crouch")
		if i == 23:
			Input.action_release("crouch")
		await _pf()
	await _wait(30)
	_record({"task": "nook", "states": states, "max_feet_y": snappedf(max_y, 0.01), "end": _v(_player.global_position),
		"nook_done": bool(get_tree().root.get_node("Game").call("is_unlocked", "hub_nook_done"))})
	await _shot("nook_after_slam")


# ------------------------------------------------------------------ task: long-jump lane (H-I)

func task_longjump_lane() -> void:
	var g := get_tree().root.get_node("Game")
	for variant in ["long", "single"]:
		_mark = "lane:" + variant
		_teleport(Vector3(-8.4, 0.02, 3.4), 0.0)
		await _wait(30)
		var a0 := int(g.get("acorns"))
		var fired := false
		var f := 0
		var maxz := 0.0
		for i in 240:
			var p := _player.global_position
			_steer(Vector3(0, 0, -1))
			if not fired and p.z < 0.2:
				fired = true
			if fired:
				if variant == "long":
					if f == 0: Input.action_press("crouch")
					if f == 2: Input.action_press("jump")
					if f == 6: Input.action_release("crouch")
					if f == 16: Input.action_release("jump")
				else:
					if f == 0: Input.action_press("jump")
					if f == 18: Input.action_release("jump")
				f += 1
				if f > 20 and _grounded():
					break
			await _pf()
		_release_all()
		_record({"task": "lane", "variant": variant, "acorns_gained": int(g.get("acorns")) - a0, "end": _v(_player.global_position)})
		await _wait(20)


# ------------------------------------------------------------------ task: updraft with stick held (H-F)

func task_updraft() -> void:
	for variant in [["hands_off", Vector3.ZERO], ["hold_hall", Vector3(1, 0, -0.3).normalized()], ["hold_out", Vector3(-0.9, 0, 0.6).normalized()]]:
		_mark = "updraft:" + str(variant[0])
		_teleport(Vector3(-8.1, 0.42, 5.7), yaw_for(Vector3(-9.34 + 8.1, 0, 6.54 - 5.7).normalized()))
		await _wait(30)
		var max_y := 0.0
		var states: Array[String] = []
		for i in 360:
			var p := _player.global_position
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
			max_y = maxf(max_y, p.y)
			if i < 12:
				_steer((Vector3(-9.34, 0, 6.54) - Vector3(p.x, 0, p.z)).normalized())
			elif i == 12:
				Input.action_press("jump")
			else:
				_steer(variant[1])
			if i == 30:
				Input.action_release("jump")
			if i > 60 and _grounded():
				break
			await _pf()
		_release_all()
		_record({"task": "updraft", "variant": variant[0], "max_y": snappedf(max_y, 0.01), "end": _v(_player.global_position),
			"floor": _floor_name(), "states": states})
		await _wait(20)


# ------------------------------------------------------------------ task: what is under the cornice gap (layer 1)

func task_gap_audit() -> void:
	var space := _cam.get_world_3d().direct_space_state
	var rows := []
	var th := 124.0
	while th <= 152.0:
		for r in [14.6, 15.0, 15.3, 15.6, 15.85]:
			var top := pp(r, th, 10.5)
			var q := PhysicsRayQueryParameters3D.create(top, pp(r, th, 6.0), 1, _excl())
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				rows.append([th, r, null])
			else:
				var c: Object = hit.get("collider")
				rows.append([th, r, snappedf((hit["position"] as Vector3).y, 0.01), snappedf((hit["normal"] as Vector3).y, 0.01), str((c as Node).name) if c is Node else "?"])
		th += 2.0
	_record({"task": "gap_audit", "rows": rows})


# ------------------------------------------------------------------ task: hug the wall across the gap (r 15.6)

func task_cap_walk() -> void:
	for rr in [15.6, 15.75]:
		_mark = "cap_walk:%.2f" % rr
		_teleport(pp(rr, 125.0, 8.55), yaw_for(tangent(125.0)))
		await _wait(60)
		await _shot("cap_walk_start_%.2f" % rr)
		var states: Array[String] = []
		var max_th := 0.0
		for i in 360:
			var p := _player.global_position
			var th := theta_of(p)
			var r := Vector2(p.x, p.z).length()
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
			max_th = maxf(max_th, th)
			_steer((tangent(th) + pp(1, th, 0) * clampf((rr - r) * 1.5, -0.6, 0.6)).normalized() * 0.5)
			if p.y < 7.5 or th > 150.0:
				break
			await _pf()
		_release_all()
		await _wait(60)
		_record({"task": "cap_walk", "r": rr, "states": states, "max_th": snappedf(max_th, 0.1), "end": _v(_player.global_position),
			"end_th": snappedf(theta_of(_player.global_position), 0.1), "floor": _floor_name()})


# ------------------------------------------------------------------ task: take-off lane width and the cap wedge in the gap

func task_wedge() -> void:
	# 1) Run along the runway at fixed radii without jumping: does the cap wedge's end face at theta 128 stop Mak?
	for rr in [14.7, 14.95, 15.15, 15.45]:
		_mark = "lane_r%.2f" % rr
		_teleport(pp(rr, 116.0, 8.55), yaw_for(tangent(116.0)))
		await _wait(30)
		var sp := {}
		var min_sp := 99.0
		var states: Array[String] = []
		for i in 300:
			var p := _player.global_position
			var th := theta_of(p)
			var r := Vector2(p.x, p.z).length()
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
			var hs := (_player.call("get_horizontal_velocity") as Vector3).length()
			for k in [124.0, 126.0, 127.0, 127.5, 128.0, 128.5]:
				if th >= k and not sp.has(str(k)):
					sp[str(k)] = [snappedf(hs, 0.01), snappedf(r, 0.01)]
			if th > 125.5:
				min_sp = minf(min_sp, hs)
			_steer((tangent(th) + pp(1, th, 0) * clampf((rr - r) * 1.5, -0.6, 0.6)).normalized())
			if p.y < 8.0 or th > 131.0 or (i > 200 and hs < 0.3):
				break
			await _pf()
		_release_all()
		_record({"task": "lane", "r": rr, "speed_at_theta": sp, "min_speed_after_125_5": snappedf(min_sp, 0.01), "states": states,
			"end": _v(_player.global_position), "end_th": snappedf(theta_of(_player.global_position), 0.1)})
		await _wait(20)
	# 2) Land on the wedge in the gap with no input / holding along the gap / jumping from the slide.
	for variant in ["neutral", "hold_along", "jump_from_slide", "jump_twice"]:
		_mark = "wedge:" + variant
		_teleport(pp(15.6, 133.0, 9.6), yaw_for(tangent(133.0)))
		var states: Array[String] = []
		var max_th := 0.0
		var max_y := 0.0
		var jumps := 0
		var jf := -1
		var on_b_y := -1.0
		for i in 240:
			var p := _player.global_position
			var th := theta_of(p)
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
			max_th = maxf(max_th, th)
			max_y = maxf(max_y, p.y)
			if variant != "neutral":
				_steer(tangent(th))
			if variant.begins_with("jump") and st == "slope_slide" and jf < 0 and (jumps == 0 or (variant == "jump_twice" and jumps == 1)):
				Input.action_press("jump")
				jf = 0
				jumps += 1
			if jf >= 0:
				jf += 1
				if jf > 16:
					Input.action_release("jump")
					if st != "jump":
						jf = -1
			if th > 148.5 and p.y > 8.4 and _grounded():
				on_b_y = p.y
			await _pf()
		_release_all()
		_record({"task": "wedge", "variant": variant, "states": states, "jumps": jumps, "max_th": snappedf(max_th, 0.1), "max_y": snappedf(max_y, 0.01),
			"end": _v(_player.global_position), "end_th": snappedf(theta_of(_player.global_position), 0.1), "reached_cornice_B": on_b_y > 0.0,
			"floor": _floor_name()})
		await _wait(20)


func task_wedge2() -> void:
	# Natural landings on the cap wedge: drop from 1.2 m above it, and the real case (single jump bonks the lintel).
	for variant in ["drop_neutral", "drop_hold_along", "drop_jump_on_land", "bonk_rejump"]:
		_mark = "wedge2:" + variant
		if variant == "bonk_rejump":
			_teleport(pp(14.8, 112.0, 8.55), yaw_for(tangent(112.0)))
		else:
			_teleport(pp(15.55, 133.0, 10.5), yaw_for(tangent(133.0)))
		var states: Array[String] = []
		var max_th := 0.0
		var jumps := 0
		var jf := -1
		var on_b := false
		var phase := 0
		var floors: Array[String] = []
		for i in 300:
			var p := _player.global_position
			var th := theta_of(p)
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
				floors.append(_floor_name().get_slice("<", 0) + "@%.2f" % p.y)
			max_th = maxf(max_th, th)
			if variant != "drop_neutral":
				var r := Vector2(p.x, p.z).length()
				_steer((tangent(th) + pp(1, th, 0) * clampf((14.8 - r) * 1.5, -0.4, 0.4) * (1.0 if th < 128.0 else 0.0)).normalized())
			if variant == "bonk_rejump" and phase == 0 and th >= 123.0 and _grounded():
				Input.action_press("jump")
				jf = 0
				jumps += 1
				phase = 1
			elif variant != "drop_neutral" and variant != "drop_hold_along" and phase <= 1 and i > 3 and (st == "slope_slide" or st == "land" or (phase == 1 and jf < 0 and _grounded() and p.y > 8.6)):
				if jf < 0:
					Input.action_press("jump")
					jf = 0
					jumps += 1
					phase = 2
			if jf >= 0:
				jf += 1
				if jf > 16:
					Input.action_release("jump")
					jf = -1
			if th > 148.5 and p.y > 8.4 and _grounded():
				on_b = true
			if p.y < 6.0 and i > 60:
				break
			await _pf()
		_release_all()
		_record({"task": "wedge2", "variant": variant, "states": states, "floors": floors, "jumps": jumps, "max_th": snappedf(max_th, 0.1),
			"end": _v(_player.global_position), "end_th": snappedf(theta_of(_player.global_position), 0.1), "reached_cornice_B": on_b})
		await _wait(20)


func _fallers_idle() -> bool:
	var sp := _spiral()
	if sp == null:
		return true
	for d in sp.get("_books"):
		if String(d["kind"]) == "falling" and String(d["state"]) != "idle":
			return false
	return true


## Hop rhythm on the spiral: after each landing wait `delay` physics frames, then jump (a jump inside the 0.25 s chain
## window becomes a double jump). Static run SP01 -> SP04 and faller run SP04 -> SP07.
func task_rhythm() -> void:
	var bk := HubSpiral.BOOKS
	for run in [["static", 0, [1, 2, 3]], ["faller", 3, [4, 5, 6]]]:
		for delay in [3, 10, 16, 20, 24]:
			for i in 400:
				if _fallers_idle():
					break
				await _pf()
			_mark = "rhythm:%s:d%d" % [run[0], delay]
			var start: Vector3 = bk[int(run[1])][2]
			var first: Vector3 = bk[(run[2] as Array)[0]][2]
			var d0 := first - start
			d0.y = 0
			_teleport(start + Vector3(0, 0.12, 0), yaw_for(d0.normalized()))
			await _wait(25)
			var hops := []
			var k := 0
			for idx in run[2]:
				var tgt: Vector3 = bk[idx][2]
				var h: Dictionary = await _hop(tgt, 6 if k == 0 else delay)
				h["to"] = bk[idx][0]
				hops.append(h)
				k += 1
				if not h["on"]:
					break
			_release_all()
			_record({"task": "rhythm", "run": run[0], "delay_frames": delay, "hops": hops})
			await _wait(20)


## Mastery chimney (HJ4) with the gameplay camera: same input logic as the builder's autopilot (run tangentially at
## fin B, jump, kick back and forth until above 9.7, drift onto the top balcony). Shots at each kick.
func task_chimney() -> void:
	_mark = "chimney"
	_teleport(pp(14.5, 206.6, 4.55), yaw_for(tangent(206.6)))
	await _wait(60)
	await _shot("chimney_00_start")
	var dir := 1.0
	var kicks := 0
	var jumped := false
	var jf := 0
	var prev := ""
	var t := 0
	var states: Array[String] = []
	var result := "timeout"
	for i in 900:
		var p := _player.global_position
		var th := theta_of(p)
		var st := _state()
		if states.is_empty() or states[-1] != st:
			states.append(st)
		var tang := tangent(th)
		if _grounded() and p.y > 9.6:
			result = "top_balcony"
			break
		if p.y > 10.2:
			_steer(-tang)
		else:
			_steer(tang * dir)
		if not jumped and _grounded() and t > 15:
			jumped = true
			jf = 16
		if st == "wall_slide" and prev != "wall_slide":
			jf = 10
			kicks += 1
			dir = -dir
			await _shot("chimney_%02d_kick" % kicks)
		prev = st
		if jf > 0:
			Input.action_press("jump")
			jf -= 1
			if jf == 0:
				Input.action_release("jump")
		if jumped and _grounded() and t > 60 and p.y < 5.0:
			result = "fell_back"
			break
		t += 1
		await _pf()
	_release_all()
	await _wait(30)
	await _shot("chimney_99_end")
	_record({"task": "chimney", "result": result, "kicks": kicks, "states": states, "end": _v(_player.global_position)})


## Ladder L2 to the cornice (and L1) with the gameplay camera.
func task_ladder() -> void:
	for spec in [["L2", Vector3(12.55, 4.55, 3.6), Vector3(12.5, 4.5, 4.55)], ["L1", Vector3(8.9, 0.05, -5.2), pp(11.25, 60.0, 0.0)]]:
		_mark = "ladder:" + str(spec[0])
		var tgt: Vector3 = spec[2]
		var d0 := tgt - (spec[1] as Vector3)
		d0.y = 0
		_teleport(spec[1], yaw_for(d0.normalized()))
		await _wait(30)
		var states: Array[String] = []
		var climbing := false
		var shots := 0
		for i in 720:
			var p := _player.global_position
			var st := _state()
			if states.is_empty() or states[-1] != st:
				states.append(st)
				if st in ["pole_climb", "ledge_hang", "ledge_climb"] or (climbing and st == "idle"):
					shots += 1
					await _shot("ladder_%s_%02d_%s" % [spec[0], shots, st])
			if st == "pole_climb":
				climbing = true
				_steer(Vector3.ZERO)
				Input.action_press("move_forward", 1.0)
			elif not climbing:
				var d := tgt - p
				d.y = 0
				_steer(d.normalized())
				if d.length() < 0.8 and _grounded():
					Input.action_press("jump")
			else:
				Input.action_release("jump")
				if _grounded() and i > 30:
					break
			await _pf()
		_release_all()
		await _wait(40)
		await _shot("ladder_%s_99_top" % spec[0])
		_record({"task": "ladder", "ladder": spec[0], "states": states, "end": _v(_player.global_position)})


## A person on the cornice holds the stick to the right (the radial camera makes "right" the run direction). No
## correction: where does Mak run, and does he reach the take-off at full speed?
func task_stick_right() -> void:
	for r0 in [14.8, 15.2]:
		_mark = "stick_right:%.1f" % r0
		_teleport(pp(r0, 102.0, 8.55), yaw_for(tangent(102.0)))
		_release_all()
		await _wait(90)
		var log := {}
		var min_sp := 99.0
		for i in 300:
			Input.action_press("move_right", 1.0)
			var p := _player.global_position
			var th := theta_of(p)
			var r := Vector2(p.x, p.z).length()
			var hs := (_player.call("get_horizontal_velocity") as Vector3).length()
			for k in [106.0, 110.0, 115.0, 120.0, 124.0, 126.0, 127.0, 128.0]:
				if th >= k and not log.has(str(k)):
					log[str(k)] = [snappedf(r, 0.02), snappedf(hs, 0.01), snappedf(rad_to_deg(float(_rig.get("yaw"))), 0.1)]
			if th > 124.0:
				min_sp = minf(min_sp, hs)
			if p.y < 8.0 or th > 130.0 or (i > 150 and hs < 0.3):
				break
			await _pf()
		_release_all()
		_record({"task": "stick_right", "r0": r0, "at_theta[r, speed, cam_yaw]": log, "min_speed_after_124": snappedf(min_sp, 0.01),
			"end": _v(_player.global_position), "end_th": snappedf(theta_of(_player.global_position), 0.1), "state": _state()})
		await _wait(20)

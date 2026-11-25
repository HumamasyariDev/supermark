extends Node
## Critique W2 round 1, QA probe 2 (targeted follow-ups to probe 1).
## 1 E02 / E01 spawn trace vs the island surface; 2 runtime notice_radius vs what w2_play.gd asked for;
## 3 reachability of acorns whose centre is inside world collision; 4 views of suspect spots;
## 5 fall-out respawn; 6 vsync-on frame rate; 7 the seed descent end state.

const CAPSULE_R := 0.35
const CAPSULE_H := 1.25

var out_dir := ""
var world: Node
var player: CharacterBody3D
var report := {}
var damage_log: Array = []
var _bucket: PackedFloat32Array = PackedFloat32Array()
var _measuring := false
var _trace: Array = []
var _trace_frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("qa-out", OS.get_user_data_dir().path_join("w2_qa2")) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _process(delta: float) -> void:
	if _measuring:
		_bucket.append(delta)


func _physics_process(_d: float) -> void:
	if world == null or _trace_frames > 90:
		return
	_trace_frames += 1
	var row := {"f": _trace_frames}
	for id in ["E01", "E02"]:
		var e := world.find_child(id, true, false) as Node3D
		if e:
			row[id] = [snappedf(e.global_position.y, 0.01)]
	if _trace_frames in [1, 2, 3, 5, 10, 20, 40, 90]:
		_trace.append(row)


func log_line(s: String) -> void:
	print("[QA2] " + s)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _space() -> PhysicsDirectSpaceState3D:
	return (world as Node3D).get_world_3d().direct_space_state


func _surface_y(x: float, z: float, from_y: float) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - 40.0, z), 1)
	if player:
		q.exclude = [player.get_rid()]
	var hit := _space().intersect_ray(q)
	return null if hit.is_empty() else snappedf((hit["position"] as Vector3).y, 0.01)


func _capsule_free(feet: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_R
	shape.height = CAPSULE_H
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), feet + Vector3(0, CAPSULE_H * 0.5 + 0.02, 0))
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	return _space().intersect_shape(q, 1).is_empty()


func _all_of(root: Node, pred: Callable, acc: Array) -> Array:
	if pred.call(root):
		acc.append(root)
	for c in root.get_children():
		_all_of(c, pred, acc)
	return acc


func _shot(name_: String, eye: Vector3, at: Vector3, fov := 60.0) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	world.add_child(cam)
	cam.global_position = eye
	cam.look_at(at, Vector3.UP)
	var prev := get_viewport().get_camera_3d()
	cam.make_current()
	await _wait(0.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name_ + ".png"))
	if prev:
		prev.make_current()
	cam.queue_free()


func _measure(name_: String, settle: float, sec: float) -> Dictionary:
	await _wait(settle)
	_bucket = PackedFloat32Array()
	_measuring = true
	await _wait(sec)
	_measuring = false
	var arr := Array(_bucket)
	arr.sort()
	if arr.is_empty():
		return {"name": name_}
	var sum := 0.0
	var over := 0
	for d in arr:
		sum += d
		if d > 1.0 / 60.0 + 0.002:
			over += 1
	var p99: float = arr[maxi(int(floor(arr.size() * 0.99)) - 1, 0)]
	var s := {"name": name_, "frames": arr.size(), "mean_fps": snappedf(arr.size() / sum, 0.1), "p99_ms": snappedf(p99 * 1000.0, 0.01), "max_ms": snappedf(float(arr[arr.size() - 1]) * 1000.0, 0.01), "frames_over_18_7ms": over}
	log_line("FPS " + JSON.stringify(s))
	return s


func _place(p: Vector3, yaw := 0.0) -> void:
	player.call("respawn", Transform3D(Basis(Vector3.UP, yaw), p))
	player.reset_physics_interpolation()
	var rig := player.get_node_or_null("MakCamera")
	if rig and rig.has_method("snap_behind"):
		rig.call("snap_behind")


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and cs.get("player") != null:
			world = cs
			player = cs.get("player") as CharacterBody3D
			break
		if Time.get_ticks_msec() - t0 > 120000:
			get_tree().quit(2)
			return
	var game := get_node_or_null("/root/Game")
	game.damaged.connect(func(a: int) -> void: damage_log.append({"t": Time.get_ticks_msec(), "pos": _v(player.global_position), "phase": report.get("_phase", "")}))
	# 1 + 2: spawn trace and notice radii.
	var b = world.get("builder")
	var asked := {"E01": 5.5, "E02": 5.5, "E03": 8.0, "E04": 8.0, "E05": 10.0, "E06": 10.0, "E07": 10.0, "E08": 10.0, "E09": 10.0, "E10": 7.0, "E11": 0.0, "E12": 0.0, "E13": 0.0, "E14": 8.0, "E15": 8.0}
	var nr := []
	for e in get_tree().get_nodes_in_group("enemy"):
		var id := str(e.name)
		nr.append({"id": id, "asked": asked.get(id, null), "runtime": e.get("notice_radius"), "lose_radius": e.get("lose_radius"), "reload_time": e.get("reload_time") if "reload_time" in e else null})
	report["notice_radius"] = nr
	var spawn_y := {}
	for id in ["E01", "E02"]:
		var e := world.find_child(id, true, false) as Node3D
		if e:
			var hx: Variant = b.call("island_h", e.global_position.x, e.global_position.z) if b and b.has_method("island_h") else null
			spawn_y[id] = {"pos_now": _v(e.global_position), "island_h": hx, "collision_surface": _surface_y(e.global_position.x, e.global_position.z, 10.0)}
	report["garden_pods"] = spawn_y
	await _wait(2.0)
	report["spawn_trace"] = _trace
	# Distance from the Default spawn to E01, and whether E01 noticed.
	var e01 := world.find_child("E01", true, false) as Node3D
	var dm := world.get_node("Spawns/Default") as Node3D
	report["default_to_E01_m"] = snappedf(e01.global_position.distance_to(dm.global_position), 0.01) if e01 else null
	report["E01_state_2s"] = str(e01.get("state")) if e01 else null
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# 3: acorn reachability.
	report["_phase"] = "acorns"
	var ac_rows := []
	var pq := PhysicsPointQueryParameters3D.new()
	pq.collision_mask = 1
	for ac in _all_of(world, func(n: Node) -> bool: return n is Acorn, []):
		var hh: float = float(ac.get("hover_height")) if "hover_height" in ac else 0.0
		var c: Vector3 = (ac as Node3D).global_position + Vector3(0, hh, 0)
		pq.position = c
		var hits := _space().intersect_point(pq, 1)
		if hits.is_empty():
			continue
		# Could Mak's capsule overlap the 0.45 m pickup sphere anywhere? Try capsule feet around the acorn.
		var reach := false
		for dy in [-1.4, -1.0, -0.6, -0.2, 0.2]:
			for k in 12:
				var a := TAU * float(k) / 12.0
				for r in [0.0, 0.4, 0.7]:
					var feet := c + Vector3(cos(a) * r, dy, sin(a) * r)
					# Capsule axis closest point to c must be within 0.45 + 0.35.
					var axis_y := clampf(c.y, feet.y + CAPSULE_R, feet.y + CAPSULE_H - CAPSULE_R)
					var d := Vector2(c.x - feet.x, c.z - feet.z).length()
					var dist := sqrt(d * d + pow(c.y - axis_y, 2))
					if dist <= 0.45 + CAPSULE_R and _capsule_free(feet):
						reach = true
						break
				if reach:
					break
			if reach:
				break
		ac_rows.append({"name": str(ac.get_path()).replace(str(world.get_path()), ""), "centre": _v(c), "inside": str((hits[0]["collider"] as Node).name) if hits[0]["collider"] else "?", "reachable": reach})
	report["acorns_inside_collision"] = ac_rows
	log_line("ACORNS " + JSON.stringify(ac_rows))
	# 4: views of suspect spots (gameplay paused feel not needed).
	await _shot("view_E02_spawn", Vector3(16, 4, 34), Vector3(11.5, 0, 28.5))
	await _shot("view_crate_A12a", Vector3(22.0, 29.0, -9.0), Vector3(17.5, 24.0, -15.5))
	await _shot("view_acorn_A35_1", Vector3(14.5, 52.0, -12.0), Vector3(12.0, 48.6, -17.6))
	await _shot("view_acorns_A38", Vector3(-5.0, 59.5, -31.0), Vector3(-9.2, 57.0, -36.4))
	await _shot("view_acorns_A15", Vector3(24.0, 30.0, -6.0), Vector3(27.6, 27.9, -11.6))
	await _shot("view_acorn_A22", Vector3(-37.0, 49.0, -35.0), Vector3(-41.8, 46.0, -39.3))
	# 5: fall-out respawn. Touch CP2 first (sets the bookmark), then drop below kill_y.
	report["_phase"] = "fallout"
	var cp2 := world.find_child("CP2", true, false) as Node3D
	_place(cp2.global_position + Vector3(0, 0.3, 0))
	await _wait(1.0)
	var h0: int = int(game.get("health"))
	var has_cp: bool = game.call("has_checkpoint", "W2")
	_place(Vector3(30.0, float(world.get("kill_y")) + 3.0, 30.0))
	await _wait(2.0)
	report["fallout"] = {"checkpoint_set": has_cp, "health_before": h0, "health_after": int(game.get("health")), "respawned_at": _v(player.global_position), "cp2": _v(cp2.global_position), "on_floor": player.is_on_floor()}
	log_line("FALLOUT " + JSON.stringify(report["fallout"]))
	# 6: vsync-on frame pacing at the three busiest gameplay spots.
	report["_phase"] = "vsync"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	report["refresh_rate"] = DisplayServer.screen_get_refresh_rate()
	var vs := []
	for pt in [["Default", dm.global_position], ["CP2b", (world.find_child("CP2b", true, false) as Node3D).global_position], ["Page2", Vector3(-14.4, 8.3, 18.9)], ["CP4", (world.find_child("CP4", true, false) as Node3D).global_position]]:
		_place(pt[1] + Vector3(0, 0.2, 0))
		vs.append(await _measure("vsync:" + str(pt[0]), 1.0, 3.0))
	report["vsync_on"] = vs
	# 7: descent end state.
	report["_phase"] = "descent"
	var d := world.find_child("W2Descent", true, false)
	if d:
		var layer0 := player.collision_layer
		d.call("start")
		await _wait(6.0)
		report["descent_mid"] = {"pos": _v(player.global_position), "layer": player.collision_layer, "physics": player.is_physics_processing()}
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("descent_mid.png"))
		await _wait(8.0)
		var dmg0 := damage_log.size()
		await _wait(4.0)
		report["descent_end"] = {"pos": _v(player.global_position), "layer": player.collision_layer, "layer_before": layer0, "physics": player.is_physics_processing(), "on_floor": player.is_on_floor(), "damage_within_4s_after_landing": damage_log.size() - dmg0, "running": d.get("running")}
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("descent_end.png"))
		log_line("DESCENT " + JSON.stringify(report["descent_end"]))
	report["damage_log"] = damage_log
	var f := FileAccess.open(out_dir.path_join("w2_qa_probe2.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	get_tree().quit()

extends Node
## Critique W2 round 1 (QA lens, pass r1c, 20:55 Bangkok, on the fix-round build with w2_fix2.gd).
## Read-only for the world: moves the player, presses actions, calls public start/open methods.
## Phases:
##  A void catch (w2_fix2): safe ground recorded on a MOVING body (U02 runner leaf, the bell), then a fall into the
##    void; counts catches and checks where Mak ends (looping catches = softlock).
##  B void catch from static high ground (castle bank) and a plain kill_y fall from the island rim (time, hearts).
##  C bluebell bud: open it and check where Page4 and the A19 ring end up (unbury after re-adding).
##  D seed descent: start, jump-skip at 2 s, landing on floor, physics/collision restored, camera restored, damage,
##    whether the skip press leaks into a jump.
##  E truffle save: stand on W2-1, check save file and ghost state after a scene reload.
##  F gameplay-camera fps on a scripted run along the Lower Stalk and at the castle courtyard.
## Run: python tools/godot.py capture res://tests/critique_w2/W2QA.tscn <png> --wait 999999 -- --profile=critic_w2_qa_p4 --w2-nointro --qa-probe=4 --qa-out=<abs dir>

var out_dir := ""
var world: Node
var player: CharacterBody3D
var report := {}
var damage_log: Array = []
var truffle_log: Array = []
var _bucket: PackedFloat32Array = PackedFloat32Array()
var _measuring := false
var _trace_on := false
var _trace: Array = []
var _t0 := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("qa-out", OS.get_user_data_dir().path_join("w2_qa4")) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _physics_process(_d: float) -> void:
	if _trace_on and player and is_instance_valid(player):
		_trace.append([Time.get_ticks_msec(), player.global_position, player.is_on_floor()])


func _process(delta: float) -> void:
	if _measuring:
		_bucket.append(delta)
	if Time.get_ticks_msec() - _t0 > 330000:
		report["aborted"] = "global cap 330 s"
		_save()
		get_tree().quit(3)


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func _save() -> void:
	report["damage_log"] = damage_log
	report["truffle_log"] = truffle_log
	var f := FileAccess.open(out_dir.path_join("w2_qa_probe4.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(out_dir.path_join(name_ + ".png"))


func _ray_down(p: Vector3, dist := 80.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3(0, -dist, 0), 1)
	return player.get_world_3d().direct_space_state.intersect_ray(q)


func _place(p: Vector3) -> void:
	player.call("respawn", Transform3D(Basis(), p))


func _wait_world() -> bool:
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and cs.get("player") != null and cs.get("builder") != null:
			world = cs
			player = cs.get("player") as CharacterBody3D
			return true
		if Time.get_ticks_msec() - t0 > 180000:
			return false
	return false


func _run() -> void:
	if not await _wait_world():
		print("[QA4] TIMEOUT")
		get_tree().quit(2)
		return
	report["load_ms"] = Time.get_ticks_msec() - _t0
	var game := get_node_or_null("/root/Game")
	if game:
		game.damaged.connect(func(a: int) -> void: damage_log.append({"t": Time.get_ticks_msec() - _t0, "amount": a, "pos": _v(player.global_position), "phase": report.get("_phase", "")}))
		game.truffle_collected.connect(func(id: String) -> void: truffle_log.append({"id": id, "phase": report.get("_phase", "")}))
	report["viewport"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(3.0)
	for ph in ["A", "B", "C", "D", "F", "E"]:
		report["_phase"] = ph
		print("[QA4] phase ", ph)
		match ph:
			"A": await _phase_a()
			"B": await _phase_b()
			"C": await _phase_c()
			"D": await _phase_d()
			"E": await _phase_e()
			"F": await _phase_f()
		_save()
	report["_phase"] = "done"
	_save()
	print("[QA4] done")
	get_tree().quit(0)


## Finds a point 3-9 m out from `from` (horizontal) with no collision for 80 m below.
func _void_near(from: Vector3) -> Vector3:
	var c: Vector3 = world.get("builder").call("stalk_center", from.y) if world.get("builder").has_method("stalk_center") else Vector3.ZERO
	var out := Vector3(from.x - c.x, 0, from.z - c.z)
	if out.length() < 0.1:
		out = Vector3(1, 0, 0)
	out = out.normalized()
	for r: float in [3.0, 4.0, 5.0, 6.0, 8.0, 10.0]:
		for a: float in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 180.0]:
			var d := out.rotated(Vector3.UP, deg_to_rad(a))
			var p := from + d * r + Vector3(0, 0.5, 0)
			if _ray_down(p, 120.0).is_empty():
				return p
	return Vector3.INF


## Stand on `body` for `stand` s, optionally wait `drift` s, then drop into the void beside it; trace 9 s.
func _catch_test(label: String, body: Node3D, stand: float, drift: float) -> Dictionary:
	var r := {"label": label}
	if body == null:
		r["error"] = "body missing"
		return r
	var top := _ray_down(body.global_position + Vector3(0, 6, 0), 12.0)
	var stand_at: Vector3 = (top["position"] if not top.is_empty() else body.global_position) + Vector3(0, 0.3, 0)
	_place(stand_at)
	await _wait(stand)
	r["stood_on_floor"] = player.is_on_floor()
	r["body_at_stand"] = _v(body.global_position)
	r["player_at_stand"] = _v(player.global_position)
	await _wait(drift)
	r["body_at_drop"] = _v(body.global_position)
	var vp := _void_near(player.global_position)
	if vp == Vector3.INF:
		r["error"] = "no void point found"
		return r
	r["drop_from"] = _v(vp)
	var hearts_before := int(get_node("/root/Game").get("health"))
	var dmg_before := damage_log.size()
	_trace.clear()
	_trace_on = true
	_place(vp)
	await _wait(9.0)
	_trace_on = false
	# Count teleports up (catches / respawns): a frame-to-frame rise above 2.5 m.
	var jumps := []
	for i in range(1, _trace.size()):
		var a: Vector3 = _trace[i - 1][1]
		var b: Vector3 = _trace[i][1]
		if b.y - a.y > 2.5 or a.distance_to(b) > 6.0:
			jumps.append({"t_ms": _trace[i][0] - _trace[0][0], "from": _v(a), "to": _v(b)})
	r["teleports"] = jumps
	r["end"] = _v(player.global_position)
	r["end_on_floor"] = player.is_on_floor()
	r["min_y"] = snappedf(_trace.reduce(func(m, e): return minf(m, (e[1] as Vector3).y), 1e9), 0.01) if _trace.size() > 0 else 0.0
	r["hearts_lost"] = hearts_before - int(get_node("/root/Game").get("health"))
	r["damage_events"] = damage_log.size() - dmg_before
	await _shot("A_" + label)
	return r


func _phase_a() -> void:
	var b = world.get("builder")
	var life: Node = world.get("life")
	var res := []
	res.append(await _catch_test("U02_moving_leaf_drift1p8", b.bodies.get("U02"), 1.0, 1.8))
	res.append(await _catch_test("U02_moving_leaf_nodrift", b.bodies.get("U02"), 1.0, 0.0))
	var bell: Node3D = life.get("bell") if life else null
	res.append(await _catch_test("bell_drift1p5", bell, 1.0, 1.5))
	var lb5: Node3D = b.bodies.get("LB5")
	res.append(await _catch_test("LB5_bouncer", lb5, 0.6, 0.0))
	report["A_void_catch"] = res


func _phase_b() -> void:
	var res := []
	# Static high ground: CP5 / CP6 / CP7 area (castle), then a low island rim fall to kill_y.
	var cps := world.find_child("Checkpoints", true, false)
	for nm in ["CP5", "CP7"]:
		var c := cps.find_child(nm, true, false) as Node3D if cps else null
		if c:
			var dummy := Node3D.new()
			add_child(dummy)
			dummy.global_transform = c.global_transform
			res.append(await _catch_test("static_" + nm, dummy, 1.2, 0.0))
			dummy.queue_free()
	# Kill-y fall from the garden rim.
	var dm := world.get_node("Spawns/Default") as Node3D
	var p := dm.global_position
	var vp := Vector3.INF
	for r: float in [20.0, 26.0, 32.0, 40.0, 48.0]:
		for a: int in range(0, 360, 30):
			var q := p + Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a))) * r + Vector3(0, 1, 0)
			if _ray_down(q, 200.0).is_empty():
				vp = q
				break
		if vp != Vector3.INF:
			break
	var kr := {"label": "killy_fall"}
	if vp != Vector3.INF:
		var hb := int(get_node("/root/Game").get("health"))
		_trace.clear()
		_trace_on = true
		var t0 := Time.get_ticks_msec()
		_place(vp)
		var back := -1
		while Time.get_ticks_msec() - t0 < 12000:
			await get_tree().physics_frame
			if player.global_position.y > vp.y - 1.0 and Time.get_ticks_msec() - t0 > 300 and player.global_position.distance_to(vp) > 5.0:
				back = Time.get_ticks_msec() - t0
				break
		_trace_on = false
		kr["drop_from"] = _v(vp)
		kr["kill_y"] = world.get("kill_y")
		kr["respawn_after_ms"] = back
		kr["respawn_at"] = _v(player.global_position)
		kr["hearts_lost"] = hb - int(get_node("/root/Game").get("health"))
		await _wait(2.0)
		kr["end_on_floor"] = player.is_on_floor()
	res.append(kr)
	report["B_static_and_killy"] = res
	get_node("/root/Game").call("full_heal")


func _phase_c() -> void:
	var play = world.get("play")
	var r := {}
	if play == null:
		report["C_bud"] = {"error": "no play"}
		return
	var held: Array = play.get("_bud_held")
	r["held_before"] = held.map(func(n): return [String(n.name), _v(n.position)]) if held else []
	var bud: Node3D = play.get("bud")
	r["bud_at"] = _v(bud.global_position) if bud else null
	# Stand on the closed bud top first (the old exploit), 2 s.
	if bud:
		var top := _ray_down(bud.global_position + Vector3(0, 8, 0), 12.0)
		if not top.is_empty():
			_place(top["position"] + Vector3(0, 0.3, 0))
			await _wait(2.0)
			r["page_count_on_closed_bud"] = int(get_node("/root/Game").call("page_count", "W2"))
			await _shot("C_on_closed_bud")
		_place(bud.global_position + Vector3(4, 3, 0))
	play.call("open_bud", "bee")
	await _wait(1.5)
	var pg := world.find_child("Page4", true, false) as Node3D
	r["page4_after_open"] = _v(pg.global_position) if pg else null
	if pg:
		var below := _ray_down(pg.global_position + Vector3(0, 0.2, 0), 30.0)
		r["page4_floor_gap"] = snappedf(pg.global_position.y - float(below["position"].y), 0.01) if not below.is_empty() else -1.0
	var a19 := world.find_child("A19", true, false) as Node3D
	if a19:
		var arr := []
		for c in a19.get_children():
			if c is Node3D:
				var below2 := _ray_down((c as Node3D).global_position + Vector3(0, 0.2, 0), 30.0)
				arr.append({"n": String(c.name), "pos": _v((c as Node3D).global_position), "gap": snappedf((c as Node3D).global_position.y - float(below2["position"].y), 0.01) if not below2.is_empty() else -1.0})
		r["a19_after_open"] = arr
	# Walk the player onto the page.
	if pg:
		var pc0 := int(get_node("/root/Game").call("page_count", "W2"))
		_place(pg.global_position + Vector3(0, 0.2, 0))
		await _wait(1.5)
		r["page_collected_by_touch"] = int(get_node("/root/Game").call("page_count", "W2")) > pc0
	await _shot("C_bud_opened")
	report["C_bud"] = r


func _phase_d() -> void:
	var life: Node = world.get("life")
	var d: Node = life.get_node_or_null("W2Descent") if life else null
	var r := {}
	if d == null:
		report["D_descent"] = {"error": "no W2Descent"}
		return
	var gcam := get_viewport().get_camera_3d()
	r["gameplay_cam"] = String(gcam.name) if gcam else ""
	var dm0 := damage_log.size()
	var tb := truffle_log.size()
	d.call("start")
	await _wait(0.5)
	r["running"] = d.get("running")
	r["player_layer_during"] = player.collision_layer
	await _wait(1.6)
	await _shot("D_descent_2s")
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("jump")
	var tr := []
	for i in 60:
		await get_tree().physics_frame
		tr.append([snappedf(player.global_position.y, 0.01), snappedf(player.velocity.y, 0.01), String(player.get("state")) if player.get("state") != null else ""])
	r["skip_trace_first_60_frames"] = tr.slice(0, 12)
	r["max_vy_after_skip"] = tr.reduce(func(m, e): return maxf(m, float(e[1])), -99.0)
	r["running_after_skip"] = d.get("running")
	r["end_pos"] = _v(player.global_position)
	var dm := world.get_node("Spawns/Default") as Node3D
	r["dist_to_default"] = snappedf(player.global_position.distance_to(dm.global_position), 0.01)
	await _wait(2.0)
	r["on_floor_2s"] = player.is_on_floor()
	r["physics_on"] = player.is_physics_processing()
	r["layer_after"] = player.collision_layer
	var cam_now := get_viewport().get_camera_3d()
	r["cam_after"] = String(cam_now.name) if cam_now else ""
	r["cam_restored"] = cam_now == gcam
	r["damage_during"] = damage_log.size() - dm0
	r["truffles_during"] = truffle_log.size() - tb
	await _shot("D_descent_landed")
	# Full unskipped descent: trace pickups/damage and landing.
	_place(Vector3(-18, 70, -24))
	await _wait(1.0)
	var dm1 := damage_log.size()
	var ac0 := int(get_node("/root/Game").get("acorns"))
	d.call("start")
	await _wait(13.0)
	r["full_running_after_13s"] = d.get("running")
	r["full_end_pos"] = _v(player.global_position)
	r["full_damage"] = damage_log.size() - dm1
	r["full_acorns_gained"] = int(get_node("/root/Game").get("acorns")) - ac0
	await _wait(1.5)
	r["full_on_floor"] = player.is_on_floor()
	report["D_descent"] = r


func _phase_e() -> void:
	var game := get_node("/root/Game")
	var r := {}
	r["save_path"] = game.call("save_path")
	r["had_W2_1"] = game.call("has_truffle", "W2-1")
	var tr: Node3D = null
	for n in world.find_children("*", "", true, false):
		if n.get("truffle_id") == "W2-1":
			tr = n as Node3D
			break
	if tr == null:
		report["E_save"] = {"error": "W2-1 truffle node not found"}
		return
	r["truffle_pos"] = _v(tr.global_position)
	r["truffle_visible"] = tr.is_visible_in_tree()
	var tb := truffle_log.size()
	_place(tr.global_position + Vector3(0, 0.1, 0))
	await _wait(5.0)
	r["collected_events"] = truffle_log.slice(tb)
	r["has_W2_1"] = game.call("has_truffle", "W2-1")
	r["save_exists"] = FileAccess.file_exists(String(game.call("save_path")))
	var f := FileAccess.open(String(game.call("save_path")), FileAccess.READ)
	if f:
		var js: Variant = JSON.parse_string(f.get_as_text())
		r["save_truffles"] = (js as Dictionary).get("truffles", {}).keys() if js is Dictionary else "parse fail"
	r["tree_paused_after_5s"] = get_tree().paused
	# Reload and check the ghost.
	_save()
	report["E_save"] = r
	get_tree().change_scene_to_file("res://scenes/worlds/w2/W2.tscn")
	await _wait(1.0)
	if not await _wait_world():
		r["reload"] = "timeout"
		return
	await _wait(3.0)
	for n in world.find_children("*", "", true, false):
		if n.get("truffle_id") == "W2-1":
			r["reload_is_ghost"] = n.get("is_ghost")
			break
	r["reload_acorns"] = game.get("acorns")
	r["reload_truffle_count"] = game.call("truffle_count")
	report["E_save"] = r


func _phase_f() -> void:
	var res := []
	var cps := world.find_child("Checkpoints", true, false)
	for nm in ["CP0", "CP1", "CP3", "CP5", "CP6", "CP7"]:
		var c := cps.find_child(nm, true, false) as Node3D if cps else null
		if c == null:
			continue
		player.call("respawn", c.global_transform)
		await _wait(2.5)
		_bucket.clear()
		_measuring = true
		await _wait(5.0)
		_measuring = false
		var arr := Array(_bucket)
		arr.sort()
		var n := arr.size()
		var total := 0.0
		var over := 0
		for dd in arr:
			total += dd
			if dd > 1.0 / 60.0 + 0.0005:
				over += 1
		res.append({"spot": nm, "frames": n, "mean_fps": snappedf(n / maxf(total, 0.001), 0.1), "p99_ms": snappedf(arr[int(n * 0.99) - 1] * 1000.0, 0.01) if n > 10 else 0.0, "max_ms": snappedf(arr[n - 1] * 1000.0, 0.01) if n > 0 else 0.0, "over_16_7": over, "draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), "prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)})
		await _shot("F_" + nm)
	report["F_fps"] = res
	report["window"] = [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]

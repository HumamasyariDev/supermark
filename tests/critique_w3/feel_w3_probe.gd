extends Node
## Critique W3 round 1, GAME FEEL / MOVEMENT / CAMERA lens. Lives under /root while W3 is the current scene.
## It never edits world files: it teleports Mak, drives the real controller through MakInput's replay layer with a
## naive "hold the stick at the target" model (what a first-time player does), and samples the gameplay camera
## (spring-arm distance, camera inside solid geometry, line of sight to Mak) with native viewport screenshots.
## Output: <feel-out>/feel_w3_probe.json plus PNGs. Phases: --feel-phases=a,b,c (default all).

const CHEST := Vector3(0, 0.75, 0)

var out_dir := ""
var world: Node3D
var level: Node3D
var player: CharacterBody3D
var inp: Object
var stick := Vector2.ZERO
var drive := true
var report := {}
var damage_log: Array = []
var last_jump := ""
var jump_log: Array = []
var phase := ""
var shot_i := 0
var tag := "all"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	var dev := get_node_or_null("/root/Dev")
	out_dir = String(dev.call("arg", "feel-out", OS.get_user_data_dir().path_join("w3_feel"))) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	if dev:
		tag = String(dev.call("arg", "feel-tag", "all"))
	_run.call_deferred()


func _physics_process(_d: float) -> void:
	if inp and drive:
		inp.set("_r_stick", stick)


func log_line(s: String) -> void:
	print("[W3FEEL] " + s)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and String(cs.get("world_id")) == "W3" and get_tree().get_first_node_in_group("player") != null and cs.get_node_or_null("Level") != null:
			world = cs as Node3D
			level = cs.get_node("Level") as Node3D
			player = get_tree().get_first_node_in_group("player") as CharacterBody3D
			break
		if Time.get_ticks_msec() - t0 > 240000:
			log_line("TIMEOUT waiting for W3")
			get_tree().quit(2)
			return
	report["load_ms"] = Time.get_ticks_msec() - t0
	var game := get_node_or_null("/root/Game")
	if game:
		game.damaged.connect(func(a: int) -> void: damage_log.append({"amount": a, "pos": _v(player.global_position), "phase": phase, "t": Time.get_ticks_msec()}))
	player.connect("jumped", func(k: String) -> void:
		last_jump = k
		jump_log.append(k))
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1600, 900)
	await _wait(3.0)
	inp = player.get("inp")
	if inp:
		inp.call("setup", {"steer": "world", "events": []}, 0.2, 1.0)
	await _wait(0.5)
	var phases := ["audit", "jelly", "jelly2", "liftpole2", "candles2", "bouncer", "liftpole", "candles", "pillars", "gumdrops", "river", "camera", "slide"]
	var only := String(get_node("/root/Dev").call("arg", "feel-phases", "")) if get_node_or_null("/root/Dev") else ""
	for ph in phases:
		if only != "" and not (ph in only.split(",")):
			continue
		phase = ph
		log_line("phase " + ph)
		var r: Variant = await Callable(self, "_ph_" + ph).call()
		report[ph] = r
		_write()
	report["damage_log"] = damage_log
	_write()
	log_line("report written " + out_dir.path_join("feel_w3_probe_%s.json" % tag))
	get_tree().quit()


func _write() -> void:
	var f := FileAccess.open(out_dir.path_join("feel_w3_probe_%s.json" % tag), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()


# ------------------------------------------------------------------ helpers

func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _space() -> PhysicsDirectSpaceState3D:
	return world.get_world_3d().direct_space_state


func _st() -> String:
	return String(player.call("get_state_name"))


func _grounded() -> bool:
	return bool(player.get("grounded"))


func _press(action: String, frames: int) -> void:
	var hf: Dictionary = inp.get("_hold_frames")
	hf[action] = frames


func _tp(pos: Vector3, yaw_deg: float, settle := 30) -> void:
	stick = Vector2.ZERO
	player.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))
	await _frames(settle)


func _toward(t: Vector3, dead := 0.35) -> Vector2:
	var p := player.global_position
	var d := Vector2(t.x - p.x, t.z - p.z)
	if d.length() < dead:
		return Vector2.ZERO
	return Vector2(d.x, -d.y).normalized()


func _hdist(t: Vector3) -> float:
	var p := player.global_position
	return Vector2(t.x - p.x, t.z - p.z).length()


func _ground_name() -> String:
	var p := player.global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.3, 0), p - Vector3(0, 1.5, 0), 1 | 4)
	q.exclude = [player.get_rid()]
	var h := _space().intersect_ray(q)
	if h.is_empty():
		return "none"
	return String((h["collider"] as Node).name)


## Run toward `t` until within `dist` (horizontal). Returns false on timeout.
func _goto(t: Vector3, dist := 0.4, max_s := 8.0) -> bool:
	var n := int(max_s * 60.0)
	for i in n:
		if _hdist(t) <= dist:
			return true
		stick = _toward(t, 0.0)
		await _frames(1)
	return false


## One naive jump at `t` (top-centre of the target): press jump, hold the stick at the target centre in the air,
## climb if a ledge is grabbed. Returns the outcome.
func _jump_at(t: Vector3, hold := 14, label := "") -> Dictionary:
	last_jump = ""
	var dmg0 := damage_log.size()
	var p0 := player.global_position
	stick = _toward(t)
	_press("jump", hold)
	var f := 0
	var grabbed := false
	var max_y := p0.y
	while f < 300:
		await _frames(1)
		f += 1
		stick = _toward(t)
		max_y = maxf(max_y, player.global_position.y)
		var st := _st()
		if st == "ledge_hang" and not grabbed:
			grabbed = true
			await _frames(4)
			_press("jump", 8)
		if f > 6 and _grounded():
			break
		if player.global_position.y < t.y - 4.0:
			break
	stick = Vector2.ZERO
	var p := player.global_position
	var ok := absf(p.y - t.y) < 0.45 and _hdist(t) < 2.2
	var r := {"label": label, "kind": last_jump, "from": _v(p0), "target": _v(t), "landed": _v(p), "on": _ground_name(), "ok": ok,
		"ledge_grab": grabbed, "apex_rel": snappedf(max_y - p0.y, 0.01), "frames": f, "damage": damage_log.size() - dmg0, "state": _st()}
	log_line("jump %s -> %s" % [label, JSON.stringify(r)])
	return r


## A sequence of naive jumps. `wait_s` = how long the player stands after each landing before the next press
## (0 = presses on the landing frame, which chains single -> double -> triple).
func _seq(name_: String, start: Vector3, yaw: float, targets: Array, wait_s: float, jump_at_dist := 2.0) -> Dictionary:
	await _tp(start, yaw)
	var res := {"name": name_, "wait_s": wait_s, "jumps": []}
	var t0 := Time.get_ticks_msec()
	var ok_all := true
	for i in targets.size():
		var t: Vector3 = targets[i]
		if i == 0:
			var reached := await _goto(t, jump_at_dist, 6.0)
			if not reached:
				res["error"] = "never reached the first take-off point"
				ok_all = false
				break
		else:
			if wait_s > 0.0:
				stick = Vector2.ZERO
				await _wait(wait_s)
		var j := await _jump_at(t, 14, "%s#%d" % [name_, i + 1])
		(res["jumps"] as Array).append(j)
		if not bool(j["ok"]):
			ok_all = false
			break
	res["ok"] = ok_all
	res["ms"] = Time.get_ticks_msec() - t0
	log_line("seq %s ok=%s" % [name_, ok_all])
	return res


func _rig() -> Node3D:
	return player.get_node_or_null("MakCamera") as Node3D


## Camera sample: spring-arm distance, camera inside solid geometry, line of sight from camera to Mak's chest.
func _cam(label: String, shot := false) -> Dictionary:
	var vc := get_viewport().get_camera_3d()
	var rig := _rig()
	var cp := vc.global_position
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = cp
	pq.collision_mask = 1 | 4
	pq.collide_with_areas = false
	var inside: Array = []
	for h in _space().intersect_point(pq, 4):
		inside.append(String((h["collider"] as Node).name))
	var chest := player.global_position + CHEST
	var rq := PhysicsRayQueryParameters3D.create(cp, chest, 1 | 4)
	rq.exclude = [player.get_rid()]
	var hit := _space().intersect_ray(rq)
	var occ := "" if hit.is_empty() else String((hit["collider"] as Node).name)
	var r := {"label": label, "cam_is_rig": rig != null and vc == rig.get_node_or_null("Camera3D"), "cam_pos": _v(cp), "mak": _v(player.global_position),
		"cam_to_mak_m": snappedf(cp.distance_to(chest), 0.01), "inside": inside, "occluder": occ, "state": _st()}
	if rig:
		r["arm_m"] = snappedf(float(rig.get("_cur_dist")), 0.01)
		r["arm_want_m"] = snappedf(float(rig.get("_cur_target_dist")), 0.01)
	if shot:
		r["png"] = await _shot(label)
	return r


func _shot(label: String) -> String:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	shot_i += 1
	var utc := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var fn := "%sZ__feel_%02d_%s.png" % [utc, shot_i, label.replace(" ", "_").replace("/", "-")]
	img.save_png(out_dir.path_join(fn))
	return fn


func _candle(i: int) -> Node:
	return level.find_child("birthday_candle_%d" % i, true, false)


# ------------------------------------------------------------------ phases

func _ph_audit() -> Dictionary:
	var r := {}
	var names := ["jelly_step_1", "jelly_step_2", "marshmallow_bouncer", "ChocLift", "CandyPoleD", "birthday_candle_1", "birthday_candle_2",
		"birthday_candle_3", "CherryCap", "GlaceCherry", "peppermint_pillar", "rock_candy_pillar_1", "rock_candy_pillar_2", "rock_candy_pillar_3",
		"rock_candy_pillar_4", "kitchen_oven", "WaferBridge", "ravine_spire", "biscuit_balcony", "BalconyBreeze", "KitchenCam"]
	var found := {}
	for n in names:
		var nd := level.find_child(n, true, false) as Node3D
		found[n] = _v(nd.global_position) if nd else "MISSING"
	r["nodes"] = found
	var cps := {}
	var cpg := level.get_node_or_null("Checkpoints")
	if cpg:
		for c in cpg.get_children():
			cps[String(c.name)] = _v((c as Node3D).global_position)
	r["checkpoints"] = cps
	var ledge := []
	for n in ["kitchen_oven", "kitchen_pantry_W", "kitchen_pantry_E", "ravine_spire", "crow_nest_trunk", "crow_nest"]:
		var nd := level.find_child(n, true, false)
		ledge.append({"id": n, "exists": nd != null, "no_ledge_grab": nd != null and (nd.is_in_group("no_ledge_grab") or bool(nd.get_meta("no_ledge_grab", false)))})
	r["ledge_optout"] = ledge
	var cz := []
	for a in get_tree().get_nodes_in_group("camera_zone"):
		cz.append(String((a as Node).get_path()))
	r["camera_zones"] = cz
	var wz := []
	for a in get_tree().get_nodes_in_group("wind_zone"):
		wz.append(String((a as Node).name))
	r["wind_zones"] = wz
	var fog := level.find_children("*", "FogVolume", true, false)
	r["fog_volumes"] = fog.size()
	r["camera_exclude_members"] = get_tree().get_nodes_in_group("camera_exclude").size()
	var rig := _rig()
	if rig:
		r["rig"] = {"distance": rig.get("distance"), "min_distance": rig.get("min_distance"), "pitch": rig.get("default_pitch_deg")}
	log_line("audit " + JSON.stringify(r))
	return r


func _ph_jelly() -> Dictionary:
	var start := Vector3(23.9, 8.25, -24.0)
	var t := [Vector3(27.11, 9.0, -22.26), Vector3(30.34, 10.0, -25.24), Vector3(33.6, 12.0, -28.2)]
	var out := {}
	out["rhythm"] = await _seq("jelly_rhythm", start, -90.0, t, 0.0, 2.1)
	out["careful_0.4s"] = await _seq("jelly_careful", start, -90.0, t, 0.4, 2.1)
	out["slow_0.9s"] = await _seq("jelly_slow", start, -90.0, t, 0.9, 2.1)
	return out


func _ph_bouncer() -> Dictionary:
	var out := {}
	out["naive"] = await _seq("bouncer", Vector3(50.0, 12.1, -30.5), -135.0, [Vector3(53.5, 12.8, -33.0), Vector3(51.0, 16.0, -36.5)], 0.0, 2.2)
	await _tp(Vector3(50.0, 12.1, -30.5), -135.0)
	out["cam_on_bouncer_approach"] = await _cam("tierA_bouncer_view", true)
	return out


func _ph_liftpole() -> Dictionary:
	var out := {}
	var lift := level.find_child("ChocLift", true, false) as Node3D
	await _tp(Vector3(48.6, 16.1, -40.6), -90.0)
	var t0 := Time.get_ticks_msec()
	# Wait for the lift at the bottom, then walk on.
	var w := 0
	while lift and lift.global_position.y > 16.2 and w < 600:
		await _frames(1)
		w += 1
	out["lift_wait_s"] = snappedf(w / 60.0, 0.01)
	await _goto(Vector3(51.0, 16.3, -41.0), 0.35, 4.0)
	stick = Vector2.ZERO
	var rise := 0
	while lift and lift.global_position.y < 20.1 and rise < 600:
		await _frames(1)
		rise += 1
	out["lift_rise_s"] = snappedf(rise / 60.0, 0.01)
	out["on_lift_top"] = _v(player.global_position)
	out["cam_lift_top"] = await _cam("lift_top_facing_west", true)
	await _goto(Vector3(48.4, 20.0, -42.0), 0.35, 4.0)
	stick = Vector2.ZERO
	await _frames(20)
	out["on_tier_C"] = _v(player.global_position)
	out["cam_tierC_pole"] = await _cam("tierC_pole_and_tierD", true)
	# Natural approach: the lift is east of the pole, so the player jumps into the pole from the east.
	var pole := Vector3(46.6, 20.0, -42.0)
	stick = _toward(pole)
	_press("jump", 10)
	var f := 0
	while f < 90 and _st() != "pole_climb":
		await _frames(1)
		stick = _toward(pole, 0.0)
		f += 1
	out["grabbed_pole"] = _st() == "pole_climb"
	out["pole_side_x"] = snappedf(player.global_position.x - 46.6, 0.01)
	stick = Vector2(0, 1)
	await _wait(1.4)
	out["climb_top"] = _v(player.global_position)
	out["cam_on_pole"] = await _cam("on_pole_top_from_east", true)
	# A first-time player pushes toward tier D (west) and presses jump.
	stick = Vector2(-1, 0)
	_press("jump", 14)
	await _frames(8)
	var f2 := 0
	while f2 < 200 and not (_grounded() and f2 > 6):
		await _frames(1)
		f2 += 1
	out["naive_pole_jump_landed"] = _v(player.global_position)
	out["naive_pole_jump_on"] = _ground_name()
	out["naive_pole_jump_ok"] = absf(player.global_position.y - 24.0) < 0.5
	out["route_time_ms"] = Time.get_ticks_msec() - t0
	# Informed player: grab, climb, orbit to the west side, then jump.
	await _tp(Vector3(48.4, 20.05, -42.0), 90.0)
	stick = _toward(pole)
	_press("jump", 10)
	f = 0
	while f < 90 and _st() != "pole_climb":
		await _frames(1)
		stick = _toward(pole, 0.0)
		f += 1
	stick = Vector2(0, 1)
	await _wait(1.2)
	var orbit_f := 0
	while orbit_f < 240 and player.global_position.x > 46.3:
		stick = Vector2(1, 0)
		await _frames(1)
		orbit_f += 1
	out["orbit_s_to_west_side"] = snappedf(orbit_f / 60.0, 0.01)
	stick = Vector2(-1, 0)
	_press("jump", 14)
	await _frames(8)
	f2 = 0
	while f2 < 200 and not (_grounded() and f2 > 6):
		await _frames(1)
		f2 += 1
	out["informed_pole_jump_landed"] = _v(player.global_position)
	out["informed_pole_jump_on"] = _ground_name()
	out["informed_facing_after"] = snappedf(rad_to_deg(float(player.get("facing_yaw"))), 0.1)
	out["cam_after_pole_jump"] = await _cam("tierD_after_pole_jump", true)
	log_line("liftpole " + JSON.stringify(out))
	return out


func _ph_candles() -> Dictionary:
	var out := {}
	var tops := [Vector3(43.3, 25.2, -44.0), Vector3(43.4, 26.4, -41.5), Vector3(42.9, 27.6, -39.2), Vector3(39.6, 28.0, -41.0)]
	# (a) a watcher: waits on each perch until the next candle has just gone out.
	await _tp(Vector3(41.4, 24.1, -45.2), -60.0)
	out["cam_wave_view"] = await _cam("tierD_candle_wave", true)
	var dmg0 := damage_log.size()
	var t0 := Time.get_ticks_msec()
	var jumps: Array = []
	for i in 4:
		if i < 3:
			var c := _candle(i + 1)
			var w := 0
			# wait for "lit" then "out" (a fresh out window)
			while c and not bool(c.get("_lit")) and w < 400:
				await _frames(1)
				w += 1
			while c and bool(c.get("_lit")) and w < 800:
				await _frames(1)
				w += 1
		var j := await _jump_at(tops[i], 14, "candle_watch#%d" % (i + 1))
		jumps.append(j)
		if not bool(j["ok"]):
			break
	out["watcher"] = {"jumps": jumps, "damage": damage_log.size() - dmg0, "ms": Time.get_ticks_msec() - t0}
	# (b) a hurried player: hops straight up the wave with 0.15 s pauses, no timing.
	await _tp(Vector3(41.4, 24.1, -45.2), -60.0)
	dmg0 = damage_log.size()
	var j2: Array = []
	for i in 4:
		await _wait(0.15)
		var j := await _jump_at(tops[i], 14, "candle_hurry#%d" % (i + 1))
		j2.append(j)
		if not bool(j["ok"]):
			break
	out["hurried"] = {"jumps": j2, "damage": damage_log.size() - dmg0}
	# (c) summit: cherry cap by a standing double / side somersault (J82) is not tested; sample the summit camera.
	await _tp(Vector3(39.4, 28.1, -40.4), 180.0)
	out["cam_summit"] = await _cam("summit_slide_gate", true)
	log_line("candles " + JSON.stringify(out))
	return out


func _ph_pillars() -> Dictionary:
	var start := Vector3(-16.6, 8.1, -35.8)
	var t := [Vector3(-21.6, 9.6, -36.0), Vector3(-26.2, 11.2, -37.4), Vector3(-30.8, 12.8, -38.2), Vector3(-35.4, 14.4, -37.6), Vector3(-36.6, 16.0, -43.2)]
	var out := {}
	await _tp(start, 90.0)
	out["cam_start"] = await _cam("knoll_pillars_view", true)
	out["rhythm"] = await _seq("pillars_rhythm", start, 90.0, t, 0.0, 3.4)
	out["careful_0.3s"] = await _seq("pillars_careful", start, 90.0, t, 0.3, 3.4)
	return out


func _ph_gumdrops() -> Dictionary:
	var out := {}
	var tops: Array = []
	for i in range(1, 8):
		tops.append(level.call("_gum", i))
	tops.append(Vector3(20, 24.4, 38))
	out["tops"] = tops.map(func(v: Vector3) -> Array: return _v(v))
	await _tp(Vector3(9.4, 2.1, 38.0), -90.0)
	out["cam_lawn"] = await _cam("lawn_gumdrop_spiral", true)
	await _goto(Vector3(11.0, 2.0, 38.0), 0.3, 3.0)
	var jumps: Array = []
	var j0 := await _jump_at(tops[0], 16, "gum#1")
	jumps.append(j0)
	# Bounce chain: a competent human holds the stick at the next dome; slams over grumpy domes 5-7.
	var cur := 0
	var f := 0
	var dmg0 := damage_log.size()
	if bool(j0["ok"]) or player.global_position.y > 3.0:
		while f < 60 * 20 and cur < tops.size() - 1:
			await _frames(1)
			f += 1
			var tgt: Vector3 = tops[cur + 1]
			stick = _toward(tgt)
			var p := player.global_position
			var vy := float(player.get("vy"))
			var grumpy := cur + 1 >= 4 and cur + 1 <= 6
			if grumpy and vy < 0.0 and _hdist(tgt) < 0.9 and p.y > tgt.y + 1.0 and _st() != "ham_slam":
				_press("crouch", 4)
			if p.y > tgt.y - 0.6 and _hdist(tgt) < 1.6 and (vy > 6.0 or _grounded()):
				jumps.append({"reached": cur + 2, "at": _v(p), "frame": f})
				cur += 1
			if p.y < 2.6 and f > 30:
				jumps.append({"fell_after": cur + 1, "at": _v(p), "frame": f})
				break
	stick = Vector2.ZERO
	out["chain"] = jumps
	out["reached_index"] = cur + 1
	out["damage"] = damage_log.size() - dmg0
	log_line("gumdrops " + JSON.stringify(out))
	return out


func _ph_river() -> Dictionary:
	var out := {}
	for case_ in [["mid_river_hold_to_south_bank", Vector3(49.0, 1.2, 19.0), Vector2(0, -1)], ["mid_river_no_input", Vector3(49.0, 1.2, 19.0), Vector2.ZERO],
			["lagoon_hold_south", Vector3(20.0, 1.2, 15.0), Vector2(0, -1)]]:
		await _tp(case_[1], 180.0, 2)
		var dmg0 := damage_log.size()
		var h0 := int(get_node("/root/Game").get("health"))
		var f := 0
		var out_at := -1
		while f < 60 * 7:
			stick = case_[2]
			await _frames(1)
			f += 1
			var p := player.global_position
			if out_at < 0 and _grounded() and float(level.call("h_at", p.x, p.z)) > 0.45 and p.y > 0.4:
				out_at = f
		stick = Vector2.ZERO
		out[case_[0]] = {"damage_events": damage_log.size() - dmg0, "health_before": h0, "health_after": int(get_node("/root/Game").get("health")),
			"seconds_to_bank": snappedf(out_at / 60.0, 0.01) if out_at > 0 else -1, "end": _v(player.global_position)}
		get_node("/root/Game").call("heal", 6)
		await _frames(100)
	log_line("river " + JSON.stringify(out))
	return out


func _ph_camera() -> Dictionary:
	var out := {}
	var spots := [
		["maze_entrance_north", Vector3(-36.0, 4.1, 24.6), 0.0],
		["maze_cell_3_2_west", Vector3(-43.2, 4.1, 18.0), 90.0],
		["maze_cell_1_1_north", Vector3(-52.0, 4.1, 14.6), 0.0],
		["kitchen_hearth", Vector3(-2.4, 100.3, -29.0), 90.0],
		["kitchen_flour_mark", Vector3(-6.0, 100.1, -29.9), 180.0],
		["kitchen_oven_top", Vector3(-6.4, 103.5, -32.6), 0.0],
		["cottage_ridge_east", Vector3(-8.0, 18.1, -29.0), -90.0],
		["chimney_top", Vector3(-2.4, 20.1, -29.0), 180.0],
		["grotto_inside_north", Vector3(-44.0, 5.1, -39.4), 0.0],
		["pool_rock2_to_grotto", Vector3(-43.0, 2.9, -35.0), 0.0],
		["tierA_ring_face_south_near_B", Vector3(45.0, 12.1, -29.6), 180.0],
		["MA2_chimney_face_B_wall", Vector3(40.0, 12.1, -29.3), 0.0],
		["wafer_bridge_east", Vector3(14.0, 8.3, -24.0), -90.0],
		["page2_shelf_under_bridge", Vector3(-2.9, 0.95, 1.4), 0.0],
		["ravine_slabs_view", Vector3(15.0, 8.3, -24.6), 0.0],
		["balcony_runway_east", Vector3(57.0, 2.1, 34.5), -90.0],
		["fort_walkway_north", Vector3(46.0, 5.7, 37.0), -90.0],
		["islet_to_laneE", Vector3(23.4, 1.7, 7.0), -70.0],
	]
	var samples: Array = []
	for s in spots:
		await _tp(s[1], s[2], 60)
		samples.append(await _cam(s[0], true))
	out["spots"] = samples
	# Walk the maze solution and track the spring arm.
	var cells := [Vector3(-36, 4, 22), Vector3(-36, 4, 18), Vector3(-40, 4, 18), Vector3(-44, 4, 18), Vector3(-44, 4, 14), Vector3(-48, 4, 14),
		Vector3(-52, 4, 14), Vector3(-52, 4, 10), Vector3(-48, 4, 10), Vector3(-48, 4, 7.5)]
	await _tp(Vector3(-36.0, 4.1, 25.0), 0.0, 40)
	var arm: Array = []
	var min_arm := 99.0
	var occluded := 0
	var inside := 0
	var n := 0
	for c in cells:
		var f := 0
		while _hdist(c) > 0.5 and f < 360:
			stick = _toward(c, 0.0)
			await _frames(1)
			f += 1
			if f % 6 == 0:
				var cs := await _cam("maze_walk")
				n += 1
				min_arm = minf(min_arm, float(cs.get("arm_m", 99.0)))
				if String(cs["occluder"]) != "":
					occluded += 1
				if (cs["inside"] as Array).size() > 0:
					inside += 1
				arm.append(cs.get("arm_m", -1))
		if c == cells[3] or c == cells[6]:
			samples.append(await _cam("maze_walk_corner_%d" % cells.find(c), true))
	stick = Vector2.ZERO
	out["maze_walk"] = {"samples": n, "min_arm_m": min_arm, "occluded_samples": occluded, "inside_samples": inside, "arm_series": arm}
	log_line("camera maze walk " + JSON.stringify(out["maze_walk"]))
	return out


func _ph_slide() -> Dictionary:
	var out := {}
	var plans: Dictionary = level.call("_bot_plans")
	var bot := Node.new()
	bot.set_script(load("res://scripts/worlds/w3_bot.gd"))
	level.add_child(bot)
	bot.call("setup", "feel_w34", plans["w34"], 40.0)
	drive = false
	var series: Array = []
	var shots: Array = []
	var f := 0
	var max_err := 0.0
	var sum_err := 0.0
	var cnt := 0
	while f < 60 * 22:
		await _frames(1)
		f += 1
		var v: Vector3 = player.velocity
		var hv := Vector2(v.x, v.z)
		if f % 10 == 0 and hv.length() > 4.0:
			var vc := get_viewport().get_camera_3d()
			var fwd := -vc.global_basis.z
			var a := rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(hv))
			max_err = maxf(max_err, absf(a))
			sum_err += absf(a)
			cnt += 1
			var cs := await _cam("slide")
			series.append({"f": f, "p": _v(player.global_position), "speed": snappedf(hv.length(), 0.1), "cam_vs_vel_deg": snappedf(a, 0.1),
				"arm": cs.get("arm_m", -1), "occ": cs["occluder"], "state": _st()})
		if f in [150, 260, 360, 470, 600]:
			shots.append(await _cam("slide_f%d" % f, true))
		if bool(bot.get("_done")):
			break
	drive = true
	out["series"] = series
	out["shots"] = shots
	out["cam_vs_velocity_max_deg"] = snappedf(max_err, 0.1)
	out["cam_vs_velocity_mean_deg"] = snappedf(sum_err / maxf(cnt, 1), 0.1)
	bot.queue_free()
	log_line("slide max cam err %.1f mean %.1f" % [max_err, sum_err / maxf(cnt, 1)])
	return out


func _ph_jelly2() -> Dictionary:
	var out := {}
	# (a) skilled: land on jelly 1, stop, turn to face jelly 2 (a short stick tap), then a running single, then
	# immediately chain a double onto tier A (the designer's "jump, jump, double").
	await _tp(Vector3(23.9, 8.25, -24.0), -90.0)
	await _goto(Vector3(27.11, 9.0, -22.26), 2.1, 6.0)
	var j1 := await _jump_at(Vector3(27.11, 9.0, -22.26), 14, "jelly_skilled#1")
	var t2 := Vector3(30.34, 10.0, -25.24)
	# brake and turn on the cube (a human releases the stick, then nudges toward the next cube)
	stick = Vector2.ZERO
	await _frames(8)
	stick = _toward(t2, 0.0) * 0.3
	await _frames(8)
	var j2 := await _jump_at(t2, 14, "jelly_skilled#2")
	var j3 := {}
	if bool(j2["ok"]):
		j3 = await _jump_at(Vector3(33.6, 12.0, -28.2), 14, "jelly_skilled#3")
	out["skilled"] = {"j1": j1, "j2": j2, "j3": j3, "on_jelly1_after_brake": true}
	# (b) bypass: a running double jump straight at tier A's 4 m wall from T1 (no jellies) + ledge grab.
	await _tp(Vector3(28.0, 8.1, -20.0), 135.0)
	var wall := Vector3(34.0, 12.0, -27.0)
	var f := 0
	while f < 90:
		stick = _toward(wall, 0.0)
		await _frames(1)
		f += 1
	var a := await _jump_at(wall, 14, "tierA_bypass#1")
	var b := await _jump_at(wall, 14, "tierA_bypass#2")
	out["bypass_running_double"] = {"first": a, "second": b, "end": _v(player.global_position)}
	log_line("jelly2 " + JSON.stringify(out))
	return out


func _ph_liftpole2() -> Dictionary:
	var out := {}
	var lift := level.find_child("ChocLift", true, false) as Node3D
	# (1) the called lift: walk onto it from tier B, then stand still for 5 s and log its height.
	await _tp(Vector3(48.8, 16.1, -41.0), -90.0)
	out["lift_y_start"] = snappedf(lift.global_position.y, 0.01) if lift else -1.0
	out["lift_busy_meta"] = bool(lift.get_meta("busy", false)) if lift else false
	await _goto(Vector3(51.0, 16.3, -41.0), 0.3, 4.0)
	stick = Vector2.ZERO
	var ys: Array = []
	for i in 10:
		await _wait(0.5)
		ys.append([snappedf(lift.global_position.y, 0.01), snappedf(player.global_position.y, 0.01)])
	out["walk_on_lift_y_series"] = ys
	# (2) jump onto it from tier B (landing from the air).
	await _tp(Vector3(48.8, 16.1, -41.0), -90.0)
	var jl := await _jump_at(Vector3(51.0, 16.3, -41.0), 10, "lift_hop")
	var ys2: Array = []
	for i in 8:
		await _wait(0.5)
		ys2.append([snappedf(lift.global_position.y, 0.01), snappedf(player.global_position.y, 0.01)])
	out["hop_on_lift"] = jl
	out["hop_on_lift_y_series"] = ys2
	# (3) pole: arrive from the east (the lift side) and jump into the pole, as a player coming off the lift does.
	var pole := Vector3(46.6, 20.0, -42.0)
	for variant in ["naive_push_west", "orbit_exact_west"]:
		await _tp(Vector3(48.9, 20.1, -42.0), 90.0)
		stick = _toward(pole)
		_press("jump", 10)
		var f := 0
		while f < 90 and _st() != "pole_climb":
			await _frames(1)
			stick = _toward(pole, 0.0)
			f += 1
		var r := {"grabbed": _st() == "pole_climb", "grab_offset": _v(player.global_position - Vector3(46.6, player.global_position.y, -42.0))}
		stick = Vector2(0, 1)
		await _wait(1.3)
		r["feet_y_at_top"] = snappedf(player.global_position.y, 0.01)
		if variant == "orbit_exact_west":
			var of := 0
			while of < 300:
				var off := player.global_position - Vector3(46.6, 0, -42.0)
				var ang := rad_to_deg(atan2(off.z, off.x))
				if absf(absf(ang) - 180.0) < 6.0:
					break
				stick = Vector2(0.5, 0)
				await _frames(1)
				of += 1
			r["orbit_s"] = snappedf(of / 60.0, 0.01)
			stick = Vector2.ZERO
			await _frames(2)
		r["cam"] = await _cam("pole_%s" % variant, true)
		stick = Vector2(-1, 0)
		_press("jump", 14)
		await _frames(8)
		var f2 := 0
		while f2 < 200 and not (_grounded() and f2 > 6):
			await _frames(1)
			f2 += 1
		stick = Vector2.ZERO
		r["landed"] = _v(player.global_position)
		r["on"] = _ground_name()
		r["ok_tier_D"] = absf(player.global_position.y - 24.0) < 0.5
		out[variant] = r
	log_line("liftpole2 " + JSON.stringify(out))
	return out


func _ph_candles2() -> Dictionary:
	# Watcher with a competent stop: after each landing the stick is released at once; logs how far from the
	# candle centre Mak stops (top radius 0.7) and whether he stays on it while waiting for the next out window.
	var tops := [Vector3(43.3, 25.2, -44.0), Vector3(43.4, 26.4, -41.5), Vector3(42.9, 27.6, -39.2), Vector3(39.6, 28.0, -41.0)]
	var out := {"runs": []}
	for run in 3:
		await _tp(Vector3(41.6, 24.1, -44.9), -70.0)
		var dmg0 := damage_log.size()
		var jumps: Array = []
		var okall := true
		for i in 4:
			if i < 3:
				var c := _candle(i + 1)
				var w := 0
				while c and not bool(c.get("_lit")) and w < 400:
					await _frames(1)
					w += 1
				while c and bool(c.get("_lit")) and w < 800:
					await _frames(1)
					w += 1
			var j := await _jump_at(tops[i], 12, "candle2_r%d#%d" % [run, i + 1])
			stick = Vector2.ZERO
			await _frames(20)
			j["after_settle"] = _v(player.global_position)
			j["off_centre_m"] = snappedf(_hdist(tops[i]), 0.01)
			j["still_on"] = absf(player.global_position.y - tops[i].y) < 0.3
			jumps.append(j)
			if not bool(j["still_on"]):
				okall = false
				break
		(out["runs"] as Array).append({"ok": okall, "damage": damage_log.size() - dmg0, "jumps": jumps})
	log_line("candles2 " + JSON.stringify(out))
	return out

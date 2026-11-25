extends "res://tests/critique_w3/feel_w3_probe.gd"
## Critique W3 round 1 (pass C, 2026-10-18 evening, after fix round 1), GAME FEEL / MOVEMENT / CAMERA lens.
## Reuses the pass-A probe helpers (naive "stick at the target" driver, camera sampler) and adds phases for the
## current geometry: moved jellies and candles, the auto-oriented pole jump, the kitchen backflip, the balcony long
## jump and breeze, the cherry cap, fall-out respawns and camera sampling during the W3 bot plans.
## Never edits the world. Output: <feel-out>/feel_w3_probe_<tag>.json plus PNGs.

var _falls: Array = []


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
	player.connect("state_changed", func(a: String, b: String) -> void:
		if b == "fallout" or a == "fallout":
			_falls.append({"from": a, "to": b, "pos": _v(player.global_position), "t": Time.get_ticks_msec(), "phase": phase}))
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1600, 900)
	await _wait(3.0)
	inp = player.get("inp")
	if inp:
		inp.call("setup", {"steer": "world", "events": []}, 0.2, 1.0)
	await _wait(0.5)
	var phases := _phase_list()
	var only := String(get_node("/root/Dev").call("arg", "feel-phases", "")) if get_node_or_null("/root/Dev") else ""
	for ph in phases:
		if only != "" and not (ph in only.split(",")):
			continue
		phase = ph
		log_line("phase " + ph)
		var r: Variant = await Callable(self, "_ph_" + ph).call()
		report[ph] = r
		_write()
		var g := get_node_or_null("/root/Game")
		if g and g.has_method("heal"):
			g.call("heal", 8)
	report["damage_log"] = damage_log
	report["fallout_log"] = _falls
	_write()
	log_line("report written " + out_dir.path_join("feel_w3_probe_%s.json" % tag))
	get_tree().quit()


func _phase_list() -> Array:
	return ["audit", "jelly3", "polecandle", "pillars", "gumdrops", "kitchen", "balcony", "cherry", "river", "camera", "fallouts", "bots"]


func _hy(x: float, z: float) -> float:
	return float(level.call("h_at", x, z))


func _land_wait(max_f := 300) -> int:
	var f := 0
	while f < max_f:
		await _frames(1)
		f += 1
		if f > 6 and _grounded():
			break
	return f


# ------------------------------------------------------------------ jelly beat (runtime positions)

func _ph_jelly3() -> Dictionary:
	var out := {}
	var start := Vector3(22.8, 8.25, -24.2)
	var t := [Vector3(26.3, 9.0, -25.0), Vector3(29.4, 10.5, -26.1), Vector3(32.6, 12.0, -28.6)]
	out["rhythm"] = await _seq("jelly3_rhythm", start, -90.0, t, 0.0, 2.2)
	out["careful_0.4s"] = await _seq("jelly3_careful", start, -90.0, t, 0.4, 2.2)
	out["slow_1.2s"] = await _seq("jelly3_slow", start, -90.0, t, 1.2, 2.2)
	await _tp(start, -100.0)
	out["cam_start"] = await _cam("jelly_beat_from_T1", true)
	return out


# ------------------------------------------------------------------ pole jump + candle wave

func _pole_from_lift(stick_dir: Vector2) -> Dictionary:
	var pole := Vector3(46.6, 20.0, -42.0)
	await _tp(Vector3(48.9, 20.1, -42.0), 90.0)
	var dmg0 := damage_log.size()
	stick = _toward(pole)
	_press("jump", 10)
	var f := 0
	while f < 90 and _st() != "pole_climb":
		await _frames(1)
		stick = _toward(pole, 0.0)
		f += 1
	var r := {"grabbed": _st() == "pole_climb"}
	stick = Vector2(0, 1)
	await _wait(1.6)
	r["feet_y_at_top"] = snappedf(player.global_position.y, 0.01)
	r["cam_on_pole"] = await _cam("pole_top_%s" % str(stick_dir), true)
	stick = stick_dir
	_press("jump", 14)
	await _frames(8)
	await _land_wait(200)
	stick = Vector2.ZERO
	await _frames(10)
	r["landed"] = _v(player.global_position)
	r["on"] = _ground_name()
	r["ok_tier_D"] = absf(player.global_position.y - 24.0) < 0.5
	r["damage"] = damage_log.size() - dmg0
	return r


func _wait_out(i: int) -> int:
	var c := _candle(i)
	var w := 0
	while c and not bool(c.get("_lit")) and w < 400:
		await _frames(1)
		w += 1
	while c and bool(c.get("_lit")) and w < 800:
		await _frames(1)
		w += 1
	return w


func _ph_polecandle() -> Dictionary:
	var out := {}
	out["pole_naive_west"] = await _pole_from_lift(Vector2(-1, 0))
	out["pole_no_stick"] = await _pole_from_lift(Vector2.ZERO)
	out["pole_stick_camera_forward"] = await _pole_from_lift(Vector2(0, -1))
	var c := []
	for i in range(1, 4):
		var nd := _candle(i) as Node3D
		c.append(_v(nd.global_position) if nd else "MISSING")
	out["candle_bases"] = c
	var tops := [Vector3(42.6, 25.2, -44.6), Vector3(42.9, 26.4, -39.5), Vector3(40.9, 27.6, -38.3), Vector3(39.4, 28.0, -40.4)]
	var land := Vector3(43.3, 24.05, -42.0)
	# (a) the wave in designed order from the landing biscuit, a watcher who waits for each fresh out window.
	var runs: Array = []
	for run in 2:
		await _tp(land, 180.0 if run == 0 else 0.0)
		var dmg0 := damage_log.size()
		var jumps: Array = []
		for i in 4:
			if i < 3:
				await _wait_out(i + 1)
			var j := await _jump_at(tops[i], 14, "wave_r%d#%d" % [run, i + 1])
			stick = Vector2.ZERO
			await _frames(12)
			j["still_on"] = absf(player.global_position.y - tops[i].y) < 0.3
			jumps.append(j)
			if not bool(j["still_on"]):
				break
		runs.append({"jumps": jumps, "damage": damage_log.size() - dmg0})
	out["wave_order_watcher"] = runs
	# (b) the skip: landing biscuit -> candle 2 directly (standing double), then 3, then the summit.
	await _tp(land, 0.0)
	var dmg1 := damage_log.size()
	await _wait_out(2)
	var s1 := await _jump_at(tops[1], 14, "skip#c2_single")
	var s2 := {}
	if not bool(s1["ok"]):
		await _tp(land, 0.0)
		await _wait_out(2)
		# first hop up and press again on landing = chained double from tier D floor
		s1 = await _jump_at(land + Vector3(0, 0, 0.6), 8, "skip#prehop")
		s2 = await _jump_at(tops[1], 14, "skip#c2_double")
	out["skip_to_candle2"] = {"single": s1, "double": s2, "damage": damage_log.size() - dmg1}
	# (c) gap check from candle 1 straight up: how far a standing single from c1 gets toward c2.
	await _tp(tops[0] + Vector3(0, 0.05, 0), 0.0)
	await _wait_out(2)
	out["c1_to_c2_from_centre"] = await _jump_at(tops[1], 14, "c1_to_c2")
	await _tp(Vector3(41.6, 24.1, -42.4), -90.0)
	out["cam_candles"] = await _cam("candle_zone_view", true)
	log_line("polecandle " + JSON.stringify(out))
	return out


# ------------------------------------------------------------------ kitchen backflip

func _oven_cold_start() -> void:
	var w := 0
	while w < 400 and not (String(level.get("_oven_state")) == "cold" and float(level.get("_oven_t")) < 0.2):
		await _frames(1)
		w += 1


func _backflip_from(pos: Vector3, label: String) -> Dictionary:
	await _tp(pos, 180.0, 20)
	await _oven_cold_start()
	var dmg0 := damage_log.size()
	stick = Vector2.ZERO
	_press("crouch", 26)
	await _frames(8)
	_press("jump", 14)
	var f := 0
	var maxy := player.global_position.y
	var kinds := ""
	await _frames(2)
	kinds = _st()
	while f < 200:
		await _frames(1)
		f += 1
		maxy = maxf(maxy, player.global_position.y)
		if f > 6 and _grounded():
			break
	await _frames(6)
	var r := {"label": label, "from": _v(pos), "state_after_press": kinds, "apex_feet": snappedf(maxy, 0.01), "landed": _v(player.global_position),
		"on": _ground_name(), "on_oven": player.global_position.y > 103.2, "damage": damage_log.size() - dmg0, "oven_state_at_land": String(level.get("_oven_state"))}
	log_line("backflip " + JSON.stringify(r))
	return r


func _ph_kitchen() -> Dictionary:
	var out := {}
	# Hearth arrival as the chimney drop leaves him (KitchenCam must be live).
	await _tp(Vector3(-2.4, 100.3, -29.0), 90.0, 60)
	out["cam_hearth"] = await _cam("kitchen_hearth", true)
	out["kitchen_cam_current"] = get_viewport().get_camera_3d().name
	# Backflip from the flour mark (designed), and off-mark positions a human might use.
	out["bf_mark_1.9m"] = await _backflip_from(Vector3(-6.0, 100.05, -29.9), "mark")
	out["cam_on_oven"] = await _cam("kitchen_after_backflip", true)
	out["bf_1.3m"] = await _backflip_from(Vector3(-6.0, 100.05, -30.5), "1.3m_from_face")
	out["bf_2.5m"] = await _backflip_from(Vector3(-6.0, 100.05, -29.3), "2.5m_from_face")
	out["bf_3.1m"] = await _backflip_from(Vector3(-6.0, 100.05, -28.7), "3.1m_from_face")
	out["bf_side_0.8"] = await _backflip_from(Vector3(-6.8, 100.05, -29.9), "mark_0.8m_west")
	# Negative: standing double jump at the face.
	await _tp(Vector3(-6.0, 100.05, -31.0), 0.0, 20)
	await _oven_cold_start()
	var a := await _jump_at(Vector3(-6.0, 103.4, -32.6), 10, "oven_double#1")
	var b := await _jump_at(Vector3(-6.0, 103.4, -32.6), 14, "oven_double#2")
	out["neg_double"] = {"a": a, "b": b, "on_oven": player.global_position.y > 103.2}
	# Exit: walk from the truffle spot through the door in a cold window; log damage.
	await _tp(Vector3(-8.6, 100.05, -27.6), 180.0, 20)
	await _oven_cold_start()
	var dmg0 := damage_log.size()
	var ok := await _goto(Vector3(-6.0, 100.0, -24.6), 0.3, 4.0)
	await _frames(30)
	out["exit_walk"] = {"reached_door": ok, "damage": damage_log.size() - dmg0, "end": _v(player.global_position)}
	log_line("kitchen " + JSON.stringify(out))
	return out


# ------------------------------------------------------------------ balcony long jump and breeze

func _long_jump_from(take_off_x: float, label: String) -> Dictionary:
	var z := 34.5
	await _tp(Vector3(47.0, 2.1, z), -90.0, 20)
	var f := 0
	var fired := false
	var p0 := Vector3.ZERO
	var spd := 0.0
	while f < 600:
		stick = Vector2(1, 0)
		await _frames(1)
		f += 1
		if not fired and player.global_position.x >= take_off_x:
			fired = true
			p0 = player.global_position
			spd = float(player.get("forward_speed"))
			_press("crouch", 10)
			_press("jump", 14)
		if fired and f > 10 and _grounded() and player.global_position.x > take_off_x + 1.0:
			break
		if player.global_position.y < -6.0:
			break
	stick = Vector2.ZERO
	await _frames(6)
	var p := player.global_position
	var r := {"label": label, "take_off": _v(p0), "speed": snappedf(spd, 0.01), "kind": last_jump, "landed": _v(p), "on": _ground_name(),
		"distance_m": snappedf(p.x - p0.x, 0.01), "on_balcony": p.x > 70.4 and p.y > 0.8 and p.y < 2.5}
	log_line("long jump " + JSON.stringify(r))
	return r


func _ph_balcony() -> Dictionary:
	var out := {}
	await _tp(Vector3(56.0, 2.1, 34.5), -90.0, 40)
	out["cam_runway"] = await _cam("balcony_runway_view", true)
	out["lj_at_59.4"] = await _long_jump_from(59.4, "lip")
	out["lj_at_57.5"] = await _long_jump_from(57.5, "early_1.9m")
	out["lj_at_56.0"] = await _long_jump_from(56.0, "early_3.4m")
	# Running triple attempt from the runway (should miss: the gap is reserved for the long jump).
	await _tp(Vector3(47.0, 2.1, 34.5), -90.0, 20)
	var f := 0
	var jumps := 0
	while f < 900 and player.global_position.y > -6.0:
		stick = Vector2(1, 0)
		await _frames(1)
		f += 1
		if player.global_position.x > 50.0 and _grounded() and jumps < 3 and f % 2 == 0:
			_press("jump", 14)
			jumps += 1
			await _frames(4)
		if jumps >= 3 and _grounded() and f > 30:
			break
	stick = Vector2.ZERO
	out["triple_from_runway"] = {"jumps": jump_log.slice(maxi(0, jump_log.size() - 3)), "end": _v(player.global_position), "on": _ground_name()}
	# Gumdrop bounce home with the stick held west.
	for k in 2:
		await _tp(Vector3(72.0, 1.1, 34.5), -90.0, 20)
		await _goto(Vector3(73.6, 1.0, 34.5), 0.2, 2.0)
		stick = Vector2(1, 0)
		_press("jump", 14)
		var g := 0
		var top := 0.0
		while g < 400:
			await _frames(1)
			g += 1
			top = maxf(top, player.global_position.y)
			if player.global_position.y > 4.0 or g > 40:
				stick = Vector2(-1, 0) if k == 0 else Vector2(-0.7, 0)
			if g > 20 and _grounded():
				break
			if player.global_position.y < -6.0:
				break
		stick = Vector2.ZERO
		await _frames(6)
		out["bounce_home_%d" % k] = {"stick": "full west" if k == 0 else "70% west", "apex_y": snappedf(top, 0.01), "landed": _v(player.global_position), "on": _ground_name(),
			"home": player.global_position.x < 60.2 and player.global_position.y > 1.5, "frames": g}
		if k == 0:
			out["cam_after_bounce"] = await _cam("after_breeze_return", true)
	log_line("balcony " + JSON.stringify(out))
	return out


# ------------------------------------------------------------------ cherry cap (J82)

func _ph_cherry() -> Dictionary:
	var out := {}
	var cap := Vector3(38.6, 30.4, -43.4)
	# Standing double: hop, then press on landing.
	await _tp(Vector3(39.0, 28.1, -42.0), 180.0, 30)
	var a := await _jump_at(Vector3(39.0, 28.0, -42.4), 10, "cherry_prehop")
	var b := await _jump_at(cap, 14, "cherry_double")
	out["standing_double"] = {"pre": a, "jump": b}
	# Single only (negative-ish).
	await _tp(Vector3(39.0, 28.1, -42.2), 180.0, 30)
	out["single"] = await _jump_at(cap, 14, "cherry_single")
	await _tp(Vector3(39.4, 28.1, -40.6), 180.0, 30)
	out["cam_summit"] = await _cam("summit_to_cherry", true)
	return out


# ------------------------------------------------------------------ fall-outs: where and how fast Mak comes back

func _fall_case(label: String, pos: Vector3, yaw: float, st: Vector2) -> Dictionary:
	await _tp(pos, yaw, 2)
	var t0 := Time.get_ticks_msec()
	var dmg0 := damage_log.size()
	var h0 := int(get_node("/root/Game").get("health"))
	var f := 0
	var low := pos.y
	var seen_fall := false
	while f < 60 * 12:
		stick = st if f < 40 else Vector2.ZERO
		await _frames(1)
		f += 1
		low = minf(low, player.global_position.y)
		if _st() == "fallout":
			seen_fall = true
		if f > 30 and _grounded() and (seen_fall or player.global_position.distance_to(pos) > 6.0):
			break
	await _frames(30)
	var r := {"label": label, "start": _v(pos), "lowest_y": snappedf(low, 0.01), "fallout_state": seen_fall, "back_at": _v(player.global_position),
		"seconds": snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.01), "damage_events": damage_log.size() - dmg0, "health": [h0, int(get_node("/root/Game").get("health"))]}
	r["cam_back"] = await _cam("fall_back_" + label, true)
	log_line("fall " + JSON.stringify(r))
	return r


func _ph_fallouts() -> Dictionary:
	var out := {}
	out["balcony_gap"] = await _fall_case("balcony_gap", Vector3(65.0, 1.5, 34.5), -90.0, Vector2.ZERO)
	out["summit_edge_south"] = await _fall_case("summit_west_drop", Vector3(36.4, 28.2, -42.0), 90.0, Vector2(-1, 0))
	out["pillar_miss"] = await _fall_case("pillar_valley", Vector3(-28.5, 11.5, -37.8), 90.0, Vector2.ZERO)
	out["candle_miss"] = await _fall_case("tierD_east_drop", Vector3(44.6, 24.2, -42.0), -90.0, Vector2(1, 0))
	return out


# ------------------------------------------------------------------ W3 bot plans with camera sampling

func _bot_run(plan_name: String, max_s: float, shot_frames: Array) -> Dictionary:
	var plans: Dictionary = level.call("_bot_plans")
	if not plans.has(plan_name):
		return {"error": "no plan " + plan_name}
	var bot := Node.new()
	bot.set_script(load("res://scripts/worlds/w3_bot.gd"))
	level.add_child(bot)
	bot.call("setup", "feel_" + plan_name, plans[plan_name], max_s)
	drive = false
	var dmg0 := damage_log.size()
	var f := 0
	var n := 0
	var occl := 0
	var inside := 0
	var min_arm := 99.0
	var worst := {}
	var shots: Array = []
	var max_err := 0.0
	var errs := 0.0
	var ne := 0
	while f < int(max_s * 60.0):
		await _frames(1)
		f += 1
		if f % 8 == 0:
			var cs := await _cam("bot_" + plan_name)
			n += 1
			if String(cs["occluder"]) != "":
				occl += 1
				if worst.is_empty():
					worst = cs
			if (cs["inside"] as Array).size() > 0:
				inside += 1
			min_arm = minf(min_arm, float(cs.get("arm_m", 99.0)) if bool(cs["cam_is_rig"]) else 99.0)
			var v: Vector3 = player.velocity
			var hv := Vector2(v.x, v.z)
			if hv.length() > 6.0 and _st() in ["belly_slide", "slide", "walk", "run", "slope_slide", "dive"]:
				var vc := get_viewport().get_camera_3d()
				var fwd := -vc.global_basis.z
				var a := absf(rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(hv)))
				max_err = maxf(max_err, a)
				errs += a
				ne += 1
		if f in shot_frames:
			shots.append(await _cam("%s_f%d" % [plan_name, f], true))
		if bool(bot.get("_done")):
			break
	drive = true
	var r := {"plan": plan_name, "frames": f, "done": bool(bot.get("_done")), "samples": n, "occluded": occl, "cam_inside_geometry": inside,
		"min_arm_m": snappedf(min_arm, 0.01), "first_occlusion": worst, "damage": damage_log.size() - dmg0, "shots": shots,
		"fast_move_cam_vs_vel_max_deg": snappedf(max_err, 0.1), "fast_move_cam_vs_vel_mean_deg": snappedf(errs / maxf(ne, 1), 0.1)}
	bot.queue_free()
	await _frames(10)
	log_line("bot " + JSON.stringify(r).left(1500))
	return r


func _ph_bots() -> Dictionary:
	var out := {}
	out["w34_joust"] = await _bot_run("w34", 40.0, [150, 300, 450, 600, 750])
	await _tp(Vector3(0, 2.1, 45), 0.0, 30)
	out["w33_dunk"] = await _bot_run("w33", 45.0, [200, 400, 600, 800])
	await _tp(Vector3(0, 2.1, 45), 0.0, 30)
	out["w36_kitchen"] = await _bot_run("w36", 40.0, [120, 240, 420, 600])
	await _tp(Vector3(0, 2.1, 45), 0.0, 30)
	out["w38_sprint"] = await _bot_run("w38", 40.0, [120, 300, 500, 700])
	return out

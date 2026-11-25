extends Node
## Exit gate test bot (dev only, --exitbot [--exitbot-out=<abs dir>]). Added to /root by WorldExits.install, so it
## outlives the world it tests. Drives the real MakPlayer through its replay input layer (world-steered stick, held
## jump) and sends real key / pad events for the prompt and the confirm:
##   walk_blocked   walk straight into the closed gate (must stop in front of it)
##   jump_*         run and keep jumping at the gate, beside it (just past the opening) and further along the wall
##   arch_top (W1)  from the top of the Page Gate arch, run off the back and keep jumping toward the void
##   prompt         stand at the gate: the interact prompt shows ("Return to the library")
##   confirm_no     E opens "Return to the Grand Library?", input is blocked while it is open, pad A on the default
##                  "No" closes it and Mak stays in the world
##   confirm_yes    pad Y opens it again, Right + Enter picks "Yes": the page turns to the Hub
## A movement run fails if Mak passes behind the wall line or drops more than 3 m below the gate base (the void).
## Captures (gameplay camera) go to <out>/<world>_gate.png, _prompt.png, _confirm.png, _hub.png; results to
## <out>/<world>_exitbot.json. Prints "[ExitBot] PASS|FAIL <test> ...".

var world_id := ""
var p: CharacterBody3D
var inp: Object
var stick := Vector2.ZERO
var gate: Node3D
var out_dir := ""
var results: Array = []
var _min_lz := INF
var _min_y := INF
var _track := false
var _base_y := 0.0
var _wall_back := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	var dev := get_node_or_null("/root/Dev")
	out_dir = String(dev.call("arg", "exitbot-out", "")) if dev else ""
	await get_tree().create_timer(2.0).timeout
	p = get_tree().get_first_node_in_group("player") as CharacterBody3D
	gate = get_tree().get_first_node_in_group("exit_gate") as Node3D
	if p == null or gate == null:
		print("[ExitBot] FAIL setup player=%s gate=%s" % [p, gate])
		get_tree().quit()
		return
	inp = p.get("inp")
	inp.call("setup", {"steer": "world", "events": []}, 0.2, 1.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		e.set("ai_enabled", false)
	_base_y = gate.global_position.y
	var b: Array = gate.get("bounds")
	if not b.is_empty():
		_wall_back = float((b[0][1] as Vector3).z) - float((b[0][0] as Vector3).z) * 0.5
	print("[ExitBot] %s gate at %s, wall back face local z %.2f" % [world_id, gate.global_position, _wall_back])
	var hw := float(gate.get("open_w")) * 0.5
	if dev and dev.call("has_arg", "shots"):
		# W1: show the post-W1-4 well (spout on, roof gone) for the before/after capture of that spot.
		var lv := get_tree().current_scene.get_node_or_null("Level") if get_tree().current_scene else null
		if world_id == "W1" and lv and lv.has_method("_erupt") and lv.get_node_or_null("WellRing") == null:
			lv.call("_erupt", false)
			await wait(30)
		var sb = Node.new()
		sb.set_script(load("res://scripts/worlds/shot_bot.gd"))
		sb.set("auto", false)
		add_child(sb)
		await sb.run(false)
	if world_id == "W1":
		await _log_tests()
	# 1. The closed gate from the gameplay camera.
	await tp_local(Vector3(0, 0.6, 7.0))
	await wait(240)  # past the entry banner
	_shot("gate")
	# 2. Movement: walk in, jump at it, beside it and further along.
	await move_test("walk_blocked", Vector3(0, 0.6, 3.5), Vector3(0, 0, -8), false, 180)
	await move_test("jump_center", Vector3(0, 0.6, 5.0), Vector3(0, 0, -8), true, 300)
	for sx in [-1.0, 1.0]:
		var tag := "L" if sx < 0 else "R"
		await move_test("jump_side_" + tag, Vector3(sx * (hw + 1.6), 0.8, 4.0), Vector3(sx * (hw + 1.6), 0, -8), true, 300)
		await move_test("jump_far_" + tag, Vector3(sx * (hw + 5.0), 1.2, 4.0), Vector3(sx * (hw + 5.0), 0, -8), true, 300)
		await move_test("jump_diag_" + tag, Vector3(sx * 0.5, 0.6, 4.0), Vector3(sx * (hw + 6.0), 0, -8), true, 300)
	if world_id == "W1":
		# The Page Gate's arch top (secret A19 ring): run off its back and keep jumping toward the page edge.
		await move_test("arch_top", Vector3(0, 0, 0), Vector3(0, 0, -12), true, 360, Vector3(0, 8.0, 57.5))
	# 3. Prompt.
	stick = Vector2.ZERO
	await tp_local(Vector3(0, 0.6, 1.4))
	await wait(70)
	var shown := bool(gate.get("_prompt_shown"))
	_row("prompt", shown, "prompt shown %s, verb '%s'" % [shown, gate.get("prompt_verb")])
	_shot("prompt")
	# 4. Confirm, No (keyboard E opens, pad A answers the default No).
	await _key(KEY_E)
	await wait(30)
	var ui := get_node_or_null("/root/UI")
	var pm: Node = ui.get("pause_menu") if ui else null
	var conf: Control = pm.get("_confirm") if pm else null
	var open_ok := conf != null and conf.visible and get_tree().paused and bool(ui.call("is_input_blocked"))
	_shot("confirm")
	# Input to Mak is held while the card is open.
	var before := p.global_position
	stick = Vector2(0, 1)
	inp.get("_hold_frames")["jump"] = 20
	await wait(40)
	stick = Vector2.ZERO
	inp.get("_hold_frames")["jump"] = 0
	var still := p.global_position.distance_to(before) < 0.05
	var focus: Control = get_viewport().gui_get_focus_owner()
	var focus_cap := String(focus.get("caption")) if focus and "caption" in focus else "?"
	await _pad(JOY_BUTTON_A)
	await wait(60)
	var closed := conf != null and not conf.visible and not get_tree().paused and not bool(pm.call("is_open"))
	var g0 := get_node_or_null("/root/Game")
	var in_world := is_instance_valid(gate) and is_instance_valid(p) and g0 != null and String(g0.get("current_world")) == world_id
	var moved := p.global_position.distance_to(before) if is_instance_valid(p) else -1.0
	_row("confirm_no", open_ok and still and closed and in_world, "opened %s, input held while open %s, default focus '%s', closed %s, still in %s %s (moved %.2f m after closing)" % [open_ok, still, focus_cap, closed, world_id, in_world, moved])
	# 5. Confirm, Yes (pad Y opens, keyboard Right + Enter picks Yes): the page turns to the Hub.
	await tp_local(Vector3(0, 0.6, 1.4))
	await wait(80)
	var open2 := false
	var tries := 0
	for attempt in 3:
		tries += 1
		if attempt == 1:
			await _key(KEY_E)
		else:
			await _pad(JOY_BUTTON_Y)
		await wait(30)
		open2 = conf != null and conf.visible
		if open2:
			break
		print("[ExitBot] reopen try %d: near=%s cool=%.2f shown=%s blocked=%s paused=%s" % [tries, gate.get("player_near") != null, float(gate.get("_cool")), gate.get("_prompt_shown"), ui.call("is_input_blocked"), get_tree().paused])
		await wait(40)
	await _key(KEY_RIGHT)
	await wait(8)
	focus = get_viewport().gui_get_focus_owner()
	var focus2 := String(focus.get("caption")) if focus and "caption" in focus else "?"
	await _key(KEY_ENTER)
	var t0 := Time.get_ticks_msec()
	var hub := false
	while Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		var g := get_node_or_null("/root/Game")
		var r := get_node_or_null("/root/Router")
		if cs and String(cs.scene_file_path).contains("Hub") and g and String(g.get("current_world")) == "HUB" and r and not bool(r.get("busy")):
			hub = true
			break
	if hub:
		await get_tree().create_timer(2.5).timeout
		_shot("hub")
	var g2 := get_node_or_null("/root/Game")
	_row("confirm_yes", open2 and focus2 == "Yes" and hub, "opened %s (press %d), focus after Right '%s', hub loaded %s (%.1fs), world %s" % [open2, tries, focus2, hub, (Time.get_ticks_msec() - t0) / 1000.0, g2.get("current_world") if g2 else "?"])
	_finish()


func _physics_process(_d: float) -> void:
	if inp and is_instance_valid(p):
		inp.set("_r_stick", stick)
		if _track and is_instance_valid(gate):
			var lp := gate.global_transform.affine_inverse() * p.global_position
			_min_lz = minf(_min_lz, lp.z)
			_min_y = minf(_min_y, p.global_position.y)


func wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func tp_local(lp: Vector3, world_pos: Vector3 = Vector3.INF) -> void:
	stick = Vector2.ZERO
	var at := world_pos if world_pos != Vector3.INF else gate.global_transform * lp
	if world_pos == Vector3.INF:
		at.y = gate.global_position.y + lp.y
	var face := gate.global_basis * Vector3(0, 0, -1)
	face.y = 0.0
	p.call("respawn", Transform3D(Basis.looking_at(face.normalized(), Vector3.UP), at))
	await wait(14)


func steer_local(lt: Vector3) -> float:
	var t := gate.global_transform * lt
	var d := t - p.global_position
	d.y = 0.0
	if d.length() < 0.2:
		stick = Vector2.ZERO
		return 0.0
	stick = Vector2(d.x, -d.z).normalized()
	return d.length()


func move_test(id: String, from_l: Vector3, to_l: Vector3, jumps: bool, n: int, from_world: Vector3 = Vector3.INF) -> void:
	await tp_local(from_l, from_world)
	_min_lz = INF
	_min_y = INF
	_track = true
	var hf: Dictionary = inp.get("_hold_frames")
	var jumps_n := 0
	var air := 0
	for f in n:
		steer_local(to_l)
		if jumps and p.is_on_floor() and air > 4 and int(hf.get("jump", 0)) <= 0:
			hf["jump"] = 18
			jumps_n += 1
			air = 0
		air += 1
		await get_tree().physics_frame
		while get_tree().paused:
			await get_tree().process_frame
	_track = false
	stick = Vector2.ZERO
	var through := _min_lz < _wall_back - 0.2
	var fell := _min_y < _base_y - 3.0
	var lp := gate.global_transform.affine_inverse() * p.global_position
	_row(id, not through and not fell, "min local z %.2f (wall back %.2f), min y %.2f (base %.2f), %d jumps, end local (%.1f, %.1f, %.1f)" % [_min_lz, _wall_back, _min_y, _base_y, jumps_n, lp.x, lp.y, lp.z])


## W1-5 P1 Hollow Log (owner fix 2026-10-19): the 1.0 m tunnel must stop standing Mak (1.25 m capsule) at the east
## mouth (x -14) and let him through crouched (the W1 bot's own P1 leg crouch-walks it too).
func _log_tests() -> void:
	var start := Vector3(-11.5, W1Terrain.height(-11.5, 1.5) + 0.1, 1.5)
	var hf: Dictionary = inp.get("_hold_frames")
	for crouch in [false, true]:
		stick = Vector2.ZERO
		p.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), start))
		await wait(20)
		var min_x := INF
		for f in 330:
			var d := Vector3(-18.5, 0, 1.5) - p.global_position
			d.y = 0.0
			stick = Vector2(d.x, -d.z).normalized() if d.length() > 0.3 else Vector2.ZERO
			if crouch and p.global_position.x < -12.6:
				hf["crouch"] = 10
			min_x = minf(min_x, p.global_position.x)
			await get_tree().physics_frame
		stick = Vector2.ZERO
		hf["crouch"] = 0
		if crouch:
			_row("log_crouch_passes", min_x < -17.5, "crouched Mak reached x %.2f (log spans -20..-14)" % min_x)
		else:
			_row("log_stand_blocked", min_x > -14.2, "standing Mak stopped at x %.2f (east mouth x -14, ceiling 1.0 m)" % min_x)
		await wait(30)


func _row(id: String, ok: bool, msg: String) -> void:
	results.append({"test": id, "pass": ok, "detail": msg})
	print("[ExitBot] %s %s %s: %s" % ["PASS" if ok else "FAIL", world_id, id, msg])


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await wait(3)
	var r := e.duplicate() as InputEventKey
	r.pressed = false
	Input.parse_input_event(r)
	await wait(2)


func _pad(button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = 0
	e.pressed = true
	e.pressure = 1.0
	Input.parse_input_event(e)
	await wait(3)
	var r := e.duplicate() as InputEventJoypadButton
	r.pressed = false
	r.pressure = 0.0
	Input.parse_input_event(r)
	await wait(2)


func _shot(tag: String) -> void:
	if out_dir == "":
		return
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(out_dir.path_join("%s_%s.png" % [world_id, tag]))


func _finish() -> void:
	var ok := 0
	for r in results:
		if r["pass"]:
			ok += 1
	print("[ExitBot] DONE %s %d/%d" % [world_id, ok, results.size()])
	if out_dir != "":
		var f := FileAccess.open(out_dir.path_join("%s_exitbot.json" % world_id), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"utc": Time.get_datetime_string_from_system(true), "world": world_id, "passed": ok, "total": results.size(), "results": results}, "  "))
	get_tree().paused = false
	get_tree().quit()

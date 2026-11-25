extends Node
## W2 fix round 2 verification driver (dev only: --w2-verify=<case,case,...> or "all").
## Drives the REAL player through Input actions (camera-relative stick, jump/attack/crouch presses). A teleport
## only ever places Mak at the START of a challenge, never past it. Prints "[W2V]" result lines and saves
## gameplay-camera shots to Docs/progress/w2/fix2/ (dir passed with --w2-verify-out=<abs dir>).
## Cases: bud, e04, cp1cam, viewcams, bankfall, lb, strike.

var world: Node3D
var player: CharacterBody3D
var cases: PackedStringArray
var out_dir := ""
var t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func say(s: String) -> void:
	print("[W2V] t=%.2f %s" % [t, s])


func _process(delta: float) -> void:
	t += delta


func _health() -> int:
	var g := get_node_or_null("/root/Game")
	return int(g.get("health")) if g and "health" in g else -1


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _phys() -> void:
	await get_tree().physics_frame


func _tp(pos: Vector3, yaw_deg: float) -> void:
	_release()
	if player.has_method("respawn"):
		player.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))
	else:
		player.global_position = pos
	player.velocity = Vector3.ZERO
	await _wait(0.6)


func _stick_world(d: Vector3, mag := 1.0) -> void:
	var cam := get_viewport().get_camera_3d()
	_release_moves()
	if cam == null or d.length() < 0.001:
		return
	var f := -cam.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var r := cam.global_basis.x
	r.y = 0.0
	r = r.normalized()
	d.y = 0.0
	d = d.normalized() * mag
	var x := d.dot(r)
	var y := d.dot(f)
	if x > 0.0: Input.action_press("move_right", minf(x, 1.0))
	elif x < 0.0: Input.action_press("move_left", minf(-x, 1.0))
	if y > 0.0: Input.action_press("move_forward", minf(y, 1.0))
	elif y < 0.0: Input.action_press("move_back", minf(-y, 1.0))


func _release_moves() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func _release() -> void:
	_release_moves()
	for a in ["attack", "jump", "crouch"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func _tap(action: String, frames := 1) -> void:
	Input.action_press(action)
	for i in frames:
		await _phys()
	Input.action_release(action)


func _shot(name_: String) -> void:
	if out_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var p := out_dir.path_join("%sZ__%s.png" % [stamp, name_])
	img.save_png(p)
	say("shot %s" % p)


func _state() -> String:
	return String(player.call("get_state_name")) if player.has_method("get_state_name") else ""


func _run() -> void:
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and cs.get("player") != null:
			world = cs
			player = cs.get("player") as CharacterBody3D
			break
	var dev := get_node_or_null("/root/Dev")
	var arg := String(dev.call("arg", "w2-verify", "all")) if dev else "all"
	out_dir = String(dev.call("arg", "w2-verify-out", "")) if dev else ""
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	cases = PackedStringArray(["bud", "e04", "cp1cam", "viewcams", "bankfall", "lb", "strike"]) if arg == "all" else arg.split(",")
	await _wait(3.0)
	for c in cases:
		say("CASE %s begin" % c)
		match c:
			"bud": await _case_bud()
			"e04": await _case_e04()
			"cp1cam": await _case_cp1cam()
			"viewcams": await _case_viewcams()
			"bankfall": await _case_bankfall()
			"lb": await _case_lb()
			"t3": await _case_t3()
			"strike": await _case_strike()
			"caw": await _case_caw()
		_release()
		say("CASE %s end" % c)
	say("DONE")
	get_tree().quit(0)


func _case_bud() -> void:
	var play = world.get("play")
	var held: Array = play.get("_bud_held") if play else []
	var page_in := play != null and (play.get("holder") as Node).get_node_or_null("Page4") != null
	say("RESULT bud: held=%d page4_in_tree=%s (pass = held 2, page4 not in tree)" % [held.size(), page_in])
	# Stand on the closed bud's top for 1.5 s: nothing may be collected.
	var g := get_node_or_null("/root/Game")
	var pages_before: int = int(g.call("page_count", "W2")) if g and g.has_method("page_count") else -1
	await _tp(Vector3(7.2, 38.6, -6.0), 0.0)
	await _wait(1.5)
	var pages_after: int = int(g.call("page_count", "W2")) if g and g.has_method("page_count") else -1
	say("RESULT bud_top: pages %d -> %d, mak y %.2f" % [pages_before, pages_after, player.global_position.y])


func _case_e04() -> void:
	# Idle on the Cloud Landing for 10 s: count hits and where the crow is.
	await _tp(Vector3(-4.5, 24.1, -12.0), 0.0)
	var h0 := _health()
	var e04: Node3D = (world.get("play").get("nodes") as Dictionary).get("E04")
	var min_d := 999.0
	for i in 100:
		await _wait(0.1)
		if e04 and is_instance_valid(e04):
			min_d = minf(min_d, e04.global_position.distance_to(player.global_position))
	say("RESULT e04: health %d -> %d over 10 s on C1; crow min dist %.1f; mak still on C1: %s (y %.2f)" % [h0, _health(), min_d, player.global_position.y > 23.5, player.global_position.y])


func _case_cp1cam() -> void:
	await _tp(Vector3(5.44, 20.45, -6.22), 90.0)
	await _wait(2.2)
	await _shot("cp1_respawn_cam")


func _case_viewcams() -> void:
	for v in [["M06", Vector3(1.28, 35.65, -10.84), 160.0], ["L12", Vector3(1.31, 21.65, -7.46), 100.0], ["M04", Vector3(1.68, 33.25, -3.76), 180.0],
			["courtyard_apron", Vector3(6.0, 50.1, -19.0), 0.0], ["kitchen_floor", Vector3(-4.0, 50.1, -29.0), 90.0], ["allotment_R1", Vector3(14.5, 24.1, -13.5), -90.0]]:
		await _tp(v[1], v[2])
		await _wait(2.0)
		await _shot("view_" + String(v[0]))


func _case_bankfall() -> void:
	# Walk off the castle bank's south rim: a cloud must catch Mak and put him back on the bank, no heart lost.
	await _tp(Vector3(31.0, 50.1, -27.0), -90.0)
	await _wait(0.8)
	var h0 := _health()
	var t0 := t
	_stick_world(Vector3(1, 0, 0))
	var caught := false
	var min_y := 99.0
	for i in 600:
		await _phys()
		min_y = minf(min_y, player.global_position.y)
		if player.global_position.y < 47.0:
			_release_moves()
		if min_y < 45.0 and player.global_position.y > 49.0 and player.is_on_floor():
			caught = true
			break
	_release()
	say("RESULT bankfall: caught=%s in %.1f s, lowest y %.1f, health %d -> %d, back at %s" % [caught, t - t0, min_y, h0, _health(), player.global_position])


func _case_lb() -> void:
	# Leaf Bouncer chain with the stick held toward the next pad on every bounce (a first-timer's input).
	var b = world.get("builder")
	var pads: Array[Node3D] = []
	for id in ["LB1", "LB2", "LB3", "LB4", "LB5"]:
		pads.append(b.bodies.get(id))
	for attempt in 3:
		await _tp(Vector3(-17.2, 44.1, -9.6), 0.0)
		var h0 := _health()
		var next := 0
		var reached: Array = []
		var t0 := t
		var jumped := false
		var lost := false
		var left_start := false
		while t - t0 < 22.0:
			await _phys()
			var pp := player.global_position
			var target: Vector3 = pads[next].global_position if next < pads.size() else Vector3(-40.5, 46.0, -36.5)
			# Like a player, look ahead: once over the pad being landed on, hold toward the one after it.
			var aim := target
			if next < pads.size() and Vector2(target.x - pp.x, target.z - pp.z).length() < 2.2:
				aim = pads[next + 1].global_position if next + 1 < pads.size() else Vector3(-40.5, 46.0, -36.5)
			_stick_world(aim - pp)
			if not jumped:
				var flat := Vector2(target.x - pp.x, target.z - pp.z).length()
				if flat < 4.6 or pp.x < -19.4:
					await _tap("jump", 10)
					jumped = true
			var fl: Object = null
			for i in player.get_slide_collision_count():
				var col := player.get_slide_collision(i)
				if col.get_normal().y > 0.6:
					fl = col.get_collider()
			if fl != null and next < pads.size() and fl == pads[next]:
				reached.append(next + 1)
				next += 1
				say("  lb landed on LB%d at %s" % [next, player.global_position])
			elif fl != null and next > 0 and fl != pads[next - 1] and player.is_on_floor() and (fl as Node).name != "UC":
				say("  lb landed on %s at %s" % [(fl as Node).name, player.global_position])
			if pp.distance_to(Vector3(-17.0, 44.05, -9.2)) > 3.0:
				left_start = true
			if pp.y < 40.0 or (left_start and pp.distance_to(Vector3(-17.0, 44.05, -9.2)) < 0.8):
				lost = true
				say("  lb lost at %s heading for pad %d (pad at %s)" % [pp, next + 1, target])
				break
			if next >= pads.size() and pp.distance_to(Vector3(-40.5, 46.0, -38.0)) < 3.2 and player.is_on_floor():
				break
		_release()
		say("RESULT lb attempt %d: pads reached %s, islet=%s, lost=%s, %.1f s, health %d -> %d" % [attempt + 1, str(reached), next >= pads.size() and not lost, lost, t - t0, h0, _health()])
		# Finishing pass: all three attempts run, so the result is a success rate, not a first success.


func _case_t3() -> void:
	# Finishing pass: V3 top -> T3 with the stick held toward T3 (pole jump), 3 attempts.
	var t3 := Vector3(-8.6, 62.8, -16.6)
	for attempt in 3:
		await _tp(Vector3(-7.0, 59.6, -15.7), 0.0)
		await _wait(0.8)
		var st0 := _state()
		Input.action_press("move_forward")
		await _wait(1.0)
		_release_moves()
		var st1 := _state()
		_stick_world(t3 - player.global_position)
		await _tap("jump", 8)
		var best := 99.0
		var t0 := t
		while t - t0 < 2.5:
			await _phys()
			_stick_world(t3 - player.global_position)
			if player.is_on_floor() and t - t0 > 0.2:
				break
		_release()
		var pp := player.global_position
		best = Vector2(pp.x - t3.x, pp.z - t3.z).length()
		say("RESULT t3 attempt %d: state %s -> %s, landed at %s, %.2f m from T3 centre, on_floor=%s" % [attempt + 1, st0, st1, pp, best, player.is_on_floor()])


func _case_strike() -> void:
	# Pea Pod Patrol lane R1 (z -13.5; pods at x 19.0, 22.2, 25.4; the deck spans x 14.8..31.2 there). Ham Slam
	# beside E06 from the lane's north side, run east for room, then turn and dive west down the lane.
	var life: Node = world.get("life")
	var play = world.get("play")
	var alive := func() -> int:
		var n := 0
		for p in play.get("poppers"):
			if is_instance_valid(p) and not bool(p.get("is_defeated")):
				n += 1
		return n
	for attempt in 3:
		var a0: int = alive.call()
		await _tp(Vector3(20.6, 24.4, -12.4), -90.0)
		var h_slam := _health()
		await _tap("jump", 8)
		await _wait(0.25)
		var st_slam := _state()
		await _tap("crouch", 2)
		await _wait(0.55)
		var stunned: int = (life.get("_stunned_pods") as Dictionary).size()
		var near_txt := ""
		for p in play.get("poppers"):
			if is_instance_valid(p) and not bool(p.get("is_defeated")):
				near_txt += "%s@%.1f " % [p.name, Vector2(p.global_position.x - player.global_position.x, p.global_position.z - player.global_position.z).length()]
		say("  slam: state before crouch %s, health %d -> %d, stunned %d, pods %s" % [st_slam, h_slam, _health(), stunned, near_txt])
		var t_slam := t
		var t0 := t
		while player.global_position.x < 30.4 and t - t0 < 2.2:
			_stick_world(Vector3(1, 0, clampf((-11.0 - player.global_position.z) * 0.8, -0.6, 0.6)))
			await _phys()
		var dove := false
		var dive_x := 0.0
		var dive_v := 0.0
		var slid := false
		var end_x := 0.0
		var states := {}
		t0 = t
		while t - t0 < 3.5:
			var dz := -13.5 - player.global_position.z
			_stick_world(Vector3(-1, 0, clampf(dz * 0.7, -0.5, 0.5)))
			await _phys()
			var st := _state()
			states[st] = true
			var fs := float(player.get("forward_speed"))
			if not dove and (fs >= 6.85 or player.global_position.x < 27.4):
				dive_x = player.global_position.x
				dive_v = fs
				Input.action_press("attack")
				await _phys()
				Input.action_release("attack")
				dove = true
				continue
			if dove and st in ["dive", "belly_slide", "crouch_slide"]:
				slid = true
			if slid and not (st in ["dive", "belly_slide", "crouch_slide"]):
				end_x = player.global_position.x
				break
		_release()
		await _wait(0.6)
		say("RESULT strike attempt %d: stunned %d (dive %.1f s after the slam), pods alive %d -> %d, dive at x %.1f speed %.1f, slide ended x %.1f, health %d, states %s" % [attempt + 1, stunned, t0 - t_slam, a0, alive.call(), dive_x, dive_v, end_x, _health(), str(states.keys())])
		if a0 - int(alive.call()) >= 3 or int(alive.call()) <= 2:
			break


func _case_caw() -> void:
	# W2-4: wake Captain Caw at TAUNT, then bounce in place on LB2 (and LB4) and jump-kick at the top of each bounce.
	var caw: Node3D = (world.get("play").get("nodes") as Dictionary).get("E17")
	if caw == null:
		say("RESULT caw: no Captain Caw (W2-4 already owned?)")
		return
	await _tp(Vector3(-19.2, 44.35, -10.2), 125.0)
	await _wait(1.5)
	var b = world.get("builder")
	for pad_id in ["LB2", "LB4"]:
		var pad: Node3D = b.bodies.get(pad_id)
		var h0 := int(caw.get("hits"))
		await _tp(pad.global_position + Vector3(0, 0.8, 0), 135.0)
		var kicks := 0
		var t0 := t
		var was_up := false
		while t - t0 < 9.0 and int(caw.get("hits")) == h0:
			await _phys()
			var vy := player.velocity.y
			# Keep over the swinging pad with small stick nudges.
			var d := pad.global_position - player.global_position
			d.y = 0.0
			if d.length() > 0.35:
				_stick_world(d, clampf(d.length() * 0.6, 0.2, 0.8))
			else:
				_release_moves()
			if vy > 4.0:
				was_up = true
			if was_up and vy < 1.2 and not player.is_on_floor():
				was_up = false
				await _tap("attack", 1)
				kicks += 1
		_release()
		say("RESULT caw %s: hits %d -> %d after %d apex kicks in %.1f s (caw stage %s)" % [pad_id, h0, int(caw.get("hits")), kicks, t - t0, String(caw.get("stage"))])

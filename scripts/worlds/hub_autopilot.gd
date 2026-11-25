class_name HubAutopilot
extends Node
## Closed-loop scripted input for hub route tests (`-- --hub-test=<name>`). It drives the real input actions
## (Input.action_press on move_* and jump), converting world-space steering to camera-relative stick values
## exactly as the player reads them, so every test runs the same physics a human would.
## Tests: hub1 (L2 -> cornice -> gap -> top balcony -> HUB-1), book1 (enter Book 1), book2_locked, l1 (ladder L1 up),
## chimney (mastery wall kicks to the top balcony).

var test := ""
var steps: Array = []
var _i := 0
var _t := 0.0
var _step_t := 0.0
var _jump_frames := 0
var _jumped := false
var _done := false
var _result := ""
var _log_t := 0.0
var _events: Array[String] = []
var _crouch_frames := 0
var _jump_delay := 0
var _atk_cd := 0.0
var _atk_release := 0
## Fix r1b: sequence mode (`-- --hub-seq=spiral@Test_Spiral,bong@Test_Rim`) runs several route tests in ONE Godot
## launch (the machine has two run slots shared by many agents): each test reloads the hub, moves Mak to its spawn
## marker and runs; the game quits after the last one. Static state survives the scene reload.
static var seq_tests: PackedStringArray = []
static var seq_i := 0
static var seq_loaded := false
var _seq_spawn := ""


static func seq_current() -> String:
	return String(seq_tests[seq_i]).get_slice("@", 0) if seq_i < seq_tests.size() else ""


func _ready() -> void:
	process_priority = -100
	process_physics_priority = -100
	var dev := get_node_or_null("/root/Dev")
	if dev and not seq_loaded and String(dev.call("arg", "hub-seq", "")) != "":
		seq_tests = String(dev.call("arg", "hub-seq", "")).split(",", false)
		seq_loaded = true
	if not seq_tests.is_empty() and seq_i < seq_tests.size():
		test = seq_current()
		_seq_spawn = String(seq_tests[seq_i]).get_slice("@", 1) if String(seq_tests[seq_i]).contains("@") else ""
		if _seq_spawn != "":
			_done = true
			_seq_place.call_deferred()
	else:
		test = String(dev.call("arg", "hub-test", "")) if dev else ""
	steps = _plan(test)
	print("[HubTest] start %s with %d steps" % [test, steps.size()])
	var game := get_node_or_null("/root/Game")
	if game:
		game.truffle_collected.connect(func(id: String) -> void: _event("truffle_collected:" + id))
	for p in get_tree().get_nodes_in_group("storybook_portal"):
		if p.has_signal("entered"):
			p.connect("entered", func(w: String) -> void: _event("portal_entered:" + w))


func _event(e: String) -> void:
	_events.append(e)
	print("[HubTest] event %s at t=%.2f pos=%s" % [e, _t, _player().global_position if _player() else Vector3.ZERO])


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


static func pp(r: float, th: float, y: float) -> Vector3:
	return HubKit.polar(r, th, y)


func _plan(name: String) -> Array:
	match name:
		"hub1":
			# Amendments R1.3: L2, back to the cornice's north end, long jump the 128-148 gap, hop up, Ham Slam the gilt board, take the jar.
			var s: Array = []
			# r1 fix round: aim at the ladder axis (it leans out to x 13.0 by y 6.8), not beside its foot; with the
			# current jump arc the old target landed Mak short of the grab radius.
			# Completion pass: from the east bay the gallery rail (1 m) stops Mak 1.7 m short of the ladder, and the bot
			# only jumped inside 1.0 m, so it pushed against the rail for 20 s. It now jumps from 2.6 m out, the way a
			# player hops the rail onto the ladder.
			s.append({"goto": Vector3(12.85, 4.5, 4.65), "tol": 0.3, "jump_dist": 2.6, "until_state": "pole_climb"})
			s.append({"climb": true, "until_y": 8.3})
			s.append({"wait": 0.3})
			s.append({"goto": pp(15.2, 101.5, 8.5), "tol": 0.5})
			for th in [108.0, 114.0, 120.0]:
				s.append({"goto": pp(15.25, th, 8.5), "tol": 0.7})
			s.append({"goto": pp(15.2, 152.0, 8.5), "tol": 0.8, "jump_dist": 7.05, "long": true})
			for th in [157.0, 162.0, 166.0]:
				s.append({"goto": pp(15.2, th, 8.5), "tol": 0.6})
			s.append({"goto": pp(15.0, 178.0, 9.7), "tol": 0.6, "jump_dist": 2.6})
			s.append({"goto": pp(14.6, 185.0, 9.7), "tol": 0.4})
			s.append({"goto": pp(14.6, 186.0, 9.7), "tol": 0.15, "slow": true})
			s.append({"wait": 0.4})
			s.append({"slam": true})
			s.append({"wait": 3.6})
			s.append({"goto": pp(14.9, 190.0, 9.7), "tol": 0.3, "until_event": "truffle_collected:HUB-1"})
			return s
		"hub1_short":
			# Negative check: a plain running jump at the long-jump spot must fall short onto the gallery.
			var s2: Array = []
			s2.append({"goto": Vector3(12.5, 4.5, 4.0), "tol": 0.5, "jump_dist": 0.7, "until_state": "pole_climb"})
			s2.append({"climb": true, "until_y": 8.3})
			s2.append({"wait": 0.3})
			s2.append({"goto": pp(15.2, 101.5, 8.5), "tol": 0.5})
			for th in [108.0, 114.0, 120.0]:
				s2.append({"goto": pp(15.25, th, 8.5), "tol": 0.7})
			s2.append({"goto": pp(15.2, 152.0, 8.5), "tol": 0.8, "jump_dist": 7.05})
			s2.append({"wait": 2.0})
			return s2
		"vine":
			return [{"goto": Vector3(5.0, 0, 10.6), "tol": 0.5}, {"goto": Vector3(9.8, 0, 8.8), "tol": 0.4}, {"goto": Vector3(8.9, 0, 7.0), "tol": 0.3, "jump_dist": 1.1, "until_state": "pole_climb"}, {"climb": true, "until_y": 4.3}, {"wait": 1.0}]
		"updraft":
			return [{"goto": Vector3(-6.0, 0, 10.6), "tol": 0.5}, {"goto": Vector3(-9.6, 0, 9.2), "tol": 0.4}, {"goto": Vector3(-9.34, 0, 6.54), "tol": 0.2, "jump_dist": 1.5, "release_after_jump": true, "until_y_above": 4.4}, {"wait": 1.0}]
		"tea_start":
			return [{"goto": Vector3(2.4, 0, 8.8), "tol": 0.4}, {"interact": true}, {"wait": 6.0}]
		"nook":
			return [{"goto": Vector3(-1.2, 0, -11.3), "tol": 0.4}, {"goto": Vector3(0, 0, -11.8), "tol": 0.15, "slow": true}, {"wait": 0.4}, {"slam": true}, {"wait": 2.0}]
		"cub":
			return [{"goto": Vector3(-4.0, 0, 9.0), "tol": 0.5}, {"wait": 1.8}, {"chase": true}, {"wait": 2.0}]
		"book1":
			return [{"goto": Vector3(-5.6, 0, 7.8), "tol": 0.4}, {"goto": Vector3(-7.07, 0, 7.07), "tol": 0.2, "jump_dist": 1.4, "until_event": "portal_entered:W1"}]
		"book2_locked":
			# Locked at 0 truffles: Mak pushes and jumps at the roped book for 6 s; PASS only if no portal fires.
			return [{"goto": Vector3(5.2, 0, 10.6), "tol": 0.5}, {"goto": Vector3(7.07, 0, 7.07), "tol": 0.3, "jump_dist": 2.6, "soft_t": 6.0}, {"wait": 2.5}, {"expect_no_event": "portal_entered"}]
		"l1":
			var a := pp(11.25, 60.0, 0.0)
			return [{"goto": Vector3(6.0, 0, -2.0), "tol": 0.6}, {"goto": a, "tol": 0.5, "jump_dist": 0.9, "until_state": "pole_climb"}, {"climb": true, "until_y": 4.3}, {"wait": 1.0}]
		"chimney":
			return [{"goto": pp(14.5, 206.6, 4.5), "tol": 0.3}, {"chimney": true}, {"wait": 0.5}, {"goto": pp(13.95, 193.0, 9.7), "tol": 0.4}, {"goto": pp(14.0, 187.0, 9.7), "tol": 0.4}, {"goto": pp(14.6, 186.0, 9.7), "tol": 0.15, "slow": true}, {"wait": 0.4}, {"slam": true}, {"wait": 3.6}, {"goto": pp(14.9, 190.0, 9.7), "tol": 0.3, "until_event": "truffle_collected:HUB-1"}]
		"spiral":
			# H-G with --unlock-all from Test_Spiral: hop the rail onto SP01, then book to book at a fixed pace
			# (ignores the wing-book rhythm on purpose, so a fall from SP02 or SP09 is a valid outcome, R3.4 test 2).
			var sp: Array = [{"goto": Vector3(6.56, 5.0, -7.81), "tol": 0.5, "jump_dist": 3.2}]
			if bool(dev_arg_fixed_pace()):
				sp.push_front({"wait": randf_range(0.0, 3.0)})  # R3.4 test 2: random start phase
			var prev_kind := "static"
			for b in HubSpiral.BOOKS.slice(1):
				if not bool(dev_arg_fixed_pace()):
					if String(b[1]) == "wing":
						sp.append({"wait_wing": float(b[5])})  # R3.4 test 1: leave so as to land in the open window
					elif String(b[1]) == "static" and prev_kind != "wing":
						sp.append({"wait": 0.25})  # never dawdle on a wing book
				prev_kind = String(b[1])
				if String(b[1]) == "falling":
					sp.append({"goto": b[2], "tol": 1.7, "jump_dist": 2.6, "auto_jump": true, "slow": true, "stick": 0.8})  # keep moving on fallers (anywhere on the 2.0 x 2.7 cover counts)
				else:
					sp.append({"goto": b[2], "tol": 0.45, "jump_dist": 2.6, "auto_jump": true, "slow": true, "stick": 0.8})
			sp.append({"wait": 0.4})
			# R2.5 / HJ16: backflip from SP10 up onto the chandelier rim (2.2 m back toward the hall axis, 2.9 m up).
			if not bool(dev_arg_fixed_pace()):
				sp.append({"backflip_to": Vector3(0.0, 9.1, 0.0)})
			sp.append({"wait": 1.0})
			return sp
		"bong":
			# R3.3 pass test 1 and 3 from Test_Rim (with --unlock-all): hop inward off the rim and Ham Slam the clock
			# (EV_grand_bong once), then a second slam on the dome plays the plain EV_dome_bong.
			return [{"wait": 1.2}, {"hop_slam": Vector3(0, 0, 1.0)}, {"wait": 4.0}, {"slam": true}, {"wait": 2.0}]
		"idle":
			# Fix r1b: stand still for 3 s (camera-hint captures at a spawn marker in sequence mode).
			return [{"wait": 3.0}]
		"stair":
			return [{"goto": Vector3(2.7, 0, 2.5), "tol": 0.7}, {"goto": Vector3(1.0, 0, -2.6), "tol": 0.6}, {"goto": Vector3(0, 2.25, -8.25), "tol": 0.5}, {"goto": Vector3(0, 4.5, -13.0), "tol": 0.5}, {"wait": 2.0}]
	return []


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_step_t += delta
	var p := _player()
	if p == null:
		return
	_release()
	if _t > (125.0 if test == "cub" else 90.0):
		_finish("TIMEOUT")
		return
	if test == "spiral" and _i >= 1 and p.global_position.y < 3.0:
		_finish("FAIL fell from the spiral before step %d" % _i)
		return
	if _i >= steps.size():
		if test == "spiral":
			_finish("PASS reached the rim" if p.global_position.y > 8.8 else "PASS reached SP10 (rim not reached)")
		else:
			_finish("DONE")
		return
	var st: Dictionary = steps[_i]
	var state := String(p.call("get_state_name")) if p.has_method("get_state_name") else ""
	_log_t += delta
	if _log_t > 0.5:
		_log_t = 0.0
		print("[HubTest] t=%.1f step=%d state=%s pos=(%.2f, %.2f, %.2f)" % [_t, _i, state, p.global_position.x, p.global_position.y, p.global_position.z])
	if st.has("wait_wing"):
		var spi := get_parent().get_node_or_null("HG_Catalogue_Spiral")
		if spi == null:
			_next()
			return
		var ph := fposmod(float(spi.get("_t")) + float(st["wait_wing"]), HubSpiral.WING_PERIOD)
		# Depart just before it reopens: the hop takes about 1.2-1.7 s, so Mak lands early in the 2.0 s window.
		# Fix r1b: measured hop SP01 -> SP02 is about 1.6 s from leaving the wait to touching down, so leave at
		# phase 1.55-1.75 to land just after the cover reopens (phase ~0.2) with the whole 2.0 s window ahead.
		if (ph > 1.55 and ph < 1.75) or _step_t > 6.0:
			_next()
		return
	if st.has("expect_no_event"):
		for e in _events:
			if e.begins_with(String(st["expect_no_event"])):
				_finish("FAIL unexpected " + e)
				return
		_finish("PASS")
		return
	if st.has("wait"):
		if _step_t >= float(st["wait"]):
			_next()
		return
	if st.has("climb"):
		Input.action_press("move_forward", 1.0)
		if p.global_position.y >= float(st["until_y"]) and state != "pole_climb":
			_next()
		elif _step_t > 8.0:
			_finish("FAIL climb stuck")
		return
	if st.has("slam"):
		# Jump straight up, then Ham Slam (crouch in the air).
		if _step_t < 0.05 and _is_grounded(state):
			_jump_frames = 10
		if _step_t > 0.32 and _step_t < 0.36:
			Input.action_press("crouch")
		elif _step_t >= 0.36:
			Input.action_release("crouch")
		if _jump_frames > 0:
			if not Input.is_action_pressed("jump"):
				Input.action_press("jump")
			_jump_frames -= 1
			if _jump_frames == 0:
				Input.action_release("jump")
		if _step_t > 1.4:
			_next()
		return
	if st.has("backflip_to"):
		# Face away from the target, stop, crouch, then jump while crouched: a backflip carries Mak back onto it.
		var bt: Vector3 = st["backflip_to"]
		var away := p.global_position - bt
		away.y = 0.0
		if _step_t < 0.22 and away.length() > 0.1:
			_steer(p, away.normalized() * 0.3)
		if _step_t >= 0.45 and _step_t < 0.95:
			Input.action_press("crouch")
		elif _step_t >= 0.95:
			Input.action_release("crouch")
		if _step_t >= 0.6 and _step_t < 0.85:
			if not Input.is_action_pressed("jump"):
				Input.action_press("jump")
		elif _step_t >= 0.85:
			Input.action_release("jump")
		if _step_t > 0.9 and _step_t < 1.6 and not _is_grounded(state):
			var back := bt - p.global_position
			back.y = 0.0
			if back.length() > 0.3:
				_steer(p, back.normalized() * 0.4)
		if _step_t > 2.2 and _is_grounded(state):
			print("[HubTest] backflip landed at %s y=%.2f" % [p.global_position, p.global_position.y])
			_next()
		elif _step_t > 4.0:
			_next()
		return
	if st.has("hop_slam"):
		var tgt: Vector3 = st["hop_slam"]
		var dd := tgt - p.global_position
		dd.y = 0.0
		if dd.length() > 0.1 and _step_t < 0.4:
			_steer(p, dd.normalized())
		if _step_t < 0.05 and _is_grounded(state):
			_jump_frames = 12
		if _step_t > 0.4 and _step_t < 0.45:
			Input.action_press("crouch")
		elif _step_t >= 0.45:
			Input.action_release("crouch")
		if _jump_frames > 0:
			if not Input.is_action_pressed("jump"):
				Input.action_press("jump")
			_jump_frames -= 1
			if _jump_frames == 0:
				Input.action_release("jump")
		if _step_t > 3.0:
			print("[HubTest] hop_slam landed at %s" % p.global_position)
			_next()
		return
	if st.has("interact"):
		# Tap interact a few times (open the dialog and page through it).
		var f := int(_step_t * 60.0)
		if f % 30 == 0:
			Input.action_press("interact")
		elif f % 30 == 3:
			Input.action_release("interact")
		if _step_t > 4.0:
			Input.action_release("interact")
			_next()
		return
	if st.has("chase"):
		var cub := get_tree().root.find_child("WoollyWolfCub", true, false) as Node3D
		var game := get_node_or_null("/root/Game")
		if game and HubKit.flag(self, "hub_cub_done"):
			_event("cub_caught")
			_next()
			return
		if cub == null:
			_finish("FAIL no cub")
			return
		var dc := cub.global_position - p.global_position
		dc.y = 0.0
		# Play it like a person: in phase 1 cut the corner to the sheep's next waypoint and wait for it;
		# in phase 2 hold still through the aim and charge, then rush it during the skid or dizzy spell.
		var acts := get_parent().get("activities") as Node if get_parent() else null
		var cst := String(acts.get("_cub_state")) if acts else ""
		var aim := dc
		if cst == "run" and acts and dc.length() > 5.0:
			var loop: Array = HubActivities.CUB_LOOP
			var wi := int(acts.get("_cub_i"))
			aim = (loop[(wi + 1) % loop.size()] as Vector3) - p.global_position
			aim.y = 0.0
		var hold := cst in ["aim", "windup", "charge"]
		if not hold and aim.length() > 0.6:
			_steer(p, aim.normalized())
		_atk_cd -= delta
		var reach := 1.8 if cst in ["skid", "dizzy"] else 2.6
		if not hold and dc.length() < reach and _atk_cd <= 0.0:
			_atk_cd = 0.5
			Input.action_press("attack")
			_atk_release = 2
		if _atk_release > 0:
			_atk_release -= 1
			if _atk_release == 0:
				Input.action_release("attack")
		if _step_t > 100.0:
			_finish("FAIL chase timeout")
		return
	if st.has("chimney"):
		_chimney(p, state)
		return
	if st.has("goto"):
		var target: Vector3 = st["goto"]
		var d := target - p.global_position
		d.y = 0.0
		var dist := d.length()
		if st.has("until_y_above") and p.global_position.y > float(st["until_y_above"]) and _is_grounded(state):
			_next()
			return
		if st.has("until_state") and state == String(st["until_state"]):
			_next()
			return
		if st.has("until_event"):
			if _events.has(String(st["until_event"])):
				_finish("PASS")
				return
		elif dist < float(st.get("tol", 0.5)) and (not _jumped or _is_grounded(state)):
			_next()
			return
		if dist > 0.05 and not (bool(st.get("release_after_jump", false)) and _jumped and _step_t > 0.0 and not _is_grounded(state)):
			_steer(p, d / dist * (float(st.get("stick", 0.35)) if bool(st.get("slow", false)) else 1.0))
		if state == "ledge_hang" and test == "spiral":
			_jump_frames = 6  # climb up from a ledge hang, as a player would
		var jd := float(st.get("jump_dist", -1.0))
		if bool(st.get("auto_jump", false)):
			# Fix r1b: a skilled player times the hop to his speed (flight about 0.75 s for a single, so he leaves
			# when the target is about 0.62 x speed away). The fixed 2.6 m take-off overshot SP07 at a jog.
			var pv: Vector3 = p.get("velocity") if p.get("velocity") != null else Vector3(4.0, 0.0, 0.0)
			var hv := Vector2(pv.x, pv.z).length()
			jd = clampf(0.62 * hv + 0.3, 2.2, 3.4)
		if jd > 0.0 and not _jumped and dist < jd and _is_grounded(state):
			_jumped = true
			if bool(st.get("long", false)):
				# Long jump: crouch while running, then jump on the next frames.
				Input.action_press("crouch")
				_crouch_frames = 6
				_jump_delay = 2
			else:
				_jump_frames = 18
		if _jump_delay > 0:
			_jump_delay -= 1
			if _jump_delay == 0:
				_jump_frames = 14
		if _crouch_frames > 0:
			Input.action_press("crouch")
			_crouch_frames -= 1
			if _crouch_frames == 0:
				Input.action_release("crouch")
		if int(st.get("kick", 0)) > 0 and _jumped and state == "wall_slide":
			_jump_frames = 12
			st["kick"] = int(st["kick"]) - 1
		if _jump_frames > 0:
			if not Input.is_action_pressed("jump"):
				Input.action_press("jump")
			_jump_frames -= 1
			if _jump_frames == 0:
				Input.action_release("jump")
		if st.has("soft_t") and _step_t > float(st["soft_t"]):
			_next()  # a blocked approach is the expected outcome (locked book behind its rope ring)
			return
		if _step_t > 20.0:
			_finish("FAIL step %d timeout at %s state %s" % [_i, p.global_position, state])


var _chim_dir := 1.0
var _chim_kicks := 0
var _prev_state := ""


## Mastery chimney: run tangentially at fin B, jump, and kick back and forth between the fins until above
## the top balcony (y 9.7), then drift west onto it.
func _chimney(p: Node3D, state: String) -> void:
	var th := rad_to_deg(atan2(p.global_position.x, -p.global_position.z))
	th = fposmod(th, 360.0)
	var tang := Vector3(cos(deg_to_rad(th)), 0, sin(deg_to_rad(th)))
	if _is_grounded(state) and p.global_position.y > 9.6:
		_next()
		return
	if p.global_position.y > 10.2:
		_steer(p, -tang)
		return
	_steer(p, tang * _chim_dir)
	if not _jumped and _is_grounded(state) and _step_t > 0.25:
		_jumped = true
		_jump_frames = 16
	if state == "wall_slide" and _prev_state != "wall_slide":
		_jump_frames = 10
		_chim_kicks += 1
		_chim_dir = -_chim_dir
		print("[HubTest] wall kick %d at y=%.2f" % [_chim_kicks, p.global_position.y])
	_prev_state = state
	if _jump_frames > 0:
		if not Input.is_action_pressed("jump"):
			Input.action_press("jump")
		_jump_frames -= 1
		if _jump_frames == 0:
			Input.action_release("jump")
	if _jumped and _is_grounded(state) and _step_t > 1.0 and p.global_position.y < 5.0:
		_finish("FAIL chimney fell back to the gallery after %d kicks" % _chim_kicks)
	if _step_t > 12.0:
		_finish("FAIL chimney timeout")


func _is_grounded(state: String) -> bool:
	return state in ["idle", "walk", "run", "skid", "land", "crouch", "crawl", "turn"]


func _steer(p: Node3D, dir: Vector3) -> void:
	# `dir` may be shorter than 1 for a gentle walk.
	var yaw := 0.0
	if p.has_method("_camera_yaw"):
		yaw = float(p.call("_camera_yaw"))
	# The player now keeps a locked steering basis while the stick is held (player fix r1/r2); steer in that basis,
	# or a camera swing at spawn sends the bot the wrong way.
	if bool(p.get("_steer_locked")) and p.get("_steer_yaw") != null:
		yaw = float(p.get("_steer_yaw"))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var sx := dir.dot(right)
	var sy := dir.dot(fwd)
	if sx > 0.0:
		Input.action_press("move_right", sx)
	else:
		Input.action_press("move_left", -sx)
	if sy > 0.0:
		Input.action_press("move_forward", sy)
	else:
		Input.action_press("move_back", -sy)


func _release() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)


func _next() -> void:
	Input.action_release("jump")
	print("[HubTest] step %d complete at t=%.2f" % [_i, _t])
	_i += 1
	_step_t = 0.0
	_jumped = false
	_jump_frames = 0


func _finish(r: String) -> void:
	_done = true
	_release()
	Input.action_release("jump")
	Input.action_release("crouch")
	_result = r
	var p := _player()
	print("[HubTest] RESULT %s %s t=%.2f pos=%s events=%s" % [test, r, _t, p.global_position if p else Vector3.ZERO, _events])
	await get_tree().create_timer(4.0, true).timeout
	if not seq_tests.is_empty() and seq_i + 1 < seq_tests.size():
		seq_i += 1
		print("[HubTest] SEQ next %s" % seq_tests[seq_i])
		get_tree().reload_current_scene()
		return
	get_tree().quit()


func _seq_place() -> void:
	_done = true  # hold the route until Mak stands at the marker
	for k in 3:
		await get_tree().physics_frame
	var m := get_tree().current_scene.get_node_or_null("Spawns/" + _seq_spawn) as Node3D if get_tree().current_scene else null
	var p := _player()
	if m and p and p.has_method("respawn"):
		p.call("respawn", m.global_transform)
		print("[HubTest] SEQ %s placed at %s" % [test, _seq_spawn])
	else:
		print("[HubTest] SEQ %s: spawn %s not found" % [test, _seq_spawn])
	for k in 20:
		await get_tree().physics_frame
	_t = 0.0
	_step_t = 0.0
	_done = false


func dev_arg_fixed_pace() -> bool:
	var dev := get_node_or_null("/root/Dev")
	return dev != null and bool(dev.call("has_arg", "fixed-pace"))

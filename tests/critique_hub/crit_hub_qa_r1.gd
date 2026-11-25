extends Node
## CRITIC round 1, QA AND TECHNICAL lens, HUB (night 01). Test-only; no level uses it.
## The scene's root spawns a copy of this script under /root (so it survives the scene change), loads the real
## res://scenes/hub/Hub.tscn and then runs one QA mode against it with the real player controller and real input actions:
##   --qa=probe    static data and geometry probes: truffle ids, portals, spawn markers (embedded / floating),
##                 floor and ledge hole scans, wall containment rays, acorn placement, ledger, key collisions
##   --qa=exploit  scripted real-input attempts at the HUB-1 sequence: long jump baseline, plain single, inward-arc
##                 single round the lintel, and slow double jumps / side flips from the gallery up to cornice B
##   --qa=cub      wakes the impostor and reveals it, then parks Mak on the stair landing and logs whether the
##                 phase-2 cub walks into solid geometry
##   --qa=fps      windowed 1920x1080 frame-time sampling over gameplay positions and story cameras
##   --qa=fps12    the same with 12 truffles (storm preset, spiral, all locks open)
## Run: python tools/godot.py run res://tests/critique_hub/CritHubQaR1.tscn --seconds 900 -- --profile=crit_hub_qa_<mode> --qa=<mode> --qa_out=<abs dir>

const HUB := "res://scenes/hub/Hub.tscn"

var mode := "probe"
var out_dir := ""
var _started := false
var _wait := -1
var _player: Node3D
var _lines: PackedStringArray = []
var _done := false

# exploit trial runner
var _trials: Array = []
var _ti := -1
var _tf := 0
var _phase := ""
var _jump_hold := 0
var _crouch_hold := 0
var _jump_delay := 0
var _land_n := 0
var _was_grounded := true
var _max_y := -INF
var _states := {}
var _air_t := 0
var _shot_taken := false
var _results: Array = []
var _blocked_frames := 0

# fps sampler
var _fps_points: Array = []
var _fps_i := -1
var _fps_t := 0.0
var _fps_samples: Array = []
var _fps_gpu: Array = []
var _fps_cpu: Array = []
var _fps_report: Array = []

# cub watcher
var _cub_t := 0.0
var _cub_log: Array = []


func _ready() -> void:
	if not has_meta("driver"):
		var d := Node.new()
		d.set_meta("driver", true)
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		get_tree().change_scene_to_file.call_deferred(HUB)
		return
	process_priority = -100
	process_physics_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	mode = String(dev.call("arg", "qa", "probe")) if dev else "probe"
	out_dir = String(dev.call("arg", "qa_out", "")) if dev else ""
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	var g := get_node_or_null("/root/Game")
	if g:
		# Skip the first-boot cutscene so the scripted input starts at once (the intro is not under test here).
		var gd: Dictionary = g.get("data")
		var u: Dictionary = gd.get("unlocks", {})
		u["hub_intro_seen"] = true
		if mode == "fps12":
			var t: Dictionary = {}
			for w in ["W1", "W2"]:
				for i in range(1, 7):
					t["%s-%d" % [w, i]] = {"utc": ""}
					u["hub_seen_%s-%d" % [w, i]] = true
			gd["truffles"] = t
			u["hub_huff7_done"] = true
		gd["unlocks"] = u
	_log("[QA] mode=%s profile=%s" % [mode, String(g.get("profile")) if g else "?"])


func _log(s: String) -> void:
	print(s)
	_lines.append(s)


func _physics_process(delta: float) -> void:
	if not has_meta("driver") or _done:
		return
	var sc := get_tree().current_scene
	if sc == null or sc.name != "Hub":
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
		_wait = 150
		_log("[QA] hub loaded, player found")
	if _wait > 0:
		_wait -= 1
		return
	if not _started:
		_started = true
		match mode:
			"probe":
				_probe(sc)
				_finish()
			"exploit", "exploit2":
				_setup_trials()
				_next_trial()
			"cub":
				_cub_start(sc)
			"fps", "fps12":
				_fps_start(sc)
		return
	match mode:
		"exploit", "exploit2":
			_trial_step()
		"cub":
			_cub_step(sc, delta)


func _process(delta: float) -> void:
	if not has_meta("driver") or _done or not _started:
		return
	if mode == "fps" or mode == "fps12":
		_fps_step(delta)


func _finish() -> void:
	_done = true
	for a in ["move_left", "move_right", "move_forward", "move_back", "jump", "crouch", "attack"]:
		Input.action_release(a)
	_log("[QA] done")
	if out_dir != "":
		var f := FileAccess.open(out_dir.path_join("qa_%s.log" % mode), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_lines))
			f.close()
	await get_tree().create_timer(1.0, true).timeout
	get_tree().quit()


static func pp(r: float, th: float, y: float) -> Vector3:
	var t := deg_to_rad(th)
	return Vector3(r * sin(t), y, -r * cos(t))


static func theta_of(p: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(p.x, -p.z)), 360.0)


static func r_of(p: Vector3) -> float:
	return Vector2(p.x, p.z).length()


# ======================================================================= PROBE

func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return space.intersect_ray(q)


func _probe(sc: Node) -> void:
	var space := (sc as Node3D).get_world_3d().direct_space_state
	var level := sc.get_node_or_null("Level")
	# --- truffles
	var ids := {}
	for t in get_tree().get_nodes_in_group("truffle"):
		var id := String(t.get("truffle_id"))
		ids[id] = int(ids.get(id, 0)) + 1
		_log("[QA][truffle] id=%s pos=%s monitoring=%s ghost=%s" % [id, (t as Node3D).global_position, t.get("monitoring"), t.get("is_ghost")])
	for id in ids.keys():
		if int(ids[id]) > 1:
			_log("[QA][FAIL] duplicate truffle id %s x%d" % [id, ids[id]])
	# --- portals
	for p in get_tree().get_nodes_in_group("storybook_portal"):
		_log("[QA][portal] %s world=%s need=%s open=%s route_on_enter=%s pos=%s" % [p.name, p.get("world_id"), p.get("required_truffles"), p.get("is_open"), p.get("route_on_enter"), (p as Node3D).global_position])
	# --- spawn markers: floor under them and capsule overlap
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.25
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.collision_mask = 1
	for m in sc.get_node("Spawns").get_children():
		var o: Vector3 = (m as Node3D).global_position
		var hit := _ray(space, o + Vector3(0, 1.0, 0), o + Vector3(0, -3.0, 0))
		var fy: Variant = (hit["position"] as Vector3).y if not hit.is_empty() else null
		sq.transform = Transform3D(Basis(), o + Vector3(0, 0.625 + 0.08, 0))
		var over := space.intersect_shape(sq, 4)
		var names: Array = []
		for h in over:
			names.append(String((h["collider"] as Node).name))
		var flag := ""
		if fy == null:
			flag = " [FAIL no floor within 3 m]"
		elif absf(float(fy) - o.y) > 0.25:
			flag = " [WARN floor %.2f m off]" % (float(fy) - o.y)
		if not over.is_empty():
			flag += " [FAIL capsule overlaps %s]" % [names]
		_log("[QA][spawn] %s at %s floor_y=%s%s" % [m.name, o, fy, flag])
	# --- ground floor holes (rays from 0.3 m down; a ray starting inside a solid ignores it and finds the floor under it)
	var holes: Array = []
	var x := -16.0
	while x <= 16.0:
		var z := -16.0
		while z <= 16.0:
			if Vector2(x, z).length() <= 15.4:
				var h := _ray(space, Vector3(x, 0.3, z), Vector3(x, -2.0, z))
				if h.is_empty():
					holes.append(Vector2(x, z))
			z += 0.5
		x += 0.5
	_log("[QA][floor] ground-floor cells without floor collision: %d %s" % [holes.size(), holes.slice(0, 40)])
	# --- gallery ring (r 12.75-15.9, y 4.5)
	var ggaps: Array = []
	var th := 0.0
	while th < 360.0:
		for r in [12.8, 13.6, 14.4, 15.2, 15.85]:
			var a := pp(r, th, 4.8)
			var h2 := _ray(space, a, a + Vector3(0, -1.2, 0))
			if h2.is_empty():
				ggaps.append("%.0f/%.2f" % [th, r])
		th += 1.0
	_log("[QA][gallery] gallery points without floor: %d %s" % [ggaps.size(), ggaps.slice(0, 60)])
	# --- cornice and top balcony coverage
	for spec in [["cornice A", 100.5, 127.5, 8.5], ["cornice B", 148.5, 167.5, 8.5], ["top balcony", 172.5, 205.0, 9.7]]:
		var miss: Array = []
		var t2: float = spec[1]
		while t2 <= float(spec[2]):
			for r in [14.5, 15.2, 15.9]:
				var a2 := pp(r, t2, float(spec[3]) + 0.3)
				if _ray(space, a2, a2 + Vector3(0, -0.6, 0)).is_empty():
					miss.append("%.1f/%.1f" % [t2, r])
			t2 += 0.5
		_log("[QA][ledge] %s points without collision: %d %s" % [spec[0], miss.size(), miss.slice(0, 30)])
	# --- containment: rays outward from inside the hall at several heights
	for spec in [[0.7, 12.0], [2.0, 12.0], [5.3, 13.0], [6.8, 13.0], [9.0, 14.6], [10.4, 14.0], [12.5, 13.5]]:
		var leaks: Array = []
		var far: Array = []
		var t3 := 0.0
		while t3 < 360.0:
			var a3 := pp(float(spec[1]), t3, float(spec[0]))
			var b3 := pp(40.0, t3, float(spec[0]))
			var h3 := _ray(space, a3, b3)
			if h3.is_empty():
				leaks.append(int(t3))
			elif r_of(h3["position"]) > 17.6:
				far.append("%d:%.1f" % [int(t3), r_of(h3["position"])])
			t3 += 2.0
		_log("[QA][contain] y=%.1f from r=%.1f: no-hit=%d %s; hit beyond r17.6=%d %s" % [spec[0], spec[1], leaks.size(), leaks, far.size(), far.slice(0, 30)])
	# --- ceiling: can anything be stood on above y 14 (dome)?
	var up := _ray(space, Vector3(0.0, 9.5, 0.0), Vector3(0.0, 40.0, 0.0))
	_log("[QA][ceiling] centre ray up from 9.5 hits %s" % [up.get("position", "nothing")])
	# --- acorns
	var acorn_nodes: Array = []
	for n in sc.find_children("*", "Area3D", true, false):
		var scr: Script = n.get_script()
		if scr and String(scr.resource_path).ends_with("acorn.gd"):
			acorn_nodes.append(n)
	var floating := 0
	var buried := 0
	for a4 in acorn_nodes:
		var p4: Vector3 = (a4 as Node3D).global_position
		var dn := _ray(space, p4 + Vector3(0, 0.3, 0), p4 + Vector3(0, -12.0, 0))
		var gap := p4.y - ((dn["position"] as Vector3).y if not dn.is_empty() else -99.0)
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = p4 + Vector3(0, 0.25, 0)
		pq.collision_mask = 1
		var inside := space.intersect_point(pq, 1)
		var tag := ""
		if not inside.is_empty():
			buried += 1
			tag = " [FAIL inside %s]" % (inside[0]["collider"] as Node).name
		if gap > 2.2:
			floating += 1
			tag += " [NOTE %.1f m above the surface below]" % gap
		_log("[QA][acorn] %s/%s at %s gap=%.2f%s" % [(a4 as Node).get_parent().name, a4.name, p4, gap, tag])
	_log("[QA][acorn] total=%d inside_solid=%d high_above_surface=%d" % [acorn_nodes.size(), buried, floating])
	# --- ledger
	if level and level.has_method("ledger_total"):
		_log("[QA][ledger] count=%d total=%d" % [int(level.call("ledger_count")), int(level.call("ledger_total"))])
	# --- key solid props (ray at knee height toward their centres from 4 m)
	for spec in [["clock drum", Vector3(0, 0.5, 1.0)], ["globe", Vector3(-5.6, 0.5, -3.4)], ["old globe spot", Vector3(-4.8, 0.5, -3.8)], ["hat stand", Vector3(4.6, 0.5, 12.4)], ["ledger stand", Vector3(-4.6, 0.5, 12.6)], ["Bramwell", Vector3(2.4, 0.5, 8.4)], ["tea table", Vector3(-10.4, 0.4, 0.0)], ["desk", Vector3(8.0, 0.5, -2.0)]]:
		var c: Vector3 = spec[1]
		var from := c + Vector3(0, 0, 4.0)
		var h5 := _ray(space, from, c)
		_log("[QA][solid] %s: ray from +z 4 m %s" % [spec[0], ("hits %s at %.2f m" % [(h5["collider"] as Node).name, from.distance_to(h5["position"])]) if not h5.is_empty() else "MISSES (no collision)"])
	# --- the impostor and the activities
	var acts := level.get_node_or_null("Activities") if level else null
	if acts:
		_log("[QA][cub] state=%s" % acts.get("_cub_state"))
	_log("[QA][kill_y] %s" % sc.get("kill_y"))
	_log("[QA][monitors] objects=%d nodes=%d physics_active=%d" % [Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)])


# ======================================================================= EXPLOIT TRIALS

func _setup_trials() -> void:
	if mode == "exploit2":
		_setup_trials2()
		return
	# kind: long / single / arc / dbl / side
	_trials.append({"name": "long_jump_baseline", "kind": "long", "start": pp(15.2, 103.0, 8.55), "run_r": 15.2, "takeoff": 124.0, "land": pp(15.2, 152.0, 8.5)})
	# r1b: can Mak simply WALK across the HUB-1 gap along the wall cap (r 15.2-16)? The fixer's 02:14Z rerun had every jump
	# landing grounded at theta 135-143 r 15.6 y 8.5, i.e. inside the gap.
	for rl in [15.3, 15.5, 15.7]:
		_trials.append({"name": "walk_the_gap_wall_cap_r%.1f" % rl, "kind": "lip", "start": pp(rl, 124.0, 8.55), "run_r": rl})
	_trials.append({"name": "single_straight_r15.2", "kind": "single", "start": pp(15.2, 103.0, 8.55), "run_r": 15.2, "takeoff": 125.5, "land": pp(15.2, 152.0, 8.5)})
	_trials.append({"name": "single_straight_r14.6", "kind": "single", "start": pp(14.6, 103.0, 8.55), "run_r": 14.6, "takeoff": 126.5, "land": pp(14.8, 150.0, 8.5)})
	for rm in [13.9, 13.6, 13.3, 13.0]:
		_trials.append({"name": "single_inward_arc_mid_r%.1f" % rm, "kind": "arc", "start": pp(14.6, 103.0, 8.55), "run_r": 14.6, "takeoff": 126.8, "mid": pp(rm, 137.0, 8.5), "land": pp(14.9, 151.0, 8.5)})
	for rm2 in [13.6, 13.2]:
		_trials.append({"name": "single_inward_arc_dive_mid_r%.1f" % rm2, "kind": "arc", "dive": true, "start": pp(14.6, 103.0, 8.55), "run_r": 14.6, "takeoff": 126.8, "mid": pp(rm2, 137.0, 8.5), "land": pp(14.9, 151.0, 8.5)})
	# Gallery under cornice B (top 8.5, edge r 14.4, underside 8.2): slow chained double jump facing the wall.
	for spec in [[13.0, 0.45], [13.2, 0.45], [13.0, 0.7], [13.3, 0.3]]:
		_trials.append({"name": "gallery_double_to_corniceB_r%.1f_s%.2f" % [spec[0], spec[1]], "kind": "dbl", "start": pp(spec[0], 152.0, 4.55), "r0": spec[0], "stick": spec[1], "th_jump": 155.0})
	_trials.append({"name": "gallery_sideflip_to_corniceB", "kind": "side", "start": pp(13.6, 157.0, 4.55), "r0": 13.6})
	_trials.append({"name": "gallery_double_to_corniceA_r13.1", "kind": "dbl", "start": pp(13.1, 108.0, 4.55), "r0": 13.1, "stick": 0.45, "th_jump": 111.0})
	# Containment: walk (and hop) at the wall openings whose sides have no collision in the probe.
	_trials.append({"name": "escape_entrance_east_gap", "kind": "walk", "start": Vector3(1.55, 0.05, 14.3), "to": Vector3(1.55, 0.0, 24.0), "secs": 4.0})
	_trials.append({"name": "escape_entrance_west_gap", "kind": "walk", "start": Vector3(-1.55, 0.05, 14.3), "to": Vector3(-1.55, 0.0, 24.0), "secs": 4.0})
	_trials.append({"name": "escape_wolf_door_east_side", "kind": "walk", "start": Vector3(1.12, 4.55, -13.9), "to": Vector3(1.12, 4.5, -24.0), "secs": 4.0})
	_trials.append({"name": "escape_wolf_door_west_side", "kind": "walk", "start": Vector3(-1.12, 4.55, -13.9), "to": Vector3(-1.12, 4.5, -24.0), "secs": 4.0})
	_trials.append({"name": "escape_west_window1_hop", "kind": "walk", "start": pp(14.2, 250.0, 4.55), "to": pp(30.0, 250.0, 4.5), "secs": 4.0, "jump_at": 20})
	_trials.append({"name": "escape_west_window2_hop", "kind": "walk", "start": pp(14.2, 290.0, 4.55), "to": pp(30.0, 290.0, 4.5), "secs": 4.0, "jump_at": 20})
	# Spawn markers: does Mak settle where the marker says?
	for m in ["Default", "From_W1", "From_W2", "From_W3", "From_BOSS", "Balcony", "HUB-1", "Fireside", "Intro_Mark", "ChimneyFoot", "Test_Spiral"]:
		_trials.append({"name": "spawn_" + m, "kind": "spawn", "marker": m, "start": Vector3.ZERO})


func _setup_trials2() -> void:
	for rl in [14.9, 15.0, 15.1]:
		_trials.append({"name": "walk_the_gap_cap_lip_r%.1f" % rl, "kind": "lip", "start": pp(rl, 124.0, 8.55), "run_r": rl})
	_trials.append({"name": "single_straight_r15.2_repeat", "kind": "single", "snap": true, "start": pp(15.2, 103.0, 8.55), "run_r": 15.2, "takeoff": 125.5, "land": pp(15.2, 152.0, 8.5)})
	_trials.append({"name": "single_straight_r15.2_early_takeoff_121", "kind": "single", "snap": true, "start": pp(15.2, 103.0, 8.55), "run_r": 15.2, "takeoff": 121.0, "land": pp(15.2, 152.0, 8.5)})
	_trials.append({"name": "double_jump_attempt_from_cornice_A", "kind": "single", "start": pp(15.2, 101.0, 8.55), "run_r": 15.2, "takeoff": 104.0, "chain": true, "land": pp(15.2, 152.0, 8.5)})
	for spec in [[12.95, 0.25], [12.95, 0.35], [13.1, 0.25]]:
		_trials.append({"name": "gallery_hop_double_to_corniceB_r%.2f_s%.2f" % [spec[0], spec[1]], "kind": "dbl2", "start": pp(spec[0], 157.0, 4.55), "r0": spec[0], "stick": spec[1]})
	_trials.append({"name": "escape_west_window1_hop", "kind": "walk", "start": pp(14.2, 250.0, 4.55), "to": pp(30.0, 250.0, 4.5), "secs": 4.0, "jump_at": 20})
	_trials.append({"name": "escape_west_window2_hop", "kind": "walk", "start": pp(14.2, 290.0, 4.55), "to": pp(30.0, 290.0, 4.5), "secs": 4.0, "jump_at": 20})
	_trials.append({"name": "escape_wolf_door_east_side", "kind": "walk", "start": Vector3(1.12, 4.55, -13.9), "to": Vector3(1.12, 4.5, -24.0), "secs": 4.0})
	_trials.append({"name": "escape_wolf_door_west_side", "kind": "walk", "start": Vector3(-1.12, 4.55, -13.9), "to": Vector3(-1.12, 4.5, -24.0), "secs": 4.0})


func _next_trial() -> void:
	_release()
	_ti += 1
	if _ti >= _trials.size():
		_log("[QA] SUMMARY")
		for r in _results:
			_log("[QA][result] %s" % r)
		_finish()
		return
	var tr: Dictionary = _trials[_ti]
	var start: Vector3 = tr["start"]
	var face: Vector3
	if String(tr["kind"]) == "spawn":
		var mk := get_tree().current_scene.get_node_or_null("Spawns/" + String(tr["marker"])) as Node3D
		if mk == null:
			_results.append("%s -> marker missing" % tr["name"])
			_next_trial.call_deferred()
			return
		tr["start"] = mk.global_position
		_player.call("respawn", mk.global_transform)
		_tf = 0
		_phase = "spawn"
		_states = {}
		_max_y = -INF
		_log("[QA] trial %s at %s" % [tr["name"], mk.global_position])
		return
	match String(tr["kind"]):
		"walk":
			face = (tr["to"] as Vector3) - start
		"dbl":
			face = pp(13.0, theta_of(start) + 10.0, start.y) - start  # tangential, clockwise
		"side":
			face = -Vector3(start.x, 0, start.z)  # facing the hall
		"dbl2":
			face = Vector3(start.x, 0, start.z)  # facing the wall
		_:
			face = pp(float(tr["run_r"]), theta_of(start) + 8.0, start.y) - start
	face.y = 0.0
	var xf := Transform3D(Basis.looking_at(face.normalized(), Vector3.UP), start)
	_player.call("respawn", xf)
	if _player.has_method("reset_physics_interpolation"):
		_player.reset_physics_interpolation()
	_tf = 0
	_phase = "settle"
	_land_n = 0
	_max_y = -INF
	_states = {}
	_air_t = 0
	_jump_hold = 0
	_crouch_hold = 0
	_jump_delay = 0
	_shot_taken = false
	_log("[QA] trial %s start=%s" % [tr["name"], start])


func _state() -> String:
	return String(_player.call("get_state_name"))


func _grounded(s: String) -> bool:
	return s in ["idle", "walk", "run", "skid", "land", "crouch", "crawl", "turn", "slam_land", "slide_getup"]


func _release() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)


func _steer(dir: Vector3) -> void:
	var yaw := float(_player.call("_camera_yaw")) if _player.has_method("_camera_yaw") else 0.0
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


func _toward(target: Vector3, mag := 1.0) -> void:
	var d := target - _player.global_position
	d.y = 0.0
	if d.length() > 0.05:
		_steer(d.normalized() * mag)


func _press_jump(frames: int) -> void:
	_jump_hold = frames


func _tick_buttons() -> void:
	if _crouch_hold > 0:
		Input.action_press("crouch")
		_crouch_hold -= 1
		if _crouch_hold == 0:
			Input.action_release("crouch")
	if _jump_delay > 0:
		_jump_delay -= 1
		if _jump_delay == 0:
			_jump_hold = 14
	if _jump_hold > 0:
		if not Input.is_action_pressed("jump"):
			Input.action_press("jump")
		_jump_hold -= 1
		if _jump_hold == 0:
			Input.action_release("jump")


func _snap(tag: String) -> void:
	if _shot_taken or out_dir == "" or DisplayServer.get_name() == "headless":
		return
	_shot_taken = true
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(out_dir.path_join("%s__%s.png" % [Time.get_datetime_string_from_system(true).replace(":", "").replace("-", ""), tag]))


func _close_dialogs() -> bool:
	var ui := get_node_or_null("/root/UI")
	if ui == null or not ui.has_method("is_input_blocked") or not bool(ui.call("is_input_blocked")):
		return false
	var dlg: Node = ui.get("dialog")
	if dlg and dlg.has_method("is_open") and bool(dlg.call("is_open")):
		_log("[QA] dialog was open during trial %s: %s -> closing it" % [_trials[_ti]["name"] if _ti >= 0 and _ti < _trials.size() else "-", dlg.get("_lines")])
		dlg.call("close")
		return true
	_blocked_frames += 1
	if _blocked_frames == 120:
		var router := get_node_or_null("/root/Router")
		_log("[QA] input blocked for 2 s with no dialog open (router busy=%s)" % [router.get("busy") if router else "?"])
	return _blocked_frames < 600


func _trial_step() -> void:
	var tr: Dictionary = _trials[_ti]
	if _close_dialogs():
		return
	_tf += 1
	_release()
	var s := _state()
	var p := _player.global_position
	_states[s] = true
	_max_y = maxf(_max_y, p.y)
	var g := _grounded(s)
	if g and not _was_grounded:
		_land_n += 1
	_was_grounded = g
	if s == "ledge_hang" or s == "ledge_climb":
		_snap(String(tr["name"]) + "_ledge")
	var kind := String(tr["kind"])
	if _phase == "spawn":
		if _tf >= 50:
			var st0: Vector3 = tr["start"]
			var res0 := "%s -> settled at %s, moved %.2f m (dy %.2f), state %s" % [tr["name"], p, p.distance_to(st0), p.y - st0.y, s]
			_results.append(res0)
			_log("[QA] trial end: " + res0)
			_next_trial()
		return
	if kind == "walk" and _phase != "settle":
		if not tr.has("min_y"):
			tr["min_y"] = p.y
			tr["max_r"] = r_of(p)
			tr["max_dz"] = 0.0
		tr["min_y"] = minf(float(tr["min_y"]), p.y)
		tr["max_r"] = maxf(float(tr["max_r"]), r_of(p))
		tr["max_dz"] = maxf(float(tr["max_dz"]), absf(p.z - (tr["start"] as Vector3).z))
		_toward(tr["to"])
		if _tf == int(tr.get("jump_at", -1)):
			_press_jump(18)
		_tick_buttons()
		if _tf > int(float(tr["secs"]) * 60.0):
			var esc := float(tr["min_y"]) < -1.0 or float(tr["max_r"]) > 17.3
			var res1 := "%s -> %s: final %s, min_y %.2f, max_r %.2f, max |dz| %.2f, states %s, tree_paused %s" % [tr["name"], "ESCAPED THE HALL" if esc else "contained", p, tr["min_y"], tr["max_r"], tr["max_dz"], _states.keys(), get_tree().paused]
			_results.append(res1)
			_log("[QA] trial end: " + res1)
			_next_trial()
		return
	if _phase == "settle":
		if _tf > 20:
			_phase = "run"
			_tf = 0
		_tick_buttons()
		return
	if _phase == "run":
		match kind:
			"long", "single", "arc":
				var th := theta_of(p)
				_toward(pp(float(tr["run_r"]), th + 6.0, p.y))
				if th >= float(tr["takeoff"]) and g:
					_phase = "air"
					_air_t = 0
					if kind == "long":
						_crouch_hold = 6
						_jump_delay = 2
					else:
						_press_jump(18)
			"dbl":
				var th2 := theta_of(p)
				_toward(pp(float(tr["r0"]), th2 + 6.0, p.y), float(tr["stick"]))
				if th2 >= float(tr["th_jump"]) and g:
					_press_jump(8)
					_phase = "dbl_wait_land"
					_air_t = 0
			"lip":
				var thl := theta_of(p)
				_toward(pp(float(tr["run_r"]), thl + 4.0, p.y), 0.45)
				if p.y < 7.5:
					_end_trial(p, s)
					return
				if thl > 150.0 and g:
					_end_trial(p, s)
					return
			"dbl2":
				_steer(Vector3(p.x, 0, p.z).normalized() * float(tr["stick"]))
				if _tf == 6:
					_press_jump(6)
				if _tf > 10 and not g:
					_phase = "dbl_wait_land2"
					_air_t = 0
			"side":
				# step toward the hall, then flick the stick at the wall and jump (side flip)
				_toward(Vector3(0, p.y, 0))
				if _tf > 12 and g:
					_phase = "side_flick"
					_tf = 0
		_tick_buttons()
		_check_timeout()
		return
	if _phase == "side_flick":
		_steer(Vector3(p.x, 0, p.z).normalized())
		if _tf == 2:
			_press_jump(16)
		if _tf > 4 and not g:
			_phase = "air"
			_air_t = 0
		_tick_buttons()
		_check_timeout()
		return
	if _phase == "dbl_wait_land2":
		_air_t += 1
		_steer(Vector3(p.x, 0, p.z).normalized() * float(tr["stick"]))
		if g:
			_press_jump(16)
			_phase = "air"
			_air_t = 0
		_tick_buttons()
		_check_timeout()
		return
	if _phase == "dbl_wait_land":
		_air_t += 1
		_toward(pp(float(tr["r0"]), theta_of(p) + 6.0, p.y), float(tr["stick"]))
		if g and _air_t > 6:
			# chained double jump with the stick at the wall (outward)
			_steer(Vector3(p.x, 0, p.z).normalized() * 0.9)
			_press_jump(16)
			_phase = "air"
			_air_t = 0
		_tick_buttons()
		_check_timeout()
		return
	if _phase == "air":
		_air_t += 1
		match kind:
			"arc":
				var vy := (_player.get("velocity") as Vector3).y if _player.get("velocity") != null else 0.0
				if _air_t < 4 or vy > 0.0:
					_toward(tr["mid"])
				else:
					_toward(tr["land"])
				if bool(tr.get("dive", false)) and _air_t == 26:
					Input.action_press("attack")
				elif _air_t == 28:
					Input.action_release("attack")
			"long", "single":
				_toward(tr["land"])
				if bool(tr.get("chain", false)) and g and _air_t > 6 and not tr.has("chained"):
					tr["chained"] = true
					_press_jump(18)
					_air_t = 0
			"dbl", "side", "dbl2":
				# drift to just inside the cornice edge (axis r 13.95) and keep facing the wall
				var rr := r_of(p)
				if rr < 13.95:
					_steer(Vector3(p.x, 0, p.z).normalized() * 0.8)
		if s == "ledge_hang":
			# climb up like a player would
			_steer(Vector3(p.x, 0, p.z).normalized())
		if _air_t > 10 and (g or s == "pole_climb") and not (bool(tr.get("chain", false)) and not tr.has("chained")):
			_end_trial(p, s)
			return
		_tick_buttons()
		_check_timeout()


func _check_timeout() -> void:
	if _tf > 60 * 20 or _air_t > 60 * 8:
		_end_trial(_player.global_position, _state())


func _end_trial(p: Vector3, s: String) -> void:
	var tr: Dictionary = _trials[_ti]
	var th := theta_of(p)
	var where := "gallery/floor"
	if p.y > 9.5:
		where = "TOP BALCONY"
	elif p.y > 8.3:
		where = "CORNICE B" if th > 146.0 and th < 170.0 else ("cornice A" if th >= 98.0 and th <= 129.0 else "upper ledge")
	var ledge := _states.has("ledge_hang") or _states.has("ledge_climb")
	var res := "%s -> %s at theta %.1f r %.2f y %.2f (max_y %.2f, ledge_grab=%s, states=%s, tree_paused=%s)" % [tr["name"], where, th, r_of(p), p.y, _max_y, ledge, _states.keys(), get_tree().paused]
	if bool(tr.get("snap", false)) or where != "gallery/floor":
		_shot_taken = false
		_snap(String(tr["name"]) + "_landing")
	_results.append(res)
	_log("[QA] trial end: " + res)
	_next_trial()


# ======================================================================= CUB

func _cub_start(sc: Node) -> void:
	var acts := sc.get_node_or_null("Level/Activities")
	if acts == null:
		_log("[QA][FAIL] no Activities node")
		_finish()
		return
	_log("[QA][cub] initial state=%s" % acts.get("_cub_state"))
	# Walk-in wake: teleport 6.9 m from Book 1, then walk at it.
	_player.call("respawn", Transform3D(Basis.looking_at(Vector3(-7.07, 0, 7.07) - Vector3(-1.0, 0, 10.4), Vector3.UP), Vector3(-1.0, 0.05, 10.4)))
	_phase = "approach"
	_cub_t = 0.0


func _cub_step(sc: Node, delta: float) -> void:
	var acts := sc.get_node_or_null("Level/Activities")
	if acts == null:
		_finish()
		return
	_release()
	_cub_t += delta
	var st := String(acts.get("_cub_state"))
	var cub := acts.get("_cub") as Node3D
	var p := _player.global_position
	match _phase:
		"approach":
			_toward(Vector3(-7.07, 0, 7.07), 0.5)
			if st != "rug":
				_log("[QA][cub] woke at t=%.2f state=%s, Mak at %s (%.2f m from Book 1)" % [_cub_t, st, p, Vector2(p.x + 7.07, p.z - 7.07).length()])
				_phase = "try_book"
				_cub_t = 0.0
		"try_book":
			# Land on Book 1's pages while the impostor holds the bookmark (R3.2 test 1).
			_toward(Vector3(-7.07, 0, 7.07), 1.0)
			if _cub_t > 0.2 and _cub_t < 0.25:
				_press_jump(14)
			var b1 := sc.get_node_or_null("Level/Book_W1")
			if b1 and _cub_t > 0.3 and _cub_t < 2.6 and not has_meta("b1hooked"):
				set_meta("b1hooked", true)
				b1.connect("entered", func(w: String) -> void: _log("[QA][cub] Book_W1 'entered' fired during the chase (world %s, route_on_enter=%s) at t=%.2f" % [w, b1.get("route_on_enter"), _cub_t]))
			if _cub_t > 3.0:
				_log("[QA][cub] after page attempt: Mak at %s state=%s" % [p, _state()])
				if st == "run":
					acts.call("cub_hit", "punch")  # shortcut to phase 2 (real-input catches are covered by the builder's cub replay)
					_log("[QA][cub] forced reveal; state now %s" % acts.get("_cub_state"))
				_player.call("respawn", Transform3D(Basis(), Vector3(0.0, 2.3, -8.25)))  # stair landing
				_phase = "watch"
				_cub_t = 0.0
		"watch":
			if cub and is_instance_valid(cub):
				var space := (sc as Node3D).get_world_3d().direct_space_state
				var pq := PhysicsPointQueryParameters3D.new()
				pq.position = cub.global_position + Vector3(0, 0.5, 0)
				pq.collision_mask = 1
				var inside := space.intersect_point(pq, 1)
				if not inside.is_empty() or int(_cub_t * 4.0) % 4 == 0:
					var e := "[QA][cub] t=%.2f state=%s cub=%s %s" % [_cub_t, st, cub.global_position, ("INSIDE " + String((inside[0]["collider"] as Node).name)) if not inside.is_empty() else ""]
					if _cub_log.size() == 0 or _cub_log[-1] != e:
						_cub_log.append(e)
						_log(e)
			if _cub_t > 24.0:
				_finish()
	_tick_buttons()


# ======================================================================= FPS

func _fps_start(sc: Node) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_log("[QA][fps] window=%s viewport=%s vsync=%d max_fps=%d" % [DisplayServer.window_get_size(), get_viewport().get_visible_rect().size, DisplayServer.window_get_vsync_mode(), Engine.max_fps])
	_fps_points = [
		["spawn_default", Vector3(0, 0.05, 11.5), Vector3(0, 0, 0), ""],
		["intro_mark_look_north", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), ""],
		["book1_side", Vector3(-4.0, 0.05, 9.0), Vector3(-7, 0, 7), ""],
		["fireside", Vector3(-10.5, 0.05, 1.8), Vector3(0, 0, 0), ""],
		["nook", Vector3(-3.0, 0.05, -10.6), Vector3(0, 0, -11.8), ""],
		["gallery_east", pp(13.4, 80.0, 4.55), Vector3(0, 4.5, 0), ""],
		["cornice_a", pp(15.2, 115.0, 8.55), pp(15.2, 140.0, 8.5), ""],
		["top_balcony", pp(14.6, 186.0, 9.75), Vector3(0, 5, 0), ""],
		["cam_A_v3", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "StoryCam_A_v3"],
		["cam_B", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "StoryCam_B"],
		["cam_E", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "StoryCam_E"],
		["cam_H", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "StoryCam_H"],
		["TitleCam", Vector3(-0.4, 0.05, 9.0), Vector3(0, 0, -10), "TitleCam"],
	]
	_fps_i = -1
	_fps_next(sc)


func _fps_next(sc: Node) -> void:
	if _fps_i >= 0:
		_fps_summarise()
	_fps_i += 1
	if _fps_i >= _fps_points.size():
		_log("[QA][fps] SUMMARY")
		for r in _fps_report:
			_log("[QA][fps] " + String(r))
		_finish()
		return
	var pt: Array = _fps_points[_fps_i]
	var pos: Vector3 = pt[1]
	var look: Vector3 = pt[2] - pos
	look.y = 0.0
	_player.call("respawn", Transform3D(Basis.looking_at(look.normalized(), Vector3.UP), pos))
	var cam_name := String(pt[3])
	if cam_name != "":
		var c := sc.get_node_or_null("StoryCams/" + cam_name) as Camera3D
		if c:
			c.make_current()
	else:
		var rig := _player.get("camera_rig") as Node
		if rig:
			var rc := rig.get_node_or_null("Camera3D") as Camera3D
			if rc:
				rc.make_current()
			if rig.has_method("snap_behind"):
				rig.call("snap_behind")
	_fps_t = 0.0
	_fps_samples.clear()
	_fps_gpu.clear()
	_fps_cpu.clear()


func _fps_step(delta: float) -> void:
	var sc := get_tree().current_scene
	_fps_t += delta
	if _fps_t > 1.5:  # settle, then sample 4 s
		_fps_samples.append(delta)
		var rid := get_viewport().get_viewport_rid()
		_fps_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		_fps_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu())
	if _fps_t > 5.5:
		if _fps_i == 0 or _fps_i == 8:
			_snap_fps(String(_fps_points[_fps_i][0]))
		_fps_next(sc)


func _snap_fps(tag: String) -> void:
	if out_dir == "":
		return
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(out_dir.path_join("%s__fps_%s_%s.png" % [Time.get_datetime_string_from_system(true).replace(":", "").replace("-", ""), mode, tag]))


func _pct(arr: Array, q: float) -> float:
	if arr.is_empty():
		return 0.0
	var s := arr.duplicate()
	s.sort()
	return float(s[clampi(int(q * float(s.size() - 1)), 0, s.size() - 1)])


func _fps_summarise() -> void:
	var pt: Array = _fps_points[_fps_i]
	var n := _fps_samples.size()
	if n == 0:
		return
	var tot := 0.0
	for d in _fps_samples:
		tot += float(d)
	var avg_fps := float(n) / tot
	var worst := _pct(_fps_samples, 0.99)
	var below60 := 0
	for d in _fps_samples:
		if float(d) > 1.0 / 58.0:
			below60 += 1
	var r := "%s: avg %.1f fps, p99 frame %.1f ms (%.1f fps), frames over 17.2 ms %d/%d, GPU median %.2f ms p95 %.2f ms, CPU median %.2f ms p95 %.2f ms, draw calls %d, primitives %d" % [
		pt[0], avg_fps, worst * 1000.0, 1.0 / maxf(worst, 0.0001), below60, n, _pct(_fps_gpu, 0.5), _pct(_fps_gpu, 0.95), _pct(_fps_cpu, 0.5), _pct(_fps_cpu, 0.95),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
	_fps_report.append(r)
	_log("[QA][fps] " + r)

extends Node
## Critique W1 round 1, QA and technical lens. Lives under /root while W1 is the current scene.
## Phases: static audit (truffle ids, spawns, cams, enemies, ground holes, embedded pickups) -> spawn drop tests ->
## fps at 1920x1080 (gameplay camera at every spawn, then StoryCams A-D) -> real-input punch test on every
## Woolly Wolf -> W1-1 reward -> W1-3 rope-bridge skip (real movement) -> cross-visit pages check -> enemy drift ->
## JSON report under --qa-out, then quit. It never edits the world's files; it only moves the player and drives input.

const CAPSULE_R := 0.35
const CAPSULE_H := 1.25

var out_dir := ""
var world: Node3D
var level: Node3D
var player: CharacterBody3D
var inp: Object
var stick := Vector2.ZERO
var report := {}
var damage_log: Array = []
var truffle_log: Array = []
var _bucket: PackedFloat32Array = PackedFloat32Array()
var _measuring := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("qa-out", OS.get_user_data_dir().path_join("w1_qa")) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _process(delta: float) -> void:
	if _measuring:
		_bucket.append(delta)


func _physics_process(_d: float) -> void:
	if inp:
		inp.set("_r_stick", stick)


func log_line(s: String) -> void:
	print("[W1QA] " + s)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
	while get_tree().paused:
		await get_tree().process_frame


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and String(cs.get("world_id")) == "W1" and get_tree().get_first_node_in_group("player") != null and cs.get_node_or_null("Level") != null:
			world = cs as Node3D
			level = cs.get_node("Level") as Node3D
			player = get_tree().get_first_node_in_group("player") as CharacterBody3D
			break
		if Time.get_ticks_msec() - t0 > 180000:
			log_line("TIMEOUT waiting for W1")
			get_tree().quit(2)
			return
	report["load_ms"] = Time.get_ticks_msec() - t0
	var game := get_node_or_null("/root/Game")
	if game:
		game.damaged.connect(func(a: int) -> void: damage_log.append({"amount": a, "pos": _v(player.global_position), "phase": report.get("_phase", "")}))
		game.truffle_collected.connect(func(id: String) -> void: truffle_log.append({"id": id, "phase": report.get("_phase", "")}))
	await _wait(2.5)
	inp = player.get("inp")
	if inp:
		inp.call("setup", {"steer": "world", "events": []}, 0.2, 1.0)
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1920, 1080)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(1.0)
	report["viewport"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	report["window"] = [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	report["gpu"] = RenderingServer.get_video_adapter_name()
	var phases := ["audit", "spawns", "fps", "punch", "siege", "skip_w1_3", "pages", "drift", "acorn2", "hay", "holes"]
	var only := String(get_node("/root/Dev").call("arg", "qa-phases", "")) if get_node_or_null("/root/Dev") else ""
	for ph in phases:
		if only != "" and not (ph in only.split(",")):
			continue
		report["_phase"] = ph
		log_line("phase " + ph)
		await Callable(self, "_ph_" + ph).call()
		_write()
	report["damage_log"] = damage_log
	report["truffle_log"] = truffle_log
	_write()
	log_line("report written " + out_dir.path_join("w1_qa_probe.json"))
	get_tree().quit()


func _write() -> void:
	var f := FileAccess.open(out_dir.path_join("w1_qa_probe.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()


# ------------------------------------------------------------------ helpers

func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _space() -> PhysicsDirectSpaceState3D:
	return world.get_world_3d().direct_space_state


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [player.get_rid()]
	return _space().intersect_ray(q)


func _ground(p: Vector3, up := 0.6, down := 8.0) -> Dictionary:
	var hit := _ray(p + Vector3(0, up, 0), p - Vector3(0, down, 0))
	if hit.is_empty():
		return {}
	return {"y": snappedf((hit["position"] as Vector3).y, 0.01), "gap": snappedf(p.y - (hit["position"] as Vector3).y, 0.01), "by": _rel(hit["collider"])}


func _rel(n: Variant) -> String:
	if n == null or not (n is Node):
		return "?"
	return str((n as Node).get_path()).replace(str(world.get_path()), "")


func _overlap(p: Vector3, r: float) -> Array:
	var s := SphereShape3D.new()
	s.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = s
	q.transform = Transform3D(Basis(), p)
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	var out: Array = []
	for r2 in _space().intersect_shape(q, 4):
		out.append(_rel(r2["collider"]))
	return out


func _embedded_capsule(p: Vector3) -> Array:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_R * 0.9
	shape.height = CAPSULE_H * 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), p + Vector3(0, CAPSULE_H * 0.5 + 0.08, 0))
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	var names: Array = []
	for r in _space().intersect_shape(q, 4):
		names.append(_rel(r["collider"]))
	return names


func _stats(name_: String, frames: PackedFloat32Array) -> Dictionary:
	if frames.size() < 2:
		return {"name": name_, "frames": frames.size()}
	var arr := Array(frames)
	arr.sort()
	var sum := 0.0
	var over := 0
	for d in arr:
		sum += d
		if d > 1.0 / 60.0 + 0.0005:
			over += 1
	var mean := sum / arr.size()
	var p99: float = arr[int(floor(arr.size() * 0.99)) - 1]
	var mx: float = arr[arr.size() - 1]
	return {"name": name_, "frames": arr.size(), "mean_fps": snappedf(1.0 / mean, 0.1), "p99_ms": snappedf(p99 * 1000.0, 0.01),
		"low1_fps": snappedf(1.0 / p99, 0.1), "worst_ms": snappedf(mx * 1000.0, 0.01), "pct_over_16_7ms": snappedf(100.0 * over / arr.size(), 0.1),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01)}


func _measure(name_: String, sec: float) -> Dictionary:
	_bucket = PackedFloat32Array()
	_measuring = true
	await _wait(sec)
	_measuring = false
	var s := _stats(name_, _bucket)
	log_line("fps %s %s" % [name_, JSON.stringify(s)])
	return s


func _tp(pos: Vector3, yaw_deg := 0.0) -> void:
	stick = Vector2.ZERO
	player.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos + Vector3(0, 0.05, 0)))
	await _frames(10)


func _hold(action: String, n: int) -> void:
	var hf: Dictionary = inp.get("_hold_frames")
	hf[action] = n


func _steer(t: Vector3, mag := 1.0) -> float:
	var d := t - player.global_position
	d.y = 0.0
	if d.length() < 0.01:
		stick = Vector2.ZERO
		return 0.0
	stick = Vector2(d.x, -d.z).normalized() * mag
	return d.length()


func _go(t: Vector3, tol := 0.35, timeout := 10.0) -> bool:
	for f in int(timeout * 60.0):
		var d := _steer(t)
		if d < tol:
			stick = Vector2.ZERO
			return true
		if d < 1.2:
			stick *= clampf(d / 1.2, 0.35, 1.0)
		await _frames(1)
	stick = Vector2.ZERO
	return false


func _set_ai(on: bool) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if "ai_enabled" in e:
			e.set("ai_enabled", on)


func _has(id: String) -> bool:
	var g := get_node_or_null("/root/Game")
	return g != null and bool(g.call("has_truffle", id))


# ------------------------------------------------------------------ phases

func _ph_audit() -> void:
	var a := {}
	a["kill_y"] = world.get("kill_y")
	var spawns: Dictionary = {}
	var sp := world.get_node_or_null("Spawns")
	if sp:
		for m in sp.get_children():
			if m is Node3D:
				var p := (m as Node3D).global_position
				spawns[str(m.name)] = {"pos": _v(p), "ground": _ground(p), "embedded": _embedded_capsule(p)}
	a["spawns"] = spawns
	var cams: Array = []
	var sc := world.get_node_or_null("StoryCams")
	if sc:
		for c in sc.get_children():
			cams.append(str(c.name))
	a["storycams"] = cams
	# Truffles and reward spawners.
	var tr: Array = []
	var ids: Dictionary = {}
	for n in world.find_children("*", "", true, false):
		if "truffle_id" in n and String(n.get("truffle_id")) != "":
			var id := String(n.get("truffle_id"))
			var p := (n as Node3D).global_position
			tr.append({"kind": "truffle", "id": id, "path": _rel(n), "pos": _v(p), "visible": (n as Node3D).is_visible_in_tree(), "ground": _ground(p, 0.2, 30.0), "embedded": _overlap(p + Vector3(0, 0.3, 0), 0.2)})
			ids[id] = int(ids.get(id, 0)) + 1
		elif "reward_truffle_id" in n and String(n.get("reward_truffle_id")) != "":
			var p2 := (n as Node3D).global_position
			if n.has_method("reward_marker"):
				p2 = (n.call("reward_marker") as Node3D).global_position
			tr.append({"kind": "spawner", "id": String(n.get("reward_truffle_id")), "path": _rel(n), "marker": _v(p2), "script": (n.get_script() as Script).get_global_name() if n.get_script() else ""})
	a["truffles"] = tr
	a["live_truffle_id_counts"] = ids
	# Enemies.
	var en: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not world.is_ancestor_of(e):
			continue
		var p3 := (e as Node3D).global_position
		var glbs := 0
		var meshes := 0
		for c in (e as Node).find_children("*", "", true, false):
			if c is MeshInstance3D:
				meshes += 1
			if c.scene_file_path.ends_with(".glb"):
				glbs += 1
		var hb: Variant = e.get("hurtbox") if "hurtbox" in e else null
		en.append({"name": str(e.name), "script": (e.get_script() as Script).get_global_name() if e.get_script() else "", "pos": _v(p3),
			"hp": e.get("hp") if "hp" in e else null, "has_hit_api": e.has_method("hit_by_player"), "glb_instances": glbs, "meshes": meshes,
			"mesh_path": e.get("mesh_path") if "mesh_path" in e else "", "hurtbox_layer": (hb as CollisionObject3D).collision_layer if hb is CollisionObject3D else -1,
			"ground": _ground(p3, 1.0, 30.0), "state": e.get("state") if "state" in e else ""})
	a["enemies"] = en
	# Characters that are not enemies (NPCs, sheep): do they carry a generated model?
	var npcs: Array = []
	for nm in ["Pip", "Hazel", "Bertram"]:
		var n2 := level.get_node_or_null(nm)
		if n2:
			var g2 := 0
			for c in n2.find_children("*", "", true, false):
				if c.scene_file_path.ends_with(".glb"):
					g2 += 1
			npcs.append({"name": nm, "glb_instances": g2, "pos": _v((n2 as Node3D).global_position)})
	a["npcs"] = npcs
	# Ground holes: vertical rays over the whole square.
	var holes: Array = []
	var low: Array = []
	var cells := 0
	var x := -66.0
	while x <= 66.0:
		var z := -66.0
		while z <= 66.0:
			cells += 1
			var hit := _ray(Vector3(x, 90, z), Vector3(x, -40, z))
			if hit.is_empty():
				holes.append([x, z])
			elif (hit["position"] as Vector3).y < -1.2:
				low.append([x, z, snappedf((hit["position"] as Vector3).y, 0.01), _rel(hit["collider"])])
			z += 2.0
		x += 2.0
	a["ground_cells"] = cells
	a["ground_holes"] = holes
	a["ground_below_-1.2"] = low
	# Pickups embedded in world geometry or floating far above any surface.
	var acorns: Array = []
	var emb: Array = []
	var floating: Array = []
	for n3 in get_tree().get_nodes_in_group("acorn"):
		if not world.is_ancestor_of(n3):
			continue
		var p4 := (n3 as Node3D).global_position
		acorns.append(p4)
		var o := _overlap(p4 + Vector3(0, 0.25, 0), 0.12)
		if not o.is_empty():
			emb.append({"path": _rel(n3), "pos": _v(p4), "in": o})
		var gr := _ground(p4, 0.1, 40.0)
		if gr.is_empty() or float(gr["gap"]) > 6.0:
			floating.append({"path": _rel(n3), "pos": _v(p4), "ground": gr})
	a["acorns_loose"] = acorns.size()
	a["acorns_embedded"] = emb
	a["acorns_high_above_ground"] = floating
	var crates: Array = []
	var crate_total := 0
	for n4 in world.find_children("*", "", true, false):
		if "acorns" in n4 and n4.get_script() and (n4.get_script() as Script).get_global_name() == "BreakableCrate":
			crates.append({"path": _rel(n4), "acorns": n4.get("acorns"), "pos": _v((n4 as Node3D).global_position)})
			crate_total += int(n4.get("acorns"))
	a["crates"] = crates
	a["crate_acorns"] = crate_total
	var pages: Array = []
	for i in range(1, 6):
		var pg := level.get_node_or_null("Page_P%d" % i) as Node3D
		if pg:
			var hp := pg.global_position + Vector3(0, float(pg.get("hover_height")), 0)
			pages.append({"id": "P%d" % i, "index": pg.get("page_index"), "pos": _v(hp), "embedded": _overlap(hp, 0.2), "ground": _ground(hp, 0.1, 30.0), "monitoring": pg.get("monitoring"), "visible": pg.is_visible_in_tree()})
	a["pages"] = pages
	var game := get_node_or_null("/root/Game")
	if game:
		a["game_page_count_W1_at_load"] = game.call("page_count", "W1")
		a["truffles_owned_at_load"] = game.call("truffle_count")
	var lps := level.get_node_or_null("LostPageSet_W1-5")
	if lps:
		a["lost_page_set_found_at_load"] = (lps.get("found") as Dictionary).size()
	var hy := level.get_node_or_null("HayYard_W1-7")
	if hy:
		a["hay_yard_seed_note"] = "w1_hayyard.gd seeds its RNG with --seed or 7: same shuffle every play"
	report["audit"] = a
	log_line("audit: %d truffle nodes, %d enemies, %d holes, %d embedded acorns" % [tr.size(), en.size(), holes.size(), emb.size()])


func _ph_spawns() -> void:
	_set_ai(false)
	var out: Array = []
	var pts: Array = []
	var sp := world.get_node_or_null("Spawns")
	if sp:
		for m in sp.get_children():
			if m is Node3D:
				pts.append(["spawn:" + str(m.name), (m as Node3D).global_position])
	for c in level.get_children():
		if str(c.name).begins_with("CP") and c is Node3D:
			pts.append(["checkpoint:" + str(c.name), (c as Node3D).global_position + Vector3(1.2, 0.2, 0)])
	for pr in pts:
		var p: Vector3 = pr[1]
		await _tp(p)
		await _wait(1.2)
		var fp := player.global_position
		out.append({"name": pr[0], "at": _v(p), "after_1_2s": _v(fp), "dy": snappedf(fp.y - p.y, 0.01), "on_floor": player.is_on_floor(), "state": player.call("get_state_name")})
	report["spawn_drops"] = out
	_set_ai(true)


func _ph_fps() -> void:
	var res: Array = []
	var sp := world.get_node_or_null("Spawns")
	var names := ["Default", "W1-1", "W1-2", "W1-3", "W1-4", "W1-6", "W1-7"]
	for nm in names:
		var m := sp.get_node_or_null(nm) as Node3D if sp else null
		if m == null:
			continue
		var yaw := rad_to_deg(m.global_transform.basis.get_euler().y)
		await _tp(m.global_position, yaw)
		await _wait(1.5)
		res.append(await _measure("gameplay@" + nm, 6.0))
	# A full turn of the camera at the hero spawn (worst direction).
	var prev := get_viewport().get_camera_3d()
	var sc := world.get_node_or_null("StoryCams")
	for cn in ["StoryCam_A", "StoryCam_B", "StoryCam_C", "StoryCam_D"]:
		var c := sc.get_node_or_null(cn) as Camera3D if sc else null
		if c == null:
			continue
		c.current = true
		await _wait(1.0)
		res.append(await _measure("story@" + cn, 4.0))
	if is_instance_valid(prev):
		prev.current = true
	report["fps"] = res


func _ph_punch() -> void:
	# Real input: stand 1.0 m from each Woolly Wolf, face it, tap attack (punch), see whether a hit lands.
	_set_ai(false)
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not world.is_ancestor_of(e) or not (e.get_script() and (e.get_script() as Script).get_global_name() == "WoollyWolf"):
			continue
		if not str(e.name).begins_with("WW"):
			continue
		var w := e as Node3D
		var hits: Array = []
		var cb := func(kind: String, landed: bool) -> void: hits.append([kind, landed])
		if e.has_signal("hit_taken"):
			e.connect("hit_taken", cb)
		var hp0: int = int(e.get("hp"))
		var wp := w.global_position
		var row := {"name": str(e.name), "pos": _v(wp), "hp0": hp0}
		for k in 3:
			if bool(e.get("is_defeated")):
				break
			wp = w.global_position
			var dirs := [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, -1)]
			var placed := false
			for d in dirs:
				var at: Vector3 = wp + d * 1.05
				var g := _ground(at + Vector3(0, 2.0, 0), 0.0, 6.0)
				if g.is_empty():
					continue
				at.y = float(g["y"])
				if not _embedded_capsule(at).is_empty():
					continue
				var face := (wp - at).normalized()
				await _tp(at, rad_to_deg(atan2(-face.x, -face.z)))
				placed = true
				break
			if not placed:
				row["note"] = "no free spot next to it"
				break
			_steer(wp, 0.2)
			await _frames(3)
			stick = Vector2.ZERO
			_hold("attack", 1)
			await _frames(40)
		row["hits"] = hits
		row["hp_after"] = e.get("hp")
		row["defeated"] = e.get("is_defeated")
		row["state_after"] = e.get("state")
		row["landed_any"] = hits.any(func(h: Array) -> bool: return bool(h[1]))
		out.append(row)
		if e.has_signal("hit_taken") and e.is_connected("hit_taken", cb):
			e.disconnect("hit_taken", cb)
	report["punch"] = out
	_set_ai(true)


func _ph_siege() -> void:
	# Finish any siege wolf that is still standing through the enemy API, then watch for the W1-1 reward.
	var r := {}
	for id in ["WW1", "WW2", "WW3", "WW4"]:
		var w := level.get_node_or_null(id)
		if w == null or not is_instance_valid(w):
			r[id] = "gone"
			continue
		var n := 0
		while not bool(w.get("is_defeated")) and n < 8:
			w.call("hit_by_player", "stomp", (w as Node3D).global_position + Vector3(0, 1.5, 0))
			n += 1
			await _frames(30)
		r[id] = "defeated after %d API stomps" % n if bool(w.get("is_defeated")) else "NOT defeated"
	await _wait(4.0)
	var found := false
	for t in world.find_children("*", "", true, false):
		if "truffle_id" in t and String(t.get("truffle_id")) == "W1-1":
			found = true
			r["truffle_pos"] = _v((t as Node3D).global_position)
	r["w1_1_truffle_spawned"] = found
	r["siege_left"] = level.get("siege_left")
	report["siege"] = r


func _ph_skip_w1_3() -> void:
	# Can W1-3 be taken without the Stick Scaffold? Hill Lane -> Brick Hill -> rope bridge west -> treehouse deck.
	_set_ai(false)
	var r := {"owned_before": _has("W1-3")}
	var land := level.get_node_or_null("RopeBridge/BridgeLanding") as Node3D
	var start := Vector3(-6.6, 12.4, -31.5)
	if land:
		start = land.global_position + Vector3(0, 0.3, 0)
	var g := _ground(start + Vector3(0, 1, 0), 0.0, 4.0)
	if not g.is_empty():
		start.y = float(g["y"])
	await _tp(start, 90.0)
	r["start"] = _v(player.global_position)
	var s := Vector3(-43.0, 16.0, -31.5)
	var e := Vector3(-8.5, 12.3, -31.5)
	var deck := func(t: float) -> Vector3:
		return Vector3(lerpf(s.x, e.x, t), lerpf(s.y, e.y, t) - 1.2 * sin(PI * t), s.z)
	var ok1 := await _go(deck.call(0.535), 0.3, 12.0)
	r["at_gap_east"] = _v(player.global_position)
	# Single running jump across the 2 m plank gap.
	var far: Vector3 = deck.call(0.40)
	_steer(far)
	await _frames(8)
	_hold("jump", 16)
	for f in 120:
		_steer(far)
		await _frames(1)
		if f > 6 and player.is_on_floor():
			break
	r["after_gap"] = _v(player.global_position)
	var ok2 := await _go(deck.call(0.03), 0.4, 14.0)
	r["at_deck_end"] = _v(player.global_position)
	await _go(Vector3(-46.2, 16.0, -31.4), 0.3, 6.0)
	await _wait(1.0)
	await _frames(10)
	r["end"] = _v(player.global_position)
	r["owned_after"] = _has("W1-3")
	r["verdict"] = "SKIPPABLE: truffle taken via rope bridge without the scaffold" if (_has("W1-3") and not bool(r["owned_before"])) else "not taken this way"
	report["skip_w1_3"] = r
	_set_ai(true)


func _ph_pages() -> void:
	# The harness seeded pages 0-2 into the save before W1 loaded (a player who found them on an earlier visit).
	var game := get_node_or_null("/root/Game")
	var r := {}
	if game == null:
		report["pages"] = {"error": "no Game"}
		return
	r["game_page_count_before"] = game.call("page_count", "W1")
	var vis: Array = []
	for i in range(1, 6):
		var pg := level.get_node_or_null("Page_P%d" % i)
		if pg:
			vis.append({"id": "P%d" % i, "already_saved": game.call("has_page", "W1", int(pg.get("page_index"))), "still_collectable": bool(pg.get("monitoring")) and not bool(pg.get("is_collected"))})
	r["pages_in_world"] = vis
	for i in [4, 5]:
		var pg2 := level.get_node_or_null("Page_P%d" % i)
		if pg2 and not bool(pg2.get("is_collected")):
			pg2.call("collect")
	await _wait(2.5)
	await _frames(5)
	r["game_page_count_after"] = game.call("page_count", "W1")
	var lps := level.get_node_or_null("LostPageSet_W1-5")
	r["lost_page_set_found"] = (lps.get("found") as Dictionary).size() if lps else -1
	r["lost_page_set_rewarded"] = lps.get("reward_given") if lps else null
	var spawned := false
	for t in world.find_children("*", "", true, false):
		if "truffle_id" in t and String(t.get("truffle_id")) == "W1-5":
			spawned = true
	r["w1_5_truffle_spawned"] = spawned
	report["pages"] = r


func _ph_drift() -> void:
	# Enemy state after the run (AI on): anything below the ground, under kill_y, or far from home?
	var out: Array = []
	var ky := float(world.get("kill_y"))
	for e in get_tree().get_nodes_in_group("enemy"):
		if not world.is_ancestor_of(e) or not is_instance_valid(e):
			continue
		var p := (e as Node3D).global_position
		var home: Vector3 = e.get("home") if "home" in e else p
		var g := _ground(p, 3.0, 40.0)
		out.append({"name": str(e.name), "pos": _v(p), "home": _v(home), "moved": snappedf(p.distance_to(home), 0.01), "below_kill_y": p.y < ky,
			"ground": g, "state": e.get("state") if "state" in e else "", "defeated": e.get("is_defeated") if "is_defeated" in e else null})
	report["drift"] = out


func _ph_acorn2() -> void:
	# Re-check suspicious acorns from 30 m above (rays that start inside the terrain miss it).
	var out: Array = []
	for n in get_tree().get_nodes_in_group("acorn"):
		if not world.is_ancestor_of(n):
			continue
		var p := (n as Node3D).global_position
		var hit := _ray(p + Vector3(0, 30, 0), p - Vector3(0, 30, 0))
		if hit.is_empty():
			out.append({"path": _rel(n), "pos": _v(p), "ground": "none"})
			continue
		var gy := (hit["position"] as Vector3).y
		if gy > p.y + 0.05:
			out.append({"path": _rel(n), "pos": _v(p), "surface_above_acorn": snappedf(gy, 0.01), "by": _rel(hit["collider"])})
	report["acorns_below_surface"] = out


func _cam_name() -> String:
	var c := get_viewport().get_camera_3d()
	return str(c.name) if c else "none"


func _slam() -> void:
	_hold("jump", 10)
	await _frames(22)
	_hold("crouch", 6)
	await _frames(60)


func _ph_hay() -> void:
	# W1-7 shell game with an oracle: in each guess window stand on the Foreman's stack and Ham Slam with real input.
	# Also: one wrong slam, one walk-out reset in the middle of a shuffle, then the reward and the punchline cameras.
	var game := get_node_or_null("/root/Game")
	for e in get_tree().get_nodes_in_group("enemy"):
		if "ai_enabled" in e:
			e.set("ai_enabled", false)
	var hy := level.get_node_or_null("HayYard_W1-7")
	var r := {"log": []}
	if hy == null:
		report["hay"] = {"error": "no hay yard"}
		return
	var c: Vector3 = hy.get("center")
	await _tp(c, 0.0)
	var t0 := Time.get_ticks_msec()
	var did_wrong := false
	var did_walkout := false
	var windows := 0
	var good_slams := 0
	var failed_slams := 0
	while Time.get_ticks_msec() - t0 < 240000:
		if game:
			game.call("heal", 6)
		var st := String(hy.get("state"))
		if st == "done":
			break
		if st == "shuffle" and int(hy.get("hp")) == 2 and not did_walkout:
			did_walkout = true
			var cam_before := _cam_name()
			await _tp(c + Vector3(0, 0, 10.5), 0.0)
			await _frames(20)
			r["log"].append({"t": (Time.get_ticks_msec() - t0) / 1000.0, "walkout": true, "cam_during_shuffle": cam_before, "state_after_leaving": hy.get("state"), "cam_after_leaving": _cam_name(), "hp": hy.get("hp")})
			await _tp(c, 0.0)
			continue
		if st == "window":
			windows += 1
			var i := int(hy.call("foreman_stack"))
			var stacks: Array = hy.get("stacks")
			if not did_wrong:
				did_wrong = true
				var j := (i + 2) % 5
				var spw := (stacks[j] as Node3D).global_position
				await _tp(spw + Vector3(0, 1.92, 0), 0.0)
				await _frames(4)
				await _slam()
				r["log"].append({"t": (Time.get_ticks_msec() - t0) / 1000.0, "wrong_slam_on": j, "state_after": hy.get("state"), "hp": hy.get("hp")})
				await _tp(c, 0.0)
				continue
			var hp0 := int(hy.get("hp"))
			var sp := (stacks[i] as Node3D).global_position
			await _tp(sp + Vector3(0, 1.92, 0), 0.0)
			await _frames(4)
			var on_top := player.is_on_floor() and player.global_position.y > sp.y + 1.6
			var st_before := String(hy.get("state"))
			await _slam()
			var hp1 := int(hy.get("hp"))
			var row := {"t": (Time.get_ticks_msec() - t0) / 1000.0, "stack": i, "on_top_before_slam": on_top, "player_y": snappedf(player.global_position.y, 0.01), "stack_y": snappedf(sp.y, 0.01), "state_before": st_before, "state_after": hy.get("state"), "hp_before": hp0, "hp_after": hp1}
			if hp1 < hp0:
				good_slams += 1
			else:
				failed_slams += 1
			r["log"].append(row)
			await _tp(c + Vector3(0, 0, 2.5), 0.0)
			continue
		await _frames(2)
	r["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
	r["final_state"] = hy.get("state")
	r["windows"] = windows
	r["good_slams"] = good_slams
	r["failed_slams_on_right_stack"] = failed_slams
	# Reward and punchline: grab the truffle at once and watch which camera is live (and whether the tree is paused).
	var cams: Array = []
	var tpos := Vector3.INF
	for t in world.find_children("*", "", true, false):
		if "truffle_id" in t and String(t.get("truffle_id")) == "W1-7":
			tpos = (t as Node3D).global_position
	r["truffle_spawned"] = tpos != Vector3.INF
	if tpos != Vector3.INF:
		await get_tree().create_timer(1.0, true).timeout
		player.call("respawn", Transform3D(Basis(), tpos - Vector3(0, 0.6, 0)))
		for k in 24:
			cams.append([snappedf(k * 0.5 + 1.0, 0.1), _cam_name(), get_tree().paused])
			await get_tree().create_timer(0.5, true).timeout
	r["camera_timeline_after_defeat"] = cams
	r["owned_W1_7"] = _has("W1-7")
	r["cam_at_end"] = _cam_name()
	report["hay"] = r


func _ph_holes() -> void:
	# Fine scan (0.5 m) of the playable square for columns with no world collision at all, then drop Mak into the
	# biggest hole cluster to see whether he falls out of the world.
	var holes: Array = []
	var x := -57.0
	while x <= 57.0:
		var z := -57.0
		while z <= 57.0:
			var hit := _ray(Vector3(x, 90, z), Vector3(x, -40, z))
			if hit.is_empty():
				holes.append([x, z])
			z += 0.5
		x += 0.5
	var r := {"cells": 229 * 229, "holes": holes.size(), "list": holes.slice(0, 200)}
	var game := get_node_or_null("/root/Game")
	var drops: Array = []
	var tried := 0
	for h in holes:
		if tried >= 3:
			break
		tried += 1
		var p := Vector3(float(h[0]), 3.0, float(h[1]))
		var falls0: int = int(game.get("data")["stats"].get("falls", 0)) if game else 0
		await _tp(p, 0.0)
		var lowest := p.y
		for k in 150:
			lowest = minf(lowest, player.global_position.y)
			await _frames(1)
		var falls1: int = int(game.get("data")["stats"].get("falls", 0)) if game else 0
		drops.append({"at": _v(p), "lowest_y": snappedf(lowest, 0.01), "end": _v(player.global_position), "fell_out_count_delta": falls1 - falls0})
	r["drops"] = drops
	report["holes_fine"] = r

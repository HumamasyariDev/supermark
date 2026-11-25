extends "res://tests/critique_w1/w1_qa_probe.gd"
## Critique W1 round 1, QA lens, pass "r1c" (20:55 Bangkok resume, on the fix-round-2 build).
## Adds to the base probe:
##   gate_geo     - world AABBs of Hazel's TreehouseGate shapes and the scaffold-top reward triggers;
##   bridge_skip  - real input: from the rope bridge, hop the 1.2 m rail onto sc7, then sc8 -> sc9 -> deck -> W1-3;
##   cp_respawn   - every checkpoint: activate it, fall below kill_y, see where Mak respawns, idle 4 s (drift, damage);
##   fps8         - 8 s windows at every spawn (gameplay camera) and StoryCams A-D at 1920x1080, vsync off.
## Run: python tools/godot.py run res://tests/critique_w1/W1QA_r1c.tscn --seconds 1500 -- --profile=<fresh> --spawn=Default
##      --qa-out=<abs dir> [--qa-phases=a,b]  (the harness never edits the world; it moves the player and drives input)


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
	report["pass"] = "r1c"
	var game := get_node_or_null("/root/Game")
	if game:
		game.damaged.connect(func(a: int) -> void: damage_log.append({"amount": a, "pos": _v(player.global_position), "phase": report.get("_phase", "")}))
		game.truffle_collected.connect(func(id: String) -> void: truffle_log.append({"id": id, "phase": report.get("_phase", ""), "pos": _v(player.global_position)}))
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
	var phases := ["audit", "gate_geo", "spawns", "fps8", "bridge_skip", "cp_respawn", "punch", "siege", "pages", "drift", "acorn2", "hay", "holes", "reenter", "cleft", "hundred", "ghosts"]
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


func _top(id: String) -> Vector3:
	var pl: Dictionary = level.get("plat")
	if not pl.has(id):
		return Vector3.INF
	var a: Array = pl[id]["top"]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _aabb_of_shape(cs: CollisionShape3D) -> Dictionary:
	var xf := cs.global_transform
	var sh := cs.shape
	if sh is BoxShape3D:
		var ext := (sh as BoxShape3D).size * 0.5
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p := xf * Vector3(ext.x * sx, ext.y * sy, ext.z * sz)
					lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
					hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		return {"min": _v(lo), "max": _v(hi)}
	return {"center": _v(xf.origin), "shape": sh.get_class() if sh else "none"}


func _ph_gate_geo() -> void:
	var r := {}
	var gate := level.find_child("TreehouseGate", true, false)
	r["gate_present"] = gate != null
	if gate:
		var boxes: Array = []
		for c in gate.get_children():
			if c is CollisionShape3D:
				boxes.append(_aabb_of_shape(c))
		r["gate_boxes"] = boxes
		r["gate_layer"] = (gate as CollisionObject3D).collision_layer
	var trig: Array = []
	for c in level.get_children():
		if str(c.name).begins_with("ScaffoldTop_"):
			var bx: Array = []
			for s in c.get_children():
				if s is CollisionShape3D:
					bx.append(_aabb_of_shape(s))
			trig.append({"name": str(c.name), "pos": _v((c as Node3D).global_position), "mask": (c as Area3D).collision_mask, "boxes": bx})
	r["scaffold_top_triggers"] = trig
	var tops := {}
	for id in ["scaffold_sc1", "scaffold_sc2", "scaffold_sc3", "scaffold_pole", "scaffold_sc7", "scaffold_sc8", "scaffold_sc9", "treehouse_deck"]:
		var t := _top(id)
		if t != Vector3.INF:
			tops[id] = {"top": _v(t), "type": String((level.get("plat") as Dictionary)[id].get("type", "")), "size": (level.get("plat") as Dictionary)[id].get("size")}
	r["tops"] = tops
	var rail: Array = []
	for nm in ["Rail-1", "Rail1"]:
		var rn := level.find_child(nm, true, false)
		if rn:
			rail.append({"name": nm, "layer": (rn as CollisionObject3D).collision_layer, "shapes": rn.get_child_count()})
	r["bridge_rails"] = rail
	report["gate_geo"] = r


func _hop(t: Vector3, hold_frames := 18, max_frames := 240) -> Dictionary:
	var d0 := _steer(t)
	_hold("jump", hold_frames)
	await _frames(4)
	var f := 0
	var peak := player.global_position.y
	while f < max_frames:
		var d := _steer(t)
		if d < 0.25:
			stick = Vector2.ZERO
		await _frames(1)
		f += 1
		peak = maxf(peak, player.global_position.y)
		if f > 6 and player.is_on_floor():
			break
	stick = Vector2.ZERO
	await _frames(3)
	var g := _ground(player.global_position, 0.3, 1.0)
	return {"start_dist": snappedf(d0, 0.01), "land": _v(player.global_position), "peak_y": snappedf(peak, 0.01), "on_floor": player.is_on_floor(), "floor": g.get("by", ""), "frames": f}


func _bridge_y(x: float, z: float) -> float:
	var hit := _ray(Vector3(x, 22.0, z), Vector3(x, 8.0, z))
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y


func _truffle_node(id: String) -> Node3D:
	for t in world.find_children("*", "", true, false):
		if "truffle_id" in t and String(t.get("truffle_id")) == id and t is Node3D:
			return t as Node3D
	return null


func _ph_bridge_skip() -> void:
	# Hazel's gate shuts the treehouse end of the rope bridge, and the W1-3 truffle now waits for a touch on sc8/sc9.
	# But the bridge's own rail walls are 1.2 m tall along the rest of its length, and sc7 (y 12.4) sits ~0.6 m north of
	# the north rail, 2.7 m below the bridge. Can Mak hop the rail onto sc7 and take W1-3 without sc1-sc3 and the pole?
	_set_ai(false)
	var r := {"owned_before": _has("W1-3"), "attempts": []}
	var s7 := _top("scaffold_sc7")
	var s8 := _top("scaffold_sc8")
	var s9 := _top("scaffold_sc9")
	r["sc7"] = _v(s7)
	var landed := false
	for x in [-38.3, -37.9, -37.5, -37.0, -36.4]:
		var z0 := -31.75
		var by := _bridge_y(x + 1.2, z0)
		if is_nan(by):
			r["attempts"].append({"x": x, "error": "no bridge surface"})
			continue
		await _tp(Vector3(x + 1.2, by, z0), 135.0)
		await _frames(20)
		var start := player.global_position
		# Short diagonal run-up toward sc7, jump once the stick has carried Mak to the take-off x.
		var f := 0
		while f < 90 and player.global_position.x > x:
			_steer(s7)
			await _frames(1)
			f += 1
		var take := player.global_position
		var h := await _hop(s7, 18, 240)
		var row := {"x": x, "start": _v(start), "takeoff": _v(take), "hop": h}
		var lp := player.global_position
		row["on_sc7"] = absf(lp.y - s7.y) < 0.45 and Vector2(lp.x - s7.x, lp.z - s7.z).length() < 1.3
		r["attempts"].append(row)
		if bool(row["on_sc7"]):
			landed = true
			break
	r["landed_on_sc7_from_bridge"] = landed
	if landed:
		var legs: Array = []
		legs.append({"to": "sc8", "hop": await _hop(s8, 18, 240)})
		legs.append({"to": "sc9", "hop": await _hop(s9, 18, 240)})
		await _wait(0.5)
		var tn := _truffle_node("W1-3")
		r["truffle_spawned_after_sc9"] = tn != null
		legs.append({"to": "deck", "hop": await _hop(Vector3(-42.9, 16.0, -27.0), 18, 240)})
		r["legs"] = legs
		if tn and is_instance_valid(tn):
			r["truffle_pos"] = _v(tn.global_position)
			await _go(Vector3(tn.global_position.x, player.global_position.y, tn.global_position.z), 0.3, 8.0)
			await _wait(1.5)
			await _frames(10)
		r["end"] = _v(player.global_position)
	r["owned_after"] = _has("W1-3")
	r["verdict"] = "SKIPPABLE: W1-3 taken from the rope bridge without sc1-sc3 or the greased pole" if (bool(r["owned_after"]) and not bool(r["owned_before"])) else ("sc7 reachable from the bridge" if landed else "not reached from the bridge")
	log_line("bridge_skip: " + String(r["verdict"]))
	report["bridge_skip"] = r
	_set_ai(true)


func _ph_cp_respawn() -> void:
	# Each checkpoint as a player meets it: activate, fall out of the world, respawn at the bookmark, then stand still
	# for 4 s with the AI on. Flags: drift > 1 m (wind, slopes, conveyor), damage while idle, not on floor, below kill_y.
	_set_ai(true)
	var game := get_node_or_null("/root/Game")
	var out: Array = []
	var ky := float(world.get("kill_y"))
	for c in get_tree().get_nodes_in_group("checkpoint"):
		if not world.is_ancestor_of(c) or not c.has_method("activate"):
			continue
		if game:
			game.call("full_heal")
		c.set("is_active", false)
		c.call("activate")
		var xf: Transform3D = c.call("get_respawn_transform")
		await _tp((c as Node3D).global_position + Vector3(0, 30, 0))
		player.global_position = Vector3(xf.origin.x, ky - 5.0, xf.origin.z)
		await _frames(30)
		var dmg0 := damage_log.size()
		var p0 := player.global_position
		var lowest := p0.y
		for k in 240:
			lowest = minf(lowest, player.global_position.y)
			await _frames(1)
		var p1 := player.global_position
		var row := {"name": str(c.name), "bookmark": _v((c as Node3D).global_position), "respawn_xf": _v(xf.origin), "fallback": c.get("respawn_fallback_used"),
			"respawned_at": _v(p0), "respawn_vs_xf": snappedf(p0.distance_to(xf.origin), 0.01), "after_4s": _v(p1), "drift_m": snappedf(Vector2(p1.x - p0.x, p1.z - p0.z).length(), 0.01),
			"dy": snappedf(p1.y - p0.y, 0.01), "on_floor": player.is_on_floor(), "state": player.call("get_state_name"), "idle_damage": damage_log.size() - dmg0,
			"below_kill_y": lowest < ky, "embedded_at_respawn": _embedded_capsule(p0)}
		row["flag"] = (float(row["drift_m"]) > 1.0) or int(row["idle_damage"]) > 0 or not bool(row["on_floor"]) or bool(row["below_kill_y"]) or float(row["respawn_vs_xf"]) > 1.5
		out.append(row)
		log_line("cp %s drift %.2f dmg %d floor %s" % [row["name"], row["drift_m"], row["idle_damage"], row["on_floor"]])
	report["cp_respawn"] = out
	if game:
		game.call("full_heal")


func _ph_fps8() -> void:
	var res: Array = []
	var sp := world.get_node_or_null("Spawns")
	var names: Array = []
	if sp:
		for m in sp.get_children():
			names.append(str(m.name))
	for nm in names:
		var m := sp.get_node_or_null(nm) as Node3D
		if m == null:
			continue
		var yaw := rad_to_deg(m.global_transform.basis.get_euler().y)
		await _tp(m.global_position, yaw)
		await _wait(1.5)
		res.append(await _measure("gameplay@" + nm, 8.0))
	var prev := get_viewport().get_camera_3d()
	var sc := world.get_node_or_null("StoryCams")
	for cn in ["StoryCam_A", "StoryCam_B", "StoryCam_C", "StoryCam_D"]:
		var c := sc.get_node_or_null(cn) as Camera3D if sc else null
		if c == null:
			continue
		c.current = true
		await _wait(1.0)
		res.append(await _measure("story@" + cn, 6.0))
	if is_instance_valid(prev):
		prev.current = true
	report["fps8"] = res


func _ph_reenter() -> void:
	# Leave W1 and come back (as the hub would), then collect a truffle: stale signal connections from the first
	# visit's level (lambdas capturing freed nodes) show up as errors in the Godot log right after this line.
	var game := get_node_or_null("/root/Game")
	var r := {}
	var conns_before := game.get_signal_connection_list("truffle_collected").size() if game else -1
	get_tree().change_scene_to_file("res://scenes/worlds/w1/W1.tscn")
	var t0 := Time.get_ticks_msec()
	await _wait(1.0)
	while Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and cs != world and "world_id" in cs and cs.get_node_or_null("Level") != null and get_tree().get_first_node_in_group("player") != null:
			break
	var cs2 := get_tree().current_scene
	if cs2 and cs2.get_node_or_null("Level") != null:
		world = cs2 as Node3D
		level = cs2.get_node("Level") as Node3D
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	await _wait(3.0)
	r["reload_ms"] = Time.get_ticks_msec() - t0
	r["truffle_collected_connections_before_reload"] = conns_before
	r["truffle_collected_connections_after_reload"] = game.get_signal_connection_list("truffle_collected").size() if game else -1
	log_line("REENTER: collecting W1-8 through Game now (watch for errors below)")
	if game:
		game.call("collect_truffle", "W1-8")
	await _wait(2.0)
	log_line("REENTER: done")
	r["owned_W1_8"] = _has("W1-8")
	report["reenter"] = r


func _ph_hundred() -> void:
	# W1-100: w1_level._on_acorn_progress moves the AcornHundred spawner to (Mak + 1.6 up - forward 1.5) at the moment
	# the 100th acorn is taken, with no ground or wall check. Collect a real acorn as the 100th at risky spots and see
	# where the bonus truffle lands. Between spots the spawner is re-armed (test only).
	var ah := level.get_node_or_null("AcornHundred_W1-100")
	var out: Array = []
	if ah == null:
		report["hundred"] = {"error": "no AcornHundred_W1-100"}
		return
	_set_ai(false)
	var spots := [
		["chimney flue, facing the north wall", Vector3(11.3, 12.05, -35.6), 0.0],
		["rope bridge, at the plank gap facing west", Vector3(-25.2, 0.0, -31.5), 90.0],
		["brick-house wall, facing it at 0.6 m", Vector3(6.3, 0.0, -32.2), 180.0],
		["open meadow (control)", Vector3(0.0, 0.0, 30.0), 0.0],
	]
	var ps := load(ObjSvc.ACORN_SCENE) as PackedScene
	for sp in spots:
		var p: Vector3 = sp[1]
		if p.y == 0.0:
			var g := _ground(Vector3(p.x, 40.0, p.z), 0.0, 60.0)
			p.y = float(g.get("y", 0.0))
		var old := _truffle_node("W1-100")
		if old:
			old.queue_free()
		ah.set("reward_given", false)
		await _tp(p, float(sp[2]))
		await _frames(20)
		ObjSvc.visit_acorns = 99
		var gm := get_node_or_null("/root/Game")
		if gm:
			gm.set("acorns", 99)
		var a := ps.instantiate() as Node3D
		level.add_child(a)
		a.global_position = player.global_position + Vector3(0, 0.3, 0)
		await _frames(20)
		var t := _truffle_node("W1-100")
		var row := {"spot": sp[0], "mak": _v(player.global_position), "mak_on_floor": player.is_on_floor(), "game_acorns": get_node("/root/Game").get("acorns") if get_node_or_null("/root/Game") else -1}
		if t:
			var c := t.global_position + Vector3(0, 0.9, 0)
			var below := _ray(c, c - Vector3(0, 60, 0))
			row["truffle_origin"] = _v(t.global_position)
			row["collect_sphere_centre_inside_or_touching"] = _overlap(c, 0.3)
			row["surface_below"] = snappedf((below["position"] as Vector3).y, 0.01) if not below.is_empty() else null
			row["height_above_surface"] = snappedf(c.y - (below["position"] as Vector3).y, 0.01) if not below.is_empty() else null
			row["los_from_mak_blocked"] = not _ray(player.global_position + Vector3(0, 1.0, 0), c).is_empty()
		else:
			row["truffle"] = "not spawned"
		out.append(row)
		log_line("hundred %s -> %s" % [sp[0], JSON.stringify(row)])
	var last := _truffle_node("W1-100")
	if last:
		last.queue_free()
	report["hundred"] = out
	_set_ai(true)


func _ph_ghosts() -> void:
	# Revisit with every W1 truffle owned: where do the ghost truffles and the persistent tale states end up?
	var game := get_node_or_null("/root/Game")
	var r := {}
	if game == null:
		report["ghosts"] = {"error": "no Game"}
		return
	for id in ["W1-1", "W1-2", "W1-3", "W1-4", "W1-5", "W1-6", "W1-7", "W1-8", "W1-100"]:
		if not _has(id):
			game.call("collect_truffle", id)
	await _wait(1.0)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/worlds/w1/W1.tscn")
	var t0 := Time.get_ticks_msec()
	await _wait(1.0)
	while Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and cs != world and "world_id" in cs and cs.get_node_or_null("Level") != null and get_tree().get_first_node_in_group("player") != null:
			world = cs as Node3D
			level = cs.get_node("Level") as Node3D
			player = get_tree().get_first_node_in_group("player") as CharacterBody3D
			break
	await _wait(3.0)
	var g: Array = []
	for t in world.find_children("*", "", true, false):
		if "truffle_id" in t and String(t.get("truffle_id")) != "":
			var p := (t as Node3D).global_position
			g.append({"id": String(t.get("truffle_id")), "pos": _v(p), "ghost": t.get("is_ghost"), "ground": _ground(p, 0.5, 30.0), "inside": _overlap(p + Vector3(0, 0.9, 0), 0.3)})
	r["truffles_on_revisit"] = g
	r["gate_present"] = level.find_child("TreehouseGate", true, false) != null
	report["ghosts"] = r


func _ph_cleft() -> void:
	# What occupies the P4 Kick Cleft slot and the W1-7 approach where the bot stalls? Box queries on layer 1 and 4.
	var out := {}
	var boxes := {"kick_cleft_slot": [Vector3(-54.0, 4.5, -7.9), Vector3(2.4, 7.0, 4.8)], "cleft_mouth": [Vector3(-54.0, 2.0, -11.0), Vector3(3.0, 3.0, 2.5)],
		"w1_7_approach": [Vector3(-32.4, 1.0, -45.3), Vector3(1.6, 1.6, 2.4)], "chimney_flue": [Vector3(11.3, 20.0, -36.0), Vector3(2.8, 15.0, 2.4)]}
	for k in boxes:
		var b: Array = boxes[k]
		var sh := BoxShape3D.new()
		sh.size = b[1]
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sh
		q.transform = Transform3D(Basis(), b[0])
		q.collision_mask = 1 | 4
		q.exclude = [player.get_rid()]
		var names: Array = []
		for r2 in _space().intersect_shape(q, 32):
			var col: Object = r2["collider"]
			var nm := _rel(col)
			if nm.begins_with("/Level/Dressing") and col is CollisionObject3D:
				var det := {"path": nm, "layer": (col as CollisionObject3D).collision_layer, "origin": _v((col as Node3D).global_position), "shapes": []}
				var si: int = int(r2.get("shape", 0))
				var owner_id := (col as CollisionObject3D).shape_find_owner(si)
				var sown := (col as CollisionObject3D).shape_owner_get_owner(owner_id)
				if sown is CollisionShape3D:
					det["shapes"].append(_aabb_of_shape(sown))
				var meshes: Array = []
				for c in (col as Node).get_children():
					meshes.append(str(c.name))
				det["children"] = meshes.slice(0, 6)
				names.append(det)
			else:
				names.append(nm)
		out[k] = names
	var walls := {}
	for nm in ["kick_cleft_e", "kick_cleft_w"]:
		var n := level.find_child(nm, true, false)
		if n:
			var bx: Array = []
			for c in n.get_children():
				if c is CollisionShape3D:
					bx.append(_aabb_of_shape(c))
			walls[nm] = {"pos": _v((n as Node3D).global_position), "boxes": bx}
	out["cleft_walls"] = walls
	report["cleft"] = out

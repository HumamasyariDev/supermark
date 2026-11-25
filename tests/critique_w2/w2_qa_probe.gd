extends Node
## Critique W2 round 1, QA and technical lens. Lives under /root while W2 is the current scene.
## Phases: static audit -> idle at spawn (spawn safety, enemy drift) -> fps at the four StoryCams ->
## drop tests + gameplay-camera fps at every spawn, checkpoint, truffle and reward marker -> enemy API
## hit test (pod patrol reward) -> JSON report under --qa-out, then quit.
## Read-only for the world: it only moves the player, flips pickup monitoring off and calls hit_by_player.

const CAPSULE_R := 0.35
const CAPSULE_H := 1.25

var out_dir := ""
var world: Node
var player: CharacterBody3D
var report := {}
var damage_log: Array = []
var truffle_log: Array = []

var _bucket: PackedFloat32Array = PackedFloat32Array()
var _measuring := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("qa-out", OS.get_user_data_dir().path_join("w2_qa")) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _process(delta: float) -> void:
	if _measuring:
		_bucket.append(delta)


func log_line(s: String) -> void:
	print("[QA] " + s)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func _run() -> void:
	# Wait for W2 and the player.
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and cs.get("player") != null:
			world = cs
			player = cs.get("player") as CharacterBody3D
			break
		if Time.get_ticks_msec() - t0 > 120000:
			log_line("TIMEOUT waiting for W2")
			get_tree().quit(2)
			return
	report["load_ms"] = Time.get_ticks_msec() - t0
	var game := get_node_or_null("/root/Game")
	if game:
		game.damaged.connect(func(a: int) -> void: damage_log.append({"t": Time.get_ticks_msec(), "amount": a, "pos": _v(player.global_position), "phase": report.get("_phase", "")}))
		game.truffle_collected.connect(func(id: String) -> void: truffle_log.append({"id": id, "phase": report.get("_phase", "")}))
	await _wait(2.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	report["viewport"] = _v2(get_viewport().get_visible_rect().size)
	report["window"] = _v2(Vector2(DisplayServer.window_get_size()))
	report["_phase"] = "audit"
	_audit()
	report["_phase"] = "idle_spawn"
	await _idle_at_spawn()
	report["_phase"] = "storycams"
	await _storycams()
	report["_phase"] = "drops"
	await _drops()
	report["_phase"] = "enemy_hits"
	await _enemy_hits()
	report["damage_log"] = damage_log
	report["truffle_log"] = truffle_log
	report["kill_y"] = world.get("kill_y")
	var f := FileAccess.open(out_dir.path_join("w2_qa_probe.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	log_line("report written " + out_dir.path_join("w2_qa_probe.json"))
	get_tree().quit()


# ------------------------------------------------------------------ helpers

func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _v2(p: Vector2) -> Array:
	return [p.x, p.y]


func _space() -> PhysicsDirectSpaceState3D:
	return (world as Node3D).get_world_3d().direct_space_state


func _ray_down(p: Vector3, up := 0.6, down := 6.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, up, 0), p - Vector3(0, down, 0), 1)
	q.exclude = [player.get_rid()]
	var hit := _space().intersect_ray(q)
	if hit.is_empty():
		return {}
	return {"y": snappedf((hit["position"] as Vector3).y, 0.01), "gap": snappedf(p.y - (hit["position"] as Vector3).y, 0.01), "by": str((hit["collider"] as Node).name) if hit["collider"] else "?"}


func _embedded(p: Vector3) -> Array:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_R * 0.9
	shape.height = CAPSULE_H * 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), p + Vector3(0, CAPSULE_H * 0.5 + 0.08, 0))
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	var res := _space().intersect_shape(q, 4)
	var names: Array = []
	for r in res:
		if r["collider"]:
			names.append(str((r["collider"] as Node).get_path()).replace(str(world.get_path()), ""))
	return names


func _stats(name_: String, frames: PackedFloat32Array) -> Dictionary:
	if frames.size() == 0:
		return {"name": name_, "frames": 0}
	var arr := Array(frames)
	arr.sort()
	var sum := 0.0
	var over := 0
	for d in arr:
		sum += d
		if d > 1.0 / 60.0 + 0.0005:
			over += 1
	var mean := sum / arr.size()
	var p99: float = arr[int(floor(arr.size() * 0.99)) - 1] if arr.size() > 1 else arr[0]
	var mx: float = arr[arr.size() - 1]
	return {"name": name_, "frames": arr.size(), "mean_fps": snappedf(1.0 / mean, 0.1), "p99_ms": snappedf(p99 * 1000.0, 0.01),
		"low1_fps": snappedf(1.0 / p99, 0.1), "max_ms": snappedf(mx * 1000.0, 0.01), "frames_over_16_7ms": over,
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))}


func _measure(name_: String, settle: float, sec: float) -> Dictionary:
	await _wait(settle)
	_bucket = PackedFloat32Array()
	_measuring = true
	await _wait(sec)
	_measuring = false
	var s := _stats(name_, _bucket)
	log_line("FPS %s" % JSON.stringify(s))
	return s


func _place_player(p: Vector3, yaw := 0.0) -> void:
	if player.has_method("respawn"):
		player.respawn(Transform3D(Basis(Vector3.UP, yaw), p))
	else:
		player.global_position = p
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var rig := player.get_node_or_null("MakCamera")
	if rig and rig.has_method("snap_behind"):
		rig.call("snap_behind")


func _all_of(root: Node, pred: Callable, acc: Array) -> Array:
	if pred.call(root):
		acc.append(root)
	for c in root.get_children():
		_all_of(c, pred, acc)
	return acc


# ------------------------------------------------------------------ phase 1: static audit

func _audit() -> void:
	var a := {}
	# Truffle ids: placed truffles plus every reward source.
	var ids: Array = []
	var sources: Array = []
	for t in get_tree().get_nodes_in_group("truffle"):
		ids.append(str(t.get("truffle_id")))
		sources.append({"kind": "Truffle", "id": str(t.get("truffle_id")), "node": str(t.name), "pos": _v((t as Node3D).global_position)})
	var spawners := _all_of(world, func(n: Node) -> bool: return n is Node3D and "reward_truffle_id" in n, [])
	for s in spawners:
		var rid := str(s.get("reward_truffle_id"))
		var m := (s as Node).get_node_or_null("TruffleMarker") as Node3D
		var mp: Vector3 = m.global_position if m else (s as Node3D).global_position
		sources.append({"kind": (s as Node).get_class() + ":" + str((s as Node).name), "id": rid, "pos": _v(mp)})
		if rid != "":
			ids.append(rid)
	var expected := ["W2-1", "W2-2", "W2-3", "W2-4", "W2-5", "W2-6", "W2-7", "W2-8", "W2-100"]
	var missing: Array = []
	for e in expected:
		if not ids.has(e):
			missing.append(e)
	var dup: Array = []
	var seen := {}
	for i in ids:
		if seen.has(i) and not dup.has(i):
			dup.append(i)
		seen[i] = true
	var unexpected: Array = []
	for i in ids:
		if not expected.has(i) and i != "":
			unexpected.append(i)
	a["truffle_sources"] = sources
	a["truffle_missing"] = missing
	a["truffle_duplicates"] = dup
	a["truffle_unexpected"] = unexpected
	# Support and embedding at every reward point.
	var rp: Array = []
	for s in sources:
		var p := Vector3(s["pos"][0], s["pos"][1], s["pos"][2])
		rp.append({"id": s["id"], "kind": s["kind"], "pos": s["pos"], "floor": _ray_down(p, 0.6, 8.0), "embedded": _embedded(p)})
	a["reward_points"] = rp
	# Spawns and checkpoints.
	var sp: Array = []
	var spawns := world.get_node_or_null("Spawns")
	if spawns:
		for m in spawns.get_children():
			if m is Node3D:
				var p: Vector3 = (m as Node3D).global_position
				sp.append({"name": str(m.name), "pos": _v(p), "floor": _ray_down(p, 0.6, 4.0), "embedded": _embedded(p)})
	a["spawns"] = sp
	var cps: Array = []
	for c in _all_of(world, func(n: Node) -> bool: return n is CheckpointBookmark, []):
		var p: Vector3 = (c as Node3D).global_position
		cps.append({"name": str(c.name), "pos": _v(p), "floor": _ray_down(p, 0.6, 4.0), "embedded": _embedded(p)})
	a["checkpoints"] = cps
	# Pages.
	var pages: Array = []
	for pg in _all_of(world, func(n: Node) -> bool: return n is LostPage, []):
		var p: Vector3 = (pg as Node3D).global_position
		pages.append({"name": str(pg.name), "index": pg.get("page_index"), "pos": _v(p), "floor": _ray_down(p, 0.6, 12.0), "embedded": _embedded(p - Vector3(0, 0.3, 0))})
	a["pages"] = pages
	# Acorns: count and those inside world collision (uncollectable) or below kill_y.
	var acorns := _all_of(world, func(n: Node) -> bool: return n is Acorn, [])
	var crate_acorns := 0
	for c in _all_of(world, func(n: Node) -> bool: return n is BreakableCrate, []):
		crate_acorns += int(c.get("acorns"))
	var buried: Array = []
	var pq := PhysicsPointQueryParameters3D.new()
	pq.collision_mask = 1
	for ac in acorns:
		var p: Vector3 = (ac as Node3D).global_position
		pq.position = p + Vector3(0, 0.3, 0)
		var hits := _space().intersect_point(pq, 2)
		if hits.size() > 0:
			buried.append({"name": str(ac.get_path()).replace(str(world.get_path()), ""), "pos": _v(p), "in": str((hits[0]["collider"] as Node).name) if hits[0]["collider"] else "?"})
	var enemy_acorns := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		enemy_acorns += int(e.get("acorns_on_defeat")) if "acorns_on_defeat" in e else 0
	a["acorn_nodes"] = acorns.size()
	a["acorns_in_crates"] = crate_acorns
	a["acorns_from_enemies"] = enemy_acorns
	a["acorns_buried"] = buried
	# Enemies.
	var en: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		var e3 := e as Node3D
		var hb: Node = e.get("hurtbox") if "hurtbox" in e else null
		var info := {"name": str(e.name), "class": e.get_class(), "script": str(e.get_script().resource_path.get_file()) if e.get_script() else "", "pos": _v(e3.global_position),
			"gravity": e.get("uses_gravity"), "hurtbox": hb != null, "hurtbox_layer": (hb as CollisionObject3D).collision_layer if hb is CollisionObject3D else -1,
			"hurtbox_monitorable": (hb as Area3D).monitorable if hb is Area3D else false, "floor": _ray_down(e3.global_position, 0.6, 6.0),
			"mesh": str(e.get("mesh_path")) if "mesh_path" in e else "", "has_mesh_root": e.get("mesh_root") != null if "mesh_root" in e else false,
			"placeholder_visible": (e.get("placeholder") as Node3D).visible if "placeholder" in e and e.get("placeholder") is Node3D else null,
			"state": str(e.get("state")) if "state" in e else ""}
		en.append(info)
	a["enemies"] = en
	# Node budget.
	a["node_count"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var meshes := _all_of(world, func(n: Node) -> bool: return n is MeshInstance3D, [])
	a["mesh_instances"] = meshes.size()
	var lights := _all_of(world, func(n: Node) -> bool: return n is OmniLight3D or n is SpotLight3D, [])
	var shadow_lights := 0
	for l in lights:
		if (l as Light3D).shadow_enabled:
			shadow_lights += 1
	a["local_lights"] = lights.size()
	a["local_shadow_lights"] = shadow_lights
	a["gpu_particles"] = _all_of(world, func(n: Node) -> bool: return n is GPUParticles3D, []).size()
	a["bodies"] = _all_of(world, func(n: Node) -> bool: return n is CollisionObject3D, []).size()
	report["audit"] = a
	log_line("AUDIT truffles missing=%s dup=%s unexpected=%s acorn_nodes=%d crates=%d enemies=%d buried=%d" % [missing, dup, unexpected, acorns.size(), crate_acorns, en.size(), buried.size()])


# ------------------------------------------------------------------ phase 2: idle at spawn

func _idle_at_spawn() -> void:
	var start := {}
	for e in get_tree().get_nodes_in_group("enemy"):
		start[e] = (e as Node3D).global_position
	var p0 := player.global_position
	var s := await _measure("spawn_gameplay_idle", 1.0, 12.0)
	var drift: Array = []
	for e in start.keys():
		if not is_instance_valid(e):
			drift.append({"name": "(freed)"})
			continue
		var p: Vector3 = (e as Node3D).global_position
		var d: Vector3 = p - start[e]
		var row := {"name": str(e.name), "start": _v(start[e]), "end": _v(p), "dy": snappedf(d.y, 0.01), "state": str(e.get("state")), "floor_now": _ray_down(p, 0.6, 6.0)}
		if not p.is_finite() or p.y < float(world.get("kill_y")) or d.y < -2.0:
			row["flag"] = "FELL"
		drift.append(row)
	report["idle"] = {"fps": s, "player_start": _v(p0), "player_end": _v(player.global_position), "enemies": drift, "damage_during": damage_log.duplicate()}


# ------------------------------------------------------------------ phase 3: StoryCams

func _storycams() -> void:
	var prev := get_viewport().get_camera_3d()
	var res: Array = []
	for n in ["StoryCam_A", "StoryCam_B", "StoryCam_C", "StoryCam_D"]:
		var cam := world.find_child(n, true, false) as Camera3D
		if cam == null:
			res.append({"name": n, "missing": true})
			continue
		cam.make_current()
		res.append(await _measure(n, 1.5, 4.0))
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("fps_%s.png" % n))
	if prev:
		prev.make_current()
	report["storycams"] = res


# ------------------------------------------------------------------ phase 4: drop tests + gameplay fps

func _drops() -> void:
	# Pickups off so the drop tests do not collect anything.
	for n in get_tree().get_nodes_in_group("truffle"):
		(n as Area3D).set_deferred("monitoring", false)
	for pg in _all_of(world, func(n: Node) -> bool: return n is LostPage, []):
		(pg as Area3D).set_deferred("monitoring", false)
	var pts: Array = []
	var spawns := world.get_node_or_null("Spawns")
	if spawns:
		for m in spawns.get_children():
			if m is Node3D and not str(m.name).begins_with("dev_"):
				pts.append(["spawn:" + str(m.name), (m as Node3D).global_position])
	for c in _all_of(world, func(n: Node) -> bool: return n is CheckpointBookmark, []):
		pts.append(["cp:" + str(c.name), (c as Node3D).global_position])
	for s in report["audit"]["truffle_sources"]:
		pts.append(["reward:" + str(s["id"]), Vector3(s["pos"][0], s["pos"][1], s["pos"][2])])
	for pg in report["audit"]["pages"]:
		var p := Vector3(pg["pos"][0], pg["pos"][1], pg["pos"][2])
		var fl: Dictionary = pg["floor"]
		if not fl.is_empty():
			p.y = float(fl["y"])
		pts.append(["page:" + str(pg["name"]), p])
	for sw in _all_of(world, func(n: Node) -> bool: return n is SlamSwitch, []):
		pts.append(["switch:" + str(sw.name), (sw as Node3D).global_position])
	var res: Array = []
	var seen := {}
	for pt in pts:
		var key := "%s" % [_v(pt[1])]
		if seen.has(key):
			continue
		seen[key] = true
		var p: Vector3 = pt[1]
		var fl := _ray_down(p, 0.6, 8.0)
		var drop_from := p + Vector3(0, 1.0, 0)
		if not fl.is_empty():
			drop_from = Vector3(p.x, float(fl["y"]) + 1.0, p.z)
		var dmg0 := damage_log.size()
		_place_player(drop_from)
		var fps := await _measure("gp:" + str(pt[0]), 0.6, 1.6)
		var end := player.global_position
		var row := {"name": pt[0], "target": _v(p), "drop_from": _v(drop_from), "end": _v(end), "on_floor": player.is_on_floor(),
			"fell": snappedf(drop_from.y - end.y, 0.01), "horiz_drift": snappedf(Vector2(end.x - drop_from.x, end.z - drop_from.z).length(), 0.01),
			"floor": fl, "damage": damage_log.size() - dmg0, "fps": fps}
		var flags: Array = []
		if fl.is_empty():
			flags.append("NO_FLOOR_WITHIN_8M")
		if drop_from.y - end.y > 2.5:
			flags.append("FELL_THROUGH_OR_OFF")
		if Vector2(end.x - drop_from.x, end.z - drop_from.z).length() > 2.0:
			flags.append("PUSHED")
		if damage_log.size() > dmg0:
			flags.append("HURT_ON_ARRIVAL")
		if fps.get("mean_fps", 999.0) < 60.0 or fps.get("low1_fps", 999.0) < 60.0:
			flags.append("FPS_BELOW_60")
		row["flags"] = flags
		res.append(row)
		if flags.size() > 0:
			log_line("DROP %s %s" % [pt[0], JSON.stringify(row)])
		var vp := get_viewport().get_texture().get_image()
		vp.save_png(out_dir.path_join("gp_%s.png" % str(pt[0]).replace(":", "_")))
	report["drops"] = res


# ------------------------------------------------------------------ phase 5: enemy API hits

func _enemy_hits() -> void:
	# Park the player at the W2-6 spawn so the pod patrol reward spawns next to it.
	var res: Array = []
	var from := player.global_position
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("hit_by_player"):
			continue
		var landed_any := false
		var kinds_landed: Array = []
		for k in ["punch", "jump_kick", "stomp", "slam", "dive"]:
			if not is_instance_valid(e) or bool(e.get("is_defeated")):
				break
			var ep := (e as Node3D).global_position
			var landed: bool = e.call("hit_by_player", k, ep + Vector3(0, 0.4, 1.0))
			if landed:
				landed_any = true
				kinds_landed.append(k)
			await _wait(0.35)
		res.append({"name": str(e.name) if is_instance_valid(e) else "(freed)", "landed": landed_any, "kinds_landed": kinds_landed, "defeated": (not is_instance_valid(e)) or bool(e.get("is_defeated"))})
	await _wait(3.0)
	var w26 := false
	for t in get_tree().get_nodes_in_group("truffle"):
		if str(t.get("truffle_id")) == "W2-6":
			w26 = true
	var low_acorns: Array = []
	for ac in _all_of(world, func(n: Node) -> bool: return n is Acorn, []):
		var p: Vector3 = (ac as Node3D).global_position
		if p.y < float(world.get("kill_y")) + 1.0:
			low_acorns.append(_v(p))
	report["enemy_hits"] = {"rows": res, "w2_6_truffle_spawned": w26, "acorns_lost_below_kill_y": low_acorns, "player_at": _v(from)}
	log_line("ENEMY HITS w2_6_spawned=%s rows=%s" % [w26, JSON.stringify(res)])

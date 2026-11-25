extends Node
## Critique W3 round 1, QA and technical lens. Lives under /root while W3 is the current scene.
## Phases (--qa-phases, comma list; default all): audit -> idle (spawn safety, enemy drift, 30 s) -> cams (fps at
## StoryCam_A..D) -> drops (drop test + gameplay-camera fps at every spawn, checkpoint, reward, page) -> engage
## (park Mak 5 m from every enemy: does it notice, move, hurt, stay on its floor?) -> hits (hit_by_player API from
## front and back) -> kitchen (containment and exits of the W3-6 pocket set) -> JSON report under --qa-out, then quit.
## Read-only for the world: it only moves the player, heals him, flips pickup monitoring off and calls hit_by_player.

const CAPSULE_R := 0.35
const CAPSULE_H := 1.25

var out_dir := ""
var world: Node
var player: CharacterBody3D
var game: Node
var report := {}
var damage_log: Array = []
var truffle_log: Array = []
var phases: PackedStringArray

var _bucket: PackedFloat32Array = PackedFloat32Array()
var _gpu: PackedFloat32Array = PackedFloat32Array()
var _cpu: PackedFloat32Array = PackedFloat32Array()
var _measuring := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("qa-out", OS.get_user_data_dir().path_join("w3_qa")) if dev else OS.get_user_data_dir()
	phases = String(dev.arg("qa-phases", "audit,idle,cams,drops,engage,hits,kitchen") if dev else "audit").split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _process(delta: float) -> void:
	if _measuring:
		_bucket.append(delta)
		var vp := get_viewport().get_viewport_rid()
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())


func _shot(name_: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	img.save_jpg(out_dir.path_join(name_ + ".jpg"), 0.82)


func log_line(s: String) -> void:
	print("[QA] " + s)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _heal() -> void:
	if game and game.has_method("full_heal"):
		game.call("full_heal")


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and cs.get("player") != null:
			world = cs
			player = cs.get("player") as CharacterBody3D
			break
		if Time.get_ticks_msec() - t0 > 180000:
			log_line("TIMEOUT waiting for W3")
			get_tree().quit(2)
			return
	report["load_ms"] = Time.get_ticks_msec() - t0
	game = get_node_or_null("/root/Game")
	if game:
		if game.has_signal("damaged"):
			game.damaged.connect(func(a: int) -> void: damage_log.append({"t": Time.get_ticks_msec(), "amount": a, "pos": _v(player.global_position), "phase": report.get("_phase", "")}))
		else:
			game.health_changed.connect(func(v: int) -> void: damage_log.append({"t": Time.get_ticks_msec(), "health": v, "pos": _v(player.global_position), "phase": report.get("_phase", "")}))
		game.truffle_collected.connect(func(id: String) -> void: truffle_log.append({"id": id, "phase": report.get("_phase", "")}))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _wait(2.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	report["viewport"] = _v2(get_viewport().get_visible_rect().size)
	report["window"] = _v2(Vector2(DisplayServer.window_get_size()))
	report["video_adapter"] = RenderingServer.get_video_adapter_name()
	if "audit" in phases:
		report["_phase"] = "audit"
		_audit()
		_save("partial")
	if "idle" in phases:
		report["_phase"] = "idle_spawn"
		await _idle_at_spawn()
		_save("partial")
	if "cams" in phases:
		report["_phase"] = "storycams"
		await _storycams()
		_save("partial")
	if "drops" in phases:
		report["_phase"] = "drops"
		await _drops()
		_save("partial")
	if "engage" in phases:
		report["_phase"] = "engage"
		await _engage()
		_save("partial")
	if "hits" in phases:
		report["_phase"] = "enemy_hits"
		await _enemy_hits()
		_save("partial")
	if "kitchen" in phases:
		report["_phase"] = "kitchen"
		await _kitchen()
	if "views" in phases:
		report["_phase"] = "views"
		await _views()
	if "joust" in phases:
		report["_phase"] = "joust"
		await _joust()
	if "geode" in phases:
		report["_phase"] = "geode"
		await _geode()
	report["damage_log"] = damage_log
	report["truffle_log"] = truffle_log
	report["kill_y"] = world.get("kill_y")
	_save("final")
	get_tree().quit()


func _save(tag: String) -> void:
	var f := FileAccess.open(out_dir.path_join("w3_qa_probe.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	log_line("report %s written %s" % [tag, out_dir.path_join("w3_qa_probe.json")])


# ------------------------------------------------------------------ helpers

func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _v2(p: Vector2) -> Array:
	return [p.x, p.y]


func _rel(n: Node) -> String:
	return str(n.get_path()).replace(str(world.get_path()), "")


func _space() -> PhysicsDirectSpaceState3D:
	return (world as Node3D).get_world_3d().direct_space_state


func _ray_down(p: Vector3, up := 0.6, down := 6.0, mask := 1) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, up, 0), p - Vector3(0, down, 0), mask)
	q.exclude = [player.get_rid()]
	var hit := _space().intersect_ray(q)
	if hit.is_empty():
		return {}
	return {"y": snappedf((hit["position"] as Vector3).y, 0.01), "gap": snappedf(p.y - (hit["position"] as Vector3).y, 0.01), "by": _rel(hit["collider"]) if hit["collider"] else "?"}


func _embedded(p: Vector3) -> Array:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_R * 0.9
	shape.height = CAPSULE_H * 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), p + Vector3(0, CAPSULE_H * 0.5 + 0.08, 0))
	q.collision_mask = 1 | 4
	q.exclude = [player.get_rid()]
	var res := _space().intersect_shape(q, 4)
	var names: Array = []
	for r in res:
		if r["collider"] and not (r["collider"] as Node).is_in_group("enemy"):
			names.append(_rel(r["collider"]))
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
	var p99: float = arr[maxi(0, int(floor(arr.size() * 0.99)) - 1)]
	var mx: float = arr[arr.size() - 1]
	var g := Array(_gpu)
	g.sort()
	var c := Array(_cpu)
	c.sort()
	var gm := 0.0
	for x in g:
		gm += x
	var cm := 0.0
	for x in c:
		cm += x
	return {"name": name_, "frames": arr.size(), "mean_fps": snappedf(1.0 / mean, 0.1), "p99_ms": snappedf(p99 * 1000.0, 0.01),
		"low1_fps": snappedf(1.0 / p99, 0.1), "max_ms": snappedf(mx * 1000.0, 0.01), "frames_over_16_7ms": over,
		"gpu_ms_mean": snappedf(gm / maxf(1.0, g.size()), 0.01), "gpu_ms_p95": snappedf(g[int(g.size() * 0.95)] if g.size() > 0 else 0.0, 0.01),
		"cpu_ms_mean": snappedf(cm / maxf(1.0, c.size()), 0.01),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))}


func _measure(name_: String, settle: float, sec: float) -> Dictionary:
	await _wait(settle)
	_bucket = PackedFloat32Array()
	_gpu = PackedFloat32Array()
	_cpu = PackedFloat32Array()
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


func _has_visible_mesh(n: Node) -> bool:
	for c in n.get_children():
		if c is GeometryInstance3D and (c as Node3D).is_visible_in_tree():
			return true
		if not (c is CollisionObject3D) and _has_visible_mesh(c):
			return true
	return false


# ------------------------------------------------------------------ phase 1: static audit

func _audit() -> void:
	var a := {}
	var ids: Array = []
	var sources: Array = []
	for t in get_tree().get_nodes_in_group("truffle"):
		ids.append(str(t.get("truffle_id")))
		sources.append({"kind": "Truffle", "id": str(t.get("truffle_id")), "node": _rel(t), "pos": _v((t as Node3D).global_position),
			"process_mode": (t as Node).process_mode, "monitoring": (t as Area3D).monitoring if t is Area3D else null})
	var spawners := _all_of(world, func(n: Node) -> bool: return n is Node3D and "reward_truffle_id" in n, [])
	for s in spawners:
		var rid := str(s.get("reward_truffle_id"))
		var m := (s as Node).get_node_or_null("TruffleMarker") as Node3D
		var mp: Vector3 = m.global_position if m else (s as Node3D).global_position
		sources.append({"kind": (s as Node).get_class() + ":" + _rel(s), "id": rid, "pos": _v(mp)})
		if rid != "":
			ids.append(rid)
	var expected := ["W3-1", "W3-2", "W3-3", "W3-4", "W3-5", "W3-6", "W3-7", "W3-8", "W3-100"]
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
	a["truffle_missing_at_load"] = missing
	a["truffle_missing_note"] = "W3-6 (cage) and W3-8 (geode) are spawned at runtime by ObjSvc.spawn_truffle; they are expected to be missing here."
	a["truffle_duplicates"] = dup
	a["truffle_unexpected"] = unexpected
	var rp: Array = []
	for s in sources:
		var p := Vector3(s["pos"][0], s["pos"][1], s["pos"][2])
		rp.append({"id": s["id"], "kind": s["kind"], "pos": s["pos"], "floor": _ray_down(p, 0.6, 12.0), "embedded": _embedded(p - Vector3(0, 0.5, 0))})
	a["reward_points"] = rp
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
	var pages: Array = []
	for pg in _all_of(world, func(n: Node) -> bool: return n is LostPage, []):
		var p: Vector3 = (pg as Node3D).global_position
		pages.append({"name": str(pg.name), "index": pg.get("page_index"), "world_id": pg.get("world_id"), "pos": _v(p), "floor": _ray_down(p, 0.6, 12.0), "embedded": _embedded(p - Vector3(0, 0.3, 0))})
	a["pages"] = pages
	var acorns := _all_of(world, func(n: Node) -> bool: return n is Acorn, [])
	var crate_acorns := 0
	var crates := _all_of(world, func(n: Node) -> bool: return n is BreakableCrate, [])
	for c in crates:
		crate_acorns += int(c.get("acorns")) if "acorns" in c else 0
	var buried: Array = []
	var below: Array = []
	var pq := PhysicsPointQueryParameters3D.new()
	pq.collision_mask = 1
	for ac in acorns:
		var p: Vector3 = (ac as Node3D).global_position
		pq.position = p + Vector3(0, 0.25, 0)
		var hits := _space().intersect_point(pq, 2)
		if hits.size() > 0:
			buried.append({"name": _rel(ac), "pos": _v(p), "in": _rel(hits[0]["collider"]) if hits[0]["collider"] else "?"})
		var fl := _ray_down(p, 0.3, 30.0)
		if fl.is_empty():
			below.append({"name": _rel(ac), "pos": _v(p)})
	var enemy_acorns := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		enemy_acorns += int(e.get("acorns_on_defeat")) if "acorns_on_defeat" in e else 0
	a["acorn_nodes"] = acorns.size()
	a["crates"] = crates.size()
	a["acorns_in_crates"] = crate_acorns
	a["acorns_from_enemies"] = enemy_acorns
	a["acorns_buried_in_world_collision"] = buried
	a["acorns_with_no_floor_30m"] = below
	# Enemies.
	var en: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		var e3 := e as Node3D
		var hb: Node = e.get("hurtbox") if "hurtbox" in e else null
		var info := {"name": _rel(e), "class": e.get_class(), "script": str(e.get_script().resource_path.get_file()) if e.get_script() else "", "pos": _v(e3.global_position),
			"gravity": e.get("uses_gravity"), "ai": e.get("ai_enabled"), "hurtbox": hb != null, "hurtbox_layer": (hb as CollisionObject3D).collision_layer if hb is CollisionObject3D else -1,
			"hurtbox_monitorable": (hb as Area3D).monitorable if hb is Area3D else false, "floor": _ray_down(e3.global_position, 0.6, 6.0),
			"mesh": str(e.get("mesh_path")) if "mesh_path" in e else "", "has_mesh_root": e.get("mesh_root") != null if "mesh_root" in e else false,
			"placeholder_visible": (e.get("placeholder") as Node3D).is_visible_in_tree() if "placeholder" in e and e.get("placeholder") is Node3D else null,
			"state": str(e.get("state")) if "state" in e else "", "hp": e.get("hp"), "visible": e3.is_visible_in_tree()}
		en.append(info)
	a["enemies"] = en
	# Character GLBs actually used (NPCs/ambient) -- scan instanced scene file paths for assets/characters and assets/enemies.
	var chars := {}
	for n in _all_of(world, func(x: Node) -> bool: return x.scene_file_path != "" and (x.scene_file_path.contains("/characters/") or x.scene_file_path.contains("/enemies/")), []):
		chars[n.scene_file_path] = int(chars.get(n.scene_file_path, 0)) + 1
	a["character_scene_instances"] = chars
	# Invisible solid bodies (layer 1, no visible geometry in their own subtree): candidates for "invisible wall" bugs.
	var inv: Array = []
	for b in _all_of(world, func(x: Node) -> bool: return x is StaticBody3D or x is AnimatableBody3D, []):
		var co := b as CollisionObject3D
		if (co.collision_layer & 1) == 0:
			continue
		if _has_visible_mesh(b) or (b.get_parent() is GeometryInstance3D and (b.get_parent() as Node3D).is_visible_in_tree()):
			continue
		var shapes: Array = []
		for c in b.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape:
				var sh := (c as CollisionShape3D).shape
				var sz := ""
				if sh is BoxShape3D:
					sz = str((sh as BoxShape3D).size)
				elif sh is CylinderShape3D:
					sz = "cyl r%.2f h%.2f" % [(sh as CylinderShape3D).radius, (sh as CylinderShape3D).height]
				elif sh is SphereShape3D:
					sz = "sph r%.2f" % (sh as SphereShape3D).radius
				else:
					sz = sh.get_class()
				shapes.append({"at": _v((c as Node3D).global_position), "shape": sz, "disabled": (c as CollisionShape3D).disabled})
		if shapes.is_empty():
			continue
		inv.append({"name": _rel(b), "pos": _v((b as Node3D).global_position), "shapes": shapes.slice(0, 4), "n_shapes": shapes.size()})
	a["invisible_solid_bodies"] = inv
	a["node_count"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	a["mesh_instances"] = _all_of(world, func(n: Node) -> bool: return n is MeshInstance3D, []).size()
	var lights := _all_of(world, func(n: Node) -> bool: return n is OmniLight3D or n is SpotLight3D, [])
	var shadow_lights := 0
	for l in lights:
		if (l as Light3D).shadow_enabled:
			shadow_lights += 1
	a["local_lights"] = lights.size()
	a["local_shadow_lights"] = shadow_lights
	a["gpu_particles"] = _all_of(world, func(n: Node) -> bool: return n is GPUParticles3D, []).size()
	a["cpu_particles"] = _all_of(world, func(n: Node) -> bool: return n is CPUParticles3D, []).size()
	a["bodies"] = _all_of(world, func(n: Node) -> bool: return n is CollisionObject3D, []).size()
	a["areas"] = _all_of(world, func(n: Node) -> bool: return n is Area3D, []).size()
	a["label3d"] = _all_of(world, func(n: Node) -> bool: return n is Label3D, []).size()
	report["audit"] = a
	log_line("AUDIT truffles missing=%s dup=%s unexpected=%s acorn_nodes=%d crates=%d(%d) enemies=%d buried=%d nofloor=%d invisible_solids=%d" % [missing, dup, unexpected, acorns.size(), crates.size(), crate_acorns, en.size(), buried.size(), below.size(), inv.size()])


# ------------------------------------------------------------------ phase 2: idle at spawn (30 s)

func _idle_at_spawn() -> void:
	var start := {}
	for e in get_tree().get_nodes_in_group("enemy"):
		start[e] = (e as Node3D).global_position
	var p0 := player.global_position
	var s := await _measure("spawn_gameplay_idle", 1.0, 12.0)
	_shot("idle_spawn_gameplay")
	await _wait(18.0)
	var drift: Array = []
	for e in start.keys():
		if not is_instance_valid(e):
			drift.append({"name": "(freed)"})
			continue
		var p: Vector3 = (e as Node3D).global_position
		var d: Vector3 = p - start[e]
		var row := {"name": _rel(e), "start": _v(start[e]), "end": _v(p), "dy": snappedf(d.y, 0.01), "moved": snappedf(d.length(), 0.01), "state": str(e.get("state")), "floor_now": _ray_down(p, 0.6, 6.0)}
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
		res.append(await _measure(n, 1.5, 5.0))
		_shot("fps_%s" % n)
	if prev:
		prev.make_current()
	report["storycams"] = res


# ------------------------------------------------------------------ phase 4: drop tests + gameplay fps

func _drops() -> void:
	for n in get_tree().get_nodes_in_group("truffle"):
		if n is Area3D:
			(n as Area3D).set_deferred("monitoring", false)
	for pg in _all_of(world, func(n: Node) -> bool: return n is LostPage, []):
		(pg as Area3D).set_deferred("monitoring", false)
	var pts: Array = []
	var spawns := world.get_node_or_null("Spawns")
	if spawns:
		for m in spawns.get_children():
			if m is Node3D:
				pts.append(["spawn:" + str(m.name), (m as Node3D).global_position])
	for c in _all_of(world, func(n: Node) -> bool: return n is CheckpointBookmark, []):
		pts.append(["cp:" + str(c.name), (c as Node3D).global_position])
	for s in report.get("audit", {}).get("truffle_sources", []):
		pts.append(["reward:" + str(s["id"]), Vector3(s["pos"][0], s["pos"][1], s["pos"][2])])
	for pg in report.get("audit", {}).get("pages", []):
		var p := Vector3(pg["pos"][0], pg["pos"][1], pg["pos"][2])
		var fl: Dictionary = pg["floor"]
		if not fl.is_empty():
			p.y = float(fl["y"])
		pts.append(["page:" + str(pg["name"]), p])
	# Runtime truffle points (from the code): W3-6 cage reward, W3-8 geode reward.
	pts.append(["runtime:W3-6", Vector3(-8.6, 100.8, -27.6)])
	pts.append(["runtime:W3-8", Vector3(-44, 5.8, -39.6)])
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
		_heal()
		var dmg0 := damage_log.size()
		_place_player(drop_from)
		var fps := await _measure("gp:" + str(pt[0]), 0.6, 1.8)
		var end := player.global_position
		var row := {"name": pt[0], "target": _v(p), "drop_from": _v(drop_from), "end": _v(end), "on_floor": player.is_on_floor(),
			"fell": snappedf(drop_from.y - end.y, 0.01), "horiz_drift": snappedf(Vector2(end.x - drop_from.x, end.z - drop_from.z).length(), 0.01),
			"floor": fl, "damage": damage_log.size() - dmg0, "fps": fps, "state": str(player.call("get_state_name")) if player.has_method("get_state_name") else ""}
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
		_shot("gp_%s" % str(pt[0]).replace(":", "_"))
	report["drops"] = res


# ------------------------------------------------------------------ phase 5: engagement (does every enemy react?)

func _engage() -> void:
	var res: Array = []
	var kill_y := float(world.get("kill_y"))
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("is_defeated")):
			continue
		var e3 := e as Node3D
		var ep := e3.global_position
		var spot := Vector3.INF
		for dir in [Vector3(5, 0, 0), Vector3(-5, 0, 0), Vector3(0, 0, 5), Vector3(0, 0, -5), Vector3(3.5, 0, 3.5), Vector3(-3.5, 0, -3.5)]:
			var fl := _ray_down(ep + dir + Vector3(0, 3, 0), 0.6, 14.0)
			if fl.is_empty():
				continue
			var cand := Vector3(ep.x + dir.x, float(fl["y"]) + 0.05, ep.z + dir.z)
			if absf(cand.y - ep.y) < 3.5 and _embedded(cand).is_empty():
				spot = cand
				break
		if spot == Vector3.INF:
			res.append({"name": _rel(e), "skipped": "no floor spot within 5 m at a similar height"})
			continue
		_heal()
		var dmg0 := damage_log.size()
		var hp0 := int(game.get("health")) if game else -1
		var st0 := str(e.get("state"))
		_place_player(spot, atan2(-(ep.x - spot.x), -(ep.z - spot.z)))
		var states := {}
		var closest := 999.0
		var t := 0.0
		while t < 5.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			if not is_instance_valid(e):
				break
			states[str(e.get("state"))] = true
			closest = minf(closest, (e as Node3D).global_position.distance_to(player.global_position))
		var row := {"name": _rel(e), "script": str(e.get_script().resource_path.get_file()) if e.get_script() else "", "enemy_start": _v(ep), "player_at": _v(spot), "state_before": st0}
		if is_instance_valid(e):
			var p: Vector3 = (e as Node3D).global_position
			row["enemy_end"] = _v(p)
			row["moved"] = snappedf(p.distance_to(ep), 0.01)
			row["states_seen"] = states.keys()
			row["closest_m"] = snappedf(closest, 0.01)
			row["floor_end"] = _ray_down(p, 0.6, 8.0)
			if p.y < kill_y or not p.is_finite() or p.y < ep.y - 3.0:
				row["flag"] = "ENEMY_FELL"
		else:
			row["freed"] = true
		row["damage_events"] = damage_log.size() - dmg0
		row["health_after"] = int(game.get("health")) if game else -1
		row["health_before"] = hp0
		res.append(row)
		log_line("ENGAGE " + JSON.stringify(row))
		_shot("engage_%s" % str(e.name))
		_place_player(Vector3(0, 2.1, 48))
		await _wait(0.6)
	_heal()
	report["engage"] = res


# ------------------------------------------------------------------ phase 6: enemy API hits

func _enemy_hits() -> void:
	_place_player(Vector3(0, 2.1, 48))
	var res: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("hit_by_player"):
			continue
		var landed_any := false
		var kinds_landed: Array = []
		var kinds_blocked: Array = []
		for k in ["punch", "jump_kick", "stomp", "slam", "dive", "slide"]:
			for side in ["front", "back"]:
				if not is_instance_valid(e) or bool(e.get("is_defeated")):
					break
				var e3 := e as Node3D
				var fwd := -e3.global_transform.basis.z
				var from := e3.global_position + Vector3(0, 0.4, 0) + (fwd if side == "front" else -fwd) * 1.0
				if k == "stomp" or k == "slam":
					from = e3.global_position + Vector3(0, 1.6, 0)
				var landed: bool = e.call("hit_by_player", k, from)
				if landed:
					landed_any = true
					kinds_landed.append(k + "@" + side)
				else:
					kinds_blocked.append(k + "@" + side)
				await _wait(0.4)
		res.append({"name": str(e.name) if is_instance_valid(e) else "(freed)", "landed": landed_any, "kinds_landed": kinds_landed, "kinds_not_landed": kinds_blocked,
			"defeated": (not is_instance_valid(e)) or bool(e.get("is_defeated"))})
	await _wait(4.0)
	var spawned: Array = []
	for t in get_tree().get_nodes_in_group("truffle"):
		spawned.append(str(t.get("truffle_id")))
	var low_acorns: Array = []
	for ac in _all_of(world, func(n: Node) -> bool: return n is Acorn, []):
		var p: Vector3 = (ac as Node3D).global_position
		if p.y < float(world.get("kill_y")) + 1.0:
			low_acorns.append(_v(p))
	report["enemy_hits"] = {"rows": res, "truffles_present_after": spawned, "acorns_lost_below_kill_y": low_acorns, "truffles_collected_during": truffle_log.duplicate()}
	log_line("ENEMY HITS truffles_after=%s rows=%d" % [spawned, res.size()])


# ------------------------------------------------------------------ phase 7: kitchen containment

func _kitchen() -> void:
	_heal()
	var k := {}
	var kroot := world.find_child("Kitchen", true, false)
	k["kitchen_found"] = kroot != null
	k["door_bar_present"] = kroot != null and kroot.get_node_or_null("DoorBar") != null
	# Land in the hearth like the chimney entry does.
	_place_player(Vector3(-2.4, 104.5, -29), deg_to_rad(90.0))
	await _wait(2.0)
	k["after_entry"] = _v(player.global_position)
	k["camera"] = str(get_viewport().get_camera_3d().name) if get_viewport().get_camera_3d() else ""
	_shot("kitchen_entry")
	# Walk into the barred door from inside (time the run to the oven's cold window is not needed; just push south).
	_place_player(Vector3(-6.0, 100.1, -26.0), PI)
	await _wait(0.2)
	var t := 0.0
	var dmg0 := damage_log.size()
	while t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		player.velocity.x = 0.0
		player.velocity.z = 5.0
	k["after_pushing_door_3s"] = _v(player.global_position)
	k["escaped_through_barred_door"] = player.global_position.y < 99.0 or player.global_position.z > -23.6
	k["damage_while_at_door"] = damage_log.size() - dmg0
	# Any open path out besides the door? Probe a ring of horizontal rays at head height from the room centre.
	var leaks: Array = []
	for i in 36:
		var a := TAU * i / 36.0
		for h in [100.6, 102.0, 104.0, 105.6]:
			var from := Vector3(-6, h, -29)
			var to := from + Vector3(cos(a), 0, sin(a)) * 12.0
			var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
			q.exclude = [player.get_rid()]
			var hit := _space().intersect_ray(q)
			if hit.is_empty():
				leaks.append({"deg": i * 10, "h": h})
	k["ray_leaks_from_centre"] = leaks
	_heal()
	_place_player(Vector3(0, 2.1, 48))
	await _wait(1.0)
	report["kitchen"] = k
	log_line("KITCHEN " + JSON.stringify(k))


# ------------------------------------------------------------------ phase 8: inspection views (temporary runtime camera)

func _views() -> void:
	var shots := [
		["cliff_top_from_east", Vector3(-26, 26, -36), Vector3(-48, 12, -49)],
		["cliff_top_page1", Vector3(-42, 22, -40), Vector3(-52, 13, -50.5)],
		["cliff_top_from_south", Vector3(-45, 20, -22), Vector3(-46, 10, -48)],
		["maze_from_south", Vector3(-46, 20, 34), Vector3(-46, 4, 15)],
		["maze_overhead", Vector3(-46, 34, 22), Vector3(-46, 4, 15.5)],
		["tierA_slide_acorns", Vector3(40, 18, -16), Vector3(44, 12.5, -27)],
		["cottage_roof_acorns", Vector3(-6, 20, -13), Vector3(-6, 16.5, -27)],
		["cp8_syrup_pool", Vector3(-28, 7, -25), Vector3(-35, 1.5, -33)],
		["balcony_and_runway", Vector3(58, 9, 44), Vector3(70, 1, 34.5)],
		["kitchen_from_cam", Vector3(-6, 104.4, -21.0), Vector3(-6, 101.0, -29.4)],
	]
	var cam := Camera3D.new()
	cam.name = "QAViewCam"
	cam.fov = 60.0
	world.add_child(cam)
	var prev := get_viewport().get_camera_3d()
	_place_player(Vector3(0, 2.1, 48))
	for s in shots:
		cam.global_transform = Transform3D(Basis(), s[1]).looking_at(s[2], Vector3.UP)
		cam.make_current()
		await _wait(0.8)
		_shot("view_%s" % s[0])
		log_line("VIEW " + str(s[0]))
	if prev:
		prev.make_current()
	cam.queue_free()


# ------------------------------------------------------------------ phase 9: joust abandonment / summit idle

func _watch(sec: float, label: String) -> Dictionary:
	var jumps: Array = []
	var last := player.global_position
	var t := 0.0
	var js := world.find_child("*Joust*", true, false)
	var states := {}
	while t < sec:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var p := player.global_position
		if p.distance_to(last) > 4.0:
			jumps.append({"t": snappedf(t, 0.01), "from": _v(last), "to": _v(p)})
		last = p
		if js:
			states[str(js.get("state"))] = true
	return {"label": label, "teleports": jumps, "end": _v(player.global_position), "joust_states": states.keys(), "joust_node": str(js.name) if js else ""}


func _joust() -> void:
	var res := {}
	_heal()
	var j := world.find_child("*Joust*", true, false)
	if j == null:
		for n in _all_of(world, func(x: Node) -> bool: return x.has_method("bot_lat"), []):
			j = n
	res["joust_found"] = j != null
	res["joust_path"] = _rel(j) if j else ""
	# A: land on the summit next to the gate, then walk away by teleport to the glade (models jumping off / taking the lift).
	_place_player(Vector3(41.0, 28.2, -41.5))
	await _wait(1.2)
	res["state_after_summit_landing"] = str(j.get("state")) if j else ""
	_place_player(Vector3(0, 2.1, 46))
	res["abandon_to_glade"] = await _watch(20.0, "abandon_to_glade")
	_shot("joust_abandon_end")
	_heal()
	await _wait(3.0)
	# B: stand idle on the summit for 30 s (explorer at the cherry / summit acorns).
	_place_player(Vector3(39.6, 28.2, -42.6))
	res["summit_idle_30s"] = await _watch(30.0, "summit_idle")
	_heal()
	_place_player(Vector3(0, 2.1, 48))
	await _wait(1.0)
	report["joust"] = res
	log_line("JOUST " + JSON.stringify(res))


# ------------------------------------------------------------------ phase 10: do the W3-8 geodes crack on a plain landing?

func _geode() -> void:
	var res: Array = []
	var cracked_log: Array = []
	for i in 3:
		var gn := world.find_child("Geode%d" % i, true, false) as Node3D
		if gn == null:
			res.append({"geode": i, "missing": true})
			continue
		var before := bool(gn.get_meta("cracked", false))
		_heal()
		# Plain fall from 1.6 m above the geode centre, no input.
		_place_player(gn.global_position + Vector3(0, 1.6, 0))
		var states := {}
		var t := 0.0
		while t < 2.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			states[str(player.call("get_state_name"))] = true
		var after := bool(gn.get_meta("cracked", false))
		res.append({"geode": i, "pos": _v(gn.global_position), "cracked_before": before, "cracked_after_plain_fall": after, "player_end": _v(player.global_position), "states": states.keys()})
		# Walk-into test: stand beside it for 1 s.
		_place_player(gn.global_position + Vector3(0, -0.4, 1.0))
		await _wait(1.0)
		res[-1]["cracked_after_walk_into"] = bool(gn.get_meta("cracked", false))
	report["geode"] = {"rows": res, "truffles": truffle_log.duplicate()}
	log_line("GEODE " + JSON.stringify(report["geode"]))
	_place_player(Vector3(0, 2.1, 48))
	await _wait(0.5)

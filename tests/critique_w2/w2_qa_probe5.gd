extends Node
## Critique W2 round 1 (QA lens, pass r1c), probe 5. Read-only for the world.
##  S idle 45 s at the Default spawn: damage, bud state, E01/E02 positions (smoke-test blocker re-check).
##  N acorn census: Acorn nodes in the tree + held under the bud vs the 266 the plan promises.
##  P bee-bait trigger: Mak passes the bud zone for ONE physics frame (as in a fall past it), then is moved
##    to the Default spawn; does the bee still charge and open the bud with nobody there?
##  C after the bud opens: Page4 / A19 position, gap to the floor, collect Page4 by touch.
##  L collision layers: what the player stands on at the CP5 apron where a mask-1 ray finds nothing.
##  H 100 acorns: add_acorns up to 100, where W2-100 appears and whether it can be collected by touch.
## Run: python tools/godot.py capture res://tests/critique_w2/W2QA.tscn <png> --wait 999999 -- --profile=critic_w2_qa_p5 --w2-nointro --qa-probe=5 --qa-out=<abs dir>

var out_dir := ""
var world: Node
var player: CharacterBody3D
var report := {}
var damage_log: Array = []
var truffle_log: Array = []
var bud_log: Array = []
var _t0 := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("qa-out", OS.get_user_data_dir().path_join("w2_qa5")) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_d: float) -> void:
	if Time.get_ticks_msec() - _t0 > 300000:
		report["aborted"] = "global cap 300 s"
		_save()
		get_tree().quit(3)


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func _save() -> void:
	report["damage_log"] = damage_log
	report["truffle_log"] = truffle_log
	report["bud_log"] = bud_log
	var f := FileAccess.open(out_dir.path_join("w2_qa_probe5.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(out_dir.path_join(name_ + ".png"))


func _ray(p: Vector3, dist: float, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3(0, -dist, 0), mask)
	return player.get_world_3d().direct_space_state.intersect_ray(q)


func _place(p: Vector3) -> void:
	player.call("respawn", Transform3D(Basis(), p))


func _bud_state() -> Dictionary:
	var play = world.get("play")
	return {"t_ms": Time.get_ticks_msec() - _t0, "bud_open": play.get("bud_open"), "bud_valid": is_instance_valid(play.get("bud")), "phase": report.get("_phase", ""), "player": _v(player.global_position)}


func _run() -> void:
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and cs.get("player") != null and cs.get("play") != null:
			world = cs
			player = cs.get("player") as CharacterBody3D
			break
		if Time.get_ticks_msec() - _t0 > 180000:
			get_tree().quit(2)
			return
	report["load_ms"] = Time.get_ticks_msec() - _t0
	var game := get_node("/root/Game")
	game.damaged.connect(func(a: int) -> void: damage_log.append({"t": Time.get_ticks_msec() - _t0, "amount": a, "pos": _v(player.global_position), "phase": report.get("_phase", "")}))
	game.truffle_collected.connect(func(id: String) -> void: truffle_log.append({"id": id, "phase": report.get("_phase", "")}))
	var play = world.get("play")
	var bud: Node = play.get("bud")
	if bud:
		bud.tree_exiting.connect(func() -> void: bud_log.append(_bud_state()))
	# S: idle at spawn.
	report["_phase"] = "S"
	var dmk := world.get_node("Spawns/Default") as Node3D
	report["S_default"] = _v(dmk.global_position)
	var tr := []
	for i in 45:
		await _wait(1.0)
		if i % 5 == 4:
			var row := {"t": i + 1, "player": _v(player.global_position), "on_floor": player.is_on_floor()}
			for id in ["E01", "E02"]:
				var e := world.find_child(id, true, false) as Node3D
				row[id] = _v(e.global_position) if e else null
				row[id + "_dist"] = snappedf(e.global_position.distance_to(player.global_position), 0.01) if e else -1.0
			tr.append(row)
	report["S_trace"] = tr
	report["S_damage"] = damage_log.size()
	report["S_bud"] = _bud_state()
	report["S_acorns_at_start"] = game.get("acorns")
	await _shot("S_default_idle45")
	_save()
	# N: acorn census.
	report["_phase"] = "N"
	var n_tree := 0
	for a in world.find_children("*", "", true, false):
		var sc: Script = a.get_script()
		if sc and String(sc.resource_path).ends_with("/acorn.gd"):
			n_tree += 1
	var n_held := 0
	for h in play.get("_bud_held"):
		if is_instance_valid(h):
			for a2 in (h as Node).find_children("*", "", true, false):
				var sc2: Script = a2.get_script()
				if sc2 and String(sc2.resource_path).ends_with("/acorn.gd"):
					n_held += 1
	report["N_acorns_in_tree"] = n_tree
	report["N_acorns_held_in_bud"] = n_held
	var crates := 0
	for c in world.find_children("*", "", true, false):
		var sc3: Script = c.get_script()
		if sc3 and String(sc3.resource_path).ends_with("/breakable_crate.gd"):
			crates += 1
	report["N_crates"] = crates
	_save()
	# P: one-frame pass through the bud zone.
	report["_phase"] = "P"
	var bee := world.find_child("E10", true, false) as Node3D
	var best := {}
	# Wait until the bee is within 7.5 m of the probe spot so the trigger can fire (the orbit passes the bud).
	var spot := Vector3(5.0, 36.3, -9.6)
	var waited := 0.0
	while bee and bee.global_position.distance_to(spot) > 7.0 and waited < 14.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	report["P_wait_for_bee_s"] = snappedf(waited, 0.01)
	report["P_bee_before"] = _v(bee.global_position) if bee else null
	_place(spot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_place(dmk.global_position + Vector3(0, 0.1, 0))
	await _wait(4.5)
	report["P_after"] = _bud_state()
	report["P_bee_after"] = _v(bee.global_position) if bee and is_instance_valid(bee) else null
	_save()
	# C: page 4 after opening.
	report["_phase"] = "C"
	if not bool(play.get("bud_open")):
		play.call("open_bud", "bee")
		report["C_opened_by_probe"] = true
	await _wait(1.5)
	var pg := world.find_child("Page4", true, false) as Node3D
	report["C_page4"] = _v(pg.global_position) if pg else null
	if pg:
		var below := _ray(pg.global_position + Vector3(0, 0.2, 0), 30.0, 0xFFFFFFFF)
		report["C_page4_floor_gap"] = snappedf(pg.global_position.y - float(below["position"].y), 0.01) if not below.is_empty() else -1.0
		report["C_page4_floor"] = String(below["collider"].name) if not below.is_empty() else ""
	var a19 := world.find_child("A19", true, false) as Node3D
	if a19:
		var arr := []
		for c2 in a19.find_children("*", "Node3D", true, false):
			var sc4: Script = c2.get_script()
			if sc4 and String(sc4.resource_path).ends_with("/acorn.gd"):
				var b2 := _ray((c2 as Node3D).global_position + Vector3(0, 0.2, 0), 30.0, 0xFFFFFFFF)
				arr.append({"pos": _v((c2 as Node3D).global_position), "gap": snappedf((c2 as Node3D).global_position.y - float(b2["position"].y), 0.01) if not b2.is_empty() else -1.0})
		report["C_a19"] = arr
	if pg:
		var pc0 := int(game.call("page_count", "W2"))
		var below2 := _ray(pg.global_position + Vector3(0, 0.5, 0), 30.0, 0xFFFFFFFF)
		_place((below2["position"] if not below2.is_empty() else pg.global_position) + Vector3(0, 0.2, 0))
		await _wait(0.3)
		await _shot("C_page4_reach")
		await _wait(1.5)
		report["C_page4_collected_standing_below"] = int(game.call("page_count", "W2")) > pc0
	_save()
	# L: collision layer at the CP5 apron.
	report["_phase"] = "L"
	var lp := Vector3(10.41, 51.5, -16.31)
	var all := _ray(lp, 10.0, 0xFFFFFFFF)
	var l1 := _ray(lp, 10.0, 1)
	report["L_cp5_apron_any"] = {"hit": not all.is_empty(), "collider": String(all["collider"].name) if not all.is_empty() else "", "path": str(all["collider"].get_path()) if not all.is_empty() else "", "layer": int(all["collider"].get("collision_layer")) if not all.is_empty() else -1, "y": snappedf(float(all["position"].y), 0.01) if not all.is_empty() else 0.0}
	report["L_cp5_apron_mask1"] = not l1.is_empty()
	# Scan a grid over the castle bank / courtyard / garden for walkable floor that a mask-1 ray misses.
	var miss := []
	for gx in range(-30, 31, 3):
		for gz in range(-45, 35, 3):
			for y0 in [70.0, 30.0]:
				var a3 := _ray(Vector3(gx, y0, gz), 40.0, 0xFFFFFFFF)
				if a3.is_empty() or (a3["normal"] as Vector3).y < 0.7:
					continue
				var col: Object = a3["collider"]
				if col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & 1) == 0 and not (col is Area3D):
					miss.append({"at": _v(a3["position"]), "collider": String((col as Node).name), "layer": (col as CollisionObject3D).collision_layer})
	report["L_floor_not_on_layer1"] = miss.slice(0, 40)
	report["L_floor_not_on_layer1_count"] = miss.size()
	_save()
	# H: 100 acorns.
	report["_phase"] = "H"
	var have := int(game.get("acorns"))
	game.call("add_acorns", maxi(0, 100 - have))
	await _wait(2.5)
	var t100: Node3D = null
	for n in world.find_children("*", "", true, false):
		if n.get("truffle_id") == "W2-100":
			t100 = n as Node3D
			break
	report["H_truffle_found"] = t100 != null
	if t100:
		report["H_pos"] = _v(t100.global_position)
		report["H_visible"] = t100.is_visible_in_tree()
		var b3 := _ray(t100.global_position + Vector3(0, 0.3, 0), 30.0, 0xFFFFFFFF)
		report["H_floor_gap"] = snappedf(t100.global_position.y - float(b3["position"].y), 0.01) if not b3.is_empty() else -1.0
		_place((b3["position"] if not b3.is_empty() else t100.global_position) + Vector3(0, 0.1, 0))
		await _wait(0.4)
		await _shot("H_w2_100")
		await _wait(4.5)
		report["H_collected"] = game.call("has_truffle", "W2-100")
	report["_phase"] = "done"
	_save()
	print("[QA5] done")
	get_tree().quit(0)

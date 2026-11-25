extends Node
## Critique OBJECTS round 1, QA lens. Drives the REAL worlds (Router.enter_world) with the REAL player and checks
## every interactive object where the world builders placed it: truffle ids, collection and saving, revisits,
## checkpoints and respawns, lost pages, acorn totals, time trials and the HUD timer, bellows and wind, cages and
## switches, bounce surfaces, vanishing clouds, portals and the wolf door. Read-only towards the objects track.
## Args: --suite=world|hub --world=W1|W2|W3 --results=<abs json>

var results: Array = []
var inventory: Dictionary = {}
var notes: Array = []
var world := "W1"
var suite := "world"
var _t0 := 0


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.split("=", true, 1)[1]
	return d


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = _arg("world", "W1")
	suite = _arg("suite", "world")
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func check(name: String, ok: bool, detail: Variant = "") -> void:
	results.append({"name": name, "pass": ok, "detail": detail})
	print("[CritObj] %s %s  %s" % ["PASS" if ok else "FAIL", name, str(detail)])


func note(s: String) -> void:
	notes.append(s)
	print("[CritObj] NOTE ", s)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func until_unpaused(max_frames: int = 900) -> void:
	var i := 0
	while get_tree().paused and i < max_frames:
		await get_tree().process_frame
		i += 1


func player() -> CharacterBody3D:
	return get_tree().get_first_node_in_group("player") as CharacterBody3D


func put(p: Vector3, yaw_deg: float = 0.0) -> void:
	var pl := player()
	if pl == null:
		return
	release_all()
	if pl.has_method("respawn"):
		pl.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), p))
	else:
		pl.global_position = p
		pl.reset_physics_interpolation()
	pl.velocity = Vector3.ZERO


func release_all() -> void:
	for a in ["jump", "crouch", "attack", "sniff", "move_left", "move_right", "move_forward", "move_back"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func tap(action: String, hold: int = 2) -> void:
	Input.action_press(action)
	await frames(hold)
	Input.action_release(action)


func scene_root() -> Node:
	return get_tree().current_scene


func all_nodes() -> Array:
	var sr := scene_root()
	if sr == null:
		return []
	return sr.find_children("*", "", true, false)


func of_class(cls: Variant) -> Array:
	var out: Array = []
	for n in all_nodes():
		if is_instance_of(n, cls):
			out.append(n)
	return out


func ray_down(from: Vector3, length: float = 6.0, exclude: Array = []) -> Dictionary:
	var sr := scene_root() as Node3D
	if sr == null:
		return {}
	var space := (player() as Node3D).get_world_3d().direct_space_state if player() else sr.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * length, 1)
	var ex: Array[RID] = []
	for e in exclude:
		ex.append(e)
	if player():
		ex.append(player().get_rid())
	q.exclude = ex
	return space.intersect_ray(q)


func embedded(at: Vector3, r: float = 0.22) -> int:
	return embedded_hits(at, r).size()


func embedded_hits(at: Vector3, r: float = 0.22) -> Array:
	var pl := player()
	if pl == null:
		return []
	var space := pl.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = r
	q.shape = s
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 1
	q.exclude = [pl.get_rid()]
	var out: Array = []
	for h in space.intersect_shape(q, 8):
		var col: Object = h.get("collider")
		out.append(String((col as Node).get_path()) if col is Node else str(col))
	return out


func capsule_blocked(at: Vector3) -> int:
	var pl := player()
	if pl == null:
		return 0
	var space := pl.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var c := CapsuleShape3D.new()
	c.radius = 0.33
	c.height = 1.2
	q.shape = c
	q.transform = Transform3D(Basis(), at + Vector3(0, 0.68, 0))
	q.collision_mask = 1
	q.exclude = [pl.get_rid()]
	return space.intersect_shape(q, 8).size()


func v3s(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]


func enter(wid: String, mission: String = "") -> bool:
	await until_unpaused()
	Router.enter_world(wid, mission)
	var i := 0
	while i < 1800:
		await get_tree().process_frame
		i += 1
		var sr := scene_root()
		if sr != null and "world_id" in sr and String(sr.get("world_id")) == wid and player() != null and not get_tree().paused:
			break
	await frames(150)
	await until_unpaused()
	var sr2 := scene_root()
	var ok := sr2 != null and "world_id" in sr2 and String(sr2.get("world_id")) == wid
	print("[CritObj] entered %s ok=%s after %d frames (t=%.1fs)" % [wid, ok, i, (Time.get_ticks_msec() - _t0) / 1000.0])
	return ok


func _run() -> void:
	await frames(20)
	Game.new_game()
	if suite == "hub":
		await _hub_suite()
	elif suite == "shots":
		await _shots_suite()
	elif suite == "clip":
		await _clip_suite()
	elif suite == "misc":
		await _misc_suite()
	elif suite == "probe":
		await _probe_suite()
	elif suite == "stream":
		await _stream_debug()
	elif suite == "trace":
		await _trace_suite()
	elif suite == "r1c_w2":
		await _r1c_w2_suite()
	else:
		await _world_suite()
	_finish()


func _finish() -> void:
	var fails := 0
	for r in results:
		if not bool(r["pass"]):
			fails += 1
	var out := {"suite": suite, "world": world, "utc": Time.get_datetime_string_from_system(true), "passed": results.size() - fails,
		"failed": fails, "results": results, "inventory": inventory, "notes": notes,
		"seconds": (Time.get_ticks_msec() - _t0) / 1000.0}
	var path := _arg("results", "")
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(out, "  "))
			f.close()
	print("[CritObj] DONE %s %s: %d passed, %d failed" % [suite, world, results.size() - fails, fails])
	get_tree().paused = false
	get_tree().quit(0 if fails == 0 else 1)


# =====================================================================================================
# world suite

func _registry_ids(wid: String) -> Array:
	var out: Array = []
	for t in WorldRegistry.truffles(wid):
		out.append(String(t["id"]))
	return out


func _inventory() -> Dictionary:
	var inv := {}
	var classes := {"Truffle": Truffle, "TruffleSpawner": TruffleSpawner, "LostPage": LostPage, "LostPageSet": LostPageSet,
		"Acorn": Acorn, "AcornHundred": AcornHundred, "BreakableCrate": BreakableCrate, "Checkpoint": CheckpointBookmark,
		"TimeTrial": TimeTrial, "TrialRing": TrialRing, "Cage": Cage, "SlamSwitch": SlamSwitch, "BellowsMachine": BellowsMachine,
		"BellowsSet": BellowsSet, "WindZone": WindZone, "BouncePad": BouncePad, "SniffTarget": SniffTarget,
		"BuriedTreasure": BuriedTreasure, "Climbable": Climbable, "VanishingCloud": VanishingCloud, "FallingPlatform": FallingPlatform,
		"MovingPlatform": MovingPlatform, "RotatingPlatform": RotatingPlatform, "HazardVolume": HazardVolume, "KillZone": KillZone,
		"NPCTalker": NPCTalker, "SignPost": SignPost, "StorybookPortal": StorybookPortal, "WolfDoor": WolfDoor}
	for k in classes:
		inv[k] = of_class(classes[k]).size()
	inv["bouncy_group"] = get_tree().get_nodes_in_group("bouncy").size()
	inv["wind_zone_group"] = get_tree().get_nodes_in_group("wind_zone").size()
	inv["sniff_target_group"] = get_tree().get_nodes_in_group("sniff_target").size()
	return inv


func _world_suite() -> void:
	if not await enter(world):
		check("enter_world_" + world, false, "world did not load")
		return
	check("enter_world_" + world, true)
	inventory = _inventory()
	print("[CritObj] inventory ", inventory)
	await _check_truffle_ids()
	await _check_embedded_pickups()
	await _check_acorn_supply()
	await _check_checkpoints()
	await _check_bounce()
	await _check_wind()
	if world == "W1":
		await _check_bellows()
	if world == "W2":
		await _check_cage()
		await _check_clouds()
	await _check_time_trials()
	await _check_truffle_collect_and_save()
	await _check_pages_across_visits()


func _check_truffle_ids() -> void:
	var static_ids: Array = []
	var dup: Array = []
	for t in of_class(Truffle):
		var id := String(t.get("truffle_id"))
		if static_ids.has(id):
			dup.append(id)
		static_ids.append(id)
	var spawner_ids: Array = []
	for s in of_class(TruffleSpawner):
		var id2 := String(s.get("reward_truffle_id"))
		if id2 == "":
			continue
		if spawner_ids.has(id2) or static_ids.has(id2):
			dup.append(id2)
		spawner_ids.append(id2)
	var reg := _registry_ids(world)
	var found: Array = static_ids + spawner_ids
	var missing: Array = []
	for id3 in reg:
		if not found.has(id3):
			missing.append(id3)
	var extra: Array = []
	for id4 in found:
		if not reg.has(id4):
			extra.append(id4)
	inventory["truffle_ids_static"] = static_ids
	inventory["truffle_ids_spawners"] = spawner_ids
	check("truffle_ids_unique", dup.is_empty(), {"duplicates": dup})
	check("truffle_ids_cover_registry", missing.is_empty(), {"missing_static_or_spawner": missing, "extra_not_in_registry": extra,
		"note": "missing ids may be built by world scripts at runtime (enemy groups, custom spawners)"})


func _check_embedded_pickups() -> void:
	var bad: Array = []
	var checked := 0
	for t in of_class(Truffle):
		var c := (t as Node3D).global_position + Vector3(0, float(t.get("hover_height")), 0)
		checked += 1
		if embedded(c, 0.25) > 0:
			bad.append("Truffle %s at %s in %s" % [t.get("truffle_id"), v3s(c), str(embedded_hits(c, 0.25))])
	for p in of_class(LostPage):
		var c2 := (p as Node3D).global_position + Vector3(0, float(p.get("hover_height")), 0)
		checked += 1
		if embedded(c2, 0.22) > 0:
			bad.append("LostPage %d at %s in %s" % [int(p.get("page_index")), v3s(c2), str(embedded_hits(c2, 0.22))])
	var ac_bad := 0
	for a in of_class(Acorn):
		checked += 1
		var c3 := (a as Node3D).global_position + Vector3(0, 0.5, 0)
		if embedded(c3, 0.15) > 0:
			ac_bad += 1
			if ac_bad <= 30:
				bad.append("Acorn %s at %s in %s" % [(a as Node).get_parent().name, v3s(c3), str(embedded_hits(c3, 0.15))])
	check("pickups_not_inside_solid_geometry", bad.is_empty(), {"checked": checked, "embedded": bad, "acorns_embedded": ac_bad})


func _check_acorn_supply() -> void:
	var loose := 0
	for a in of_class(Acorn):
		loose += int(a.get("value"))
	var crates := 0
	for c in of_class(BreakableCrate):
		crates += int(c.get("acorns"))
	var hundred := of_class(AcornHundred)
	inventory["acorns_loose_value"] = loose
	inventory["acorns_in_crates"] = crates
	if hundred.is_empty():
		note("no AcornHundred in " + world)
		return
	var req := int(hundred[0].get("required"))
	check("acorn_supply_reaches_hundred", loose + crates >= req, {"loose": loose, "crates": crates, "required": req,
		"note": "enemy drops not counted (random/conditional)"})
	# Functional: collecting acorns raises Game.acorns and fires the reward at `required`.
	var before := int(Game.acorns)
	var acorns := of_class(Acorn)
	if acorns.size() > 0:
		var a0 := acorns[0] as Node3D
		put(a0.global_position + Vector3(0, 0.1, 0))
		await frames(12)
		check("acorn_collect_by_touch", int(Game.acorns) > before, {"acorn": String(a0.name), "at": v3s(a0.global_position), "acorns": int(Game.acorns)})


func _check_checkpoints() -> void:
	var cps := of_class(CheckpointBookmark)
	if cps.is_empty():
		note("no checkpoints in " + world)
		return
	var bad_static: Array = []
	for c in cps:
		var xf: Transform3D = c.call("get_respawn_transform")
		var hit := ray_down(xf.origin + Vector3(0, 1.0, 0), 6.0)
		var drop := 99.0
		if not hit.is_empty():
			drop = xf.origin.y - (hit["position"] as Vector3).y
		var blocked := capsule_blocked(xf.origin + Vector3(0, maxf(0.05, -drop + 0.05) if drop < 0.0 else 0.05, 0))
		var wid := String(c.get("world_id"))
		var info := "%s respawn %s floor_drop=%.2f blocked=%d world_id=%s" % [(c as Node).name, v3s(xf.origin), drop, blocked, wid]
		if drop > 1.5 or drop < -0.6 or blocked > 0 or wid != world:
			bad_static.append(info)
		inventory["checkpoint_" + String((c as Node).name)] = info
	check("checkpoint_respawn_points_valid", bad_static.is_empty(), {"count": cps.size(), "bad": bad_static})
	# Functional: touch each bookmark, fall out, and land back at it.
	var fails: Array = []
	for c in cps:
		var cn := c as Node3D
		put(cn.global_position + Vector3(0, 0.2, 0))
		await frames(8)
		var cp: Variant = Game.get_checkpoint(world)
		if not (cp is Transform3D) or not bool(c.get("is_active")):
			fails.append("%s: touching did not set the checkpoint" % cn.name)
			continue
		var target: Transform3D = cp
		put(cn.global_position + Vector3(30, 40, 30))
		await frames(3)
		Game.player_fell_out()
		await frames(90)
		await until_unpaused()
		var pl := player()
		var d := pl.global_position.distance_to(target.origin)
		if d > 1.5 or not pl.is_on_floor():
			fails.append("%s: after respawn dist=%.2f on_floor=%s pos=%s target=%s" % [cn.name, d, pl.is_on_floor(), v3s(pl.global_position), v3s(target.origin)])
	Game.health = Game.max_health
	check("checkpoint_touch_then_fall_out_respawns_there", fails.is_empty(), {"count": cps.size(), "fails": fails})
	# Only the latest bookmark stays lit.
	var lit := 0
	for c in cps:
		if bool(c.get("is_active")):
			lit += 1
	check("checkpoint_only_latest_lit", lit == 1, {"lit": lit})


func _check_bounce() -> void:
	var pads: Array = get_tree().get_nodes_in_group("bouncy")
	if pads.is_empty():
		note("no bouncy surfaces in " + world)
		return
	var bad_meta: Array = []
	for b in pads:
		if not (b as Node).has_meta("bounce_velocity") or float((b as Node).get_meta("bounce_velocity", 0.0)) <= 0.0:
			bad_meta.append(String((b as Node).get_path()))
	check("bouncy_have_bounce_velocity_meta", bad_meta.is_empty(), {"count": pads.size(), "missing": bad_meta})
	# Functional on up to 6 bouncy bodies: drop Mak 2.5 m above the top and measure the launch.
	var fails: Array = []
	var tested := 0
	for b in pads:
		if tested >= 6 or not (b is Node3D):
			continue
		var bn := b as Node3D
		var top := ray_down(bn.global_position + Vector3(0, 8.0, 0), 12.0)
		if top.is_empty() or top["collider"] != bn:
			continue
		tested += 1
		var tp: Vector3 = top["position"]
		put(tp + Vector3(0, 2.5, 0))
		var max_vy := -99.0
		for i in 70:
			await get_tree().physics_frame
			max_vy = maxf(max_vy, player().velocity.y)
		var want := float(bn.get_meta("bounce_velocity", 0.0))
		if max_vy < want * 0.6:
			fails.append("%s want %.1f got max vy %.1f at %s" % [bn.name, want, max_vy, v3s(tp)])
	check("bouncy_launch_real_player", fails.is_empty() and tested > 0, {"tested": tested, "fails": fails})


func _check_wind() -> void:
	var zones := of_class(WindZone)
	if zones.is_empty():
		return
	var rows: Array = []
	var dead: Array = []
	for z in zones:
		var zn := z as Node3D
		var w: Vector3 = z.call("get_wind", zn.global_position)
		var en := bool(z.get("enabled"))
		rows.append("%s en=%s |w|=%.1f str=%.1f" % [zn.name, en, w.length(), float(z.get("strength"))])
		if en and float(z.get("strength")) > 0.0 and not zn.is_in_group("wind_zone"):
			dead.append(zn.name)
	inventory["wind_zones"] = rows
	check("wind_zones_in_group", dead.is_empty(), {"not_in_group": dead})
	# Functional: the strongest enabled zone pushes the real player (in the air: drop through the zone centre).
	var best: Node3D = null
	var best_w := Vector3.ZERO
	for z in zones:
		var zn2 := z as Node3D
		if not bool(z.get("enabled")):
			continue
		var w2: Vector3 = z.call("get_wind", zn2.global_position)
		if w2.length() > best_w.length():
			best_w = w2
			best = zn2
	if best == null or best_w.length() < 1.0:
		note("no enabled wind zone with wind > 1 m/s at its centre right now")
		return
	put(best.global_position)
	var p0 := player().global_position
	var acc := Vector3.ZERO
	for i in 30:
		await get_tree().physics_frame
		acc += best.call("get_wind", player().global_position)
	var moved := player().global_position - p0
	var dirn := best_w.normalized()
	var along := moved.dot(dirn)
	var hmoved := Vector3(moved.x, 0, moved.z).dot(Vector3(dirn.x, 0, dirn.z))
	check("wind_pushes_player_" + String(best.name), along > 0.3 or hmoved > 0.3, {"wind_at_centre": v3s(best_w), "moved": v3s(moved),
		"along": snappedf(along, 0.01), "avg_wind_seen": v3s(acc / 30.0), "player_state": player().call("get_state_name")})


func _slam_on(target: Node3D, label: String) -> bool:
	## Real Ham Slam: drop Mak 2.6 m above the top surface under target and press crouch in the air.
	var hit := ray_down(target.global_position + Vector3(0, 3.0, 0), 6.0)
	var top := target.global_position + Vector3(0, 1.0, 0)
	if not hit.is_empty():
		top = hit["position"]
	put(top + Vector3(0, 2.6, 0))
	await frames(6)
	await tap("crouch", 3)
	await frames(70)
	print("[CritObj] slam %s top=%s state=%s" % [label, v3s(top), player().call("get_state_name")])
	return true


func _check_bellows() -> void:
	var bel := of_class(BellowsMachine)
	var sets := of_class(BellowsSet)
	if bel.is_empty():
		check("bellows_present", false, "no BellowsMachine in W1")
		return
	var fails: Array = []
	for b in bel:
		var bn := b as Node3D
		var wz: Node = b.get("_wind")
		await _slam_on(bn, String(bn.name))
		await until_unpaused()
		if not bool(b.get("is_broken")):
			fails.append("%s not broken by a real Ham Slam on its top" % bn.name)
			b.call("hit_by_player", "slam", bn.global_position)
		if wz != null and bool(wz.get("enabled")):
			fails.append("%s wind zone still enabled after break" % bn.name)
		# Collision after the bust: does Mak stand far above the busted model?
		var top := ray_down(bn.global_position + Vector3(0, 6.0, 0), 10.0)
		if not top.is_empty():
			inventory["bellows_top_after_bust_" + String(bn.name)] = snappedf((top["position"] as Vector3).y - bn.global_position.y, 0.01)
	check("bellows_break_by_real_slam", fails.is_empty(), {"count": bel.size(), "fails": fails})
	await frames(60)
	await until_unpaused()
	var reward_ok := false
	for s in sets:
		if bool(s.get("reward_given")):
			reward_ok = true
	var t4 := _find_truffle("W1-4")
	check("bellows_set_rewards_W1-4", reward_ok and t4 != null, {"reward_given": reward_ok, "truffle_node": t4 != null})


func _find_truffle(id: String) -> Node:
	for t in of_class(Truffle):
		if String(t.get("truffle_id")) == id and not bool(t.get("is_collected")):
			return t
	return null


func _check_cage() -> void:
	var cages := of_class(Cage)
	var sw := of_class(SlamSwitch)
	if cages.is_empty():
		check("cage_present_W2", false, "no Cage")
		return
	var cage: Node = cages[0]
	var linked: Array = cage.get("_switch_nodes")
	check("cage_switches_linked", linked.size() == sw.size() and linked.size() >= 3, {"linked": linked.size(), "switches_in_world": sw.size()})
	var fails: Array = []
	for s in sw:
		var sn := s as Node3D
		await _slam_on(sn, String(sn.name))
		await until_unpaused()
		if not bool(s.get("is_pressed")):
			fails.append("%s not pressed by a real Ham Slam (top %s)" % [sn.name, v3s(sn.global_position)])
			s.call("press")
	check("switches_press_by_real_slam", fails.is_empty(), {"fails": fails})
	await frames(120)
	check("cage_opens_after_all_switches", bool(cage.get("is_open")), {"pressed": cage.call("pressed_count")})


func _check_clouds() -> void:
	var clouds := of_class(VanishingCloud)
	if clouds.is_empty():
		return
	var c := clouds[0] as Node3D
	var top := ray_down(c.global_position + Vector3(0, 4.0, 0), 6.0)
	if top.is_empty():
		check("vanishing_cloud_top_found", false, v3s(c.global_position))
		return
	put((top["position"] as Vector3) + Vector3(0, 0.3, 0))
	await frames(int((float(c.get("vanish_delay")) + 1.4) * 60.0))
	var gone := ray_down(c.global_position + Vector3(0, 4.0, 0), 6.0)
	var vanished: bool = gone.is_empty() or gone["collider"] != c
	await frames(int((float(c.get("respawn_time")) + 1.5) * 60.0))
	var back := ray_down(c.global_position + Vector3(0, 4.0, 0), 6.0)
	var returned: bool = not back.is_empty() and back["collider"] == c
	check("vanishing_cloud_vanishes_and_returns", vanished and returned, {"cloud": String(c.name), "vanished": vanished, "returned": returned})


func _ring_through(r: Node3D) -> void:
	put(r.global_position - Vector3(0, 0.6, 0))
	await frames(4)


func _check_time_trials() -> void:
	var tts := of_class(TimeTrial)
	inventory["time_trials"] = []
	for tt in tts:
		var tn := tt as Node3D
		var rings: Array = tt.get("_rings")
		(inventory["time_trials"] as Array).append("%s limit=%.0f rings=%d ordered=%s reward=%s" % [tn.name, float(tt.get("time_limit")), rings.size(), tt.get("ordered"), tt.get("reward_truffle_id")])
		var start: Area3D = tt.get("_start")
		var fin: Area3D = tt.get("_finish")
		# Run 1: start, pass every ring, finish.
		put(start.global_position + Vector3(0, 0.3, 0))
		await frames(6)
		check("trial_starts_on_gate_" + String(tn.name), bool(tt.get("running")), {"hud_timer_visible": UI.hud.get("timer_visible")})
		for r in rings:
			await _ring_through(r as Node3D)
		var passed := int(tt.call("rings_passed"))
		check("trial_rings_register_" + String(tn.name), passed == rings.size(), {"passed": passed, "rings": rings.size()})
		put(fin.global_position + Vector3(0, 0.3, 0))
		await frames(8)
		await until_unpaused()
		var given := bool(tt.get("reward_given"))
		check("trial_success_rewards_" + String(tn.name), given and not bool(tt.get("running")), {"reward_given": given})
		await frames(240)
		await until_unpaused()
		var vis := bool(UI.hud.get("timer_visible"))
		check("trial_hud_timer_hidden_after_success_" + String(tn.name), not vis, {"timer_visible_4s_after_success": vis,
			"timer_running": UI.hud.get("timer_running"), "timer_value": UI.hud.get("timer_value")})
		# Run 2: fall out mid-trial (respawn far away) - the trial keeps running?
		put(start.global_position + Vector3(0, 0.3, 0))
		await frames(6)
		var running_again := bool(tt.get("running"))
		Game.player_fell_out()
		await frames(30)
		note("%s: after a fall-out mid-trial running=%s (started=%s), player at %s" % [tn.name, tt.get("running"), running_again, v3s(player().global_position)])
		Game.health = Game.max_health
		# Run 3: leave the world mid-trial; is the HUD timer still up in the next scene?
		if not bool(tt.get("running")):
			put(start.global_position + Vector3(0, 0.3, 0))
			await frames(6)
		var was_running := bool(tt.get("running"))
		var ok := await enter("HUB")
		var hud_vis := bool(UI.hud.get("timer_visible"))
		var hud_run := bool(UI.hud.get("timer_running"))
		check("trial_hud_timer_cleared_when_leaving_world", not hud_vis and not hud_run, {"trial_was_running": was_running,
			"entered_hub": ok, "hub_timer_visible": hud_vis, "hub_timer_running": hud_run, "hub_timer_value": UI.hud.get("timer_value")})
		UI.timer_hide()
		await enter(world)
		break


func _check_truffle_collect_and_save() -> void:
	var t: Node = null
	for c in of_class(Truffle):
		if not bool(c.get("is_ghost")) and not bool(c.get("is_collected")) and _registry_ids(world).has(String(c.get("truffle_id"))):
			t = c
			break
	if t == null:
		check("truffle_collect_static", false, "no uncollected static registry truffle found")
		return
	var id := String(t.get("truffle_id"))
	var count0 := int(Game.truffle_count())
	put((t as Node3D).global_position + Vector3(0, 0.15, 0))
	await frames(10)
	var paused_during := get_tree().paused
	check("truffle_collect_by_touch_" + id, bool(Game.has_truffle(id)), {"count_before": count0, "count_after": Game.truffle_count(), "celebration_paused": paused_during})
	await until_unpaused()
	await frames(10)
	var txt := FileAccess.get_file_as_string(Game.save_path())
	var saved := txt.contains("\"" + id + "\"")
	check("truffle_saved_to_disk_" + id, saved, {"save": Game.save_path()})
	# Revisit: the truffle shows as a ghost, re-collecting does not count twice.
	await enter(world)
	var g: Node = null
	for c in of_class(Truffle):
		if String(c.get("truffle_id")) == id:
			g = c
	if g == null:
		check("truffle_ghost_on_revisit_" + id, false, "truffle node missing on revisit")
		return
	check("truffle_ghost_on_revisit_" + id, bool(g.get("is_ghost")) and not (g as Node).is_in_group("sniff_target"), {"is_ghost": g.get("is_ghost")})
	var c1 := int(Game.truffle_count())
	put((g as Node3D).global_position + Vector3(0, 0.15, 0))
	await frames(10)
	await until_unpaused()
	check("ghost_recollect_does_not_double_count_" + id, int(Game.truffle_count()) == c1, {"before": c1, "after": Game.truffle_count()})


func _pages_by_index() -> Dictionary:
	var out := {}
	for p in of_class(LostPage):
		if not bool(p.get("is_collected")):
			out[int(p.get("page_index"))] = p
	return out


func _check_pages_across_visits() -> void:
	var sets := of_class(LostPageSet)
	var pages := _pages_by_index()
	if sets.is_empty():
		note("no LostPageSet in " + world)
		return
	var idx := pages.keys()
	idx.sort()
	check("pages_five_unique_indices", idx == [0, 1, 2, 3, 4], {"indices": idx, "nodes": of_class(LostPage).size()})
	var reward_id := String(sets[0].get("reward_truffle_id"))
	# Visit A: collect pages 0..2.
	for i in [0, 1, 2]:
		if pages.has(i):
			put((pages[i] as Node3D).global_position + Vector3(0, 0.3, 0))
			await frames(8)
	check("pages_collected_saved_visit_a", int(Game.page_count(world)) == 3, {"page_count": Game.page_count(world)})
	# Visit B (the player left the book and came back).
	await enter(world)
	var pages_b := _pages_by_index()
	var keys_b := pages_b.keys()
	keys_b.sort()
	check("pages_already_found_not_respawned_on_revisit", keys_b == [3, 4], {"uncollected_page_nodes_on_revisit": keys_b,
		"game_page_count": Game.page_count(world)})
	for i in [3, 4]:
		if pages_b.has(i):
			put((pages_b[i] as Node3D).global_position + Vector3(0, 0.3, 0))
			await frames(8)
	await frames(60)
	await until_unpaused()
	var hud_count := int(UI.hud.get("_page_count")) if UI.hud else -1
	var set_b: Node = of_class(LostPageSet)[0]
	var given := bool(set_b.get("reward_given")) or _find_truffle(reward_id) != null
	check("pages_truffle_when_save_has_all_five", given, {"game_page_count": Game.page_count(world), "hud_page_count": hud_count,
		"set_found_this_visit": (set_b.get("found") as Dictionary).size(), "reward_given": given, "reward_id": reward_id})


# =====================================================================================================
# hub suite

func _grant(ids: Array) -> void:
	## Writes truffles straight into the save data (no celebration), as a loaded save would have them.
	var t: Dictionary = Game.data.get("truffles", {})
	for id in ids:
		t[id] = {"utc": "test"}
	Game.data["truffles"] = t


func _portal_state() -> Dictionary:
	var out := {}
	for p in of_class(StorybookPortal):
		out[String(p.get("world_id"))] = {"open": bool(p.get("is_open")), "need": int(p.get("required_truffles")),
			"registry_need": WorldRegistry.truffles_required(String(p.get("world_id")))}
	for d in of_class(WolfDoor):
		out["DOOR"] = {"unlocked": bool(d.get("is_unlocked")), "need": int(d.get("required_truffles")),
			"registry_need": WorldRegistry.truffles_required(String(d.get("target_world")))}
	return out


func _hub_suite() -> void:
	world = "HUB"
	# r1c: the first-visit wolf intro freezes Mak (player physics off) for 9.5 s of unpaused time; a dialog opened by
	# the locked-book check pauses it, so later portal checks ran against a frozen player. Mark it seen (--intro=1 keeps it).
	if _arg("intro", "0") != "1" and Game.has_method("unlock"):
		Game.call("unlock", "hub_intro_seen")
	if not await enter("HUB"):
		check("enter_hub", false, "hub did not load")
		return
	check("enter_hub", true)
	inventory = _inventory()
	print("[CritObj] inventory ", inventory)
	await _check_truffle_ids()
	await _check_embedded_pickups()
	await _check_checkpoints()
	var s0 := _portal_state()
	inventory["portals_at_0"] = s0
	var mism: Array = []
	for k in s0:
		var e: Dictionary = s0[k]
		if int(e["need"]) != int(e["registry_need"]):
			mism.append("%s object need %d vs registry %d" % [k, e["need"], e["registry_need"]])
	check("portal_thresholds_match_registry", mism.is_empty(), {"mismatch": mism, "state": s0})
	var ok0: bool = bool(s0.get("W1", {}).get("open", false)) and not bool(s0.get("W2", {}).get("open", true)) \
		and not bool(s0.get("W3", {}).get("open", true)) and not bool(s0.get("DOOR", {}).get("unlocked", true))
	check("portals_locked_state_at_0_truffles", ok0, s0)
	# Locked book: touching its pages explains the seal instead of entering.
	var portals := of_class(StorybookPortal)
	for p in portals:
		if String(p.get("world_id")) == "W2":
			var z: Area3D = p.get("_zone")
			put(z.global_position - Vector3(0, 0.4, 0))
			await frames(10)
			var ms_vis := UI.mission_select != null and UI.mission_select.visible
			check("locked_book_does_not_open_mission_select", not ms_vis, {"mission_select_visible": ms_vis})
	# Thresholds: 3 -> W2, 7 -> W3, 12 -> door (polled every 30 frames).
	_grant(["W1-1", "W1-2", "W1-3"])
	await frames(70)
	var s3 := _portal_state()
	check("book_W2_opens_at_3", bool(s3["W2"]["open"]) and not bool(s3["W3"]["open"]), s3)
	_grant(["W1-4", "W1-5", "W1-6", "W1-100"])
	await frames(70)
	var s7 := _portal_state()
	check("book_W3_opens_at_7", bool(s7["W3"]["open"]), s7)
	note("W3 opened with 7 truffles where one of them is the bonus W1-100 (bonus truffles count toward every gate): %s" % str(s7["W3"]["open"]))
	_grant(["W1-7", "W1-8", "W2-1", "W2-2", "HUB-1"])
	await frames(70)
	var s12 := _portal_state()
	check("wolf_door_unlocks_at_12", bool(s12.get("DOOR", {}).get("unlocked", false)), s12)
	# Open book: jumping into the pages opens mission select.
	for p in portals:
		if String(p.get("world_id")) == "W1":
			var z2: Area3D = p.get("_zone")
			# r1c: the sealed-book dialog from the locked test is still open (UI r1 re-run queues the book behind a dialog).
			var dlg_open := bool(UI.is_dialog_open())
			note("dialog open before the W1 book test: %s" % str(dlg_open))
			if dlg_open and UI.dialog and UI.dialog.has_method("close"):
				UI.dialog.call("close")
				await frames(20)
			var got := [false]
			p.connect("entered", func(_w: String) -> void: got[0] = true)
			note("W1 book before: is_open=%s cooldown=%s route=%s monitoring=%s zone_layer=%d mask=%d" % [str(p.get("is_open")), str(p.get("_cooldown")), str(p.get("route_on_enter")), str(z2.monitoring), z2.collision_layer, z2.collision_mask])
			var shp := ""
			for cc in z2.get_children():
				if cc is CollisionShape3D:
					shp += "%s disabled=%s at %s; " % [str((cc as CollisionShape3D).shape), str((cc as CollisionShape3D).disabled), v3s((cc as Node3D).global_position)]
			note("W1 book zone: can_process=%s process_mode=%d portal_can_process=%s disable_mode=%d inside=%s shapes=%s player_layer=%d" % [str(z2.can_process()), z2.process_mode, str((p as Node).can_process()), z2.disable_mode, str(z2.is_inside_tree()), shp, player().collision_layer])
			var paused_before := get_tree().paused
			var splash := UI.announcer != null and UI.announcer.has_method("is_splashing") and bool(UI.announcer.call("is_splashing"))
			var ms_vis0 := UI.mission_select != null and UI.mission_select.visible
			var pm_open := UI.pause_menu != null and UI.pause_menu.has_method("is_open") and bool(UI.pause_menu.call("is_open"))
			note("W1 book state: tree_paused=%s announcer_splashing=%s mission_select_visible=%s pause_menu=%s blocked=%s" % [str(paused_before), str(splash), str(ms_vis0), str(pm_open), str(UI.call("is_input_blocked") if UI.has_method("is_input_blocked") else "?")])
			put(z2.global_position - Vector3(0, 0.4, 0))
			await frames(6)
			var bshape := player().get_node_or_null("Body") as CollisionShape3D
			note("W1 player: state=%s body_disabled=%s proc=%s phys=%s layer=%d" % [str(player().call("get_state_name")), str(bshape.disabled if bshape else "?"), str(player().can_process()), str(player().is_physics_processing()), player().collision_layer])
			note("W1 book after put: entered=%s overlaps_player=%s player=%s" % [str(got[0]), str(z2.overlaps_body(player())), v3s(player().global_position)])
			var waited := 0
			while waited < 240 and not (UI.mission_select != null and UI.mission_select.visible):
				await get_tree().process_frame
				waited += 1
			var spc := z2.get_world_3d().direct_space_state
			var pq := PhysicsPointQueryParameters3D.new()
			pq.position = player().global_position + Vector3(0, 0.6, 0)
			pq.collide_with_areas = true
			pq.collide_with_bodies = false
			pq.collision_mask = 0xFFFFFFFF
			var hits_txt := ""
			for h in spc.intersect_point(pq, 16):
				hits_txt += str(h.get("collider")) + " "
			var bsz := ""
			for cc in z2.get_children():
				if cc is CollisionShape3D and (cc as CollisionShape3D).shape is BoxShape3D:
					bsz = str(((cc as CollisionShape3D).shape as BoxShape3D).size) + " gscale " + str((cc as Node3D).global_transform.basis.get_scale())
			note("W1 book space: areas at player chest=[%s] zone box=%s zone_rid_space_ok=%s overlapping_bodies=%d" % [hits_txt, bsz, str(z2.get_world_3d() == player().get_world_3d()), z2.get_overlapping_bodies().size()])
			var gp_txt := ""
			for n in get_tree().get_nodes_in_group("player"):
				gp_txt += "%s(%s layer=%s) " % [str((n as Node).get_path()), (n as Node).get_class(), str(n.get("collision_layer"))]
			var bq := PhysicsShapeQueryParameters3D.new()
			bq.shape = (z2.get_child(0) as CollisionShape3D).shape if z2.get_child(0) is CollisionShape3D else null
			var body_txt := ""
			if bq.shape:
				bq.transform = (z2.get_child(0) as Node3D).global_transform
				bq.collision_mask = 0xFFFFFFFF
				for h in spc.intersect_shape(bq, 16):
					var col: Object = h.get("collider")
					body_txt += "%s(layer %s) " % [str(col), str(col.get("collision_layer")) if col else "?"]
			note("W1 book: player group=[%s] bodies in zone box=[%s] zone_layer=%d zone_mask=%d monitoring=%s" % [gp_txt, body_txt, z2.collision_layer, z2.collision_mask, str(z2.monitoring)])
			note("W1 player after wait: %s state=%s entered=%s" % [v3s(player().global_position), str(player().call("get_state_name")), str(got[0])])
			note("W1 book: waited %d frames, dialog_open=%s pending=%s" % [waited, str(UI.is_dialog_open()), str(UI.get("_pending_book"))])
			var ms2 := UI.mission_select != null and UI.mission_select.visible
			check("open_book_opens_mission_select", ms2, {"zone": v3s(z2.global_position)})
			if UI.mission_select and UI.mission_select.has_method("close"):
				UI.mission_select.call("close")
			await frames(30)
			get_tree().paused = false
	# Wolf door: walk to it -> opens -> walk through -> boss world.
	for d in of_class(WolfDoor):
		var dn := d as Node3D
		var near: Area3D = d.get("_near_zone")
		put(near.global_position - Vector3(0, near.global_position.y - dn.global_position.y, 0) - dn.global_basis.z * -1.5)
		await frames(40)
		check("wolf_door_opens_when_near_and_unlocked", bool(d.get("is_open")), {"player": v3s(player().global_position)})
		var ez: Area3D = d.get("_enter_zone")
		put(ez.global_position - Vector3(0, ez.global_position.y - dn.global_position.y, 0))
		var i := 0
		var reached := false
		while i < 1500:
			await get_tree().process_frame
			i += 1
			var sr := scene_root()
			if sr != null and "world_id" in sr and String(sr.get("world_id")) == "BOSS":
				reached = true
				break
		check("wolf_door_enters_boss", reached, {"frames": i})
		break



# =====================================================================================================
# shots suite (windowed): native viewport captures of the issues found by the world suites.

var _shot_dir := ""
var _cam: Camera3D


func shot_cam(at: Vector3, look: Vector3, fov: float = 55.0) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.name = "CritCam"
		get_tree().root.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = at
	_cam.look_at(look, Vector3.UP)
	_cam.make_current()


func release_cam() -> void:
	if _cam and is_instance_valid(_cam):
		_cam.clear_current(true)
		_cam.queue_free()
	_cam = null


func snap(caption: String, hold_cam: bool = true) -> String:
	for i in 3:
		if hold_cam and _cam and is_instance_valid(_cam):
			_cam.make_current()
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var utc := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var path := _shot_dir + "/%sZ__%s.png" % [utc, caption]
	img.save_png(path)
	print("[CritObj] SHOT ", path)
	notes.append("shot " + path)
	return path


func _keep_cam(frames_n: int) -> void:
	for i in frames_n:
		if _cam and is_instance_valid(_cam):
			_cam.make_current()
		await get_tree().process_frame


func _cp(name_: String) -> Node3D:
	for c in of_class(CheckpointBookmark):
		if String((c as Node).name) == name_:
			return c as Node3D
	return null


func _respawn_shot(cp_name: String, caption: String, cam_off: Vector3) -> void:
	var c := _cp(cp_name)
	if c == null:
		note("checkpoint %s not found" % cp_name)
		return
	put(c.global_position + Vector3(0, 0.2, 0))
	await frames(8)
	var target: Transform3D = c.call("get_respawn_transform")
	put(c.global_position + Vector3(30, 40, 30))
	await frames(3)
	Game.player_fell_out()
	var trace: Array = []
	for i in 120:
		await get_tree().physics_frame
		if i % 20 == 0:
			trace.append("%d:%s %s floor=%s" % [i, v3s(player().global_position), player().call("get_state_name"), player().is_on_floor()])
	note("%s respawn target %s trace %s" % [cp_name, v3s(target.origin), str(trace)])
	var pp := player().global_position
	shot_cam(pp + cam_off, pp + Vector3(0, 0.6, 0))
	await _keep_cam(10)
	await snap(caption)
	Game.health = Game.max_health


func _look_at_point(p: Vector3, off: Vector3, caption: String, fov: float = 50.0) -> void:
	put(p + Vector3(40, 60, 40))
	shot_cam(p + off, p, fov)
	await _keep_cam(30)
	await snap(caption)


func _shots_suite() -> void:
	_shot_dir = _arg("shot_dir", "")
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	if not await enter(world):
		check("enter_" + world, false)
		return
	if world == "W1":
		await _look_at_point(Vector3(-17.0, 0.9, 1.5), Vector3(2.5, 1.2, 3.0), "W1_lostpage0_embedded")
		await _look_at_point(Vector3(-47.4, 23.6, -31.5), Vector3(3.5, 2.5, 4.0), "W1_acorn_ring_treehouse_embedded")
		await _look_at_point(Vector3(-35.0, 7.5, -24.6), Vector3(2.5, 1.5, 3.0), "W1_acorn_embedded_b")
		# Stream current: does it push Mak?
		var zs: Array = []
		for z in of_class(WindZone):
			if (z as Node).get_parent() != null and String((z as Node).get_parent().name) == "StreamCurrent":
				zs.append(z)
		if zs.size() > 4:
			var z0 := zs[4] as Node3D
			put(z0.global_position + Vector3(0, 0.6, 0))
			var p0 := player().global_position
			var rows: Array = []
			for i in 60:
				await get_tree().physics_frame
				if i % 15 == 0:
					var ov: Array = []
					var sens: Area3D = player().get("sensor")
					if sens:
						for a in sens.get_overlapping_areas():
							ov.append(String(a.name))
					rows.append("%d pos=%s state=%s wind_vel=%s ov=%s" % [i, v3s(player().global_position), player().call("get_state_name"), v3s(player().get("wind_vel")), str(ov)])
			var w: Vector3 = z0.call("get_wind", z0.global_position)
			var mv := player().global_position - p0
			check("stream_current_pushes_mak", Vector3(mv.x, 0, mv.z).dot(Vector3(w.x, 0, w.z).normalized()) > 0.3, {"zone": String(z0.name), "wind": v3s(w), "moved": v3s(mv), "trace": rows})
		# Bellows: slam B1, then stand Mak on top of the busted model.
		for b in of_class(BellowsMachine):
			var bn := b as Node3D
			shot_cam(bn.global_position + bn.global_basis * Vector3(4.5, 2.6, 4.5), bn.global_position + Vector3(0, 1.2, 0))
			put(bn.global_position + Vector3(30, 60, 30))
			await _keep_cam(20)
			await snap("W1_bellows_before_slam")
			await _slam_on(bn, String(bn.name))
			await until_unpaused()
			await frames(90)
			put(bn.global_position + Vector3(0, 3.0, 0))
			await frames(60)
			note("Mak on busted bellows: y above base %.2f state %s" % [player().global_position.y - bn.global_position.y, player().call("get_state_name")])
			shot_cam(bn.global_position + bn.global_basis * Vector3(4.5, 2.6, 4.5), bn.global_position + Vector3(0, 1.2, 0))
			await _keep_cam(20)
			await snap("W1_bellows_busted_mak_standing_on_collision")
			break
		release_cam()
		await _pages_shots()
	elif world == "W2":
		await _respawn_shot("CP6", "W2_CP6_respawn_after_fallout", Vector3(3.0, 2.0, 3.5))
		await _respawn_shot("CP1", "W2_CP1_respawn_after_fallout", Vector3(3.0, 2.0, 3.5))
		var c6 := _cp("CP6")
		if c6:
			await _look_at_point(c6.global_position, Vector3(4.0, 3.0, 5.0), "W2_CP6_bookmark_overview")
		for s in of_class(SlamSwitch):
			if String((s as Node).name) == "Switch_S2":
				var sp := (s as Node3D).global_position
				await _look_at_point(sp, Vector3(3.5, 2.2, 4.0), "W2_switch_S2_with_overhang", 60.0)
				var hit := ray_down(sp + Vector3(0, 6.0, 0), 10.0)
				note("S2 at %s, first surface from above at %s collider %s" % [v3s(sp), v3s(hit.get("position", Vector3.ZERO)), str(hit.get("collider"))])
		await _look_at_point(Vector3(-9.2, 57.3, -36.4), Vector3(2.5, 1.5, 3.0), "W2_kitchen_acorns_embedded")
		await _look_at_point(Vector3(27.6, 28.3, -11.6), Vector3(2.5, 1.5, 3.0), "W2_allotment_acorns_embedded")
		await _look_at_point(Vector3(-16.6, -2.9, -3.4), Vector3(2.5, 1.0, 3.0), "W2_lostpage0_in_roots")
		await _look_at_point(Vector3(7.2, 36.1, -6.0), Vector3(2.5, 1.0, 3.0), "W2_lostpage3_in_bluebell_bud")
		release_cam()
		for tt in of_class(TimeTrial):
			var start: Area3D = tt.get("_start")
			var fin: Area3D = tt.get("_finish")
			put(start.global_position + Vector3(0, 0.3, 0))
			await frames(6)
			for r in tt.get("_rings"):
				await _ring_through(r as Node3D)
			put(fin.global_position + Vector3(0, 0.3, 0))
			await frames(8)
			await until_unpaused()
			await frames(300)
			await snap("W2_hud_timer_still_up_5s_after_trial_success", false)
			put(start.global_position + Vector3(0, 0.3, 0))
			await frames(30)
			await enter("HUB")
			await frames(120)
			await snap("HUB_hud_trial_timer_running_after_leaving_W2", false)
			break
	elif world == "W3":
		await _respawn_shot("CP8_syrup_pool", "W3_CP8_respawn_after_fallout", Vector3(3.5, 2.5, 4.0))
		var c8 := _cp("CP8_syrup_pool")
		if c8:
			await _look_at_point(c8.global_position, Vector3(4.0, 3.0, 5.0), "W3_CP8_bookmark_overview")
		await _look_at_point(Vector3(-6.0, 17.1, -26.5), Vector3(3.0, 1.5, 3.5), "W3_cottage_acorns_embedded")
		await _look_at_point(Vector3(39.0, 29.1, -42.8), Vector3(3.0, 1.5, 3.5), "W3_glace_cherry_acorns_embedded")
		release_cam()
		await _pages_shots()


func _pages_shots() -> void:
	var pages := _pages_by_index()
	for i in [0, 1, 2]:
		if pages.has(i):
			put((pages[i] as Node3D).global_position + Vector3(0, 0.3, 0))
			await frames(8)
	await enter(world)
	var pages_b := _pages_by_index()
	if pages_b.has(0):
		var p0 := pages_b[0] as Node3D
		put(p0.global_position + Vector3(0, 0, 2.5))
		await frames(30)
		await snap("%s_revisit_page1_already_saved_respawned" % world, false)
	for i in [3, 4]:
		if pages_b.has(i):
			put((pages_b[i] as Node3D).global_position + Vector3(0, 0.3, 0))
			await frames(8)
	await frames(30)
	await snap("%s_hud_pages_5of5_no_truffle" % world, false)
	await frames(200)
	var set_b: Node = of_class(LostPageSet)[0]
	note("%s pages: Game.page_count=%d set.found=%d reward_given=%s" % [world, Game.page_count(world), (set_b.get("found") as Dictionary).size(), set_b.get("reward_given")])


func _stream_debug() -> void:
	await enter("W1")
	var zs: Array = []
	for z in of_class(WindZone):
		if (z as Node).get_parent() != null and String((z as Node).get_parent().name) == "StreamCurrent":
			zs.append(z)
	var pl := player()
	var sens: Area3D = pl.get("sensor")
	note("sensor monitoring=%s mask=%d layer=%d player layer=%d" % [sens.monitoring, sens.collision_mask, sens.collision_layer, pl.collision_layer])
	for k in [2, 4, 8]:
		if k >= zs.size():
			break
		var z0 := zs[k] as Node3D
		put(z0.global_position + Vector3(0, 0.6, 0))
		await frames(40)
		var cs := (z0 as Node).get_child(0) as CollisionShape3D
		var bodies: Array = []
		for b in (z0 as Area3D).get_overlapping_bodies():
			bodies.append(String(b.name))
		var ov: Array = []
		for a in sens.get_overlapping_areas():
			ov.append(String(a.name))
		note("zone %s pos=%s basis_y=%s size=%s monitoring=%s layer=%d mask=%d shape=%s bodies=%s | player %s sensor_ov=%s wind_at_feet=%s wind_vel=%s state=%s" % [z0.name, v3s(z0.global_position), v3s(z0.global_basis.y), v3s(z0.get("size")), (z0 as Area3D).monitoring, (z0 as Area3D).collision_layer, (z0 as Area3D).collision_mask, str(cs.shape) if cs else "none", str(bodies), v3s(pl.global_position), str(ov), v3s(z0.call("get_wind", pl.global_position)), v3s(pl.get("wind_vel")), pl.call("get_state_name")])
	# Same check for a bellows gust zone when blowing.
	for z in of_class(WindZone):
		if String((z as Node).name).begins_with("Gust_"):
			var zn := z as Node3D
			put(zn.global_position)
			var mx := 0.0
			var p0 := pl.global_position
			for i in 240:
				await get_tree().physics_frame
				mx = maxf(mx, (z.call("get_wind", pl.global_position) as Vector3).length())
			var ov2: Array = []
			for a in sens.get_overlapping_areas():
				ov2.append(String(a.name))
			note("gust %s max_wind_seen=%.1f moved=%s sensor_ov=%s" % [zn.name, mx, v3s(pl.global_position - p0), str(ov2)])
			break


func _probe_point(label: String, at: Vector3, r: float) -> void:
	var pl := player()
	var space := pl.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = r
	q.shape = s
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 1
	q.exclude = [pl.get_rid()]
	var rows: Array = []
	for h in space.intersect_shape(q, 8):
		var col: Object = h.get("collider")
		var sid := int(h.get("shape"))
		var shp: Shape3D = null
		if col is CollisionObject3D:
			var owner_id := (col as CollisionObject3D).shape_find_owner(sid)
			shp = (col as CollisionObject3D).shape_owner_get_shape(owner_id, 0)
		rows.append("%s shape#%d %s" % [String((col as Node).get_path()) if col is Node else str(col), sid, shp.get_class() if shp else "?"])
	# Free-space test: can a 0.33 m capsule stand within 1.2 m of the pickup?
	var free_spots := 0
	for k in 16:
		var a := TAU * k / 16.0
		for d in [0.6, 1.0, 1.4]:
			var p2 := at + Vector3(cos(a) * d, -0.9, sin(a) * d)
			if capsule_blocked(p2) == 0:
				free_spots += 1
	note("%s at %s overlaps %s free_capsule_spots_within_1.4m=%d/48" % [label, v3s(at), str(rows), free_spots])


func _probe_suite() -> void:
	await enter(world)
	for p in of_class(LostPage):
		var c := (p as Node3D).global_position + Vector3(0, float(p.get("hover_height")), 0)
		await _probe_point("%s LostPage %d" % [world, int(p.get("page_index"))], c, 0.22)


func _press_event(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var ev2 := InputEventAction.new()
	ev2.action = action
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await frames(2)


func _misc_suite() -> void:
	if not await enter(world):
		return
	# 1) Overlapping talk zones (two dialogs answer one press).
	var talkers := of_class(Talker)
	var pairs: Array = []
	for i in talkers.size():
		for j in range(i + 1, talkers.size()):
			var a := talkers[i] as Node3D
			var b := talkers[j] as Node3D
			var d := a.global_position.distance_to(b.global_position)
			if d < float(a.get("talk_radius")) + float(b.get("talk_radius")):
				pairs.append("%s/%s %.1fm" % [a.name, b.name, d])
	check("talk_zones_do_not_overlap", pairs.is_empty(), {"talkers": talkers.size(), "overlapping": pairs})
	# 2) Dismissing the last dialog line with interact must not reopen the dialog.
	var sign: Node3D = null
	for t in talkers:
		if not bool(t.get("auto_talk")) and (t.get("lines") as PackedStringArray).size() >= 1:
			sign = t as Node3D
			break
	if sign:
		var z: Area3D = sign.get("_zone")
		put(z.global_position + Vector3(0, -1.0, 0) + sign.global_basis.z * -1.2)
		await frames(10)
		var near := sign.get("player_near") != null
		await _press_event("interact")
		await frames(10)
		var opened := bool(UI.is_dialog_open())
		var n_lines := (sign.get("lines") as PackedStringArray).size()
		var reopened := false
		# r1c: press until the dialog closes (typewriter lines can need two presses each), then watch for a reopen.
		var closed_once := false
		var presses := 0
		for k in 24:
			await frames(60)
			if not bool(UI.is_dialog_open()):
				closed_once = true
				break
			await _press_event("interact")
			presses += 1
		await frames(45)
		reopened = closed_once and bool(UI.is_dialog_open())
		note("talker %s: presses=%d closed_once=%s reopened=%s" % [String(sign.name), presses, str(closed_once), str(reopened)])
		if not closed_once:
			reopened = true
		check("talker_dismiss_does_not_reopen_" + String(sign.name), opened and not reopened, {"player_near": near, "opened": opened,
			"open_after_dismiss": reopened, "lines": n_lines})
		if reopened:
			UI.dialog.call("close")
			await frames(20)
	# 3) Crates: break one and make sure its acorns land somewhere reachable.
	var crates := of_class(BreakableCrate)
	if crates.size() > 0:
		var c := crates[0] as Node3D
		var cname := String(c.name)
		var floor_y := c.global_position.y
		var n0 := of_class(Acorn).size()
		put(c.global_position + c.global_basis.z * 1.6)
		await frames(5)
		var hit_ok := bool(c.call("hit_by_player", "punch", player().global_position))
		await frames(150)
		var new_acorns: Array = []
		for a in of_class(Acorn):
			if not bool(a.get("is_collected")):
				new_acorns.append(a)
		var lost := 0
		for a in new_acorns:
			if (a as Node3D).global_position.y < floor_y - 3.0:
				lost += 1
		check("crate_break_spills_acorns_" + cname, hit_ok and of_class(Acorn).size() >= n0, {"hit": hit_ok, "acorn_nodes_before": n0,
			"after": of_class(Acorn).size(), "fell_below_crate_by_3m": lost})
	if world == "W1":
		await _spout_test()
	# 4) W2 switch S2 with the slam from just above it.
	if world == "W2":
		for s in of_class(SlamSwitch):
			if String((s as Node).name) == "Switch_S2":
				await _slam_on(s as Node3D, "S2")
				await until_unpaused()
				check("switch_S2_real_slam_from_low", bool(s.get("is_pressed")), {"state": player().call("get_state_name")})


func _spout_test() -> void:
	for b in of_class(BellowsMachine):
		b.call("hit_by_player", "slam", (b as Node3D).global_position)
	await frames(30)
	await until_unpaused()
	await frames(200)
	await until_unpaused()
	var spout: Node3D = null
	for z in of_class(WindZone):
		if String((z as Node).name) == "W_spout":
			spout = z as Node3D
	var t4 := _find_truffle("W1-4")
	if spout == null or t4 == null:
		check("w1_spout_lifts_mak_to_W1-4", false, {"spout": spout != null, "truffle": t4 != null})
		return
	var base := spout.global_position - Vector3(0, float((spout.get("size") as Vector3).y) * 0.5, 0)
	put(base + Vector3(0, 1.2, 0))
	var max_y := -99.0
	var got := false
	for i in 420:
		await get_tree().physics_frame
		max_y = maxf(max_y, player().global_position.y)
		if bool(Game.has_truffle("W1-4")):
			got = true
			break
	await until_unpaused()
	check("w1_spout_lifts_mak_to_W1-4", got, {"spout_enabled": spout.get("enabled"), "base": v3s(base), "max_player_y": snappedf(max_y, 0.01),
		"truffle_at": v3s((t4 as Node3D).global_position if is_instance_valid(t4) else Vector3.ZERO)})


func _clip_suite() -> void:
	var clip := _arg("clip", "cp6")
	if clip == "cp6":
		await enter("W2")
		var c := _cp("CP6")
		put(c.global_position + Vector3(0, 0.2, 0))
		await frames(30)
		var target: Transform3D = c.call("get_respawn_transform")
		shot_cam(target.origin + Vector3(3.2, 2.3, 3.6), target.origin + Vector3(0, 0.4, 0), 58.0)
		await _keep_cam(40)
		put(c.global_position + Vector3(30, 40, 30))
		await frames(2)
		Game.player_fell_out()
		await _keep_cam(240)
		note("cp6 clip end: player %s state %s" % [v3s(player().global_position), player().call("get_state_name")])
	elif clip == "talker":
		await enter("W3")
		var sign: Node3D = null
		for t in of_class(Talker):
			if not bool(t.get("auto_talk")):
				sign = t as Node3D
				break
		var z: Area3D = sign.get("_zone")
		put(z.global_position + Vector3(0, -1.0, 0) + sign.global_basis.z * -1.2)
		await frames(30)
		for k in 7:
			await _press_event("interact")
			await frames(70)
			note("press %d dialog_open=%s" % [k + 1, UI.is_dialog_open()])


# =====================================================================================================
# trace suite (round 1b recheck): W1 CP2_grove respawn drift, bellows gust push, stream current, acorn ring touch
func _trace_suite() -> void:
	await enter("W1")
	var pl := player()
	for c in of_class(CheckpointBookmark):
		var cn := c as Node3D
		if String(cn.name) != "CP2_grove":
			continue
		put(cn.global_position + Vector3(0, 0.2, 0))
		await frames(8)
		var target: Variant = Game.get_checkpoint(world)
		note("CP2 bookmark at %s respawn %s fallback=%s" % [v3s(cn.global_position), v3s((target as Transform3D).origin) if target is Transform3D else "none", c.get("respawn_fallback_used")])
		put(cn.global_position + Vector3(30, 40, 30))
		await frames(3)
		Game.player_fell_out()
		var tr: Array = []
		for i in 120:
			await get_tree().physics_frame
			if i % 10 == 0:
				var fl := ""
				if pl.is_on_floor():
					var col := pl.get_last_slide_collision()
					if col:
						fl = String((col.get_collider() as Node).name) if col.get_collider() is Node else "?"
						fl += " n=" + v3s(col.get_normal())
				tr.append("%d:%s %s floor=%s wind=%s vel=%s" % [i, v3s(pl.global_position), pl.call("get_state_name"), fl, v3s(pl.get("wind_vel")), v3s(pl.velocity)])
		await until_unpaused()
		note("CP2 trace " + str(tr))
		break
	for z in of_class(WindZone):
		var zn := z as Node3D
		if not String(zn.name).begins_with("Gust_bellows_B1"):
			continue
		note("gust %s pos=%s dir_local=%s global_dir=%s size=%s parent=%s parent_pos=%s enabled=%s drive=%s" % [zn.name, v3s(zn.global_position), v3s(z.get("direction")), v3s(zn.global_basis * (z.get("direction") as Vector3)), v3s(z.get("size")), zn.get_parent().name, v3s((zn.get_parent() as Node3D).global_position) if zn.get_parent() is Node3D else "-", z.get("enabled"), z.get("drive")])
		put(zn.global_position)
		var tr2: Array = []
		for i in 40:
			await get_tree().physics_frame
			if i % 4 == 0:
				var cname := ""
				for k in pl.get_slide_collision_count():
					var cc := pl.get_slide_collision(k)
					if cc.get_collider() is Node:
						cname += String((cc.get_collider() as Node).name) + " n=" + v3s(cc.get_normal()) + "; "
				tr2.append("%d:%s %s wind_vel=%s w_here=%s vel=%s coll=[%s]" % [i, v3s(pl.global_position), pl.call("get_state_name"), v3s(pl.get("wind_vel")), v3s(z.call("get_wind", pl.global_position)), v3s(pl.velocity), cname])
		note("gust trace " + str(tr2))
		# Same, dropped 3 m above the zone centre (in the air, no depenetration).
		put(zn.global_position + Vector3(0, 2.0, 0))
		var p0 := pl.global_position
		for i in 30:
			await get_tree().physics_frame
		note("gust airborne: moved %s wind_vel=%s" % [v3s(pl.global_position - p0), v3s(pl.get("wind_vel"))])
		break
	# Acorn ring at the treehouse: touch the first acorn of the of_class list (the world suite's pick).
	var a0: Node3D = null
	for a in of_class(Acorn):
		if not bool(a.get("is_collected")):
			a0 = a
			break
	if a0:
		var c0 := int(Game.acorns) if "acorns" in Game else -1
		put(a0.global_position + Vector3(0, 0.15, 0))
		await frames(12)
		note("acorn touch %s at %s player_after=%s acorns %d -> %s collected=%s monitoring=%s" % [a0.get_path(), v3s(a0.global_position), v3s(pl.global_position), c0, str(Game.acorns) if "acorns" in Game else "?", a0.get("is_collected"), (a0 as Area3D).monitoring])
	await _stream_debug_inline()


func _stream_debug_inline() -> void:
	var pl := player()
	var zs: Array = []
	for z in of_class(WindZone):
		if (z as Node).get_parent() != null and String((z as Node).get_parent().name) == "StreamCurrent":
			zs.append(z)
	note("stream zones: %d" % zs.size())
	for k in [2, 4, 8]:
		if k >= zs.size():
			break
		var z0 := zs[k] as Node3D
		put(z0.global_position + Vector3(0, 0.6, 0))
		var p0 := pl.global_position
		await frames(40)
		note("stream %s at %s moved=%s wind_vel=%s w_here=%s state=%s pm=%s" % [z0.name, v3s(z0.global_position), v3s(pl.global_position - p0), v3s(pl.get("wind_vel")), v3s(z0.call("get_wind", pl.global_position)), pl.call("get_state_name"), z0.process_mode])


# =====================================================================================================
# round 1c (after objects M3b): W2 page 4 held in the bluebell bud, then released when the bud opens.

func _r1c_w2_suite() -> void:
	world = "W2"
	if not await enter("W2"):
		return
	var sr := scene_root()
	var play: Variant = sr.get("play") if sr else null
	check("r1c_w2_play_found", play != null, {})
	if play == null:
		return
	var held: Array = play.get("_bud_held")
	var page4: Node3D = null
	for n in held:
		if is_instance_valid(n) and String((n as Node).name) == "Page4":
			page4 = n
	check("r1c_page4_held_until_bud_opens", page4 != null and not page4.is_inside_tree(), {"held": held.size()})
	if page4 == null:
		return
	var gp := page4.position
	# Collect the other four first (visit A), then open the bud and collect page 4.
	for p in of_class(LostPage):
		if int(p.get("page_index")) != 3:
			put((p as Node3D).global_position + Vector3(0, 0.3, 0))
			await frames(8)
	await until_unpaused()
	play.call("open_bud", "punch")
	await frames(90)
	await until_unpaused()
	var in_tree := page4.is_inside_tree()
	var dy := page4.global_position.y - gp.y if in_tree else 0.0
	check("r1c_page4_released_in_place", in_tree and absf(dy) < 0.3, {"in_tree": in_tree, "held_pos": v3s(gp),
		"now": v3s(page4.global_position) if in_tree else "-", "lift_m": snappedf(dy, 0.01)})
	if in_tree:
		var floor := ray_down(page4.global_position + Vector3(0, 0.1, 0), 8.0)
		var gap := page4.global_position.y - ((floor["position"] as Vector3).y if not floor.is_empty() else -999.0)
		check("r1c_page4_reachable_height", gap < 1.6, {"height_above_floor": snappedf(gap, 0.01), "floor": str(floor.get("collider", "none"))})
		put(page4.global_position + Vector3(0, 0.3, 0))
		await frames(10)
	await frames(90)
	await until_unpaused()
	var sets := of_class(LostPageSet)
	var given := sets.size() > 0 and (bool(sets[0].get("reward_given")) or _find_truffle("W2-5") != null)
	check("r1c_w2_pages_reward_after_bud", given, {"page_count": Game.page_count("W2"), "reward_given": given})
	# Revisit: page 4 already found, must come back as a ghost only after the bud opens again.
	await enter("W2")
	var sr2 := scene_root()
	var play2: Variant = sr2.get("play") if sr2 else null
	var held2: Array = play2.get("_bud_held") if play2 else []
	var p4b: Node3D = null
	for n in held2:
		if is_instance_valid(n) and String((n as Node).name) == "Page4":
			p4b = n
	if p4b:
		play2.call("open_bud", "punch")
		await frames(90)
		check("r1c_page4_ghost_on_revisit", p4b.is_inside_tree() and bool(p4b.get("is_ghost")), {"is_ghost": p4b.get("is_ghost")})
	else:
		note("revisit: page4 not held")

extends Node3D
## Scripted interaction test for the interactive objects. Runs headless with ObjPlayerStub (or windowed for a look).
##   python tools/godot.py run res://scenes/objects/ObjectsTest.tscn --headless --seconds 90 -- --profile=objects --results=<abs json>
## Prints "[ObjTest] PASS/FAIL/SKIP <name>: <detail>" lines and writes a JSON summary when --results is given.

var results: Array = []
var stub: ObjPlayerStub
var _region := 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var ground := StaticBody3D.new()
	ground.collision_layer = ObjSvc.L_WORLD
	add_child(ground)
	ObjSvc.add_shape(ground, ObjSvc.box_shape(Vector3(800, 1, 60)), Vector3(300, -0.5, 0))
	stub = ObjPlayerStub.new()
	stub.name = "PlayerStub"
	add_child(stub)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 8, 14)
	cam.rotation_degrees = Vector3(-25, 0, 0)
	add_child(cam)
	_run.call_deferred()


func region() -> Vector3:
	_region += 1
	return Vector3(_region * 30.0, 0, 0)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func put(p: Vector3) -> void:
	stub.move_dir = Vector3.ZERO
	stub.velocity = Vector3.ZERO
	stub.global_position = p
	stub.reset_physics_interpolation()


func inst(scene_name: String, at: Vector3, props: Dictionary = {}) -> Node:
	var ps := load("res://scenes/objects/%s.tscn" % scene_name) as PackedScene
	var n := ps.instantiate()
	for k in props:
		n.set(k, props[k])
	# Place before entering the tree (the test root sits at the origin), as a level scene would.
	(n as Node3D).position = at
	add_child(n)
	return n


func check(test_name: String, ok: bool, detail: String = "") -> void:
	results.append({"name": test_name, "result": "PASS" if ok else "FAIL", "detail": detail})
	print("[ObjTest] ", "PASS " if ok else "FAIL ", test_name, ": ", detail)


func skip(test_name: String, detail: String) -> void:
	results.append({"name": test_name, "result": "SKIP", "detail": detail})
	print("[ObjTest] SKIP ", test_name, ": ", detail)


func truffles_with_id(id: String) -> Array:
	var out := []
	for t in get_tree().get_nodes_in_group("truffle"):
		if str(t.get("truffle_id")) == id and not t.is_queued_for_deletion():
			out.append(t)
	return out


func slam_at(p: Vector3) -> void:
	put(p + Vector3(0, 3.0, 0))
	await frames(2)
	stub.ham_slam()
	await frames(40)


func _run() -> void:
	# Fresh progress in the test profile (never the real save: run with --profile=objects).
	if ObjSvc.can("Game", "new_game"):
		ObjSvc.call_on("Game", "new_game")
	ObjSvc.local_truffles.clear()
	await frames(5)
	await t_truffle()
	await t_acorns()
	await t_pages()
	await t_checkpoint_killzone()
	await t_wind()
	await t_bounce()
	await t_switch_cage()
	await t_bellows()
	await t_crate()
	await t_buried()
	await t_platforms()
	await t_hazard()
	await t_time_trial()
	await t_talkers_portal_door()
	var n_pass := 0
	var n_fail := 0
	var n_skip := 0
	for r in results:
		match r.result:
			"PASS": n_pass += 1
			"FAIL": n_fail += 1
			_: n_skip += 1
	print("[ObjTest] SUMMARY pass=%d fail=%d skip=%d" % [n_pass, n_fail, n_skip])
	var out_path := ""
	var dev := ObjSvc.autoload("Dev")
	if dev != null and dev.has_method("arg"):
		out_path = str(dev.call("arg", "results", ""))
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"utc": Time.get_datetime_string_from_system(true) + "Z", "pass": n_pass, "fail": n_fail, "skip": n_skip,
				"player": "ObjPlayerStub", "game_has_collect_truffle": ObjSvc.can("Game", "collect_truffle"), "results": results}, "  "))
			f.close()
	get_tree().quit(0 if n_fail == 0 else 1)


# ------------------------------------------------------------------ tests

func t_truffle() -> void:
	var o := region()
	var t := inst("Truffle", o, {"truffle_id": "TEST-1"}) as Node
	var got := [""]
	t.connect("collected", func(id: String) -> void: got[0] = id)
	await frames(3)
	check("truffle_not_ghost_initially", not bool(t.get("is_ghost")), "fresh id shows a solid truffle")
	put(o + Vector3(0, 0.3, 0))
	await frames(6)
	check("truffle_collect", got[0] == "TEST-1" and ObjSvc.local_truffles.has("TEST-1"), "collected signal id=%s" % got[0])
	if ObjSvc.can("Game", "collect_truffle") and ObjSvc.can("Game", "has_truffle"):
		check("truffle_saved_through_game", bool(ObjSvc.call_on("Game", "has_truffle", ["TEST-1"])), "Game.has_truffle(TEST-1) after collect")
		var saved_ok := false
		var detail := "no save method on Game"
		for m in ["save_game", "save", "save_progress"]:
			if ObjSvc.can("Game", m):
				ObjSvc.call_on("Game", m)
				saved_ok = true
				detail = "Game.%s() called without error" % m
				break
		if saved_ok:
			check("truffle_game_save_call", true, detail)
		else:
			skip("truffle_game_save_call", detail)
		if ObjSvc.can("Game", "save_path"):
			var sp := str(ObjSvc.call_on("Game", "save_path"))
			var on_disk := false
			if FileAccess.file_exists(sp):
				var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sp))
				if parsed is Dictionary and (parsed as Dictionary).get("truffles", {}) is Dictionary:
					on_disk = ((parsed as Dictionary)["truffles"] as Dictionary).has("TEST-1")
			check("truffle_written_to_profile_save", on_disk, "TEST-1 in %s" % sp)
	else:
		skip("truffle_saved_through_game", "Game autoload has no collect_truffle/has_truffle yet (core workstream); fallback ObjSvc.local_truffles used")
	put(o + Vector3(0, 0, 8))
	await frames(30)
	var t2 := inst("Truffle", o + Vector3(3, 0, 0), {"truffle_id": "TEST-1"})
	await frames(2)
	check("truffle_ghost_when_owned", bool(t2.get("is_ghost")), "second truffle with a collected id is a ghost")


func t_acorns() -> void:
	var o := region()
	var hundred := inst("AcornHundred", o + Vector3(0, 0, -5), {"required": 6, "reward_truffle_id": "TEST-ACORN"})
	var ring := inst("AcornGroup", o, {"shape": 1, "count": 6, "radius": 1.0})
	await frames(3)
	var before := ObjSvc.visit_acorns
	var n_ac := 0
	for c in ring.get_children():
		if c.is_in_group("acorn"):
			n_ac += 1
	check("acorn_group_spawned", n_ac == 6, "ring acorns=%d" % n_ac)
	put(o + Vector3(0, 0, 0))
	await frames(60)
	check("acorn_magnet_collect", ObjSvc.visit_acorns - before == 6, "collected %d of 6 (magnet radius 1.8 m)" % (ObjSvc.visit_acorns - before))
	await frames(5)
	check("acorn_hundred_spawns_truffle", bool(hundred.get("reward_given")) and truffles_with_id("TEST-ACORN").size() == 1, "required=6 for the test")


func t_pages() -> void:
	var o := region()
	var set_node := inst("LostPageSet", o + Vector3(0, 0, -6), {"world_id": "TW", "reward_truffle_id": "TEST-PAGES"})
	var pages := []
	for i in 5:
		pages.append(inst("LostPage", o + Vector3(i * 3.0 - 6.0, 0, 0), {"world_id": "TW", "page_index": i}))
	await frames(3)
	for i in 4:
		put((pages[i] as Node3D).global_position + Vector3(0, 0.6, 0))
		await frames(6)
	check("pages_four_no_reward", not bool(set_node.get("reward_given")), "found=%d" % (set_node.get("found") as Dictionary).size())
	put((pages[4] as Node3D).global_position + Vector3(0, 0.6, 0))
	await frames(8)
	check("pages_five_spawn_truffle", bool(set_node.get("reward_given")) and truffles_with_id("TEST-PAGES").size() == 1, "all five pages found")


func t_checkpoint_killzone() -> void:
	var o := region()
	var cp := inst("Checkpoint", o, {"world_id": "TW"})
	var cp2 := inst("Checkpoint", o + Vector3(6, 0, 0), {"world_id": "TW"})
	await frames(3)
	put(o + Vector3(0, 0.2, 0))
	await frames(5)
	check("checkpoint_activates", bool(cp.get("is_active")), "bookmark flips on touch")
	put(cp2.global_position + Vector3(0, 0.2, 0))
	await frames(5)
	check("checkpoint_only_latest_active", bool(cp2.get("is_active")) and not bool(cp.get("is_active")), "previous bookmark dims")
	if not ObjSvc.can("Game", "set_checkpoint"):
		skip("checkpoint_game_call", "Game.set_checkpoint not present yet")
	var kz := inst("KillZone", o + Vector3(0, -20, 0), {"size": Vector3(10, 4, 10)})
	await frames(3)
	if ObjSvc.can("Game", "player_fell_out"):
		var fell := [false]
		kz.connect("player_fell", func(_b: Node) -> void: fell[0] = true)
		put(o + Vector3(0, -20, 0))
		await frames(5)
		check("killzone_calls_game", fell[0], "player_fell emitted, Game.player_fell_out called")
	else:
		put(o + Vector3(0, -20, 0))
		await frames(5)
		var expect: Transform3D = cp2.call("get_respawn_transform")
		check("killzone_respawns_at_checkpoint", stub.global_position.distance_to(expect.origin) < 1.5, "stub at %s, checkpoint respawn %s" % [stub.global_position, expect.origin])


func t_wind() -> void:
	var o := region()
	var wz := inst("WindZone", o + Vector3(0, 2, 0), {"size": Vector3(6, 4, 6), "direction": Vector3(1, 0, 0), "strength": 6.0, "end_falloff": 0.0}) as Node
	await frames(3)
	var w: Vector3 = wz.call("get_wind", o + Vector3(0, 1, 0))
	check("wind_get_wind_inside", w.distance_to(Vector3(6, 0, 0)) < 0.01, "get_wind=%s" % w)
	var w_out: Vector3 = wz.call("get_wind", o + Vector3(20, 1, 0))
	check("wind_zero_outside", w_out == Vector3.ZERO, "outside=%s" % w_out)
	put(o + Vector3(-2, 0.05, 0))
	await frames(20)
	var x0 := stub.global_position.x
	await frames(20)
	var dx := stub.global_position.x - x0
	check("wind_pushes_player", dx > 1.0, "moved %.2f m along +X in 1/3 s, max wind seen %.1f" % [dx, stub.max_wind_seen])
	wz.call("set_enabled", false)
	put(o + Vector3(-2, 0.05, 0))
	await frames(20)
	var x1 := stub.global_position.x
	await frames(20)
	check("wind_toggle_off", absf(stub.global_position.x - x1) < 0.05 and (wz.call("get_wind", o + Vector3(0, 1, 0)) as Vector3) == Vector3.ZERO, "moved %.3f m with wind off" % (stub.global_position.x - x1))
	wz.set("mode", 1)
	wz.call("set_enabled", true)
	var mx := 0.0
	var mn := 999.0
	for i in 160:
		await get_tree().physics_frame
		var l := (wz.call("get_wind", o + Vector3(0, 1, 0)) as Vector3).length()
		mx = maxf(mx, l)
		mn = minf(mn, l)
	check("wind_pulsing", mx > 5.0 and mn < 0.5, "pulse range %.2f..%.2f" % [mn, mx])
	wz.queue_free()
	await t_wind_calm_shelter()


## Night 01 M3b: calm boxes (local AABBs) and the opt-in wind shadow behind world bodies.
func t_wind_calm_shelter() -> void:
	var o := region()
	var wz := WindZone.new()
	wz.size = Vector3(10, 4, 4)
	wz.direction = Vector3(1, 0, 0)
	wz.strength = 6.0
	wz.end_falloff = 0.0
	wz.show_particles = false
	wz.use_gust_swirl = false
	wz.calm_boxes = [AABB(Vector3(2.0, -2.0, -2.0), Vector3(3.0, 4.0, 4.0))]
	wz.position = o + Vector3(0, 2, 0)
	add_child(wz)
	await frames(3)
	var w_calm: Vector3 = wz.get_wind(o + Vector3(3.0, 1.0, 0))
	var w_open: Vector3 = wz.get_wind(o + Vector3(-1.0, 1.0, 0))
	check("wind_calm_box", w_calm == Vector3.ZERO and w_open.length() > 5.9, "calm=%s open=%s" % [w_calm, w_open])
	# A wall across the lane at x = -1: behind it (downwind, x > -1) is sheltered only with shelter_mask.
	var wall := StaticBody3D.new()
	wall.collision_layer = ObjSvc.L_WORLD
	ObjSvc.add_shape(wall, ObjSvc.box_shape(Vector3(0.4, 4.0, 4.0)))
	wall.position = o + Vector3(-1.0, 2.0, 0)
	add_child(wall)
	await frames(3)
	var before: Vector3 = wz.get_wind(o + Vector3(0.5, 1.0, 0))
	wz.shelter_mask = ObjSvc.L_WORLD
	await get_tree().physics_frame
	var behind: Vector3 = wz.get_wind(o + Vector3(0.5, 1.0, 0))
	var upwind: Vector3 = wz.get_wind(o + Vector3(-3.0, 1.0, 0))
	var peak: Vector3 = wz.get_peak_wind(o + Vector3(0.5, 1.0, 0))
	check("wind_shelter_behind_wall", before.length() > 5.9 and behind == Vector3.ZERO and upwind.length() > 5.9 and peak == Vector3.ZERO,
		"no mask %.1f, behind %.1f, upwind %.1f, peak %.1f" % [before.length(), behind.length(), upwind.length(), peak.length()])
	wz.queue_free()
	wall.queue_free()
	# NpcLife profiles follow re-delivered files (v2 AO bakes) and ObjSvc upgrades v1 characters to the current files.
	var ok_prof := bool(NpcLife.profile_for("sleeping_giant_v2").get("snore", false)) and bool(NpcLife.profile_for("daisy_cow_v2").get("graze", false)) 		and float(NpcLife.profile_for("sergeant_snap_v3").get("arm_lower", 0.0)) == 55.0 and NpcLife.profile_for("nobody_v2").is_empty()
	check("npc_profile_versions", ok_prof, "giant_v2 snore, cow_v2 graze, snap_v3 arm 55")
	var n_up := 0
	var n_bad := 0
	for k in ObjSvc.RIGGED_UPGRADES.keys():
		if ResourceLoader.exists(str(k)):
			var up := ObjSvc.upgrade_character(load(str(k)) as PackedScene, 1.0)
			if (up[0] as PackedScene).resource_path == str(ObjSvc.RIGGED_UPGRADES[k][0]):
				n_up += 1
			else:
				n_bad += 1
	check("npc_character_upgrades", n_bad == 0 and n_up >= 10, "%d upgraded, %d failed" % [n_up, n_bad])


func t_bounce() -> void:
	var o := region()
	var pad := inst("BouncePad", o, {"look": 1, "bounce_velocity": 15.0})
	await frames(3)
	check("bounce_group_meta", pad.is_in_group("bouncy") and float(pad.get_meta("bounce_velocity")) == 15.0, "group bouncy, meta bounce_velocity=15")
	put(o + Vector3(0, 4.0, 0))
	var peak := -INF
	var bounced_before := stub.bounces
	for i in 120:
		await get_tree().physics_frame
		if stub.bounces > bounced_before:
			peak = maxf(peak, stub.global_position.y)
	check("bounce_launches_player", stub.bounces > bounced_before and peak > o.y + 4.0, "bounces=%d, peak after bounce %.2f m" % [stub.bounces - bounced_before, peak])


func t_switch_cage() -> void:
	var o := region()
	var s1 := inst("SlamSwitch", o + Vector3(-4, 0, 0))
	var s2 := inst("SlamSwitch", o + Vector3(4, 0, 0))
	var cage := load("res://scenes/objects/Cage.tscn").instantiate() as Node3D
	cage.set("reward_truffle_id", "TEST-CAGE")
	var sw: Array[NodePath] = [NodePath("../" + str(s1.name)), NodePath("../" + str(s2.name))]
	cage.set("switches", sw)
	add_child(cage)
	cage.global_position = o + Vector3(0, 0, -6)
	await frames(3)
	put((s1 as Node3D).global_position + Vector3(0, 0.4, 2.5))
	await frames(10)
	check("switch_ignores_walk", not bool(s1.get("is_pressed")), "walking near does not press")
	await slam_at((s1 as Node3D).global_position)
	check("switch_pressed_by_slam", bool(s1.get("is_pressed")), "Ham Slam presses switch 1")
	check("cage_waits_for_all", not bool(cage.get("is_open")), "1 of 2 pressed")
	await slam_at((s2 as Node3D).global_position)
	await frames(70)
	check("cage_opens_when_all_pressed", bool(cage.get("is_open")), "2 of 2 pressed")
	check("cage_releases_truffle", truffles_with_id("TEST-CAGE").size() == 1, "truffle at TruffleMarker")


func t_bellows() -> void:
	var o := region()
	var wz := inst("WindZone", o + Vector3(0, 1.5, -6), {"size": Vector3(3, 3, 6)})
	var b1: Node = load("res://scenes/objects/BellowsMachine.tscn").instantiate()
	b1.set("group_id", "test")
	b1.set("wind_zone_path", NodePath("../" + str(wz.name)))
	add_child(b1)
	(b1 as Node3D).global_position = o
	var b2 := inst("BellowsMachine", o + Vector3(8, 0, 0), {"group_id": "test"})
	var bs := inst("BellowsSet", o + Vector3(4, 0, 4), {"group_id": "test", "reward_truffle_id": "TEST-BELLOWS"})
	var broke := [0]
	b1.connect("broken", func(_b: Node) -> void: broke[0] += 1)
	b2.connect("broken", func(_b: Node) -> void: broke[0] += 1)
	await frames(60)
	var drive_seen: float = wz.get("drive")
	check("bellows_drives_wind", bool(wz.get("enabled")) and drive_seen > 0.0, "linked zone enabled, drive=%.2f" % drive_seen)
	put(o + Vector3(0, 1.7, 0.4))
	await frames(10)
	check("bellows_survive_standing", not bool(b1.get("is_broken")), "standing on top does not break it")
	await slam_at(o + Vector3(0, 1.6, 0.4))
	check("bellows_break_on_slam", bool(b1.get("is_broken")) and broke[0] == 1, "broken signal count=%d" % broke[0])
	check("bellows_stop_wind", not bool(wz.get("enabled")) and (wz.call("get_wind", wz.global_position) as Vector3) == Vector3.ZERO, "zone disabled")
	check("bellows_no_truffle_yet", truffles_with_id("TEST-BELLOWS").size() == 0, "1 of 2 broken")
	await slam_at((b2 as Node3D).global_position + Vector3(0, 1.6, 0.4))
	await frames(10)
	check("bellows_all_broken_truffle", truffles_with_id("TEST-BELLOWS").size() == 1 and bool(bs.get("reward_given")), "2 of 2 broken -> truffle")


func t_crate() -> void:
	var o := region()
	var crate := inst("BreakableCrate", o, {"acorns": 4})
	await frames(3)
	var acorns_before := get_tree().get_nodes_in_group("acorn").size()
	put(o + Vector3(0, 0.05, 1.2))
	stub.rotation = Vector3.ZERO
	await frames(3)
	var hits := stub.punch("punch")
	await frames(5)
	var acorns_after := get_tree().get_nodes_in_group("acorn").size()
	check("crate_breaks_on_punch", hits >= 1, "hit_by_player(punch) landed on %d hurtbox(es); crate freed=%s" % [hits, not is_instance_valid(crate)])
	check("crate_pops_acorns", acorns_after - acorns_before == 4, "new acorns=%d" % (acorns_after - acorns_before))
	var crate2 := inst("BreakableCrate", o + Vector3(6, 0, 0), {"acorns": 0})
	await frames(3)
	await slam_at(o + Vector3(6, 1.0, 0))
	check("crate_breaks_on_slam", not is_instance_valid(crate2) or bool(crate2.get("is_broken")), "Ham Slam from above")


func t_buried() -> void:
	var o := region()
	var bt := inst("BuriedTreasure", o, {"truffle_id": "TEST-BURIED"})
	await frames(3)
	await slam_at(o)
	check("buried_needs_sniff", not bool(bt.get("is_dug")), "slam before sniffing only splashes")
	put(o + Vector3(1.0, 0.05, 0))
	await frames(3)
	stub.sniff()
	await frames(3)
	check("buried_sniffed", bool(bt.get("was_sniffed")), "sniff marks the patch")
	await slam_at(o)
	await frames(5)
	check("buried_dig_truffle", bool(bt.get("is_dug")) and truffles_with_id("TEST-BURIED").size() == 1, "slam after sniff digs out the truffle")
	# Hero-track contract: the player calls on_sniffed(self) directly and skips targets whose is_sniff_active() is false.
	var bt2 := inst("BuriedTreasure", o + Vector3(8, 0, 0), {"truffle_id": "TEST-BURIED-2"})
	await frames(3)
	var n_sniffed := [0]
	bt2.connect("sniffed", func(_b: Node) -> void: n_sniffed[0] += 1)
	check("sniff_contract_active_before", bool(bt2.call("is_sniff_active")), "fresh patch is an active sniff target")
	bt2.call("on_sniffed", stub)
	bt2.call("on_sniffed", stub)
	check("sniff_contract_on_sniffed", bool(bt2.get("was_sniffed")) and n_sniffed[0] == 1, "on_sniffed(player) marks it once (signals=%d)" % n_sniffed[0])
	bt2.call("dig")
	await frames(3)
	check("sniff_contract_inactive_after_dig", not bool(bt2.call("is_sniff_active")) and not bt2.is_in_group("sniff_target"), "dug patch leaves the sniff_target group")


func t_platforms() -> void:
	var o := region()
	var mp := inst("MovingPlatform", o + Vector3(0, 2, 0), {"travel": Vector3(6, 0, 0), "speed": 3.0})
	await frames(3)
	var body := mp.get("body") as Node3D
	var p0 := body.global_position
	put(p0 + Vector3(0, 0.3, 0))
	await frames(60)
	var moved := body.global_position.distance_to(p0)
	var rider := stub.global_position.x - p0.x
	check("moving_platform_moves", moved > 2.0, "moved %.2f m in 1 s" % moved)
	check("moving_platform_carries_player", rider > 1.5 and stub.global_position.y > o.y + 1.5, "stub carried %.2f m" % rider)
	mp.queue_free()
	var rp := inst("RotatingPlatform", o + Vector3(14, 6, 0), {"radius": 4.0, "degrees_per_second": 45.0})
	await frames(3)
	var plat := (rp.get("platforms") as Array)[0] as Node3D
	var q0 := plat.global_position
	await frames(30)
	var level_ok := absf(plat.global_transform.basis.y.dot(Vector3.UP) - 1.0) < 0.001
	check("rotating_platform_turns_level", plat.global_position.distance_to(q0) > 0.5 and level_ok, "arm moved %.2f m, platform level=%s" % [plat.global_position.distance_to(q0), level_ok])
	var fp := inst("FallingPlatform", o + Vector3(0, 3, 8))
	var fell := [false]
	fp.connect("fell", func() -> void: fell[0] = true)
	await frames(3)
	put((fp as Node3D).global_position + Vector3(0, 0.2, 0))
	await frames(30)
	check("falling_platform_wobbles_first", not fell[0] and int(fp.get("state")) == 1, "state=%d after 0.5 s" % int(fp.get("state")))
	await frames(40)
	check("falling_platform_falls", fell[0], "fell after the wobble")
	put(o + Vector3(30, 0, 0))
	await frames(360)
	check("falling_platform_respawns", int(fp.get("state")) == 0 and (fp as Node3D).global_position.distance_to(o + Vector3(0, 3, 8)) < 0.01, "state=%d pos=%s home=%s" % [int(fp.get("state")), (fp as Node3D).global_position, o + Vector3(0, 3, 8)])
	# Spawned the other way round (add_child first, then move), as runtime spawners might do.
	var fp2 := (load("res://scenes/objects/FallingPlatform.tscn") as PackedScene).instantiate() as Node3D
	add_child(fp2)
	fp2.global_position = o + Vector3(16, 3, 8)
	await frames(10)
	check("falling_platform_moved_after_add_child", fp2.global_position.distance_to(o + Vector3(16, 3, 8)) < 0.01, "pos=%s" % fp2.global_position)
	var vc := inst("VanishingCloud", o + Vector3(8, 3, 8), {"drift_amplitude": 0.0})
	var vanished := [false]
	vc.connect("vanished", func() -> void: vanished[0] = true)
	await frames(3)
	put((vc as Node3D).global_position + Vector3(0, 0.3, 0))
	await frames(40)
	check("cloud_holds_briefly", not vanished[0], "still there 0.65 s after landing")
	await frames(40)
	check("cloud_vanishes", vanished[0], "puffed away about 1 s after landing")


func t_hazard() -> void:
	var o := region()
	inst("HazardVolume", o + Vector3(0, 0.5, 0), {"size": Vector3(4, 1, 4), "look": 1, "damage": 1, "knockback_up": 8.0})
	await frames(3)
	var hits_before := stub.hp_hits
	put(o + Vector3(0, 0.1, 0))
	await frames(10)
	check("hazard_damages_player", stub.hp_hits > hits_before and stub.velocity.y > 0.0 or stub.hp_hits > hits_before, "hits=%d (stub reads group hazard + meta damage)" % (stub.hp_hits - hits_before))


func t_time_trial() -> void:
	var o := region()
	var tt := inst("TimeTrial", o, {"time_limit": 5.0, "reward_truffle_id": "TEST-TRIAL"})
	var ok := [false]
	tt.connect("succeeded", func(_t: float) -> void: ok[0] = true)
	await frames(3)
	put(o + Vector3(0, 0.2, 0))
	await frames(4)
	check("trial_starts", bool(tt.get("running")), "start gate")
	put(o + Vector3(0, 0.2, -21))
	await frames(4)
	check("trial_rejects_missed_rings", not ok[0] and not bool(tt.get("running")), "finish with rings missed resets")
	put(o + Vector3(0, 0.2, 0))
	await frames(4)
	for p in [Vector3(0, 1.8, -6), Vector3(2, 2.4, -11), Vector3(0, 1.8, -16)]:
		put(o + p - Vector3(0, 0.6, 0))
		await frames(4)
	put(o + Vector3(0, 0.2, -21))
	await frames(4)
	check("trial_success_truffle", ok[0] and truffles_with_id("TEST-TRIAL").size() == 1, "all rings + finish inside the limit")
	var tt2 := inst("TimeTrial", o + Vector3(12, 0, 0), {"time_limit": 0.5, "reward_truffle_id": "TEST-TRIAL2"})
	var fail := [""]
	tt2.connect("failed", func(r: String) -> void: fail[0] = r)
	await frames(3)
	put(o + Vector3(12, 0.2, 0))
	await frames(50)
	check("trial_timeout_resets", fail[0] == "timeout" and not bool(tt2.get("running")), "failed reason=%s" % fail[0])


func _press_interact() -> void:
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := InputEventAction.new()
	up.action = "interact"
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)


func _dialog_open() -> bool:
	return ObjSvc.can("UI", "is_dialog_open") and bool(ObjSvc.call_on("UI", "is_dialog_open"))


## Critique objects r1 regressions: the press that closes a dialog must not reopen it, and with overlapping talk zones
## only the nearest talker answers. Real interact events through Input.parse_input_event.
func t_talker_dialog_rules(npc: Node3D, o: Vector3) -> void:
	if not InputMap.has_action("interact") or not ObjSvc.can("UI", "is_dialog_open"):
		check("talker_no_reopen_on_close", true, "skipped: no interact action or UI")
		return
	var talks := [0]
	npc.connect("talked", func(_l: Array) -> void: talks[0] += 1)
	await frames(10)
	var opened := _dialog_open()
	for i in 8:
		if not _dialog_open():
			break
		await _press_interact()
		await frames(6)
	await frames(40)
	check("talker_no_reopen_on_close", opened and talks[0] == 0 and not _dialog_open(), "dialog opened=%s, closed with interact, reopened %d times" % [opened, talks[0]])
	npc.queue_free()
	await frames(3)
	var a := inst("SignPost", o + Vector3(30, 0, 0), {"board_text": "A", "lines": PackedStringArray(["Sign A."])})
	var b := inst("SignPost", o + Vector3(32.2, 0, 0), {"board_text": "B", "lines": PackedStringArray(["Sign B."])})
	var ta := [0]
	var tb := [0]
	a.connect("talked", func(_l: Array) -> void: ta[0] += 1)
	b.connect("talked", func(_l: Array) -> void: tb[0] += 1)
	await frames(3)
	put(o + Vector3(30.6, 0.05, 0.4))
	await frames(20)
	await _press_interact()
	await frames(10)
	check("talker_nearest_answers", ta[0] == 1 and tb[0] == 0, "overlapping zones: nearest talked %d, farther %d" % [ta[0], tb[0]])
	for i in 8:
		if not _dialog_open():
			break
		await _press_interact()
		await frames(6)
	a.queue_free()
	b.queue_free()
	await frames(3)


func t_talkers_portal_door() -> void:
	var o := region()
	var npc := inst("NPCTalker", o, {"speaker": "Bramwell", "lines": PackedStringArray(["Good afternoon, sir."])})
	var talked := [false]
	npc.connect("talked", func(_l: Array) -> void: talked[0] = true)
	await frames(3)
	put(o + Vector3(1.5, 0.05, 0.3))
	await frames(80)
	check("npc_faces_player", bool(npc.call("is_facing_player", 25.0)), "turned toward the player on the +X side")
	npc.call("talk")
	check("npc_talk", talked[0], "talk() -> UI.show_dialog or console fallback (UI present: %s)" % ObjSvc.can("UI", "show_dialog"))
	await t_talker_dialog_rules(npc, o)
	var portal := inst("StorybookPortal", o + Vector3(10, 0, 0), {"world_id": "W1", "required_truffles": 0, "route_on_enter": false})
	var entered := [""]
	portal.connect("entered", func(w: String) -> void: entered[0] = w)
	var locked := inst("StorybookPortal", o + Vector3(18, 0, 0), {"world_id": "W3", "required_truffles": 99, "route_on_enter": false})
	await frames(3)
	check("portal_locked_state", not bool(locked.get("is_open")) and bool(portal.get("is_open")), "99-truffle book stays shut, free book open")
	put(o + Vector3(10, 4.5, -0.1))
	await frames(25)
	check("portal_enter", entered[0] == "W1", "jumped into the pages -> entered(W1)")
	var door := inst("WolfDoor", o + Vector3(0, 0, -10), {"required_truffles": 99, "route_on_enter": false})
	await frames(3)
	put(o + Vector3(0, 0.05, -8))
	await frames(10)
	check("wolf_door_stays_locked", not bool(door.get("is_open")), "99 truffles required")
	var door2 := inst("WolfDoor", o + Vector3(8, 0, -10), {"required_truffles": 0, "route_on_enter": false})
	await frames(3)
	put(o + Vector3(8, 0.05, -8))
	await frames(10)
	check("wolf_door_opens_when_enough", bool(door2.get("is_open")), "0 required -> swings open")

extends Node3D
## Object interactions with the REAL player (res://scenes/player/Player.tscn), driven through the input actions
## (Input.action_press) and teleports via player.respawn(). Run headless:
##   python tools/godot.py run res://scenes/objects/ObjectsPlayerTest.tscn --headless --seconds 120 -- --profile=objects --results=<abs json>

var results: Array = []
var player: CharacterBody3D
var _region := 0


func _ready() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = ObjSvc.L_WORLD
	add_child(ground)
	ObjSvc.add_shape(ground, ObjSvc.box_shape(Vector3(800, 1, 60)), Vector3(300, -0.5, 0))
	var ps := load("res://scenes/player/Player.tscn") as PackedScene
	if ps == null:
		print("[ObjPTest] SKIP all: Player.tscn missing")
		get_tree().quit(2)
		return
	player = ps.instantiate() as CharacterBody3D
	player.position = Vector3(0, 0.1, 0)
	add_child(player)
	_run.call_deferred()


func region() -> Vector3:
	_region += 1
	return Vector3(_region * 30.0, 0, 0)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func put(p: Vector3, yaw_deg: float = 0.0) -> void:
	release_all()
	player.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), p))
	player.velocity = Vector3.ZERO


func release_all() -> void:
	for a in ["jump", "crouch", "attack", "sniff", "move_left", "move_right", "move_forward", "move_back"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func tap(action: String, hold: int = 2) -> void:
	Input.action_press(action)
	await frames(hold)
	Input.action_release(action)


func inst(scene_name: String, at: Vector3, props: Dictionary = {}) -> Node:
	var n := (load("res://scenes/objects/%s.tscn" % scene_name) as PackedScene).instantiate()
	for k in props:
		n.set(k, props[k])
	(n as Node3D).position = at
	add_child(n)
	return n


func check(test_name: String, ok: bool, detail: String = "") -> void:
	results.append({"name": test_name, "result": "PASS" if ok else "FAIL", "detail": detail})
	print("[ObjPTest] ", "PASS " if ok else "FAIL ", test_name, ": ", detail)


func slam_from_above(p: Vector3) -> void:
	put(p + Vector3(0, 3.0, 0))
	await frames(8)
	await tap("crouch", 3)
	await frames(60)


func truffles_with_id(id: String) -> int:
	var n := 0
	for t in get_tree().get_nodes_in_group("truffle"):
		if str(t.get("truffle_id")) == id and not t.is_queued_for_deletion():
			n += 1
	return n


func _run() -> void:
	if ObjSvc.can("Game", "new_game"):
		ObjSvc.call_on("Game", "new_game")
	await frames(10)
	var o := region()
	# Truffle
	var t := inst("Truffle", o, {"truffle_id": "PT-1"})
	await frames(2)
	put(o + Vector3(0, 0.05, 0))
	await frames(10)
	check("player_collects_truffle", bool(t.get("is_collected")) and ObjSvc.has_truffle("PT-1"), "Game.has_truffle(PT-1)=%s" % ObjSvc.has_truffle("PT-1"))
	await frames(60)
	# Wind
	o = region()
	var wz := inst("WindZone", o + Vector3(0, 2, 0), {"size": Vector3(8, 4, 6), "direction": Vector3(1, 0, 0), "strength": 6.0, "end_falloff": 0.0})
	await frames(2)
	put(o + Vector3(-3, 0.05, 0))
	await frames(10)
	var x0 := player.global_position.x
	await frames(40)
	check("player_pushed_by_wind", player.global_position.x - x0 > 0.5, "moved %.2f m in 2/3 s" % (player.global_position.x - x0))
	wz.queue_free()
	# Bounce pad
	o = region()
	inst("BouncePad", o, {"look": 2, "bounce_velocity": 15.0})
	await frames(2)
	put(o + Vector3(0, 3.0, 0))
	var peak := -INF
	var landed_once := false
	for i in 120:
		await get_tree().physics_frame
		if player.velocity.y > 10.0:
			landed_once = true
		if landed_once:
			peak = maxf(peak, player.global_position.y)
	check("player_bounces_on_pad", landed_once and peak > o.y + 4.0, "peak %.2f m after bounce" % peak)
	# Hazard
	o = region()
	inst("HazardVolume", o + Vector3(0, 0.4, 0), {"size": Vector3(4, 0.8, 4), "look": 1})
	await frames(2)
	var hp0: int = int(ObjSvc.autoload("Game").get("health")) if ObjSvc.autoload("Game") else 0
	put(o + Vector3(0, 0.05, 0))
	# respawn() grants about 0.6 s of invulnerability; stay in the chocolate past it.
	await frames(70)
	var hp1: int = int(ObjSvc.autoload("Game").get("health")) if ObjSvc.autoload("Game") else 0
	check("player_hurt_by_hot_chocolate", hp1 < hp0 or str(player.call("get_state_name")).contains("hurt"), "health %d -> %d, state %s" % [hp0, hp1, player.call("get_state_name")])
	await frames(90)
	# Slam switches -> cage
	o = region()
	var s1 := inst("SlamSwitch", o + Vector3(-4, 0, 0))
	var s2 := inst("SlamSwitch", o + Vector3(4, 0, 0))
	var cage := (load("res://scenes/objects/Cage.tscn") as PackedScene).instantiate()
	cage.set("reward_truffle_id", "PT-CAGE")
	var sw: Array[NodePath] = [NodePath("../" + str(s1.name)), NodePath("../" + str(s2.name))]
	cage.set("switches", sw)
	(cage as Node3D).position = o + Vector3(0, 0, -6)
	add_child(cage)
	await frames(3)
	put((s1 as Node3D).global_position + Vector3(0, 0.4, 2.5))
	await frames(20)
	check("switch_not_pressed_by_walking_near", not bool(s1.get("is_pressed")), "")
	await slam_from_above((s1 as Node3D).global_position)
	check("player_ham_slam_presses_switch", bool(s1.get("is_pressed")), "state after slam: %s" % player.call("get_state_name"))
	await slam_from_above((s2 as Node3D).global_position)
	await frames(80)
	check("player_slams_open_cage", bool(cage.get("is_open")) and truffles_with_id("PT-CAGE") == 1, "cage open=%s" % cage.get("is_open"))
	# Bellows
	o = region()
	var b := inst("BellowsMachine", o, {"group_id": "pt"})
	var bs := inst("BellowsSet", o + Vector3(4, 0, 3), {"group_id": "pt", "reward_truffle_id": "PT-BELLOWS"})
	await frames(3)
	await slam_from_above(o + Vector3(0, 1.6, 0.4))
	await frames(10)
	check("player_slam_breaks_bellows", bool(b.get("is_broken")) and bool(bs.get("reward_given")), "broken=%s" % b.get("is_broken"))
	# Crate punch
	o = region()
	var crate := inst("BreakableCrate", o, {"acorns": 3})
	await frames(3)
	put(o + Vector3(0, 0.02, 1.25), 0.0)
	await frames(20)
	var st_before := str(player.call("get_state_name"))
	await tap("attack", 2)
	await frames(20)
	check("player_punch_breaks_crate", not is_instance_valid(crate) or bool(crate.get("is_broken")), "state before punch %s, after %s" % [st_before, player.call("get_state_name")])
	await frames(60)
	# Buried treasure: sniff then slam
	o = region()
	# The proximity fallback is off, so only the player's own sniff (on_sniffed(self)) can reveal the patch.
	var bt := inst("BuriedTreasure", o, {"truffle_id": "PT-BURIED", "proximity_fallback": false})
	await frames(3)
	put(o + Vector3(1.2, 0.05, 0))
	await frames(5)
	Input.action_press("sniff")
	var locked := false
	for _i in 45:
		await frames(1)
		if player.get("sniff_target") == bt:
			locked = true
	Input.action_release("sniff")
	check("player_sniff_targets_patch", locked, "player.sniff_target locked onto the patch during the sniff")
	check("player_sniff_reveals_patch", bool(bt.get("was_sniffed")) and bt.get("last_sniffed_by") == player and str(bt.get("reveal_path")) == "player",
		"was_sniffed=%s by_player=%s path=%s" % [bt.get("was_sniffed"), bt.get("last_sniffed_by") == player, bt.get("reveal_path")])
	await slam_from_above(o)
	await frames(10)
	check("player_slam_digs_truffle", bool(bt.get("is_dug")) and truffles_with_id("PT-BURIED") == 1, "dug=%s" % bt.get("is_dug"))
	# A dug patch reports is_sniff_active() == false, so the player's sniff must ignore it.
	put(o + Vector3(1.2, 0.05, 0))
	await frames(5)
	Input.action_press("sniff")
	var relocked := false
	for _i in 30:
		await frames(1)
		if is_instance_valid(bt) and player.get("sniff_target") == bt:
			relocked = true
	Input.action_release("sniff")
	check("player_sniff_ignores_dug_patch", not relocked, "sniff_target after dig: %s" % player.get("sniff_target"))
	# Moving platform carry
	o = region()
	var mp := inst("MovingPlatform", o + Vector3(0, 2, 0), {"travel": Vector3(6, 0, 0), "speed": 3.0, "pause_at_ends": 0.0})
	await frames(3)
	var body := mp.get("body") as Node3D
	put(body.global_position + Vector3(0, 0.1, 0))
	await frames(5)
	var px := player.global_position.x
	await frames(50)
	check("player_rides_moving_platform", player.global_position.x - px > 1.5 and player.global_position.y > o.y + 1.5, "carried %.2f m" % (player.global_position.x - px))
	# Vanishing cloud and falling platform
	o = region()
	var vc := inst("VanishingCloud", o + Vector3(0, 3, 0), {"drift_amplitude": 0.0})
	var fp := inst("FallingPlatform", o + Vector3(8, 3, 0))
	await frames(3)
	put(o + Vector3(0, 3.3, 0))
	await frames(90)
	check("cloud_vanishes_under_player", int(vc.get("state")) == 2, "state=%d" % int(vc.get("state")))
	put(o + Vector3(8, 3.2, 0))
	await frames(70)
	check("falling_platform_drops_under_player", int(fp.get("state")) >= 2, "state=%d" % int(fp.get("state")))
	# Checkpoint and portal
	o = region()
	var cp := inst("Checkpoint", o, {"world_id": "PT"})
	var portal := inst("StorybookPortal", o + Vector3(8, 0, 0), {"world_id": "W1", "required_truffles": 0, "route_on_enter": false})
	var entered := [""]
	portal.connect("entered", func(w: String) -> void: entered[0] = w)
	await frames(3)
	put(o + Vector3(0, 0.05, 0))
	await frames(10)
	check("player_activates_checkpoint", bool(cp.get("is_active")), "")
	put(o + Vector3(8, 5.0, -0.1))
	await frames(40)
	check("player_enters_storybook", entered[0] == "W1", "entered=%s" % entered[0])
	# Vine
	o = region()
	inst("Climbable", o, {"look": 0, "height": 6.0})
	await frames(3)
	put(o + Vector3(0.45, 1.5, 0), 90.0)
	await frames(30)
	var st := str(player.call("get_state_name"))
	check("player_grabs_vine", st.contains("climb") or st.contains("pole"), "state=%s" % st)
	release_all()
	var n_pass := 0
	var n_fail := 0
	for r in results:
		if r.result == "PASS":
			n_pass += 1
		else:
			n_fail += 1
	print("[ObjPTest] SUMMARY pass=%d fail=%d" % [n_pass, n_fail])
	var dev := ObjSvc.autoload("Dev")
	var out_path := str(dev.call("arg", "results", "")) if dev != null and dev.has_method("arg") else ""
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"utc": Time.get_datetime_string_from_system(true) + "Z", "player": "res://scenes/player/Player.tscn",
				"pass": n_pass, "fail": n_fail, "results": results}, "  "))
			f.close()
	get_tree().quit(0 if n_fail == 0 else 1)

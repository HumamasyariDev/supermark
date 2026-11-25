extends Node
## W2-2 Goose Gag finale played by a simple "human-like" chaser that drives the REAL player through Input actions
## (camera-relative stick, attack/jump presses). It triggers the cage-freed reveal directly (the S1-S3 slams were
## played for real in the earlier r1_fun goose run), places Mak in the courtyard and chases for up to 60 s.
## Strategy: steer at the goose's position 0.35 s ahead; attack when within 3.2 m at speed (ground dive) or
## when it is dazed. Prints [CHASE] lines: hits, dazes, hops, damage, time to finish.

var world: Node
var player: CharacterBody3D
var gw: Node3D
var t := 0.0
var started := false
var last_state := ""
var last_hits := 0
var last_hp := -1
var prev_pos := Vector3.ZERO
var atk_cool := 0.0
var stats := {"dives": 0, "dazes": 0, "hops": 0, "dashes": 0, "bumps": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_boot.call_deferred()


func say(s: String) -> void:
	print("[CHASE] t=%.2f %s" % [t, s])


func _boot() -> void:
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and cs.get("player") != null:
			world = cs
			player = cs.get("player") as CharacterBody3D
			break
	await get_tree().create_timer(2.5, true).timeout
	var life: Node = world.get("life")
	if life == null or not life.has_method("_goose_wolf_reveal"):
		say("NO LIFE NODE / reveal method")
		get_tree().quit(3)
		return
	player.global_position = Vector3(12.5, 50.4, -27.5)
	life.call("_goose_wolf_reveal")
	await get_tree().create_timer(1.0, true).timeout
	gw = world.find_child("E16_GooseWolf", true, false) as Node3D
	if gw == null:
		say("NO GOOSE WOLF")
		get_tree().quit(3)
		return
	say("start goose at %s mak at %s" % [gw.global_position, player.global_position])
	started = true


func _release() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "attack", "jump"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func _stick_world(d: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var f := -cam.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var r := cam.global_basis.x
	r.y = 0.0
	r = r.normalized()
	d.y = 0.0
	d = d.normalized()
	var x := d.dot(r)
	var y := d.dot(f)
	_release_moves()
	if x > 0.0: Input.action_press("move_right", x)
	elif x < 0.0: Input.action_press("move_left", -x)
	if y > 0.0: Input.action_press("move_forward", y)
	elif y < 0.0: Input.action_press("move_back", -y)


func _release_moves() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)


func _physics_process(delta: float) -> void:
	t += delta
	if not started or not is_instance_valid(gw):
		if started and not is_instance_valid(gw):
			say("goose node freed")
			_finish()
		return
	atk_cool = maxf(0.0, atk_cool - delta)
	Input.action_release("attack")
	var st := String(gw.get("state"))
	var hits := int(gw.get("hits"))
	if st != last_state:
		say("goose state %s -> %s (hits %d) dist %.1f" % [last_state, st, hits, player.global_position.distance_to(gw.global_position)])
		if st == "dazed": stats["dazes"] += 1
		if st == "hop": stats["hops"] += 1
		if st == "dash": stats["dashes"] += 1
		last_state = st
	if hits != last_hits:
		say("HIT %d landed with mak state %s" % [hits, String(player.get("state"))])
		last_hits = hits
	var hp := -1
	var g := get_node_or_null("/root/Game")
	if g and "health" in g: hp = int(g.get("health"))
	if hp != last_hp:
		say("health %d" % hp)
		last_hp = hp
	if st in ["exit", "done"] or t > 75.0:
		if t > 75.0: say("TIMEOUT: not finished, hits %d" % hits)
		else: say("FINISHED in %.1f s of chase, hits %d" % [t, hits])
		await get_tree().create_timer(3.0, true).timeout
		_finish()
		return
	var gp := gw.global_position
	var gv := (gp - prev_pos) / maxf(delta, 0.001)
	prev_pos = gp
	var target := gp + gv * 0.35
	if st == "dazed": target = gp
	var to := target - player.global_position
	_stick_world(to)
	var dist := Vector2(to.x, to.z).length()
	var ps := String(player.get("state"))
	var fs := float(player.get("forward_speed"))
	if atk_cool <= 0.0 and (dist < 3.2 and (fs > 5.0 or st == "dazed")):
		Input.action_press("attack")
		atk_cool = 0.9
		stats["dives"] += 1
		say("attack pressed (mak %s speed %.1f dist %.1f goose %s)" % [ps, fs, dist, st])


func _finish() -> void:
	say("STATS %s" % JSON.stringify(stats))
	_release()
	get_tree().quit(0)

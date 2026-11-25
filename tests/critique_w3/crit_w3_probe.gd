extends Node
## Critic plans for W3 (FUN lens, round 1). Each plan is a list of steps for the builder's bot driver
## (w3_bot.gd). Also logs Mak's health and state once per second ("[CRIT] ..." lines) so the critic can see damage.

var _level: Node
var _t := 0.0
var _last_hp := -1
var _f: FileAccess


## Pass r1c: the run log is trimmed to its last 400 lines by tools/godot.py, so the probe also writes its own file.
func _log(t: String) -> void:
	print(t)
	if _f == null:
		var dev := get_node_or_null("/root/Dev")
		var nm: String = String(dev.call("arg", "crit-plan", "x")) if dev else "x"
		var dir := ProjectSettings.globalize_path("res://").path_join("../Docs/progress/critique/w3/r1_fun/r1c")
		DirAccess.make_dir_recursive_absolute(dir)
		_f = FileAccess.open(dir.path_join("probe_%s_%d.log" % [nm, Time.get_unix_time_from_system()]), FileAccess.WRITE)
	if _f:
		_f.store_line(t)
		_f.flush()


func _plans() -> Dictionary:
	var p := {}
	# Main route from the courtyard to tier C: wafer bridge, jelly beat (jump, jump, double), tier A ring,
	# marshmallow bouncer to tier B, called lift to tier C.
	p["climb"] = [
		{"do": "teleport", "at": Vector3(8.0, 8.1, -24.0), "yaw": -90.0},
		{"do": "wait", "frames": 20},
		{"do": "goto", "at": Vector3(22.5, 8.2, -24.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(25.4, 8.0, -21.0), "tol": 0.5, "stop": true},
		{"do": "wait", "frames": 10},
		{"do": "mark", "text": "CRIT jelly beat"},
		{"do": "press", "action": "jump", "frames": 12},
		{"do": "hop", "at": Vector3(27.11, 9.0, -22.26)},
		{"do": "wait", "frames": 4},
		{"do": "press", "action": "jump", "frames": 12},
		{"do": "hop", "at": Vector3(30.34, 10.0, -25.24)},
		{"do": "wait", "frames": 4},
		{"do": "press", "action": "jump", "frames": 16},
		{"do": "hop", "at": Vector3(33.4, 12.0, -27.7)},
		{"do": "mark", "text": "CRIT on tier A"},
		{"do": "goto", "at": Vector3(44.0, 12.0, -26.3), "tol": 0.8},
		{"do": "goto", "at": Vector3(51.6, 12.0, -29.2), "tol": 0.6},
		{"do": "goto", "at": Vector3(53.0, 12.0, -30.6), "tol": 0.4, "stop": true},
		{"do": "press", "action": "jump", "frames": 12},
		{"do": "hop", "at": Vector3(53.5, 12.8, -33.0), "next": Vector3(50.0, 16.0, -36.5)},
		{"do": "hop", "at": Vector3(50.0, 16.0, -36.5)},
		{"do": "mark", "text": "CRIT on tier B"},
		{"do": "goto", "at": Vector3(51.0, 16.3, -41.0), "tol": 0.4, "stop": true},
		{"do": "until_y_above", "y": 20.1, "max_s": 6.0},
		{"do": "goto", "at": Vector3(47.5, 20.0, -43.0), "tol": 0.5, "stop": true},
		{"do": "mark", "text": "CRIT on tier C"},
		{"do": "wait", "frames": 30},
	]
	# Candle wave from tier D, played naively (no waiting for the flames) and then with waiting.
	p["candles"] = [
		{"do": "teleport", "at": Vector3(41.2, 24.1, -44.6), "yaw": -90.0},
		{"do": "wait", "frames": 30},
		{"do": "mark", "text": "CRIT candle 1 naive"},
		{"do": "press", "action": "jump", "frames": 12},
		{"do": "hop", "at": Vector3(43.3, 25.2, -44.0)},
		{"do": "press", "action": "jump", "frames": 12},
		{"do": "hop", "at": Vector3(43.4, 26.4, -41.5)},
		{"do": "press", "action": "jump", "frames": 12},
		{"do": "hop", "at": Vector3(42.9, 27.6, -39.2)},
		{"do": "press", "action": "jump", "frames": 12},
		{"do": "hop", "at": Vector3(40.0, 28.0, -40.6)},
		{"do": "mark", "text": "CRIT on summit"},
		{"do": "wait", "frames": 60},
	]
	# Maze as a player who never sniffs: walk the solution cells by hand (the crows and brute are live).
	p["maze_walk"] = [
		{"do": "teleport", "at": Vector3(-36.0, 4.1, 26.0), "yaw": 0.0},
		{"do": "wait", "frames": 20},
		{"do": "goto", "at": Vector3(-36.0, 4.0, 18.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(-44.0, 4.0, 18.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(-44.0, 4.0, 14.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(-52.0, 4.0, 14.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(-52.0, 4.0, 10.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(-48.0, 4.0, 10.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(-48.0, 4.0, 6.0), "tol": 0.6},
		{"do": "mark", "text": "CRIT through the gate"},
		{"do": "goto", "at": Vector3(-48.0, 4.0, 1.5), "tol": 0.6, "stop": true},
		{"do": "wait", "frames": 180},
		{"do": "press", "action": "jump", "frames": 14, "stick": Vector2(0, 0.7)},
		{"do": "until_truffle", "id": "W3-1", "max_s": 4.0},
	]
	# Pass r1c: a first-timer in the maze who never sniffs. Walks the entrance corridor, wakes the stalker at (3,2),
	# then wanders (a wrong turn north, a dead-end pause) while the brute hops. Logs health and how long it takes.
	p["maze_naive"] = [
		{"do": "teleport", "at": Vector3(-36.0, 4.1, 26.0), "yaw": 0.0},
		{"do": "wait", "frames": 20},
		{"do": "goto", "at": Vector3(-36.0, 4.0, 18.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(-44.0, 4.0, 18.0), "tol": 0.6},
		{"do": "mark", "text": "CRIT junction (3,2): stalker should wake"},
		{"do": "steer", "stick": Vector2(-1, 0), "frames": 90},
		{"do": "steer", "stick": Vector2(0, 1), "frames": 90},
		{"do": "steer", "stick": Vector2(0, 0), "frames": 120},
		{"do": "mark", "text": "CRIT dead-end pause over"},
		{"do": "steer", "stick": Vector2(1, 0), "frames": 90},
		{"do": "steer", "stick": Vector2(0, -1), "frames": 60},
		{"do": "goto", "at": Vector3(-44.0, 4.0, 14.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(-52.0, 4.0, 14.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(-52.0, 4.0, 10.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(-48.0, 4.0, 10.0), "tol": 0.6},
		{"do": "goto", "at": Vector3(-48.0, 4.0, 6.0), "tol": 0.6},
		{"do": "mark", "text": "CRIT through the gate"},
		{"do": "goto", "at": Vector3(-48.0, 4.0, 2.0), "tol": 0.6, "stop": true},
		{"do": "wait", "frames": 240},
	]
	# Pass r1c: the nest as a first-timer tries it: a triple jump at the trunk, then jump-mashing near the brute.
	p["nest_naive"] = [
		{"do": "teleport", "at": Vector3(-48.0, 4.1, 8.0), "yaw": 0.0},
		{"do": "wait", "frames": 30},
		{"do": "goto", "at": Vector3(-48.0, 4.0, 5.0), "tol": 0.6, "stop": true},
		{"do": "mark", "text": "CRIT triple jump at the trunk"},
		{"do": "press", "action": "jump", "frames": 8, "stick": Vector2(0, 1)},
		{"do": "until_grounded", "stick": Vector2(0, 1)},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(0, 1)},
		{"do": "until_grounded", "stick": Vector2(0, 1)},
		{"do": "press", "action": "jump", "frames": 16, "stick": Vector2(0, 1)},
		{"do": "until_grounded", "stick": Vector2(0, 0)},
		{"do": "mark", "text": "CRIT after triple"},
		{"do": "goto", "at": Vector3(-48.0, 4.0, 1.0), "tol": 0.6, "stop": true},
		{"do": "steer", "stick": Vector2(0, 0), "frames": 300},
		{"do": "mark", "text": "CRIT stood still 5 s under the nest"},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(0, 0)},
		{"do": "wait", "frames": 90},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(0, 0)},
		{"do": "wait", "frames": 90},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(0, 0)},
		{"do": "wait", "frames": 90},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(0, 0)},
		{"do": "wait", "frames": 240},
	]
	# Pass r1c: the fort as a first-timer plays it: walk in, ignore the drum, punch the squad for 20 s.
	p["fort_naive"] = [
		{"do": "teleport", "at": Vector3(36.0, 2.1, 43.0), "yaw": -90.0},
		{"do": "wait", "frames": 20},
		{"do": "steer", "stick": Vector2(1, 0), "frames": 60},
		{"do": "steer", "stick": Vector2(0, 0), "frames": 150},
		{"do": "mark", "text": "CRIT punching the squad"},
		{"do": "steer", "stick": Vector2(1, 0.3), "frames": 30},
		{"do": "press", "action": "attack", "frames": 4},
		{"do": "wait", "frames": 20},
		{"do": "press", "action": "attack", "frames": 4},
		{"do": "wait", "frames": 20},
		{"do": "steer", "stick": Vector2(1, -0.3), "frames": 30},
		{"do": "press", "action": "attack", "frames": 4},
		{"do": "wait", "frames": 20},
		{"do": "press", "action": "attack", "frames": 4},
		{"do": "wait", "frames": 20},
		{"do": "steer", "stick": Vector2(-1, 0.3), "frames": 30},
		{"do": "press", "action": "attack", "frames": 4},
		{"do": "wait", "frames": 20},
		{"do": "press", "action": "attack", "frames": 4},
		{"do": "steer", "stick": Vector2(1, 0), "frames": 40},
		{"do": "press", "action": "attack", "frames": 4},
		{"do": "wait", "frames": 20},
		{"do": "press", "action": "attack", "frames": 4},
		{"do": "wait", "frames": 20},
		{"do": "steer", "stick": Vector2(0, 1), "frames": 40},
		{"do": "press", "action": "attack", "frames": 4},
		{"do": "wait", "frames": 600},
		{"do": "mark", "text": "CRIT end"},
	]
	# Pass r1c: the builder's nest finale from the hedge gate (skips the maze), with the bot's brute_bounce step.
	p["nest_bot"] = [
		{"do": "teleport", "at": Vector3(-48.0, 4.1, 8.0), "yaw": 0.0},
		{"do": "wait", "frames": 30},
		{"do": "goto", "at": Vector3(-48.0, 4.0, 1.4), "tol": 0.5, "stop": true},
		{"do": "mark", "text": "CRIT in the clearing under the nest"},
		{"do": "brute_bounce", "id": "brute_clearing", "to": Vector3(-48, 11.0, -1), "max_s": 45.0},
		{"do": "until_truffle", "id": "W3-1", "max_s": 4.0},
	]
	return p


func _process(delta: float) -> void:
	if _level == null:
		var cs := get_tree().current_scene
		if cs == null or cs.name != "W3":
			return
		for c in cs.get_children():
			if c.has_method("_bot_plans"):
				_level = c
		if _level == null:
			return
		var dev := get_node_or_null("/root/Dev")
		var nm: String = String(dev.call("arg", "crit-plan", "climb")) if dev else "climb"
		var plans := _plans()
		if not plans.has(nm):
			print("[CRIT] unknown plan ", nm)
			return
		var bot := Node.new()
		bot.name = "CritBot"
		bot.set_script(load("res://scripts/worlds/w3_bot.gd"))
		_level.add_child(bot)
		bot.call("setup", "crit_" + nm, plans[nm], 120.0)
		_log("[CRIT] plan %s attached (%d steps)" % [nm, plans[nm].size()])
		return
	_t += delta
	var g := get_node_or_null("/root/Game")
	var hp := int(g.get("health")) if g else -1
	if hp != _last_hp:
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		_log("[CRIT] health %d -> %d at %s (t=%.1f)" % [_last_hp, hp, pl.global_position if pl else Vector3.ZERO, _t])
		_last_hp = hp
	if _t >= 1.0 and fmod(_t, 1.0) < delta:
		var pl2 := get_tree().get_first_node_in_group("player") as Node3D
		if pl2:
			var extra := ""
			var cb := _level.get_node_or_null("CritBot")
			if cb:
				extra += " step=%d done=%s" % [int(cb.get("step")), cb.get("_done")]
			var gm := get_node_or_null("/root/Game")
			if gm:
				extra += " acorns=%s" % gm.get("acorns")
				if gm.has_method("has_truffle"):
					extra += " W3-1=%s" % gm.call("has_truffle", "W3-1")
			var fort := _level.get_node_or_null("FortEncounter")
			if fort:
				extra += " fort=%d/%s hits=%d" % [int(fort.get("phase")), fort.get("_sub"), int(fort.get("hits"))]
			var ens: Variant = _level.get("enemies")
			if ens is Dictionary and (ens as Dictionary).has("brute_clearing") and is_instance_valid(ens["brute_clearing"]):
				var br: Node3D = ens["brute_clearing"]
				extra += " brute=%s@%s" % [br.get("state"), br.global_position.snapped(Vector3(0.1, 0.1, 0.1))]
			_log("[CRIT] t=%.0f pos=%s state=%s%s" % [_t, pl2.global_position.snapped(Vector3(0.1, 0.1, 0.1)), pl2.call("get_state_name"), extra])

extends Node3D
## Fix stage r1 probe of JuiceSfx's polled runtime glue, through the real autoloads (Audio, Juice -> JuiceSfx, UI):
## a stand-in node in group "player" reports states (wall_slide, belly_slide, pole_climb) while it moves, so the
## wall-slide loop, the slide loop's speed modulation, climb steps and the low-health pulse can be measured; then the
## pause menu treatment (low-pass, -6 dB, SFX paused and resumed), the death music duck, proximity loops near a
## truffle-group node, and the per-world reverb. Prints AUDIO_FIX_PROBE {...}.
## Run: python tools/godot.py run res://assets/audio/tests/AudioFixProbe.tscn --seconds 90 -- --profile=audio_fix --out=<abs json>

class FakePlayer extends Node3D:
	var state := "idle"
	func get_state_name() -> String:
		return state

var fails: Array = []
var checks := 0
var res := {}


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var juice := get_node_or_null("/root/Juice")
	var sfx: Node = juice.get_node_or_null("JuiceSfx") if juice else null
	var audio := get_node_or_null("/root/Audio")
	_ok(sfx != null and audio != null, "JuiceSfx and Audio present")
	if sfx == null:
		return _finish()
	sfx.set("log_plays", true)
	var pl := FakePlayer.new()
	pl.add_to_group("player")
	add_child(pl)
	sfx.set("_player", null)
	# --- wall slide: loop starts, louder when falling fast, stops when the state ends
	pl.state = "wall_slide"
	var v_slow := await _slide_down(pl, 1.0, 0.6, "wall_slide", sfx)
	var v_fast := await _slide_down(pl, 6.0, 0.6, "wall_slide", sfx)
	res["wall_slide_db"] = [v_slow, v_fast]
	_ok(v_slow > -70.0 and v_fast > v_slow + 4.0, "wall-slide loop plays and follows the fall speed (%.1f -> %.1f dB)" % [v_slow, v_fast])
	pl.state = "idle"
	await get_tree().create_timer(0.6).timeout
	_ok(not (sfx.get("_loops") as Dictionary).has("wall_slide"), "wall-slide loop stops with the state")
	# --- slide: started by polling (slope), pitch follows speed
	pl.state = "slope_slide"
	var p_slow := await _move(pl, Vector3(3.0, 0, 0), 0.7, "slide", sfx, "pitch_scale")
	var p_fast := await _move(pl, Vector3(12.0, 0, 0), 0.7, "slide", sfx, "pitch_scale")
	res["slide_pitch"] = [p_slow, p_fast]
	_ok(p_slow > 0.0 and p_fast > p_slow + 0.08, "slide loop starts on a slope and its pitch follows speed (%.2f -> %.2f)" % [p_slow, p_fast])
	await _move(pl, Vector3(10.0, 0, 0), 4.0, "slide", sfx, "pitch_scale")
	_ok((sfx.get("_loops") as Dictionary).has("slide"), "slide loop still runs after 5.4 s (was cut at 2.5 s)")
	pl.state = "idle"
	await get_tree().create_timer(0.7).timeout
	_ok(not (sfx.get("_loops") as Dictionary).has("slide"), "slide loop stops when the slide ends")
	# --- pole climb steps
	(sfx.get("played") as Array).clear()
	pl.state = "pole_climb"
	await _move(pl, Vector3(0, 1.6, 0), 2.0, "", sfx, "")
	var steps := (sfx.get("played") as Array).filter(func(r): return r["key"] == "climb_shimmy").size()
	res["climb_steps_2s"] = steps
	_ok(steps >= 3, "climb steps while moving on a pole: %d in 2 s" % steps)
	pl.state = "idle"
	# --- low health pulse at one slice
	var game := get_node_or_null("/root/Game")
	if game != null and "health" in game:
		var hp: int = game.get("health")
		game.set("health", 1)
		(sfx.get("played") as Array).clear()
		await get_tree().create_timer(5.5).timeout
		var pulses := (sfx.get("played") as Array).filter(func(r): return r["key"] == "low_health").size()
		res["low_health_pulses_5s"] = pulses
		_ok(pulses >= 1 and pulses <= 3, "soft low-health pulse at one slice: %d in 5.5 s" % pulses)
		game.set("health", hp)
	# --- death duck on the Music bus
	sfx.call("duck_music", -14.0, 0.05, 0.6, 0.5)
	await get_tree().create_timer(0.3).timeout
	var duck_db := _effect_db("Music", "juice_duck")
	await get_tree().create_timer(1.2).timeout
	var after_db := _effect_db("Music", "juice_duck")
	res["duck_db"] = [duck_db, after_db]
	_ok(duck_db < -12.0 and after_db > -0.5, "music duck -14 dB and back (%.1f, %.1f)" % [duck_db, after_db])
	# --- pause menu treatment
	var a2 := audio as Node
	var p2: Node = a2.call("play_sfx", "thunder", Vector3.INF, 0.0, -20.0)
	var ui := get_node_or_null("/root/UI")
	var pm: Variant = ui.get("pause_menu") if ui != null and "pause_menu" in ui else null
	if pm is Node:
		(pm as Node).call("open")
		await get_tree().create_timer(0.4, true).timeout
		var lp_on := _effect_enabled("Music", "juice_pause_lp")
		var paused_sfx := p2 != null and bool(p2.get("stream_paused"))
		res["pause"] = {"lowpass_on": lp_on, "amp_db": _effect_db("Ambience", "juice_pause_db"), "thunder_paused": paused_sfx}
		_ok(lp_on and _effect_db("Ambience", "juice_pause_db") < -5.0 and paused_sfx, "pause menu: low-pass and -6 dB on, SFX paused %s" % str(res["pause"]))
		(pm as Node).call("resume")
		await get_tree().create_timer(0.4, true).timeout
		_ok(not _effect_enabled("Music", "juice_pause_lp") and not bool(p2.get("stream_paused")), "pause closed: filter off, SFX resumed")
	else:
		res["pause"] = "no pause menu in this run"
	_finish()


func _slide_down(pl: Node3D, speed: float, dur: float, id: String, sfx: Node) -> float:
	return await _move(pl, Vector3(0, -speed, 0), dur, id, sfx, "volume_db")


func _move(pl: Node3D, vel: Vector3, dur: float, id: String, sfx: Node, prop: String) -> float:
	var t := 0.0
	while t < dur:
		await get_tree().process_frame
		var d := get_process_delta_time()
		pl.global_position += vel * d
		t += d
	if id == "":
		return 0.0
	var loops: Dictionary = sfx.get("_loops")
	if not loops.has(id) or not is_instance_valid(loops[id]["player"]):
		return -99.0 if prop == "volume_db" else 0.0
	return float((loops[id]["player"] as Node).get(prop))


func _effect(bus: String, tag: String) -> Array:
	var bi := AudioServer.get_bus_index(bus)
	for i in AudioServer.get_bus_effect_count(bi):
		var e := AudioServer.get_bus_effect(bi, i)
		if e != null and e.resource_name == tag:
			return [bi, i, e]
	return []


func _effect_db(bus: String, tag: String) -> float:
	var r := _effect(bus, tag)
	return (r[2] as AudioEffectAmplify).volume_db if not r.is_empty() and r[2] is AudioEffectAmplify else 99.0


func _effect_enabled(bus: String, tag: String) -> bool:
	var r := _effect(bus, tag)
	return not r.is_empty() and AudioServer.is_bus_effect_enabled(int(r[0]), int(r[1]))


func _ok(cond: bool, what: String) -> void:
	checks += 1
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		fails.append(what)


func _finish() -> void:
	res["checks"] = checks
	res["failures"] = fails
	print("AUDIO_FIX_PROBE " + JSON.stringify(res))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			var f := FileAccess.open(a.substr(6), FileAccess.WRITE)
			f.store_string(JSON.stringify(res, " "))
	get_tree().paused = false
	get_tree().quit(0 if fails.is_empty() else 1)

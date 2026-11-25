extends Node
## CRITIC round 1, QA lens, BOSS track (night 01). Test-only; no level uses it.
## The scene root spawns a copy of this script under /root (survives scene changes), enters the boss through the real
## Router and runs one mode:
##   --qa=fullrun   the track's real-player bot (--bosstest --bosstest-hold) plays the whole fight; this probe samples
##                  frame time (CPU wall clock + GPU render time), draw calls, nodes, Engine.time_scale, boss state
##                  transitions and every engine error/warning; after the outro it follows the Router to the hub and
##                  checks the hat Mak wears there, the saved hat, the top_hat unlock, BOSS-1 and the spawn.
##   --qa=softlock  forced edge cases on the real arena (no bot): a game over during each phase transition, a game over
##                  while the P3 tea ring is collapsed, a game over and a fall during the updraft slow motion, a fall while
##                  the wolf is wedged (cork fallback), slow motion across a scene change, and a revisit after the win.
## Run: python tools/godot.py run res://tests/critique_boss/BossQaR1.tscn --seconds 300 -- --qa=fullrun --bosstest --bosstest-hold --profile=crit_boss_qa_full
##      python tools/godot.py run res://tests/critique_boss/BossQaR1.tscn --seconds 240 -- --qa=softlock --no-cine --profile=crit_boss_qa_soft
## Writes Docs/progress/critique/boss/r1_qa/<UTC>__qa_<mode>_results.json plus native captures.

const LOGGER := preload("res://tests/critique_boss/boss_qa_logger.gd")

var mode := "fullrun"
var out_dir := ""
var stamp := ""
var logger: Logger
var t := 0.0
var res := {}
var _last_us := 0
var _shots: Array = []


func _ready() -> void:
	if not has_meta("driver"):
		var d := Node.new()
		d.set_meta("driver", true)
		d.name = "BossQaDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	if dev != null:
		mode = String(dev.call("arg", "qa", "fullrun"))
	out_dir = ProjectSettings.globalize_path("res://").path_join("../Docs/progress/critique/boss/r1_qa").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var d2 := Time.get_datetime_dict_from_system(true)
	stamp = "%04d%02d%02dT%02d%02d%02dZ" % [d2.year, d2.month, d2.day, d2.hour, d2.minute, d2.second]
	logger = LOGGER.new()
	OS.add_logger(logger)
	res = {"mode": mode, "utc": stamp, "steps": []}
	print("[BossQA] mode=%s out=%s" % [mode, out_dir])
	match mode:
		"fullrun":
			_fullrun()
		"softlock":
			_softlock()
		"extra":
			_extra()
		_:
			_softlock()


func _process(delta: float) -> void:
	t += delta
	if logger != null:
		(logger as Object).set("t", t)
		var sc := get_tree().current_scene
		(logger as Object).set("scene_name", sc.name if sc != null else "")
	if mode == "fullrun":
		_sample(delta)


func _step(s: String) -> void:
	print("[BossQA] t=%.2f %s" % [t, s])
	(res["steps"] as Array).append({"t": snappedf(t, 0.01), "s": s})


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t0 := t
	while not bool(cond.call()):
		if t - t0 > timeout:
			return false
		await get_tree().process_frame
	return true


func _scene() -> Node:
	return get_tree().current_scene


func _world_id() -> String:
	var sc := _scene()
	if sc == null:
		return ""
	var w: Variant = sc.get("world_id")
	return String(w) if w != null else ""


func _arena() -> Node:
	return _scene() if _world_id() == "BOSS" else null


func _boss() -> Node:
	var a := _arena()
	return a.get("boss") if a != null else null


func _game() -> Node:
	return get_node_or_null("/root/Game")


func _router() -> Node:
	return get_node_or_null("/root/Router")


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _shot(caption: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var d := Time.get_datetime_dict_from_system(true)
	var s := "%04d%02d%02dT%02d%02d%02dZ" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
	var p := out_dir.path_join("%s__%s.png" % [s, caption])
	img.save_png(p)
	_shots.append(p)
	_step("capture " + p.get_file())


func _enter_boss() -> bool:
	var r := _router()
	r.call("enter_world", "BOSS", "")
	var ok := await _wait_until(func() -> bool: return _boss() != null and not bool(r.get("busy")), 30.0)
	await _wait(0.3)
	return ok


func _write() -> void:
	res["errors_and_warnings"] = logger.call("take") if logger != null else []
	var errs := 0
	var warns := 0
	var by_msg := {}
	for e in res["errors_and_warnings"]:
		var ty := String(e["type"])
		if ty == "warning":
			warns += 1
		else:
			errs += 1
		var k := ty + " | " + String(e.get("where", "")) + " | " + String(e["msg"]).left(140)
		by_msg[k] = int(by_msg.get(k, 0)) + 1
	res["error_count"] = errs
	res["warning_count"] = warns
	res["log_summary"] = by_msg
	res["captures"] = _shots
	var p := out_dir.path_join("%s__qa_%s_results.json" % [stamp, mode])
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  ", true))
	f.close()
	print("[BossQA] wrote ", p, " errors=", errs, " warnings=", warns)


func _finish() -> void:
	_write()
	await _wait(0.3)
	get_tree().quit()


# ================================================================== fullrun

var _samples: Array = []      # [t, wall_ms, cpu_process_ms, cpu_physics_ms, gpu_ms, phase_key]
var _per_sec: Array = []
var _sec_t := 0.0
var _state_log: Array = []
var _last_state := ""
var _ts_bad_t := 0.0
var _ts_bad_max := 0.0
var _ts_events: Array = []
var _min_health := 99
var _sampling := false


func _phase_key() -> String:
	var b := _boss()
	if b == null:
		return "hub" if _world_id() == "HUB" else "other"
	if bool(b.get("defeated")):
		return "defeat"
	var s := String(b.get("state"))
	if s == "intro":
		return "intro"
	return "P%d" % int(b.get("phase"))


func _sample(delta: float) -> void:
	if not _sampling:
		return
	var now := Time.get_ticks_usec()
	var wall := (now - _last_us) / 1000.0 if _last_us > 0 else delta * 1000.0
	_last_us = now
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var cpu_p := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var cpu_ph := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var key := _phase_key()
	_samples.append([snappedf(t, 0.001), snappedf(wall, 0.01), snappedf(cpu_p, 0.01), snappedf(cpu_ph, 0.01), snappedf(gpu, 0.01), key])
	_sec_t += delta
	if _sec_t >= 1.0:
		_sec_t = 0.0
		_per_sec.append({"t": snappedf(t, 0.1), "key": key, "fps": Engine.get_frames_per_second(),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			"static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
			"vram_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
			"time_scale": Engine.time_scale})
	var b := _boss()
	if b != null:
		var s := String(b.get("state"))
		if s != _last_state:
			_state_log.append({"t": snappedf(t, 0.01), "phase": int(b.get("phase")), "hits": int(b.get("hits")), "state": s})
			_last_state = s
	if not is_equal_approx(Engine.time_scale, 1.0):
		if _ts_bad_t == 0.0:
			_ts_events.append({"t": snappedf(t, 0.01), "scale": Engine.time_scale})
		_ts_bad_t += wall / 1000.0
		_ts_bad_max = maxf(_ts_bad_max, _ts_bad_t)
	else:
		_ts_bad_t = 0.0
	var g := _game()
	if g != null:
		_min_health = mini(_min_health, int(g.get("health")))


func _stats(arr: Array) -> Dictionary:
	if arr.is_empty():
		return {}
	var s := arr.duplicate()
	s.sort()
	var n := s.size()
	var sum := 0.0
	for v in s:
		sum += float(v)
	var over_20 := 0
	var over_33 := 0
	var over_50 := 0
	for v in s:
		if float(v) > 20.0:
			over_20 += 1
		if float(v) > 33.4:
			over_33 += 1
		if float(v) > 50.0:
			over_50 += 1
	return {"n": n, "mean": snappedf(sum / n, 0.01), "p50": s[int(n * 0.5)], "p95": s[mini(n - 1, int(n * 0.95))],
		"p99": s[mini(n - 1, int(n * 0.99))], "max": s[n - 1], "frames_over_20ms": over_20, "frames_over_33ms": over_33, "frames_over_50ms": over_50}


func _fullrun() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	res["display"] = {"window": str(DisplayServer.window_get_size()), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"adapter": RenderingServer.get_video_adapter_name(), "physics_ticks": Engine.physics_ticks_per_second}
	await _wait(0.5)
	var ok := await _enter_boss()
	_step("entered BOSS through the Router: %s" % str(ok))
	if not ok:
		await _finish()
		return
	_sampling = true
	var b := _boss()
	var shot_phase := {}
	# Follow the fight until the Router takes us to the hub (the bot holds; the outro calls go_to_hub("From_BOSS")).
	var t0 := t
	while _world_id() != "HUB" and t - t0 < 230.0:
		b = _boss()
		if b != null:
			var key := "P%d_%s" % [int(b.get("phase")), String(b.get("state"))]
			for want in ["P1_p1", "P2_charge", "P3_p3", "P3_wedged", "P3_popped"]:
				if key == want and not shot_phase.has(want):
					shot_phase[want] = true
					await _shot("qa_full_" + want.to_lower())
			res["boss_last"] = {"phase": int(b.get("phase")), "hits": int(b.get("hits")), "total": int(b.get("total")), "state": String(b.get("state")),
				"defeated": bool(b.get("defeated")), "fight_time": snappedf(float(b.get("fight_time")), 0.01),
				"slices_lost": int((b.get("stats") as Dictionary)["slices_lost"]), "falls": int((b.get("stats") as Dictionary)["falls"])}
			var g0 := _game()
			if g0 != null:
				res["before_hub"] = {"hat_saved": String(g0.call("get_hat")), "top_hat_unlocked": bool(g0.call("is_unlocked", "top_hat")),
					"has_BOSS_1": bool(g0.call("has_truffle", "BOSS-1"))}
			var pl := _player()
			if pl != null:
				res["player_hat_in_arena"] = String(pl.get("hat"))
		await get_tree().process_frame
	_step("left the fight loop: world=%s after %.1f s" % [_world_id(), t - t0])
	var hub_ok := _world_id() == "HUB"
	res["reached_hub"] = hub_ok
	if hub_ok:
		await _wait_until(func() -> bool: return not bool(_router().get("busy")), 15.0)
		await _wait(3.0)
		var g := _game()
		var pl := _player()
		var hub := {}
		hub["player_hat_var"] = String(pl.get("hat")) if pl != null else "?"
		hub["saved_hat"] = String(g.call("get_hat"))
		hub["top_hat_unlocked"] = bool(g.call("is_unlocked", "top_hat"))
		hub["has_BOSS_1"] = bool(g.call("has_truffle", "BOSS-1"))
		hub["available_hats"] = g.call("available_hats")
		hub["current_world"] = String(g.get("current_world"))
		hub["player_pos"] = str(pl.global_position) if pl != null else "?"
		var m: Node3D = null
		if _scene().has_method("find_marker"):
			m = _scene().call("find_marker", "From_BOSS") as Node3D
		hub["from_boss_marker"] = str(m.global_position) if m != null else "MISSING"
		if m != null and pl != null:
			hub["spawn_dist"] = snappedf(pl.global_position.distance_to(m.global_position), 0.01)
		# Visible UI panels (a dialog that opens on arrival would show here).
		var vis: Array = []
		var ui := get_node_or_null("/root/UI")
		if ui != null:
			for c in ui.find_children("*", "Control", true, false):
				var cc := c as Control
				if cc.is_visible_in_tree() and (cc.name.to_lower().contains("dialog") or cc.name.to_lower().contains("lock") or cc.name.to_lower().contains("panel") or cc.name.to_lower().contains("prompt")):
					vis.append(String(cc.get_path()))
		hub["visible_ui_panels"] = vis
		hub["time_scale"] = Engine.time_scale
		hub["paused"] = get_tree().paused
		# The save on disk.
		var sp := String(g.call("save_path"))
		var txt := FileAccess.get_file_as_string(sp)
		var js: Variant = JSON.parse_string(txt)
		if js is Dictionary:
			hub["save_file"] = {"path": ProjectSettings.globalize_path(sp), "hat": js.get("hat"), "unlocks": js.get("unlocks"), "truffles": (js.get("truffles", {}) as Dictionary).keys()}
		res["hub_after_outro"] = hub
		await _shot("qa_full_hub_after_outro")
	_sampling = false
	var wall: Dictionary = {}
	var gpu: Dictionary = {}
	var cpu: Dictionary = {}
	var keys := {}
	for s in _samples:
		keys[s[5]] = true
	for k in keys.keys():
		var w: Array = []
		var gg: Array = []
		var cc2: Array = []
		for s in _samples:
			if s[5] == k:
				w.append(s[1])
				gg.append(s[4])
				cc2.append(s[2])
		wall[k] = _stats(w)
		gpu[k] = _stats(gg)
		cpu[k] = _stats(cc2)
	var allw: Array = []
	var allg: Array = []
	for s in _samples:
		allw.append(s[1])
		allg.append(s[4])
	wall["ALL"] = _stats(allw)
	gpu["ALL"] = _stats(allg)
	res["frame_wall_ms"] = wall
	res["frame_gpu_ms"] = gpu
	res["cpu_process_ms"] = cpu
	res["per_second"] = _per_sec
	res["boss_state_log"] = _state_log
	res["time_scale_not_1_events"] = _ts_events
	res["time_scale_longest_not_1_s"] = snappedf(_ts_bad_max, 0.01)
	res["min_health"] = _min_health
	# Worst 15 frames with their time and phase.
	var worst := _samples.duplicate()
	worst.sort_custom(func(a: Array, c: Array) -> bool: return float(a[1]) > float(c[1]))
	res["worst_frames"] = worst.slice(0, 15)
	await _finish()


# ================================================================== softlock

func _sc(nm: String) -> Dictionary:
	var d := {"name": nm}
	(res.get_or_add("scenarios", []) as Array).append(d)
	_step("== scenario " + nm)
	return d


func _boss_snapshot() -> Dictionary:
	var b := _boss()
	if b == null:
		return {"boss": "missing", "world": _world_id()}
	var bar: Variant = b.get("bar")
	var rem: Variant = bar.get("remaining") if bar != null and "remaining" in bar else null
	return {"phase": int(b.get("phase")), "hits": int(b.get("hits")), "total": int(b.get("total")), "state": String(b.get("state")),
		"fighting": bool(b.get("fighting")), "defeated": bool(b.get("defeated")), "bar_remaining": rem, "time_scale": Engine.time_scale}


func _game_over() -> void:
	var g := _game()
	g.call("damage", int(g.get("health")))


func _goto_phase(p: int) -> void:
	var b := _boss()
	b.set("total", (p - 1) * 2)
	b.call("_enter_phase", p)
	b.get("bar").call("set_remaining", 6 - (p - 1) * 2)


func _softlock() -> void:
	await _wait(0.5)
	await _s_p1_transition()
	await _s_p2_transition()
	await _s_p3_collapsed_ring()
	await _s_p3_updraft()
	await _s_wedged_fall()
	await _s_slowmo_scene_change()
	await _s_revisit()
	await _finish()


## A game over during the P1 -> P2 transition (both P1 hits landed).
func _s_p1_transition() -> void:
	var d := _sc("game_over_during_p1_transition")
	await _enter_boss()
	await _wait(1.0)
	var b := _boss()
	b.set("hits", 1)
	b.set("total", 1)
	b.call("_register_hit", "pant slam")
	var ok := await _wait_until(func() -> bool: return String(_boss().get("state")) == "p1_trans", 5.0)
	d["reached_p1_trans"] = ok
	d["before"] = _boss_snapshot()
	_game_over()
	await _wait(5.0)
	d["after_5s"] = _boss_snapshot()
	d["verdict"] = "BUG: completed phase 1 was reset" if int(d["after_5s"]["phase"]) == 1 else "ok"
	_step(str(d))


## A game over while the wolf reels from the second P2 hit (p2_hurt with hits == 2).
func _s_p2_transition() -> void:
	var d := _sc("game_over_during_p2_hurt_after_hit_2")
	await _enter_boss()
	_goto_phase(2)
	await _wait(1.0)
	var b := _boss()
	b.set("hits", 1)
	b.set("total", 3)
	b.set("stuck_chimney", _arena().get("chimneys")["C2"])
	b.call("set_state", "stuck")
	b.call("_register_hit", "tail slam")
	d["before"] = _boss_snapshot()
	_game_over()
	await _wait(5.0)
	d["after_5s"] = _boss_snapshot()
	var smashed := []
	for id in (_arena().get("chimneys") as Dictionary).keys():
		if bool(_arena().get("chimneys")[id].get("smashed")):
			smashed.append(id)
	d["smashed_after"] = smashed
	d["verdict"] = "BUG: completed phase 2 was reset" if int(d["after_5s"]["phase"]) == 2 else "ok"
	_step(str(d))


## A game over while the P3 tea ring lies collapsed (p3_dizzy after hit 1): are the pieces restored?
func _s_p3_collapsed_ring() -> void:
	var d := _sc("game_over_while_p3_ring_collapsed")
	await _enter_boss()
	_goto_phase(3)
	await _wait(2.5)
	var b := _boss()
	b.call("_register_hit", "head slam")
	await _wait(0.9)
	d["before"] = _boss_snapshot()
	_game_over()
	await _wait(4.0)
	d["after_4s"] = _boss_snapshot()
	var pieces: Array = b.get("ring_pieces")
	var low := 0
	var mon := 0
	var info: Array = []
	for a in pieces:
		var ar := a as Area3D
		if ar.position.y < 0.6:
			low += 1
		if ar.monitorable:
			mon += 1
		info.append({"y": snappedf(ar.position.y, 0.01), "r": snappedf(Vector2(ar.position.x, ar.position.z).length(), 0.01), "monitorable": ar.monitorable})
	d["ring_pieces_on_floor"] = low
	d["ring_pieces_monitorable"] = mon
	d["ring_on"] = b.get("ring_on")
	d["pieces"] = info
	await _shot("qa_soft_p3_reset_ring_on_floor")
	# Does a floor piece hurt a grounded Mak? Park him on the circle the floor pieces sweep and watch the cake.
	var g := _game()
	var pl := _player()
	var h0 := int(g.get("health"))
	var hits_taken := 0
	if low > 0 and pl != null:
		var a0 := pieces[0] as Area3D
		var r0 := Vector2(a0.position.x, a0.position.z).length()
		var ang := deg_to_rad(250.0)
		pl.call("respawn", Transform3D(Basis(), Vector3(sin(ang) * r0, 0.05, -cos(ang) * r0)))
		await _wait(5.0)
		hits_taken = h0 - int(g.get("health"))
	d["standing_on_floor_ring_health_lost_in_5s"] = hits_taken
	d["verdict"] = ("BUG: collapsed pieces stay on the floor and are live hazards after the reset" if low > 0 and mon > 0 else ("BUG: pieces stay on the floor" if low > 0 else "ok"))
	_step(str(d))


## A game over, then a fall, during the Backfire Updraft slow motion + hold camera.
func _s_p3_updraft() -> void:
	for variant in ["game_over", "fall_out"]:
		var d := _sc("updraft_apex_" + variant)
		await _enter_boss()
		_goto_phase(3)
		await _wait(2.0)
		var b := _boss()
		var a := _arena()
		var pl := _player()
		pl.call("respawn", Transform3D(Basis(), Vector3(0.5, 9.0, 0.5)))
		b.set("hits", 1)
		b.set("total", 5)
		b.set("hit2_armed", true)
		b.call("set_state", "p3_tell")
		b.set("updraft", "apex")
		a.get("director").call("slowmo", 0.8, 0.5)
		a.get("director").call("hold", "Cine_Updraft", Vector3(8.0, 15.0, 12.0), Vector3(-1.5, 9.0, -8.0), 60.0, 0.3)
		await get_tree().process_frame
		d["during"] = _boss_snapshot()
		d["during_hold_id"] = String(a.get("director").get("hold_cam_id"))
		if variant == "game_over":
			_game_over()
		else:
			pl.call("respawn", Transform3D(Basis(), Vector3(25.0, -20.0, 0.0)))
		await _wait(4.0)
		d["after_4s"] = _boss_snapshot()
		d["after_hold_id"] = String(a.get("director").get("hold_cam_id"))
		var cam := get_viewport().get_camera_3d()
		d["current_camera"] = String(cam.get_path()) if cam != null else "none"
		var stuck := not is_equal_approx(Engine.time_scale, 1.0) or String(d["after_hold_id"]) != ""
		d["verdict"] = "BUG: slow motion or hold camera stranded" if stuck else "ok"
		_step(str(d))


## Mak falls off while the wolf is wedged in the cork chimney: the fallback must still pop him and spawn BOSS-1.
func _s_wedged_fall() -> void:
	var d := _sc("fall_while_wedged")
	await _enter_boss()
	_goto_phase(3)
	await _wait(2.0)
	var b := _boss()
	b.set("hits", 1)
	b.set("total", 5)
	b.call("_register_hit", "head slam")
	var ok := await _wait_until(func() -> bool: return String(_boss().get("state")) == "wedged", 8.0)
	d["reached_wedged"] = ok
	_player().call("respawn", Transform3D(Basis(), Vector3(25.0, -20.0, 0.0)))
	var popped := await _wait_until(func() -> bool: return bool(_boss().get("popped")), 20.0)
	d["popped_within_20s"] = popped
	await _wait(2.5)
	d["truffle_spawned"] = _arena().get_node_or_null("GreatTruffle") != null
	d["after"] = _boss_snapshot()
	d["verdict"] = "ok" if popped and d["truffle_spawned"] else "BUG: defeat softlock"
	_step(str(d))


## Slow motion running when the scene changes (pause menu -> leave): does Engine.time_scale come back?
func _s_slowmo_scene_change() -> void:
	var d := _sc("slowmo_then_scene_change")
	await _enter_boss()
	_arena().get("director").call("slowmo", 0.8, 0.5)
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
	await _wait(3.0)
	d["time_scale_after"] = Engine.time_scale
	d["verdict"] = "ok" if is_equal_approx(Engine.time_scale, 1.0) else "BUG: time_scale stranded at %.2f" % Engine.time_scale
	Engine.time_scale = 1.0
	_step(str(d))


## Re-entering after the win: BOSS-1 owned, top_hat unlocked.
func _s_revisit() -> void:
	var d := _sc("revisit_after_win")
	var g := _game()
	g.call("collect_truffle", "BOSS-1")
	g.call("unlock", "top_hat")
	g.call("unlock", "boss_intro_seen")
	await _enter_boss()
	await _wait(3.0)
	d["after_3s"] = _boss_snapshot()
	var tr := _arena().get_node_or_null("GreatTruffle")
	d["great_truffle_present"] = tr != null
	d["note"] = "fight restarts from P1 on every revisit" if bool(d["after_3s"]["fighting"]) else "no fight on revisit"
	_step(str(d))


# ================================================================== extra (exit with a full save, ring evidence)

func _extra() -> void:
	await _wait(0.5)
	await _s_ring_evidence()
	await _s_exit_with_12()
	await _finish()


## The collapsed P3 ring after a game over, seen from a story camera so the pieces on the floor are in frame.
func _s_ring_evidence() -> void:
	var d := _sc("ring_floor_evidence")
	await _enter_boss()
	_goto_phase(3)
	await _wait(2.5)
	var b := _boss()
	b.call("_register_hit", "head slam")
	await _wait(0.9)
	await _shot("qa_extra_before_reset_ring_collapsed_dizzy")
	_game_over()
	await _wait(4.0)
	var pl := _player()
	pl.call("respawn", Transform3D(Basis(), Vector3(0.0, 0.05, 8.5)))
	await _wait(1.5)
	await _shot("qa_extra_after_reset_ring_still_on_floor")
	var pieces: Array = b.get("ring_pieces")
	var low := 0
	for a in pieces:
		if (a as Area3D).position.y < 0.6:
			low += 1
	d["pieces_on_floor_after_reset"] = low
	d["state"] = _boss_snapshot()
	_step(str(d))


## Leaving the boss with a real end-game save (12 world truffles + BOSS-1): where does From_BOSS put Mak?
func _s_exit_with_12() -> void:
	var d := _sc("exit_to_hub_with_12_truffles")
	var g := _game()
	for w in ["W1", "W2"]:
		for i in range(1, 7):
			g.call("collect_truffle", "%s-%d" % [w, i])
	g.call("collect_truffle", "BOSS-1")
	g.call("unlock", "top_hat")
	d["truffles"] = int(g.call("truffle_count"))
	_router().call("go_to_hub", "From_BOSS")
	await _wait_until(func() -> bool: return _world_id() == "HUB" and not bool(_router().get("busy")), 30.0)
	var seen := {}
	var t0 := t
	while t - t0 < 8.0:
		seen[_world_id()] = true
		await get_tree().process_frame
	d["worlds_seen_in_8s"] = seen.keys()
	d["world_now"] = _world_id()
	var pl := _player()
	d["player_pos"] = str(pl.global_position) if pl != null else "?"
	var vis: Array = []
	var ui := get_node_or_null("/root/UI")
	if ui != null:
		for c in ui.find_children("*", "Control", true, false):
			var cc := c as Control
			if cc.is_visible_in_tree() and cc.name.to_lower().contains("dialog"):
				vis.append(String(cc.get_path()))
	d["visible_dialogs"] = vis
	var cam := get_viewport().get_camera_3d()
	d["camera"] = str(cam.global_position) if cam != null else "none"
	await _shot("qa_extra_hub_arrival_with_12_truffles")
	d["verdict"] = "BUG: re-entered the boss on arrival" if (seen.has("BOSS") and _world_id() != "HUB") or _world_id() == "BOSS" else "no loop"
	_step(str(d))

extends Node3D
## Critique JUICE r1, PERFORMANCE lens: isolated costs in an empty stage (no world, so contention from the world
## itself is out of the numbers). Measures the cold Juice.prewarm() cost, the per-event CPU cost split into the
## full call, VFX-only (silent), SFX-only (no_vfx), the `fired` listeners alone, Audio.play_sfx alone, a pooled
## FxEffect.play() alone, and reproduces the freed-owner loop cases with the error output kept short.
##   python tools/godot.py run res://tests/critique_juice/PerfMicroR1.tscn --seconds 300 -- --profile=crit_juice_perf --out=<abs dir>

var out := ""
var results := {}
var _cam: Camera3D


func _log(msg: String) -> void:
	print("[CritJuiceMicro] ", msg)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _mean(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var t := 0.0
	for v in arr:
		t += float(v)
	return t / arr.size()


func _median(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := arr.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if out == "":
		out = OS.get_user_data_dir().path_join("crit_juice_perf")
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Bounded so --quit-after (frames) does not end the run early; per-call costs are wall clock around the call.
	Engine.max_fps = 240
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.position = Vector3(0, 3, 9)
	_cam.look_at(Vector3(0, 0.5, 0))
	_cam.current = true
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_run.call_deferred()


func _run() -> void:
	# Juice schedules its own prewarm 0.25 s after the scene appears. Measure frames across it, then time a manual
	# prewarm call (pool already warm, so that one shows the steady-state cost of re-prewarming on every load).
	var dts: Array = []
	var last := Time.get_ticks_usec()
	var pw_frame := -1
	for i in 120:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		dts.append(snappedf(float(now - last) / 1000.0, 0.01))
		last = now
		if pw_frame < 0 and Juice.stats.has("prewarmed"):
			pw_frame = i
	results["auto_prewarm"] = {"frame": pw_frame, "frame_ms_around": dts.slice(maxi(pw_frame - 2, 0), pw_frame + 5),
		"median_ms": _median(dts.slice(1)), "prewarmed": Juice.stats.get("prewarmed", -1)}
	_log("auto prewarm frame=%d around=%s median=%.2f" % [pw_frame, str(results.auto_prewarm.frame_ms_around), _median(dts.slice(1))])
	await _frames(120)
	var t := Time.get_ticks_usec()
	Juice.prewarm()
	results["manual_prewarm_warm_pool_us"] = Time.get_ticks_usec() - t
	await _frames(120)
	# Per-event split.
	var right := Vector3.RIGHT
	var list := [
		["player_footstep", Vector3.ZERO, {"surface": "grass", "speed": 7.0}],
		["player_punch", Vector3(0, 0.8, 0), {"direction": right, "combo": 1}],
		["player_land", Vector3.ZERO, {"impact": 12.0}],
		["player_jump_3", Vector3.ZERO, {"node": _cam}],
		["player_ham_slam", Vector3.ZERO, {"impact": 15.0}],
		["enemy_defeat", Vector3(0, 0.6, 0), {"family": "woolly_wolf"}],
		["object_truffle_collect", Vector3(0, 1, 0), {}],
		["boss_defeat", Vector3(0, 1, 0), {}],
		["ui_select", Vector3.INF, {}],
	]
	var m := {}
	for it in list:
		var name := String(it[0])
		var row := {}
		for mode in ["full", "silent", "no_vfx", "fired_only"]:
			var costs: Array = []
			for k in 16:
				var params: Dictionary = (it[2] as Dictionary).duplicate()
				if mode == "silent":
					params["silent"] = true
				elif mode == "no_vfx":
					params["no_vfx"] = true
				var p: Vector3 = it[1]
				var t0 := Time.get_ticks_usec()
				if mode == "fired_only":
					Juice.fired.emit(name, p, params)
				else:
					Juice.event(name, p, params)
				costs.append(Time.get_ticks_usec() - t0)
				Juice.end_hitstop()
				await _frames(3 if name != "boss_defeat" else 12)
			row[mode] = {"median_us": _median(costs), "mean_us": snappedf(_mean(costs), 1), "max_us": costs.max()}
		m[name] = row
		_log("%s full=%dus silent=%dus no_vfx=%dus fired_only=%dus" % [name, row.full.median_us, row.silent.median_us,
			row.no_vfx.median_us, row.fired_only.median_us])
	results["event_split"] = m
	# Warm pool: wait until every one-shot has returned to the pool before the next call (no pool misses).
	var warm := {}
	for it in list:
		var name := String(it[0])
		var row := {}
		for mode in ["full", "silent", "no_vfx"]:
			var costs: Array = []
			for k in 6:
				var t_end := Time.get_ticks_msec() + 3500
				while int(Juice.get("_active")) > 0 and Time.get_ticks_msec() < t_end:
					await get_tree().process_frame
				var params: Dictionary = (it[2] as Dictionary).duplicate()
				if mode == "silent":
					params["silent"] = true
				elif mode == "no_vfx":
					params["no_vfx"] = true
				var r0 := int(Juice.stats["reused"])
				var t0 := Time.get_ticks_usec()
				Juice.event(name, it[1], params)
				costs.append(Time.get_ticks_usec() - t0)
				Juice.end_hitstop()
				row["reused_last"] = int(Juice.stats["reused"]) - r0
			row[mode] = {"median_us": _median(costs), "max_us": costs.max()}
		warm[name] = row
		_log("warm %s full=%dus silent=%dus no_vfx=%dus" % [name, row.full.median_us, row.silent.median_us, row.no_vfx.median_us])
	results["event_warm_pool"] = warm
	# Direct engine-side costs.
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		var ac: Array = []
		for k in 30:
			var t1 := Time.get_ticks_usec()
			audio.call("play_sfx", "ui_select", Vector3.INF, 0.0, -30.0)
			ac.append(Time.get_ticks_usec() - t1)
			await _frames(2)
		var ac3: Array = []
		for k in 30:
			var t1 := Time.get_ticks_usec()
			audio.call("play_sfx", "ui_select", Vector3(0, 0, 0), 0.0, -30.0)
			ac3.append(Time.get_ticks_usec() - t1)
			await _frames(2)
		results["audio_play_sfx_us"] = {"2d_median": _median(ac), "3d_median": _median(ac3), "2d_max": ac.max(), "3d_max": ac3.max()}
		_log("Audio.play_sfx 2d=%dus 3d=%dus" % [_median(ac), _median(ac3)])
	# Pooled FxEffect.play() and fresh instantiation (what attach items do every time).
	var fxc: Array = []
	var fx := FxEffect.new()
	fx.preset = "dust_puff"
	fx.autoplay = false
	fx.free_when_done = false
	add_child(fx)
	await _frames(2)
	for k in 30:
		var t2 := Time.get_ticks_usec()
		fx.fx_scale = 1.0 + 0.01 * k
		fx.play()
		fxc.append(Time.get_ticks_usec() - t2)
		await _frames(3)
	var inst: Array = []
	for k in 12:
		var t3 := Time.get_ticks_usec()
		var f2 := FxEffect.new()
		f2.preset = "jump_trail" if FxPresets.get_preset("jump_trail").size() > 0 else "dust_puff"
		f2.autoplay = false
		add_child(f2)
		f2.play()
		inst.append(Time.get_ticks_usec() - t3)
		await _frames(2)
		f2.queue_free()
	results["fx_play_pooled_us"] = {"median": _median(fxc), "max": fxc.max()}
	results["fx_instantiate_and_play_us"] = {"median": _median(inst), "max": inst.max()}
	_log("FxEffect.play pooled=%dus  new+play=%dus" % [_median(fxc), _median(inst)])
	# Shake and handles.
	var sh: Array = []
	for k in 50:
		var t4 := Time.get_ticks_usec()
		Juice.shake(0.1, 0.1, Vector3.ZERO)
		sh.append(Time.get_ticks_usec() - t4)
	results["shake_us_median"] = _median(sh)
	# Freed owners with live loops: count error-producing frames.
	_log("LOOPS-BEGIN freed owners (expect errors below if the bug exists)")
	for i in 3:
		var dummy := Node3D.new()
		add_child(dummy)
		Juice.event("enemy_stunned", Vector3.INF, {"node": dummy})
		Juice.event("player_slide_start", Vector3.INF, {"node": dummy})
		await _frames(2)
		dummy.queue_free()
		await _frames(1)
	await _frames(5)
	results["loops_after_free"] = (Juice.get("_loops") as Dictionary).size()
	_log("LOOPS juice _loops=%d; calling Juice.stop_loops() (runs on every scene change)" % results.loops_after_free)
	Juice.stop_loops()
	results["loops_after_stop_loops"] = (Juice.get("_loops") as Dictionary).size()
	_log("LOOPS after stop_loops=%d" % results.loops_after_stop_loops)
	var sfx := Juice.get_node_or_null("JuiceSfx")
	if sfx != null:
		results["juicesfx_loops_after_free"] = (sfx.get("_loops") as Dictionary).size()
	await _frames(5)
	_log("LOOPS-END")
	var f := FileAccess.open(out.path_join("micro_perf.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	_log("done " + JSON.stringify(results))
	get_tree().quit()

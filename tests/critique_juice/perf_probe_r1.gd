extends Node
## Critique JUICE r1, PERFORMANCE lens. Read only: loads a real world, drops the ambient effects the way
## Docs/JUICE.md tells builders to, fires Juice events in realistic and pathological patterns and measures
## real frame time (vsync off), viewport CPU/GPU render time, draw calls, primitives, node and memory counters,
## the Juice pool size and private tables (loops, cooldowns) across a soak and repeated scene loads.
##   python tools/godot.py run res://tests/critique_juice/PerfProbeR1.tscn --seconds 600 -- --profile=crit_juice_perf
##       --world=W1 --out=<abs dir> [--phases=load,idle,ambient,micro,combat,stress,spike,overdraw,soak,loops,reload]
## Writes <out>/<world>_perf.json and PNG frames <out>/<world>_<label>.png. Quits when done.

const WORLDS := {
	"HUB": "res://scenes/hub/Hub.tscn",
	"W1": "res://scenes/worlds/w1/W1.tscn",
	"W2": "res://scenes/worlds/w2/W2.tscn",
	"W3": "res://scenes/worlds/w3/W3.tscn",
	"BOSS": "res://scenes/boss/WolfRooftop.tscn",
}
## [scene, local offset (right, up, forward) from Mak, area half extents or ZERO]. Follows Docs/JUICE.md per-world guidance.
const AMBIENT := {
	"HUB": [["ambient/Fireflies", Vector3(0, 1.0, 5), Vector3(6, 1.5, 5)], ["ambient/DustMotes", Vector3(1.5, 2.0, 4), Vector3(3, 2.5, 3)],
		["ambient/DustMotes", Vector3(-3, 2.0, 7), Vector3(3, 2.5, 3)], ["ambient/FireEmbers", Vector3(2, 0.5, 6), Vector3.ZERO]],
	"W1": [["ambient/Pollen", Vector3(0, 1.4, 6), Vector3(10, 2, 8)], ["ambient/Pollen", Vector3(-12, 1.4, 14), Vector3(10, 2, 8)],
		["Butterflies", Vector3(-2, 1.0, 5), Vector3.ZERO], ["FallingLeaves", Vector3(3, 3.0, 8), Vector3.ZERO],
		["ChimneySmoke", Vector3(6, 4.0, 14), Vector3.ZERO], ["ChimneySmoke", Vector3(-8, 4.0, 18), Vector3.ZERO]],
	"W2": [["ambient/CloudWisps", Vector3(0, 0.5, 9), Vector3(12, 2.5, 8)], ["ambient/CloudWisps", Vector3(8, -2.0, 18), Vector3(12, 2.5, 8)],
		["ambient/Petals", Vector3(0, 3.0, 5), Vector3.ZERO]],
	"W3": [["ambient/CandySparkles", Vector3(0, 1.2, 5), Vector3(8, 2, 6)], ["ambient/CandySparkles", Vector3(-9, 1.2, 12), Vector3(8, 2, 6)],
		["ambient/CocoaSteam", Vector3(3, 0.2, 6), Vector3.ZERO], ["ambient/CocoaSteam", Vector3(3, 0.2, 14), Vector3.ZERO],
		["ChimneySmoke", Vector3(-5, 4.0, 15), Vector3.ZERO]],
	"BOSS": [],
}
const FAMILY := {"HUB": "woolly_wolf", "W1": "woolly_wolf", "W2": "peapod_popper", "W3": "gingerbread_grenadier", "BOSS": "crow_bandit"}
const ALL_PHASES := "load,idle,ambient,post,micro,bursts,combat,stress,spike,overdraw,soak,reload"

var runner := false
var world := "W1"
var out := ""
var phases := ALL_PHASES
var results := {}
var _vp: RID
var _player: Node3D
var _cam: Camera3D
var _base := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _right := Vector3.RIGHT
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if runner:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run.call_deferred()
		return
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var r := Node.new()
	r.set_script(load("res://tests/critique_juice/perf_probe_r1.gd"))
	r.set("runner", true)
	r.set("world", String(args.get("world", "W1")))
	r.set("out", String(args.get("out", OS.get_user_data_dir().path_join("crit_juice_perf"))))
	r.set("phases", String(args.get("phases", ALL_PHASES)))
	r.name = "CritJuicePerfR1"
	get_tree().root.add_child.call_deferred(r)


# ------------------------------------------------------------------ helpers

func _log(msg: String) -> void:
	print("[CritJuicePerf] ", msg)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [out, world, label]
	img.save_png(path)
	_log("saved " + path)


func _w(local: Vector3) -> Vector3:
	return _base + _right * local.x + Vector3.UP * local.y + _fwd * local.z


func _pctl(arr: Array, p: float) -> float:
	if arr.is_empty():
		return 0.0
	var s := arr.duplicate()
	s.sort()
	return float(s[clampi(int(round(p * (s.size() - 1))), 0, s.size() - 1)])


func _mean(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var t := 0.0
	for v in arr:
		t += float(v)
	return t / arr.size()


func _summ(arr: Array) -> Dictionary:
	var med := _pctl(arr, 0.5)
	var spikes := 0
	var over33 := 0
	var over16 := 0
	for v in arr:
		if float(v) > maxf(med * 2.0, 8.0):
			spikes += 1
		if float(v) > 33.3:
			over33 += 1
		if float(v) > 16.7:
			over16 += 1
	return {"n": arr.size(), "mean": snappedf(_mean(arr), 0.01), "p50": snappedf(med, 0.01), "p95": snappedf(_pctl(arr, 0.95), 0.01),
		"p99": snappedf(_pctl(arr, 0.99), 0.01), "max": snappedf(_pctl(arr, 1.0), 0.01), "spikes_2x_median": spikes,
		"over_16_7ms": over16, "over_33ms": over33}


func _pool_count() -> Dictionary:
	var a := 0
	var vis := 0
	var lights := 0
	var particles := 0
	for host_name in ["FxPool", "FxPoolAlways"]:
		var h := Juice.get_node_or_null(host_name)
		if h == null:
			continue
		for c in h.get_children():
			a += 1
			if (c as Node3D).visible:
				vis += 1
			for g in c.get_children():
				if g is OmniLight3D:
					lights += 1
				elif g is GPUParticles3D:
					particles += 1
	var pool: Dictionary = Juice.get("_pool")
	var idle := 0
	for k in pool:
		idle += (pool[k] as Array).size()
	return {"pool_nodes": a, "pool_visible": vis, "pool_lights": lights, "pool_gpu_particles": particles, "pool_keys": pool.size(),
		"pool_idle": idle, "active_counter": int(Juice.get("_active")), "loops": (Juice.get("_loops") as Dictionary).size(),
		"cooldowns": (Juice.get("_cooldowns") as Dictionary).size()}


func _counters() -> Dictionary:
	var d := {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mb": snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"juice_stats": Juice.stats.duplicate(),
	}
	d.merge(_pool_count())
	return d


## Samples `frames` frames; `tick` (optional) is called before each frame (fires events). Real dt in ms (vsync off).
func _sample(label: String, frames: int, tick: Callable = Callable()) -> Dictionary:
	var dts: Array = []
	var gpu: Array = []
	var cpu: Array = []
	var proc: Array = []
	var draws: Array = []
	var prims: Array = []
	var objs: Array = []
	var visible_fx: Array = []
	var worst_i := -1
	var worst := 0.0
	var st0: Dictionary = Juice.stats.duplicate()
	var last := Time.get_ticks_usec()
	for i in frames:
		if tick.is_valid():
			tick.call(i)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		dts.append(dt)
		if dt > worst:
			worst = dt
			worst_i = i
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu())
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		if i % 10 == 0:
			visible_fx.append(_pool_count()["pool_visible"])
	var st1: Dictionary = Juice.stats.duplicate()
	var dstats := {}
	for k in st1:
		dstats[k] = int(st1[k]) - int(st0.get(k, 0))
	var r := {"frame_ms": _summ(dts), "gpu_ms": _summ(gpu), "cpu_render_ms": _summ(cpu), "process_ms": _summ(proc),
		"draw_calls": {"mean": snappedf(_mean(draws), 0.1), "max": _pctl(draws, 1.0)},
		"primitives": {"mean": snappedf(_mean(prims), 1.0), "max": _pctl(prims, 1.0)},
		"objects": {"mean": snappedf(_mean(objs), 0.1), "max": _pctl(objs, 1.0)},
		"visible_pool_fx_max": _pctl(visible_fx, 1.0), "worst_frame_index": worst_i, "juice_stats_delta": dstats,
		"counters_after": _counters()}
	results[label] = r
	_log("%s frame p50=%.2f p95=%.2f p99=%.2f max=%.2f | gpu p50=%.2f p95=%.2f max=%.2f | draws mean=%.0f max=%.0f | dropped=%d vfx=%d" % [
		label, r.frame_ms.p50, r.frame_ms.p95, r.frame_ms.p99, r.frame_ms.max, r.gpu_ms.p50, r.gpu_ms.p95, r.gpu_ms.max,
		r.draw_calls.mean, r.draw_calls.max, int(dstats.get("dropped", 0)), int(dstats.get("vfx", 0))])
	return r


func _save() -> void:
	var f := FileAccess.open("%s/%s_perf.json" % [out, world], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(results, "  "))
		f.close()


func _fire(name: String, local: Vector3, params: Dictionary = {}) -> void:
	Juice.event(name, _w(local), params)


## A realistic fight: Mak running, punching and slamming through a squad; about 7 events a second plus footsteps.
func _combat_tick(i: int) -> void:
	var fam: String = FAMILY.get(world, "woolly_wolf")
	if i % 15 == 0:
		_fire("player_footstep", Vector3(0, 0, 0), {"surface": "grass", "speed": 7.0, "node": _player})
	if i % 8 != 0:
		return
	var x := _rng.randf_range(-2.5, 2.5)
	var z := _rng.randf_range(1.5, 5.0)
	match (i / 8) % 10:
		0: _fire("player_punch", Vector3(x, 0.8, z), {"direction": _right, "combo": 1, "node": _player})
		1: _fire("enemy_hurt", Vector3(x, 0.8, z), {"family": fam})
		2: _fire("player_kick", Vector3(x, 0.8, z), {"direction": _right, "node": _player})
		3: _fire("player_jump_1", Vector3(0, 0, 0), {"node": _player})
		4: _fire("player_land", Vector3(0, 0, 0), {"impact": 10.0})
		5: _fire("enemy_defeat", Vector3(x, 0.6, z), {"family": fam})
		6: _fire("object_acorn_collect", Vector3(x, 0.8, z), {})
		7: _fire("player_jump_3", Vector3(0, 0, 0), {"node": _player})
		8: _fire("player_ham_slam", Vector3(0, 0, 0), {"impact": 15.0})
		9: _fire("enemy_notice", Vector3(x, 1.4, z), {"family": fam})


const HEAVY := [
	["player_ham_slam", Vector3(0, 0, 1.0), {"impact": 18.0}],
	["object_truffle_collect", Vector3(0, 1.0, 2.5), {}],
	["boss_defeat", Vector3(0, 1.0, 5.0), {}],
	["enemy_defeat", Vector3(-1.5, 0.6, 3.0), {"family": "woolly_wolf"}],
	["enemy_defeat", Vector3(1.5, 0.6, 3.0), {"family": "crow_bandit"}],
	["enemy_defeat", Vector3(0.5, 0.6, 4.0), {"family": "gummy_brute"}],
	["enemy_defeat", Vector3(-0.5, 0.6, 4.5), {"family": "gingerbread_grenadier"}],
	["object_checkpoint", Vector3(2.0, 0, 3.0), {}],
	["object_crate_break", Vector3(-2.0, 0.4, 2.5), {}],
	["player_land", Vector3(0, 0, 0.5), {"impact": 18.0}],
	["object_bounce_pad", Vector3(-1.0, 0, 2.0), {"impact": 14.0}],
	["boss_chimney_smash", Vector3(2.5, 0, 6.0), {}],
]


func _spike_burst() -> void:
	for h in HEAVY:
		_fire(String(h[0]), h[1], h[2])


# ------------------------------------------------------------------ run

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	_rng.seed = 64
	get_window().size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	results["meta"] = {"world": world, "engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(),
		"driver": RenderingServer.get_video_adapter_api_version(), "viewport": str(get_viewport().get_visible_rect().size),
		"window": str(get_window().size), "utc": Time.get_datetime_string_from_system(true), "phases": phases,
		"cpu": OS.get_processor_name(), "threads": OS.get_processor_count()}
	results["boot_counters"] = _counters()
	var ph := phases.split(",")
	var path: String = WORLDS.get(world, WORLDS["W1"])
	# Phase load: every frame from the scene change to 6 s later, including Juice.prewarm() at +0.25 s.
	var t0 := Time.get_ticks_usec()
	get_tree().change_scene_to_file(path)
	var load_dts: Array = []
	var prewarm_frame := -1
	var last := Time.get_ticks_usec()
	var pw0 := int(Juice.stats.get("prewarmed", -1))
	for i in 420:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		load_dts.append(snappedf(float(now - last) / 1000.0, 0.01))
		last = now
		if prewarm_frame < 0 and Juice.stats.has("prewarmed") and int(Juice.stats["prewarmed"]) != pw0:
			prewarm_frame = i
	# Frames after the first one (which carries the scene load).
	var tail: Array = load_dts.slice(1)
	var pw_window: Array = load_dts.slice(maxi(prewarm_frame - 1, 0), prewarm_frame + 6) if prewarm_frame >= 0 else []
	results["load"] = {"first_frame_ms": load_dts[0], "after_first": _summ(tail), "prewarm_frame": prewarm_frame,
		"prewarm_window_ms": pw_window, "prewarmed_effects": Juice.stats.get("prewarmed", -1),
		"top10": _top(load_dts, 10), "wall_ms": snappedf(float(Time.get_ticks_usec() - t0) / 1000.0, 1), "counters": _counters()}
	_log("load first=%.1f prewarm_frame=%d window=%s top=%s" % [load_dts[0], prewarm_frame, str(pw_window), str(_top(load_dts, 6))])
	if world == "HUB" or world == "BOSS":
		await _frames(300)
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_cam = get_viewport().get_camera_3d()
	if _player == null or _cam == null:
		_log("FAIL no player or camera")
		results["error"] = "no player or camera"
		_save()
		get_tree().quit(1)
		return
	var f := -_cam.global_basis.z
	f.y = 0.0
	_fwd = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	_right = _fwd.cross(Vector3.UP).normalized()
	_base = _player.global_position
	await _frames(60)
	if "idle" in ph:
		await _shot("idle")
		await _sample("idle_world", 360)
	if "ambient" in ph:
		var scene := get_tree().current_scene
		for a in AMBIENT.get(world, []):
			var ps := load("res://scenes/fx/%s.tscn" % a[0]) as PackedScene
			if ps == null:
				continue
			var fx := ps.instantiate() as Node3D
			if a[2] != Vector3.ZERO:
				fx.set("area", a[2])
			scene.add_child(fx)
			fx.global_position = _w(a[1])
		await _frames(120)
		await _shot("ambient")
		await _sample("idle_ambient", 360)
	if "post" in ph and world != "BOSS":
		# FxDresser as JUICE.md tells builders (ambient volumes plus the storybook ink-line post), measured separately.
		FxDresser.dress(get_tree().current_scene as Node3D, {"terrain": null, "post": true, "butterflies": [_w(Vector3(-1.5, 1.0, 5.0))],
			"leaves": [_w(Vector3(2.0, 3.0, 6.0))]})
		await _frames(120)
		await _shot("ambient_dresser_post")
		await _sample("idle_ambient_dresser_post", 360)
		await _sample("idle_ambient_dresser_post_b", 360)
	if "micro" in ph:
		await _micro()
	if "showcase" in ph:
		# Movie Maker reel for the making-of: a realistic slam on a group, then the 12-event burst, each shown
		# normally and in Godot's overdraw view.
		for pass_i in 4:
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_OVERDRAW if pass_i % 2 == 1 else Viewport.DEBUG_DRAW_DISABLED
			await _frames(20)
			var lst: Array = SLAM_GROUP if pass_i < 2 else HEAVY
			for h in lst:
				_fire(String(h[0]), h[1], h[2])
			await _frames(100)
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
		_log("showcase done")
		get_tree().quit()
		return
	if "bursts" in ph:
		await _bursts()
	if "combat" in ph:
		await _frames(60)
		await _sample("combat_mix", 900, _combat_tick)
		await _frames(150)
	if "stress" in ph:
		# Pathological: 3 heavy-ish events every frame for 5 s at 60 fps equivalent; hitstop cancelled so lifetimes are real.
		var stress := func(i: int) -> void:
			var fam: String = FAMILY.get(world, "woolly_wolf")
			_fire("enemy_defeat", Vector3(_rng.randf_range(-3, 3), 0.6, _rng.randf_range(2, 6)), {"family": fam})
			_fire("player_land", Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(1, 4)), {"impact": 14.0})
			_fire("object_acorn_collect", Vector3(_rng.randf_range(-2, 2), 0.8, _rng.randf_range(1, 4)), {})
			Juice.end_hitstop()
		await _sample("stress_3_per_frame", 300, stress)
		await _frames(240)
	if "spike" in ph:
		var spike := func(i: int) -> void:
			if i == 10:
				_spike_burst()
		await _sample("spike_12_heavy", 240, spike)
		results["spike_12_heavy"]["frames_after_burst"] = results["spike_12_heavy"]["worst_frame_index"] - 10
		await _frames(240)
	if "overdraw" in ph:
		await _overdraw()
	if "soak" in ph:
		await _soak()
	if "loops" in ph:
		await _loops_leak()
	_save()
	if "reload" in ph:
		await _reload_cycle(path)
	results["end_counters"] = _counters()
	if "idle" in ph:
		await _sample("idle_end_noise_check", 360)
	_save()
	_log("done " + world)
	get_tree().quit()


func _top(arr: Array, n: int) -> Array:
	var idx: Array = []
	for i in arr.size():
		idx.append([float(arr[i]), i])
	idx.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return idx.slice(0, n)


## Per-event CPU cost of Juice.event() (usec, wall clock around the call), first call and mean of 12 later calls.
func _micro() -> void:
	var fam: String = FAMILY.get(world, "woolly_wolf")
	var list := [
		["player_footstep", Vector3.ZERO, {"surface": "grass", "speed": 7.0}],
		["player_punch", Vector3(0, 0.8, 2), {"direction": _right, "combo": 1, "node": _player}],
		["player_land", Vector3.ZERO, {"impact": 12.0}],
		["player_jump_1", Vector3.ZERO, {"node": _player}],
		["player_jump_3", Vector3.ZERO, {"node": _player}],
		["player_backflip", Vector3.ZERO, {"node": _player}],
		["player_ham_slam", Vector3.ZERO, {"impact": 15.0}],
		["enemy_hurt", Vector3(0, 0.8, 3), {"family": fam}],
		["enemy_defeat", Vector3(0, 0.6, 3), {"family": fam}],
		["object_truffle_collect", Vector3(0, 1, 2.5), {}],
		["object_acorn_collect", Vector3(0, 0.8, 2), {}],
		["boss_defeat", Vector3(0, 1, 5), {}],
		["ui_select", Vector3.INF, {}],
	]
	var m := {}
	for it in list:
		var name := String(it[0])
		var costs: Array = []
		for k in 13:
			var p: Vector3 = it[1]
			var t := Time.get_ticks_usec()
			if p == Vector3.INF:
				Juice.event(name)
			else:
				_fire(name, p, it[2])
			costs.append(Time.get_ticks_usec() - t)
			Juice.end_hitstop()
			await _frames(4 if name != "boss_defeat" else 20)
		m[name] = {"first_us": costs[0], "mean_us": snappedf(_mean(costs.slice(1)), 1), "max_us": _pctl(costs.slice(1), 1.0)}
		_log("micro %s first=%dus mean=%.0fus" % [name, costs[0], _mean(costs.slice(1))])
	results["micro_event_cpu"] = m
	# _resolve deep copy cost alone (called by every event and every handles()).
	var t2 := Time.get_ticks_usec()
	for _k in 1000:
		Juice.handles("enemy_defeat", "vfx", {"family": fam})
	results["micro_handles_us"] = snappedf(float(Time.get_ticks_usec() - t2) / 1000.0, 0.1)
	await _frames(200)


func _overdraw() -> void:
	var vp := get_viewport()
	# Normal frame mid-burst, then the same burst in Godot's overdraw debug view.
	_spike_burst()
	Juice.end_hitstop()
	await _frames(8)
	await _shot("burst_normal")
	await _frames(300)
	vp.debug_draw = Viewport.DEBUG_DRAW_OVERDRAW
	await _frames(30)
	await _shot("overdraw_idle")
	var base := await _sample("overdraw_idle_gpu", 60)
	_spike_burst()
	Juice.end_hitstop()
	await _frames(8)
	await _shot("overdraw_burst")
	await _frames(300)
	# Close-up: the same burst 1.2 m in front of the camera (Mak's camera in a corner).
	var cam_fwd := -_cam.global_basis.z
	var near := _cam.global_position + cam_fwd * 1.6 + Vector3.DOWN * 0.4
	var saved := _base
	_base = near - _fwd * 1.0
	_spike_burst()
	Juice.end_hitstop()
	await _frames(8)
	await _shot("overdraw_burst_closeup")
	vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	await _frames(300)
	var cu := func(i: int) -> void:
		if i == 5:
			_spike_burst()
			Juice.end_hitstop()
	await _sample("closeup_burst_gpu", 120, cu)
	await _frames(8)
	_base = saved
	await _frames(300)
	var fa := func(i: int) -> void:
		if i == 5:
			_spike_burst()
			Juice.end_hitstop()
	await _sample("normal_burst_gpu", 120, fa)
	await _frames(240)


## 60 s of the combat mix; counters every 600 frames to show whether pools, nodes and memory plateau.
func _soak() -> void:
	var rows: Array = []
	rows.append(_counters())
	var frame := 0
	for block in 6:
		for i in 600:
			_combat_tick(frame)
			frame += 1
			await get_tree().process_frame
		var c := _counters()
		c["frame"] = frame
		rows.append(c)
		_log("soak %d nodes=%d objects=%d orphans=%d static=%.1fMB video=%.1fMB pool=%d keys=%d cooldowns=%d" % [frame, c.nodes,
			c.objects, c.orphans, c.static_mb, c.video_mb, c.pool_nodes, c.pool_keys, c.cooldowns])
	await _frames(300)
	var c2 := _counters()
	c2["frame"] = frame + 300
	c2["settled"] = true
	rows.append(c2)
	results["soak"] = rows


## Attached loops on nodes that are freed without the matching *_end event (an enemy defeated while dizzy,
## Mak respawning mid-slide) and footsteps from many nodes (cooldown keys).
func _loops_leak() -> void:
	var before := _pool_count()
	var scene := get_tree().current_scene
	for i in 40:
		var dummy := Node3D.new()
		scene.add_child(dummy)
		dummy.global_position = _w(Vector3(_rng.randf_range(-2, 2), 0.5, 3))
		Juice.event("enemy_stunned", Vector3.INF, {"node": dummy})
		Juice.event("player_slide_start", Vector3.INF, {"node": dummy})
		Juice.event("player_footstep", Vector3.INF, {"node": dummy, "surface": "grass", "speed": 6.0})
		await _frames(2)
		dummy.queue_free()
		await _frames(1)
	await _frames(30)
	var after := _pool_count()
	results["loops_leak"] = {"before": before, "after_40_freed_nodes": after}
	_log("loops before=%d after=%d cooldowns before=%d after=%d" % [before.loops, after.loops, before.cooldowns, after.cooldowns])


## Reload the same world 3 times with combat in between: pool, node, resource and memory counters per load.
func _reload_cycle(path: String) -> void:
	var rows: Array = []
	for k in 3:
		get_tree().change_scene_to_file(path)
		var dts: Array = []
		var last := Time.get_ticks_usec()
		for i in 360:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			dts.append(float(now - last) / 1000.0)
			last = now
		if world == "HUB" or world == "BOSS":
			await _frames(300)
		_player = get_tree().get_first_node_in_group("player") as Node3D
		_cam = get_viewport().get_camera_3d()
		if _player != null:
			_base = _player.global_position
		for i in 600:
			_combat_tick(i)
			await get_tree().process_frame
		await _frames(240)
		var c := _counters()
		c["load"] = k + 1
		c["load_first_frame_ms"] = snappedf(float(dts[0]), 0.1)
		c["load_top5"] = _top(dts, 5)
		rows.append(c)
		_log("reload %d nodes=%d objects=%d resources=%d static=%.1fMB video=%.1fMB pool=%d orphans=%d" % [k + 1, c.nodes, c.objects,
			c.resources, c.static_mb, c.video_mb, c.pool_nodes, c.orphans])
		results["reload"] = rows
		_save()


const SLAM_GROUP := [
	["player_ham_slam", Vector3(0, 0, 0.5), {"impact": 16.0}],
	["enemy_hurt", Vector3(-1.0, 0.8, 1.5), {"family": "woolly_wolf"}],
	["enemy_defeat", Vector3(1.0, 0.6, 1.5), {"family": "woolly_wolf"}],
	["enemy_defeat", Vector3(0.0, 0.6, 2.2), {"family": "crow_bandit"}],
	["object_crate_break", Vector3(1.8, 0.4, 1.0), {}],
	["object_acorn_collect", Vector3(0.3, 0.8, 1.0), {}],
	["object_acorn_collect", Vector3(-0.3, 0.8, 1.2), {}],
	["object_acorn_collect", Vector3(0.0, 0.8, 1.4), {}],
]


## Repeated bursts with gaps: CPU time inside the Juice.event() calls (wall clock around the loop), the burst frame
## and the next two frames versus the median of the 30 frames before. Robust against one-off contention.
func _bursts() -> void:
	var out_rows := {}
	for kind in ["slam_group_8", "heavy_12"]:
		var list: Array = SLAM_GROUP if kind == "slam_group_8" else HEAVY
		var rows: Array = []
		for rep in 8:
			await _frames(200)
			var pre: Array = []
			var last := Time.get_ticks_usec()
			for i in 30:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				pre.append(float(now - last) / 1000.0)
				last = now
			var t0 := Time.get_ticks_usec()
			for h in list:
				_fire(String(h[0]), h[1], h[2])
			var call_ms := float(Time.get_ticks_usec() - t0) / 1000.0
			Juice.end_hitstop()
			var post: Array = []
			for i in 3:
				await get_tree().process_frame
				var now2 := Time.get_ticks_usec()
				post.append(snappedf(float(now2 - last) / 1000.0, 0.01))
				last = now2
			rows.append({"calls_ms": snappedf(call_ms, 0.01), "pre_median_ms": snappedf(_pctl(pre, 0.5), 0.01), "post_frames_ms": post})
		var calls: Array = []
		var burst_frames: Array = []
		var excess: Array = []
		for r in rows:
			calls.append(r["calls_ms"])
			burst_frames.append(r["post_frames_ms"][0])
			excess.append(float(r["post_frames_ms"][0]) - float(r["pre_median_ms"]))
		out_rows[kind] = {"reps": rows, "calls_ms_median": snappedf(_pctl(calls, 0.5), 0.01), "calls_ms_max": _pctl(calls, 1.0),
			"burst_frame_ms_median": snappedf(_pctl(burst_frames, 0.5), 0.01), "burst_frame_excess_ms_median": snappedf(_pctl(excess, 0.5), 0.01),
			"burst_frame_ms_max": _pctl(burst_frames, 1.0)}
		_log("bursts %s calls median=%.2fms max=%.2fms | burst frame median=%.2fms excess=%.2fms max=%.2fms" % [kind,
			out_rows[kind]["calls_ms_median"], out_rows[kind]["calls_ms_max"], out_rows[kind]["burst_frame_ms_median"],
			out_rows[kind]["burst_frame_excess_ms_median"], out_rows[kind]["burst_frame_ms_max"]])
	results["bursts"] = out_rows
	await _frames(200)

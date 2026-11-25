extends Node
## Critique W2 round 1 (QA lens, resumed 11:10 Bangkok), probe 3: re-checks the round 1 fixes on the current build.
## 1 moving/droopy/bouncer leaf rest positions vs the level JSON (the L06-L08 / LB1-LB5 origin blocker);
## 2 runtime notice/lose radius of every enemy; 3 E01/E02 height over 6 s (E02 fell through the lawn before);
## 4 idle 20 s at the Default spawn (damage count); 5 frame rate at 1920x1080, vsync off, gameplay camera, 4 spots;
## 6 checkpoint respawns: on floor, state, damage within 3 s.
## Run: python tools/godot.py capture res://tests/critique_w2/W2QA.tscn <png> --wait 999999 -- --profile=critic_w2_qa_p3 --w2-nointro --qa-probe=3 --qa-out=<abs dir>

var out_dir := ""
var world: Node
var player: CharacterBody3D
var report := {}
var damage_log: Array = []
var _bucket: PackedFloat32Array = PackedFloat32Array()
var _measuring := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("qa-out", OS.get_user_data_dir().path_join("w2_qa3")) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


var _gpu: PackedFloat32Array = PackedFloat32Array()
var _cpu: PackedFloat32Array = PackedFloat32Array()


func _process(delta: float) -> void:
	if _measuring:
		_bucket.append(delta)
		var vp := get_viewport().get_viewport_rid()
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())


func _median(a: PackedFloat32Array) -> float:
	var x := Array(a)
	x.sort()
	return snappedf(float(x[x.size() / 2]), 0.01) if x.size() > 0 else -1.0


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func _save() -> void:
	report["damage_log"] = damage_log
	var f := FileAccess.open(out_dir.path_join("w2_qa_probe3.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and cs.get("player") != null:
			world = cs
			player = cs.get("player") as CharacterBody3D
			break
		if Time.get_ticks_msec() - t0 > 180000:
			print("[QA3] TIMEOUT")
			get_tree().quit(2)
			return
	report["load_ms"] = Time.get_ticks_msec() - t0
	var game := get_node_or_null("/root/Game")
	if game:
		game.damaged.connect(func(a: int) -> void: damage_log.append({"t": Time.get_ticks_msec(), "amount": a, "pos": _v(player.global_position), "phase": report.get("_phase", "")}))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# 3: garden pods height trace + 4: idle at spawn
	report["_phase"] = "idle_spawn"
	var trace := []
	for i in 20:
		await _wait(1.0)
		var row := {"t": i + 1, "player": _v(player.global_position)}
		for id in ["E01", "E02"]:
			var e := world.find_child(id, true, false) as Node3D
			row[id] = _v(e.global_position) if e else null
		trace.append(row)
	report["idle_trace"] = trace
	report["idle_damage"] = damage_log.size()
	# 1: leaves
	report["_phase"] = "leaves"
	var leaves := []
	var b = world.get("builder")
	var life = world.get("life")
	if b and life:
		for id in b.bodies.keys():
			var body: Node3D = b.bodies[id]
			var kind := String(body.get_meta("kind", ""))
			if kind in ["droop_leaf", "moving_leaf", "bouncy_leaf_swing"]:
				var want: Vector3 = life.call("_jpos", b.plat[id])
				leaves.append({"id": id, "kind": kind, "now": _v(body.global_position), "json": _v(want), "dist": snappedf(body.global_position.distance_to(want), 0.01), "near_origin": body.global_position.length() < 3.0})
	report["leaves"] = leaves
	# 2: notice radius
	var rad := []
	for e in world.find_children("E*", "CharacterBody3D", true, false):
		rad.append({"id": e.name, "notice": e.get("notice_radius"), "lose": e.get("lose_radius"), "pos": _v((e as Node3D).global_position)})
	report["radius"] = rad
	_save()
	# 5: fps
	report["_phase"] = "fps"
	var fps := []
	var spots := {"Default": "Spawns/Default", "CP2": "", "CP4": "", "CP6": ""}
	var cps := world.find_child("Checkpoints", true, false)
	for k in spots.keys():
		var xf: Transform3D
		if k == "Default":
			xf = (world.get_node("Spawns/Default") as Node3D).global_transform
		else:
			var c := cps.find_child(k, true, false) as Node3D if cps else null
			if c == null:
				continue
			xf = c.global_transform
		if player.has_method("respawn"):
			player.call("respawn", xf)
		else:
			player.global_transform = xf
		await _wait(2.0)
		_bucket.clear()
		_gpu.clear()
		_cpu.clear()
		_measuring = true
		await _wait(6.0)
		_measuring = false
		var arr := Array(_bucket)
		arr.sort()
		var n := arr.size()
		var total := 0.0
		for d in arr:
			total += d
		var over := 0
		for d in arr:
			if d > 1.0 / 60.0 + 0.0005:
				over += 1
		fps.append({"spot": k, "frames": n, "mean_fps": snappedf(n / maxf(total, 0.001), 0.1), "p99_ms": snappedf(arr[int(n * 0.99) - 1] * 1000.0, 0.01) if n > 10 else 0.0, "max_ms": snappedf(arr[n - 1] * 1000.0, 0.01) if n > 0 else 0.0, "frames_over_16_7ms": over, "gpu_ms_median": _median(_gpu), "render_cpu_ms_median": _median(_cpu), "draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), "prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)})
	report["fps"] = fps
	_save()
	# 6: checkpoint respawns
	report["_phase"] = "cp_respawn"
	var cpr := []
	if cps:
		for c in cps.get_children():
			if not (c is Node3D):
				continue
			var before := damage_log.size()
			var xf2 := (c as Node3D).global_transform
			if player.has_method("respawn"):
				player.call("respawn", xf2)
			else:
				player.global_transform = xf2
			await _wait(3.0)
			cpr.append({"cp": c.name, "end": _v(player.global_position), "drift": snappedf(player.global_position.distance_to(xf2.origin), 0.01), "on_floor": player.is_on_floor(), "state": str(player.get("state")), "damage_3s": damage_log.size() - before})
	report["cp_respawn"] = cpr
	report["_phase"] = "done"
	_save()
	print("[QA3] done")
	get_tree().quit(0)

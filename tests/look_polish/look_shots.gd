extends Node
## Look-polish shot driver (test only). RetroLook adds this node when the dev argument --look-shots=<abs json> is given.
## For each spot it respawns Mak (MakPlayer.respawn: the gameplay camera snaps behind him), optionally turns the camera
## rig by yaw_offset degrees, waits, saves a native 1920x1080 PNG from the gameplay camera and, when "measure" is set,
## averages GPU / render-CPU frame time over 180 frames. Writes <out>/<prefix>_timing.json and quits.
## JSON: {"out": "<abs dir>", "prefix": "before", "spots": [{"name": "w1_cleft", "x": -47, "z": -9.5, "yaw": 90,
##        "yaw_offset": 0, "pitch": -17, "wait": 70, "measure": true}]}

var cfg: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	var path := String(dev.call("arg", "look-shots", "")) if dev else ""
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		push_error("[LookShots] bad json " + path)
		return
	cfg = d
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _player() -> Node3D:
	var ps := get_tree().get_nodes_in_group("player")
	for p in ps:
		if p.has_method("respawn"):
			return p as Node3D
	return null


func _rig(n: Node) -> Node:
	if n.has_method("snap_behind"):
		return n
	for c in n.get_children():
		var r := _rig(c)
		if r != null:
			return r
	return null


func _floor_y(x: float, z: float) -> float:
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 90.0, z), Vector3(x, -30.0, z))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else 0.5


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var pl: Node3D = null
	while pl == null and Time.get_ticks_msec() - t0 < 60000:
		await _frames(10)
		pl = _player()
	if pl == null:
		push_error("[LookShots] no player")
		get_tree().quit(2)
		return
	await _frames(int(cfg.get("settle", 240)))
	for n in get_tree().get_nodes_in_group("hud"):
		if n is CanvasLayer:
			n.visible = false
	var out := String(cfg["out"])
	DirAccess.make_dir_recursive_absolute(out)
	var prefix := String(cfg.get("prefix", "shot"))
	var timing := {}
	var rig := _rig(get_tree().current_scene)
	for s in cfg["spots"]:
		var sp: Dictionary = s
		var x := float(sp["x"])
		var z := float(sp["z"])
		var y := float(sp["y"]) if sp.has("y") else _floor_y(x, z) + 0.15
		var yaw := deg_to_rad(float(sp.get("yaw", 0.0)))
		pl.call("respawn", Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z)))
		await _frames(2)
		var wait := int(sp.get("wait", 70))
		for i in wait:
			if rig != null and (sp.has("yaw_offset") or sp.has("pitch")):
				rig.set("yaw", float(pl.get("facing_yaw")) + deg_to_rad(float(sp.get("yaw_offset", 0.0))))
				rig.set("pitch", deg_to_rad(float(sp.get("pitch", -17.0))))
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var f := out.path_join("%s_%s.png" % [prefix, String(sp["name"])])
		img.save_png(f)
		print("[LookShots] saved ", f)
		if bool(sp.get("measure", false)):
			timing[String(sp["name"])] = await _measure()
	var tf := FileAccess.open(out.path_join("%s_timing.json" % prefix), FileAccess.WRITE)
	if tf:
		tf.store_string(JSON.stringify(timing, " "))
		tf.close()
	print("[LookShots] timing ", timing)
	get_tree().quit()


func _measure() -> Dictionary:
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(20)
	var gpu := 0.0
	var cpu := 0.0
	var proc := 0.0
	var n := 180
	for i in n:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return {"gpu_ms": gpu / n, "render_cpu_ms": cpu / n, "process_ms": proc / n,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0}

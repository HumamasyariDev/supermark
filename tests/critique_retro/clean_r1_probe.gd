extends Node
## Critique RETRO round 1, IMAGE CLEANLINESS AND PERFORMANCE lens. Test-only probe (never part of gameplay).
## Added under /root by clean_r1_harness.gd so it survives scene changes.
##
## --clean-mode=perf  (default): visits HUB, W1, W2, W3, BOSS, HUB, W1 at a 1920x1080 window with vsync off and records
##     per area: load hitch frames, RetroLook apply stats, memory and RetroLook cache sizes, frame times (gameplay camera,
##     A/B/A/B live toggle when the look is on), a spawn hitch test in W1, blob-shadow ground fit (floating / buried rims,
##     double shadows) with close-up captures, and a grazing horizon capture (retro off/on) for mip and far-field checks.
## --clean-mode=movie: loads W1, flies a scripted camera from StoryCam_C (lateral + slow forward dolly) twice, first with the
##     look off, then on, for Movie Maker shimmer comparison. Frame markers go to <out>/movie_marks.json.
## Args: --clean-out=<abs dir> --clean-tag=<label> [--clean-areas=HUB,W1,...] [--clean-settle=240]

const AREAS := {
	"HUB": "res://scenes/hub/Hub.tscn", "W1": "res://scenes/worlds/w1/W1.tscn", "W2": "res://scenes/worlds/w2/W2.tscn",
	"W3": "res://scenes/worlds/w3/W3.tscn", "BOSS": "res://scenes/boss/WolfRooftop.tscn"}
const DEFAULT_ORDER := ["HUB", "W1", "W2", "W3", "BOSS", "HUB", "W1"]
const SPAWN_TEST := ["res://scenes/enemies/GingerbreadGrenadier.tscn", "res://scenes/enemies/GummyBrute.tscn"]

var out_dir := ""
var tag := "run"
var mode := "perf"
var settle := 240
var rl: Node
var report := {"areas": []}
var _visit := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	rl = get_node_or_null("/root/RetroLook")
	out_dir = String(dev.arg("clean-out", "")) if dev else ""
	tag = String(dev.arg("clean-tag", "run")) if dev else "run"
	mode = String(dev.arg("clean-mode", "perf")) if dev else "perf"
	settle = int(dev.arg("clean-settle", "240")) if dev else 240
	DirAccess.make_dir_recursive_absolute(out_dir)
	if mode == "perf":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		get_window().size = Vector2i(1920, 1080)
	report["tag"] = tag
	report["mode"] = mode
	report["retro_enabled_at_start"] = rl.get("enabled") if rl else null
	report["gpu"] = RenderingServer.get_video_adapter_name()
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save_json() -> void:
	var f := FileAccess.open(out_dir.path_join("clean_r1_%s.json" % tag), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()


func _run() -> void:
	await _frames(5)
	if mode == "movie":
		await _run_movie()
	else:
		var order: Array = DEFAULT_ORDER
		var dev := get_node_or_null("/root/Dev")
		if dev and dev.has_arg("clean-areas"):
			order = String(dev.arg("clean-areas", "")).split(",", false)
		for a in order:
			await _area(String(a))
			_save_json()
	_save_json()
	print("[CleanR1] done ", tag)
	get_tree().quit()


# ------------------------------------------------------------------ perf mode

func _area(key: String) -> void:
	_visit += 1
	var path: String = AREAS[key]
	var rec := {"area": key, "visit": _visit, "path": path}
	var t0 := Time.get_ticks_usec()
	get_tree().change_scene_to_file(path)
	# Frame-by-frame wall deltas from the change call through the first 150 frames (load hitch profile).
	var deltas: Array = []
	var last := t0
	var seen_at := -1
	for i in 150:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		deltas.append(snappedf((now - last) / 1000.0, 0.01))
		last = now
		if seen_at < 0 and get_tree().current_scene != null and get_tree().current_scene.scene_file_path == path:
			seen_at = i
	rec["load_first_frames_ms"] = deltas.slice(0, 12)
	rec["load_total_150f_ms"] = snappedf((last - t0) / 1000.0, 0.1)
	var over := 0
	var worst_after := 0.0
	for i in range(2, deltas.size()):
		worst_after = maxf(worst_after, float(deltas[i]))
		if float(deltas[i]) > 33.4:
			over += 1
	rec["frames_over_33ms_after_frame2"] = over
	rec["worst_frame_after_frame2_ms"] = worst_after
	rec["retro_stats"] = rl.get("last_stats").duplicate() if rl else {}
	await _frames(settle)
	rec["viewport_size"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	rec["window_size"] = [get_window().size.x, get_window().size.y]
	rec["mem"] = _mem()
	if key == "W1" and _visit <= 2:
		rec["spawn_hitch"] = await _spawn_hitch()
	rec["frame_ab"] = await _frame_ab()
	rec["mem_after_ab"] = _mem()
	if rl and bool(rl.get("enabled")):
		rec["blobs"] = await _blob_fit(key)
		# Grazing off/on pair only in the look-on launch (toggling on would pollute the clean retro=0 launch).
		await _grazing_shots(key)
	report["areas"].append(rec)
	print("[CleanR1] ", key, " ", JSON.stringify(rec["frame_ab"]))


func _mem() -> Dictionary:
	var d := {
		"static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"texture_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mb": snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	if rl:
		for k in ["_mats", "_tex", "_dups", "_envs", "_popped", "_variants", "_node_overrides", "_blobs"]:
			var v: Variant = rl.get(k)
			if v is Dictionary or v is Array:
				d["rl" + k] = v.size()
	return d


func _measure(n: int) -> Dictionary:
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(5)
	var gpu: Array = []
	var cpu: Array = []
	var wall: Array = []
	var last := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		wall.append((now - last) / 1000.0)
		last = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	return {"gpu_med": _pct(gpu, 0.5), "gpu_p95": _pct(gpu, 0.95), "cpu_render_med": _pct(cpu, 0.5),
		"wall_med": _pct(wall, 0.5), "wall_p99": _pct(wall, 0.99), "wall_max": _pct(wall, 1.0),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)}


static func _pct(a: Array, p: float) -> float:
	var s := a.duplicate()
	s.sort()
	if s.is_empty():
		return 0.0
	return snappedf(float(s[clampi(int(round(p * (s.size() - 1))), 0, s.size() - 1)]), 0.001)


func _frame_ab() -> Dictionary:
	var out := {"seq": []}
	if rl == null:
		return out
	var start_on := bool(rl.get("enabled"))
	var seq: Array = [start_on, not start_on, start_on, not start_on] if start_on else [false, false]
	# Freeze the view: a static camera at the gameplay camera's current transform, so intro cameras or a drifting
	# follow camera cannot change what is drawn between the A and B samples.
	var gc := get_viewport().get_camera_3d()
	var fixed := Camera3D.new()
	if gc:
		fixed.fov = gc.fov
		fixed.far = gc.far
		fixed.near = gc.near
	get_tree().current_scene.add_child(fixed)
	if gc:
		fixed.global_transform = gc.global_transform
	fixed.make_current()
	out["cam_pos"] = [snappedf(fixed.global_position.x, 0.1), snappedf(fixed.global_position.y, 0.1), snappedf(fixed.global_position.z, 0.1)]
	for on in seq:
		if bool(rl.get("enabled")) != on:
			var t := Time.get_ticks_usec()
			rl.call("set_enabled", on)
			var toggle_ms := (Time.get_ticks_usec() - t) / 1000.0
			await _frames(90)
			var m: Dictionary = await _measure(240)
			m["on"] = on
			m["toggle_call_ms"] = snappedf(toggle_ms, 0.1)
			out["seq"].append(m)
		else:
			await _frames(30)
			var m2: Dictionary = await _measure(240)
			m2["on"] = on
			out["seq"].append(m2)
	if bool(rl.get("enabled")) != start_on:
		rl.call("set_enabled", start_on)
		await _frames(30)
	if gc and is_instance_valid(gc):
		gc.make_current()
	fixed.queue_free()
	return out


func _spawn_hitch() -> Dictionary:
	var res := {}
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return res
	await _frames(20)
	var base: Array = []
	var last := Time.get_ticks_usec()
	for i in 60:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		base.append((now - last) / 1000.0)
		last = now
	res["baseline_med_ms"] = _pct(base, 0.5)
	for p in SPAWN_TEST:
		var ps := load(p) as PackedScene
		if ps == null:
			continue
		var t0 := Time.get_ticks_usec()
		var n := ps.instantiate()
		if n is Node3D:
			var pos := cam.global_position - cam.global_transform.basis.z * 7.0
			get_tree().current_scene.add_child(n)
			(n as Node3D).global_position = pos
			if n.has_method("set_physics_process"):
				n.set_physics_process(false)
		var add_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var fr: Array = []
		last = Time.get_ticks_usec()
		for i in 8:
			await get_tree().process_frame
			var now2 := Time.get_ticks_usec()
			fr.append(snappedf((now2 - last) / 1000.0, 0.01))
			last = now2
		res[p.get_file()] = {"instantiate_add_ms": snappedf(add_ms, 0.1), "next_frames_ms": fr,
			"retro_tex_jobs_total": int(rl.get("last_stats").get("tex_jobs", 0)) if rl else 0}
		n.queue_free()
		await _frames(10)
	return res


func _blob_fit(key: String) -> Dictionary:
	var blobs: Array = []
	for n in get_tree().current_scene.find_children("RetroBlobShadow", "", true, false):
		if n is MeshInstance3D and (n as MeshInstance3D).visible:
			blobs.append(n)
	var space := get_viewport().get_world_3d().direct_space_state
	var rows: Array = []
	var floating := 0
	var buried := 0
	var doubles := 0
	var sun_shadows := false
	for l in get_tree().current_scene.find_children("*", "DirectionalLight3D", true, false):
		if (l as DirectionalLight3D).shadow_enabled and (l as DirectionalLight3D).visible:
			sun_shadows = true
	for b in blobs:
		var mi := b as MeshInstance3D
		var xf := mi.global_transform
		var nrm := xf.basis.y.normalized()
		var ax := xf.basis.x
		var az := xf.basis.z
		var size := ax.length()
		var tgt: Variant = mi.get("target")
		var excl: Array[RID] = []
		var ex: Variant = mi.get("_exclude")
		if ex is Array:
			for r in ex:
				excl.append(r)
		var max_float := 0.0
		var max_bury := 0.0
		var voids := 0
		for k in 12:
			var a := TAU * k / 12.0
			var p := xf.origin + (ax.normalized() * cos(a) + az.normalized() * sin(a)) * size * 0.9
			var q := PhysicsRayQueryParameters3D.create(p + nrm * 1.2, p - nrm * 2.5, 1, excl)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				voids += 1
				continue
			var d := (p - (hit["position"] as Vector3)).dot(nrm)
			max_float = maxf(max_float, d)
			max_bury = maxf(max_bury, -d)
		var dbl := false
		if sun_shadows and tgt is Node3D:
			for g in (tgt as Node3D).find_children("*", "GeometryInstance3D", true, false):
				var gi := g as GeometryInstance3D
				if gi != mi and gi.visible and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and not (gi is GPUParticles3D):
					dbl = true
					break
		var is_float := voids >= 2 or max_float > 0.15
		var is_bury := max_bury > 0.02
		if is_float:
			floating += 1
		if is_bury:
			buried += 1
		if dbl:
			doubles += 1
		rows.append({"target": String((tgt as Node).name) if tgt is Node else "?", "size": snappedf(size, 0.01),
			"max_float": snappedf(max_float, 0.001), "max_bury": snappedf(max_bury, 0.001), "void_rim": voids, "double": dbl,
			"pos": [snappedf(xf.origin.x, 0.1), snappedf(xf.origin.y, 0.1), snappedf(xf.origin.z, 0.1)], "_node": mi})
	# Close-ups of the worst offenders (most buried / floating).
	rows.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		return maxf(a["max_bury"], a["max_float"] + a["void_rim"] * 0.1) > maxf(c["max_bury"], c["max_float"] + c["void_rim"] * 0.1))
	var shots := 0
	for r in rows:
		if shots >= 3:
			break
		if float(r["max_bury"]) < 0.03 and float(r["max_float"]) < 0.15 and int(r["void_rim"]) < 2:
			break
		var mi2: MeshInstance3D = r["_node"]
		if not is_instance_valid(mi2):
			continue
		var c := Camera3D.new()
		c.fov = 45.0
		get_tree().current_scene.add_child(c)
		var center := mi2.global_position
		var sz := maxf(float(r["size"]), 0.4)
		c.global_position = center + Vector3(sz * 2.2 + 1.2, sz * 1.1 + 0.7, sz * 1.4 + 0.8)
		c.look_at(center, Vector3.UP)
		var prev := get_viewport().get_camera_3d()
		c.make_current()
		await _frames(4)
		await _shot("%s__clean_blob_%s_%d" % [_stamp(), key.to_lower(), shots])
		r["shot"] = "%s_%d" % [key.to_lower(), shots]
		if prev:
			prev.make_current()
		c.queue_free()
		shots += 1
	for r in rows:
		r.erase("_node")
	return {"count": rows.size(), "floating": floating, "buried": buried, "double_with_sun_shadow": doubles,
		"sun_shadows": sun_shadows, "rows": rows.slice(0, 24)}


func _grazing_shots(key: String) -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var gc := get_viewport().get_camera_3d()
	if pl == null or gc == null:
		return
	var fwd := -gc.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var c := Camera3D.new()
	c.fov = 60.0
	c.far = 600.0
	get_tree().current_scene.add_child(c)
	c.global_position = pl.global_position + Vector3.UP * 1.6 + fwd * 1.2 + fwd.cross(Vector3.UP) * 0.8
	c.look_at(c.global_position + fwd * 10.0 + Vector3.DOWN * 1.1, Vector3.UP)
	c.make_current()
	var was := bool(rl.get("enabled")) if rl else true
	var st := _stamp()
	for on in [false, true]:
		if rl:
			rl.call("set_enabled", on)
		await _frames(30)
		await _shot("%s__clean_grazing_%s_v%d_retro%d" % [st, key.to_lower(), _visit, int(on)])
	if rl and bool(rl.get("enabled")) != was:
		rl.call("set_enabled", was)
	if gc and is_instance_valid(gc):
		gc.make_current()
	c.queue_free()
	await _frames(10)


static func _stamp() -> String:
	return Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "") + "Z"


func _shot(base: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(base + ".png"))


# ------------------------------------------------------------------ movie mode

func _run_movie() -> void:
	var dev := get_node_or_null("/root/Dev")
	var area := String(dev.arg("clean-movie-area", "W1")) if dev else "W1"
	var cam_kind := String(dev.arg("clean-movie-cam", "story")) if dev else "story"
	get_tree().change_scene_to_file(AREAS[area])
	await _frames(settle)
	var scene := get_tree().current_scene
	var base_cam := scene.find_child("StoryCam_C", true, false) as Camera3D
	if base_cam == null:
		base_cam = scene.find_child("StoryCam_A", true, false) as Camera3D
	var base := base_cam.global_transform if base_cam else Transform3D(Basis(), Vector3(0, 6, 10))
	if cam_kind == "grazing":
		# Gameplay-height view over the ground in front of the player (where nearest texels and dithered blends show most).
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		var gc := get_viewport().get_camera_3d()
		if pl and gc:
			var fwd := -gc.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD
			var p0 := pl.global_position + Vector3.UP * 1.7 + fwd * 1.2
			base = Transform3D(Basis(), p0).looking_at(p0 + fwd * 10.0 + Vector3.DOWN * 1.6, Vector3.UP)
		base_cam = null
	var c := Camera3D.new()
	c.fov = base_cam.fov if base_cam else 60.0
	c.far = 600.0
	scene.add_child(c)
	var marks := {}
	for on in [false, true]:
		if rl:
			rl.call("set_enabled", on)
		c.global_transform = base
		c.make_current()
		await _frames(40)
		marks["retro%d_start" % int(on)] = Engine.get_frames_drawn()
		for i in 300:
			var t := i / 60.0
			var xf := base
			xf.origin += base.basis.x.normalized() * 0.55 * t - base.basis.z.normalized() * 0.35 * t
			xf.basis = Basis(Vector3.UP, deg_to_rad(1.6 * t)) * base.basis
			c.global_transform = xf
			c.make_current()
			await get_tree().process_frame
		marks["retro%d_end" % int(on)] = Engine.get_frames_drawn()
	report["marks"] = marks
	report["movie_area"] = area
	report["movie_cam"] = String(base_cam.name) if base_cam else cam_kind

extends Node
## Render-fix shot driver (test only; transparency fix and soft shadows, 2026-10-19). RetroLook adds this node when the
## dev argument --render-shots=<abs json> is given. One launch visits every listed area (change_scene_to_file), and per
## area: dumps a lighting / material diagnosis, saves native captures from the gameplay camera (MakCamera rig with a set
## distance, yaw offset and pitch) or from a free camera aimed at the nearest node of a group, optionally dumps a
## running clip as JPG frames, and measures GPU / CPU frame time and uncapped fps at the window size.
## JSON: {"out": "<abs dir>", "prefix": "before", "size": [1600, 900], "settle": 200,
##   "areas": [{"name": "hub", "scene": "res://scenes/hub/Hub.tscn", "spots": [
##     {"name": "mak_front", "kind": "hero", "dist": 1.9, "yaw_offset": 150, "pitch": -12, "wait": 60},
##     {"name": "npc", "kind": "target", "group": "npc", "az": 25, "el": 12, "dist": 3.2},
##     {"name": "wide", "kind": "hero", "dist": 8.0, "pitch": -28, "measure": true},
##     {"name": "run", "kind": "clip", "frames": 120, "every": 2, "dist": 4.5, "yaw_offset": 60}]}]}
## Optional per-spot "shadows": "off"/"soft" switches the Game setting before the shot.

var cfg: Dictionary = {}
var diag: Dictionary = {}
var timing: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	var path := String(dev.call("arg", "render-shots", "")) if dev else ""
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		push_error("[RenderShots] bad json " + path)
		return
	cfg = d
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _player() -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
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


func _run() -> void:
	var sz: Array = cfg.get("size", [1600, 900])
	get_window().size = Vector2i(int(sz[0]), int(sz[1]))
	var out := String(cfg["out"])
	DirAccess.make_dir_recursive_absolute(out)
	var prefix := String(cfg.get("prefix", "shot"))
	var first := true
	for a in cfg["areas"]:
		var area: Dictionary = a
		if not first:
			get_tree().paused = false
			get_tree().change_scene_to_file(String(area["scene"]))
			await _frames(20)
		first = false
		var t0 := Time.get_ticks_msec()
		var pl: Node3D = null
		while pl == null and Time.get_ticks_msec() - t0 < 60000:
			await _frames(10)
			pl = _player()
		if pl == null:
			push_error("[RenderShots] no player in " + String(area["name"]))
			continue
		await _frames(int(cfg.get("settle", 200)))
		for n in get_tree().get_nodes_in_group("hud"):
			if n is CanvasLayer:
				n.visible = false
		diag[String(area["name"])] = _diagnose(pl)
		for s in area["spots"]:
			await _spot(s as Dictionary, pl, out, "%s_%s" % [prefix, String(area["name"])])
	var tf := FileAccess.open(out.path_join("%s_timing.json" % prefix), FileAccess.WRITE)
	if tf:
		tf.store_string(JSON.stringify({"timing": timing, "diag": diag}, " "))
		tf.close()
	print("[RenderShots] timing ", JSON.stringify(timing))
	get_tree().quit()


func _spot(sp: Dictionary, pl: Node3D, out: String, base: String) -> void:
	var game := get_node_or_null("/root/Game")
	if sp.has("shadows") and game:
		game.call("set_setting", "soft_shadows", String(sp["shadows"]) != "off", false)
		await _frames(4)
	var kind := String(sp.get("kind", "hero"))
	var rig := _rig(get_tree().current_scene)
	var free_cam: Camera3D = null
	var wait := int(sp.get("wait", 60))
	var legacy: Array = []
	if bool(sp.get("legacy_sil", false)):
		legacy.append_array(_legacy_silhouette(pl))
	if bool(sp.get("legacy_cards", false)):
		legacy.append_array(_legacy_cards())
	if bool(sp.get("legacy_log", false)):
		legacy.append_array(_legacy_log())
	if sp.has("at_node") or sp.has("x"):
		var at := Vector3.ZERO
		if sp.has("at_node"):
			var an := get_tree().current_scene.find_child(String(sp["at_node"]), true, false) as Node3D
			if an == null:
				print("[RenderShots] no node ", sp["at_node"])
				return
			at = an.global_position
		else:
			at = Vector3(float(sp["x"]), float(sp.get("y", 0.0)), float(sp["z"]))
		var off: Array = sp.get("offset", [0.0, 0.3, 0.0])
		at += Vector3(off[0], off[1], off[2])
		pl.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(float(sp.get("yaw", 0.0)))), at))
		await _frames(2)
	var occ: Node3D = null
	if kind == "orbit" or kind == "free":
		free_cam = Camera3D.new()
		free_cam.fov = float(sp.get("fov", 40.0))
		get_tree().current_scene.add_child(free_cam)
		if kind == "free":
			var fp: Array = sp["pos"]
			var la: Array = sp["look"]
			free_cam.global_position = Vector3(fp[0], fp[1], fp[2])
			free_cam.look_at(Vector3(la[0], la[1], la[2]), Vector3.UP)
		else:
			var c := pl.global_position + Vector3.UP * float(sp.get("look_h", 0.62))
			var fwd := Vector3(sin(float(pl.get("facing_yaw"))), 0.0, cos(float(pl.get("facing_yaw"))))
			fwd = -fwd if bool(sp.get("flip", false)) else fwd
			fwd = fwd.rotated(Vector3.UP, deg_to_rad(float(sp.get("az", 0.0))))
			var el := deg_to_rad(float(sp.get("el", 15.0)))
			var dist := float(sp.get("dist", 2.0))
			free_cam.global_position = c + (fwd * cos(el) + Vector3.UP * sin(el)) * dist
			free_cam.look_at(c, Vector3.UP)
			if bool(sp.get("occluder", false)):
				# Test-only wall halfway between the camera and Mak (the occlusion silhouette must still show him).
				occ = MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(1.6, 2.4, 0.12)
				(occ as MeshInstance3D).mesh = bm
				var om := StandardMaterial3D.new()
				om.albedo_color = Color(0.55, 0.42, 0.32)
				(occ as MeshInstance3D).material_override = om
				get_tree().current_scene.add_child(occ)
				occ.global_position = c.lerp(free_cam.global_position, 0.45)
				occ.look_at(free_cam.global_position, Vector3.UP)
		free_cam.make_current()
	if kind == "target":
		var tgt := _nearest(String(sp.get("group", "npc")), pl.global_position, String(sp.get("name_has", "")))
		if tgt == null:
			print("[RenderShots] no target for ", sp["name"])
			return
		free_cam = Camera3D.new()
		free_cam.fov = float(sp.get("fov", 45.0))
		get_tree().current_scene.add_child(free_cam)
		var box := _box(tgt)
		var c := box.get_center()
		print("[RenderShots] target ", tgt.name, " box ", box)
		var fwd := tgt.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 0.01:
			fwd = Vector3.BACK
		fwd = fwd.normalized().rotated(Vector3.UP, deg_to_rad(float(sp.get("az", 0.0))))
		var el := deg_to_rad(float(sp.get("el", 12.0)))
		var dist := float(sp.get("dist", maxf(box.size.y, 0.6) * 2.4))
		free_cam.global_position = c + (fwd * cos(el) + Vector3.UP * sin(el)) * dist
		free_cam.look_at(c, Vector3.UP)
		free_cam.make_current()
	if kind == "clip":
		await _clip(sp, pl, rig, out, base)
		return
	for i in wait:
		if kind == "hero" and rig != null:
			_aim_rig(rig, pl, sp)
		if i == wait - 3:
			_hide_overlays()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var f := out.path_join("%s_%s.png" % [base, String(sp["name"])])
	img.save_png(f)
	print("[RenderShots] saved ", f)
	if bool(sp.get("measure", false)):
		timing["%s_%s" % [base, String(sp["name"])]] = await _measure(rig, pl, sp)
	for e in legacy:
		(e as Callable).call()
	if occ != null:
		occ.queue_free()
	if free_cam != null:
		free_cam.queue_free()
		var gc: Variant = rig.get("cam") if rig != null else null
		if gc is Camera3D:
			(gc as Camera3D).make_current()


func _hide_overlays() -> void:
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for lb in get_tree().root.find_children("*", "Label3D", true, false):
		(lb as Node3D).visible = false


## A/B in one run: the pre-fix occlusion silhouette (no stencil test, 0.8 m gap). Returns restore callables.
func _legacy_silhouette(pl: Node3D) -> Array:
	var out: Array = []
	var seen := {}
	for m in pl.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count() + 1:
			# The last index walks the material_overlay chain (self mark -> silhouette since the gold-hat fix).
			var mat: Material = mi.material_overlay if s == mi.mesh.get_surface_count() else mi.get_active_material(s)
			var guard := 0
			while mat != null and guard < 8:
				if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null and not seen.has(mat.get_instance_id()):
					var sm := mat as ShaderMaterial
					if sm.shader.code.contains("min_gap") and sm.shader.code.contains("stencil_mode read"):
						seen[mat.get_instance_id()] = true
						var old_sh := sm.shader
						var old_gap: Variant = sm.get_shader_parameter("min_gap")
						var lsh := Shader.new()
						lsh.code = old_sh.code.replace("stencil_mode read, compare_not_equal, 77;", "")
						sm.shader = lsh
						sm.set_shader_parameter("min_gap", 0.8)
						out.append(func() -> void:
							sm.shader = old_sh
							sm.set_shader_parameter("min_gap", old_gap))
				mat = mat.next_pass
				guard += 1
	print("[RenderShots] legacy silhouette swaps: ", out.size())
	return out


## A/B in one run: the pre-fix W1 hollow-log fade (bark at 22 % alpha, alpha-hash dither). Returns restore callables.
func _legacy_log() -> Array:
	var lv := get_tree().current_scene.find_child("Level", true, false)
	if lv == null or lv.get("_fade_mat") == null:
		return []
	var old: Variant = lv.get("_fade_mat")
	var leg := StandardMaterial3D.new()
	leg.albedo_texture = (old as ShaderMaterial).get_shader_parameter("albedo_texture")
	leg.albedo_color = Color(0.9, 0.72, 0.52, 0.22)
	leg.roughness = 0.85
	leg.uv1_triplanar = true
	leg.uv1_world_triplanar = true
	leg.uv1_triplanar_sharpness = 4.0
	leg.uv1_scale = Vector3.ONE * 0.45
	leg.rim_enabled = true
	leg.rim = 0.18
	leg.rim_tint = 0.6
	leg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	leg.cull_mode = BaseMaterial3D.CULL_BACK
	var fades: Array = []
	var hl := get_tree().current_scene.find_child("HollowLog", true, false)
	if hl:
		for c in hl.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh:
				fades.append(c)
	lv.set("_fade_mat", leg)
	for f in fades:
		if (f as MeshInstance3D).material_override == old:
			(f as MeshInstance3D).material_override = leg
	print("[RenderShots] legacy log fade on ", fades.size(), " meshes")
	return [func() -> void:
		lv.set("_fade_mat", old)
		for f in fades:
			if (f as MeshInstance3D).material_override == leg:
				(f as MeshInstance3D).material_override = old]


## A/B in one run: the pre-fix double-sided W1 card material. Returns restore callables.
func _legacy_cards() -> Array:
	var out: Array = []
	var leg := StandardMaterial3D.new()
	leg.vertex_color_use_as_albedo = true
	leg.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	leg.cull_mode = BaseMaterial3D.CULL_DISABLED
	leg.disable_fog = true
	for m in get_tree().current_scene.find_children("Card*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var old := mi.material_override
		if old is ShaderMaterial and (old as ShaderMaterial).shader != null 				and (old as ShaderMaterial).shader.resource_path.ends_with("backdrop_card.gdshader"):
			mi.material_override = leg
			out.append(func() -> void: mi.material_override = old)
	print("[RenderShots] legacy card swaps: ", out.size())
	return out


func _aim_rig(rig: Node, pl: Node3D, sp: Dictionary) -> void:
	if sp.has("dist"):
		rig.set("distance", float(sp["dist"]))
	rig.set("yaw", float(pl.get("facing_yaw")) + deg_to_rad(float(sp.get("yaw_offset", 0.0))))
	rig.set("pitch", deg_to_rad(float(sp.get("pitch", -17.0))))


## Mak runs forward (input action) for `frames` frames; every `every`-th frame is saved as a JPG.
func _clip(sp: Dictionary, pl: Node3D, rig: Node, out: String, base: String) -> void:
	var dir := out.path_join("%s_%s_frames" % [base, String(sp["name"])])
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 30:
		if rig != null:
			_aim_rig(rig, pl, sp)
		await get_tree().process_frame
	Input.action_press("move_forward", 1.0)
	var turn := String(sp.get("turn", ""))
	var n := int(sp.get("frames", 120))
	var every := int(sp.get("every", 2))
	for i in n:
		if turn != "" and i == n / 2:
			Input.action_press(turn, 0.7)
		if rig != null and bool(sp.get("hold_cam", true)):
			if sp.has("dist"):
				rig.set("distance", float(sp["dist"]))
		await RenderingServer.frame_post_draw
		if i % every == 0:
			var img := get_viewport().get_texture().get_image()
			img.save_jpg(dir.path_join("f%04d.jpg" % (i / every)), 0.92)
		await get_tree().process_frame
	Input.action_release("move_forward")
	if turn != "":
		Input.action_release(turn)
	print("[RenderShots] clip ", dir)


func _measure(rig: Node, pl: Node3D, sp: Dictionary) -> Dictionary:
	var rid := get_viewport().get_viewport_rid()
	var vs := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(60)
	var gpu := 0.0
	var cpu := 0.0
	var n := 240
	var t0 := Time.get_ticks_usec()
	for i in n:
		if rig != null:
			_aim_rig(rig, pl, sp)
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var secs := (Time.get_ticks_usec() - t0) / 1e6
	DisplayServer.window_set_vsync_mode(vs)
	return {"gpu_ms": snappedf(gpu / n, 0.001), "render_cpu_ms": snappedf(cpu / n, 0.001), "fps": snappedf(n / secs, 0.1),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"size": [get_window().size.x, get_window().size.y]}


func _nearest(group: String, from: Vector3, name_has: String) -> Node3D:
	var best: Node3D = null
	var bd := INF
	var cands: Array = []
	for g in group.split(",", false):
		cands.append_array(get_tree().get_nodes_in_group(g))
		if not cands.is_empty():
			break
	for n in cands:
		if not (n is Node3D) or not (n as Node3D).is_visible_in_tree():
			continue
		var nm := String(n.name).to_lower()
		if nm.contains("sign") or (name_has != "" and not nm.contains(name_has)):
			continue
		var d := (n as Node3D).global_position.distance_to(from)
		if d < bd:
			bd = d
			best = n as Node3D
	return best


func _box(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for v in n.find_children("*", "VisualInstance3D", true, false):
		var vi := v as VisualInstance3D
		if not vi.is_visible_in_tree() or vi is Decal or String(vi.name).to_lower().contains("shadow"):
			continue
		var b := vi.global_transform * vi.get_aabb()
		if b.size.length() > 30.0:
			continue
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(n.global_position - Vector3(0.4, 0.0, 0.4), Vector3(0.8, 1.2, 0.8))
	return box


## Lights, shadow casters and the hero's material chains (transparency, render modes, pass order).
func _diagnose(pl: Node3D) -> Dictionary:
	var scene := get_tree().current_scene
	var lights: Array = []
	for l in scene.find_children("*", "Light3D", true, false):
		var li := l as Light3D
		if not li.is_visible_in_tree():
			continue
		var e := {"name": String(li.name), "type": li.get_class(), "energy": li.light_energy, "shadow": li.shadow_enabled,
			"opacity": li.shadow_opacity, "blur": li.shadow_blur}
		if li is DirectionalLight3D:
			var dl := li as DirectionalLight3D
			e["max_dist"] = dl.directional_shadow_max_distance
			e["mode"] = dl.directional_shadow_mode
			e["dir"] = str(-dl.global_transform.basis.z)
			e["sky_mode"] = dl.sky_mode
		lights.append(e)
	var cast := {"on": 0, "off": 0, "double": 0, "shadows_only": 0}
	for g in scene.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		match gi.cast_shadow:
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: cast["off"] += 1
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON: cast["on"] += 1
			GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED: cast["double"] += 1
			_: cast["shadows_only"] += 1
	var hero: Array = []
	for m in pl.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var chain: Array = []
			var guard := 0
			while mat != null and guard < 8:
				chain.append(_mat_desc(mat))
				mat = mat.next_pass
				guard += 1
			hero.append({"mesh": String(mi.name), "surf": s, "cast": mi.cast_shadow, "vis": mi.is_visible_in_tree(),
				"overlay": _mat_desc(mi.material_overlay) if mi.material_overlay else "", "chain": chain})
	var env := scene.find_children("*", "WorldEnvironment", true, false)
	var ambient := {}
	if not env.is_empty() and (env[0] as WorldEnvironment).environment:
		var en := (env[0] as WorldEnvironment).environment
		ambient = {"src": en.ambient_light_source, "energy": en.ambient_light_energy, "sky_contrib": en.ambient_light_sky_contribution,
			"color": str(en.ambient_light_color)}
	var res := {"lights": lights, "cast": cast, "hero": hero, "ambient": ambient}
	print("[RenderShots] diag ", JSON.stringify(res))
	return res


static func _mat_desc(m: Material) -> String:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		return "Std(%s tr=%d depth=%d cull=%d nodepth=%s prio=%d)" % [b.resource_name, b.transparency, b.depth_draw_mode,
			b.cull_mode, b.no_depth_test, b.render_priority]
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var code := sm.shader.code if sm.shader else ""
		var rm := ""
		var i := code.find("render_mode")
		if i >= 0:
			rm = code.substr(i + 12, code.find(";", i) - i - 12)
		var p := sm.shader.resource_path.get_file() if sm.shader else "?"
		return "Sh(%s alpha=%s prio=%d rm=%s)" % [p, code.contains("ALPHA"), sm.render_priority, rm]
	return m.get_class()

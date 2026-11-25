extends Node
## QA driver, included only in diagnostic exports. Real scenes, cameras and UI.

var _js: JavaScriptObject
var _busy := false
var _previous_camera: Camera3D
var _route: Node
var _imports: Dictionary = {}   # Round 4: imported texture source path -> {"mipmaps": bool, "mode": int}
var _pixel_bytes: Dictionary = {}


func _list_imports(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_list_imports(folder.path_join(sub))
	for file in dir.get_files():
		if not file.ends_with(".import"):
			continue
		var config := ConfigFile.new()
		if config.load(folder.path_join(file)) != OK or String(config.get_value("remap", "type", "")) != "CompressedTexture2D":
			continue
		_imports[folder.path_join(file.trim_suffix(".import"))] = {"mode": int(config.get_value("params", "compress/mode", -1)),
			"mipmaps": bool(config.get_value("params", "mipmaps/generate", false))}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		_js = JavaScriptBridge.get_interface("makReview")
	elif Dev.has_arg("review-plan"):
		_native_plan.call_deferred()
	print("[WebReview] driver ready")


func _process(_delta: float) -> void:
	if _js == null or _busy:
		return
	var request := String(_js.next())
	if request.is_empty():
		return
	_busy = true
	var command: Dictionary = JSON.parse_string(request)
	var result: Dictionary = await _command(command)
	_js.report(JSON.stringify({"id": command["id"], "result": result}))
	_busy = false


func _command(command: Dictionary) -> Dictionary:
	var kind := String(command.get("kind", "state"))
	if _js != null and _js.normalRun == true and kind not in ["state", "route", "route-state", "walk", "measure", "memory"]:
		return {"error": "Normal input review cannot change scene, progress or presentation"}
	match kind:
		"route":
			if is_instance_valid(_route):
				return {"error": "route already active"}
			var world := Game.current_world
			if world == "BOSS":
				_route = load("res://tests/web/boss_route.gd").new()
				get_tree().current_scene.add_child(_route)
				_route.start(get_tree().current_scene)
			elif world == "W3":
				_route = load("res://tests/web/w3_route.gd").new()
				get_tree().current_scene.get_node("Level").add_child(_route)
			else:
				_route = load("res://tests/web/walk_route.gd").new()
				_route.world = world
				get_tree().current_scene.add_child(_route)
			return {"started": world, "real_input": true}
		"route-state":
			return _route.result if is_instance_valid(_route) else {"gone": true}
		"walk":
			if not is_instance_valid(_route):
				_route = load("res://tests/web/walk_route.gd").new()
				get_tree().current_scene.add_child(_route)
			var at: Array = command["at"]
			var arrived: bool = await _route.go(Vector3(at[0],at[1],at[2]), 0.5, 20.0)
			_route.inp.set("replay_active", false)
			_route.queue_free()
			_route = null
			return {"arrived": arrived}
		"wait":
			await get_tree().create_timer(float(command.get("seconds", 1.0)), true).timeout
			return {}
		"shot":
			await RenderingServer.frame_post_draw
			var destination := String(Dev.arg("review-out")).path_join(String(command["name"]) + ".png")
			DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
			get_viewport().get_texture().get_image().save_png(destination)
			return {"path": destination}
		"title-pose":
			for title in get_tree().get_nodes_in_group("title_screen"):
				title.set("_t", 3.0)
				title.set("_logo_k", 1.0)
				title.call("_process", 0.0)
				title.set_process(false)
			return {}
		"input":
			var key := InputEventKey.new()
			key.physical_keycode = int(command["code"])
			key.keycode = key.physical_keycode
			key.pressed = true
			Input.parse_input_event(key)
			await get_tree().process_frame
			key = key.duplicate()
			key.pressed = false
			Input.parse_input_event(key)
			return {}
		"goto":
			if Router.busy:
				await Router.transition_finished
			get_tree().paused = false
			if UI.pause_menu.is_open():
				UI.pause_menu.resume()
			if UI.mission_select.visible:
				UI.mission_select._close()
			var world := String(command["world"])
			if world == "HUB":
				Router.go_to_hub()
			else:
				Router.enter_world(world)
			await Router.transition_finished
			return {"world": Game.current_world}
		"memory":
			# Round 4: what a long session keeps (engine heap, GPU allocations, live objects).
			return {"world": Game.current_world, "static_mb": OS.get_static_memory_usage() / 1048576.0,
				"static_peak_mb": OS.get_static_memory_peak_usage() / 1048576.0,
				"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				"texture_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
				"buffer_mb": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
				"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
				"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
				"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)}
		"textures":
			# Round 4: every imported texture alive right now (ResourceLoader's cache is weak, so something holds
			# each one), largest first. Bytes come from the GPU format and the import's mipmap flag.
			if _imports.is_empty():
				_list_imports("res://")
			var rows: Array = []
			var total := 0.0
			for source: String in _imports:
				if not ResourceLoader.has_cached(source):
					continue
				var texture := ResourceLoader.get_cached_ref(source) as Texture2D
				if texture == null:
					continue
				var format := RenderingServer.texture_get_format(texture.get_rid())
				if not _pixel_bytes.has(format):
					_pixel_bytes[format] = Image.create_empty(4, 4, false, format).get_data_size() / 16.0
				var mb := texture.get_width() * texture.get_height() * float(_pixel_bytes[format]) / 1048576.0
				if bool(_imports[source]["mipmaps"]):
					mb *= 4.0 / 3.0
				# Round 4: a released map keeps its Texture2D and size but holds one pixel on the GPU.
				var released_map: Variant = RetroLook.get("_released")
				var released: bool = released_map is Dictionary and (released_map as Dictionary).has(texture.get_instance_id())
				if released:
					mb = 0.0
				total += mb
				rows.append({"path": source, "w": texture.get_width(), "h": texture.get_height(), "format": format,
					"mode": _imports[source]["mode"], "mb": mb, "released": released})
			rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["mb"]) > float(b["mb"]))
			var released_all: Variant = RetroLook.get("_released")
			return {"world": Game.current_world, "count": rows.size(), "total_mb": total,
				"released": (released_all as Dictionary).size() if released_all is Dictionary else 0,
				"top": rows.slice(0, int(command.get("limit", 80)))}
		"camera":
			_previous_camera = get_viewport().get_camera_3d()
			var name := String(command.get("name", "StoryCam_A"))
			var camera := get_tree().current_scene.find_child(name, true, false) as Camera3D
			if camera == null:
				return {"error": "camera missing", "name": name}
			camera.make_current()
			return {"position": str(camera.global_position), "rotation": str(camera.global_rotation), "fov": camera.fov,
				"acorns": _acorn_probe()}
		"gameplay-camera":
			if is_instance_valid(_previous_camera):
				_previous_camera.make_current()
			return {}
		"book":
			Router.open_book(String(command.get("world", "W1")))
			return {"opened": true}
		"pause":
			UI.open_pause()
			return {"opened": UI.pause_menu.is_open()}
		"settings-display":
			# Round 4: the settings page scrolled to Display (Graphics, Classic textures, Shadows).
			if not UI.pause_menu.is_open():
				UI.open_pause()
			UI.pause_menu._on_settings()
			await get_tree().process_frame
			var menu: Node = UI.pause_menu._settings
			var graphics: Control = menu.get("_graphics_button") if menu != null else null
			if graphics != null:
				graphics.grab_focus()
				# The focus tween stops short of the fade; centre the row once it has finished.
				await get_tree().create_timer(0.4, true).timeout
				var scroll: ScrollContainer = menu.get("_scroll")
				if scroll != null:
					scroll.scroll_vertical = int(scroll.scroll_vertical + graphics.global_position.y
						- scroll.global_position.y - scroll.size.y * 0.5)
			return {"graphics_row": graphics != null, "graphics": String(graphics.get("text")) if graphics != null else ""}
		"resume":
			UI.pause_menu.resume()
			return {"opened": UI.pause_menu.is_open()}
		"close-dialog":
			UI.dialog.close()
			return {}
		"close-book":
			UI.mission_select._close()
			return {}
		"joy-start":
			var button := InputEventJoypadButton.new()
			button.button_index = JOY_BUTTON_START
			button.pressed = true
			Input.parse_input_event(button)
			await get_tree().process_frame
			button = button.duplicate()
			button.pressed = false
			Input.parse_input_event(button)
			return {"pause_open": UI.pause_menu.is_open()}
		"batch-check":
			var before := Game.acorns
			var acorns := get_tree().get_nodes_in_group("acorn")
			var selected: Node
			for acorn: Node in acorns:
				if not acorn.get("is_collected") and acorn.can_process():
					selected = acorn
					break
			if selected == null:
				return {"error": "no acorn available"}
			var weak: WeakRef = weakref(selected)
			var expected := before + int(selected.get("value"))
			selected.call("collect")
			await get_tree().create_timer(0.6, true).timeout
			var collected := Game.acorns >= expected and weak.get_ref() == null
			Game.settings_changed.emit()
			await get_tree().process_frame
			var observers := 0
			for node in get_tree().current_scene.find_children("*", "MeshInstance3D", true, false):
				if node.has_method("observe"):
					observers += 1
			return {"collected_and_freed": collected, "settings_restored_sources": observers == 0,
				"acorns_before": before, "acorns_after": Game.acorns, "expected_minimum": expected,
				"fixture": "one production pickup collected; settings refresh after visual capture"}
		"probe-particles":
			var changed := 0
			for particle: GPUParticles3D in get_tree().root.find_children("*", "GPUParticles3D", true, false):
				if particle.draw_order == GPUParticles3D.DRAW_ORDER_VIEW_DEPTH:
					particle.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
					changed += 1
			return {"view_sorted_emitters_changed": changed, "diagnostic_only": true}
		"probe-batches":
			Game.settings_changed.emit()
			return {"batches_disabled": true, "diagnostic_only": true}
		"render-probe":
			if command.has("atlas"):
				# Round 4: 16-bit depth by default, as the game's project setting uses.
				RenderingServer.directional_shadow_atlas_set_size(int(command["atlas"]), bool(command.get("bits16", true)))
			if command.has("positional"):
				get_viewport().positional_shadow_atlas_size = int(command["positional"])
			if command.has("msaa"):
				get_viewport().msaa_3d = int(command["msaa"])
			if command.has("scale"):
				# Fill-rate probe: a large gain at a lower 3D scale means the frame waits on the GPU.
				get_viewport().scaling_3d_scale = float(command["scale"])
			if command.has("lod"):
				get_viewport().mesh_lod_threshold = float(command["lod"])
			for light: Light3D in get_tree().current_scene.find_children("*", "Light3D", true, false):
				if light is DirectionalLight3D and command.has("splits"):
					light.directional_shadow_mode = int(command["splits"])
				if command.has("shadows"):
					light.shadow_enabled = bool(command["shadows"])
			return {"diagnostic_only": true, "parameters": command}
		"cloud-probe":
			var shader := load("res://assets/shaders/cloud.gdshader") as Shader
			if not shader.has_meta("qa_original"):
				shader.set_meta("qa_original", shader.code)
			var code: String = shader.get_meta("qa_original")
			if bool(command.get("no_ambient", false)):
				code = code.replace("diffuse_lambert, specular_disabled", "diffuse_lambert, specular_disabled, ambient_light_disabled")
			if bool(command.get("linear_uniforms", false)):
				# GLES3 custom light() receives source_color uniforms in sRGB,
				# while its light accumulator is linear. Test that boundary alone.
				var begin := code.find("void light()")
				var lighting := code.substr(begin)
				for uniform in ["light_color", "shade_color"]:
					lighting = lighting.replace(uniform + ".rgb", "pow(" + uniform + ".rgb, vec3(2.2))")
				code = code.substr(0, begin) + lighting
			shader.code = code
			return {"diagnostic_only": true, "parameters": command}
		"grade-probe":
			var values: Array = []
			for we: WorldEnvironment in get_tree().current_scene.find_children("*", "WorldEnvironment", true, false):
				var env := we.environment
				if not env.has_meta("qa_grade"):
					env.set_meta("qa_grade", [env.adjustment_brightness, env.adjustment_saturation, env.tonemap_exposure])
				var original: Array = env.get_meta("qa_grade")
				env.adjustment_brightness = original[0] * float(command.get("brightness", 1.0))
				env.adjustment_saturation = original[1] * float(command.get("saturation", 1.0))
				env.tonemap_exposure = original[2] * float(command.get("exposure", 1.0))
				values.append({"brightness": env.adjustment_brightness, "saturation": env.adjustment_saturation, "exposure": env.tonemap_exposure})
			return {"diagnostic_only": true, "values": values}
		"dialog":
			# Production dialog widget with the existing native UI-showcase line.
			UI.show_dialog("Bramwell", ["Good heavens, Master Mak! The Wolf has huffed every Golden Truffle clean out of the library."])
			return {"source": "production dialog widget, existing showcase text"}
		"bridge":
			return _bridge_test()
		"ending":
			var arena := get_tree().current_scene as WolfRooftop
			if arena == null:
				return {"error": "not in boss arena"}
			arena.boss.fighting = false
			Dev.args["boss-stay"] = "true"
			arena.boss.defeated = true
			arena.boss.state = "done"
			arena.boss._on_truffle("BOSS-1")
			return {"fixture": "real outro invoked after simulated victory; not a normal-run completion"}
		"measure":
			var viewport_rid := get_viewport().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
			var frames: Array[float] = []
			var long_frames: Array[Dictionary] = []
			var seconds := float(command.get("seconds", 10.0))
			var start := Time.get_ticks_usec()
			var previous := start
			var process_ms := 0.0
			var physics_ms := 0.0
			var render_cpu_ms := 0.0
			var gpu_ms := 0.0
			while (Time.get_ticks_usec() - start) / 1000000.0 < seconds:
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				frames.append((now - previous) / 1000.0)
				if frames[-1] > 100.0:
					long_frames.append({"since_start_ms": (now - start) / 1000.0, "duration_ms": frames[-1]})
				previous = now
				process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
				physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
				gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
				if bool(command.get("stop_route", false)) and is_instance_valid(_route) and bool(_route.result.get("done", false)):
					break
			frames.sort()
			var count := frames.size()
			var elapsed := (Time.get_ticks_usec() - start) / 1000000.0
			return {"frames": count, "seconds": elapsed, "fps": count / elapsed,
				"p50_ms": frames[int(count * 0.5)], "p95_ms": frames[mini(count - 1, int(count * 0.95))],
				"max_ms": frames[-1], "over_100_ms": frames.filter(func(v: float) -> bool: return v > 100.0).size(),
				"process_ms": process_ms / count, "physics_ms": physics_ms / count,
				"render_cpu_ms": render_cpu_ms / count, "gpu_ms": gpu_ms / count,
				"long_frames": long_frames,
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	return {"world": Game.current_world, "paused": get_tree().paused, "router_busy": Router.busy,
		"truffles": Game.data.get("truffles",{}), "mission": Game.current_mission,
		"cache_hits": RetroLook.last_stats.get("web_cache_hits", 0), "cache_misses": RetroLook._web_misses.keys(),
		"mouse_mode": Input.mouse_mode, "pause_open": UI.pause_menu.is_open(),
		"bridge_normal": P0Bridge._normal, "bridge_won": P0Bridge._won}


## OPUSLOOK diagnostic: the material and texture size the first acorns draw with (pickup 128 px, environment 256 px).
func _acorn_probe() -> Array:
	var out: Array = []
	for acorn in get_tree().get_nodes_in_group("acorn"):
		for mi: MeshInstance3D in acorn.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null or mi.mesh is PlaneMesh or mi.mesh is QuadMesh:
				continue
			for surface in mi.mesh.get_surface_count():
				var material := mi.get_active_material(surface)
				var texture: Variant = null
				if material is BaseMaterial3D:
					texture = (material as BaseMaterial3D).albedo_texture
				elif material is ShaderMaterial:
					texture = (material as ShaderMaterial).get_shader_parameter("albedo_texture")
				out.append({"acorn": String(acorn.name), "mesh": String(mi.name), "surface": surface,
					"material": material.get_class() if material else "none",
					"texture_width": (texture as Texture2D).get_width() if texture is Texture2D else -1,
					"layers": mi.layers, "role": String((material.get_meta("retro_state", {}) as Dictionary).get("role", "-")) if material else "-"})
		if out.size() >= 6:
			break
	return out


func _native_plan() -> void:
	var plan: Array = JSON.parse_string(FileAccess.get_file_as_string(Dev.arg("review-plan")))
	var results: Array = []
	for command: Dictionary in plan:
		results.append({"command": command, "result": await _command(command)})
	var output := FileAccess.open(Dev.arg("review-out").path_join("native-results.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(results, "\t"))
	print("[WebReview] native plan finished")
	get_tree().quit()


func _bridge_test() -> Dictionary:
	var arena := get_tree().current_scene as WolfRooftop
	if arena == null or _js == null:
		return {"error": "requires web boss fixture"}
	var previous := {"normal": P0Bridge._normal, "hub": P0Bridge._saw_hub, "story": P0Bridge._story_boss,
		"won": P0Bridge._won, "defeated": arena.boss.defeated, "mission": Game.current_mission}
	P0Bridge._normal = true
	P0Bridge._saw_hub = true
	P0Bridge._won = false
	Game.current_mission = ""
	P0Bridge._on_transition("BOSS")
	arena.boss.defeated = true
	_js.phase("absent")
	_js.setHost(false)
	P0Bridge._on_truffle("BOSS-1")
	P0Bridge.record_time("contract", 12.5)
	var absent_ok := not P0Bridge._won
	_js.setHost(true)
	_js.phase("debug")
	P0Bridge._normal = false
	P0Bridge._on_transition("BOSS")
	P0Bridge._on_truffle("BOSS-1")
	P0Bridge.record_time("contract", 12.5)
	_js.phase("practice")
	P0Bridge._normal = true
	Game.current_mission = "boss-practice"
	P0Bridge._on_transition("BOSS")
	P0Bridge._on_truffle("BOSS-1")
	P0Bridge.record_time("contract", 12.5)
	_js.phase("not-defeated")
	Game.current_mission = ""
	P0Bridge._on_transition("BOSS")
	arena.boss.defeated = false
	P0Bridge._on_truffle("BOSS-1")
	_js.phase("win-once")
	arena.boss.defeated = true
	P0Bridge._on_truffle("W1-1")
	P0Bridge._on_truffle("BOSS-1")
	P0Bridge._on_truffle("BOSS-1")
	_js.phase("score")
	Game.record_time("GODOTWEB-contract-test", 12.345)
	P0Bridge.record_time("contract", NAN)
	P0Bridge.record_time("contract", -1.0)
	P0Bridge._normal = previous["normal"]
	P0Bridge._saw_hub = previous["hub"]
	P0Bridge._story_boss = previous["story"]
	P0Bridge._won = previous["won"]
	arena.boss.defeated = previous["defeated"]
	Game.current_mission = previous["mission"]
	_js.phase("after")
	return {"absent_noop": absent_ok, "fixture": "policy and JavaScript contract; not a story playthrough"}

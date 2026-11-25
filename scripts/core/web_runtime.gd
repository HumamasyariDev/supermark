extends Node
## Compatibility workarounds are isolated from the native renderer.

const WebBatches := preload("res://scripts/core/web_batches.gd")
const WebCpuParticles := preload("res://scripts/fx/web_cpu_particles.gd")
const WAIT_PROGRAMS_MS := 90000

var _trace: JavaScriptObject
var _monitor_at := 0


func trace_start() -> int:
	return Time.get_ticks_usec() if _trace != null else 0


func trace_end(label: String, started: int) -> void:
	if _trace != null and started > 0:
		_trace.span(label, (Time.get_ticks_usec() - started) / 1000.0)


func _process(_delta: float) -> void:
	if _trace == null or Time.get_ticks_msec() < _monitor_at:
		return
	_monitor_at = Time.get_ticks_msec() + 1000
	_trace.monitor(JSON.stringify({
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}))


var _shell: JavaScriptObject
var _warming := false
var _portraits_warm := false
var _web_shaders: Array[Shader] = []


func _enter_tree() -> void:
	if not OS.has_feature("web"):
		return
	# Every scenery mesh otherwise reserves an instance-uniform block for a flash
	# it never uses. WebGL's uniform-buffer limit cannot be raised in project settings.
	# Keep the shared resource path, so preloads and runtime retro variants agree.
	var toon := load("res://assets/shaders/toon.gdshader") as Shader
	toon.code = toon.code.replace("instance uniform float flash", "uniform float flash")
	_web_shaders.append(toon)
	# Forward+ reconstructs depth from [0, 1]; WebGL uses [-1, 1]. Without
	# this conversion every river pixel is mistaken for shoreline foam.
	for file in ["water", "fx_inked", "fx_inked_top", "fx_puff", "post_storybook"]:
		var shader := load("res://assets/shaders/%s.gdshader" % file) as Shader
		var code := shader.code
		for variable in ["raw_depth", "rdepth", "depth", "d"]:
			code = code.replace(", " + variable + ", 1.0)", ", (" + variable + " * 2.0 - 1.0), 1.0)")
		if file == "post_storybook":
			# Compatibility has no normal/roughness buffer. Reconstruct the same
			# geometric edge signal from depth in the view's coordinate space.
			code = code.replace("uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;", "")
			code = code.replace("vec3 normal_at(vec2 uv)", "vec3 normal_at(vec2 uv, mat4 inv_proj)")
			code = code.replace("return texture(normal_tex, uv).xyz * 2.0 - 1.0;", "float d = texture(depth_tex, uv).r;\n\tvec4 p = inv_proj * vec4(vec3(uv, d) * 2.0 - 1.0, 1.0);\n\tvec3 v = p.xyz / p.w;\n\treturn normalize(cross(dFdx(v), dFdy(v)));")
			for expression in ["uv", "uv + vec2(px.x, 0.0)", "uv + vec2(0.0, px.y)"]:
				code = code.replace("normal_at(" + expression + ")", "normal_at(" + expression + ", INV_PROJECTION_MATRIX)")
		shader.code = code
		# ResourceLoader's cache is weak. Retain these resources until their
		# worlds load, otherwise they reload the original Forward+ shader.
		_web_shaders.append(shader)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	if not OS.has_feature("web"):
		return
	get_tree().node_added.connect(_on_node_added)
	# Project 0 supplies its own HTML. Only the standalone export defines this
	# helper; probing a missing global with get_interface emits a Godot error.
	var window := JavaScriptBridge.get_interface("window")
	if "--web-profile" in OS.get_cmdline_user_args() and window.makTrace != null:
		_trace = window.makTrace
		set_process(true)
	if window != null and window.makWeb != null:
		_shell = JavaScriptBridge.get_interface("makWeb")


func _on_node_added(node: Node) -> void:
	if node is CPUParticles3D:
		_web_particle_colors.call_deferred(node)


## OPUSLOOK: scripted CPU particles drawn with a StandardMaterial3D that takes vertex colour as albedo show their colours
## as linear on the desktop (paler: chimney smoke, soot, confetti) and as sRGB here (darker, dirtier). Their colours are
## encoded once so both builds show the same particles. Converted GPU emitters keep theirs (their process material already
## supplied authored values), and additive ones keep theirs (the web adds them after encoding).
func _web_particle_colors(particles: CPUParticles3D) -> void:
	if not is_instance_valid(particles) or particles.has_meta("web_srgb") or particles.get_script() == WebCpuParticles:
		return
	var material := particles.material_override as BaseMaterial3D
	if material == null and particles.mesh != null and particles.mesh.get_surface_count() > 0:
		material = particles.mesh.surface_get_material(0) as BaseMaterial3D
	if material == null or not material.vertex_color_use_as_albedo or material.vertex_color_is_srgb 			or material.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return
	particles.set_meta("web_srgb", true)
	particles.color = _encoded(particles.color)
	for property in ["color_ramp", "color_initial_ramp"]:
		var ramp := particles.get(property) as Gradient
		if ramp != null:
			ramp = ramp.duplicate() as Gradient
			for i in ramp.get_point_count():
				ramp.set_color(i, _encoded(ramp.get_color(i)))
			particles.set(property, ramp)


static func _encoded(c: Color) -> Color:
	var e := c.linear_to_srgb()
	e.a = c.a
	return e


func loading(message: String) -> void:
	if OS.has_feature("web"):
		# Do not compile the unconverted materials on the first scene frame.
		# The page's loading layer remains animated while the scene is prepared.
		get_viewport().disable_3d = true
	if _shell != null:
		_shell.loading(message)
	else:
		_platform_hud(message)


func loaded() -> void:
	if _shell != null:
		_shell.loaded()
	else:
		_platform_hud("")


func _platform_hud(message: String) -> void:
	if not OS.has_feature("web"):
		return
	var window := JavaScriptBridge.get_interface("window")
	if window != null and window.p0 != null and window.p0.hud != null:
		window.p0.hud(message)


func warm_scene(scene: Node) -> void:
	if not OS.has_feature("web") or scene == null or _warming:
		return
	_warming = true
	var title_only := scene.is_in_group("title_screen")
	loading("Preparing the chapter...")
	var look := get_node_or_null("/root/RetroLook")
	# Router has already yielded two frames, letting RetroLook apply the current
	# scene. Title is a child of Boot and needs its own pass. Avoid a second full
	# world traversal (0.6-0.9 seconds in the initial W1/W2/W3 measurements).
	if look and (title_only or look._scene != scene):
		var t := trace_start()
		look.apply_to(scene)
		trace_end("RetroLook.apply_to", t)
	for role in ["player", "enemy", "boss"]:
		for actor in get_tree().get_nodes_in_group(role):
			FxToon.prepare_web_flash(actor)
	if not scene.has_node("WebDrawBatches"):
		var batches := WebBatches.new()
		scene.add_child(batches)
		var t := trace_start()
		batches.call("build", scene)
		trace_end("WebBatches.build", t)
	var world := "HUB" if title_only else Game.current_world
	if world in ["HUB", "BOSS"] and not scene.has_node("WebAtmosphere"):
		var atmosphere := preload("res://scripts/core/web_atmosphere.gd").new()
		atmosphere.name = "WebAtmosphere"
		scene.add_child(atmosphere)
		atmosphere.setup(scene, world)
	var hud_wanted: bool = UI._hud_wanted
	if not title_only:
		UI.set_hud_visible(true)
	# Actual materials, including the generated retro variants, are drawn before
	# controls resume. Small batches let the browser paint its loading indicator.
	var representatives: Dictionary = {}
	var hidden: Array = []
	var stack: Array[Node] = [scene]
	if not title_only:
		stack.append(UI)
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GeometryInstance3D and node.layers != 0:
			hidden.append([node, node.layers])
		var mesh: Mesh
		if node is MeshInstance3D:
			mesh = node.mesh
		elif node is MultiMeshInstance3D and node.multimesh != null:
			mesh = node.multimesh.mesh
		if mesh != null and node.layers != 0 and node.is_visible_in_tree() \
				and (not title_only or _in_camera(node, get_viewport().get_camera_3d())):
			for surface in mesh.get_surface_count():
				var material: Material = node.get_active_material(surface) if node is MeshInstance3D else mesh.surface_get_material(surface)
				if node is MultiMeshInstance3D and node.material_override != null:
					# Procedural cloud/prop batches override their mesh's material.
					# Warm the material actually drawn, including meshes with no base material.
					material = node.material_override
				if material:
					var key := _material_key(material) + node.get_class()
					if node is MeshInstance3D:
						key += str(node.skin != null)
					representatives[key] = node
		for child in node.get_children():
			stack.append(child)
	# The old camera sweep also rendered every other visible object. A single
	# frame then linked dozens of programs while its loading animation froze.
	# Keep real geometry and lights, but admit just one representative per frame.
	for entry: Array in hidden:
		entry[0].layers = 0
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	# The real world's fog, lights, shadows, skinning and instancing select the
	# actual Compatibility programs. A sphere in an empty world warms different
	# programs and leaves expensive first-use work for gameplay.
	viewport.world_3d = get_viewport().world_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.near = 0.01
	camera.current = true
	var flash_light := OmniLight3D.new()
	flash_light.light_energy = 0.001
	flash_light.shadow_enabled = false
	flash_light.visible = false
	scene.add_child(flash_light)
	var started := Time.get_ticks_msec()
	# Where the loading time goes (milliseconds per step), printed with the summary below.
	var steps := {}
	var step_at := started
	# ROUND3, background linking only: draw the live view behind the chapter page and start the effects now, so their
	# particle programs (3 to 5 s each to link) link while the representatives are drawn.
	var early_effects := not title_only and Game.current_world != "" and async_programs()
	if early_effects:
		get_viewport().disable_3d = false
		Juice.prewarm(true)
	print("[WebRuntime] preparing %d representatives, title=%s" % [representatives.size(), title_only])
	for geometry: GeometryInstance3D in representatives.values():
		geometry.layers = 1
		viewport.world_3d = geometry.get_world_3d()
		var bounds: AABB = geometry.global_transform * geometry.get_aabb()
		var radius := maxf(0.1, bounds.size.length() * 0.5)
		var center := bounds.get_center()
		camera.far = maxf(100.0, radius * 8.0)
		camera.global_position = center + Vector3(0.0, radius * 0.3, radius * 2.5)
		camera.look_at(center)
		await get_tree().process_frame
		# Combat adds short local lights even in areas lit only by the sun.
		# Compile that lighting program under the loading layer as well.
		if not title_only:
			flash_light.global_position = center
			flash_light.omni_range = radius * 4.0 + 3.0
			flash_light.visible = true
			await get_tree().process_frame
			flash_light.visible = false
		geometry.layers = 0
	flash_light.queue_free()
	steps["representatives"] = Time.get_ticks_msec() - step_at
	step_at = Time.get_ticks_msec()
	# Camera cuts can reveal another light/shadow combination, even when the
	# material was already drawn elsewhere. Include the authored story cameras
	# and the player's actual camera in the loading pass.
	viewport.world_3d = get_viewport().world_3d
	var held_particles: Array = []
	for entry: Array in hidden:
		if is_instance_valid(entry[0]):
			if title_only and entry[0] is GPUParticles3D and async_programs():
				# ROUND3: the title's ambient particles (hall dust, hearth sparks) need particle programs that take 3 to
				# 5 s each to link. The title opens without waiting for them; they start a few seconds later.
				held_particles.append(entry)
				continue
			entry[0].layers = entry[1]
	for view: Camera3D in scene.find_children("*", "Camera3D", true, false):
		if title_only and view != get_viewport().get_camera_3d():
			continue
		camera.global_transform = view.global_transform
		camera.fov = view.fov
		camera.near = view.near
		camera.far = view.far
		camera.cull_mask = view.cull_mask
		await get_tree().process_frame
	steps["views"] = Time.get_ticks_msec() - step_at
	step_at = Time.get_ticks_msec()
	await _wait_for_programs(WAIT_PROGRAMS_MS)
	steps["linking"] = Time.get_ticks_msec() - step_at
	step_at = Time.get_ticks_msec()
	viewport.queue_free()
	get_viewport().disable_3d = false
	var live_camera := get_viewport().get_camera_3d()
	if live_camera and not title_only:
		var burst_host := Node3D.new()
		burst_host.process_mode = Node.PROCESS_MODE_ALWAYS
		scene.add_child(burst_host)
		for unshaded: bool in [false, true]:
			ObjSvc.burst(burst_host, live_camera.global_position - live_camera.global_basis.z * 3.0,
				Color.WHITE, 1, 0.0, 0.01, 0.0, 0.2, unshaded)
		for _frame in 4:
			await get_tree().process_frame
		burst_host.queue_free()
	if not _portraits_warm and not title_only:
		_portraits_warm = true
		var portrait := UIModelView.new()
		portrait.position = Vector2(-100, -100)
		portrait.size = Vector2(32, 32)
		add_child(portrait)
		portrait.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var seen: Dictionary = {}
		for info: Array in UISpeakers.SPEAKERS.values():
			var path := String(info[0])
			if seen.has(path):
				continue
			seen[path] = true
			portrait.set_model(path, "bust")
			await get_tree().process_frame
		portrait.queue_free()
	steps["bursts_portraits"] = Time.get_ticks_msec() - step_at
	step_at = Time.get_ticks_msec()
	# Juice owns pooled particles and sound preloads; keep their first-use work
	# under the same loading indicator instead of releasing it mid-queue.
	# Combat effects cannot play on the title. Prepare them when entering a
	# playable area, rather than front-loading the whole catalogue at boot.
	if Game.current_world != "":
		if not early_effects:
			Juice.prewarm(true)
		while not Juice.is_warm():
			await get_tree().process_frame
	steps["effects"] = Time.get_ticks_msec() - step_at
	step_at = Time.get_ticks_msec()
	for _frame in 4:
		await get_tree().process_frame
	# The area itself, drawn from the live camera behind the chapter page, may still ask for a light combination
	# the representatives did not show.
	await _wait_for_programs(WAIT_PROGRAMS_MS)
	steps["final_linking"] = Time.get_ticks_msec() - step_at
	for entry: Array in held_particles:
		if is_instance_valid(entry[0]):
			entry[0].layers = entry[1]
	UI.set_hud_visible(hud_wanted)
	print("[WebRuntime] warmed %d material/geometry variants in %d ms %s" % [representatives.size(),
		Time.get_ticks_msec() - started, JSON.stringify(steps)])
	_warming = false


## Round 3 web engine (custom export template): material programs link on the browser's compiler threads while
## frames continue, and the renderer skips an element until its program is ready. This is the number still linking.
## The stock template links every program before drawing it and always reports 0.
static func linking_programs() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)


## True once the round 3 engine has started any program in the background (the stock template never does).
static func async_programs() -> bool:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION) > 0


## Keeps the loading page animating until every requested program has linked (or the limit passes).
func _wait_for_programs(limit_ms: int) -> void:
	var t := trace_start()
	var until := Time.get_ticks_msec() + limit_ms
	var waited := false
	while linking_programs() > 0 and Time.get_ticks_msec() < until:
		waited = true
		await get_tree().process_frame
	if waited:
		trace_end("linking_programs", t)
	if linking_programs() > 0:
		push_warning("[WebRuntime] %d programs still linking after %d ms" % [linking_programs(), limit_ms])


func _in_camera(geometry: GeometryInstance3D, camera: Camera3D) -> bool:
	if camera == null:
		return true
	var bounds: AABB = geometry.global_transform * geometry.get_aabb()
	if bounds.has_point(camera.global_position) or camera.is_position_in_frustum(bounds.get_center()):
		return true
	for endpoint in 8:
		if camera.is_position_in_frustum(bounds.get_endpoint(endpoint)):
			return true
	return false


func _material_key(material: Material) -> String:
	# Hundreds of differently coloured toon materials use the same program.
	# Drawing every colour adds minutes of redundant warm-up on ANGLE.
	var key := str(material.get_rid())
	if material is ShaderMaterial and material.shader != null:
		key = material.shader.code.sha256_text()
	elif material is BaseMaterial3D:
		# StandardMaterial programs depend on feature/flag switches and texture
		# presence. Colour, UV scale and roughness values are uniforms.
		var switches: Array = [material.get_class()]
		for property in material.get_property_list():
			if int(property["type"]) in [TYPE_BOOL, TYPE_INT]:
				switches.append([property["name"], material.get(property["name"])])
		for slot in BaseMaterial3D.TEXTURE_MAX:
			switches.append(material.get_texture(slot) != null)
		key = str(switches)
	if material.next_pass != null:
		key += ":" + _material_key(material.next_pass)
	return key

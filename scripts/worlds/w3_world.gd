extends WorldRoot
## W3 Gingerbread Grove root (WorldRoot + W3 dev helpers).
## Built by res://scripts/worlds/w3_bake.gd; never hand-edit W3.tscn (re-run the baker).
## Dev args (after --): --w3-fps[=seconds] logs Engine.get_frames_per_second() once a second, then quits.

var _fps_samples: Array[float] = []


func _ready() -> void:
	var web_trace_t := WebRuntime.trace_start()
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_arg("hide-hud"):
		show_entry_banner = false
	_tune_environment()
	super._ready()
	if dev and dev.has_arg("w3-fps"):
		var secs := float(dev.arg("w3-fps", "30"))
		if secs <= 1.0:
			secs = 30.0
		_measure_fps(secs)
	WebRuntime.trace_end("builder_ready:worlds/w3_world", web_trace_t)


## Local copy of the shared W3 environment with a clearer sky and lighter haze (key art: crisp blue sky,
## pastel distance). The shared resource in assets/shaders/environments is left untouched.


func _tune_environment() -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment.duplicate(true) as Environment
	# R1 visual blocker: every outdoor frame was pale lavender at half the key art's contrast (StoryCam_A sat 0.23,
	# val_std 0.075, mean 0.84 vs key art 07_w3_grove 0.40 / 0.19 / 0.73). Thinner neutral-blue haze, a warm and
	# weaker sky ambient (so shadows get real values), a teal-blue sky instead of pink, more contrast.
	env.fog_density = 0.18
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 300.0
	env.fog_light_color = Color(0.84, 0.91, 1.0)
	env.fog_aerial_perspective = 0.2
	# R1 visual major (re-check 11:00): frames still milky (mean value 0.84-0.92, val_std 0.05-0.13 vs key art 0.73 /
	# 0.19). Lower exposure, weaker sky ambient so shadows reach about 0.45 value, a stronger warm sun for long readable
	# shadows, a touch more contrast.
	env.ambient_light_sky_contribution = 0.4
	env.ambient_light_color = Color(0.98, 0.9, 0.85)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.8
	env.tonemap_white = 4.5
	env.adjustment_saturation = 1.3
	env.adjustment_contrast = 1.28
	env.adjustment_brightness = 0.9
	env.glow_intensity = 0.45
	env.ssao_intensity = 2.0
	var sky_mat := env.sky.sky_material as ShaderMaterial if env.sky else null
	if sky_mat:
		sky_mat.set_shader_parameter("top_color", Color(0.2, 0.5, 0.88))
		sky_mat.set_shader_parameter("horizon_color", Color(0.78, 0.88, 0.97))
		sky_mat.set_shader_parameter("haze_color", Color(1.0, 0.96, 0.9))
		sky_mat.set_shader_parameter("haze_strength", 0.22)
		sky_mat.set_shader_parameter("gradient_power", 0.55)
		sky_mat.set_shader_parameter("bottom_color", Color(0.8, 0.88, 0.95))
		sky_mat.set_shader_parameter("cloud_coverage", 0.55)
		sky_mat.set_shader_parameter("cloud_light", Color(1.0, 0.98, 0.95))
		sky_mat.set_shader_parameter("cloud_shade", Color(0.82, 0.87, 0.97))
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_energy = 2.0
		sun.light_color = Color(1.0, 0.9, 0.74)
	# Terrain shadows: deeper cool-violet instead of pale lavender (rest of the world: w3_level.toon()).
	var tm := get_node_or_null("Terrain/Mesh") as MeshInstance3D
	if tm and tm.material_override is ShaderMaterial:
		(tm.material_override as ShaderMaterial).set_shader_parameter("shadow_tint", Color(0.42, 0.4, 0.6))
	we.environment = env


func _measure_fps(secs: float) -> void:
	await get_tree().create_timer(4.0).timeout
	var t := 0.0
	while t < secs:
		await get_tree().create_timer(1.0).timeout
		t += 1.0
		var f := Engine.get_frames_per_second()
		_fps_samples.append(f)
		print("[W3 fps] t=%d fps=%.1f" % [int(t), f])
	var mn := 1e9
	var sum := 0.0
	for f in _fps_samples:
		mn = minf(mn, f)
		sum += f
	print("[W3 fps] RESULT samples=%d avg=%.1f min=%.1f size=%s vsync=%d" % [_fps_samples.size(), sum / _fps_samples.size(), mn,
		str(get_viewport().get_visible_rect().size), DisplayServer.window_get_vsync_mode()])
	get_tree().quit()

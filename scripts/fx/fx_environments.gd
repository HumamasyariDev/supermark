class_name FxEnvironments
extends RefCounted
## Look-development presets per area: Environment (tonemap, glow, SSAO, depth haze, colour
## adjustment), the painterly sky material, and recommended sun settings.
## Saved copies live in res://assets/shaders/environments/env_<ID>.tres (built by VFXLab's builder).
## Runtime use from a world script:
##   FxEnvironments.apply(self, "W1")   # configures the WorldEnvironment and the sun DirectionalLight3D it finds

const IDS := ["HUB", "W1", "W2", "W3", "BOSS"]


static func sky_params(id: String) -> Dictionary:
	match id:
		"HUB":
			# Seen through the stained-glass window: a honeyed evening.
			return {"top_color": Color(0.24, 0.27, 0.5), "horizon_color": Color(0.98, 0.72, 0.45), "bottom_color": Color(0.3, 0.2, 0.16),
				"haze_color": Color(1.0, 0.78, 0.55), "sun_color": Color(1.0, 0.8, 0.5), "cloud_light": Color(1.0, 0.82, 0.62),
				"cloud_shade": Color(0.55, 0.45, 0.62), "cloud_coverage": 0.45, "sun_size": 0.05, "sun_glow": 0.55, "haze_strength": 0.7}
		"W1":
			return {"top_color": Color(0.2, 0.48, 0.95), "horizon_color": Color(0.7, 0.86, 0.99), "bottom_color": Color(0.45, 0.6, 0.4),
				"haze_color": Color(0.96, 0.95, 0.9), "sun_color": Color(1.0, 0.95, 0.8), "cloud_light": Color(1.0, 1.0, 0.98),
				"cloud_shade": Color(0.58, 0.68, 0.92), "cloud_coverage": 0.46, "sun_size": 0.035, "sun_glow": 0.3, "haze_strength": 0.4,
				"haze_height": 0.1}
		"W2":
			return {"top_color": Color(0.38, 0.42, 0.95), "horizon_color": Color(0.88, 0.8, 0.98), "bottom_color": Color(0.8, 0.76, 0.95),
				"haze_color": Color(0.98, 0.92, 0.98), "sun_color": Color(1.0, 0.92, 0.75), "cloud_light": Color(1.0, 1.0, 1.0),
				"cloud_shade": Color(0.66, 0.62, 0.92), "cloud_coverage": 0.6, "sun_size": 0.04, "sun_glow": 0.35, "haze_strength": 0.5,
				"cloud_scale": 0.9}
		"W3":
			return {"top_color": Color(0.55, 0.62, 0.95), "horizon_color": Color(1.0, 0.8, 0.86), "bottom_color": Color(0.72, 0.55, 0.5),
				"haze_color": Color(1.0, 0.87, 0.85), "sun_color": Color(1.0, 0.9, 0.78), "cloud_light": Color(1.0, 0.94, 0.97),
				"cloud_shade": Color(0.95, 0.66, 0.8), "cloud_coverage": 0.5, "sun_size": 0.04, "sun_glow": 0.35, "haze_strength": 0.6,
				"paint_steps": 3.0}
		"BOSS":
			return {"top_color": Color(0.17, 0.12, 0.33), "horizon_color": Color(1.0, 0.52, 0.3), "bottom_color": Color(0.3, 0.16, 0.25),
				"haze_color": Color(1.0, 0.6, 0.38), "sun_color": Color(1.0, 0.62, 0.32), "cloud_light": Color(1.0, 0.62, 0.42),
				"cloud_shade": Color(0.3, 0.2, 0.4), "cloud_coverage": 0.68, "sun_size": 0.06, "sun_glow": 0.7, "haze_strength": 0.65,
				"cloud_speed": 0.02, "streak_amount": 0.55, "paint_steps": 3.0, "cloud_softness": 0.12}
	return {}


static func sun_settings(id: String) -> Dictionary:
	# rotation_degrees for a DirectionalLight3D, colour, energy and shadow tuning.
	match id:
		"HUB":
			return {"rotation_degrees": Vector3(-38, 140, 0), "color": Color(1.0, 0.82, 0.6), "energy": 1.3}
		"W1":
			return {"rotation_degrees": Vector3(-48, -35, 0), "color": Color(1.0, 0.94, 0.82), "energy": 1.45}
		"W2":
			return {"rotation_degrees": Vector3(-55, 25, 0), "color": Color(1.0, 0.95, 0.88), "energy": 1.5}
		"W3":
			return {"rotation_degrees": Vector3(-42, -60, 0), "color": Color(1.0, 0.9, 0.82), "energy": 1.4}
		"BOSS":
			return {"rotation_degrees": Vector3(-14, 160, 0), "color": Color(1.0, 0.66, 0.42), "energy": 1.6}
	return {"rotation_degrees": Vector3(-50, -30, 0), "color": Color.WHITE, "energy": 1.3}


static func make_sky_material(id: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/sky.gdshader")
	var p := sky_params(id)
	for k in p:
		m.set_shader_parameter(k, p[k])
	return m


static func make(id: String) -> Environment:
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = make_sky_material(id)
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.85
	e.ambient_light_energy = 1.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_normalized = false
	e.glow_intensity = 0.55
	e.glow_strength = 1.0
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 0.95
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.6
	e.ssao_power = 1.4
	e.ssao_light_affect = 0.15
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_depth_begin = 30.0
	e.fog_depth_end = 220.0
	e.fog_depth_curve = 1.4
	e.fog_density = 0.85
	e.fog_sky_affect = 0.0
	e.fog_aerial_perspective = 0.55
	e.fog_light_energy = 1.0
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.05
	e.adjustment_saturation = 1.12
	match id:
		"HUB":
			e.fog_light_color = Color(0.55, 0.38, 0.28)
			e.fog_depth_begin = 12.0
			e.fog_depth_end = 70.0
			e.fog_density = 0.45
			e.fog_aerial_perspective = 0.0
			e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			e.ambient_light_color = Color(0.55, 0.42, 0.36)
			e.ambient_light_energy = 0.7
			e.glow_intensity = 0.8
			e.glow_hdr_threshold = 0.8
			e.ssao_intensity = 2.0
			e.adjustment_saturation = 1.1
			e.tonemap_exposure = 1.05
		"W1":
			e.fog_light_color = Color(0.74, 0.85, 0.97)
			e.fog_density = 0.7
		"W2":
			e.fog_light_color = Color(0.84, 0.8, 0.98)
			e.fog_density = 0.7
			e.fog_depth_begin = 25.0
			e.fog_depth_end = 180.0
			e.ambient_light_energy = 1.1
			e.tonemap_exposure = 1.05
		"W3":
			e.fog_light_color = Color(1.0, 0.86, 0.88)
			e.adjustment_saturation = 1.15
		"BOSS":
			e.fog_light_color = Color(0.85, 0.5, 0.45)
			e.fog_depth_begin = 20.0
			e.fog_depth_end = 160.0
			e.fog_aerial_perspective = 0.7
			e.glow_intensity = 0.8
			e.adjustment_contrast = 1.1
			e.adjustment_saturation = 1.08
	return e


static func load_env(id: String) -> Environment:
	var path := "res://assets/shaders/environments/env_%s.tres" % id
	if ResourceLoader.exists(path):
		return load(path) as Environment
	return make(id)


## Configure a world: sets the first WorldEnvironment's environment and the first DirectionalLight3D's look.
static func apply(root: Node, id: String, adjust_sun := true) -> void:
	var we := _find(root, "WorldEnvironment") as WorldEnvironment
	if we == null:
		we = WorldEnvironment.new()
		we.name = "WorldEnvironment"
		root.add_child(we)
	we.environment = load_env(id)
	if not adjust_sun:
		return
	var sun := _find(root, "DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		return
	var s := sun_settings(id)
	sun.rotation_degrees = s["rotation_degrees"]
	sun.light_color = s["color"]
	sun.light_energy = s["energy"]
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 120.0
	sun.light_angular_distance = 1.5


static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null

extends WorldRoot
## W1 Huff & Puff Hollow root (WorldRoot contract). Applies the W1 look (VFX preset plus the level plan's
## golden-afternoon sun) before WorldRoot spawns the player. Dev: --w1-fps=<seconds> logs the frame rate.

const SUN_ROT := Vector3(-28, -70, 0)  # W1_amendments R1.2: low 3/4 key from the west-south-west

var _fps_samples: PackedFloat32Array = PackedFloat32Array()
var _fps_t := 0.0
var _fps_window := 0.0
var _proc_ms := 0.0
var _phys_ms := 0.0


func _ready() -> void:
	_apply_look()
	var dev0 := get_node_or_null("/root/Dev")
	if dev0 and dev0.has_arg("hide-hud"):
		show_entry_banner = false
	super._ready()
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_arg("w1bot"):
		var bot := Node.new()
		bot.name = "W1Bot"
		bot.set_script(load("res://scripts/worlds/w1_bot.gd"))
		add_child(bot)
	if dev and dev.has_arg("w1cam"):
		# Dev review camera: --w1cam=x,y,z,tx,ty,tz[,fov]
		var v := String(dev.arg("w1cam", "")).split(",")
		if v.size() >= 6:
			var cam := Camera3D.new()
			cam.name = "W1ReviewCam"
			cam.fov = float(v[6]) if v.size() > 6 else 55.0
			cam.far = 600.0
			add_child(cam)
			cam.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			cam.look_at(Vector3(float(v[3]), float(v[4]), float(v[5])))
			cam.current = true
			set_meta("review_cam", cam)
	_maybe_intro(dev)
	if dev and dev.has_arg("w1-fps"):
		_fps_window = float(dev.arg("w1-fps", "30"))
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(1920, 1080)
		Engine.max_fps = 0
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0)
		var skip := String(dev.arg("w1-skip", ""))
		if "terrain" in skip:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.45, 0.7, 0.3)
			for mi in get_node("Terrain").find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = sm
		if "level" in skip:
			get_node("Level").process_mode = Node.PROCESS_MODE_DISABLED
		if "interp" in skip:
			get_node("Level").physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if "enemies" in skip:
				for e in get_tree().get_nodes_in_group("enemy"):
					e.process_mode = Node.PROCESS_MODE_DISABLED
			if "acorns" in skip:
				for e in get_tree().get_nodes_in_group("acorn"):
					e.process_mode = Node.PROCESS_MODE_DISABLED
			if "wind" in skip:
				for e in get_tree().get_nodes_in_group("wind_zone"):
					e.process_mode = Node.PROCESS_MODE_DISABLED
			if "fx" in skip:
				for e in get_node("Level").find_children("*", "GPUParticles3D", true, false):
					e.process_mode = Node.PROCESS_MODE_DISABLED
					(e as GPUParticles3D).emitting = false)
		if "shadow" in skip:
			(get_node("Sun") as DirectionalLight3D).shadow_enabled = false
		if "ssao" in skip or "env" in skip:
			var we := get_node("WorldEnvironment") as WorldEnvironment
			we.environment.ssao_enabled = false
			if "env" in skip:
				we.environment.glow_enabled = false
				we.environment.fog_enabled = false
				we.environment.volumetric_fog_enabled = false
				we.environment.ssil_enabled = false
				we.environment.sdfgi_enabled = false


func _apply_look() -> void:
	FxEnvironments.apply(self, "W1", false)
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		var e := we.environment.duplicate() as Environment
		# Golden late afternoon: warm haze only past ~70 m, a little more colour.
		# Fix round 1 (visual critic r1: zenith sampled a milky #AFC5DA, thin wisps, no peach band): a saturated
		# palette-blue zenith, a warm peach haze band, fat painterly cumulus, warmer fog that starts further out.
		e.fog_light_color = Color("f2d2a8")  # fix round 2 (visual r1): warmer golden haze
		e.fog_depth_begin = 70.0
		e.fog_depth_end = 280.0
		e.fog_aerial_perspective = 0.15  # fix round 2: less grey mid-frame band
		if e.sky and e.sky.sky_material is ShaderMaterial:
			var sm := (e.sky.sky_material as ShaderMaterial).duplicate() as ShaderMaterial
			sm.set_shader_parameter("top_color", Color("3e9be0"))
			sm.set_shader_parameter("horizon_color", Color("9ed3f2"))
			sm.set_shader_parameter("haze_color", Color("ffd6a0"))
			sm.set_shader_parameter("haze_height", 0.09)
			sm.set_shader_parameter("haze_strength", 0.42)
			sm.set_shader_parameter("gradient_power", 0.36)
			sm.set_shader_parameter("sun_color", Color("ffe2b0"))
			sm.set_shader_parameter("sun_glow", 0.3)
			sm.set_shader_parameter("cloud_coverage", 0.4)  # fix round 2 (visual r1): fewer, bigger, rounder cumulus
			sm.set_shader_parameter("cloud_scale", 1.3)
			sm.set_shader_parameter("cloud_softness", 0.05)
			sm.set_shader_parameter("cloud_light", Color("fffaf0"))
			sm.set_shader_parameter("cloud_shade", Color("c9c3e6"))
			sm.set_shader_parameter("cloud_opacity", 1.0)
			sm.set_shader_parameter("paint_steps", 4.0)
			var sky := e.sky.duplicate() as Sky
			sky.sky_material = sm
			e.sky = sky
		e.adjustment_saturation = 1.14
		e.ambient_light_energy = 0.95
		we.environment = e
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = SUN_ROT
		sun.light_color = Color("ffd49a")
		sun.light_energy = 1.76  # fix round 2: +10 %
		sun.shadow_enabled = true
		sun.shadow_blur = 1.5
		sun.light_angular_distance = 1.5
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 140.0


func _process(delta: float) -> void:
	if has_meta("review_cam"):
		(get_meta("review_cam") as Camera3D).current = true
	if _fps_window <= 0.0:
		return
	_fps_t += delta
	if _fps_t > 3.0:
		_fps_samples.append(1.0 / maxf(delta, 1e-4))
		_proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if _fps_t >= _fps_window + 3.0:
		var lo := 1e9
		var sum := 0.0
		for f in _fps_samples:
			lo = minf(lo, f)
			sum += f
		print("[W1 fps] window=%.0fs samples=%d mean=%.1f min=%.1f size=%s vsync=off process_ms=%.2f physics_ms=%.2f nodes=%d gpu=%s" % [_fps_window, _fps_samples.size(), sum / maxf(1.0, _fps_samples.size()), lo, get_window().size, _proc_ms / maxf(1.0, _fps_samples.size()), _phys_ms / maxf(1.0, _fps_samples.size()), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), RenderingServer.get_video_adapter_name()])
		_fps_window = 0.0
		get_tree().quit()


## R1.2 / R1.11: on the first entry (no W1 truffle yet, not a test run) StoryCam_Intro holds for 6 s while Sir Reginald
## stands on Hollow Tor, lowers his spyglass, inflates and floats off north-east; then control returns to the follow camera.
## --w1-intro forces it (for captures).
func _maybe_intro(dev: Node) -> void:
	var game := get_node_or_null("/root/Game")
	var forced: bool = dev != null and dev.has_arg("w1-intro")
	if not forced:
		if dev and (dev.call("is_test_run") or dev.has_arg("w1bot") or dev.has_arg("spawn") or dev.has_arg("mission") or dev.has_arg("w1cam") or dev.has_arg("w1-fps")):
			return
		if game:
			for id in ["W1-1", "W1-2", "W1-3", "W1-4", "W1-5", "W1-6", "W1-7", "W1-8"]:
				if game.call("has_truffle", id):
					return
	var cam := get_node_or_null("StoryCams/StoryCam_Intro_v2") as Camera3D  # R2.9 (inside the Page Gate arch)
	if cam == null:
		cam = get_node_or_null("StoryCams/StoryCam_Intro") as Camera3D
	if cam == null:
		return
	var prev := get_viewport().get_camera_3d()
	cam.current = true
	# R3.9 / fix round 1: no HUD during the intro.
	var ui := get_node_or_null("/root/UI")
	var hud_off := func(on: bool) -> void:
		if ui and ui.has_method("set_hud_visible"):
			ui.call("set_hud_visible", on)
	get_tree().process_frame.connect(func() -> void: hud_off.call(false), CONNECT_ONE_SHOT)
	get_tree().create_timer(0.2).timeout.connect(func() -> void: hud_off.call(false))
	get_tree().create_timer(6.6).timeout.connect(func() -> void: hud_off.call(true))
	var boss: Node3D = null
	var path := "res://assets/characters/wolf_boss/wolf_boss.glb"
	if ResourceLoader.exists(path):
		boss = Node3D.new()
		boss.name = "CameoReginald"
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		boss.add_child(inst)
		add_child(boss)
		# Fix round 1 (fun critic r1: hidden behind the apple tree, then a 30 px dot): he stands on the Tor's west rim at
		# 1.4x, facing the intro camera, chest swelling before he floats off (W1Dress.CAM_CLEAR keeps the sightline clear).
		boss.global_position = Vector3(31, W1Terrain.height(31, 2), 2)
		boss.rotation.y = atan2(-1.5 - 31.0, 55.5 - 2.0)
		boss.scale = Vector3.ONE * 1.4
		var bp := W1Poser.attach(inst)
		if bp:
			bp.set_mode("talk")
		var tw := boss.create_tween()
		tw.tween_interval(2.2)
		tw.tween_callback(func() -> void:
			if bp:
				bp.set_mode("huff"))
		tw.tween_property(boss, "scale", Vector3(1.8, 1.6, 1.8), 0.6).set_trans(Tween.TRANS_BACK)
		tw.tween_property(boss, "global_position", boss.global_position + Vector3(14, 22, -18), 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(boss, "rotation_degrees:y", boss.rotation_degrees.y + 200.0, 3.2)
		tw.tween_callback(boss.queue_free)
	# R2.9: Mak drops in from 9 m at t 1.0 s and lands in the hero shot.
	if player and player.has_method("respawn"):
		var spawn_x := player.global_transform
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if is_instance_valid(player):
				player.call("respawn", Transform3D(spawn_x.basis, spawn_x.origin + Vector3(0, 8.6, 0))))
	# R3.9: a 1.6 s face close-up of the landed hero at 2.2-3.8 s.
	var face := get_node_or_null("StoryCams/StoryCam_Intro_face") as Camera3D
	if face and not (dev and dev.has_arg("w1-intro-wide")):
		var a01 := get_node_or_null("Level/A01") as Node3D  # fix round 1: an acorn covered a quarter of the face shot
		get_tree().create_timer(2.2).timeout.connect(func() -> void:
			if cam.current:
				face.current = true
				if a01:
					a01.visible = false)
		get_tree().create_timer(3.8).timeout.connect(func() -> void:
			if a01:
				a01.visible = true
			if face.current:
				cam.current = true)
	var hold := 6.6 if not (dev and dev.has_arg("capture")) else 60.0
	get_tree().create_timer(hold).timeout.connect(func() -> void:
		if is_instance_valid(prev):
			prev.current = true
		elif player:
			var c := player.find_child("*Camera*", true, false)
			if c is Camera3D:
				(c as Camera3D).current = true)

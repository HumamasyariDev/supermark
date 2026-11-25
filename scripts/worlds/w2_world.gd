extends WorldRoot
## W2 Beanstalk Skyway root (WorldRoot contract). Before WorldRoot spawns the player it builds the level
## deterministically from res://assets/environment/w2/w2_level.json (a copy of data/levels/W2.json):
## geometry and collision (w2_build.gd), gameplay nodes (w2_play.gd) and motion (w2_life.gd).
## Dev: --w2-fps=<seconds> logs the frame rate and quits; --w2-noplay builds geometry only.

const LEVEL_JSON := "res://assets/environment/w2/w2_level.json"
const Build := preload("res://scripts/worlds/w2_build.gd")
const Play := preload("res://scripts/worlds/w2_play.gd")
const Life := preload("res://scripts/worlds/w2_life.gd")
const Fix2 := preload("res://scripts/worlds/w2_fix2.gd")

var level_data: Dictionary = {}
var builder
var play
var life: Node

var _fps_samples: PackedFloat32Array = PackedFloat32Array()
var _fps_t := 0.0
var _fps_window := 0.0


func _ready() -> void:
	var web_trace_t := WebRuntime.trace_start()
	var t0 := Time.get_ticks_msec()
	level_data = _load_json()
	Fix2.patch_data(level_data)
	_apply_look()
	builder = Build.new()
	builder.build(self, level_data)
	var dev := get_node_or_null("/root/Dev")
	if not (dev and dev.has_arg("w2-noplay")):
		play = Play.new()
		play.build(self, level_data, builder)
	life = Life.new()
	life.name = "W2Life"
	add_child(life)
	life.setup(self, level_data, builder, play)
	var fix2 := Fix2.new()
	fix2.name = "W2Fix2"
	add_child(fix2)
	fix2.setup(self, builder, play, life)
	print("[W2] built in %d ms" % (Time.get_ticks_msec() - t0))
	if dev and dev.has_arg("w2-verify"):
		var v: Node = (load("res://scripts/worlds/w2_verify.gd") as GDScript).new()
		v.name = "W2Verify"
		get_tree().root.add_child.call_deferred(v)
	super._ready()
	if dev and dev.has_arg("w2-fps"):
		_fps_window = float(dev.arg("w2-fps", "30"))
	WebRuntime.trace_end("builder_ready:worlds/w2_world", web_trace_t)


func _load_json() -> Dictionary:
	var f := FileAccess.open(LEVEL_JSON, FileAccess.READ)
	if f == null:
		push_error("[W2] missing " + LEVEL_JSON)
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _apply_look() -> void:
	FxEnvironments.apply(self, "W2", false)
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		var e := we.environment.duplicate() as Environment
		# Golden-hour wonder (grade fix r1: the old 0.55 depth fog washed the sky to #CBC8D7 and halved the
		# saturation; now a light distant haze, no fog on the sky, warmer neutral ambient, more contrast).
		e.fog_enabled = true
		e.fog_light_color = Color("d6c4f0")
		e.fog_density = 0.22
		e.fog_depth_begin = 90.0
		e.fog_depth_end = 380.0
		e.fog_sky_affect = 0.04
		e.fog_aerial_perspective = 0.1
		e.fog_height = -12.0
		e.fog_height_density = 0.05
		e.adjustment_enabled = true
		e.adjustment_saturation = 1.2
		e.adjustment_contrast = 1.12
		e.ambient_light_color = Color("f2e8da")
		e.ambient_light_sky_contribution = 0.55
		e.ambient_light_energy = 0.5
		# Grade fix r2 (visual critic: exterior saturation 0.14-0.16 and luma std 0.11 against the key art's 0.25
		# and 0.23): lower exposure, a harder filmic white, more contrast, no fog on the sky, fewer sky clouds.
		e.fog_sky_affect = 0.0
		e.tonemap_exposure = 0.95
		e.tonemap_white = 4.5
		e.adjustment_contrast = 1.2
		e.adjustment_saturation = 1.12
		if e.sky and e.sky.sky_material is ShaderMaterial:
			var sk := e.sky.duplicate() as Sky
			var sm := (e.sky.sky_material as ShaderMaterial).duplicate() as ShaderMaterial
			sm.set_shader_parameter("cloud_coverage", 0.42)
			sm.set_shader_parameter("haze_strength", 0.3)
			sm.set_shader_parameter("cloud_light", Color("fff1e6"))
			sm.set_shader_parameter("cloud_shade", Color("9a8ad8"))
			sk.sky_material = sm
			e.sky = sk
		we.environment = e
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = Vector3(-27.0, -67.5, 0.0)
		sun.light_color = Color("ffc98a")
		sun.light_energy = 1.7
		sun.shadow_enabled = true
		sun.shadow_blur = 1.5
		sun.light_angular_distance = 1.2
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 140.0


func _process(delta: float) -> void:
	if _fps_window <= 0.0:
		return
	_fps_t += delta
	if _fps_t > 3.0:
		_fps_samples.append(Engine.get_frames_per_second())
	if int(_fps_t) != int(_fps_t - delta):
		print("[W2 perf] t=%d fps=%d proc=%.1fms phys=%.1fms draws=%d prims=%d objs=%d nodes=%d" % [int(_fps_t), Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	if _fps_t >= _fps_window + 3.0:
		var lo := 1e9
		var sum := 0.0
		for f in _fps_samples:
			lo = minf(lo, f)
			sum += f
		print("[W2 fps] window=%.0fs samples=%d mean=%.1f min=%.1f size=%s" % [_fps_window, _fps_samples.size(), sum / maxf(1.0, _fps_samples.size()), lo, get_viewport().get_visible_rect().size])
		_fps_window = 0.0
		get_tree().quit()

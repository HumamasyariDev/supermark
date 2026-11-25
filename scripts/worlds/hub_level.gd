class_name HubLevel
extends Node3D
const GoldenHatLib := preload("res://scripts/objects/golden_hat.gd")
## Mak Manor's Grand Library (HUB): assembles the procedural shell (HubArchitecture), generated props, portals,
## Bramwell, the secret HUB-1 truffle, acorns, ladders, lighting and ambient life at runtime. Deterministic.
## Plan: Docs/levels/HUB.md, data/levels/HUB.json. Owner: hub builder.

const PORTAL_SCENE := "res://scenes/objects/StorybookPortal.tscn"
const WOLF_DOOR_SCENE := "res://scenes/objects/WolfDoor.tscn"
const NPC_SCENE := "res://scenes/objects/NPCTalker.tscn"
const TRUFFLE_SCENE := "res://scenes/objects/Truffle.tscn"
const ACORN_SCENE := "res://scenes/objects/Acorn.tscn"
const CRATE_SCENE := "res://scenes/objects/BreakableCrate.tscn"
const P := "res://assets/props/"

const ACORNS := {
	"AG01_clock_ring": [Vector3(0.99, 0.6, -1.40), Vector3(2.40, 0.6, 0.01), Vector3(2.40, 0.6, 1.99), Vector3(0.99, 0.6, 3.40), Vector3(-0.99, 0.6, 3.40), Vector3(-2.40, 0.6, 1.99), Vector3(-2.40, 0.6, 0.01), Vector3(-0.99, 0.6, -1.40)],  # r1 visual: rotated 22.5 deg so no acorn hides the plate
	"AG02_pawprint_line": [Vector3(-1.2, 0.6, 9.6), Vector3(-2.2, 0.6, 8.8), Vector3(-3.2, 0.6, 8.0), Vector3(-4.2, 0.6, 7.2), Vector3(-5.2, 0.6, 6.4)],
	"AG03_mantel": [Vector3(-14.3, 2.5, -1.6), Vector3(-14.3, 2.5, -0.8), Vector3(-14.3, 2.5, 0.0), Vector3(-14.3, 2.5, 0.8), Vector3(-14.3, 2.5, 1.6)],
	"AG04_cornice_a": [Vector3(14.92, 9.00, 2.90), Vector3(14.68, 9.00, 3.93), Vector3(13.99, 9.00, 5.94), Vector3(13.54, 9.00, 6.90), Vector3(13.03, 9.00, 7.83), Vector3(12.45, 9.00, 8.72)],
	"AG05_gap_arc": [Vector3(11.30, 9.40, 10.17), Vector3(10.17, 9.40, 11.30), Vector3(8.93, 9.40, 12.30)],
	"AG06_cornice_b": [Vector3(7.37, 9.00, 13.29), Vector3(6.42, 9.00, 13.78), Vector3(5.45, 9.00, 14.19), Vector3(4.44, 9.00, 14.54), Vector3(3.42, 9.00, 14.81)],
	"AG07_nook": [Vector3(-2.0, 0.6, -10.6), Vector3(-1.0, 0.6, -10.6), Vector3(0.0, 0.6, -10.6), Vector3(1.0, 0.6, -10.6), Vector3(2.0, 0.6, -10.6)],
	"AG08_bay_arc": [Vector3(10.8, 5.1, -2.94), Vector3(9.56, 5.1, -1.7), Vector3(9.1, 5.1, 0.0), Vector3(9.56, 5.1, 1.7), Vector3(10.8, 5.1, 2.94)],
	"AG09_balcony_ring": [Vector3(0.0, 5.1, 17.6), Vector3(1.91, 5.1, 18.7), Vector3(1.91, 5.1, 20.9), Vector3(0.0, 5.1, 22.0), Vector3(-1.91, 5.1, 20.9), Vector3(-1.91, 5.1, 18.7)],
	"AG12_vine": [Vector3(8.9, 1.6, 7.0), Vector3(8.9, 2.8, 7.0), Vector3(8.9, 4.0, 7.0), Vector3(8.9, 5.2, 7.0)],
	"AG13_updraft": [Vector3(-9.34, 2.2, 6.54), Vector3(-9.34, 3.4, 6.54), Vector3(-9.34, 4.6, 6.54), Vector3(-9.34, 5.8, 6.54)],
	# Fix r2 (feel major) tried and reverted: take-offs 1.2 m and 1.7 m from fin B both failed 3/3 with the hub
	# autopilot (the player only wall-slides when falling; the first kick then comes too early to reach fin A).
	"AG10_chimney_column": [Vector3(-7.4, 6.0, 12.12), Vector3(-7.4, 7.2, 12.12), Vector3(-7.4, 8.4, 12.12), Vector3(-7.4, 9.6, 12.12)],
}

const BRAMWELL_LINES := {
	0: "The wolf went straight for The Three Little Pigs, sir. Mind the draughts.",
	3: "Jack's beanstalk will see you now. I have dusted the rope off its posts.",
	7: "The gingerbread book smells of burnt sugar. Do be careful, sir.",
	12: "That knocker has started growling. I shall put the kettle on for afterwards.",
}
const BRAMWELL_SECRET := "Your grandfather kept something on the top balcony. Look up, where the cornice fell. A good long run-up, sir."
const BRAMWELL_SECRET_LOCKED := "Your grandfather always said the floor remembers more than the shelves do, sir."
const BRAMWELL_FIRST := "Ah, sir. The wolf has been. And one of the sheep in Book One looks rather... large."

var portals: Dictionary = {}
var wolf_door: Node3D
var bramwell: Node3D
var hub_truffle: Node3D
var clock: Node3D
var activities: Node3D
var _locks: Dictionary = {}  # world id -> Node3D lock dressing
var _dioramas: Dictionary = {}  # world id -> Node3D
var _flicker: Array[OmniLight3D] = []
var _flicker_base: Array[float] = []
var _chandelier: Node3D
var _tapestry: MeshInstance3D
var _t := 0.0
var _bell_jar: Node3D
var _pendulum: Node3D
## HubEvents holds the lock drops until the return flights end, then plays a gate ceremony per newly open book.
var hold_locks := false


func _ready() -> void:
	var web_trace_t := WebRuntime.trace_start()
	var t0 := Time.get_ticks_msec()
	_tick_ms = t0
	# Clean story frames: --hide-hud also suppresses the WorldRoot entry banner (children are ready before the root).
	var dev0 := get_node_or_null("/root/Dev")
	if dev0 and bool(dev0.call("has_arg", "hide-hud")) and "show_entry_banner" in get_parent():
		get_parent().set("show_entry_banner", false)
	if dev0 and String(dev0.call("arg", "cam", "")).begins_with("StoryCam_A_v"):
		_place_at_intro_mark.call_deferred()
	HubArchitecture.build(self)
	_tick("HubArchitecture.build(self)")
	_environment()
	_tick("_environment()")
	_rug_and_decals()
	_tick("_rug_and_decals()")
	_stained_glass()
	_tick("_stained_glass()")
	_entrance_doors()
	_tick("_entrance_doors()")
	_fireplace()
	_tick("_fireplace()")
	_props()
	_tick("_props()")
	clock = HubTruffleClock.new()
	clock.name = "TruffleClock"
	clock.position = Vector3(0, 0, 1.0)
	add_child(clock)
	_portals()
	_tick("_portals()")
	_wolf_door()
	_tick("_wolf_door()")
	_ladders()
	_tick("_ladders()")
	_bramwell()
	_tick("_bramwell()")
	_hub_truffle()
	_tick("_hub_truffle()")
	_acorns()
	_tick("_acorns()")
	activities = HubActivities.new()
	activities.name = "Activities"
	activities.level = self
	add_child(activities)
	_tick("activities")
	var ev := HubEvents.new()
	ev.name = "Events"
	ev.level = self
	add_child(ev)
	_tick("events")
	if HubSpiral.wanted(self):
		var sp := HubSpiral.new()
		sp.level = self
		add_child(sp)
		_tick("spiral")
	_lights()
	_tick("_lights()")
	_ambient()
	_tick("_ambient()")
	if ResourceLoader.exists("res://scripts/worlds/hub_backdrop.gd"):
		var bd := Node3D.new()
		bd.name = "Backdrop"
		bd.set_script(load("res://scripts/worlds/hub_backdrop.gd"))
		add_child(bd)
		_tick("backdrop")
	# Set dressing seen through the west windows and the French doors (hub_vista.gd, 19 Oct 2026).
	var vista := (load("res://scripts/worlds/hub_vista.gd") as GDScript).new() as Node3D
	vista.name = "Vista"
	add_child(vista)
	_tick("vista")
	print("[Hub] built in %d ms" % (Time.get_ticks_msec() - t0))
	var game := get_node_or_null("/root/Game")
	if game and game.has_signal("truffle_collected"):
		game.truffle_collected.connect(_on_truffle)
	_update_bramwell()
	_greeting.call_deferred()
	var dev := get_node_or_null("/root/Dev")
	_fps_log = dev != null and bool(dev.call("has_arg", "hub-fps"))
	if dev and (bool(dev.call("has_arg", "hub-test")) or bool(dev.call("has_arg", "hub-seq"))):
		var ap := HubAutopilot.new()
		ap.name = "HubAutopilot"
		add_child(ap)
	if HubVerify.wanted(dev):
		var hv := HubVerify.new()
		hv.name = "HubVerify"
		add_child(hv)
	WebRuntime.trace_end("builder_ready:worlds/hub_level", web_trace_t)


## Hero-shot captures (StoryCam_A_v2/A_v3) show Mak where the opening leaves him: Intro_Mark (R1.1).


func _place_at_intro_mark() -> void:
	await get_tree().physics_frame
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var m := get_parent().get_node_or_null("Spawns/Intro_Mark") as Node3D
	if p and m and p.has_method("respawn"):
		p.call("respawn", m.global_transform)


# ------------------------------------------------------------------ helpers

var _tick_ms := 0


func _tick(what: String) -> void:
	var now := Time.get_ticks_msec()
	if _tick_ms > 0 and now - _tick_ms > 120:
		print("[Hub] %s took %d ms" % [what, now - _tick_ms])
	_tick_ms = now


func _glb(path: String) -> PackedScene:
	return HubAssets.scene(path)


## Places a generated prop: node at `pos` with yaw (0 faces north/-Z), the glTF wrapped in a Visual turned 180.
func prop(path: String, pos: Vector3, yaw_deg: float, scl: Variant = 1.0, boxes: Array = [], node_name := "") -> Node3D:
	var root := Node3D.new()
	root.name = node_name if node_name != "" else path.get_file().get_basename().capitalize().replace(" ", "")
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	add_child(root)
	var ps := _glb(path)
	if ps:
		var v := ps.instantiate() as Node3D
		v.name = "Visual"
		v.rotation_degrees.y = 180.0
		v.scale = scl if scl is Vector3 else Vector3.ONE * float(scl)
		root.add_child(v)
	if not boxes.is_empty():
		var body := HubArchitecture.static_body(root, "Collision")
		for bx in boxes:
			# [size, centre]
			HubKit.add_box_collision(body, null, bx[0], Transform3D(Basis(), bx[1]))
	return root


func _omni(pos: Vector3, color: Color, energy: float, rng: float, shadow := false, flicker := false, parent: Node3D = null) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadow
	# Only the sun, the fire and the stained glass light the haze, so the window shafts stay crisp.
	l.light_volumetric_fog_energy = 0.0
	if shadow:
		l.shadow_bias = 0.08
		l.shadow_normal_bias = 1.5
		# Fix r2 (performance): dual paraboloid (2 passes) instead of a cube map (6 passes) for the chandelier
		# and the fire, which cover most of the room.
		l.omni_shadow_mode = OmniLight3D.SHADOW_CUBE if OS.has_feature("web") else OmniLight3D.SHADOW_DUAL_PARABOLOID
	(parent if parent else self).add_child(l)
	if flicker:
		_flicker.append(l)
		_flicker_base.append(energy)
	return l


func _flame(parent: Node3D, pos: Vector3, size := 0.09) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size * 1.7)
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = _flame_tex()
	mat.albedo_color = Color(1.6, 1.05, 0.5)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = pos
	parent.add_child(m)
	return m


static var _ftex: Texture2D


static func _flame_tex() -> Texture2D:
	if _ftex:
		return _ftex
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 32:
			var u := (float(x) - 15.5) / 16.0
			var v := float(y) / 63.0
			var w := 0.15 + 0.85 * sin(v * PI * 0.92) * (1.0 - v * 0.35)
			var d := absf(u) / maxf(w, 0.01)
			var a := clampf(1.0 - d, 0.0, 1.0) * clampf(v * 3.0, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1.0, 0.75 + 0.25 * (1.0 - v), 0.4 + 0.5 * (1.0 - v) * (1.0 - d), a))
	_ftex = ImageTexture.create_from_image(img)
	return _ftex


func _label(parent: Node3D, text: String, pos: Vector3, size := 64, color := Color("3b2416")) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(1.0, 0.9, 0.7, 0.6)
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ environment

func _environment() -> void:
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		return
	var env: Environment = (we.environment.duplicate() as Environment) if we.environment else Environment.new()
	we.environment = env
	# Own copy of the sky material, so the hub's colour script can repaint it per preset (r1 visual: muddy beige sky).
	if env.sky and env.sky.sky_material:
		var sky := env.sky.duplicate() as Sky
		sky.sky_material = env.sky.sky_material.duplicate()
		env.sky = sky
	set_sky("LP0")
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# r1 visual round 2: a cool sky-blue ambient (#8FA6C8, R1.10 / LP0) against the warm key and the walnut.
	env.ambient_light_color = Color("8fa6c8")
	env.ambient_light_energy = 0.5  # amendments R1.10
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_hdr_threshold = 0.9
	env.glow_bloom = 0.08
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.8
	env.ssil_enabled = true
	env.ssil_intensity = 0.8
	# Depth haze only reaches the backdrop (the hall is 32 m across).
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	# r1 visual round 2: the amber haze washed the countryside beige; a cool blue-lilac aerial haze instead.
	env.fog_light_color = Color("8c93b8")
	env.fog_light_energy = 1.0
	env.fog_density = 0.3
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 460.0
	env.fog_depth_curve = 1.4
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_albedo = Color("ffe2b8")
	env.volumetric_fog_emission = Color(0.05, 0.03, 0.02)
	env.volumetric_fog_emission_energy = 0.4
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.04
	# Volumetric haze only inside the hall, so the sun shafts glow but the countryside stays clear.
	if OS.has_feature("web"):
		# Compatibility retains the authored depth haze and window-shaft meshes.
		# Local volumetric scattering has no WebGL implementation.
		env.volumetric_fog_enabled = false
	else:
		var fv := FogVolume.new()
		fv.name = "HallHaze"
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_CYLINDER
		# r1 visual: the haze started at the floor and turned the far floor milky beyond 10 m. It now starts at y 1.5.
		fv.size = Vector3(33.0, 20.0, 33.0)
		fv.position = Vector3(0, 11.5, 0)
		var fm := FogMaterial.new()
		fm.density = 0.02
		fm.albedo = Color("ffe2b8")
		fm.edge_fade = 0.05
		fv.material = fm
		add_child(fv)
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = Vector3(-14, -75, 0)
		sun.light_color = Color("ffd39a")
		sun.light_energy = 2.2
		sun.shadow_enabled = true
		# Fix r2 (QA major, frame-time headroom): 4 splits over 70 m re-rendered the whole room and backdrop four
		# times for the sun alone. The playfield is 16 m in radius plus the balcony: 2 splits over 42 m.
		sun.directional_shadow_max_distance = 42.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.shadow_bias = 0.04
		sun.shadow_normal_bias = 1.0
		sun.light_volumetric_fog_energy = 6.0
		sun.shadow_blur = 1.5


## Sky colours per lighting preset (R2.8; LP0 from the r1 visual critique: blue top, warm horizon, light haze).
const SKY_PRESETS := {
	"LP0": [Color("4f8de0"), Color("ffe4bc"), 0.16, Color("fff6e8"), Color("b4c4f0"), 0.2],
	"LP1": [Color("6f98d0"), Color("ffcf8f"), 0.32, Color("fff0d6"), Color("b4a0e0"), 0.42],
	"LP2": [Color("5d78b8"), Color("ffb070"), 0.36, Color("ffe2c4"), Color("a68fd0"), 0.48],
	"LP3": [Color("2c2f5c"), Color("8e86c0"), 0.25, Color("c7c4e8"), Color("4a3f78"), 0.7],
	"LP4": [Color("8ab8e8"), Color("fff0c8"), 0.25, Color("ffffff"), Color("c4b8f0"), 0.35],
}


func set_sky(preset: String) -> void:
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment if get_parent() else null
	if we == null or we.environment == null or we.environment.sky == null:
		return
	var m := we.environment.sky.sky_material as ShaderMaterial
	if m == null or not SKY_PRESETS.has(preset):
		return
	var sp: Array = SKY_PRESETS[preset]
	m.set_shader_parameter("top_color", sp[0])
	m.set_shader_parameter("horizon_color", sp[1])
	m.set_shader_parameter("haze_strength", sp[2])
	m.set_shader_parameter("haze_color", (sp[1] as Color).lightened(0.15))
	m.set_shader_parameter("cloud_light", sp[3])
	m.set_shader_parameter("cloud_shade", sp[4])
	m.set_shader_parameter("cloud_coverage", sp[5])
	m.set_shader_parameter("bottom_color", Color("6f8a5a") if preset != "LP3" else Color("2a2a40"))
	# r1 visual round 2: keep the warm horizon in the bottom band only, so the upper sky reads blue.
	m.set_shader_parameter("haze_height", 0.06)
	# Fix r1b: at 0.5 the blue only began well above the horizon, so balcony views (looking level) read grey-beige.
	m.set_shader_parameter("gradient_power", 0.32)
	m.set_shader_parameter("sun_glow", 0.3 if preset != "LP3" else 0.15)


# ------------------------------------------------------------------ decor

func _rug_and_decals() -> void:
	var rug := HubKit.Buf.new()
	HubKit.disc(rug, 6.0, 0.015, 96, Vector3(0, 0, 1.0), 1.0)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/environment/hub/hub_rug.gdshader")
	sm.set_shader_parameter("centre", Vector2(0.0, 1.0))
	# Amendments R1.10: teal field with a gold border for value contrast against the walnut floor.
	sm.set_shader_parameter("field", Color("2e6b6b"))
	sm.set_shader_parameter("field_dark", Color("1d4a4b"))
	sm.set_shader_parameter("teal", Color("7a1f2e"))
	HubArchitecture.mi(self, rug.commit(), sm, "Rug", Transform3D.IDENTITY, false)
	# PZ04 muddy wolf paw prints from the broken doors to Book 1 (every 0.9 m along a spline).
	var path := [Vector3(0.6, 0, 15.2), Vector3(-0.8, 0, 12.0), Vector3(-3.0, 0, 9.4), Vector3(-5.6, 0, 7.6), Vector3(-6.4, 0, 6.6)]
	var curve := Curve3D.new()
	for p in path:
		curve.add_point(p)
	var length := curve.get_baked_length()
	var paw := _paw_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.15, 0.09, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.4
	var d := 0.0
	var side := 1.0
	while d < length:
		var p := curve.sample_baked(d)
		var p2 := curve.sample_baked(minf(d + 0.1, length))
		var dir := (p2 - p).normalized()
		var right := dir.cross(Vector3.UP).normalized()
		var m := HubArchitecture.mi(self, paw, mat, "", Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), p + right * side * 0.16 + Vector3(0, 0.022, 0)), false)
		m.name = "Paw"
		side = -side
		d += 0.45
	# PZ03 loose pages on the floor.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# r1 visual round 2: the pages read as pure-white quads; darker parchment with printed lines, half as many.
	# Fix r2 (visual minor): the pages still read as barcodes competing with the pickups. Half as many again, cream
	# #EAD8B0 with three soft grey-brown lines.
	var page_mat := HubArchitecture.flat_toon(Color("ead8b0"), 0.1, 0.05)
	var pb := HubKit.Buf.new()
	var ink := HubKit.Buf.new()
	for i in 40:
		if i % 4 != 0:
			rng.randf()
			rng.randf()
			continue
		var r := sqrt(rng.randf()) * 11.0
		var th := rng.randf() * 360.0
		var p := HubKit.polar(r, th, 0.03)
		if absf(p.x) < 3.0 and p.z < -2.5 and p.z > -13.0:
			continue
		if Vector2(p.x, p.z - 1.0).length() < 1.9:
			continue
		var pbs := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08))
		HubKit.rounded_box(pb, Vector3(0.24, 0.006, 0.32), 0.002, Transform3D(pbs, p))
		for ln in 3:
			HubKit.rounded_box(ink, Vector3(0.15 if ln < 2 else 0.09, 0.002, 0.01), 0.0005, Transform3D(pbs, p + pbs * Vector3(-0.01, 0.004, -0.07 + 0.06 * float(ln))))
	HubArchitecture.mi(self, pb.commit(), page_mat, "LoosePages", Transform3D.IDENTITY, false)
	HubArchitecture.mi(self, ink.commit(), HubArchitecture.flat_toon(Color("a08a6a"), 0.05, 0.0), "LoosePageInk", Transform3D.IDENTITY, false)


func _paw_mesh() -> ArrayMesh:
	var b := HubKit.Buf.new()
	var pads := [[Vector3(0, 0, 0.02), 0.07], [Vector3(-0.065, 0, -0.07), 0.03], [Vector3(-0.022, 0, -0.1), 0.03], [Vector3(0.022, 0, -0.1), 0.03], [Vector3(0.065, 0, -0.07), 0.03]]
	for pd in pads:
		HubKit.disc(b, pd[1], 0.0, 12, pd[0])
	return b.commit()


func _stained_glass() -> void:
	# Pointed-arch window (A02 opening 352.8-7.2, y 9-14.5) with an emissive stained-glass panel and a walnut frame.
	var outline := PackedVector2Array()
	var w := 1.9
	outline.append(Vector2(-w, 9.05))
	outline.append(Vector2(w, 9.05))
	outline.append(Vector2(w, 12.6))
	for i in range(1, 12):
		var a := float(i) / 12.0
		var x := w * (1.0 - a)
		var y := 12.6 + 1.85 * sin(acos(1.0 - a)) * 1.0
		outline.append(Vector2(x * (1.0 - a * 0.15), y))
	outline.append(Vector2(0.0, 14.45))
	for i in range(11, 0, -1):
		var a := float(i) / 12.0
		var x := -w * (1.0 - a)
		var y := 12.6 + 1.85 * sin(acos(1.0 - a))
		outline.append(Vector2(x * (1.0 - a * 0.15), y))
	outline.append(Vector2(-w, 12.6))
	var tri := Geometry2D.triangulate_polygon(outline)
	if tri.is_empty():
		print("HUBKIT glass fail ", outline)
	var b := HubKit.Buf.new()
	var base := b.v.size()
	for p in outline:
		b.vert(Vector3(p.x, p.y, -15.98), Vector3.BACK, Vector2((p.x + w) / (2.0 * w), 1.0 - (p.y - 9.05) / 5.4))
	for k in range(0, tri.size(), 3):
		b.tri(base + tri[k], base + tri[k + 1], base + tri[k + 2])
	var glass := StandardMaterial3D.new()
	glass.albedo_texture = load("res://assets/textures/stained_glass.webp")
	glass.emission_enabled = true
	glass.emission_texture = glass.albedo_texture
	glass.emission = Color.WHITE
	glass.emission_energy_multiplier = 2.2
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.uv1_scale = Vector3(1.0, 1.0, 1.0)
	var gm := HubArchitecture.mi(self, b.commit(), glass, "StainedGlass", Transform3D.IDENTITY, false)
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Plaster spandrels close the square opening around the arch.
	var sp := HubKit.Buf.new()
	var rect := PackedVector2Array([Vector2(-2.1, 12.4), Vector2(2.1, 12.4), Vector2(2.1, 14.6), Vector2(-2.1, 14.6)])
	var clipped := Geometry2D.clip_polygons(rect, outline)
	for poly in clipped:
		if Geometry2D.is_polygon_clockwise(poly):
			continue
		var t2 := Geometry2D.triangulate_polygon(poly)
		if t2.is_empty():
			print("HUBKIT spandrel fail ", poly)
		var b0 := sp.v.size()
		for p in poly:
			sp.vert(Vector3(p.x, p.y, -15.97), Vector3.BACK, Vector2(p.x, p.y))
		for k in range(0, t2.size(), 3):
			sp.tri(b0 + t2[k], b0 + t2[k + 1], b0 + t2[k + 2])
	HubArchitecture.mi(self, sp.commit(), HubArchitecture.toon("damask_wallpaper", Color(0.95, 0.72, 0.68), 0.45), "GlassSpandrels")
	# Lead and walnut tracery.
	var fr := HubKit.Buf.new()
	for i in outline.size():
		var p0 := outline[i]
		var p1 := outline[(i + 1) % outline.size()]
		var a3 := Vector3(p0.x, p0.y, -15.9)
		var b3 := Vector3(p1.x, p1.y, -15.9)
		var d := b3 - a3
		if d.length() < 0.01:
			continue
		HubKit.rounded_box(fr, Vector3(d.length() + 0.2, 0.22, 0.25), 0.07, Transform3D(HubArchitecture.along(d), (a3 + b3) * 0.5))
	HubKit.rounded_box(fr, Vector3(4.6, 0.3, 0.6), 0.1, Transform3D(Basis(), Vector3(0, 8.95, -15.75)))
	HubArchitecture.mi(self, fr.commit(), HubArchitecture.toon("bookshelf_wood", Color(0.62, 0.42, 0.3), 0.7), "GlassFrame")
	var lead := HubKit.Buf.new()
	for x in [-0.95, 0.0, 0.95]:
		HubKit.rounded_box(lead, Vector3(0.05, 4.2, 0.05), 0.02, Transform3D(Basis(), Vector3(x, 11.15, -15.95)))
	for y in [10.3, 11.6, 12.8]:
		HubKit.rounded_box(lead, Vector3(3.8, 0.05, 0.05), 0.02, Transform3D(Basis(), Vector3(0, y, -15.95)))
	HubArchitecture.mi(self, lead.commit(), HubArchitecture.iron(), "GlassLead")
	# The coloured pool on the stair: a projector spot shaped like the window.
	var spot := SpotLight3D.new()
	spot.name = "StainedGlassSpot"
	spot.light_color = Color("e9b7ff")
	spot.light_energy = 6.0
	spot.spot_range = 24.0
	spot.spot_angle = 16.0
	spot.spot_attenuation = 0.6
	spot.light_projector = load("res://assets/textures/stained_glass.webp")
	spot.shadow_enabled = true
	spot.light_volumetric_fog_energy = 2.5
	add_child(spot)
	spot.look_at_from_position(Vector3(0, 13.5, -15.2), Vector3(0, 0.0, -2.0), Vector3.UP)


func _entrance_doors() -> void:
	# A24: the front doors at z 16.1. Owner (19 Oct 2026): "why does the exit look so broken? weird" (a 1 m leaf hung askew
	# in a 4 m opening, the frame never met the leaves, a black panel behind). Now two full-width panelled leaves that
	# fill the frame: the right one shut, the left one huffed ajar 24 degrees on its hinges, so a believable gap shows
	# the sunny porch, steps and drive outside. The wolf's paw prints still lead in through that gap.
	var wood := HubArchitecture.toon("bookshelf_wood", Color(0.84, 0.58, 0.4), 0.8)
	var panel_wood := HubArchitecture.toon("bookshelf_wood", Color(0.56, 0.35, 0.24), 0.8)
	var b := HubKit.Buf.new()
	var pb := HubKit.Buf.new()
	var iron := HubKit.Buf.new()
	var brass := HubKit.Buf.new()
	var body := HubArchitecture.static_body(self, "EntranceDoors")
	# The closed right leaf keeps the old door block; the whole opening stays closed just behind the door plane
	# (r1 QA blocker: Mak walked out past the frame posts).
	HubKit.add_box_collision(body, null, Vector3(2.1, 4.0, 0.3), Transform3D(Basis(), Vector3(0, 2.0, 16.25)), "DoorBlock")
	HubKit.add_box_collision(body, null, Vector3(5.0, 4.4, 0.5), Transform3D(Basis(), Vector3(0, 2.2, 16.45)), "EntranceFrame")
	for sx in [-1.0, 1.0]:
		HubKit.add_box_collision(body, null, Vector3(0.4, 4.2, 0.8), Transform3D(Basis(), Vector3(sx * 2.1, 2.1, 15.95)), "EntrancePost")
	var open_deg := 30.0
	for side: float in [-1.0, 1.0]:
		# Hinge on the frame post's inner face; the leaf runs toward the middle. Positive yaw swings it into the hall.
		var ang := deg_to_rad(open_deg) if side < 0.0 else 0.0
		var hinge := Transform3D(Basis(Vector3.UP, ang * -side), Vector3(side * 1.9, 0.0, 16.1))
		var w := 1.88
		var dx := -side
		HubKit.rounded_box(b, Vector3(w, 3.9, 0.14), 0.04, hinge * Transform3D(Basis(), Vector3(dx * w * 0.5, 1.97, 0.0)))
		for fz in [-1.0, 1.0]:
			# Raised panels (tall upper, short lower) and a lock rail on both faces.
			HubKit.rounded_box(pb, Vector3(w - 0.5, 1.95, 0.05), 0.03, hinge * Transform3D(Basis(), Vector3(dx * w * 0.5, 2.62, fz * 0.08)))
			HubKit.rounded_box(pb, Vector3(w - 0.5, 0.95, 0.05), 0.03, hinge * Transform3D(Basis(), Vector3(dx * w * 0.5, 0.82, fz * 0.08)))
			for hy in [0.55, 3.35]:
				HubKit.rounded_box(iron, Vector3(0.75, 0.1, 0.03), 0.02, hinge * Transform3D(Basis(), Vector3(dx * 0.4, hy, fz * 0.085)))
			HubKit.rounded_box(brass, Vector3(0.07, 0.34, 0.07), 0.03, hinge * Transform3D(Basis(), Vector3(dx * (w - 0.2), 1.25, fz * 0.13)))
			HubKit.rounded_box(brass, Vector3(0.16, 0.24, 0.02), 0.02, hinge * Transform3D(Basis(), Vector3(dx * (w - 0.2), 1.25, fz * 0.085)))
		if side < 0.0:
			# The ajar leaf stands in the hall, so it gets its own collision.
			HubKit.add_box_collision(body, null, Vector3(w, 3.9, 0.2), hinge * Transform3D(Basis(), Vector3(dx * w * 0.5, 1.97, 0.0)), "AjarLeaf")
	# Door frame: posts, lintel and a threshold, flush with the leaves.
	HubKit.rounded_box(b, Vector3(4.6, 0.4, 0.8), 0.08, Transform3D(Basis(), Vector3(0, 4.15, 15.95)))
	for sx in [-1.0, 1.0]:
		HubKit.rounded_box(b, Vector3(0.4, 4.2, 0.8), 0.08, Transform3D(Basis(), Vector3(sx * 2.1, 2.1, 15.95)))
	HubKit.rounded_box(b, Vector3(4.2, 0.06, 0.7), 0.02, Transform3D(Basis(), Vector3(0, 0.02, 16.15)))
	HubArchitecture.mi(self, b.commit(), wood, "DoorLeaves")
	HubArchitecture.mi(self, pb.commit(), panel_wood, "DoorPanels")
	HubArchitecture.mi(self, iron.commit(), HubArchitecture.iron(), "DoorHinges")
	HubArchitecture.mi(self, brass.commit(), HubArchitecture.brass(), "DoorHandle")
	# Afternoon light spilling in through the gap.
	var leak := _omni(Vector3(-0.9, 1.5, 15.4), Color(1.0, 0.85, 0.6), 1.2, 4.0)
	leak.name = "DoorLeak"
	# Outside the gap: a stone porch under the balcony and three steps down to the drive (seen, never walked).
	var porch := HubKit.Buf.new()
	HubKit.rounded_box(porch, Vector3(5.6, 1.6, 4.2), 0.06, Transform3D(Basis(), Vector3(0, -0.8, 18.5)))
	for k in 3:
		HubKit.rounded_box(porch, Vector3(4.8 - 0.3 * float(k), 1.6, 0.62), 0.05, Transform3D(Basis(), Vector3(0, -0.8 - 0.5 * float(k + 1), 20.9 + 0.6 * float(k))))
	HubArchitecture.mi(self, porch.commit(), HubArchitecture.toon("castle_stone", Color(0.95, 0.88, 0.78), 0.4), "Porch").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _fireplace() -> void:
	# Chimney breast is architecture; the generated fireplace stands in front of it facing east.
	# Fix r2 (visual major): the 1.6 x-scale inflated the stones into grey pillows and the model read bleached. Uniform
	# 1.25 (collision narrowed to match), warm sandstone tint and a hearth uplight.
	var fp := prop(P + "hub/fireplace/fireplace.glb", Vector3(-14.75, 0, 0), -90.0, Vector3(1.25, 1.25, 1.25),
		[[Vector3(1.6, 2.1, 3.45), Vector3(0, 1.05, 0.7)], [Vector3(3.45, 0.25, 1.0), Vector3(0, 1.95, -0.2)]], "Fireplace")
	matte_surfaces(fp, 0.0, 0.9, Color("d9b98a"))
	var up := _omni(Vector3(-14.1, 0.35, 0), Color("ffb060"), 1.2, 4.0)
	up.name = "HearthUplight"
	# The fire: glowing logs, flame cards and a flickering light, behind a guard.
	var fire := Node3D.new()
	fire.name = "Fire"
	fire.position = Vector3(-14.25, 0.0, 0)
	add_child(fire)
	var logs := HubKit.Buf.new()
	for i in 3:
		HubKit.rounded_box(logs, Vector3(0.22, 0.22, 1.2), 0.1, Transform3D(Basis(Vector3.UP, deg_to_rad(-20.0 + 20.0 * i)), Vector3(0.0, 0.14 + (0.18 if i == 1 else 0.0), -0.3 + 0.3 * i)))
	HubArchitecture.mi(fire, logs.commit(), HubKit.emissive(Color(0.9, 0.35, 0.1), 1.6, "embers"), "Logs")
	for i in 7:
		var f := _flame(fire, Vector3(randf_range(-0.1, 0.15), 0.55 + randf() * 0.15, -0.55 + i * 0.18), 0.45 + randf() * 0.25)
		f.set_meta("phase", randf() * TAU)
		f.add_to_group("hub_flame")
	var fl := _omni(Vector3(-13.9, 1.0, 0), Color("ff8a3d"), 4.0, 10.0, true, true)
	fl.name = "FireLight"
	fl.light_volumetric_fog_energy = 1.0
	var sparks := GPUParticles3D.new()
	sparks.amount = 24
	sparks.lifetime = 1.8
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.2, 0.1, 0.6)
	pm.direction = Vector3(0.3, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.4, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	sparks.process_material = pm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.04, 0.04)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.albedo_color = Color(2.0, 1.0, 0.3)
	sq.material = smat
	sparks.draw_pass_1 = sq
	sparks.position = Vector3(0.1, 0.7, 0)
	fire.add_child(sparks)
	# r1 visual round 2: fire bounce on the hall side of the wingbacks (their velvet backs crushed to near black).
	_omni(Vector3(-10.2, 1.4, 0.0), Color("ffb070"), 0.8, 6.5)
	# Hearth-safe: a hazard-free blocker in front of the flames.
	var guard := HubArchitecture.static_body(self, "FireGuard")
	HubKit.add_box_collision(guard, null, Vector3(0.3, 1.0, 2.6), Transform3D(Basis(), Vector3(-13.6, 0.5, 0)))


func _props() -> void:
	# Armchairs angled toward the hearth (HJ7: seat 0.55, back 1.4).
	for zc in [-3.2, 3.2]:
		var pos := Vector3(-12.3, 0, zc)
		var to_fire := Vector3(-14.6, 0, 0) - pos
		var yaw := rad_to_deg(atan2(-to_fire.x, -to_fire.z))
		prop(P + "hub/wingback_armchair_v4/wingback_armchair_v4.glb", pos, yaw, 1.05,
			[[Vector3(1.2, 0.6, 0.85), Vector3(0, 0.3, 0)], [Vector3(1.2, 1.5, 0.28), Vector3(0, 0.75, 0.32)]], "Armchair")
	prop(P + "hub/tea_table_set_v4/tea_table_set_v4.glb", Vector3(-10.2, 0, 0.4), 70.0, 1.3, [[Vector3(1.0, 0.5, 1.0), Vector3(0, 0.25, 0)]], "TeaTable")
	prop(P + "hub/library_globe/library_globe.glb", Vector3(-4.8, 0, -3.8), 30.0, 1.0, [[Vector3(0.8, 1.4, 0.8), Vector3(0, 0.7, 0)]], "Globe")
	var gc_pos := HubKit.polar(14.55, 320.0)
	var gclock := prop(P + "hub/grandfather_clock_v3/grandfather_clock_v3.glb", gc_pos, HubKit.yaw_facing_centre(320.0), 1.1, [[Vector3(0.82, 2.7, 0.55), Vector3(0, 1.35, 0)]], "GrandfatherClock")
	_pendulum = gclock.find_child("pendulum*", true, false) as Node3D
	# Free-standing tall bookcases flank the nook and the entrance.
	for th in [166.5, 193.5]:
		prop(P + "hub/bookshelf_tall/bookshelf_tall.glb", HubKit.polar(14.9, th), HubKit.yaw_facing_centre(th), 0.95, [[Vector3(2.2, 3.8, 1.0), Vector3(0, 1.9, 0)]], "Bookcase")
	# Reading desk with a green banker's lamp (procedural: no generated mesh requested for it).
	var desk := Node3D.new()
	desk.name = "ReadingDesk"
	desk.position = Vector3(4.8, 0, -3.8)
	desk.rotation_degrees.y = -30.0
	add_child(desk)
	var db := HubKit.Buf.new()
	HubKit.rounded_box(db, Vector3(1.6, 0.1, 0.8), 0.04, Transform3D(Basis(), Vector3(0, 0.8, 0)))
	for sx in [-0.7, 0.7]:
		for sz in [-0.32, 0.32]:
			HubKit.turned(db, PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.07, 0.1), Vector2(0.045, 0.4), Vector2(0.06, 0.75)]), 10, Vector3(sx, 0, sz))
	HubKit.rounded_box(db, Vector3(0.5, 0.06, 0.36), 0.02, Transform3D(Basis(Vector3.UP, 0.3), Vector3(-0.3, 0.88, 0.05)))
	HubArchitecture.mi(desk, db.commit(), HubArchitecture.toon("bookshelf_wood", Color(0.7, 0.48, 0.34), 0.9), "Desk")
	var lamp := HubKit.Buf.new()
	HubKit.turned(lamp, PackedVector2Array([Vector2(0.12, 0.85), Vector2(0.1, 0.9), Vector2(0.025, 0.92), Vector2(0.02, 1.2)]), 12)
	HubArchitecture.mi(desk, lamp.commit(), HubArchitecture.brass(), "LampStand").position = Vector3(0.45, 0, -0.1)
	var shade := HubKit.Buf.new()
	HubKit.rounded_box(shade, Vector3(0.42, 0.12, 0.2), 0.06, Transform3D(Basis(), Vector3(0.45, 1.24, -0.1)))
	HubArchitecture.mi(desk, shade.commit(), HubKit.emissive(Color("2f8f4a"), 0.6, "banker_green"), "LampShade")
	_omni(Vector3(0.45, 1.05, -0.1), Color(1.0, 0.86, 0.6), 1.2, 3.2, false, false, desk)
	var dbody := HubArchitecture.static_body(desk, "Collision")
	HubKit.add_box_collision(dbody, null, Vector3(1.6, 0.9, 0.8), Transform3D(Basis(), Vector3(0, 0.45, 0)))
	# Book piles on the gallery (PZ01) and the fallen cornice books under the gap (PZ02).
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var piles := HubKit.Buf.new()
	var pile_body := HubArchitecture.static_body(self, "BookPiles")
	var th := 15.0
	while th < 360.0:
		var skip := false
		for g in [[95.0, 125.0], [168.0, 192.0], [196.0, 228.0], [244.0, 296.0], [348.0, 372.0], [50.0, 68.0]]:
			if th > g[0] and th < g[1]:
				skip = true
		if not skip:
			_book_pile(piles, HubKit.polar(14.85, th, GALLERY_Y), rng, rng.randi_range(2, 6))
		th += rng.randf_range(9.0, 16.0)
	for i in 6:
		var p := HubKit.polar(rng.randf_range(13.8, 14.9), 132.0 + rng.randf_range(0.0, 12.0), GALLERY_Y)
		_book_pile(piles, p, rng, rng.randi_range(3, 8), true)
	HubKit.add_box_collision(pile_body, null, Vector3(1.6, 0.45, 1.0), Transform3D(Basis(Vector3.UP, deg_to_rad(-138.0)), HubKit.polar(14.4, 138.0, GALLERY_Y + 0.22)))
	var books := HubArchitecture.mi(self, piles.commit(), HubKit.vcol_mat(0.75, "hub_piles"), "BookPiles")
	books.material_override = HubKit.vcol_mat(0.75, "hub_piles")
	# Potted ferns on the landing ends (PZ05) and stone urns on the outdoor balcony (PZ06).
	for sx in [-3.6, 3.6]:
		_fern(Vector3(sx, 2.25, -8.25))
	for sx in [-4.2, 4.2]:
		_urn(Vector3(sx, GALLERY_Y, 18.4))
	# AG11 tea-chest crate on the gallery. Fix r1b (QA ledger): its 5 acorns are one-off ledger acorns (AG11_crate),
	# burst out when the chest breaks; they used to be plain respawning acorns outside the ledger.
	var ps := _glb(CRATE_SCENE)
	if ps:
		var crate := ps.instantiate() as Node3D
		crate.set("acorns", 0)
		crate.set("size", 0.8)
		crate.position = Vector3(6.85, GALLERY_Y, 12.89)
		crate.name = "TeaChest"
		add_child(crate)
		if crate.has_signal("broken"):
			crate.connect("broken", func(_c: Node) -> void: _burst_ledger("AG11_crate", Vector3(6.85, GALLERY_Y, 12.89), 0.9, 5))
	# Brass telescope on the balcony aimed at the wolf tower (procedural).
	_telescope(Vector3(3.0, GALLERY_Y, 21.0))


const GALLERY_Y := 4.5


func _book_pile(b: HubKit.Buf, at: Vector3, rng: RandomNumberGenerator, n: int, toppled := false) -> void:
	var y := 0.0
	var yaw := rng.randf() * TAU
	for i in n:
		var w := rng.randf_range(0.3, 0.45)
		var dd := rng.randf_range(0.22, 0.32)
		var h := rng.randf_range(0.06, 0.1)
		var col: Color = HubArchitecture.BOOK_COLORS[rng.randi() % HubArchitecture.BOOK_COLORS.size()]
		yaw += rng.randf_range(-0.4, 0.4)
		var off := Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
		if toppled:
			off = Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
			y = 0.0 if rng.randf() < 0.5 else y
		HubKit.rounded_box(b, Vector3(w, h, dd), 0.02, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, rng.randf_range(-0.05, 0.05) if not toppled else rng.randf_range(-0.5, 0.5)), at + off + Vector3(0, y + h * 0.5, 0)), 1, col)
		HubKit.rounded_box(b, Vector3(w + 0.004, h * 0.8, dd * 0.92), 0.01, Transform3D(Basis(Vector3.UP, yaw), at + off + Vector3(0.012, y + h * 0.5, 0)), 1, Color("efe2c2"))
		y += h
	b.use_color = true


func _fern(at: Vector3) -> void:
	var n := Node3D.new()
	n.name = "Fern"
	n.position = at
	add_child(n)
	var pot := HubKit.Buf.new()
	HubKit.turned(pot, PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.3, 0.45), Vector2(0.34, 0.5), Vector2(0.3, 0.52)]), 16)
	HubArchitecture.mi(n, pot.commit(), HubArchitecture.flat_toon(Color("b8733a")), "Pot")
	var leaf := HubArchitecture.flat_toon(Color("4f9a3c"), 0.3, 0.2)
	var lb := HubKit.Buf.new()
	for i in 9:
		var a := TAU * float(i) / 9.0
		var tilt := 0.7 + 0.2 * float(i % 3)
		var bs := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -tilt)
		HubKit.rounded_box(lb, Vector3(0.14, 0.03, 0.7), 0.012, Transform3D(bs, Vector3(0, 0.6, 0) + bs * Vector3(0, 0, -0.33)))
	HubArchitecture.mi(n, lb.commit(), leaf, "Fronds")


func _urn(at: Vector3) -> void:
	var n := Node3D.new()
	n.name = "Urn"
	n.position = at
	add_child(n)
	var b := HubKit.Buf.new()
	HubKit.turned(b, PackedVector2Array([Vector2(0.28, 0.0), Vector2(0.22, 0.12), Vector2(0.14, 0.3), Vector2(0.3, 0.6), Vector2(0.4, 0.85), Vector2(0.36, 0.9)]), 18)
	HubArchitecture.mi(n, b.commit(), HubArchitecture.toon("castle_stone", Color(1.0, 0.95, 0.86), 1.2), "Urn")
	var fl := HubKit.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 10.0) + 99
	for i in 14:
		var p := Vector3(rng.randf_range(-0.3, 0.3), 0.95 + rng.randf() * 0.25, rng.randf_range(-0.3, 0.3))
		var c := Color("ff7fb0") if i % 3 == 0 else (Color("ffd23c") if i % 3 == 1 else Color("6dbe45"))
		HubKit.rounded_box(fl, Vector3(0.16, 0.12, 0.16), 0.06, Transform3D(Basis(), p), 1, c)
	fl.use_color = true
	HubArchitecture.mi(n, fl.commit(), HubKit.vcol_mat(0.6, "urn_flowers"), "Flowers")
	var body := HubArchitecture.static_body(n, "Collision")
	HubKit.add_cyl_collision(body, null, 0.4, 1.0, Vector3(0, 0.5, 0))


func _telescope(at: Vector3) -> void:
	var n := Node3D.new()
	n.name = "Telescope"
	n.position = at
	add_child(n)
	var target := Vector3(-140, 60, 380)
	var b := HubKit.Buf.new()
	for k in 3:
		var a := TAU * float(k) / 3.0
		var foot := Vector3(cos(a) * 0.45, 0, sin(a) * 0.45)
		var top := Vector3(0, 1.1, 0)
		var d := top - foot
		HubKit.rounded_box(b, Vector3(d.length(), 0.06, 0.06), 0.025, Transform3D(HubArchitecture.along(d), (foot + top) * 0.5))
	HubArchitecture.mi(n, b.commit(), HubArchitecture.toon("bookshelf_wood", Color(0.7, 0.48, 0.34), 0.9), "Tripod")
	var tube := Node3D.new()
	tube.position = Vector3(0, 1.15, 0)
	n.add_child(tube)
	var tb := HubKit.Buf.new()
	HubKit.lathe(tb, PackedVector2Array([Vector2(0.0, -0.6), Vector2(0.06, -0.6), Vector2(0.07, -0.2), Vector2(0.09, 0.2), Vector2(0.11, 0.7), Vector2(0.0, 0.7)]), 0.0, 360.0, 20.0, false, false, 50.0)
	var tm := HubArchitecture.mi(tube, tb.commit(), HubArchitecture.brass(), "Tube")
	tm.rotation_degrees.x = -90.0
	tube.look_at_from_position(at + Vector3(0, 1.15, 0), target, Vector3.UP)
	var body := HubArchitecture.static_body(n, "Collision")
	HubKit.add_cyl_collision(body, null, 0.4, 1.3, Vector3(0, 0.65, 0))
	var sign := HubAssets.scene("res://scenes/objects/SignPost.tscn")
	if sign:
		var talker := sign.instantiate() as Node3D
		talker.set("board_text", "Look")  # r1 visual: "Telescope" wrapped as "elescop/e" on the small board
		talker.set("speaker", "Telescope")
		talker.set("lines", PackedStringArray(["Through the brass eyepiece: a black tower on the far hills, wrapped in its own storm cloud.", "Something with a very large mouth paces the battlements, polishing a monocle."]))
		talker.set("talk_radius", 1.8)
		talker.position = Vector3(-0.9, 0, 0.4)
		talker.scale = Vector3.ONE * 0.6
		n.add_child(talker)


# ------------------------------------------------------------------ portals

func _portals() -> void:
	var specs := [
		{"world": "W1", "title": "The Three Little Pigs", "need": 0, "pos": Vector3(-7.07, 0, 7.07), "face": Vector3(0, 0, 10.5), "cover": Color("e9c45a"), "accent": Color("b84a32"), "glow": Color(1.0, 0.88, 0.55)},
		{"world": "W2", "title": "Jack and the Beanstalk", "need": 3, "pos": Vector3(7.07, 0, 7.07), "face": Vector3(0, 0, 10.5), "cover": Color("3e9a45"), "accent": Color("e8b23a"), "glow": Color(0.75, 1.0, 0.6)},
		{"world": "W3", "title": "Hansel and Gretel", "need": 7, "pos": Vector3(10.8, GALLERY_Y, 0.0), "face": Vector3(0, GALLERY_Y, 0.0), "cover": Color("b8733a"), "accent": Color("ff7fb0"), "glow": Color(1.0, 0.7, 0.85)},
	]
	var lectern := _glb(P + "hub/book_lectern/book_lectern.glb")
	var ps := HubAssets.scene(PORTAL_SCENE)
	for s in specs:
		var portal := ps.instantiate() as Node3D
		var wid: String = s["world"]
		portal.name = "Book_" + wid
		portal.set("world_id", wid)
		portal.set("book_title", s["title"])
		portal.set("required_truffles", s["need"])
		portal.set("cover_color", s["cover"])
		portal.set("accent_color", s["accent"])
		portal.set("page_glow", s["glow"])
		portal.set("visual_scene", lectern)
		portal.set("visual_scale", 0.85)
		portal.set("scale_factor", 0.95)
		var pos: Vector3 = s["pos"]
		var face: Vector3 = s["face"]
		var d := face - pos
		_dais(pos)
		portal.position = pos + Vector3(0, 0.4, 0)
		portal.rotation.y = atan2(-d.x, -d.z)
		add_child(portal)
		portals[wid] = portal
		# The open-book swirl reads as big opaque balls in the hero and title frames: finer, softer motes here.
		var sw := portal.get("_swirl") as GPUParticles3D
		if sw and sw.process_material is ParticleProcessMaterial:
			var spm := (sw.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
			spm.scale_min = 0.15  # r1 visual round 2: the swirl motes read as big blurry discs in the hero shot
			spm.scale_max = 0.28
			sw.process_material = spm
		_diorama(portal, wid)
		if int(s["need"]) > 0:
			_lock_dressing(portal, wid, int(s["need"]))
		var tl := _label(portal, s["title"], Vector3(0, 0.55, -0.62), 46, Color("ffc93c"))
		tl.rotation_degrees.y = 180.0
		# r1 visual round 2: storybook lettering (Cherry Swash, gold with an ink outline) instead of plain grey text.
		if ResourceLoader.exists("res://assets/fonts/cherryswash/CherrySwash-Bold.ttf"):
			tl.font = load("res://assets/fonts/cherryswash/CherrySwash-Bold.ttf")
		tl.outline_size = 14
		tl.outline_modulate = Color("3b2416")
		tl.double_sided = false  # fix r1b: from behind the dais the title read mirrored


## A27 walnut dais: two 0.2 m steps (r 1.8 and r 1.45), walkable from every side without a jump.
func _dais(at: Vector3) -> void:
	var b := HubKit.Buf.new()
	HubKit.turned(b, PackedVector2Array([Vector2(1.8, 0.0), Vector2(1.8, 0.16), Vector2(1.76, 0.2), Vector2(1.5, 0.2), Vector2(1.45, 0.24), Vector2(1.45, 0.36), Vector2(1.41, 0.4)]), 40, at)
	HubArchitecture.mi(self, b.commit(), HubArchitecture.toon("bookshelf_wood", Color(0.6, 0.42, 0.33), 1.0), "Dais")
	var g := HubKit.Buf.new()
	HubKit.lathe(g, HubKit.round_rect_profile(1.76, 1.82, 0.08, 0.13, 0.02, 0.02, 0.02, 0.02), 0.0, 360.0, 9.0, true, false, 40.0, 1.0, Color.WHITE, at)
	HubArchitecture.mi(self, g.commit(), HubArchitecture.brass(), "DaisBand")
	# r1 visual round 2: the step tops read as a flat pale band; burgundy velvet treads with brass nosings, as on
	# the clock dais.
	var vel := HubKit.Buf.new()
	HubKit.lathe(vel, HubKit.round_rect_profile(1.47, 1.74, 0.195, 0.215, 0.0, 0.0, 0.008, 0.008), 0.0, 360.0, 9.0, true, false, 40.0, 1.0, Color.WHITE, at)
	HubKit.lathe(vel, HubKit.round_rect_profile(0.0, 1.38, 0.395, 0.415, 0.0, 0.0, 0.008, 0.008), 0.0, 360.0, 9.0, true, false, 40.0, 1.0, Color.WHITE, at)
	HubArchitecture.mi(self, vel.commit(), HubArchitecture.flat_toon(Color("7a1f2e"), 0.55, 0.45), "DaisVelvet")
	var nose := HubKit.Buf.new()
	HubKit.lathe(nose, HubKit.round_rect_profile(1.74, 1.79, 0.17, 0.215, 0.01, 0.01, 0.01, 0.01), 0.0, 360.0, 9.0, true, false, 40.0, 1.0, Color.WHITE, at)
	HubKit.lathe(nose, HubKit.round_rect_profile(1.38, 1.44, 0.37, 0.415, 0.01, 0.01, 0.01, 0.01), 0.0, 360.0, 9.0, true, false, 40.0, 1.0, Color.WHITE, at)
	HubArchitecture.mi(self, nose.commit(), HubArchitecture.brass(), "DaisNosing")
	var body := HubArchitecture.static_body(self, "DaisCollision")
	HubKit.add_cyl_collision(body, null, 1.8, 0.2, at + Vector3(0, 0.1, 0))
	HubKit.add_cyl_collision(body, null, 1.45, 0.4, at + Vector3(0, 0.2, 0))


## Pop-up scenes standing on the open pages, made from the worlds' own generated meshes (key art 08).
func _diorama(portal: Node3D, wid: String) -> void:
	var d := Node3D.new()
	d.name = "PopUp"
	d.position = Vector3(0, 2.3, 0.02)
	d.rotation_degrees.x = 18.0
	portal.add_child(d)
	match wid:
		"W1":
			_dprop(d, P + "w1/windmill_body/windmill_body.glb", Vector3(-0.38, 0, 0.05), 0.09, 20.0)
			var sails := _dprop(d, P + "w1/windmill_sails/windmill_sails.glb", Vector3(-0.38, 1.12, -0.27), 0.09, 20.0)
			if sails:
				sails.add_to_group("hub_spin")
			_dprop(d, P + "w1/straw_house/straw_house.glb", Vector3(0.42, 0, 0.14), 0.08, -25.0)
			_dprop(d, P + "w1/apple_tree/apple_tree.glb", Vector3(0.08, 0, -0.26), 0.09, 0.0)
		"W2":
			var stalk := _dprop(d, P + "w2/beanstalk_segment/beanstalk_segment.glb", Vector3(0.0, 0, 0.0), 0.15, 0.0)
			if stalk:
				stalk.add_to_group("hub_sway")
			_dprop(d, P + "w2/jack_cottage/jack_cottage.glb", Vector3(0.48, 0, 0.16), 0.09, -30.0)
			_dprop(d, P + "w2/bean_flower/bean_flower.glb", Vector3(-0.48, 0, 0.14), 0.4, 30.0)
		"W3":
			_dprop(d, P + "w3/gingerbread_cottage/gingerbread_cottage.glb", Vector3(-0.2, 0, 0.0), 0.09, 15.0)
			_dprop(d, P + "w3/lollipop_tree/lollipop_tree.glb", Vector3(0.45, 0, -0.14), 0.25, -10.0)
			_dprop(d, P + "w3/lollipop_tree/lollipop_tree_mint.glb", Vector3(0.56, 0, 0.2), 0.2, 20.0)
			_dprop(d, P + "w3/gumdrop/gumdrop.glb", Vector3(-0.6, 0, 0.24), 0.2, 0.0)
	_dioramas[wid] = d
	var unlocked := bool(portal.get("is_open"))
	d.scale = _diorama_scale(wid)
	d.visible = true
	if not unlocked:
		_sepia(d)
	if _world_count(wid) >= 8:
		var sp := ObjSvc.sparkles(d, Color(1.0, 0.85, 0.4), 24, 0.7, 0.12, 1.4, 0.3)
		sp.position = Vector3(0, 0.4, 0)
	# Rim light on each pop-up (LT_diorama_rim).
	var rim := SpotLight3D.new()
	rim.light_color = Color("ffe7a3")
	rim.light_energy = 1.0
	rim.spot_angle = 30.0
	rim.spot_range = 5.0
	rim.light_volumetric_fog_energy = 0.0
	portal.add_child(rim)
	rim.position = Vector3(0, 4.9, 1.5)
	rim.look_at(portal.global_position + Vector3(0, 2.6, 0), Vector3.UP)


## Locked books show their pop-up in faded sepia under the chain (round 2 #9).
func _sepia(n: Node) -> void:
	# r1 visual: the flat grey-brown read dead. Warm parchment sepia with a bright paper-edge rim.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("c8a878")
	m.roughness = 0.85
	m.rim_enabled = true
	m.rim = 0.9
	m.rim_tint = 0.1
	for c in n.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = m


func _world_count(wid: String) -> int:
	var game := get_node_or_null("/root/Game")
	if game and game.has_method("world_truffle_count"):
		return int(game.call("world_truffle_count", wid))
	return 0


## Pop-up stages (R1.2): 0 truffles = flat paper cut-outs, 1-3 = standing at 40 %, 4+ = full size (8 adds sparkle).
func _diorama_scale(wid: String) -> Vector3:
	# Round 2 (#9): stage 0 already stands, so the hero shot reads like key art 08.
	var n := _world_count(wid)
	# r1 visual round 2: Book 3 sits up on the east gallery bay; a taller pop-up reads above the gallery rail in the
	# hero shot (key art 08 wants three standing pop-ups).
	var k := 1.35 if wid == "W3" else 1.0
	if n <= 0:
		return Vector3.ONE * 0.6 * k
	if n < 4:
		return Vector3.ONE * 0.8 * k
	return Vector3.ONE * 1.0 * k


func _dprop(parent: Node3D, path: String, pos: Vector3, scl: float, yaw: float) -> Node3D:
	var ps := _glb(path)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.position = pos
	n.scale = Vector3.ONE * scl
	n.rotation_degrees.y = 180.0 + yaw
	parent.add_child(n)
	return n


## Velvet rope ring with brass stanchions and a number sign around a locked book; drops when the book opens.
func _lock_dressing(portal: Node3D, wid: String, need: int) -> void:
	var lock := Node3D.new()
	lock.name = "Lock"
	portal.add_child(lock)
	lock.position.y = -0.4  # the portal stands on its 0.4 m dais; the rope ring stands on the floor
	var brass := HubArchitecture.brass()
	var velvet := HubArchitecture.flat_toon(Color("7a1f2e"), 0.45, 0.4)
	var b := HubKit.Buf.new()
	var rope := HubKit.Buf.new()
	var n := 7
	var r := 2.1
	var prev := Vector3.ZERO
	for i in n + 1:
		var a := deg_to_rad(-150.0 + 300.0 * float(i) / float(n))
		var p := Vector3(sin(a) * r, 0, -cos(a) * r)
		HubKit.turned(b, PackedVector2Array([Vector2(0.16, 0.0), Vector2(0.16, 0.04), Vector2(0.05, 0.08), Vector2(0.035, 0.9), Vector2(0.07, 0.95), Vector2(0.07, 1.02), Vector2(0.0, 1.06)]), 12, p)
		if i > 0:
			for k in 6:
				var t0 := float(k) / 6.0
				var t1 := float(k + 1) / 6.0
				var q0 := prev.lerp(p, t0) + Vector3(0, 0.9 - sin(t0 * PI) * 0.22, 0)
				var q1 := prev.lerp(p, t1) + Vector3(0, 0.9 - sin(t1 * PI) * 0.22, 0)
				var dd := q1 - q0
				HubKit.rounded_box(rope, Vector3(dd.length() + 0.03, 0.07, 0.07), 0.033, Transform3D(HubArchitecture.along(dd), (q0 + q1) * 0.5))
		prev = p
	HubArchitecture.mi(lock, b.commit(), brass, "Stanchions")
	HubArchitecture.mi(lock, rope.commit(), velvet, "Rope")
	# Easel sign with a truffle and the number, facing the reader (-Z).
	var sign := Node3D.new()
	sign.position = Vector3(0, 0, -1.95)
	lock.add_child(sign)
	sign.position = Vector3(0, 0, -2.3)
	var sb := HubKit.Buf.new()
	var tilt := Basis(Vector3.RIGHT, 0.2)
	HubKit.rounded_box(sb, Vector3(0.62, 0.5, 0.05), 0.03, Transform3D(tilt, Vector3(0, 1.0, 0)))
	for lx in [-0.22, 0.22]:
		HubKit.rounded_box(sb, Vector3(0.04, 1.0, 0.04), 0.015, Transform3D(tilt, Vector3(lx, 0.5, -0.08)))
	HubKit.rounded_box(sb, Vector3(0.04, 1.0, 0.04), 0.015, Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 0.5, 0.14)))
	HubArchitecture.mi(sign, sb.commit(), brass, "Easel")
	var lab := _label(sign, "%d" % need, Vector3(-0.08, 1.0, -0.04), 110, Color("3b2416"))
	lab.rotation_degrees = Vector3(-11.5, 180, 0)
	lab.outline_size = 0
	var tr := _glb("res://assets/props/pickups/golden_truffle_v2/golden_truffle_v2.glb")
	if tr:
		var t := tr.instantiate() as Node3D
		t.scale = Vector3.ONE * 0.45
		t.position = Vector3(0.15, 0.92, -0.08)
		sign.add_child(t)
	# Iron chains in an X from cover corner to cover corner, drooping over the pages (r1 visual: the old links read
	# as a dotted row floating above the book), and the wolf's red wax seal where they cross.
	# Fix r2 (visual major): 18 small pewter tori per diagonal read as lilac donuts or a bead row. Ten elongated dark
	# iron links per diagonal (alternating 90 degrees, no rim), and a bigger red wax seal as the main read from the hall.
	var tm := TorusMesh.new()
	tm.inner_radius = 0.028
	tm.outer_radius = 0.06
	tm.rings = 12
	tm.ring_segments = 6
	var iron_m := HubArchitecture.flat_toon(Color("4a4650"), 0.0, 0.6)
	for diag in [[Vector3(-0.85, 2.62, 0.45), Vector3(0.85, 3.05, -0.55)], [Vector3(0.85, 2.62, 0.45), Vector3(-0.85, 3.05, -0.55)]]:
		var a: Vector3 = diag[0]
		var e: Vector3 = diag[1]
		var cnt := 10
		var prevp := a
		for i in cnt + 1:
			var t := float(i) / float(cnt)
			var pnt := a.lerp(e, t) - Vector3(0, sin(t * PI) * 0.12, 0)
			if i > 0:
				var dir := (pnt - prevp).normalized()
				var link := HubArchitecture.mi(lock, tm, iron_m, "")
				# Stretched along the chain (x of the along() frame) so neighbouring links meet: about 0.2 m long.
				var lb := HubArchitecture.along(dir) * Basis.from_scale(Vector3(1.65, 1.0, 1.0)) * Basis(Vector3.RIGHT, PI * 0.5 if i % 2 == 0 else 0.0) * Basis(Vector3.BACK, PI * 0.5)
				link.transform = Transform3D(lb, (pnt + prevp) * 0.5)
				link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			prevp = pnt
	var seal := HubKit.Buf.new()
	HubKit.turned(seal, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.2, 0.0), Vector2(0.22, 0.03), Vector2(0.2, 0.06), Vector2(0.12, 0.07), Vector2(0.0, 0.075)]), 18)
	var seal_mi := HubArchitecture.mi(lock, seal.commit(), HubArchitecture.flat_toon(Color("a8202a"), 0.25, 0.5), "WaxSeal")
	seal_mi.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-72.0)).scaled(Vector3.ONE * 1.25), Vector3(0, 2.76, -0.06))
	var sl := _label(lock, "W", Vector3(0, 2.77, -0.0), 64, Color("5a0e14"))
	sl.rotation_degrees = Vector3(-72.0 + 90.0 - 90.0, 180.0, 0)
	sl.outline_size = 0
	sl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_locks[wid] = lock
	lock.set_meta("wid", wid)
	# Fix r1b (fun): a book opened since the last visit keeps its lock until the gate ceremony drops it on camera
	# (the t3 return capture showed Book 2 already bare at load, so the ceremony never played).
	lock.visible = not bool(portal.get("is_open")) or (not _flag_set("hub_gate_seen_" + wid) and not _is_title())


# ------------------------------------------------------------------ Wolf's Door

func _wolf_door() -> void:
	var ps := HubAssets.scene(WOLF_DOOR_SCENE)
	wolf_door = ps.instantiate() as Node3D
	wolf_door.name = "Wolf_Door"
	wolf_door.set("visual_scene", _glb(P + "hub/wolf_door/wolf_door.glb"))
	wolf_door.set("visual_scale", 1.2)
	wolf_door.set("required_truffles", 12)
	wolf_door.set("target_world", "BOSS")
	wolf_door.set("width", 2.4)
	wolf_door.set("height", 3.8)
	wolf_door.set("visual_flip_180", false)
	wolf_door.position = Vector3(0, GALLERY_Y, -15.75)
	add_child(wolf_door)
	# Fix r2 (fun/visual minor): from the hero shot only a red glow of the door showed past the clock. A menacing red
	# wash on the door and its surround makes the boss goal read above the clock silhouette.
	var dg := _omni(Vector3(0, GALLERY_Y + 2.6, -14.4), Color("ff4a3a"), 2.2, 5.5, false, true)
	dg.name = "WolfDoorGlow"
	# Swing the generated door with the hinge so it opens visibly at 12 truffles.
	var vis := wolf_door.get_node_or_null("Visual") as Node3D
	var hinge := wolf_door.get_node_or_null("Hinge") as Node3D
	if vis and hinge:
		vis.reparent(hinge, true)
	# Iron chains in an X across the door with a "12" padlock (hidden once unlocked).
	var lock := Node3D.new()
	lock.name = "Chains"
	wolf_door.add_child(lock)
	var iron := HubArchitecture.iron()
	for diag in [[Vector3(-1.2, 0.4, 0.45), Vector3(1.2, 3.5, 0.45)], [Vector3(1.2, 0.4, 0.45), Vector3(-1.2, 3.5, 0.45)]]:
		var a: Vector3 = diag[0]
		var bb: Vector3 = diag[1]
		var n := 16
		for i in n:
			var p := a.lerp(bb, (float(i) + 0.5) / float(n))
			var tm := TorusMesh.new()
			tm.inner_radius = 0.05
			tm.outer_radius = 0.1
			var link := HubArchitecture.mi(lock, tm, iron, "")
			var dir := (bb - a).normalized()
			link.transform = Transform3D(HubArchitecture.along(dir) * Basis(Vector3.RIGHT, PI * 0.5 if i % 2 == 0 else 0.0) * Basis(Vector3.BACK, PI * 0.5), p)
	var pl := HubKit.Buf.new()
	HubKit.rounded_box(pl, Vector3(0.5, 0.44, 0.18), 0.08, Transform3D(Basis(), Vector3(0, 1.95, 0.55)))
	HubArchitecture.mi(lock, pl.commit(), HubArchitecture.brass(), "Padlock")
	var shackle := TorusMesh.new()
	shackle.inner_radius = 0.12
	shackle.outer_radius = 0.17
	HubArchitecture.mi(lock, shackle, iron, "Shackle").transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 2.2, 0.55))
	var lab := _label(lock, "12", Vector3(0, 1.93, 0.65), 90, Color("3b2416"))
	lab.outline_size = 0
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_locks["BOSS"] = lock
	lock.visible = not bool(wolf_door.get("is_unlocked"))
	# Warm red uplight on the lacquer so the door is the first thing you see at the top of the stair.
	_omni(Vector3(0, GALLERY_Y + 1.6, -13.4), Color(1.0, 0.5, 0.35), 3.5, 6.5)
	# Two brass lanterns flank the door.
	for sx in [-1.0, 1.0]:
		var lp := Vector3(sx * 1.85, GALLERY_Y + 2.6, -15.55)
		var lb := HubKit.Buf.new()
		HubKit.rounded_box(lb, Vector3(0.3, 0.42, 0.3), 0.08, Transform3D(Basis(), lp))
		HubKit.rounded_box(lb, Vector3(0.08, 0.08, 0.4), 0.03, Transform3D(Basis(), lp + Vector3(0, 0.25, -0.2)))
		HubArchitecture.mi(self, lb.commit(), HubArchitecture.brass(), "DoorLantern")
		var gl := SphereMesh.new()
		gl.radius = 0.12
		gl.height = 0.24
		HubArchitecture.mi(self, gl, HubKit.emissive(Color(1.0, 0.7, 0.35), 4.0, "lantern_glow"), "LanternGlow").position = lp
		_omni(lp + Vector3(0, 0, 0.3), Color(1.0, 0.68, 0.4), 1.4, 4.0, false, true)


# ------------------------------------------------------------------ ladders

func _ladders() -> void:
	var lad := _glb(P + "hub/rolling_ladder/rolling_ladder.glb")
	var specs := [
		{"name": "L1_ladder", "foot": HubKit.polar(11.25, 60.0, 0.0), "top": HubKit.polar(12.3, 60.0, 4.5), "exit": HubKit.polar(13.3, 60.0, 4.5), "theta": 60.0, "lean": 0.0, "scale": 0.98},
		{"name": "L2_ladder", "foot": Vector3(12.5, 4.5, 4.55), "top": Vector3(13.44, 8.5, 4.89), "exit": Vector3(14.28, 8.5, 5.2), "theta": 110.0, "lean": 14.0, "scale": 0.92},
	]
	for s in specs:
		var hl := HubLadder.new()
		hl.name = s["name"]
		hl.foot = s["foot"]
		hl.top = s["top"]
		hl.exit_point = s["exit"]
		hl.exit_yaw_deg = HubKit.yaw_facing_centre(float(s["theta"])) + 180.0
		add_child(hl)
		if lad:
			var v := lad.instantiate() as Node3D
			v.name = "LadderMesh"
			var th: float = s["theta"]
			# Rails tangential, rungs facing the hall; the glTF already leans about 11 degrees.
			v.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-th)) * Basis.from_scale(Vector3.ONE * float(s["scale"])), s["foot"])
			add_child(v)


# ------------------------------------------------------------------ Bramwell

func _bramwell() -> void:
	var ps := HubAssets.scene(NPC_SCENE)
	bramwell = ps.instantiate() as Node3D
	bramwell.name = "Bramwell"
	# Fix r2: bramwell_v2 (round 5 asset fix: AO bake, roughness floor 0.72; pure path swap) when it is imported.
	var bram_path := "res://assets/characters/bramwell/bramwell_v2.glb"
	if not ResourceLoader.exists(bram_path):
		bram_path = "res://assets/characters/bramwell/bramwell.glb"
	bramwell.set("visual_scene", _glb(bram_path))
	bramwell.set("speaker", "Bramwell")
	bramwell.set("talk_radius", 2.2)
	bramwell.position = Vector3(3.2, 0, 7.6)
	bramwell.rotation_degrees.y = 140.63
	add_child(bramwell)
	if bramwell.has_signal("talked"):
		bramwell.connect("talked", _on_bramwell_talked)
	# Fix r2 (visual major): the generated material reads metal 1.0, so RetroLook kept it as shiny metal and Bramwell
	# rendered as chrome (silver streaks over skin, shell and tailcoat). D034: characters are matte.
	# Finishing pass (WORLDS, 2026-10-19): at gameplay distance the olive-and-black Tripo albedo plus the baked v2 AO read
	# as a dark, broken blob beside the W2 pedestal. Brighter warm tint, no AO darkening, and a soft warm key like the cub's.
	matte_surfaces(bramwell, 0.0, 0.78, Color(1.38, 1.3, 1.12))
	matte_surfaces.call_deferred(bramwell, 0.0, 0.78, Color(1.38, 1.3, 1.12))
	_bramwell_no_ao.call_deferred()
	var bram_key := OmniLight3D.new()
	bram_key.name = "BramwellKey"
	bram_key.light_color = Color("ffe6c4")
	bram_key.light_energy = 1.1
	bram_key.omni_range = 3.2
	bram_key.position = Vector3(0, 1.7, 1.1)
	bram_key.shadow_enabled = false
	bramwell.add_child(bram_key)
	_occluders.append({"node": bramwell, "y": 0.85, "r": 0.75})


func _bramwell_no_ao() -> void:
	if bramwell == null or not is_instance_valid(bramwell):
		return
	for n in bramwell.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(si) as BaseMaterial3D
			if m:
				m.ao_enabled = false


## Fix r2: forces matte surfaces (metallic, roughness, a gentle albedo tint) on every mesh under `root` through
## surface overrides, before RetroLook reads them. Idempotent per mesh instance.
func matte_surfaces(root: Node, metallic: float, roughness: float, tint := Color.WHITE) -> void:
	if root == null or not is_instance_valid(root):
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.has_meta("hub_matte"):
			continue
		mi.set_meta("hub_matte", true)
		for si in mi.mesh.get_surface_count():
			var ov := mi.get_surface_override_material(si)
			var m: Material = ov if ov != null else mi.mesh.surface_get_material(si)
			if not (m is BaseMaterial3D):
				continue
			var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			d.metallic = metallic
			d.roughness = maxf(roughness, d.roughness) if metallic <= 0.0 else roughness
			d.metallic_specular = minf(d.metallic_specular, 0.3)
			d.albedo_color = d.albedo_color * tint
			mi.set_surface_override_material(si, d)


## Fix r2 (fun major): NPCs between the camera and Mak (Bramwell after every W2 return ceremony) fade to 70 %
## transparency instead of filling the lower third of the frame. Entries: node, body-centre height, radius.
var _occluders: Array = []


func _occluder_fade() -> void:
	var cam := get_viewport().get_camera_3d()
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if cam == null or p == null:
		return
	var a := cam.global_position
	var b := p.global_position + Vector3(0, 0.7, 0)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	for e in _occluders:
		var n: Node3D = e["node"]
		if n == null or not is_instance_valid(n):
			continue
		var c := n.global_position + Vector3(0, float(e["y"]), 0)
		var k := clampf((c - a).dot(ab) / len2, 0.0, 1.0)
		var want := 0.0
		if k > 0.0 and k < 0.93 and (a + ab * k).distance_to(c) < float(e["r"]) + 0.35:
			want = 0.72
		if a.distance_to(c) < 1.4:
			want = 0.85
		var cur := float(e.get("t", 0.0))
		if absf(cur - want) < 0.01:
			continue
		cur = move_toward(cur, want, get_process_delta_time() * 3.0)
		e["t"] = cur
		if not e.has("geoms"):
			e["geoms"] = n.find_children("*", "GeometryInstance3D", true, false)
		for g in e["geoms"]:
			if is_instance_valid(g):
				(g as GeometryInstance3D).transparency = cur


var _bram_talks := 0


## r1 fun: every talk used to be a 6-7 box monologue. Now each talk is one or two lines: the most relevant line
## first (the chase hint while the impostor is loose, then gate news), then one rotating extra.
func _bramwell_lines() -> PackedStringArray:
	var n := 0
	var game := get_node_or_null("/root/Game")
	if game and game.has_method("truffle_count"):
		n = int(game.call("truffle_count"))
	var key := 0
	for k in [0, 3, 7, 12]:
		if n >= k:
			key = k
	var first := ""
	var extra: Array[String] = []
	var cub_live := activities != null and activities.has_method("chase_active") and bool(activities.call("chase_active"))
	if cub_live:
		first = "That sheep has your bookmark, sir. I am told wolves are poor at corners. A slide or a dive should do it."
	elif not _flag_set("hub_cub_done"):
		first = BRAMWELL_FIRST if n == 0 else "One of Book One's sheep still looks rather... large, sir."
	else:
		first = BRAMWELL_LINES[key]
	if first != BRAMWELL_LINES[key]:
		extra.append(BRAMWELL_LINES[key])
	if key < 12:
		var nxt := 3 if key == 0 else (7 if key == 3 else 12)
		extra.append("You have %d Golden Truffle%s, sir. The next seal loosens at %d." % [n, "" if n == 1 else "s", nxt])
	if n > 0 and not _flag_set("hub_nook_done"):
		extra.append("Your snout, sir: the wolf may have missed something. Your grandfather hid things low.")
	var has_hub := game != null and game.has_method("has_truffle") and bool(game.call("has_truffle", "HUB-1"))
	if not has_hub:
		extra.append(BRAMWELL_SECRET if (_flag_set("hub_nook_done") and n >= 3) else BRAMWELL_SECRET_LOCKED)
	else:
		extra.append("I see you found your grandfather's truffle. He would be terribly proud, sir.")
	if activities != null and activities.has_method("tea_available") and bool(activities.call("tea_available")):
		extra.append("Fancy a Tea Run, sir? The teacup on the tray by the doors starts it.")
	if not _flag_set("hat_acorncap") and ledger_total() > 0:
		extra.append("The ledger by the door wants every acorn in this room, sir: %d of %d so far." % [ledger_count(), ledger_total()])
	var lines := PackedStringArray([first])
	if not extra.is_empty():
		lines.append(extra[_bram_talks % extra.size()])
	return lines


func _on_bramwell_talked(_l: Array) -> void:
	_bram_talks += 1
	_update_bramwell.call_deferred()


func _update_bramwell() -> void:
	if bramwell:
		bramwell.set("lines", _bramwell_lines())


func _greeting() -> void:
	# r1 visual: Bramwell's speech stayed on screen in --hide-hud story frames.
	var devg := get_node_or_null("/root/Dev")
	if devg and bool(devg.call("has_arg", "hide-hud")):
		return
	# A speech bubble over Bramwell for the first seconds of the visit (non-blocking).
	if bramwell == null:
		return
	var game := get_node_or_null("/root/Game")
	var n := int(game.call("truffle_count")) if game and game.has_method("truffle_count") else 0
	var text := "Ah, sir. The wolf has been." if n == 0 else ("Welcome back, sir. %d truffle%s so far." % [n, "" if n == 1 else "s"])
	# Fix r2 (fun minor): the greeting was an oversized Label3D cut at the screen edge; it now uses the UI bark
	# (same style as every other line), after a short beat, only while Mak is within 12 m.
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func() -> void:
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p and p.global_position.distance_to(bramwell.global_position) < 12.0:
			_bubble_on(bramwell, text, 4.5))


## A speech bubble over any node for `secs` seconds (non-blocking).
func _bubble_on(n: Node3D, text: String, secs: float, height := 2.05) -> void:
	if n == null:
		return
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("bark"):
		ui.call("bark", n, text, secs, {"height": height})
		return
	var l := _label(n, text, Vector3(0, height, 0), 44, Color("3b2416"))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 14
	l.outline_modulate = Color(1.0, 0.96, 0.86)
	l.width = 900.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------ HUB-1

func _hub_truffle() -> void:
	var th := 190.0
	var at := HubKit.polar(15.0, th, 9.7)
	# Side table with a glass bell jar.
	var table := Node3D.new()
	table.name = "BellJarTable"
	table.position = at
	add_child(table)
	var tb := HubKit.Buf.new()
	HubKit.turned(tb, PackedVector2Array([Vector2(0.25, 0.0), Vector2(0.25, 0.04), Vector2(0.06, 0.1), Vector2(0.05, 0.55), Vector2(0.32, 0.62), Vector2(0.32, 0.68), Vector2(0.0, 0.7)]), 18)
	HubArchitecture.mi(table, tb.commit(), HubArchitecture.toon("bookshelf_wood", Color(0.7, 0.48, 0.34), 0.9), "Table")
	var tbody := HubArchitecture.static_body(table, "Collision")
	HubKit.add_cyl_collision(tbody, null, 0.3, 0.7, Vector3(0, 0.35, 0))
	_bell_jar = Node3D.new()
	_bell_jar.name = "BellJar"
	_bell_jar.position = Vector3(0, 0.7, 0)
	table.add_child(_bell_jar)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.95, 1.0, 0.18)
	glass.roughness = 0.05
	glass.rim_enabled = true
	glass.rim = 0.7
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var jb := HubKit.Buf.new()
	var prof := PackedVector2Array()
	for i in 9:
		var a := deg_to_rad(90.0 * float(i) / 8.0)
		prof.append(Vector2(0.3 * cos(a), 0.55 + 0.3 * sin(a)))
	prof.insert(0, Vector2(0.3, 0.0))
	HubKit.lathe(jb, prof, 0.0, 360.0, 15.0, false, false, 80.0)
	HubArchitecture.mi(_bell_jar, jb.commit(), glass, "Glass").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var knob := SphereMesh.new()
	knob.radius = 0.05
	knob.height = 0.1
	var knob_mi := HubArchitecture.mi(_bell_jar, knob, HubArchitecture.brass(), "Knob")
	knob_mi.position = Vector3(0, 0.88, 0)
	var ps := HubAssets.scene(TRUFFLE_SCENE)
	hub_truffle = ps.instantiate() as Node3D
	hub_truffle.name = "HUB-1"
	hub_truffle.set("truffle_id", "HUB-1")
	hub_truffle.set("mission_title", "Top of the Library")
	hub_truffle.set("hover_height", 1.05)
	hub_truffle.set("bob_height", 0.06)
	hub_truffle.position = at
	add_child(hub_truffle)
	if hub_truffle.has_signal("collected"):
		hub_truffle.connect("collected", _on_hub1)
	# Crest tapestry hanging from the dome at r 13.4, theta 182-198, hiding the balcony from the floor.
	var tap := HubKit.Buf.new()
	HubKit.lathe(tap, PackedVector2Array([Vector2(13.4, 9.2), Vector2(13.4, 16.0)]), 182.0, 198.0, 1.0, false, false, 10.0, 1.0)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/environment/hub/hub_tapestry.gdshader")
	_tapestry = HubArchitecture.mi(self, tap.commit(), sm, "CrestTapestry")
	var rod := HubKit.Buf.new()
	HubKit.lathe(rod, HubKit.round_rect_profile(13.32, 13.48, 15.9, 16.06, 0.07, 0.07, 0.07, 0.07), 181.0, 199.0, 2.0, true, true)
	HubArchitecture.mi(self, rod.commit(), HubArchitecture.brass(), "TapestryRod")
	# Warm glow leaking round the tapestry edges.
	_omni(HubKit.polar(14.6, 190.0, 10.6), Color(1.0, 0.78, 0.4), 1.6, 4.5)


func _on_hub1(_id: String = "") -> void:
	if _bell_jar:
		var tw := create_tween()
		tw.tween_property(_bell_jar, "position:y", 1.6, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_bell_jar, "scale", Vector3(0.01, 0.01, 0.01), 0.25)
	_update_bramwell()


# ------------------------------------------------------------------ acorns

func _acorns() -> void:
	var ps := HubAssets.scene(ACORN_SCENE)
	var holder := Node3D.new()
	holder.name = "Acorns"
	add_child(holder)
	var game := get_node_or_null("/root/Game")
	var dev := get_node_or_null("/root/Dev")
	var all := dev != null and bool(dev.call("has_arg", "unlock-all"))
	for gid in ACORNS.keys():
		# R3.9 "absent cleanly": shortcut acorns only exist once their shortcut has grown.
		var need := {"AG12_vine": "W2-1", "AG13_updraft": "W1-4"}.get(gid, "") as String
		if need != "" and not all and not (game != null and game.has_method("has_truffle") and bool(game.call("has_truffle", need))):
			continue
		var g := Node3D.new()
		g.name = gid
		holder.add_child(g)
		var i := 0
		for p in ACORNS[gid]:
			ledger_acorn(g, gid, i, p as Vector3)
			i += 1
	_ledger_plate()
	_hat_stand()


# ------------------------------------------------------------------ H-J The Library Ledger (R3.6)

var _ledger_label: Label3D


## True when this hub is only the title screen's backdrop (never spend story flags there).
func _is_title() -> bool:
	var root := get_parent()
	return root != null and (root.has_meta("title_backdrop") or root.is_in_group("title_backdrop"))


func _flag_set(flag: String) -> bool:
	return HubKit.flag(self, flag)


var _ledger_groups: Dictionary = {}  # gid prefix (AG01...) -> highest index + 1 actually built

## r1 QA + fun round 2: the ledger total is FIXED for this build (every Tier A group plus the built Tier B shortcut
## groups, gated or not), so the acorn cap can never be awarded before the spiral or the shortcuts exist, and the
## plate never drops back to "incomplete". Gated groups show as locked lines on the plate.
## AG18 is the cub drop (it was keyed AG15, which the plan reserves for the dome bong).
## Fix r1b: AG11 (tea chest, 5) and AG15 (dome bong, 5) joined the plan: Tier A is now the full 85 of R3.6
## (57 + 5 + 5 + 10 + 8), plus the 8 Tier B shortcut acorns = 93.
const LEDGER_PLAN := {"AG01": 8, "AG02": 5, "AG03": 5, "AG04": 6, "AG05": 3, "AG06": 5, "AG07": 5, "AG08": 5, "AG09": 6,
	"AG10": 4, "AG11": 5, "AG12": 4, "AG13": 4, "AG14": 5, "AG15": 5, "AG16": 10, "AG18": 8}
const LEDGER_LOCKED_TEXT := {"AG11": "in the tea chest", "AG12": "after Jack's beanstalk grows", "AG13": "after the bellows wake",
	"AG15": "ring the clock dome", "AG16": "after the huff (7 truffles)", "AG18": "the sheep has them"}


## One-off ledger acorn (R3.6 / HUB-D12): built only while its flag is unset; every group that calls this counts
## toward the ledger total, so the total is exactly the acorns this visit can reach (r1 QA: the old total summed
## AG12/AG13 before their shortcuts grew and skipped AG14, AG16 and the cub drop).
func ledger_acorn(parent: Node3D, gid: String, i: int, pos: Vector3) -> Node3D:
	var key := gid.substr(0, 4)
	_ledger_groups[key] = maxi(int(_ledger_groups.get(key, 0)), i + 1)
	var flag := "hub_acorn_%s_%d" % [key, i]
	if _flag_set(flag):
		return null
	var ps := HubAssets.scene(ACORN_SCENE)
	if ps == null:
		return null
	var a := ps.instantiate() as Node3D
	a.position = pos - Vector3(0, 0.45, 0)
	parent.add_child(a)
	_gild(a)
	if a.has_signal("picked"):
		a.connect("picked", _on_ledger_acorn.bind(flag))
	_ledger_refresh()
	return a


static var _gild_mat: ShaderMaterial


## r1 visual round 2: acorns read dull brown on the walnut floor; a gold fresnel rim and a travelling glint
## (additive overlay, hub-side, the shared Acorn scene is untouched).
func _gild(n: Node) -> void:
	if _gild_mat == null:
		var sh := load("res://assets/environment/hub/hub_gild_overlay.gdshader") as Shader
		if sh == null:
			return
		_gild_mat = ShaderMaterial.new()
		_gild_mat.shader = sh
		# D034: RetroLook's gameplay-pop pass already adds a warm rim and an ink outline to pickups; keep the gold
		# body tint but halve the hub's own rim so the two never stack into a white blob.
		var rl := get_node_or_null("/root/RetroLook")
		if rl and bool(rl.get("enabled")) and bool(rl.get("pop_enabled")):
			_gild_mat.set_shader_parameter("rim_strength", 0.4)
			_gild_mat.set_shader_parameter("lift", 0.12)
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		# Fix r1b: skip flat cards (the acorn's blob-shadow PlaneMesh); the additive gold turned each shadow into
		# a bright yellow square on the floor next to its acorn.
		if mi.mesh == null or mi.mesh is PlaneMesh or mi.mesh is QuadMesh:
			continue
		var bb := mi.mesh.get_aabb()
		if minf(bb.size.x, minf(bb.size.y, bb.size.z)) < 0.01:
			continue
		mi.material_overlay = _gild_mat


## One-off ledger acorns that burst out of something (AG11 tea chest, AG15 dome bong): a ring of `n` at radius `r`
## round `at`, only those not yet collected, once per visit.
var _burst_done: Dictionary = {}


func _burst_ledger(gid: String, at: Vector3, r: float, n: int) -> void:
	if _burst_done.has(gid):
		return
	_burst_done[gid] = true
	var holder := Node3D.new()
	holder.name = gid
	add_child(holder)
	for i in n:
		var a := TAU * float(i) / float(n) + 0.3
		var pos := at + Vector3(cos(a) * r, 0.6, sin(a) * r)
		var acorn := ledger_acorn(holder, gid, i, pos)
		if acorn:
			var end := acorn.position
			acorn.position = at + Vector3(0, 0.3, 0) - Vector3(0, 0.45, 0)
			var tw := acorn.create_tween()
			tw.tween_property(acorn, "position", end + Vector3(0, 0.8, 0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(acorn, "position", end, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	ObjSvc.burst(self, at + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.4), 24, 3.5, 0.16, -4.0, 0.8)


## EV_dome_bong / EV_grand_bong: AG15, five ledger acorns pop out of the dome and land round the clock.
func dome_bong_acorns() -> void:
	_burst_ledger("AG15_dome_bong", Vector3(0, 0.0, 1.0), 3.3, 5)


func ledger_total() -> int:
	var n := 0
	for k in LEDGER_PLAN.keys():
		n += int(LEDGER_PLAN[k])
	return n


func ledger_count() -> int:
	var n := 0
	for k in LEDGER_PLAN.keys():
		for i in int(LEDGER_PLAN[k]):
			if _flag_set("hub_acorn_%s_%d" % [k, i]):
				n += 1
	return n


## Plan groups with nothing placed this visit and nothing collected yet: shown as padlock lines on the plate.
func ledger_locked_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for k in LEDGER_PLAN.keys():
		if _ledger_groups.has(k):
			continue
		var got := 0
		for i in int(LEDGER_PLAN[k]):
			if _flag_set("hub_acorn_%s_%d" % [k, i]):
				got += 1
		if got < int(LEDGER_PLAN[k]):
			out.append("%d locked: %s" % [int(LEDGER_PLAN[k]) - got, LEDGER_LOCKED_TEXT.get(k, "later")])
	return out


func _on_ledger_acorn(_value: int, flag: String) -> void:
	var game := get_node_or_null("/root/Game")
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_method("is_test_run") and bool(dev.call("is_test_run")):
		return  # captures and replays run on the default save: never write ledger flags there
	if game and game.has_method("unlock"):
		game.call("unlock", flag)
	_ledger_refresh()
	if ledger_total() > 0 and ledger_count() >= ledger_total() and not _flag_set("hat_acorncap"):
		if game and game.has_method("unlock"):
			game.call("unlock", "hat_acorncap")
		_bubble_on(bramwell, "Every acorn in the ledger, sir! The acorn cap is on the hat stand.", 4.0)
		_update_bramwell()


## The ledger: a brass-cornered open register on a stand by the doors, showing the room's acorn tally.
func _ledger_plate() -> void:
	var stand := Node3D.new()
	stand.name = "H-J_Ledger"
	stand.position = Vector3(-4.6, 0, 12.6)  # by the doors, clear of the cub loop and the Tea Run line
	stand.rotation_degrees.y = -20.0  # pages tilt toward the hall
	add_child(stand)
	var b := HubKit.Buf.new()
	HubKit.rounded_box(b, Vector3(0.16, 1.0, 0.16), 0.05, Transform3D(Basis(), Vector3(0, 0.5, 0)))
	HubKit.rounded_box(b, Vector3(0.6, 0.06, 0.6), 0.03, Transform3D(Basis(), Vector3(0, 0.03, 0)))
	HubArchitecture.mi(stand, b.commit(), HubArchitecture.flat_toon(Color("5a3420"), 0.5, 0.2), "Stand")
	var pb := HubKit.Buf.new()
	HubKit.rounded_box(pb, Vector3(0.9, 0.06, 0.62), 0.03, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-25.0)), Vector3(0, 1.08, 0)))
	HubArchitecture.mi(stand, pb.commit(), HubArchitecture.flat_toon(Color("f1e3c0"), 0.6, 0.1), "Pages")
	var body := HubArchitecture.static_body(stand, "Collision")
	HubKit.add_box_collision(body, null, Vector3(0.6, 1.15, 0.6), Transform3D(Basis(), Vector3(0, 0.575, 0)))
	_ledger_label = _label(stand, "", Vector3(0, 1.45, 0), 30, Color("3b2416"))
	_ledger_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_ledger_label.pixel_size = 0.003
	_ledger_label.outline_size = 10
	_ledger_label.outline_modulate = Color(1.0, 0.96, 0.86)
	_ledger_refresh()


# ------------------------------------------------------------------ R1.9 hat stand (HS_hat_stand)

const HAT_GLBS := {
	"beanie": "res://assets/characters/mak/mak_beanie_v2.glb",
	"top_hat": "res://assets/characters/mak/mak_tophat.glb",
	"golden_top_hat": "res://assets/characters/mak/mak_tophat.glb",  # the Wolf's reward, gilded below
}
const HUB_HATS := {"bowler": "hat_bowler", "deerstalker": "hat_deerstalker", "teacosy": "hat_teacosy", "acorncap": "hat_acorncap", "monocle": "hat_monocle"}
var _hat_stand_node: Node3D


func _hub_hat_mesh(hat: String, earned: bool) -> Node3D:
	var n := Node3D.new()
	n.name = "Hat_" + hat
	var b := HubKit.Buf.new()
	var col := Color("2e2a2b")
	match hat:
		"bowler":
			HubKit.turned(b, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.17, 0.0), Vector2(0.17, 0.02), Vector2(0.11, 0.03), Vector2(0.11, 0.1), Vector2(0.08, 0.15), Vector2(0.0, 0.16)]), 18)
			col = Color("2b2422")
		"deerstalker":
			HubKit.turned(b, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.13, 0.0), Vector2(0.12, 0.08), Vector2(0.07, 0.13), Vector2(0.0, 0.14)]), 16)
			HubKit.rounded_box(b, Vector3(0.12, 0.02, 0.08), 0.01, Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.01, -0.15)))
			HubKit.rounded_box(b, Vector3(0.12, 0.02, 0.08), 0.01, Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.01, 0.15)))
			col = Color("8a6a46")
		"teacosy":
			HubKit.turned(b, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.14, 0.0), Vector2(0.14, 0.06), Vector2(0.1, 0.14), Vector2(0.0, 0.17)]), 16)
			HubKit.rounded_box(b, Vector3(0.05, 0.05, 0.05), 0.024, Transform3D(Basis(), Vector3(0, 0.19, 0)))
			col = Color("c4473f")
		"acorncap":
			HubKit.turned(b, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.14, 0.0), Vector2(0.15, 0.04), Vector2(0.1, 0.09), Vector2(0.0, 0.1)]), 16)
			HubKit.rounded_box(b, Vector3(0.02, 0.07, 0.02), 0.008, Transform3D(Basis(Vector3.BACK, 0.3), Vector3(0.01, 0.13, 0)))
			col = Color("8a5a2e")
		"monocle":
			HubKit.lathe(b, HubKit.round_rect_profile(0.06, 0.075, -0.01, 0.01, 0.005, 0.005, 0.005, 0.005), 0.0, 360.0, 15.0, true, false)
			HubKit.rounded_box(b, Vector3(0.008, 0.16, 0.008), 0.003, Transform3D(Basis(), Vector3(0.07, -0.08, 0)))
			col = Color("c9a04a")
	var m: Material
	if earned:
		m = HubArchitecture.flat_toon(col, 0.45, 0.4)
	else:
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.12, 0.08, 0.06)
		dark.roughness = 0.9
		m = dark
	HubArchitecture.mi(n, b.commit(), m, "Mesh")
	n.scale = Vector3.ONE * 1.3
	return n
var _hat_cd := 0.0


## A turned walnut hat stand by the doors. Its pegs show the hats the game can actually put on Mak
## (Game.available_hats); a hat not earned yet hangs as a dark silhouette. Interact beside it to change hats.
func _hat_stand() -> void:
	var hs := Node3D.new()
	hs.name = "HS_hat_stand"
	hs.position = Vector3(4.6, 0, 12.4)
	hs.rotation_degrees.y = 150.0
	add_child(hs)
	_hat_stand_node = hs
	# Finishing pass (HERO camera tour): the dark walnut pole has no collision, so the lens passed through it near the
	# doors; it now fades like Bramwell when it sits between the camera and Mak or right at the lens.
	_occluders.append({"node": hs, "y": 1.0, "r": 0.3})
	var walnut := HubArchitecture.flat_toon(Color("6a3b22"), 0.5, 0.25)
	var pole := HubKit.turned_mesh(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.36, 0.0), Vector2(0.36, 0.05), Vector2(0.12, 0.12),
		Vector2(0.05, 0.3), Vector2(0.045, 1.6), Vector2(0.07, 1.68), Vector2(0.05, 1.78), Vector2(0.08, 1.86), Vector2(0.0, 1.92)]), 20)
	HubArchitecture.mi(hs, pole, walnut, "Pole")
	var game := get_node_or_null("/root/Game")
	var have: Array = game.call("available_hats") if game and game.has_method("available_hats") else ["beanie"]
	var i := 0
	for hat in HAT_GLBS.keys():
		var a := deg_to_rad(51.4 * float(i) + 25.0)
		var peg := HubKit.turned_mesh(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.025, 0.0), Vector2(0.025, 0.28), Vector2(0.045, 0.3), Vector2(0.0, 0.33)]), 10)
		var pm := HubArchitecture.mi(hs, peg, HubArchitecture.brass(), "Peg_" + hat)
		pm.transform = Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(60.0)), Vector3(0, 1.55, 0))
		var tip := Vector3(sin(a), 0, cos(a)) * 0.29 + Vector3(0, 1.55 + 0.17, 0)
		var ps := _glb(HAT_GLBS[hat])
		if ps:
			var h := ps.instantiate() as Node3D
			h.scale = Vector3.ONE * 0.9
			h.position = tip + Vector3(0, -0.02, 0)
			h.rotation = Vector3(0.25, a, 0.0)
			hs.add_child(h)
			if GoldenHatLib.is_golden(hat) and have.has(hat):
				GoldenHatLib.gild(h, true)
				GoldenHatLib.sparkle(h, true, 0.2)
			if not have.has(hat):
				var dark := StandardMaterial3D.new()
				dark.albedo_color = Color(0.12, 0.08, 0.06)
				dark.roughness = 0.9
				for m in h.find_children("*", "MeshInstance3D", true, false):
					(m as MeshInstance3D).material_override = dark
		i += 1
	# r1 QA: the hub's own hat rewards had nowhere to show. Five more pegs hold procedural stand-ins (until the
	# P-H02/03/04/08/14 meshes land): dark silhouettes until earned, full colour after. Wearing them needs the core
	# hat registry (requested).
	for hat in HUB_HATS.keys():
		var a2 := deg_to_rad(51.4 * float(i) + 25.0)
		var peg2 := HubKit.turned_mesh(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.025, 0.0), Vector2(0.025, 0.28), Vector2(0.045, 0.3), Vector2(0.0, 0.33)]), 10)
		var pm2 := HubArchitecture.mi(hs, peg2, HubArchitecture.brass(), "Peg_" + hat)
		var py := 1.55 if i % 2 == 0 else 1.3
		pm2.transform = Transform3D(Basis(Vector3.UP, a2) * Basis(Vector3.RIGHT, deg_to_rad(60.0)), Vector3(0, py, 0))
		var tip2 := Vector3(sin(a2), 0, cos(a2)) * 0.29 + Vector3(0, py + 0.17, 0)
		var earned := _flag_set(String(HUB_HATS[hat]))
		var hn := _hub_hat_mesh(hat, earned)
		hn.position = tip2
		hn.rotation = Vector3(0.25, a2, 0.0)
		hs.add_child(hn)
		i += 1
	var body := HubArchitecture.static_body(hs, "Collision")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 1.9
	cs.shape = cyl
	cs.position.y = 0.95
	body.add_child(cs)


func _hat_stand_process(delta: float) -> void:
	_hat_cd = maxf(0.0, _hat_cd - delta)
	if _hat_stand_node == null or _hat_cd > 0.0 or not Input.is_action_just_pressed("interact"):
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or p.global_position.distance_to(_hat_stand_node.global_position) > 1.6:
		return
	var game := get_node_or_null("/root/Game")
	if game == null or not game.has_method("cycle_hat"):
		return
	_hat_cd = 0.5
	var hat := String(game.call("cycle_hat"))
	var line := String({"beanie": "The beanie. Practical.", "top_hat": "The top hat. Distinguished.", "golden_top_hat": "The Golden Top Hat. Wolf-proof."}.get(hat, hat))
	# r1 QA: the hub's own hat rewards are save flags with no wearable mesh yet; say so instead of silently skipping.
	var pegged: Array[String] = []
	for h in HUB_HATS.keys():
		if _flag_set(String(HUB_HATS[h])):
			pegged.append(String(h).replace("teacosy", "tea cosy").replace("acorncap", "acorn cap"))
	if not pegged.is_empty():
		line += "
(The %s stay%s on the stand in this build.)" % [", ".join(pegged), "s" if pegged.size() == 1 else ""]
	_bubble_on(_hat_stand_node, line, 2.4, 2.2)


## Fix r2 (fun/visual minor): the full ledger text block read as debug text across the first walk to Book 1. From
## afar the plate shows only "Ledger n / total"; the remaining-groups list appears within 2.2 m.
var _ledger_short := ""
var _ledger_long := ""


func _ledger_refresh() -> void:
	if _ledger_label:
		var done := ledger_count() >= ledger_total()
		var locked := ledger_locked_lines()
		_ledger_short = "Ledger %d / %d%s" % [ledger_count(), ledger_total(), "  (cap earned)" if done else ""]
		_ledger_long = _ledger_short
		if not locked.is_empty() and not done:
			var shown := locked.slice(0, 2)
			_ledger_long += "
" + "
".join(shown)
		_ledger_label.text = _ledger_short


func _ledger_near_process() -> void:
	if _ledger_label == null:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var near := p != null and p.global_position.distance_to(_ledger_label.global_position) < 2.6
	var want := _ledger_long if near else _ledger_short
	if _ledger_label.text != want:
		_ledger_label.text = want


# ------------------------------------------------------------------ lights

func _lights() -> void:
	# Chandelier: generated brass ring hanging from the dome on a chain, swaying 2 degrees over 6 s.
	_chandelier = Node3D.new()
	_chandelier.name = "Chandelier"
	_chandelier.position = Vector3(0, 21.8, 0)
	add_child(_chandelier)
	var ch := _glb(P + "hub/brass_chandelier_v3/brass_chandelier_v3.glb")
	var scl := 1.75
	if ch:
		var v := ch.instantiate() as Node3D
		v.scale = Vector3.ONE * scl
		v.position = Vector3(0, -21.8 + 8.6, 0)
		_chandelier.add_child(v)
	var chain := HubKit.Buf.new()
	var top_y := 8.6 + 2.21 * scl
	var n := int((21.8 - top_y) / 0.18)
	for i in n:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.04
		tm.outer_radius = 0.08
		var link := HubArchitecture.mi(_chandelier, tm, HubArchitecture.brass(), "")
		link.transform = Transform3D(Basis(Vector3.UP, PI * 0.5 * float(i % 2)) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -float(i) * 0.18 - 0.1, 0))
	# Candle flames on the generated chandelier's candle tips (found from the mesh: local height maxima off-axis).
	var tips: Array[Vector3] = []
	if ch:
		# v2 carries candle markers on the wick tips; fall back to the mesh scan for older models.
		for c in (_chandelier.get_child(0) as Node3D).find_children("candle_*", "Node3D", true, false):
			tips.append((c as Node3D).global_position)
		if tips.is_empty():
			tips = _candle_tips(_chandelier.get_child(0) as Node3D)
	var tip_i := 0
	var wax := HubKit.Buf.new()
	# Fix r1b: the fixed 0.075 m shell sat inside the generated candles (about 0.15-0.2 m at this scale), so they
	# still read grey from the floor. Measure each candle from the mesh and wrap it 4 % wider.
	var radii := _candle_radii(_chandelier.get_child(0) as Node3D, tips) if ch else []
	var ti := 0
	for tip in tips:
		var lt := _chandelier.to_local(tip)
		var r: float = radii[ti] if ti < radii.size() else 0.075
		var hgt := clampf(r * 3.2, 0.3, 0.75)
		HubKit.turned(wax, PackedVector2Array([Vector2(r, -hgt), Vector2(r, -0.06), Vector2(r * 0.8, -0.02), Vector2(0.0, -0.01)]), 14, lt)
		ti += 1
	if not tips.is_empty():
		# r1 visual round 2: the generated candles read as grey unlit cylinders; cream wax (#F6ECD6) like the sconces.
		var wm := HubKit.emissive(Color("f6ecd6"), 0.9, "chandelier_wax")
		HubArchitecture.mi(_chandelier, wax.commit(), wm, "ChandelierWax")
	for tip in tips:
		var halo := _flame(_chandelier, _chandelier.to_local(tip) + Vector3(0, 0.12, 0), 0.5)
		(halo.material_override as StandardMaterial3D).albedo_color = Color(0.9, 0.55, 0.2, 0.35)
		var f := _flame(_chandelier, _chandelier.to_local(tip) + Vector3(0, 0.1, 0), 0.17)
		f.set_meta("phase", float(tip_i))
		f.add_to_group("hub_flame")
		tip_i += 1
	var cl := _omni(Vector3(0, 9.4 - 21.8, 0), Color("ffd38a"), 3.0, 20.0, true, true, _chandelier)
	cl.name = "ChandelierLight"
	cl.shadow_enabled = true
	# Newel lamps.
	for sx in [-2.6, 2.6]:
		var g := SphereMesh.new()
		g.radius = 0.2
		g.height = 0.4
		HubArchitecture.mi(self, g, HubKit.emissive(Color(1.0, 0.85, 0.55), 2.5, "lamp_globe"), "NewelGlobe").position = Vector3(sx, 1.5, -3.0)
		_omni(Vector3(sx, 1.6, -3.0), Color(1.0, 0.8, 0.5), 1.4, 5.0, false, true)
	# Eight gallery sconces at r 15, y 7 (a brass bracket, a candle and a warm pool).
	var sb := HubKit.Buf.new()
	var candle := HubKit.Buf.new()
	for k in 8:
		var th := 45.0 * float(k)
		if th == 0.0 or th == 270.0:
			th += 22.5
		var p := HubKit.polar(15.05, th, 7.0)
		var inward := -Vector3(p.x, 0, p.z).normalized()
		HubKit.rounded_box(sb, Vector3(0.24, 0.36, 0.08), 0.03, Transform3D(HubArchitecture.facing_centre(th), p))
		HubKit.rounded_box(sb, Vector3(0.06, 0.06, 0.4), 0.02, Transform3D(HubArchitecture.facing_centre(th), p + inward * 0.2))
		HubKit.turned(sb, PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.12, 0.05), Vector2(0.05, 0.07)]), 12, p + inward * 0.4 + Vector3(0, -0.05, 0))
		HubKit.turned(candle, PackedVector2Array([Vector2(0.045, 0.0), Vector2(0.045, 0.24), Vector2(0.03, 0.26)]), 10, p + inward * 0.4)
		var f := _flame(self, p + inward * 0.4 + Vector3(0, 0.33, 0), 0.11)
		f.set_meta("phase", float(k) * 1.7)
		f.add_to_group("hub_flame")
		_omni(p + inward * 0.6 + Vector3(0, 0.35, 0), Color(1.0, 0.72, 0.42), 1.5, 5.5, false, true)
	HubArchitecture.mi(self, sb.commit(), HubArchitecture.brass(), "Sconces")
	HubArchitecture.mi(self, candle.commit(), HubArchitecture.flat_toon(Color("f6ecd6"), 0.2, 0.2), "SconceCandles")
	# R1.10 bounce light. Fix r2 (visual major): at 0.9 from (0, 3, 3) it clipped Mak's cream body to white in the
	# hall; 0.6 and moved behind the clock.
	_omni(Vector3(0, 3.0, -1.0), Color("ffd9a8"), 0.6, 14.0)
	# Soft fills so corners never go muddy (no shadows).
	for spec in [[Vector3(0, 3.0, 9.0), 0.8, 14.0], [Vector3(-8.0, 2.5, -4.0), 0.6, 11.0], [Vector3(8.0, 2.5, -4.0), 0.6, 11.0], [Vector3(0, 7.0, -12.0), 0.7, 10.0], [Vector3(10.0, 6.5, 4.0), 0.5, 9.0], [Vector3(-10.0, 6.5, 6.0), 0.5, 9.0]]:
		_omni(spec[0], Color(1.0, 0.9, 0.78), spec[1], spec[2])


## World positions of candle tips on a generated chandelier: vertices binned on a 10 cm XZ grid away from the
## stem, keeping cells that are higher than all their neighbours within 25 cm.
## Per wick tip: the candle's radius (85th percentile of the horizontal vertex distance in the band 0.08-0.3 m
## below the tip, within 0.4 m), times 1.04, clamped to 0.06-0.3 m.
func _candle_radii(root: Node3D, tips: Array[Vector3]) -> Array:
	var dists: Array = []
	var y_lo := INF
	var y_hi := -INF
	for t in tips:
		dists.append(PackedFloat32Array())
		y_lo = minf(y_lo, t.y - 0.3)
		y_hi = maxf(y_hi, t.y - 0.08)
	for mi_node in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi_node as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := m.global_transform
		for si in m.mesh.get_surface_count():
			var verts: PackedVector3Array = m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w := xf * v
				if w.y < y_lo or w.y > y_hi:
					continue
				for k in tips.size():
					var t: Vector3 = tips[k]
					var dy := t.y - w.y
					if dy < 0.08 or dy > 0.3:
						continue
					var dh := Vector2(w.x - t.x, w.z - t.z).length()
					if dh < 0.4:
						(dists[k] as PackedFloat32Array).append(dh)
	var out: Array = []
	for k in tips.size():
		var arr: PackedFloat32Array = dists[k]
		if arr.size() < 8:
			out.append(0.075)
			continue
		arr.sort()
		out.append(clampf(arr[int(float(arr.size() - 1) * 0.85)] * 1.04, 0.06, 0.3))
	return out


func _candle_tips(root: Node3D) -> Array[Vector3]:
	var cells: Dictionary = {}
	for mi_node in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi_node as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := m.global_transform
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w := xf * v
				var rel := w - root.global_position
				if Vector2(rel.x, rel.z).length() < 0.6:
					continue
				var key := Vector2i(int(floor(rel.x / 0.1)), int(floor(rel.z / 0.1)))
				if not cells.has(key) or (cells[key] as Vector3).y < w.y:
					cells[key] = w
	var out: Array[Vector3] = []
	for key in cells.keys():
		var p: Vector3 = cells[key]
		var best := true
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				if dx == 0 and dz == 0:
					continue
				var n: Variant = cells.get(Vector2i(key.x + dx, key.y + dz))
				if n != null and (n as Vector3).y > p.y:
					best = false
					break
			if not best:
				break
		if best:
			out.append(p)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	return out.slice(0, 14)


# ------------------------------------------------------------------ ambient life

func _ambient() -> void:
	# Dust motes drifting in the sun shafts and over the hall.
	var dust := GPUParticles3D.new()
	dust.name = "DustMotes"
	dust.amount = 260
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.visibility_aabb = AABB(Vector3(-16, -1, -16), Vector3(32, 14, 32))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13, 4.5, 13)
	pm.direction = Vector3(0.3, 0.2, -0.1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.12
	pm.gravity = Vector3(0, 0.01, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.3
	pm.scale_max = 0.6
	var alpha := Curve.new()
	alpha.add_point(Vector2(0, 0))
	alpha.add_point(Vector2(0.2, 1))
	alpha.add_point(Vector2(0.8, 1))
	alpha.add_point(Vector2(1, 0))
	var ac := CurveTexture.new()
	ac.curve = alpha
	pm.alpha_curve = ac
	dust.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 0.85, 0.55, 0.7)
	# Motes that drift right past a camera read as big blurry balls (TitleCam, hero shot): fade them out up close.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 2.0
	m.distance_fade_max_distance = 4.5
	if ResourceLoader.exists("res://assets/textures/fx/soft_dot.webp"):
		m.albedo_texture = load("res://assets/textures/fx/soft_dot.webp")
	q.material = m
	dust.draw_pass_1 = q
	dust.position = Vector3(0, 5.0, 0)
	add_child(dust)


var _fps_log := false
var _fps_t := 0.0
var _fps_samples: Array[float] = []


func _process(delta: float) -> void:
	_t += delta
	_hat_stand_process(delta)
	if _fps_log:
		_fps_t += delta
		if _fps_t >= 1.0:
			_fps_t = 0.0
			var f := Engine.get_frames_per_second()
			_fps_samples.append(f)
			var mn := 9999.0
			var sum := 0.0
			for x in _fps_samples:
				mn = minf(mn, x)
				sum += x
			print("[HubFPS] t=%.0f fps=%.0f min=%.0f avg=%.1f size=%s" % [_t, f, mn, sum / float(_fps_samples.size()), get_viewport().get_visible_rect().size])
	for i in _flicker.size():
		var l := _flicker[i]
		var f := 0.86 + 0.08 * sin(_t * 13.0 + float(i) * 1.3) + 0.06 * sin(_t * 23.0 + float(i) * 2.1)
		l.light_energy = _flicker_base[i] * f
	for f in get_tree().get_nodes_in_group("hub_flame"):
		var mesh := f as Node3D
		var ph: float = mesh.get_meta("phase", 0.0)
		mesh.scale = Vector3(1.0 + 0.08 * sin(_t * 17.0 + ph), 1.0 + 0.16 * sin(_t * 11.0 + ph * 1.7), 1.0)
	if _pendulum:
		_pendulum.rotation_degrees.z = sin(_t * PI) * 9.0
	if _chandelier:
		_chandelier.rotation_degrees.z = sin(_t * TAU / 6.0) * 1.2
		_chandelier.rotation_degrees.x = sin(_t * TAU / 7.3) * 0.8
		_chandelier.rotation_degrees.y += delta * 2.0
	for s in get_tree().get_nodes_in_group("hub_spin"):
		(s as Node3D).rotate_object_local(Vector3.BACK, delta * 0.9)
	for s in get_tree().get_nodes_in_group("hub_sway"):
		(s as Node3D).rotation.z = sin(_t * 1.3) * 0.06
	_tapestry_fade()
	_occluder_fade()
	_ledger_near_process()
	# Locks and pop-ups follow the portals' state.
	for wid in portals.keys():
		if hold_locks:
			break
		var portal: Node3D = portals[wid]
		var open := bool(portal.get("is_open"))
		var lock: Node3D = _locks.get(wid)
		if lock and lock.visible == open:
			if open:
				_drop_lock(lock)
			else:
				lock.visible = true
		var d: Node3D = _dioramas.get(wid)
		if d and open and not d.has_meta("colour"):
			d.set_meta("colour", true)
			for c in d.find_children("*", "MeshInstance3D", true, false):
				(c as MeshInstance3D).material_override = null
			d.scale = Vector3(1, 0.05, 1)
			var tw := create_tween()
			tw.tween_property(d, "scale", _diorama_scale(wid), 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if wolf_door:
		var lk: Node3D = _locks.get("BOSS")
		if lk and lk.visible and bool(wolf_door.get("is_unlocked")):
			_drop_lock(lk)


## r1 critique: on the top balcony the camera sat behind the crest tapestry (no collision, never faded). It now
## fades to 25 % while Mak is on the balcony side of it or the camera is within 1.5 m of it.
func _tapestry_fade() -> void:
	if _tapestry == null or not _tapestry.visible or _tapestry.position.y < -1.0:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	var want := 0.0
	if p:
		var pp := p.global_position
		var pr := Vector2(pp.x, pp.z).length()
		var pth := fposmod(rad_to_deg(atan2(pp.x, -pp.z)), 360.0)
		if pp.y > 8.8 and pr > 13.0 and pth > 170.0 and pth < 210.0:
			want = 0.75
	if cam:
		var cp := cam.global_position
		var cr := Vector2(cp.x, cp.z).length()
		var cth := fposmod(rad_to_deg(atan2(cp.x, -cp.z)), 360.0)
		if cp.y > 9.0 and cth > 178.0 and cth < 202.0 and (absf(cr - 13.4) < 1.5 or cr > 13.4):
			want = 0.75
	_tapestry.transparency = lerpf(_tapestry.transparency, want, 0.15)


func _drop_lock(lock: Node3D) -> void:
	if lock.has_meta("dropping"):
		return
	lock.set_meta("dropping", true)
	var g := get_node_or_null("/root/Game")
	if g and g.has_method("unlock") and lock.has_meta("wid") and not _is_title():
		g.call("unlock", "hub_gate_seen_" + String(lock.get_meta("wid")))
	var tw := create_tween()
	tw.tween_property(lock, "position:y", -1.2, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: lock.visible = false)
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("play_sfx"):
		audio.call("play_sfx", "chime", lock.global_position)


func _on_truffle(id: String) -> void:
	# Won right here in the hub: it is already in the clock, no return flight next visit.
	var game := get_node_or_null("/root/Game")
	if game and game.has_method("unlock"):
		game.call("unlock", "hub_seen_" + id)
	if clock and clock.has_method("refresh"):
		clock.call("refresh")
	_update_bramwell()

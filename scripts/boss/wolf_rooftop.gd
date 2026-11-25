class_name WolfRooftop
extends WorldRoot
## "The Wolf's Own Tale": the boss arena at plan scale (Docs/levels/BOSS.md + BOSS_amendments R1-R3).
## A round paved rooftop (r 18) on a crooked brick tower above a stormy sunset sea of clouds:
## parapet with two crumbled gaps, the wolf's tea terrace (armchair, trolley, parasol), four Tripo P2
## chimneys rotated 45 degrees, four brass vents at r 5, the dormer hatch, the sky page, banners,
## spires, storm masses, lightning, rain and wind streaks. The fight itself lives in WolfBoss.
## Conventions: theta/bearing from north clockwise, pos = (r sin t, y, -r cos t).
## Dev args: --bosstest (bot drives the real Player through the fight), --boss-phase=<1..3>, --no-cine.

const R := 18.0
const PAVER := Color(0.70, 0.64, 0.63)
const PAVER_DARK := Color(0.46, 0.4, 0.43)
const MORTAR := Color(0.29, 0.25, 0.32)
const BRICK := Color(0.64, 0.27, 0.18)
const BRICK_DARK := Color(0.37, 0.14, 0.13)
const SANDSTONE := Color(0.85, 0.73, 0.54)
const BRASS := Color(0.79, 0.63, 0.29)
const BURGUNDY := Color(0.48, 0.12, 0.18)
const MUSTARD := Color(0.83, 0.65, 0.16)
const HAZARD := Color(1.0, 0.35, 0.24)
const CREAM := Color(1.0, 0.95, 0.84)
const LAVENDER := Color(0.72, 0.61, 0.85)
const GAPS := [[70.0, 82.0], [278.0, 290.0]]
const CHIMNEYS := {"C1": Vector3(6.72, 0, -6.72), "C2": Vector3(6.72, 0, 6.72), "C3": Vector3(-6.72, 0, 6.72), "C4": Vector3(-6.72, 0, -6.72)}
const LEE := {"C1": 132.1, "C2": 161.0, "C3": 199.0, "C4": 227.9}
const VENTS := {"V1": Vector3(0, 0, -5), "V2": Vector3(5, 0, 0), "V3": Vector3(0, 0, 5), "V4": Vector3(-5, 0, 0)}
const TERRACE_C := Vector3(0, 1.0, -15.0)
const STAND := Vector3(0, 1.0, -13.4)

var boss: WolfBoss
var chimneys: Dictionary = {}
var vents: Dictionary = {}
var lee_decals: Dictionary = {}
var sky_page: Node3D
var director: BossDirector
var hud: BossTale
var bot: Node
var trolley: Node3D
var spectators: Array = []
var hurricane := false
var phase_look := 1
var _t := 0.0
var _sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _env: Environment
var _bolt_t := 6.0
var _rain: CPUParticles3D
var _streaks: CPUParticles3D
var _shingles: CPUParticles3D
var _rng := RandomNumberGenerator.new()
var _headline: Label3D
var _chapter: Label3D
var _strike: MeshInstance3D
var _page_mat: StandardMaterial3D
var _cloud_mat: ShaderMaterial
var _lt_shaft: DirectionalLight3D
var _lt_stage: OmniLight3D
var _flags: Array[Node3D] = []
var _occluders: Array[Node3D] = []


func _ready() -> void:
	var web_trace_t := WebRuntime.trace_start()
	world_id = "BOSS"
	if display_name == "":
		display_name = "The Wolf's Own Tale"
	if ambience_key == "":
		ambience_key = "amb_storm_loop"
	music_key = "music_boss"
	_rng.seed = 2860
	_sun = get_node_or_null("Sun") as DirectionalLight3D
	if get_node_or_null("Arena") == null:
		_build()
	_setup_spawns()
	# Finish pass: the boss title shows once, on the sky page; the generic HUD entry banner repeated it twice more.
	show_entry_banner = false
	super._ready()
	# The fight.
	boss = WolfBoss.new()
	boss.name = "WolfBoss"
	boss.arena = self
	add_child(boss)
	hud = BossTale.new()
	hud.name = "BossTale"
	add_child(hud)
	director = BossDirector.new()
	director.name = "BossDirector"
	director.arena = self
	add_child(director)
	var dev := get_node_or_null("/root/Dev")
	if dev != null and dev.call("has_arg", "bosstest"):
		bot = (load("res://scripts/boss/boss_bot.gd") as GDScript).new() as Node
		bot.name = "BossBot"
		add_child(bot)
		bot.call("start", self)
	boss.begin_fight()
	WebRuntime.trace_end("builder_ready:boss/wolf_rooftop", web_trace_t)


func _setup_spawns() -> void:
	var sp := get_node_or_null("Spawns") as Node3D
	if sp == null:
		return
	for n in ["Default", "Phase2", "Phase3"]:
		var m := sp.get_node_or_null(n) as Marker3D
		if m == null:
			m = Marker3D.new()
			m.name = n
			sp.add_child(m)
		m.position = Vector3(0, 0.05, 14)
		m.rotation = Vector3.ZERO
	var t := sp.get_node_or_null("BOSS-1") as Marker3D
	if t == null:
		t = Marker3D.new()
		t.name = "BOSS-1"
		sp.add_child(t)
	t.position = Vector3(0, 0.05, 4)


func checkpoint_xform() -> Transform3D:
	# Finish pass (boss fight-design major: the respawn sat at the dormer, in the 180-degree gust lane, with the huff
	# cycle still running). Respawn 3 m into the lee of chimney C3 (sheltered from the gust apex), facing the wolf.
	var apex := Vector3(0, 0, -12.8)
	var c3: Vector3 = CHIMNEYS["C3"]
	var away := (c3 - apex).normalized()
	var pos := c3 + away * 3.0 + Vector3(0, 0.05, 0)
	var basis := Basis.looking_at((Vector3(0, 0, -13.4) - pos) * Vector3(1, 0, 1), Vector3.UP)
	return Transform3D(basis, global_position + pos)


static func polar(theta_deg: float, r: float, y: float = 0.0) -> Vector3:
	var a := deg_to_rad(theta_deg)
	return Vector3(r * sin(a), y, -r * cos(a))


static func bearing_dir(b_deg: float) -> Vector3:
	var a := deg_to_rad(b_deg)
	return Vector3(sin(a), 0, -cos(a))


static func in_gap(theta_deg: float) -> bool:
	var t := fposmod(theta_deg, 360.0)
	for g in GAPS:
		if t >= float(g[0]) and t <= float(g[1]):
			return true
	return false


static func theta_of(p: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(p.x, -p.z)), 360.0)


# ------------------------------------------------------------------ look and colour script

## Colour script per phase (R1.10 / R2.7): 1 Huff, 2 Puff, 3 Hurricane, 4 Defeat.
func set_phase_look(p: int, seconds: float = 2.5) -> void:
	phase_look = p
	hurricane = p == 3
	var key_rot: Vector3 = [Vector3(-24, -165, 0), Vector3(-24, -165, 0), Vector3(-19, -165, 0), Vector3(-15, -165, 0), Vector3(-12, -150, 0)][p]
	var key_col: Color = [Color("ffb060"), Color("ffb060"), Color("ff8a3d"), Color("f09058"), Color("ffc86b")][p]
	# Look 4 (the POP and after): a warm low sun for long shadows (was 0.3, about 0.19 energy: flat and yellow).
	# LOOK finish (phase-3 critique: a pink-magenta wash with little value contrast between Mak, the wolf and the roof):
	# a stronger key, a thinner and less magenta storm haze and a dimmer stage light in phase 3.
	var key_e: float = [2.4, 2.4, 2.1, 2.1, 2.6][p]
	var top: Color = [Color("4a2f6b"), Color("4a2f6b"), Color("3a2558"), Color("2b1e4a"), Color("6a4a8e")][p]
	var hor: Color = [Color("ff8a3d"), Color("ff8a3d"), Color("ff6a3a"), Color("d9523a"), Color("ffc93c")][p]
	var fogc: Color = [Color("6e4a6b"), Color("6e4a6b"), Color("5e3e66"), Color("3c3a58"), Color("7a5a7a")][p]
	var fogd: float = [0.005, 0.005, 0.007, 0.006, 0.004][p]
	var cover: float = [0.62, 0.62, 0.72, 0.85, 0.35][p]
	var tw := create_tween().set_parallel(true)
	if _sun != null:
		tw.tween_property(_sun, "rotation_degrees", key_rot, seconds)
		tw.tween_property(_sun, "light_color", key_col, seconds)
		# OPUSLOOK: the outro (phase 4) lights Mak with the unshadowed shaft as well; on the web the separately added sun
		# pass then clipped his whites (story-camera mean 0.52 against the desktop's 0.44), so it takes half again there.
		var web_k := SoftShadows.web_energy(_sun, "BOSS") * (0.5 if p == 4 and OS.has_feature("web") else 1.0)
		tw.tween_property(_sun, "light_energy", key_e * 0.62 * web_k, seconds)
	if _sky_mat != null:
		tw.tween_property(_sky_mat, "shader_parameter/top_color", top, seconds)
		tw.tween_property(_sky_mat, "shader_parameter/horizon_color", hor, seconds)
		tw.tween_property(_sky_mat, "shader_parameter/cloud_coverage", cover, seconds)
	if _env != null:
		tw.tween_property(_env, "fog_light_color", fogc, seconds)
		tw.tween_property(_env, "fog_density", fogd, seconds)
	if _rain != null:
		_rain.emitting = p == 3 or p == 2
		_rain.speed_scale = 1.0 if p == 3 else 0.8
	if _shingles != null:
		_shingles.emitting = p == 3
	if _lt_stage != null:
		tw.tween_property(_lt_stage, "light_energy", 0.65 if p == 3 else 0.0, seconds)
	if _lt_shaft != null:
		tw.tween_property(_lt_shaft, "light_energy", 2.6 if p == 4 else 0.0, 2.0)
	_bolt_t = minf(_bolt_t, 2.0)


func lightning(near: bool = false) -> void:
	var a := _rng.randf() * TAU
	var dist := _rng.randf_range(40.0, 70.0) if near else _rng.randf_range(70.0, 140.0)
	var base := Vector3(cos(a) * dist, -10.0, sin(a) * dist)
	if near:
		base = Vector3(_rng.randf_range(-12, 12), 10.0, -40.0)
	var bolt := Node3D.new()
	add_child(bolt)
	var p := base + Vector3(0, 55, 0)
	# r1 spectacle: a thin white-hot core with a soft violet halo and two forks, and a double flicker (was a chain of
	# nine 0.5 m BoxMesh segments shown once for 0.16 s).
	var mat := EnemyKit.glow_mat(Color(0.95, 0.96, 1.0), 10.0)
	var halo := EnemyKit.glow_mat(Color(0.7, 0.62, 1.0, 0.28), 4.0)
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var pts: Array = [p]
	for i in 11:
		var q := p + Vector3(_rng.randf_range(-4, 4), -5.5, _rng.randf_range(-4, 4))
		_bolt_seg(bolt, p, q, 0.16, mat)
		_bolt_seg(bolt, p, q, 0.9, halo)
		pts.append(q)
		p = q
	for f in 2:
		var fp: Vector3 = pts[3 + f * 3]
		for k in 3:
			var fq := fp + Vector3(_rng.randf_range(-4, 4) + (5.0 if f == 0 else -5.0), -4.0, _rng.randf_range(-3, 3))
			_bolt_seg(bolt, fp, fq, 0.09, mat)
			fp = fq
	var tw := bolt.create_tween()
	tw.tween_interval(0.07)
	tw.tween_callback(func() -> void: bolt.visible = false)
	tw.tween_interval(0.05)
	tw.tween_callback(func() -> void: bolt.visible = true)
	tw.tween_interval(0.09)
	tw.tween_callback(bolt.queue_free)
	if _sky_mat != null:
		var hz: Color = _sky_mat.get_shader_parameter("haze_color")
		_sky_mat.set_shader_parameter("haze_color", Color(1.0, 0.95, 1.0))
		get_tree().create_timer(0.15).timeout.connect(func() -> void:
			if _sky_mat != null:
				_sky_mat.set_shader_parameter("haze_color", hz))
	if _env != null:
		var ae := _env.ambient_light_energy
		_env.ambient_light_energy = ae + 0.9
		create_tween().tween_property(_env, "ambient_light_energy", ae, 0.3)
	var d := 1.5 if not near else 0.3
	get_tree().create_timer(d).timeout.connect(func() -> void:
		Audio_sfx("thunder", Vector3.INF))


func _bolt_seg(bolt: Node3D, a: Vector3, b: Vector3, w: float, mat: Material) -> void:
	var seg := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, a.distance_to(b), w)
	seg.mesh = bm
	seg.material_override = mat
	seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.add_child(seg)
	seg.global_position = (a + b) * 0.5
	var up := (a - b).normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	seg.global_basis = Basis(side, up, side.cross(up)).orthonormalized()


func Audio_sfx(key: String, at: Vector3 = Vector3.INF) -> void:
	var a := get_node_or_null("/root/Audio")
	if a != null and a.has_method("play_sfx"):
		a.call("play_sfx", key, at)


func _process(delta: float) -> void:
	_t += delta
	var lo: Array = [[10.0, 14.0], [10.0, 14.0], [6.0, 10.0], [3.0, 6.0], [999.0, 999.0]]
	if phase_look < 4:
		_bolt_t -= delta
		if _bolt_t <= 0.0:
			var rng_lo: Array = lo[phase_look]
			_bolt_t = _rng.randf_range(float(rng_lo[0]), float(rng_lo[1]))
			lightning()
	# Banners and flags flutter.
	for i in _flags.size():
		var f := _flags[i]
		f.rotation.y = float(f.get_meta("yaw0", 0.0)) + sin(_t * 3.1 + float(i)) * 0.18
		f.rotation.z = sin(_t * 5.3 + float(i) * 2.0) * 0.06
	if _headline != null:
		sky_page.rotation.z = sin(_t * 0.7) * 0.012
		sky_page.position.y = 12.0 + sin(_t * 0.5) * 0.15
	# Rain follows the active camera so it is always around the view.
	var cam := get_viewport().get_camera_3d()
	if cam != null and _rain != null:
		_rain.global_position = cam.global_position + Vector3(0, 9, 0) - cam.global_basis.z * 6.0
	_fade_occluders(cam, delta)


## Rim props (banner poles) that stand between the gameplay camera and Mak fade out instead of filling the frame:
## BossFraming keeps the camera on the wolf-to-Mak line, so near the south rim it sits outside the parapet.
func _fade_occluders(cam: Camera3D, delta: float) -> void:
	if cam == null or player == null or _occluders.is_empty():
		return
	var a := Vector2(cam.global_position.x, cam.global_position.z)
	var b := Vector2(player.global_position.x, player.global_position.z)
	var look2 := Vector2.INF
	if director != null and (director.in_cine or director.hold_cam_id != ""):
		var fwd := -cam.global_basis.z
		var hit := cam.global_position + fwd * 12.0
		look2 = Vector2(hit.x, hit.z)
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 0.0001)
	for o in _occluders:
		var c := Vector2(o.global_position.x, o.global_position.z)
		var k := clampf((c - a).dot(ab) / l2, 0.0, 1.0)
		var blocking := k > 0.0 and k < 0.97 and (a + ab * k).distance_to(c) < 1.9
		if not blocking and look2 != Vector2.INF:
			# During a cine or hold, also test the camera-to-look-target segment (r1 spectacle: a ghost pole crossed
			# the wolf in the defeat hold).
			var ab2 := look2 - a
			var k2 := clampf((c - a).dot(ab2) / maxf(ab2.length_squared(), 0.0001), 0.0, 1.0)
			blocking = k2 > 0.0 and k2 < 0.97 and (a + ab2 * k2).distance_to(c) < 2.5
		var f := float(o.get_meta("fade", 0.0))
		# Fade all the way out and hide (r1 spectacle major: stopping at 0.82 left an 18 % ghost column in frame).
		f = move_toward(f, 1.0 if blocking else 0.0, delta * 4.0)
		if absf(f - float(o.get_meta("fade", 0.0))) < 0.0001:
			continue
		o.set_meta("fade", f)
		for g in o.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).transparency = f
			(g as GeometryInstance3D).visible = f < 0.99


# ------------------------------------------------------------------ sky page

func page_headline(text: String, chapter: String = "", strike_first: bool = false) -> void:
	if _headline == null:
		return
	if strike_first and _headline.text != "":
		_strike.visible = true
		_strike.scale = Vector3(0.01, 1, 1)
		var tw := create_tween()
		tw.tween_property(_strike, "scale", Vector3(1, 1, 1), 0.4).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(0.35)
		tw.tween_callback(func() -> void:
			_strike.visible = false
			_type_headline(text, chapter))
	else:
		_type_headline(text, chapter)


func _type_headline(text: String, chapter: String) -> void:
	if chapter != "":
		_chapter.text = chapter
	_headline.text = ""
	create_tween().tween_method(func(k: float) -> void:
		_headline.text = text.substr(0, int(round(k * float(text.length())))), 0.0, 1.0, 0.8)
	Audio_sfx("book_page_turn", Vector3.INF)


func page_stamp(text: String, color: Color = Color(0.72, 0.1, 0.1)) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = _headline.font
	l.font_size = 520
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 0
	l.position = Vector3(0, -0.6, 0.08)
	l.rotation_degrees.z = 12.0
	l.double_sided = false
	sky_page.add_child(l)
	l.scale = Vector3(2.5, 2.5, 2.5)
	create_tween().tween_property(l, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if is_instance_valid(l):
			EnemyKit.fade_free(l, 0.4))


# ------------------------------------------------------------------ build

func _build() -> void:
	var arena := Node3D.new()
	arena.name = "Arena"
	add_child(arena)
	_build_env()
	_build_roof(arena)
	_build_parapet(arena)
	_build_terrace(arena)
	_build_chimneys(arena)
	_build_vents(arena)
	_build_dormer(arena)
	_build_props(arena)
	_build_sky_page(arena)
	_build_surroundings(arena)
	_build_weather(arena)
	_build_acorns(arena)
	_build_cams()


func _build_env() -> void:
	FxEnvironments.apply(self, "BOSS", false)
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		_env = we.environment.duplicate() as Environment
		we.environment = _env
		if _env.sky != null:
			_env.sky = _env.sky.duplicate() as Sky
			if _env.sky.sky_material is ShaderMaterial:
				_sky_mat = (_env.sky.sky_material as ShaderMaterial).duplicate() as ShaderMaterial
				_env.sky.sky_material = _sky_mat
		_env.fog_enabled = true
		_env.fog_light_color = Color("6e4a6b")
		_env.fog_density = 0.005
		_env.fog_height = -10.0
		_env.fog_height_density = 0.03
		# r1 spectacle major: a flat COLOR ambient (6f5a8c at 0.8) lifted every shadow to mid-lilac (P2/P3 tonal range
		# 66 levels against 133 in concept 09). Sky ambient, lower, with a little lilac kept, plus stronger SSAO.
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_env.ambient_light_sky_contribution = 0.75
		_env.ambient_light_color = Color("6f5a8c")
		_env.ambient_light_energy = 0.45
		_env.ssao_intensity = 1.8
		_env.adjustment_enabled = true
		_env.adjustment_contrast = 1.12
		_env.adjustment_saturation = 1.06
		_env.glow_enabled = true
		_env.ssao_enabled = true
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("sun_size", 0.07)
		_sky_mat.set_shader_parameter("sun_glow", 0.8)
	if _sun == null:
		_sun = DirectionalLight3D.new()
		_sun.name = "Sun"
		add_child(_sun)
	_sun.rotation_degrees = Vector3(-24, -165, 0)
	_sun.light_color = Color("ffb060")
	_sun.light_energy = 1.5
	_sun.shadow_enabled = true
	_sun.shadow_opacity = 0.75
	_sun.shadow_blur = 1.4
	_sun.directional_shadow_max_distance = 80.0
	var fill := DirectionalLight3D.new()
	fill.name = "LT_fill"
	fill.rotation_degrees = Vector3(-30, 20, 0)
	fill.light_color = Color("b79bd9")
	fill.light_energy = 0.45
	add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "LT_rim"
	rim.rotation_degrees = Vector3(-25, 60, 0)
	rim.light_color = Color("8c7cff")
	rim.light_energy = 0.4
	add_child(rim)
	var ck := DirectionalLight3D.new()
	ck.name = "LT_char_key"
	ck.rotation_degrees = Vector3(-35, 15, 0)
	ck.light_color = Color("ffe4c4")
	ck.light_energy = 0.7
	if OS.has_feature("web"):
		# OPUSLOOK: Mak and the wolf already get this key in the base pass; on the web the sun pass is added on top after
		# encoding and his whites clipped in close-ups (outro mean 0.52 against the desktop's 0.44). Half the key there.
		ck.light_energy = 0.35
	ck.light_cull_mask = 2
	add_child(ck)
	_lt_shaft = DirectionalLight3D.new()
	_lt_shaft.name = "LT_shaft"
	_lt_shaft.rotation_degrees = Vector3(-58, 30, 0)
	_lt_shaft.light_color = Color("ffc86b")
	_lt_shaft.light_energy = 0.0
	add_child(_lt_shaft)
	_lt_stage = OmniLight3D.new()
	_lt_stage.name = "LT_stage"
	_lt_stage.position = Vector3(0, 6, 0)
	_lt_stage.light_color = Color("ffb27a")
	_lt_stage.light_energy = 0.0
	_lt_stage.omni_range = 14.0
	add_child(_lt_stage)
	set_phase_look(1, 0.01)


func _toon(c: Color, tex: String, tri: float) -> Material:
	if ResourceLoader.exists("res://assets/textures/%s.webp" % tex):
		return FxMaterials.toon(c, tex, tri)
	return EnemyKit.mat(c)


func _build_roof(arena: Node3D) -> void:
	var roof := StaticBody3D.new()
	roof.name = "Roof"
	roof.collision_layer = 1
	arena.add_child(roof)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = R + 0.6
	cyl.height = 2.0
	cs.shape = cyl
	cs.position = Vector3(0, -1.0, 0)
	roof.add_child(cs)
	# Paver disc (herringbone stone, grey-rose), moss ring and the compass rose.
	var disc := EnemyKit.cylinder(roof, R + 0.6, R + 0.6, 0.6, PAVER, Vector3(0, -0.3, 0))
	disc.material_override = _toon(Color(0.98, 0.9, 0.88), "castle_stone", 0.45)
	var moss := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 14.0
	tm.outer_radius = 18.0
	tm.rings = 64
	tm.ring_segments = 6
	moss.mesh = tm
	moss.scale = Vector3(1, 0.012, 1)
	moss.position = Vector3(0, 0.005, 0)
	var mm := EnemyKit.mat(Color(0.42, 0.5, 0.36, 0.22), 0.9, 0.1)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	moss.material_override = mm
	moss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	roof.add_child(moss)
	var rose := EnemyKit.cylinder(roof, 3.0, 3.0, 0.04, SANDSTONE, Vector3(0, 0.01, 0))
	rose.material_override = _toon(SANDSTONE, "parchment", 0.3)
	var ringm := EnemyKit.mat(BRASS, 0.3, 0.25, 0.85)
	for rr in [1.0, 2.0, 2.95]:
		var rg := EnemyKit.ring(roof, rr - 0.06, rr + 0.06, BRASS, Vector3(0, 0.035, 0))
		rg.material_override = ringm
		rg.scale = Vector3(1, 0.2, 1)
	for k in 4:
		var len := 5.6 if k % 2 == 0 else 3.6
		var pt := EnemyKit.box(roof, Vector3(0.18, 0.03, len), BRASS if k % 2 == 0 else BRICK, Vector3(0, 0.04, 0))
		pt.rotation_degrees.y = float(k) * 45.0
		pt.material_override = ringm if k % 2 == 0 else EnemyKit.mat(BRICK)
	# Cornice skirt and the crooked tower falling into the clouds.
	var cornice := EnemyKit.cylinder(roof, R + 1.0, R + 0.4, 1.0, SANDSTONE, Vector3(0, -1.1, 0))
	cornice.material_override = _toon(SANDSTONE, "castle_stone", 0.3)
	var tower := EnemyKit.cylinder(roof, R - 1.0, 12.0, 58.0, BRICK, Vector3(0, -30.0, 0))
	tower.material_override = _toon(Color(0.95, 0.75, 0.7), "brick", 0.4)
	tower.rotation_degrees.z = 1.5
	for i in 4:
		var band := EnemyKit.cylinder(roof, R - 1.2 - float(i) * 1.1, R - 1.2 - float(i) * 1.1, 0.5, BRICK_DARK, Vector3(0, -6.0 - float(i) * 9.0, 0))
		band.material_override = EnemyKit.mat(BRICK_DARK)
	var wmat := EnemyKit.glow_mat(Color(1.0, 0.78, 0.4), 2.2)
	for i in 14:
		var a := _rng.randf() * TAU
		var y := _rng.randf_range(-4.0, -26.0)
		var rr := lerpf(R - 1.0, 12.0, (-y - 1.0) / 58.0) + 0.05
		var w := EnemyKit.box(roof, Vector3(0.7, 1.1, 0.2), Color(1, 0.8, 0.4), Vector3(cos(a) * rr, y, sin(a) * rr))
		w.rotation.y = -a + PI * 0.5
		w.material_override = wmat


func _build_parapet(arena: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Parapet"
	arena.add_child(holder)
	var bm := _toon(Color(1.0, 0.82, 0.76), "brick", 1.2)
	var cm := _toon(SANDSTONE, "castle_stone", 0.6)
	var n := 72
	for i in n:
		var t0 := float(i) * 360.0 / float(n)
		var tc := t0 + 2.5
		if in_gap(tc) or in_gap(t0) or in_gap(t0 + 5.0):
			continue
		var b := StaticBody3D.new()
		b.collision_layer = 1
		holder.add_child(b)
		b.position = polar(tc, R + 0.3, 0.4)
		b.rotation.y = -deg_to_rad(tc)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(TAU * (R + 0.3) / float(n) + 0.04, 0.8, 0.6)
		cs.shape = bs
		b.add_child(cs)
		var wall := EnemyKit.box(b, bs.size, BRICK, Vector3.ZERO)
		wall.material_override = bm
		var cop := EnemyKit.box(b, Vector3(bs.size.x + 0.02, 0.14, 0.8), SANDSTONE, Vector3(0, 0.45, 0))
		cop.material_override = cm
	# Crumbled gap lips: scattered bricks.
	for g in GAPS:
		for k in 9:
			var th := _rng.randf_range(float(g[0]) - 1.0, float(g[1]) + 1.0)
			var br := EnemyKit.box(holder, Vector3(0.45, 0.22, 0.25), BRICK.darkened(_rng.randf() * 0.3), polar(th, _rng.randf_range(16.8, 18.9), 0.1))
			br.rotation = Vector3(_rng.randf() * 0.6, _rng.randf() * TAU, _rng.randf() * 0.6)
		for edge in [float(g[0]), float(g[1])]:
			var stub := EnemyKit.box(holder, Vector3(0.5, 0.5, 0.7), BRICK, polar(edge, R + 0.3, 0.25))
			stub.rotation.y = -deg_to_rad(edge)
			stub.material_override = bm
	# Wolf-head gargoyles on corbels at 45/135/225/315 (procedural silhouettes).
	for th in [45.0, 135.0, 225.0, 315.0]:
		var gg := Node3D.new()
		holder.add_child(gg)
		gg.position = polar(th, R + 0.55, 0.75)
		gg.rotation.y = -deg_to_rad(th) + PI
		var stone := Color(0.55, 0.5, 0.55)
		EnemyKit.box(gg, Vector3(0.7, 0.3, 0.9), SANDSTONE, Vector3(0, 0, 0))
		EnemyKit.ball(gg, 0.32, stone, Vector3(0, 0.38, 0.1), Vector3(1, 0.95, 1.1))
		EnemyKit.capsule(gg, 0.14, 0.6, stone, Vector3(0, 0.3, 0.45), Vector3(80, 0, 0))
		EnemyKit.cone(gg, 0.12, 0.3, stone, Vector3(0.18, 0.7, 0.05), Vector3(0, 0, -15))
		EnemyKit.cone(gg, 0.12, 0.3, stone, Vector3(-0.18, 0.7, 0.05), Vector3(0, 0, 15))


func _build_terrace(arena: Node3D) -> void:
	# Raised sandstone tea terrace (r 4.5 at (0, 1, -15)), clipped by the roof edge with CSG.
	var comb := CSGCombiner3D.new()
	comb.name = "Terrace"
	comb.use_collision = true
	comb.collision_layer = 1
	arena.add_child(comb)
	var t := CSGCylinder3D.new()
	t.radius = 4.5
	t.height = 1.0
	t.sides = 40
	t.position = Vector3(0, 0.5, -15.0)
	t.material = _toon(SANDSTONE, "castle_stone", 0.5)
	comb.add_child(t)
	var clip := CSGCylinder3D.new()
	clip.radius = R - 0.02
	clip.height = 4.0
	clip.sides = 72
	clip.operation = CSGShape3D.OPERATION_INTERSECTION
	clip.position = Vector3(0, 0.5, 0)
	comb.add_child(clip)
	var step := StaticBody3D.new()
	step.collision_layer = 1
	arena.add_child(step)
	step.position = Vector3(0, 0.25, -10.55)
	var scs := CollisionShape3D.new()
	var sb := BoxShape3D.new()
	sb.size = Vector3(4.0, 0.5, 0.7)
	scs.shape = sb
	step.add_child(scs)
	var sv := EnemyKit.box(step, sb.size, SANDSTONE, Vector3.ZERO)
	sv.material_override = t.material
	# Brass trim on the terrace rim.
	var trim := EnemyKit.ring(arena, 4.45, 4.6, BRASS, Vector3(0, 1.0, -15.0))
	trim.scale = Vector3(1, 0.3, 1)
	trim.material_override = EnemyKit.mat(BRASS, 0.3, 0.25, 0.85)


func _build_chimneys(arena: Node3D) -> void:
	var yaws := {"C1": 0.0, "C2": 90.0, "C3": 180.0, "C4": 270.0}
	for id in CHIMNEYS.keys():
		var ch := BossChimney.new()
		ch.name = "Chimney_" + String(id)
		ch.label = String(id)
		ch.mesh_yaw_deg = float(yaws[id])
		ch.position = CHIMNEYS[id]
		ch.rotation_degrees.y = 45.0
		arena.add_child(ch)
		chimneys[id] = ch
		_build_lee_decal(arena, String(id))
	# Variant attachments: Tall Tom's extra pot, Squat Sid's pig weathervane, Ivy's lantern.
	var c1: BossChimney = chimneys["C1"]
	EnemyKit.cylinder(c1, 0.18, 0.22, 0.9, Color(0.72, 0.42, 0.3), Vector3(0.75, 4.85, -0.6))
	var c2: BossChimney = chimneys["C2"]
	var vane := Node3D.new()
	c2.add_child(vane)
	vane.position = Vector3(-0.7, 4.4, 0.7)
	EnemyKit.cylinder(vane, 0.03, 0.03, 1.4, BRASS, Vector3(0, 0.7, 0))
	EnemyKit.ball(vane, 0.22, BRASS, Vector3(0, 1.5, 0), Vector3(1.4, 1, 0.8))
	EnemyKit.ball(vane, 0.1, BRASS, Vector3(0.3, 1.52, 0), Vector3(0.6, 0.6, 0.6))
	_flags.append(vane)
	var c3: BossChimney = chimneys["C3"]
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("ffc46b")
	lamp.light_energy = 0.6
	lamp.omni_range = 3.0
	lamp.position = Vector3(1.6, 2.6, 0)
	c3.add_child(lamp)
	var lg := EnemyKit.ball(c3, 0.16, Color(1, 0.8, 0.4), Vector3(1.6, 2.5, 0))
	lg.material_override = EnemyKit.glow_mat(Color(1, 0.75, 0.35), 3.0)
	EnemyKit.box(c3, Vector3(0.5, 0.05, 0.05), Color(0.1, 0.1, 0.1), Vector3(1.35, 2.8, 0))


## Lavender lee wedge behind each chimney: the exact gust shadow from the apex (R2.2.4), P1 only.
func _build_lee_decal(arena: Node3D, id: String) -> void:
	var c: Vector3 = CHIMNEYS[id]
	var apex := Vector3(0, 0, -12.8)
	var d := (c - apex)
	d.y = 0
	var dist := d.length()
	var dir := d / dist
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Wedge from 1.6 m behind the centre out to the rim, widening with the shadow (half width grows from 1.6).
	var side := Vector3(-dir.z, 0, dir.x)
	var near_c := c + dir * 1.6
	var far_len := 0.0
	for k in 40:
		var q := c + dir * float(k)
		if Vector2(q.x, q.z).length() > R - 0.4:
			break
		far_len = float(k)
	var far_c := c + dir * far_len
	var w0 := 1.55
	var w1 := w0 * (dist + far_len) / dist
	var pts := [near_c - side * w0, near_c + side * w0, far_c + side * w1, far_c - side * w1]
	for idx in [0, 1, 2, 0, 2, 3]:
		var v: Vector3 = pts[idx]
		st.set_uv(Vector2(0.0 if idx in [0, 3] else 1.0, 0.0 if idx in [0, 1] else 1.0))
		st.add_vertex(Vector3(v.x, 0.02, v.z))
	st.generate_normals()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(LAVENDER.r, LAVENDER.g, LAVENDER.b, 0.32)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Lee_" + id
	arena.add_child(mi)
	lee_decals[id] = mi
	# Near band (turns hazard orange in the Chimney Sweep tell).
	var nb := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.0, 1.9)
	nb.mesh = pm
	nb.position = c + dir * 2.05 + Vector3(0, 0.03, 0)
	nb.rotation.y = atan2(dir.x, dir.z)
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(HAZARD.r, HAZARD.g, HAZARD.b, 0.0)
	nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nb.material_override = nm
	nb.name = "LeeNear_" + id
	nb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arena.add_child(nb)


func set_lee_visible(on: bool) -> void:
	for id in lee_decals.keys():
		var mi: MeshInstance3D = lee_decals[id]
		var m := mi.material_override as StandardMaterial3D
		create_tween().tween_property(m, "albedo_color:a", 0.32 if on else 0.0, 0.6)


func set_near_bands(alpha: float) -> void:
	var arena := get_node_or_null("Arena")
	if arena == null:
		return
	for id in CHIMNEYS.keys():
		var nb := arena.get_node_or_null("LeeNear_" + String(id)) as MeshInstance3D
		if nb != null:
			(nb.material_override as StandardMaterial3D).albedo_color.a = alpha


func _build_vents(arena: Node3D) -> void:
	for id in VENTS.keys():
		var v := BossVent.new()
		v.name = "Vent_" + String(id)
		v.vid = String(id)
		v.position = VENTS[id]
		arena.add_child(v)
		vents[id] = v


func _build_dormer(arena: Node3D) -> void:
	var d := StaticBody3D.new()
	d.name = "Dormer"
	d.collision_layer = 1
	arena.add_child(d)
	# Off the spawn line (x -3.4): on the axis it sat 3.2 m behind the spawn, so BossFraming's camera (10 m behind
	# Mak on the wolf-to-Mak line) ended inside the ajar door on every arrival from the hub. Door still faces the centre.
	d.position = Vector3(-3.4, 0, 16.9)
	d.rotation_degrees.y = -11.4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	# Deep enough to hold the ajar door leaf and its glow, so the camera spring stops outside every visible mesh.
	bs.size = Vector3(2.6, 3.0, 2.2)
	cs.shape = bs
	cs.position = Vector3(0, 1.5, -0.3)
	d.add_child(cs)
	var wall := EnemyKit.box(d, Vector3(2.6, 2.4, 1.6), BRICK, Vector3(0, 1.2, 0))
	wall.material_override = _toon(Color(1.0, 0.82, 0.76), "brick", 1.0)
	var slate := _toon(Color(0.55, 0.55, 0.68), "roof_shingles_slate", 0.8)
	for s in [-1.0, 1.0]:
		var rf := EnemyKit.box(d, Vector3(1.6, 0.12, 1.9), Color(0.35, 0.35, 0.45), Vector3(0.62 * s, 2.75, 0), Vector3(0, 0, -38.0 * s))
		rf.material_override = slate
	var door := EnemyKit.box(d, Vector3(1.1, 1.8, 0.1), Color(0.36, 0.22, 0.14), Vector3(0, 0.9, -0.82))
	door.material_override = _toon(Color(0.7, 0.5, 0.36), "wood_planks", 1.0)
	door.rotation_degrees.y = -25.0
	var glow := EnemyKit.box(d, Vector3(1.0, 1.7, 0.05), Color(1, 0.8, 0.45), Vector3(0, 0.88, -0.78))
	glow.material_override = EnemyKit.glow_mat(Color(1.0, 0.75, 0.4), 1.6)
	var knob := EnemyKit.ball(d, 0.06, BRASS, Vector3(0.4, 0.9, -0.9))
	knob.material_override = EnemyKit.mat(BRASS, 0.3, 0.3, 0.9)


func _build_props(arena: Node3D) -> void:
	# The wolf's throne: the Tripo P2 wingback armchair at 1.8x, tinted bottle green.
	var chair_path := "res://assets/props/hub/wingback_armchair_v2/wingback_armchair_v2.glb"
	if ResourceLoader.exists(chair_path):
		var chair := Node3D.new()
		chair.name = "Throne"
		arena.add_child(chair)
		chair.position = Vector3(0, 1.0, -16.6)
		var m := (load(chair_path) as PackedScene).instantiate() as Node3D
		m.rotation_degrees.y = 0.0
		m.scale = Vector3.ONE * 1.8
		chair.add_child(m)
		for n in m.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for s in mi.get_surface_override_material_count():
				var src := mi.mesh.surface_get_material(s)
				if src is StandardMaterial3D:
					var dup := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.albedo_color = Color(0.45, 0.85, 0.62)
					mi.set_surface_override_material(s, dup)
	# Tea trolley (Tripo P2) with the silver teapot on its socket.
	trolley = Node3D.new()
	trolley.name = "TeaTrolley"
	arena.add_child(trolley)
	trolley.position = Vector3(2.6, 1.0, -15.2)
	trolley.rotation_degrees.y = -20.0
	var tp := "res://assets/props/boss/tea_trolley/tea_trolley.glb"
	if ResourceLoader.exists(tp):
		var tr := (load(tp) as PackedScene).instantiate() as Node3D
		tr.scale = Vector3.ONE * 1.25
		tr.rotation_degrees.y = 180.0
		trolley.add_child(tr)
		var pot_p := "res://assets/props/boss/teapot/teapot.glb"
		if ResourceLoader.exists(pot_p):
			var pot := (load(pot_p) as PackedScene).instantiate() as Node3D
			pot.scale = Vector3.ONE * 0.7
			var sock := tr.find_child("teapot_socket", true, false) as Node3D
			(sock if sock != null else tr).add_child(pot)
	var steam := CPUParticles3D.new()
	steam.amount = 10
	steam.lifetime = 1.6
	steam.direction = Vector3.UP
	steam.spread = 10.0
	steam.initial_velocity_min = 0.4
	steam.initial_velocity_max = 0.7
	steam.gravity = Vector3(0.2, 0.2, 0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.45))
	g.set_color(1, Color(1, 1, 1, 0))
	steam.color_ramp = g
	var sph := SphereMesh.new()
	sph.radius = 0.08
	sph.height = 0.16
	steam.mesh = sph
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	steam.material_override = sm
	steam.position = Vector3(0.4, 1.5, 0)
	trolley.add_child(steam)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 1.4, 0)
	lamp.light_color = Color("ffc46b")
	lamp.light_energy = 0.9
	lamp.omni_range = 4.0
	trolley.add_child(lamp)
	# Striped parasol with a standable canopy (r 1.4, top y 4.0).
	var para := StaticBody3D.new()
	para.name = "Parasol"
	para.collision_layer = 1
	arena.add_child(para)
	para.position = Vector3(-2.6, 1.0, -15.4)
	EnemyKit.cylinder(para, 0.05, 0.05, 3.0, BRASS, Vector3(0, 1.5, 0)).material_override = EnemyKit.mat(BRASS, 0.3, 0.3, 0.9)
	var canopy := Node3D.new()
	para.add_child(canopy)
	canopy.position = Vector3(0, 2.75, 0)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 1.6
	cm.height = 0.55
	cm.radial_segments = 24
	cone.mesh = cm
	var stripes := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nuniform vec4 a : source_color = vec4(0.48,0.12,0.18,1.0);\nuniform vec4 b : source_color = vec4(1.0,0.95,0.84,1.0);\nvoid fragment(){ float s = step(0.5, fract(atan(VERTEX.x, VERTEX.z) * 0.0 + UV.x * 12.0)); ALBEDO = mix(a.rgb, b.rgb, s); ROUGHNESS = 0.8; }\n"
	stripes.shader = sh
	cone.material_override = stripes
	canopy.add_child(cone)
	for k in 12:
		var a := TAU * float(k) / 12.0
		EnemyKit.ball(canopy, 0.06, MUSTARD, Vector3(cos(a) * 1.58, -0.32, sin(a) * 1.58))
	var ccs := CollisionShape3D.new()
	var ccyl := CylinderShape3D.new()
	ccyl.radius = 1.4
	ccyl.height = 0.2
	ccs.shape = ccyl
	ccs.position = Vector3(0, 2.9, 0)
	para.add_child(ccs)
	EnemyKit.ball(para, 0.16, BRASS, Vector3(0, 3.15, 0))
	# Side table with The Daily Howl.
	var tbl := Node3D.new()
	arena.add_child(tbl)
	tbl.position = Vector3(-1.4, 1.0, -16.9)
	EnemyKit.cylinder(tbl, 0.45, 0.45, 0.06, Color(0.4, 0.25, 0.15), Vector3(0, 0.8, 0))
	EnemyKit.cylinder(tbl, 0.05, 0.08, 0.8, Color(0.3, 0.2, 0.12), Vector3(0, 0.4, 0))
	EnemyKit.box(tbl, Vector3(0.5, 0.03, 0.36), Color(0.92, 0.9, 0.82), Vector3(0, 0.85, 0), Vector3(0, 20, 0))
	# Banner poles at theta 150 and 210 (burgundy with a mustard crest).
	for th in [150.0, 210.0]:
		var pole := Node3D.new()
		arena.add_child(pole)
		pole.position = polar(th, 17.6)
		EnemyKit.cylinder(pole, 0.12, 0.14, 5.0, Color(0.25, 0.2, 0.18), Vector3(0, 2.5, 0))
		EnemyKit.ball(pole, 0.22, BRASS, Vector3(0, 5.05, 0)).material_override = EnemyKit.mat(BRASS, 0.3, 0.3, 0.9)
		var flag := Node3D.new()
		pole.add_child(flag)
		flag.position = Vector3(0, 4.7, 0)
		var cloth := EnemyKit.box(flag, Vector3(0.05, 2.4, 1.2), BURGUNDY, Vector3(0, -1.2, 0.65))
		cloth.material_override = EnemyKit.mat(BURGUNDY, 0.85, 0.2)
		var crest := EnemyKit.ball(flag, 0.32, MUSTARD, Vector3(0.04, -1.0, 0.65), Vector3(0.2, 1, 1))
		crest.material_override = EnemyKit.mat(MUSTARD, 0.5, 0.3, 0.4)
		flag.rotation.y = deg_to_rad(-th) + PI * 0.5
		flag.set_meta("yaw0", flag.rotation.y)
		_flags.append(flag)
		_occluders.append(pole)
	# Checkpoint bookmark.
	if ResourceLoader.exists("res://scenes/objects/Checkpoint.tscn"):
		var bk := (load("res://scenes/objects/Checkpoint.tscn") as PackedScene).instantiate() as Node3D
		bk.set("world_id", "BOSS")
		bk.position = Vector3(2.2, 0, 15.2)
		arena.add_child(bk)
		_occluders.append(bk)


func _build_sky_page(arena: Node3D) -> void:
	sky_page = Node3D.new()
	sky_page.name = "SkyPage"
	arena.add_child(sky_page)
	sky_page.position = Vector3(0, 12, -24)
	sky_page.rotation_degrees.x = -10.0
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(18, 10)
	qm.subdivide_width = 16
	qm.subdivide_depth = 8
	quad.mesh = qm
	var pm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.95, 0.9, 0.77, 1.0);
void vertex(){
	float c = (UV.x - 0.5);
	VERTEX.z += 0.6 * c * c * 4.0 - 0.3 + sin(TIME * 1.3 + UV.x * 5.0) * 0.12 * UV.y;
}
void fragment(){
	vec3 t = texture(tex, UV * vec2(1.8, 1.0)).rgb;
	float edge = smoothstep(0.0, 0.04, UV.x) * smoothstep(0.0, 0.04, 1.0 - UV.x) * smoothstep(0.0, 0.05, UV.y) * smoothstep(0.0, 0.05, 1.0 - UV.y);
	ALBEDO = tint.rgb * mix(vec3(0.62, 0.42, 0.26), t, 0.5 + 0.5 * edge) * 0.92;
	ROUGHNESS = 0.9;
	EMISSION = tint.rgb * 0.08;
	BACKLIGHT = vec3(0.6, 0.4, 0.25);
}
"""
	pm.shader = sh
	if ResourceLoader.exists("res://assets/textures/parchment.webp"):
		pm.set_shader_parameter("tex", load("res://assets/textures/parchment.webp"))
	quad.material_override = pm
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_page.add_child(quad)
	var font: Font = null
	if ResourceLoader.exists("res://assets/fonts/cherryswash/CherrySwash-Bold.ttf"):
		font = load("res://assets/fonts/cherryswash/CherrySwash-Bold.ttf") as Font
	_chapter = Label3D.new()
	_chapter.font = font
	_chapter.font_size = 200
	_chapter.pixel_size = 0.004
	_chapter.modulate = Color("3b2416")
	_chapter.outline_size = 0
	_chapter.position = Vector3(0, 3.2, 0.35)
	_chapter.text = "Prologue"
	sky_page.add_child(_chapter)
	_headline = Label3D.new()
	_headline.font = font
	_headline.font_size = 440
	_headline.pixel_size = 0.004
	_headline.modulate = Color("3b2416")
	_headline.outline_size = 0
	_headline.line_spacing = -60.0
	_headline.position = Vector3(0, -0.2, 0.35)
	_headline.text = "THE WOLF'S\nOWN TALE"
	_headline.width = 4200.0
	_headline.autowrap_mode = TextServer.AUTOWRAP_OFF
	sky_page.add_child(_headline)
	_strike = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(15.0, 0.28, 0.05)
	_strike.mesh = bm
	_strike.material_override = EnemyKit.unshaded(Color(0.62, 0.08, 0.08))
	_strike.position = Vector3(0, -0.2, 0.4)
	_strike.rotation_degrees.z = -3.0
	_strike.visible = false
	sky_page.add_child(_strike)
	# Two brass clips hold the page to the sky.
	for x in [-8.6, 8.6]:
		var clip := EnemyKit.box(sky_page, Vector3(0.6, 1.2, 0.2), BRASS, Vector3(x, 4.6, 0.25))
		clip.material_override = EnemyKit.mat(BRASS, 0.3, 0.3, 0.9)


func _build_surroundings(arena: Node3D) -> void:
	# Cloud sea: layered noise drifting east (shader embedded, procedural).
	var sea := MeshInstance3D.new()
	sea.name = "CloudSea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	pm.subdivide_width = 60
	pm.subdivide_depth = 60
	sea.mesh = pm
	sea.position = Vector3(0, -30, 0)
	_cloud_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 lit : source_color = vec4(0.95, 0.65, 0.48, 1.0);
uniform vec4 shade : source_color = vec4(0.29, 0.22, 0.35, 1.0);
uniform vec4 far_col : source_color = vec4(0.62, 0.38, 0.45, 1.0);
float h(vec2 p){ return fract(sin(dot(floor(p), vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(h(i), h(i+vec2(1,0)), f.x), mix(h(i+vec2(0,1)), h(i+vec2(1,1)), f.x), f.y); }
float fbm(vec2 p){ float s = 0.0; float a = 0.5; for (int k = 0; k < 5; k++){ s += a * n(p); p *= 2.03; a *= 0.5; } return s; }
varying float vh;
varying vec3 wp;
void vertex(){
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * 0.012 + vec2(TIME * 0.0012, 0.0);
	vh = fbm(p * 2.0);
	VERTEX.y += vh * 14.0;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
	vec2 p = wp.xz * 0.03 + vec2(TIME * 0.006, 0.0);
	float d = fbm(p) * 0.6 + vh * 0.7;
	float lum = smoothstep(0.35, 0.85, d);
	vec3 c = mix(shade.rgb, lit.rgb, floor(lum * 4.0 + 0.5) / 4.0);
	float far = smoothstep(80.0, 400.0, length(wp.xz));
	ALBEDO = mix(c, far_col.rgb, far * 0.6);
	EMISSION = ALBEDO * 0.25;
	ROUGHNESS = 1.0;
}
"""
	_cloud_mat.shader = sh
	sea.material_override = _cloud_mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arena.add_child(sea)
	# Crooked spires poking out of the clouds.
	var spires := [[Vector3(-70, -30, -40), 38.0], [Vector3(55, -30, -85), 30.0], [Vector3(95, -30, 30), 22.0], [Vector3(-35, -30, 110), 26.0], [Vector3(-150, -30, -160), 55.0]]
	var bm := _toon(Color(0.85, 0.6, 0.55), "brick", 0.3)
	var sl := _toon(Color(0.45, 0.42, 0.55), "roof_shingles_slate", 0.3)
	for s in spires:
		var at: Vector3 = s[0]
		var h: float = s[1]
		var sp := Node3D.new()
		arena.add_child(sp)
		sp.position = at
		sp.rotation_degrees = Vector3(_rng.randf_range(-4, 4), _rng.randf() * 360.0, _rng.randf_range(-4, 4))
		var r := h * 0.12
		EnemyKit.cylinder(sp, r, r * 1.25, h, BRICK, Vector3(0, h * 0.5, 0)).material_override = bm
		EnemyKit.cone(sp, r * 1.5, h * 0.4, Color(0.35, 0.33, 0.45), Vector3(0, h + h * 0.2, 0)).material_override = sl
		for k in 3:
			var wa := _rng.randf() * TAU
			var w := EnemyKit.box(sp, Vector3(r * 0.35, r * 0.6, 0.3), Color(1, 0.8, 0.4), Vector3(cos(wa) * r * 1.02, h * _rng.randf_range(0.5, 0.9), sin(wa) * r * 1.02))
			w.rotation.y = -wa + PI * 0.5
			w.material_override = EnemyKit.glow_mat(Color(1.0, 0.75, 0.4), 2.5)
	# Storm masses on the horizon (violet cumulonimbus).
	var storm_mat := EnemyKit.mat(Color(0.3, 0.22, 0.4), 1.0, 0.6)
	for c in [Vector3(-260, 10, -220), Vector3(180, 5, -300), Vector3(-60, 20, -360), Vector3(300, 0, -60)]:
		for k in 9:
			var b := EnemyKit.ball(arena, _rng.randf_range(18, 34), Color(0.26, 0.2, 0.36), c + Vector3(_rng.randf_range(-60, 60), _rng.randf_range(-10, 45), _rng.randf_range(-30, 30)), Vector3(1.3, 0.9, 1.0))
			b.material_override = storm_mat
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_weather(arena: Node3D) -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 900
	_rain.lifetime = 0.9
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(22, 1, 22)
	_rain.direction = Vector3(0.25, -1, 0.1)
	_rain.spread = 3.0
	_rain.initial_velocity_min = 22.0
	_rain.initial_velocity_max = 26.0
	_rain.gravity = Vector3(0, -6, 0)
	_rain.particle_flag_align_y = true
	var cap := CapsuleMesh.new()
	cap.radius = 0.012
	cap.height = 0.7
	cap.radial_segments = 4
	cap.rings = 1
	_rain.mesh = cap
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.85, 0.82, 0.95, 0.35)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain.material_override = rm
	_rain.local_coords = false
	_rain.emitting = false
	add_child(_rain)
	_rain.position = Vector3(0, 10, 0)
	# Wind streak cards across the roof (always a little, more in the storm).
	_streaks = CPUParticles3D.new()
	_streaks.name = "WindStreaks"
	_streaks.amount = 26
	_streaks.lifetime = 1.6
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_streaks.emission_box_extents = Vector3(1, 3.5, 20)
	_streaks.direction = Vector3(1, 0.02, 0)
	_streaks.spread = 4.0
	_streaks.initial_velocity_min = 18.0
	_streaks.initial_velocity_max = 26.0
	_streaks.gravity = Vector3.ZERO
	var sc := CapsuleMesh.new()
	sc.radius = 0.02
	sc.height = 2.4
	sc.radial_segments = 4
	sc.rings = 1
	_streaks.mesh = sc
	_streaks.particle_flag_align_y = true
	var stm := StandardMaterial3D.new()
	stm.albedo_color = Color(1, 0.95, 0.92, 0.22)
	stm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_streaks.material_override = stm
	_streaks.position = Vector3(-24, 3.5, 0)
	_streaks.emitting = true
	arena.add_child(_streaks)
	# Shingles and leaves whipping across in the hurricane.
	_shingles = CPUParticles3D.new()
	_shingles.amount = 60
	_shingles.lifetime = 2.6
	_shingles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_shingles.emission_box_extents = Vector3(2.0, 5.0, 22.0)
	_shingles.direction = Vector3(1, 0.15, 0)
	_shingles.spread = 12.0
	_shingles.initial_velocity_min = 14.0
	_shingles.initial_velocity_max = 22.0
	_shingles.gravity = Vector3(0, -1.5, 0)
	_shingles.angular_velocity_min = -540.0
	_shingles.angular_velocity_max = 540.0
	var q := BoxMesh.new()
	q.size = Vector3(0.24, 0.03, 0.16)
	_shingles.mesh = q
	_shingles.material_override = EnemyKit.mat(Color(0.36, 0.33, 0.45))
	_shingles.position = Vector3(-26, 4.0, 0)
	_shingles.emitting = false
	arena.add_child(_shingles)


func _build_acorns(arena: Node3D) -> void:
	if not ResourceLoader.exists("res://scenes/objects/Acorn.tscn"):
		return
	var ps := load("res://scenes/objects/Acorn.tscn") as PackedScene
	var groups := {
		"C1": [Vector3(9.2, 0.6, -5.53), Vector3(8.78, 0.6, -5.1), Vector3(8.35, 0.6, -4.67), Vector3(7.93, 0.6, -4.25)],
		"C2": [Vector3(8.4, 0.6, 8.9), Vector3(7.83, 0.6, 9.09), Vector3(7.26, 0.6, 9.28), Vector3(6.69, 0.6, 9.47)],
		"C3": [Vector3(-6.69, 0.6, 9.47), Vector3(-7.26, 0.6, 9.28), Vector3(-7.83, 0.6, 9.09), Vector3(-8.4, 0.6, 8.9)],
		"C4": [Vector3(-7.93, 0.6, -4.25), Vector3(-8.35, 0.6, -4.67), Vector3(-8.78, 0.6, -5.1), Vector3(-9.2, 0.6, -5.53)]}
	var holder := Node3D.new()
	holder.name = "Acorns"
	arena.add_child(holder)
	for k in groups.keys():
		for p in groups[k]:
			var a := ps.instantiate() as Node3D
			a.position = (p as Vector3) - Vector3(0, 0.45, 0)
			a.set("heal_amount", 1)
			holder.add_child(a)


func _build_cams() -> void:
	var sc := get_node_or_null("StoryCams") as Node3D
	if sc == null:
		sc = Node3D.new()
		sc.name = "StoryCams"
		add_child(sc)
	var defs := {
		"StoryCam_A_v2": [Vector3(0, 5.5, 22), Vector3(0, 4.0, -14), 50.0],
		"StoryCam_B_v2": [Vector3(0, 34, 24), Vector3(0, 0, -1), 55.0],
		"StoryCam_C_v2": [Vector3(1.5, 0.9, 4.5), Vector3(0, 3, -14.5), 50.0],
		"StoryCam_D_v2": [Vector3(-55, 2, 45), Vector3(0, 4, 0), 30.0],
		"StoryCam_Hero": [Vector3(24, 7, 12), Vector3(-3, 2, -3), 55.0]}
	for n in defs.keys():
		if sc.get_node_or_null(String(n)) != null:
			continue
		var d: Array = defs[n]
		var c := Camera3D.new()
		c.name = String(n)
		sc.add_child(c)
		c.position = d[0]
		c.look_at_from_position(d[0], d[1], Vector3.UP)
		c.fov = float(d[2])

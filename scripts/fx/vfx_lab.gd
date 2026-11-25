extends Node3D
## VFX Lab: a look-development playground presenting every Super Mak 64 shader, texture,
## environment preset and effect. Everything is built in code so it never depends on other
## workstreams' assets. Run: python tools/godot.py capture res://scenes/fx/VFXLab.tscn out.png --cam StoryCam_A
## Dev args (after --):
##   --env=W1|W2|W3|HUB|BOSS   pick the environment preset (default W1)
##   --pageturn=0.45            freeze a page-turn transition at this progress for review
##   --fxfocus                  re-trigger effects faster for captures
##   --nopost                   disable the storybook post-process (ink lines, grade, vignette, paper)
##   --build-env                save env_<ID>.tres presets into res://assets/shaders/environments/ and quit

const T := "res://assets/textures/"
const FX_ROW := [
	["DustPuff", "dust_puff"], ["LandingRing", "landing_ring"], ["SlamShockwave", "slam_shockwave"], ["CollectPop", "collect_pop"],
	["TruffleBurst", "truffle_burst"], ["HitStars", "hit_stars"], ["Confetti", "confetti"], ["FeatherBurst", "feather_burst"],
	["CrumbBurst", "crumb_burst"], ["PeaSplat", "pea_splat"], ["PageFlutter", "page_flutter"], ["JumpTrail", "jump_trail"],
	["Splash", "splash"], ["CocoaSplash", "cocoa_splash"], ["Poof", "poof"], ["CheckpointGlow", "checkpoint_glow"],
]

var env_id := "W1"
var _mak: Node3D
var _truffle: Node3D
var _scent: ScentTrail
var _fx_points: Array = []
var _timer := 100.0
var _fx_index := 0
var _period := 2.4
var _grass_mats: Array[ShaderMaterial] = []
var _fire_all := false
var _reel_cam: Camera3D
var _reel_look: Node3D


func _ready() -> void:
	# Captures count frames; lock the lab to 60 fps so frame waits map to real effect timing.
	Engine.max_fps = 60
	var dev := get_node_or_null("/root/Dev")
	if dev != null:
		env_id = dev.arg("env", "W1")
		if dev.has_arg("fxfocus"):
			# Review mode: fire every one-shot together 0.5 s after start, then every 2.4 s.
			_fire_all = true
			_timer = _period - 0.5
		if dev.has_arg("build-env"):
			_build_env_resources()
			get_tree().quit()
			return
	_setup_environment()
	_build_terrain()
	_build_water_and_chocolate()
	_build_props()
	_build_character_showcase()
	_build_clouds()
	_build_effects()
	_build_dioramas()
	_build_cameras()
	if dev == null or not dev.has_arg("nopost"):
		var post := FxPost.new()
		post.name = "StorybookPost"
		add_child(post)
	if dev != null and dev.has_arg("pageturn"):
		_demo_page_turn(float(dev.arg("pageturn", "0.45")))
	if dev != null and dev.has_arg("perf"):
		_measure_perf()
	if dev != null and dev.has_arg("reel"):
		_fire_all = true
		_period = 1.5
		_start_reel()


# ------------------------------------------------------------------ environment

func _build_env_resources() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/shaders/environments")
	for id in FxEnvironments.IDS:
		var e := FxEnvironments.make(id)
		var path := "res://assets/shaders/environments/env_%s.tres" % id
		var err := ResourceSaver.save(e, path)
		print("[VFXLab] saved ", path, " err=", err)
	FxMaterials.save_library()


func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)
	FxEnvironments.apply(self, env_id)
	sun.directional_shadow_max_distance = 80.0


# ------------------------------------------------------------------ terrain

func _height(x: float, z: float) -> float:
	var h := sin(x * 0.12) * 0.8 + cos(z * 0.1 + 0.5) * 0.6 + sin((x + z) * 0.25) * 0.25
	# Back cliff: a steep rise behind the lab.
	h += smoothstep(-11.0, -15.0, z) * 7.0 + smoothstep(-15.0, -22.0, z) * 3.0
	# Rounded hill on the right.
	h += 3.2 * exp(-(pow(x - 15.0, 2.0) + pow(z + 2.0, 2.0)) / 30.0)
	# Stream channel.
	var sz := _stream_z(x)
	var d := absf(z - sz)
	h -= 1.3 * (1.0 - smoothstep(1.4, 3.2, d))
	return h


func _stream_z(x: float) -> float:
	return 7.0 + sin(x * 0.18) * 2.5


func _path_amount(x: float, z: float) -> float:
	var px := -4.0 + sin(z * 0.22) * 2.5
	return 1.0 - smoothstep(0.9, 1.7, absf(x - px))


func _build_terrain() -> void:
	var size := 60.0
	var res := 120
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / res
	var verts := []
	for j in res + 1:
		for i in res + 1:
			var x := -size * 0.5 + i * step
			var z := -size * 0.5 + j * step
			verts.append(Vector3(x, _height(x, z), z))
	for j in res:
		for i in res:
			var a: Vector3 = verts[j * (res + 1) + i]
			var b: Vector3 = verts[j * (res + 1) + i + 1]
			var c: Vector3 = verts[(j + 1) * (res + 1) + i]
			var d: Vector3 = verts[(j + 1) * (res + 1) + i + 1]
			for v in [a, b, c, b, d, c]:
				st.set_color(Color(_path_amount(v.x, v.z), 0, 0, 1))
				st.set_uv(Vector2(v.x, v.z) * 0.1)
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/terrain.gdshader")
	m.set_shader_parameter("grass_texture", load(T + "grass.webp"))
	m.set_shader_parameter("dirt_texture", load(T + "dirt_path.webp"))
	m.set_shader_parameter("rock_texture", load(T + "cliff_rock.webp"))
	mi.material_override = m
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	mi.add_child(body)
	# Grass and flowers.
	var grass := FxScatter.new()
	grass.name = "GrassScatter"
	grass.auto_build = false
	grass.count = 14000
	grass.scatter_seed = 11
	grass.source_mesh = FxScatter.make_grass_tuft(0.42, 7, 5)
	var gm := FxScatter.grass_material(Color(0.2, 0.44, 0.14), Color(0.68, 0.88, 0.32))
	_grass_mats.append(gm)
	grass.material = gm
	grass.max_slope_degrees = 30.0
	grass.min_height = -0.5
	grass.clump_strength = 0.45
	add_child(grass)
	grass.target_path = grass.get_path_to(mi)
	grass.build()
	var colors := [Color(1.0, 0.85, 0.25), Color(1, 1, 1), Color(1.0, 0.55, 0.7), Color(0.6, 0.65, 1.0)]
	for k in colors.size():
		var fl := FxScatter.new()
		fl.name = "Flowers%d" % k
		fl.auto_build = false
		fl.count = 260
		fl.scatter_seed = 100 + k
		fl.source_mesh = FxScatter.make_flower(colors[k])
		fl.material = FxScatter.flower_material()
		fl.max_slope_degrees = 25.0
		fl.min_height = -0.3
		fl.clump_strength = 0.85
		fl.clump_frequency = 0.2
		fl.scale_range = Vector2(0.8, 1.4)
		add_child(fl)
		fl.target_path = fl.get_path_to(mi)
		fl.build()


# ------------------------------------------------------------------ liquids

func _build_water_and_chocolate() -> void:
	# Stream: a ribbon mesh following the channel.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 80
	for i in n:
		var x0 := -30.0 + 60.0 * i / n
		var x1 := -30.0 + 60.0 * (i + 1) / n
		var z0 := _stream_z(x0)
		var z1 := _stream_z(x1)
		var y := -0.75
		var w := 3.0
		var quad := [Vector3(x0, y, z0 - w), Vector3(x1, y, z1 - w), Vector3(x0, y, z0 + w), Vector3(x1, y, z1 + w)]
		for k in [0, 1, 2, 1, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(float(i) / n, 0.0 if k < 2 else 1.0))
			st.add_vertex(quad[k])
	st.generate_tangents()
	var water := MeshInstance3D.new()
	water.name = "Stream"
	water.mesh = st.commit()
	var wm := ShaderMaterial.new()
	wm.shader = load("res://assets/shaders/water.gdshader")
	wm.set_shader_parameter("flow_along_uv", true)
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# Waterfall foam where the stream enters (left edge).
	_add_fx("WaterfallFoam", "waterfall_foam", Vector3(-12.0, -0.7, _stream_z(-12.0)), false)
	# Hot chocolate pool with a floating biscuit.
	var pool_pos := Vector3(9.0, _height(9.0, 15.5) + 0.35, 15.5)
	var rim := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 3.2
	tor.outer_radius = 4.1
	tor.rings = 48
	tor.ring_segments = 16
	rim.mesh = tor
	rim.position = pool_pos + Vector3(0, 0.75, 0)
	rim.scale = Vector3(1, 1.4, 1)
	rim.material_override = _toon(Color(1, 1, 1), T + "frosting.webp", Vector3(6, 1, 1))
	add_child(rim)
	var bowl := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.4
	cyl.bottom_radius = 3.0
	cyl.height = 1.2
	bowl.mesh = cyl
	bowl.position = pool_pos + Vector3(0, 0.0, 0)
	bowl.material_override = _toon(Color(0.35, 0.2, 0.12))
	add_child(bowl)
	var choc := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(7.0, 7.0)
	pm.subdivide_depth = 24
	pm.subdivide_width = 24
	choc.mesh = pm
	choc.position = pool_pos + Vector3(0, 0.72, 0)
	var cm := ShaderMaterial.new()
	cm.shader = load("res://assets/shaders/hot_chocolate.gdshader")
	cm.set_shader_parameter("round_clip", true)
	cm.set_shader_parameter("edge_mode", 2)
	choc.material_override = cm
	add_child(choc)
	var biscuit := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.9
	bm.bottom_radius = 0.95
	bm.height = 0.22
	biscuit.mesh = bm
	biscuit.position = pool_pos + Vector3(-0.8, 0.8, 0.6)
	biscuit.material_override = _toon(Color(1, 1, 1), T + "gingerbread.webp")
	add_child(biscuit)
	var tw := create_tween().set_loops()
	tw.tween_property(biscuit, "position:y", pool_pos.y + 0.86, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(biscuit, "position:y", pool_pos.y + 0.78, 1.6).set_trans(Tween.TRANS_SINE)


# ------------------------------------------------------------------ props

func _toon(color: Color, tex := "", uv_scale := Vector3.ONE, outline := false, tri := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/toon.gdshader")
	m.set_shader_parameter("albedo", color)
	if tex != "":
		m.set_shader_parameter("albedo_texture", load(tex))
		m.set_shader_parameter("uv_scale", Vector2(uv_scale.x, uv_scale.y))
	if tri > 0.0:
		m.set_shader_parameter("triplanar", true)
		m.set_shader_parameter("triplanar_scale", tri)
	if outline:
		var o := ShaderMaterial.new()
		o.shader = load("res://assets/shaders/outline.gdshader")
		m.next_pass = o
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	if parent == null:
		parent = self
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_props() -> void:
	# A brick cottage with a straw roof and a smoking chimney.
	var house := Node3D.new()
	house.name = "Cottage"
	house.position = Vector3(-12.0, _height(-12.0, -6.0) - 0.2, -6.0)
	house.rotation_degrees.y = 20.0
	add_child(house)
	var brick := _toon(Color(1, 1, 1), T + "brick.webp", Vector3.ONE, false, 0.35)
	_box(Vector3(5.0, 3.4, 4.0), Vector3(0, 1.7, 0), brick, house)
	var roof := MeshInstance3D.new()
	var pr := PrismMesh.new()
	pr.size = Vector3(5.8, 2.6, 4.8)
	roof.mesh = pr
	roof.position = Vector3(0, 4.7, 0)
	roof.material_override = _toon(Color(1, 1, 1), T + "straw_thatch.webp", Vector3.ONE, false, 0.4)
	house.add_child(roof)
	_box(Vector3(0.8, 2.4, 0.8), Vector3(1.6, 5.3, 0.8), brick, house)
	_box(Vector3(1.1, 2.0, 0.15), Vector3(0, 1.0, 2.05), _toon(Color(1, 1, 1), T + "wood_planks.webp", Vector3.ONE, false, 0.8), house)
	_add_fx("ChimneySmoke", "chimney_smoke", Vector3(1.6, 6.6, 0.8), false, house)
	# Trees with swaying leaf balls.
	for tp in [Vector3(-5.0, 0, -9.0), Vector3(3.0, 0, -10.5), Vector3(-19.0, 0, 2.0)]:
		_tree(tp + Vector3(0, _height(tp.x, tp.z), 0))
	_add_fx("FallingLeaves", "falling_leaves", Vector3(-1.0, 6.5, -8.0), false)
	_add_fx("Butterflies", "butterflies", Vector3(0.0, 1.4, 1.0), false)
	# Candy corner: candy-cane posts and frosting / chocolate / cobble sample blocks.
	var samples := ["candy_stripes", "frosting", "chocolate", "cobblestone", "bookshelf_wood", "parchment", "bark", "wood_planks"]
	for i in samples.size():
		var x := 16.0 + (i % 4) * 1.9
		var z := 10.0 + floorf(i / 4.0) * 1.9
		var mi := MeshInstance3D.new()
		var sm: PrimitiveMesh = SphereMesh.new() if i % 2 == 0 else BoxMesh.new()
		if sm is SphereMesh:
			(sm as SphereMesh).radius = 0.7
			(sm as SphereMesh).height = 1.4
		else:
			(sm as BoxMesh).size = Vector3(1.3, 1.3, 1.3)
		mi.mesh = sm
		mi.position = Vector3(x, _height(x, z) + 0.75, z)
		mi.material_override = _toon(Color(1, 1, 1), T + samples[i] + ".webp")
		add_child(mi)
	for k in 3:
		var cane := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.18
		cy.bottom_radius = 0.18
		cy.height = 2.4
		cane.mesh = cy
		var x2 := 15.0 + k * 3.0
		cane.position = Vector3(x2, _height(x2, 13.8) + 1.2, 13.8)
		cane.material_override = _toon(Color(1, 1, 1), T + "candy_stripes.webp", Vector3(1, 2, 1))
		add_child(cane)


func _tree(pos: Vector3) -> void:
	var t := Node3D.new()
	t.position = pos
	add_child(t)
	var trunk := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.35
	cy.bottom_radius = 0.6
	cy.height = 4.0
	trunk.mesh = cy
	trunk.position = Vector3(0, 2.0, 0)
	trunk.material_override = _toon(Color(1, 1, 1), T + "bark.webp", Vector3(3, 1, 1))
	t.add_child(trunk)
	var leaf := ShaderMaterial.new()
	leaf.shader = load("res://assets/shaders/foliage.gdshader")
	leaf.set_shader_parameter("albedo_texture", load(T + "leaf_canopy.webp"))
	leaf.set_shader_parameter("base_color", Color(0.85, 0.95, 0.85))
	leaf.set_shader_parameter("tip_color", Color(1.1, 1.1, 0.95))
	leaf.set_shader_parameter("sway_height", 7.0)
	leaf.set_shader_parameter("wind_strength", 0.25)
	leaf.set_shader_parameter("flutter", 0.02)
	leaf.set_shader_parameter("translucency", 0.25)
	for b in [[Vector3(0, 4.6, 0), 1.9], [Vector3(1.1, 4.0, 0.5), 1.3], [Vector3(-1.0, 4.1, -0.4), 1.4], [Vector3(0.2, 5.6, -0.2), 1.3]]:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = b[1]
		sm.height = b[1] * 1.8
		s.mesh = sm
		s.position = b[0]
		s.material_override = leaf
		t.add_child(s)


# ------------------------------------------------------------------ hero stand-in

func _build_character_showcase() -> void:
	# Primitive Mr. Mak stand-in, only to judge the toon shader, rim light and outline.
	var mak := Node3D.new()
	mak.name = "MakStandIn"
	mak.position = Vector3(-1.0, _height(-1.0, 2.0), 2.0)
	mak.rotation_degrees.y = 25.0
	add_child(mak)
	_mak = mak
	var cream := _toon(Color(1.0, 0.93, 0.84), "", Vector3.ONE, true)
	var pink := _toon(Color(1.0, 0.62, 0.66), "", Vector3.ONE, true)
	var brown := _toon(Color(0.42, 0.27, 0.18), "", Vector3.ONE, true)
	var grey := _toon(Color(0.55, 0.57, 0.62), T + "frosting.webp", Vector3.ONE, true)
	grey.set_shader_parameter("albedo_texture", null)
	var body := _sphere(0.42, Vector3(0, 0.5, 0), cream, mak)
	body.scale = Vector3(1.0, 0.95, 0.92)
	var head := _sphere(0.36, Vector3(0, 1.0, 0.05), cream, mak)
	head.scale = Vector3(1.1, 1.0, 1.0)
	var snout := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.13
	sc.bottom_radius = 0.15
	sc.height = 0.14
	snout.mesh = sc
	snout.rotation_degrees.x = 90.0
	snout.position = Vector3(0, 0.95, -0.37)
	snout.material_override = pink
	mak.add_child(snout)
	for sx in [-1.0, 1.0]:
		var ear := _sphere(0.12, Vector3(sx * 0.24, 1.33, 0.02), pink, mak)
		ear.scale = Vector3(0.9, 1.3, 0.45)
		ear.rotation_degrees.z = -sx * 25.0
		var eye := _sphere(0.055, Vector3(sx * 0.13, 1.06, -0.3), _toon(Color(0.2, 0.12, 0.08)), mak)
		eye.scale = Vector3(1, 1.3, 0.6)
		var hoof := _sphere(0.11, Vector3(sx * 0.2, 0.08, -0.05), brown, mak)
		hoof.scale = Vector3(1, 0.8, 1.2)
		_sphere(0.1, Vector3(sx * 0.45, 0.55, -0.08), brown, mak)
	var beanie := _sphere(0.34, Vector3(0, 1.18, 0.06), grey, mak)
	beanie.scale = Vector3(1.08, 0.75, 1.05)
	_box(Vector3(0.42, 0.42, 0.2), Vector3(0, 0.62, 0.42), brown, mak)
	# Golden truffle with aura sparkle.
	_truffle = Node3D.new()
	_truffle.name = "TruffleStandIn"
	_truffle.position = Vector3(6.0, _height(6.0, -3.0) + 1.3, -3.0)
	add_child(_truffle)
	var gold := _toon(Color(1.0, 0.76, 0.22), "", Vector3.ONE, true)
	gold.set_shader_parameter("emission_color", Color(1.0, 0.6, 0.15))
	gold.set_shader_parameter("emission_energy", 0.35)
	gold.set_shader_parameter("spec_strength", 1.2)
	gold.set_shader_parameter("rim_color", Color(1.0, 0.95, 0.7))
	gold.set_shader_parameter("rim_strength", 0.9)
	var tr := _sphere(0.42, Vector3.ZERO, gold, _truffle)
	tr.scale = Vector3(1.0, 0.85, 0.9)
	var spin := create_tween().set_loops()
	spin.tween_property(_truffle, "rotation:y", TAU, 3.0).from(0.0)
	var bob := create_tween().set_loops()
	bob.tween_property(_truffle, "position:y", _truffle.position.y + 0.25, 1.1).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_truffle, "position:y", _truffle.position.y, 1.1).set_trans(Tween.TRANS_SINE)
	_add_fx("Sparkle", "sparkle", _truffle.position, false)
	# Scent trail from the snout to the truffle.
	_scent = ScentTrail.new()
	_scent.name = "ScentTrail"
	_scent.start_offset = Vector3(0, 0.95, -0.3)
	_scent.width = 0.16
	mak.add_child(_scent)
	_scent.set_target(_truffle.global_position)
	# Gust swirl blowing across the meadow.
	var gust := GustSwirl.new()
	gust.name = "GustSwirl"
	gust.length = 12.0
	gust.radius = 1.3
	gust.position = Vector3(-14.0, _height(-14.0, -1.0) + 1.6, -1.0)
	gust.rotation_degrees.y = -100.0
	add_child(gust)
	# Run dust under the stand-in's feet.
	_add_fx("RunDust", "run_dust", mak.position + Vector3(0.0, 0.05, 0.3), false)


func _sphere(r: float, pos: Vector3, mat: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 32
	s.rings = 16
	mi.mesh = s
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ clouds

func _build_clouds() -> void:
	var cm := ShaderMaterial.new()
	cm.shader = load("res://assets/shaders/cloud.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for c in [Vector3(4.0, 5.5, 4.0), Vector3(10.0, 7.0, -4.0), Vector3(-8.0, 9.0, -14.0), Vector3(18.0, 12.0, -16.0)]:
		var cloud := Node3D.new()
		cloud.position = c
		add_child(cloud)
		for k in 7:
			var r := rng.randf_range(0.7, 1.3)
			var off := Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.2, 0.5), rng.randf_range(-1.0, 1.0))
			_sphere(r, off, cm, cloud)
		var tw := create_tween().set_loops()
		tw.tween_property(cloud, "position:x", c.x + 1.5, 4.0 + rng.randf() * 2.0).set_trans(Tween.TRANS_SINE)
		tw.tween_property(cloud, "position:x", c.x, 4.0 + rng.randf() * 2.0).set_trans(Tween.TRANS_SINE)


# ------------------------------------------------------------------ effects

func _add_fx(n: String, preset: String, pos: Vector3, one_shot_demo: bool, parent: Node = null) -> FxEffect:
	if parent == null:
		parent = self
	var fx := FxEffect.new()
	fx.name = n
	fx.preset = preset
	fx.free_when_done = false
	fx.autoplay = not one_shot_demo
	fx.position = pos
	parent.add_child(fx)
	return fx


func _build_effects() -> void:
	# A row of one-shot effects on little wooden plinths with labels, re-triggered in sequence.
	var base := Vector3(-5.2, 0.0, 10.6)
	var plank := _toon(Color(1, 1, 1), T + "wood_planks.webp", Vector3.ONE, false, 0.6)
	for i in FX_ROW.size():
		var x := base.x + (i % 4) * 2.8
		var z := base.z + floorf(i / 4.0) * 2.5
		var y := 0.0
		var p := Vector3(x, y, z)
		_box(Vector3(1.4, 0.3, 1.4), p + Vector3(0, 0.15, 0), plank)
		var fx := _add_fx(FX_ROW[i][0], FX_ROW[i][1], p + Vector3(0, 0.32, 0), true)
		var lbl := Label3D.new()
		lbl.text = FX_ROW[i][0]
		lbl.font_size = 40
		lbl.pixel_size = 0.006
		lbl.outline_size = 10
		lbl.modulate = Color(1, 0.97, 0.88)
		lbl.outline_modulate = Color(0.25, 0.15, 0.1)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = p + Vector3(0, 0.36, 0.85)
		add_child(lbl)
		_fx_points.append(fx)
	# Stage for the row: a cobblestone plaza (sits above the stream bank).
	var plaza := _box(Vector3(13.0, 0.4, 11.0), Vector3(base.x + 4.2, -0.2, base.z + 3.7), _toon(Color(1, 1, 1), T + "cobblestone.webp", Vector3.ONE, false, 0.4))
	plaza.name = "Plaza"


func _process(delta: float) -> void:
	_timer += delta
	if _fire_all:
		if _timer >= _period:
			_timer = 0.0
			for fx in _fx_points:
				(fx as FxEffect).play()
	elif _timer >= _period / 2.0 and _fx_points.size() > 0:
		_timer = 0.0
		# Fire two at a time so a capture usually shows several effects mid-flight.
		for k in 2:
			var fx: FxEffect = _fx_points[_fx_index % _fx_points.size()]
			fx.play()
			_fx_index += 1
	if _reel_cam != null:
		_reel_cam.look_at(_reel_look.position, Vector3.UP)
	if _mak != null:
		var p := _mak.global_position
		for gm in _grass_mats:
			gm.set_shader_parameter("pusher", Vector4(p.x, p.y, p.z, 1.0))
		if _scent != null and _truffle != null:
			_scent.set_target(_truffle.global_position)


## --reel: a 24 s camera tour (overview, hero and scent trail, effect grid, liquids, dioramas) for showcase clips.
## Record with: python tools/godot.py movie res://scenes/fx/VFXLab.tscn Recordings/.../reel.avi --frames 1440 -- --reel
func _start_reel() -> void:
	var cam := Camera3D.new()
	cam.name = "ReelCam"
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	var keys := [
		[0.0, Vector3(-16.0, 11.0, 28.0), Vector3(2.0, 1.0, 0.0)],
		[4.0, Vector3(-8.0, 6.0, 16.0), Vector3(0.0, 1.0, 0.0)],
		[7.5, Vector3(3.5, 2.6, 6.5), Vector3(2.0, 1.4, -1.0)],
		[11.0, Vector3(-1.0, 5.4, 22.5), Vector3(-1.0, 0.4, 14.0)],
		[15.0, Vector3(12.0, 4.5, 23.0), Vector3(9.0, 1.0, 15.5)],
		[19.0, Vector3(-6.0, 6.5, 37.0), Vector3(-13.5, 2.0, 24.5)],
		[24.0, Vector3(-22.0, 7.0, 34.0), Vector3(-17.0, 2.0, 24.5)],
	]
	var look := Node3D.new()
	add_child(look)
	cam.position = keys[0][1]
	look.position = keys[0][2]
	var tw := create_tween()
	var tl := create_tween()
	for i in range(1, keys.size()):
		var d: float = keys[i][0] - keys[i - 1][0]
		tw.tween_property(cam, "position", keys[i][1], d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tl.tween_property(look, "position", keys[i][2], d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_reel_cam = cam
	_reel_look = look


func _measure_perf() -> void:
	# --perf: uncapped frame rate, then report the average frame time over 3 s from the current camera.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await get_tree().create_timer(2.0).timeout
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	await get_tree().create_timer(3.0).timeout
	var frames := Engine.get_frames_drawn() - f0
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxf(frames, 1)
	print("[VFXLab] perf: %d frames, %.2f ms/frame (%.0f fps), draw calls %d, primitives %d" % [frames, ms, 1000.0 / ms,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()


func _demo_page_turn(progress: float) -> void:
	await get_tree().create_timer(0.8).timeout
	var pt := PageTurn.new()
	pt.free_after = false
	get_tree().root.add_child(pt)
	await pt.capture()
	# Swap the scene underneath to a different environment so the reveal is visible.
	FxEnvironments.apply(self, "BOSS" if env_id != "BOSS" else "W1")
	pt.set_progress(progress)


# ------------------------------------------------------------------ world dioramas

func _mat(name: String) -> Material:
	var path := "res://assets/shaders/materials/%s.tres" % name
	if ResourceLoader.exists(path):
		return load(path)
	return FxMaterials.library().get(name)


func _cyl(r: float, h: float, pos: Vector3, mat: Material, parent: Node, top_r := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r if top_r < 0.0 else top_r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 40
	mi.mesh = c
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_dioramas() -> void:
	# Four pedestals sampling the other worlds' materials: Skyway, Gingerbread Grove, the Library hub, the Wolf's roof.
	var root := Node3D.new()
	root.name = "Dioramas"
	add_child(root)
	var y := 2.2
	var xs := [-24.0, -17.0, -10.0, -3.0]
	var z := 25.0
	for x in xs:
		_cyl(2.8, y, Vector3(x, y * 0.5 - 0.6, z), _mat("toon_bookshelf_wood"), root)
	# W2 Skyway: castle flagstones, a beanstalk with leaves and a vanishing cloud.
	var a := Vector3(xs[0], y - 0.6, z)
	_cyl(2.75, 0.12, a + Vector3(0, 0.06, 0), _mat("toon_castle_stone"), root)
	var stalk := _cyl(0.32, 4.5, a + Vector3(-0.8, 2.25, -0.6), _mat("toon_beanstalk_skin"), root, 0.22)
	stalk.rotation_degrees.z = 6.0
	for k in 3:
		var leaf := _sphere(0.7, a + Vector3(-0.8 + (0.6 if k % 2 == 0 else -0.6), 1.4 + k * 1.1, -0.6), _mat("foliage_beanstalk_leaf"), root)
		leaf.scale = Vector3(1.2, 0.25, 0.8)
	var cloud := Node3D.new()
	cloud.position = a + Vector3(1.0, 1.4, 0.6)
	root.add_child(cloud)
	var cm := (_mat("cloud_platform") as ShaderMaterial).duplicate() as ShaderMaterial
	for off in [Vector3(0, 0, 0), Vector3(0.6, 0.1, 0.2), Vector3(-0.6, 0.05, -0.1), Vector3(0.1, 0.3, -0.4)]:
		_sphere(0.55, off, cm, cloud)
	var tw := create_tween().set_loops()
	tw.tween_method(func(v: float) -> void: cm.set_shader_parameter("dissolve", v), 0.0, 0.0, 1.5)
	tw.tween_method(func(v: float) -> void: cm.set_shader_parameter("dissolve", v), 0.0, 1.0, 1.2)
	tw.tween_method(func(v: float) -> void: cm.set_shader_parameter("dissolve", v), 1.0, 0.0, 0.6)
	# W3 Gingerbread Grove: frosting ground, gumdrops, a lollipop and a hot-chocolate stream.
	var b := Vector3(xs[1], y - 0.6, z)
	_cyl(2.75, 0.12, b + Vector3(0, 0.06, 0), _mat("toon_frosting"), root)
	for g in [[Vector3(0.9, 0.35, 0.7), Color(0.6, 1.0, 0.8)], [Vector3(1.6, 0.3, -0.4), Color(1.0, 0.65, 0.8)], [Vector3(0.3, 0.3, 1.5), Color(1.0, 0.9, 0.5)]]:
		var gm := (_mat("toon_gumdrop_sugar") as ShaderMaterial).duplicate() as ShaderMaterial
		gm.set_shader_parameter("albedo", g[1])
		var drop := _sphere(0.45, b + g[0], gm, root)
		drop.scale = Vector3(1.0, 0.85, 1.0)
	_cyl(0.06, 2.0, b + Vector3(-1.1, 1.0, -0.6), _toon(Color(1, 0.97, 0.92)), root)
	var lolly := _cyl(0.6, 0.18, b + Vector3(-1.1, 2.1, -0.6), _mat("toon_candy_stripes"), root)
	lolly.rotation_degrees.x = 90.0
	var river := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	rp.size = Vector2(5.0, 1.1)
	river.mesh = rp
	river.position = b + Vector3(0, 0.14, -1.6)
	river.material_override = _mat("hot_chocolate_river")
	root.add_child(river)
	# HUB library: carpet, damask wall, glowing stained glass, a bookshelf and a parchment page.
	var c := Vector3(xs[2], y - 0.6, z)
	_cyl(2.75, 0.12, c + Vector3(0, 0.06, 0), _mat("toon_library_carpet"), root)
	_box(Vector3(4.2, 3.2, 0.3), c + Vector3(0, 1.7, -1.6), _mat("toon_damask_wallpaper"), root)
	_box(Vector3(1.2, 2.0, 0.1), c + Vector3(0.9, 2.0, -1.42), _mat("toon_stained_glass_glow"), root)
	_box(Vector3(1.4, 2.4, 0.6), c + Vector3(-1.1, 1.3, -1.1), _mat("toon_bookshelf_wood"), root)
	var page := _box(Vector3(0.8, 0.02, 1.0), c + Vector3(0.6, 0.15, 0.6), _mat("toon_parchment"), root)
	page.rotation_degrees.y = 20.0
	# BOSS: slate rooftop with brick chimneys under the wolf's stormy sky.
	var d := Vector3(xs[3], y - 0.6, z)
	_cyl(2.75, 0.12, d + Vector3(0, 0.06, 0), _mat("toon_roof_shingles_slate"), root)
	for ch in [Vector3(-1.0, 0.9, -0.8), Vector3(1.1, 0.9, -0.5)]:
		_box(Vector3(0.8, 1.6, 0.8), d + ch, _mat("toon_brick"), root)
	_add_fx("BossSmoke", "chimney_smoke", d + Vector3(1.1, 1.8, -0.5), false, root)
	var gust := GustSwirl.new()
	gust.length = 4.0
	gust.radius = 0.6
	gust.with_motes = false
	gust.position = d + Vector3(1.8, 1.0, 1.0)
	gust.rotation_degrees.y = 90.0
	root.add_child(gust)


# ------------------------------------------------------------------ cameras

func _build_cameras() -> void:
	var cams := Node3D.new()
	cams.name = "StoryCams"
	add_child(cams)
	_cam(cams, "StoryCam_A", Vector3(-14.0, 9.5, 26.0), Vector3(2.0, 1.0, 0.0), 55.0)
	_cam(cams, "StoryCam_B", Vector3(0.6, 2.2, -1.2), Vector3(-0.6, 1.0, 1.8), 50.0)
	_cam(cams, "StoryCam_C", Vector3(-1.0, 5.6, 23.5), Vector3(-1.0, 0.4, 14.0), 62.0)
	_cam(cams, "StoryCam_D", Vector3(16.0, 6.0, 24.0), Vector3(9.0, 1.5, 12.0), 55.0)
	# Review-only views (not story cameras): the sky and the toon close-up from the front.
	_cam(cams, "SkyCam", Vector3(0.0, 3.0, 22.0), Vector3(-4.0, 12.0, -20.0), 65.0)
	_cam(cams, "DioramaCam", Vector3(-13.5, 7.5, 38.5), Vector3(-13.5, 2.0, 24.5), 60.0)
	_cam(cams, "TrailCam", Vector3(4.0, 3.2, 7.5), Vector3(2.5, 1.6, -0.5), 55.0)
	_cam(cams, "ToonCam", Vector3(-1.6, 1.5, 0.2), Vector3(-1.0, 0.85, 2.0), 45.0)
	var main := cams.get_node("StoryCam_A") as Camera3D
	main.current = true


func _cam(parent: Node, n: String, pos: Vector3, look: Vector3, fov: float) -> void:
	var c := Camera3D.new()
	c.name = n
	c.fov = fov
	parent.add_child(c)
	c.position = pos
	c.look_at(look, Vector3.UP)

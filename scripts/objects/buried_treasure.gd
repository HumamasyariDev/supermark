class_name BuriedTreasure
extends SniffTarget
## A muddy patch with a buried truffle (W1-8, W3-8). After it has been sniffed, a Ham Slam on it digs the truffle
## out in a spray of mud. Slamming before sniffing only splashes mud (unless require_sniff is off).

signal dug_out(id: String)

@export var truffle_id: String = "W1-8"
@export var require_sniff: bool = true
@export var patch_radius: float = 1.3

var is_dug := false
var _sensor: SlamSensor
var _patch: Node3D
var _t := 0.0
var _bubbles: Array[Node3D] = []
var _sniff_light: OmniLight3D


func _ready() -> void:
	super._ready()
	add_to_group("buried_treasure")
	var v := ObjSvc.ensure_visual(self)
	_patch = v
	if not ObjSvc.visual_has_content(v):
		_build_placeholder(v)
	_sensor = SlamSensor.create(self, patch_radius, 1.2, Vector3(0, -0.1, 0))
	_sensor.slammed.connect(_on_slam)
	if ObjSvc.has_truffle(truffle_id):
		# Already found on an earlier visit: the patch stays as a flattened, grassy dent.
		is_dug = true
		active = false
		remove_from_group("sniff_target")
		_crater(false)


## Critique objects r1: the patch read as a hard-edged hole decal ringed with spiky triangles. Now: a soft-edged mud
## decal that follows the ground, a raised lumpy rim, pebbles, a crossed-stick X and a few bubbles; after the dig the
## rim heaps up into a crater with a dark hole in the middle.
var _lumps: Array[Node3D] = []
var _hole: Decal


## Decals need real image data (a GradientTexture2D is generated later and never reaches the decal atlas).
static var _img_cache: Dictionary = {}


static func _radial_image(inner: Color, outer: Color, size: int) -> ImageTexture:
	var key := "%s%s%d" % [inner.to_html(), outer.to_html(), size]
	if _img_cache.has(key):
		return _img_cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var t := clampf(Vector2(x + 0.5, y + 0.5).distance_to(c) / (size * 0.5), 0.0, 1.0)
			# Soft shoulder, then a feathered edge, with a little noise so the rim is not a perfect circle.
			var n := sin(atan2(y - c.y, x - c.x) * 7.0) * 0.04
			img.set_pixel(x, y, inner.lerp(outer, smoothstep(0.45 + n, 1.0, t)))
	var tex := ImageTexture.create_from_image(img)
	_img_cache[key] = tex
	return tex


func _mud_decal(v: Node3D, radius: float, inner: Color, outer: Color, n: String) -> Decal:
	var d := Decal.new()
	d.name = n
	d.size = Vector3(radius * 2.0, 0.8, radius * 2.0 * 0.85)
	d.texture_albedo = _radial_image(inner, outer, 128)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.position = Vector3(0, 0.1, 0)
	v.add_child(d)
	return d


## Critique objects r1 re-run: the ring of glossy, uniform dark hemispheres read as droppings. The patch is now a low
## mound of freshly turned soil (noise-displaced, triplanar dirt texture, toon-lit like the ground) with a lighter tan
## rim and a dark wet centre, a broken ring of irregular flattened clods, crumbs, pebbles, grass tufts and one twig
## stuck in the top. The dig sprays clods outward, the mound sinks and a shallow crater stays.
var _mound: MeshInstance3D
var _twig: Node3D
var _soil_mat: Material
static var _clod_cache: Dictionary = {}

const SOIL_LIGHT := Color(0.64, 0.52, 0.4)
const SOIL_DARK := Color(0.34, 0.22, 0.12)
const SOIL_WET := Color(0.2, 0.12, 0.07)


## A noise-displaced, flattened lump (seeded, cached). Vertex colour runs from a darker underside to a lighter top.
static func clod_mesh(seed_i: int, radius: float, flat: float, rough_amp: float = 0.28, top: Color = SOIL_LIGHT, under: Color = SOIL_DARK, segs: int = 14) -> ArrayMesh:
	var key := "%d_%.3f_%.3f_%.3f_%s_%s_%d" % [seed_i, radius, flat, rough_amp, top.to_html(), under.to_html(), segs]
	if _clod_cache.has(key):
		return _clod_cache[key]
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = segs
	sm.rings = maxi(8, int(segs * 0.5))
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed_i
	noise.frequency = 1.1
	noise.fractal_octaves = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in verts.size():
		var d := verts[i].normalized()
		var n := noise.get_noise_3dv(d * 1.7)
		var r := radius * (1.0 + n * rough_amp * 2.0)
		var p := d * r
		p.y *= flat
		# Sit on the ground: flatten the underside and sink it a touch.
		if p.y < 0.0:
			p.y *= 0.25
		p.y -= radius * flat * 0.08
		st.set_color(under.lerp(top, clampf(d.y * 0.8 + 0.35 + n * 0.4, 0.0, 1.0)))
		st.add_vertex(p)
	for k in idx:
		st.add_index(k)
	st.generate_normals()
	var m := st.commit()
	_clod_cache[key] = m
	return m


func _soil_material(tint: Color) -> Material:
	var base := load("res://assets/shaders/materials/toon_dirt_path.tres") as ShaderMaterial
	if base != null:
		var m := base.duplicate() as ShaderMaterial
		m.set_shader_parameter("use_vertex_color", true)
		m.set_shader_parameter("albedo", tint)
		m.set_shader_parameter("triplanar_scale", 1.4)
		m.set_shader_parameter("spec_strength", 0.04)
		m.set_shader_parameter("rim_strength", 0.12)
		m.set_shader_parameter("roughness_value", 0.95)
		return m
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = tint
	sm.roughness = 0.95
	sm.metallic_specular = 0.1
	if ResourceLoader.exists("res://assets/textures/dirt_path.webp"):
		sm.albedo_texture = load("res://assets/textures/dirt_path.webp")
		sm.uv1_triplanar = true
		sm.uv1_scale = Vector3.ONE * 1.4
	return sm


func _build_placeholder(v: Node3D) -> void:
	# A muted tint: the dirt texture times the vertex colours alone reads orange next to the grass.
	_soil_mat = _soil_material(Color(0.8, 0.72, 0.66))
	_mud_decal(v, patch_radius * 1.25, Color(0.52, 0.38, 0.23, 0.85), Color(0.55, 0.42, 0.26, 0.0), "MudDecal")
	_mud_decal(v, patch_radius * 0.62, Color(0.24, 0.15, 0.08, 0.9), Color(0.36, 0.25, 0.14, 0.0), "WetDecal")
	_hole = _mud_decal(v, patch_radius * 0.55, Color(0.07, 0.04, 0.02, 1.0), Color(0.16, 0.1, 0.05, 0.0), "HoleDecal")
	_hole.visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	# Fix r2: the 0.36 mound rose ~0.27 m and Mak stood in it up to the knees (it has no collision, so the patch
	# stays a flat slam target); 0.22 keeps a readable heap at ~0.16 m.
	var crown_y := patch_radius * 0.62 * 0.2
	# The turned-soil mound: lighter tan shoulders, darker wet crown.
	_mound = MeshInstance3D.new()
	_mound.name = "Mound"
	_mound.mesh = clod_mesh(7, patch_radius * 0.62, 0.22, 0.12, SOIL_DARK.lerp(SOIL_WET, 0.35), SOIL_LIGHT, 32)
	_mound.material_override = _soil_mat
	_mound.scale = Vector3(1.0, 1.0, 0.86)
	v.add_child(_mound)
	# A broken ring of irregular clods: clusters with gaps, different sizes, flattened.
	var n_clods := 11
	for i in n_clods:
		if i == 3 or i == 8:
			continue  # gaps so it never reads as a ring of beads
		var a := TAU * float(i) / float(n_clods) + rng.randf_range(-0.18, 0.18)
		var lump := Node3D.new()
		var rad := patch_radius * rng.randf_range(0.66, 0.95)
		lump.position = Vector3(cos(a) * rad, 0.0, sin(a) * rad * 0.86)
		lump.rotation.y = rng.randf() * TAU
		v.add_child(lump)
		var rr := rng.randf_range(0.08, 0.17) * (patch_radius / 1.3)
		var mi := MeshInstance3D.new()
		mi.mesh = clod_mesh(100 + i, rr, rng.randf_range(0.45, 0.62))
		mi.material_override = _soil_mat
		lump.add_child(mi)
		if rng.randf() < 0.5:
			var mi2 := MeshInstance3D.new()
			mi2.mesh = clod_mesh(200 + i, rr * 0.55, 0.6)
			mi2.material_override = _soil_mat
			mi2.position = Vector3(rr * 0.9, 0.0, rng.randf_range(-0.5, 0.5) * rr)
			lump.add_child(mi2)
		_lumps.append(lump)
	# Crumbs scattered outward.
	for i in 9:
		var a2 := rng.randf() * TAU
		var r2 := patch_radius * rng.randf_range(0.85, 1.25)
		var c := MeshInstance3D.new()
		c.mesh = clod_mesh(300 + i, rng.randf_range(0.025, 0.045), 0.6)
		c.material_override = _soil_mat
		c.position = Vector3(cos(a2) * r2, 0.0, sin(a2) * r2 * 0.86)
		v.add_child(c)
	# A few glossy wet beads on the crown (small, they pulse).
	var wet := ObjSvc.unique_mat(SOIL_WET, 0.25)
	for i in 3:
		var b := Node3D.new()
		var a3 := rng.randf() * TAU
		var r3 := rng.randf_range(0.05, patch_radius * 0.3)
		b.position = Vector3(cos(a3) * r3, crown_y * 0.85, sin(a3) * r3 * 0.8)
		v.add_child(b)
		ObjSvc.sphere(b, rng.randf_range(0.025, 0.04), wet, Vector3.ZERO, Vector3(1, 0.45, 1))
		_bubbles.append(b)
	# Pebbles: irregular grey stones.
	var stone := StandardMaterial3D.new()
	stone.vertex_color_use_as_albedo = true
	stone.roughness = 0.9
	for i in 6:
		var a4 := rng.randf() * TAU
		var r4 := patch_radius * rng.randf_range(0.55, 1.1)
		var pb := MeshInstance3D.new()
		pb.mesh = clod_mesh(400 + i, rng.randf_range(0.035, 0.07), 0.55, 0.2, Color(0.72, 0.7, 0.66), Color(0.45, 0.43, 0.4))
		pb.material_override = stone
		pb.position = Vector3(cos(a4) * r4, 0.0, sin(a4) * r4 * 0.86)
		pb.rotation.y = rng.randf() * TAU
		v.add_child(pb)
	# Grass tufts poking through at the rim (thin tapered blades, two greens).
	var g1 := ObjSvc.mat(Color(0.42, 0.66, 0.26), 0.8)
	var g2 := ObjSvc.mat(Color(0.55, 0.76, 0.32), 0.8)
	for i in 5:
		var a5 := rng.randf() * TAU
		var r5 := patch_radius * rng.randf_range(0.95, 1.2)
		var tuft := Node3D.new()
		tuft.position = Vector3(cos(a5) * r5, 0.0, sin(a5) * r5 * 0.86)
		v.add_child(tuft)
		for k in 5:
			var h := rng.randf_range(0.12, 0.24)
			var blade := ObjSvc.cylinder(tuft, 0.0, 0.014, h, g1 if k % 2 == 0 else g2, Vector3(0, h * 0.5, 0))
			var tilt := rng.randf_range(10.0, 30.0)
			var yaw := float(k) / 5.0 * 360.0 + rng.randf_range(-20.0, 20.0)
			blade.rotation_degrees = Vector3(tilt, yaw, 0)
			blade.position = Vector3(sin(deg_to_rad(yaw)) * 0.03, h * 0.45, cos(deg_to_rad(yaw)) * 0.03)
	# One twig stuck in the crown at a jaunty angle, with a single leaf: the spot is marked, not crossed out.
	_twig = Node3D.new()
	_twig.name = "Twig"
	_twig.position = Vector3(0.12, crown_y * 0.7, -0.05)
	_twig.rotation_degrees = Vector3(18, 30, -14)
	v.add_child(_twig)
	var bark := ObjSvc.mat(Color(0.47, 0.32, 0.18), 0.85)
	ObjSvc.cylinder(_twig, 0.016, 0.026, 0.5, bark, Vector3(0, 0.25, 0))
	ObjSvc.cylinder(_twig, 0.008, 0.014, 0.16, bark, Vector3(0.05, 0.4, 0), Vector3(0, 0, -40))
	var leaf := ObjSvc.sphere(_twig, 0.05, ObjSvc.mat(Color(0.45, 0.68, 0.25), 0.7), Vector3(0.11, 0.46, 0), Vector3(1.6, 0.25, 0.8))
	leaf.rotation_degrees = Vector3(0, 0, -30)


## The dug state (after the reveal, or on a revisit): the mound sinks, the rim heaps up and a dark hole opens.
func _crater(animate: bool) -> void:
	if _hole:
		_hole.visible = true
	if _mound:
		if animate:
			var mt := create_tween()
			mt.tween_property(_mound, "scale", Vector3(1.15, 0.12, 1.0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			_mound.scale = Vector3(1.15, 0.12, 1.0)
	if _twig:
		if animate:
			_fling_twig()
		else:
			_twig.visible = false
	for l in _lumps:
		var to := l.position * 1.16
		var sc := Vector3(1.15, 1.6, 1.15)
		if animate:
			var tw := create_tween().set_parallel()
			tw.tween_property(l, "position", to, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(l, "scale", sc, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			l.position = to
			l.scale = sc
	for b in _bubbles:
		b.visible = false


## The twig cartwheels away and lies on the grass.
func _fling_twig() -> void:
	var start := _twig.position
	var land := Vector3(patch_radius * 1.15, 0.03, patch_radius * 0.3)
	var tw := create_tween().set_parallel()
	tw.tween_method(func(t: float) -> void:
		_twig.position = start.lerp(land, t) + Vector3(0, sin(t * PI) * 0.9, 0), 0.0, 1.0, 0.55)
	tw.tween_property(_twig, "rotation_degrees", Vector3(90, 30, 400), 0.55)


## Clods spray out of the hole on a parabola, bounce once, then settle and sink into the grass.
func _spray_clods(count: int = 10) -> void:
	var par := get_parent() as Node3D
	if par == null or _soil_mat == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = clod_mesh(500 + i % 6, rng.randf_range(0.06, 0.12) * (patch_radius / 1.3), 0.6)
		mi.material_override = _soil_mat
		par.add_child(mi)
		var a := TAU * float(i) / float(count) + rng.randf_range(-0.3, 0.3)
		var from := global_position + Vector3(0, 0.15, 0)
		var dist := patch_radius * rng.randf_range(1.2, 2.3)
		var to := global_position + Vector3(cos(a) * dist, 0.02, sin(a) * dist)
		var h := rng.randf_range(0.9, 1.7)
		var dur := rng.randf_range(0.5, 0.7)
		mi.global_position = from
		mi.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		var r0 := mi.rotation
		var spin := Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), 0)
		var tw := mi.create_tween()
		tw.tween_method(func(t: float) -> void:
			if is_instance_valid(mi):
				mi.global_position = from.lerp(to, t) + Vector3(0, sin(t * PI) * h, 0)
				mi.rotation = r0 + spin * t * dur, 0.0, 1.0, dur)
		# A small bounce on landing, then rest and sink away.
		var bounce_to := to + (to - from).normalized() * 0.18
		bounce_to.y = to.y
		tw.tween_method(func(t: float) -> void:
			if is_instance_valid(mi):
				mi.global_position = to.lerp(bounce_to, t) + Vector3(0, sin(t * PI) * 0.12, 0), 0.0, 1.0, 0.18)
		tw.tween_interval(rng.randf_range(1.2, 1.8))
		tw.tween_property(mi, "scale", Vector3(1.2, 0.05, 1.2), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)


func _process(delta: float) -> void:
	_t += delta
	for i in _bubbles.size():
		var s := 0.7 + 0.5 * absf(sin(_t * 1.5 + i * 2.1))
		_bubbles[i].scale = Vector3(s, s, s)


func _on_slam(_by: Node) -> void:
	if is_dug:
		return
	if require_sniff and not was_sniffed:
		ObjSvc.feedback("object_dig_splash", global_position, {}, "mud_splat")
		if not ObjSvc.juice_handles("object_dig_splash", "vfx"):
			ObjSvc.burst(get_parent(), global_position + Vector3(0, 0.2, 0), Color(0.36, 0.24, 0.13), 30, 5.0, 0.25, -14.0, 0.8)
		# The mud wobbles back: not here yet, sniff first.
		var tw := create_tween()
		tw.tween_property(_patch, "scale", Vector3(1.15, 0.7, 1.15), 0.07)
		tw.tween_property(_patch, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		return
	dig()


func dig() -> void:
	if is_dug:
		return
	is_dug = true
	active = false
	remove_from_group("sniff_target")
	if _sniff_light:
		_sniff_light.queue_free()
		_sniff_light = null
	ObjSvc.feedback("object_dig", global_position, {}, "dig_out")
	if not ObjSvc.juice_handles("object_dig", "vfx"):
		ObjSvc.burst(get_parent(), global_position + Vector3(0, 0.3, 0), Color(0.4, 0.27, 0.15), 40, 7.0, 0.3, -14.0, 1.0)
		ObjSvc.fx(self, "DustPuff", global_position)
	_spray_clods(10)
	var tw := create_tween()
	tw.tween_property(_patch, "scale", Vector3(1.2, 1.6, 1.2), 0.1)
	tw.tween_property(_patch, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_crater(true)
	ObjSvc.spawn_truffle(get_parent(), Transform3D(Basis(), global_position), truffle_id, true)
	dug_out.emit(truffle_id)


func is_sniff_active() -> bool:
	return active and not is_dug


## Sniffed: the patch answers with a golden pulse (ring over the mud, glints on the twig X, a warm light) so the
## player knows where to Ham Slam. Called by the player's sniff (on_sniffed(self)) or the proximity fallback.
func on_sniffed(by: Node = null) -> void:
	var first := not was_sniffed and active and not is_dug
	super.on_sniffed(by)
	if not first:
		return
	# The patch answers the sniff: a wiggle and a puff of dust.
	var wt := create_tween()
	for i in 3:
		wt.tween_property(_patch, "scale", Vector3(1.08, 1.25, 1.08), 0.07)
		wt.tween_property(_patch, "scale", Vector3(0.96, 0.9, 0.96), 0.08)
	wt.tween_property(_patch, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	ObjFx.puffs(get_parent(), global_position + Vector3(0, 0.15, 0), Color(0.62, 0.5, 0.36, 0.7), 6, patch_radius * 0.6, 0.45, 0.8)
	if not ObjSvc.juice_handles("object_sniff_reveal", "vfx"):
		ObjFx.ground_ring(get_parent(), global_position, patch_radius * 1.8, Color(1.0, 0.85, 0.4, 0.8), 0.6)
		ObjFx.star_ring(get_parent(), global_position + Vector3(0, 0.3, 0), 6, patch_radius, 0.35, Color(1.0, 0.88, 0.5), 0.6)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.4)
	l.omni_range = patch_radius * 2.2
	l.position = Vector3(0, 0.5, 0)
	l.light_energy = 0.0
	add_child(l)
	var tw := l.create_tween().set_loops()
	tw.tween_property(l, "light_energy", 1.4, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(l, "light_energy", 0.4, 0.6).set_trans(Tween.TRANS_SINE)
	_sniff_light = l

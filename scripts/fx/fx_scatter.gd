@tool
class_name FxScatter
extends MultiMeshInstance3D
## Scatters MultiMesh instances (grass tufts, flowers, pebbles, props) over a target mesh surface.
## Deterministic: the same seed gives the same layout. Filters by slope, height, an optional mask
## texture over a world XZ rectangle and vertex colour red (paths, where dirt should stay bare).
## In the editor, tick "regenerate" to rebuild. At runtime it builds once in _ready if auto_build.
##
## Typical use from a world script:
##   var s := FxScatter.new(); s.target_path = terrain.get_path(); s.source_mesh = FxScatter.make_grass_tuft()
##   s.count = 6000; s.material = FxScatter.grass_material(); add_child(s); s.build()

@export var target_path: NodePath
@export var source_mesh: Mesh
@export var material: Material
@export var count := 2000
@export var scatter_seed := 1
@export var max_slope_degrees := 32.0
@export var min_height := -1000.0
@export var max_height := 1000.0
@export var scale_range := Vector2(0.7, 1.3)
@export var align_to_normal := 0.3
@export var random_yaw := true
@export var sink := 0.02
## Skip points where the weighted vertex colour exceeds this (dirt paths painted in red). 1.1 disables.
@export var avoid_vertex_red := 0.5
## Per-channel weights for the avoid test (max of r*x, g*y, b*z, a*w). Default: red only.
## W1 terrain: Vector4(1, 1, 1, 0) skips dirt (R), cobble (G) and wet banks (B).
@export var avoid_channels := Vector4(1, 0, 0, 0)
@export var mask_texture: Texture2D
@export var mask_rect := Rect2(-60, -60, 120, 120)
@export_range(0, 3) var mask_channel := 0
@export var mask_threshold := 0.5
## Clumping: noise frequency (per metre) and how strongly it thins out instances outside clumps.
@export var clump_frequency := 0.15
@export_range(0.0, 1.0) var clump_strength := 0.5
@export var auto_build := true
@export var regenerate := false:
	set(v):
		regenerate = false
		if Engine.is_editor_hint() and is_inside_tree():
			build()


func _ready() -> void:
	if auto_build and not Engine.is_editor_hint() and multimesh == null:
		build()


func build() -> int:
	var target := get_node_or_null(target_path) as MeshInstance3D
	if target == null or target.mesh == null or source_mesh == null:
		push_warning("[FxScatter] needs a MeshInstance3D target and a source_mesh")
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed
	var noise := FastNoiseLite.new()
	noise.seed = scatter_seed
	noise.frequency = clump_frequency
	var mask_img: Image = null
	if mask_texture != null:
		mask_img = mask_texture.get_image()
		if mask_img != null and mask_img.is_compressed():
			mask_img.decompress()
	# Collect triangles (world space) with their area for area-weighted sampling.
	var xf := target.global_transform
	var tris: Array = []
	var areas := PackedFloat32Array()
	var total := 0.0
	for si in target.mesh.get_surface_count():
		var arrays := target.mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n_idx := idx.size() if idx.size() > 0 else verts.size()
		for t in range(0, n_idx - 2, 3):
			var i0 := idx[t] if idx.size() > 0 else t
			var i1 := idx[t + 1] if idx.size() > 0 else t + 1
			var i2 := idx[t + 2] if idx.size() > 0 else t + 2
			var a := xf * verts[i0]
			var b := xf * verts[i1]
			var c := xf * verts[i2]
			var area := (b - a).cross(c - a).length() * 0.5
			if area <= 0.000001:
				continue
			var red := 0.0
			if cols.size() > 0:
				var cc := (cols[i0] + cols[i1] + cols[i2]) / 3.0
				red = maxf(maxf(cc.r * avoid_channels.x, cc.g * avoid_channels.y), maxf(cc.b * avoid_channels.z, cc.a * avoid_channels.w))
			tris.append([a, b, c, red])
			total += area
			areas.append(total)
	if tris.is_empty():
		return 0
	var max_cos := cos(deg_to_rad(max_slope_degrees))
	var xforms: Array[Transform3D] = []
	var attempts := count * 4
	var inv := global_transform.affine_inverse()
	while xforms.size() < count and attempts > 0:
		attempts -= 1
		var r := rng.randf() * total
		var ti := areas.bsearch(r)
		ti = clampi(ti, 0, tris.size() - 1)
		var tri: Array = tris[ti]
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		if tri[3] > avoid_vertex_red:
			continue
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		var p := a + (b - a) * u + (c - a) * v
		var n := (b - a).cross(c - a).normalized()
		if n.y < 0.0:
			n = -n
		if n.y < max_cos or p.y < min_height or p.y > max_height:
			continue
		if clump_strength > 0.0:
			var cv := noise.get_noise_2d(p.x, p.z) * 0.5 + 0.5
			if rng.randf() > lerpf(1.0, cv * 1.6, clump_strength):
				continue
		if mask_img != null:
			var mu := (p.x - mask_rect.position.x) / mask_rect.size.x
			var mv := (p.z - mask_rect.position.y) / mask_rect.size.y
			if mu < 0.0 or mu > 1.0 or mv < 0.0 or mv > 1.0:
				continue
			var px := mask_img.get_pixel(int(mu * (mask_img.get_width() - 1)), int(mv * (mask_img.get_height() - 1)))
			var val := [px.r, px.g, px.b, px.a][mask_channel] as float
			if val < mask_threshold:
				continue
		var up := Vector3.UP.lerp(n, align_to_normal).normalized()
		var basis := Basis()
		if random_yaw:
			basis = Basis(Vector3.UP, rng.randf() * TAU)
		var tilt_axis := Vector3.UP.cross(up)
		if tilt_axis.length() > 0.0001:
			basis = Basis(tilt_axis.normalized(), Vector3.UP.angle_to(up)) * basis
		var s := rng.randf_range(scale_range.x, scale_range.y)
		basis = basis.scaled(Vector3(s, s, s))
		xforms.append(inv * Transform3D(basis, p - up * sink))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = source_mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	multimesh = mm
	if material != null:
		material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return xforms.size()


# ------------------------------------------------------------ ready-made foliage meshes

## A chunky stylised grass tuft: several curved, tapered blades fanned around the origin.
## Height in metres; vertex colour alpha = 0 at the root, 1 at the tip (for the foliage shader).
static func make_grass_tuft(height := 0.45, blades := 7, seed_value := 3) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades:
		var yaw := float(b) / blades * TAU + rng.randf() * 0.6
		var lean := rng.randf_range(0.15, 0.45)
		var h := height * rng.randf_range(0.65, 1.15)
		var w := height * rng.randf_range(0.11, 0.16)
		var dir := Vector3(cos(yaw), 0, sin(yaw))
		var side := Vector3(-dir.z, 0, dir.x)
		var root := dir * rng.randf_range(0.0, 0.06)
		var segs := 4
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for s in segs + 1:
			var t := float(s) / segs
			var centre := root + dir * lean * h * t * t + Vector3.UP * h * t
			var half := w * 0.5 * (1.0 - t * 0.92)
			var l := centre - side * half
			var r := centre + side * half
			if s > 0:
				var t0 := float(s - 1) / segs
				var n := (side.cross(Vector3.UP + dir * lean)).normalized()
				_tri(st, prev_l, prev_r, r, t0, t0, t, n)
				_tri(st, prev_l, r, l, t0, t, t, n)
			prev_l = l
			prev_r = r
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ta: float, tb: float, tc: float, _n: Vector3) -> void:
	for pair in [[a, ta], [b, tb], [c, tc]]:
		st.set_color(Color(1, 1, 1, pair[1]))
		st.set_uv(Vector2(0.5, 1.0 - pair[1]))
		st.add_vertex(pair[0])


## A simple flower: a stem plus a round five-petal head (vertex colour carries petal colour).
static func make_flower(petal := Color(1.0, 0.85, 0.3), height := 0.38) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_col := Color(0.35, 0.6, 0.22)
	# Stem (thin crossed quads).
	for a in [0.0, PI * 0.5]:
		var s := Vector3(cos(a), 0, sin(a)) * 0.012
		var top := Vector3(0, height, 0)
		for tri in [[-s, s, top + s], [-s, top + s, top - s]]:
			for i in 3:
				var v: Vector3 = tri[i]
				st.set_color(Color(stem_col, clampf(v.y / height, 0.0, 1.0)))
				st.set_uv(Vector2(0.5, 0.5))
				st.add_vertex(v)
	# Head: a fan of petals around a centre.
	var centre := Vector3(0, height, 0)
	var petals := 5
	for p in petals:
		var a0 := float(p) / petals * TAU
		var a1 := a0 + TAU / petals * 0.5
		var a2 := a0 + TAU / petals
		var r := 0.075
		var v0 := centre + Vector3(cos(a0), 0.12, sin(a0)) * r * 0.6
		var v1 := centre + Vector3(cos(a1), 0.25, sin(a1)) * r * 1.25
		var v2 := centre + Vector3(cos(a2), 0.12, sin(a2)) * r * 0.6
		for v in [centre + Vector3(0, 0.012, 0), v0, v1, centre + Vector3(0, 0.012, 0), v1, v2]:
			st.set_color(Color(petal, 1.0))
			st.set_uv(Vector2(0.5, 0.5))
			st.add_vertex(v)
	# Centre button.
	for p in 6:
		var a0 := float(p) / 6.0 * TAU
		var a1 := float(p + 1) / 6.0 * TAU
		for v in [centre + Vector3(0, 0.03, 0), centre + Vector3(cos(a0), 0.4, sin(a0)) * 0.03, centre + Vector3(cos(a1), 0.4, sin(a1)) * 0.03]:
			st.set_color(Color(0.95, 0.6, 0.15, 1.0))
			st.set_uv(Vector2(0.5, 0.5))
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func grass_material(base := Color(0.24, 0.48, 0.16), tip := Color(0.66, 0.86, 0.32)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/foliage.gdshader")
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("tip_color", tip)
	m.set_shader_parameter("use_color_weight", true)
	m.set_shader_parameter("wind_strength", 0.12)
	return m


static func flower_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/foliage.gdshader")
	m.set_shader_parameter("base_color", Color(1, 1, 1))
	m.set_shader_parameter("tip_color", Color(1, 1, 1))
	m.set_shader_parameter("use_vertex_color", true)
	m.set_shader_parameter("use_color_weight", true)
	m.set_shader_parameter("gradient_by_height", false)
	m.set_shader_parameter("wind_strength", 0.1)
	m.set_shader_parameter("translucency", 0.15)
	return m

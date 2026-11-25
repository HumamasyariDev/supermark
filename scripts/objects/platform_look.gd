class_name PlatformLook
extends RefCounted
## Placeholder looks for platforms, built from smooth primitives in the area palettes.
## The top surface of every look sits at y = 0 (the platform origin), so collision shapes line up.

enum Kind { WOOD, BRICK, LEAF, CLOUD, BISCUIT, BOOK }


static func build(parent: Node3D, size: Vector3, theme: int) -> void:
	match theme:
		Kind.WOOD:
			_wood(parent, size)
		Kind.BRICK:
			_brick(parent, size)
		Kind.LEAF:
			_leaf(parent, size)
		Kind.CLOUD:
			_cloud(parent, size)
		Kind.BISCUIT:
			_biscuit(parent, size)
		Kind.BOOK:
			_book(parent, size)


## Critique objects r1 re-run: flat-coloured planks read as primitives next to the textured props. The planks and
## bricks now carry the shared painted textures (triplanar), tinted per plank.
static func _tex_mat(path: String, tint: Color, rough: float, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path) as Texture2D
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
	return m


static func _wood(p: Node3D, s: Vector3) -> void:
	var planks := maxi(2, int(round(s.x / 0.5)))
	var w := s.x / float(planks)
	for i in planks:
		var shade := 0.9 + 0.1 * float(i % 2)
		var m := _tex_mat("res://assets/textures/wood_planks.webp", Color(1.0 * shade, 0.92 * shade, 0.85 * shade), 0.75, 0.9)
		ObjSvc.soft_box(p, Vector3(w - 0.03, s.y, s.z), m, Vector3(-s.x * 0.5 + w * (i + 0.5), -s.y * 0.5, 0), Vector3(0, 0, 0), minf(0.05, s.y * 0.3))
	var dark := ObjSvc.mat(ObjSvc.WALNUT_DARK, 0.8)
	for sz in [-1.0, 1.0]:
		ObjSvc.box(p, Vector3(s.x * 0.98, s.y * 0.5, 0.12), dark, Vector3(0, -s.y * 0.95, sz * (s.z * 0.5 - 0.2)))
	var brass := ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.8)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			ObjSvc.sphere(p, 0.05, brass, Vector3(sx * (s.x * 0.5 - 0.15), 0.0, sz * (s.z * 0.5 - 0.15)))


static func _brick(p: Node3D, s: Vector3) -> void:
	var cols := maxi(2, int(round(s.x / 0.6)))
	var rows := maxi(1, int(round(s.z / 0.6)))
	var bw := s.x / float(cols)
	var bd := s.z / float(rows)
	var mortar := ObjSvc.mat(Color(0.88, 0.82, 0.72), 0.95)
	ObjSvc.box(p, Vector3(s.x - 0.04, s.y * 0.9, s.z - 0.04), mortar, Vector3(0, -s.y * 0.5, 0))
	for r in rows:
		for c in cols:
			var shade := 0.85 + 0.15 * float((r * 7 + c * 3) % 4) / 3.0
			var m := _tex_mat("res://assets/textures/brick.webp", Color(shade, shade, shade), 0.8, 0.8)
			ObjSvc.soft_box(p, Vector3(bw - 0.06, s.y, bd - 0.06), m, Vector3(-s.x * 0.5 + bw * (c + 0.5), -s.y * 0.5, -s.z * 0.5 + bd * (r + 0.5)), Vector3.ZERO, minf(0.04, s.y * 0.3))


static func _leaf(p: Node3D, s: Vector3) -> void:
	var green := ObjSvc.mat(ObjSvc.BEAN, 0.45)
	var light := ObjSvc.mat(ObjSvc.BEAN.lightened(0.3), 0.5)
	ObjSvc.sphere(p, 0.5, green, Vector3(0, -0.06, 0), Vector3(s.x, 0.22, s.z))
	ObjSvc.sphere(p, 0.5, light, Vector3(0, -0.02, 0), Vector3(s.x * 0.85, 0.1, s.z * 0.85))
	# Midrib and veins.
	var vein := ObjSvc.mat(Color(0.75, 0.9, 0.45), 0.5)
	ObjSvc.capsule(p, 0.035, s.z * 0.9, vein, Vector3(0, 0.03, 0), Vector3(90, 0, 0))
	for i in 3:
		var z := -s.z * 0.25 + i * s.z * 0.25
		ObjSvc.capsule(p, 0.025, s.x * 0.45, vein, Vector3(-s.x * 0.18, 0.03, z + 0.1), Vector3(0, 35, 90))
		ObjSvc.capsule(p, 0.025, s.x * 0.45, vein, Vector3(s.x * 0.18, 0.03, z + 0.1), Vector3(0, -35, 90))
	ObjSvc.cone(p, s.x * 0.12, s.z * 0.25, green, Vector3(0, -0.04, -s.z * 0.55), Vector3(-90, 0, 0))


## Critique objects r1 re-run: clouds were a cluster of white spheres ("white puffs"). Now one sculpted cumulus mesh:
## a sphere displaced by billowing noise (big lobes plus small cauliflower bumps), a flat-ish belly and a domed,
## lumpy top, so the cloud_platform shader's lavender underside and gold rim follow real forms. Cached per size.
static var _cloud_cache: Dictionary = {}


static func cloud_mesh(s: Vector3, seed_i: int = 3) -> ArrayMesh:
	var key := "%.2f_%.2f_%.2f_%d" % [s.x, s.y, s.z, seed_i]
	if _cloud_cache.has(key):
		return _cloud_cache[key]
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 48
	sm.rings = 24
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var big := FastNoiseLite.new()
	big.seed = seed_i
	big.frequency = 0.9
	big.fractal_type = FastNoiseLite.FRACTAL_NONE
	var small := FastNoiseLite.new()
	small.seed = seed_i + 11
	small.frequency = 2.6
	small.fractal_octaves = 2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in verts.size():
		var d := verts[i].normalized()
		# Billow noise: absolute value gives rounded lobes with creases between them.
		var lobes := 1.0 - absf(big.get_noise_3dv(d * 1.6))
		var bumps := 1.0 - absf(small.get_noise_3dv(d * 2.2))
		var up := clampf(d.y * 0.5 + 0.5, 0.0, 1.0)
		var r := 0.78 + lobes * 0.22 * (0.4 + up) + bumps * 0.08 * up
		var p := d * r
		# Belly: flattened and tucked in; top: domed.
		if p.y < 0.0:
			p.y *= 0.32
		else:
			p.y *= 0.95
		st.add_vertex(Vector3(p.x * s.x * 0.5, p.y * s.y * 0.75 - s.y * 0.66, p.z * s.z * 0.5))
	for k in idx:
		st.add_index(k)
	st.generate_normals()
	var m := st.commit()
	_cloud_cache[key] = m
	return m


static func _cloud(p: Node3D, s: Vector3) -> void:
	var white := ObjSvc.mat(ObjSvc.CLOUD, 0.95, 0.0, Color(0.9, 0.92, 1.0), 0.15)
	var mi := MeshInstance3D.new()
	mi.name = "Cumulus"
	mi.mesh = cloud_mesh(s, int(s.x * 7.0 + s.z * 3.0))
	mi.material_override = white
	p.add_child(mi)
	# Two small satellite puffs tucked against the side, so the outline is never a perfect disc.
	for k in 2:
		var ss := s * Vector3(0.42, 0.7, 0.42)
		var sat := MeshInstance3D.new()
		sat.mesh = cloud_mesh(ss, 20 + k)
		sat.material_override = white
		var a := 0.8 + k * 2.6
		sat.position = Vector3(cos(a) * s.x * 0.42, -s.y * 0.12, sin(a) * s.z * 0.42)
		p.add_child(sat)


const BISCUIT_MESH := "res://assets/props/w3/biscuit_platform/biscuit_platform.glb"
const BISCUIT_MESH_SIZE := Vector3(2.5, 0.72, 2.5)


## Instances a generated glb scaled to the platform footprint with its top at y = 0. Returns false if missing.
static func _generated(p: Node3D, path: String, native: Vector3, s: Vector3) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var ps := load(path) as PackedScene
	if ps == null:
		return false
	var n := ps.instantiate() as Node3D
	if n == null:
		return false
	var k := minf(s.x / native.x, s.z / native.z)
	n.scale = Vector3.ONE * k
	n.position = Vector3(0, -native.y * k, 0)
	n.name = "Generated"
	p.add_child(n)
	return true


static func _biscuit(p: Node3D, s: Vector3) -> void:
	if _generated(p, BISCUIT_MESH, BISCUIT_MESH_SIZE, s):
		return
	var biscuit := ObjSvc.mat(Color(0.86, 0.62, 0.32), 0.7)
	var edge := ObjSvc.mat(Color(0.72, 0.48, 0.22), 0.75)
	var r := minf(s.x, s.z) * 0.5
	ObjSvc.cylinder(p, r, r, s.y, biscuit, Vector3(0, -s.y * 0.5, 0))
	ObjSvc.torus(p, r - s.y * 0.5, r + s.y * 0.1, edge, Vector3(0, -s.y * 0.5, 0)).scale = Vector3(1, s.y * 2.0, 1)
	var dot := ObjSvc.mat(Color(0.6, 0.38, 0.16), 0.8)
	for i in 8:
		var a := TAU * float(i) / 8.0
		ObjSvc.sphere(p, 0.05, dot, Vector3(cos(a) * r * 0.55, 0.0, sin(a) * r * 0.55), Vector3(1, 0.4, 1))
	ObjSvc.sphere(p, r * 0.25, ObjSvc.mat(ObjSvc.ICING, 0.4), Vector3(0, 0.0, 0), Vector3(1, 0.2, 1))


static func _book(p: Node3D, s: Vector3) -> void:
	var cover := ObjSvc.mat(ObjSvc.BURGUNDY, 0.55)
	var paper := ObjSvc.mat(ObjSvc.PAPER, 0.9)
	ObjSvc.soft_box(p, Vector3(s.x, s.y * 0.25, s.z), cover, Vector3(0, -s.y * 0.125, 0), Vector3.ZERO, 0.03)
	ObjSvc.box(p, Vector3(s.x * 0.96, s.y * 0.55, s.z * 0.94), paper, Vector3(0.03, -s.y * 0.5, 0))
	ObjSvc.soft_box(p, Vector3(s.x, s.y * 0.25, s.z), cover, Vector3(0, -s.y * 0.875, 0), Vector3.ZERO, 0.03)
	ObjSvc.capsule(p, s.y * 0.5, s.z, cover, Vector3(-s.x * 0.5, -s.y * 0.5, 0), Vector3(90, 0, 0))
	ObjSvc.box(p, Vector3(s.x * 0.5, 0.01, 0.05), ObjSvc.mat(ObjSvc.GOLD, 0.3, 0.8), Vector3(0, 0.005, 0))

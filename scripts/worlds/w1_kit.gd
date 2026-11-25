class_name W1Kit
extends RefCounted
## W1 building kit: cached "storybook toybox" materials, rounded-box meshes, static collision helpers and
## generated-mesh lookup (res://assets/props/w1/<name>/<name>.glb) with procedural stand-ins as fallback.

const PROPS_DIR := "res://assets/props/w1/"

# W1 palette (Docs/ART_V2.md + Docs/levels/W1.md section 14).
const MEADOW := Color("6dbe45")
const DEEP_GRASS := Color("3f8f3a")
const STRAW := Color("e9c45a")
const THATCH := Color("d9a441")
const BRICK := Color("b84a32")
const MORTAR := Color("ead9bd")
const SLATE := Color("5b6577")
const WOOD := Color("8a5a3b")
const WOOD_LIGHT := Color("b07a4f")
const WOOD_DARK := Color("5c3a21")
const BIRCH := Color("efe9dc")
const BIRCH_MARK := Color("3b3b3b")
const STONE := Color("b9b2a6")
const STONE_DARK := Color("8d877d")
const MOSS := Color("6f9a3a")
const APPLE := Color("d83a34")
const CREAM := Color("f6ecd6")
const RED_RIBBON := Color("c8302e")
const HAZARD := Color("ff5a3c")
const GOLD := Color("ffc93c")
const LEAF := Color("7cc043")
const LEAF_DARK := Color("4f9a37")
const SKY := Color("7ec8f0")

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


static func mat(color: Color, rough: float = 0.75, rim: float = 0.22) -> StandardMaterial3D:
	var key := "c|%s|%.2f|%.2f" % [color.to_html(), rough, rim]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.6
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


## World-space triplanar textured material (brick, thatch, planks, bark, cobble, rock).
static func tex_mat(tex_name: String, tint: Color = Color.WHITE, scale: float = 0.35, rough: float = 0.85, strength: float = 1.0) -> StandardMaterial3D:
	var key := "t|%s|%s|%.3f|%.2f" % [tex_name, tint.to_html(), scale, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var path := "res://assets/textures/%s.webp" % tex_name
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.rim_enabled = true
	m.rim = 0.18
	m.rim_tint = 0.6
	_mats[key] = m
	return m


static func glow_mat(color: Color, energy: float = 1.5) -> StandardMaterial3D:
	var key := "g|%s|%.2f" % [color.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	_mats[key] = m
	return m


# ---------------------------------------------------------------- meshes

## Rounded box mesh (single surface, smooth normals on the rounded edges), cached by size and radius.
static func rounded_box_mesh(size: Vector3, radius: float, seg: int = 4) -> ArrayMesh:
	radius = minf(radius, minf(size.x, minf(size.y, size.z)) * 0.5 - 0.001)
	radius = maxf(radius, 0.0)
	var key := "rb|%.3f|%.3f|%.3f|%.3f|%d" % [size.x, size.y, size.z, radius, seg]
	if _meshes.has(key):
		return _meshes[key]
	var h := size * 0.5
	var inner := h - Vector3.ONE * radius
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := seg * 2 + 1
	# Six faces: normal axis, u axis, v axis.
	var faces := [
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
	]
	for f in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var grid: Array = []
		for j in n + 1:
			for i in n + 1:
				var a := -1.0 + 2.0 * i / n
				var b := -1.0 + 2.0 * j / n
				var p := nrm * (nrm.abs().dot(h)) + u * (a * u.abs().dot(h)) + v * (b * v.abs().dot(h))
				var c := p.clamp(-inner, inner)
				var d := p - c
				var dn := d.normalized() if d.length() > 1e-6 else nrm
				grid.append([c + dn * radius, dn])
		for j in n:
			for i in n:
				var i0 := j * (n + 1) + i
				var quad := [i0, i0 + 1, i0 + n + 2, i0 + n + 1]
				# Wind so the face points along nrm (Godot front faces are clockwise).
				var p0: Vector3 = grid[quad[0]][0]
				var p1: Vector3 = grid[quad[1]][0]
				var p2: Vector3 = grid[quad[2]][0]
				var tri := [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]
				var flip := (p1 - p0).cross(p2 - p0).dot(nrm) > 0.0
				for t in tri:
					var order: Array = [t[0], t[2], t[1]] if flip else t
					for k in order:
						st.set_normal(grid[k][1])
						st.set_uv(Vector2(0, 0))
						st.add_vertex(grid[k][0])
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


static func add(parent: Node, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func rbox(parent: Node, size: Vector3, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, radius: float = -1.0) -> MeshInstance3D:
	if radius < 0.0:
		radius = clampf(minf(size.x, minf(size.y, size.z)) * 0.18, 0.03, 0.35)
	return add(parent, rounded_box_mesh(size, radius), material, pos, rot_deg)


static func sphere(parent: Node, r: float, material: Material, pos: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var key := "sp|%.3f" % r
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 20
		m.rings = 10
		_meshes[key] = m
	return add(parent, _meshes[key], material, pos, Vector3.ZERO, scl)


static func cyl(parent: Node, r_top: float, r_bottom: float, h: float, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, segs: int = 16) -> MeshInstance3D:
	var key := "cy|%.3f|%.3f|%.3f|%d" % [r_top, r_bottom, h, segs]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bottom
		m.height = h
		m.radial_segments = segs
		m.rings = 1
		_meshes[key] = m
	return add(parent, _meshes[key], material, pos, rot_deg)


static func capsule(parent: Node, r: float, h: float, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var key := "ca|%.3f|%.3f" % [r, h]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 16
		m.rings = 4
		_meshes[key] = m
	return add(parent, _meshes[key], material, pos, rot_deg)


static func cone(parent: Node, r: float, h: float, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, segs: int = 12) -> MeshInstance3D:
	return cyl(parent, 0.0, r, h, material, pos, rot_deg, segs)


static func torus(parent: Node, inner: float, outer: float, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var key := "to|%.3f|%.3f" % [inner, outer]
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 20
		m.ring_segments = 10
		_meshes[key] = m
	return add(parent, _meshes[key], material, pos, rot_deg)


# ---------------------------------------------------------------- collision

static func body(parent: Node, body_name: String = "Body", pos: Vector3 = Vector3.ZERO, yaw_deg: float = 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = body_name
	b.collision_layer = 1
	b.collision_mask = 0
	b.position = pos
	b.rotation_degrees.y = yaw_deg
	parent.add_child(b)
	return b


static func shape_box(b: CollisionObject3D, size: Vector3, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	cs.rotation_degrees = rot_deg
	b.add_child(cs)
	return cs


static func shape_cyl(b: CollisionObject3D, r: float, h: float, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	cs.shape = s
	cs.position = pos
	cs.rotation_degrees = rot_deg
	b.add_child(cs)
	return cs


## A static box whose TOP centre is `top` (plan convention), with an optional visual.
static func platform(parent: Node, pname: String, top: Vector3, size: Vector3, yaw_deg: float, material: Material, radius: float = -1.0) -> StaticBody3D:
	var b := body(parent, pname, top, yaw_deg)
	shape_box(b, size, Vector3(0, -size.y * 0.5, 0))
	if material:
		rbox(b, size, material, Vector3(0, -size.y * 0.5, 0), Vector3.ZERO, radius)
	return b


# ---------------------------------------------------------------- generated meshes

## Returns the first existing GLB among candidate names (folder-per-asset convention), or "".
static func find_glb(names: Array) -> String:
	for n in names:
		var s := String(n)
		for p in [PROPS_DIR + s + "/" + s + ".glb", PROPS_DIR + s + ".glb"]:
			if ResourceLoader.exists(p):
				return p
	return ""


## Instances a generated mesh scaled to `target_height` (or `target_size` on its largest horizontal axis),
## base centred on the origin and turned 180 degrees so +Z models face -Z. Returns null if missing.
static func glb_visual(parent: Node3D, names: Array, target_height: float = -1.0, target_width: float = -1.0) -> Node3D:
	var path := find_glb(names)
	if path == "":
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.rotation_degrees.y = 180.0
	visual.add_child(inst)
	var aabb := _aabb(inst, Transform3D.IDENTITY)
	if aabb.size.length() < 1e-4:
		aabb = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	var s := 1.0
	if target_height > 0.0:
		s = target_height / maxf(aabb.size.y, 1e-3)
	elif target_width > 0.0:
		s = target_width / maxf(maxf(aabb.size.x, aabb.size.z), 1e-3)
	inst.scale = Vector3.ONE * s
	var c := aabb.get_center()
	inst.position = Vector3(-c.x * s, -aabb.position.y * s, -c.z * s)
	parent.add_child(visual)
	return visual


static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is VisualInstance3D:
		var a := t * (n as VisualInstance3D).get_aabb()
		out = a
		first = false
	for c in n.get_children():
		var ca := _aabb(c, t)
		if ca.size.length() > 0.0:
			if first:
				out = ca
				first = false
			else:
				out = out.merge(ca)
	return out

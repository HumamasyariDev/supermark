extends RefCounted
## W2 Beanstalk Skyway: deterministic geometry and collision builder (owned by the W2 world builder).
## Builds the garden island, roots, beanstalk, leaf and cloud platforms, the Giant's castle and kitchen,
## Jack's cottage, the cloud layers, the cloud sea and the backdrop from w2_level.json (a copy of
## data/levels/W2.json). Everything is generated at load time from fixed formulas and seeds, so the
## result is identical on every run. Gameplay nodes live in w2_play.gd; motion lives in w2_life.gd.

const M := preload("res://scripts/worlds/w2_mesh.gd")
const PROPS := "res://assets/props/w2/"
const TOON := "res://assets/shaders/toon.gdshader"

const C_GRASS := Color("7cc657")
const C_SOIL := Color("9a6b45")
const C_ROCK := Color("8c7a68")
const C_STALK := Color("3a9440")
const C_STALK_DARK := Color("245a26")
const C_STALK_LIGHT := Color("7fd04e")
const C_LEAF := Color("8dd35f")
const C_STONE := Color("e2d8c8")
const C_STONE_DARK := Color("b9a58e")
const C_SLATE := Color("6e4a9e")
const C_ROOF := Color("a93a2a")
const C_WOOD := Color("a0683c")
const C_WOOD_DARK := Color("6b4226")
const C_CREAM := Color("f2e6cf")
const C_THATCH := Color("e3c26b")
const C_TIMBER := Color("8a5a35")
const C_GOLD := Color("f2b632")
const C_BANNER := Color("b3263a")
const C_PEA := Color("9ad84a")

var world: Node3D
var level: Node3D
var data: Dictionary
var plat := {}            # id -> platform dictionary from the JSON
var bodies := {}          # id -> StaticBody3D / node created for that platform (used by w2_play / w2_life)
var visuals := {}         # id -> visual Node3D
var _mats := {}
var _sphere_mesh: SphereMesh
var _leaf_mesh: Mesh
var _cloud_groups := {}   # name -> Array[Transform3D]


func build(w: Node3D, d: Dictionary) -> Node3D:
	world = w
	data = d
	for p in data.get("platforms", []):
		plat[String(p["id"])] = p
	level = Node3D.new()
	level.name = "Level"
	world.add_child(level)
	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radius = 1.0
	_sphere_mesh.height = 2.0
	_sphere_mesh.radial_segments = 20
	_sphere_mesh.rings = 10
	_island()
	_roots()
	_stalk()
	_leaves()
	_cloud_decks()
	_special_platforms()
	_allotment()
	_cottage()
	_garden_props()
	_castle()
	_kitchen()
	_belfry()
	_r1_structures()
	_r2_structures()
	_r3_structures()
	_cloud_layers()
	_backdrop()
	_flush_clouds()
	return level


# ------------------------------------------------------------------ helpers

func _node(n: String, parent: Node = null) -> Node3D:
	var x := Node3D.new()
	x.name = n
	(parent if parent else level).add_child(x)
	return x


func _body(n: String, parent: Node = null) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = n
	b.collision_layer = 1
	b.collision_mask = 0
	(parent if parent else level).add_child(b)
	return b


func _shape(body: CollisionObject3D, s: Shape3D, xf := Transform3D.IDENTITY) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.transform = xf
	body.add_child(cs)
	return cs


func _box_col(body: CollisionObject3D, size: Vector3, xf := Transform3D.IDENTITY) -> void:
	var b := BoxShape3D.new()
	b.size = size
	_shape(body, b, xf)


func _cyl_col(body: CollisionObject3D, r: float, h: float, center: Vector3) -> void:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	_shape(body, c, Transform3D(Basis(), center))


## Elliptic prism whose top is at `top` (world/local of the body), for cloud decks and leaves.
func _ellipse_col(body: CollisionObject3D, top: Vector3, rx: float, rz: float, thick: float, rot_y := 0.0, segs := 20) -> void:
	var pts := PackedVector3Array()
	var b := Basis(Vector3.UP, deg_to_rad(rot_y))
	# Near-vertical rim (no overhang to bump Mak's head when he jumps up from below), slab 0.8 m deep
	# at the rim, then tapering underneath.
	for s in segs:
		var a := TAU * float(s) / float(segs)
		var o := b * Vector3(cos(a) * rx, 0, sin(a) * rz)
		pts.append(top + o)
		pts.append(top + o * 0.995 + Vector3(0, -minf(0.8, thick), 0))
		pts.append(top + o * 0.7 + Vector3(0, -thick, 0))
	var cp := ConvexPolygonShape3D.new()
	cp.points = pts
	_shape(body, cp)


func _mi(mesh: Mesh, parent: Node = null, xf := Transform3D.IDENTITY, n := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if n != "":
		mi.name = n
	mi.mesh = mesh
	mi.transform = xf
	(parent if parent else level).add_child(mi)
	return mi


## Look polish 2026-10-19 (owner: "hardly any texture on this level, it looks like one colour"): every vertex-coloured
## toon surface gets a quiet world-space value grain (game/assets/textures/w2_grain_<kind>.png, made from the project's
## retro tiles): "paint" by default, "leaf" for plants, "soil" for earth and roots, "" for none. Hue stays the vertex
## colour; the albedo lift keeps the mean value.
const GRAIN := {"paint": [0.55, 1.1], "leaf": [0.7, 1.22], "soil": [0.6, 1.18]}


const APPLE_TREE_GLB := "res://assets/props/w1/apple_tree/apple_tree.glb"


func vc_mat(rim := 0.35, spec := 0.3, grain := "paint") -> ShaderMaterial:
	var key := "vc_%s_%s_%s" % [rim, spec, grain]
	if _mats.has(key):
		return _mats[key]
	var sm := ShaderMaterial.new()
	sm.shader = load(TOON)
	sm.set_shader_parameter("use_vertex_color", true)
	sm.set_shader_parameter("albedo", Color.WHITE)
	var gp := "res://assets/textures/w2_grain_%s.png" % grain
	if GRAIN.has(grain) and ResourceLoader.exists(gp):
		var gk: Array = GRAIN[grain]
		sm.set_shader_parameter("albedo_texture", load(gp))
		sm.set_shader_parameter("triplanar", true)
		sm.set_shader_parameter("triplanar_scale", float(gk[0]))
		sm.set_shader_parameter("albedo", Color(float(gk[1]), float(gk[1]), float(gk[1])))
	sm.set_shader_parameter("rim_strength", rim)
	sm.set_shader_parameter("spec_strength", spec)
	sm.set_shader_parameter("shadow_tint", Color(0.62, 0.55, 0.78))
	_mats[key] = sm
	return sm


## Textured toon material (world-space triplanar) tinted by vertex colour.
func tex_mat(tex_name: String, scale := 0.35) -> Material:
	var key := "tex_%s_%s" % [tex_name, scale]
	if _mats.has(key):
		return _mats[key]
	var path := "res://assets/shaders/materials/toon_%s.tres" % tex_name
	var m: Material
	if ResourceLoader.exists(path):
		var sm := (load(path) as ShaderMaterial).duplicate() as ShaderMaterial
		sm.set_shader_parameter("use_vertex_color", true)
		sm.set_shader_parameter("triplanar_scale", scale)
		sm.set_shader_parameter("shadow_tint", Color(0.62, 0.55, 0.78))
		m = sm
	else:
		m = vc_mat()
	_mats[key] = m
	return m


func cloud_mat() -> Material:
	if _mats.has("cloud"):
		return _mats["cloud"]
	var m: Material
	if ResourceLoader.exists("res://assets/shaders/materials/cloud_platform.tres"):
		# Round 2 value pass: deck tops about 90 % value with a warm peach tint, lavender shade, so the
		# cream hero reads against them.
		var cm := (load("res://assets/shaders/materials/cloud_platform.tres") as ShaderMaterial).duplicate() as ShaderMaterial
		if OS.has_feature("web"):
			# The Compatibility ambient/base pass washes these custom-lit puffs
			# into flat white. The controlled web probe recovers their ramp when
			# ambient is omitted. Keep this shader copy local to W2's clouds.
			# OPUSLOOK: still needed after the colour fix. With ambient on, the base pass and the separately added sun
			# pass both land near white and their sum clips (tried without it: flat white puffs).
			cm.shader = cm.shader.duplicate() as Shader
			cm.shader.code = cm.shader.code.replace("diffuse_lambert, specular_disabled", "diffuse_lambert, specular_disabled, ambient_light_disabled")
		# Grade fix r2: whiter tops and a cooler, lighter shade (the key art's clouds are white with soft blue-lavender
		# shading; the stronger grade otherwise turned whole decks purple).
		cm.set_shader_parameter("light_color", Color("f7f1f2"))
		cm.set_shader_parameter("shade_color", Color("aaa6dc"))
		m = cm
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color("fff8f0")
		sm.roughness = 1.0
		m = sm
	_mats["cloud"] = m
	return m


## Grade fix r2 (visual critic: wide shots washed out by the white cloud sea): the cloud sea and the far cloud
## mountains get a deeper periwinkle shade and a lilac top, so depth reads and the playable decks stay the
## whitest things in frame.
func sea_mat() -> Material:
	if _mats.has("sea"):
		return _mats["sea"]
	var base := cloud_mat()
	var m := base.duplicate() as Material
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("light_color", Color("e6dcf0"))
		(m as ShaderMaterial).set_shader_parameter("shade_color", Color("8b86d2"))
	_mats["sea"] = m
	return m


## Fix r1: walkable decks get the W2 deck shader (normal-graded albedo: light tops, lavender sides and undersides).
func deck_mat() -> Material:
	if _mats.has("deck"):
		return _mats["deck"]
	var path := "res://assets/environment/w2/w2_cloud_deck.gdshader"
	if not ResourceLoader.exists(path):
		return cloud_mat()
	var sm := ShaderMaterial.new()
	sm.shader = load(path)
	var base := cloud_mat() as ShaderMaterial
	if base:
		for prm in ["light_color", "shade_color", "rim_color", "rim_strength", "puff_amount", "puff_scale", "puff_speed", "ramp_softness", "glow"]:
			var v: Variant = base.get_shader_parameter(prm)
			if v != null:
				sm.set_shader_parameter(prm, v)
	sm.set_shader_parameter("light_color", Color("fff6ee"))
	sm.set_shader_parameter("rim_color", Color("ffd9a8"))
	_mats["deck"] = sm
	return sm


func glb(path: String) -> Node3D:
	var full := path if path.begins_with("res://") else PROPS + path
	if not ResourceLoader.exists(full):
		return null
	var ps := load(full) as PackedScene
	return ps.instantiate() as Node3D if ps else null


func glb_mesh(path: String) -> Mesh:
	var n := glb(path)
	if n == null:
		return null
	var out: Mesh = null
	for c in n.find_children("*", "MeshInstance3D", true, false):
		out = (c as MeshInstance3D).mesh
		break
	n.free()
	return out


func place_glb(path: String, parent: Node3D, xf: Transform3D, n := "") -> Node3D:
	var g := glb(path)
	if g == null:
		return null
	if n != "":
		g.name = n
	g.transform = xf
	parent.add_child(g)
	return g


## Local-space bounds of all meshes under a freshly instanced (not yet in tree) scene.
static func glb_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D()
		var c: Node = mi
		while c != n and c != null:
			if c is Node3D:
				xf = (c as Node3D).transform * xf
			c = c.get_parent()
		var bb := xf * (mi as MeshInstance3D).get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


## Places a generated prop with its base centre at `base`, uniformly scaled to fit inside `fit` (world
## axes after the yaw), turned by `yaw` radians. Returns null when the file is missing.
func place_fit(path: String, parent: Node3D, base: Vector3, fit: Vector3, yaw: float, n := "") -> Node3D:
	var g := glb(path)
	if g == null:
		return null
	var bb := glb_aabb(g)
	var sx := bb.size.x
	var sz := bb.size.z
	if absf(sin(yaw)) > 0.7:
		var tmp := sx
		sx = sz
		sz = tmp
	var k := minf(fit.y / maxf(bb.size.y, 0.001), minf(fit.x / maxf(sx, 0.001), fit.z / maxf(sz, 0.001)))
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * k)
	var centre := Vector3(bb.position.x + bb.size.x * 0.5, bb.position.y, bb.position.z + bb.size.z * 0.5)
	g.transform = Transform3D(basis, base - basis * centre)
	if n != "":
		g.name = n
	parent.add_child(g)
	return g


func _cloud(group: String, xf: Transform3D) -> void:
	if not _cloud_groups.has(group):
		_cloud_groups[group] = []
	(_cloud_groups[group] as Array).append(xf)


func _flush_clouds() -> void:
	var holder := _node("CloudPuffs")
	for g in _cloud_groups.keys():
		var arr: Array = _cloud_groups[g]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _sphere_mesh
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Clouds_" + String(g)
		mmi.multimesh = mm
		var gname := String(g)
		mmi.material_override = deck_mat() if (gname.begins_with("deck_") or gname == "bank") else cloud_mat()
		if gname.begins_with("sea") or gname.begins_with("far"):
			mmi.material_override = sea_mat()  # grade fix r2: the far cloud sea sits in blue-lavender haze
		if String(g).begins_with("layer") or String(g).begins_with("sea") or String(g).begins_with("far"):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)


static func v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func h01(x: float, y: float, s := 0.0) -> float:
	return M.hash01(x, y, s)


## Generic smooth grid into a batch: rows of points (each a PackedVector3Array of equal length).
func grid_into(m, rows: Array, colrows: Array, wrap: bool, outward: Callable) -> void:
	var R := rows.size()
	var C := (rows[0] as PackedVector3Array).size()
	var ids := PackedInt32Array()
	for r in R:
		var row: PackedVector3Array = rows[r]
		var crow: PackedColorArray = colrows[r]
		for c in C:
			var p := row[c]
			var cp: Vector3 = row[(c + 1) % C] if wrap else row[mini(c + 1, C - 1)]
			var cm: Vector3 = row[(c - 1 + C) % C] if wrap else row[maxi(c - 1, 0)]
			var rp: Vector3 = (rows[mini(r + 1, R - 1)] as PackedVector3Array)[c]
			var rm: Vector3 = (rows[maxi(r - 1, 0)] as PackedVector3Array)[c]
			var o: Vector3 = outward.call(p)
			var n := (cp - cm).cross(rp - rm)
			if n.length_squared() < 1e-10:
				n = o
			n = n.normalized()
			if n.dot(o) < 0.0:
				n = -n
			ids.append(m.add_v(p, n, crow[c]))
	m.grid(ids, R, C, wrap)


# ------------------------------------------------------------------ island

const ISLAND_C := Vector2(0, 14)
const ISLAND_R := 22.0


func island_h(x: float, z: float) -> float:
	var h := 1.8 * exp(-((x - 13.0) ** 2 + (z - 28.0) ** 2) / (2.0 * 16.0)) + 1.0 * exp(-((x + 17.0) ** 2 + (z - 8.0) ** 2) / (2.0 * 20.25))
	h *= smoothstep(5.0, 7.0, Vector2(x, z).distance_to(Vector2(-12, 18)))
	h *= smoothstep(3.5, 5.0, Vector2(x, z).length())
	# Gentle hand-made undulation away from the paths and pads.
	h += 0.18 * (M.vnoise(x * 0.18, z * 0.18, 3.0) - 0.5) * smoothstep(6.0, 9.0, Vector2(x, z).distance_to(Vector2(-12, 18))) * smoothstep(4.5, 7.0, Vector2(x, z).length())
	var r := Vector2(x, z).distance_to(ISLAND_C)
	var bev := 0.6
	if r > ISLAND_R - bev:
		var t := clampf((r - (ISLAND_R - bev)) / bev, 0.0, 1.0)
		h -= bev * (1.0 - cos(t * PI * 0.5)) * 1.0
	return h


func _path_mask(x: float, z: float) -> float:
	var best := 0.0
	for p in data["terrain"]["paths"]:
		var pts: Array = []
		for q in p["points"]:
			pts.append(v3(q))
		var line := M.catmull(pts, 0.8)
		var hw := float(p["width"]) * 0.5
		var d := 1e9
		for i in line.size() - 1:
			var a := Vector2(line[i].x, line[i].z)
			var b := Vector2(line[i + 1].x, line[i + 1].z)
			var ab := b - a
			var t := clampf((Vector2(x, z) - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			d = minf(d, Vector2(x, z).distance_to(a + ab * t))
		var wob := (M.vnoise(x * 0.9, z * 0.9, 7.0) - 0.5) * 0.35
		best = maxf(best, 1.0 - smoothstep(hw - 0.35 + wob, hw + 0.25 + wob, d))
	return best


func _island() -> void:
	var holder := _node("GardenIsland")
	var m = M.new()
	m.linear_colors = false
	var rows := []
	var cols := []
	var NR := 40
	var NS := 144
	for ri in NR + 1:
		var t := float(ri) / float(NR)
		var rr := ISLAND_R * (1.0 - pow(1.0 - t, 1.35))
		var row := PackedVector3Array()
		var crow := PackedColorArray()
		for s in NS:
			var a := TAU * float(s) / float(NS)
			var x := ISLAND_C.x + cos(a) * rr
			var z := ISLAND_C.y + sin(a) * rr
			row.append(Vector3(x, island_h(x, z), z))
			var pm := _path_mask(x, z)
			crow.append(Color(pm, 0.0, 0.0, 1.0))
		rows.append(row)
		cols.append(crow)
	grid_into(m, rows, cols, true, func(_p: Vector3) -> Vector3: return Vector3.UP)
	var tmat: Material = load("res://assets/shaders/materials/terrain_skyway.tres") if ResourceLoader.exists("res://assets/shaders/materials/terrain_skyway.tres") else vc_mat()
	if tmat is ShaderMaterial and ResourceLoader.exists("res://assets/textures/w2_meadow.png"):
		# Look polish 2026-10-19: a 128 px meadow tile with visible blades instead of the near-flat 64 px grass, and
		# half the macro variation (its dithered bands read as giant pixels from the follow camera).
		tmat = (tmat as ShaderMaterial).duplicate()
		(tmat as ShaderMaterial).set_shader_parameter("grass_texture", load("res://assets/textures/w2_meadow.png"))
		(tmat as ShaderMaterial).set_shader_parameter("macro_variation", 0.07)
		(tmat as ShaderMaterial).set_shader_parameter("grass_brightness", 1.0)
	var top_mesh: ArrayMesh = m.commit(tmat)
	_mi(top_mesh, holder, Transform3D.IDENTITY, "IslandTop")
	var body := _body("IslandCollision", holder)
	var cps := ConcavePolygonShape3D.new()
	cps.set_faces(m.faces())
	_shape(body, cps)
	# Underside: soil band then a lobed rock cone to the apex.
	var u = M.new()
	var urows := []
	var ucols := []
	var NU := 16
	var apex := Vector3(0, -20, 14)
	for ri in NU + 1:
		var t := float(ri) / float(NU)
		var row := PackedVector3Array()
		var crow := PackedColorArray()
		for s in NS / 2:
			var a := TAU * float(s) / float(NS / 2)
			var lobe := sin(a * 8.0 + 0.6) * 0.5 + 0.5
			var nz := M.vnoise(a * 3.0, t * 5.0, 11.0)
			var rr: float
			var y: float
			if ri == 0:
				rr = ISLAND_R
				y = -0.6
			elif ri == 1:
				rr = ISLAND_R - 0.05
				y = -1.3
			else:
				var k := (t - 1.0 / NU) / (1.0 - 1.0 / NU)
				rr = (ISLAND_R - 0.4) * pow(1.0 - k, 0.75) + (lobe * 1.5 + nz * 1.2) * (1.0 - k) * sin(k * PI + 0.3)
				y = lerpf(-1.3, apex.y, pow(k, 0.85))
			row.append(Vector3(ISLAND_C.x + cos(a) * rr, y, ISLAND_C.y + sin(a) * rr))
			var c := C_SOIL if ri <= 1 else C_ROCK.lerp(C_ROCK.darkened(0.25), t).lerp(Color("a48a72"), nz * 0.4)
			crow.append(c)
		urows.append(row)
		ucols.append(crow)
	grid_into(u, urows, ucols, true, func(p: Vector3) -> Vector3: return Vector3(p.x - ISLAND_C.x, -0.6, p.z - ISLAND_C.y).normalized())
	_mi(u.commit(tex_mat("cliff_rock", 0.18)), holder, Transform3D.IDENTITY, "IslandUnderside")
	var ub := _body("UndersideCollision", holder)
	var ucp := ConcavePolygonShape3D.new()
	ucp.set_faces(u.faces())
	_shape(ub, ucp)
	# Hanging roots under the island.
	var hr = M.new()
	for i in 14:
		var a := TAU * float(i) / 14.0 + 0.2
		var rr := 14.0 + h01(i, 1.0) * 6.0
		var base := Vector3(ISLAND_C.x + cos(a) * rr, -3.0 - h01(i, 2.0) * 4.0, ISLAND_C.y + sin(a) * rr)
		var pts: Array = [base]
		var L := 3.0 + h01(i, 3.0) * 5.0
		for k in 4:
			pts.append(base + Vector3(sin(k * 1.3 + i) * 0.6, -L * float(k + 1) / 4.0, cos(k * 1.7 + i) * 0.6))
		var line := M.catmull(pts, 0.5)
		var radii := PackedFloat32Array()
		for j in line.size():
			radii.append(lerpf(0.32, 0.05, float(j) / float(line.size() - 1)))
		hr.tube(line, radii, Color("7a5638"), 7, false, true)
	_mi(hr.commit(vc_mat(0.2, 0.3, "soil")), holder, Transform3D.IDENTITY, "HangingRoots")


func _roots() -> void:
	var holder := _node("Roots")
	var m = M.new()
	var body := _body("RootCollision", holder)
	for r in data["terrain"]["roots"]:
		var pts: Array = []
		for q in r["points"]:
			pts.append(v3(q))
		var line := M.catmull(pts, 0.4)
		var radii := PackedFloat32Array()
		var base_r := float(r["radius"])
		for j in line.size():
			var t := float(j) / float(line.size() - 1)
			radii.append(base_r * lerpf(1.15, 0.55, t))
		var one = M.new()
		one.tube(line, radii, C_STALK_DARK.lerp(Color("6b5a2e"), 0.35), 12, false, true, C_STALK, 2)
		m.append(one)
		if true:   # look polish: was bool(r.get("walkable", false))
			var cps := ConcavePolygonShape3D.new()
			cps.set_faces(one.faces())
			_shape(body, cps)
	_mi(m.commit(vc_mat(0.3, 0.3, "soil")), holder, Transform3D.IDENTITY, "RootMesh")


# ------------------------------------------------------------------ beanstalk

func stalk_spline() -> Array:
	var out: Array = []
	for k in data["terrain"]["stalk"]["spline"]:
		out.append(k)
	return out


func _stalk() -> void:
	var holder := _node("Beanstalk")
	var spl := stalk_spline()
	var knots: Array = []
	var radii_k: Array = []
	for k in spl:
		knots.append(Vector3(k[0], k[1], k[2]))
		radii_k.append(float(k[3]))
	# The amended spline ends in the hook that carries the Giant's bell; finish it with a small curl.
	var tip: Vector3 = knots[knots.size() - 1]
	knots.append(tip + Vector3(-1.1, -0.3, 0.2))
	radii_k.append(0.36)
	knots.append(tip + Vector3(-1.3, -1.1, 0.3))
	radii_k.append(0.3)
	var line := M.catmull(knots, 0.45)
	# Radius per sample from the nearest knot interpolation by height.
	var rads := PackedFloat32Array()
	var arc := PackedFloat32Array()
	var acc := 0.0
	for i in line.size():
		if i > 0:
			acc += line[i].distance_to(line[i - 1])
		arc.append(acc)
		rads.append(_radius_at(line[i], knots, radii_k))
	var m = M.new()
	# Core.
	var core_r := PackedFloat32Array()
	for i in line.size():
		core_r.append(rads[i] * 0.66)
	m.tube(line, core_r, C_STALK_DARK, 14, true, true)
	# Three twisted strands.
	var twist := deg_to_rad(float(data["terrain"]["stalk"].get("twist_deg_per_m", 9.0)))
	for k in 3:
		var pts := PackedVector3Array()
		var rr := PackedFloat32Array()
		for i in line.size():
			var th := arc[i] * twist + TAU * float(k) / 3.0
			var off := rads[i] * 0.46
			pts.append(line[i] + Vector3(cos(th) * off, 0, sin(th) * off))
			rr.append(rads[i] * 0.56)
		var col := C_STALK.lerp(C_STALK_LIGHT, 0.12 * k)
		m.tube(pts, rr, col, 14, true, true, C_STALK_LIGHT.lightened(0.15), 1)
	_mi(m.commit(vc_mat(0.4, 0.45)), holder, Transform3D.IDENTITY, "StalkMesh")
	# Knots and bean pods (visual).
	var deco = M.new()
	for i in range(6, line.size() - 8, 9):
		var p := line[i]
		var a := h01(float(i), 4.0) * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var r := rads[i]
		deco.sphere(Transform3D(Basis().scaled(Vector3(0.5, 0.42, 0.5) * r), p + out * r * 0.95), C_STALK.lerp(C_STALK_LIGHT, 0.15), 22, 11, C_STALK_DARK.lerp(C_STALK, 0.4))  # fix r1: smooth, graded knots
		if i % 2 == 0 and p.y > 2.0:
			# Hanging bean pod.
			var pod_top := p + out * (r + 0.4)
			var pod_b := Basis(Vector3.FORWARD, 0.25 * (h01(i, 5.0) - 0.5)).scaled(Vector3(0.28, 0.9, 0.22))
			deco.sphere(Transform3D(pod_b, pod_top + Vector3(0, -0.9, 0)), C_PEA.darkened(0.1), 12, 8)
		elif p.y > 3.0 and p.y < 64.0:
			# Fix r2 (visual critic): violet bean flowers along the stalk, as in the key art.
			var fa := a + 1.9
			var fo := Vector3(cos(fa), 0.25, sin(fa)).normalized()
			var fc := p + Vector3(cos(fa), 0, sin(fa)) * (r + 0.12)
			var fb := Basis.looking_at(-fo, Vector3.UP)
			for q in 5:
				var pa := TAU * float(q) / 5.0
				var pd := fb * Vector3(cos(pa), sin(pa), 0.0)
				deco.sphere(Transform3D(fb.scaled(Vector3(0.26, 0.26, 0.09)), fc + pd * 0.24 + fo * 0.08), Color("8c5ce0").lerp(Color("b38cff"), float(q % 2) * 0.4), 12, 6, Color("6a3cc0"))
			deco.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.11), fc + fo * 0.16), Color("ffe27a"), 10, 6)
	_mi(deco.commit(vc_mat(0.35)), holder, Transform3D.IDENTITY, "StalkKnots")
	# Small decorative leaves along the stalk (instances of the real leaf mesh).
	_leaf_mesh = glb_mesh("giant_leaf/giant_leaf.glb")
	if _leaf_mesh:
		var xfs: Array = []
		var i := 3
		while i < line.size() - 4:
			var p := line[i]
			var a := arc[i] * 1.7 + h01(float(i), 9.0) * 1.2
			var out := Vector3(cos(a), 0, sin(a))
			var s := clampf(rads[i] * 0.22, 0.22, 0.55)
			var b := Basis.looking_at(-out, Vector3.UP)  # -Z toward the stalk = stem inward
			b = b * Basis(Vector3.RIGHT, -0.35 - h01(float(i), 2.0) * 0.4)
			var lp := p + out * rads[i] * 0.9
			# Fix r1: no decorative leaf inside the Giant's bell sweep (pivot (-13, 66.5, -16), 6 m swing).
			if Vector2(lp.x + 13.0, lp.z + 16.0).length() > 3.8 or lp.y < 58.0 or lp.y > 68.0:
				xfs.append(Transform3D(b.scaled(Vector3(s, s, s)), lp))
			i += 3
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _leaf_mesh
		mm.instance_count = xfs.size()
		for j in xfs.size():
			mm.set_instance_transform(j, xfs[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "StalkLeaves"
		mmi.multimesh = mm
		holder.add_child(mmi)
	var ten = M.new()
	# Curly tendrils off the stalk.
	for k in 10:
		var j := 20 + k * int((line.size() - 40) / 10)
		var p := line[j]
		var a := h01(float(k), 6.0) * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var cp: Array = []
		for q in 9:
			var ang := float(q) * 0.75
			var rad := 1.3 * (1.0 - float(q) / 10.0)
			cp.append(p + out * (rads[j] + 0.3 + float(q) * 0.22) + Vector3(0, sin(ang) * rad, 0) + out.cross(Vector3.UP) * cos(ang) * rad * 0.6)
		var cl := M.catmull(cp, 0.25)
		var cr := PackedFloat32Array()
		for q in cl.size():
			cr.append(lerpf(0.12, 0.04, float(q) / float(cl.size() - 1)))
		ten.tube(cl, cr, C_STALK_LIGHT, 6, false, true)
	_mi(ten.commit(vc_mat(0.35)), holder, Transform3D.IDENTITY, "Tendrils")
	# Collision: one capsule per spline segment.
	var body := _body("StalkCollision", holder)
	body.add_to_group("w2_stalk")
	for i in spl.size() - 1:
		var a: Vector3 = v3(spl[i])
		var b: Vector3 = v3(spl[i + 1])
		if b.y > 62.6:
			break  # the hook above 62.5 is visual only (nobody walks the hook to the belfry)
		var r := (float(spl[i][3]) + float(spl[i + 1][3])) * 0.5 * 0.92
		var cap := CapsuleShape3D.new()
		cap.radius = r
		cap.height = a.distance_to(b) + 2.0 * r
		var y := (b - a).normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		_shape(body, cap, Transform3D(Basis(x, y, z), (a + b) * 0.5))


func _radius_at(p: Vector3, knots: Array, radii_k: Array) -> float:
	for i in knots.size() - 1:
		var a: Vector3 = knots[i]
		var b: Vector3 = knots[i + 1]
		if p.y <= b.y or i == knots.size() - 2:
			var t := clampf((p.y - a.y) / maxf(b.y - a.y, 0.001), 0.0, 1.0)
			return lerpf(float(radii_k[i]), float(radii_k[i + 1]), t)
	return float(radii_k[radii_k.size() - 1])


## Point on the stalk's centre line at height y (for stems and dressing).
func stalk_center(y: float) -> Vector3:
	var spl := stalk_spline()
	for i in spl.size() - 1:
		var a := v3(spl[i])
		var b := v3(spl[i + 1])
		if y <= b.y or i == spl.size() - 2:
			var t := clampf((y - a.y) / maxf(b.y - a.y, 0.001), 0.0, 1.0)
			return a.lerp(b, t)
	return v3(spl[spl.size() - 1])


# ------------------------------------------------------------------ leaves

func _leaves() -> void:
	var holder := _node("Leaves")
	var stems = M.new()
	for id in plat.keys():
		var p: Dictionary = plat[id]
		var kind := String(p["kind"])
		if not (kind in ["leaf", "bouncy_leaf", "droop_leaf", "moving_leaf", "bouncy_leaf_swing"]):
			continue
		var pos := v3(p["pos"])
		var bouncy := kind == "bouncy_leaf" or kind == "bouncy_leaf_swing"
		var animated := kind in ["droop_leaf", "moving_leaf", "bouncy_leaf_swing"]
		var stem_to: Vector3 = v3(p["stem_to"]) if p.has("stem_to") else Vector3.ZERO
		var has_stem := p.has("stem_to") and kind != "moving_leaf"
		var body: PhysicsBody3D
		if animated:
			var ab := AnimatableBody3D.new()
			ab.name = String(id)
			ab.sync_to_physics = true
			ab.collision_layer = 1
			ab.collision_mask = 0
			# Place before entering the tree: a sync_to_physics body read back in the same frame otherwise reports
			# the origin (critic round 1 blocker: L06-L08 and LB1-LB5 parked at (0,0,0)).
			ab.position = pos
			holder.add_child(ab)
			body = ab
		else:
			body = _body(String(id), holder)
		body.position = pos
		body.set_meta("kind", kind)
		bodies[id] = body
		var yaw_basis: Basis
		if has_stem:
			var dir := stem_to - pos
			dir.y = 0.0
			if dir.length() < 0.05:
				dir = Vector3.FORWARD
			yaw_basis = Basis.looking_at(dir.normalized(), Vector3.UP)
		else:
			yaw_basis = Basis(Vector3.UP, deg_to_rad(float(p.get("rot_y", 0.0)) + h01(pos.x, pos.z) * 90.0))
		var vis := Node3D.new()
		vis.name = "Visual"
		body.add_child(vis)
		visuals[id] = vis
		var path := "giant_leaf/giant_leaf_bouncy.glb" if bouncy else "giant_leaf/giant_leaf.glb"
		if kind == "moving_leaf" and p.has("stem_to"):
			var d2 := stem_to - pos
			d2.y = 0.0
			yaw_basis = Basis.looking_at(d2.normalized(), Vector3.UP)
		var size_scale: float
		if String(p["shape"]) == "disc":
			var r := float(p["r"])
			size_scale = r / 1.55
			_cyl_col(body, r, float(p.get("thickness", 0.35)), Vector3(0, -float(p.get("thickness", 0.35)) * 0.5, 0))
		else:
			size_scale = 0.82
			_box_col(body, Vector3(2.7, 0.35, 3.1), Transform3D(yaw_basis, Vector3(0, -0.175, 0)))
		var g: Node3D = null
		if id != "BEARD":
			g = place_glb(path, vis, Transform3D(yaw_basis.scaled(Vector3.ONE * size_scale), Vector3(0, -LEAF_TOP * size_scale, 0)), "Leaf")
		if g == null and id != "BEARD":
			var lm = M.new()
			lm.leaf(Transform3D(yaw_basis, Vector3.ZERO), 1.4 * size_scale / 0.82, 1.6 * size_scale / 0.82, 0.3, C_LEAF, C_STALK, C_LEAF.lightened(0.3))
			_mi(lm.commit(vc_mat(0.35, 0.3, "leaf")), vis)
		if bouncy and id != "BEARD":
			body.add_to_group("bouncy")
			var apex := float(p.get("bounce_apex", 4.0))
			body.set_meta("bounce_velocity", sqrt(2.0 * GRAVITY * apex))
			body.set_meta("bounce_apex", apex)
			# Teal glow ring under the bouncy leaf so it reads as springy.
			var ring = M.new()
			ring.torus(Transform3D(Basis(), Vector3(0, -0.28, 0)), 0.9 * size_scale / 0.82, 0.12, Color("3fc6a0"), 20, 6)
			_mi(ring.commit(vc_mat(0.6)), vis, Transform3D.IDENTITY, "Spring")
		elif id == "BEARD":
			body.add_to_group("bouncy")
			body.set_meta("bounce_velocity", sqrt(2.0 * GRAVITY * float(p.get("bounce_apex", 5.0))))
		# Stem: from the leaf's inner edge to the stalk point (or a hanging tendril for free leaves).
		if has_stem:
			var inner := pos + yaw_basis * Vector3(0, -0.18, -1.3 * size_scale / 0.82)
			var target := stem_to
			var c := stalk_center(target.y)
			target = c + (target - c).normalized() * 0.2 if (target - c).length() > 0.01 else c
			var mid := inner.lerp(target, 0.5) + Vector3(0, -0.45, 0)
			var line := M.catmull([inner, mid, target], 0.3)
			var rr := PackedFloat32Array()
			for j in line.size():
				rr.append(lerpf(0.13, 0.24, float(j) / float(line.size() - 1)))
			stems.tube(line, rr, C_STALK, 8, true, false)
		elif p.has("hang"):
			# Hanging tendril; it is part of the body so it swings with the pad.
			var hm = M.new()
			var pts: Array = [Vector3(0, -0.1, 0), Vector3(0.3, 2.0, 0.2), Vector3(-0.2, 4.0, -0.1), Vector3(0, 6.0, 0)]
			var line := M.catmull(pts, 0.4)
			var rr := PackedFloat32Array()
			for j in line.size():
				rr.append(lerpf(0.12, 0.07, float(j) / float(line.size() - 1)))
			hm.tube(line, rr, C_STALK, 7, false, true)
			_mi(hm.commit(vc_mat(0.35)), vis, Transform3D.IDENTITY, "Tendril")
	_mi(stems.commit(vc_mat(0.35, 0.3, "leaf")), holder, Transform3D.IDENTITY, "Stems")


const GRAVITY := 28.0
## Height of the walkable blade top above the giant_leaf.glb origin (calibrated against captures).
const LEAF_TOP := 0.32


# ------------------------------------------------------------------ clouds

## Adds a puffy cloud body around an ellipse whose walkable top is at `top`.
func cloud_visual(group: String, top: Vector3, rx: float, rz: float, thick: float, seed := 0.0, dense := 1.0) -> void:
	# Top cushion: a broad, flat ellipsoid whose crown sits a hair above the walkable top.
	_cloud(group, Transform3D(Basis().scaled(Vector3(rx * 0.96, 0.55, rz * 0.96)), top + Vector3(0, -0.5, 0)))
	var per := maxf(rx, rz) * TAU
	var n := int(clampf(per / 1.6 * dense, 8, 90))
	for i in n:
		var a := TAU * (float(i) + h01(i, seed) * 0.5) / float(n)
		var e := Vector3(cos(a) * rx, 0, sin(a) * rz)
		var s := lerpf(0.8, 2.0, h01(i, seed + 1.0)) * clampf(minf(rx, rz) / 3.0, 0.55, 1.4)
		_cloud(group, Transform3D(Basis().scaled(Vector3(s, s * 0.8, s)), top + e * 0.93 + Vector3(0, -s * 0.55, 0)))
	# Underside lumps for volume (lavender in shade).
	var m := int(clampf(rx * rz / 4.0 * dense, 4, 60))
	for i in m:
		var a := h01(i, seed + 3.0) * TAU
		var d := sqrt(h01(i, seed + 4.0)) * 0.75
		var s := lerpf(1.0, 2.0, h01(i, seed + 5.0)) * clampf(minf(rx, rz) / 3.0, 0.6, 1.3)
		var lp := top + Vector3(cos(a) * rx * d, -thick * 0.45 - s * 0.2, sin(a) * rz * d)
		if group != "bank" and in_sightline(lp, s):
			continue
		_cloud(group, Transform3D(Basis().scaled(Vector3(s, s * 0.7, s)), lp))


func _cloud_decks() -> void:
	var holder := _node("CloudDecks")
	for id: String in plat.keys():
		var p: Dictionary = plat[id]
		if String(p["kind"]) != "cloud" or id == "BANK" or String(p["shape"]) == "annulus_sector":
			continue
		var pos := v3(p["pos"])
		var rx := float(p.get("rx", p.get("r", 2.0)))
		var rz := float(p.get("rz", p.get("r", 2.0)))
		var th := float(p.get("thickness", 1.0))
		var body := _body(id, holder)
		bodies[id] = body
		_ellipse_col(body, pos, rx, rz, th)
		cloud_visual("deck_" + id, pos, rx, rz, th, float(id.hash() % 97))
	# Castle bank: big ellipse plus the core box under the castle.
	var bp: Dictionary = plat["BANK"]
	var bpos := v3(bp["pos"])
	var bank := _body("BANK", holder)
	bodies["BANK"] = bank
	_ellipse_col(bank, bpos, 36.0, 15.0, 6.0, 0.0, 32)
	_box_col(bank, Vector3(44, 6, 22), Transform3D(Basis(), Vector3(2, 47, -35)))
	cloud_visual("bank", bpos, 36.0, 15.0, 4.0, 41.0, 0.55)
	# Extra puffs hugging the north side behind the castle.
	for i in 18:
		var x := -22.0 + float(i) * 2.6
		var s := 2.2 + h01(i, 51.0) * 1.8
		_cloud("bank", Transform3D(Basis().scaled(Vector3(s, s * 0.7, s)), Vector3(x, 49.2 - s * 0.3, -46.5 - h01(i, 52.0) * 1.5)))


# ------------------------------------------------------------------ special platforms

func _special_platforms() -> void:
	var holder := _node("Special")
	# M07: a fat bean pod lying on the stalk.
	var p: Dictionary = plat["M07"]
	var pos := v3(p["pos"])
	var body := _body("M07", holder)
	body.position = pos
	bodies["M07"] = body
	var yaw := deg_to_rad(float(p.get("rot_y", 0.0)))
	var b := Basis(Vector3.UP, yaw)
	_box_col(body, Vector3(float(p["sx"]), 0.6, float(p["sz"])), Transform3D(b, Vector3(0, -0.3, 0)))
	var m = M.new()
	m.sphere(Transform3D(b.scaled(Vector3(2.15, 0.62, 1.0)), Vector3(0, -0.55, 0)), C_PEA, 22, 12, C_STALK_DARK)
	# Three peas peeking out of the split top.
	for i in 3:
		var x := (float(i) - 1.0) * 1.15
		m.sphere(Transform3D(b.scaled(Vector3(0.42, 0.3, 0.42)), b * Vector3(x, -0.12, 0)), Color("b6ea62"), 14, 8)
	m.tube(M.catmull([b * Vector3(2.1, -0.5, 0), b * Vector3(2.7, -0.2, 0.2), stalk_center(pos.y) - pos], 0.3), _ramp(9, 0.16, 0.24), C_STALK, 8, true, false)
	_mi(m.commit(vc_mat(0.4, 0.5)), body, Transform3D.IDENTITY, "PodVisual")
	# Pea-vine bridge between the Cloud Landing and the Allotment.
	var bp: Dictionary = plat["PEA_BRIDGE"]
	var bpos := v3(bp["pos"])
	var bb := _body("PEA_BRIDGE", holder)
	bodies["PEA_BRIDGE"] = bb
	var by := Basis(Vector3.UP, deg_to_rad(float(bp["rot_y"])))
	var L := float(bp["sx"])
	_box_col(bb, Vector3(L + 1.0, 0.5, float(bp["sz"])), Transform3D(by, bpos + Vector3(0, -0.25, 0)))
	var bm = M.new()
	var a := bpos + by * Vector3(-L * 0.5 - 0.5, 0, 0)
	var c := bpos + by * Vector3(L * 0.5 + 0.5, 0, 0)
	for k in 3:
		var off := by * Vector3(0, 0, (float(k) - 1.0) * 0.55)
		var line := M.catmull([a + off + Vector3(0, -0.3, 0), a.lerp(c, 0.5) + off + Vector3(0, -0.5 + 0.1 * k, 0), c + off + Vector3(0, -0.3, 0)], 0.4)
		bm.tube(line, _ramp(line.size(), 0.32, 0.32), C_STALK.lerp(C_STALK_LIGHT, 0.2 * k), 10, true, true, C_STALK_LIGHT, 1)
	for i in 9:
		var t := (float(i) + 0.5) / 9.0
		var q := a.lerp(c, t) + Vector3(0, -0.15 - sin(t * PI) * 0.15, 0)
		var side := 1.0 if i % 2 == 0 else -1.0
		bm.leaf(Transform3D(by * Basis(Vector3.UP, side * 1.2) * Basis(Vector3.RIGHT, 0.25), q + by * Vector3(0, 0, side * 0.9)), 0.45, 0.6, 0.06, C_LEAF, C_STALK, C_LEAF.lightened(0.3), 0.05, 3, 16)
		if i % 3 == 1:
			bm.sphere(Transform3D(Basis().scaled(Vector3(0.18, 0.5, 0.15)), q + by * Vector3(0, -0.8, side * 0.5)), C_PEA, 10, 6)
	_mi(bm.commit(vc_mat(0.35)), holder, Transform3D.IDENTITY, "PeaBridge")
	# Bluebell Hive: a big blue bell cup on a curled side shoot (walkable rim with a floor inside).
	var hp: Dictionary = plat["HIVE"]
	var hpos := v3(hp["pos"])
	var hb := _body("HIVE", holder)
	bodies["HIVE"] = hb
	_cyl_col(hb, 1.8, 0.4, hpos + Vector3(0, -0.2, 0))
	var hm = M.new()
	var bell := Color("6f8ff0")
	hm.cylinder(Transform3D(Basis(), hpos + Vector3(0, -0.75, 0)), 1.95, 1.05, 1.5, bell, 24, false)
	hm.torus(Transform3D(Basis(), hpos + Vector3(0, 0.02, 0)), 1.95, 0.16, bell.lightened(0.2), 24, 8)
	hm.disc(Transform3D(Basis(), hpos + Vector3(0, -0.02, 0)), 1.8, 1.8, Color("ffe08a"), 24)
	hm.sphere(Transform3D(Basis().scaled(Vector3(1.05, 0.5, 1.05)), hpos + Vector3(0, -1.5, 0)), bell.darkened(0.15), 16, 8)
	# Tiny round hive door inside.
	hm.puck(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), hpos + Vector3(0, 0.25, -1.55)), 0.35, 0.08, 0.03, Color("8a5a35"), 16)
	var shoot := M.catmull([stalk_center(33.6) + Vector3(0.5, 0, 0), hpos + Vector3(-2.4, -2.2, 0.3), hpos + Vector3(-0.6, -2.0, 0), hpos + Vector3(0, -1.7, 0)], 0.3)
	hm.tube(shoot, _ramp(shoot.size(), 0.35, 0.22), C_STALK, 10, true, true)
	_mi(hm.commit(vc_mat(0.45)), holder, Transform3D.IDENTITY, "BluebellHive")
	# Root Ledge under the north-west rim.
	var rp: Dictionary = plat["ROOT_LEDGE"]
	var rpos := v3(rp["pos"])
	var rb := _body("ROOT_LEDGE", holder)
	bodies["ROOT_LEDGE"] = rb
	var ry := Basis(Vector3.UP, deg_to_rad(float(rp["rot_y"])))
	_box_col(rb, Vector3(float(rp["sx"]), 0.5, float(rp["sz"])), Transform3D(ry, rpos + Vector3(0, -0.25, 0)))
	var rm = M.new()
	rm.rbox(Transform3D(ry, rpos + Vector3(0, -0.35, 0)), Vector3(float(rp["sx"]) + 0.2, 0.7, float(rp["sz"]) + 0.2), 0.25, Color("8a6a4a"), 3, Color("7cc657"))
	_mi(rm.commit(tex_mat("cliff_rock", 0.3)), holder, Transform3D.IDENTITY, "RootLedge")


static func _ramp(n: int, a: float, b: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in n:
		out.append(lerpf(a, b, float(i) / float(maxi(n - 1, 1))))
	return out


# ------------------------------------------------------------------ the Giant's Allotment

func _allotment() -> void:
	var holder := _node("Allotment")
	var body := _body("AllotmentCollision", holder)
	var m = M.new()
	var greens = M.new()   # look polish: plants get the leaf grain
	var soil := Color("7a5638")
	# A lawn bed on top of the Allotment cloud so it reads as a garden plot, not bare cloud.
	var al: Dictionary = plat["ALLOT"]
	var ac := v3(al["pos"])
	var lawn = M.new()
	lawn.linear_colors = true
	lawn.puck(Transform3D(Basis().scaled(Vector3(float(al["rx"]) * 0.86, 1.0, float(al["rz"]) * 0.86)), ac + Vector3(0, -0.03, 0)), 1.0, 0.2, 0.06, Color("6fb84a"), 40, Color("86cc58"))
	# Look polish 2026-10-19: the lawn uses the 128 px meadow tile too (the 64 px grass read as giant blurry pixels).
	var lawn_mat := tex_mat("grass", 0.25)
	if lawn_mat is ShaderMaterial and ResourceLoader.exists("res://assets/textures/w2_meadow.png"):
		lawn_mat = (lawn_mat as ShaderMaterial).duplicate()
		(lawn_mat as ShaderMaterial).set_shader_parameter("albedo_texture", load("res://assets/textures/w2_meadow.png"))
	_mi(lawn.commit(lawn_mat), holder, Transform3D.IDENTITY, "AllotmentLawn")
	# Soil rows (visual 0.2 m mounds, no collision); the poppers sit in mounds along them.
	for row in data["props_zones"][6]["boxes"]:
		var x0 := float(row[0])
		var z := float(row[2])
		var L := float(row[3])
		var wdt := float(row[4])
		var c := Vector3(x0 + L * 0.5, 24.0, z)
		m.rbox(Transform3D(Basis(), c), Vector3(L, 0.4, wdt), 0.18, soil, 3, soil.lightened(0.12))
		for k in int(L / 1.6):
			var x := x0 + 0.8 + float(k) * 1.6
			if (k + int(z)) % 3 == 0:
				# Giant carrot tops.
				for f in 3:
					var a := float(f) * 2.1 + z
					greens.sphere(Transform3D(Basis(Vector3(cos(a), 0, sin(a)), 0.5).scaled(Vector3(0.18, 0.75, 0.18)), Vector3(x + cos(a) * 0.15, 25.0, z + sin(a) * 0.15)), Color("5fb043"), 8, 5)
				m.sphere(Transform3D(Basis().scaled(Vector3(0.35, 0.25, 0.35)), Vector3(x, 24.45, z)), Color("ff8a3d"), 10, 6)
			elif (k + int(z)) % 3 == 1:
				greens.sphere(Transform3D(Basis().scaled(Vector3(0.6, 0.45, 0.6)), Vector3(x, 24.65, z)), Color("8fd055").lerp(Color("5cae40"), h01(k, z)), 12, 7, Color("3f8a30"))
	# Giant cabbages (cover against pea lobs).
	for id: String in ["CABBAGE_A", "CABBAGE_B"]:
		var cp := v3(plat[id]["pos"])
		var ctr := cp + Vector3(0, -1.7, 0)
		greens.sphere(Transform3D(Basis().scaled(Vector3(1.9, 1.65, 1.9)), ctr), Color("a8de6c"), 28, 16, Color("4c9a32"))
		for k in 7:
			var a := TAU * float(k) / 7.0 + 0.3
			var lb := Basis(Vector3.UP, -a) * Basis(Vector3.BACK, 0.5)
			greens.sphere(Transform3D(lb.scaled(Vector3(1.3, 1.5, 0.35)), ctr + Vector3(cos(a), 0, sin(a)) * 1.55 + Vector3(0, 0.1, 0)), Color("6cb84c").lerp(Color("b9e47a"), h01(k, 3.0) * 0.5), 22, 12, Color("4c9a32"))
		var sp := SphereShape3D.new()
		sp.radius = 1.85
		_shape(body, sp, Transform3D(Basis(), ctr + Vector3(0, -0.2, 0)))
	# Flower pot, sacks and the giant watering can (route to the spout page).
	var pot := v3(plat["POT"]["pos"])
	m.cylinder(Transform3D(Basis(), Vector3(pot.x, 24.6, pot.z)), 1.3, 1.0, 1.2, Color("c4664a"), 20, true, Color("6b4430"))
	m.torus(Transform3D(Basis(), Vector3(pot.x, 25.1, pot.z)), 1.3, 0.14, Color("d27a5a"), 20, 6)
	for k in 4:
		m.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.4), Vector3(pot.x + cos(k * 1.6) * 0.6, 25.5, pot.z + sin(k * 1.6) * 0.6)), [Color("ff7fb0"), Color("ffd24a"), Color("b07cff"), Color("fff3c4")][k], 10, 6)
	_cyl_col(body, 1.3, 1.2, Vector3(pot.x, 24.6, pot.z))
	var sk := v3(plat["SACKS"]["pos"])
	m.sphere(Transform3D(Basis().scaled(Vector3(0.95, 1.2, 0.95)), Vector3(sk.x - 0.1, 25.2, sk.z)), Color("d8c08a"), 16, 9, Color("b89a62"))
	m.sphere(Transform3D(Basis().scaled(Vector3(0.75, 0.5, 0.75)), Vector3(sk.x + 0.2, 26.0, sk.z + 0.1)), Color("e6d3a8"), 14, 8)
	_box_col(body, Vector3(1.8, 2.4, 1.8), Transform3D(Basis(), Vector3(sk.x, 25.2, sk.z)))
	var can := v3(plat["CAN"]["pos"])
	var blue := Color("6f9ec4")
	m.cylinder(Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.78)), Vector3(can.x + 0.2, 25.8, can.z)), 1.9, 2.0, 3.6, blue, 26, true, blue.lightened(0.15))
	m.torus(Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.78)), Vector3(can.x + 0.2, 27.6, can.z)), 1.9, 0.12, blue.lightened(0.25), 26, 6)
	var handle := M.catmull([Vector3(can.x + 1.6, 27.4, can.z), Vector3(can.x + 1.2, 28.9, can.z), Vector3(can.x - 0.6, 28.9, can.z), Vector3(can.x - 1.0, 27.5, can.z)], 0.3)
	m.tube(handle, _ramp(handle.size(), 0.16, 0.16), blue.darkened(0.15), 8, true, true)
	_box_col(body, Vector3(4.0, 3.6, 3.0), Transform3D(Basis(), Vector3(can.x, 25.8, can.z)))
	var s0 := Vector3(28.8, 26.4, can.z)
	var s1 := Vector3(26.6, 28.3, can.z)
	var spout := M.catmull([s0, s1], 0.3)
	m.tube(spout, _ramp(spout.size(), 0.62, 0.5), blue, 14, true, false)
	m.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5 - 0.7), s1 + Vector3(-0.15, 0.1, 0)), 0.85, 0.5, 0.5, blue.lightened(0.1), 18, true, Color("cfd8e0"))
	var cap := CapsuleShape3D.new()
	cap.radius = 0.7
	cap.height = s0.distance_to(s1) + 1.4
	_shape(body, cap, Transform3D(_basis_y(s1 - s0), (s0 + s1) * 0.5))
	# Wolf-mask scarecrow on a post, wearing the wide straw hat that is the P3 triple-jump perch (round 1).
	var sc := v3(plat["SCARECROW"]["pos"])
	var sc_path := "res://assets/characters/wolf_scarecrow/wolf_scarecrow_v2.glb"
	if not ResourceLoader.exists(sc_path):
		sc_path = "res://assets/characters/wolf_scarecrow/wolf_scarecrow.glb"
	# Fix r2: faces west, toward the lift and CP3 where Mak arrives, so the paper wolf mask reads (was facing east).
	var real_sc := place_glb(sc_path, holder, Transform3D(Basis(Vector3.UP, -PI * 0.5), sc), "WolfScarecrow")
	if real_sc:
		visuals["SCARECROW"] = real_sc
		_cyl_col(body, 0.3, 3.6, sc + Vector3(0, 1.8, 0))
		var hat2 := v3(plat["SCARECROW_HAT"]["pos"]) if plat.has("SCARECROW_HAT") else sc + Vector3(0, 4.3, 0)
		_cyl_col(body, 1.3, 0.15, hat2 + Vector3(0, -0.075, 0))
	else:
		_proc_scarecrow(m, body, sc)
	_mi(greens.commit(vc_mat(0.35, 0.2, "leaf")), holder, Transform3D.IDENTITY, "AllotmentGreens")
	_pod_mounds(m)
	_allotment_rest(m, holder, body)


func _proc_scarecrow(m, body: StaticBody3D, sc: Vector3) -> void:
	m.cylinder(Transform3D(Basis(), sc + Vector3(0, 1.8, 0)), 0.16, 0.2, 3.6, C_WOOD, 10)
	m.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), sc + Vector3(0, 2.7, 0)), 0.12, 0.12, 3.2, C_WOOD, 8)
	m.sphere(Transform3D(Basis().scaled(Vector3(0.95, 1.15, 0.6)), sc + Vector3(0, 2.45, 0)), Color("4a3a5a"), 14, 8)
	for side: float in [-1.0, 1.0]:
		m.sphere(Transform3D(Basis().scaled(Vector3(0.5, 0.18, 0.18)), sc + Vector3(side * 1.25, 2.7, 0)), Color("4a3a5a"), 10, 6)
		m.sphere(Transform3D(Basis().scaled(Vector3(0.22, 0.3, 0.22)), sc + Vector3(side * 1.7, 2.6, 0)), Color("e3c26b"), 8, 5)
	m.sphere(Transform3D(Basis().scaled(Vector3(0.58, 0.62, 0.58)), sc + Vector3(0, 3.65, 0)), Color("e3c26b"), 14, 8)
	m.sphere(Transform3D(Basis().scaled(Vector3(0.6, 0.48, 0.2)), sc + Vector3(0, 3.7, 0.45)), Color("8e949b"), 12, 6)
	m.sphere(Transform3D(Basis().scaled(Vector3(0.22, 0.18, 0.3)), sc + Vector3(0, 3.55, 0.75)), Color("6e7488"), 10, 6)
	for side: float in [-1.0, 1.0]:
		m.sphere(Transform3D(Basis(Vector3.BACK, side * 0.3).scaled(Vector3(0.12, 0.3, 0.1)), sc + Vector3(side * 0.38, 4.05, 0.3)), Color("6e7488"), 8, 5)
	m.torus(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), sc + Vector3(0.25, 3.75, 0.66)), 0.16, 0.03, C_GOLD, 12, 5)
	var hat := v3(plat["SCARECROW_HAT"]["pos"]) if plat.has("SCARECROW_HAT") else sc + Vector3(0, 4.3, 0)
	m.puck(Transform3D(Basis(), hat + Vector3(0, -0.08, 0)), 1.3, 0.16, 0.07, Color("e3c26b"), 28, Color("f0d27a"))
	m.cylinder(Transform3D(Basis(), hat + Vector3(0, 0.18, 0)), 0.5, 0.58, 0.4, Color("e3c26b"), 18, true)
	m.torus(Transform3D(Basis(), hat + Vector3(0, 0.05, 0)), 0.6, 0.07, C_BANNER, 18, 5)
	_cyl_col(body, 1.3, 0.15, hat + Vector3(0, -0.075, 0))
	for k in 3:
		m.cylinder(Transform3D(Basis(), sc + Vector3(-1.5 + k * 1.5, 2.15 - (k % 2) * 0.3, 0.1)), 0.14, 0.14, 0.32, Color("c9c9d2"), 10)
	_cyl_col(body, 0.3, 3.6, sc + Vector3(0, 1.8, 0))


func _pod_mounds(m) -> void:
	# Pod mounds (rounds 1 and 2): soft soil humps the poppers sit in.
	for pmd in data.get("pod_mounds", []):
		var pp := v3(pmd["pos"])
		m.sphere(Transform3D(Basis().scaled(Vector3(0.85, 0.32, 0.85)), Vector3(pp.x, 24.0, pp.z)), Color("8a6444"), 24, 10, Color("6b4a30"))


func _allotment_rest(m, holder: Node3D, body: StaticBody3D) -> void:
	# Giant sunflower (visual) and two pea trellis wigwams.
	var sf := Vector3(18, 24, 5)
	m.cylinder(Transform3D(Basis(), sf + Vector3(0, 4.5, 0)), 0.3, 0.42, 9.0, Color("4f9a3a"), 12)
	for k in 3:
		var a := float(k) * 2.2
		m.sphere(Transform3D((Basis(Vector3.UP, -a) * Basis(Vector3.BACK, 0.6)).scaled(Vector3(1.4, 0.15, 0.8)), sf + Vector3(cos(a) * 1.2, 3.0 + k * 1.8, sin(a) * 1.2)), Color("5fb043"), 12, 6)
	var hb := Basis(Vector3.RIGHT, -0.5)
	m.puck(Transform3D(hb, sf + Vector3(0, 9.6, 0.5)), 1.4, 0.5, 0.2, Color("7a4a24"), 24)
	for k in 16:
		var a := TAU * float(k) / 16.0
		m.sphere(Transform3D((hb * Basis(Vector3.UP, -a)).scaled(Vector3(1.0, 0.12, 0.45)), sf + Vector3(0, 9.6, 0.5) + hb * Vector3(cos(a) * 1.95, 0.05, sin(a) * 1.95)), Color("ffcf3a").lerp(Color("f2a020"), float(k % 2) * 0.4), 10, 5)
	_cyl_col(body, 0.4, 9.0, sf + Vector3(0, 4.5, 0))
	for wg: Vector3 in [Vector3(16, 24, -2), Vector3(29, 24, -9)]:
		for k in 4:
			var a := TAU * float(k) / 4.0
			var foot: Vector3 = wg + Vector3(cos(a) * 0.9, 0, sin(a) * 0.9)
			var tip: Vector3 = wg + Vector3(0, 3.5, 0)
			m.tube(PackedVector3Array([foot, tip]), PackedFloat32Array([0.06, 0.04]), Color("d8c08a"), 6, false, false)
			for q in 4:
				m.sphere(Transform3D(Basis().scaled(Vector3(0.12, 0.35, 0.1)), foot.lerp(tip, 0.25 + q * 0.18) + Vector3(0.1, -0.2, 0)), C_PEA, 8, 5)
		m.sphere(Transform3D(Basis().scaled(Vector3(0.9, 1.6, 0.9)), wg + Vector3(0, 1.7, 0)), Color("6cbf4a"), 12, 8)
	_mi(m.commit(vc_mat(0.4, 0.3, "soil")), holder, Transform3D.IDENTITY, "AllotmentProps")

# ------------------------------------------------------------------ cottage and garden

const COT_C := Vector3(-12, 0, 18)
const COT_YAW := 20.0


func _cottage() -> void:
	var holder := _node("JacksCottage")
	holder.position = COT_C
	holder.rotation_degrees.y = COT_YAW
	var body := _body("CottageCollision", holder)
	var m = M.new()
	var t = M.new()
	var W := 7.0
	var D := 6.0
	var H := 3.4
	# Plaster walls with a stone plinth.
	m.rbox(Transform3D(Basis(), Vector3(0, H * 0.5, 0)), Vector3(W, H, D), 0.18, C_CREAM, 3)
	m.rbox(Transform3D(Basis(), Vector3(0, 0.3, 0)), Vector3(W + 0.25, 0.6, D + 0.25), 0.15, Color("b8a48c"), 2)
	_box_col(body, Vector3(W, H, D), Transform3D(Basis(), Vector3(0, H * 0.5, 0)))
	# Timber frame.
	for x: float in [-3.4, -1.2, 1.2, 3.4]:
		for z: float in [-3.02, 3.02]:
			t.rbox(Transform3D(Basis(), Vector3(x, H * 0.5, z)), Vector3(0.28, H, 0.12), 0.05, C_TIMBER, 2)
	for z: float in [-1.0, 1.0, -2.95, 2.95]:
		for x: float in [-3.52, 3.52]:
			t.rbox(Transform3D(Basis(), Vector3(x, H * 0.5, z)), Vector3(0.12, H, 0.28), 0.05, C_TIMBER, 2)
	for z: float in [-3.04, 3.04]:
		t.rbox(Transform3D(Basis(), Vector3(0, H - 0.15, z)), Vector3(W + 0.1, 0.25, 0.12), 0.05, C_TIMBER, 2)
		t.rbox(Transform3D(Basis(Vector3.FORWARD, 0.6), Vector3(-2.3, H * 0.5, z)), Vector3(0.18, 2.6, 0.1), 0.04, C_TIMBER, 2)
		t.rbox(Transform3D(Basis(Vector3.FORWARD, -0.6), Vector3(2.3, H * 0.5, z)), Vector3(0.18, 2.6, 0.1), 0.04, C_TIMBER, 2)
	# Round green door on the east gable (+x local faces the path).
	t.puck(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(3.55, 1.25, 0)), 0.95, 0.16, 0.06, Color("3f8f4a"), 24)
	t.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.09), Vector3(3.66, 1.2, 0.5)), C_GOLD, 8, 5)
	# Windows with warm glow panes.
	var glow = M.new()
	for z: float in [-3.08, 3.08]:
		for x: float in [-1.8, 1.9]:
			t.rbox(Transform3D(Basis(), Vector3(x, 1.8, z)), Vector3(1.2, 1.1, 0.14), 0.06, C_TIMBER, 2)
			glow.rbox(Transform3D(Basis(), Vector3(x, 1.8, z * 1.012)), Vector3(0.95, 0.85, 0.06), 0.03, Color("ffcf7a"), 2)
			# Flower box.
			t.rbox(Transform3D(Basis(), Vector3(x, 1.12, z * 1.06)), Vector3(1.3, 0.3, 0.35), 0.06, C_WOOD, 2)
			for f in 4:
				t.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.16), Vector3(x - 0.45 + f * 0.3, 1.35, z * 1.07)), [Color("ff6f91"), Color("ffd24a"), Color("b07cff"), Color("ff8a3d")][f], 8, 5)
	# Thatched roof: two 32 degree slopes over a 8.4 x 7.4 eave, rounded ridge.
	var slope := deg_to_rad(32.0)
	var half_d := 3.7
	var rise := half_d * tan(slope)
	var slab_len := half_d / cos(slope) + 0.3
	var roof = M.new()
	for side: float in [-1.0, 1.0]:
		var bas := Basis(Vector3.RIGHT, side * slope)
		var ctr := Vector3(0, H + rise * 0.5 + 0.25, side * half_d * 0.5)
		roof.rbox(Transform3D(bas, ctr), Vector3(8.4, 0.55, slab_len), 0.26, C_THATCH, 3)
		_box_col(body, Vector3(8.4, 0.5, slab_len), Transform3D(bas, ctr + bas * Vector3(0, 0.02, 0)))
	roof.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, H + rise + 0.32, 0)), 0.42, 0.42, 8.6, C_THATCH.darkened(0.08), 16, true)
	_mi(roof.commit(tex_mat("straw_thatch", 0.5)), holder, Transform3D.IDENTITY, "Thatch")
	# Leaning brick chimney on the west end; a shoulder step makes the climb a fair double jump.
	var ch_local := (Basis(Vector3.UP, -deg_to_rad(COT_YAW)) * (Vector3(-14.4, 0, 18.9) - COT_C))
	var ch_top := 8.2
	var brick = M.new()
	var ch_h := ch_top - 3.0
	brick.rbox(Transform3D(Basis(), Vector3(ch_local.x, 3.0 + ch_h * 0.5, ch_local.z)), Vector3(1.5, ch_h, 1.5), 0.12, Color("c4664a"), 2)
	brick.rbox(Transform3D(Basis(), Vector3(ch_local.x, ch_top - 0.12, ch_local.z)), Vector3(1.75, 0.25, 1.75), 0.08, Color("a85a40"), 2)
	brick.cylinder(Transform3D(Basis(), Vector3(ch_local.x + 0.3, ch_top + 0.25, ch_local.z)), 0.22, 0.25, 0.5, Color("b86a4a"), 10)
	_box_col(body, Vector3(1.5, ch_h, 1.5), Transform3D(Basis(), Vector3(ch_local.x, 3.0 + ch_h * 0.5, ch_local.z)))
	var step_y := H + rise + 1.15
	brick.rbox(Transform3D(Basis(), Vector3(ch_local.x + 1.05, step_y - 0.2, ch_local.z)), Vector3(0.9, 0.4, 1.3), 0.08, Color("a85a40"), 2)
	_box_col(body, Vector3(0.9, 0.4, 1.3), Transform3D(Basis(), Vector3(ch_local.x + 1.05, step_y - 0.2, ch_local.z)))
	_mi(brick.commit(tex_mat("brick", 0.8)), holder, Transform3D.IDENTITY, "Chimney")
	_mi(m.commit(tex_mat("plaster_wall", 0.4)), holder, Transform3D.IDENTITY, "Walls")
	_mi(t.commit(vc_mat(0.3)), holder, Transform3D.IDENTITY, "Timber")
	var gmat := ShaderMaterial.new()
	gmat.shader = load(TOON)
	gmat.set_shader_parameter("use_vertex_color", true)
	gmat.set_shader_parameter("emission_color", Color("ffb45e"))
	gmat.set_shader_parameter("emission_energy", 1.4)
	_mi(glow.commit(gmat), holder, Transform3D.IDENTITY, "WindowGlow")
	visuals["CHIMNEY_TOP"] = holder
	# Woodpile and water butt (route to the roof).
	var wp: Dictionary = plat["COTTAGE_WOODPILE"]
	var wpos := v3(wp["pos"])
	var wb := _body("COTTAGE_WOODPILE", level)
	var wy := Basis(Vector3.UP, deg_to_rad(float(wp["rot_y"])))
	_box_col(wb, Vector3(2.0, wpos.y, 1.6), Transform3D(wy, Vector3(wpos.x, wpos.y * 0.5, wpos.z)))
	var logs = M.new()
	for row in 4:
		var n := 4 - row
		for k in n:
			var lx := (float(k) - float(n - 1) * 0.5) * 0.48
			var ly := 0.27 + float(row) * 0.47
			logs.cylinder(Transform3D(wy * Basis(Vector3.RIGHT, PI * 0.5), Vector3(wpos.x, ly, wpos.z) + wy * Vector3(lx, 0, 0)), 0.25, 0.25, 1.6, C_WOOD.lerp(C_WOOD_DARK, h01(row, k) * 0.6), 12, true, Color("e8c48a"))
	logs.rbox(Transform3D(wy, Vector3(wpos.x, wpos.y - 0.1, wpos.z)), Vector3(2.0, 0.2, 1.6), 0.06, C_WOOD_DARK, 2)
	var bt: Dictionary = plat["COTTAGE_BUTT"]
	var bpos := v3(bt["pos"])
	var bb := _body("COTTAGE_BUTT", level)
	_cyl_col(bb, 0.8, bpos.y, Vector3(bpos.x, bpos.y * 0.5, bpos.z))
	logs.cylinder(Transform3D(Basis(), Vector3(bpos.x, bpos.y * 0.5, bpos.z)), 0.8, 0.72, bpos.y, C_WOOD, 18, true, Color("5fb6d9"))
	for hy: float in [0.25, bpos.y - 0.25]:
		logs.torus(Transform3D(Basis(), Vector3(bpos.x, hy, bpos.z)), 0.8, 0.05, Color("5a5a62"), 18, 5)
	_mi(logs.commit(vc_mat(0.3)), level, Transform3D.IDENTITY, "WoodpileAndButt")


func _garden_props() -> void:
	var holder := _node("Garden")
	var m = M.new()
	var body := _body("GardenCollision", holder)
	# Well with a shingle roof (lid is the W2-5 truffle spot).
	var wp: Dictionary = plat["WELL"]
	var wpos := v3(wp["pos"])
	# Look polish 2026-10-19 (owner: "made from primitives"): the textured wishing-well GLB from W1 replaces the
	# primitive ring, posts, roof and bucket; the wooden lid (W2-5 truffle spot) and the rim collision stay.
	var well_glb := "res://assets/props/w1/wishing_well/wishing_well.glb"
	if ResourceLoader.exists(well_glb) and place_fit(well_glb, holder, Vector3(wpos.x, -0.05, wpos.z), Vector3(3.0, 3.5, 3.0), PI, "GardenWell") != null:
		m.disc(Transform3D(Basis(), Vector3(wpos.x, 0.98, wpos.z)), 1.0, 1.0, C_WOOD, 20)
	else:
		m.cylinder(Transform3D(Basis(), Vector3(wpos.x, 0.5, wpos.z)), 1.3, 1.35, 1.0, Color("b8a48c"), 22, false)
		m.torus(Transform3D(Basis(), Vector3(wpos.x, 1.0, wpos.z)), 1.25, 0.14, Color("cbb89c"), 22, 6)
		m.disc(Transform3D(Basis(), Vector3(wpos.x, 0.98, wpos.z)), 1.15, 1.15, C_WOOD, 20)
	_cyl_col(body, 1.3, 1.0, Vector3(wpos.x, 0.5, wpos.z))
	# Stepping stones along the well path.
	for i in 7:
		var t := float(i) / 6.0
		var q := Vector3(-1, 0, 26).lerp(Vector3(8.5, 0, 23.2), t)
		m.puck(Transform3D(Basis(Vector3.UP, h01(i, 7.0) * 3.0).scaled(Vector3(1, 1, 0.8)), Vector3(q.x, island_h(q.x, q.z) + 0.04, q.z)), 0.45, 0.12, 0.05, Color("c9c0b0"), 12)
	# Picket fence along the rim (inset 1.2 m) with gaps for the gate, the NW peek and the stalk.
	var fence = M.new()
	var fr := 20.8
	var count := int(TAU * fr / 1.2)
	# Fix r1: storybook pickets (rounded tops, a slight wobble) joined by two continuous rails per span, so the
	# fence no longer reads as a row of grave crosses.
	var posts: Array = []
	for i in count:
		var a := TAU * float(i) / float(count)
		var x := cos(a) * fr
		var z := 14.0 + sin(a) * fr
		var keep := true
		if z > 33.0 and absf(x) < 3.5:
			keep = false
		if Vector2(x, z).distance_to(Vector2(-14.6, -0.6)) < 2.6:
			keep = false
		if z < -5.0 + 14.0 - 14.0 and absf(x) < 4.0:
			keep = false
		if Vector2(x, z).distance_to(Vector2(9.5, -2.5)) < 3.0:
			keep = false
		posts.append(Vector3(x, island_h(x, z), z) if keep else Vector3.INF)
	for i in count:
		var pp: Vector3 = posts[i]
		if pp == Vector3.INF:
			continue
		var a := TAU * float(i) / float(count)
		var wob := Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, (h01(float(i), 3.0) - 0.5) * 0.12)
		fence.rbox(Transform3D(wob, pp + Vector3(0, 0.45, 0)), Vector3(0.14, 0.9, 0.16), 0.06, Color("f7f1e3"), 2)
		fence.sphere(Transform3D(wob.scaled(Vector3(0.085, 0.11, 0.09)), pp + wob * Vector3(0, 0.92, 0)), Color("fffaf0"), 12, 6)
		var nx: Vector3 = posts[(i + 1) % count]
		if nx == Vector3.INF:
			continue
		var d := nx - pp
		var mid := (pp + nx) * 0.5
		var rb := Basis.looking_at(Vector3(d.x, 0, d.z).normalized(), Vector3.UP)
		for ry: float in [0.32, 0.68]:
			fence.rbox(Transform3D(rb * Basis(Vector3.RIGHT, atan2(d.y, Vector2(d.x, d.z).length())), mid + Vector3(0, ry, 0)), Vector3(0.06, 0.09, d.length() + 0.1), 0.025, Color("efe6d4"), 1)
	_mi(fence.commit(vc_mat(0.25)), holder, Transform3D.IDENTITY, "PicketFence")
	# Gate posts at the south.
	# Finishing pass (D034 B4, "giant white posts"): the opening camera sits just behind them, so the cream 1.5 m posts
	# filled the frame like pillars. Now low wooden posts with small finials, set wider.
	for sx: float in [-2.2, 2.2]:
		m.rbox(Transform3D(Basis(), Vector3(sx, 0.5, 34.6)), Vector3(0.24, 1.0, 0.24), 0.06, C_WOOD_DARK, 2)
		m.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.12), Vector3(sx, 1.06, 34.6)), C_WOOD, 10, 6)
	# Vegetable beds (x 2..14, z 24..30): soil mounds that follow the knoll, lettuces and bean canes.
	# Look polish 2026-10-19: soil and plants go into their own meshes with the soil and leaf grains.
	var beds = M.new()
	var greens = M.new()
	for row in 3:
		var z := 25.0 + float(row) * 2.2
		for k in 9:
			var x := 3.2 + float(k) * 1.2
			var gy := island_h(x, z)
			beds.puck(Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.8)), Vector3(x, gy + 0.06, z)), 0.62, 0.3, 0.12, Color("6e4a2e"), 12, Color("8a6444"))
			if row == 1 and k % 3 == 0:
				m.cylinder(Transform3D(Basis(), Vector3(x, gy + 1.0, z)), 0.03, 0.04, 2.0, C_WOOD, 6)
				for q in 3:
					greens.sphere(Transform3D(Basis().scaled(Vector3(0.1, 0.28, 0.08)), Vector3(x + 0.12, gy + 0.7 + q * 0.45, z)), C_PEA, 8, 5)
			else:
				greens.sphere(Transform3D(Basis().scaled(Vector3(0.38, 0.3, 0.38)), Vector3(x, gy + 0.42, z)), Color("8fd055").lerp(Color("4c9a32"), h01(row, k)), 10, 6, Color("3f8a30"))
	# Trees: apple on the knoll, two round oaks, a pear tree.
	for tr in data["props_zones"][3]["items"]:
		var tp := Vector3(float(tr[0]), 0.0, float(tr[2]))
		tp.y = island_h(tp.x, tp.z)
		var h := 6.0 if String(tr[3]).contains("6 m") else (7.0 if String(tr[3]).contains("7 m") else 5.0)
		var trunk := Color("8a5a35")
		_cyl_col(body, 0.45, h * 0.5, tp + Vector3(0, h * 0.25, 0))
		# Look polish 2026-10-19: the apple and pear trees are the textured W1 apple-tree GLB (was spheres on a stick).
		var fruit := String(tr[3]).contains("apple") or String(tr[3]).contains("pear")
		if fruit and ResourceLoader.exists(APPLE_TREE_GLB) \
				and place_fit(APPLE_TREE_GLB, holder, tp + Vector3(0, -0.1, 0), Vector3(h * 0.95, h, h * 0.95), h01(tp.x, tp.z) * TAU, "GardenTree") != null:
			continue
		m.cylinder(Transform3D(Basis(), tp + Vector3(0, h * 0.25, 0)), 0.32, 0.5, h * 0.5, trunk, 10)
		var leaf_c := Color("5fb043") if not String(tr[3]).contains("pear") else Color("7cc04a")
		for k in 5:
			var off := Vector3(cos(k * 1.3) * 1.1, h * 0.62 + sin(k * 2.1) * 0.5, sin(k * 1.3) * 1.1) if k > 0 else Vector3(0, h * 0.72, 0)
			var s := h * (0.3 if k == 0 else 0.22)
			greens.sphere(Transform3D(Basis().scaled(Vector3(s, s * 0.9, s)), tp + off), leaf_c.lerp(Color("8ad15a"), h01(k, h)), 14, 8, leaf_c.darkened(0.25))
		if String(tr[3]).contains("apple") or String(tr[3]).contains("pear"):
			for k in 7:
				var a := float(k) * 0.9
				var fp := tp + Vector3(cos(a) * h * 0.3, h * 0.6 + sin(a * 1.7) * 0.6, sin(a) * h * 0.3)
				m.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.16), fp), Color("e04a3a") if String(tr[3]).contains("apple") else Color("d8e05a"), 8, 5)
	_mi(m.commit(vc_mat(0.35)), holder, Transform3D.IDENTITY, "GardenProps")
	_mi(beds.commit(vc_mat(0.3, 0.2, "soil")), holder, Transform3D.IDENTITY, "GardenBeds")
	_mi(greens.commit(vc_mat(0.35, 0.2, "leaf")), holder, Transform3D.IDENTITY, "GardenGreens")
	_flowers(holder)


func _flowers(holder: Node3D) -> void:
	# PZ1 flower meadow: chunky flower clusters (MultiMesh), avoiding paths, pads and the stalk.
	var cols := [Color("ff7fb0"), Color("fff3c4"), Color("b07cff"), Color("ffd24a"), Color("ff6a4a")]
	var stem_m := CylinderMesh.new()
	stem_m.top_radius = 0.03
	stem_m.bottom_radius = 0.04
	stem_m.height = 0.6
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.2
	head.radial_segments = 16  # fix r1: no facets on organic shapes
	head.rings = 8
	var tuft := SphereMesh.new()
	tuft.radius = 0.35
	tuft.height = 0.4
	tuft.radial_segments = 16
	tuft.rings = 8
	var heads := []
	var stems := []
	var tufts := []
	var hcols := []
	var i := 0
	var placed := 0
	# Finishing pass (D034 B4, flower confetti): about 40 % of the old 520 placements, grouped into a few drifts
	# (low-frequency patch mask) so the meadow reads as planted beds instead of an even sprinkle.
	while placed < 210 and i < 6000:
		i += 1
		var a := h01(i, 21.0) * TAU
		var r := sqrt(h01(i, 22.0)) * 20.0
		var x := cos(a) * r
		var z := 14.0 + sin(a) * r
		if sin(x * 0.29 + 1.7) * cos(z * 0.33 - 0.4) < 0.3:
			continue
		if _path_mask(x, z) > 0.05 or Vector2(x, z).distance_to(Vector2(-12, 18)) < 5.5 or Vector2(x, z).length() < 4.5:
			continue
		if x > 1.5 and x < 14.5 and z > 23.5 and z < 30.5:
			continue
		if Vector2(x, z).distance_to(Vector2(9, 22)) < 2.0 or Vector2(x, z).distance_to(Vector2(9.5, -2.5)) < 2.5:
			continue
		var y := island_h(x, z)
		placed += 1
		if placed % 3 == 0:
			tufts.append(Transform3D(Basis().scaled(Vector3(1.0, 0.7 + h01(i, 23.0) * 0.5, 1.0)), Vector3(x, y + 0.05, z)))
			continue
		var hh := 0.35 + h01(i, 24.0) * 0.5
		stems.append(Transform3D(Basis().scaled(Vector3(1, hh / 0.6, 1)), Vector3(x, y + hh * 0.5, z)))
		heads.append(Transform3D(Basis().scaled(Vector3(1, 0.8, 1) * (0.8 + h01(i, 25.0) * 0.6)), Vector3(x, y + hh, z)))
		hcols.append(cols[int(h01(i, 26.0) * cols.size()) % cols.size()])
	var fol: Material = load("res://assets/shaders/materials/foliage_grass.tres") if ResourceLoader.exists("res://assets/shaders/materials/foliage_grass.tres") else null
	_mm(holder, "FlowerStems", stem_m, stems, [], _plain(Color("4f9a3a")))
	_mm(holder, "FlowerHeads", head, heads, hcols, _plain(Color.WHITE, true))
	_mm(holder, "GrassTufts", tuft, tufts, [], fol if fol else _plain(Color("6cbf4a")))


func _plain(c: Color, use_instance_color := false) -> Material:
	var key := "plain_%s_%s" % [c.to_html(), use_instance_color]
	if _mats.has(key):
		return _mats[key]
	var sm := ShaderMaterial.new()
	sm.shader = load(TOON)
	sm.set_shader_parameter("albedo", c)
	sm.set_shader_parameter("use_vertex_color", use_instance_color)
	sm.set_shader_parameter("rim_strength", 0.3)
	_mats[key] = sm
	return sm


func _mm(parent: Node3D, n: String, mesh: Mesh, xfs: Array, colors: Array, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if colors.size() > 0:
			mm.set_instance_color(i, (colors[i] as Color).srgb_to_linear())
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi


# ------------------------------------------------------------------ castle

const WALL_TOP := 58.0
const FLOOR_Y := 50.0


## Fix r2 (visual critic): the bank top in front of the castle was a flat pink plane. A warm cobbled apron from
## CP7 to the gate, a moss and grass fringe along the south wall, flower tubs either side of the gate and some
## giant-scale clutter (a 2 m crumb, an overturned thimble, a dropped spoon). Visual only, except the tubs,
## crumb and thimble, which are solid and kept against the wall, out of the walking lines.
func _castle_apron(holder: Node3D) -> void:
	var cob = M.new()
	cob.rbox(Transform3D(Basis(), Vector3(4.0, FLOOR_Y - 0.01, -21.3)), Vector3(31.0, 0.08, 5.2), 0.03, Color("dccfc0"), 2)
	_mi(cob.commit(tex_mat("cobblestone", 0.35)), holder, Transform3D.IDENTITY, "GateApron")
	var d = M.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2602
	# Moss and grass fringe along the wall foot (south face at z -24).
	for i in 46:
		var x := -11.5 + float(i) * 0.7 + rng.randf_range(-0.2, 0.2)
		if x > 10.6 and x < 17.4:
			continue  # the gate opening
		var c := Vector3(x, FLOOR_Y + 0.02, -23.75 + rng.randf_range(0.0, 0.35))
		var sz := rng.randf_range(0.35, 0.6)
		d.sphere(Transform3D(Basis().scaled(Vector3(sz * 1.4, sz * 0.45, sz)), c), Color("7fae4a").lerp(Color("a8c95a"), rng.randf()), 10, 5, Color("5f8a3a"), 0.0)
		if i % 3 == 0:
			for k in 3:
				var bl := c + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.1, 0.2))
				d.cylinder(Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.3, 0.3)), bl + Vector3(0, 0.3, 0)), 0.0, 0.05, 0.6, Color("8cbf55"), 5)
	# Flower tubs either side of the gate (outside the gate towers).
	var body := _body("ApronProps", holder)
	for tx in [6.9, 21.1]:
		var tc := Vector3(tx, FLOOR_Y, -23.1)
		d.puck(Transform3D(Basis(), tc + Vector3(0, 0.45, 0)), 0.75, 0.9, 0.12, Color("a8673a"), 22, Color("c07a45"))
		d.torus(Transform3D(Basis(), tc + Vector3(0, 0.88, 0)), 0.72, 0.07, Color("8a4f2a"), 22, 6)
		d.sphere(Transform3D(Basis().scaled(Vector3(0.68, 0.3, 0.68)), tc + Vector3(0, 0.95, 0)), Color("6e9e3e"), 14, 6)
		for k in 7:
			var a := TAU * float(k) / 7.0
			var fc := tc + Vector3(cos(a) * 0.42, 1.25, sin(a) * 0.42)
			var fcol: Color = [Color("ff7aa8"), Color("ffd25a"), Color("b58cff")][k % 3]
			d.sphere(Transform3D(Basis().scaled(Vector3(0.2, 0.14, 0.2)), fc), fcol, 10, 6, fcol.darkened(0.25))
			d.sphere(Transform3D(Basis().scaled(Vector3(0.07, 0.07, 0.07)), fc + Vector3(0, 0.1, 0)), Color("fff2a8"), 8, 4)
		var cy := CylinderShape3D.new()
		cy.radius = 0.75
		cy.height = 0.9
		_shape(body, cy, Transform3D(Basis(), tc + Vector3(0, 0.45, 0)))
	# A giant breadcrumb (2 m) against the wall, west of the Giant's boot.
	var crumb := Vector3(-15.0, FLOOR_Y, -22.8)
	d.sphere(Transform3D(Basis(Vector3.UP, 0.6).scaled(Vector3(1.1, 0.7, 0.85)), crumb + Vector3(0, 0.55, 0)), Color("e3b56e"), 14, 8, Color("c48a45"), 0.0)
	d.sphere(Transform3D(Basis(Vector3.UP, 0.6).scaled(Vector3(0.8, 0.45, 0.6)), crumb + Vector3(0.3, 0.95, 0.1)), Color("f2d29a"), 12, 6)
	var cb := BoxShape3D.new()
	cb.size = Vector3(1.8, 1.1, 1.4)
	_shape(body, cb, Transform3D(Basis(Vector3.UP, 0.6), crumb + Vector3(0, 0.55, 0)))
	# An overturned silver thimble (giant scale, 1.1 m) between CP7 and the gate.
	var th := Vector3(1.6, FLOOR_Y, -23.0)
	d.cylinder(Transform3D(Basis(), th + Vector3(0, 0.55, 0)), 0.55, 0.68, 1.1, Color("c9ccd6"), 22, true, Color("e8eaf2"))
	for k in 4:
		d.torus(Transform3D(Basis(), th + Vector3(0, 0.2 + float(k) * 0.25, 0)), 0.64 - float(k) * 0.03, 0.025, Color("9aa0b0"), 22, 4)
	var tcy := CylinderShape3D.new()
	tcy.radius = 0.66
	tcy.height = 1.1
	_shape(body, tcy, Transform3D(Basis(), th + Vector3(0, 0.55, 0)))
	# A dropped teaspoon lying flat on the cobbles (walkable height, visual only).
	var sp := Vector3(-3.4, FLOOR_Y + 0.05, -19.4)
	var sb := Basis(Vector3.UP, 0.9)
	d.rbox(Transform3D(sb, sp + sb * Vector3(0, 0, 1.0)), Vector3(0.3, 0.08, 2.2), 0.04, Color("d7dae2"), 2)
	d.sphere(Transform3D(sb.scaled(Vector3(0.55, 0.12, 0.75)), sp + sb * Vector3(0, 0.02, -0.4)), Color("e4e6ee"), 16, 6, Color("aeb3c2"))
	var dm := vc_mat(0.4) as Material
	_mi(d.commit(dm), holder, Transform3D.IDENTITY, "ApronDressing")


func _castle() -> void:
	var holder := _node("Castle")
	var body := _body("CastleCollision", holder)
	var s = M.new()     # stone
	var dark = M.new()  # darker stone trims
	# Floors: kitchen planks, courtyard cobbles.
	var floor_m = M.new()
	floor_m.rbox(Transform3D(Basis(), Vector3(-5, FLOOR_Y - 0.15, -34)), Vector3(22.2, 0.3, 16.2), 0.08, Color("b8a084"), 2)  # fix r2: muted oak (was red-orange)
	_mi(floor_m.commit(tex_mat("wood_planks", 0.25)), holder, Transform3D.IDENTITY, "KitchenFloor")
	var cob = M.new()
	cob.rbox(Transform3D(Basis(), Vector3(14, FLOOR_Y - 0.15, -34)), Vector3(12.2, 0.3, 16.2), 0.08, Color("d9cfc0"), 2)
	cob.rbox(Transform3D(Basis(), Vector3(14, FLOOR_Y - 0.15, -21)), Vector3(8, 0.3, 10), 0.08, Color("d9cfc0"), 2)
	_mi(cob.commit(tex_mat("cobblestone", 0.35)), holder, Transform3D.IDENTITY, "CourtyardFloor")
	_castle_apron(holder)
	_box_col(body, Vector3(40, 1, 20), Transform3D(Basis(), Vector3(2, FLOOR_Y - 0.5, -34)))
	# Curtain walls (2 m thick, 50..58). South wall has the gate gap at x 11..17 (lintel 57..58).
	_wall(s, body, Vector3(-18, 0, -44), Vector3(22, 0, -42), Vector3(0, 0, -1))   # north
	_wall(s, body, Vector3(-18, 0, -26), Vector3(11, 0, -24), Vector3(0, 0, 1))    # south west part
	_wall(s, body, Vector3(17, 0, -26), Vector3(22, 0, -24), Vector3(0, 0, 1))     # south east part
	_wall(s, body, Vector3(-18, 0, -42), Vector3(-16, 0, -26), Vector3(-1, 0, 0))  # west
	_wall(s, body, Vector3(20, 0, -42), Vector3(22, 0, -26), Vector3(1, 0, 0))     # east
	# Gate lintel and arch trim.
	s.rbox(Transform3D(Basis(), Vector3(14, 57.5, -25)), Vector3(6.2, 1.0, 2.0), 0.15, C_STONE, 3)
	_box_col(body, Vector3(6, 1.0, 2), Transform3D(Basis(), Vector3(14, 57.5, -25)))
	for k in 13:
		var a := PI * float(k) / 12.0
		var p := Vector3(14 + cos(a) * 3.1, 50.0 + 4.0 + sin(a) * 3.0, -23.95)
		dark.rbox(Transform3D(Basis(Vector3.BACK, a), p), Vector3(0.5, 0.9, 0.3), 0.1, C_STONE_DARK, 2)
	# Raised portcullis (visual).
	for k in 7:
		dark.rbox(Transform3D(Basis(), Vector3(11.3 + k * 0.9, 56.0, -25.0)), Vector3(0.14, 2.0, 0.14), 0.04, Color("4a4550"), 1)
	# Partition wall x 6..8 with an arch at z -30.5..-26.5 (6.5 m tall).
	s.rbox(Transform3D(Basis(), Vector3(7, 54, -36.25)), Vector3(2, 8, 11.5), 0.2, C_STONE, 3)
	_box_col(body, Vector3(2, 8, 11.5), Transform3D(Basis(), Vector3(7, 54, -36.25)))
	s.rbox(Transform3D(Basis(), Vector3(7, 57.25, -28.5)), Vector3(2, 1.5, 4.0), 0.2, C_STONE, 3)
	_box_col(body, Vector3(2, 1.5, 4.0), Transform3D(Basis(), Vector3(7, 57.25, -28.5)))
	s.rbox(Transform3D(Basis(), Vector3(7, 54, -26.25)), Vector3(2, 8, 0.5), 0.1, C_STONE, 2)
	# Merlons on the outer edges.
	_merlons(s, body, Vector3(-16, 0, -43.55), Vector3(20, 0, -43.55), true)
	_merlons(s, body, Vector3(-13, 0, -24.45), Vector3(11, 0, -24.45), true)
	_merlons(s, body, Vector3(17, 0, -24.45), Vector3(20, 0, -24.45), true)
	_merlons(s, body, Vector3(-17.55, 0, -40), Vector3(-17.55, 0, -30), false)
	_merlons(s, body, Vector3(21.55, 0, -42), Vector3(21.55, 0, -26), false)
	# Corner turrets NW, NE, SE.
	for tp: Vector3 in [Vector3(-18, 0, -44), Vector3(22, 0, -44), Vector3(22, 0, -24)]:
		_turret(s, dark, body, tp, tp.x > 0.0 and tp.z < -30.0)
	# Wolf banners (red with an iron wolf head) on the south and east walls.
	var cloth = M.new()
	var banners := [Vector3(-6, 0, -23.9), Vector3(2, 0, -23.9), Vector3(19.5, 0, -23.9), Vector3(22.1, 0, -30), Vector3(22.1, 0, -37), Vector3(-12, 0, -23.9)]
	var bn := _node("Banners", holder)
	for i in banners.size():
		var bp: Vector3 = banners[i]
		var east := bp.x > 22.0
		var n := Node3D.new()
		n.name = "Banner%d" % i
		n.position = Vector3(bp.x, 57.2, bp.z)
		n.rotation.y = -PI * 0.5 if east else 0.0
		bn.add_child(n)
		var bm = M.new()
		bm.rbox(Transform3D(Basis(), Vector3(0, -2.0, 0.12)), Vector3(1.6, 4.0, 0.08), 0.04, C_BANNER, 2)
		bm.sphere(Transform3D(Basis().scaled(Vector3(0.45, 0.45, 0.12)), Vector3(0, -1.6, 0.18)), Color("4a4550"), 12, 6)
		bm.sphere(Transform3D(Basis().scaled(Vector3(0.14, 0.2, 0.1)), Vector3(-0.32, -1.2, 0.18)), Color("4a4550"), 8, 4)
		bm.sphere(Transform3D(Basis().scaled(Vector3(0.14, 0.2, 0.1)), Vector3(0.32, -1.2, 0.18)), Color("4a4550"), 8, 4)
		bm.rbox(Transform3D(Basis(), Vector3(0, -4.05, 0.12)), Vector3(1.6, 0.18, 0.1), 0.03, C_GOLD, 1)
		bm.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.05, 0.12)), 0.07, 0.07, 1.9, C_WOOD_DARK, 8)
		_mi(bm.commit(vc_mat(0.3)), n, Transform3D.IDENTITY, "Cloth")
	# Lanterns at the gate.
	for sx: float in [10.4, 17.6]:
		dark.rbox(Transform3D(Basis(), Vector3(sx, 54.5, -23.6)), Vector3(0.5, 0.7, 0.5), 0.08, Color("3b3640"), 2)
	_mi(s.commit(tex_mat("castle_stone", 0.3)), holder, Transform3D.IDENTITY, "Stone")
	_mi(dark.commit(vc_mat(0.3)), holder, Transform3D.IDENTITY, "StoneTrim")
	# Giant's stairs along the east inner wall (8 steps of 1.0 m rise).
	var st = M.new()
	for i in 8:
		var sp: Dictionary = plat["STAIR%d" % (i + 1)]
		var spos := v3(sp["pos"])
		var h := spos.y - FLOOR_Y
		st.rbox(Transform3D(Basis(), Vector3(spos.x, FLOOR_Y + h * 0.5, spos.z)), Vector3(3.0, h, 1.62), 0.1, C_STONE.darkened(0.04 * (i % 2)), 2)
		_box_col(body, Vector3(3.0, h, 1.6), Transform3D(Basis(), Vector3(spos.x, FLOOR_Y + h * 0.5, spos.z)))
	_mi(st.commit(tex_mat("castle_stone", 0.3)), holder, Transform3D.IDENTITY, "GiantStairs")
	# Plinth for the goose cage.
	var pl: Dictionary = plat["PLINTH"]
	var ppos := v3(pl["pos"])
	var pm = M.new()
	pm.puck(Transform3D(Basis(), Vector3(ppos.x, FLOOR_Y + (ppos.y - FLOOR_Y) * 0.5, ppos.z)), 2.2, ppos.y - FLOOR_Y, 0.15, C_GOLD.darkened(0.15), 28, C_GOLD)
	pm.puck(Transform3D(Basis(), Vector3(ppos.x, FLOOR_Y + 0.1, ppos.z + 2.5)), 1.2, 0.2, 0.06, C_STONE_DARK, 20)
	_cyl_col(body, 2.2, ppos.y - FLOOR_Y, Vector3(ppos.x, FLOOR_Y + (ppos.y - FLOOR_Y) * 0.5, ppos.z))
	_mi(pm.commit(vc_mat(0.4, 0.6)), holder, Transform3D.IDENTITY, "Plinth")
	# The Giant's broom leaning on the north wall-walk.
	var br: Dictionary = plat["BROOM"]
	var a0 := v3(br["pos"])
	var a1 := v3(br["top"])
	var bm2 = M.new()
	var dir := (a1 - a0).normalized()
	bm2.tube(M.catmull([a0 - dir * 1.5, a1 + dir * 0.4], 0.4), _ramp(int((a1 - a0).length() / 0.4) + 6, 0.28, 0.24), Color("b07a48"), 10, true, true)
	var head_c := a0 - dir * 2.6 + Vector3(0, 0, 0)
	bm2.cylinder(Transform3D(_basis_y(dir), head_c), 0.55, 1.1, 2.4, C_THATCH, 16)
	bm2.torus(Transform3D(_basis_y(dir), a0 - dir * 1.6), 0.55, 0.1, C_BANNER, 16, 6)
	_mi(bm2.commit(vc_mat(0.3)), holder, Transform3D.IDENTITY, "Broom")


## Fix r1: a graded spire (lighter tip, darker base) with seven shingle rings, instead of a flat red cone.
func _spire(m, centre: Vector3, r_top: float, r_bot: float, h: float) -> void:
	var base := centre.y - h * 0.5
	var nsl := 8
	for i in nsl:
		var u0 := float(i) / float(nsl)
		var u1 := float(i + 1) / float(nsl)
		var y0 := base + u0 * h
		var y1 := base + u1 * h
		m.cylinder(Transform3D(Basis(), Vector3(centre.x, (y0 + y1) * 0.5, centre.z)), lerpf(r_bot, r_top, u1), lerpf(r_bot, r_top, u0), y1 - y0, C_ROOF.darkened(0.2).lerp(C_ROOF.lightened(0.3), (u0 + u1) * 0.5), 24, i == 0)
	for k in 7:
		var u := (float(k) + 0.6) / 8.0
		var r := lerpf(r_bot, r_top, u)
		m.torus(Transform3D(Basis(), Vector3(centre.x, base + u * h, centre.z)), r + 0.03, maxf(0.05, r * 0.06), C_ROOF.darkened(0.3).lerp(C_ROOF.lightened(0.15), u), 24, 5)


func _basis_y(y: Vector3) -> Basis:
	y = y.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


func _wall(s, body: StaticBody3D, a: Vector3, b: Vector3, outer := Vector3.ZERO) -> void:
	var size := Vector3(absf(b.x - a.x), WALL_TOP - FLOOR_Y, absf(b.z - a.z))
	var c := Vector3((a.x + b.x) * 0.5, (WALL_TOP + FLOOR_Y) * 0.5, (a.z + b.z) * 0.5)
	s.rbox(Transform3D(Basis(), c), size + Vector3(0.02, 0, 0.02), 0.22, C_STONE, 3, C_STONE.lightened(0.12))
	_box_col(body, size, Transform3D(Basis(), c))
	if outer == Vector3.ZERO:
		return
	# Buttress strips on the outer face for a chunky rhythm.
	var along_x := size.x > size.z
	var L := size.x if along_x else size.z
	var n := int(L / 5.0)
	for i in range(1, n):
		var t := -L * 0.5 + L * float(i) / float(n)
		var off := Vector3(t, 0, outer.z * size.z * 0.5) if along_x else Vector3(outer.x * size.x * 0.5, 0, t)
		s.rbox(Transform3D(Basis(), Vector3(c.x, FLOOR_Y + 3.2, c.z) + off), Vector3(0.8, 6.4, 0.8), 0.25, C_STONE_DARK.lightened(0.15), 2)


func _merlons(s, body: StaticBody3D, a: Vector3, b: Vector3, along_x: bool) -> void:
	var L := (b - a).length()
	var n := int(L / 2.1)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(maxi(n, 1)))
		var size := Vector3(1.1, 0.9, 0.7) if along_x else Vector3(0.7, 0.9, 1.1)
		s.rbox(Transform3D(Basis(), Vector3(p.x, WALL_TOP + 0.45, p.z)), size, 0.16, C_STONE.lightened(0.05), 2)
		_box_col(body, size, Transform3D(Basis(), Vector3(p.x, WALL_TOP + 0.45, p.z)))


func _turret(s, dark, body: StaticBody3D, c: Vector3, walkable_top: bool) -> void:
	# Solid drum to the wall-walk, an open arcade (4 piers) to 62, then a floor and merlons or a slate cone.
	s.puck(Transform3D(Basis(), Vector3(c.x, (FLOOR_Y + WALL_TOP) * 0.5 - 1.0, c.z)), 3.0, WALL_TOP - FLOOR_Y + 2.0, 0.2, C_STONE, 28)
	_cyl_col(body, 3.0, WALL_TOP - FLOOR_Y, Vector3(c.x, (FLOOR_Y + WALL_TOP) * 0.5, c.z))
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * float(k)
		var p := Vector3(c.x + cos(a) * 2.3, 60.0, c.z + sin(a) * 2.3)
		s.rbox(Transform3D(Basis(Vector3.UP, -a), p), Vector3(1.3, 4.0, 1.3), 0.2, C_STONE, 2)
		_box_col(body, Vector3(1.1, 4.0, 1.1), Transform3D(Basis(Vector3.UP, -a), p))
	s.puck(Transform3D(Basis(), Vector3(c.x, 62.0 - 0.3, c.z)), 3.2, 0.6, 0.15, C_STONE.lightened(0.08), 28)
	_cyl_col(body, 3.2, 0.6, Vector3(c.x, 62.0 - 0.3, c.z))
	if walkable_top:
		for k in 8:
			var a := TAU * float(k) / 8.0
			var p := Vector3(c.x + cos(a) * 2.8, 62.45, c.z + sin(a) * 2.8)
			s.rbox(Transform3D(Basis(Vector3.UP, -a), p), Vector3(0.6, 0.9, 1.1), 0.14, C_STONE, 2)
			if k != 6:  # leave the south-west crenel open toward the broom
				_box_col(body, Vector3(0.6, 0.9, 1.1), Transform3D(Basis(Vector3.UP, -a), p))
	else:
		_spire(dark, Vector3(c.x, 68.5, c.z), 0.08, 3.3, 13.0)
		dark.torus(Transform3D(Basis(), Vector3(c.x, 62.3, c.z)), 3.25, 0.18, C_GOLD, 24, 6)
		dark.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.4), Vector3(c.x, 75.2, c.z)), C_GOLD, 12, 8)
		dark.cylinder(Transform3D(Basis(), Vector3(c.x, 76.6, c.z)), 0.05, 0.05, 2.4, Color("6b5a4a"), 6)
		dark.rbox(Transform3D(Basis(), Vector3(c.x + 0.7, 77.3, c.z)), Vector3(1.3, 0.7, 0.05), 0.02, C_BANNER, 1, C_GOLD)


# ------------------------------------------------------------------ kitchen

func _kitchen() -> void:
	var holder := _node("Kitchen")
	var body := _body("KitchenCollision", holder)
	var w = M.new()
	# Table x -12..1, z -38..-30, top 55.6 (0.6 thick), four legs.
	var tc := Vector3(-5.5, 55.3, -34)
	w.rbox(Transform3D(Basis(), tc), Vector3(13.0, 0.6, 8.0), 0.18, Color("d6c0a4"), 3, Color("e4d0b4"))
	_box_col(body, Vector3(13, 0.6, 8), Transform3D(Basis(), tc))
	for lx: float in [-11.3, 0.3]:
		for lz: float in [-37.3, -30.7]:
			w.rbox(Transform3D(Basis(), Vector3(lx, 52.5, lz)), Vector3(0.9, 5.0, 0.9), 0.2, C_WOOD_DARK, 2)
			_box_col(body, Vector3(0.9, 5.0, 0.9), Transform3D(Basis(), Vector3(lx, 52.5, lz)))
	# Chair: seat x 2..6, z -36..-32, top 54.4; back x 5.4..6 to 61. Generated mesh when present.
	_box_col(body, Vector3(4, 0.6, 4), Transform3D(Basis(), Vector3(3.4, 54.1, -34)))
	_box_col(body, Vector3(0.6, 6.6, 4), Transform3D(Basis(), Vector3(5.1, 57.7, -34)))
	var chair := place_fit("giant_chair_v2/giant_chair_v2.glb", holder, Vector3(3.4, 50.0, -34.0), Vector3(4.2, 11.0, 4.2), -PI * 0.5, "GiantChair")
	if chair == null:
		chair = place_fit("giant_chair/giant_chair.glb", holder, Vector3(3.4, 50.0, -34.0), Vector3(4.2, 11.0, 4.2), -PI * 0.5, "GiantChair")
	if chair == null:
		w.rbox(Transform3D(Basis(), Vector3(3.4, 54.1, -34)), Vector3(4, 0.6, 4), 0.15, Color("cfb497"), 3)
		w.rbox(Transform3D(Basis(), Vector3(3.3, 54.55, -34)), Vector3(3.6, 0.35, 3.6), 0.17, C_BANNER.lightened(0.15), 3)
		w.rbox(Transform3D(Basis(), Vector3(5.1, 57.7, -34)), Vector3(0.6, 6.6, 4), 0.2, Color("cfb497"), 3)
		for lz: float in [-35.6, -32.4]:
			w.rbox(Transform3D(Basis(), Vector3(1.8, 51.9, lz)), Vector3(0.5, 3.8, 0.5), 0.12, C_WOOD_DARK, 2)
			w.rbox(Transform3D(Basis(), Vector3(5.0, 51.9, lz)), Vector3(0.5, 3.8, 0.5), 0.12, C_WOOD_DARK, 2)
	# Pantry steps: sugar sack, crate, cookbooks.
	var sack := Vector3(-0.4, 51.2, -28.4)
	var crate := Vector3(1.8, 52.4, -28.4)
	var books := Vector3(4.0, 53.4, -29.4)
	var soft = M.new()
	soft.sphere(Transform3D(Basis().scaled(Vector3(1.05, 0.62, 1.05)), sack + Vector3(0, -0.6, 0)), Color("e6d3a8"), 16, 9, Color("c9b07c"))
	soft.sphere(Transform3D(Basis().scaled(Vector3(0.35, 0.3, 0.35)), sack + Vector3(0, 0.05, 0)), Color("d8c08a"), 10, 6)
	_box_col(body, Vector3(2, sack.y - FLOOR_Y, 2), Transform3D(Basis(), Vector3(sack.x, (sack.y + FLOOR_Y) * 0.5, sack.z)))
	w.rbox(Transform3D(Basis(), Vector3(crate.x, (crate.y + FLOOR_Y) * 0.5, crate.z)), Vector3(2, crate.y - FLOOR_Y, 2), 0.1, C_WOOD, 2)
	_box_col(body, Vector3(2, crate.y - FLOOR_Y, 2), Transform3D(Basis(), Vector3(crate.x, (crate.y + FLOOR_Y) * 0.5, crate.z)))
	var bcols := [Color("7a1f2e"), Color("2e5c8a"), Color("3f7a3a"), Color("8a5a2e")]
	var nb := 4
	for i in nb:
		var bh := (books.y - FLOOR_Y) / float(nb)
		soft.rbox(Transform3D(Basis(Vector3.UP, 0.05 * (i % 2)), Vector3(books.x, FLOOR_Y + bh * (float(i) + 0.5), books.z)), Vector3(2.0 - 0.06 * i, bh - 0.03, 3.2 - 0.08 * i), 0.1, bcols[i], 2, Color("f3e6c4"))
	_box_col(body, Vector3(2, books.y - FLOOR_Y, 3.2), Transform3D(Basis(), Vector3(books.x, (books.y + FLOOR_Y) * 0.5, books.z)))
	# Dresser along the north wall: back panel and five shelves (A..TOP).
	w.rbox(Transform3D(Basis(), Vector3(-2, 55.5, -41.85)), Vector3(8.6, 11.0, 0.3), 0.1, Color("b49a80"), 2)
	for sid: String in ["SHELF_A", "SHELF_B", "SHELF_C", "SHELF_D", "SHELF_TOP"]:
		var sp: Dictionary = plat[sid]
		var spos := v3(sp["pos"])
		var th := float(sp["thickness"])
		w.rbox(Transform3D(Basis(), spos + Vector3(0, -th * 0.5, 0)), Vector3(float(sp["sx"]), th, float(sp["sz"])), 0.06, Color("e0c9ab"), 2)
		_box_col(body, Vector3(float(sp["sx"]), th, float(sp["sz"])), Transform3D(Basis(), spos + Vector3(0, -th * 0.5, 0)))
		# Bracket under each shelf.
		w.rbox(Transform3D(Basis(), spos + Vector3(0, -0.6, -0.3)), Vector3(0.3, 1.0, 1.0), 0.06, C_WOOD_DARK, 2)
	# Crockery on the shelves (dressing, no collision): jam jars and plates.
	var crock = M.new()
	var jar_spots := [Vector3(-5.4, 52.0, -41.5), Vector3(1.4, 54.0, -41.6), Vector3(-5.5, 56.0, -41.5), Vector3(-1.5, 58.0, -41.6), Vector3(-2.6, 60.0, -41.6)]
	for i in jar_spots.size():
		var jp: Vector3 = jar_spots[i]
		crock.cylinder(Transform3D(Basis(), jp + Vector3(0, 0.45, 0)), 0.32, 0.34, 0.9, [Color("d8304a"), Color("ff9a3d"), Color("7a3aa8")][i % 3], 14, true)
		crock.puck(Transform3D(Basis(), jp + Vector3(0, 0.95, 0)), 0.36, 0.12, 0.04, Color("f3e6c4"), 14)
	for i in 3:
		crock.puck(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.15), Vector3(-0.5 + i * 0.7, 54.6, -41.6)), 0.55, 0.06, 0.02, Color("f7f5ff"), 18)
	_mi(crock.commit(vc_mat(0.4, 0.7)), holder, Transform3D.IDENTITY, "Crockery")
	# Hearth in the north-west corner with a glow.
	var hearth = M.new()
	hearth.rbox(Transform3D(Basis(), Vector3(-13.5, 52.2, -41.2)), Vector3(4.4, 4.4, 1.6), 0.3, Color("a85a40"), 3)
	hearth.rbox(Transform3D(Basis(), Vector3(-13.5, 51.4, -40.4)), Vector3(2.6, 2.6, 0.3), 0.2, Color("2a1a14"), 2)
	_box_col(body, Vector3(4.4, 4.4, 1.6), Transform3D(Basis(), Vector3(-13.5, 52.2, -41.2)))
	var fire = M.new()
	for k in 5:
		fire.sphere(Transform3D(Basis().scaled(Vector3(0.35, 0.6 + 0.2 * (k % 2), 0.35)), Vector3(-14.3 + k * 0.4, 50.6, -40.1)), Color("ff8a3d").lerp(Color("ffd24a"), float(k % 2)), 10, 6)
	var fmat := ShaderMaterial.new()
	fmat.shader = load(TOON)
	fmat.set_shader_parameter("use_vertex_color", true)
	fmat.set_shader_parameter("emission_color", Color("ff8a3d"))
	fmat.set_shader_parameter("emission_energy", 2.5)
	_mi(fire.commit(fmat), holder, Transform3D.IDENTITY, "HearthFire")
	_mi(hearth.commit(tex_mat("brick", 0.22)), holder, Transform3D.IDENTITY, "Hearth")
	# Giant spoon leaning by the hearth.
	var sp2 = M.new()
	sp2.tube(M.catmull([Vector3(-10.6, 50.1, -41.2), Vector3(-10.1, 55.0, -41.4)], 0.5), _ramp(12, 0.14, 0.14), Color("c9c9d2"), 8, true, true)
	sp2.sphere(Transform3D(Basis().scaled(Vector3(0.6, 0.85, 0.25)), Vector3(-10.0, 55.6, -41.4)), Color("d9d9e2"), 12, 8)
	_mi(sp2.commit(vc_mat(0.4, 0.9)), holder, Transform3D.IDENTITY, "Spoon")
	_mi(w.commit(tex_mat("wood_planks", 0.15)), holder, Transform3D.IDENTITY, "Furniture")
	_mi(soft.commit(vc_mat(0.3)), holder, Transform3D.IDENTITY, "PantrySoft")
	# Table objects: pocket watch, teacup, loaf, butter, sugar bowl.
	var top := 55.6
	var wp := v3(plat["WATCH"]["pos"])
	var watch := place_glb("pocket_watch/pocket_watch.glb", holder, Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * 0.9), Vector3(wp.x, top, wp.z)), "PocketWatch")
	visuals["WATCH"] = watch
	_cyl_col(body, 1.6, wp.y - top, Vector3(wp.x, (wp.y + top) * 0.5, wp.z))
	var tcp := v3(plat["TEACUP"]["pos"])
	place_glb("giant_teacup/giant_teacup.glb", holder, Transform3D(Basis(Vector3.UP, 2.4), Vector3(tcp.x, top, tcp.z)), "Teacup")
	_cyl_col(body, 1.3, tcp.y - top - 0.2, Vector3(tcp.x, (tcp.y - 0.2 + top) * 0.5, tcp.z))
	var tea := Area3D.new()
	tea.name = "HotTea"
	tea.add_to_group("hazard")
	tea.set_meta("damage", 1)
	tea.set_meta("knockback_up", 6.0)
	tea.collision_layer = 16
	tea.collision_mask = 0
	tea.monitorable = true
	tea.position = Vector3(tcp.x, tcp.y - 0.05, tcp.z)
	var tcs := CollisionShape3D.new()
	var tcy := CylinderShape3D.new()
	tcy.radius = 1.25
	tcy.height = 0.9
	tcs.shape = tcy
	tcs.position = Vector3(0, 0.3, 0)
	tea.add_child(tcs)
	holder.add_child(tea)
	_cyl_col(body, 1.95, 0.35, Vector3(tcp.x, top + 0.17, tcp.z))
	visuals["TEACUP"] = holder
	var lp := v3(plat["LOAF"]["pos"])
	place_glb("giant_loaf/giant_loaf.glb", holder, Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(0.88, 0.6, 0.6)), Vector3(lp.x, top, lp.z)), "Loaf")
	var loaf_pts := PackedVector3Array()
	for zz: float in [-2.2, 2.2]:
		loaf_pts.append(Vector3(lp.x - 0.95, top, lp.z + zz))
		loaf_pts.append(Vector3(lp.x + 0.95, top, lp.z + zz))
		loaf_pts.append(Vector3(lp.x, lp.y, lp.z + zz))
	var lcp := ConvexPolygonShape3D.new()
	lcp.points = loaf_pts
	_shape(body, lcp)
	var tm = M.new()
	var bp := v3(plat["BUTTER"]["pos"])
	tm.rbox(Transform3D(Basis(), Vector3(bp.x, top + 0.1, bp.z)), Vector3(2.0, 0.2, 1.6), 0.08, Color("f7f5ff"), 2)
	tm.rbox(Transform3D(Basis(), Vector3(bp.x, (bp.y + top) * 0.5 + 0.05, bp.z)), Vector3(1.6, bp.y - top - 0.1, 1.2), 0.12, Color("ffe27a"), 3)
	_shape(body, _dome(Vector3(bp.x, top, bp.z), 1.0, 57.4 - top))
	var glass = M.new()
	glass.sphere(Transform3D(Basis().scaled(Vector3(1.05, 57.4 - top, 1.05)), Vector3(bp.x, top, bp.z)), Color("dfe9f5"), 20, 10, Color(0, 0, 0, 0), 0.0)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.85, 0.92, 1.0, 0.28)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.roughness = 0.05
	gmat.metallic_specular = 1.0
	gmat.rim_enabled = true
	_mi(glass.commit(gmat), holder, Transform3D.IDENTITY, "Cloche")
	var sgp := v3(plat["SUGAR"]["pos"])
	var bowl := place_fit("sugar_bowl/sugar_bowl.glb", holder, Vector3(sgp.x, top, sgp.z), Vector3(2.3, 1.45, 2.3), 0.0, "SugarBowl")
	if bowl == null:
		_sugar_bowl_proc(tm, sgp, top)
	_shape(body, _dome(Vector3(sgp.x, top, sgp.z), 1.15, 58.0 - top))
	var lid = M.new()
	lid.sphere(Transform3D(Basis().scaled(Vector3(1.12, 1.0, 1.12)), Vector3(sgp.x, sgp.y - 0.15, sgp.z)), Color("f7f5ff"), 20, 10, Color("d8d0e8"), 0.0)
	lid.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.22), Vector3(sgp.x, sgp.y + 0.92, sgp.z)), Color("e8b23a"), 10, 6)
	_mi(lid.commit(vc_mat(0.4, 0.7)), holder, Transform3D.IDENTITY, "SugarLid")
	# Crumbs scattered on the table.
	_crumbs(tm, top)
	_mi(tm.commit(vc_mat(0.4, 0.7)), holder, Transform3D.IDENTITY, "TableThings")


func _sugar_bowl_proc(tm, sgp: Vector3, top: float) -> void:
	tm.cylinder(Transform3D(Basis(), Vector3(sgp.x, (sgp.y + top) * 0.5, sgp.z)), 1.1, 0.75, sgp.y - top, Color("f7f5ff"), 22, false)
	tm.torus(Transform3D(Basis(), Vector3(sgp.x, sgp.y, sgp.z)), 1.08, 0.08, Color("e8b23a"), 22, 6)
	tm.disc(Transform3D(Basis(), Vector3(sgp.x, sgp.y - 0.1, sgp.z)), 1.0, 1.0, Color("fffaf0"), 20)
	for k in 6:
		var a := float(k) * 1.1
		tm.rbox(Transform3D(Basis(Vector3.UP, a), Vector3(sgp.x + cos(a) * 0.55, sgp.y - 0.02, sgp.z + sin(a) * 0.55)), Vector3(0.28, 0.24, 0.28), 0.05, Color.WHITE, 2)
	# Rose sprigs on the bowl.
	for k in 4:
		var a := float(k) * PI * 0.5 + 0.4
		tm.sphere(Transform3D(Basis().scaled(Vector3(0.14, 0.14, 0.05)), Vector3(sgp.x + cos(a) * 1.0, sgp.y - 0.5, sgp.z + sin(a) * 1.0)), Color("b07cff"), 8, 5)


func _crumbs(tm, top: float) -> void:
	for k in 14:
		var q := Vector3(-10.5 + h01(k, 31.0) * 11.0, top + 0.05, -37.5 + h01(k, 32.0) * 7.0)
		tm.sphere(Transform3D(Basis().scaled(Vector3(0.12, 0.08, 0.12) * (1.0 + h01(k, 33.0))), q), Color("e3b070"), 6, 4)


# ------------------------------------------------------------------ belfry

func _belfry() -> void:
	var holder := _node("Belfry")
	var body := _body("BelfryCollision", holder)
	var c := Vector3(-18, 0, -24)
	var s = M.new()
	var d = M.new()
	# Rock foundation hanging below the bank (40..50) and the tower drum (50..68).
	var rock = M.new()
	rock.cylinder(Transform3D(Basis(), Vector3(c.x, 45.0, c.z)), 5.2, 2.5, 10.0, C_ROCK, 20, true)
	rock.sphere(Transform3D(Basis().scaled(Vector3(2.6, 2.0, 2.6)), Vector3(c.x, 40.5, c.z)), C_ROCK.darkened(0.15), 14, 8)
	_mi(rock.commit(tex_mat("cliff_rock", 0.2)), holder, Transform3D.IDENTITY, "Foundation")
	# Fix r1: the hanging foundation read as a floating flowerpot. Wrap its top in underside cloud puffs and hang
	# vines and roots from it so it reads as a rocky stalactite under the cloud bank.
	var wrap_m = M.new()
	for k in 14:
		var a := TAU * float(k) / 14.0 + h01(float(k), 7.0) * 0.3
		var rr := 5.0 + h01(float(k), 2.0) * 1.2
		var sc := 1.6 + h01(float(k), 5.0) * 1.0
		wrap_m.sphere(Transform3D(Basis().scaled(Vector3(sc * 1.3, sc * 0.7, sc * 1.3)), Vector3(c.x + cos(a) * rr, 48.6 - h01(float(k), 9.0) * 1.2, c.z + sin(a) * rr)), Color("b8a6de"), 14, 8, Color("9c8ad0"))
	for k in 9:
		var a := TAU * float(k) / 9.0 + 0.2
		var r0 := 4.2 - float(k % 3) * 0.6
		var top := Vector3(c.x + cos(a) * r0, 47.5, c.z + sin(a) * r0)
		var ln := 3.0 + h01(float(k), 4.0) * 4.0
		var pts := M.catmull([top, top + Vector3(0.3, -ln * 0.5, 0.2), top + Vector3(-0.2, -ln, 0.1)], 0.4)
		var rads := PackedFloat32Array()
		for j in pts.size():
			rads.append(lerpf(0.16, 0.05, float(j) / float(pts.size() - 1)))
		wrap_m.tube(pts, rads, C_STALK if k % 2 == 0 else Color("7a5a3a"), 7, false, true)
		if k % 2 == 0:
			wrap_m.sphere(Transform3D(Basis().scaled(Vector3(0.35, 0.12, 0.25)), pts[pts.size() - 1]), C_LEAF, 10, 5)
	_mi(wrap_m.commit(vc_mat(0.4)), holder, Transform3D.IDENTITY, "FoundationWrap")
	s.puck(Transform3D(Basis(), Vector3(c.x, 59.0, c.z)), 5.0, 18.0, 0.25, C_STONE, 36)
	_cyl_col(body, 5.0, 18.0, Vector3(c.x, 59.0, c.z))
	# Balconies B1 (58) and B2 (66, with a notch above the slot).
	for by: float in [58.0, 66.0]:
		var notch := false
		var segs := 36
		for k in segs:
			var a0 := TAU * float(k) / float(segs)
			var mid := a0 + TAU / float(segs) * 0.5
			var dirv := Vector3(cos(mid), 0, sin(mid))
			var p := Vector3(c.x, by - 0.3, c.z) + dirv * 5.75
			# South is +z: the slot sits at angle ~ +90 degrees (z > 0).
			if notch and absf(wrapf(mid - PI * 0.5, -PI, PI)) < 0.28:
				continue
			s.rbox(Transform3D(Basis(Vector3.UP, -mid), p), Vector3(1.5, 0.6, 1.08), 0.12, C_STONE.lightened(0.06), 2)
			_box_col(body, Vector3(1.5, 0.6, 1.06), Transform3D(Basis(Vector3.UP, -mid), p))
		# Corbels.
		for k in 12:
			var a := TAU * float(k) / 12.0
			if notch and absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.3:
				continue
			d.rbox(Transform3D(Basis(Vector3.UP, -a), Vector3(c.x, by - 0.9, c.z) + Vector3(cos(a), 0, sin(a)) * 5.4), Vector3(0.8, 0.7, 0.5), 0.1, C_STONE_DARK, 2)
	# Bell gallery spur on B2 (round 1; replaces the wall-kick slot): vertical faces, ledge-grabbable.
	var gal: Dictionary = plat.get("BELL_GALLERY", {})
	if not gal.is_empty():
		var gp := v3(gal["pos"])
		var gs := Vector3(float(gal["sx"]), float(gal["thickness"]), float(gal["sz"]))
		s.rbox(Transform3D(Basis(), gp + Vector3(0, -gs.y * 0.5, 0)), gs, 0.08, C_STONE.lightened(0.06), 2)
		_box_col(body, gs, Transform3D(Basis(), gp + Vector3(0, -gs.y * 0.5, 0)))
		d.rbox(Transform3D(Basis(), gp + Vector3(0, -gs.y - 0.35, 0)), Vector3(gs.x * 0.7, 0.7, gs.z * 0.7), 0.1, C_STONE_DARK, 2)
	# Bell openings (visual) on the east and north faces, and the bell itself.
	for a: float in [0.0, -PI * 0.5]:
		var dirv := Vector3(cos(a), 0, sin(a))
		d.rbox(Transform3D(Basis(Vector3.UP, -a), Vector3(c.x, 64.0, c.z) + dirv * 4.95), Vector3(0.3, 3.6, 2.4), 0.15, Color("3b2e3a"), 2)
	# Top platform (68) with 12 merlons; one crenel is centred over the slot (south).
	s.puck(Transform3D(Basis(), Vector3(c.x, 67.8, c.z)), 5.3, 0.4, 0.12, C_STONE.lightened(0.1), 36)
	for k in 12:
		var a := TAU * (float(k) + 0.5) / 12.0
		var p := Vector3(c.x, 68.45, c.z) + Vector3(cos(a), 0, sin(a)) * 4.75
		s.rbox(Transform3D(Basis(Vector3.UP, -a), p), Vector3(0.7, 0.9, 1.3), 0.14, C_STONE, 2)
		_box_col(body, Vector3(0.7, 0.9, 1.3), Transform3D(Basis(Vector3.UP, -a), p))
	_mi(s.commit(tex_mat("castle_stone", 0.3)), holder, Transform3D.IDENTITY, "BelfryStone")
	_mi(d.commit(vc_mat(0.3)), holder, Transform3D.IDENTITY, "BelfryTrim")
	# Bean flower: petals at 68.6 around a heart disc at 69.4.
	var fl := _node("BeanFlower", holder)
	fl.position = Vector3(c.x, 68.0, c.z)
	visuals["FLOWER"] = fl
	var fb := _body("FlowerCollision", fl)
	_cyl_col(fb, 1.4, 0.6, Vector3(0, 1.1, 0))
	for k in 6:
		var a := TAU * float(k) / 6.0
		var piv := Node3D.new()
		piv.name = "Petal%d" % k
		piv.position = Vector3(cos(a) * 1.2, 0.5, sin(a) * 1.2)
		piv.rotation.y = -a
		fl.add_child(piv)
		var pm = M.new()
		pm.sphere(Transform3D(Basis().scaled(Vector3(1.4, 0.18, 0.85)), Vector3(1.2, 0.0, 0)), Color("fff3f6"), 16, 8, Color("ff9ab8"))
		_mi(pm.commit(vc_mat(0.5)), piv, Transform3D.IDENTITY, "Petal")
		var pc := StaticBody3D.new()
		pc.collision_layer = 1
		piv.add_child(pc)
		_box_col(pc, Vector3(2.6, 0.2, 1.6), Transform3D(Basis(), Vector3(1.3, 0.0, 0)))
	var hm = M.new()
	hm.puck(Transform3D(Basis(), Vector3(0, 1.1, 0)), 1.4, 0.6, 0.2, Color("ffd24a"), 24, Color("ffe79a"))
	for k in 10:
		var a := TAU * float(k) / 10.0
		hm.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.16), Vector3(cos(a) * 0.9, 1.45, sin(a) * 0.9)), Color("f2b632"), 8, 5)
	_mi(hm.commit(vc_mat(0.5)), fl, Transform3D.IDENTITY, "Heart")
	var bf := place_glb("bean_flower/bean_flower.glb", fl, Transform3D(Basis().scaled(Vector3.ONE * 1.4), Vector3(2.6, 0.0, 2.6)), "SideBloom")
	if bf:
		bf.rotation.y = 0.8


# ------------------------------------------------------------------ round 1 structures

func _r1_structures() -> void:
	var holder := _node("Round1")
	var body := _body("Round1Collision", holder)
	# K1 Knot Shelf: a woody shelf glued to the trunk (backflip shortcut to Vine 1).
	if plat.has("K1"):
		var k: Dictionary = plat["K1"]
		var km = M.new()
		_sector(km, v3(k["pos"]), float(k["r_in"]) - 0.4, float(k["r"]), float(k["az_from"]), float(k["az_to"]), float(k["thickness"]), Color("6b8a3a"), C_STALK_DARK)
		_mi(km.commit(vc_mat(0.35)), holder, Transform3D.IDENTITY, "KnotShelf")
		var cps := ConcavePolygonShape3D.new()
		cps.set_faces(km.faces())
		_shape(body, cps)
	# CC1 Cloud Collar: a catch cloud around the stalk under the Upper Runner.
	if plat.has("CC1"):
		var c: Dictionary = plat["CC1"]
		var cm = M.new()
		var ctr := v3(c["pos"])
		_sector(cm, ctr, float(c["r_in"]), float(c["r"]), float(c["az_from"]), float(c["az_to"]), float(c["thickness"]), Color("fff8f0"), Color("cbb8ea"))
		_mi(cm.commit(cloud_mat()), holder, Transform3D.IDENTITY, "CloudCollar")
		var cps2 := ConcavePolygonShape3D.new()
		cps2.set_faces(cm.faces())
		_shape(body, cps2)
		var a0 := deg_to_rad(float(c["az_from"]))
		var a1 := deg_to_rad(float(c["az_to"]))
		for i in 16:
			var a := lerpf(a0, a1, (float(i) + 0.5) / 16.0)
			var rr := float(c["r"]) - 0.4
			var sz := 0.9 + h01(i, 61.0) * 0.8
			_cloud("deck_CC1", Transform3D(Basis().scaled(Vector3(sz, sz * 0.8, sz)), ctr + Vector3(cos(a) * rr, -0.5, sin(a) * rr)))
			_cloud("deck_CC1", Transform3D(Basis().scaled(Vector3(sz * 1.4, sz, sz * 1.4)), ctr + Vector3(cos(a) * (rr - 2.0), -1.4, sin(a) * (rr - 2.0))))
	# Gatehouse roof over the gate (S1 sits on it; backflip from the wall-walk).
	if plat.has("GATEHOUSE"):
		var gh := Vector3(14, 59.7, -25.4)
		var s = M.new()
		s.rbox(Transform3D(Basis(), gh), Vector3(6.0, 3.4, 3.6), 0.2, C_STONE, 3, C_STONE.lightened(0.12))
		_box_col(body, Vector3(6.0, 3.4, 3.6), Transform3D(Basis(), gh))
		for i in 4:
			var mp := Vector3(11.6 + i * 1.6, 61.85, -23.85)
			s.rbox(Transform3D(Basis(), mp), Vector3(0.9, 0.9, 0.6), 0.14, C_STONE.lightened(0.05), 2)
			_box_col(body, Vector3(0.9, 0.9, 0.6), Transform3D(Basis(), mp))
		# Arrow-slit windows and a little slate eave.
		for i in 2:
			s.rbox(Transform3D(Basis(), Vector3(12.5 + i * 3.0, 59.6, -23.58)), Vector3(0.35, 1.2, 0.1), 0.05, Color("3b2e3a"), 1)
		_mi(s.commit(tex_mat("castle_stone", 0.3)), holder, Transform3D.IDENTITY, "Gatehouse")
		var arrows = M.new()
		for i in 3:
			arrows.rbox(Transform3D(Basis(Vector3.UP, 0.0), Vector3(14, 58.02, -27.5 - i * 0.55)), Vector3(0.18, 0.02, 0.45), 0.01, Color("f7f5ff"), 1)
		_mi(arrows.commit(vc_mat(0.1)), holder, Transform3D.IDENTITY, "ChalkArrows")
	# The Giant's head dome (slopes over 50 degrees: Mak slides off) and the pom-pom perch.
	if plat.has("GIANT_HEAD"):
		# One steep hull over the head and folded forearms (every face over 55 degrees: Mak slides off).
		var pts := PackedVector3Array([Vector3(-13.6, 55.6, -36.7), Vector3(-10.4, 55.6, -36.7), Vector3(-13.6, 55.6, -31.3), Vector3(-10.4, 55.6, -31.3), Vector3(-12.3, 60.2, -34.0)])
		var cp := ConvexPolygonShape3D.new()
		cp.points = pts
		_shape(body, cp)
	if plat.has("POMPOM"):
		var pp := v3(plat["POMPOM"]["pos"])
		_cyl_col(body, 1.1, 0.8, pp + Vector3(0, -0.4, 0))
	# Round oak crown (OAK_TOP) for the magic-bean secret.
	if plat.has("OAK_TOP"):
		var op := v3(plat["OAK_TOP"]["pos"])
		var om = M.new()
		om.sphere(Transform3D(Basis().scaled(Vector3(2.3, 0.75, 2.3)), op + Vector3(0, -0.6, 0)), Color("6cbf4a"), 18, 10, Color("4f9a3a"))
		_mi(om.commit(vc_mat(0.35, 0.3, "leaf")), holder, Transform3D.IDENTITY, "OakCrown")
		_cyl_col(body, 2.0, 1.0, op + Vector3(0, -0.5, 0))


## Convex dome (steep sides) standing on `base`.
func _dome(base: Vector3, r: float, h: float) -> ConvexPolygonShape3D:
	var pts := PackedVector3Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(base + Vector3(cos(a) * r, 0, sin(a) * r))
		pts.append(base + Vector3(cos(a) * r * 0.55, h * 0.75, sin(a) * r * 0.55))
	pts.append(base + Vector3(0, h, 0))
	var cp := ConvexPolygonShape3D.new()
	cp.points = pts
	return cp


func _r2_structures() -> void:
	var holder := _node("Round2")
	var body := _body("Round2Collision", holder)
	var s = M.new()
	# Kitchen screen walls over the west and north wall-walks (block jump chains to the pom-pom).
	for id: String in ["WALL_SCREEN_W", "WALL_SCREEN_N"]:
		if not plat.has(id):
			continue
		var p: Dictionary = plat[id]
		var top := v3(p["pos"])
		var size := Vector3(float(p["sx"]), float(p["thickness"]), float(p["sz"]))
		var c := top + Vector3(0, -size.y * 0.5, 0)
		s.rbox(Transform3D(Basis(), c), size + Vector3(0.1, 0, 0.1), 0.14, Color("ece2d4"), 3, Color("e0d2bf"))  # fix r1/r2: cream plaster, not a red block
		_box_col(body, size, Transform3D(Basis(), c))
		var cap := CylinderShape3D.new()
		cap.radius = 0.4
		cap.height = maxf(size.x, size.z)
		var cap_basis := Basis(Vector3.BACK, PI * 0.5) if size.x > size.z else Basis(Vector3.RIGHT, PI * 0.5)
		_shape(body, cap, Transform3D(cap_basis, top))
		s.cylinder(Transform3D(cap_basis, top), 0.3, 0.3, maxf(size.x, size.z), Color("a8784a"), 12)
	if plat.has("WALL_SCREEN_B1"):
		var w: Dictionary = plat["WALL_SCREEN_B1"]
		var wm = M.new()
		_sector(wm, v3(w["pos"]), float(w["r_in"]) - 0.1, float(w["r"]) + 0.1, float(w["az_from"]), float(w["az_to"]), float(w["thickness"]), Color("e2c9a8"), Color("c9a982"))
		_mi(wm.commit(tex_mat("plaster_wall", 0.22)), holder, Transform3D.IDENTITY, "ScreenB1")  # fix r2: plaster
		var cps := ConcavePolygonShape3D.new()
		cps.set_faces(wm.faces())
		_shape(body, cps)
	# Fix r2 (visual critic: the orange brick screens reached saturation 0.56-0.59): warm plaster like the cottage.
	_mi(s.commit(tex_mat("plaster_wall", 0.22)), holder, Transform3D.IDENTITY, "ScreenWalls")
	# Copper pans on the kitchen side of the west screen, a plate rack on the north screen (scale cues).
	var d = M.new()
	for i in 4:
		var pz := -40.5 + float(i) * 2.8
		var pc := Vector3(-15.75, 61.0 - float(i % 2) * 0.6, pz)
		d.puck(Transform3D(Basis(Vector3.BACK, PI * 0.5), pc), 0.9 + 0.2 * float(i % 2), 0.25, 0.08, Color("d07a40"), 20)
		d.cylinder(Transform3D(Basis(), pc + Vector3(0.05, 1.4, 0)), 0.08, 0.08, 1.8, Color("b06a30"), 8)
	for i in 5:
		d.puck(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.12), Vector3(-14.5 + float(i) * 1.6, 61.0, -41.75)), 0.7, 0.08, 0.03, Color("f7f5ff"), 20)
	d.rbox(Transform3D(Basis(), Vector3(-11.3, 60.2, -41.7)), Vector3(8.4, 0.15, 0.5), 0.05, C_WOOD, 2)
	_mi(d.commit(vc_mat(0.4, 0.8)), holder, Transform3D.IDENTITY, "PansAndPlates")
	# The Giant's seated body: a steep hull nobody can stand on.
	if plat.has("GIANT_BODY"):
		var gp := PackedVector3Array([Vector3(-16, 50, -36.5), Vector3(-12.5, 50, -36.5), Vector3(-16, 50, -31.5), Vector3(-12.5, 50, -31.5), Vector3(-14.5, 61.5, -34.3), Vector3(-14.0, 61.5, -33.7)])
		var gcp := ConvexPolygonShape3D.new()
		gcp.points = gp
		_shape(body, gcp)
	# The Giant's boot, kicked off beside the belfry (4.4 m long: the Giant is about 25 m tall).
	if plat.has("GIANT_BOOT"):
		var bm = M.new()
		var leather := Color("7a4a2a")
		bm.rbox(Transform3D(Basis(), Vector3(-11.0, 50.8, -19.2)), Vector3(2.4, 1.6, 1.9), 0.6, leather, 3, leather.lightened(0.1))
		_box_col(body, Vector3(2.4, 1.6, 1.8), Transform3D(Basis(), Vector3(-11.0, 50.8, -19.2)))
		bm.cylinder(Transform3D(Basis(), Vector3(-11.0, 52.1, -21.1)), 1.2, 1.25, 4.2, leather.darkened(0.1), 22, true, Color("3b2416"))
		bm.torus(Transform3D(Basis(), Vector3(-11.0, 54.2, -21.1)), 1.2, 0.12, Color("5a3520"), 22, 6)
		bm.rbox(Transform3D(Basis(), Vector3(-11.0, 50.25, -20.5)), Vector3(2.6, 0.5, 4.6), 0.2, Color("3b2416"), 2)
		for k in 4:
			bm.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.12), Vector3(-9.8, 52.6 + k * 0.4, -21.1)), C_GOLD, 6, 4)
		bm.rbox(Transform3D(Basis(Vector3.UP, 0.3), Vector3(-11.6, 51.4, -18.6)), Vector3(0.7, 0.5, 0.06), 0.03, Color("a86a3a"), 1)
		_mi(bm.commit(vc_mat(0.35)), holder, Transform3D.IDENTITY, "GiantBoot")
		_cyl_col(body, 1.2, 4.2, Vector3(-11.0, 52.1, -21.1))
	# A giant fork planted in the bank east of the gate as a flagpole with a wolf banner.
	var fk = M.new()
	fk.cylinder(Transform3D(Basis(), Vector3(20.5, 54.5, -18.5)), 0.18, 0.22, 9.0, Color("c9c9d2"), 10)
	for k in 4:
		fk.cylinder(Transform3D(Basis(), Vector3(20.5 + (float(k) - 1.5) * 0.35, 59.6, -18.5)), 0.07, 0.09, 1.6, Color("d9d9e2"), 8)
	fk.rbox(Transform3D(Basis(), Vector3(20.5, 58.8, -18.5)), Vector3(1.4, 0.3, 0.2), 0.08, Color("c9c9d2"), 2)
	fk.rbox(Transform3D(Basis(), Vector3(21.4, 57.0, -18.5)), Vector3(1.6, 2.6, 0.08), 0.04, C_BANNER, 2)
	_mi(fk.commit(vc_mat(0.4, 0.9)), holder, Transform3D.IDENTITY, "GiantFork")
	_cyl_col(body, 0.25, 9.0, Vector3(20.5, 54.5, -18.5))


func _r3_structures() -> void:
	var holder := _node("Round3")
	var body := _body("Round3Collision", holder)
	var s = M.new()
	var d = M.new()
	# Gate towers with spires either side of the gate (castle silhouette from the garden).
	for id: String in ["GATE_TOWER_W", "GATE_TOWER_E"]:
		if not plat.has(id):
			continue
		var tp := v3(plat[id]["pos"])
		var c := Vector3(tp.x, 0, tp.z)
		s.puck(Transform3D(Basis(), Vector3(c.x, 56.0, c.z)), 1.6, 12.0, 0.2, C_STONE, 24)
		_cyl_col(body, 1.6, 12.0, Vector3(c.x, 56.0, c.z))
		for k in 8:
			var a := TAU * float(k) / 8.0
			s.rbox(Transform3D(Basis(Vector3.UP, -a), Vector3(c.x + cos(a) * 1.65, 61.4, c.z + sin(a) * 1.65)), Vector3(0.5, 0.9, 0.6), 0.1, C_STONE.lightened(0.05), 2)
		_spire(d, Vector3(c.x, 68.0, c.z), 0.06, 2.0, 12.0)
		d.torus(Transform3D(Basis(), Vector3(c.x, 62.1, c.z)), 2.0, 0.14, C_GOLD, 20, 6)
		d.sphere(Transform3D(Basis().scaled(Vector3.ONE * 0.35), Vector3(c.x, 74.2, c.z)), C_GOLD, 10, 6)
		d.cylinder(Transform3D(Basis(), Vector3(c.x, 75.4, c.z)), 0.04, 0.04, 2.0, Color("6b5a4a"), 6)
		d.rbox(Transform3D(Basis(), Vector3(c.x + 0.6, 76.0, c.z)), Vector3(1.1, 0.6, 0.05), 0.02, C_BANNER, 1, C_GOLD)
		var pts := PackedVector3Array()
		for k in 12:
			var a := TAU * float(k) / 12.0
			pts.append(Vector3(c.x + cos(a) * 2.0, 62.0, c.z + sin(a) * 2.0))
		pts.append(Vector3(c.x, 74.0, c.z))
		var cp := ConvexPolygonShape3D.new()
		cp.points = pts
		_shape(body, cp)
		for k in 3:
			d.rbox(Transform3D(Basis(), Vector3(c.x, 54.0 + k * 2.3, c.z + 1.58)), Vector3(0.3, 0.9, 0.1), 0.04, Color("3b2e3a"), 1)
	_mi(s.commit(tex_mat("castle_stone", 0.3)), holder, Transform3D.IDENTITY, "GateTowers")
	_mi(d.commit(vc_mat(0.35, 0.5)), holder, Transform3D.IDENTITY, "Spires")
	# Colossus leaves: six huge visual leaves that give the beanstalk its bulk at distance.
	var cl := [[11.5, -100.0], [17.0, 180.0], [19.5, 120.0], [30.5, -110.0], [38.5, 100.0], [54.5, -20.0]]
	var leaves := _node("ColossusLeaves", holder)
	var pods = M.new()
	for e in cl:
		var y := float(e[0])
		var az := deg_to_rad(float(e[1]))
		var ctr := stalk_center(y)
		var out := Vector3(cos(az), 0, sin(az))
		var basis := Basis.looking_at(-out, Vector3.UP) * Basis(Vector3.RIGHT, deg_to_rad(-20.0))
		var base := ctr + out * 1.6
		var g := place_glb("giant_leaf/giant_leaf.glb", leaves, Transform3D(basis * Basis.from_scale(Vector3(4.5 / 3.38, 1.6, 7.0 / 4.0)), base + basis * Vector3(0, 0, 3.5)), "CLV")
		if g:
			for mi in g.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var tip := base + basis * Vector3(0, 0, 7.0)
		pods.sphere(Transform3D(Basis().scaled(Vector3(0.45, 1.5, 0.38)), tip + Vector3(0, -1.6, 0)), C_PEA.darkened(0.1), 14, 8)
		pods.tube(PackedVector3Array([tip, tip + Vector3(0, -0.2, 0)]), PackedFloat32Array([0.08, 0.08]), C_STALK, 6)
	_mi(pods.commit(vc_mat(0.4)), holder, Transform3D.IDENTITY, "ColossusPods")
	# The Giant's candle on the table (second breath telegraph) and his hunched back.
	if plat.has("CANDLE"):
		var cp2 := v3(plat["CANDLE"]["pos"])
		var cm = M.new()
		cm.puck(Transform3D(Basis(), cp2 + Vector3(0, -0.2, 0)), 0.9, 0.4, 0.1, Color("c9a04a"), 22)
		cm.torus(Transform3D(Basis(Vector3.BACK, PI * 0.5), cp2 + Vector3(1.0, -0.1, 0)), 0.25, 0.06, Color("c9a04a"), 12, 5)
		cm.cylinder(Transform3D(Basis(), cp2 + Vector3(0, 2.0, 0)), 0.55, 0.55, 4.0, Color("fff3d8"), 18, true, Color("fff8e8"))
		for k in 4:
			var a := float(k) * 1.6
			cm.sphere(Transform3D(Basis().scaled(Vector3(0.14, 0.5, 0.14)), cp2 + Vector3(cos(a) * 0.52, 3.6 - k * 0.2, sin(a) * 0.52)), Color("fff3d8"), 8, 5)
		cm.cylinder(Transform3D(Basis(), cp2 + Vector3(0, 4.2, 0)), 0.02, 0.02, 0.25, Color("3b2416"), 4)
		_mi(cm.commit(vc_mat(0.4, 0.6)), holder, Transform3D.IDENTITY, "Candle")
		_cyl_col(body, 0.9, 0.4, cp2 + Vector3(0, -0.2, 0))
		_cyl_col(body, 0.55, 4.1, cp2 + Vector3(0, 2.05, 0))
		visuals["CANDLE_TOP"] = cp2 + Vector3(0, 4.35, 0)
	if plat.has("GIANT_BACK"):
		var gb := PackedVector3Array([Vector3(-16.0, 58, -39.0), Vector3(-14.2, 58, -39.0), Vector3(-16.0, 58, -30.8), Vector3(-14.2, 58, -30.8), Vector3(-15.6, 65, -35.2), Vector3(-15.6, 65, -34.6)])
		var gcp := ConvexPolygonShape3D.new()
		gcp.points = gb
		_shape(body, gcp)


## Annulus sector (top at center.y): rounded lip, smooth shading, closed loop cross-section.
func _sector(m, c: Vector3, r_in: float, r_out: float, az_from: float, az_to: float, thick: float, col_top: Color, col_side: Color) -> void:
	var rows := []
	var cols := []
	var n := maxi(8, int(absf(az_to - az_from) / 4.0))
	var prof := [[r_in, 0.0, 0.0], [lerpf(r_in, r_out, 0.5), 0.0, 0.0], [r_out - 0.15, -0.02, 0.0], [r_out, -thick * 0.35, 1.0], [r_out - 0.2, -thick, 1.0], [r_in, -thick, 1.0]]
	for i in n + 1:
		var a := deg_to_rad(lerpf(az_from, az_to, float(i) / float(n)))
		var d := Vector3(cos(a), 0, sin(a))
		var row := PackedVector3Array()
		var crow := PackedColorArray()
		for pr in prof:
			row.append(c + d * float(pr[0]) + Vector3(0, float(pr[1]), 0))
			crow.append(col_top.lerp(col_side, float(pr[2])))
		rows.append(row)
		cols.append(crow)
	var rm := (r_in + r_out) * 0.5
	grid_into(m, rows, cols, true, func(p: Vector3) -> Vector3:
		var a2 := atan2(p.z - c.z, p.x - c.x)
		var cen := c + Vector3(cos(a2), 0, sin(a2)) * rm + Vector3(0, -thick * 0.5, 0)
		var o := p - cen
		return o.normalized() if o.length() > 0.001 else Vector3.UP)

# ------------------------------------------------------------------ cloud layers, sea and backdrop

func _cloud_layers() -> void:
	# CL1 (y 22..25.5) and CL2 (y 42..45.5): broken rings of flattened puffs with holes around the route.
	var holes1 := [[Vector2(0, -3.5), 6.0], [Vector2(-5.5, -13.5), 9.0], [Vector2(23, -4), 15.0], [Vector2(9.5, -2.5), 4.0], [Vector2(-24.5, -12), 10.5], [Vector2(6.5, -11), 4.0], [Vector2(5.4, -6.2), 4.0], [Vector2(-1.5, -7.4), 4.0]]
	var holes2 := [[Vector2(-3.5, -12.5), 6.0], [Vector2(-14, -8), 8.5], [Vector2(2, -31), 19.0], [Vector2(-24.5, -12.5), 4.0], [Vector2(-29.5, -16.5), 4.0], [Vector2(-34, -21), 4.0], [Vector2(-38, -26), 4.0], [Vector2(-40.5, -31.5), 4.0], [Vector2(-40.5, -38), 5.0], [Vector2(-1, -9), 7.0]]
	_layer("layer1", 23.0, holes1, 90, 1.0, 101.0)
	_layer("layer2", 43.2, holes2, 60, 0.8, 202.0)


func _layer(group: String, y: float, holes: Array, count: int, size_k: float, seed: float) -> void:
	# Broken cloud banks well outside the play column, so the route and the castle stay visible.
	var placed := 0
	var i := 0
	while placed < count and i < count * 8:
		i += 1
		var a := h01(i, seed) * TAU
		var r := 34.0 + pow(h01(i, seed + 1.0), 0.8) * 70.0
		var p := Vector2(cos(a) * r, -8.0 + sin(a) * r)
		var clump := M.vnoise(p.x * 0.03, p.y * 0.03, seed)
		if clump < 0.5:
			continue
		var ok := true
		for h in holes:
			if p.distance_to(h[0]) < float(h[1]) + 4.0:
				ok = false
				break
		if not ok:
			continue
		var s := (1.6 + h01(i, seed + 2.0) * 2.6) * size_k * (0.6 + clump)
		if in_sightline(Vector3(p.x, y, p.y), s * 1.4):
			continue
		placed += 1
		_cloud(group + "_" + str(int(a / TAU * 4.0)), Transform3D(Basis().scaled(Vector3(s * 1.35, s * 0.42, s)), Vector3(p.x, y + (h01(i, seed + 3.0) - 0.5) * 2.5, p.y)))


## Round 1 sightline corridors: nothing visual may enter the 8 degree cone from the Default eye to the
## belfry flower, nor the 10 degree cone from StoryCam_A to its look-at point.
const SIGHTLINES := [[Vector3(0, 1.6, 29), Vector3(-18, 69, -24), 8.0], [Vector3(0, 1.6, 35), Vector3(-18, 69, -24), 8.0], [Vector3(26, 7, 44), Vector3(-3, 33, -14), 10.0], [Vector3(26, 7, 44), Vector3(2, 58, -36), 6.0]]


func in_sightline(p: Vector3, radius: float) -> bool:
	for sl in SIGHTLINES:
		var e: Vector3 = sl[0]
		var axis: Vector3 = ((sl[1] as Vector3) - e).normalized()
		var d := p - e
		var along := d.dot(axis)
		if along <= 0.0:
			continue
		var perp := (d - axis * along).length()
		if perp - radius < along * tan(deg_to_rad(float(sl[2]))):
			return true
	return false


func _backdrop() -> void:
	var holder := _node("Backdrop")
	# Cloud sea far below: big soft mounds between radius 26 and 300.
	for i in 300:
		var a := h01(i, 301.0) * TAU
		var r := 26.0 + pow(h01(i, 302.0), 0.6) * 280.0
		var s := 9.0 + h01(i, 303.0) * 18.0 + r * 0.04
		_cloud("sea_" + str(int(a / TAU * 6.0)), Transform3D(Basis().scaled(Vector3(s * 1.3, s * 0.42, s)), Vector3(cos(a) * r, -26.0 + h01(i, 304.0) * 4.0, -8.0 + sin(a) * r)))
	# Distant cloud mountains on a 180-240 m ring.
	for i in 70:
		var a := TAU * float(i) / 70.0 + h01(i, 305.0) * 0.08
		var r := 190.0 + h01(i, 306.0) * 60.0
		var s := 16.0 + h01(i, 307.0) * 18.0
		var hgt := -22.0 + h01(i, 308.0) * 22.0
		if in_sightline(Vector3(cos(a) * r, hgt, -8.0 + sin(a) * r), s * 1.2):
			continue
		_cloud("far_" + str(int(a / TAU * 6.0)), Transform3D(Basis().scaled(Vector3(s * 1.2, s, s)), Vector3(cos(a) * r, hgt, -8.0 + sin(a) * r)))
	# The Giant's keep looming behind the playable courtyard (pop-up cutaway backdrop).
	var keep := place_glb("giant_castle/giant_castle.glb", holder, Transform3D(Basis().scaled(Vector3.ONE * 1.25), Vector3(2, 41.0, -66)), "GiantKeep")
	if keep:
		visuals["KEEP"] = keep
		# Fix r2 (visual critic): read as far scenery, not an unfinished second castle: one hazy blue-lavender
		# silhouette material, slightly lit so the towers keep their shape.
		var hz := StandardMaterial3D.new()
		hz.albedo_color = Color("a99bd9")
		hz.roughness = 1.0
		hz.emission_enabled = true
		hz.emission = Color("8f84c8")
		hz.emission_energy_multiplier = 0.35
		for mi in keep.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = hz
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A neighbour's floating cottage islet far to the east, and the golden harp's islet to the west.
	var far_cot := place_glb("jack_cottage/jack_cottage.glb", holder, Transform3D(Basis(Vector3.UP, -0.9).scaled(Vector3.ONE * 2.2), Vector3(78, 6.0, 30)), "FarIslet")
	if far_cot:
		visuals["FAR_ISLET"] = far_cot
	cloud_visual("far_islet", Vector3(78, 6.5, 30), 6.0, 5.0, 2.0, 77.0, 0.6)

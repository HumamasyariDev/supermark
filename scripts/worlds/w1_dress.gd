class_name W1Dress
extends RefCounted
## W1 dressing: procedural landmarks without a generated mesh (Grand Birch treehouse, Hollow Tor, willow,
## Spring Grotto, henchmen's camp, scarecrow), foliage and prop scatter (MultiMesh grass and flowers,
## generated birch and apple trees, hedgerows, haystacks, reeds), ambient effects and signposts.
## Everything is deterministic (fixed seeds).

const K := preload("res://scripts/worlds/w1_kit.gd")
## Fix round 2 (visual r1): v4 paints the limb strips (no pale stubs at the forks); same geometry as v3.
const BIRCH_GLB := "res://assets/props/w1/birch_tree_v4/birch_tree_v4.glb"
## R3.6 sightline from the spawn to the Hay Hoist (widened 2 m each side at the far end): no trees inside.
const HOIST_SIGHT := [Vector2(-1.5, 55.5), Vector2(-39.0, -57.0), Vector2(-31.0, -57.0)]
## Skep beehive groups (R3.12); W1Life circles small bees round them.
const SKEPS := [Vector2(-30.0, 53.4), Vector2(53.4, 14.0), Vector2(-53.4, -12.0)]
const APPLE_GLB := "res://assets/props/w1/apple_tree/apple_tree.glb"
const HAY_GLB := "res://assets/props/w1/hay_bale/hay_bale.glb"

static var swayers: Array[Node3D] = []


static func gy(x: float, z: float) -> float:
	return W1Terrain.height(x, z)


static func fx(parent: Node3D, scene_name: String, pos: Vector3, props: Dictionary = {}) -> Node3D:
	var path := "res://scenes/fx/%s.tscn" % scene_name
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	for k in props:
		n.set(k, props[k])
	n.position = pos
	parent.add_child(n)
	return n


static func glb_inst(path: String, parent: Node3D, pos: Vector3, yaw_deg: float, scl: Vector3) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	inst.position = pos
	inst.rotation_degrees.y = yaw_deg
	inst.scale = scl
	parent.add_child(inst)
	return inst


## Posts from a platform's underside down to the ground.
static func posts_under(b: Node3D, size: Vector3, top: Vector3, ground_y: float) -> void:
	var h := top.y - size.y - ground_y
	if h < 0.2:
		return
	var wood := K.mat(Color("6e4a2c"), 0.85)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			K.cyl(b, 0.1, 0.13, h + 0.3, wood, Vector3(sx * (size.x * 0.5 - 0.2), -size.y - h * 0.5, sz * (size.z * 0.5 - 0.2)), Vector3.ZERO, 8)


# ------------------------------------------------------------------ landmarks

static func landmarks(level: Node3D) -> void:
	_treehouse(level)
	_tor(level)
	_willow(level)
	_grotto(level)
	_camp(level)
	_scarecrow(level)
	_signs(level)
	_battle_plan(level)


static func _treehouse(level: Node3D) -> void:
	var root := Node3D.new()
	root.name = "GrandBirchTreehouse"
	level.add_child(root)
	# Grand Birch: the generated birch at 2.6x (26 m), trunk collision only.
	var trunk_base := Vector3(-47.5, gy(-47.5, -31.5) - 0.2, -31.5)
	var tree := glb_inst(BIRCH_GLB, root, trunk_base, 30.0, Vector3.ONE * 2.6)
	if tree == null:
		K.cyl(root, 0.9, 1.3, 24.0, K.mat(K.BIRCH), trunk_base + Vector3(0, 12, 0))
		K.sphere(root, 7.0, K.mat(K.LEAF), trunk_base + Vector3(0, 22, 0), Vector3(1.1, 0.75, 1.1))
	var tb := K.body(root, "GrandBirchTrunk", trunk_base)
	# Fix round 2 (feel r1: at the Crows' Nest the arm collapsed to 1.3 m inside the canopy): the trunk above the deck
	# (y 16) blocks Mak only (layer 3), so the camera arm passes it; below the deck it stays world collision.
	var low_h := 16.0 - trunk_base.y
	K.shape_cyl(tb, 0.8, low_h, Vector3(0, low_h * 0.5, 0))
	var tb_hi := K.body(root, "GrandBirchTrunkUpper", trunk_base)
	tb_hi.collision_layer = 4
	K.shape_cyl(tb_hi, 0.8, 26.0 - low_h, Vector3(0, low_h + (26.0 - low_h) * 0.5, 0))
	# Treehouse deck (top 16) with rails on the west, north and south; the east edge is open for the
	# scaffold arrival and the rope bridge.
	var plank := K.tex_mat("wood_planks", Color(1.02, 0.84, 0.62), 0.6)
	var dark := K.mat(Color("6e4a2c"), 0.85)
	var deck := K.platform(root, "treehouse_deck", Vector3(-46, 16.0, -30), Vector3(6.0, 0.4, 6.0), 0.0, plank, 0.08)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			K.cyl(deck, 0.12, 0.12, 2.6, dark, Vector3(sx * 2.6, -1.6, sz * 2.6), Vector3(sz * 25.0, 0, -sx * 25.0), 8)
	var rail_mat := K.mat(Color("8a5a3b"), 0.8)
	var rails := [[Vector3(-3.0, 0.5, 0), Vector3(0.12, 1.0, 6.0)], [Vector3(0, 0.5, -3.0), Vector3(6.0, 1.0, 0.12)], [Vector3(-1.25, 0.5, 3.0), Vector3(3.5, 1.0, 0.12)]]
	for r in rails:
		var rp: Vector3 = r[0]
		var rs: Vector3 = r[1]
		K.shape_box(deck, rs, rp)
		K.rbox(deck, Vector3(rs.x, 0.1, rs.z), rail_mat, rp + Vector3(0, 0.45, 0), Vector3.ZERO, 0.04)
		var n := int(maxf(rs.x, rs.z) / 0.7)
		for i in n + 1:
			var t := -0.5 + float(i) / n
			K.cyl(deck, 0.05, 0.05, 1.0, rail_mat, rp + Vector3(rs.x * t if rs.x > 1 else 0.0, 0, rs.z * t if rs.z > 1 else 0.0), Vector3.ZERO, 6)
	# Round plank hut, walls 3.3 m, flat turf roof top 19.3 (R1.5 P3: backflip from the door; eave not grabbable).
	var hut := Vector3(-47.5, 16.0, -28.6)
	var hb := K.body(root, "TreehouseHut", hut)
	hb.set_meta("no_ledge_grab", true)
	hb.add_to_group("no_ledge_grab")
	K.shape_cyl(hb, 1.45, 3.3, Vector3(0, 1.65, 0))
	K.shape_box(hb, Vector3(3.0, 0.3, 3.0), Vector3(0, 3.15, 0))
	K.cyl(hb, 1.4, 1.5, 3.1, K.tex_mat("wood_planks", Color(0.95, 0.7, 0.5), 0.8), Vector3(0, 1.55, 0), Vector3.ZERO, 18)
	K.cyl(hb, 1.75, 1.85, 0.35, K.tex_mat("grass", Color(0.95, 1.05, 0.8), 0.7), Vector3(0, 3.15, 0), Vector3.ZERO, 18)
	K.sphere(hb, 1.2, K.mat(Color("7cc043"), 0.85), Vector3(0, 3.3, 0), Vector3(1.3, 0.22, 1.3))
	K.cyl(hb, 0.35, 0.35, 0.12, K.mat(Color("ffe3a0"), 0.3), Vector3(0, 2.0, 1.45), Vector3(90, 0, 0), 14)
	K.torus(hb, 0.32, 0.44, dark, Vector3(0, 2.0, 1.48), Vector3(90, 0, 0))
	# Door faces east onto the deck (R1.1).
	K.rbox(hb, Vector3(0.14, 1.8, 0.9), K.mat(Color("3f8f5a")), Vector3(1.45, 0.9, 0.0), Vector3.ZERO, 0.05)
	K.sphere(hb, 0.06, K.mat(K.GOLD, 0.3), Vector3(1.54, 0.9, 0.3))
	# Pennant on the hut.
	K.cyl(hb, 0.04, 0.04, 1.6, dark, Vector3(-0.8, 4.0, -0.6), Vector3.ZERO, 6)
	K.rbox(hb, Vector3(0.7, 0.4, 0.04), K.mat(K.RED_RIBBON), Vector3(-0.45, 4.55, -0.6), Vector3.ZERO, 0.02)
	# Fireman's pole down to the grove floor beside the south-east corner of the deck.
	var pole_base := Vector3(-44.6, gy(-44.6, -26.4), -26.4)
	var climb_h := 16.6 - pole_base.y
	# R3.2: the old fireman's pole let Mak climb 12 m from the floor and skip W1-3; it is now a greased decorative post.
	var post := K.cyl(root, 0.15, 0.17, climb_h, K.mat(Color("8a6a4a"), 0.15), pole_base + Vector3(0, climb_h * 0.5, 0), Vector3.ZERO, 10)
	post.name = "TreehousePoleGreased"
	var pb := K.body(root, "TreehousePolePost", pole_base)
	K.shape_cyl(pb, 0.17, climb_h, Vector3(0, climb_h * 0.5, 0))
	K.platform(root, "PoleLanding", Vector3(-42.9, 16.0, -27.0), Vector3(1.4, 0.3, 1.4), 0.0, plank, 0.05)
	# Rope-and-bucket pulley and leaves falling from the canopy.
	K.cyl(root, 0.02, 0.02, 9.0, K.mat(Color("d8c08a")), Vector3(-49.2, 11.5, -27.2), Vector3.ZERO, 4)
	K.cyl(root, 0.25, 0.2, 0.4, K.mat(Color("a8743f")), Vector3(-49.2, 7.2, -27.2), Vector3.ZERO, 10)
	fx(root, "FallingLeaves", Vector3(-46, 20, -30))


static func _tor(level: Node3D) -> void:
	var root := Node3D.new()
	root.name = "HollowTor"
	level.add_child(root)
	var rock := K.tex_mat("cliff_rock", Color(1.1, 1.06, 1.0), 0.35)
	var moss := K.mat(Color("7fae45"), 0.85)
	# Look polish 2026-10-19 (owner: "rings of round mounds" hid the stepping pillars, had no collision and ruined the
	# view from the top): the 11-boulder ring round the cliff skirt is gone. One low boulder stays at the foot of the
	# south-east face, clear of the pillar spiral (west/north), the long-jump lane (east, z 3) and the haystack arc (x 36.5).
	for b in [[Vector3(40.4, 0, 8.0), 1.0]]:
		var bp: Vector3 = b[0]
		var bs: float = b[1]
		bp.y = gy(bp.x, bp.z)
		K.sphere(root, bs, rock, bp + Vector3(0, bs * 0.25, 0), Vector3(1.15, 0.62, 1.0))
	# Take-off board at the east rim (P2): a plank strip with two red chevrons pointing at the Stone Finger, so the top
	# reads as a run-up lane for the long jump (sign SIGN_P2 explains the move).
	var board := Node3D.new()
	board.name = "FingerTakeoff"
	board.position = Vector3(37.4, gy(37.4, 3.0) + 0.03, 3.0)
	root.add_child(board)
	K.rbox(board, Vector3(2.2, 0.06, 1.3), K.tex_mat("wood_planks", Color(1.0, 0.86, 0.68), 0.6), Vector3.ZERO, Vector3.ZERO, 0.02)
	var red := K.mat(Color("c8302e"), 0.8)
	for cx in [-0.45, 0.35]:
		for side in [-1.0, 1.0]:
			K.rbox(board, Vector3(0.5, 0.03, 0.12), red, Vector3(cx, 0.04, side * 0.17), Vector3(0, side * 35.0, 0), 0.01)
	# Lookout cairn and a little flag on top.
	K.sphere(root, 0.6, rock, Vector3(35.6, 7.3, 4.4), Vector3(1, 0.7, 1))
	K.sphere(root, 0.45, rock, Vector3(35.5, 7.9, 4.3), Vector3(1, 0.7, 1))
	K.cyl(root, 0.04, 0.04, 1.6, K.mat(Color("6e4a2c")), Vector3(35.4, 8.9, 4.3), Vector3.ZERO, 6)
	K.rbox(root, Vector3(0.7, 0.4, 0.04), K.mat(Color("2e6f8c")), Vector3(35.75, 9.4, 4.3), Vector3.ZERO, 0.02)
	K.sphere(root, 2.2, moss, Vector3(33, 7.0, 2.2), Vector3(1.6, 0.06, 1.3))


static func _willow(level: Node3D) -> void:
	var root := Node3D.new()
	root.name = "WeepingWillow"
	var base := Vector3(48, gy(48, 13), 13)
	root.position = base
	level.add_child(root)
	var bark := K.tex_mat("bark", Color(0.8, 0.7, 0.55), 0.5)
	var b := K.body(root, "WillowTrunk")
	K.shape_cyl(b, 0.9, 6.0, Vector3(0, 3.0, 0))
	K.cyl(root, 0.75, 1.15, 6.0, bark, Vector3(0, 3.0, 0), Vector3(0, 0, 4), 12)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		K.cyl(root, 0.18, 0.5, 2.0, bark, Vector3(cos(a) * 0.9, 0.3, sin(a) * 0.9), Vector3(sin(a) * 50.0, 0, -cos(a) * 50.0), 8)
	# Fix round 1 (visual critic r1: 3 spheres and 70 capsule rods read as a green jellyfish): a lumpy canopy of nine
	# clumps that spill over the rim, and a curtain of tapered, curved, double-sided frond ribbons (two greens, light
	# tips; MultiMesh), parted on the south side so the W1-8 mud patch reads from the lane. Interim until W1-M18.
	var leaf := K.mat(Color("6fae3a"), 0.8)
	var leaf2 := K.mat(Color("4f9a37"), 0.8)
	var leaf3 := K.mat(Color("86c04a"), 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	K.sphere(root, 2.6, leaf2, Vector3(0, 8.2, 0), Vector3(1.25, 0.6, 1.25))
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(2.2, 3.1)
		var sc := rng.randf_range(1.5, 2.1)
		K.sphere(root, sc, [leaf, leaf2, leaf3][i % 3], Vector3(cos(a) * r, rng.randf_range(6.9, 8.1), sin(a) * r), Vector3(1.15, 0.62, 1.15))
	K.sphere(root, 1.6, leaf3, Vector3(0.4, 9.1, -0.3), Vector3(1.2, 0.6, 1.2))
	var fm := _frond_mesh()
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fmat.roughness = 0.8
	fmat.rim_enabled = true
	fmat.rim = 0.2
	for g in 4:
		var xf: Array[Transform3D] = []
		for i in 22:
			var a := TAU * (g * 22 + i) / 88.0 + rng.randf_range(-0.03, 0.03)
			var gap := absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.38
			var r := rng.randf_range(3.0, 4.2)
			var ln := rng.randf_range(3.4, 5.6) if not gap else rng.randf_range(1.0, 1.6)
			var dir := Vector3(cos(a), 0, sin(a))
			var bx := dir
			var bz := bx.cross(Vector3.UP)
			var bas := Basis(bx, Vector3.UP, bz).scaled(Vector3(rng.randf_range(0.8, 1.2), ln, rng.randf_range(0.8, 1.15)))
			xf.append(Transform3D(bas, Vector3(cos(a) * r, rng.randf_range(7.0, 7.8), sin(a) * r)))
		var holder := Node3D.new()
		holder.name = "WillowFronds%d" % g
		root.add_child(holder)
		holder.position = Vector3(0, 7.4, 0)
		for k in xf.size():
			xf[k].origin -= Vector3(0, 7.4, 0)
		_mm(holder, fm, fmat, xf, "Fronds")
		var tw := holder.create_tween().set_loops()
		var amp := 1.6 + g * 0.4
		tw.tween_property(holder, "rotation_degrees", Vector3(amp, 0, -amp * 0.6), 2.2 + g * 0.3).set_trans(Tween.TRANS_SINE)
		tw.tween_property(holder, "rotation_degrees", Vector3(-amp * 0.7, 0, amp), 2.4 + g * 0.3).set_trans(Tween.TRANS_SINE)
	# Mossy bank and roots.
	K.sphere(root, 2.5, K.mat(Color("6f9a3a")), Vector3(0, -0.6, 0), Vector3(1.4, 0.35, 1.4))


## A unit-length willow frond ribbon: hangs down 1 m from its root, bowing outward along +X, 0.55 m wide at the root
## tapering to 0.08 m, dark green to a light tip (vertex colour).
static func _frond_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 8
	var dark := Color("4f9a37")
	var light := Color("a6d65a")
	var pts: Array[Vector3] = []
	var cols: Array[Color] = []
	for i in segs + 1:
		var t := float(i) / segs
		var x := 0.32 * sin(t * PI * 0.6)
		var y := -t
		var w := lerpf(0.55, 0.08, t)
		pts.append(Vector3(x, y, -w * 0.5))
		pts.append(Vector3(x, y, w * 0.5))
		var c := dark.lerp(light, t * t)
		cols.append(c)
		cols.append(c)
	for i in segs:
		var q := [i * 2, i * 2 + 1, i * 2 + 2, i * 2 + 1, i * 2 + 3, i * 2 + 2]
		for k in q:
			st.set_color(cols[k])
			st.set_normal(Vector3(1.0, 0.35, 0.0).normalized())
			st.add_vertex(pts[k])
	return st.commit()


static func _grotto(level: Node3D) -> void:
	# Spring Grotto (R1.5): the Kick Cleft's three granite walls are platforms (w1_level); this adds the waterfall cave
	# in the south half (sniff stash ST2) and mossy dressing that wraps the cleft.
	var root := Node3D.new()
	root.name = "SpringGrotto"
	level.add_child(root)
	var rock := K.tex_mat("cliff_rock", Color(0.98, 1.0, 0.95), 0.35)
	var moss := K.mat(Color("6f9a3a"), 0.9)
	var b := K.body(root, "GrottoRocks")
	var pieces := [[Vector3(-57.3, 1.5, -2.2), 2.0], [Vector3(-55.6, 1.1, 0.0), 1.5], [Vector3(-55.9, 3.3, -2.4), 2.0], [Vector3(-53.6, 1.0, 0.6), 1.0]]
	for pc in pieces:
		var pp: Vector3 = pc[0]
		var r: float = pc[1]
		pp.y += gy(pp.x, pp.z)
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = r
		cs.shape = sp
		cs.position = pp
		b.add_child(cs)
		K.sphere(root, r, rock, pp, Vector3(1.05, 1.0, 1.0))
	K.sphere(root, 2.0, moss, Vector3(-55.9, gy(-55.9, -2.4) + 5.0, -2.4), Vector3(1.1, 0.3, 1.1))
	K.sphere(root, 2.6, moss, Vector3(-54.0, 7.05, -7.75), Vector3(1.0, 0.08, 1.6))
	# Waterfall curtain over the cave mouth, facing east; walk through it.
	var wm := load("res://assets/shaders/materials/water_stream_ribbon.tres") as Material
	var top_y := gy(-53.0, -2.4) + 4.6
	for rot in [90.0, -90.0]:
		var fall := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2.4, 4.6)
		fall.mesh = q
		fall.material_override = wm if wm else K.mat(Color(0.6, 0.85, 1.0, 0.6))
		fall.position = Vector3(-53.1, top_y - 2.3, -2.3)
		fall.rotation_degrees = Vector3(0, rot, 0)
		fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fall)
	fx(root, "WaterfallFoam", Vector3(-53.0, gy(-53, -2.3), -2.3))
	var pool := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 2.4
	pm.bottom_radius = 2.4
	pm.height = 0.05
	pool.mesh = pm
	var wmat := load("res://assets/shaders/materials/water_stream.tres") as Material
	pool.material_override = wmat if wmat else K.mat(Color(0.4, 0.75, 0.9))
	pool.position = Vector3(-51.0, gy(-51, -2.0) + 0.04, -2.0)
	root.add_child(pool)
	pool.add_to_group("wade_water")   # look polish: splash steps in the grotto pool (WaterWade)
	K.sphere(root, 0.5, rock, Vector3(-52.6, gy(-52.6, -0.4) + 0.2, -0.4), Vector3(1.2, 0.6, 1))


static func _camp(level: Node3D) -> void:
	var root := Node3D.new()
	root.name = "HenchmenCamp"
	root.position = Vector3(-27.5, gy(-27.5, -50), -50)  # R2.1: 2.5 m east, clear of the hay-yard pen
	root.rotation_degrees.y = 20.0
	level.add_child(root)
	var canvas := K.mat(Color("8e949b"), 0.85)
	var red := K.mat(Color("b84a32"), 0.8)
	var wood := K.mat(Color("6e4a2c"), 0.85)
	var tent := K.body(root, "Tent", Vector3(-3.5, 0, -1.5))
	K.shape_box(tent, Vector3(4.0, 2.6, 3.4), Vector3(0, 1.3, 0))
	for i in 5:
		var m := canvas if i % 2 == 0 else red
		var s := K.rbox(tent, Vector3(0.82, 0.1, 2.6), m, Vector3(-1.6 + i * 0.8, 1.45, 0.9), Vector3(-48, 0, 0), 0.04)
		s.scale = Vector3(1, 1, 1)
		K.rbox(tent, Vector3(0.82, 0.1, 2.6), m, Vector3(-1.6 + i * 0.8, 1.45, -0.9), Vector3(48, 0, 0), 0.04)
	K.cyl(tent, 0.06, 0.06, 4.6, wood, Vector3(0, 2.4, 0), Vector3(0, 0, 90), 6)
	K.rbox(tent, Vector3(0.1, 2.0, 0.6), K.mat(Color("2b2220")), Vector3(2.0, 0.9, 0), Vector3.ZERO, 0.04)
	# Campfire ring with a dented kettle and a warm flicker light.
	for i in 8:
		var a := TAU * i / 8.0
		K.sphere(root, 0.22, K.tex_mat("cliff_rock", Color.WHITE, 0.6), Vector3(1.5 + cos(a) * 0.7, 0.12, 1.0 + sin(a) * 0.7), Vector3(1, 0.7, 1))
	for i in 3:
		K.cyl(root, 0.1, 0.1, 1.0, wood, Vector3(1.5, 0.2, 1.0), Vector3(70, i * 60.0, 0), 6)
	K.sphere(root, 0.35, K.glow_mat(Color("ff8a3d"), 3.0), Vector3(1.5, 0.35, 1.0), Vector3(1, 1.3, 1))
	K.cyl(root, 0.22, 0.28, 0.4, K.mat(Color("3b3b44"), 0.4), Vector3(1.5, 1.1, 1.0), Vector3(0, 0, 8), 12)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb060")
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position = Vector3(1.5, 1.0, 1.0)
	root.add_child(light)
	fx(root, "ChimneySmoke", Vector3(1.5, 0.8, 1.0))
	# WANTED: PIGLET poster on a post.
	K.cyl(root, 0.08, 0.1, 2.4, wood, Vector3(-0.5, 1.2, 3.2), Vector3.ZERO, 8)
	K.rbox(root, Vector3(0.9, 1.2, 0.04), K.mat(Color("eadcb0"), 0.9), Vector3(-0.5, 1.9, 3.27), Vector3.ZERO, 0.02)
	var lbl := Label3D.new()
	lbl.text = "WANTED\nPIGLET\n(in a beanie)"
	lbl.font_size = 40
	lbl.modulate = Color("5c3a21")
	lbl.outline_size = 0
	lbl.position = Vector3(-0.5, 1.95, 3.3)
	lbl.pixel_size = 0.004
	root.add_child(lbl)
	# Spare bellows parts on a supply wagon.
	K.rbox(root, Vector3(2.2, 0.5, 1.4), K.tex_mat("wood_planks", Color(0.9, 0.7, 0.5), 0.8), Vector3(4.5, 0.8, -1.0), Vector3(0, 12, 0), 0.06)
	K.sphere(root, 0.6, K.mat(Color("8b5a33"), 0.85), Vector3(4.4, 1.35, -1.0), Vector3(1.4, 0.6, 1))
	K.cyl(root, 0.15, 0.3, 0.8, K.mat(K.GOLD, 0.3), Vector3(5.2, 1.3, -1.2), Vector3(0, 0, 80), 12)


static func _scarecrow(level: Node3D) -> void:
	# R1.5 P5: a posh scarecrow on a single pole with a giant boater (top 4.48, dia 1.8): the triple-jump target.
	var base := Vector3(16, gy(16, 40), 40)
	var root := K.body(level, "Scarecrow", base)
	root.set_meta("no_ledge_grab", true)
	root.add_to_group("no_ledge_grab")
	root.rotation_degrees.y = 135.0
	var top := 4.48 - base.y
	K.shape_cyl(root, 0.12, top - 0.3, Vector3(0, (top - 0.3) * 0.5, 0))
	K.shape_cyl(root, 0.9, 0.25, Vector3(0, top - 0.125, 0))
	var wood := K.tex_mat("bark", Color(0.9, 0.75, 0.6), 0.6)
	K.cyl(root, 0.1, 0.12, top, wood, Vector3(0, top * 0.5, 0), Vector3.ZERO, 8)
	K.cyl(root, 0.09, 0.09, 2.6, wood, Vector3(0, top - 1.9, 0), Vector3(0, 0, 90), 8)
	var tweed := K.mat(Color("7a6a4a"), 0.85)
	K.rbox(root, Vector3(0.9, 1.1, 0.5), tweed, Vector3(0, top - 2.25, 0), Vector3.ZERO, 0.2)
	for sx in [-1.0, 1.0]:
		K.capsule(root, 0.17, 1.0, tweed, Vector3(sx * 0.75, top - 1.9, 0), Vector3(0, 0, 90))
		K.sphere(root, 0.18, K.tex_mat("straw_thatch", Color.WHITE, 0.8), Vector3(sx * 1.3, top - 1.9, 0), Vector3(1.3, 0.8, 0.8))
	K.rbox(root, Vector3(0.34, 0.18, 0.08), K.mat(Color("c8302e")), Vector3(0, top - 1.62, 0.27), Vector3.ZERO, 0.04)
	var sack := K.mat(Color("d9c08a"), 0.9)
	K.sphere(root, 0.46, sack, Vector3(0, top - 1.05, 0), Vector3(1, 1.05, 0.95))
	for sx in [-1.0, 1.0]:
		K.sphere(root, 0.08, K.mat(Color("2b2220")), Vector3(sx * 0.16, top - 0.95, 0.42))
	K.rbox(root, Vector3(0.32, 0.04, 0.04), K.mat(Color("2b2220")), Vector3(0, top - 1.2, 0.44), Vector3(0, 0, 8), 0.01)
	var boater := K.tex_mat("straw_thatch", Color(1.2, 1.08, 0.8), 0.9)
	K.cyl(root, 0.9, 0.92, 0.1, boater, Vector3(0, top - 0.2, 0), Vector3.ZERO, 22)
	K.cyl(root, 0.48, 0.5, 0.42, boater, Vector3(0, top - 0.45, 0), Vector3.ZERO, 18)
	K.cyl(root, 0.505, 0.505, 0.12, K.mat(Color("7a1f2e")), Vector3(0, top - 0.5, 0), Vector3.ZERO, 18)
	K.cyl(root, 0.86, 0.86, 0.03, K.mat(Color("f2d277"), 0.7), Vector3(0, top - 0.13, 0), Vector3.ZERO, 22)
	# Crushed-flower take-off marks along the triple-jump runway (single, double, triple).
	for m in [Vector2(2.5, 27.35), Vector2(7.25, 31.79), Vector2(12.94, 37.13)]:
		var mm := K.cyl(level, 0.8, 0.8, 0.03, K.mat(Color("c9a35a"), 0.95), Vector3(m.x, gy(m.x, m.y) + 0.02, m.y), Vector3.ZERO, 16)
		mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx(level, "Butterflies", base + Vector3(-3, 1.5, 2))


static func hollow_log(level: Node3D, top: Vector3, size: Vector3) -> void:
	# R1.5 P1: hollow oak on the north bank, axis east-west; inner clear height 1.0 m (crouch-slide or dive through).
	var floor_y := -INF
	for x in [-20.0, -18.5, -17.0, -15.5, -14.0]:
		for z in [0.9, 1.5, 2.1]:
			floor_y = maxf(floor_y, gy(x, z))
	floor_y = maxf(floor_y, maxf(top.y, 0.75))  # level with the log ramp's top (R2.7); 1.0 m clearance fallback
	var root := K.body(level, "HollowLog", Vector3(top.x, floor_y, top.z))
	root.set_meta("length", size.x)
	var bark := K.tex_mat("bark", Color(0.9, 0.72, 0.52), 0.45)
	var length := size.x
	# Floor, two side walls (z 0.8 and 2.2) and a roof slab whose underside is 1.0 m above the floor.
	K.shape_box(root, Vector3(length, 0.3, 1.6), Vector3(0, -0.15, 0))
	K.shape_box(root, Vector3(length, 1.4, 0.3), Vector3(0, 0.6, -0.85))
	K.shape_box(root, Vector3(length, 1.4, 0.3), Vector3(0, 0.6, 0.85))
	K.shape_box(root, Vector3(length, 0.5, 2.0), Vector3(0, 1.25, 0))
	# Owner fix 2026-10-19 (W1-5 P1): the tube read as a plastic pipe, its 1.3 m visual hole hid the 1.0 m ceiling (so the
	# crouch requirement was invisible), and two thin dark boards near the mouths looked like breakable barriers that
	# never broke. Now the hole is drawn at the real clearance (1.0 m tall, 1.4 m wide: standing Mak, 1.25 m, visibly
	# does not fit; crouch-walk, crouch-slide or a dive does), the boards are gone, and it is a log: furrowed bark
	# outside, end-grain rings on both cut faces, a dark heartwood inside with a plank floor.
	var hole_c := Vector3(0, 0.3, 0)  # hole centre: r 0.72 -> top 1.02, 0.65 m either side at the floor
	K.cyl(root, 1.2, 1.2, length, bark, hole_c, Vector3(0, 0, 90), 20)
	var furrow := K.tex_mat("bark", Color(0.62, 0.46, 0.32), 0.45)
	for i in 11:
		var a := deg_to_rad(-75.0 + i * 15.0)  # upper and side faces only (the bottom is in the ground)
		var off := Vector3(0, sin(a + PI * 0.5), cos(a + PI * 0.5)) * 1.19
		var ridge := K.rbox(root, Vector3(length - 0.25 - 0.3 * float(i % 3), 0.1, 0.16), furrow, hole_c + off, Vector3.ZERO, 0.04)
		ridge.rotation = Vector3(-a, 0, 0)
		ridge.set_meta("log_fade", true)  # faded with the bark by the W1 cutaway while Mak is inside
	# Dark heartwood inside (drawn from inside too) and a plank floor.
	var heart := K.mat(Color("4a2f1e"), 0.95).duplicate() as StandardMaterial3D
	heart.cull_mode = BaseMaterial3D.CULL_DISABLED
	K.cyl(root, 0.72, 0.72, length + 0.02, heart, hole_c, Vector3(0, 0, 90), 18)
	K.rbox(root, Vector3(length, 0.06, 1.3), K.tex_mat("wood_planks", Color(0.5, 0.36, 0.26), 0.5), Vector3(0, -0.02, 0), Vector3.ZERO, 0.02)
	# End grain on both cut faces: sapwood, light and dark annual rings out to a bark rim.
	var rings := [[0.72, 0.8, Color("8e5a32")], [0.8, 0.9, Color("e3c08a")], [0.9, 0.96, Color("b98a52")], [0.96, 1.06, Color("e8c995")], [1.06, 1.12, Color("b07a45")], [1.12, 1.24, Color("5a3a22")]]
	for e in [-1.0, 1.0]:
		for r in rings:
			K.torus(root, r[0], r[1], K.mat(r[2], 0.8), hole_c + Vector3(e * length * 0.5, 0, 0), Vector3(0, 0, 90))
	# A knot, a moss cushion and a toadstool on top (the walkable top is the roof slab, y 1.5).
	K.sphere(root, 0.16, K.mat(Color("5a3a22"), 0.9), Vector3(0.9, 0.6, 1.18), Vector3(1.0, 1.3, 0.5))
	K.sphere(root, 0.5, K.mat(Color("6f9a3a"), 0.9), Vector3(1.0, 1.46, 0.2), Vector3(1.6, 0.3, 1.0))
	K.sphere(root, 0.25, K.mat(Color("e8413b"), 0.6), Vector3(-1.4, 1.62, -0.3), Vector3(1.2, 0.6, 1.2))
	K.cyl(root, 0.05, 0.12, 0.25, K.mat(Color("f2ead8"), 0.7), Vector3(-1.4, 1.5, -0.3), Vector3.ZERO, 8)


static func _battle_plan(level: Node3D) -> void:
	var p := Vector3(-25.0, gy(-25.0, -53.5), -53.5)
	var t := K.body(level, "BattlePlanTable", p, 20.0)
	K.shape_box(t, Vector3(2.0, 0.9, 1.0), Vector3(0, 0.45, 0))
	var wood := K.tex_mat("wood_planks", Color(0.85, 0.65, 0.48), 0.8)
	K.rbox(t, Vector3(2.0, 0.12, 1.0), wood, Vector3(0, 0.86, 0), Vector3.ZERO, 0.04)
	for sx in [-1.0, 1.0]:
		K.cyl(t, 0.06, 0.06, 1.0, wood, Vector3(sx * 0.8, 0.42, 0), Vector3(0, 0, sx * 20.0), 6)
	K.rbox(t, Vector3(1.4, 0.02, 0.8), K.mat(Color("eadcb0"), 0.9), Vector3(0, 0.93, 0), Vector3(0, 6, 0), 0.01)
	K.cyl(t, 0.06, 0.06, 0.9, K.mat(Color("eadcb0"), 0.9), Vector3(0, 0.98, -0.42), Vector3(0, 0, 90), 8)
	K.cyl(t, 0.05, 0.05, 0.12, K.mat(Color("c8302e")), Vector3(0.3, 0.98, 0.1), Vector3.ZERO, 6)
	K.cyl(t, 0.05, 0.05, 0.12, K.mat(Color("2e6f8c")), Vector3(-0.3, 0.98, -0.1), Vector3.ZERO, 6)


static func _signs(level: Node3D) -> void:
	var ps := load("res://scenes/objects/SignPost.tscn") as PackedScene
	if ps == null:
		return
	var signs := [
		[Vector3(-3.2, 0, -0.8), 130.0, "Hill Lane", ["Hill Lane: up to the Brick House.", "Mind the bellows at the top. They blow a proper gale."]],
		[Vector3(6.2, 0, -5.6), -100.0, "Mill Lane", ["Mill Lane: to the Windmill.", "Hint from Pip: the hay cart by the mill is VERY springy."]],
		[Vector3(-3.4, 0, 30.5), 45.0, "Pip's House", ["Pip's Straw House. Please do not huff.", "(Somebody has scrawled 'or puff' underneath.)"]],
		[Vector3(-27.5, 0, -10.0), 160.0, "Birch Grove", ["The Birch Grove. Treehouse straight up.", "Builders' note: the wobbly plank is wobbly ON PURPOSE."]],
	]
	for s in signs:
		var p: Vector3 = s[0]
		p.y = gy(p.x, p.z)
		var n := ps.instantiate() as Node3D
		n.set("board_text", String(s[2]))
		var lines := PackedStringArray()
		for l in s[3]:
			lines.append(String(l))
		n.set("lines", lines)
		n.position = p
		n.rotation_degrees.y = float(s[1])
		level.add_child(n)


static func wolf_sign(level: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(pos.x, gy(pos.x, pos.z), pos.z)
	root.rotation_degrees.y = yaw + 160.0
	level.add_child(root)
	K.cyl(root, 0.06, 0.08, 1.6, K.mat(Color("6e4a2c")), Vector3(0, 0.8, 0), Vector3(0, 0, 6), 6)
	K.rbox(root, Vector3(1.0, 0.6, 0.06), K.mat(Color("ffcf3c"), 0.6), Vector3(0, 1.45, 0), Vector3(0, 0, -5), 0.04)
	var lbl := Label3D.new()
	lbl.text = "PROPERTY OF\nTHE WOLF\nKEEP OFF!"
	lbl.font_size = 34
	lbl.pixel_size = 0.004
	lbl.modulate = Color("7a1f2e")
	lbl.outline_size = 0
	lbl.position = Vector3(0, 1.45, 0.04)
	lbl.rotation_degrees.z = -5.0
	root.add_child(lbl)


static func relay_dressing(level: Node3D, straw: Vector3, stick: Vector3, brick: Vector3) -> void:
	# Pennant pole on the straw ridge and brass bells on the other two ridges (visual only).
	var pole := K.mat(Color("f2ead8"), 0.5)
	var brass := K.mat(Color("c9a04a"), 0.3)
	K.cyl(level, 0.05, 0.05, 2.0, pole, straw + Vector3(1.6, 1.0, 0), Vector3.ZERO, 6)
	K.rbox(level, Vector3(0.9, 0.5, 0.04), K.mat(K.RED_RIBBON), straw + Vector3(2.05, 1.75, 0), Vector3.ZERO, 0.02)
	for p in [stick, brick]:
		K.cyl(level, 0.05, 0.05, 2.2, K.mat(Color("6e4a2c")), p + Vector3(0, 1.1, 1.2), Vector3.ZERO, 6)
		K.cyl(level, 0.05, 0.3, 0.4, brass, p + Vector3(0, 2.0, 1.2), Vector3.ZERO, 12)


static func thistles(level: Node3D, c: Vector3, r: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.x * 100.0 + c.z)
	var stem := K.mat(Color("4f7a3a"), 0.8)
	var head := K.mat(Color("c23a5a"), 0.6)
	var spike := K.mat(Color("ff5a3c"), 0.5)
	for i in 9:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r * 0.85
		var p := Vector3(c.x + cos(a) * d, 0, c.z + sin(a) * d)
		p.y = gy(p.x, p.z)
		var h := rng.randf_range(0.6, 1.0)
		K.cyl(level, 0.04, 0.06, h, stem, p + Vector3(0, h * 0.5, 0), Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8)), 6)
		K.sphere(level, 0.16, head, p + Vector3(0, h + 0.08, 0))
		for k in 4:
			var ka := TAU * k / 4.0
			K.cone(level, 0.05, 0.3, spike, p + Vector3(cos(ka) * 0.15, h - 0.05, sin(ka) * 0.15), Vector3(sin(ka) * 60.0, 0, -cos(ka) * 60.0), 5)


# ------------------------------------------------------------------ scatter and ambience

static func dress(level: Node3D, lv: Dictionary) -> void:
	swayers.clear()
	var root := Node3D.new()
	root.name = "Dressing"
	level.add_child(root)
	var dev := level.get_node_or_null("/root/Dev")
	var skip := String(dev.call("arg", "w1-skip", "")) if dev else ""
	if not "trees" in skip:
		_trees(root)
	if not "grass" in skip:
		_grass(root)
	_hedges(root)
	if not "berm" in skip:
		_berm_dressing(root)
	_haystacks(root)
	_sunflowers(root)
	_fences(root, lv)
	hoses(root, lv)
	if not "backdrop" in skip:
		_backdrop(root)
	if not "ambient" in skip:
		_ambient(root)
	_perf_ranges(root)


## Fix round 1 (QA r1: 76.6 fps mean, 52 fps 1 % low, 3,526 draw calls at the hero spawn): small dressing stops
## casting shadows and fades out past 70 m; trees fade past 120 m. The backdrop is exempt (it is meant to be far).
static func _perf_ranges(root: Node3D) -> void:
	var back := root.get_node_or_null("Backdrop")
	for gi: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if back and back.is_ancestor_of(gi):
			continue
		if gi.visibility_range_end > 0.0:
			continue
		var ab := gi.get_aabb()
		var sz := (ab.size * gi.global_basis.get_scale()).length()
		if sz < 1.6:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gi.visibility_range_end = 70.0
			gi.visibility_range_end_margin = 8.0
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		elif sz < 4.0:
			gi.visibility_range_end = 95.0
			gi.visibility_range_end_margin = 10.0
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		else:
			gi.visibility_range_end = 130.0
			gi.visibility_range_end_margin = 12.0
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func _clear_of_paths(x: float, z: float, margin: float) -> bool:
	return W1Terrain.path_distance(x, z) > margin and W1Terrain.stream_info(x, z)["distance"] > 4.0


static func _trees(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1001
	var keep_out: Array[Vector4] = [
		Vector4(-42, -18, 6.0, 0), Vector4(-38, -28, 7.5, 0), Vector4(-46, -30, 5.0, 0), Vector4(-28, -16, 6.0, 0),
		Vector4(-20, 26, 8.0, 0), Vector4(5, -35, 11.0, 0), Vector4(40, -44, 9.0, 0), Vector4(2, -3, 7.0, 0),
		Vector4(34, 3, 7.0, 0), Vector4(48, 13, 6.0, 0), Vector4(-30, -50, 7.0, 0), Vector4(-55, -4, 5.0, 0),
		Vector4(16, 40, 4.0, 0), Vector4(0, 54, 9.0, 0), Vector4(-6, 10, 6.0, 0), Vector4(32, -26, 5.0, 0),
		Vector4(-36, -7, 4.0, 0),  # fix round 1: the W1-3 mission spawn
	]
	var birches := 0
	var tries := 0
	var placed: Array[Vector2] = []
	# Birch grove polygon (plan Z_birch_grove) plus a few strays along the west edge.
	var poly := PackedVector2Array([Vector2(-58, -42), Vector2(-24, -42), Vector2(-20, -6), Vector2(-30, 0), Vector2(-58, -2)])
	while birches < 34 and tries < 900:
		tries += 1
		var p := Vector2(rng.randf_range(-58, -20), rng.randf_range(-44, 0))
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		if not _ok_spot(p, keep_out, placed, 4.0) or not _clear_of_paths(p.x, p.y, 3.2):
			continue
		if absf(p.y + 31.5) < 3.0 and p.x > -44.0:
			continue  # rope bridge corridor
		if p.distance_to(Vector2(-51.6, -7.6)) < 4.2:
			continue  # finishing pass (W1 QA r1c major 3): a birch trunk stood in the Kick Cleft mouth and blocked P4
		if Geometry2D.is_point_in_polygon(p, PackedVector2Array(HOIST_SIGHT)):
			continue  # R3.6: the Hay Hoist stays visible from the spawn
		var s := rng.randf_range(0.85, 1.3)
		if blocks_cams(Vector3(p.x, gy(p.x, p.y), p.y), s):
			continue
		placed.append(p)
		var t := glb_inst(BIRCH_GLB, root, Vector3(p.x, gy(p.x, p.y) - 0.1, p.y), rng.randf() * 360.0, Vector3(s, s * rng.randf_range(0.9, 1.15), s))
		if t:
			swayers.append(t)
			_trunk_collider(root, Vector3(p.x, gy(p.x, p.y), p.y), 0.3 * s, 5.0)
		birches += 1
	# Orchard: apple trees on a 7 m grid with jitter (rect x 20-48, z 26-50), clear of the Orchard Track.
	for gx in range(22, 49, 7):
		for gz in range(27, 51, 7):
			var p2 := Vector2(gx + rng.randf_range(-1.5, 1.5), gz + rng.randf_range(-1.5, 1.5))
			if not _ok_spot(p2, keep_out, placed, 5.0) or not _clear_of_paths(p2.x, p2.y, 3.5):
				continue
			var s2 := rng.randf_range(0.9, 1.15)
			if blocks_cams(Vector3(p2.x, gy(p2.x, p2.y), p2.y), s2):
				continue
			placed.append(p2)
			var t2 := glb_inst(APPLE_GLB, root, Vector3(p2.x, gy(p2.x, p2.y) - 0.05, p2.y), rng.randf() * 360.0, Vector3.ONE * s2)
			if t2:
				swayers.append(t2)
				_trunk_collider(root, Vector3(p2.x, gy(p2.x, p2.y), p2.y), 0.35 * s2, 2.5)
	# Lone trees that frame the meadow and the hillsides.
	var lone := [Vector2(-38, 40), Vector2(-46, 30), Vector2(22, 18), Vector2(-14, -22), Vector2(20, -12), Vector2(50, -12), Vector2(-50, 48), Vector2(46, 50), Vector2(-10, 50), Vector2(12, 52), Vector2(26, -48), Vector2(-4, -50)]
	for i in lone.size():
		var p3: Vector2 = lone[i]
		if not _clear_of_paths(p3.x, p3.y, 3.0) or Geometry2D.is_point_in_polygon(p3, PackedVector2Array(HOIST_SIGHT)):
			continue
		var path := APPLE_GLB if i % 3 == 0 else BIRCH_GLB
		var s3 := rng.randf_range(1.0, 1.35)
		if blocks_cams(Vector3(p3.x, gy(p3.x, p3.y), p3.y), s3):
			continue
		var t3 := glb_inst(path, root, Vector3(p3.x, gy(p3.x, p3.y) - 0.1, p3.y), rng.randf() * 360.0, Vector3.ONE * s3)
		if t3:
			swayers.append(t3)
			_trunk_collider(root, Vector3(p3.x, gy(p3.x, p3.y), p3.y), 0.32 * s3, 4.0)
	fx(root, "FallingLeaves", Vector3(-38, 9, -24))
	fx(root, "FallingLeaves", Vector3(34, 5, 38))



## Fix round 1 (critics r1): the finale cameras must see the whole pen. A tree is rejected when any of its sample
## points (trunk, canopy) projects into one of these frames nearer than the framed subject plus a margin.
## [pos, look_at, vertical fov, subject depth]
const CAM_CLEAR := [
	[Vector3(-43.0, 19.0, -44.0), Vector3(-43.0, 0.3, -48.5), 55.0, 26.0],   # CamHint_hay_shuffle (overhead)
	[Vector3(-52.5, 9.0, -41.5), Vector3(-42.5, 1.2, -48.5), 55.0, 22.0],    # StoryCam_H2_hayyard
	[Vector3(-33.0, 8.0, -58.5), Vector3(-43.5, 1.5, -46.5), 50.0, 22.0],    # StoryCam_H_hayyard
	[Vector3(-40.0, 8.0, 0.0), Vector3(-38.0, 6.0, -17.0), 55.0, 20.0],      # StoryCam_I_sticks
	[Vector3(30.0, 14.5, -30.0), Vector3(34.0, 14.0, -36.0), 45.0, 10.0],    # StoryCam_G2_cameo
	[Vector3(21.0, 17.0, -17.0), Vector3(20.0, 15.0, -36.0), 60.0, 24.0],    # StoryCam_J2_huff
	[Vector3(-1.5, 3.6, 55.5), Vector3(31.0, 8.0, 2.0), 14.0, 64.0],         # intro sightline to the Tor cameo
	[Vector3(-6.0, 5.0, 40.0), Vector3(-20.0, 3.0, 26.0), 55.0, 20.0],       # StoryCam_E_blowdown
]


static func blocks_cams(base: Vector3, s: float) -> bool:
	var pts: Array[Vector3] = []
	for h in [1.5, 4.0, 6.5, 9.0]:
		for off in [Vector3.ZERO, Vector3(2.6, 0, 0), Vector3(-2.6, 0, 0), Vector3(0, 0, 2.6), Vector3(0, 0, -2.6)]:
			pts.append(base + (Vector3(0, h, 0) + off) * s)
	for c in CAM_CLEAR:
		var cp: Vector3 = c[0]
		var xf := Transform3D(Basis.looking_at((c[1] as Vector3) - cp, Vector3.UP), cp).affine_inverse()
		var tv := tan(deg_to_rad(float(c[2]) * 0.5)) * 1.08
		var th := tv * 1.78
		for p in pts:
			var q := xf * p
			var depth := -q.z
			if depth < 0.3 or depth > float(c[3]):
				continue
			if absf(q.x / depth) < th and absf(q.y / depth) < tv:
				return true
	return false


static func _ok_spot(p: Vector2, keep_out: Array[Vector4], placed: Array[Vector2], spacing: float) -> bool:
	for k in keep_out:
		if p.distance_to(Vector2(k.x, k.y)) < k.z:
			return false
	for q in placed:
		if p.distance_to(q) < spacing:
			return false
	return true


static func _trunk_collider(root: Node3D, base: Vector3, r: float, h: float) -> void:
	var b := K.body(root, "Trunk", base)
	# Fix round 2 (feel r1: thin dressing trunks popped the camera arm on the W1-3 approach): Mak still bumps them
	# (layer 3 is in his mask), the spring arm (layer 1 only) does not.
	b.collision_layer = 4
	K.shape_cyl(b, r, h, Vector3(0, h * 0.5, 0))


static func _grass(root: Node3D) -> void:
	var tuft := load("res://assets/shaders/materials/mesh_grass_tuft.tres") as Mesh
	var gmat := load("res://assets/shaders/materials/foliage_grass.tres") as Material
	var fmat := load("res://assets/shaders/materials/foliage_flowers.tres") as Material
	var flowers: Array[Mesh] = []
	for c in ["pink", "white", "yellow"]:
		var fm := load("res://assets/shaders/materials/mesh_flower_%s.tres" % c) as Mesh
		if fm:
			flowers.append(fm)
	if tuft == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var cell := 24.0
	var cx := -60.0
	while cx < 60.0:
		var cz := -60.0
		while cz < 60.0:
			var grass_xf: Array[Transform3D] = []
			var flower_xf: Array = [[], [], []]
			var reed_xf: Array[Transform3D] = []
			for i in 1100:
				var x := cx + rng.randf() * cell
				var z := cz + rng.randf() * cell
				var m := W1Terrain.mask(x, z)
				var y := gy(x, z)
				if m.r > 0.25 or m.a > 0.45 or y < -0.3:
					continue
				# Stream distance from the baked wet mask (B = 1 inside 3 m of the centreline, fading to 0 by 5.5 m).
				var wet := m.b
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, 0.7, 1.0) * rng.randf_range(0.7, 1.25))
				if wet > 0.3 and wet < 0.995 and rng.randf() < 0.7:
					reed_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.1, rng.randf_range(2.2, 3.2), 1.1)), Vector3(x, y - 0.05, z)))
					continue
				if wet > 0.97:
					continue
				var meadow := z > 10.0 and absf(x) < 56.0
				if flowers.size() > 0 and meadow and rng.randf() < 0.22:
					var k := rng.randi() % flowers.size()
					(flower_xf[k] as Array).append(Transform3D(basis.scaled(Vector3.ONE * 1.3), Vector3(x, y - 0.02, z)))
				elif rng.randf() < 0.75:
					grass_xf.append(Transform3D(basis, Vector3(x, y - 0.04, z)))
			_mm(root, tuft, gmat, grass_xf, "Grass")
			for k in flowers.size():
				var arr: Array[Transform3D] = []
				for t in flower_xf[k]:
					arr.append(t)
				_mm(root, flowers[k], fmat, arr, "Flowers")
			_mm(root, tuft, _reed_mat(gmat), reed_xf, "Reeds")
			cz += cell
		cx += cell


static var _reed: Material


static func _reed_mat(base: Material) -> Material:
	if _reed == null and base != null:
		_reed = base.duplicate()
		if _reed is ShaderMaterial:
			(_reed as ShaderMaterial).set_shader_parameter("base_color", Color("3f6f2f"))
			(_reed as ShaderMaterial).set_shader_parameter("tip_color", Color("b7c46a"))
	return _reed


static func _mm(root: Node3D, mesh: Mesh, mat: Material, xf: Array[Transform3D], nm: String) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 75.0
	mmi.visibility_range_end_margin = 10.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mmi)


static func _hedges(root: Node3D) -> void:
	# Rounded hedgerow boxes along the border band, with a few gaps showing the painted backdrop to the north-east.
	var hedge_xf: Array[Transform3D] = []
	var hedge_col: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var b := K.body(root, "Hedgerows")
	for side in 4:
		var t := -58.0
		while t < 58.0:
			var len := rng.randf_range(4.0, 6.5)
			var mid := t + len * 0.5
			var p := Vector3.ZERO
			var size := Vector3(len, 2.6, 2.4)
			match side:
				0:
					p = Vector3(mid, 0, -56.5)
				1:
					p = Vector3(mid, 0, 57.5)
					if absf(mid) < 6.0:
						t += len
						continue
				2:
					p = Vector3(-56.5, 0, mid)
					size = Vector3(2.4, 2.6, len)
				3:
					p = Vector3(56.5, 0, mid)
					size = Vector3(2.4, 2.6, len)
			if side == 0 and mid > 34.0:
				t += len
				continue
			if side == 2 and absf(mid - 20.0) < 3.4:
				t += len
				continue  # the five-bar gate (fix round 2)
			p.y = gy(p.x, p.z)
			# Fix round 2 (visual r1: straight pool-noodle boxes): each segment is 3-5 overlapping squashed leaf puffs with
			# height noise, darker at the base (one MultiMesh for the whole border, below).
			var n_puffs := 3 + rng.randi() % 3
			var along_x := size.x > size.z
			for k in n_puffs:
				var f := (k + 0.5) / n_puffs - 0.5
				var off := Vector3(f * size.x, 0, rng.randf_range(-0.25, 0.25)) if along_x else Vector3(rng.randf_range(-0.25, 0.25), 0, f * size.z)
				var ph := rng.randf_range(2.3, 2.9)
				var pw := maxf(size.x, size.z) / n_puffs * rng.randf_range(1.35, 1.7)
				var sc := Vector3(pw, ph, 2.5) if along_x else Vector3(2.5, ph, pw)
				hedge_xf.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)).scaled(sc), p + off + Vector3(0, ph * 0.42, 0)))
				var gcol := Color("5aa23c") if rng.randf() < 0.6 else Color("4f9a37")
				hedge_col.append(gcol.lerp(Color("86c04a"), rng.randf_range(0.0, 0.25)))
			K.shape_box(b, size, p + Vector3(0, 1.3, 0))
			t += len - 0.4
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 14
	puff.rings = 7
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = puff
	mm.instance_count = hedge_xf.size()
	for i in hedge_xf.size():
		mm.set_instance_transform(i, hedge_xf[i])
		mm.set_instance_color(i, hedge_col[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "HedgePuffs"
	mmi.multimesh = mm
	var hm := StandardMaterial3D.new()
	hm.vertex_color_use_as_albedo = true
	hm.roughness = 0.9
	hm.rim_enabled = true
	hm.rim = 0.2
	mmi.material_override = hm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Border-wide MultiMesh: its AABB centre is the world centre, so a distance fade would dither the whole hedge.
	mmi.visibility_range_end = 600.0
	root.add_child(mmi)
	_gate_and_postbox(root)


## R3.12 berm dressing: a five-bar gate with a stile in the west hedge, and a red post box at the spawn end.
static func _gate_and_postbox(root: Node3D) -> void:
	var wood := K.tex_mat("wood_planks", Color(0.95, 0.85, 0.7), 0.6)
	var post := K.mat(Color("6e4a2c"), 0.85)
	var g := Node3D.new()
	g.name = "FiveBarGate"
	root.add_child(g)
	g.position = Vector3(-55.2, gy(-55.2, 20.0), 20.0)
	g.rotation_degrees.y = 90.0
	for x in [-1.6, 1.6]:
		K.cyl(g, 0.11, 0.13, 1.6, post, Vector3(x, 0.8, 0), Vector3.ZERO, 8)
	for k in 5:
		K.rbox(g, Vector3(3.1, 0.11, 0.07), wood, Vector3(0, 0.3 + k * 0.24, 0), Vector3.ZERO, 0.02)
	var gb := K.body(g, "GateBody")
	K.shape_box(gb, Vector3(7.0, 2.6, 0.4), Vector3(0, 1.3, 0))
	var brace := K.rbox(g, Vector3(3.4, 0.11, 0.07), wood, Vector3(0, 0.78, 0.02), Vector3(0, 0, 18.0), 0.02)
	brace.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Stile: two steps over the hedge beside the gate.
	for k in 2:
		K.rbox(g, Vector3(0.8, 0.08, 0.3), wood, Vector3(2.4, 0.35 + k * 0.4, 0.3 - k * 0.3), Vector3.ZERO, 0.02)
		K.cyl(g, 0.05, 0.05, 0.4 + k * 0.4, post, Vector3(2.05, (0.4 + k * 0.4) * 0.5, 0.3 - k * 0.3), Vector3.ZERO, 6)
	var pb := Node3D.new()
	pb.name = "PostBox"
	root.add_child(pb)
	pb.position = Vector3(9.5, gy(9.5, 53.5), 53.5)
	pb.rotation_degrees.y = 200.0
	var red := K.mat(Color("c8302e"), 0.45)
	K.cyl(pb, 0.32, 0.34, 1.25, red, Vector3(0, 0.62, 0), Vector3.ZERO, 18)
	K.sphere(pb, 0.33, red, Vector3(0, 1.25, 0), Vector3(1, 0.55, 1))
	K.cyl(pb, 0.36, 0.38, 0.1, K.mat(Color("2b2220"), 0.6), Vector3(0, 0.05, 0), Vector3.ZERO, 18)
	K.rbox(pb, Vector3(0.28, 0.05, 0.06), K.mat(Color("2b2220"), 0.6), Vector3(0, 1.0, 0.31), Vector3.ZERO, 0.01)
	K.rbox(pb, Vector3(0.22, 0.14, 0.03), K.mat(Color("f3e6c8"), 0.8), Vector3(0, 0.78, 0.33), Vector3.ZERO, 0.01)
	var pbb := K.body(root, "PostBoxBody", pb.position)
	K.shape_cyl(pbb, 0.34, 1.3, Vector3(0, 0.65, 0))


## R3.12 Z_berm_dressing (builder 06:35): a dry-stone wall at the hedge foot, generated apple and birch trees on the berm
## crest every 12-16 m, and three groups of straw skep beehives. Outside the playable square, so no collision.
static func _berm_dressing(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 512
	var holder := Node3D.new()
	holder.name = "BermDressing"
	root.add_child(holder)
	for side in 4:
		var t := -57.0 + rng.randf_range(0.0, 6.0)
		while t < 57.0:
			var p2 := Vector2.ZERO
			match side:
				0: p2 = Vector2(t, -59.2)
				1: p2 = Vector2(t, 59.6)
				2: p2 = Vector2(-59.2, t)
				3: p2 = Vector2(59.2, t)
			# Keep the north-east gap (sail-ride background) and the south gate gap open.
			if (side == 0 and t > 34.0) or (side == 1 and absf(t) < 7.0):
				t += 6.0
				continue
			var path := APPLE_GLB if rng.randf() < 0.45 else BIRCH_GLB
			var sc := rng.randf_range(1.1, 1.5)
			if blocks_cams(Vector3(p2.x, gy(p2.x, p2.y), p2.y), sc):
				t += rng.randf_range(12.0, 16.0)
				continue
			var tr := glb_inst(path, holder, Vector3(p2.x, gy(p2.x, p2.y) - 0.15, p2.y), rng.randf() * 360.0, Vector3(sc, sc * rng.randf_range(0.95, 1.15), sc))
			if tr:
				swayers.append(tr)
			t += rng.randf_range(12.0, 16.0)
	# Dry-stone wall: rounded stones in two courses along the inner foot of the hedge line (x/z = +-55), with gaps.
	# One MultiMesh (the level is CPU-bound by node count).
	var xf: Array[Transform3D] = []
	for side in 4:
		var u := -54.0
		while u < 54.0:
			if (side == 0 and u > 34.0) or (side == 1 and absf(u) < 7.0) or rng.randf() < 0.08:
				u += 3.0
				continue
			for course in 2:
				var off := u + (0.35 if course == 1 else 0.0)
				var q := Vector2(off, -55.0) if side == 0 else (Vector2(off, 55.6) if side == 1 else (Vector2(-55.0, off) if side == 2 else Vector2(55.0, off)))
				var sz := Vector3(rng.randf_range(0.66, 0.9), rng.randf_range(0.36, 0.46), rng.randf_range(0.48, 0.62))
				if side >= 2:
					sz = Vector3(sz.z, sz.y, sz.x)
				var y := gy(q.x, q.y) + 0.16 + course * 0.34
				var bas := Basis.from_euler(Vector3(deg_to_rad(rng.randf_range(-6, 6)), deg_to_rad(rng.randf_range(-12, 12)), deg_to_rad(rng.randf_range(-6, 6)))).scaled(sz)
				xf.append(Transform3D(bas, Vector3(q.x, y, q.y)))
			u += 0.72
	var stone_mesh := SphereMesh.new()
	stone_mesh.radius = 0.5
	stone_mesh.height = 1.0
	stone_mesh.radial_segments = 10
	stone_mesh.rings = 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = stone_mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		var v := rng.randf_range(0.82, 1.08)
		mm.set_instance_color(i, Color(v, v * 0.98, v * 0.92))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "DryStoneWall"
	mmi.visibility_range_end = 600.0
	mmi.multimesh = mm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("b3ab98")
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 0.9
	mmi.material_override = sm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mmi)
	# Three groups of straw skep beehives on little plank stands, with a buzz of bees (butterfly FX stand-in for bees).
	var straw := K.tex_mat("straw_thatch", Color(1.15, 1.0, 0.72), 0.5)
	var plank := K.tex_mat("wood_planks", Color(1.0, 0.84, 0.62), 0.6)
	for g in SKEPS:
		for k in 3:
			var off := Vector2(k - 1.0, 0.0) * 1.3 if absf(g.y) > 50.0 else Vector2(0.0, k - 1.0) * 1.3
			var bp := Vector3(g.x + off.x, gy(g.x + off.x, g.y + off.y), g.y + off.y)
			K.rbox(holder, Vector3(1.0, 0.12, 1.0), plank, bp + Vector3(0, 0.5, 0), Vector3.ZERO, 0.03)
			for lx in [-0.35, 0.35]:
				K.cyl(holder, 0.05, 0.05, 0.5, plank, bp + Vector3(lx, 0.25, 0), Vector3.ZERO, 6)
			for ring in 4:
				var r := 0.44 - ring * 0.09
				K.torus(holder, r - 0.09, r + 0.05, straw, bp + Vector3(0, 0.66 + ring * 0.15, 0))
			K.sphere(holder, 0.17, straw, bp + Vector3(0, 1.2, 0))
			K.sphere(holder, 0.07, K.mat(Color("2b2220")), bp + Vector3(0, 0.66, 0.4) if absf(g.y) > 50.0 else bp + Vector3(0.4 * -signf(g.x), 0.66, 0))
		# (Fix round 2: the butterfly stand-in for bees is gone; W1Life circles real bee models round each group.)


static func _haystacks(root: Node3D) -> void:
	var hay := K.tex_mat("straw_thatch", Color(1.1, 1.2, 1.7), 0.5)
	# (-34, 32) is WW3's hiding stack, built by W1Life (fix round 2).
	for p2 in [Vector2(-28, 23), Vector2(-12, 44), Vector2(36, -20), Vector2(44, -26)]:
		var p := Vector3(p2.x, gy(p2.x, p2.y), p2.y)
		var b := K.body(root, "Haystack", p)
		K.shape_cyl(b, 1.15, 2.0, Vector3(0, 1.0, 0))
		K.sphere(b, 1.25, hay, Vector3(0, 0.95, 0), Vector3(1.0, 1.05, 1.0))
		K.cone(b, 1.0, 1.15, hay, Vector3(0, 2.25, 0), Vector3.ZERO, 14)
		K.torus(b, 1.08, 1.2, K.mat(Color("8a6a3a"), 0.9), Vector3(0, 1.45, 0))
		K.cyl(b, 0.04, 0.04, 1.8, K.mat(Color("6e4a2c")), Vector3(0.6, 2.1, 0.3), Vector3(20, 0, -25), 6)
	var bale_ps: PackedScene = load(HAY_GLB) if ResourceLoader.exists(HAY_GLB) else null
	if bale_ps:
		for q in [Vector3(-8, 0, 40), Vector3(-9.2, 0, 40.5), Vector3(-8.6, 1.1, 40.2), Vector3(30, 0, -18), Vector3(24, 0, 28), Vector3(-36, 0, 12), Vector3(46, 0, -18)]:
			var p3 := Vector3(q.x, gy(q.x, q.z) + q.y, q.z)
			var bb := K.body(root, "Bale", p3, float(int(q.x * 7.0) % 50))
			K.shape_box(bb, Vector3(1.6, 1.1, 1.2), Vector3(0, 0.55, 0))
			var bi := bale_ps.instantiate() as Node3D
			bi.position.y = 0.06
			bb.add_child(bi)


static func _sunflowers(root: Node3D) -> void:
	# Sunflower rows (rect x 6-22, z 30-48) with an alley along acorn line A16; MultiMesh per part.
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var stems: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var centres: Array[Transform3D] = []
	var leaves: Array[Transform3D] = []
	var a16a := Vector2(10, 34)
	var a16b := Vector2(20, 46)
	# Finishing pass (D034 B4, "sunflower wall"): the 160 even scatter became four planted clumps with open grass
	# between them, so the field reads as a garden and the A16 alley stays visible.
	var clumps: Array[Vector2] = [Vector2(8.0, 32.5), Vector2(19.5, 36.0), Vector2(9.5, 45.0), Vector2(20.0, 46.5)]
	for i in 160:
		var p := Vector2(rng.randf_range(6, 22), rng.randf_range(30, 48))
		var near_clump := false
		for c in clumps:
			if p.distance_to(c) < 2.6:
				near_clump = true
		if not near_clump:
			continue
		if Geometry2D.get_closest_point_to_segment(p, a16a, a16b).distance_to(p) < 1.5:
			continue
		if p.distance_to(Vector2(16, 40)) < 2.5 or p.distance_to(Vector2(17.4, 41.4)) < 1.6:
			continue
		if W1Terrain.path_distance(p.x, p.y) < 2.5:
			continue
		var y := gy(p.x, p.y)
		# Fix round 2 (visual r1: lollipops, a straight cylinder and a flat disc, all one height): a two-part stem with a
		# 6-10 degree droop, two leaves, a petal ring round a domed dark centre; heights vary 20 %, heads yaw 25 degrees.
		var h := rng.randf_range(1.55, 2.25)
		var yaw := deg_to_rad(-140.0 + rng.randf_range(-25.0, 25.0))
		var droop := deg_to_rad(rng.randf_range(6.0, 10.0))
		var lower_h := h * 0.62
		var base := Vector3(p.x, y, p.y)
		stems.append(Transform3D(Basis().scaled(Vector3(1, lower_h, 1)), base + Vector3(0, lower_h * 0.5, 0)))
		var bend := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -droop)
		var upper_h := h - lower_h
		var knee := base + Vector3(0, lower_h, 0)
		stems.append(Transform3D(bend.scaled(Vector3(0.85, upper_h, 0.85)), knee + bend.y * upper_h * 0.5))
		var top := knee + bend.y * upper_h
		for lk in 2:
			var la := yaw + (PI * 0.5 if lk == 0 else -PI * 0.5) + rng.randf_range(-0.3, 0.3)
			var lb := Basis(Vector3.UP, la) * Basis(Vector3.RIGHT, deg_to_rad(-35.0))
			leaves.append(Transform3D(lb.scaled(Vector3(0.22, 0.04, 0.38)), base + Vector3(0, lower_h * (0.45 + 0.25 * lk), 0) + lb.z * 0.16))
		var face := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-70.0 + rng.randf_range(-10.0, 10.0)) - droop)
		heads.append(Transform3D(face, top))
		centres.append(Transform3D(face, top + face.y * 0.05))
	var stem_m := CylinderMesh.new()
	stem_m.top_radius = 0.04
	stem_m.bottom_radius = 0.06
	stem_m.height = 1.0
	stem_m.radial_segments = 6
	var leaf_m := SphereMesh.new()
	leaf_m.radius = 0.5
	leaf_m.height = 1.0
	leaf_m.radial_segments = 8
	leaf_m.rings = 4
	var centre := SphereMesh.new()
	centre.radius = 0.22
	centre.height = 0.2
	centre.radial_segments = 12
	centre.rings = 6
	var petal := CylinderMesh.new()
	petal.top_radius = 0.4
	petal.bottom_radius = 0.46
	petal.height = 0.05
	petal.radial_segments = 16
	_mm(root, stem_m, K.mat(Color("4f8f2f"), 0.8), stems, "SunflowerStems")
	_mm(root, leaf_m, K.mat(Color("5aa23c"), 0.8), leaves, "SunflowerLeaves")
	_mm(root, petal, K.mat(Color("ffcc2e"), 0.6), heads, "SunflowerPetals")
	_mm(root, centre, K.mat(Color("6b4430"), 0.7), centres, "SunflowerCentres")


static func _ambient(root: Node3D) -> void:
	for p in [Vector3(-14, 1.4, 40), Vector3(10, 1.4, 22), Vector3(28, 1.4, 38), Vector3(-36, 5.4, -10), Vector3(2, 13.4, -26)]:
		fx(root, "Butterflies", p)
	fx(root, "ChimneySmoke", Vector3(-41.2, 9.4, -19.0))
	fx(root, "ChimneySmoke", Vector3(1.6, 22.4, -37.6))
	fx(root, "WaterfallFoam", Vector3(4.2, -0.3, 13.0))


## Post-and-rail fences along lane edges (MultiMesh visuals, thin box colliders). side +1 = right of travel.
static func _fences(root: Node3D, lv: Dictionary) -> void:
	var runs := [
		["page_lane", 1.0, 0.0, 0.42, [[0.27, 0.33]]],
		["page_lane", -1.0, 0.04, 0.2, []],
		["hill_lane", 1.0, 0.2, 0.95, []],
		["mill_lane", -1.0, 0.55, 0.98, []],
	]
	var paths: Dictionary = lv["_derived"]["path_samples"]
	var widths := {}
	for pth in lv["splines"]["paths"]:
		widths[String(pth["id"])] = float(pth["width"])
	var posts: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	var b := K.body(root, "Fences")
	for r in runs:
		var pid: String = r[0]
		if not paths.has(pid):
			continue
		var pts: Array = paths[pid]
		var side: float = r[1]
		var off: float = widths.get(pid, 3.0) * 0.5 + 0.9
		# Resample the lane at 2.4 m spacing.
		var poly: Array[Vector3] = []
		for q in pts:
			poly.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
		var total := 0.0
		for i in range(1, poly.size()):
			total += poly[i].distance_to(poly[i - 1])
		var gaps: Array = r[4]
		var s := float(r[2]) * total
		var prev := Vector3.INF
		while s < float(r[3]) * total:
			var t := s / total
			var in_gap := false
			for gp in gaps:
				if t > float(gp[0]) and t < float(gp[1]):
					in_gap = true
			var a := _along(poly, s)
			var a2 := _along(poly, s + 0.5)
			var tan := (a2 - a)
			tan.y = 0.0
			tan = tan.normalized()
			var nrm := Vector3(-tan.z, 0, tan.x) * side
			var p := a + nrm * off
			p.y = gy(p.x, p.z)
			if in_gap or W1Terrain.stream_info(p.x, p.z)["distance"] < 4.5:
				prev = Vector3.INF
				s += 2.4
				continue
			posts.append(Transform3D(Basis(), p + Vector3(0, 0.55, 0)))
			if prev != Vector3.INF:
				var mid := (prev + p) * 0.5
				var d := p - prev
				var basis := Basis.looking_at(d.normalized(), Vector3.UP)
				for hgt in [0.45, 0.85]:
					rails.append(Transform3D(basis.scaled(Vector3(1, 1, d.length())), mid + Vector3(0, hgt, 0)))
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.15, 1.0, d.length())
				cs.shape = bs
				cs.transform = Transform3D(basis, mid + Vector3(0, 0.5, 0))
				b.add_child(cs)
			prev = p
			s += 2.4
	var post_m := CylinderMesh.new()
	post_m.top_radius = 0.07
	post_m.bottom_radius = 0.09
	post_m.height = 1.1
	post_m.radial_segments = 6
	var rail_m := BoxMesh.new()
	rail_m.size = Vector3(0.08, 0.1, 1.0)
	var wood := K.mat(Color("9a6a40"), 0.85)
	_mm(root, post_m, wood, posts, "FencePosts")
	_mm(root, rail_m, K.mat(Color("b07a4f"), 0.85), rails, "FenceRails")
	for n in root.get_children():
		if n is MultiMeshInstance3D and String(n.name).begins_with("Fence"):
			(n as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			(n as MultiMeshInstance3D).visibility_range_end = 0.0


static func _along(poly: Array[Vector3], s: float) -> Vector3:
	var acc := 0.0
	for i in range(1, poly.size()):
		var l := poly[i].distance_to(poly[i - 1])
		if acc + l >= s:
			return poly[i - 1].lerp(poly[i], (s - acc) / maxf(l, 1e-4))
		acc += l
	return poly[poly.size() - 1]


## Rolling painted hills and tree lines beyond the hedgerows, so every horizon reads as countryside.
static func _backdrop(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var holder := Node3D.new()
	holder.name = "Backdrop"
	root.add_child(holder)
	var greens := [Color("8cc85a"), Color("79b64c"), Color("9fd16a"), Color("6aa843")]
	var pw_shader := load("res://assets/environment/w1/w1_patchwork.gdshader") as Shader
	var trees := [Color("5f9e3f"), Color("4f8f37"), Color("74b04a")]
	# Builder 06:25: a smooth 48x24 sphere for the hills; the shared 20x10 sphere faceted visibly when a hill sits 20 m from
	# StoryCam_B and the west rim.
	var hill_mesh := SphereMesh.new()
	hill_mesh.radius = 1.0
	hill_mesh.height = 2.0
	hill_mesh.radial_segments = 48
	hill_mesh.rings = 24
	for ring in 3:
		var radius := 95.0 + ring * 45.0
		var count := 16 + ring * 4
		for i in count:
			var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / count
			var rx := rng.randf_range(28.0, 46.0) + ring * 10.0
			var ry := rng.randf_range(9.0, 20.0) + ring * 6.0
			var m: Material = K.mat(greens[(i + ring) % greens.size()], 0.95, 0.0)
			var rz := rx * rng.randf_range(0.6, 0.9)
			# Fix round 1: patchwork fields with hedgerow seams; 30 % of the hills are long, low downs.
			var downs := rng.randf() < 0.3
			if downs:
				ry *= 0.5
				rx *= 1.35
			if pw_shader:
				var pm := ShaderMaterial.new()
				pm.shader = pw_shader
				pm.set_shader_parameter("seed", float(i * 7 + ring * 31))
				pm.set_shader_parameter("angle", rng.randf_range(-0.8, 0.8))
				pm.set_shader_parameter("cell", 0.2 if ring == 0 else 0.15)
				var fade := 1.0 - ring * 0.08
				pm.set_shader_parameter("c1", Color(0.55, 0.78, 0.35) * fade)
				pm.set_shader_parameter("c2", Color(0.72, 0.82, 0.38) * fade)
				pm.set_shader_parameter("c3", Color(0.47, 0.70, 0.33) * fade)
				pm.set_shader_parameter("c4", (Color(0.80, 0.74, 0.86) if ring == 2 and i % 3 == 0 else Color(0.83, 0.80, 0.48)) * fade)
				m = pm
			# Builder 06:30: keep every hill outside the play square (+-60 plus a 6 m margin) along its own bearing. At the
			# corners a ring-0 hill reached 49 m from the centre and stood as a flat green wall behind the hay yard (W1-7),
			# beside StoryCam_B and on the east edge of StoryCam_A.
			var edge := 66.0 / maxf(absf(cos(a)), absf(sin(a)))
			var rr := maxf(radius, edge + maxf(rx, rz) * 0.92)
			var c := Vector3(cos(a) * rr, -2.0 - ring * 2.0, sin(a) * rr)
			var hill := K.add(holder, hill_mesh, m, c, Vector3.ZERO, Vector3(rx, ry, rz))
			hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hill.rotation.y = a
			# Tree clumps along the crest of the nearer hills.
			if ring < 2 and i % 2 == 0:
				# Half as many crest trees, grouped in a clump of three.
				var ta := a + rng.randf_range(-0.1, 0.1)
				var tr := rr - rng.randf_range(0.0, rx * 0.3)
				var base := Vector3(cos(ta) * tr, c.y + ry * rng.randf_range(0.6, 0.85), sin(ta) * tr)
				for k in 3:
					var sz := rng.randf_range(3.0, 5.5) + ring * 2.0
					var tp := base + Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0)) * sz * 1.3
					var tm := K.sphere(holder, 1.0, K.mat(trees[k % trees.size()], 0.95, 0.0), tp, Vector3(sz, sz * 1.2, sz))
					tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# R3.12 W2 tease: a twisting beanstalk rising into a cloud cap far beyond the windmill ridge. Builder 06:20: the
	# generated W2 beanstalk segment (four stacked, yawed 90 deg apart) replaces the stepped cylinder stack, which read
	# as a zigzag of boxes in StoryCam B/C.
	var bean_path := "res://assets/props/w2/beanstalk_segment/beanstalk_segment.glb"
	if ResourceLoader.exists(bean_path):
		for i in 4:
			var sc := 1.15 - i * 0.12
			var seg_i := glb_inst(bean_path, holder, Vector3(64.0, 2.0 + i * 10.2, -92.0), 37.0 + i * 90.0, Vector3(sc, 1.08, sc))
			if seg_i:
				for mi in seg_i.find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var bean := K.mat(Color("6fb24a"), 0.9, 0.0)
		for i in 22:
			var t := float(i) / 21.0
			var bp := Vector3(64.0 + sin(t * 9.0) * 2.4, 2.0 + t * 42.0, -92.0 + cos(t * 9.0) * 2.4)
			var seg := K.cyl(holder, 1.1 - t * 0.5, 1.3 - t * 0.5, 2.6, bean, bp, Vector3(sin(t * 9.0) * 18.0, 0, cos(t * 9.0) * 18.0), 8)
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fix round 2 (visual r1: five opaque white balls read as a cotton-ball lollipop): a flattened cumulus of a dozen
	# overlapping puffs with a lavender underside, drifting and bobbing; the stalk top fades into it.
	var cap := Node3D.new()
	cap.name = "BeanstalkCloudCap"
	holder.add_child(cap)
	cap.position = Vector3(64.0, 44.5, -92.0)
	var c_top := K.mat(Color("fbf8ff"), 0.95, 0.0)
	var c_under := K.mat(Color("b9a6e8"), 0.95, 0.0)
	var crng := RandomNumberGenerator.new()
	crng.seed = 4401
	for k in 12:
		var a := TAU * k / 12.0 + crng.randf_range(-0.2, 0.2)
		var rr := crng.randf_range(2.0, 7.5) if k > 0 else 0.0
		var sz := crng.randf_range(3.2, 5.2)
		var pm := K.sphere(cap, 1.0, c_top, Vector3(cos(a) * rr, crng.randf_range(0.0, 1.6), sin(a) * rr * 0.6), Vector3(sz, sz * 0.45, sz * 0.8))
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var und := K.sphere(cap, 1.0, c_under, Vector3(0, -0.9, 0), Vector3(9.5, 1.4, 5.0))
	und.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ctw := cap.create_tween().set_loops()
	ctw.tween_property(cap, "position", Vector3(66.5, 45.3, -92.0), 9.0).set_trans(Tween.TRANS_SINE)
	ctw.tween_property(cap, "position", Vector3(62.5, 44.2, -92.0), 9.0).set_trans(Tween.TRANS_SINE)
	_cards(holder)
	# A far windmill and a church spire silhouette for storybook depth.
	var far := K.mat(Color("a9c7a0"), 0.95, 0.0)
	K.cyl(holder, 2.0, 3.0, 12.0, far, Vector3(-120, 10, -95), Vector3.ZERO, 8)
	K.cone(holder, 2.6, 4.0, far, Vector3(-120, 18, -95), Vector3.ZERO, 8)
	K.cyl(holder, 1.6, 2.4, 9.0, far, Vector3(130, 12, -40), Vector3.ZERO, 6)
	K.cone(holder, 1.6, 9.0, far, Vector3(130, 21, -40), Vector3.ZERO, 6)


## R3.12 far_hills_backdrop (fix round 2, visual r1: rows of identical sphere hills): three pop-up card layers along the
## north horizon, each a flat painted cut-out with a cream paper edge, behind the hedge line and outside the play square.
## L1 (r 76): patchwork fields, a dry-stone wall and a hedgerow with trees (tops 12-15).
## L2 (r 80): rolling hills with a village, a church spire and a distant windmill whose sails turn (tops 16-24).
## L3 (r 86): lavender downs. Cloud cards on wires drift in front of L3. One mesh per layer (vertex colours, unshaded).
static func _cards(holder: Node3D) -> void:
	var root := Node3D.new()
	root.name = "PopUpCards"
	holder.add_child(root)
	var x0 := -140.0
	var x1 := 140.0
	var paper := Color("f3ebda")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3131
	# L3: lavender downs.
	var st3 := _card_st()
	var downs := _hill_poly(x0, x1, -4.0, func(x: float) -> float: return 22.5 + 3.2 * sin(x * 0.021 + 2.0) + 1.6 * sin(x * 0.067 + 0.4))
	_card_poly(st3, _grow(downs, 0.45), -86.08, paper, paper, -4.0, 30.0)
	_card_poly(st3, downs, -86, Color("c3b2ee"), Color("9f8ed6"), -4.0, 27.0)
	var far := _hill_poly(x0 + 20.0, x1 - 30.0, -4.0, func(x: float) -> float: return 18.0 + 2.5 * sin(x * 0.05 + 1.1))
	_card_poly(st3, _grow(far, 0.35), -85.98, paper, paper, 0, 1)
	_card_poly(st3, far, -85.96, Color("b3a3e6"), Color("9a8ad2"), -4.0, 21.0)
	_card_commit(root, st3, "CardL3")
	# L2: green hills, a village, a church and a windmill.
	var st2 := _card_st()
	var hill_f := func(x: float) -> float: return 16.8 + 2.4 * sin(x * 0.031 + 0.7) + 1.3 * sin(x * 0.093)
	var hills := _hill_poly(x0, x1, -4.0, hill_f)
	_card_poly(st2, _grow(hills, 0.45), -80.08, paper, paper, -4.0, 22.0)
	_card_poly(st2, hills, -80, Color("a4d46c"), Color("6fae45"), -4.0, 20.0)
	var wall_c := Color("f3e6c8")
	for k in 8:
		var hx := 18.0 + k * 3.3 + rng.randf_range(-0.4, 0.4)
		var hy: float = float(hill_f.call(hx)) - 1.6
		var hw := rng.randf_range(2.0, 2.8)
		var hh := rng.randf_range(1.5, 2.2)
		var house := PackedVector2Array([Vector2(hx - hw * 0.5, hy), Vector2(hx + hw * 0.5, hy), Vector2(hx + hw * 0.5, hy + hh), Vector2(hx - hw * 0.5, hy + hh)])
		var roof := PackedVector2Array([Vector2(hx - hw * 0.62, hy + hh), Vector2(hx + hw * 0.62, hy + hh), Vector2(hx, hy + hh + hw * 0.55)])
		_card_poly(st2, _grow(house, 0.18), -79.99, paper, paper, 0, 1)
		_card_poly(st2, _grow(roof, 0.18), -79.99, paper, paper, 0, 1)
		_card_poly(st2, house, -79.96, wall_c, wall_c.darkened(0.12), hy, hy + hh)
		var slate := k % 3 == 0
		_card_poly(st2, roof, -79.95, Color("6d7a8c") if slate else Color("c0703f"), Color("566273") if slate else Color("a85a30"), hy + hh, hy + hh + 1.5)
		var win := PackedVector2Array([Vector2(hx - 0.25, hy + 0.6), Vector2(hx + 0.25, hy + 0.6), Vector2(hx + 0.25, hy + 1.1), Vector2(hx - 0.25, hy + 1.1)])
		_card_poly(st2, win, -79.94, Color("ffd98a"), Color("ffcf6a"), 0, 1)
	# Church with a tall spire (top about y 24).
	var cx := 48.5
	var cy: float = float(hill_f.call(cx)) - 1.5
	var nave := PackedVector2Array([Vector2(cx - 2.6, cy), Vector2(cx + 1.0, cy), Vector2(cx + 1.0, cy + 2.6), Vector2(cx - 2.6, cy + 2.6)])
	var nave_roof := PackedVector2Array([Vector2(cx - 2.8, cy + 2.6), Vector2(cx + 1.0, cy + 2.6), Vector2(cx - 0.9, cy + 4.0)])
	var tower := PackedVector2Array([Vector2(cx + 0.6, cy), Vector2(cx + 2.4, cy), Vector2(cx + 2.4, cy + 5.2), Vector2(cx + 0.6, cy + 5.2)])
	var spire := PackedVector2Array([Vector2(cx + 0.4, cy + 5.2), Vector2(cx + 2.6, cy + 5.2), Vector2(cx + 1.5, cy + 9.8)])
	for pc: PackedVector2Array in [nave, nave_roof, tower, spire]:
		_card_poly(st2, _grow(pc, 0.18), -79.99, paper, paper, 0, 1)
	_card_poly(st2, nave, -79.96, Color("e9dcc3"), Color("cdbf9f"), cy, cy + 2.6)
	_card_poly(st2, nave_roof, -79.95, Color("6d7a8c"), Color("566273"), 0, 1)
	_card_poly(st2, tower, -79.95, Color("e9dcc3"), Color("cdbf9f"), cy, cy + 5.2)
	_card_poly(st2, spire, -79.94, Color("6d7a8c"), Color("4f5a69"), cy + 5.2, cy + 9.8)
	# Poplars and round trees along the hills.
	for k in 9:
		var tx := -60.0 + k * 15.0 + rng.randf_range(-3.0, 3.0)
		var ty: float = float(hill_f.call(tx)) - 0.8
		var tall := k % 2 == 0
		var tree := _ellipse(Vector2(tx, ty + (2.6 if tall else 1.6)), 0.9 if tall else 1.7, 2.8 if tall else 1.6, 14)
		_card_poly(st2, _grow(tree, 0.18), -79.99, paper, paper, 0, 1)
		_card_poly(st2, tree, -79.97, Color("5f9e3f"), Color("3f7a2f"), ty, ty + 5.0)
	# The distant windmill: the tower on this card, the turning sails on their own small card.
	var wx := -26.0
	var wy: float = float(hill_f.call(wx)) - 1.2
	var mill := PackedVector2Array([Vector2(wx - 1.6, wy), Vector2(wx + 1.6, wy), Vector2(wx + 1.0, wy + 6.4), Vector2(wx - 1.0, wy + 6.4)])
	var mill_cap := PackedVector2Array([Vector2(wx - 1.3, wy + 6.4), Vector2(wx + 1.3, wy + 6.4), Vector2(wx, wy + 8.0)])
	for pc: PackedVector2Array in [mill, mill_cap]:
		_card_poly(st2, _grow(pc, 0.18), -79.99, paper, paper, 0, 1)
	_card_poly(st2, mill, -79.96, Color("efe4cc"), Color("cdbf9f"), wy, wy + 6.4)
	_card_poly(st2, mill_cap, -79.95, Color("8a5a3b"), Color("6e4a2c"), 0, 1)
	_card_commit(root, st2, "CardL2")
	var sails_st := _card_st()
	for k in 4:
		var a := TAU * k / 4.0
		var dir := Vector2(cos(a), sin(a))
		var nrm := Vector2(-dir.y, dir.x)
		var blade := PackedVector2Array([nrm * -0.12, dir * 4.4 - nrm * 0.12, dir * 4.4 + nrm * 0.8, dir * 0.9 + nrm * 0.8])
		_card_poly(sails_st, _grow(blade, 0.14), -0.02, paper, paper, 0, 1)
		_card_poly(sails_st, blade, 0.0, Color("f3ead6"), Color("b89a72"), 0, 1)
	var sails := _card_commit(root, sails_st, "CardMillSails")
	sails.position = _bend(wx, wy + 6.0, -79.9)
	sails.rotation.y = -wx / 79.9
	var stw := sails.create_tween().set_loops()
	stw.tween_property(sails, "rotation:z", -TAU, 16.0).as_relative()
	# L1: patchwork fields, a dry-stone wall and the hedgerow with trees.
	var st1 := _card_st()
	var field_f := func(x: float) -> float: return 9.6 + 1.3 * sin(x * 0.047) + 0.8 * sin(x * 0.13 + 1.0)
	var field := _hill_poly(x0, x1, -4.0, field_f)
	var hedge_top := PackedVector2Array()
	var xx := x0
	while xx <= x1 + 0.01:
		hedge_top.append(Vector2(xx, float(field_f.call(xx)) + 2.3 + 1.1 * absf(sin(xx * 0.55)) + 0.6 * sin(xx * 0.21)))
		xx += 1.2
	var hedge := PackedVector2Array()
	for q in hedge_top:
		hedge.append(q)
	for i in range(hedge_top.size() - 1, -1, -1):
		var hxp := hedge_top[i].x
		hedge.append(Vector2(hxp, float(field_f.call(hxp)) - 0.8))
	_card_poly(st1, _grow(hedge, 0.4), -76.08, paper, paper, 0, 1)
	_card_poly(st1, _grow(field, 0.4), -76.08, paper, paper, 0, 1)
	_card_poly(st1, field, -76, Color("9fd16a"), Color("6aa843"), -4.0, 11.0)
	var cols := [Color("8cc85a"), Color("c9cf6a"), Color("79b64c"), Color("e0c878"), Color("a8d46e")]
	var bx := x0 - 8.0
	var bi := 0
	while bx < x1:
		var bw := rng.randf_range(9.0, 15.0)
		var band := PackedVector2Array([Vector2(bx, -4.0), Vector2(bx + bw, -4.0), Vector2(bx + bw + 6.0, 12.0), Vector2(bx + 6.0, 12.0)])
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(field, band):
			var pc: Color = cols[bi % cols.size()]
			_card_poly(st1, piece, -75.97, pc.lightened(0.06), pc.darkened(0.1), -4.0, 11.0)
		bx += bw
		bi += 1
	_card_poly(st1, hedge, -75.95, Color("5aa23c"), Color("3f7a2f"), 8.0, 15.0)
	for k in 7:
		var tx := -70 + k * 23.0 + rng.randf_range(-4.0, 4.0)
		var ty: float = float(field_f.call(tx)) + 3.2
		var crown := _ellipse(Vector2(tx, ty + 1.8), 2.4, 2.2, 16)
		_card_poly(st1, _grow(crown, 0.3), -76.06, paper, paper, 0, 1)
		_card_poly(st1, crown, -75.94, Color("6aa843"), Color("4f8f37"), ty, ty + 4.0)
	var wall := PackedVector2Array()
	xx = x0
	while xx <= x1 + 0.01:
		wall.append(Vector2(xx, 2.6 + 0.35 * absf(sin(xx * 1.3))))
		xx += 0.8
	xx = x1
	while xx >= x0 - 0.01:
		wall.append(Vector2(xx, 0.8))
		xx -= 3.0
	_card_poly(st1, wall, -75.93, Color("c4bba6"), Color("958b78"), 0.8, 3.0)
	_card_commit(root, st1, "CardL1")
	# Cloud cards on wires drifting in front of L3.
	var cl_st := _card_st()
	var cloud := _cloud_poly(rng)
	_card_poly(cl_st, _grow(cloud, 0.35), -0.05, paper, paper, 0, 1)
	_card_poly(cl_st, cloud, 0.0, Color("fffaf3"), Color("c9c3e6"), -1.5, 3.0)
	var cloud_mesh := cl_st.commit()
	var wire_m := K.mat(Color("6d6a73"), 0.8)
	for k in 4:
		var c := MeshInstance3D.new()
		c.name = "CardCloud%d" % k
		c.mesh = cloud_mesh
		c.material_override = _card_mat()
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(c)
		var cxp := -60.0 + k * 38.0 + rng.randf_range(-6.0, 6.0)
		var cyp := rng.randf_range(31.0, 40.0)
		c.position = _bend(cxp, cyp, -83)
		c.rotation.y = -cxp / 83.0
		c.scale = Vector3.ONE * rng.randf_range(1.1, 1.6)
		var w := K.cyl(c, 0.012, 0.012, 9.0, wire_m, Vector3(0, 6.0, -0.02), Vector3.ZERO, 4)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tw := c.create_tween().set_loops()
		var dx := rng.randf_range(3.0, 5.0)
		tw.tween_property(c, "position", _bend(cxp + dx, cyp, -83), rng.randf_range(14.0, 20.0)).set_trans(Tween.TRANS_SINE)
		tw.tween_property(c, "position", _bend(cxp - dx, cyp, -83), rng.randf_range(14.0, 20.0)).set_trans(Tween.TRANS_SINE)


static func _card_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static var _cmat: ShaderMaterial


## Render fix 2026-10-19: the cards are one-sided by position (backdrop_card.gdshader), so from behind the map edge
## they no longer fill the view with a paper-coloured wall. Same unshaded vertex-colour, no-fog look as before.
static func _card_mat() -> ShaderMaterial:
	if _cmat == null:
		_cmat = ShaderMaterial.new()
		_cmat.shader = load("res://assets/shaders/backdrop_card.gdshader") as Shader
	return _cmat


static func _card_commit(root: Node3D, st: SurfaceTool, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	mi.material_override = _card_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


static func _card_poly(st: SurfaceTool, poly: PackedVector2Array, z: float, top: Color, bottom: Color, y0: float, y1: float) -> void:
	if poly.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(poly)
	# Ear clipping fans long strips from one corner; bent onto the circle those long triangles become chords that cut
	# across the play square (the first r2 capture showed pale sheets over Brick Hill). Split every triangle until no
	# edge is longer than 4 m, then bend.
	var tris: Array[PackedVector2Array] = []
	for k in range(0, idx.size(), 3):
		_split_tri(PackedVector2Array([poly[idx[k]], poly[idx[k + 1]], poly[idx[k + 2]]]), tris, 0, z > -5.0)
	for tri in tris:
		for p in tri:
			var t := clampf((p.y - y0) / maxf(y1 - y0, 0.01), 0.0, 1.0)
			st.set_color(_haze(bottom.lerp(top, t), z))
			st.add_vertex(_bend(p.x, p.y, z))


static func _split_tri(t: PackedVector2Array, out: Array[PackedVector2Array], depth: int, flat: bool) -> void:
	var l0 := t[0].distance_to(t[1])
	var l1 := t[1].distance_to(t[2])
	var l2 := t[2].distance_to(t[0])
	var m := maxf(l0, maxf(l1, l2))
	if flat or m < 4.0 or depth > 12:
		out.append(t)
		return
	if m == l0:
		var c := (t[0] + t[1]) * 0.5
		_split_tri(PackedVector2Array([t[0], c, t[2]]), out, depth + 1, flat)
		_split_tri(PackedVector2Array([c, t[1], t[2]]), out, depth + 1, flat)
	elif m == l1:
		var c := (t[1] + t[2]) * 0.5
		_split_tri(PackedVector2Array([t[0], t[1], c]), out, depth + 1, flat)
		_split_tri(PackedVector2Array([t[0], c, t[2]]), out, depth + 1, flat)
	else:
		var c := (t[2] + t[0]) * 0.5
		_split_tri(PackedVector2Array([t[0], t[1], c]), out, depth + 1, flat)
		_split_tri(PackedVector2Array([c, t[1], t[2]]), out, depth + 1, flat)


## The card layers curve round the play square on a circle about the world centre (radius = the layer's depth), so no
## camera ever sees a card edge-on as a flat wall; a card's world z at x = 0 is its depth. z > -5: local (no bend).
static func _bend(x: float, y: float, z: float) -> Vector3:
	if z > -5.0:
		return Vector3(x, y, z)
	var r := -z
	var th := x / r
	return Vector3(r * sin(th), y, -r * cos(th))


## Cards are unshaded and opt out of fog, so they get a fixed share of the golden haze by depth instead (a little
## saturation kept, the far downs softest).
static func _haze(c: Color, z: float) -> Color:
	if z > -5.0:
		return c
	var k := clampf((-z - 74.0) / 14.0, 0.0, 1.0) * 0.22 + 0.06
	return c.lerp(Color("f2dcc0"), k)


static func _grow(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := Geometry2D.offset_polygon(poly, d, Geometry2D.JOIN_ROUND)
	return out[0] if out.size() > 0 else poly


static func _hill_poly(x0: float, x1: float, base_y: float, f: Callable) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := x0
	while x <= x1 + 0.01:
		pts.append(Vector2(x, float(f.call(x))))
		x += 1.5
	# A dense bottom edge too, so the triangles stay local and bend cleanly with the card.
	x = x1
	while x >= x0 - 0.01:
		pts.append(Vector2(x, base_y))
		x -= 3.0
	return pts


static func _ellipse(c: Vector2, rx: float, ry: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _cloud_poly(rng: RandomNumberGenerator) -> PackedVector2Array:
	var poly := _ellipse(Vector2(0, 0), 3.2, 1.2, 20)
	for k in 5:
		var puff := _ellipse(Vector2(-2.4 + k * 1.2, 0.6 + rng.randf_range(0.0, 0.8)), rng.randf_range(1.0, 1.5), rng.randf_range(0.9, 1.3), 16)
		var merged := Geometry2D.merge_polygons(poly, puff)
		if merged.size() > 0:
			poly = merged[0]
	return poly


## R2.5 Crows' Loot Nest in the Grand Birch fork (top 22.6): a stick bowl with stolen trinkets.
static func crows_nest(level: Node3D, top: Vector3, size: Vector3) -> void:
	var b := K.body(level, "CrowsNest", top)
	b.set_meta("no_ledge_grab", true)
	b.add_to_group("no_ledge_grab")
	var r := size.x * 0.5
	K.shape_cyl(b, r, 0.5, Vector3(0, -0.25, 0))
	var twig := K.tex_mat("bark", Color(0.85, 0.7, 0.52), 0.9)
	K.cyl(b, r, r * 0.8, 0.5, K.mat(Color("6e4a2c"), 0.9), Vector3(0, -0.3, 0), Vector3.ZERO, 16)
	K.torus(b, r * 0.75, r * 1.05, twig, Vector3(0, -0.02, 0))
	for i in 12:
		var a := TAU * i / 12.0
		K.cyl(b, 0.04, 0.04, 1.3, twig, Vector3(cos(a) * r * 0.9, 0.0, sin(a) * r * 0.9), Vector3(randf_range(-30, 30), rad_to_deg(a), 80), 5)
	K.rbox(b, Vector3(0.5, 0.06, 0.12), K.mat(Color("c9a04a"), 0.3), Vector3(0.3, 0.05, 0.2), Vector3(0, 30, 0), 0.02)
	K.torus(b, 0.08, 0.11, K.mat(Color("c9a04a"), 0.3), Vector3(-0.4, 0.05, -0.2), Vector3(70, 0, 0))
	K.rbox(b, Vector3(0.3, 0.12, 0.12), K.mat(Color("7a1f2e"), 0.6), Vector3(-0.1, 0.06, 0.45), Vector3(0, -20, 0), 0.04)
	var ps := load("res://scenes/objects/AcornGroup.tscn") as PackedScene
	if ps:
		var g := ps.instantiate() as Node3D
		g.set("shape", AcornGroup.Shape.RING)
		g.set("count", 10)
		# Fix round 2 (QA r1: the 0.75 m ring sat inside the trunk and was pushed out into a floating ring): on the bowl,
		# between the trunk (0.8 m) and the rim (1.3 m).
		g.set("radius", 1.05)
		g.position = top + Vector3(0, 0.4, 0)
		g.name = "A30"
		level.add_child(g)


## R2.4 bellows hoses: fat canvas tubes from each machine to the well, half sunk in the grass, brass clamps every 4 m.
static func hoses(level: Node3D, lv: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "BellowsHoses"
	level.add_child(root)
	var leather := K.mat(Color("8b5a33"), 0.75)
	var glow := K.glow_mat(Color("ffc86b"), 1.8)
	for h in lv.get("bellows_hoses", []):
		var pts: Array[Vector3] = []
		for q in h["points"]:
			pts.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
		var samples: Array[Vector3] = []
		var ext: Array[Vector3] = [pts[0] - (pts[1] - pts[0])]
		ext.append_array(pts)
		ext.append(pts[-1] + (pts[-1] - pts[-2]))
		for i in range(1, ext.size() - 2):
			for k in 10:
				var t := k / 10.0
				var p0 := ext[i - 1]
				var p1 := ext[i]
				var p2 := ext[i + 1]
				var p3 := ext[i + 2]
				samples.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
		samples.append(pts[-1])
		# Fix round 1 (visual critic r1: straight tan tubes with brass rings read as rigid pipes): sagging leather hose
		# in slack S-curves, partly sunk into the grass, darker pleat rings every 0.5 m, and a warm pulse that runs
		# from the well toward its machine every 1.5 s, so each hose leads the way.
		var r: float = float(h.get("diameter", 0.4)) * 0.5
		var total := 0.0
		for i in range(1, samples.size()):
			total += samples[i].distance_to(samples[i - 1])
		var run := 0.0
		var bent: Array[Vector3] = []
		for i in samples.size():
			if i > 0:
				run += samples[i].distance_to(samples[i - 1])
			var q := samples[i]
			var tdir := (samples[mini(i + 1, samples.size() - 1)] - samples[maxi(i - 1, 0)])
			tdir.y = 0.0
			var side := Vector3(-tdir.z, 0, tdir.x).normalized() if tdir.length() > 0.01 else Vector3.ZERO
			var env := clampf(run / 2.0, 0.0, 1.0) * clampf((total - run) / 2.0, 0.0, 1.0)
			q += side * sin(run * 0.55) * 0.32 * env
			var g := W1Terrain.height(q.x, q.z) + r * 0.35
			q.y = maxf(q.y - 0.1, g) if q.y > g + 0.3 else g
			bent.append(q)
		# Fix round 2 (visual r1: one dark 40 m cable snaking across the meadow and up Brick Hill): only the last 7 m at the
		# machine and 3 m at the well head show as leather hose (30 % thinner, lighter leather, brass clamps every 1.5 m);
		# the run between is buried under the path as a low soil hump with a turf cap every 3 m. The pulse still rides it.
		var vis_r := r * 0.7
		var soil := K.mat(Color("8a6a48"), 0.95)
		var cap := K.mat(Color("7fae45"), 0.9)
		var brass := K.mat(Color("c9a04a"), 0.35)
		var along := 0.0
		var next_clamp := 0.6
		var next_cap := 1.5
		for i in range(1, bent.size()):
			var a := bent[i - 1]
			var c := bent[i]
			var d := c - a
			var l := d.length()
			if l < 0.01:
				continue
			var mid_run := along + l * 0.5
			var shown := mid_run < 7.0 or mid_run > total - 3.0
			var bas := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.FORWARD) * Basis(Vector3.RIGHT, PI * 0.5)
			if shown:
				var mi := K.cyl(root, vis_r, vis_r, l + 0.06, leather, (a + c) * 0.5, Vector3.ZERO, 10)
				mi.basis = bas
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if along + l > next_clamp:
					var k := clampf((next_clamp - along) / l, 0.0, 1.0)
					var cl := K.torus(root, vis_r * 0.95, vis_r * 1.3, brass, a.lerp(c, k))
					cl.basis = bas
					cl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					next_clamp += 1.5
			else:
				var ga := Vector3(a.x, W1Terrain.height(a.x, a.z) + 0.02, a.z)
				var gc := Vector3(c.x, W1Terrain.height(c.x, c.z) + 0.02, c.z)
				var gd := gc - ga
				var hb := Basis.looking_at(gd.normalized(), Vector3.UP if absf(gd.normalized().y) < 0.95 else Vector3.FORWARD) * Basis(Vector3.RIGHT, PI * 0.5)
				var hm := K.cyl(root, r * 1.25, r * 1.25, gd.length() + 0.08, soil, (ga + gc) * 0.5, Vector3.ZERO, 8)
				hm.basis = hb * Basis.from_scale(Vector3(1.0, 1.0, 0.32))
				hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if along + l > next_cap:
					var k2 := clampf((next_cap - along) / l, 0.0, 1.0)
					var cp := ga.lerp(gc, k2)
					var cm := K.sphere(root, 0.42, cap, cp + Vector3(0, 0.03, 0), Vector3(1.0, 0.22, 1.0))
					cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					next_cap += 3.0
				bent[i] = Vector3(c.x, gc.y + r * 0.3, c.z)
			along += l
		# The pulse: a glowing bulge riding the hose from the well end (last point) to the machine (first point).
		var bulge := K.sphere(root, r * 1.1, glow, bent[-1], Vector3(1.0, 1.0, 1.6))
		bulge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var path := bent.duplicate()
		var tw := bulge.create_tween().set_loops()
		tw.tween_method(func(k: float) -> void:
			var f := (1.0 - k) * float(path.size() - 1)
			var i0 := int(floor(f))
			var i1 := mini(i0 + 1, path.size() - 1)
			var pa: Vector3 = path[i0]
			var pb: Vector3 = path[i1]
			bulge.position = pa.lerp(pb, f - i0)
			var dd := (pa - pb).normalized()
			if pa.distance_to(pb) > 0.01 and absf(dd.y) < 0.95:
				bulge.basis = Basis.looking_at(dd, Vector3.UP) * Basis.from_scale(Vector3(1.0, 1.0, 1.6)), 0.0, 1.0, maxf(total / 14.0, 0.8))
		tw.tween_interval(1.5)

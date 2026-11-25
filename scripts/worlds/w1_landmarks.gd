class_name W1Landmarks
extends RefCounted
## W1 landmark builders. Gameplay collision always uses the builder's boxes at the exact plan sizes
## (Docs/levels/W1_assets.md "Collision rule for W1"); visuals are procedural stand-ins until a generated
## GLB exists under res://assets/props/w1/, then the GLB replaces the stand-in visual.

const K := preload("res://scripts/worlds/w1_kit.gd")


## Sloped box whose top surface runs through the world line from `a` to `b` (same x span), `x_len` long.
static func slope_box(b: CollisionObject3D, x_center: float, x_len: float, a: Vector3, c: Vector3, thick: float) -> CollisionShape3D:
	var d := c - a
	var dn := d.normalized()
	var xa := Vector3.RIGHT
	var y := dn.cross(xa)
	if y.y < 0.0:
		xa = -xa
		y = dn.cross(xa)
	var basis := Basis(xa, y, dn)
	var mid := (a + c) * 0.5
	mid.x = x_center
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(x_len, thick, d.length())
	cs.shape = s
	cs.transform = Transform3D(basis, mid - y * thick * 0.5)
	b.add_child(cs)
	return cs


## Visual roof slab matching slope_box.
static func slope_visual(parent: Node3D, x_center: float, x_len: float, a: Vector3, c: Vector3, thick: float, mat: Material, radius := 0.12) -> MeshInstance3D:
	var d := c - a
	var dn := d.normalized()
	var xa := Vector3.RIGHT
	var y := dn.cross(xa)
	if y.y < 0.0:
		xa = -xa
		y = dn.cross(xa)
	var mid := (a + c) * 0.5
	mid.x = x_center
	var mi := K.rbox(parent, Vector3(x_len, thick, d.length()), mat, Vector3.ZERO, Vector3.ZERO, radius)
	mi.transform = Transform3D(Basis(xa, y, dn), mid - y * thick * 0.5)
	return mi


static func _visual_or_null(n: Node3D, names: Array, h: float, yaw_extra := 0.0) -> Node3D:
	var v := K.glb_visual(n, names, h)
	if v:
		v.rotation_degrees.y += yaw_extra - 180.0
	return v


# ---------------------------------------------------------------- straw house (local origin = base centre)

static func straw_house(n: Node3D) -> void:
	var b := K.body(n, "Collision")
	K.shape_box(b, Vector3(7.0, 3.4, 6.0), Vector3(0, 1.7, 0))
	# Collision slopes at 36 degrees so the roof is walkable (visual pitch 40).
	var eave := 5.9 - tan(deg_to_rad(36.0)) * 3.2
	slope_box(b, 0.0, 7.6, Vector3(0, eave, 3.2), Vector3(0, 5.9, 0), 0.4)
	slope_box(b, 0.0, 7.6, Vector3(0, eave, -3.2), Vector3(0, 5.9, 0), 0.4)
	if _visual_or_null(n, ["straw_house", "w1_straw_house"], 6.3):
		return
	var v := Node3D.new()
	v.name = "Visual"
	n.add_child(v)
	var straw := K.tex_mat("straw_thatch", Color(1.08, 1.0, 0.82), 0.45)
	var thatch := K.tex_mat("straw_thatch", Color(1.15, 0.98, 0.7), 0.3)
	var timber := K.tex_mat("wood_planks", Color(0.82, 0.62, 0.45), 0.5)
	var cream := K.mat(Color("f3e2b8"), 0.9)
	# Bulging loaf walls.
	K.rbox(v, Vector3(7.0, 3.5, 6.0), straw, Vector3(0, 1.72, 0), Vector3.ZERO, 0.6)
	K.rbox(v, Vector3(7.3, 0.4, 6.3), K.mat(Color("c9a35a")), Vector3(0, 0.15, 0), Vector3.ZERO, 0.18)
	# Timber corner posts and a cross beam.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			K.rbox(v, Vector3(0.35, 3.5, 0.35), timber, Vector3(sx * 3.35, 1.75, sz * 2.85))
	K.rbox(v, Vector3(7.2, 0.3, 0.3), timber, Vector3(0, 3.35, 3.02))
	# Gable ends (triangle fill) as stacked shrinking boxes.
	for sx in [-1.0, 1.0]:
		for i in 5:
			var hgt := 0.5
			var w := 5.6 * (1.0 - (i + 0.5) / 5.5)
			K.rbox(v, Vector3(0.5, hgt, w), straw, Vector3(sx * 3.2, 3.6 + i * hgt, 0), Vector3.ZERO, 0.2)
	# Shaggy thatch roof slabs (thick, overhanging, slightly crooked).
	slope_visual(v, 0.0, 8.2, Vector3(0, 3.35, 3.7), Vector3(0, 6.05, -0.1), 0.75, thatch, 0.35)
	slope_visual(v, 0.0, 8.2, Vector3(0, 3.35, -3.7), Vector3(0, 6.05, 0.1), 0.75, thatch, 0.35)
	K.capsule(v, 0.32, 8.4, K.mat(Color("c48a3a")), Vector3(0, 6.1, 0), Vector3(0, 0, 90))
	for i in 5:
		K.torus(v, 0.28, 0.4, K.mat(Color("8a5a3b")), Vector3(-3.2 + i * 1.6, 6.1, 0), Vector3(0, 0, 90))
	# Round door with a tiny porch, south face.
	var door := K.mat(Color("8a5a3b"), 0.8)
	K.cyl(v, 0.85, 0.85, 0.2, door, Vector3(0, 1.25, 3.05), Vector3(90, 0, 0), 20)
	K.rbox(v, Vector3(1.7, 1.25, 0.2), door, Vector3(0, 0.62, 3.05))
	K.sphere(v, 0.09, K.mat(K.GOLD, 0.35), Vector3(0.5, 1.0, 3.2))
	K.rbox(v, Vector3(2.4, 0.18, 1.2), thatch, Vector3(0, 2.45, 3.5), Vector3(-12, 0, 0))
	# Windows with red-checked curtains.
	for sx in [-1.0, 1.0]:
		K.rbox(v, Vector3(1.1, 1.0, 0.16), K.mat(Color("6b4430")), Vector3(sx * 2.0, 2.0, 3.05))
		K.rbox(v, Vector3(0.85, 0.75, 0.1), K.mat(Color("ffe9b0"), 0.4), Vector3(sx * 2.0, 2.0, 3.1))
		K.rbox(v, Vector3(0.4, 0.75, 0.06), K.mat(Color("d8433b")), Vector3(sx * 2.0 - 0.22, 2.0, 3.14))
		K.rbox(v, Vector3(0.95, 0.12, 0.3), K.mat(Color("8a5a3b")), Vector3(sx * 2.0, 1.45, 3.15))
		for k in 3:
			K.sphere(v, 0.13, K.mat([Color("e8413b"), Color("ffcf3c"), Color("f2f0ff")][k]), Vector3(sx * 2.0 - 0.3 + k * 0.3, 1.6, 3.25))
	# Crooked straw chimney.
	K.cyl(v, 0.38, 0.5, 1.8, thatch, Vector3(2.0, 5.9, -1.2), Vector3(0, 0, -8))
	K.torus(v, 0.25, 0.45, K.mat(Color("8a5a3b")), Vector3(2.12, 6.8, -1.2))
	# Straw wisps poking out.
	var wisp := K.mat(Color("f2d277"), 0.9)
	for i in 14:
		var a := float(i) * 2.399
		K.capsule(v, 0.05, 0.7, wisp, Vector3(cos(a) * 3.6, 3.4 + fmod(a, 1.0) * 0.4, sin(a) * 3.3 + 0.2), Vector3(randf_range(-40, 40), 0, randf_range(50, 80) * (1 if i % 2 else -1)))


# ---------------------------------------------------------------- stick house (base y 4, door east)

static func stick_house(n: Node3D) -> void:
	var b := K.body(n, "Collision")
	K.shape_box(b, Vector3(6.0, 3.0, 5.0), Vector3(0, 1.5, 0))
	var eave := 5.2 - tan(deg_to_rad(36.0)) * 2.7
	slope_box(b, 0.0, 6.6, Vector3(0, eave, 2.7), Vector3(0, 5.2, 0), 0.4)
	slope_box(b, 0.0, 6.6, Vector3(0, eave, -2.7), Vector3(0, 5.2, 0), 0.4)
	if _visual_or_null(n, ["stick_house", "w1_stick_house"], 5.2):
		return
	var v := Node3D.new()
	v.name = "Visual"
	n.add_child(v)
	var bark := K.tex_mat("bark", Color(0.95, 0.8, 0.62), 0.6)
	var twig := K.mat(Color("9a6a40"), 0.85)
	var twig2 := K.mat(Color("7a5030"), 0.85)
	K.rbox(v, Vector3(5.8, 3.0, 4.8), K.mat(Color("6e4a2c")), Vector3(0, 1.5, 0), Vector3.ZERO, 0.2)
	# Bundled sticks: vertical poles all around the walls, slightly leaning.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for side in 4:
		var count := 12 if side < 2 else 10
		for i in count:
			var t := (i + 0.5) / count
			var p := Vector3.ZERO
			if side == 0:
				p = Vector3(-2.9 + t * 5.8, 0, 2.45)
			elif side == 1:
				p = Vector3(-2.9 + t * 5.8, 0, -2.45)
			elif side == 2:
				p = Vector3(-2.95, 0, -2.4 + t * 4.8)
			else:
				p = Vector3(2.95, 0, -2.4 + t * 4.8)
			if side == 3 and absf(p.z) < 0.7:
				continue
			var hh := rng.randf_range(3.0, 3.6)
			K.cyl(v, 0.1, 0.13, hh, bark if i % 3 else twig, p + Vector3(0, hh * 0.5, 0), Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5)), 8)
	# Twine bands.
	for y in [0.9, 2.3]:
		K.rbox(v, Vector3(6.05, 0.1, 5.05), K.mat(Color("d8c08a")), Vector3(0, y, 0), Vector3.ZERO, 0.05)
	# Lopsided twig thatch roof: rows of sticks along the slopes.
	for s in [-1.0, 1.0]:
		slope_visual(v, 0.0, 6.9, Vector3(0, 2.75, s * 3.1), Vector3(0, 5.3, 0.0), 0.35, twig2, 0.12)
		for i in 7:
			var t := (i + 0.5) / 7.0
			var p := Vector3(0, lerpf(2.95, 5.45, t), s * lerpf(3.0, 0.1, t))
			K.cyl(v, 0.11, 0.11, 7.0, bark if i % 2 else twig, p, Vector3(0, 0, 90 + rng.randf_range(-3, 3)), 8)
	# Gables.
	for sx in [-1.0, 1.0]:
		for i in 4:
			K.rbox(v, Vector3(0.3, 0.6, 4.4 * (1.0 - (i + 0.5) / 4.5)), twig2, Vector3(sx * 2.9, 3.3 + i * 0.55, 0), Vector3.ZERO, 0.1)
	# Branch door on the east face.
	K.rbox(v, Vector3(0.2, 2.0, 1.2), K.mat(Color("5c3a21")), Vector3(3.0, 1.0, 0))
	# Clay chimney with smoke.
	K.cyl(v, 0.28, 0.36, 1.4, K.mat(Color("c0703f")), Vector3(-1.6, 5.0, -1.0))
	# Leaves sprouting from the walls.
	for i in 10:
		K.sphere(v, 0.25, K.mat(K.LEAF), Vector3(rng.randf_range(-2.9, 2.9), rng.randf_range(0.4, 2.8), 2.55 * (1 if i % 2 else -1)), Vector3(1, 0.6, 0.5))


# ---------------------------------------------------------------- brick house (base y 12, centre (5, -36))

static func brick_house(n: Node3D) -> void:
	# Local frame: origin at (5, 12, -36). Chimney outer x 9.5-13.1 -> local 4.5..8.1; z -37.6..-34.4 -> local -1.6..1.6.
	var b := K.body(n, "Collision")
	K.shape_box(b, Vector3(9.0, 6.0, 7.0), Vector3(0, 3.0, 0))
	var eave := 9.0 - tan(deg_to_rad(36.5)) * 3.5
	slope_box(b, -0.2, 9.4, Vector3(0, eave, 3.5), Vector3(0, 9.0, 0), 0.4)
	slope_box(b, -0.2, 9.4, Vector3(0, eave, -3.5), Vector3(0, 9.0, 0), 0.4)
	# Chimney shaft walls (inner x local 4.8..7.8, z -1.3..1.3, y 0..14).
	var cb := K.body(n, "Chimney")
	cb.add_to_group("w1_chimney")
	K.shape_box(cb, Vector3(0.3, 14.0, 3.2), Vector3(4.65, 7.0, 0))  # west wall (against the gable)
	K.shape_box(cb, Vector3(3.6, 14.0, 0.3), Vector3(6.3, 7.0, -1.45))  # north wall
	K.shape_box(cb, Vector3(3.6, 14.0, 0.3), Vector3(6.3, 7.0, 1.45))  # south wall
	# East wall with the soot door (z -0.8..0.8, y 0..1.9).
	K.shape_box(cb, Vector3(0.3, 14.0, 0.8), Vector3(7.95, 7.0, -1.2))
	K.shape_box(cb, Vector3(0.3, 14.0, 0.8), Vector3(7.95, 7.0, 1.2))
	K.shape_box(cb, Vector3(0.3, 12.1, 1.6), Vector3(7.95, 1.9 + 6.05, 0))
	# Soot ledge: x 9.8-12.8, z -35.6..-34.7, top y 19.0 -> local z 0.4..1.3, top 7.0.
	K.shape_box(cb, Vector3(3.0, 0.4, 0.9), Vector3(6.3, 6.8, 0.85))
	var brick := K.tex_mat("brick", Color(1.06, 0.92, 0.86), 0.42)
	_chimney_visual(n, brick)
	if _visual_or_null(n, ["brick_house", "w1_brick_house"], 9.0):
		return
	var v := Node3D.new()
	v.name = "Visual"
	n.add_child(v)
	var slate := K.tex_mat("roof_shingles_slate", Color(0.9, 0.95, 1.05), 0.35)
	if not ResourceLoader.exists("res://assets/textures/roof_shingles_slate.webp"):
		slate = K.mat(K.SLATE, 0.7) as StandardMaterial3D
	var white := K.mat(Color("f7f1e4"), 0.6)
	var glass := K.mat(Color("ffe3a0"), 0.3)
	K.rbox(v, Vector3(9.0, 6.0, 7.0), brick, Vector3(0, 3.0, 0), Vector3.ZERO, 0.25)
	K.rbox(v, Vector3(9.3, 0.6, 7.3), K.mat(K.STONE), Vector3(0, 0.3, 0), Vector3.ZERO, 0.2)
	# Gable triangles.
	for sx in [-1.0, 1.0]:
		for i in 6:
			K.rbox(v, Vector3(0.6, 0.5, 6.8 * (1.0 - (i + 0.5) / 6.4)), brick, Vector3(sx * 4.25, 6.25 + i * 0.5, 0), Vector3.ZERO, 0.12)
	slope_visual(v, -0.25, 9.8, Vector3(0, 5.7, 3.95), Vector3(0, 9.15, -0.05), 0.5, slate, 0.18)
	slope_visual(v, -0.25, 9.8, Vector3(0, 5.7, -3.95), Vector3(0, 9.15, 0.05), 0.5, slate, 0.18)
	K.capsule(v, 0.22, 9.9, K.mat(Color("4a5263")), Vector3(-0.25, 9.18, 0), Vector3(0, 0, 90))
	# Sash windows with flower boxes (south face z +3.5), two rows.
	for row in 2:
		for i in 3:
			var x := -3.0 + i * 3.0
			if row == 0 and absf(x + 2.0) < 0.9:
				continue
			var y := 1.9 + row * 2.6
			K.rbox(v, Vector3(1.3, 1.5, 0.2), white, Vector3(x, y, 3.55))
			K.rbox(v, Vector3(1.0, 1.2, 0.1), glass, Vector3(x, y, 3.62))
			K.rbox(v, Vector3(1.05, 0.08, 0.12), white, Vector3(x, y, 3.68))
			K.rbox(v, Vector3(1.4, 0.3, 0.4), K.mat(Color("8a5a3b")), Vector3(x, y - 0.85, 3.75))
			for k in 4:
				K.sphere(v, 0.14, K.mat([Color("e8413b"), Color("ff7fb0"), Color("e8413b"), Color("ffcf3c")][k]), Vector3(x - 0.45 + k * 0.3, y - 0.62, 3.8))
	# Round-topped green front door at local x -2 (world x 3).
	var green := K.mat(Color("3f8f5a"), 0.6)
	K.rbox(v, Vector3(1.4, 2.0, 0.25), green, Vector3(-2.0, 1.0 + 0.6, 3.55))
	K.cyl(v, 0.7, 0.7, 0.25, green, Vector3(-2.0, 2.6, 3.55), Vector3(90, 0, 0), 20)
	K.sphere(v, 0.08, K.mat(K.GOLD, 0.3), Vector3(-1.6, 1.6, 3.72))
	K.rbox(v, Vector3(2.0, 0.25, 1.0), K.mat(K.STONE), Vector3(-2.0, 0.72, 4.0))


static func _chimney_visual(n: Node3D, brick: Material) -> void:
	var v := Node3D.new()
	v.name = "ChimneyVisual"
	n.add_child(v)
	# Four walls drawn as boxes so the shaft is truly hollow; the crown flares out.
	K.rbox(v, Vector3(0.3, 14.0, 3.2), brick, Vector3(4.65, 7.0, 0), Vector3.ZERO, 0.08)
	K.rbox(v, Vector3(3.6, 14.0, 0.3), brick, Vector3(6.3, 7.0, -1.45), Vector3.ZERO, 0.08)
	K.rbox(v, Vector3(3.6, 14.0, 0.3), brick, Vector3(6.3, 7.0, 1.45), Vector3.ZERO, 0.08)
	K.rbox(v, Vector3(0.3, 14.0, 0.8), brick, Vector3(7.95, 7.0, -1.2), Vector3.ZERO, 0.08)
	K.rbox(v, Vector3(0.3, 14.0, 0.8), brick, Vector3(7.95, 7.0, 1.2), Vector3.ZERO, 0.08)
	K.rbox(v, Vector3(0.3, 12.1, 1.6), brick, Vector3(7.95, 7.95, 0), Vector3.ZERO, 0.08)
	# Soot door arch.
	K.torus(v, 0.7, 0.95, K.mat(K.STONE_DARK), Vector3(8.12, 1.9, 0), Vector3(0, 0, 90))
	# Soot ledge.
	K.rbox(v, Vector3(3.0, 0.4, 0.9), K.mat(Color("6d5a52")), Vector3(6.3, 6.8, 0.85), Vector3.ZERO, 0.08)
	# Crown band and two chimney pots on the corners (outside the opening).
	var crown := K.mat(Color("d8c7a8"))
	for z in [-1.55, 1.55]:
		K.rbox(v, Vector3(4.0, 0.45, 0.5), crown, Vector3(6.3, 13.85, z), Vector3.ZERO, 0.1)
	for x in [4.55, 8.05]:
		K.rbox(v, Vector3(0.5, 0.45, 3.6), crown, Vector3(x, 13.85, 0), Vector3.ZERO, 0.1)
	var pot := K.mat(Color("c0703f"))
	K.cyl(v, 0.24, 0.3, 0.9, pot, Vector3(4.6, 14.5, -1.5))
	K.cyl(v, 0.24, 0.3, 0.9, pot, Vector3(8.0, 14.5, 1.5))
	# Sooty interior glow strip (makes the shaft read as an opening from above).
	K.rbox(v, Vector3(2.9, 0.06, 2.5), K.mat(Color("2b2220")), Vector3(6.3, 0.03, 0))


# ---------------------------------------------------------------- windmill (base (40, 12, -46))

static func windmill(n: Node3D) -> void:
	var b := K.body(n, "Collision")
	var pts := PackedVector3Array()
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		pts.append(Vector3(cos(a) * 3.0, 0.0, sin(a) * 3.0))
		pts.append(Vector3(cos(a) * 2.25, 12.0, sin(a) * 2.25))
	var conv := ConvexPolygonShape3D.new()
	conv.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = conv
	b.add_child(cs)
	K.shape_cyl(b, 3.6, 0.3, Vector3(0, 11.85, 0))  # gallery ring, top y 24
	K.shape_cyl(b, 2.5, 3.5, Vector3(0, 13.75, 0))   # cap 24..27.5
	K.shape_cyl(b, 1.4, 0.5, Vector3(0, 15.75, 0))   # weathervane deck, top 28
	var v := Node3D.new()
	v.name = "Visual"
	n.add_child(v)
	var deck := K.tex_mat("wood_planks", Color(1.0, 0.85, 0.65), 0.6)
	K.cyl(v, 1.4, 1.45, 0.5, deck, Vector3(0, 15.75, 0), Vector3.ZERO, 20)
	K.torus(v, 1.3, 1.5, K.mat(Color("5c3a21")), Vector3(0, 16.05, 0))
	# Gallery ring with railing posts.
	K.cyl(v, 3.6, 3.6, 0.3, deck, Vector3(0, 11.85, 0), Vector3.ZERO, 24)
	for i in 16:
		var a := TAU * i / 16.0
		K.cyl(v, 0.06, 0.06, 0.9, K.mat(Color("f2ead8")), Vector3(cos(a) * 3.45, 12.45, sin(a) * 3.45), Vector3.ZERO, 6)
	K.torus(v, 3.38, 3.52, K.mat(Color("f2ead8")), Vector3(0, 12.9, 0))
	if K.glb_visual(v, ["windmill_body", "windmill_tower", "w1_windmill_tower"], 16.0):
		return
	var board := K.tex_mat("wood_planks", Color(1.25, 1.22, 1.15), 0.5)
	var tower := K.cyl(v, 2.25, 3.0, 12.0, board, Vector3(0, 6.0, 0), Vector3(0, 22.5, 0), 8)
	tower.name = "Tower"
	K.cyl(v, 3.15, 3.3, 1.4, K.tex_mat("cliff_rock", Color(1.05, 1.0, 0.95), 0.5), Vector3(0, 0.7, 0), Vector3(0, 22.5, 0), 8)
	# Boat-shaped thatch cap.
	var cap := K.tex_mat("straw_thatch", Color(0.72, 0.6, 0.48), 0.4)
	K.sphere(v, 2.6, cap, Vector3(0, 13.2, 0), Vector3(1.0, 0.85, 1.15))
	K.cyl(v, 2.55, 2.6, 1.0, cap, Vector3(0, 12.5, 0), Vector3.ZERO, 20)
	# Round windows and a door.
	var win := K.mat(Color("ffe3a0"), 0.3)
	for i in 3:
		var y := 3.5 + i * 3.4
		var r := lerpf(2.95, 2.3, y / 12.0)
		K.cyl(v, 0.4, 0.4, 0.15, win, Vector3(0, y, r - 0.02), Vector3(90, 0, 0), 14)
		K.torus(v, 0.38, 0.5, K.mat(Color("5c3a21")), Vector3(0, y, r + 0.02), Vector3(90, 0, 0))
	K.rbox(v, Vector3(1.3, 2.2, 0.3), K.mat(Color("3f8f5a")), Vector3(0, 1.4, 3.0))
	# Rooster weathervane.
	var iron := K.mat(Color("3b3b44"), 0.4)
	K.cyl(v, 0.05, 0.05, 2.0, iron, Vector3(-0.8, 17.0, -0.6), Vector3.ZERO, 6)
	K.rbox(v, Vector3(0.7, 0.5, 0.08), iron, Vector3(-0.8, 18.1, -0.6))


## Sail blades (visual only), in the plane just in front of the tower. Rotated by the level each frame.
static func windmill_sails(parent: Node3D) -> Node3D:
	var rotor := Node3D.new()
	rotor.name = "SailRotor"
	parent.add_child(rotor)
	var g := K.glb_visual(rotor, ["windmill_sails", "w1_windmill_sails"], -1.0, 18.0)
	if g:
		return rotor
	var wood := K.mat(Color("6e4a2c"), 0.8)
	var canvas := K.mat(Color("f7efdc"), 0.9)
	canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
	var red := K.mat(Color("c8302e"), 0.7)
	K.cyl(rotor, 0.7, 0.8, 1.2, wood, Vector3(0, 0, -0.3), Vector3(90, 0, 0), 16)
	K.sphere(rotor, 0.55, K.mat(K.GOLD, 0.35), Vector3(0, 0, 0.35), Vector3(1, 1, 0.6))
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = TAU * i / 4.0 + PI / 4.0
		rotor.add_child(arm)
		K.rbox(arm, Vector3(9.0, 0.32, 0.32), wood, Vector3(4.6, 0, 0))
		var furled := i % 2 == 1
		var sail_h := 1.0 if furled else 1.7
		K.rbox(arm, Vector3(6.6, sail_h, 0.06), canvas, Vector3(5.3, sail_h * 0.5 + 0.12, 0.05), Vector3.ZERO, 0.03)
		for k in 7:
			K.rbox(arm, Vector3(0.09, 1.9, 0.09), wood, Vector3(2.2 + k * 1.05, 0.95, 0.1), Vector3.ZERO, 0.03)
		K.rbox(arm, Vector3(6.6, 0.09, 0.09), wood, Vector3(5.3, 1.85, 0.1), Vector3.ZERO, 0.03)
		K.rbox(arm, Vector3(0.6, 1.9, 0.1), red, Vector3(8.9, 0.95, 0.08), Vector3.ZERO, 0.03)
	return rotor


# ---------------------------------------------------------------- page gate (base (0, 0.4, 57.5))

static func page_gate(n: Node3D) -> void:
	var b := K.body(n, "Collision")
	# Two book stacks (x +/-3.6) and the arch top (page_gate_top: top y 7.5 world -> local 7.1).
	K.shape_box(b, Vector3(2.0, 6.5, 2.0), Vector3(-3.6, 3.25, 0))
	K.shape_box(b, Vector3(2.0, 6.5, 2.0), Vector3(3.6, 3.25, 0))
	K.shape_box(b, Vector3(9.0, 0.6, 2.0), Vector3(0, 6.8, 0))
	if K.glb_visual(n, ["page_gate", "w1_page_gate"], 7.5):
		return
	var v := Node3D.new()
	v.name = "Visual"
	n.add_child(v)
	var covers := [Color("7a1f2e"), Color("2e6f8c"), Color("3f8f3a"), Color("c9a04a"), Color("8c5ce0"), Color("b84a32")]
	var page := K.mat(Color("f6ecd6"), 0.9)
	for sx in [-1.0, 1.0]:
		var y := 0.0
		for i in 6:
			var hh := 0.9 + fmod(i * 0.37, 0.4)
			var size := Vector3(2.3 - fmod(i * 0.13, 0.4), hh, 2.2 - fmod(i * 0.21, 0.3))
			var c := K.mat(covers[(i + (3 if sx > 0 else 0)) % covers.size()], 0.6)
			var rot := Vector3(0, (i * 17.0 + sx * 9.0) - 40.0 * floorf(i / 3.0), 0)
			K.rbox(v, size, c, Vector3(sx * 3.6, y + hh * 0.5, 0), rot, 0.12)
			K.rbox(v, Vector3(size.x - 0.1, hh * 0.8, size.z + 0.04), page, Vector3(sx * 3.6 + 0.08, y + hh * 0.5, 0), rot, 0.05)
			y += hh
	# Ribbon bookmark arching between the stacks, forked tail fluttering at one side.
	var ribbon := K.mat(K.RED_RIBBON, 0.45)
	for i in 13:
		var t := i / 12.0
		var x := lerpf(-3.6, 3.6, t)
		var yy := 6.5 + sin(t * PI) * 0.9
		var ang := rad_to_deg(atan(cos(t * PI) * 0.9 * PI / 7.2))
		K.rbox(v, Vector3(0.75, 0.22, 1.7), ribbon, Vector3(x, yy, 0), Vector3(0, 0, ang), 0.08)
	K.rbox(v, Vector3(0.7, 2.6, 0.12), ribbon, Vector3(4.4, 5.6, 0.9), Vector3(0, 0, -12))
	K.rbox(v, Vector3(0.7, 2.2, 0.12), ribbon, Vector3(4.9, 5.4, 0.95), Vector3(0, 0, -22))
	K.sphere(v, 0.3, K.mat(K.GOLD, 0.3), Vector3(0, 7.5, 0.85))


# ---------------------------------------------------------------- village well (base (2, 0.4, -3))

static func village_well(n: Node3D) -> void:
	var b := K.body(n, "Collision")
	K.shape_cyl(b, 1.3, 0.9, Vector3(0, 0.45, 0))
	K.shape_box(b, Vector3(0.25, 2.8, 0.25), Vector3(-1.1, 1.4, 0))
	K.shape_box(b, Vector3(0.25, 2.8, 0.25), Vector3(1.1, 1.4, 0))
	slope_box(b, 0.0, 2.8, Vector3(0, 2.6, 1.0), Vector3(0, 3.2, 0), 0.25)
	slope_box(b, 0.0, 2.8, Vector3(0, 2.6, -1.0), Vector3(0, 3.2, 0), 0.25)
	if K.glb_visual(n, ["wishing_well", "village_well", "w1_village_well"], 3.2):
		return
	var v := Node3D.new()
	v.name = "Visual"
	n.add_child(v)
	var stone := K.tex_mat("cobblestone", Color(1.05, 1.0, 0.95), 0.6)
	K.cyl(v, 1.3, 1.35, 0.9, stone, Vector3(0, 0.45, 0), Vector3.ZERO, 20)
	K.torus(v, 1.05, 1.38, K.mat(K.STONE), Vector3(0, 0.92, 0))
	K.cyl(v, 1.05, 1.05, 0.05, K.mat(Color("2f7fa3"), 0.2), Vector3(0, 0.55, 0), Vector3.ZERO, 20)
	var wood := K.mat(K.WOOD)
	for sx in [-1.0, 1.0]:
		K.rbox(v, Vector3(0.22, 2.8, 0.22), wood, Vector3(sx * 1.1, 1.4, 0))
	K.cyl(v, 0.1, 0.1, 2.4, wood, Vector3(0, 2.1, 0), Vector3(0, 0, 90), 8)
	var shingle := K.mat(Color("8c4a3a"), 0.7)
	slope_visual(v, 0.0, 3.0, Vector3(0, 2.5, 1.2), Vector3(0, 3.25, -0.02), 0.2, shingle, 0.06)
	slope_visual(v, 0.0, 3.0, Vector3(0, 2.5, -1.2), Vector3(0, 3.25, 0.02), 0.2, shingle, 0.06)
	K.cyl(v, 0.25, 0.2, 0.35, K.mat(Color("a8743f")), Vector3(0.3, 1.5, 0), Vector3.ZERO, 10)


# ---------------------------------------------------------------- arched footbridge (Page Lane over the stream)

static func arched_bridge(parent: Node3D) -> void:
	# Deck y(z) = 0.6 + 1.8 sin(pi (14 - z) / 8), z 14 -> 6, x -7.5..-4.5 (world coordinates).
	var b := K.body(parent, "ArchedBridge")
	var v := Node3D.new()
	v.name = "Visual"
	parent.add_child(v)
	var have_glb := K.glb_visual(v, ["stone_bridge", "arched_bridge", "w1_arched_bridge"], -1.0, 8.0) != null
	if have_glb:
		v.position = Vector3(-6.0, 0.0, 10.0)
		v.rotation_degrees.y = 90.0
	var segs := 16
	var stone := K.tex_mat("cobblestone", Color(1.02, 1.0, 0.96), 0.55)
	var wall := K.tex_mat("cliff_rock", Color(1.05, 1.02, 0.95), 0.4)
	for i in segs:
		var z0 := 14.5 - 9.0 * i / segs
		var z1 := 14.5 - 9.0 * (i + 1) / segs
		var y0 := _bridge_y(z0)
		var y1 := _bridge_y(z1)
		var a := Vector3(-6.0, y0, z0)
		var c := Vector3(-6.0, y1, z1)
		slope_box(b, -6.0, 3.0, a, c, 0.5)
		# Parapet walls (rails) as low invisible-ish walls.
		for sx in [-1.0, 1.0]:
			var cs := slope_box(b, -6.0 + sx * 1.6, 0.3, a + Vector3(0, 0.75, 0), c + Vector3(0, 0.75, 0), 0.75)
			cs.position.x = -6.0 + sx * 1.6
		if not have_glb:
			slope_visual(v, -6.0, 3.0, a, c, 0.6, stone, 0.08)
			for sx in [-1.0, 1.0]:
				var mi := slope_visual(v, -6.0, 0.35, a + Vector3(0, 0.6, 0), c + Vector3(0, 0.6, 0), 0.6, wall, 0.12)
				mi.position.x = -6.0 + sx * 1.62
	if not have_glb:
		# Arch underside and abutments.
		for sx in [-1.0, 1.0]:
			K.rbox(v, Vector3(3.4, 1.4, 1.6), wall, Vector3(-6.0, 0.0, 10.0 + sx * 4.4), Vector3.ZERO, 0.3)
		var mossy := K.mat(K.MOSS)
		K.rbox(v, Vector3(3.3, 0.15, 1.2), mossy, Vector3(-6.0, 0.62, 14.6), Vector3.ZERO, 0.06)


static func _bridge_y(z: float) -> float:
	var t := clampf((14.0 - z) / 8.0, 0.0, 1.0)
	if z > 14.0:
		return 0.6 - (z - 14.0) * 0.3
	if z < 6.0:
		return 0.6 - (6.0 - z) * 0.3
	return 0.6 + 1.8 * sin(PI * t)

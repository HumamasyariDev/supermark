class_name HubArchitecture
extends RefCounted
## Mak Manor Grand Library: deterministic procedural shell (Docs/levels/HUB.md section 3, ids A01-A26).
## Builds visual meshes and collision under one parent at runtime. Every number here comes from the level plan
## (metres; x east, y up, z south; theta = polar angle from north clockwise, pos = (r sin t, y, -r cos t)).

const R_IN := 16.0
const WALL_SPLIT_Y := 8.95
const R_WALL := 16.9
const H_WALL := 16.0
const GALLERY_Y := 4.5
const GALLERY_R_IN := 12.5

## Wall openings: [theta0, theta1, y0, y1].
const OPENINGS := [
	[172.8, 187.2, 0.0, 4.0],  # entrance
	[175.7, 184.3, 4.5, 8.0],  # French doors to the outdoor balcony
	[246.0, 254.0, 5.2, 8.3],  # west window 1
	[286.0, 294.0, 5.2, 8.3],  # west window 2
	[355.7, 360.0, 4.5, 8.3], [0.0, 4.3, 4.5, 8.3],  # Wolf's Door
	[352.8, 360.0, 9.0, 14.5], [0.0, 7.2, 9.0, 14.5],  # stained glass
]

const GROUND_SHELF_GAPS := [[170.0, 190.0], [260.0, 280.0]]
const GALLERY_SHELF_GAPS := [[174.0, 186.0], [246.0, 254.0], [262.0, 278.0], [286.0, 294.0], [354.0, 366.0]]
# r1 QA round 2: cornice A runs 1.5 degrees further (to 129.5) so a long jump started up to ~1.4 m before the edge
# still lands; singles are capped by the lintel above, so the shorter gap (18.5 degrees, 4.9 m) does not help them.
const CORNICE_WALKS := [[100.0, 129.5], [148.0, 168.0]]  # amendments R1.3 (gap was 20 degrees, 5.28 m)
const CORNICE_GAP := [128.0, 148.0]
const TOP_BALCONY := [172.0, 205.5]
const BALUSTRADE_GAPS := [[350.8, 369.2], [73.0, 107.0], [57.0, 63.0], [124.0, 132.0], [231.0, 239.0]]  # R1.6 gates are separate nodes
const BOOK_COLORS := [Color("7a1f2e"), Color("2f5d3a"), Color("26375e"), Color("d4a62a"), Color("ead8b0"), Color("2e8c8a"),
	Color("8a4e24"), Color("b84a32"), Color("4a2f6b"), Color("6e8a3a")]

static var _toon_cache: Dictionary = {}


# ------------------------------------------------------------------ materials

static func toon(tex_name: String, tint := Color.WHITE, tri_scale := -1.0, emission := Color.BLACK, emission_energy := 0.0) -> ShaderMaterial:
	var key := "%s_%s_%.2f_%s_%.2f" % [tex_name, tint.to_html(), tri_scale, emission.to_html(), emission_energy]
	if _toon_cache.has(key):
		return _toon_cache[key]
	var path := "res://assets/shaders/materials/toon_%s.tres" % tex_name
	var m: ShaderMaterial
	if ResourceLoader.exists(path):
		m = (load(path) as ShaderMaterial).duplicate() as ShaderMaterial
	else:
		m = ShaderMaterial.new()
		m.shader = load("res://assets/shaders/toon.gdshader")
		m.set_shader_parameter("triplanar", true)
	m.set_shader_parameter("albedo", tint)
	if tri_scale > 0.0:
		m.set_shader_parameter("triplanar_scale", tri_scale)
	if emission_energy > 0.0:
		m.set_shader_parameter("emission_color", emission)
		m.set_shader_parameter("emission_energy", emission_energy)
	_toon_cache[key] = m
	return m


static func flat_toon(color: Color, rim := 0.35, spec := 0.3) -> ShaderMaterial:
	var key := "flat_%s_%.2f_%.2f" % [color.to_html(), rim, spec]
	if _toon_cache.has(key):
		return _toon_cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/toon.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("triplanar", false)
	m.set_shader_parameter("rim_strength", rim)
	m.set_shader_parameter("spec_strength", spec)
	_toon_cache[key] = m
	return m


static func brass() -> StandardMaterial3D:
	return HubKit.mat(Color("c9a04a"), 0.3, 1.0, "hub_brass")


static func iron() -> StandardMaterial3D:
	return HubKit.mat(Color("2e2a2b"), 0.45, 0.8, "hub_iron")


# ------------------------------------------------------------------ node helpers

static func mi(parent: Node3D, mesh: Mesh, material: Material, node_name := "", xf := Transform3D.IDENTITY, shadows := true) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	if material:
		m.material_override = material
	if node_name != "":
		m.name = node_name
	m.transform = xf
	if not shadows:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


static func static_body(parent: Node3D, node_name: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = node_name
	b.collision_layer = 1
	b.collision_mask = 0
	parent.add_child(b)
	return b


## Basis whose -Z looks toward the hall centre from polar angle theta (local +X runs clockwise along the ring).
static func facing_centre(theta_deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(HubKit.yaw_facing_centre(theta_deg)))


## Basis with local X along `dir` (any slope) and local Y as close to world up as possible.
static func along(dir: Vector3) -> Basis:
	var x := dir.normalized()
	var z := x.cross(Vector3.UP).normalized()
	if z.length() < 0.01:
		z = Vector3.BACK
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


# ------------------------------------------------------------------ range helpers

## Splits [a, b] by removing the gap ranges (degrees, gaps may wrap past 360).
static func subtract_ranges(a: float, b: float, gaps: Array) -> Array:
	var out: Array = [[a, b]]
	for g in gaps:
		var g0: float = g[0]
		var g1: float = g[1]
		for shift: float in [-360.0, 0.0, 360.0]:
			var s0 := g0 + shift
			var s1 := g1 + shift
			var nxt: Array = []
			for r in out:
				var r0: float = r[0]
				var r1: float = r[1]
				if s1 <= r0 or s0 >= r1:
					nxt.append(r)
					continue
				if s0 > r0:
					nxt.append([r0, s0])
				if s1 < r1:
					nxt.append([s1, r1])
			out = nxt
	return out


# ------------------------------------------------------------------ build

static func build(root: Node3D, rng_seed := 1907) -> Node3D:
	var arch := Node3D.new()
	arch.name = "Architecture"
	root.add_child(arch)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var body := static_body(arch, "ShellCollision")
	_floor(arch, body)
	_wall(arch, body)
	_dome(arch)
	_gallery(arch, body)
	_book3_bay(arch, body)
	_columns(arch, body)
	_stairs(arch, body)
	_shelves(arch, body, rng)
	_upper_ledges(arch, body)
	_fireplace_breast(arch, body)
	_outdoor_balcony(arch, body)
	_balusters_commit(arch)
	HubDrumArt.build(arch)
	return arch


# A01 floor ----------------------------------------------------------------

static func _floor(arch: Node3D, body: StaticBody3D) -> void:
	var b := HubKit.Buf.new()
	HubKit.disc(b, R_IN + 0.2, 0.0, 96, Vector3.ZERO, 1.0)
	# r1 visual: the floor read saturated orange; pulled toward the plan's walnut (#5A3A22-#7A4E2E).
	# Fix r1b (visual): every wide shot was one orange-red band; ~20 % less saturated and a little lighter, so
	# the teal rug, gold acorns and burgundy daises separate from the boards.
	# Fix r2 (visual major): still one orange hue with the daises and carpet; a cooler multiplier pulls the boards
	# toward walnut #5C3A21 (about 0.55 saturation) so only the daises and the stair runner stay burgundy.
	var fm := toon("wood_planks", Color(0.46, 0.415, 0.46), 0.55).duplicate() as ShaderMaterial
	# The toon rim lit the floor at grazing angles: the far floor went milky cream (r1 visual). Floors get no rim.
	fm.set_shader_parameter("rim_strength", 0.04)
	fm.set_shader_parameter("spec_strength", 0.18)
	mi(arch, b.commit(), fm, "Floor")
	# Skirting: dark walnut ring at the shelf/wall foot where the ground shelves have gaps.
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = R_IN + 0.5
	cyl.height = 1.0
	cs.shape = cyl
	cs.position = Vector3(0, -0.5, 0)
	cs.name = "FloorDisc"
	body.add_child(cs)


# A02 wall -------------------------------------------------------------------

static func _wall(arch: Node3D, body: StaticBody3D) -> void:
	var cuts: Array[float] = [0.0, 360.0]
	for o in OPENINGS:
		for k in [0, 1]:
			var v: float = o[k]
			if not cuts.has(v):
				cuts.append(v)
	cuts.sort()
	var wall_b := HubKit.Buf.new()
	var plaster_b := HubKit.Buf.new()
	var outer_b := HubKit.Buf.new()
	for i in cuts.size() - 1:
		var a := cuts[i]
		var bb := cuts[i + 1]
		if bb - a < 0.001:
			continue
		var mid := (a + bb) * 0.5
		var solids: Array = [[0.0, H_WALL]]
		for o in OPENINGS:
			if mid > float(o[0]) and mid < float(o[1]):
				var nx: Array = []
				for s in solids:
					var s0: float = s[0]
					var s1: float = s[1]
					var o0: float = o[2]
					var o1: float = o[3]
					if o1 <= s0 or o0 >= s1:
						nx.append(s)
						continue
					if o0 > s0:
						nx.append([s0, o0])
					if o1 < s1:
						nx.append([o1, s1])
				solids = nx
		for s in solids:
			# r1 visual: the dark damask band above the gallery filled 30-40 % of every wide shot. Damask stays below the
			# cornice line (8.95); above it the wall is warm cream plaster like key art 08.
			var s0w: float = s[0]
			var s1w: float = s[1]
			if s0w < WALL_SPLIT_Y:
				HubKit.lathe(wall_b, HubKit.rect_profile(R_IN, R_WALL, s0w, minf(s1w, WALL_SPLIT_Y)), a, bb, 4.0, true, true, 30.0, 0.5)
			if s1w > WALL_SPLIT_Y:
				HubKit.lathe(plaster_b, HubKit.rect_profile(R_IN, R_WALL, maxf(s0w, WALL_SPLIT_Y), s1w), a, bb, 4.0, true, true, 30.0, 0.5)
			HubKit.lathe(outer_b, HubKit.rect_profile(R_WALL, R_WALL + 0.12, s[0], s[1]), a, bb, 4.0, true, true, 30.0, 0.5)
			HubKit.add_sector_collision(body, null, R_IN, R_WALL + 0.12, s[0], s[1], a, bb, 8.0, Vector3.ZERO, "Wall")
	mi(arch, wall_b.commit(), toon("damask_wallpaper", Color(0.62, 0.86, 0.8), 0.5), "WallInner")
	mi(arch, plaster_b.commit(), toon("plaster_wall", Color("e9d9bd"), 0.5), "WallPlaster")
	# Walnut pilasters every 22.5 deg above the cornice and a gilt frieze under the dome rim.
	var pil := HubKit.Buf.new()
	var k := 0
	while k < 16:
		var thp := 11.25 + 22.5 * float(k)
		k += 1
		var blocked := thp > 178.0 and thp < 200.0  # grandfather's portrait frame
		for o in OPENINGS:
			if thp > float(o[0]) - 3.0 and thp < float(o[1]) + 3.0 and float(o[3]) > WALL_SPLIT_Y:
				blocked = true
		if blocked:
			continue
		HubKit.rounded_box(pil, Vector3(0.55, 15.5 - WALL_SPLIT_Y, 0.22), 0.06, Transform3D(facing_centre(thp), HubKit.polar(R_IN - 0.08, thp, (WALL_SPLIT_Y + 15.5) * 0.5)))
	mi(arch, pil.commit(), toon("bookshelf_wood", Color(0.5, 0.33, 0.24), 0.6), "Pilasters")
	var fr := HubKit.Buf.new()
	HubKit.lathe(fr, HubKit.round_rect_profile(R_IN - 0.14, R_IN + 0.02, 15.1, 15.5, 0.03, 0.03, 0.04, 0.04), 0.0, 360.0, 3.0, true, false, 40.0)
	mi(arch, fr.commit(), brass(), "GiltFrieze")
	mi(arch, outer_b.commit(), toon("castle_stone", Color(1.0, 0.93, 0.82), 0.35), "WallOuter")
	# Window and door openings get a chunky walnut reveal so the cut edges never look raw.
	var frame := toon("bookshelf_wood", Color(0.75, 0.55, 0.42), 0.6)
	var fb := HubKit.Buf.new()
	for o in [[246.0, 254.0, 5.2, 8.3], [286.0, 294.0, 5.2, 8.3]]:
		_window_frame(fb, o[0], o[1], o[2], o[3])
		# Invisible glass so nobody hops out of the gallery windows.
		HubKit.add_sector_collision(body, null, R_IN - 0.05, R_IN + 0.3, o[2], o[3], o[0], o[1], 4.0, Vector3.ZERO, "WinBlock")
	mi(arch, fb.commit(), frame, "WindowFrames")
	# A deep shadowed vestibule behind the Wolf's Door so the opening reads as a passage.
	var back := HubKit.Buf.new()
	HubKit.rounded_box(back, Vector3(3.2, 4.2, 0.3), 0.05, Transform3D(Basis(), Vector3(0, 6.4, -17.25)))
	mi(arch, back.commit(), HubKit.mat(Color("1d1210"), 0.9), "DoorVestibule")


static func _window_frame(fb: HubKit.Buf, th0: float, th1: float, y0: float, y1: float) -> void:
	var p0 := HubKit.polar(R_IN - 0.05, th0)
	var p1 := HubKit.polar(R_IN - 0.05, th1)
	var mid := (p0 + p1) * 0.5
	var dir := (p1 - p0)
	var w := dir.length()
	var bs := along(dir)
	var h := y1 - y0
	# Sill, head, jambs, a cross mullion.
	HubKit.rounded_box(fb, Vector3(w + 0.5, 0.22, 0.5), 0.06, Transform3D(bs, mid + Vector3(0, y0 - 0.06, 0)))
	HubKit.rounded_box(fb, Vector3(w + 0.5, 0.3, 0.45), 0.08, Transform3D(bs, mid + Vector3(0, y1 + 0.1, 0)))
	for sx in [-0.5, 0.5]:
		HubKit.rounded_box(fb, Vector3(0.22, h + 0.2, 0.45), 0.06, Transform3D(bs, mid + bs.x * (w * sx) + Vector3(0, y0 + h * 0.5, 0)))
	HubKit.rounded_box(fb, Vector3(0.1, h, 0.12), 0.03, Transform3D(bs, mid + Vector3(0, y0 + h * 0.5, 0)))
	HubKit.rounded_box(fb, Vector3(w, 0.1, 0.12), 0.03, Transform3D(bs, mid + Vector3(0, y0 + h * 0.62, 0)))


# A03 dome ---------------------------------------------------------------------

static func _dome(arch: Node3D) -> void:
	var prof := PackedVector2Array()
	for i in 13:
		var a := deg_to_rad(90.0 * float(i) / 12.0)
		prof.append(Vector2(2.5 + 14.5 * cos(a), 16.0 + 6.0 * pow(sin(a), 0.8)))
	var b := HubKit.Buf.new()
	HubKit.lathe(b, prof, 0.0, 360.0, 6.0, false, false, 80.0, 1.0)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/environment/hub/hub_dome.gdshader")
	sm.set_shader_parameter("rim_len", 16.0)
	mi(arch, b.commit(), sm, "Dome")
	# Gilded rim moulding where the dome meets the wall, and a ring around the oculus.
	var mb := HubKit.Buf.new()
	HubKit.lathe(mb, HubKit.round_rect_profile(15.55, 16.05, 15.55, 16.2, 0.0, 0.15, 0.2, 0.1), 0.0, 360.0, 4.0, true, false, 45.0)
	HubKit.lathe(mb, HubKit.round_rect_profile(2.3, 2.75, 21.8, 22.2, 0.1, 0.15, 0.15, 0.1), 0.0, 360.0, 10.0, true, false, 45.0)
	mi(arch, mb.commit(), brass(), "DomeMouldings")
	# Ribs: eight walnut ribs sweep up the dome like an umbrella of a storybook pavilion.
	var rb := HubKit.Buf.new()
	for k in 8:
		var th := 22.5 + 45.0 * float(k)
		var rp := PackedVector2Array()
		for i in 13:
			var a := deg_to_rad(90.0 * float(i) / 12.0)
			rp.append(Vector2(2.5 + 14.45 * cos(a), 16.0 + 6.0 * pow(sin(a), 0.8) - 0.03))
		for i in rp.size() - 1:
			var p0 := HubKit.polar(rp[i].x, th, rp[i].y)
			var p1 := HubKit.polar(rp[i + 1].x, th, rp[i + 1].y)
			var d := p1 - p0
			HubKit.rounded_box(rb, Vector3(d.length() + 0.08, 0.22, 0.32), 0.08, Transform3D(along(d), (p0 + p1) * 0.5))
	# r1 visual round 2: gilt coffer ribs (#C9A04A) instead of walnut, with rosettes (HubDrumArt).
	mi(arch, rb.commit(), brass(), "DomeRibs")


# A05-A06 gallery ---------------------------------------------------------------

static func _gallery(arch: Node3D, body: StaticBody3D) -> void:
	var b := HubKit.Buf.new()
	HubKit.lathe(b, HubKit.round_rect_profile(GALLERY_R_IN, R_IN + 0.05, GALLERY_Y - 0.4, GALLERY_Y, 0.0, 0.0, 0.06, 0.0), 0.0, 360.0, 3.0, true, false, 40.0)
	mi(arch, b.commit(), toon("wood_planks", Color(0.72, 0.54, 0.45), 0.55), "GalleryFloor")
	HubKit.add_sector_collision(body, null, GALLERY_R_IN, R_IN, GALLERY_Y - 0.4, GALLERY_Y, 0.0, 360.0, 6.0, Vector3.ZERO, "Gallery")
	# Carved fascia under the gallery edge with a gilt bead.
	var f := PackedVector2Array([Vector2(12.45, 3.45), Vector2(12.75, 3.45), Vector2(12.75, 4.12), Vector2(12.36, 4.12),
		Vector2(12.26, 4.04), Vector2(12.26, 3.9), Vector2(12.34, 3.8), Vector2(12.3, 3.66), Vector2(12.36, 3.52)])
	var fb := HubKit.Buf.new()
	HubKit.lathe(fb, f, 0.0, 360.0, 3.0, true, false, 50.0, 0.5)
	mi(arch, fb.commit(), toon("bookshelf_wood", Color(0.5, 0.34, 0.27), 0.9), "GalleryFascia")
	var gb := HubKit.Buf.new()
	HubKit.lathe(gb, HubKit.round_rect_profile(12.22, 12.3, 3.86, 3.94, 0.03, 0.03, 0.03, 0.03), 0.0, 360.0, 3.0, true, false, 50.0)
	mi(arch, gb.commit(), brass(), "GalleryGiltBead")
	# Balustrade at r 12.6 with gaps for the stair head, the Book 3 bay and ladder L1.
	for rr in subtract_ranges(0.0, 360.0, BALUSTRADE_GAPS):
		var pts: Array[Vector3] = []
		var a: float = rr[0]
		var e: float = rr[1]
		var n := maxi(1, int(ceil((e - a) / 3.0)))
		for i in n + 1:
			pts.append(HubKit.polar(12.65, a + (e - a) * float(i) / float(n), GALLERY_Y))
		rail(arch, body, pts, 1.0, "wood")


# A07 Book 3 bay ------------------------------------------------------------------

static func _book3_bay(arch: Node3D, body: StaticBody3D) -> void:
	var c := Vector3(12.5, 0, 0)
	var b := HubKit.Buf.new()
	HubKit.lathe(b, HubKit.round_rect_profile(0.0, 4.5, GALLERY_Y - 0.4, GALLERY_Y, 0.0, 0.0, 0.0, 0.0), 180.0, 360.0, 6.0, true, false, 40.0, 1.0, Color.WHITE, c)
	mi(arch, b.commit(), toon("wood_planks", Color(0.72, 0.54, 0.45), 0.55), "BayFloor")
	var fb := HubKit.Buf.new()
	var f := PackedVector2Array([Vector2(4.2, 3.45), Vector2(4.5, 3.45), Vector2(4.5, 4.12), Vector2(4.6, 4.12),
		Vector2(4.68, 4.04), Vector2(4.68, 3.9), Vector2(4.6, 3.8), Vector2(4.62, 3.66), Vector2(4.55, 3.52)])
	# Fascia profile mirrored outward (the bay edge faces away from its own centre).
	var f2 := PackedVector2Array()
	for p in f:
		f2.append(Vector2(p.x, p.y))
	f2 = PackedVector2Array([Vector2(4.2, 3.45), Vector2(4.6, 3.5), Vector2(4.66, 3.66), Vector2(4.6, 3.8), Vector2(4.68, 3.92), Vector2(4.6, 4.12), Vector2(4.2, 4.12)])
	HubKit.lathe(fb, f2, 180.0, 360.0, 6.0, true, false, 50.0, 0.5, Color.WHITE, c)
	mi(arch, fb.commit(), toon("bookshelf_wood", Color(0.7, 0.48, 0.34), 0.7), "BayFascia")
	HubKit.add_sector_collision(body, null, 0.0, 4.5, GALLERY_Y - 0.4, GALLERY_Y, 180.0, 360.0, 15.0, c, "Bay")
	# Rail on the arc, only where it stands proud of the gallery ring.
	var pts: Array[Vector3] = []
	for i in 61:
		var th := 180.0 + 180.0 * float(i) / 60.0
		var p := c + HubKit.polar(4.35, th, GALLERY_Y)
		if Vector2(p.x, p.z).length() < 12.62:
			pts.append(p)
		elif pts.size() > 1:
			rail(arch, body, pts, 1.0, "wood")
			pts = []
		else:
			pts = []
	if pts.size() > 1:
		rail(arch, body, pts, 1.0, "wood")


# A08 columns ------------------------------------------------------------------------

static func _columns(arch: Node3D, body: StaticBody3D) -> void:
	var prof := PackedVector2Array([Vector2(0.46, 0.0), Vector2(0.46, 0.16), Vector2(0.38, 0.26), Vector2(0.31, 0.42),
		Vector2(0.27, 2.0), Vector2(0.29, 3.5), Vector2(0.34, 3.66), Vector2(0.44, 3.82), Vector2(0.5, 3.96), Vector2(0.5, 4.1)])
	var b := HubKit.Buf.new()
	for k in 8:
		var th := 22.5 + 45.0 * float(k)
		if th == 157.5 or th == 202.5:
			continue  # the two entrance columns are left out so the hero shot (StoryCam_A_v2) sees Book 1
		var p := HubKit.polar(12.6, th)
		HubKit.turned(b, prof, 20, p, Color.WHITE, 50.0)
		HubKit.add_cyl_collision(body, null, 0.32, 4.1, p + Vector3(0, 2.05, 0), "Col%d" % k)
	mi(arch, b.commit(), toon("bookshelf_wood", Color(0.5, 0.34, 0.27), 1.6), "Columns")
	var gb := HubKit.Buf.new()
	for k in 8:
		if k == 3 or k == 4:
			continue
		var p := HubKit.polar(12.6, 22.5 + 45.0 * float(k))
		HubKit.lathe(gb, HubKit.round_rect_profile(0.27, 0.33, 3.45, 3.55, 0.03, 0.03, 0.03, 0.03), 0.0, 360.0, 20.0, true, false, 50.0, 1.0, Color.WHITE, p)
		HubKit.lathe(gb, HubKit.round_rect_profile(0.3, 0.4, 0.4, 0.48, 0.03, 0.03, 0.03, 0.03), 0.0, 360.0, 20.0, true, false, 50.0, 1.0, Color.WHITE, p)
	mi(arch, gb.commit(), brass(), "ColumnRings")


# A14-A17 grand stair ------------------------------------------------------------

static func _stairs(arch: Node3D, body: StaticBody3D) -> void:
	var tread := HubKit.Buf.new()
	var riser := HubKit.Buf.new()
	# Flight 1: 9 solid steps, 0.5 deep, 0.25 rise, 5.0 wide.
	for i in range(1, 10):
		var z0 := -3.0 - float(i - 1) * 0.5
		var top := 0.25 * float(i)
		HubKit.rounded_box(riser, Vector3(5.0, top, 0.5), 0.03, Transform3D(Basis(), Vector3(0, top * 0.5 - 0.02, z0 - 0.25)))
		HubKit.rounded_box(tread, Vector3(5.1, 0.07, 0.58), 0.03, Transform3D(Basis(), Vector3(0, top - 0.02, z0 - 0.27)))
	# Landing.
	HubKit.rounded_box(riser, Vector3(8.0, 0.3, 1.5), 0.05, Transform3D(Basis(), Vector3(0, 2.1, -8.25)))
	HubKit.rounded_box(tread, Vector3(8.1, 0.07, 1.58), 0.03, Transform3D(Basis(), Vector3(0, 2.23, -8.25)))
	# Flight 2: 9 steps of 0.389 m to the gallery (open underneath: the nook).
	var d2 := 3.5 / 9.0
	for i in range(1, 10):
		var z0 := -9.0 - float(i - 1) * d2
		var top := 2.25 + 0.25 * float(i)
		HubKit.rounded_box(riser, Vector3(4.0, 0.55, d2), 0.03, Transform3D(Basis(), Vector3(0, top - 0.275, z0 - d2 * 0.5)))
		HubKit.rounded_box(tread, Vector3(4.1, 0.07, d2 + 0.08), 0.03, Transform3D(Basis(), Vector3(0, top - 0.02, z0 - d2 * 0.5 - 0.02)))
	mi(arch, riser.commit(), toon("bookshelf_wood", Color(0.55, 0.38, 0.3), 0.9), "StairBody")
	# The runner: a burgundy carpet down the middle of both flights.
	mi(arch, tread.commit(), toon("wood_planks", Color(0.7, 0.52, 0.42), 0.6), "StairTreads")
	var run := HubKit.Buf.new()
	for i in range(1, 10):
		var z0 := -3.0 - float(i - 1) * 0.5
		var top := 0.25 * float(i)
		HubKit.rounded_box(run, Vector3(2.4, 0.02, 0.5), 0.01, Transform3D(Basis(), Vector3(0, top + 0.025, z0 - 0.25)))
		HubKit.rounded_box(run, Vector3(2.4, 0.25, 0.02), 0.01, Transform3D(Basis(), Vector3(0, top - 0.125, z0 + 0.0)))
	HubKit.rounded_box(run, Vector3(2.4, 0.02, 1.5), 0.01, Transform3D(Basis(), Vector3(0, 2.29, -8.25)))
	for i in range(1, 10):
		var z0 := -9.0 - float(i - 1) * d2
		var top := 2.25 + 0.25 * float(i)
		HubKit.rounded_box(run, Vector3(2.0, 0.02, d2), 0.01, Transform3D(Basis(), Vector3(0, top + 0.025, z0 - d2 * 0.5)))
		HubKit.rounded_box(run, Vector3(2.0, 0.25, 0.02), 0.01, Transform3D(Basis(), Vector3(0, top - 0.125, z0)))
	mi(arch, run.commit(), toon("library_carpet", Color(1.0, 0.75, 0.75), 0.8), "StairRunner")
	# Collision as ramps (through the tread centres) plus the landing and a lip onto the gallery.
	var c1 := CollisionShape3D.new()
	c1.shape = HubKit.ramp_hull(Vector3(0, 0.0, -2.75), Vector3(0, 2.25, -7.25), 5.0, 0.3, true)
	c1.name = "Flight1"
	body.add_child(c1)
	HubKit.add_box_collision(body, null, Vector3(8.0, 0.3, 1.75), Transform3D(Basis(), Vector3(0, 2.1, -8.125)), "Landing")
	var c2 := CollisionShape3D.new()
	c2.shape = HubKit.ramp_hull(Vector3(0, 2.25, -8.805), Vector3(0, 4.5, -12.306), 4.0, 0.35)
	c2.name = "Flight2"
	body.add_child(c2)
	HubKit.add_box_collision(body, null, Vector3(4.0, 0.3, 0.7), Transform3D(Basis(), Vector3(0, 4.35, -12.45)), "StairHead")
	# Nook back panel with wainscot.
	var nb := HubKit.Buf.new()
	HubKit.rounded_box(nb, Vector3(4.0, 3.6, 0.2), 0.05, Transform3D(Basis(), Vector3(0, 1.8, -12.5)))
	mi(arch, nb.commit(), toon("bookshelf_wood", Color(0.6, 0.42, 0.3), 0.7), "NookPanel")
	HubKit.add_box_collision(body, null, Vector3(4.0, 3.6, 0.2), Transform3D(Basis(), Vector3(0, 1.8, -12.5)), "NookPanel")
	# Rails: both sides of both flights and round the landing.
	for sx in [-1.0, 1.0]:
		rail(arch, body, [Vector3(sx * 2.55, 0.25, -3.05), Vector3(sx * 2.55, 2.25, -7.45)] as Array[Vector3], 1.0, "wood", true)
		rail(arch, body, [Vector3(sx * 2.55, 2.25, -7.45), Vector3(sx * 4.0, 2.25, -7.45)] as Array[Vector3], 1.0, "wood", true)
		rail(arch, body, [Vector3(sx * 4.0, 2.25, -9.0), Vector3(sx * 2.05, 2.25, -9.0)] as Array[Vector3], 1.0, "wood", true)
		rail(arch, body, [Vector3(sx * 2.05, 2.25, -9.0), Vector3(sx * 2.05, 4.5, -12.3)] as Array[Vector3], 1.0, "wood", true)
	# Newel posts with brass lamp globes at the foot of the stair.
	var nwb := HubKit.Buf.new()
	var prof := PackedVector2Array([Vector2(0.24, 0.0), Vector2(0.24, 0.2), Vector2(0.17, 0.3), Vector2(0.15, 1.0), Vector2(0.22, 1.12), Vector2(0.22, 1.25), Vector2(0.12, 1.32)])
	for sx in [-1.0, 1.0]:
		HubKit.turned(nwb, prof, 16, Vector3(sx * 2.6, 0, -3.0))
		HubKit.add_cyl_collision(body, null, 0.24, 1.3, Vector3(sx * 2.6, 0.65, -3.0), "Newel")
	mi(arch, nwb.commit(), toon("bookshelf_wood", Color(0.7, 0.48, 0.34), 0.7), "Newels")


# A04, A09, A10 shelves --------------------------------------------------------------

static var _book_xforms: Array[Transform3D] = []
static var _book_cols: Array[Color] = []


static func _shelves(arch: Node3D, body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	_book_xforms.clear()
	_book_cols.clear()
	var wood := HubKit.Buf.new()
	var backs := HubKit.Buf.new()
	var ground_rows := [0.26, 0.86, 1.46, 2.06, 2.66, 3.26]
	var gallery_rows := [4.72, 5.34, 5.96, 6.58, 7.2, 7.82]
	for rr in subtract_ranges(0.0, 360.0, GROUND_SHELF_GAPS):
		_shelf_band(wood, backs, rr[0], rr[1], 0.0, 4.1, ground_rows, 0.6, rng)
		HubKit.add_sector_collision(body, null, 15.2, R_IN, 0.0, 4.1, rr[0], rr[1], 8.0, Vector3.ZERO, "ShelfG")
	for rr in subtract_ranges(0.0, 360.0, GALLERY_SHELF_GAPS + [CORNICE_GAP]):
		_shelf_band(wood, backs, rr[0], rr[1], GALLERY_Y, 8.5, gallery_rows, 0.62, rng)
		if is_equal_approx(float(rr[0]), float(CORNICE_GAP[1])):
			# Fix r1b (gap blocker, traced by the hub_verify gap probe): the upper shelf block that ends at theta 148
			# has its top at 8.5 under cornice B, and its gap-facing end face was the ledge that single jumps on an
			# inward arc grabbed. Its first 2.5 degrees refuse ledge grabs (player meta no_ledge_grab).
			var sl := StaticBody3D.new()
			sl.name = "ShelfU_NoGrabEnd"
			sl.set_meta("no_ledge_grab", true)
			arch.add_child(sl)
			HubKit.add_sector_collision(sl, null, 15.2, R_IN, GALLERY_Y, 8.5, rr[0], float(rr[0]) + 2.5, 2.5, Vector3.ZERO, "ShelfUEnd")
			HubKit.add_sector_collision(body, null, 15.2, R_IN, GALLERY_Y, 8.5, float(rr[0]) + 2.5, rr[1], 8.0, Vector3.ZERO, "ShelfU")
		else:
			HubKit.add_sector_collision(body, null, 15.2, R_IN, GALLERY_Y, 8.5, rr[0], rr[1], 8.0, Vector3.ZERO, "ShelfU")
	# Fix r1 blocker (HUB-1 gap): under the cornice gap the top of the gallery bookcase was a flat floor at y 8.5
	# (r 15.2-16), so single jumps landed in the gap and walked across. Here the huff knocked the top rows loose
	# (they are the lintel above): the bookcase stops at y 6.0 and a collapsed board slopes from (15.15, 6.0) up to
	# (16.0, 8.45). That slope is 71 degrees (normal y 0.33), never a floor; anything that drops into the gap slides
	# inward onto the gallery at y 4.5. It stays below y 8.5, so the long jump's arc above it is untouched.
	_shelf_band(wood, backs, CORNICE_GAP[0], CORNICE_GAP[1], GALLERY_Y, 6.0, [4.72, 5.34], 0.62, rng)
	HubKit.add_sector_collision(body, null, 15.2, R_IN, GALLERY_Y, 6.0, CORNICE_GAP[0], CORNICE_GAP[1], 8.0, Vector3.ZERO, "ShelfUGap")
	var slope_prof := PackedVector2Array([Vector2(15.15, 5.95), Vector2(16.0, 5.95), Vector2(16.0, 8.45)])
	var slope := HubKit.Buf.new()
	HubKit.lathe(slope, slope_prof, CORNICE_GAP[0], CORNICE_GAP[1], 2.0, true, true, 30.0, 0.5)
	mi(arch, slope.commit(), toon("bookshelf_wood", Color(0.36, 0.24, 0.19), 0.9), "GapCollapsedBoard")
	var g0: float = CORNICE_GAP[0]
	var gspan: float = CORNICE_GAP[1] - CORNICE_GAP[0]
	for i in 5:
		var a := g0 + gspan * float(i) / 5.0
		var b := g0 + gspan * float(i + 1) / 5.0
		var pts := PackedVector3Array()
		for th in [a, b]:
			pts.append(HubKit.polar(15.15, th, 5.95))
			pts.append(HubKit.polar(16.0, th, 5.95))
			pts.append(HubKit.polar(16.0, th, 8.45))
		var sh := ConvexPolygonShape3D.new()
		sh.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = sh
		cs.name = "GapSlope%d" % i
		body.add_child(cs)
	mi(arch, wood.commit(), toon("bookshelf_wood", Color(0.6, 0.42, 0.34), 0.9), "ShelfCarcass")
	mi(arch, backs.commit(), HubKit.mat(Color("2a1810"), 0.9), "ShelfBacks")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	mm.instance_count = _book_xforms.size()
	for i in _book_xforms.size():
		mm.set_instance_transform(i, _book_xforms[i])
		mm.set_instance_color(i, _book_cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BookSpines"
	mmi.multimesh = mm
	# Fix r2 (visual major, D032): painted spines (gilt bands, title blocks, worn tops) instead of flat colour boxes.
	var bmat := ShaderMaterial.new()
	bmat.shader = load("res://assets/environment/hub/hub_book_spine.gdshader")
	mmi.material_override = bmat
	# Fix r2 (QA major, performance): the spines are small; no shadow casting.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arch.add_child(mmi)


static func _shelf_band(wood: HubKit.Buf, backs: HubKit.Buf, th0: float, th1: float, y0: float, y1: float, rows: Array, row_h: float, rng: RandomNumberGenerator) -> void:
	var span := th1 - th0
	var n := maxi(1, int(round(span / 7.5)))
	var bay := span / float(n)
	# Back panel and plinth/crown as continuous lathes.
	HubKit.lathe(backs, HubKit.rect_profile(15.92, 16.0, y0, y1), th0, th1, 3.0, true, false)
	HubKit.lathe(wood, HubKit.round_rect_profile(15.18, 15.95, y0, y0 + 0.24, 0.0, 0.03, 0.03, 0.0), th0, th1, 3.0, true, true, 40.0, 0.5)
	HubKit.lathe(wood, HubKit.round_rect_profile(15.12, 15.95, y1 - 0.26, y1, 0.0, 0.04, 0.06, 0.04), th0, th1, 3.0, true, true, 40.0, 0.5)
	for r in rows:
		var ry: float = r
		if ry <= y0 + 0.2:
			continue
		HubKit.lathe(wood, HubKit.round_rect_profile(15.24, 15.95, ry - 0.05, ry, 0.0, 0.02, 0.02, 0.0), th0, th1, 3.0, true, false, 40.0, 0.5)
	var circ := deg_to_rad(1.0) * 15.6
	for k in n + 1:
		var th := th0 + bay * float(k)
		var p := HubKit.polar(15.56, th, (y0 + y1) * 0.5)
		HubKit.rounded_box(wood, Vector3(0.14, y1 - y0, 0.8), 0.04, Transform3D(facing_centre(th), p))
	# Books per bay and row.
	for k in n:
		var a0 := th0 + bay * float(k) + 0.1 / circ
		var a1 := th0 + bay * float(k + 1) - 0.1 / circ
		for r in rows:
			var base: float = r
			var top_lim := base + row_h - 0.1
			if top_lim > y1 - 0.26:
				top_lim = y1 - 0.26
			var avail := top_lim - base
			if avail < 0.2:
				continue
			var th := a0
			var lean_next := false
			while th < a1:
				var w := rng.randf_range(0.06, 0.15)
				var dth := w / circ
				if th + dth > a1:
					break
				if rng.randf() < 0.05:
					th += dth * 2.0
					lean_next = true
					continue
				var h := clampf(rng.randf_range(0.55, 0.92) * avail, 0.18, avail - 0.02)
				var d := rng.randf_range(0.42, 0.58)
				var mid_th := th + dth * 0.5
				var bs := facing_centre(mid_th)
				var pos := HubKit.polar(15.9 - d * 0.5, mid_th, base + h * 0.5)
				var basis := bs
				if lean_next:
					basis = bs * Basis(Vector3.BACK, deg_to_rad(rng.randf_range(-16.0, 16.0)))
					lean_next = false
				_book_xforms.append(Transform3D(basis * Basis.from_scale(Vector3(w * 0.92, h, d)), pos))
				var col: Color = BOOK_COLORS[rng.randi() % BOOK_COLORS.size()]
				col = col.lightened(rng.randf_range(-0.08, 0.12)) if rng.randf() < 0.5 else col.darkened(rng.randf_range(0.0, 0.18))
				_book_cols.append(col)
				th += dth


# A10-A13 upper ledges: cap, cornice walk, top balcony, chimney fins ------------------

static func _upper_ledges(arch: Node3D, body: StaticBody3D) -> void:
	var wood := HubKit.Buf.new()
	# A10 cap: crown everywhere above the gallery shelves; collision is a steep wedge so it cannot be stood on.
	# The cap stops at the HUB-1 gap (r1 critique blocker): no moulding visual and no wedge collision over theta 128-148,
	# so the void reads as a void and a bonked single jump has nothing to land on.
	var cap_ranges := subtract_ranges(0.0, 360.0, GALLERY_SHELF_GAPS + [CORNICE_GAP])
	for rr in cap_ranges:
		HubKit.lathe(wood, PackedVector2Array([Vector2(15.1, 8.5), Vector2(16.0, 8.5), Vector2(16.0, 8.95), Vector2(15.75, 8.95), Vector2(15.3, 8.7)]), rr[0], rr[1], 3.0, true, true, 30.0, 0.5)
		for piece in subtract_ranges(rr[0], rr[1], CORNICE_WALKS + [TOP_BALCONY]):
			_wedge_collision(body, piece[0], piece[1])
	# A11 cornice walks r 14.4-16 at 8.5, with corbels.
	for cw in CORNICE_WALKS:
		HubKit.lathe(wood, HubKit.round_rect_profile(14.4, 16.0, 8.2, 8.5, 0.0, 0.0, 0.05, 0.08), cw[0], cw[1], 2.0, true, true, 40.0, 0.5)
		if is_equal_approx(float(cw[0]), float(CORNICE_GAP[1])):
			# Fix r1b (gap blocker): with cornice A running to 129.5, single jumps on an inward arc hit cornice B's
			# gap-facing end face and ledge-grabbed it (QA exploit rerun 15:06Z: 4 of 4 arcs ended in ledge_hang at
			# theta 146.6). The first 2.5 degrees of cornice B are a separate body that refuses ledge grabs (player
			# meta no_ledge_grab); landing on top is unchanged, so the long jump still lands there.
			var lip := StaticBody3D.new()
			lip.name = "CorniceB_NoGrabLip"
			lip.set_meta("no_ledge_grab", true)
			arch.add_child(lip)
			HubKit.add_sector_collision(lip, null, 14.4, R_IN, 8.2, 8.5, cw[0], cw[0] + 2.5, 2.5, Vector3.ZERO, "CorniceLip")
			HubKit.add_sector_collision(body, null, 14.4, R_IN, 8.2, 8.5, cw[0] + 2.5, cw[1], 6.0, Vector3.ZERO, "Cornice")
		else:
			HubKit.add_sector_collision(body, null, 14.4, R_IN, 8.2, 8.5, cw[0], cw[1], 6.0, Vector3.ZERO, "Cornice")
		var th: float = cw[0] + 2.0
		while th < float(cw[1]) - 1.0:
			HubKit.rounded_box(wood, Vector3(0.18, 0.55, 0.9), 0.06, Transform3D(facing_centre(th), HubKit.polar(15.0, th, 7.92)))
			th += 5.0
	# Broken ends of the cornice gap (splintered stubs).
	for th in [float(CORNICE_WALKS[0][1]), float(CORNICE_WALKS[1][0])]:
		HubKit.rounded_box(wood, Vector3(0.3, 0.36, 1.4), 0.04, Transform3D(facing_centre(th) * Basis(Vector3.BACK, deg_to_rad(8.0 if th < 140.0 else -8.0)), HubKit.polar(15.2, th, 8.3)))
	# A30 fallen-shelf lintel (amendments R2.1): a section of upper shelving knocked loose by the huff hangs over the
	# gap from y 11.85 to 13.35. A long jump (apex 1.88 m) passes under it; single, double and triple jumps bonk.
	var lint := HubKit.Buf.new()
	HubKit.lathe(lint, HubKit.round_rect_profile(14.4, 16.0, 11.85, 13.35, 0.06, 0.06, 0.08, 0.08), 120.0, 150.0, 2.0, true, true, 40.0, 0.5)
	HubArchitecture.mi(arch, lint.commit(), toon("bookshelf_wood", Color(0.6, 0.42, 0.34), 0.9), "FallenShelfLintel")
	HubKit.add_sector_collision(body, null, 14.4, 16.0, 11.85, 13.35, 120.0, 150.0, 2.0, Vector3.ZERO, "Lintel")
	# r1 critique blocker: single jumps that bowed inward (r 13.0-13.9) passed beside the lintel and ledge-grabbed cornice B.
	# A second fallen board hangs inward from the lintel to r 12.6 on chains, with a fringe of dangling books, so the
	# whole air space above the gap is capped at y 11.85 (long jump head 11.63 still passes).
	var lint2 := HubKit.Buf.new()
	HubKit.lathe(lint2, HubKit.round_rect_profile(12.7, 14.45, 12.0, 12.35, 0.05, 0.05, 0.06, 0.06), 121.0, 149.0, 2.0, true, true, 40.0, 0.5)
	HubArchitecture.mi(arch, lint2.commit(), toon("bookshelf_wood", Color(0.55, 0.38, 0.3), 0.9), "FallenShelfLintelInner")
	# r1 feel round 2 blocker: a jump + dive on an inward arc (r 13.6) still reached cornice B under the 11.85 board.
	# Inside r 14.2 the cap now comes down to y 11.3 (the long, dangling book fringe below); the long-jump lane
	# (r 14.55 and out, capsule edge 14.2+) keeps the 11.85 clearance, so the long jump is untouched.
	HubKit.add_sector_collision(body, null, 12.6, 14.2, 11.3, 12.35, 120.0, 150.0, 2.0, Vector3.ZERO, "LintelInner")
	HubKit.add_sector_collision(body, null, 14.2, 14.45, 11.85, 12.35, 120.0, 150.0, 2.0, Vector3.ZERO, "LintelInnerLip")
	var lb := HubKit.Buf.new()
	lb.use_color = true
	var lrng := RandomNumberGenerator.new()
	lrng.seed = 120
	var lth := 120.6
	while lth < 149.4:
		var w := lrng.randf_range(0.07, 0.15)
		var hh := lrng.randf_range(0.6, 1.05)
		var col: Color = BOOK_COLORS[lrng.randi() % BOOK_COLORS.size()]
		HubKit.rounded_box(lb, Vector3(w, hh, 0.5), 0.015, Transform3D(facing_centre(lth), HubKit.polar(14.62, lth, 12.05 + hh * 0.5)), 1, col)
		lth += rad_to_deg(w / 14.6) * 1.05
	# Fringe of books dangling from the inner board's lip (they hang by their ribbons, tilted).
	lth = 121.5
	while lth < 148.5:
		var w2 := lrng.randf_range(0.08, 0.14)
		var h2 := lrng.randf_range(0.5, 0.72)
		var col2: Color = BOOK_COLORS[lrng.randi() % BOOK_COLORS.size()]
		var tilt := Basis(Vector3.BACK, lrng.randf_range(-0.25, 0.25))
		# Long enough to read as the new cap (bottoms at about y 11.3, matching the collision).
		HubKit.rounded_box(lb, Vector3(w2, h2, 0.32), 0.015, Transform3D(facing_centre(lth) * tilt, HubKit.polar(12.85, lth, 12.0 - h2 * 0.5 - 0.15)), 1, col2)
		HubKit.rounded_box(lb, Vector3(w2 * 0.9, h2 * 0.9, 0.3), 0.015, Transform3D(facing_centre(lth + 0.4) * tilt.inverse(), HubKit.polar(13.75, lth + 0.4, 12.0 - h2 * 0.45 - 0.15)), 1, col2.darkened(0.15))
		lth += lrng.randf_range(1.6, 2.6)
	# Torn ends of the cornice: loose pages hang off both stubs so the break reads from below.
	for th in [130.1, 147.4]:
		for k in 4:
			var pg := Basis(Vector3.BACK, lrng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, lrng.randf_range(-0.3, 0.3))
			HubKit.rounded_box(lb, Vector3(0.22, 0.3, 0.012), 0.004, Transform3D(facing_centre(th) * pg, HubKit.polar(14.6 + 0.4 * float(k), th, 7.98 - 0.08 * float(k % 2))), 1, Color("efe2c4"))
	HubArchitecture.mi(arch, lb.commit(), HubKit.vcol_mat(0.75, "lintel_books"), "LintelBooks")
	# Two iron chains run from the lintel up toward the dome ring (visual only).
	for th in [123.0, 147.0]:
		var c0 := HubKit.polar(15.2, th, 13.35)
		var c1 := HubKit.polar(13.6, th, 17.4)
		var dd := c1 - c0
		HubKit.rounded_box(wood, Vector3(dd.length(), 0.08, 0.08), 0.03, Transform3D(along(dd), (c0 + c1) * 0.5))
	# A12 top balcony at 9.7.
	HubKit.lathe(wood, HubKit.round_rect_profile(13.6, 16.0, 9.4, 9.7, 0.0, 0.0, 0.05, 0.1), TOP_BALCONY[0], TOP_BALCONY[1], 2.0, true, true, 40.0, 0.5)
	HubKit.add_sector_collision(body, null, 13.6, R_IN, 9.4, 9.7, TOP_BALCONY[0], TOP_BALCONY[1], 5.0, Vector3.ZERO, "TopBalcony")
	var th2: float = TOP_BALCONY[0] + 2.0
	while th2 < TOP_BALCONY[1]:
		HubKit.rounded_box(wood, Vector3(0.2, 0.8, 1.6), 0.07, Transform3D(facing_centre(th2), HubKit.polar(14.6, th2, 9.0)))
		th2 += 6.0
	# Wrought-iron rail (open at the 172 end for the jump in).
	var pts: Array[Vector3] = []
	var a: float = 174.0
	while a <= TOP_BALCONY[1] + 0.01:
		pts.append(HubKit.polar(13.68, a, 9.7))
		a += 2.5
	rail(arch, body, pts, 1.0, "iron")
	# A13 chimney fins: bookcase-side slabs, inner faces 3.0 m apart at r 14.5.
	var fins := [[204.5, 4.5, 9.4], [218.4, 4.5, 12.8]]
	for f in fins:
		var th: float = f[0]
		var fy0: float = f[1]
		var fy1: float = f[2]
		var xf := Transform3D(facing_centre(th) * Basis(Vector3.UP, PI * 0.5), HubKit.polar(14.1, th, (fy0 + fy1) * 0.5))
		HubKit.rounded_box(wood, Vector3(2.2, fy1 - fy0, 0.5), 0.08, xf)
		HubKit.add_box_collision(body, null, Vector3(2.2, fy1 - fy0, 0.5), xf, "Fin%d" % int(th))
		# A small carved finial cap on top.
		HubKit.rounded_box(wood, Vector3(2.35, 0.2, 0.65), 0.08, Transform3D(xf.basis, xf.origin + Vector3(0, (fy1 - fy0) * 0.5 + 0.1, 0)))
	mi(arch, wood.commit(), toon("bookshelf_wood", Color(0.6, 0.42, 0.34), 0.9), "UpperLedges")


static func _wedge_collision(body: StaticBody3D, th0: float, th1: float) -> void:
	var span := th1 - th0
	var n := maxi(1, int(ceil(span / 8.0)))
	for i in n:
		var a := th0 + span * float(i) / float(n)
		var b := th0 + span * float(i + 1) / float(n)
		var pts := PackedVector3Array()
		for th in [a, b]:
			pts.append(HubKit.polar(15.15, th, 8.4))
			pts.append(HubKit.polar(15.15, th, 8.5))
			pts.append(HubKit.polar(16.0, th, 8.4))
			pts.append(HubKit.polar(16.0, th, 10.6))  # 68 deg (normal y 0.37): steeper than floor_max_angle, never a floor
		var sh := ConvexPolygonShape3D.new()
		sh.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = sh
		cs.name = "CapWedge%d" % body.get_child_count()
		body.add_child(cs)


# A18 chimney breast ---------------------------------------------------------------------

static func _fireplace_breast(arch: Node3D, body: StaticBody3D) -> void:
	var b := HubKit.Buf.new()
	HubKit.rounded_box(b, Vector3(1.4, 16.0, 4.5), 0.12, Transform3D(Basis(), Vector3(-15.5, 8.0, 0)))
	# Stepped corbel band at the gallery line.
	HubKit.rounded_box(b, Vector3(1.6, 0.35, 4.8), 0.1, Transform3D(Basis(), Vector3(-15.45, 4.4, 0)))
	HubKit.rounded_box(b, Vector3(1.6, 0.35, 4.8), 0.1, Transform3D(Basis(), Vector3(-15.45, 8.6, 0)))
	mi(arch, b.commit(), toon("plaster_wall", Color(1.0, 0.92, 0.82), 0.5), "ChimneyBreast")
	HubKit.add_box_collision(body, null, Vector3(1.4, 16.0, 4.5), Transform3D(Basis(), Vector3(-15.5, 8.0, 0)), "ChimneyBreast")


# A25 outdoor balcony -----------------------------------------------------------------------

static func _outdoor_balcony(arch: Node3D, body: StaticBody3D) -> void:
	var c := Vector3(0, 0, 17.0)
	var b := HubKit.Buf.new()
	HubKit.lathe(b, HubKit.round_rect_profile(0.0, 5.5, 4.0, 4.5, 0.0, 0.0, 0.0, 0.0), 90.0, 270.0, 6.0, true, true, 40.0, 1.0, Color.WHITE, c)
	HubKit.rounded_box(b, Vector3(2.6, 0.5, 1.4), 0.04, Transform3D(Basis(), Vector3(0, 4.25, 16.4)))
	mi(arch, b.commit(), toon("cobblestone", Color(1.0, 0.95, 0.88), 0.6), "OutdoorBalcony")
	HubKit.add_sector_collision(body, null, 0.0, 5.5, 4.0, 4.5, 90.0, 270.0, 15.0, c, "OutBalc")
	HubKit.add_box_collision(body, null, Vector3(2.6, 0.5, 1.6), Transform3D(Basis(), Vector3(0, 4.25, 16.3)), "Threshold")
	# Corbel under the balcony.
	var cb := HubKit.Buf.new()
	HubKit.lathe(cb, PackedVector2Array([Vector2(0.0, 2.6), Vector2(1.2, 2.8), Vector2(4.2, 3.7), Vector2(5.4, 4.0), Vector2(0.0, 4.0)]), 90.0, 270.0, 6.0, true, true, 30.0, 1.0, Color.WHITE, c)
	mi(arch, cb.commit(), toon("castle_stone", Color(1.0, 0.93, 0.82), 0.5), "BalconyCorbel")
	# Stone balustrade 1.1 m plus an invisible wall to y 8.
	var pts: Array[Vector3] = []
	for i in 25:
		pts.append(c + HubKit.polar(5.3, 90.0 + 180.0 * float(i) / 24.0, 4.5))
	rail(arch, body, pts, 1.1, "stone")
	for i in 24:
		var a := 90.0 + 180.0 * float(i) / 24.0
		var bb := a + 7.5
		var pa := c + HubKit.polar(5.45, a, 0)
		var pb := c + HubKit.polar(5.45, bb, 0)
		var d := pb - pa
		HubKit.add_box_collision(body, null, Vector3(d.length() + 0.1, 3.5, 0.2), Transform3D(along(d), (pa + pb) * 0.5 + Vector3(0, 6.25, 0)), "BalcWall")


# Rails ----------------------------------------------------------------------------------------

static var _balusters: Dictionary = {}  # style -> Array[Transform3D]


## Balustrade along a polyline of floor points: top and bottom rails, posts at the ends, balusters every ~0.26 m,
## and a box collider per segment. Style: "wood", "iron" or "stone".
static func rail(arch: Node3D, body: StaticBody3D, pts: Array[Vector3], height: float, style: String, posts_each := false) -> void:
	if pts.size() < 2:
		return
	var b := HubKit.Buf.new()
	var top_w := 0.16 if style != "stone" else 0.32
	var spacing := 0.26 if style != "stone" else 0.42
	if not _balusters.has(style):
		_balusters[style] = []
	var list: Array = _balusters[style]
	# Rail collision lives in its own body on layers 3 + 9 (r1 critique: the 1.15 m rail blocked the camera's spring arm,
	# which only tests layer 1, everywhere along the gallery). Mak (mask 1 + 3) still collides with it. It is a child
	# of `body`, so disabling a gate body disables its rail too.
	var rb := StaticBody3D.new()
	rb.name = "RailCollision"
	rb.collision_layer = (1 << 2) | (1 << 8)
	rb.collision_mask = 0
	rb.add_to_group("camera_ignore")
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var d := p1 - p0
		var l := d.length()
		if l < 0.01:
			continue
		var bs := along(d)
		var mid := (p0 + p1) * 0.5
		if style == "iron":
			HubKit.rounded_box(b, Vector3(l + 0.04, 0.07, 0.07), 0.03, Transform3D(bs, mid + Vector3(0, height, 0)))
			HubKit.rounded_box(b, Vector3(l + 0.04, 0.05, 0.05), 0.02, Transform3D(bs, mid + Vector3(0, 0.12, 0)))
		else:
			HubKit.rounded_box(b, Vector3(l + 0.06, 0.12, top_w), 0.05, Transform3D(bs, mid + Vector3(0, height, 0)))
			HubKit.rounded_box(b, Vector3(l + 0.04, 0.1, top_w * 0.75), 0.03, Transform3D(bs, mid + Vector3(0, 0.07, 0)))
		var cnt := maxi(1, int(floor(l / spacing)))
		for k in cnt:
			var t := (float(k) + 0.5) / float(cnt)
			var p := p0 + d * t
			list.append(Transform3D(Basis(), p + Vector3(0, 0.1, 0)))
		HubKit.add_box_collision(rb, null, Vector3(l + 0.05, height + 0.15, 0.2), Transform3D(bs, mid + Vector3(0, (height + 0.15) * 0.5, 0)), "Rail")
	var post_idx: Array[int] = [0, pts.size() - 1]
	if rb.get_child_count() > 0 and rb.get_parent() == null:
		body.add_child(rb)
	if posts_each:
		post_idx = []
		for i in pts.size():
			post_idx.append(i)
	for i in post_idx:
		var p := pts[i]
		if style == "iron":
			HubKit.rounded_box(b, Vector3(0.1, height + 0.15, 0.1), 0.04, Transform3D(Basis(), p + Vector3(0, (height + 0.15) * 0.5, 0)))
		else:
			HubKit.rounded_box(b, Vector3(0.26, height + 0.2, 0.26), 0.06, Transform3D(Basis(), p + Vector3(0, (height + 0.2) * 0.5, 0)))
			HubKit.turned(b, PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.15, 0.08), Vector2(0.1, 0.2), Vector2(0.03, 0.26)]), 12, p + Vector3(0, height + 0.2, 0))
	var m: Material
	match style:
		"iron":
			m = iron()
		"stone":
			m = toon("castle_stone", Color(1.0, 0.95, 0.86), 0.8)
		_:
			m = toon("bookshelf_wood", Color(0.62, 0.43, 0.34), 1.2)
	mi(arch, b.commit(), m, "Rail_%s" % style)


static func _balusters_commit(arch: Node3D) -> void:
	for style in _balusters.keys():
		var list: Array = _balusters[style]
		if list.is_empty():
			continue
		var prof: PackedVector2Array
		match style:
			"iron":
				prof = PackedVector2Array([Vector2(0.02, 0.0), Vector2(0.02, 0.35), Vector2(0.05, 0.42), Vector2(0.02, 0.5), Vector2(0.02, 0.86)])
			"stone":
				prof = PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.1, 0.06), Vector2(0.07, 0.12), Vector2(0.06, 0.3), Vector2(0.13, 0.55), Vector2(0.06, 0.82), Vector2(0.1, 0.9), Vector2(0.1, 0.96)])
			_:
				prof = PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.06, 0.05), Vector2(0.04, 0.1), Vector2(0.035, 0.22), Vector2(0.07, 0.42), Vector2(0.04, 0.66), Vector2(0.032, 0.76), Vector2(0.055, 0.82), Vector2(0.055, 0.84)])
		var mesh := HubKit.turned_mesh(prof, 10 if style != "stone" else 14, 60.0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Balusters_%s" % style
		mmi.multimesh = mm
		match style:
			"iron":
				mmi.material_override = iron()
			"stone":
				mmi.material_override = toon("castle_stone", Color(1.0, 0.95, 0.86), 0.8)
			_:
				mmi.material_override = toon("bookshelf_wood", Color(0.62, 0.43, 0.34), 1.2)
		arch.add_child(mmi)
	_balusters.clear()

class_name HubKit
extends RefCounted
## Hub builder geometry kit (hub workstream). Deterministic procedural meshes for Mak Manor's Grand Library:
## lathe (surface of revolution, used for rings, walls, columns, balusters, dome), rounded boxes, ring-sector
## collision hulls, palette materials. Used by hub_build.gd (baking) and by hub runtime scripts.
##
## Conventions (Docs/levels/HUB.md): metres, x east, y up, z south; polar angle theta from north clockwise:
## pos = (r*sin(theta), y, -r*cos(theta)).

const WALNUT := Color("5c3a21")
const WALNUT_DARK := Color("3b2416")
const WALNUT_LIGHT := Color("8a5a34")
const BURGUNDY := Color("7a1f2e")
const BRASS := Color("c9a04a")
const CANDLE := Color("ffc86b")
const PARCHMENT := Color("ead8b0")
const VELVET_GREEN := Color("2f5d3a")
const WOLF_RED := Color("b3261e")
const IRON := Color("2e2a2b")
const PLASTER := Color("e9d9bd")
const TEAL := Color("2e8c8a")
const ROSE := Color("d0607a")
const SANDSTONE := Color("d8bf94")
const MEADOW := Color("7dbe5a")

static var _mat_cache: Dictionary = {}


static func polar(r: float, theta_deg: float, y: float = 0.0) -> Vector3:
	var t := deg_to_rad(theta_deg)
	return Vector3(r * sin(t), y, -r * cos(t))


## Raw save flag (r1 QA: Game.is_unlocked() is true for every flag under --unlock-all, which erased every hub activity).
## Hub progress (hub_*, hat_*, ledger acorns) reads the save directly; --unlock-all stays for gates only.
static func flag(n: Node, f: String) -> bool:
	var g := n.get_node_or_null("/root/Game") if n and n.is_inside_tree() else null
	if g == null:
		return false
	if g.has_method("has_flag"):
		return bool(g.call("has_flag", f))
	var d: Variant = g.get("data")
	if d is Dictionary:
		var u: Variant = (d as Dictionary).get("unlocks", {})
		return u is Dictionary and (u as Dictionary).has(f)
	return false


## Yaw (rotation_degrees.y) that makes a node's -Z face the hall centre from polar angle theta.
static func yaw_facing_centre(theta_deg: float) -> float:
	return -theta_deg + 180.0


# ------------------------------------------------------------------ mesh buffer

class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var use_color := false

	func vert(p: Vector3, nn: Vector3, t: Vector2, col: Color = Color.WHITE) -> int:
		v.append(p)
		n.append(nn)
		uv.append(t)
		c.append(col)
		return v.size() - 1

	## Triangle; winding is fixed so the front face matches the vertex normals (Godot fronts are clockwise).
	func tri(a: int, b: int, cc: int) -> void:
		var na := n[a] + n[b] + n[cc]
		var g := (v[b] - v[a]).cross(v[cc] - v[a])
		if g.dot(na) > 0.0:
			idx.append_array([a, cc, b])
		else:
			idx.append_array([a, b, cc])

	func quad(a: int, b: int, cc: int, d: int) -> void:
		tri(a, b, cc)
		tri(a, cc, d)

	func commit(mesh: ArrayMesh = null, material: Material = null) -> ArrayMesh:
		var m := mesh if mesh else ArrayMesh.new()
		if v.size() == 0:
			return m
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		if use_color:
			arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if material:
			m.surface_set_material(m.get_surface_count() - 1, material)
		return m


# ------------------------------------------------------------------ lathe

## Surface of revolution. `profile` holds (r, y) points; for closed solids list them counter-clockwise
## (r to the right, y up) so normals face outward. Revolves from th0 to th1 (degrees, polar convention).
## Profile corners sharper than `smooth_deg` stay hard. `closed` joins the last profile point to the first.
## `caps` closes the two ends of a partial revolution. UV: u = arc length * uv_scale, v = profile length * uv_scale.
static func lathe(buf: Buf, profile: PackedVector2Array, th0: float, th1: float, seg_deg: float = 7.5,
		closed: bool = true, caps: bool = true, smooth_deg: float = 40.0, uv_scale: float = 1.0,
		col: Color = Color.WHITE, centre: Vector3 = Vector3.ZERO) -> void:
	var np := profile.size()
	if np < 2:
		return
	var nseg_prof := np if closed else np - 1
	var span := th1 - th0
	var steps := maxi(1, int(ceil(absf(span) / seg_deg)))
	var full := absf(absf(span) - 360.0) < 0.01
	# Segment normals in the profile plane (n.x radial, n.y up).
	var sn: Array[Vector2] = []
	var slen: Array[float] = []
	for i in nseg_prof:
		var a := profile[i]
		var b := profile[(i + 1) % np]
		var d := b - a
		slen.append(d.length())
		sn.append(Vector2(d.y, -d.x).normalized())
	var cos_lim := cos(deg_to_rad(smooth_deg))
	var vacc := 0.0
	for i in nseg_prof:
		var a := profile[i]
		var b := profile[(i + 1) % np]
		var n_a := sn[i]
		var n_b := sn[i]
		var has_prev := closed or i > 0
		var has_next := closed or i < nseg_prof - 1
		if has_prev:
			var pn := sn[(i - 1 + nseg_prof) % nseg_prof]
			if pn.dot(sn[i]) > cos_lim:
				n_a = (pn + sn[i]).normalized()
		if has_next:
			var nn := sn[(i + 1) % nseg_prof]
			if nn.dot(sn[i]) > cos_lim:
				n_b = (nn + sn[i]).normalized()
		if slen[i] < 0.00001:
			continue
		var prev_a := -1
		var prev_b := -1
		for s in steps + 1:
			var th := th0 + span * float(s) / float(steps)
			var t := deg_to_rad(th)
			var u := Vector3(sin(t), 0, -cos(t))
			var pa := centre + u * a.x + Vector3(0, a.y, 0)
			var pb := centre + u * b.x + Vector3(0, b.y, 0)
			var na3 := (u * n_a.x + Vector3(0, n_a.y, 0)).normalized()
			var nb3 := (u * n_b.x + Vector3(0, n_b.y, 0)).normalized()
			var arc_r := maxf(0.05, (a.x + b.x) * 0.5)
			var uu := deg_to_rad(th - th0) * arc_r * uv_scale
			var ia := buf.vert(pa, na3, Vector2(uu, vacc * uv_scale), col)
			var ib := buf.vert(pb, nb3, Vector2(uu, (vacc + slen[i]) * uv_scale), col)
			if prev_a >= 0:
				buf.quad(prev_a, prev_b, ib, ia)
			prev_a = ia
			prev_b = ib
		vacc += slen[i]
	if caps and closed and not full:
		var tri_idx := Geometry2D.triangulate_polygon(profile)
		if tri_idx.is_empty():
			print("HUBKIT cap fail ", profile)
		for end in [0, 1]:
			var th := th0 if end == 0 else th1
			var t := deg_to_rad(th)
			var u := Vector3(sin(t), 0, -cos(t))
			var tang := Vector3(cos(t), 0, sin(t)) * signf(span)
			var nrm := -tang if end == 0 else tang
			var base := buf.v.size()
			for p in profile:
				buf.vert(centre + u * p.x + Vector3(0, p.y, 0), nrm, p * uv_scale, col)
			for k in range(0, tri_idx.size(), 3):
				buf.tri(base + tri_idx[k], base + tri_idx[k + 1], base + tri_idx[k + 2])


static func lathe_mesh(profile: PackedVector2Array, th0: float, th1: float, seg_deg: float = 7.5,
		closed: bool = true, caps: bool = true, smooth_deg: float = 40.0, uv_scale: float = 1.0) -> ArrayMesh:
	var b := Buf.new()
	lathe(b, profile, th0, th1, seg_deg, closed, caps, smooth_deg, uv_scale)
	return b.commit()


## Closed rectangle profile for a ring solid.
static func rect_profile(r_in: float, r_out: float, y0: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(r_in, y0), Vector2(r_out, y0), Vector2(r_out, y1), Vector2(r_in, y1)])


## Rectangle profile (counter-clockwise) with rounded corners. Radii: bottom-right, top-right, top-left, bottom-left
## where "left" is r_in (the side facing the hall centre).
static func round_rect_profile(r_in: float, r_out: float, y0: float, y1: float, br := 0.0, tr := 0.0, tl := 0.0, bl := 0.0, steps: int = 3) -> PackedVector2Array:
	var p := PackedVector2Array()
	var corners := [[Vector2(r_out, y0), br, 270.0], [Vector2(r_out, y1), tr, 0.0], [Vector2(r_in, y1), tl, 90.0], [Vector2(r_in, y0), bl, 180.0]]
	for c in corners:
		var pt: Vector2 = c[0]
		var rad: float = c[1]
		var a0: float = c[2]
		if rad <= 0.0001:
			p.append(pt)
			continue
		var dir := Vector2(-1.0 if pt.x == r_out else 1.0, 1.0 if pt.y == y0 else -1.0)
		var ctr := pt + dir * rad
		for k in steps + 1:
			var a := deg_to_rad(a0 + 90.0 * float(k) / float(steps))
			p.append(ctr + Vector2(cos(a), sin(a)) * rad)
	return p


## Solid of revolution around a vertical axis (full 360), profile given as (radius, y) from bottom to top
## along the outside. The axis side is closed automatically.
static func turned(buf: Buf, outline: PackedVector2Array, segs: int = 16, centre: Vector3 = Vector3.ZERO, col := Color.WHITE, smooth_deg := 50.0) -> void:
	var p := PackedVector2Array()
	p.append(Vector2(0.0, outline[0].y))
	for q in outline:
		p.append(q)
	p.append(Vector2(0.0, outline[outline.size() - 1].y))
	lathe(buf, p, 0.0, 360.0, 360.0 / float(segs), false, false, smooth_deg, 1.0, col, centre)


static func turned_mesh(outline: PackedVector2Array, segs: int = 16, smooth_deg := 50.0) -> ArrayMesh:
	var b := Buf.new()
	turned(b, outline, segs, Vector3.ZERO, Color.WHITE, smooth_deg)
	return b.commit()


# ------------------------------------------------------------------ rounded box

static func _round_coords(h: float, r: float, segs: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in segs + 1:
		out.append(-(h - r) - r * cos(PI * 0.5 * float(k) / float(segs)))
	for k in range(segs, -1, -1):
		out.append((h - r) + r * cos(PI * 0.5 * float(k) / float(segs)))
	return out


## Box with rounded edges and smooth normals (radius clamped to the smallest half-extent).
static func rounded_box(buf: Buf, size: Vector3, radius: float, xf: Transform3D = Transform3D.IDENTITY, segs: int = 2, col := Color.WHITE) -> void:
	var h := size * 0.5
	var r := minf(radius, minf(h.x, minf(h.y, h.z)) * 0.98)
	r = maxf(r, 0.001)
	var cx := _round_coords(h.x, r, segs)
	var cy := _round_coords(h.y, r, segs)
	var cz := _round_coords(h.z, r, segs)
	var inner := h - Vector3(r, r, r)
	var basis := xf.basis
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var ua: PackedFloat32Array
			var va: PackedFloat32Array
			match axis:
				0:
					ua = cy
					va = cz
				1:
					ua = cx
					va = cz
				_:
					ua = cx
					va = cy
			var grid: Array = []
			for i in ua.size():
				var row: Array = []
				for j in va.size():
					var p := Vector3.ZERO
					match axis:
						0:
							p = Vector3(sgn * h.x, ua[i], va[j])
						1:
							p = Vector3(ua[i], sgn * h.y, va[j])
						_:
							p = Vector3(ua[i], va[j], sgn * h.z)
					var q := p.clamp(-inner, inner)
					var d := p - q
					var nrm := d.normalized() if d.length() > 0.000001 else Vector3.ZERO
					if nrm == Vector3.ZERO:
						nrm = Vector3.ZERO
						nrm[axis] = sgn
					var pos := q + nrm * r
					var t := Vector2(ua[i], va[j])
					row.append(buf.vert(xf * pos, (basis * nrm).normalized(), t, col))
				grid.append(row)
			for i in ua.size() - 1:
				for j in va.size() - 1:
					buf.quad(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])


static func rounded_box_mesh(size: Vector3, radius: float, segs: int = 2) -> ArrayMesh:
	var b := Buf.new()
	rounded_box(b, size, radius, Transform3D.IDENTITY, segs)
	return b.commit()


## Flat disc (top face only) with planar UVs (metres * uv_scale).
static func disc(buf: Buf, r: float, y: float, segs: int = 64, centre := Vector3.ZERO, uv_scale := 1.0, col := Color.WHITE) -> void:
	var c := buf.vert(centre + Vector3(0, y, 0), Vector3.UP, Vector2(centre.x, centre.z) * uv_scale, col)
	var prev := -1
	var first := -1
	for i in segs + 1:
		var t := TAU * float(i) / float(segs)
		var p := centre + Vector3(sin(t) * r, y, -cos(t) * r)
		var k := buf.vert(p, Vector3.UP, Vector2(p.x, p.z) * uv_scale, col)
		if prev >= 0:
			buf.tri(c, prev, k)
		else:
			first = k
		prev = k


# ------------------------------------------------------------------ collision helpers

## Convex hull of an annular sector (r_in..r_out, y0..y1, th0..th1); exact for small spans.
static func sector_hull(r_in: float, r_out: float, y0: float, y1: float, th0: float, th1: float, centre := Vector3.ZERO) -> ConvexPolygonShape3D:
	var pts := PackedVector3Array()
	var steps := maxi(1, int(ceil(absf(th1 - th0) / 5.0)))
	for s in steps + 1:
		var th := th0 + (th1 - th0) * float(s) / float(steps)
		for r in [r_in, r_out]:
			if r == r_in and s > 0 and s < steps:
				continue
			pts.append(centre + polar(r, th, y0))
			pts.append(centre + polar(r, th, y1))
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	return sh


## Adds ring-sector collision as convex pieces of at most `piece_deg` each.
static func add_sector_collision(body: StaticBody3D, owner_node: Node, r_in: float, r_out: float, y0: float, y1: float,
		th0: float, th1: float, piece_deg: float = 10.0, centre := Vector3.ZERO, prefix := "Seg") -> void:
	var span := th1 - th0
	var n := maxi(1, int(ceil(absf(span) / piece_deg)))
	for i in n:
		var a := th0 + span * float(i) / float(n)
		var b := th0 + span * float(i + 1) / float(n)
		var cs := CollisionShape3D.new()
		cs.name = "%s%d" % [prefix, body.get_child_count()]
		cs.shape = sector_hull(r_in, r_out, y0, y1, a, b, centre)
		body.add_child(cs)
		if owner_node:
			cs.owner = owner_node


static func add_box_collision(body: StaticBody3D, owner_node: Node, size: Vector3, xf: Transform3D, cname := "") -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = xf
	cs.name = cname if cname != "" else "Box%d" % body.get_child_count()
	body.add_child(cs)
	if owner_node:
		cs.owner = owner_node
	return cs


static func add_cyl_collision(body: StaticBody3D, owner_node: Node, r: float, h: float, pos: Vector3, cname := "") -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	cs.position = pos
	cs.name = cname if cname != "" else "Cyl%d" % body.get_child_count()
	body.add_child(cs)
	if owner_node:
		cs.owner = owner_node
	return cs


## Wedge (ramp) collision: a convex hull of the stair flight from bottom-centre to top-centre with the given width.
static func ramp_hull(bottom: Vector3, top: Vector3, width: float, thickness: float = 0.3, solid_to_floor := false) -> ConvexPolygonShape3D:
	var pts := PackedVector3Array()
	var hw := width * 0.5
	for sx in [-hw, hw]:
		pts.append(bottom + Vector3(sx, 0, 0))
		pts.append(top + Vector3(sx, 0, 0))
		if solid_to_floor:
			pts.append(Vector3(bottom.x + sx, 0.0, bottom.z))
			pts.append(Vector3(top.x + sx, 0.0, top.z))
		else:
			pts.append(bottom + Vector3(sx, -thickness, 0))
			pts.append(top + Vector3(sx, -thickness, 0))
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	return sh


# ------------------------------------------------------------------ materials

static func mat(color: Color, rough := 0.6, metal := 0.0, key := "") -> StandardMaterial3D:
	var k := key if key != "" else "%s_%.2f_%.2f" % [color.to_html(), rough, metal]
	if _mat_cache.has(k):
		return _mat_cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if metal > 0.5:
		m.metallic_specular = 0.6
	_mat_cache[k] = m
	return m


static func tex_mat(color: Color, tex_path: String, rough := 0.6, uv := Vector3.ONE, triplanar := false, key := "") -> StandardMaterial3D:
	var k := key if key != "" else "tex_%s_%s_%.2f_%s_%s" % [color.to_html(), tex_path, rough, uv, triplanar]
	if _mat_cache.has(k):
		return _mat_cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
	m.uv1_scale = uv
	m.uv1_triplanar = triplanar
	if triplanar:
		m.uv1_world_triplanar = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[k] = m
	return m


static func emissive(color: Color, energy: float, key := "") -> StandardMaterial3D:
	var k := key if key != "" else "em_%s_%.2f" % [color.to_html(), energy]
	if _mat_cache.has(k):
		return _mat_cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.5
	_mat_cache[k] = m
	return m


static func vcol_mat(rough := 0.7, key := "vcol") -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	_mat_cache[key] = m
	return m


static func clear_cache() -> void:
	_mat_cache.clear()

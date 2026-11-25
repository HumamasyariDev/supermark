extends RefCounted
## W2 Beanstalk Skyway: deterministic procedural geometry batch (owned by the W2 world builder).
## Accumulates vertex-coloured triangles (rounded boxes, cylinders, ellipsoids, swept tubes, discs)
## and commits them into one ArrayMesh surface. Triangles are oriented automatically from the
## intended normals, so every generator can list vertices in any order.
## Used only at bake time by w2_build.gd; the baked meshes live in res://assets/environment/w2/.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()
## Convert authored sRGB colours to linear (set false for data masks such as terrain path weights).
var linear_colors := true


func is_empty() -> bool:
	return idx.is_empty()


func vcount() -> int:
	return verts.size()


func add_v(p: Vector3, n: Vector3, c: Color) -> int:
	verts.append(p)
	norms.append(n.normalized() if n.length_squared() > 0.000001 else Vector3.UP)
	# Colours are authored in sRGB; vertex colours reach the shader as linear values.
	cols.append(Color(c.srgb_to_linear(), c.a) if linear_colors else c)
	return verts.size() - 1


## Adds a triangle, flipping it when needed so its front face (Godot: clockwise) matches the vertex normals.
func tri(a: int, b: int, c: int) -> void:
	var pa := verts[a]
	var fn := (verts[b] - pa).cross(verts[c] - pa)
	var en := norms[a] + norms[b] + norms[c]
	if fn.dot(en) > 0.0:
		idx.append(a); idx.append(c); idx.append(b)
	else:
		idx.append(a); idx.append(b); idx.append(c)


func quad(a: int, b: int, c: int, d: int) -> void:
	tri(a, b, c)
	tri(a, c, d)


## Grid of rows x cols vertex indices (row-major) into quads.
func grid(ids: PackedInt32Array, rows: int, ncols: int, wrap := false) -> void:
	var cmax := ncols if wrap else ncols - 1
	for r in rows - 1:
		for c in cmax:
			var c2 := (c + 1) % ncols
			quad(ids[r * ncols + c], ids[r * ncols + c2], ids[(r + 1) * ncols + c2], ids[(r + 1) * ncols + c])


func append(other) -> void:
	var base := verts.size()
	verts.append_array(other.verts)
	norms.append_array(other.norms)
	cols.append_array(other.cols)
	for i in other.idx:
		idx.append(base + i)


# ---------------------------------------------------------------- primitives

## Rounded box centred at xf.origin; size in local units; r = corner radius; k = arc steps.
func rbox(xf: Transform3D, size: Vector3, r: float, col: Color, k := 3, col_top: Color = Color(0, 0, 0, 0)) -> void:
	var h := size * 0.5
	r = clampf(r, 0.0, minf(h.x, minf(h.y, h.z)) - 0.0005)
	var top_tint := col_top.a > 0.0
	var nb := xf.basis.inverse().transposed()
	# Per-axis coordinate lists with extra samples near the edges.
	var lists := []
	for ax in 3:
		var hv: float = h[ax]
		var l := PackedFloat32Array()
		for i in k + 1:
			var a := float(i) / float(k) * PI * 0.5
			l.append(-hv + r - r * cos(a))
		for i in k + 1:
			var a := float(k - i) / float(k) * PI * 0.5
			l.append(hv - r + r * cos(a))
		lists.append(l)
	var inner := h - Vector3(r, r, r)
	for face in 6:
		var ax := int(face / 2.0)
		var sgn := -1.0 if face % 2 == 0 else 1.0
		var u_ax := (ax + 1) % 3
		var v_ax := (ax + 2) % 3
		var lu: PackedFloat32Array = lists[u_ax]
		var lv: PackedFloat32Array = lists[v_ax]
		var ids := PackedInt32Array()
		for iv in lv.size():
			for iu in lu.size():
				var p := Vector3.ZERO
				p[ax] = sgn * h[ax]
				p[u_ax] = lu[iu]
				p[v_ax] = lv[iv]
				var q := Vector3(clampf(p.x, -inner.x, inner.x), clampf(p.y, -inner.y, inner.y), clampf(p.z, -inner.z, inner.z))
				var d := p - q
				var n := Vector3.ZERO
				n[ax] = sgn
				if d.length_squared() > 0.0000001:
					n = d.normalized()
				var v := q + n * r if r > 0.0 else p
				var c := col
				if top_tint:
					c = col.lerp(col_top, clampf(n.y, 0.0, 1.0))
				ids.append(add_v(xf * v, nb * n, c))
		grid(ids, lv.size(), lu.size())


## Cylinder / truncated cone along local Y, centred at xf.origin, from -h/2 to +h/2.
func cylinder(xf: Transform3D, r_top: float, r_bot: float, h: float, col: Color, segs := 20, caps := true, col_top: Color = Color(0, 0, 0, 0)) -> void:
	var nb := xf.basis.inverse().transposed()
	var top_tint := col_top.a > 0.0
	var slope := (r_bot - r_top) / maxf(h, 0.0001)
	var ids := PackedInt32Array()
	for row in 2:
		var y := -h * 0.5 if row == 0 else h * 0.5
		var rr := r_bot if row == 0 else r_top
		for s in segs:
			var a := TAU * float(s) / float(segs)
			var n := Vector3(cos(a), slope, sin(a))
			ids.append(add_v(xf * Vector3(cos(a) * rr, y, sin(a) * rr), nb * n, col))
	grid(ids, 2, segs, true)
	if caps:
		for row in 2:
			var y := -h * 0.5 if row == 0 else h * 0.5
			var rr := r_bot if row == 0 else r_top
			if rr <= 0.001:
				continue
			var n := Vector3(0, -1 if row == 0 else 1, 0)
			var c := col_top if (top_tint and row == 1) else col
			var ci := add_v(xf * Vector3(0, y, 0), nb * n, c)
			var ring := PackedInt32Array()
			for s in segs:
				var a := TAU * float(s) / float(segs)
				ring.append(add_v(xf * Vector3(cos(a) * rr, y, sin(a) * rr), nb * n, c))
			for s in segs:
				tri(ci, ring[s], ring[(s + 1) % segs])


## Rounded cylinder (puck) with a bevelled top and bottom edge. Centred, along local Y.
func puck(xf: Transform3D, r: float, h: float, bevel: float, col: Color, segs := 24, col_top: Color = Color(0, 0, 0, 0)) -> void:
	var nb := xf.basis.inverse().transposed()
	bevel = clampf(bevel, 0.0, minf(r, h * 0.5) - 0.001)
	var top_tint := col_top.a > 0.0
	var profile := []  # [radius, y, nr, ny]
	var k := 3
	profile.append([0.0, -h * 0.5, 0.0, -1.0])
	for i in k + 1:
		var a := -PI * 0.5 + float(i) / float(k) * PI * 0.5
		profile.append([r - bevel + cos(a) * bevel, -h * 0.5 + bevel + sin(a) * bevel, cos(a), sin(a)])
	for i in k + 1:
		var a := float(i) / float(k) * PI * 0.5
		profile.append([r - bevel + cos(a) * bevel, h * 0.5 - bevel + sin(a) * bevel, cos(a), sin(a)])
	profile.append([0.0, h * 0.5, 0.0, 1.0])
	var ids := PackedInt32Array()
	for pr in profile:
		for s in segs:
			var a := TAU * float(s) / float(segs)
			var n := Vector3(cos(a) * pr[2], pr[3], sin(a) * pr[2])
			var c := col.lerp(col_top, clampf(pr[3], 0.0, 1.0)) if top_tint else col
			ids.append(add_v(xf * Vector3(cos(a) * pr[0], pr[1], sin(a) * pr[0]), nb * n, c))
	grid(ids, profile.size(), segs, true)


## Ellipsoid: unit sphere transformed by xf (scale lives in the basis).
func sphere(xf: Transform3D, col: Color, segs := 18, rings := 10, col_bottom: Color = Color(0, 0, 0, 0), flat_bottom := -2.0) -> void:
	var nb := xf.basis.inverse().transposed()
	var tint := col_bottom.a > 0.0
	var ids := PackedInt32Array()
	for ri in rings + 1:
		var phi := PI * float(ri) / float(rings)
		for s in segs:
			var th := TAU * float(s) / float(segs)
			var n := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var p := n
			if p.y < flat_bottom:
				p.y = flat_bottom
			var c := col
			if tint:
				c = col_bottom.lerp(col, smoothstep(-0.9, 0.5, n.y))
			ids.append(add_v(xf * p, nb * n, c))
	grid(ids, rings + 1, segs, true)


## Swept tube through points with per-point radii (parallel-transport frames). Optional end caps.
func tube(points: PackedVector3Array, radii: PackedFloat32Array, col: Color, segs := 12, cap_start := true, cap_end := true, col_b: Color = Color(0, 0, 0, 0), twist_cols := 0) -> void:
	var n := points.size()
	if n < 2:
		return
	var tangents: Array[Vector3] = []
	for i in n:
		var t: Vector3
		if i == 0:
			t = points[1] - points[0]
		elif i == n - 1:
			t = points[n - 1] - points[n - 2]
		else:
			t = points[i + 1] - points[i - 1]
		tangents.append(t.normalized())
	var ref := Vector3.UP if absf(tangents[0].dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var nrm := tangents[0].cross(ref).normalized()
	var ids := PackedInt32Array()
	var stripe := col_b.a > 0.0
	for i in n:
		if i > 0:
			var axis := tangents[i - 1].cross(tangents[i])
			if axis.length() > 0.00001:
				var ang := tangents[i - 1].angle_to(tangents[i])
				nrm = nrm.rotated(axis.normalized(), ang)
		var bin := tangents[i].cross(nrm).normalized()
		for s in segs:
			var a := TAU * float(s) / float(segs)
			var d := nrm * cos(a) + bin * sin(a)
			var c := col
			if stripe and twist_cols > 0:
				c = col.lerp(col_b, 0.5 + 0.5 * cos(a * twist_cols))
			ids.append(add_v(points[i] + d * radii[mini(i, radii.size() - 1)], d, c))
	grid(ids, n, segs, true)
	for e in 2:
		if (e == 0 and not cap_start) or (e == 1 and not cap_end):
			continue
		var i := 0 if e == 0 else n - 1
		var dn := -tangents[0] if e == 0 else tangents[n - 1]
		var ci := add_v(points[i] + dn * radii[mini(i, radii.size() - 1)] * 0.35, dn, col)
		for s in segs:
			var s2 := (s + 1) % segs
			var a := ids[i * segs + s]
			var b := ids[i * segs + s2]
			tri(ci, a, b)


## Flat elliptic disc (top facing +Y), centred at xf.origin.
func disc(xf: Transform3D, rx: float, rz: float, col: Color, segs := 24) -> void:
	var nb := xf.basis.inverse().transposed()
	var ci := add_v(xf.origin, nb * Vector3.UP, col)
	var ring := PackedInt32Array()
	for s in segs:
		var a := TAU * float(s) / float(segs)
		ring.append(add_v(xf * Vector3(cos(a) * rx, 0, sin(a) * rz), nb * Vector3.UP, col))
	for s in segs:
		tri(ci, ring[s], ring[(s + 1) % segs])


## Torus around local Y.
func torus(xf: Transform3D, major: float, minor: float, col: Color, segs := 24, sides := 8) -> void:
	var nb := xf.basis.inverse().transposed()
	var ids := PackedInt32Array()
	for i in segs:
		var a := TAU * float(i) / float(segs)
		var c := Vector3(cos(a), 0, sin(a))
		for j in sides:
			var b := TAU * float(j) / float(sides)
			var n := c * cos(b) + Vector3.UP * sin(b)
			ids.append(add_v(xf * (c * major + n * minor), nb * n, col))
	grid(ids, segs, sides, true)
	# close the seam between the last and first ring
	for j in sides:
		var j2 := (j + 1) % sides
		quad(ids[(segs - 1) * sides + j], ids[(segs - 1) * sides + j2], ids[j2], ids[j])


## Heart-shaped leaf: tip toward local -Z, notch toward +Z, top surface at y = 0, thickness below.
## rim_lift raises the outer rim; vein colour runs down the midrib.
func leaf(xf: Transform3D, rx: float, rz: float, thick: float, col: Color, col_edge: Color, col_vein: Color, rim_lift := 0.12, rings := 6, segs := 28) -> void:
	var nb := xf.basis.inverse().transposed()
	var outline := func(a: float) -> Vector2:
		# a = 0 points to -Z (tip). Heart: pointed tip, notch at the back.
		var x := sin(a)
		var z := -cos(a)
		var tipk := pow(maxf(0.0, cos(a)), 6.0) * 0.18     # pointy tip
		var notch := pow(maxf(0.0, -cos(a)), 14.0) * 0.28  # notch at the stem
		var s := 1.0 + tipk - notch
		return Vector2(x * rx * s, z * rz * s)
	var top_ids := PackedInt32Array()
	var bot_ids := PackedInt32Array()
	var c_top := add_v(xf * Vector3(0, -0.02, 0), nb * Vector3.UP, col_vein)
	var c_bot := add_v(xf * Vector3(0, -thick, 0), nb * Vector3.DOWN, col_edge.darkened(0.25))
	for r in range(1, rings + 1):
		var t := float(r) / float(rings)
		for s in segs:
			var a := TAU * float(s) / float(segs)
			var o: Vector2 = outline.call(a) * t
			var lift := rim_lift * t * t * t - 0.02 * (1.0 - t)
			var vein := pow(absf(sin(a)), 0.5)
			var cc := col_vein.lerp(col, clampf(vein * 3.0, 0.0, 1.0)).lerp(col_edge, t * t * 0.7)
			var n := Vector3(-o.x / rx * rim_lift * 3.0 * t * t, 1.0, -o.y / rz * rim_lift * 3.0 * t * t)
			top_ids.append(add_v(xf * Vector3(o.x, lift, o.y), nb * n, cc))
	# top fan + rings
	for s in segs:
		tri(c_top, top_ids[s], top_ids[(s + 1) % segs])
	grid(top_ids, rings, segs, true)
	# rim roll: a rounded edge down to the underside
	var rim_ids := PackedInt32Array()
	var steps := 3
	for k in steps + 1:
		var ang := float(k) / float(steps) * PI
		for s in segs:
			var a := TAU * float(s) / float(segs)
			var o: Vector2 = outline.call(a)
			var dir := Vector3(o.x, 0, o.y).normalized()
			var rr := thick * 0.5
			var p := Vector3(o.x, rim_lift - rr, o.y) + dir * sin(ang) * rr * 0.6 + Vector3.UP * cos(ang) * rr
			var n := dir * sin(ang) + Vector3.UP * cos(ang)
			rim_ids.append(add_v(xf * p, nb * n, col_edge))
	grid(rim_ids, steps + 1, segs, true)
	# underside
	for s in segs:
		var a := TAU * float(s) / float(segs)
		var o: Vector2 = outline.call(a)
		bot_ids.append(add_v(xf * Vector3(o.x, rim_lift - thick, o.y), nb * Vector3.DOWN, col_edge.darkened(0.2)))
	for s in segs:
		tri(c_bot, bot_ids[s], bot_ids[(s + 1) % segs])


# ---------------------------------------------------------------- output

func commit(material: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if idx.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if material:
		mesh.surface_set_material(0, material)
	return mesh


## Triangle soup (for ConcavePolygonShape3D.set_faces), same winding as the render mesh.
func faces() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in idx:
		out.append(verts[i])
	return out


# ---------------------------------------------------------------- curves

## Catmull-Rom resample of a polyline at roughly `step` metres.
static func catmull(points: Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := points.size()
	if n < 2:
		for p in points:
			out.append(p)
		return out
	for i in n - 1:
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, n - 1)]
		var seg := maxi(1, int(ceil(p1.distance_to(p2) / step)))
		for s in seg:
			var t := float(s) / float(seg)
			out.append(_cr(p0, p1, p2, p3, t))
	out.append(points[n - 1])
	return out


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Deterministic hash noise in 0..1.
static func hash01(x: float, y: float, s: float = 0.0) -> float:
	var v := sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453
	return v - floor(v)


static func vnoise(x: float, y: float, s: float = 0.0) -> float:
	var ix := floorf(x)
	var iy := floorf(y)
	var fx := x - ix
	var fy := y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var a := hash01(ix, iy, s)
	var b := hash01(ix + 1.0, iy, s)
	var c := hash01(ix, iy + 1.0, s)
	var d := hash01(ix + 1.0, iy + 1.0, s)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)

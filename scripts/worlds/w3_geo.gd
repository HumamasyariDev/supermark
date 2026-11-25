extends RefCounted
## W3 Gingerbread Grove: deterministic geometry helpers used by the baker (w3_bake.gd).
## Height function from Docs/levels/W3.md section 3 (ops read from data/levels/W3.json),
## spline helpers and procedural mesh builders (rounded boxes, lathes, elliptic cake tiers,
## U-trough slide, tubes). Everything is pure math: same input, same output.

const X0 := -60.0
const Z0 := -55.0
const STEP := 0.5
const NX := 241
const NZ := 221

var data: Dictionary = {}
var H := PackedFloat32Array()
var path_mask := PackedFloat32Array()   # 0..1 biscuit-path weight (inner width)
var water_mask := PackedFloat32Array()  # 0..1 near carved water
var cap_mask := PackedFloat32Array()    # 0..1 icing cap on hill crests
var paths: Array = []                   # [{id, w, sh, pts: PackedVector3Array (dense)}]
var river_pts := PackedVector3Array()   # dense: x, width, z  (y holds width)


func load_data(json_path: String) -> bool:
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		push_error("w3_geo: cannot open " + json_path)
		return false
	data = JSON.parse_string(f.get_as_text())
	return data != null


# ---------------------------------------------------------------- splines

static func catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Dense Catmull-Rom polyline through pts (endpoints duplicated), `sub` samples per segment.
static func dense(pts: PackedVector3Array, sub: int = 8) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := pts.size()
	if n < 2:
		return pts
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		for s in sub:
			out.append(catmull(p0, p1, p2, p3, float(s) / float(sub)))
	out.append(pts[n - 1])
	return out


## Resample a dense polyline at a fixed arc-length spacing.
static func resample(pts: PackedVector3Array, spacing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.size() < 2:
		return pts
	out.append(pts[0])
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var d := spacing - carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			d += spacing
		carry = seg - (d - spacing)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > spacing * 0.3:
		out.append(pts[pts.size() - 1])
	return out


static func polyline_length(pts: PackedVector3Array) -> float:
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l


## Closest point on a polyline in XZ. Returns [dist, t_along (0..1 segment param), seg_index].
static func closest_xz(pts: PackedVector3Array, x: float, z: float) -> Array:
	var best := 1e9
	var bi := 0
	var bt := 0.0
	for i in pts.size() - 1:
		var ax := pts[i].x
		var az := pts[i].z
		var dx := pts[i + 1].x - ax
		var dz := pts[i + 1].z - az
		var l2 := dx * dx + dz * dz
		var t := 0.0
		if l2 > 1e-6:
			t = clampf(((x - ax) * dx + (z - az) * dz) / l2, 0.0, 1.0)
		var px := ax + dx * t - x
		var pz := az + dz * t - z
		var d := px * px + pz * pz
		if d < best:
			best = d
			bi = i
			bt = t
	return [sqrt(best), bt, bi]


# ---------------------------------------------------------------- height function

static func smooth(e0: float, e1: float, x: float) -> float:
	if e1 == e0:
		return 1.0 if x >= e1 else 0.0
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func rect_dist(x: float, z: float, xr: Array, zr: Array, cr: float) -> float:
	var cx := (float(xr[0]) + float(xr[1])) * 0.5
	var cz := (float(zr[0]) + float(zr[1])) * 0.5
	var hx := (float(xr[1]) - float(xr[0])) * 0.5
	var hz := (float(zr[1]) - float(zr[0])) * 0.5
	var qx := absf(x - cx) - (hx - cr)
	var qz := absf(z - cz) - (hz - cr)
	var outside := Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length()
	return maxf(outside + minf(maxf(qx, qz), 0.0) - cr, 0.0)


static func ellipse_dist(x: float, z: float, c: Array, r: Array) -> float:
	var dx := (x - float(c[0])) / float(r[0])
	var dz := (z - float(c[1])) / float(r[1])
	return maxf((sqrt(dx * dx + dz * dz) - 1.0) * minf(float(r[0]), float(r[1])), 0.0)


func _max_op(h: float, d: float, top: float, falloff: float, low: float) -> float:
	if d >= falloff and falloff > 0.0:
		return h
	var v := top - (top - low) * smooth(0.0, falloff, d)
	return maxf(h, v)


func build_paths() -> void:
	paths.clear()
	for p in data["splines"]["paths"]:
		var pts := PackedVector3Array()
		for q in p["points"]:
			pts.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
		var dp := dense(pts, 6)
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for q2 in dp:
			mn = Vector2(minf(mn.x, q2.x), minf(mn.y, q2.z))
			mx = Vector2(maxf(mx.x, q2.x), maxf(mx.y, q2.z))
		var pad := float(p["width"]) * 0.5 + float(p["shoulder"]) + 0.1
		paths.append({"id": p["id"], "w": float(p["width"]), "sh": float(p["shoulder"]), "pts": dp, "raw": pts,
			"mn": mn - Vector2(pad, pad), "mx": mx + Vector2(pad, pad)})
	var rp := PackedVector3Array()
	for q in data["splines"]["river"]["points"]:
		rp.append(Vector3(float(q[0]), float(q[2]), float(q[1])))
	river_pts = dense(rp, 8)


func height_raw(x: float, z: float) -> Array:
	var h := float(data["terrain"]["base_height"])
	var pm := 0.0
	var wm := 0.0
	var cap := 0.0
	for op in data["terrain"]["ops"]:
		match String(op["op"]):
			"rect_max":
				var dr := rect_dist(x, z, op["x"], op["z"], float(op.get("corner_r", 0)))
				var fo := float(op["falloff"])
				if String(op.get("id", "")) == "falls_cliff":
					# Organic rock-candy cliff: the face recedes by up to 1.6 m in lumpy bays, and steps down in two ledges.
					# R1 QA fix: rect_dist is 0 inside the rect, so the recede used to corrugate the whole cliff top into
					# 11 m trenches. It now applies only within 2.5 m of the exposed north and east faces.
					var din := minf(float(op["z"][1]) - z, float(op["x"][1]) - x)
					var face_k := 1.0 - smooth(0.0, 2.5, din)
					dr += face_k * ((0.5 + 0.5 * sin(x * 0.55 + sin(z * 0.3) * 2.0)) * 1.2 + (0.5 + 0.5 * sin(x * 1.7 + 1.3)) * 0.4)
					fo = 2.2
				h = _max_op(h, dr, float(op["h"]), fo, float(op.get("low", 1.0)))
			"rect_flatten":
				var dfl := rect_dist(x, z, op["x"], op["z"], float(op.get("corner_r", 0)))
				h = lerpf(h, float(op["h"]), 1.0 - smooth(0.0, float(op["falloff"]), dfl))
			"ellipse_max":
				h = _max_op(h, ellipse_dist(x, z, op["c"], op["r"]), float(op["h"]), float(op["falloff"]), float(op.get("low", 1.0)))
			"circle_max":
				var dc := maxf(Vector2(x - float(op["c"][0]), z - float(op["c"][1])).length() - float(op["r"]), 0.0)
				h = _max_op(h, dc, float(op["h"]), float(op["falloff"]), float(op.get("low", 1.0)))
			"hills_add":
				for hl in op["hills"]:
					var d := Vector2(x - float(hl["c"][0]), z - float(hl["c"][1])).length()
					var r := float(hl["r"])
					if d < r:
						var kk := 0.5 * (1.0 + cos(PI * d / r))
						h += float(hl["a"]) * kk
						cap = maxf(cap, smooth(0.55, 0.75, kk + sin(atan2(z - float(hl["c"][1]), x - float(hl["c"][0])) * 5.0) * 0.05))
			"path_flatten":
				for p in paths:
					var bmn: Vector2 = p["mn"]
					var bmx: Vector2 = p["mx"]
					if x < bmn.x or z < bmn.y or x > bmx.x or z > bmx.y:
						continue
					var c := closest_xz(p["pts"], x, z)
					var d: float = c[0]
					var w2: float = p["w"] * 0.5
					if d < w2 + p["sh"]:
						var pts: PackedVector3Array = p["pts"]
						var i: int = c[2]
						var yp := lerpf(pts[i].y, pts[i + 1].y, c[1])
						var m := 1.0 - smooth(w2, w2 + p["sh"], d)
						h = lerpf(h, yp, m)
						pm = maxf(pm, 1.0 - smooth(w2 - 0.4, w2 + 0.5, d))
			"carve_spline":
				var c2 := closest_xz(river_pts, x, z)
				var j: int = c2[2]
				var w := lerpf(river_pts[j].y, river_pts[j + 1].y, c2[1])
				var e := w * 0.5
				var bed := float(op["bed"])
				var k := smooth(e, e + float(op["bank"]), c2[0])
				h = bed + (h - bed) * k
				wm = maxf(wm, 1.0 - smooth(e + float(op["bank"]) * 0.5, e + float(op["bank"]) + 1.0, c2[0]))
			"carve_ellipse":
				var de := ellipse_dist(x, z, op["c"], op["r"])
				var bed2 := float(op["bed"])
				h = bed2 + (h - bed2) * smooth(0.0, float(op["bank"]), de)
				wm = maxf(wm, 1.0 - smooth(float(op["bank"]) * 0.5, float(op["bank"]) + 1.0, de))
			"carve_circle":
				var dcc := maxf(Vector2(x - float(op["c"][0]), z - float(op["c"][1])).length() - float(op["r"]), 0.0)
				var bed3 := float(op["bed"])
				h = bed3 + (h - bed3) * smooth(0.0, float(op["bank"]), dcc)
	return [h, pm, wm, cap * (1.0 - pm)]


func bake_heights() -> void:
	build_paths()
	H.resize(NX * NZ)
	path_mask.resize(NX * NZ)
	water_mask.resize(NX * NZ)
	cap_mask.resize(NX * NZ)
	for iz in NZ:
		var z := Z0 + iz * STEP
		for ix in NX:
			var x := X0 + ix * STEP
			var r := height_raw(x, z)
			H[iz * NX + ix] = r[0]
			path_mask[iz * NX + ix] = r[1]
			water_mask[iz * NX + ix] = r[2]
			cap_mask[iz * NX + ix] = r[3]


func h_at(x: float, z: float) -> float:
	var fx := clampf((x - X0) / STEP, 0.0, NX - 1.001)
	var fz := clampf((z - Z0) / STEP, 0.0, NZ - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := H[iz * NX + ix]
	var b := H[iz * NX + ix + 1]
	var c := H[(iz + 1) * NX + ix]
	var d := H[(iz + 1) * NX + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func normal_at_index(ix: int, iz: int) -> Vector3:
	var l := H[iz * NX + maxi(ix - 1, 0)]
	var r := H[iz * NX + mini(ix + 1, NX - 1)]
	var d := H[maxi(iz - 1, 0) * NX + ix]
	var u := H[mini(iz + 1, NZ - 1) * NX + ix]
	return Vector3(l - r, 2.0 * STEP, d - u).normalized()


func path_at(x: float, z: float) -> float:
	var fx := clampf((x - X0) / STEP, 0.0, NX - 1.0)
	var fz := clampf((z - Z0) / STEP, 0.0, NZ - 1.0)
	return path_mask[int(round(fz)) * NX + int(round(fx))]


# ---------------------------------------------------------------- terrain mesh

## Vertex colour channels: r = path, g = chocolate mud near water, b = pink rock candy (falls cliff),
## a = icing lip (top of steep slopes).
func terrain_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(NX * NZ)
	norms.resize(NX * NZ)
	cols.resize(NX * NZ)
	uvs.resize(NX * NZ)
	for iz in NZ:
		for ix in NX:
			var i := iz * NX + ix
			var x := X0 + ix * STEP
			var z := Z0 + iz * STEP
			var h := H[i]
			var n := normal_at_index(ix, iz)
			verts[i] = Vector3(x, h, z)
			norms[i] = n
			uvs[i] = Vector2(x, z)
			var steep := 1.0 - smooth(0.72, 0.86, n.y)
			# icing: steep vertex whose ground 1-2 m uphill is flat and near
			var lip := 0.0
			if steep > 0.2:
				var hi := h
				for o in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
					var jx := clampi(ix + o.x, 0, NX - 1)
					var jz := clampi(iz + o.y, 0, NZ - 1)
					hi = maxf(hi, H[jz * NX + jx])
				lip = 1.0 - smooth(0.4, 1.4, hi - h)
				lip *= steep
			var mud := water_mask[i] * (1.0 - smooth(0.4, 1.0, h))
			var pink := 0.0
			if x < -28.0 and z < -38.0:
				pink = smooth(1.5, 4.0, h) * (1.0 - smooth(14.5, 15.8, h) * (1.0 - steep))
			cols[i] = Color(path_mask[i] * (1.0 - steep), mud, pink, maxf(lip, cap_mask[i]))
	var idx := PackedInt32Array()
	for iz in NZ - 1:
		for ix in NX - 1:
			var a := iz * NX + ix
			var b := a + 1
			var c := a + NX
			var d := c + 1
			# alternate diagonals for nicer shading
			if (ix + iz) % 2 == 0:
				idx.append_array([a, b, d, a, d, c])
			else:
				idx.append_array([a, b, c, b, d, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Godot front faces are clockwise seen from the front; our grid indices above are CCW seen from +Y.
static func _flip(idx: PackedInt32Array) -> PackedInt32Array:
	for t in range(0, idx.size(), 3):
		var tmp := idx[t + 1]
		idx[t + 1] = idx[t + 2]
		idx[t + 2] = tmp
	return idx


func terrain_collision(step_mult: int = 1) -> ConcavePolygonShape3D:
	var faces := PackedVector3Array()
	var s := step_mult
	for iz in range(0, NZ - s, s):
		for ix in range(0, NX - s, s):
			var a := Vector3(X0 + ix * STEP, H[iz * NX + ix], Z0 + iz * STEP)
			var b := Vector3(X0 + (ix + s) * STEP, H[iz * NX + ix + s], Z0 + iz * STEP)
			var c := Vector3(X0 + ix * STEP, H[(iz + s) * NX + ix], Z0 + (iz + s) * STEP)
			var d := Vector3(X0 + (ix + s) * STEP, H[(iz + s) * NX + ix + s], Z0 + (iz + s) * STEP)
			faces.append_array([a, d, b, a, c, d])
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(faces)
	sh.backface_collision = true
	return sh


## Cut-cake skirt down the four page edges: soil, cream and sponge bands as vertex colours.
func skirt_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := []
	# each edge: list of (ix, iz) along it, outward normal
	var south := []
	var north := []
	var west := []
	var east := []
	for ix in NX:
		south.append(Vector2i(ix, NZ - 1))
		north.append(Vector2i(NX - 1 - ix, 0))
	for iz in NZ:
		west.append(Vector2i(0, iz))
		east.append(Vector2i(NX - 1, NZ - 1 - iz))
	edges = [[south, Vector3(0, 0, 1)], [north, Vector3(0, 0, -1)], [west, Vector3(-1, 0, 0)], [east, Vector3(1, 0, 0)]]
	var bands := [[0.0, Color(0.48, 0.27, 0.14)], [-1.6, Color(0.42, 0.23, 0.12)], [-1.9, Color(1.0, 0.95, 0.88)], [-2.7, Color(1.0, 0.95, 0.88)],
		[-3.0, Color(0.95, 0.74, 0.46)], [-6.4, Color(0.9, 0.66, 0.4)], [-6.7, Color(1.0, 0.62, 0.74)], [-7.6, Color(1.0, 0.62, 0.74)], [-8.0, Color(0.95, 0.74, 0.46)]]
	for e in edges:
		var pts: Array = e[0]
		var n: Vector3 = e[1]
		for k in pts.size() - 1:
			var p0: Vector2i = pts[k]
			var p1: Vector2i = pts[k + 1]
			var a := Vector3(X0 + p0.x * STEP, H[p0.y * NX + p0.x], Z0 + p0.y * STEP)
			var b := Vector3(X0 + p1.x * STEP, H[p1.y * NX + p1.x], Z0 + p1.y * STEP)
			for bi in bands.size() - 1:
				var y0a: float = a.y + bands[bi][0] if bi > 0 else a.y
				var y0b: float = b.y + bands[bi][0] if bi > 0 else b.y
				var y1a: float = a.y + bands[bi + 1][0]
				var y1b: float = b.y + bands[bi + 1][0]
				if bi + 1 == bands.size() - 1:
					y1a = minf(y1a, -8.0)
					y1b = minf(y1b, -8.0)
				var c0: Color = bands[bi][1]
				var c1: Color = bands[bi + 1][1]
				var bulge := 0.25 * sin(float(bi) * 1.7)
				var off0 := n * (bulge)
				_quad(st, Vector3(a.x, y0a, a.z) + off0, Vector3(b.x, y0b, b.z) + off0, Vector3(b.x, y1b, b.z) + off0, Vector3(a.x, y1a, a.z) + off0, n, c0, c1)
		# underside cap is not needed (camera never looks up from below the page)
	st.generate_tangents()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ctop: Color, cbot: Color) -> void:
	# a,b top edge; c,d bottom edge (b->c, a->d). Wind so that the face points along n.
	var fn := (b - a).cross(d - a)
	var flip := fn.dot(n) > 0.0
	var tri := [[a, ctop], [b, ctop], [c, cbot], [a, ctop], [c, cbot], [d, cbot]]
	if flip:
		tri = [[a, ctop], [c, cbot], [b, ctop], [a, ctop], [d, cbot], [c, cbot]]
	for v in tri:
		st.set_normal(n)
		st.set_color(_lin(v[1]))
		st.set_uv(Vector2(v[0].x + v[0].z, v[0].y))
		st.add_vertex(v[0])


# ---------------------------------------------------------------- generic mesh builders

## Vertex colours are authored as sRGB hex values; shaders read COLOR as linear, so convert once here.
static func _lin(c: Color) -> Color:
	return c.srgb_to_linear()


## Rounded box centred at the origin. Vertex colour optional (top lighter for readability).
static func rounded_box(size: Vector3, r: float = 0.12, seg: int = 3, top_col: Color = Color.WHITE, side_col: Color = Color.WHITE) -> ArrayMesh:
	r = minf(r, minf(size.x, minf(size.y, size.z)) * 0.5 - 0.001)
	var half := size * 0.5
	var inner := half - Vector3(r, r, r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := seg * 2 + 1
	var faces := [
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var fn: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var grid := []
		for j in n + 1:
			var row := []
			for i in n + 1:
				var s := float(i) / n * 2.0 - 1.0
				var t := float(j) / n * 2.0 - 1.0
				var p := fn * half + u * half * s + v * half * t
				var q := Vector3(clampf(p.x, -inner.x, inner.x), clampf(p.y, -inner.y, inner.y), clampf(p.z, -inner.z, inner.z))
				var dir := (p - q)
				if dir.length() < 1e-5:
					dir = fn
				dir = dir.normalized()
				row.append([q + dir * r, dir])
			grid.append(row)
		for j in n:
			for i in n:
				var a: Array = grid[j][i]
				var b: Array = grid[j][i + 1]
				var c: Array = grid[j + 1][i + 1]
				var d: Array = grid[j + 1][i]
				var tri := [a, b, c, a, c, d]
				var e1: Vector3 = b[0] - a[0]
				var e2: Vector3 = c[0] - a[0]
				if e1.cross(e2).dot(fn) > 0.0:
					tri = [a, c, b, a, d, c]
				for vv in tri:
					var nn: Vector3 = vv[1]
					st.set_normal(nn)
					st.set_color(_lin(top_col.lerp(side_col, 1.0 - smooth(0.3, 0.8, nn.y))))
					st.set_uv(Vector2(vv[0].x + vv[0].z, vv[0].y))
					st.add_vertex(vv[0])
	return st.commit()


## Lathe around Y. profile: Array of Vector2(radius, y) from bottom to top. Smooth normals.
## sx/sz scale the ring into an ellipse. cols: optional per-profile-point colours.
static func lathe(profile: Array, segs: int = 32, sx: float = 1.0, sz: float = 1.0, cols: Array = [], cap_top: bool = false, cap_bottom: bool = false, wobble: float = 0.0, wobble_freq: int = 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var np := profile.size()
	# profile normals (2D) from neighbours
	var pn := []
	for k in np:
		var a: Vector2 = profile[maxi(k - 1, 0)]
		var b: Vector2 = profile[mini(k + 1, np - 1)]
		var tng := (b - a).normalized()
		pn.append(Vector2(tng.y, -tng.x))
	var ring := []
	for k in np:
		var row := []
		for s in segs + 1:
			var th := TAU * float(s) / segs
			var p: Vector2 = profile[k]
			var rr := p.x * (1.0 + wobble * sin(th * wobble_freq))
			var pos := Vector3(cos(th) * rr * sx, p.y, sin(th) * rr * sz)
			var n2: Vector2 = pn[k]
			var nrm := Vector3(cos(th) * n2.x / maxf(sx, 0.001), n2.y, sin(th) * n2.x / maxf(sz, 0.001)).normalized()
			var c: Color = cols[k] if k < cols.size() else Color.WHITE
			row.append([pos, nrm, c, Vector2(float(s) / segs, p.y)])
		ring.append(row)
	for k in np - 1:
		for s in segs:
			var a: Array = ring[k][s]
			var b: Array = ring[k][s + 1]
			var c: Array = ring[k + 1][s + 1]
			var d: Array = ring[k + 1][s]
			for vv in [a, b, c, a, c, d]:
				st.set_normal(vv[1])
				st.set_color(_lin(vv[2]))
				st.set_uv(vv[3])
				st.add_vertex(vv[0])
	if cap_top:
		_cap(st, ring[np - 1], profile[np - 1].y, true, segs)
	if cap_bottom:
		_cap(st, ring[0], profile[0].y, false, segs)
	return st.commit()


static func _cap(st: SurfaceTool, row: Array, y: float, up: bool, segs: int) -> void:
	var n := Vector3.UP if up else Vector3.DOWN
	var c: Color = row[0][2]
	for s in segs:
		var a: Vector3 = row[s][0]
		var b: Vector3 = row[s + 1][0]
		var o := Vector3(0, y, 0)
		var tri := [o, a, b] if up else [o, b, a]
		for v in tri:
			st.set_normal(n)
			st.set_color(_lin(c))
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v)


## Elliptic cake tier: sponge wall with a cream filling band, icing top and an icing lip with drips.
static func cake_tier(rx: float, rz: float, y0: float, y1: float, sponge: Color, icing: Color, segs: int = 96, seed_v: int = 1) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cream := Color(1.0, 0.96, 0.9)
	var h := y1 - y0
	var mid := y0 + h * 0.45
	# wall bands: [y, colour]
	var bands := [[y0, sponge.darkened(0.12)], [mid - 0.25, sponge], [mid - 0.18, cream], [mid + 0.18, cream], [mid + 0.25, sponge], [y1 - 0.3, sponge.lightened(0.06)]]
	for s in segs:
		var t0 := TAU * float(s) / segs
		var t1 := TAU * float(s + 1) / segs
		var n0 := Vector3(cos(t0) / rx, 0, sin(t0) / rz).normalized()
		var n1 := Vector3(cos(t1) / rx, 0, sin(t1) / rz).normalized()
		var p0 := Vector3(cos(t0) * rx, 0, sin(t0) * rz)
		var p1 := Vector3(cos(t1) * rx, 0, sin(t1) * rz)
		for b in bands.size() - 1:
			var ya: float = bands[b][0]
			var yb: float = bands[b + 1][0]
			var ca: Color = bands[b][1]
			var cb: Color = bands[b + 1][1]
			_vq(st, p0 + Vector3(0, ya, 0), p1 + Vector3(0, ya, 0), p1 + Vector3(0, yb, 0), p0 + Vector3(0, yb, 0), n0, n1, ca, cb)
	# icing lip with drips (outset 0.15, from y1 + 0.06 down to y1 - 0.6 - drip)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var drips := PackedFloat32Array()
	drips.resize(segs + 1)
	var k := 0
	while k < segs:
		var w := rng.randi_range(3, 7)
		var dl := rng.randf_range(0.15, 1.3) * minf(1.0, h / 4.0 + 0.4)
		for j in w:
			if k + j < segs:
				var tt := float(j) / float(maxi(w - 1, 1))
				drips[k + j] = dl * sin(tt * PI) * 0.9 + 0.05
		k += w + rng.randi_range(0, 3)
	drips[segs] = drips[0]
	var o := 0.15
	for s in segs:
		var t0 := TAU * float(s) / segs
		var t1 := TAU * float(s + 1) / segs
		var n0 := Vector3(cos(t0) / rx, 0, sin(t0) / rz).normalized()
		var n1 := Vector3(cos(t1) / rx, 0, sin(t1) / rz).normalized()
		var p0 := Vector3(cos(t0) * rx, 0, sin(t0) * rz) + n0 * o
		var p1 := Vector3(cos(t1) * rx, 0, sin(t1) * rz) + n1 * o
		var b0 := y1 - 0.55 - drips[s]
		var b1 := y1 - 0.55 - drips[s + 1]
		# rounded top roll of the lip
		var r0 := p0 + n0 * 0.06
		var r1 := p1 + n1 * 0.06
		_vq(st, Vector3(p0.x, b0, p0.z), Vector3(p1.x, b1, p1.z), Vector3(r1.x, y1 - 0.12, r1.z), Vector3(r0.x, y1 - 0.12, r0.z), n0, n1, icing.darkened(0.04), icing)
		var top0 := Vector3(cos(t0) * rx, y1 + 0.05, sin(t0) * rz) - n0 * 0.05
		var top1 := Vector3(cos(t1) * rx, y1 + 0.05, sin(t1) * rz) - n1 * 0.05
		_vq(st, Vector3(r0.x, y1 - 0.12, r0.z), Vector3(r1.x, y1 - 0.12, r1.z), top1, top0, (n0 + Vector3.UP).normalized(), (n1 + Vector3.UP).normalized(), icing, icing.lightened(0.05))
		# underside of the lip (closes the overhang)
		var w0 := Vector3(cos(t0) * rx, b0 + 0.02, sin(t0) * rz)
		var w1 := Vector3(cos(t1) * rx, b1 + 0.02, sin(t1) * rz)
		_vq(st, w0, w1, Vector3(p1.x, b1, p1.z), Vector3(p0.x, b0, p0.z), Vector3.DOWN, Vector3.DOWN, icing.darkened(0.15), icing.darkened(0.1))
		# drip bulb tips: small rounded bottom (just a short darker band)
		# top cap
		var c0 := Vector3(0, y1 + 0.05, 0)
		var tri := [c0, top0, top1]
		for v in tri:
			st.set_normal(Vector3.UP)
			st.set_color(_lin(icing.lightened(0.04)))
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v)
	return st.commit()


## Vertical/any quad a,b,c,d (a,b bottom; d,c top) with per-column normals n0 (a,d) and n1 (b,c).
static func _vq(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n0: Vector3, n1: Vector3, cb: Color, ct: Color) -> void:
	var face := (b - a).cross(d - a)
	var outward := (n0 + n1).normalized()
	var order := [[a, n0, cb], [d, n0, ct], [c, n1, ct], [a, n0, cb], [c, n1, ct], [b, n1, cb]]
	if face.dot(outward) < 0.0:
		order = [[a, n0, cb], [c, n1, ct], [d, n0, ct], [a, n0, cb], [b, n1, cb], [c, n1, ct]]
	for v in order:
		st.set_normal(v[1])
		st.set_color(_lin(v[2]))
		st.set_uv(Vector2(v[0].x + v[0].z, v[0].y))
		st.add_vertex(v[0])


static func ellipse_hull(rx: float, rz: float, y0: float, y1: float, segs: int = 48) -> ConvexPolygonShape3D:
	var pts := PackedVector3Array()
	for s in segs:
		var t := TAU * float(s) / segs
		pts.append(Vector3(cos(t) * rx, y0, sin(t) * rz))
		pts.append(Vector3(cos(t) * rx, y1, sin(t) * rz))
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	return sh


## U-trough along a dense centre line. Returns [mesh, collision faces].
static func trough(center: PackedVector3Array, width: float, wall_h: float, floor_col: Color, wall_col: Color) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	# cross-section profile in (side, up): floor flat with rounded walls, outer skin
	var hw := width * 0.5
	var prof := [Vector2(-hw - 0.35, wall_h + 0.05), Vector2(-hw - 0.1, wall_h + 0.18), Vector2(-hw, wall_h), Vector2(-hw + 0.05, wall_h * 0.5), Vector2(-hw + 0.35, 0.08),
		Vector2(-hw + 0.8, 0.0), Vector2(0, 0.0), Vector2(hw - 0.8, 0.0), Vector2(hw - 0.35, 0.08), Vector2(hw - 0.05, wall_h * 0.5), Vector2(hw, wall_h),
		Vector2(hw + 0.1, wall_h + 0.18), Vector2(hw + 0.35, wall_h + 0.05), Vector2(hw + 0.4, -0.25), Vector2(-hw - 0.4, -0.25), Vector2(-hw - 0.35, wall_h + 0.05)]
	var n := center.size()
	var frames := []
	for i in n:
		var a := center[maxi(i - 1, 0)]
		var b := center[mini(i + 1, n - 1)]
		var fwd := (b - a)
		var flat := Vector3(fwd.x, 0, fwd.z).normalized()
		var side := Vector3.UP.cross(flat).normalized() * -1.0   # right-hand side
		var up := fwd.normalized().cross(side).normalized() * -1.0
		if up.y < 0.0:
			up = -up
		frames.append([side, up])
	for i in n - 1:
		var s0: Vector3 = frames[i][0]
		var u0: Vector3 = frames[i][1]
		var s1: Vector3 = frames[i + 1][0]
		var u1: Vector3 = frames[i + 1][1]
		for k in prof.size() - 1:
			var pa: Vector2 = prof[k]
			var pb: Vector2 = prof[k + 1]
			var a0 := center[i] + s0 * pa.x + u0 * pa.y
			var b0 := center[i] + s0 * pb.x + u0 * pb.y
			var a1 := center[i + 1] + s1 * pa.x + u1 * pa.y
			var b1 := center[i + 1] + s1 * pb.x + u1 * pb.y
			var d2 := (pb - pa).normalized()
			var n2 := Vector2(-d2.y, d2.x)   # inward-up normal for the inner surface
			var nn0 := (s0 * n2.x + u0 * n2.y).normalized()
			var nn1 := (s1 * n2.x + u1 * n2.y).normalized()
			var inner := k >= 2 and k <= 9
			var col := floor_col if (k >= 3 and k <= 8) else wall_col
			if k >= 12:
				col = Color(0.93, 0.78, 0.55)
			var tri := [[a0, nn0], [b0, nn0], [b1, nn1], [a0, nn0], [b1, nn1], [a1, nn1]]
			var fn := (b0 - a0).cross(a1 - a0)
			if fn.dot(nn0) > 0.0:
				tri = [[a0, nn0], [b1, nn1], [b0, nn0], [a0, nn0], [a1, nn1], [b1, nn1]]
			for v in tri:
				st.set_normal(v[1])
				st.set_color(_lin(col))
				st.set_uv(Vector2(float(i) * 0.5, float(k) / prof.size()))
				st.add_vertex(v[0])
			if inner or k == 1 or k == 10:
				faces.append_array([a0, b0, b1, a0, b1, a1])
	return [st.commit(), faces]


## Tube along a polyline (liquorice pipe). Twisted stripe colours.
static func tube(pts: PackedVector3Array, r: float, segs: int, col_a: Color, col_b: Color, twist: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var rings := []
	var acc := 0.0
	var prev_side := Vector3.ZERO
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var fwd := (b - a).normalized()
		var ref := Vector3.UP if absf(fwd.y) < 0.9 else Vector3.RIGHT
		var side := fwd.cross(ref).normalized()
		if prev_side != Vector3.ZERO and side.dot(prev_side) < 0.0:
			side = -side
		prev_side = side
		var up := side.cross(fwd).normalized()
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		var row := []
		for s in segs + 1:
			var th := TAU * float(s) / segs
			var dir := side * cos(th) + up * sin(th)
			var stripe := sin(th * 2.0 + acc * twist)
			row.append([pts[i] + dir * r, dir, col_a if stripe > 0.0 else col_b])
		rings.append(row)
	for i in n - 1:
		for s in segs:
			var a: Array = rings[i][s]
			var b: Array = rings[i][s + 1]
			var c: Array = rings[i + 1][s + 1]
			var d: Array = rings[i + 1][s]
			var tri := [a, b, c, a, c, d]
			var fn: Vector3 = (b[0] - a[0]).cross(d[0] - a[0])
			if fn.dot(a[1]) > 0.0:
				tri = [a, c, b, a, d, c]
			for v in tri:
				st.set_normal(v[1])
				st.set_color(_lin(v[2]))
				st.add_vertex(v[0])
	return st.commit()


## Flat disc in the local XY plane (faces +Z and -Z) with a rounded rim, UV = local xy / r (for the swirl shader).
static func swirl_disc(r: float, thick: float, segs: int = 64) -> ArrayMesh:
	var prof := [Vector2(0.0, -thick * 0.5), Vector2(r * 0.97, -thick * 0.5), Vector2(r, -thick * 0.3), Vector2(r * 1.01, 0.0), Vector2(r, thick * 0.3), Vector2(r * 0.97, thick * 0.5), Vector2(0.0, thick * 0.5)]
	var m := lathe(prof, segs)
	# lathe builds around Y; rotate to face Z by rebuilding arrays
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv := PackedVector2Array()
	uv.resize(v.size())
	for i in v.size():
		var p := v[i]
		v[i] = Vector3(p.x, p.z, p.y)
		var q := nn[i]
		nn[i] = Vector3(q.x, q.z, q.y)
		uv[i] = Vector2(v[i].x / r, v[i].y / r)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_TEX_UV] = uv
	# swapping y/z mirrors the winding: flip triangles
	var out := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, v.size(), 3):
		for j in [0, 2, 1]:
			st.set_normal(nn[i + j])
			st.set_uv(uv[i + j])
			st.add_vertex(v[i + j])
	return st.commit()

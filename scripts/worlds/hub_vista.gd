extends Node3D
## Hub window vista (owner request 19 Oct 2026: "outside the library windows ... just a bare green slope in fog; put some
## interesting things out there"). Built by hub_level after the Backdrop. Not walkable, no physics, no shadows.
##
## Views it dresses (bearings: theta from north, clockwise, as in HubArchitecture):
##   west window 1 (theta 250): the manor's formal garden (gravel walk, parterre hedges, fountain, topiary, boundary wall
##     and rose gate), then Huff & Puff Hollow on the far hills (windmill and the three pigs' houses).
##   west window 2 (theta 290): the lily pond with the gazebo and an orchard, then Beanstalk Skyway (a beanstalk rising
##     into a cloud bank with the giant's castle) and Gingerbread Grove's candy hills.
##   French doors / balcony (theta 180): the boundary wall and the drive gate below the existing backdrop landmarks.
## A ring of far hills closes the horizon all round; a hot-air balloon drifts across the west sky.
##
## Dev arguments: --vista=0 (skip, for before/after A/B), --vista-perf (GPU/CPU frame time and draw counts every 2 s),
## --vista-probe=x,y,z,r (prints every mesh instance within r of the point once the hub has settled).

const BD := preload("res://scripts/worlds/hub_backdrop.gd")
const P := "res://assets/props/"
const V := "res://assets/props/vista/"

var _t := 0.0
var _balloon: Node3D
var _sails: Node3D
var _perf := false
var _perf_t := 0.0
var _gpu: Array[float] = []
var _cpu: Array[float] = []


static func wanted(dev: Node) -> bool:
	return dev == null or String(dev.call("arg", "vista", "1")) != "0"


func _ready() -> void:
	var dev := get_node_or_null("/root/Dev")
	_perf = dev != null and bool(dev.call("has_arg", "vista-perf"))
	if _perf:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if dev and String(dev.call("arg", "vista-probe", "")) != "":
		_probe.call_deferred(String(dev.call("arg", "vista-probe", "")))
	if dev and String(dev.call("arg", "vista-tour", "")) != "":
		_tour.call_deferred(String(dev.call("arg", "vista-tour", "")), String(dev.call("arg", "vista-label", "shot")))
	if dev and String(dev.call("arg", "vista-rug", "")) != "":
		_show_rug.call_deferred(String(dev.call("arg", "vista-rug", "")))
	if not wanted(dev):
		return
	_build()


## Review aid: lays the cub's flung-costume rug at x,z (where the owner found it by the doors) for a capture.
func _show_rug(spec: String) -> void:
	var f := spec.split_floats(",")
	var rug := get_parent().get_node_or_null("Activities/SheepskinRug") as Node3D
	if rug and f.size() >= 2:
		rug.global_position = Vector3(f[0], 0.0, f[1])
		rug.rotation_degrees.y = f[2] if f.size() > 2 else 15.0
		rug.visible = true


# Terrace tops (metres), computed from the backdrop terrain so no grass pokes through: upper lawn, parterre, lower lawn.
var _tops: Array[float] = []
const TERR := [[18.0, 30.0], [30.0, 46.0], [46.0, 62.0]]
const W_TH0 := 226.0
const W_TH1 := 316.0
const WALK_A := 250.0  # west window 1: the garden walk, fountain and rose gate
const WALK_B := 292.0  # west window 2: the lily pond and the gazebo
const FLOWERS := [Color("e0708a"), Color("f2c94c"), Color("b48ee0"), Color("f4ead6")]

var _veg: HubKit.Buf  # all hedges, topiary, flowers, lily pads: one vertex-coloured mesh (one draw call)
var _vmat: ShaderMaterial


static func pol(r: float, th: float, y := 0.0) -> Vector3:
	var t := deg_to_rad(th)
	return Vector3(r * sin(t), y, -r * cos(t))


static func lin(c: Color) -> Color:
	return c.srgb_to_linear()


func _build() -> void:
	_vmat = ShaderMaterial.new()
	_vmat.shader = load("res://assets/shaders/toon.gdshader")
	_vmat.set_shader_parameter("albedo", Color.WHITE)
	_vmat.set_shader_parameter("use_vertex_color", true)
	_vmat.set_shader_parameter("triplanar", false)
	_vmat.set_shader_parameter("rim_strength", 0.12)
	_vmat.set_shader_parameter("spec_strength", 0.0)
	_vmat.set_shader_parameter("roughness_value", 1.0)
	# The west views are back-lit by the low sun; a softer, less lilac shade keeps the greens reading through the windows.
	_vmat.set_shader_parameter("shadow_tint", Color(0.68, 0.68, 0.72))
	_veg = HubKit.Buf.new()
	_veg.use_color = true
	_terraces()
	_garden_a()
	_garden_b()
	_room_hedges()
	_drive_gate()
	_meadow()
	_far_hills()
	_world_hints()
	_sky()
	HubArchitecture.mi(self, _veg.commit(), _vmat, "GardenPlanting")
	_fix_backdrop_greens()
	# Scenery never casts shadows (the sun's cascades stay on the hall).
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The backdrop's hedgerows and front-garden trees store sRGB vertex colours on a StandardMaterial3D; the retro toon
## twin multiplies COLOR as linear, so they rendered as pale sage-white blobs from the balcony. Re-colour that one
## mesh to linear and give it the vista's toon material (same look with Classic textures on or off).
func _fix_backdrop_greens() -> void:
	var mi := get_parent().get_node_or_null("Backdrop/Hedgerows") as MeshInstance3D
	if mi == null or not (mi.mesh is ArrayMesh) or mi.has_meta("vista_linear"):
		return
	var src := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		if arr[Mesh.ARRAY_COLOR] == null:
			return
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		for i in cols.size():
			cols[i] = cols[i].srgb_to_linear()
		arr[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = out
	mi.material_override = _vmat
	mi.set_meta("vista_linear", true)


# ------------------------------------------------------------------ terraces

func _max_h(r0: float, r1: float, th0: float, th1: float) -> float:
	var m := -999.0
	for i in 13:
		for j in 25:
			var p := pol(lerpf(r0, r1, float(i) / 12.0), lerpf(th0, th1, float(j) / 24.0))
			m = maxf(m, BD.h(p.x, p.z))
	return m


func _terraces() -> void:
	var stone := HubArchitecture.toon("castle_stone", Color(0.95, 0.88, 0.78), 0.4)
	var walls := HubKit.Buf.new()
	var lawn := HubKit.Buf.new()
	lawn.use_color = true
	for k in TERR.size():
		var r0: float = TERR[k][0]
		var r1: float = TERR[k][1]
		var top := _max_h(r0, r1, W_TH0, W_TH1) + 0.3
		_tops.append(top)
		# Retaining block down to well below the slope, with a stone coping band at the top.
		HubKit.lathe(walls, HubKit.rect_profile(r0, r1, top - 26.0, top), W_TH0, W_TH1, 3.0, true, true)
		HubKit.lathe(walls, HubKit.round_rect_profile(r1 - 0.6, r1 + 0.15, top, top + 0.35, 0.05, 0.08, 0.08, 0.0), W_TH0, W_TH1, 3.0, true, true)
		# Mown lawn with stripes (bands every 2 m), inset from the coping.
		_sector_top(lawn, r0 + 0.2, r1 - 0.6, W_TH0, W_TH1, top + 0.02, 2.0)
	HubArchitecture.mi(self, walls.commit(), stone, "Terraces")
	HubArchitecture.mi(self, lawn.commit(), _vmat, "TerraceLawns")
	# Gravel walks down both garden rooms, with stairs between the terraces.
	var gravel := HubKit.Buf.new()
	gravel.use_color = true
	var steps := HubKit.Buf.new()
	for th: float in [WALK_A, WALK_B]:
		for k in TERR.size():
			var r0: float = TERR[k][0]
			var r1: float = TERR[k][1] - 0.6
			_strip(gravel, r0, r1, th, 2.8, _tops[k] + 0.05, Color("dccbaa"))
			if k + 1 < TERR.size():
				var dy: float = _tops[k] - _tops[k + 1]
				var n := maxi(2, int(ceil(dy / 0.45)))
				for i in n:
					var y_top: float = _tops[k] - dy * float(i + 1) / float(n)
					var rr: float = TERR[k][1] + 0.55 * float(i) + 0.27
					var c := pol(rr, th, (y_top + _tops[k + 1] - 0.4) * 0.5)
					HubKit.rounded_box(steps, Vector3(3.2, y_top - _tops[k + 1] + 0.4, 0.6), 0.04,
						Transform3D(Basis(Vector3.UP, deg_to_rad(-th)), c))
	HubArchitecture.mi(self, gravel.commit(), _vmat, "GardenWalks")
	HubArchitecture.mi(self, steps.commit(), stone, "GardenSteps")
	# Low parapet along the lower terrace's edge, open at the rose gate.
	var par := HubKit.Buf.new()
	var r_in: float = TERR[2][1] - 0.5
	for seg in [[W_TH0, WALK_A - 2.2], [WALK_A + 2.2, W_TH1]]:
		HubKit.lathe(par, HubKit.round_rect_profile(r_in, r_in + 0.6, _tops[2], _tops[2] + 0.95, 0.0, 0.12, 0.12, 0.0), seg[0], seg[1], 2.0, true, true)
		for th in range(int(seg[0]) + 3, int(seg[1]), 6):
			HubKit.rounded_box(par, Vector3(0.9, 1.35, 0.9), 0.1, Transform3D(Basis(Vector3.UP, deg_to_rad(-float(th))), pol(r_in + 0.3, float(th), _tops[2] + 0.68)))
	HubArchitecture.mi(self, par.commit(), stone, "Parapet")


## A flat annular sector (top face only) with stripes of `band` metres in two greens.
func _sector_top(b: HubKit.Buf, r0: float, r1: float, th0: float, th1: float, y: float, band: float) -> void:
	var nr := maxi(1, int(ceil((r1 - r0) / band)))
	var nt := maxi(2, int(ceil((th1 - th0) / 2.0)))
	var c1 := lin(Color("7cb84f"))
	var c2 := lin(Color("6aa743"))
	for i in nr:
		var ra := lerpf(r0, r1, float(i) / float(nr))
		var rb := lerpf(r0, r1, float(i + 1) / float(nr))
		var c := c1 if i % 2 == 0 else c2
		var prev_a := -1
		var prev_b := -1
		for j in nt + 1:
			var th := lerpf(th0, th1, float(j) / float(nt))
			var a := b.vert(pol(ra, th, y), Vector3.UP, Vector2(ra, th) * 0.1, c)
			var bb := b.vert(pol(rb, th, y), Vector3.UP, Vector2(rb, th) * 0.1, c)
			if prev_a >= 0:
				b.quad(prev_a, prev_b, bb, a)
			prev_a = a
			prev_b = bb


## A straight radial strip along bearing `th` (a gravel walk).
func _strip(b: HubKit.Buf, r0: float, r1: float, th: float, w: float, y: float, col: Color) -> void:
	var u := pol(1.0, th)
	var side := Vector3(-u.z, 0, u.x) * (w * 0.5)
	var c := lin(col)
	var a := b.vert(u * r0 - side + Vector3(0, y, 0), Vector3.UP, Vector2.ZERO, c)
	var bb := b.vert(u * r0 + side + Vector3(0, y, 0), Vector3.UP, Vector2.ZERO, c)
	var cc := b.vert(u * r1 + side + Vector3(0, y, 0), Vector3.UP, Vector2.ZERO, c)
	var d := b.vert(u * r1 - side + Vector3(0, y, 0), Vector3.UP, Vector2.ZERO, c)
	b.quad(a, bb, cc, d)


## Local garden frame at bearing th: `along` = tangential metres, r = radial distance, y = up.
func _gx(th: float, r: float, along: float, y: float) -> Vector3:
	var u := pol(1.0, th)
	return u * r + Vector3(-u.z, 0, u.x) * along + Vector3(0, y, 0)


func _box(at: Vector3, size: Vector3, col: Color, yaw_deg := 0.0, radius := -1.0) -> void:
	var rad := radius if radius >= 0.0 else minf(size.x, minf(size.y, size.z)) * 0.42
	HubKit.rounded_box(_veg, size, rad, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), at + Vector3(0, size.y * 0.5, 0)), 1, lin(col))


## Ball topiary in a terracotta pot: three stacked clipped balls on a short trunk.
func _ball_topiary(at: Vector3, s: float) -> void:
	_box(at, Vector3(0.9, 0.7, 0.9) * s, Color("b8613e"), 0.0, 0.08 * s)
	_box(at + Vector3(0, 0.7 * s, 0), Vector3(0.14, 1.6, 0.14) * s, Color("6b4430"), 0.0, 0.05 * s)
	var y := 0.9 * s
	for k in 3:
		var d := (1.15 - 0.3 * float(k)) * s
		var g := Color("3f8a39").lerp(Color("74b24a"), float(k) * 0.35)
		_box(at + Vector3(0, y, 0), Vector3(d, d, d), g, 0.0, d * 0.48)
		y += d * 0.95


func _upper_lawn(th: float, offset: int) -> void:
	var t1 := _tops[0] + 0.05
	for a in range(-16, 17, 4):
		if absi(a) < 3:
			continue
		_ball_topiary(_gx(th, 28.4, float(a), t1), 1.0)
	for i in 26:
		var a2 := -15.0 + float(i) * 1.2
		if absf(a2) < 1.8:
			continue
		_box(_gx(th, 19.4 + float(i % 2) * 0.5, a2, t1), Vector3(1.1, 0.5, 0.9), FLOWERS[(i + offset) % 4], 0.0, 0.3)


# ------------------------------------------------------------------ west window 1: the formal garden

func _garden_a() -> void:
	var th := WALK_A
	var t2 := _tops[1] + 0.05
	# Fountain on a round gravel plaza in the middle of the parterre.
	var plaza := HubKit.Buf.new()
	plaza.use_color = true
	HubKit.disc(plaza, 5.2, 0.0, 40, _gx(th, 38.0, 0.0, t2 + 0.01), 0.1, lin(Color("dccbaa")))
	HubArchitecture.mi(self, plaza.commit(), _vmat, "FountainPlaza")
	_glb(V + "garden_fountain/garden_fountain.glb", _gx(th, 38.0, 0.0, t2), 1.35, -th + 20.0)
	# Four knot beds: box-hedge borders with a diagonal cross, flowers in the pockets, ball topiary at the corners.
	var k := 0
	for sr: float in [-1.0, 1.0]:
		for sa: float in [-1.0, 1.0]:
			var cr := 38.0 + sr * 6.4
			var ca := sa * 5.6
			var hw := 2.6
			var hr := 2.4
			var g := Color("3d7d36")
			for e in 6:
				var f := -1.0 + 2.0 * float(e) / 5.0
				# Rounded box X runs tangentially at yaw -th and radially at yaw 90 - th.
				_box(_gx(th, cr + hr, ca + f * hw, t2), Vector3(1.1, 0.55, 0.55), g, -th)
				_box(_gx(th, cr - hr, ca + f * hw, t2), Vector3(1.1, 0.55, 0.55), g, -th)
				_box(_gx(th, cr + f * hr, ca + hw, t2), Vector3(1.05, 0.55, 0.55), g, 90.0 - th)
				_box(_gx(th, cr + f * hr, ca - hw, t2), Vector3(1.05, 0.55, 0.55), g, 90.0 - th)
			for e in 5:
				var f2 := -0.8 + 1.6 * float(e) / 4.0
				_box(_gx(th, cr + f2 * hr, ca + f2 * hw, t2), Vector3(0.9, 0.45, 0.5), g.lightened(0.08), -th + 45.0)
				_box(_gx(th, cr - f2 * hr, ca + f2 * hw, t2), Vector3(0.9, 0.45, 0.5), g.lightened(0.08), -th - 45.0)
			var fc: Color = FLOWERS[k % 4]
			for q in [[0.0, 0.55], [0.0, -0.55], [0.55, 0.0], [-0.55, 0.0]]:
				for m in 3:
					var jx := float((m * 37 + k * 11) % 7) / 7.0 - 0.5
					var jy := float((m * 53 + k * 5) % 5) / 5.0 - 0.5
					_box(_gx(th, cr + float(q[0]) * hr * 1.3 + jy * 0.6, ca + float(q[1]) * hw * 1.3 + jx * 0.6, t2), Vector3(0.6, 0.35, 0.6), fc.lightened(0.05 * float(m)), 0.0, 0.25)
			_ball_topiary(_gx(th, cr + sr * (hr + 0.9), ca + sa * (hw + 0.9), t2), 0.9)
			k += 1
	_upper_lawn(th, 0)
	# Lower lawn: topiary pigs guard the walk to the rose gate, ball topiary down both sides, roses on the parapet.
	var t3 := _tops[2] + 0.05
	_glb(V + "topiary_pig/topiary_pig.glb", _gx(th, 57.5, -3.4, t3), 1.0, -th + 15.0)
	_glb(V + "topiary_pig/topiary_pig.glb", _gx(th, 57.5, 3.4, t3), 1.0, -th - 15.0)
	for r: float in [49.5, 53.0]:
		for sa: float in [-1.0, 1.0]:
			_ball_topiary(_gx(th, r, sa * 2.6, t3), 0.95)
	_glb(V + "garden_gate/garden_gate.glb", _gx(th, TERR[2][1] - 0.2, 0.0, t3), 1.0, -th)
	for i in 12:
		var a3 := -14.0 + float(i) * 2.4
		if absf(a3) < 3.5:
			continue
		_box(_gx(th, 60.0, a3, t3), Vector3(1.6, 0.7, 1.0), Color("3f7f38"), -th, 0.3)
		_box(_gx(th, 60.0, a3 + 0.3, t3 + 0.55), Vector3(0.35, 0.3, 0.35), Color("e0708a"), 0.0, 0.14)
		_box(_gx(th, 60.2, a3 - 0.4, t3 + 0.5), Vector3(0.3, 0.28, 0.3), Color("f4ead6"), 0.0, 0.12)


# ------------------------------------------------------------------ west window 2: the lily pond and the gazebo

func _garden_b() -> void:
	var th := WALK_B
	var t2 := _tops[1] + 0.05
	var c := _gx(th, 38.5, 0.0, t2)
	var u := pol(1.0, th)
	var tv := Vector3(-u.z, 0, u.x)
	var a_rad := 6.6
	var b_rad := 5.0
	# Stone rim (an oval of rounded blocks), water and lily pads.
	var rim := HubKit.Buf.new()
	for i in 30:
		var a := TAU * float(i) / 30.0
		var p := c + u * (cos(a) * a_rad) + tv * (sin(a) * b_rad)
		var tang := (-u * sin(a) * a_rad + tv * cos(a) * b_rad).normalized()
		HubKit.rounded_box(rim, Vector3(1.55, 0.45, 0.7), 0.14, Transform3D(Basis(tang, Vector3.UP, tang.cross(Vector3.UP)).orthonormalized(), p + Vector3(0, 0.2, 0)))
	HubArchitecture.mi(self, rim.commit(), HubArchitecture.toon("castle_stone", Color(0.95, 0.88, 0.78), 0.4), "PondRim")
	var wb := HubKit.Buf.new()
	var ctr := wb.vert(c + Vector3(0, 0.12, 0), Vector3.UP, Vector2(0.5, 0.5))
	var prev := -1
	for i in 41:
		var a := TAU * float(i) / 40.0
		var p := c + u * (cos(a) * (a_rad - 0.3)) + tv * (sin(a) * (b_rad - 0.3)) + Vector3(0, 0.12, 0)
		var vi := wb.vert(p, Vector3.UP, Vector2(cos(a), sin(a)) * 0.5 + Vector2(0.5, 0.5))
		if prev >= 0:
			wb.tri(ctr, prev, vi)
		prev = vi
	var wmat: Material = load("res://assets/shaders/materials/water_stream.tres") if ResourceLoader.exists("res://assets/shaders/materials/water_stream.tres") else HubKit.mat(Color("4fb3d9"), 0.2)
	HubArchitecture.mi(self, wb.commit(), wmat, "PondWater")
	var pads := [[-2.6, 1.4], [-1.2, -2.2], [1.6, 2.4], [3.1, -0.6], [0.4, 0.9], [-3.6, -1.0], [2.2, -2.6]]
	for i in pads.size():
		var pp: Array = pads[i]
		var at := c + u * float(pp[0]) + tv * float(pp[1]) + Vector3(0, 0.1, 0)
		_box(at, Vector3(1.1, 0.06, 1.0), Color("4f9a3c"), float(i) * 47.0, 0.03)
		if i % 2 == 0:
			_box(at + Vector3(0.15, 0.05, 0.1), Vector3(0.36, 0.22, 0.36), Color("f29ab4"), 0.0, 0.14)
	_glb(V + "topiary_pig/topiary_pig.glb", _gx(th, 30.8, -4.0, t2), 0.9, -th + 25.0)
	_glb(V + "topiary_pig/topiary_pig.glb", _gx(th, 30.8, 4.0, t2), 0.9, -th - 25.0)
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		_ball_topiary(c + u * (cos(a) * (a_rad + 2.2)) + tv * (sin(a) * (b_rad + 2.4)), 0.85)
	# The gazebo on the lower lawn, facing the manor.
	_glb(V + "garden_gazebo/garden_gazebo.glb", _gx(th, 54.5, 0.0, _tops[2] + 0.05), 1.15, -th)
	_upper_lawn(th, 1)


## Tall clipped hedges between and around the two garden rooms, fruit trees in the lower corners.
func _room_hedges() -> void:
	for th: float in [W_TH0 + 1.2, 271.0, W_TH1 - 1.2]:
		for k in TERR.size():
			var r0: float = TERR[k][0] + 0.8
			var r1: float = TERR[k][1] - 1.0
			var n := int((r1 - r0) / 1.6)
			for i in n + 1:
				var r := lerpf(r0, r1, float(i) / float(n))
				_box(pol(r, th, _tops[k] + 0.05), Vector3(1.4, 2.3, 1.9), Color("3a7a35").lerp(Color("4f9442"), float(i % 3) * 0.4), -th, 0.45)
	var xs: Array[Transform3D] = []
	for th: float in [W_TH0 + 6.0, W_TH0 + 12.0, 264.0, 278.0, W_TH1 - 12.0, W_TH1 - 6.0]:
		xs.append(Transform3D(Basis(Vector3.UP, deg_to_rad(th * 7.0)).scaled(Vector3.ONE * 1.1), pol(55.0, th, _tops[2] + 0.05)))
	_multi(P + "w1/apple_tree/apple_tree.glb", xs, "TerraceTrees")


# ------------------------------------------------------------------ French doors: the drive gate and the boundary wall

func _drive_gate() -> void:
	var gz := 64.0
	var gx := sin(gz * 0.08) * 3.0
	var gy := BD.h(gx, gz)
	var gate := _glb(V + "garden_gate/garden_gate.glb", Vector3(gx, gy - 0.1, gz), 1.15, 180.0)
	if gate:
		gate.name = "DriveGate"
	# A low dry-stone wall on the terrain, from the west terraces round the front to the east.
	var wall := HubKit.Buf.new()
	var r := 66.0
	var th := 120.0
	while th < W_TH0:
		var p := pol(r, th)
		if absf(p.x - gx) > 3.2 or absf(p.z - gz) > 6.0:
			var y := BD.h(p.x, p.z)
			HubKit.rounded_box(wall, Vector3(2.3, 1.1, 0.9), 0.16, Transform3D(Basis(Vector3.UP, deg_to_rad(-th)), Vector3(p.x, y + 0.4, p.z)))
		th += 1.6
	HubArchitecture.mi(self, wall.commit(), HubArchitecture.toon("castle_stone", Color(0.88, 0.82, 0.72), 0.4), "BoundaryWall")


# ------------------------------------------------------------------ beyond the wall: path, orchard, meadow

func _meadow() -> void:
	# A gravel path from the rose gate out into the fields, curving toward Huff & Puff Hollow.
	var path := HubKit.Buf.new()
	path.use_color = true
	var prev_l := -1
	var prev_r := -1
	var col := lin(Color("d4c29c"))
	for i in 31:
		var r := 62.5 + float(i) * 2.4
		var th := WALK_A - 6.0 * sin(float(i) * 0.12)
		var p := pol(r, th)
		var u := pol(1.0, th)
		var side := Vector3(-u.z, 0, u.x) * 1.3
		var l := path.vert(p - side + Vector3(0, BD.h(p.x - side.x, p.z - side.z) + 0.18, 0), Vector3.UP, Vector2.ZERO, col)
		var rr := path.vert(p + side + Vector3(0, BD.h(p.x + side.x, p.z + side.z) + 0.18, 0), Vector3.UP, Vector2.ZERO, col)
		if prev_l >= 0:
			path.quad(prev_l, prev_r, rr, l)
		prev_l = l
		prev_r = rr
	HubArchitecture.mi(self, path.commit(), _vmat, "MeadowPath")
	# Orchards on the lower slopes (one MultiMesh per tree mesh).
	var rng := RandomNumberGenerator.new()
	rng.seed = 2610
	var apples: Array[Transform3D] = []
	for row in 4:
		for j in 7:
			for blk: float in [236.0, 300.0]:
				var th := blk - 9.0 + float(j) * 3.0 + rng.randf_range(-0.6, 0.6)
				var r := 74.0 + float(row) * 9.0 + rng.randf_range(-1.0, 1.0)
				var p := pol(r, th)
				apples.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.1, 1.45)), Vector3(p.x, BD.h(p.x, p.z) - 0.2, p.z)))
	_multi(P + "w1/apple_tree/apple_tree.glb", apples, "Orchard")
	var birches: Array[Transform3D] = []
	for i in 14:
		var th := 258.0 + rng.randf_range(0.0, 26.0)
		var r := 80.0 + rng.randf_range(0.0, 45.0)
		var p := pol(r, th)
		birches.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.2, 1.6)), Vector3(p.x, BD.h(p.x, p.z) - 0.2, p.z)))
	_multi(P + "w1/birch_tree_v2/birch_tree_v2.glb", birches, "BirchCopse")
	var bales: Array[Transform3D] = []
	for i in 9:
		var th := 244.0 + float(i % 3) * 4.0 + rng.randf_range(-1.0, 1.0)
		var r := 120.0 + float(i / 3) * 7.0
		var p := pol(r, th)
		bales.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 2.2), Vector3(p.x, BD.h(p.x, p.z), p.z)))
	_multi(P + "w1/hay_bale/hay_bale.glb", bales, "HayBales")


# ------------------------------------------------------------------ the horizon

## Far hills: rolling ridges from 240 m to 560 m round the west half, fading toward the haze colour with distance.
func _ridge_y(r: float, th: float) -> float:
	var t := deg_to_rad(th)
	var hills := 11.0 * sin(t * 7.0 + 1.3) + 7.0 * sin(t * 13.0 + r * 0.013) + 4.0 * sin(t * 23.0 - r * 0.02)
	var y := lerpf(-42.0, 6.0, smoothstep(240.0, 420.0, r)) + hills * smoothstep(240.0, 330.0, r) + 16.0 * smoothstep(420.0, 560.0, r)
	var edge := smoothstep(200.0, 222.0, th) * (1.0 - smoothstep(338.0, 356.0, th))
	return lerpf(-60.0, y, edge)


func _far_hills() -> void:
	var b := HubKit.Buf.new()
	b.use_color = true
	var rs := [240.0, 275.0, 310.0, 350.0, 395.0, 440.0, 500.0, 560.0]
	var near_c := Color("79a35f")
	var far_c := Color("93aab8")
	var ths: Array[float] = []
	var th := 196.0
	while th <= 360.0:
		ths.append(th)
		th += 2.5
	var rows := []
	for r: float in rs:
		var row := []
		var cc := lin(near_c.lerp(far_c, smoothstep(260.0, 520.0, r)))
		for t2 in ths:
			var y := _ridge_y(r, t2)
			# Normal from finite differences: tangential slope, radial slope, then into world space at this bearing.
			var arc := deg_to_rad(4.0) * r
			var gt := (_ridge_y(r, t2 + 2.0) - _ridge_y(r, t2 - 2.0)) / arc
			var gr := (_ridge_y(r + 8.0, t2) - _ridge_y(r - 8.0, t2)) / 16.0
			var u := pol(1.0, t2)
			var tv := Vector3(-u.z, 0, u.x)
			var wn := (Vector3.UP - tv * gt - u * gr).normalized()
			row.append(b.vert(pol(r, t2, y), wn, Vector2(r, t2) * 0.05, cc))
		rows.append(row)
	for i in rows.size() - 1:
		for j in ths.size() - 1:
			b.quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j])
	HubArchitecture.mi(self, b.commit(), _vmat, "FarHills")


## Rounded hill mounds that lift the world hints above the slope.
func _mound(b: HubKit.Buf, at: Vector3, rad: float, hgt: float, col: Color) -> void:
	# A soft dome with a flared foot, tinted part-way toward the aerial haze (background layer, D034).
	var outline := PackedVector2Array([Vector2(0.0, -14.0), Vector2(rad * 1.12, -14.0), Vector2(rad * 1.12, -1.0)])
	for i in 9:
		var a := deg_to_rad(90.0 * float(i) / 8.0)
		outline.append(Vector2(rad * cos(a) * (1.0 + 0.1 * (1.0 - sin(a))), hgt * pow(sin(a), 0.85)))
	HubKit.turned(b, outline, 28, at, lin(col.lerp(Color("8c93b8"), 0.22)), 80.0)


func _world_hints() -> void:
	var mounds := HubKit.Buf.new()
	mounds.use_color = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# Huff & Puff Hollow (west window 1): the windmill on its ridge and the three pigs' houses on round hills.
	var hw := [[226.0, 242.0, 40.0, 22.0, Color("6aa04a")], [188.0, 253.0, 30.0, 12.0, Color("639b46")], [212.0, 262.0, 28.0, 12.0, Color("70a64e")], [150.0, 258.0, 22.0, 8.0, Color("67a04a")]]
	var tops: Array[Vector3] = []
	for m in hw:
		var p := pol(float(m[0]), float(m[1]))
		var base := BD.h(p.x, p.z) - 2.0
		_mound(mounds, Vector3(p.x, base, p.z), float(m[2]), float(m[3]), m[4])
		tops.append(Vector3(p.x, base + float(m[3]), p.z))
	var wm := _glb(P + "w1/windmill_body/windmill_body.glb", tops[0] - Vector3(0, 0.6, 0), 2.3, -242.0)
	if wm:
		_sails = _glb(P + "w1/windmill_sails/windmill_sails.glb", wm.position + Basis(Vector3.UP, deg_to_rad(-242.0)) * (Vector3(-0.02, 12.88, 3.26) * 2.3), 2.3, -242.0)
	_glb(P + "w1/straw_house/straw_house.glb", tops[1] - Vector3(0, 0.8, 0), 2.2, -253.0 + 10.0)
	_glb(P + "w1/stick_house/stick_house.glb", tops[2] - Vector3(0, 0.6, 0), 2.6, -262.0 - 8.0)
	_glb(P + "w1/brick_house/brick_house.glb", tops[3] - Vector3(0, 0.6, 0), 1.8, -258.0 + 6.0)
	# Beanstalk Skyway (west window 2): the stalk climbs out of the far hills into a cloud bank with the giant's castle.
	var bp := pol(338.0, 283.0)
	var by := _ridge_y(338.0, 283.0) - 6.0
	for i in 5:
		var seg := _glb(P + "w2/beanstalk_segment/beanstalk_segment.glb", Vector3(bp.x, by + float(i) * 30.0, bp.z), 3.0, float(i % 3) * 120.0)
		if seg:
			seg.add_to_group("hub_backdrop_sway")
	var bank := HubKit.Buf.new()
	for k in 11:
		var s := rng.randf_range(12.0, 20.0)
		HubKit.rounded_box(bank, Vector3(s * 1.2, s * 0.8, s), s * 0.42, Transform3D(Basis(), Vector3(bp.x, by + 128.0, bp.z) + Vector3(rng.randf_range(-30, 30), rng.randf_range(-4, 5), rng.randf_range(-22, 22))), 3)
	HubArchitecture.mi(self, bank.commit(), _cloud_mat(), "BeanstalkCloudBank")
	_glb(P + "w2/giant_castle/giant_castle.glb", Vector3(bp.x, by + 134.0, bp.z), 1.7, -283.0)
	# Gingerbread Grove (west window 2, to the right): pastel candy hills with lollipops, gumdrops and the cottage.
	var cw := [[228.0, 301.0, 26.0, 11.0, Color("d6a9b9")], [252.0, 309.0, 26.0, 15.0, Color("a7cdb8")], [214.0, 312.0, 18.0, 8.0, Color("dcbf9f")]]
	var ctops: Array[Vector3] = []
	for m in cw:
		var p := pol(float(m[0]), float(m[1]))
		var base := BD.h(p.x, p.z) - 2.0
		_mound(mounds, Vector3(p.x, base, p.z), float(m[2]), float(m[3]), m[4])
		ctops.append(Vector3(p.x, base + float(m[3]), p.z))
	_glb(P + "w3/gingerbread_cottage/gingerbread_cottage.glb", ctops[0] - Vector3(0, 0.6, 0), 2.2, -302.0)
	_glb(P + "w3/cupcake_tower/cupcake_tower.glb", ctops[1] - Vector3(0, 0.6, 0), 2.6, -309.0)
	var kinds := ["lollipop_tree/lollipop_tree.glb", "lollipop_tree/lollipop_tree_mint.glb", "lollipop_tree/lollipop_tree_red.glb", "gumdrop/gumdrop.glb", "gumdrop/gumdrop_violet.glb", "gumdrop/gumdrop_mint.glb"]
	for i in 12:
		var m: Array = cw[i % 3]
		var a := rng.randf() * TAU
		var f := rng.randf_range(0.4, 0.8)
		var rr := float(m[2]) * f
		var p0 := pol(float(m[0]), float(m[1]))
		# Height on the mound's turned profile (approximately a dome).
		var y := BD.h(p0.x, p0.z) - 2.0 + float(m[3]) * (1.0 - f * f) * 0.95
		_glb(P + "w3/" + String(kinds[i % kinds.size()]), Vector3(p0.x + cos(a) * rr, y, p0.z + sin(a) * rr), rng.randf_range(2.6, 3.6), -float(m[1]) + rng.randf_range(-30.0, 30.0))
	HubArchitecture.mi(self, mounds.commit(), _vmat, "WorldHills")


func _cloud_mat() -> StandardMaterial3D:
	var m := HubKit.mat(Color("fff1dc"), 0.9, 0.0, "vista_cloud")
	m.rim_enabled = true
	m.rim = 0.7
	m.rim_tint = 0.3
	m.emission_enabled = true
	m.emission = Color("fff4e6")
	m.emission_energy_multiplier = 0.35
	return m


func _sky() -> void:
	# Low storybook cloud puffs over the western hills (the backdrop's clouds all sit to the south).
	var b := HubKit.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for c in [[300.0, 238.0, 48.0], [360.0, 262.0, 62.0], [280.0, 300.0, 44.0], [420.0, 318.0, 70.0], [340.0, 226.0, 58.0]]:
		var centre := pol(float(c[0]), float(c[1]), float(c[2]))
		for k in 7:
			var s := rng.randf_range(10.0, 19.0)
			HubKit.rounded_box(b, Vector3(s * 1.15, s * 0.85, s), s * 0.44, Transform3D(Basis(), centre + Vector3(rng.randf_range(-22, 22), rng.randf_range(-2, 6) * (1.0 if k > 2 else 0.3), rng.randf_range(-9, 9))), 3)
	HubArchitecture.mi(self, b.commit(), _cloud_mat(), "WestClouds")
	# The hot-air balloon drifting across the west sky (moved in _process).
	_balloon = _glb(V + "hot_air_balloon/hot_air_balloon.glb", pol(118.0, 270.0, 18.0), 1.0, 0.0)


# ------------------------------------------------------------------ helpers

func _glb(path: String, pos: Vector3, scl: float, yaw_deg: float) -> Node3D:
	var ps := HubAssets.scene(path)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.position = pos
	n.scale = Vector3.ONE * scl
	n.rotation_degrees.y = yaw_deg
	add_child(n)
	return n


## One MultiMeshInstance3D per mesh in the GLB with all `xforms` (node-local) applied: one draw call per mesh.
func _multi(path: String, xforms: Array[Transform3D], node_name: String) -> void:
	var ps := HubAssets.scene(path)
	if ps == null or xforms.is_empty():
		return
	var inst := ps.instantiate() as Node3D
	var holder := Node3D.new()
	holder.name = node_name
	add_child(holder)
	for mi_node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_node as MeshInstance3D
		var local := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != inst:
			local = (cur as Node3D).transform * local
			cur = cur.get_parent()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = String(mi.name)
		mmi.multimesh = mm
		if mi.material_override:
			mmi.material_override = mi.material_override
		holder.add_child(mmi)
	inst.free()


# ------------------------------------------------------------------ dev helpers

## Evidence tour in ONE launch (the machine is memory-bound): the gameplay camera behind Mak at each window marker,
## two story cameras, then GPU/CPU frame times looking out of west window 2 and from the hall floor; quits at the end.
## --vista-tour=<abs out dir> --vista-label=<file prefix>
func _tour(out: String, label: String) -> void:
	await get_tree().create_timer(3.0).timeout
	var root := get_tree().current_scene
	var player := get_tree().get_first_node_in_group("player") as Node3D
	DirAccess.make_dir_recursive_absolute(out)
	var game_cam := get_viewport().get_camera_3d()
	for tag_spawn in [["winWSW", "View_WinWSW"], ["winWNW", "View_WinWNW"], ["balcony", "Balcony"], ["entrance", "View_Entrance"]]:
		var m := root.get_node_or_null("Spawns/" + String(tag_spawn[1])) as Node3D
		if m and player and player.has_method("respawn"):
			player.call("respawn", m.global_transform)
		await get_tree().create_timer(3.5).timeout
		await RenderingServer.frame_post_draw
		_tour_save("%s/%s__%s.png" % [out, label, tag_spawn[0]])
	for cam_name in ["StoryCam_D", "ReviewCam_West"]:
		var cam := root.find_child(cam_name, true, false) as Camera3D
		if cam:
			cam.make_current()
			await get_tree().create_timer(0.6).timeout
			await RenderingServer.frame_post_draw
			_tour_save("%s/%s__%s.png" % [out, label, cam_name])
	if game_cam:
		game_cam.make_current()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	for tag_spawn in [["winWNW", "View_WinWNW"], ["winWSW", "View_WinWSW"], ["hall", "Default"]]:
		var m2 := root.get_node_or_null("Spawns/" + String(tag_spawn[1])) as Node3D
		if m2 and player and player.has_method("respawn"):
			player.call("respawn", m2.global_transform)
		await get_tree().create_timer(2.0).timeout
		var gpu: Array[float] = []
		var cpu: Array[float] = []
		var fps: Array[float] = []
		var draws := 0
		var prims := 0
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 8000:
			await get_tree().process_frame
			var vp := get_viewport().get_viewport_rid()
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
			fps.append(Engine.get_frames_per_second())
			draws = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			prims = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		gpu.sort()
		cpu.sort()
		var n := gpu.size()
		print("[VistaPerf] label=%s view=%s frames=%d fps_mean=%.0f gpu_med=%.2f gpu_p95=%.2f cpu_med=%.2f cpu_p95=%.2f draws=%d prims=%d" % [
			label, tag_spawn[0], n, float(n) / 8.0, gpu[n / 2], gpu[int(n * 0.95)], cpu[n / 2], cpu[int(n * 0.95)], draws, prims])
	get_tree().quit()


func _tour_save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	print("[VistaTour] %s %s" % ["saved" if img.save_png(path) == OK else "FAILED", path])

func _probe(spec: String) -> void:
	await get_tree().create_timer(3.0).timeout
	var f := spec.split_floats(",")
	if f.size() < 4:
		return
	var c := Vector3(f[0], f[1], f[2])
	var root := get_tree().current_scene
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var ab := g.get_aabb()
		var centre := g.global_transform * ab.get_center()
		if centre.distance_to(c) <= f[3]:
			print("[VistaProbe] %s centre=%s size=%s" % [root.get_path_to(g), centre, ab.size])


func _process(delta: float) -> void:
	_t += delta
	if _sails:
		_sails.rotate_object_local(Vector3.BACK, delta * 0.45)
	if _balloon:
		# A slow circuit across the west sky (about 4 minutes per lap) with a gentle bob.
		var a := deg_to_rad(270.0 + 26.0 * sin(_t * 0.026))
		_balloon.position = Vector3(sin(a) * 118.0, 30.0 + 2.2 * sin(_t * 0.4), -cos(a) * 118.0)
		_balloon.rotation.y = _t * 0.05
	if _perf:
		var vp := get_viewport().get_viewport_rid()
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
		_perf_t += delta
		if _perf_t >= 2.0:
			_perf_t = 0.0
			_gpu.sort()
			_cpu.sort()
			var n := _gpu.size()
			print("[VistaPerf] t=%.0f fps=%.0f gpu_med=%.2f gpu_p95=%.2f cpu_med=%.2f draws=%d prims=%d objs=%d" % [_t,
				Engine.get_frames_per_second(), _gpu[n / 2], _gpu[mini(n - 1, int(n * 0.95))], _cpu[n / 2],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
			_gpu.clear()
			_cpu.clear()

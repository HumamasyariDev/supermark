class_name HubDrumArt
extends RefCounted
## Upper drum and dome dressing (r1 visual critique, round 2): the drum above the gallery (y 9-15) read as a blank
## peach plaster band with no story, no cool colour and no motion, filling 30-45 % of the wide shots.
## - Fresco panels between the pilasters: the three tales in painted colour blocks (a turning windmill, the
##   beanstalk and its cloud castle, the gingerbread house) plus trompe-l'oeil arched sky windows (blue sky,
##   drifting clouds) beside the stained glass, so the room gets its cool counterpoint.
## - Gilt rosettes on the dome ribs (the ribs themselves turn gilt in HubArchitecture).
## - Four strings of bunting (burgundy, teal, gold, cream) sagging across the drum, fluttering in a vertex shader.
## Visual only: no collision, so no route, jump or camera changes.

const PANEL_R := 15.86
const PANEL_W := 4.97
const PANEL_Y0 := 10.4
const PANEL_Y1 := 14.0
## theta -> tale (0 pigs, 1 beanstalk, 2 gingerbread, 3 sky window). Skipped: 0 (stained glass), 180 and 202.5
## (portrait frame, chimney fins).
const PANELS := {22.5: 3, 45.0: 0, 67.5: 1, 90.0: 3, 112.5: 2, 135.0: 0, 157.5: 1, 225.0: 2, 247.5: 0, 270.0: 3,
	292.5: 1, 315.0: 2, 337.5: 3}
const BUNTING := [[30.0, 150.0], [210.0, 330.0], [120.0, 240.0], [100.0, 260.0]]  # none crosses the stained glass
const FLAG_COLS := [Color("7a1f2e"), Color("2e8c8a"), Color("c9a04a"), Color("f2e6c8")]


static func build(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "DrumArt"
	root.add_child(holder)
	_frescoes(holder)
	_rosettes(holder)
	_bunting(holder)


static func _frescoes(holder: Node3D) -> void:
	var sh := load("res://assets/environment/hub/hub_fresco.gdshader") as Shader
	if sh == null:
		return
	var i := 0
	for th: float in PANELS.keys():
		var b := HubKit.Buf.new()
		var half := rad_to_deg(asin((PANEL_W * 0.5) / PANEL_R))
		var pl := HubKit.polar(PANEL_R, th - half)
		var pr := HubKit.polar(PANEL_R, th + half)
		var inward := -Vector3(sin(deg_to_rad(th)), 0, -cos(deg_to_rad(th)))
		var a := b.vert(Vector3(pl.x, PANEL_Y0, pl.z), inward, Vector2(0, 0))
		var c := b.vert(Vector3(pr.x, PANEL_Y0, pr.z), inward, Vector2(1, 0))
		var d := b.vert(Vector3(pr.x, PANEL_Y1, pr.z), inward, Vector2(1, 1))
		var e := b.vert(Vector3(pl.x, PANEL_Y1, pl.z), inward, Vector2(0, 1))
		b.quad(a, c, d, e)
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("tale", float(PANELS[th]))
		m.set_shader_parameter("seed", float(i) * 1.37)
		# Fix r2 (visual major): the second panel of each tale is mirrored, so neighbours never repeat a picture.
		var seen := 0
		for th2: float in PANELS.keys():
			if th2 < th and int(PANELS[th2]) == int(PANELS[th]):
				seen += 1
		m.set_shader_parameter("mirror", 1.0 if seen % 2 == 1 else 0.0)
		var mi := HubArchitecture.mi(holder, b.commit(), m, "Fresco_%d" % int(th), Transform3D.IDENTITY, false)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A walnut moulding frames each panel so it reads as a fixed fresco, not a decal.
		var fb := HubKit.Buf.new()
		var mid := (pl + pr) * 0.5
		var bs := HubArchitecture.along(pr - pl)
		var cy := (PANEL_Y0 + PANEL_Y1) * 0.5
		var hh := PANEL_Y1 - PANEL_Y0
		HubKit.rounded_box(fb, Vector3(PANEL_W + 0.3, 0.16, 0.16), 0.05, Transform3D(bs, mid + inward * 0.04 + Vector3(0, PANEL_Y0 - 0.04, 0)))
		HubKit.rounded_box(fb, Vector3(PANEL_W + 0.3, 0.16, 0.16), 0.05, Transform3D(bs, mid + inward * 0.04 + Vector3(0, PANEL_Y1 + 0.04, 0)))
		for sx in [-0.5, 0.5]:
			HubKit.rounded_box(fb, Vector3(0.16, hh + 0.24, 0.16), 0.05, Transform3D(bs, mid + bs.x * (PANEL_W * sx) + inward * 0.04 + Vector3(0, cy, 0)))
		HubArchitecture.mi(holder, fb.commit(), HubArchitecture.brass(), "FrescoFrame_%d" % int(th), Transform3D.IDENTITY, false)
		i += 1


static func _rosettes(holder: Node3D) -> void:
	var b := HubKit.Buf.new()
	for k in 8:
		var th := 22.5 + 45.0 * float(k)
		for i in [3, 6, 9]:
			var a := deg_to_rad(90.0 * float(i) / 12.0)
			var r := 2.5 + 14.45 * cos(a) - 0.12
			var y := 16.0 + 6.0 * pow(sin(a), 0.8) - 0.2
			var p := HubKit.polar(r, th, y)
			var look := (Vector3(0, 6.0, 0) - p).normalized()
			var bs := Basis.looking_at(look, Vector3.UP if absf(look.y) < 0.95 else Vector3.BACK)
			# A turned rosette: a domed boss with a petal ring, facing down into the hall.
			var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.42, 0.0), Vector2(0.4, 0.06), Vector2(0.24, 0.1), Vector2(0.2, 0.16), Vector2(0.1, 0.22), Vector2(0.0, 0.24)])
			var xf := Transform3D(bs * Basis(Vector3.RIGHT, -PI * 0.5), p)
			var tmp := HubKit.Buf.new()
			HubKit.turned(tmp, prof, 16)
			for vi in tmp.v.size():
				b.vert(xf * tmp.v[vi], (xf.basis * tmp.n[vi]).normalized(), tmp.uv[vi])
			var base := b.v.size() - tmp.v.size()
			for ii in range(0, tmp.idx.size(), 3):
				b.idx.append_array([base + tmp.idx[ii], base + tmp.idx[ii + 1], base + tmp.idx[ii + 2]])
	HubArchitecture.mi(holder, b.commit(), HubArchitecture.brass(), "DomeRosettes", Transform3D.IDENTITY, false)


static func _bunting(holder: Node3D) -> void:
	var sh := load("res://assets/environment/hub/hub_pennant.gdshader") as Shader
	var flags := HubKit.Buf.new()
	flags.use_color = true
	var cord := HubKit.Buf.new()
	var ci := 0
	for spec in BUNTING:
		var p0 := HubKit.polar(15.75, float(spec[0]), 14.6)
		var p1 := HubKit.polar(15.75, float(spec[1]), 14.6)
		var span := p0.distance_to(p1)
		var n := int(span / 0.62)
		var sag := 1.9
		var prev := p0
		for i in range(1, n + 1):
			var t := float(i) / float(n)
			var q := p0.lerp(p1, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
			var dseg := q - prev
			HubKit.rounded_box(cord, Vector3(dseg.length() + 0.02, 0.025, 0.025), 0.01, Transform3D(HubArchitecture.along(dseg), (prev + q) * 0.5))
			if i < n:
				# One triangular flag hanging from the cord at q, facing across the hall.
				var dir := (p1 - p0).normalized()
				var side := Vector3(dir.z, 0, -dir.x)
				var col: Color = FLAG_COLS[ci % FLAG_COLS.size()]
				ci += 1
				var l := flags.vert(q - dir * 0.21, side, Vector2(0, 0), col)
				var r := flags.vert(q + dir * 0.21, side, Vector2(1, 0), col)
				var tip := flags.vert(q + Vector3(0, -0.52, 0), side, Vector2(0.5, 1), col)
				flags.idx.append_array([l, r, tip])
			prev = q
	HubArchitecture.mi(holder, cord.commit(), HubArchitecture.flat_toon(Color("4a2f1e"), 0.2, 0.1), "BuntingCord", Transform3D.IDENTITY, false)
	var fm: Material
	if sh:
		var smat := ShaderMaterial.new()
		smat.shader = sh
		fm = smat
	else:
		fm = HubKit.vcol_mat(0.6, "bunting")
	var fmi := HubArchitecture.mi(holder, flags.commit(), fm, "Bunting", Transform3D.IDENTITY, false)
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

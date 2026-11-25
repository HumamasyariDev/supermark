extends Node3D
## Hub outdoor backdrop (HUB.md section 3 "Outdoor backdrop"): the hill the manor stands on, field patchwork,
## hedgerows, a stream, the front garden and the four distant landmarks (W1 windmill, W2 beanstalk, W3 candy
## woods, the Wolf's tower under its storm cloud), all reusing the worlds' generated meshes. Not walkable.

const P := "res://assets/props/"
var _sails: Node3D
var _storm_light: OmniLight3D
var _bolt: MeshInstance3D
var _t := 0.0
var _next_flash := 3.0


static func h(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	# The plan height function, with its ripples faded out under the manor so no grass pokes through the floor.
	var ripple := 6.0 * sin(x / 37.0) * cos(z / 29.0) + 4.0 * sin((x + z) / 53.0) + 3.0 * sin(x / 11.0 + 1.3) * sin(z / 13.0) * smoothstep(60.0, 140.0, r)
	return -1.5 - 24.0 * smoothstep(20.0, 120.0, r) + ripple * smoothstep(19.0, 45.0, r)


func _ready() -> void:
	_terrain()
	_foundation()
	_hedges_and_garden()
	_stream()
	_landmarks()
	_clouds()


func _terrain() -> void:
	var n := 110
	var cell := 4.0
	var half := float(n) * cell * 0.5
	var b := HubKit.Buf.new()
	b.use_color = true
	var idx := []
	for j in n + 1:
		var row := []
		for i in n + 1:
			var x := -half + float(i) * cell
			var z := -half + float(j) * cell + 120.0
			var y := h(x, z)
			var e := 0.5
			var nrm := Vector3(h(x - e, z) - h(x + e, z), 2.0 * e, h(x, z - e) - h(x, z + e)).normalized()
			# Red channel marks the gravel drive so the terrain shader keeps it bare.
			var drive := 0.0
			if z > 17.0 and z < 60.0 and absf(x - sin(z * 0.08) * 3.0) < 2.2:
				drive = 1.0
			row.append(b.vert(Vector3(x, y, z), nrm, Vector2(x, z) * 0.1, Color(drive, 0, 0, 1)))
		idx.append(row)
	for j in n:
		for i in n:
			b.quad(idx[j][i], idx[j][i + 1], idx[j + 1][i + 1], idx[j + 1][i])
	# Fix r1b (visual): the shared meadow read desaturated olive under the hub's haze; a hub-side copy pushes the
	# grass toward the meadow green #6DBE45 (the shared material is untouched).
	var tm := (load("res://assets/shaders/materials/terrain_meadow.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	tm.set_shader_parameter("grass_tint", Color(0.9, 1.12, 0.74))
	tm.set_shader_parameter("grass_brightness", 1.16)
	tm.set_shader_parameter("shadow_tint", Color(0.42, 0.56, 0.5))
	var m := HubArchitecture.mi(self, b.commit(), tm, "BackdropTerrain")
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _foundation() -> void:
	var b := HubKit.Buf.new()
	HubKit.lathe(b, HubKit.rect_profile(16.8, 17.3, -6.0, 0.4), 0.0, 360.0, 6.0, true, false)
	# Exterior pilasters and a cornice band so the facade reads as architecture from the balcony.
	HubKit.lathe(b, HubKit.round_rect_profile(16.9, 17.4, 15.6, 16.4, 0.1, 0.2, 0.0, 0.0), 0.0, 360.0, 4.0, true, false)
	HubKit.lathe(b, HubKit.round_rect_profile(16.9, 17.25, 3.9, 4.3, 0.05, 0.1, 0.0, 0.0), 0.0, 360.0, 4.0, true, false)
	HubArchitecture.mi(self, b.commit(), HubArchitecture.toon("castle_stone", Color(0.95, 0.88, 0.78), 0.4), "Foundation")
	# Slate roof shell over the dome, seen from the balcony.
	var prof := PackedVector2Array()
	for i in 13:
		var a := deg_to_rad(90.0 * float(i) / 12.0)
		prof.append(Vector2(2.8 + 14.9 * cos(a), 16.3 + 6.6 * pow(sin(a), 0.8)))
	var rb := HubKit.Buf.new()
	HubKit.lathe(rb, prof, 0.0, 360.0, 6.0, false, false, 80.0, 0.5)
	HubArchitecture.mi(self, rb.commit(), HubArchitecture.toon("roof_shingles_slate", Color(0.75, 0.82, 0.95), 0.5), "Roof")
	# Chimney pots with smoke.
	for th in [140.0, 230.0]:
		var p := HubKit.polar(18.4, th, 18.0)
		var cb := HubKit.Buf.new()
		HubKit.rounded_box(cb, Vector3(1.6, 8.0, 1.6), 0.1, Transform3D(Basis(), p))
		p.y += 2.0
		HubArchitecture.mi(self, cb.commit(), HubArchitecture.toon("brick", Color(1, 0.9, 0.85), 0.8), "ChimneyStack")
		if ResourceLoader.exists("res://scenes/fx/ChimneySmoke.tscn"):
			var s := (load("res://scenes/fx/ChimneySmoke.tscn") as PackedScene).instantiate() as Node3D
			s.position = p + Vector3(0, 2.2, 0)
			add_child(s)


func _hedges_and_garden() -> void:
	var b := HubKit.Buf.new()
	b.use_color = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var hedges := [[Vector2(-150, 70), Vector2(150, 70)], [Vector2(-150, 120), Vector2(150, 130)], [Vector2(-40, 40), Vector2(-60, 200)], [Vector2(60, 40), Vector2(70, 200)]]
	for hd in hedges:
		var a: Vector2 = hd[0]
		var c: Vector2 = hd[1]
		var steps := int(a.distance_to(c) / 3.0)
		for i in steps:
			var p := a.lerp(c, float(i) / float(steps))
			var y := h(p.x, p.y)
			var s := rng.randf_range(1.6, 2.4)
			var hc := Color("3f8f3a").lerp(Color("6dbe45"), rng.randf_range(0.0, 0.45))
			HubKit.rounded_box(b, Vector3(3.4, s, 2.2), 0.9, Transform3D(Basis(Vector3.UP, atan2(c.x - a.x, c.y - a.y)), Vector3(p.x, y + s * 0.4, p.y)), 1, hc)
			if rng.randf() < 0.14:
				_tree(b, Vector3(p.x, y, p.y), rng, rng.randf_range(1.6, 2.6))
	# Front garden: topiary balls along the drive, rose bushes.
	for i in 8:
		for sx: float in [-1.0, 1.0]:
			var z := 22.0 + float(i) * 5.0
			var x := sin(z * 0.08) * 3.0 + sx * 4.2
			var y := h(x, z)
			# r1 visual round 2: varied trees (hue, size, two or three blob clusters on a visible trunk) instead of a
			# row of identical sage balls; the pink and lilac blobs became flowering bushes.
			_tree(b, Vector3(x, y, z), rng, rng.randf_range(0.7, 1.4))
			if i % 2 == 0:
				var bx := x + sx * 2.2
				HubKit.rounded_box(b, Vector3(1.5, 0.9, 1.4), 0.45, Transform3D(Basis(), Vector3(bx, y + 0.45, z + 2.0)), 1, Color("3f8f3a"))
				var fc := Color("e0708a") if (i / 2) % 2 == 0 else Color("b48ee0")
				for f in 7:
					var fo := Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.65, 0.95), rng.randf_range(-0.55, 0.55))
					HubKit.rounded_box(b, Vector3(0.24, 0.2, 0.24), 0.1, Transform3D(Basis(), Vector3(bx, y, z + 2.0) + fo), 1, fc.lightened(rng.randf_range(0.0, 0.2)))
	# Fix r1b: vertex colours were read as linear, which washed every hedge and tree to pale sage; read them as
	# sRGB so the authored lime-to-deep-green range shows.
	var vm := HubKit.vcol_mat(0.8, "backdrop_veg")
	vm.vertex_color_is_srgb = true
	var m := HubArchitecture.mi(self, b.commit(), vm, "Hedgerows")
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# r1 visual round 2: the FX butterflies are flat quad cards (two lay on the cobbles like litter) and break the
	# owner's real-model rule for creatures; they stay out until a real butterfly GLB exists (requested).
	if false and ResourceLoader.exists("res://scenes/fx/Butterflies.tscn"):
		var bf := (load("res://scenes/fx/Butterflies.tscn") as PackedScene).instantiate() as Node3D
		bf.position = Vector3(0, 5.0, 19.5)
		bf.scale = Vector3.ONE * 0.5
		add_child(bf)


## A storybook tree: a tapered trunk and two or three overlapping canopy blobs, hue from lime to deep green.
func _tree(b: HubKit.Buf, at: Vector3, rng: RandomNumberGenerator, sc: float) -> void:
	var trunk_h := 1.6 * sc
	HubKit.rounded_box(b, Vector3(0.38 * sc, trunk_h, 0.38 * sc), 0.12 * sc, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at + Vector3(0, trunk_h * 0.5, 0)), 1, Color("6b4430"))
	var base := Color("3f8f3a").lerp(Color("8fd14f"), rng.randf())
	var n := 2 + rng.randi() % 2
	for k in n:
		var r := rng.randf_range(1.2, 1.8) * sc
		var off := Vector3(rng.randf_range(-0.7, 0.7) * sc, trunk_h + r * 0.6 + float(k) * 0.5 * sc, rng.randf_range(-0.7, 0.7) * sc)
		HubKit.rounded_box(b, Vector3(r * 2.0, r * 1.7, r * 2.0), r * 0.82, Transform3D(Basis(), at + off), 2, base.lightened(0.06 * float(k)))


func _stream() -> void:
	var pts := [Vector2(-120, 60), Vector2(-60, 95), Vector2(-10, 120), Vector2(40, 150), Vector2(90, 175), Vector2(160, 190)]
	var curve := Curve3D.new()
	for p in pts:
		curve.add_point(Vector3(p.x, h(p.x, p.y) - 0.6, p.y))
	var length := curve.get_baked_length()
	var b := HubKit.Buf.new()
	var steps := int(length / 3.0)
	var prev_l := -1
	var prev_r := -1
	for i in steps + 1:
		var d := length * float(i) / float(steps)
		var p := curve.sample_baked(d)
		var p2 := curve.sample_baked(minf(d + 1.0, length))
		var dir := (p2 - p)
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		var right := dir.cross(Vector3.UP).normalized()
		var yy := minf(h(p.x - right.x * 3.0, p.z - right.z * 3.0), h(p.x + right.x * 3.0, p.z + right.z * 3.0)) + 0.15
		var l := b.vert(Vector3(p.x, yy, p.z) - right * 3.0, Vector3.UP, Vector2(d * 0.1, 0.0))
		var r := b.vert(Vector3(p.x, yy, p.z) + right * 3.0, Vector3.UP, Vector2(d * 0.1, 1.0))
		if prev_l >= 0:
			b.quad(prev_l, prev_r, r, l)
		prev_l = l
		prev_r = r
	var mat: Material = load("res://assets/shaders/materials/water_stream_ribbon.tres") if ResourceLoader.exists("res://assets/shaders/materials/water_stream_ribbon.tres") else HubKit.mat(Color("4fb3d9"), 0.1)
	HubArchitecture.mi(self, b.commit(), mat, "Stream").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _place(path: String, pos: Vector3, scl: float, yaw := 0.0) -> Node3D:
	var ps := HubAssets.scene(path)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.position = pos
	n.scale = Vector3.ONE * scl
	n.rotation_degrees.y = yaw
	add_child(n)
	return n


func _landmarks() -> void:
	# W1 windmill with turning sails.
	# Fix r2 (visual minor): at x -55 the windmill stacked in front of the Wolf's tower base from the balcony.
	var wp := Vector3(-35, h(-35, 150), 150)
	_place(P + "w1/windmill_body/windmill_body.glb", wp, 1.3, 200.0)
	_sails = _place(P + "w1/windmill_sails/windmill_sails.glb", wp + Vector3(0, 12.8 * 1.3, 0) + Basis(Vector3.UP, deg_to_rad(200.0)) * Vector3(0, 0, 3.2), 1.3, 200.0)
	_place(P + "w1/straw_house/straw_house.glb", Vector3(-30, h(-30, 95), 95), 1.0, 160.0)
	_place(P + "w1/brick_house/brick_house.glb", Vector3(-80, h(-80, 110), 110), 1.0, 140.0)
	# W2 beanstalk rising into a cloud bank.
	var bx := 95.0
	var bz := 210.0
	var by := h(bx, bz)
	for i in 6:
		var seg := _place(P + "w2/beanstalk_segment/beanstalk_segment.glb", Vector3(bx + sin(float(i)) * 2.0, by + float(i) * 29.0, bz), 3.0, float(i) * 47.0)
		if seg:
			seg.add_to_group("hub_backdrop_sway")
	# W3 candy woods.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var kinds := ["lollipop_tree/lollipop_tree.glb", "lollipop_tree/lollipop_tree_mint.glb", "lollipop_tree/lollipop_tree_red.glb", "gumdrop/gumdrop.glb", "gumdrop/gumdrop_violet.glb", "gumdrop/gumdrop_mint.glb"]
	for i in 22:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 30.0
		var x := 120.0 + cos(a) * r
		var z := 160.0 + sin(a) * r
		var k: String = kinds[rng.randi() % kinds.size()]
		_place(P + "w3/" + k, Vector3(x, h(x, z), z), rng.randf_range(2.0, 3.2), rng.randf() * 360.0)
	_place(P + "w3/cupcake_tower/cupcake_tower.glb", Vector3(128, h(128, 172), 172), 2.0, 30.0)
	_place(P + "w3/gingerbread_cottage/gingerbread_cottage.glb", Vector3(108, h(108, 150), 150), 1.4, -20.0)
	# The Wolf's tower on the horizon under a permanent storm cloud.
	var tp := Vector3(-140, h(-140, 380), 380)
	# r1 visual: the tower was a flat black cylinder and cone. Now a leaning toybox tower: three stacked brick drums,
	# each tilted a few degrees further, crenellated collars, a crooked plum slate spire and warm lit windows.
	var brick := HubKit.Buf.new()
	var trim := HubKit.Buf.new()
	var roof := HubKit.Buf.new()
	var win := HubKit.Buf.new()
	var drums := [[15.0, 30.0, 3.0], [12.5, 26.0, -4.0], [10.0, 22.0, 5.0]]
	var xf := Transform3D(Basis(), tp)
	for i in drums.size():
		var dr: Array = drums[i]
		var rad: float = dr[0]
		var hh: float = dr[1]
		xf = xf * Transform3D(Basis(Vector3.BACK, deg_to_rad(float(dr[2]))), Vector3.ZERO)
		var local := PackedVector2Array([Vector2(rad + 1.0, 0.0), Vector2(rad, 1.5), Vector2(rad * 0.96, hh - 2.0), Vector2(rad + 1.6, hh - 1.0), Vector2(rad + 1.6, hh), Vector2(0.0, hh)])
		var bb := HubKit.Buf.new()
		HubKit.turned(bb, local, 22)
		_append_xf(brick, bb, xf)
		var tb2 := HubKit.Buf.new()
		for k in 10:
			var a := TAU * float(k) / 10.0
			HubKit.rounded_box(tb2, Vector3(3.0, 2.4, 2.0), 0.5, Transform3D(Basis(Vector3.UP, -a), Vector3(sin(a), 0, -cos(a)) * (rad + 1.2) + Vector3(0, hh + 1.0, 0)))
		_append_xf(trim, tb2, xf)
		var wb := HubKit.Buf.new()
		for k in 3:
			var a2 := deg_to_rad(-25.0 + 25.0 * float(k) + 12.0 * float(i))
			HubKit.rounded_box(wb, Vector3(2.4, 4.0, 1.0), 0.8, Transform3D(Basis(Vector3.UP, -a2), Vector3(sin(a2), 0, cos(a2)) * (rad * 0.97) + Vector3(0, hh * 0.55, 0)))
		_append_xf(win, wb, xf)
		xf = xf * Transform3D(Basis(), Vector3(0, hh + 2.0, 0))
	var rb2 := HubKit.Buf.new()
	HubKit.turned(rb2, PackedVector2Array([Vector2(13.5, 0.0), Vector2(10.0, 6.0), Vector2(5.0, 16.0), Vector2(1.5, 26.0), Vector2(0.3, 30.0)]), 20)
	_append_xf(roof, rb2, xf * Transform3D(Basis(Vector3.BACK, deg_to_rad(-9.0)), Vector3.ZERO))
	var brick_m := HubArchitecture.toon("brick", Color("a34a3a"), 0.12)
	var trim_m := HubKit.mat(Color("6e5a72"), 0.85, 0.0, "tower_trim")
	var roof_m := HubKit.mat(Color("4a2f6b"), 0.7, 0.0, "tower_roof")
	for mm in [trim_m, roof_m]:
		(mm as StandardMaterial3D).disable_fog = true
	HubArchitecture.mi(self, brick.commit(), brick_m, "WolfTower").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	HubArchitecture.mi(self, trim.commit(), trim_m, "WolfTowerTrim").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	HubArchitecture.mi(self, roof.commit(), roof_m, "WolfTowerRoof").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	HubArchitecture.mi(self, win.commit(), HubKit.emissive(Color(1.0, 0.62, 0.25), 3.0, "tower_windows"), "TowerWindows")
	var storm := HubKit.Buf.new()
	var srng := RandomNumberGenerator.new()
	srng.seed = 13
	for i in 22:
		var off := Vector3(srng.randf_range(-45, 45), srng.randf_range(-6, 10), srng.randf_range(-20, 20))
		var s := srng.randf_range(16.0, 30.0)
		HubKit.rounded_box(storm, Vector3(s * 1.2, s * 0.85, s), s * 0.42, Transform3D(Basis(), tp + Vector3(0, 128.0, 0) + off), 3)
	var storm_mat := HubKit.mat(Color("4b3768"), 0.9, 0.0, "storm_cloud")
	storm_mat.disable_fog = true
	storm_mat.rim_enabled = true
	storm_mat.rim = 0.6
	storm_mat.rim_tint = 0.6
	HubArchitecture.mi(self, storm.commit(), storm_mat, "StormCloud").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_storm_light = OmniLight3D.new()
	_storm_light.position = tp + Vector3(0, 105.0, -30.0)
	_storm_light.light_color = Color(0.8, 0.75, 1.0)
	_storm_light.omni_range = 140.0
	_storm_light.light_energy = 0.0
	add_child(_storm_light)
	var bolt := HubKit.Buf.new()
	var p0 := tp + Vector3(10, 110, -10)
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	for i in 6:
		var p1 := p0 + Vector3(rr.randf_range(-5, 5), -9.0, rr.randf_range(-2, 2))
		var d := p1 - p0
		HubKit.rounded_box(bolt, Vector3(d.length(), 1.0, 1.0), 0.3, Transform3D(HubArchitecture.along(d), (p0 + p1) * 0.5))
		p0 = p1
	_bolt = HubArchitecture.mi(self, bolt.commit(), HubKit.emissive(Color(0.85, 0.8, 1.0), 6.0, "bolt"), "Lightning")
	_bolt.visible = false


func _clouds() -> void:
	var b := HubKit.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for c in 9:
		var centre := Vector3(rng.randf_range(-220, 220), rng.randf_range(70, 110), rng.randf_range(160, 420))
		if centre.x < -60.0 and centre.z > 300.0:
			continue
		# Round storybook puffs (r1 visual: the boxy marshmallow slabs read as boxes).
		for k in 8:
			var s := rng.randf_range(12.0, 24.0)
			HubKit.rounded_box(b, Vector3(s * 1.15, s * 0.9, s), s * 0.44, Transform3D(Basis(), centre + Vector3(rng.randf_range(-24, 24), rng.randf_range(-2, 8) * (1.0 if k > 2 else 0.3), rng.randf_range(-10, 10))), 3)
	# Cloud bank swallowing the beanstalk top.
	for k in 10:
		var s := rng.randf_range(14.0, 22.0)
		HubKit.rounded_box(b, Vector3(s * 1.2, s * 0.85, s), s * 0.42, Transform3D(Basis(), Vector3(95 + rng.randf_range(-30, 30), 160 + rng.randf_range(-4, 6), 210 + rng.randf_range(-20, 20))), 3)
	var m := HubKit.mat(Color("fff1dc"), 0.9, 0.0, "cloud_puff")
	m.rim_enabled = true
	m.rim = 0.7
	m.rim_tint = 0.3
	# Fix r1b: back-lit by the low sun the puffs read grey-beige; a soft self-light keeps them storybook white.
	m.emission_enabled = true
	m.emission = Color("fff4e6")
	m.emission_energy_multiplier = 0.35
	# The giant's castle sits on the beanstalk's cloud bank (W2's own generated mesh).
	_place(P + "w2/giant_castle/giant_castle.glb", Vector3(95, 166, 214), 1.6, 200.0)
	HubArchitecture.mi(self, b.commit(), m, "Clouds").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Appends `src`'s triangles to `dst`, transformed (HubKit.Buf has no transform-on-add).
func _append_xf(dst: HubKit.Buf, src: HubKit.Buf, xf: Transform3D) -> void:
	var base := dst.v.size()
	for i in src.v.size():
		dst.v.append(xf * src.v[i])
		dst.n.append((xf.basis * src.n[i]).normalized())
		dst.uv.append(Vector2(src.v[i].x + src.v[i].z, src.v[i].y) * 0.1)
		dst.c.append(Color.WHITE)
	for i in src.idx.size():
		dst.idx.append(base + src.idx[i])


func _process(delta: float) -> void:
	_t += delta
	if _sails:
		_sails.rotate_object_local(Vector3.BACK, delta * 0.5)
	for s in get_tree().get_nodes_in_group("hub_backdrop_sway"):
		(s as Node3D).rotation.z = sin(_t * 0.4 + (s as Node3D).position.y * 0.05) * 0.03
	_next_flash -= delta
	if _next_flash <= 0.0 and _storm_light:
		_next_flash = randf_range(3.0, 7.0)
		var tw := create_tween()
		_bolt.visible = true
		tw.tween_property(_storm_light, "light_energy", 30.0, 0.05)
		tw.tween_property(_storm_light, "light_energy", 4.0, 0.08)
		tw.tween_property(_storm_light, "light_energy", 24.0, 0.05)
		tw.tween_property(_storm_light, "light_energy", 0.0, 0.4)
		tw.tween_callback(func() -> void: _bolt.visible = false)

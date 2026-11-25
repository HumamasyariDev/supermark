extends Node3D
## W3-4 "The Sled Joust" (W3_amendments R3.2). Corporal Crumb sits on his biscuit sled in the summit slide gate with
## the W3-4 truffle in his basket; two sled grenadiers flank him. When Mak lands on the summit all three push off
## 0.5 s later and ride the 89 m frosting slide on speed profiles that are fractions of Mak's measured clean slide.
## Mak can bump sleds (belly slide / dive contact), dodge telegraphed lance swipes by switching halves, take the two
## outer-half boost strips, and either pop the truffle out of Crumb's basket, trigger the rocket gag at 15 m to go,
## or lose: Crumb escapes at the arch and a page turn returns Mak to CP9_summit, where the joust restarts.
## No talker, no par timer. Deterministic: no random numbers.

const O := "res://scenes/objects/"
const M_GRENADIER := "res://assets/enemies/gingerbread_grenadier/gingerbread_grenadier.glb"
const P_SLED := "res://assets/props/w3/biscuit_platform/biscuit_platform.glb"
const GATE := Vector3(39.0, 28.0, -40.3)
const CP9 := Vector3(41.0, 28.1, -41.5)
const RUNOUT := Vector3(30.5, 2.9, 34.5)
const BOOSTS := [Vector2(30.0, 34.0), Vector2(54.0, 58.0)]
const DUNK := Vector2(61.0, 80.0)
const HALF := 0.75
## Mak's clean no-boost slide profile, measured by the w34clean bot (night 01, 06:25 Bangkok): about 1 s to reach
## 11.7 m/s, then a steady 11.5-12 m/s; 8.2 s over the 89.5 m centreline.
const MAK_ACC := 12.0
const MAK_VMAX := 11.7
## Sugar-rush boost: +4 m/s held for this long (a one-frame kick is eaten by the slide's speed cap).
const RUSH_S := 2.4

var c := PackedVector3Array()
var cum := PackedFloat32Array()
var length := 0.0
var riders: Array = []
var state := "armed"         # armed, countdown, run, over, won
var t := 0.0
var truffle: Node3D
var basket: Node3D
var pa := 0.0                # Mak's arc position on the slide
var plat := 0.0              # Mak's lateral offset (+ = right of travel)
var in_trough := false
var _boost_used := {}
var _rocket_checked := false
var _toast_cd := 0.0
var _log_t := 0.0
var _outer := []             # outer-side sign per boost strip
var _won := false
var _rush := 0.0
var _rush_speed := 0.0
var _rush_base := 0.0


func setup(centre: PackedVector3Array) -> void:
	c = centre
	cum.append(0.0)
	for i in c.size() - 1:
		length += c[i].distance_to(c[i + 1])
		cum.append(length)
	for b: Vector2 in BOOSTS:
		var mid := (b.x + b.y) * 0.5
		var f1 := _fwd(mid - 4.0)
		var f2 := _fwd(mid + 4.0)
		var right1 := Vector3(-f1.z, 0, f1.x)
		_outer.append(-signf(f2.dot(right1)) if absf(f2.dot(right1)) > 0.02 else 1.0)
		_boost_strip(b, float(_outer[-1]))
	# k values tuned against the measured profile (R3.14) so the R3.2 targets hold with Mak reaching the gate about
	# 1.25 s after joust_start: G2 is caught at arc 24-34, G1 at arc 62-78, a clean run trails Crumb by about 1 s at
	# 15 m to go and a run that takes boost 1 is within 3 m of him there.
	_make_rider("CorporalCrumb", 0.92, -1.0, [], true)
	_make_rider("SledGrenadier2", 0.66, 1.0, [12.0, 22.0, 40.0], false)
	_make_rider("SledGrenadier1", 0.80, -1.0, [20.0, 46.0, 66.0], false)
	var g: Node = get_node_or_null("/root/Game")
	if g and g.has_signal("truffle_collected"):
		g.connect("truffle_collected", func(id: String) -> void:
			if id == "W3-4":
				_won = true
				state = "won"
				_toast("Corporal Crumb: \"Fine! Keep it! Soggy-trottered show-off...\"", true))
	_reset()
	print("[W3 joust] ready: slide %.1f m, boost outer sides %s" % [length, str(_outer)])


# ---------------------------------------------------------------- slide geometry

func _idx(d: float) -> int:
	return clampi(cum.bsearch(clampf(d, 0.0, length - 0.01)) - 1, 0, c.size() - 2)


func _fwd(d: float) -> Vector3:
	var i := _idx(d)
	var f := c[i + 1] - c[i]
	f.y = 0.0
	return f.normalized()


func pos_at(d: float, lat: float) -> Vector3:
	var dd := clampf(d, 0.0, length - 0.01)
	var i := _idx(dd)
	var k := (dd - cum[i]) / maxf(cum[i + 1] - cum[i], 0.001)
	var f := _fwd(dd)
	return c[i].lerp(c[i + 1], k) + Vector3(-f.z, 0, f.x) * lat


func _project(p: Vector3) -> Vector3:
	# returns (arc, lateral, horizontal distance to the centreline)
	var bi := 0
	var bd := 1e9
	for i in c.size() - 1:
		var q := c[i]
		var dd := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
		if dd < bd:
			bd = dd
			bi = i
	var f := c[bi + 1] - c[bi]
	f.y = 0.0
	var fl := f.length()
	f = f / maxf(fl, 0.001)
	var rel := p - c[bi]
	rel.y = 0.0
	var along := clampf(rel.dot(f), -1.0, fl + 1.0)
	var lat := rel.dot(Vector3(-f.z, 0, f.x))
	return Vector3(cum[bi] + along, lat, sqrt(bd))


# ---------------------------------------------------------------- build

func _glb(path: String, parent: Node, pos: Vector3, rot_y: float, scl: Variant) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees.y = rot_y
	n.scale = scl if scl is Vector3 else Vector3.ONE * float(scl)
	# Visual only: riders and sleds must never block Mak.
	for co in n.find_children("*", "CollisionObject3D", true, false):
		co.queue_free()
	return n


func _make_rider(nm: String, k: float, half: float, swaps: Array, crumb: bool) -> void:
	var root := Node3D.new()
	root.name = nm
	add_child(root)
	var tilt := Node3D.new()
	tilt.name = "Tilt"
	root.add_child(tilt)
	var sled := _glb(P_SLED, tilt, Vector3(0, 0.02, 0), 0.0, Vector3(0.5, 0.4, 0.75) if crumb else Vector3(0.55, 0.42, 0.8))
	if sled:
		sled.name = "Sled"
	# Crumb: a small round corporal (the real grenadier model scaled to 1.1 m; his own Tripo P2 model is requested).
	var body := _glb(M_GRENADIER, tilt, Vector3(0, 0.22, 0.15), 180.0, 0.8 if crumb else 0.92)
	if body:
		body.name = "Rider"
		if crumb:
			body.scale = Vector3(0.95, 0.78, 0.95)
	if crumb:
		# R1 fun/visual major: Crumb must read apart from his escorts at slide speed: a darker bake, aviator goggles,
		# a long striped scarf, and the truffle raised on a candy stalk above his basket with a gold sparkle trail.
		if body:
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.32, 0.14, 0.05, 0.38)
			dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			for mi in body.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_overlay = dark
		var gog := Node3D.new()
		gog.name = "Goggles"
		tilt.add_child(gog)
		gog.position = Vector3(0, 0.98, -0.02)
		var lens_m := StandardMaterial3D.new()
		lens_m.albedo_color = Color(0.55, 0.85, 1.0)
		lens_m.metallic = 0.6
		lens_m.roughness = 0.1
		lens_m.emission_enabled = true
		lens_m.emission = Color(0.4, 0.75, 1.0)
		lens_m.emission_energy_multiplier = 0.8
		var rim_m := StandardMaterial3D.new()
		rim_m.albedo_color = Color(0.85, 0.62, 0.2)
		rim_m.metallic = 0.8
		rim_m.roughness = 0.3
		for sx in [-0.09, 0.09]:
			var rim := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.045
			tm.outer_radius = 0.075
			rim.mesh = tm
			rim.material_override = rim_m
			gog.add_child(rim)
			rim.position = Vector3(sx, 0, -0.16)
			rim.rotation_degrees = Vector3(90, 0, 0)
			var lens := MeshInstance3D.new()
			var lm := SphereMesh.new()
			lm.radius = 0.05
			lm.height = 0.06
			lens.mesh = lm
			lens.material_override = lens_m
			gog.add_child(lens)
			lens.position = Vector3(sx, 0, -0.165)
		var strap := MeshInstance3D.new()
		var sm := TorusMesh.new()
		sm.inner_radius = 0.17
		sm.outer_radius = 0.2
		strap.mesh = sm
		var strap_m := StandardMaterial3D.new()
		strap_m.albedo_color = Color(0.25, 0.15, 0.1)
		strap.material_override = strap_m
		gog.add_child(strap)
		var scarf := Node3D.new()
		scarf.name = "Scarf"
		tilt.add_child(scarf)
		scarf.position = Vector3(0, 0.82, 0.05)
		for i in 7:
			var seg := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.16, 0.05, 0.16)
			seg.mesh = bm
			var segm := StandardMaterial3D.new()
			segm.albedo_color = Color("#E8435A") if i % 2 == 0 else Color("#FFF1DC")
			seg.material_override = segm
			scarf.add_child(seg)
			seg.position = Vector3(0.04 * sin(i * 1.3), 0.05 * i * 0.3, 0.13 * i)
			seg.rotation_degrees = Vector3(-8.0 * i, 0, 6.0 * sin(i))
		var stalk := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.045
		cm.height = 1.0
		stalk.mesh = cm
		var stalk_m := StandardMaterial3D.new()
		stalk_m.albedo_color = Color("#FF5C7A")
		stalk.material_override = stalk_m
		tilt.add_child(stalk)
		stalk.position = Vector3(0, 1.05, -0.55)
		basket = Node3D.new()
		basket.name = "Basket"
		tilt.add_child(basket)
		basket.position = Vector3(0, 1.6, -0.55)
		var halo := OmniLight3D.new()
		halo.light_color = Color(1.0, 0.8, 0.35)
		halo.light_energy = 1.6
		halo.omni_range = 3.0
		basket.add_child(halo)
		ObjSvc.sparkles(basket, Color(1.0, 0.85, 0.35), 24, 0.5, 0.12, 1.0, 0.6)
	riders.append({"node": root, "tilt": tilt, "body": body, "name": nm, "k": k, "half0": half, "swaps": swaps,
		"crumb": crumb, "d": 0.0, "v": 0.0, "lat": 0.0, "half": half, "st": "park", "tt": 0.0, "spin": 0.0,
		"lean": 0.0, "swap_i": 0, "tele": -1.0, "swipe": -1.0, "cd": 0.0, "bump_cd": 0.0, "hit": false})


func _boost_strip(b: Vector2, outer: float) -> void:
	# Sprinkle boost strip: a row of bright sprinkles along the outer half of the bend.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cap := CapsuleMesh.new()
	cap.radius = 0.07
	cap.height = 0.4
	cap.radial_segments = 6
	cap.rings = 2
	mm.mesh = cap
	var pal := [Color("#FF5FA2"), Color("#FFE04A"), Color("#5FE0C8"), Color("#FFFFFF"), Color("#FF8A3D")]
	var xs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var d := b.x
	var n := 0
	while d <= b.y:
		for j in 3:
			var lat := outer * (0.35 + 0.33 * j) + sin(d * 3.1 + j) * 0.08
			var p := pos_at(d + 0.17 * j, lat) + Vector3(0, 0.05, 0)
			var bas := Basis(Vector3.UP, d * 1.7 + j).rotated(_fwd(d).cross(Vector3.UP).normalized(), PI * 0.5)
			xs.append(Transform3D(bas, p))
			cols.append(pal[n % pal.size()])
			n += 1
		d += 0.45
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "BoostStrip_%d" % int(b.x)
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.9)
	mat.emission_energy_multiplier = 0.35
	mat.roughness = 0.4
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _reset() -> void:
	_rocket_checked = false
	_boost_used.clear()
	for r in riders:
		r["st"] = "park"
		r["v"] = 0.0
		r["tt"] = 0.0
		r["spin"] = 0.0
		r["swap_i"] = 0
		r["tele"] = -1.0
		r["swipe"] = -1.0
		r["cd"] = 0.0
		r["half"] = r["half0"]
		var n := r["node"] as Node3D
		n.visible = true
		n.scale = Vector3.ONE
		(r["tilt"] as Node3D).rotation = Vector3.ZERO
		if r["body"]:
			(r["body"] as Node3D).rotation_degrees.y = 180.0
	# Parking: Crumb in the gate, the grenadiers beside him (R3.2 setup coordinates).
	_park(riders[0], GATE, 0.0)
	_park(riders[1], Vector3(37.6, 28.0, -40.9), 0.0)
	_park(riders[2], Vector3(40.4, 28.0, -40.9), 0.0)
	if not _won:
		_spawn_truffle_in_basket()


func _park(r: Dictionary, at: Vector3, d: float) -> void:
	r["d"] = d
	r["park_pos"] = at
	var n := r["node"] as Node3D
	n.global_position = at
	n.look_at(at + _fwd(0.5), Vector3.UP)
	r["lat"] = (at - c[0]).dot(Vector3(-_fwd(0.0).z, 0, _fwd(0.0).x))


func _spawn_truffle_in_basket() -> void:
	if truffle and is_instance_valid(truffle):
		truffle.queue_free()
	var ps := load(O + "Truffle.tscn") as PackedScene
	truffle = ps.instantiate() as Node3D
	truffle.set("truffle_id", "W3-4")
	truffle.set("hover_height", 0.15)
	truffle.set("bob_height", 0.05)
	truffle.name = "TruffleW3_4"
	# Untouchable while in the basket (a disabled CollisionObject leaves the physics space).
	truffle.process_mode = Node.PROCESS_MODE_DISABLED
	basket.add_child(truffle)
	truffle.position = Vector3.ZERO
	truffle.scale = Vector3.ONE * 0.8


func _free_truffle(at: Vector3, slide_on: bool) -> void:
	if truffle == null or not is_instance_valid(truffle) or truffle.get_parent() != basket:
		return
	var tr := truffle
	tr.reparent(self)
	tr.global_position = at
	tr.scale = Vector3.ONE
	tr.process_mode = Node.PROCESS_MODE_INHERIT
	ObjSvc.burst(self, at, Color(1.0, 0.85, 0.4), 22, 4.0, 0.16, -6.0, 0.7)
	ObjSvc.sfx("pop", at)
	print("[W3 joust] truffle freed at %s (slide_on=%s)" % [at, slide_on])
	if slide_on:
		# Never lost: if Mak misses it, it slides on and rests in the runout.
		var tw := create_tween()
		tw.tween_interval(2.6)
		tw.tween_callback(func() -> void:
			if is_instance_valid(tr) and not _won:
				var tw2 := create_tween()
				tw2.tween_property(tr, "global_position", RUNOUT, 1.4).set_trans(Tween.TRANS_SINE)
				print("[W3 joust] truffle slid on to the runout"))


# ---------------------------------------------------------------- runtime

## R1 fun major: character lines were small corner toasts, unreadable on video. Lines now pop as speech bubbles over
## the speaker (Crumb gold, grenadiers cream), with a short bark; DUNKED! and the rocket gag are centre stamps.
func _toast(msg: String, force: bool = false, who: Node3D = null) -> void:
	if _toast_cd > 0.0 and not force:
		return
	_toast_cd = 1.6
	print("[W3 joust] say: " + msg)
	var crumb := msg.begins_with("Corporal Crumb:")
	var gren := msg.begins_with("Grenadier:")
	if not crumb and not gren:
		ObjSvc.call_on("UI", "show_banner", ["", msg, 1.6])
		return
	var line := msg.substr(msg.find(":") + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	if who == null:
		for r in riders:
			if bool(r["crumb"]) == crumb:
				who = r["node"] as Node3D
				break
	if who == null or not who.is_inside_tree() or not who.visible:
		ObjSvc.call_on("UI", "toast", [msg])
		return
	var lb := Label3D.new()
	lb.text = line
	lb.font_size = 88 if crumb else 72
	lb.outline_size = 22
	lb.modulate = Color(1.0, 0.86, 0.35) if crumb else Color(1.0, 0.96, 0.88)
	lb.outline_modulate = Color(0.3, 0.12, 0.04) if crumb else Color(0.42, 0.18, 0.1)
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.fixed_size = false
	lb.pixel_size = 0.009
	lb.render_priority = 10
	who.add_child(lb)
	lb.position = Vector3(0, 2.4, 0)
	lb.scale = Vector3.ONE * 0.3
	var tw := lb.create_tween()
	tw.tween_property(lb, "scale", Vector3.ONE * 1.1, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lb, "scale", Vector3.ONE, 0.08)
	tw.tween_interval(1.5)
	tw.tween_property(lb, "modulate:a", 0.0, 0.3)
	tw.tween_callback(lb.queue_free)
	ObjSvc.sfx("gingerbread_halt" if gren else "crow_cackle", who.global_position)


func start() -> void:
	if state != "armed" or _won:
		return
	state = "countdown"
	t = 0.0
	_toast("Corporal Crumb: \"Finders keepers, Piglet!\"", true)
	print("[W3 joust] joust_start")


func _physics_process(delta: float) -> void:
	_toast_cd = maxf(0.0, _toast_cd - delta)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null or c.size() < 2:
		return
	var p := pl.global_position
	var pr := _project(p)
	pa = pr.x
	plat = pr.y
	var cy := pos_at(pa, 0.0).y
	in_trough = pr.z < 2.4 and p.y > cy - 1.2 and p.y < cy + 3.0 and pa > -1.0 and pa < length + 1.0
	match state:
		"armed":
			if p.y > 27.3 and Vector2(p.x - GATE.x, p.z - GATE.z).length() < 7.5 and bool(pl.get("grounded")):
				start()
		"countdown":
			t += delta
			if t >= 0.5:
				state = "run"
				t = 0.0
				for r in riders:
					r["st"] = "ride"
					r["tt"] = 0.0
		"run", "won":
			t += delta
			_boosts(pl)
			for r in riders:
				_ride(r, delta, pl, p)
			if state == "run":
				_fly_out_check(p)
			_log_t += delta
			if _log_t >= 0.5:
				_log_t = 0.0
				print("[W3 joust] t=%.1f mak=%.1f lat=%.2f crumb=%.1f g2=%.1f g1=%.1f" % [t, pa, plat, float(riders[0]["d"]), float(riders[1]["d"]), float(riders[2]["d"])])


func _boosts(pl: Node3D) -> void:
	if not in_trough:
		_rush = 0.0
		return
	if _rush > 0.0:
		_rush -= get_physics_process_delta_time()
		if _rush <= 0.0:
			if not bool(pl.get("use_slide_vel")):
				pl.set("forward_speed", minf(float(pl.get("forward_speed")), _rush_base))
			return
		var f := _fwd(pa)
		if bool(pl.get("use_slide_vel")):
			var sv: Vector3 = pl.get("slide_vel")
			var along := sv.dot(f)
			if along < _rush_speed:
				pl.set("slide_vel", sv + f * (_rush_speed - along))
		else:
			var fs := float(pl.get("forward_speed"))
			if fs < _rush_speed:
				pl.set("forward_speed", _rush_speed)
	for i in BOOSTS.size():
		var b: Vector2 = BOOSTS[i]
		if _boost_used.has(i) or pa < b.x or pa > b.y:
			continue
		if plat * float(_outer[i]) < 0.1:
			continue
		_boost_used[i] = true
		_rush = RUSH_S
		var f0 := _fwd(pa)
		if bool(pl.get("use_slide_vel")):
			var sv: Vector3 = pl.get("slide_vel")
			_rush_speed = Vector3(sv.x, 0, sv.z).dot(f0) + 4.0
		else:
			_rush_base = float(pl.get("forward_speed"))
			_rush_speed = _rush_base + 4.0
		ObjSvc.burst(self, pl.global_position + Vector3(0, 0.2, 0), Color(1.0, 0.6, 0.85), 26, 5.0, 0.14, -4.0, 0.6)
		ObjSvc.sfx("gust_whoosh", pl.global_position)
		print("[W3 joust] slide_boost_%d at arc %.1f" % [i + 1, pa])


func _ride(r: Dictionary, delta: float, pl: Node3D, p: Vector3) -> void:
	var st := String(r["st"])
	if st == "park" or st == "out" or st == "air" or st == "gone":
		return
	r["tt"] = float(r["tt"]) + delta
	r["bump_cd"] = maxf(0.0, float(r["bump_cd"]) - delta)
	r["cd"] = maxf(0.0, float(r["cd"]) - delta)
	var tt := float(r["tt"])
	var v := float(r["k"]) * minf(MAK_ACC * tt, MAK_VMAX)
	if st == "rocket":
		v = 24.0
	if float(r["spin"]) > 0.0:
		r["spin"] = float(r["spin"]) - delta
		v *= 0.3
		(r["tilt"] as Node3D).rotation.y += delta * 14.0
		if float(r["spin"]) <= 0.0:
			(r["tilt"] as Node3D).rotation.y = 0.0
	r["v"] = v
	var d := float(r["d"]) + v * delta
	r["d"] = d
	# Lane swaps with a 0.4 s lean telegraph.
	var swaps: Array = r["swaps"]
	var si := int(r["swap_i"])
	if si < swaps.size() and d >= float(swaps[si]) - v * 0.4:
		r["lean"] = 0.4
		r["swap_i"] = si + 1
		r["swap_to"] = -float(r["half"])
	if float(r["lean"]) > 0.0:
		r["lean"] = float(r["lean"]) - delta
		(r["tilt"] as Node3D).rotation.z = float(r["swap_to"]) * -0.25
		if float(r["lean"]) <= 0.0:
			r["half"] = r["swap_to"]
			(r["tilt"] as Node3D).rotation.z = 0.0
	var target := float(r["half"]) * HALF if not bool(r["crumb"]) else -HALF * 0.9
	r["lat"] = move_toward(float(r["lat"]), target, 2.5 * delta)
	var n := r["node"] as Node3D
	if d < 1.5 and r.has("park_pos"):
		# Push off from the parked spot into the trough.
		var a := clampf(d / 1.5, 0.0, 1.0)
		n.global_position = (r["park_pos"] as Vector3).lerp(pos_at(d, float(r["lat"])), a) + Vector3(0, 0.12, 0)
	else:
		n.global_position = pos_at(d, float(r["lat"])) + Vector3(0, 0.12, 0)
	var f := _fwd(d)
	var nxt := pos_at(d + 1.0, float(r["lat"]))
	if nxt.distance_to(n.global_position) > 0.2:
		n.look_at(nxt + Vector3(0, 0.12, 0), Vector3.UP)
	if bool(r["crumb"]):
		_crumb_events(r, d)
	else:
		_swipe(r, delta, pl, p)
	if d >= length - 0.2:
		if bool(r["crumb"]):
			_crumb_arrives(r)
		else:
			r["st"] = "gone"
			var tw := create_tween()
			tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.5)
			tw.tween_callback(func() -> void: n.visible = false)
		return
	if state != "run" and state != "won":
		return
	# Sled bump: a belly slide / dive contact from behind or the side.
	if float(r["bump_cd"]) <= 0.0 and in_trough and st != "rocket":
		var rp := n.global_position + Vector3(0, 0.35, 0)
		var dist := (p + Vector3(0, 0.3, 0)).distance_to(rp)
		var sname := String(pl.call("get_state_name")) if pl.has_method("get_state_name") else ""
		var sliding := sname in ["belly_slide", "dive", "slope_slide", "slide_getup"] or bool(pl.call("is_attacking"))
		if dist < 1.25 and pa >= d - 1.6 and pa <= d + 0.6 and sliding:
			r["bump_cd"] = 0.8
			_bump(r, d, f)


func _bump(r: Dictionary, d: float, f: Vector3) -> void:
	var n := r["node"] as Node3D
	r["tele"] = -1.0
	r["swipe"] = -1.0
	ObjSvc.burst(self, n.global_position + Vector3(0, 0.6, 0), Color(1.0, 0.9, 0.6), 20, 4.5, 0.15, -8.0, 0.5)
	ObjSvc.sfx("bonk", n.global_position)
	print("[W3 joust] sled_bump %s at arc %.1f" % [r["name"], d])
	if bool(r["crumb"]):
		var full := truffle != null and is_instance_valid(truffle) and truffle.get_parent() == basket
		_toast("Corporal Crumb: \"Oi! Hands off my basket!\"" if full else "Corporal Crumb: \"Hey! I've got nothing left!\"", full)
		var at := pos_at(minf(d + 4.0, length - 1.0), 0.0) + Vector3(0, 0.45, 0)
		_free_truffle(at, true)
		r["spin"] = 1.5
		return
	var outer := float(r["half"])
	var in_boost := false
	for b: Vector2 in BOOSTS:
		if d >= b.x - 1.0 and d <= b.y + 1.0:
			in_boost = true
	if d >= DUNK.x and d <= DUNK.y:
		_throw(r, d, outer, true)
	elif in_boost:
		_throw(r, d, outer, false)
	else:
		r["spin"] = 1.5
		_toast("Grenadier: \"Whoa-oa-oa!\"", false, r["node"])


func _throw(r: Dictionary, d: float, side: float, dunk: bool) -> void:
	r["st"] = "air"
	var n := r["node"] as Node3D
	var from := n.global_position
	var side_v := Vector3(-_fwd(d).z, 0, _fwd(d).x) * (1.0 if side >= 0.0 else -1.0)
	var to := from + side_v * 5.5 + _fwd(d) * 3.0
	if dunk:
		to.y = 0.2
		ObjSvc.call_on("UI", "show_banner", ["DUNKED!", "", 1.4])
	else:
		var lv := get_parent()
		to.y = float(lv.call("h_at", to.x, to.z)) if lv and lv.has_method("h_at") else from.y - 3.0
		_toast("Grenadier: \"I'm flyiiiing!\"", true, r["node"])
	print("[W3 joust] %s %s at arc %.1f" % [r["name"], "dunked" if dunk else "thrown out", d])
	var apex := maxf(from.y, to.y) + 3.0
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		var q := from.lerp(to, k)
		q.y = lerpf(lerpf(from.y, apex, k), lerpf(apex, to.y, k), k)
		n.global_position = q
		(r["tilt"] as Node3D).rotation.x = k * TAU * 1.5, 0.0, 1.0, 1.1)
	tw.tween_callback(func() -> void:
		ObjSvc.burst(self, to + Vector3(0, 0.3, 0), Color(0.45, 0.25, 0.12) if dunk else Color(0.85, 0.6, 0.35), 30, 5.0, 0.2, -9.0, 0.8)
		ObjSvc.sfx("hot_splash" if dunk else "gingerbread_crumble", to)
		r["st"] = "out")
	tw.tween_property(n, "scale", Vector3(1.2, 0.05, 1.2), 0.5)
	tw.tween_callback(func() -> void: n.visible = false)


func _swipe(r: Dictionary, delta: float, pl: Node3D, p: Vector3) -> void:
	if state != "run" and state != "won":
		return
	var d := float(r["d"])
	var rel := pa - d
	var same := absf(plat - float(r["lat"])) < 0.8
	var body := r["body"] as Node3D
	if float(r["tele"]) > 0.0:
		r["tele"] = float(r["tele"]) - delta
		if body:
			body.rotation_degrees.y = 180.0 + 150.0 * minf(1.0, (0.6 - float(r["tele"])) * 5.0)
		if float(r["tele"]) <= 0.0:
			r["swipe"] = 0.4
			r["hit"] = false
	elif float(r["swipe"]) > 0.0:
		r["swipe"] = float(r["swipe"]) - delta
		if body:
			body.rotation_degrees.y = 180.0 + 150.0 - (0.4 - float(r["swipe"])) * 600.0
		if not bool(r["hit"]) and rel > -3.3 and rel < 0.3 and same and in_trough:
			r["hit"] = true
			var g: Node = get_node_or_null("/root/Game")
			if g and g.has_method("damage") and float(pl.get("invulnerable")) <= 0.0:
				g.call("damage", 1)
				pl.set("invulnerable", 1.2)
				pl.set("hurt_blink", 1.2)
			if bool(pl.get("use_slide_vel")):
				pl.set("slide_vel", (pl.get("slide_vel") as Vector3) * 0.7)
			pl.set("forward_speed", float(pl.get("forward_speed")) * 0.7)
			ObjSvc.burst(self, p + Vector3(0, 0.6, 0), Color(1, 0.4, 0.4), 14, 3.0, 0.12, -8.0, 0.4)
			ObjSvc.sfx("hurt", p)
			print("[W3 joust] lance swipe hit Mak (%s) at arc %.1f" % [r["name"], pa])
		if float(r["swipe"]) <= 0.0:
			r["cd"] = 2.0
			if body:
				body.rotation_degrees.y = 180.0
			if not bool(r["hit"]):
				print("[W3 joust] lance swipe dodged (%s) at arc %.1f" % [r["name"], pa])
	elif d > 3.0 and float(r["cd"]) <= 0.0 and float(r["spin"]) <= 0.0 and rel > -3.0 and rel < -0.3 and same and in_trough:
		r["tele"] = 0.6
		_toast("Grenadier: \"Halt, swine!\"", false, r["node"])
		print("[W3 joust] lance telegraph (%s) at arc %.1f" % [r["name"], pa])


func _crumb_events(r: Dictionary, d: float) -> void:
	if _rocket_checked or d < length - 15.0 or truffle == null or not is_instance_valid(truffle) or truffle.get_parent() != basket:
		return
	_rocket_checked = true
	if in_trough and pa >= d - 3.0:
		r["st"] = "rocket"
		ObjSvc.call_on("UI", "show_banner", ["WHOOSH!", "Corporal Crumb lights a rocket candle!", 1.8])
		ObjSvc.burst(self, (r["node"] as Node3D).global_position + Vector3(0, 0.5, 0), Color(1.0, 0.6, 0.2), 30, 6.0, 0.15, 2.0, 0.6)
		ObjSvc.sfx("gust_whoosh", (r["node"] as Node3D).global_position)
		print("[W3 joust] crumb_rocket at arc %.1f (mak %.1f)" % [d, pa])


func _crumb_arrives(r: Dictionary) -> void:
	var n := r["node"] as Node3D
	var st := String(r["st"])
	if st == "rocket":
		# Overshoots the arch and crashes into the marshmallow pile; the truffle drops in the runout.
		r["st"] = "air"
		var from := n.global_position
		var to := c[c.size() - 1] + (c[c.size() - 1] - c[c.size() - 4]).normalized() * 4.5
		to.y = from.y - 0.4
		var tw := create_tween()
		tw.tween_method(func(k: float) -> void:
			var q := from.lerp(to, k)
			q.y += sin(k * PI) * 3.5
			n.global_position = q
			(r["tilt"] as Node3D).rotation.x = -k * TAU, 0.0, 1.0, 0.7)
		tw.tween_callback(func() -> void:
			ObjSvc.burst(self, to + Vector3(0, 0.5, 0), Color(1.0, 0.95, 0.95), 40, 6.0, 0.25, -9.0, 0.9)
			ObjSvc.sfx("gingerbread_crumble", to)
			_toast("Corporal Crumb: \"Mmmf! Marshmallows!\"", true)
			_free_truffle(RUNOUT, false)
			r["st"] = "out")
		return
	if truffle and is_instance_valid(truffle) and truffle.get_parent() == basket:
		_escape(r, true)
	else:
		r["st"] = "out"
		_toast("Corporal Crumb: \"Bah! Biscuits!\"")


func _escape(r: Dictionary, respawn: bool) -> void:
	if state == "over":
		return
	state = "over"
	# R1 fun minor: only page-turn Mak back to the summit when he is still racing (on the slide or near the runout);
	# a player exploring elsewhere just sees the joust reset quietly.
	var plr := get_tree().get_first_node_in_group("player") as Node3D
	if respawn and plr and not in_trough and plr.global_position.distance_to(RUNOUT) > 25.0:
		respawn = false
	print("[W3 joust] crumb_escape (respawn=%s)" % respawn)
	_toast("Corporal Crumb: \"Ta-ta, trotters!\"", true)
	var n := r["node"] as Node3D
	r["st"] = "gone"
	var tw := create_tween()
	tw.tween_property(n, "global_position", n.global_position + Vector3(4.0, 0.0, 6.0), 0.8)
	tw.tween_callback(func() -> void: n.visible = false)
	if not respawn:
		var tw2 := create_tween()
		tw2.tween_interval(1.5)
		tw2.tween_callback(func() -> void:
			_reset()
			state = "armed")
		return
	var tw3 := create_tween()
	tw3.tween_interval(0.6)
	tw3.tween_callback(func() -> void:
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		var change := func() -> void:
			_reset()
			if pl and pl.has_method("respawn"):
				pl.call("respawn", Transform3D(Basis(Vector3.UP, _summit_yaw()), CP9))
			state = "rearm"
			var tw4 := create_tween()
			tw4.tween_interval(1.0)
			tw4.tween_callback(func() -> void:
				state = "armed"
				start())
		var pt: Variant = load("res://scripts/fx/page_turn.gd")
		if pt and DisplayServer.get_name() != "headless":
			pt.run(get_tree(), change, 0.8)
		else:
			change.call())


## Faces Mak down the slide's first segment at the summit respawn (R1 visual: the camera looked at his face).
func _summit_yaw() -> float:
	if c.size() > 3:
		var sd := c[3] - c[0]
		return atan2(-sd.x, -sd.z)
	return deg_to_rad(150.0)


func _fly_out_check(p: Vector3) -> void:
	# Mak flew out of the trough (a boosted, badly steered bend): Crumb escapes, no damage.
	if pa < 2.0 or pa > length - 1.0:
		return
	var cy := pos_at(pa, 0.0).y
	if not in_trough and p.y < cy - 1.5 and riders[0]["st"] != "gone":
		print("[W3 joust] Mak left the slide at arc %.1f" % pa)
		_escape(riders[0], false)


## Bot helper: the lateral offset that takes the outer-half boost strips.
func bot_lat(d: float) -> float:
	for i in BOOSTS.size():
		var b: Vector2 = BOOSTS[i]
		if d >= b.x - 8.0 and d <= b.y:
			return float(_outer[i]) * 0.6
	return 0.0

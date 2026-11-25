extends Node3D
## W1 fix round 2: the living layer of Huff & Puff Hollow, run from one processed node so the static builders stay cheap.
## - Real sheep bleat exactly like the disguised wolves (same "Baa~" popup, rate and sound) and react to Mak: a scatter
##   hop when he runs past, a roll-over in a puff or near a Ham Slam (fun r1: only the wolves made a sound).
## - Disguised wolves get a visual tell instead: a grey tail that flicks out of the fleece (fun r1 fix (b)).
## - R3.4 "Huff back": landing on an intact bellows plate fires one puff down its lane (wolves tumble or unmask, crows
##   flap off, sheep roll over), then a cooldown.
## - R2.8 escalation: WW3 hides inside a wiggling, sneezing haystack until sniffed, slammed, punched or puffed out.
## - R3.6 Hay Hoist (interim procedural derrick) with its boom swing and straw puff over the pen.
## - R3.8 riddle signs grow their literal line after a 10 s dwell within 4 m.
## - W1-2: CB6 makes one telegraphed dive at the sail rider; CB3 holds its perch meanwhile.
## - Floating Label3D barks hide under --hide-hud and while a story camera films; acorns next to the intro face camera hide.
## - Small bees (the generated Bumble Bruiser at bee scale) circle the skep beehives.

const K := preload("res://scripts/worlds/w1_kit.gd")
const D := preload("res://scripts/worlds/w1_dress.gd")
const GUST := preload("res://scripts/worlds/w1_gust_zone.gd")
const BEE_GLB := "res://assets/enemies/bumble_bruiser/bumble_bruiser_v2.glb"

var level: Node3D
var sheep: Array[Dictionary] = []
var plates: Array[Dictionary] = []
var tails: Array[Dictionary] = []
var signs: Array[Dictionary] = []
var bees: Array[Dictionary] = []
var hay: Dictionary = {}
var hoist: Dictionary = {}
var _first_puff := true
var _pl: Node3D
var _pl_connected := false
var _t := 0.0
var _label_t := 0.0
var _labels_hidden := false
var _hide_hud := false
var _ride_t := 0.0
var _ride_out := 0.0
var _ride_done := false
var _cb3_radius := -1.0
var _rng := RandomNumberGenerator.new()
var _hidden_acorns: Array[Node3D] = []


func setup(lvl: Node3D) -> void:
	level = lvl
	_rng.seed = 2611
	var dev := get_node_or_null("/root/Dev")
	_hide_hud = dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "hide-hud"))


func _player() -> Node3D:
	if _pl == null or not is_instance_valid(_pl):
		_pl = get_tree().get_first_node_in_group("player") as Node3D
		_pl_connected = false
	if _pl and not _pl_connected and _pl.has_signal("ground_pounded"):
		_pl.connect("ground_pounded", _on_ground_pounded)
		_pl_connected = true
	return _pl


func _ui() -> Node:
	return get_node_or_null("/root/UI")


func _bark(node: Node3D, text: String, seconds: float, speaker: String) -> void:
	var ui := _ui()
	if ui and ui.has_method("bark") and node != null:
		ui.call("bark", node, text, seconds, {"speaker": speaker})
	elif ui and ui.has_method("toast"):
		ui.call("toast", "%s: \"%s\"" % [speaker, text])


func _process(delta: float) -> void:
	_t += delta
	var pl := _player()
	var pp := pl.global_position if pl else Vector3(0, -1000, 0)
	var speed := 0.0
	if pl:
		var v: Variant = pl.get("velocity")
		if v is Vector3:
			speed = Vector2((v as Vector3).x, (v as Vector3).z).length()
	_sheep_step(delta, pp, speed)
	_tail_step(delta)
	_plate_step(delta)
	_hay_step(delta, pp)
	_hoist_step(delta)
	_sign_step(delta, pp)
	_ride_step(delta, pp)
	_bee_step(delta)
	_label_t -= delta
	if _label_t <= 0.0:
		_label_t = 0.4
		_label_step()


# ------------------------------------------------------------------ sheep

## holder: the grazing node (tweened by the builder); react: a child between it and the model, used for hops and rolls.
func add_sheep(holder: Node3D, react: Node3D) -> void:
	sheep.append({"holder": holder, "react": react, "baa": _rng.randf_range(0.5, 2.5), "busy": 0.0})


func _sheep_step(delta: float, pp: Vector3, speed: float) -> void:
	for s in sheep:
		var react: Node3D = s["react"]
		if not is_instance_valid(react):
			continue
		var at := react.global_position
		var far := at.distance_squared_to(pp) > 45.0 * 45.0
		s["busy"] = maxf(float(s["busy"]) - delta, 0.0)
		# Same cadence, popup and sound as WoollyWolf._graze (2.5-4.5 s, white "Baa~", wolf_cub_baa).
		s["baa"] = float(s["baa"]) - delta
		if float(s["baa"]) <= 0.0:
			s["baa"] = _rng.randf_range(2.5, 4.5)
			if not far:
				_baa(at, "Baa~")
		if float(s["busy"]) <= 0.0 and speed > 3.5:
			var d := Vector2(at.x - pp.x, at.z - pp.z)
			if d.length() < 2.2 and absf(at.y - pp.y) < 1.5:
				_scatter(s, Vector3(d.x, 0, d.y).normalized() if d.length() > 0.05 else Vector3.FORWARD)


func _baa(at: Vector3, text: String) -> void:
	EnemyKit.popup(level, at + Vector3(0, 1.7, 0), text, Color(1, 1, 1), 64, 1.1)
	EnemyKit.sfx(level, "wolf_cub_baa", at)


func _scatter(s: Dictionary, away: Vector3) -> void:
	var react: Node3D = s["react"]
	var holder: Node3D = s["holder"]
	s["busy"] = 4.0
	var local := holder.global_basis.inverse() * (away * 1.6)
	local.y = 0.0
	var tw := react.create_tween()
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(react):
			react.position = local * k + Vector3(0, 0.45 * sin(k * PI), 0), 0.0, 1.0, 0.32)
	tw.tween_interval(1.8)
	tw.tween_property(react, "position", Vector3.ZERO, 2.2).set_trans(Tween.TRANS_SINE)
	_baa(react.global_position, "Baa!")


func _roll(s: Dictionary) -> void:
	var react: Node3D = s["react"]
	if not is_instance_valid(react) or float(s["busy"]) > 2.0:
		return
	s["busy"] = 3.0
	var tw := react.create_tween()
	tw.tween_property(react, "position:y", 0.35, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(react, "rotation:z", TAU, 0.8).as_relative()
	tw.tween_property(react, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_baa(react.global_position, "Baaa?!")


func _on_ground_pounded(at: Vector3) -> void:
	for s in sheep:
		var react: Node3D = s["react"]
		if is_instance_valid(react) and react.global_position.distance_to(at) < 4.0:
			_roll(s)


# ------------------------------------------------------------------ disguised wolf tell

## A grey tail pokes out of the fleece and flicks every few seconds while the wolf is disguised (removed on reveal).
func add_tail(w: Node3D) -> void:
	# Finish pass (enemy visuals blocker): the primitive "W1TailTell" capsule floated detached and dark beside the
	# disguised wolf's GLB, which already shows its own tail. The tell is the GLB tail; no primitive is added.
	if true or not is_instance_valid(w) or not bool(w.get("disguised")):
		return
	var pivot := Node3D.new()
	pivot.name = "W1TailTell"
	w.add_child(pivot)
	pivot.position = Vector3(0, 0.5, 0.3)
	var grey := K.mat(Color("6f6a73"), 0.85)
	var tip := K.mat(Color("3f3b44"), 0.85)
	var tail := Node3D.new()
	pivot.add_child(tail)
	tail.rotation_degrees.x = 55.0
	K.capsule(tail, 0.07, 0.42, grey, Vector3(0, 0.0, 0.2), Vector3(90, 0, 0))
	K.sphere(tail, 0.085, tip, Vector3(0, 0.0, 0.42), Vector3(1, 1, 1.3))
	tails.append({"wolf": w, "pivot": pivot, "tail": tail, "next": _rng.randf_range(1.0, 3.0), "flick": 0.0})


func _tail_step(delta: float) -> void:
	for i in range(tails.size() - 1, -1, -1):
		var d: Dictionary = tails[i]
		var w: Node3D = d["wolf"]
		var pivot: Node3D = d["pivot"]
		if not is_instance_valid(w) or not is_instance_valid(pivot):
			tails.remove_at(i)
			continue
		if not bool(w.get("disguised")):
			pivot.queue_free()
			tails.remove_at(i)
			continue
		d["next"] = float(d["next"]) - delta
		if float(d["next"]) <= 0.0:
			d["next"] = _rng.randf_range(2.0, 4.0)
			d["flick"] = 0.7
		var tail: Node3D = d["tail"]
		var f := float(d["flick"])
		if f > 0.0:
			d["flick"] = f - delta
			tail.rotation_degrees.y = sin((0.7 - f) * 28.0) * 38.0
			tail.rotation_degrees.x = 35.0
		else:
			tail.rotation_degrees.y = sin(_t * 2.1) * 6.0
			tail.rotation_degrees.x = lerpf(tail.rotation_degrees.x, 55.0, 1.0 - exp(-4.0 * delta))


# ------------------------------------------------------------------ R3.4 huff back

func add_plate(lid: String, bel: Node3D, zone: Node3D) -> void:
	if bel == null or zone == null:
		return
	var a := Area3D.new()
	a.name = "PuffPlate"
	a.collision_layer = 128
	a.collision_mask = 2
	a.monitorable = false
	bel.add_child(a)
	K.shape_box(a, Vector3(2.0, 0.6, 2.4), Vector3(0, 2.65, 0.1))
	var d := {"lid": lid, "bel": bel, "zone": zone, "cool": 0.0}
	plates.append(d)
	a.body_entered.connect(func(b: Node) -> void: _on_plate(d, b))


func _plate_step(delta: float) -> void:
	for d in plates:
		d["cool"] = maxf(float(d["cool"]) - delta, 0.0)


func _on_plate(d: Dictionary, b: Node) -> void:
	if not b.is_in_group("player") or float(d["cool"]) > 0.0:
		return
	var bel: Node3D = d["bel"]
	if not is_instance_valid(bel) or bool(bel.get("is_broken")):
		return
	if b.has_method("get_state_name") and String(b.call("get_state_name")).contains("slam"):
		return
	var v: Variant = b.get("velocity")
	if v is Vector3 and (v as Vector3).y > 1.0:
		return
	d["cool"] = 3.0
	puff(d)


func puff(d: Dictionary) -> void:
	var zone: Node3D = d["zone"]
	var lid := String(d["lid"])
	if not is_instance_valid(zone):
		return
	var zsize: Vector3 = zone.get("size")
	var xf := zone.global_transform
	var blast := GUST.new()
	blast.name = "Puff_" + lid
	blast.add_child(Node3D.new())
	blast.set("size", zsize)
	blast.set("direction", Vector3(0, 0, -1))
	blast.set("strength", 12.0)
	blast.set("mode", WindZone.Mode.STEADY)
	blast.set("end_falloff", 0.35)
	blast.set("show_particles", false)
	blast.set("use_gust_swirl", false)
	if zone.get("exclude_aabbs") != null:
		blast.set("exclude_aabbs", zone.get("exclude_aabbs"))
	level.add_child(blast)
	blast.global_transform = xf
	get_tree().create_timer(1.0).timeout.connect(blast.queue_free)
	var fwd := -xf.basis.z.normalized()
	var mouth := xf.origin - fwd * zsize.z * 0.5
	var swirl := D.fx(level, "GustSwirl", mouth)
	if swirl:
		swirl.look_at(mouth + fwd * 10.0, Vector3.UP)
		swirl.set("length", zsize.z)
		swirl.set("radius", 2.2)
		if swirl.has_method("set_active"):
			swirl.call("set_active", true)
		get_tree().create_timer(1.2).timeout.connect(swirl.queue_free)
	for k in 4:
		get_tree().create_timer(0.12 * k).timeout.connect(func() -> void:
			ObjSvc.burst(level, mouth + fwd * (1.5 + k * 3.0), Color(0.97, 0.95, 0.88), 16, 7.0, 0.22, 0.0, 0.7))
	ObjSvc.sfx("bellows_pump_2", mouth)
	EnemyKit.sfx(level, "wolf_huff", mouth, 1.25)
	var inside := func(p: Vector3) -> bool:
		var l := xf.affine_inverse() * p
		return absf(l.x) <= zsize.x * 0.5 + 0.6 and absf(l.y) <= zsize.y * 0.5 + 1.2 and absf(l.z) <= zsize.z * 0.5 + 0.5
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not level.is_ancestor_of(e):
			continue
		var en := e as Node3D
		if not bool(inside.call(en.global_position)):
			continue
		if "disguised" in en:
			if bool(en.get("disguised")) and en.has_method("_rip_costume"):
				ObjSvc.burst(level, en.global_position + Vector3(0, 1.0, 0), Color(0.96, 0.92, 0.8), 30, 5.0, 0.24, -4.0, 1.0)
				en.call("_rip_costume")
			elif "state" in en and String(en.get("state")) != "defeated":
				_tumble(en, fwd)
		elif "dive_speed" in en and String(en.get("state")) == "perch":
			var h0: Vector3 = en.get("home")
			en.set("home", h0 + Vector3(0, 4.0, 0))
			if en.has_method("say"):
				en.call("say", "CAW?!", Color(0.85, 0.9, 1.0), 56)
			get_tree().create_timer(4.0).timeout.connect(func() -> void:
				if is_instance_valid(en):
					en.set("home", h0))
	for s in sheep:
		var react: Node3D = s["react"]
		if is_instance_valid(react) and bool(inside.call(react.global_position)):
			_roll(s)
	if not hay.is_empty() and not bool(hay["burst"]) and bool(inside.call(hay["pos"])):
		_hay_burst()
	if _first_puff:
		_first_puff = false
		var pip := level.get("pip") as Node3D
		if pip:
			_bark(pip, "Huff AND puff! You're a natural!", 2.6, "Pip")
	if lid == "bellows_B2":
		var hz := level.get_node_or_null("Hazel") as Node3D
		if hz:
			_bark(hz, "Oi! Wrong way!", 2.0, "Hazel")


## A revealed wolf tumbles 4 m down the lane, then sits dizzy for about 2 s.
func _tumble(en: Node3D, fwd: Vector3) -> void:
	var from := en.global_position
	var to := from + Vector3(fwd.x, 0, fwd.z).normalized() * 4.0
	to.y = W1Terrain.height(to.x, to.z) + 0.05
	en.set_physics_process(false)
	if en.has_method("say"):
		en.call("say", "Whoa-oa-oa!", Color(1, 0.9, 0.6), 56)
	var spin := en.rotation.y
	var tw := en.create_tween()
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(en):
			en.global_position = from.lerp(to, k) + Vector3(0, 1.1 * sin(k * PI), 0)
			en.rotation.y = spin + k * TAU * 1.5, 0.0, 1.0, 0.65)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(en):
			return
		en.set_physics_process(true)
		if en.has_method("set_state"):
			en.call("set_state", "dizzy"))


# ------------------------------------------------------------------ R2.8 WW3 in the haystack

## spawn_wolf(at: Vector3) -> Node3D builds and wires the real WoollyWolf (the level owns the siege count).
func add_hay_hide(pos: Vector3, spawn_wolf: Callable) -> void:
	var body := K.body(level, "WW3_Haystack", pos)
	K.shape_cyl(body, 1.15, 2.0, Vector3(0, 1.0, 0))
	var vis := Node3D.new()
	vis.name = "Wiggle"
	body.add_child(vis)
	var straw := K.tex_mat("straw_thatch", Color(1.1, 1.2, 1.7), 0.5)
	K.sphere(vis, 1.25, straw, Vector3(0, 0.95, 0), Vector3(1.0, 1.05, 1.0))
	K.cone(vis, 1.0, 1.15, straw, Vector3(0, 2.25, 0), Vector3.ZERO, 14)
	K.torus(vis, 1.08, 1.2, K.mat(Color("8a6a3a"), 0.9), Vector3(0, 1.45, 0))
	# A grey wolf tail sticking out of the straw: the visual tell for this one.
	var tail := K.capsule(vis, 0.07, 0.45, K.mat(Color("6f6a73"), 0.85), Vector3(0.95, 0.45, 0.55), Vector3(70, 0, -40))
	tail.name = "TailTell"
	var sensor := SlamSensor.create(body, 1.6, 2.6, Vector3.ZERO)
	sensor.slammed.connect(func(_by: Node) -> void: _hay_burst())
	sensor.struck.connect(func(_k: String, _p: Vector3) -> void: _hay_burst())
	var sn := level.call("obj", "SniffTarget", pos + Vector3(0, 0.8, 0), {"reveal_radius": 4.0, "scent_strength": 0.8}) as Node3D
	if sn:
		sn.name = "WW3_Scent"
		sn.connect("sniffed", func(_by: Node) -> void: _hay_burst())
	hay = {"body": body, "vis": vis, "pos": pos, "spawn": spawn_wolf, "burst": false, "wiggle": 1.5, "sneeze": 2.0, "scent": sn}


func hay_hidden() -> bool:
	return not hay.is_empty() and not bool(hay["burst"])


func _hay_step(delta: float, pp: Vector3) -> void:
	if hay.is_empty() or bool(hay["burst"]):
		return
	var vis: Node3D = hay["vis"]
	var p: Vector3 = hay["pos"]
	hay["wiggle"] = float(hay["wiggle"]) - delta
	if float(hay["wiggle"]) <= 0.0:
		hay["wiggle"] = 4.0
		var tw := vis.create_tween()
		for k in 4:
			tw.tween_property(vis, "rotation_degrees:z", 6.0 if k % 2 == 0 else -6.0, 0.09)
		tw.tween_property(vis, "rotation_degrees:z", 0.0, 0.1)
	hay["sneeze"] = float(hay["sneeze"]) - delta
	if float(hay["sneeze"]) <= 0.0 and p.distance_to(pp) < 6.0:
		hay["sneeze"] = 3.0
		ObjSvc.burst(level, p + Vector3(0, 2.4, 0), Color(1.0, 0.86, 0.45), 18, 3.5, 0.16, -6.0, 0.7)
		EnemyKit.popup(level, p + Vector3(0, 3.0, 0), "achoo!", Color(1, 1, 1), 52, 0.9)
		EnemyKit.sfx(level, "giant_sneeze", p, 2.2, -6.0)


func _hay_burst() -> void:
	if hay.is_empty() or bool(hay["burst"]):
		return
	hay["burst"] = true
	var p: Vector3 = hay["pos"]
	var body: Node3D = hay["body"]
	var vis: Node3D = hay["vis"]
	for cs in body.get_children():
		if cs is CollisionShape3D:
			(cs as CollisionShape3D).set_deferred("disabled", true)
	var sn: Node = hay["scent"]
	if is_instance_valid(sn):
		sn.queue_free()
	ObjSvc.burst(level, p + Vector3(0, 1.4, 0), Color(1.0, 0.86, 0.45), 60, 8.0, 0.3, -9.0, 1.2)
	EnemyKit.popup(level, p + Vector3(0, 3.0, 0), "A-CHOO!", Color(1, 1, 1), 80, 1.3)
	EnemyKit.sfx(level, "giant_sneeze", p, 1.6)
	var tw := vis.create_tween()
	tw.tween_property(vis, "scale", Vector3(1.5, 0.25, 1.5), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var pl := _player()
	var dir := Vector3(1, 0, 0)
	if pl:
		dir = Vector3(pl.global_position.x - p.x, 0, pl.global_position.z - p.z)
		dir = dir.normalized() if dir.length() > 0.1 else Vector3(1, 0, 0)
	var at := p + dir * 1.7
	at.y = W1Terrain.height(at.x, at.z) + 0.05
	var cb: Callable = hay["spawn"]
	if cb.is_valid():
		cb.call(at)


# ------------------------------------------------------------------ R3.6 Hay Hoist (interim procedural derrick)

func build_hoist(at: Vector3, pen_center: Vector3, hay_yard: Node) -> void:
	var root := Node3D.new()
	root.name = "HayHoist"
	level.add_child(root)
	root.global_position = at
	var timber := K.tex_mat("bark", Color(0.86, 0.66, 0.46), 0.6)
	var dark := K.mat(Color("5c3a21"), 0.85)
	var rope := K.mat(Color("d8c08a"), 0.85)
	var b := K.body(root, "HoistLegs")
	K.shape_box(b, Vector3(2.6, 3.0, 2.6), Vector3(0, 1.5, 0))
	# Four splayed legs from a 2.4 m base to the mast collar at y 7.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var foot := Vector3(sx * 1.2, 0, sz * 1.2)
			var top := Vector3(sx * 0.3, 7.0, sz * 0.3)
			var mid := (foot + top) * 0.5
			var leg := K.cyl(root, 0.13, 0.17, foot.distance_to(top), timber, mid, Vector3.ZERO, 8)
			leg.basis = Basis(Quaternion(Vector3.UP, (top - foot).normalized()))
	for y in [2.2, 4.6]:
		var w: float = 1.2 - float(y) * 0.13
		for k in 4:
			var r := K.cyl(root, 0.06, 0.06, w * 2.0, dark, Vector3(w if k == 0 else (-w if k == 1 else 0.0), y, w if k == 2 else (-w if k == 3 else 0.0)), Vector3(90, 0, 0) if k < 2 else Vector3(0, 0, 90), 6)
			r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	K.cyl(root, 0.26, 0.3, 18.0, timber, Vector3(0, 9.0, 0), Vector3.ZERO, 12)
	for y in [7.0, 12.0, 15.6]:
		K.torus(root, 0.26, 0.36, K.mat(Color("3b3b44"), 0.4), Vector3(0, y, 0))
	# Winch drum with a crank on the south side.
	K.cyl(root, 0.42, 0.42, 1.4, timber, Vector3(0, 1.6, 1.3), Vector3(0, 0, 90), 14)
	K.cyl(root, 0.05, 0.05, 0.5, dark, Vector3(0.8, 1.6, 1.3), Vector3(0, 0, 90), 6)
	K.rbox(root, Vector3(0.08, 0.5, 0.08), dark, Vector3(1.05, 1.4, 1.3), Vector3.ZERO, 0.02)
	# Grey banner with white ram horns hanging from the mast.
	var banner := K.rbox(root, Vector3(0.06, 3.2, 2.0), K.mat(Color("8e949b"), 0.9), Vector3(0.32, 12.6, 0.0), Vector3.ZERO, 0.03)
	banner.name = "RamBanner"
	var horn := K.mat(Color("f3efe6"), 0.6)
	for sz in [-1.0, 1.0]:
		K.torus(root, 0.28, 0.48, horn, Vector3(0.38, 13.0, sz * 0.42), Vector3(0, 0, 90))
	K.sphere(root, 0.22, horn, Vector3(0.38, 12.6, 0.0), Vector3(0.6, 1.0, 0.9))
	K.cone(root, 0.12, 0.3, K.mat(Color("c8302e")), Vector3(0, 18.3, 0), Vector3.ZERO, 6)
	# Boom: pivots on the mast at y 15, 9 m long along its local -Z, a bale on a rope at the tip.
	var boom := Node3D.new()
	boom.name = "Boom"
	root.add_child(boom)
	boom.position = Vector3(0, 15.0, 0)
	K.cyl(boom, 0.16, 0.2, 9.4, timber, Vector3(0, 0, -4.4), Vector3(90, 0, 0), 10)
	K.cyl(boom, 0.03, 0.03, 9.0, rope, Vector3(0, 1.2, -4.4), Vector3(83, 0, 0), 4)
	K.cyl(boom, 0.025, 0.025, 4.2, rope, Vector3(0, -2.1, -8.8), Vector3.ZERO, 4)
	var bale_ps: PackedScene = load(D.HAY_GLB) if ResourceLoader.exists(D.HAY_GLB) else null
	var bale := Node3D.new()
	bale.name = "Bale"
	boom.add_child(bale)
	bale.position = Vector3(0, -4.8, -8.8)
	if bale_ps:
		var bi := bale_ps.instantiate() as Node3D
		bi.position = Vector3(0, -0.6, 0)
		bale.add_child(bi)
	else:
		K.rbox(bale, Vector3(1.6, 1.1, 1.2), K.tex_mat("straw_thatch"), Vector3.ZERO)
	var to_pen := pen_center - at
	var pen_yaw := atan2(-to_pen.x, -to_pen.z)
	var rest_yaw := pen_yaw + deg_to_rad(95.0)
	boom.rotation.y = rest_yaw
	hoist = {"boom": boom, "bale": bale, "rest": rest_yaw, "pen": pen_yaw, "park": deg_to_rad(-45.0), "t": 6.0, "yard": hay_yard, "swinging": false}


func _hoist_step(delta: float) -> void:
	if hoist.is_empty():
		return
	var boom: Node3D = hoist["boom"]
	if not is_instance_valid(boom):
		return
	var yard: Node = hoist["yard"]
	var fighting := is_instance_valid(yard) and String(yard.get("state")) not in ["idle", "done"]
	var owned := level.has_method("i_owned") and bool(level.call("i_owned", "W1-7"))
	if fighting:
		boom.rotation.y = lerp_angle(boom.rotation.y, float(hoist["park"]), 1.0 - exp(-1.5 * delta))
		return
	if owned or bool(hoist["swinging"]):
		return
	hoist["t"] = float(hoist["t"]) - delta
	if float(hoist["t"]) > 0.0:
		return
	hoist["t"] = 20.0
	hoist["swinging"] = true
	var tw := boom.create_tween()
	tw.tween_property(boom, "rotation:y", float(hoist["pen"]), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		var bale: Node3D = hoist["bale"]
		if is_instance_valid(bale):
			ObjSvc.burst(level, bale.global_position + Vector3(0, -0.8, 0), Color(1.0, 0.86, 0.45), 30, 4.0, 0.22, -7.0, 1.2))
	tw.tween_interval(0.4)
	tw.tween_property(boom, "rotation:y", float(hoist["rest"]), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: hoist["swinging"] = false)


# ------------------------------------------------------------------ R3.8 riddle signs

func add_sign(sign: Node3D, riddle: String, fallback: String) -> void:
	if sign == null or fallback == "":
		return
	signs.append({"node": sign, "riddle": riddle, "fallback": fallback, "dwell": 0.0, "shown": false})


func _sign_step(delta: float, pp: Vector3) -> void:
	for s in signs:
		if bool(s["shown"]):
			continue
		var n: Node3D = s["node"]
		if not is_instance_valid(n):
			continue
		if n.global_position.distance_to(pp) < 4.0:
			s["dwell"] = float(s["dwell"]) + delta
			if float(s["dwell"]) >= 10.0:
				s["shown"] = true
				n.set("lines", PackedStringArray([String(s["riddle"]), String(s["fallback"])]))
				var tw := n.create_tween()
				tw.tween_property(n, "scale", Vector3.ONE * 1.12, 0.15)
				tw.tween_property(n, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK)
				_bark(n, String(s["fallback"]), 4.0, "Sign")
		else:
			s["dwell"] = maxf(float(s["dwell"]) - delta * 2.0, 0.0)


# ------------------------------------------------------------------ W1-2 sail ride dive

const RIDE_BOX := AABB(Vector3(30.0, 17.0, -46.5), Vector3(20.0, 17.0, 9.5))


func _ride_step(delta: float, pp: Vector3) -> void:
	var in_ride := RIDE_BOX.has_point(pp) and Vector2(pp.x - 40.0, pp.z + 45.2).length() > 2.3
	var cb3 := level.get_node_or_null("CB3")
	if in_ride:
		_ride_out = 0.0
		_ride_t += delta
		if cb3 and _cb3_radius < 0.0:
			_cb3_radius = float(cb3.get("notice_radius"))
			cb3.set("notice_radius", 0.5)
		if not _ride_done and _ride_t > 2.2:
			_ride_done = true
			var cb6 := level.get_node_or_null("CB6")
			if cb6 and String(cb6.get("state")) == "perch" and cb6.has_method("set_state"):
				cb6.process_mode = Node.PROCESS_MODE_INHERIT
				if cb6.has_method("say"):
					cb6.call("say", "CAW!", Color(1, 0.6, 0.4), 70)
				EnemyKit.sfx(level, "crow_caw", (cb6 as Node3D).global_position)
				cb6.call("set_state", "windup")
	else:
		_ride_out += delta
		if _ride_out > 1.0:
			_ride_t = 0.0
			if cb3 and _cb3_radius >= 0.0:
				cb3.set("notice_radius", _cb3_radius)
				_cb3_radius = -1.0
		if _ride_out > 6.0:
			_ride_done = false


# ------------------------------------------------------------------ bees

func add_bees(center: Vector3, count: int) -> void:
	if not ResourceLoader.exists(BEE_GLB):
		return
	var ps := load(BEE_GLB) as PackedScene
	for i in count:
		var holder := Node3D.new()
		holder.name = "Bee"
		level.add_child(holder)
		var inst := ps.instantiate() as Node3D
		holder.add_child(inst)
		var ab := AABB()
		var first := true
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var box := m.transform * m.mesh.get_aabb()
			ab = box if first else ab.merge(box)
			first = false
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var h := maxf(ab.size.y, 0.01)
		inst.scale = Vector3.ONE * (0.17 / h)
		inst.position = -ab.get_center() * inst.scale.x
		bees.append({"node": holder, "c": center, "r": _rng.randf_range(0.6, 1.5), "h": _rng.randf_range(0.9, 1.9), "w": _rng.randf_range(1.6, 2.8) * (1.0 if i % 2 == 0 else -1.0), "ph": _rng.randf() * TAU})


func _bee_step(_delta: float) -> void:
	for b in bees:
		var n: Node3D = b["node"]
		if not is_instance_valid(n):
			continue
		var a := float(b["ph"]) + _t * float(b["w"])
		var r := float(b["r"]) * (1.0 + 0.25 * sin(_t * 3.1 + float(b["ph"])))
		var c: Vector3 = b["c"]
		n.position = c + Vector3(cos(a) * r, float(b["h"]) + 0.25 * sin(_t * 5.3 + float(b["ph"])), sin(a) * r)
		n.rotation.y = -a + (PI if float(b["w"]) > 0.0 else 0.0)


# ------------------------------------------------------------------ labels and the intro shot

func _label_step() -> void:
	var cam := get_viewport().get_camera_3d()
	var story := cam != null and cam.get_parent() != null and String(cam.get_parent().name) == "StoryCams"
	var want := _hide_hud or story
	if want or _labels_hidden != want:
		for l: Label3D in level.find_children("*", "Label3D", true, false):
			if l.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
				l.visible = not want
		_labels_hidden = want
	# StoryCam_Intro_face: no giant acorn in front of Mak's face.
	var face := cam != null and String(cam.name) == "StoryCam_Intro_face"
	if face and _hidden_acorns.is_empty():
		for a in get_tree().get_nodes_in_group("acorn"):
			if a is Node3D and (a as Node3D).visible and (a as Node3D).global_position.distance_to(cam.global_position) < 2.6:
				(a as Node3D).visible = false
				_hidden_acorns.append(a)
	elif not face and not _hidden_acorns.is_empty():
		for a in _hidden_acorns:
			if is_instance_valid(a):
				a.visible = true
		_hidden_acorns.clear()

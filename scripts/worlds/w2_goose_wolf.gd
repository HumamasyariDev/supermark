extends Node3D
## W2-2 Goose Gag finale (amendments round 3 section 2, fix round 1): the "goose" is the Woolly Wolf in a goose
## costume. It waddle-flees clockwise round the cage plinth on an oval (centre (12.5, 50, -34), radii 3.6 x 6.0)
## at 5.5 m/s (6.2 after hit 1), flap-hops over Mak when he cuts it off, and every second lap darts for the gate,
## bonks the dropped portcullis and is dazed for 0.8 s. Only a dive or a jump kick lands (a punch, kick or slam
## lands only while it is dazed). Hit 1: the goose shell flies off ("I can SEE!"). Hit 2: it spins out through
## the lifting portcullis ("MOTHER!"). Contact never hurts Mak; it only bumps him. Real models: woolly_wolf.glb
## under a golden_goose.glb costume shell.

signal finished

# Fix r2 (fun critic): the oval is wider (3.9 x 6.8, so x 8.5..16.3 stays west of the Giant's stairs) so Mak can
# turn inside it, any fast attack (5 m/s or more) lands, every hit dazes it for 1.5 s, it dashes for the gate
# every lap after hit 1, and it stops to face Mak for 0.5 s before a flap-hop.
const C := Vector3(12.4, 50.05, -34.0)
const RX := 3.9
const RZ := 6.8
const FAST_HIT := 5.0
const GATE := Vector3(14.0, 50.05, -26.6)
const EXIT := Vector3(14.0, 50.05, -18.0)

var hits := 0
var speed := 5.5
var theta := PI * 0.5      # starts at the south end of the oval
var laps := 0.0
var state := "run"         # run, hop, dash, dazed, hide, exit, done
var st := 0.0
var _from := Vector3.ZERO
var _hop_cool := 0.0
var _dash_lap := 1
var _cool := 0.0
var visual: Node3D
var shell: Node3D
var wolf: Node3D
var portcullis: AnimatableBody3D
var _port_y := 61.2
var _port_target := 61.2
var _heckled := false
var _glyph: Label3D
var _glyph_shown := 0.0
var _miss_said := 0.0


func _ready() -> void:
	add_to_group("w2_goose_wolf")
	position = _oval(theta)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var wp := "res://assets/enemies/woolly_wolf/woolly_wolf.glb"
	if ResourceLoader.exists(wp):
		wolf = (load(wp) as PackedScene).instantiate() as Node3D
		wolf.name = "Wolf"
		wolf.rotation.y = PI
		wolf.scale = Vector3.ONE * 0.95
		wolf.visible = false
		visual.add_child(wolf)
	var gp := "res://assets/characters/golden_goose/golden_goose.glb"
	if ResourceLoader.exists(gp):
		shell = (load(gp) as PackedScene).instantiate() as Node3D
		shell.name = "GooseCostume"
		shell.rotation.y = PI
		shell.scale = Vector3.ONE * 1.4
		visual.add_child(shell)
		add_wolf_bits(shell, 2)
	var hurt := Area3D.new()
	hurt.name = "Hurtbox"
	hurt.collision_layer = 64
	hurt.collision_mask = 2
	hurt.monitorable = true
	hurt.monitoring = true
	var cs := CollisionShape3D.new()
	var sp := CapsuleShape3D.new()
	sp.radius = 0.75
	sp.height = 1.9
	cs.shape = sp
	cs.position = Vector3(0, 0.95, 0)
	hurt.add_child(cs)
	add_child(hurt)
	hurt.body_entered.connect(_on_body)
	_build_portcullis()
	_drop_portcullis(true)
	_build_track()
	# A "DIVE!" glyph pops over the goose while Mak is running fast enough to land a hit (until hit 1).
	_glyph = Label3D.new()
	_glyph.name = "DiveGlyph"
	_glyph.text = "DIVE!"
	_glyph.font_size = 96
	_glyph.outline_size = 24
	_glyph.modulate = Color("ffd23c")
	_glyph.outline_modulate = Color("5a2a10")
	_glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glyph.no_depth_test = true
	_glyph.pixel_size = 0.006
	_glyph.position = Vector3(0, 2.6, 0)
	_glyph.visible = false
	add_child(_glyph)


## A worn, darker track of trodden straw round the plinth, so the chase oval reads against the pale courtyard.
func _build_track() -> void:
	var st_ := SurfaceTool.new()
	st_.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 64
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var quad: Array[Vector3] = []
		for a in [a0, a1]:
			var c := Vector3(C.x + cos(a) * RX, 50.03, C.z + sin(a) * RZ)
			var nrm := Vector3(cos(a) / RX, 0, sin(a) / RZ).normalized()
			quad.append(c - nrm * 0.8)
			quad.append(c + nrm * 0.8)
		var col := Color("8a6a52") if i % 8 != 0 else Color("b33a3a")
		st_.set_color(col)
		st_.set_normal(Vector3.UP)
		for v in [quad[0], quad[2], quad[1], quad[1], quad[2], quad[3]]:
			st_.add_vertex(v)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.albedo_color = Color(1, 1, 1, 0.8)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.name = "ChaseTrack"
	mi.mesh = st_.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child.call_deferred(mi)
	finished.connect(func() -> void:
		if is_instance_valid(mi):
			mi.queue_free())


## The costume is falling apart: a grey wolf ear (stage >= 1) and a bushy tail (stage >= 2) poke out of the real
## goose model. Procedural props sized from the model's own bounds (glTF +Z is the goose's front).
static func add_wolf_bits(g: Node3D, stage: int) -> void:
	var box := model_aabb(g)
	if box.size.length() < 0.01:
		return
	var old := g.get_node_or_null("WolfBits")
	if old:
		old.free()
	var M := preload("res://scripts/worlds/w2_mesh.gd")
	var m = M.new()
	var h := box.size.y
	var top := box.position.y + h
	if stage >= 1:
		m.sphere(Transform3D(Basis(Vector3.BACK, 0.35).scaled(Vector3(0.06, 0.13, 0.04) * h), Vector3(box.get_center().x + box.size.x * 0.12, top - h * 0.02, box.get_center().z + box.size.z * 0.18)), Color("8e949b"), 10, 6, Color("5c6168"))
		m.sphere(Transform3D(Basis(Vector3.BACK, 0.3).scaled(Vector3(0.03, 0.08, 0.02) * h), Vector3(box.get_center().x + box.size.x * 0.12, top - h * 0.0, box.get_center().z + box.size.z * 0.2)), Color("e8a6b0"), 8, 5)
	if stage >= 2:
		m.sphere(Transform3D(Basis(Vector3.RIGHT, -0.9).scaled(Vector3(0.09, 0.26, 0.09) * h), Vector3(box.get_center().x, box.position.y + h * 0.28, box.position.z - h * 0.05)), Color("8e949b"), 12, 8, Color("e8e4dc"))
	if m.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	var mi := MeshInstance3D.new()
	mi.name = "WolfBits"
	mi.mesh = m.commit(mat)
	g.add_child(mi)


## AABB of every mesh under `root`, in root's local space (works outside the tree).
static func model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.name == "WolfBits":
			continue
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != root:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var bb := xf * mi.mesh.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


func _build_portcullis() -> void:
	portcullis = AnimatableBody3D.new()
	portcullis.name = "Portcullis"
	portcullis.sync_to_physics = true
	portcullis.collision_layer = 1
	portcullis.collision_mask = 0
	portcullis.position = Vector3(14.0, _port_y, -25.2)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(6.0, 7.0, 0.4)
	cs.shape = bs
	cs.position = Vector3(0, -3.5, 0)
	portcullis.add_child(cs)
	var M := preload("res://scripts/worlds/w2_mesh.gd")
	var m = M.new()
	var iron := Color("4a4550")
	for i in 7:
		var x := -2.7 + float(i) * 0.9
		m.cylinder(Transform3D(Basis(), Vector3(x, -3.5, 0)), 0.09, 0.09, 7.0, iron, 10)
		m.cylinder(Transform3D(Basis(), Vector3(x, -7.1, 0)), 0.0, 0.14, 0.35, iron.darkened(0.2), 10)
	for j in 4:
		m.rbox(Transform3D(Basis(), Vector3(0, -0.8 - float(j) * 1.9, 0)), Vector3(6.0, 0.16, 0.16), 0.05, iron.lightened(0.1), 2)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.5
	mat.roughness = 0.45
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit(mat)
	portcullis.add_child(mi)
	get_parent().add_child.call_deferred(portcullis)


func _drop_portcullis(down: bool) -> void:
	_port_target = 57.0 if down else 61.2
	if down:
		_say("CLANG! The portcullis drops behind you.")
		_sfx("crate_break")


func _oval(th: float) -> Vector3:
	return C + Vector3(cos(th) * RX, 0.0, sin(th) * RZ)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _in_courtyard(p: Vector3) -> bool:
	return p.x > 8.0 and p.x < 20.0 and p.y > 49.0 and p.y < 58.0 and p.z > -42.0 and p.z < -24.5


func hit_by_player(kind: String, _from_pos: Vector3) -> bool:
	if state in ["exit", "done", "hide"] or _cool > 0.0:
		return false
	var airborne := state == "hop" and visual != null and visual.position.y > 0.6
	var ok := kind in ["dive", "jump_kick", "slide"] and not airborne
	# Fix r2: a punch or kick thrown at speed counts too (the dive needs 6.8 m/s, the oval rarely allows it).
	if kind in ["punch", "kick"] and _player_speed() >= FAST_HIT and not airborne:
		ok = true
	if state == "dazed" and kind in ["punch", "kick", "slam", "stomp", "slide", "dive", "jump_kick"]:
		ok = true
	if not ok:
		_deflect()
		return false
	_cool = 0.8
	hits += 1
	_fx("FeatherBurst", global_position + Vector3(0, 1.0, 0))
	_sfx("goose_honk")
	if hits == 1:
		speed = 6.2
		_say("The \"goose\": \"I can SEE!\"")
		if shell:
			var s := shell
			shell = null
			var tw := create_tween()
			tw.tween_property(s, "position", s.position + Vector3(0, 3.0, 1.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(s, "rotation:x", 6.0, 0.6)
			tw.tween_property(s, "scale", Vector3.ONE * 0.01, 0.25)
			tw.tween_callback(s.queue_free)
		if wolf:
			wolf.visible = true
		# Daze 1.5 s (stars, squash) so the follow-up hit is a readable moment.
		state = "dazed"
		st = -0.7
		_fx("DizzyStars", global_position + Vector3(0, 1.8, 0))
		if visual:
			visual.scale = Vector3(1.3, 0.6, 1.3)
			var tw2 := create_tween()
			tw2.tween_property(visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_say("BONK! It's seeing stars: hit it again!")
	else:
		_say("The wolf: \"MOTHER!\" (it spins out through the gate)")
		state = "exit"
		st = 0.0
		_from = global_position
		_drop_portcullis(false)
	return true


func _on_body(body: Node) -> void:
	if not body.is_in_group("player") or state in ["exit", "done"]:
		return
	# Contact never hurts: it bumps Mak 2 m away.
	var away := (body as Node3D).global_position - global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3.BACK
	if body.has_method("add_impulse"):
		body.call("add_impulse", away * 6.0 + Vector3(0, 3.0, 0))


func _physics_process(delta: float) -> void:
	st += delta
	_cool = maxf(0.0, _cool - delta)
	_hop_cool = maxf(0.0, _hop_cool - delta)
	_port_y = move_toward(_port_y, _port_target, (14.0 if _port_target < _port_y else 3.0) * delta)
	if is_instance_valid(portcullis):
		portcullis.global_position = Vector3(14.0, _port_y, -25.2)
	var p := _player()
	var pp := p.global_position if p else Vector3(999, 0, 0)
	var vis_y := 0.0
	match state:
		"run":
			if p and not _in_courtyard(pp):
				state = "hide"
				st = 0.0
				_from = global_position
				_drop_portcullis(false)
				_say("The \"goose\": \"...honk?\" (it hides behind the plinth)")
				return
			var d := Vector3(-sin(theta) * RX, 0.0, cos(theta) * RZ).length()
			var dth := speed * delta / maxf(d, 0.5)
			# Cut-off: Mak stands in its path within 4 m -> flap-hop over him.
			var ahead := _oval(theta + 4.0 / maxf(d, 0.5))
			if _hop_cool <= 0.0 and Vector2(pp.x - ahead.x, pp.z - ahead.z).length() < 1.6 and pp.distance_to(global_position) < 4.5:
				state = "hop"
				st = 0.0
				_hop_cool = 2.0
			theta += dth
			laps += dth / TAU
			global_position = _oval(theta)
			_face(_oval(theta + 0.2))
			# Gate dash every second lap at the south end of the oval.
			if int(laps) >= _dash_lap and absf(wrapf(theta - PI * 0.5, -PI, PI)) < dth * 1.5:
				_dash_lap += 2 if hits == 0 else 1
				state = "dash"
				st = 0.0
				_from = global_position
			vis_y = absf(sin(st * 12.0)) * 0.08
		"hop":
			# 0.4 s crouch telegraph, then 0.6 s in the air (1.2 m high) while still going round.
			var d2 := Vector3(-sin(theta) * RX, 0.0, cos(theta) * RZ).length()
			if st < 0.5:
				vis_y = -0.15
				_face(pp)
				if visual:
					visual.scale = Vector3(1.1, 0.8, 1.1)
			else:
				var u := clampf((st - 0.5) / 0.6, 0.0, 1.0)
				theta += speed * delta / maxf(d2, 0.5)
				laps += speed * delta / maxf(d2, 0.5) / TAU
				global_position = _oval(theta)
				_face(_oval(theta + 0.2))
				vis_y = 1.2 * 4.0 * u * (1.0 - u)
				if visual:
					visual.scale = Vector3.ONE
				if u >= 1.0:
					state = "run"
					st = 0.0
		"dash":
			var u2 := clampf(st / 0.7, 0.0, 1.0)
			global_position = _from.lerp(GATE, u2)
			_face(GATE)
			if u2 >= 1.0:
				state = "dazed"
				st = 0.0
				_sfx("bonk")
				_fx("DizzyStars", global_position + Vector3(0, 1.8, 0))
				_say("BONK! The \"goose\" is seeing stars.")
		"dazed":
			visual.rotation.z = sin(st * 14.0) * 0.2
			if st > 0.8:
				visual.rotation.z = 0.0
				# Back onto the oval at the nearest point.
				var rel := global_position - C
				theta = atan2(rel.z / RZ, rel.x / RX)
				global_position = _oval(theta)
				state = "run"
				st = 0.0
		"hide":
			global_position = global_position.lerp(C + Vector3(0, 0, -3.2), 1.0 - exp(-4.0 * delta))
			if p and _in_courtyard(pp) and pp.z < -27.0:
				state = "run"
				st = 0.0
				theta = atan2((global_position.z - C.z) / RZ, (global_position.x - C.x) / RX)
				_drop_portcullis(true)
		"exit":
			var u3 := clampf(st / 1.6, 0.0, 1.0)
			global_position = _from.lerp(EXIT, u3)
			visual.rotation.y += delta * 18.0
			if u3 >= 1.0:
				state = "done"
				_fx("Poof", global_position + Vector3(0, 0.8, 0))
				visible = false
				finished.emit()
	if visual:
		visual.position.y = vis_y
	_miss_said = maxf(0.0, _miss_said - delta)
	if _glyph:
		var show := hits == 0 and state in ["run", "dazed", "dash"] and p != null and _player_speed() >= FAST_HIT and pp.distance_to(global_position) < 9.0
		_glyph_shown = _glyph_shown + delta if show else 0.0
		_glyph.visible = show
		if show:
			_glyph.scale = Vector3.ONE * (1.0 + 0.12 * sin(_glyph_shown * 14.0))
	if not _heckled and state == "run" and st > 2.0:
		_heckled = true
		_say("Crow on the eave: \"Run, Wolfie, run!\"")


func _player_speed() -> float:
	var p := _player()
	if p is CharacterBody3D:
		var v := (p as CharacterBody3D).velocity
		return Vector2(v.x, v.z).length()
	return 0.0


## A slow hit glances off: feather puff, honk squash and (once in a while) the hint.
func _deflect() -> void:
	if _miss_said > 0.0:
		return
	_miss_said = 1.2
	_fx("FeatherBurst", global_position + Vector3(0, 1.0, 0))
	_sfx("goose_honk")
	if visual:
		visual.scale = Vector3(0.8, 1.25, 0.8)
		var tw := create_tween()
		tw.tween_property(visual, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_say("The \"goose\": \"Honk! Too slow!\" (get up to speed first)")


func _face(at: Vector3) -> void:
	var d := at - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		rotation.y = atan2(-d.x, -d.z)


func _say(text: String) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("toast"):
		ui.toast(text)


func _sfx(key: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.play_sfx(key, global_position)


func _fx(scene: String, pos: Vector3) -> void:
	var path := "res://scenes/fx/%s.tscn" % scene
	if ResourceLoader.exists(path):
		var fx := (load(path) as PackedScene).instantiate() as Node3D
		get_parent().add_child(fx)
		fx.global_position = pos

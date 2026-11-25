extends TruffleSpawner
## W3-2 "Sergeant Snap" (amendments R1.6 + R2.3): a four-phase fight with four different answers.
##   1  Snap beats the snare on the north walkway (invulnerable). The squad marches in the yard. Ham Slam the parade
##      drum with grenadiers inside 7 m: they topple for 2.5 s (a stomp then defeats each). Drum rearms after 6 s.
##   2  Snap leaps into the yard and advances, spinning his lance (1.0 s red ring telegraph). A jump over it is caught;
##      a dive or belly slide into his boots trips him for 2.5 s. Stomp while tripped = hit 1.
##   3  Snap hops back onto the walkway and lobs gobstoppers (3 per volley, 1.6 s apart, ring telegraph). Climb up
##      (sugar cubes, backflip or triple jump) and stomp him = hit 2. He tumbles into the yard.
##   4  "Double-time!" He runs to his drum mark, raises the sticks (0.8 s telegraph) and beats a 2.0 s roll that pops
##      anything on the drumskin. His shako guards his head while drumming. Ham Slam the drum while he drums: BOOM, he
##      is thrown onto his back for 2.5 s; stomp = hit 3, defeat. A finished roll calls two reinforcements and one
##      sweep advance. The truffle bursts from the drum.
## Phase restart: dying in phase 3 or 4 respawns at CP11_fort_yard; that phase restarts with the squad gone and the
## earned hits kept (a static record survives the checkpoint reload).

@export var squad_paths: Array[NodePath] = []
@export var snap_path: NodePath
@export var yard_size := Vector3(14.8, 4.0, 10.8)

const DRUM := Vector3(46.0, 2.0, 43.0)     # drum base centre (top 3.0)
const DRUM_MARK := Vector3(44.2, 2.0, 43.0)
const WALK := Vector3(46.0, 5.6, 36.6)       # Snap's spot on the north walkway
const YARD_LAND := Vector3(46.0, 2.0, 40.2)
const CP11 := Vector3(39.5, 2.0, 43.0)
const E_GRENADIER := "res://scenes/enemies/GingerbreadGrenadier.tscn"

static var _saved := {}   # {"phase": int, "hits": int, "msec": int}

var drum_skin: MeshInstance3D
var drum_armed_mat: Material
var drum_spent_mat: Material

var phase := 0
var hits := 0
var _squad: Array = []
var _snap: Node3D
var _announced := false
var _armed := true
var _sub := ""          # phase sub-state
var _t := 0.0           # sub-state timer
var _beat := 0.0
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO
var _leap_len := 0.8
var _leap_h := 2.5
var _volley := 0
var _flipped := false
var _first_spin_done := false
var _reinf: Array = []
var _ring: MeshInstance3D
var _ring_t := 0.0
var _won := false


func _ready() -> void:
	super._ready()
	for p in squad_paths:
		var e := get_node_or_null(p)
		if e and e.has_signal("defeated"):
			_squad.append(e)
			e.connect("defeated", _on_squad_down)
	_snap = get_node_or_null(snap_path) as Node3D
	var yard := Area3D.new()
	yard.name = "YardTrigger"
	yard.collision_layer = 128
	yard.collision_mask = 2
	yard.monitorable = false
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = yard_size
	cs.shape = b
	cs.position = Vector3(0, yard_size.y * 0.5, 0)
	yard.add_child(cs)
	add_child(yard)
	yard.body_entered.connect(_on_yard)
	_build_slam_ring()
	call_deferred("_start")


func _start() -> void:
	if _snap == null or not is_instance_valid(_snap):
		return
	_snap.set("max_hp", 99)
	_snap.set("hp", 99)
	# Finish pass (encounter r1 major: 42 phase-1 stomps with full hurt feedback did nothing): only hits that count
	# hurt him; the rest bounce or clang (EnemyBase hit_gate).
	_snap.set_meta("hit_gate", _snap_hit_counts)
	if _snap.has_signal("hit_taken"):
		_snap.connect("hit_taken", _on_snap_hit)
	var dev := get_node_or_null("/root/Dev")
	var force_band := dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "w3-band"))
	if ObjSvc.has_truffle(reward_truffle_id) or force_band:
		_start_parade()
		return
	var resume := int(_saved.get("phase", 0))
	# Finishing pass (W3 QA r1c major): the 15 min window also caught a fresh visit from the hub, which then put
	# CP11 (the fort yard) as the checkpoint. A death restart reloads within seconds, so 3 min keeps that case only.
	if resume >= 3 and Time.get_ticks_msec() - int(_saved.get("msec", 0)) < 3 * 60 * 1000:
		# Phase restart (R2.3): the squad is already beaten and Snap keeps his earned hits.
		hits = int(_saved.get("hits", 0))
		for e in _squad:
			if is_instance_valid(e):
				e.disconnect("defeated", _on_squad_down)
				e.queue_free()
		_squad.clear()
		_announced = true
		_set_snap_vulnerable(true)
		if resume == 3:
			_place_snap(WALK)
			_enter_phase(3)
		else:
			_place_snap(DRUM_MARK + Vector3(-1.5, 0, 0))
			_enter_phase(4)
		print("[W3] fort phase restart: phase %d hits %d" % [resume, hits])
		return
	_place_snap(WALK)
	_enter_phase(1)


# ------------------------------------------------------------------ R3.8 parade band (after W3-2)

var _parade := false
var _band_t := 0.0
const BAND_LOOP := [Vector3(41, 2.05, 39.5), Vector3(51, 2.05, 39.5), Vector3(51, 2.05, 46.5), Vector3(41, 2.05, 46.5)]


func _start_parade() -> void:
	_parade = true
	_announced = true
	_set_ring(false)
	_place_snap(WALK)
	_ai(false)
	_set_snap_vulnerable(false)
	_snap.set("contact_damage", false)
	for e in _squad:
		if not is_instance_valid(e):
			continue
		e.set("ai_enabled", false)
		e.set("contact_damage", false)
		var hb: Variant = e.get("hurtbox")
		if hb is Area3D:
			(hb as Area3D).set_deferred("monitorable", false)
		var hz: Variant = e.get("head_zone")
		if hz is Area3D:
			(hz as Area3D).set_deferred("monitoring", false)
	print("[W3] world_state: parade band")


func _loop_pos(u: float) -> Vector3:
	var per := 0.0
	var lens: Array[float] = []
	for i in 4:
		var l: float = (BAND_LOOP[i] as Vector3).distance_to(BAND_LOOP[(i + 1) % 4])
		lens.append(l)
		per += l
	var d := fposmod(u, per)
	for i in 4:
		if d <= lens[i]:
			return (BAND_LOOP[i] as Vector3).lerp(BAND_LOOP[(i + 1) % 4], d / lens[i])
		d -= lens[i]
	return BAND_LOOP[0]


func _parade_step(delta: float) -> void:
	_band_t += delta
	var beat := 60.0 / 132.0
	for i in _squad.size():
		var e: Node3D = _squad[i]
		if not is_instance_valid(e) or _dead(e):
			continue
		var want := _loop_pos(_band_t * 1.1 + float(i) * 2.2)
		var to := want - e.global_position
		to.y = 0
		e.set("velocity", Vector3(to.x, 0, to.z) * 4.0)
		if to.length() > 0.05 and e.has_method("face_toward"):
			e.call("face_toward", want + to.normalized(), delta, 6.0)
	_beat += delta
	if _beat > beat * 2.0:
		_beat = 0.0
		if _snap.has_method("kick_squash"):
			_snap.call("kick_squash", 0.25)
	if _t > 4.0:
		_t = 0.0
		var pl := _player()
		if pl and pl.global_position.distance_to(DRUM) < 16.0:
			_snap_say(["Band! Quick march!", "A fine parade for a fine pig!", "Left! Right! Lovely!"][randi() % 3], 64)


# ------------------------------------------------------------------ helpers

func _dead(n: Variant) -> bool:
	if n == null or not is_instance_valid(n):
		return true
	var v: Variant = (n as Object).get("is_defeated")
	return v != null and bool(v)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _snap_say(text: String, size: int = 84) -> void:
	if _snap and _snap.has_method("say"):
		_snap.call("say", text, Color(1.0, 0.86, 0.45), size)


func _place_snap(p: Vector3) -> void:
	_snap.global_position = p
	_snap.set("velocity", Vector3.ZERO)
	_snap.set("home", p)
	if _snap.has_method("reset_physics_interpolation"):
		_snap.reset_physics_interpolation()


func _face(p: Vector3, delta: float, speed: float = 8.0) -> void:
	if _snap.has_method("face_toward"):
		_snap.call("face_toward", p, delta, speed)


func _set_snap_vulnerable(on: bool) -> void:
	var hb: Variant = _snap.get("hurtbox")
	if hb is Area3D and is_instance_valid(hb):
		(hb as Area3D).set_deferred("monitorable", on)
	var hz: Variant = _snap.get("head_zone")
	if hz is Area3D and is_instance_valid(hz):
		(hz as Area3D).set_deferred("monitoring", on)


func _ai(on: bool) -> void:
	_snap.set("ai_enabled", on)


func _sub_to(s: String) -> void:
	_sub = s
	_t = 0.0


func _leap(to: Vector3, length: float, h: float) -> void:
	_leap_from = _snap.global_position
	_leap_to = to
	_leap_len = length
	_leap_h = h
	_snap.set("uses_gravity", false)
	_sub_to("leap")


## Returns true when the leap has finished this frame.
func _leap_step() -> bool:
	var u := clampf(_t / _leap_len, 0.0, 1.0)
	var p := _leap_from.lerp(_leap_to, u)
	p.y += sin(u * PI) * _leap_h
	_snap.global_position = p
	_snap.set("velocity", Vector3.ZERO)
	if u >= 1.0:
		_snap.set("uses_gravity", true)
		if _snap.has_method("kick_squash"):
			_snap.call("kick_squash", 0.6)
		ObjSvc.fx(get_parent(), "DustPuff", _snap.global_position)
		return true
	return false


func _save() -> void:
	_saved = {"phase": phase, "hits": hits, "msec": Time.get_ticks_msec()}


func _set_cp11() -> void:
	var xf := Transform3D(Basis(Vector3.UP, -PI * 0.5), CP11)
	ObjSvc.call_on("Game", "set_checkpoint", ["W3", xf])


func _banner(title: String, sub: String, secs: float = 2.2) -> void:
	ObjSvc.call_on("UI", "show_banner", [title, sub, secs])


# ------------------------------------------------------------------ phases

func _enter_phase(n: int) -> void:
	phase = n
	print("[W3] snap phase %d (hits %d)" % [n, hits])
	match n:
		1:
			_ai(false)
			_set_snap_vulnerable(false)
			_sub_to("drum")
		2:
			_banner("Phase 2", "Dive under the spinning lance!", 2.2)
			_snap_say("Squad down?! Then I'll do it MYSELF!", 80)
			_set_snap_vulnerable(true)
			_ai(false)
			_leap(YARD_LAND, 0.9, 3.0)
			_set_ring(false)
		3:
			_save()
			_set_cp11()
			_banner("Phase 3", "Get up on the walkway!", 2.2)
			_set_snap_vulnerable(true)
			_ai(false)
			if _snap.global_position.distance_to(WALK) > 1.0:
				_snap_say("Retreat to the battlements!", 76)
				_leap(WALK, 1.0, 4.0)
			else:
				_sub_to("lob")
			_volley = 0
		4:
			_save()
			_set_cp11()
			_banner("Phase 4", "Slam the drum while he drums!", 2.4)
			_snap_say("Double-time!", 96)
			_set_snap_vulnerable(true)
			_ai(false)
			_flipped = false
			_sub_to("to_mark")
			_set_ring(true)


func _physics_process(delta: float) -> void:
	if _snap == null or not is_instance_valid(_snap) or _won:
		return
	if _dead(_snap):
		return
	_t += delta
	if _parade:
		_parade_step(delta)
		return
	_ring_step(delta)
	match phase:
		1:
			_phase1(delta)
		2:
			_phase2(delta)
		3:
			_phase3(delta)
		4:
			_phase4(delta)


func _phase1(delta: float) -> void:
	# Beating the snare on the walkway at 132 BPM, facing the yard.
	var pl := _player()
	if pl:
		_face(Vector3(pl.global_position.x, _snap.global_position.y, pl.global_position.z), delta, 3.0)
	_beat += delta
	if _beat > 60.0 / 132.0 * 2.0:
		_beat = 0.0
		if _snap.has_method("kick_squash"):
			_snap.call("kick_squash", 0.25)
	if _t > 3.2:
		_t = 0.0
		if _announced:
			_snap_say(["Left! Right! Left!", "Eyes front, squad!", "Hup! Two! Three!", "Mind that drum, lads!"][randi() % 4], 64)


func _phase2(delta: float) -> void:
	match _sub:
		"leap":
			if _leap_step():
				_snap_say("Hup-hup! Taste the lance!", 76)
				_ai(true)
				_snap.call("set_state", "advance")
				_sub_to("fight")
		"fight":
			# Built-in sergeant AI: advance, 1.0 s red ring, spin; a dive into his boots trips him ("tripped").
			if String(_snap.get("state")) == "sweep" and not _first_spin_done:
				_first_spin_done = true
				ObjSvc.call_on("UI", "show_banner", ["", "Get under it! DIVE!", 1.6])
			# The drum bonk: a spin that touches the drum leaves him dizzy (counts like a trip).
			if String(_snap.get("state")) == "sweep" and Vector2(_snap.global_position.x - DRUM.x, _snap.global_position.z - DRUM.z).length() < 3.3 and _t > 1.5:
				_t = 0.0
				ObjSvc.sfx("drum_boom", DRUM + Vector3(0, 1, 0))
				_snap_say("BONG! Ooh, the room's spinning...", 72)
				_snap.call("set_state", "tripped")


func _phase3(delta: float) -> void:
	match _sub:
		"leap":
			if _leap_step():
				_sub_to("lob")
				_volley = 0
				_snap_say("Have a gobstopper, piglet!", 76)
		"lob":
			var pl := _player()
			if pl:
				_face(pl.global_position, delta, 6.0)
			# 3 lobs 1.6 s apart, then a 2 s pause.
			if _volley < 3 and _t > 1.6:
				_t = 0.0
				_volley += 1
				if pl and _snap.has_method("_lob"):
					_snap.call("_lob")
			elif _volley >= 3 and _t > 2.0:
				_t = 0.0
				_volley = 0
			# Knocked off the walkway by a punch: back up he goes.
			if _snap.global_position.y < 4.0 and hits < 2:
				_leap(WALK, 1.0, 4.0)


func _phase4(delta: float) -> void:
	var pl := _player()
	match _sub:
		"leap":
			if _leap_step():
				_sub_to("to_mark")
		"to_mark":
			var to := DRUM_MARK - _snap.global_position
			to.y = 0
			if to.length() < 0.25:
				_sub_to("tell")
				_snap_say("Ah-ONE, ah-TWO!", 92)
				if _snap.has_method("flash"):
					_snap.call("flash", Color(1.0, 0.6, 0.2), 0.8, 0.9, true)
			else:
				var step := to.normalized() * minf(to.length(), 4.0 * delta)
				_snap.global_position += step
				_face(DRUM_MARK, delta, 10.0)
		"tell":
			_face(DRUM, delta, 10.0)
			if _t > 0.8:
				_sub_to("roll")
				_beat = 0.0
				ObjSvc.sfx("drum_roll", DRUM + Vector3(0, 1, 0))
		"roll":
			_face(DRUM, delta, 10.0)
			_beat += delta
			if _beat > 0.25:
				_beat = 0.0
				if _snap.has_method("kick_squash"):
					_snap.call("kick_squash", 0.3)
				if pl and _on_drum(pl) and pl.has_method("bounce"):
					pl.call("bounce", 6.7)   # 0.8 m pop
			if _t > 2.0:
				_snap_say("Reinforcements! Fall in!", 80)
				_call_reinforcements()
				_ai(true)
				_snap.call("set_state", "advance")
				_snap.set("_sweep_cd", 0.0)
				_sub_to("sweep")
		"sweep":
			if _t > 4.5 and String(_snap.get("state")) != "sweep" and String(_snap.get("state")) != "hurt":
				_ai(false)
				_snap.call("set_state", "recover")
				_sub_to("to_mark")
		"flipped":
			if _t > 2.5:
				_flipped = false
				_snap.call("set_state", "recover")
				if _snap.has_method("stunned"):
					_snap.call("stunned", false)
				_snap_say("Hrmph! Again, from the top!", 72)
				_sub_to("to_mark")


func _on_drum(pl: Node3D) -> bool:
	var p := pl.global_position
	return Vector2(p.x - DRUM.x, p.z - DRUM.z).length() < 1.25 and p.y > 2.8 and p.y < 3.6


func _call_reinforcements() -> void:
	var alive := 0
	for e in _reinf:
		if is_instance_valid(e) and not _dead(e):
			alive += 1
	if alive >= 2 or not ResourceLoader.exists(E_GRENADIER):
		return
	var ps := load(E_GRENADIER) as PackedScene
	var made: Array = []
	for k in 2 - alive:
		var e := ps.instantiate() as Node3D
		var start := Vector3(37.0, 2.05, 42.0 + 2.0 * k)
		var pts: Array[Vector3] = [Vector3.ZERO, Vector3(6.0, 0, 0)]
		e.set("patrol_points", pts)
		e.name = "squad_reinforcement_%d" % (k + 1)
		get_parent().get_node("Enemies").add_child(e)
		e.global_position = start
		e.set("home", start)
		e.set("formation_index", k)
		made.append(e)
		_reinf.append(e)
	for e in made:
		e.set("squad", made)
	ObjSvc.sfx("gingerbread_march", Vector3(37, 2, 43))


# ------------------------------------------------------------------ events

func _on_yard(body: Node) -> void:
	if _announced or not body.is_in_group("player"):
		return
	_announced = true
	_banner("Sergeant Snap", "Ham Slam the drum to topple the squad!", 2.6)
	_snap_say("Ten-HUT! Intruder in the yard!", 92)
	ObjSvc.sfx("drum_roll", global_position)
	_entry_pan()


## R1 fun major: a 1.8 s entry pan from the gate over the squad and the glowing drum to Snap on the walkway.
func _entry_pan() -> void:
	var prev := get_viewport().get_camera_3d()
	if prev == null:
		return
	var cam := Camera3D.new()
	cam.name = "FortPanCam"
	cam.fov = 52.0
	add_child(cam)
	cam.global_transform = prev.global_transform
	cam.make_current()
	var mid := Transform3D(Basis(), Vector3(38.5, 7.5, 47.5)).looking_at(DRUM + Vector3(0, 1.0, 0), Vector3.UP)
	var end := Transform3D(Basis(), Vector3(43.0, 6.2, 44.5)).looking_at(WALK + Vector3(0, 1.4, 0), Vector3.UP)
	var tw := create_tween()
	tw.tween_property(cam, "global_transform", mid, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(cam, "global_transform", end, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void:
		if is_instance_valid(prev):
			prev.make_current()
		cam.queue_free())


## Called by the level when the parade drum is Ham Slammed.
func on_drum_slam(c: Vector3) -> void:
	if _parade or _won:
		_boom(c)
		_snap_say("Ha! Encore!", 72)
		return
	if phase == 4 and (_sub == "tell" or _sub == "roll" or _sub == "to_mark") \
			and Vector2(_snap.global_position.x - DRUM.x, _snap.global_position.z - DRUM.z).length() < 2.8:
		# BOOM: Snap is thrown 3 m back onto his back for 2.5 s.
		_boom(c)
		_flipped = true
		var away := _snap.global_position - DRUM
		away.y = 0
		away = away.normalized() if away.length() > 0.1 else Vector3.LEFT
		_sub_to("flipped")
		var tw := _snap.create_tween()
		tw.tween_property(_snap, "global_position", _snap.global_position + away * 3.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_snap.call("set_state", "tripped")
		if _snap.has_method("stunned"):
			_snap.call("stunned", true)
		_snap_say("My DRUM! My DIGNITY!", 90)
		_banner("", "He's on his back! STOMP him!", 1.6)
		return
	if not _armed:
		return
	_boom(c)
	_armed = false
	if drum_skin and drum_spent_mat:
		drum_skin.material_override = drum_spent_mat
	_set_ring(false)
	var n := 0
	var pool: Array = _squad + _reinf
	for en in pool:
		if not is_instance_valid(en) or not en.is_inside_tree() or _dead(en):
			continue
		var d := Vector2(en.global_position.x - c.x, en.global_position.z - c.z).length()
		if d < 7.0:
			# Topple for 2.5 s (R1.6): each one still needs a stomp.
			en.call("set_state", "tripped")
			n += 1
	print("[W3] drum slam: toppled %d" % n)
	if n > 0:
		ObjSvc.call_on("UI", "show_banner", ["", "TOPPLED! Stomp them!", 1.4])
	var t := get_tree().create_timer(6.0, false, true)
	t.timeout.connect(func() -> void:
		_armed = true
		if drum_skin and drum_armed_mat:
			drum_skin.material_override = drum_armed_mat
		if phase == 1:
			_set_ring(true))


func _boom(c: Vector3) -> void:
	ObjSvc.fx(get_parent(), "SlamShockwave", c)
	ObjSvc.burst(get_parent(), c, Color(1.0, 0.85, 0.5), 40, 9.0, 0.2, -6.0, 0.8)
	ObjSvc.sfx("drum_boom", c)


func _snap_hit_counts(kind: String) -> bool:
	if _won or _parade:
		return not _parade
	match phase:
		2:
			return String(_snap.get("state")) == "tripped"
		3:
			return _snap.global_position.y > 4.5 or kind == "stomp" or kind == "slam"
		4:
			return _flipped
	return false


var _snap_hint_ms := 0


func _on_snap_hit(kind: String, landed: bool) -> void:
	if not landed and not _won and not _parade and Time.get_ticks_msec() - _snap_hint_ms > 2500:
		_snap_hint_ms = Time.get_ticks_msec()
		match phase:
			1:
				_snap_say("Ha! Beat my squad first, piglet!", 70)
			2:
				_snap_say("Ha! Not while I'm spinning! Dive at my boots!", 70)
			4:
				_snap_say("Ha! Not while I'm drumming!", 70)
	if not landed or _won:
		return
	var st := String(_snap.get("state"))
	var valid := false
	match phase:
		2:
			valid = st == "tripped"
		3:
			valid = _snap.global_position.y > 4.5 or kind == "stomp" or kind == "slam"
		4:
			valid = _flipped
	_snap.set("hp", 99)
	if not valid:
		if phase == 2 or phase == 4:
			_snap_say("Ha! Not while I'm %s!" % ("spinning" if phase == 2 else "drumming"), 70)
		return
	hits += 1
	print("[W3] snap hit %d (phase %d, %s)" % [hits, phase, kind])
	match hits:
		1:
			_snap_say("Ow! Cheeky trotters!", 80)
			_ai(false)
			call_deferred("_enter_phase", 3)
		2:
			_snap_say("Whoa-oa-oa!", 90)
			_ai(false)
			# He tumbles off the walkway into the yard, then phase 4.
			_snap.set("uses_gravity", false)
			phase = 4
			_leap(Vector3(45.0, 2.0, 39.6), 0.8, 1.0)
			call_deferred("_enter_phase_4_after_tumble")
		_:
			_win()


func _enter_phase_4_after_tumble() -> void:
	phase = 4
	_save()
	_set_cp11()
	_banner("Phase 4", "Slam the drum while he drums!", 2.4)
	_set_snap_vulnerable(true)
	_flipped = false
	_set_ring(true)
	_sub = "leap"   # finish the tumble arc, then walk to the drum mark


func _win() -> void:
	_won = true
	_saved = {}
	_set_ring(false)
	_snap.set("hp", 1)
	_snap_say("I... surrender... (the shako rolls away)", 80)
	if _snap.has_method("defeat"):
		_snap.call("defeat", "stomp", _snap.global_position + Vector3(0, 3, 0))
	for e in _reinf:
		if is_instance_valid(e) and not _dead(e) and e.has_method("defeat"):
			e.call("defeat", "slam", e.global_position + Vector3(0, 2, 0))
	print("[W3] sergeant snap defeated")
	ObjSvc.burst(get_parent(), DRUM + Vector3(0, 1.4, 0), Color(1.0, 0.85, 0.4), 50, 8.0, 0.2, -6.0, 1.0)
	give_reward()


func _on_squad_down(_e: Node) -> void:
	var left := 0
	for e in _squad:
		if is_instance_valid(e) and not _dead(e):
			left += 1
	print("[W3] fort squad left=%d" % left)
	if left <= 0 and phase == 1:
		_enter_phase(2)


# ------------------------------------------------------------------ SLAM ring on the drumskin

func _build_slam_ring() -> void:
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.05
	tm.outer_radius = 1.3
	tm.rings = 32
	tm.ring_segments = 8
	_ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.72, 0.2, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = m
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring.global_position = DRUM + Vector3(0, 1.08, 0)
	_ring.scale = Vector3(1, 0.35, 1)
	var lb := Label3D.new()
	lb.name = "SlamLabel"
	lb.text = "SLAM!"
	lb.font_size = 96
	lb.outline_size = 18
	lb.modulate = Color(1.0, 0.8, 0.3)
	lb.outline_modulate = Color(0.35, 0.12, 0.05)
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.pixel_size = 0.006
	lb.no_depth_test = false
	_ring.add_child(lb)
	lb.position = Vector3(0, 3.6, 0)


func _set_ring(on: bool) -> void:
	if _ring:
		_ring.visible = on


func _ring_step(delta: float) -> void:
	if _ring == null or not _ring.visible:
		return
	_ring_t += delta
	var s := 1.0 + 0.12 * sin(_ring_t * TAU * 1.6)
	_ring.scale = Vector3(s, 0.35, s)

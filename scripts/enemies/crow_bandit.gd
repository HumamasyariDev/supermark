class_name CrowBandit
extends EnemyBase
## Crow Bandit: a masked crow that perches, cackles, then dive-bombs Mak along a committed line,
## recovering low and slow (the punch window). Steals acorns on a hit. Defeat: feather burst.

const INK := Color(0.17, 0.18, 0.27)
const INK_LIGHT := Color(0.42, 0.45, 0.6)
const BEAK := Color(1.0, 0.62, 0.15)
const SCARF := Color(0.86, 0.18, 0.22)

@export var dive_speed: float = 11.0
## Boss minions skip perching and attack straight away.
@export var aggressive: bool = false

var stolen: int = 0
var dive_from: Vector3
var dive_to: Vector3
var dive_dir: Vector3
var _marker: MeshInstance3D
var _caw_t: float = 2.0
var _loot: Node3D
var _ground_y: float = 0.0
var _flap_prev: float = 0.0
var _cackle_t: float = 0.0
var _flap_phase: float = 0.0
var _gag_y0: float = 0.0
var _gag_ground: float = 0.0
var _dive_locked: bool = false
var _gloat_dir: Vector3 = Vector3.ZERO
## Seconds into "return" during which a hit still knocks the loot loose (after a gloat).
var _loot_live_t: float = 0.0
## Wing fold angle for the generated rig (verified on pose sheets; flip the sign here if a rig differs).
const FOLD := 1.25


## Plain defaults in _init so builder values survive (r1 blocker).
func _init() -> void:
	enemy_id = "crow_bandit"
	# Crow: a quick ruffle-up, little height.
	notice_hop = 0.12
	notice_stretch = 0.14
	notice_len = 0.32
	display_name = "Crow Bandit"
	uses_gravity = false
	body_radius = 0.3
	body_height = 0.75
	head_height = 0.8
	notice_radius = 10.0
	lose_radius = 18.0
	acorns_on_defeat = 1
	windup_len = 0.85
	rim_power = 4.0
	outline_width = 1.0


func _setup() -> void:
	_caw_t = _rng.randf_range(1.0, 3.0)


func _build_placeholder(root: Node3D) -> void:
	var body := EnemyKit.pivot(root, "body", Vector3(0, 0.34, 0))
	EnemyKit.ball(body, 0.28, INK, Vector3.ZERO, Vector3(1.0, 1.05, 1.15))
	EnemyKit.ball(body, 0.2, INK_LIGHT, Vector3(0, -0.04, -0.13), Vector3(1, 1.1, 0.7))
	EnemyKit.cone(body, 0.16, 0.18, SCARF, Vector3(0, 0.17, -0.12), Vector3(-160, 0, 0))
	var head := EnemyKit.pivot(body, "head", Vector3(0, 0.3, -0.06))
	head.set_meta("skin", INK)
	EnemyKit.ball(head, 0.21, INK, Vector3.ZERO)
	EnemyKit.ball(head, 0.07, INK, Vector3(0, 0.2, 0.02), Vector3(0.6, 1.4, 0.6))
	EnemyKit.ball(head, 0.06, INK, Vector3(0.05, 0.19, 0.06), Vector3(0.6, 1.2, 0.6))
	var beak := EnemyKit.cone(head, 0.085, 0.26, BEAK, Vector3(0, -0.04, -0.27), Vector3(-90, 0, 0))
	beak.name = "beak"
	EnemyKit.cone(head, 0.06, 0.12, Color(0.85, 0.45, 0.1), Vector3(0, -0.09, -0.21), Vector3(-100, 0, 0))
	# Robber mask across the eyes.
	EnemyKit.capsule(head, 0.07, 0.48, Color(0.05, 0.05, 0.07), Vector3(0, 0.05, -0.12), Vector3(0, 0, 90), Vector3(1, 1, 0.9))
	EnemyKit.face(head, Vector3(0, 0.05, -0.17), 0.085, 0.07, Color(0.75, 0.22, 0.12), "smug")
	for side in [-1.0, 1.0]:
		var wing := EnemyKit.pivot(body, "wing_l" if side < 0 else "wing_r", Vector3(0.24 * side, 0.06, 0.02))
		EnemyKit.ball(wing, 0.22, INK, Vector3(0.2 * side, -0.02, 0.04), Vector3(1.3, 0.3, 0.8))
		EnemyKit.ball(wing, 0.12, INK_LIGHT, Vector3(0.38 * side, -0.03, 0.1), Vector3(1.2, 0.25, 0.7))
		var leg := EnemyKit.pivot(root, "leg_l" if side < 0 else "leg_r", Vector3(0.09 * side, 0.12, 0))
		EnemyKit.cylinder(leg, 0.025, 0.025, 0.14, BEAK, Vector3(0, -0.06, 0))
		EnemyKit.ball(leg, 0.05, BEAK, Vector3(0, -0.12, -0.03), Vector3(1, 0.4, 1.5))
	var tail := EnemyKit.pivot(body, "tail", Vector3(0, -0.06, 0.25))
	for i in 3:
		EnemyKit.ball(tail, 0.08, INK, Vector3((float(i) - 1.0) * 0.07, 0, 0.12), Vector3(0.6, 0.25, 1.8), "", Vector3(0, (float(i) - 1.0) * 18.0, 0))
	# Loot sack on the back.
	EnemyKit.ball(body, 0.12, Color(0.66, 0.5, 0.3), Vector3(0.0, 0.12, 0.26), Vector3(1, 1.1, 1))
	EnemyKit.cylinder(body, 0.03, 0.05, 0.06, Color(0.5, 0.35, 0.2), Vector3(0, 0.25, 0.26))
	_loot = EnemyKit.pivot(head, "loot", Vector3(0, -0.06, -0.38))
	EnemyKit.ball(_loot, 0.07, Color(0.62, 0.36, 0.16), Vector3.ZERO, Vector3(1, 1.2, 1))
	EnemyKit.ball(_loot, 0.075, Color(0.4, 0.24, 0.1), Vector3(0, 0.05, 0), Vector3(1, 0.5, 1))
	_loot.visible = false


func _initial_state() -> String:
	return "perch"


func _build_visual() -> void:
	super._build_visual()
	# Measured to the 0.75 m spec like the grenadiers (the Tripo crow is 0.9 m: +20 % over spec, r1 visual major).
	if mesh_root != null:
		var h := _mesh_height(mesh_root)
		var sc := clampf(0.75 / h, 0.6, 1.2) if h > 0.2 else 1.0
		visual.scale = Vector3.ONE * sc
		_visual_scale_want = sc
	# The stolen-acorn prop must show on the generated mesh too: hang it on the rig at beak height.
	if mesh_root != null and _loot != null:
		_loot.get_parent().remove_child(_loot)
		rig.add_child(_loot)
		_loot.position = Vector3(0, 0.62, -0.42)
		# The stolen acorn is the real pickup model, not a placeholder ball.
		var ap := "res://assets/props/pickups/acorn_v2/acorn_v2.glb"
		if not ResourceLoader.exists(ap):
			ap = "res://assets/props/pickups/acorn/acorn.glb"
		if ResourceLoader.exists(ap):
			for c in _loot.get_children():
				c.queue_free()
			var ac := (load(ap) as PackedScene).instantiate() as Node3D
			_loot.add_child(ac)
			EnemyKit.fit_height(ac, 0.17)
			ac.rotation_degrees = Vector3(20, 0, 15)
		for mi in _loot.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = null


func _mesh_height(root: Node3D) -> float:
	var lo := INF
	var hi := -INF
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := inv * m.global_transform if m.is_inside_tree() else m.transform
		var bb := xf * m.get_aabb()
		lo = minf(lo, bb.position.y)
		hi = maxf(hi, bb.end.y)
	return hi - lo if hi > lo else 0.0


func _ground_below(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.5, 0), p + Vector3(0, -40, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else p.y - 3.0


func fly_to(target: Vector3, speed: float, delta: float, accel: float = 20.0) -> float:
	var d := target - global_position
	var want := d.normalized() * minf(speed, d.length() * 3.0) if d.length() > 0.01 else Vector3.ZERO
	velocity = velocity.move_toward(want, accel * delta)
	return d.length()


func _ai(delta: float) -> void:
	match state:
		"perch":
			fly_to(home, 3.0, delta)
			if player != null:
				face_toward(player_pos(), delta, 3.0)
			_caw_t -= delta
			if _caw_t <= 0.0:
				_caw_t = _rng.randf_range(2.5, 5.0)
				say("Caw caw!", Color(0.85, 0.9, 1.0), 56)
				EnemyKit.sfx(self, "crow_caw", global_position)
				_cackle_t = 0.7
			var r := 60.0 if aggressive else notice_radius
			if player != null and (aggressive or sees_player(r)) and dist_to_player() < r and player_pos().y < global_position.y + 1.0:
				notice_player("!", "crow_cackle")
				_cackle_t = 0.8
		"notice":
			fly_to(home, 2.0, delta)
			face_toward(player_pos(), delta, 10.0)
			# Attack token: crow pairs no longer dive on the same frame; a refused crow keeps flapping, ready.
			if state_time > 0.5 and request_attack():
				set_state("windup")
		"windup":
			fly_to(home + Vector3(0, 1.0, 0), 4.0, delta)
			if not _dive_locked:
				face_toward(player_pos(), delta, 10.0)
			if player != null and not _dive_locked:
				dive_to = player_pos()
				dive_to.y = _ground_below(dive_to) + 0.75
				if _marker == null:
					_marker = EnemyKit.ground_disc(get_parent(), Vector3(dive_to.x, dive_to.y - 0.75, dive_to.z), 0.9)
				else:
					_marker.global_position = Vector3(dive_to.x, dive_to.y - 0.71, dive_to.z)
			if not _dive_locked and state_time > windup_len - 0.3:
				# Lock-on 0.3 s before the dive: the disc stops following, flashes and tightens, a tick plays, so the
				# dive is a committed line, not a homing missile (r1 fun minor).
				_dive_locked = true
				if _marker != null:
					var mk := _marker
					var tw := mk.create_tween()
					tw.tween_property(mk, "scale", mk.scale * 0.72, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					EnemyKit.ground_ring(get_parent(), mk.global_position, 0.7, Color(1, 0.85, 0.5, 0.9), 0.25)
				EnemyKit.sfx(self, "lance_ready", dive_to, 1.6, -6.0)
				face_toward(dive_to, 1.0, 60.0)
			if state_time > windup_len:
				if player != null:
					dive_from = global_position
					dive_dir = (dive_to - dive_from).normalized()
					# Travel after the lock takes at least 0.45 s even from a low perch.
					dive_speed = clampf(dive_from.distance_to(dive_to) / 0.45, 6.0, 11.0)
					set_state("attack")
				else:
					set_state("return")
		"attack":
			velocity = dive_dir * dive_speed
			face_dir_instant(dive_dir)
			var past := (global_position - dive_to).dot(dive_dir)
			if past > 2.5 or is_on_floor() or is_on_wall() or state_time > 2.5:
				set_state("recover")
		"recover":
			_ground_y = _ground_below(global_position)
			var flat := Vector3(dive_dir.x, 0, dive_dir.z).normalized()
			var tgt := global_position + flat * 2.0
			tgt.y = _ground_y + 0.8
			fly_to(tgt, 2.5, delta, 18.0)
			if state_time > 1.6:
				set_state("return")
		"gloat":
			# After a steal: hover 1.2 m up, dangle the acorn, cackle and drift away slowly with the hurtbox live,
			# so the punish window survives a successful dive (r1 fun major: it flew straight back to its perch).
			var gy := _ground_below(global_position) + 1.2
			var tgt := global_position + _gloat_dir * 3.0 * 0.4
			tgt.y = gy
			fly_to(tgt, 3.0, delta, 12.0)
			if player != null:
				face_toward(player_pos(), delta, 6.0)
			if state_time > 1.4:
				_loot_live_t = 1.5
				set_state("return")
		"return":
			_loot_live_t = maxf(0.0, _loot_live_t - delta)
			var slow := prev_state == "gloat" or _loot_live_t > 0.0
			var d := fly_to(home, 4.0 if (slow or state_time < 1.0) else 6.0, delta, 10.0)
			face_toward(home, delta, 5.0)
			if state_time > 3.0 and d > 0.2:
				# Finish pass (encounter r1 major: W1 crow CB1 hit its own roof and sat in "return" for 27 s: its
				# perch point is inside the roof collider, so it could never get within 0.2 m). After 3 s, near
				# enough counts as home; after 5 s it settles on the perch point.
				if d < 1.6 or state_time > 5.0:
					global_position = home
					velocity = Vector3.ZERO
					d = 0.0
			if d < 0.2:
				set_state("perch")


func _on_enter_state(s: String) -> void:
	if s == "windup":
		_dive_locked = false
	if s != "windup" and _marker != null:
		EnemyKit.fade_free(_marker)
		_marker = null
	if s == "gloat":
		say("Yoink!", Color(1, 0.85, 0.3), 80)
		_cackle_t = 1.2
		EnemyKit.sfx(self, "crow_cackle", global_position)
	if s == "attack":
		moment_sfx("enemy_attack", "crow_dive")
		say("CAAAW!", Color(1, 0.6, 0.4), 70)
		_cackle_t = 0.5
	if s == "recover":
		EnemyKit.fx(get_parent(), "DustPuff", Vector3(global_position.x, _ground_below(global_position) + 0.05, global_position.z), 0.6)
	if s == "recover":
		kick_squash(0.3)


func _contact_active() -> bool:
	return state == "attack" or windup_hot()


func _after_hurt_state() -> String:
	return "return"


func _hurt_process(delta: float) -> void:
	velocity = velocity.move_toward(Vector3.ZERO, 12.0 * delta)
	velocity += knockback * 0.2
	knockback = knockback.move_toward(Vector3.ZERO, 14.0 * delta)
	if state_time > 0.55:
		set_state(_after_hurt_state())


func _on_hurt_player(p: Node3D) -> void:
	var have: Variant = EnemyKit.game_get(self, "acorns", 0)
	var n := mini(3, int(have))
	if n > 0:
		EnemyKit.game_call(self, "spend_acorns", [n])
		stolen += n
		_loot.visible = true
		EnemyKit.sfx(self, "crow_steal", global_position)
	_gloat_dir = flat_dir_to(p.global_position) * -1.0 if p != null else -forward()
	set_state("gloat")


func _animate(delta: float) -> void:
	var t := _anim_t
	bob = 0.0
	lean = 0.0
	tilt = 0.0
	spin = 0.0
	_cackle_t = maxf(0.0, _cackle_t - delta)
	var flap_rate := 16.0
	var wing_amp := 0.9
	var fold := 0.0
	var head := Vector3.ZERO
	var hv := Vector2(velocity.x, velocity.z).length()
	# Flight posture follows horizontal speed: the body pitches forward like a bird, legs tuck back along it
	# (the upright "person flapping its arms" read of r1). Upright only while hovering in the wind-up.
	var flight_lean := clampf(hv * 0.14, 0.0, 0.95)
	var legs := Vector3(-0.9, 0, 0)
	var stroke_bias := 0.6
	match state:
		"perch":
			# Perched bandit: wings tucked, head darting around, tail flicks, a shifty weight shift.
			wing_amp = 0.0
			fold = FOLD
			stroke_bias = 0.0
			bob = sin(t * 3.0) * 0.015
			tilt = sin(t * 0.7) * 0.05
			var dart := floorf(t * 0.8)
			head = Vector3(0, sin(dart * 2.7) * 0.6, sin(dart * 1.3) * 0.2)
			legs = Vector3.ZERO
			pose("tail", Vector3(maxf(0.0, sin(t * 2.6)) * 0.35, 0, 0))
		"notice":
			# Startled take-off: wings flare wide and beat fast, head snaps to Mak.
			wing_amp = 0.85
			flap_rate = 22.0
			fold = FOLD * 0.2
			head = Vector3(head_pitch_to_player(0.1), 0, 0)
			lean = maxf(flight_lean, 0.15)
			legs = Vector3(-0.5, 0, 0)
		"windup":
			# Rears back, wings high and wide, flapping hard: the dive is coming.
			wing_amp = 1.0
			flap_rate = 20.0
			lean = -0.35
			head = Vector3(head_pitch_to_player(0.0), 0, 0)
			legs = Vector3(-0.8, 0, 0)
		"attack":
			wing_amp = 0.0
			lean = 0.75
			head = Vector3(-0.35, 0, 0)
			legs = Vector3(1.4, 0, 0)
		"recover":
			wing_amp = 0.7
			flap_rate = 9.0
			lean = maxf(flight_lean, 0.3)
			tilt = sin(t * 5.0) * 0.15
			head = Vector3(0, sin(t * 3.0) * 0.3, 0)
		"return":
			wing_amp = 0.9
			flap_rate = 17.0
			lean = maxf(flight_lean, 0.35)
		"gloat":
			# Hovering taunt: upright, a lazy wide flap, rocking side to side, the loot dangling from the beak.
			wing_amp = 0.8
			flap_rate = 11.0
			lean = -0.1
			tilt = sin(t * 3.0) * 0.18
			head = Vector3(0.15 + sin(t * 6.0) * 0.08, sin(t * 2.0) * 0.25, 0)
			legs = Vector3(-0.3, 0, 0)
			if _loot != null:
				_loot.rotation = Vector3(sin(t * 7.0) * 0.4, 0, sin(t * 5.0) * 0.3)
		"hurt":
			wing_amp = 1.0
			flap_rate = 26.0
			tilt = sin(t * 30.0) * 0.4
			head = Vector3(0.4, 0, 0)
	# Asymmetric beat: fast downstroke, slow upstroke; the stroke is biased up so it spans about +50 to -35 degrees.
	_flap_phase += flap_rate * delta
	var flap := sin(_flap_phase - 0.45 * sin(_flap_phase))
	if state == "attack":
		# Dive: wings swept back like a dart.
		pose_snap("wing_l", Vector3(0.5, 0.9, -0.5), 30.0)
		pose_snap("wing_r", Vector3(0.5, -0.9, 0.5), 30.0)
		pose("forearm_l", Vector3(0, 0.5, 0))
		pose("forearm_r", Vector3(0, -0.5, 0))
	else:
		# Positive roll on the left wing lowers it on this rig (verified: *__wingsign_test_crow.png).
		pose("wing_l", Vector3(0, 0, fold - stroke_bias * minf(wing_amp, 1.0)))
		pose("wing_r", Vector3(0, 0, -fold + stroke_bias * minf(wing_amp, 1.0)))
		pose("forearm_l", Vector3(0, 0, fold * 0.35))
		pose("forearm_r", Vector3(0, 0, -fold * 0.35))
		pose_cycle("wing_l", Vector3(0, 0, -flap * wing_amp))
		pose_cycle("wing_r", Vector3(0, 0, flap * wing_amp))
		# The hand lags the arm a little (wing-tip whip).
		var lag := sin(_flap_phase - 0.6 - 0.45 * sin(_flap_phase - 0.6))
		pose_cycle("forearm_l", Vector3(0, 0, -lag * wing_amp * 0.45))
		pose_cycle("forearm_r", Vector3(0, 0, lag * wing_amp * 0.45))
		bob += -flap * wing_amp * 0.05
		# A soft wing-beat sound on each downstroke while flying.
		if wing_amp > 0.4 and _flap_prev > 0.0 and flap <= 0.0:
			EnemyKit.sfx(self, "enemy_flap", global_position, 1.0 + _rng.randf() * 0.1)
	_flap_prev = flap
	# Beak clacks while cackling.
	var beak := 0.0
	if _cackle_t > 0.0:
		beak = maxf(0.0, sin(t * 28.0)) * 0.22
		pose_cycle("head", Vector3(sin(t * 14.0) * 0.08, 0, 0))
	# The head counters the body pitch so the crow keeps looking where it flies.
	pose("head", head + Vector3(lean * 0.6 if state != "attack" else 0.0, 0, 0))
	pose("beak", Vector3(beak, 0, 0))
	pose("leg_l", legs)
	pose("leg_r", legs)
	if state != "perch":
		pose("tail", Vector3(-lean * 0.4, 0, -tilt * 0.6))


func _defeat_gag(_kind: String, _from_position: Vector3) -> float:
	# Freeze-stretch squawk (0.12 s), plucked tumble to the ground (to 0.7 s), then sits dazed in its feathers
	# until 1.15 s; the small poof comes after the hold (r1: the 0.45 s gag hid behind a poof twice its size).
	velocity = Vector3.ZERO
	say_side("Squawk!", Color(1, 0.8, 0.8), 80)
	moment_sfx("enemy_defeat", "crow_hurt")
	if not owns("enemy_defeat") and EnemyKit.fx(get_parent(), "FeatherBurst", global_position + Vector3(0, 0.4, 0), 0.6) == null:
		EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.4, 0), "feathers", [INK, INK_LIGHT], 20, 3.5)
	acorns_on_defeat = 1 + stolen
	_gag_y0 = global_position.y
	var g := floor_y_at(global_position, 0.3, 30.0)
	_gag_ground = g if not is_nan(g) else global_position.y - 0.5
	return 1.15


func _defeat_process(delta: float) -> void:
	var t := _anim_t
	if state_time < 0.12:
		scale_mult = Vector3(0.85, 1.25, 0.85)
		rig.scale = scale_mult
		pose_snap("wing_l", Vector3(0, 0, -1.2))
		pose_snap("wing_r", Vector3(0, 0, 1.2))
		pose_snap("beak", Vector3(0.45, 0, 0))
		pose_snap("head", Vector3(0.5, 0, 0))
		pose_snap("leg_l", Vector3(0.6, 0, 0))
		pose_snap("leg_r", Vector3(0.6, 0, 0))
		return
	if state_time < 0.7:
		scale_mult = Vector3.ONE
		rig.scale = Vector3.ONE
		var u := (state_time - 0.12) / 0.58
		global_position.y = lerpf(_gag_y0, _gag_ground + 0.02, u * u)
		spin += delta * 14.0 * (1.0 - u)
		tilt = sin(u * PI * 3.0) * 0.5
		pose("wing_l", Vector3(0, 0, -0.6))
		pose("wing_r", Vector3(0, 0, 0.6))
		pose_cycle("wing_l", Vector3(0, 0, sin(t * 30.0) * 0.6))
		pose_cycle("wing_r", Vector3(0, 0, -sin(t * 30.0) * 0.6))
		pose("head", Vector3(0.5, 0, 0))
		pose_cycle("head", Vector3(0, sin(t * 20.0) * 0.4, 0))
		pose("beak", Vector3(0.25, 0, 0))
		if fmod(state_time, 0.2) < delta:
			# Feather trickle while it tumbles: the VFX track's leaf-shaped feathers (the CPU quads read as glitchy
			# dark rectangles in the impl3 reel).
			if EnemyKit.fx(get_parent(), "FeatherBurst", global_position + Vector3(0, 0.35, 0), 0.25) == null:
				EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.35, 0), "feathers", [INK, INK_LIGHT], 4, 1.5)
		return
	# Dazed on the ground: plopped down, legs out, wings drooped, head wobbling, beak hanging open.
	if not has_meta("plopped"):
		set_meta("plopped", true)
		global_position.y = _gag_ground + 0.02
		kick_squash(0.55)
		EnemyKit.sfx(self, "enemy_land", global_position, 1.3, -6.0)
		EnemyKit.fx(get_parent(), "DustPuff", global_position, 0.4)
		if not owns("enemy_stunned"):
			EnemyKit.burst(get_parent(), global_position + Vector3(0, head_height + 0.15, 0), "stars", [Color(1, 0.95, 0.4)], 6, 1.5)
		juice("enemy_stunned", {}, global_position + Vector3(0, head_height * 0.8, 0))
	spin = lerp_angle(spin, 0.0, 1.0 - exp(-8.0 * delta))
	tilt = sin(t * 5.0) * 0.12
	lean = -0.25
	pose("wing_l", Vector3(0, 0, 1.4))
	pose("wing_r", Vector3(0, 0, -1.4))
	pose("leg_l", Vector3(1.2, 0, 0.3))
	pose("leg_r", Vector3(1.2, 0, -0.3))
	pose("head", Vector3(0.1, 0, 0))
	pose_cycle("head", Vector3(sin(t * 4.0) * 0.2, sin(t * 3.0) * 0.4, sin(t * 5.0) * 0.2))
	pose("beak", Vector3(0.3, 0, 0))


func _defeat_burst() -> void:
	if owns("enemy_flee"):
		return
	if EnemyKit.fx(get_parent(), "FeatherBurst", global_position + Vector3(0, 0.4, 0), 1.2) == null:
		EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.4, 0), "feathers", [INK, INK_LIGHT, SCARF], 40, 5.0)

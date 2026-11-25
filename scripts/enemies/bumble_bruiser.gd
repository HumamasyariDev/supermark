class_name BumbleBruiser
extends EnemyBase
## Bumble Bruiser: a chubby bumblebee in a leather flight helmet. Hovers and buzzes, lines up
## (ground arrow telegraph), then charges in a straight line. A wall hit leaves it dizzy on the
## ground; a miss leaves it braking and wobbly. Counter: dodge, then stomp or punch while dizzy.
## Defeat: spirals down and lands on its back.

const YELLOW := Color(1.0, 0.78, 0.16)
const STRIPE := Color(0.14, 0.11, 0.1)
const LEATHER := Color(0.5, 0.3, 0.16)
const GLASS := Color(0.6, 0.85, 1.0, 0.75)

@export var hover_height: float = 1.4
@export var charge_speed: float = 13.0
@export var charge_time: float = 1.0

var charge_dir: Vector3 = Vector3.FORWARD
var _strip: Node3D
var _buzz_t: float = 0.0
var _stars: Node3D
var _buzz: AudioStreamPlayer3D
var _wing_mat: StandardMaterial3D
var _pump_t: float = 0.0
var _dizzy_len: float = 3.0


## Plain defaults in _init so builder values survive (r1 blocker).
func _init() -> void:
	enemy_id = "bumble_bruiser"
	# Flyer: a bob up in the air.
	notice_hop = 0.18
	notice_stretch = 0.1
	notice_len = 0.45
	display_name = "Bumble Bruiser"
	uses_gravity = false
	body_radius = 0.4
	body_height = 0.9
	head_height = 0.95
	notice_radius = 10.0
	lose_radius = 18.0
	acorns_on_defeat = 2
	windup_len = 1.0
	rim_power = 3.0


func _setup() -> void:
	# Rigged v2 (Blender, enemies track): spine, head, arm_l/r, leg_l/r, wing_l/r, stinger.
	if mesh_path == "" and ResourceLoader.exists("res://assets/enemies/bumble_bruiser/bumble_bruiser_v2.glb"):
		mesh_path = "res://assets/enemies/bumble_bruiser/bumble_bruiser_v2.glb"


func _on_mesh_ready(inst: Node) -> void:
	# Translucent, slightly iridescent wings (the generated wings are opaque pale blue).
	for mi in inst.find_children("wing*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if _wing_mat == null:
			var src := m.get_active_material(0) as StandardMaterial3D
			_wing_mat = (src.duplicate() as StandardMaterial3D) if src != null else StandardMaterial3D.new()
			_wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_wing_mat.albedo_color = Color(0.9, 0.97, 1.0, 0.62)
			_wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_wing_mat.roughness = 0.08
			_wing_mat.metallic_specular = 0.9
			_wing_mat.rim_enabled = true
			_wing_mat.rim = 0.9
			_wing_mat.rim_tint = 0.1
			_wing_mat.emission_enabled = true
			_wing_mat.emission = Color(0.55, 0.75, 1.0)
			_wing_mat.emission_energy_multiplier = 0.45
			_wing_mat.render_priority = 1
		m.material_override = _wing_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Looping wing buzz on its own 3D player; pitch follows the state.
	if _buzz == null and ResourceLoader.exists("res://assets/audio/sfx/bee_buzz.ogg"):
		var st := load("res://assets/audio/sfx/bee_buzz.ogg") as AudioStream
		if st != null:
			st = st.duplicate() as AudioStream
			if st is AudioStreamOggVorbis:
				(st as AudioStreamOggVorbis).loop = true
			_buzz = AudioStreamPlayer3D.new()
			_buzz.name = "Buzz"
			_buzz.stream = st
			_buzz.bus = "SFX"
			_buzz.volume_db = -11.0
			_buzz.unit_size = 4.0
			_buzz.max_distance = 28.0
			_buzz.autoplay = true
			add_child(_buzz)


func _build_placeholder(root: Node3D) -> void:
	var body := EnemyKit.pivot(root, "body", Vector3(0, 0.42, 0.05))
	EnemyKit.ball(body, 0.38, YELLOW, Vector3.ZERO, Vector3(1.0, 0.95, 1.1))
	EnemyKit.ring(body, 0.3, 0.4, STRIPE, Vector3(0, 0, 0.05), Vector3(90, 0, 0)).scale = Vector3(0.98, 1.0, 0.92)
	EnemyKit.ring(body, 0.22, 0.32, STRIPE, Vector3(0, 0, 0.24), Vector3(90, 0, 0))
	EnemyKit.cone(body, 0.08, 0.22, STRIPE, Vector3(0, -0.02, 0.48), Vector3(90, 0, 0))
	EnemyKit.ball(body, 0.2, Color(1.0, 0.9, 0.55), Vector3(0, -0.08, -0.22), Vector3(1.1, 1, 0.6))
	var head := EnemyKit.pivot(body, "head", Vector3(0, 0.28, -0.26))
	head.set_meta("skin", YELLOW)
	EnemyKit.ball(head, 0.27, YELLOW, Vector3.ZERO, Vector3(1.05, 0.95, 1.0))
	# Leather flight helmet with ear flaps and goggles pushed up.
	EnemyKit.ball(head, 0.285, LEATHER, Vector3(0, 0.07, 0.03), Vector3(1.03, 0.8, 1.03))
	for side in [-1.0, 1.0]:
		EnemyKit.ball(head, 0.09, LEATHER, Vector3(0.25 * side, -0.07, 0.0), Vector3(0.5, 1.2, 0.9))
		EnemyKit.ring(head, 0.06, 0.09, Color(0.75, 0.6, 0.3), Vector3(0.1 * side, 0.22, -0.18), Vector3(70, 0, 0))
		var g := EnemyKit.ball(head, 0.065, GLASS, Vector3(0.1 * side, 0.22, -0.19), Vector3(1, 1, 0.5), "", Vector3(-20, 0, 0))
		g.material_override = EnemyKit.mat(GLASS, 0.05, 0.6, 0.2)
		var ant := EnemyKit.cylinder(head, 0.012, 0.015, 0.22, STRIPE, Vector3(0.08 * side, 0.36, 0.0), Vector3(-20, 0, -20 * side))
		ant.name = "antenna"
		EnemyKit.ball(head, 0.035, STRIPE, Vector3(0.12 * side, 0.46, 0.04))
	EnemyKit.ring(head, 0.27, 0.31, Color(0.75, 0.6, 0.3), Vector3(0, 0.22, -0.18), Vector3(70, 0, 0)).scale = Vector3(0.25, 1, 0.4)
	EnemyKit.face(head, Vector3(0, 0.0, -0.22), 0.1, 0.08, Color(0.35, 0.2, 0.1), "angry")
	EnemyKit.mouth(head, Vector3(0, -0.15, -0.23), 0.16, "toothy")
	for side in [-1.0, 1.0]:
		var wing := EnemyKit.pivot(body, "wing_l" if side < 0 else "wing_r", Vector3(0.14 * side, 0.32, 0.08))
		var w := EnemyKit.ball(wing, 0.24, Color(1, 1, 1, 0.45), Vector3(0.2 * side, 0.12, 0.05), Vector3(1.3, 0.12, 0.7), "", Vector3(0, 0, 25 * side))
		w.material_override = EnemyKit.mat(Color(0.92, 0.97, 1.0, 0.45), 0.1, 0.8)
		var arm := EnemyKit.pivot(body, "arm_l" if side < 0 else "arm_r", Vector3(0.32 * side, -0.02, -0.15))
		EnemyKit.capsule(arm, 0.05, 0.2, STRIPE, Vector3(0.04 * side, -0.06, 0), Vector3(0, 0, 30 * side))
		EnemyKit.ball(arm, 0.09, Color(0.85, 0.2, 0.18), Vector3(0.08 * side, -0.15, -0.04))
		var leg := EnemyKit.pivot(body, "leg_l" if side < 0 else "leg_r", Vector3(0.14 * side, -0.32, 0.05))
		EnemyKit.capsule(leg, 0.045, 0.2, STRIPE, Vector3(0, -0.08, 0))


func _initial_state() -> String:
	return "hover"


func _hover_point() -> Vector3:
	var t := Time.get_ticks_msec() / 1000.0
	return home + Vector3(sin(t * 0.7) * 1.2, hover_height + sin(t * 2.3) * 0.15, sin(t * 1.4) * 0.6)


func fly_to(target: Vector3, speed: float, delta: float, accel: float = 16.0) -> float:
	var d := target - global_position
	var want := d.normalized() * minf(speed, d.length() * 3.0) if d.length() > 0.01 else Vector3.ZERO
	velocity = velocity.move_toward(want, accel * delta)
	return d.length()


func _ai(delta: float) -> void:
	_update_buzz(delta)
	match state:
		"hover":
			fly_to(_hover_point(), 2.5, delta)
			if player != null:
				face_toward(player_pos(), delta, 3.0)
			# Finish pass (encounter r1 major: W2 bees with notice radius 0 hovered inert within punching reach for
			# 30 s). A dormant bee still wakes when Mak comes within 2.5 m.
			if sees_player() or (notice_radius <= 0.0 and player != null and ai_enabled and sees_player(2.5)):
				notice_player("!", "")
		"notice":
			velocity = velocity.move_toward(Vector3.ZERO, 10.0 * delta)
			face_toward(player_pos(), delta, 10.0)
			# Attack token: refused bees keep shadow-boxing in place and ask again.
			if state_time > 0.5 and request_attack():
				set_state("windup")
		"windup":
			if state_time < 0.55:
				face_toward(player_pos(), delta, 12.0)
				charge_dir = forward()
				# Drop to Mak's chest height so the charge line actually meets him.
				var line_y := player_pos().y + 0.3 if player != null else global_position.y
				var tgt := global_position - charge_dir * 0.6
				tgt.y = line_y
				fly_to(tgt, 3.0, delta, 24.0)
			else:
				velocity = velocity.move_toward(Vector3.ZERO, 20.0 * delta)
				if _strip == null:
					var ground := global_position
					ground.y = _ground_below(global_position)
					_strip = EnemyKit.ground_strip(get_parent(), ground + charge_dir * 0.5, charge_dir, charge_speed * charge_time, 0.8)
					say("BZZZT!", Color(1, 0.9, 0.3), 70)
			if state_time > 1.0:
				set_state("attack")
		"attack":
			velocity = charge_dir * charge_speed
			face_dir_instant(charge_dir)
			if get_slide_collision_count() > 0 and is_on_wall():
				_bonk()
			elif state_time > charge_time:
				set_state("recover")
			elif state_time > 0.12 and _void_ahead(charge_dir):
				# Island edge (W2 sky islands): a cartoon air-brake, then a 1.5 s teeter-dizzy over the lip, stompable,
				# so the designed answer "stomp it while dizzy" shows up on open islands too (r1 fun).
				velocity = Vector3(0, 1.5, 0)
				say("Whoa-whoa!", Color(1, 0.9, 0.5), 64)
				kick_squash(-0.45)
				EnemyKit.sfx(self, "enemy_skid", global_position, 1.4)
				_dizzy_len = 1.5
				set_state("dizzy")
		"recover":
			velocity = velocity.move_toward(Vector3.ZERO, 10.0 * delta)
			velocity.y = move_toward(velocity.y, -0.4, 4.0 * delta)
			if state_time > 1.3:
				set_state("hover")
		"dizzy":
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
			if not is_on_floor():
				velocity.y -= GRAVITY * delta
			else:
				velocity.y = 0.0
			if _stars != null:
				_stars.rotation.y += delta * 6.0
			if state_time > _dizzy_len:
				_dizzy_len = 3.0
				set_state("hover")


func _update_buzz(delta: float) -> void:
	if _buzz == null:
		return
	var want_pitch := 1.0
	var want_db := -11.0
	match state:
		"notice":
			want_pitch = 1.15
		"windup":
			want_pitch = 1.1 + state_time * 0.45
			want_db = -8.0
		"attack":
			want_pitch = 1.6
			want_db = -5.0
		"recover":
			want_pitch = 0.9
		"dizzy":
			want_pitch = 0.55 + sin(state_time * 6.0) * 0.08
			want_db = -17.0
	_buzz.pitch_scale = lerpf(_buzz.pitch_scale, want_pitch, 1.0 - exp(-8.0 * delta))
	_buzz.volume_db = lerpf(_buzz.volume_db, want_db, 1.0 - exp(-8.0 * delta))


## True when there is no walkable ground within 7 m below a point 1.3 m ahead along dir.
func _void_ahead(dir: Vector3) -> bool:
	var a := global_position + Vector3(dir.x, 0, dir.z).normalized() * 1.3 + Vector3(0, 0.4, 0)
	var q := PhysicsRayQueryParameters3D.create(a, a + Vector3(0, -7.0, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _ground_below(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3(0, -30, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else p.y - 1.4


func _bonk() -> void:
	set_state("dizzy")
	velocity = -charge_dir * 3.0 + Vector3.UP * 2.0
	kick_squash(0.8)
	moment_sfx("enemy_stunned", "enemy_bonk")
	say("BONK!", Color(1, 0.9, 0.4), 100)
	EnemyKit.burst(get_parent(), global_position + charge_dir * 0.4 + Vector3(0, 0.6, 0), "stars", [Color(1, 0.95, 0.4), Color(1, 1, 1)], 14, 4.0)


func _on_enter_state(s: String) -> void:
	if s == "attack" and _strip != null:
		EnemyKit.fade_free(_strip, charge_time)
		_strip = null
	elif s != "windup" and _strip != null:
		EnemyKit.fade_free(_strip)
		_strip = null
	if s != "dizzy" and prev_state == "dizzy":
		stunned(false)
	if s != "dizzy" and _stars != null:
		_stars.queue_free()
		_stars = null
	if s == "dizzy":
		stunned(true)
	if s == "dizzy" and not owns("enemy_stunned"):
		_stars = Node3D.new()
		add_child(_stars)
		_stars.position = Vector3(0, head_height + 0.25, 0)
		for i in 4:
			var a := TAU * float(i) / 4.0
			var st := EnemyKit.ball(_stars, 0.07, Color(1, 0.92, 0.3), Vector3(cos(a) * 0.35, 0, sin(a) * 0.35))
			st.material_override = EnemyKit.glow_mat(Color(1, 0.9, 0.3), 1.2)
	if s == "attack":
		moment_sfx("enemy_attack", "bee_charge")
		kick_squash(-0.3)


func _resolve_hit(kind: String, _from_position: Vector3) -> String:
	if state == "attack" and kind != "stomp" and kind != "slam":
		# Teach "sidestep the charge" instead of silently eating the punch (r1 fun).
		_block_text_once = "Too fast!"
		return "block"
	return "damage"


func _contact_active() -> bool:
	return state == "attack" or windup_hot()


func _contact_yields_to_attack() -> bool:
	return state != "attack"


## Jumping over the charge clears it (r1 fun major: hops at 0.5-1.3 m feet height still cost a slice).
func _vaultable() -> bool:
	return state == "attack"


func _after_hurt_state() -> String:
	return "dizzy" if is_on_floor() else "recover"


func _hurt_process(delta: float) -> void:
	velocity = velocity.move_toward(Vector3.ZERO, 12.0 * delta) + knockback * 0.15
	knockback = knockback.move_toward(Vector3.ZERO, 14.0 * delta)
	if state_time > 0.5:
		set_state(_after_hurt_state())


func _animate(delta: float) -> void:
	var t := _anim_t
	bob = sin(t * 4.0) * 0.05
	lean = 0.0
	tilt = sin(t * 2.0) * 0.06
	spin = 0.0
	var wing_speed := 62.0
	var wing_amp := 0.75
	# Shadow-boxing idle: little alternating jabs every couple of seconds (personality loop).
	_pump_t += delta
	var jab_on := 1.0 if fmod(_pump_t, 2.6) < 0.7 else 0.0
	var jab_l := maxf(0.0, sin(_pump_t * 9.0)) * jab_on
	var jab_r := maxf(0.0, -sin(_pump_t * 9.0)) * jab_on
	match state:
		"hover", "return":
			# Rig convention (impl3 arm tests): the gloves rest in front of the chest on short arms, +X lifts a glove
			# up and forward (about +0.4 is a straight jab at shoulder height), -X drops it; +Z on arm_l swings it out.
			# The old negative values pushed every jab down into the belly, so the boxer never visibly punched.
			pose("arm_l", Vector3(0.3, 0, 0.1))
			pose("arm_r", Vector3(0.3, 0, -0.1))
			pose_cycle("arm_l", Vector3(jab_l * 0.35, 0, -jab_l * 0.15))
			pose_cycle("arm_r", Vector3(jab_r * 0.35, 0, jab_r * 0.15))
			pose("head", Vector3(0, 0, 0))
			pose_cycle("head", Vector3(sin(t * 1.3) * 0.08, sin(t * 0.7) * 0.25, 0))
			pose_cycle("stinger", Vector3(sin(t * 5.0) * 0.18, 0, 0))
		"notice":
			lean = -0.2
			wing_speed = 75.0
			pose("head", Vector3(head_pitch_to_player(0.1), 0, 0))
			pose_snap("arm_l", Vector3(0.95, 0, 0.35), 30.0)
			pose_snap("arm_r", Vector3(0.95, 0, -0.35), 30.0)
		"windup":
			# Pull back, gloves up, stinger cocked: a clear "here it comes".
			var u := clampf(state_time / 1.0, 0.0, 1.0)
			lean = -0.35 * u
			wing_speed = 80.0 + 40.0 * u
			bob = sin(t * 30.0) * 0.015
			pose("arm_l", Vector3(1.05, 0, 0.45))
			pose("arm_r", Vector3(1.05, 0, -0.45))
			pose("head", Vector3(head_pitch_to_player(0.0) - 0.3 * u, 0, 0))
			pose("stinger", Vector3(-0.6 * u, 0, 0))
			pose("leg_l", Vector3(-0.5, 0, 0))
			pose("leg_r", Vector3(-0.5, 0, 0))
		"attack":
			# Charge: a shallow lean with the head up looking ahead, so the face stays visible; the lead glove punches
			# out straight, the trailing glove stays cocked by the cheek (the 0.6 lean hid face and glove, r1).
			lean = 0.3
			wing_speed = 95.0
			wing_amp = 0.55
			pose_snap("arm_l", Vector3(0.42, 0, -0.12))
			pose_snap("forearm_l", Vector3(0, 0, 0))
			pose("arm_r", Vector3(0.95, 0, -0.35))
			pose("forearm_r", Vector3(-1.2, 0, 0))
			pose("head", Vector3(0.22, 0, 0))
			pose("stinger", Vector3(0.5, 0, 0))
			pose("leg_l", Vector3(0.9, 0, 0))
			pose("leg_r", Vector3(0.9, 0, 0))
		"dizzy":
			# Seeing stars: guard dropped, gloves hanging, head lolling (no boxing stance while dazed).
			bob = 0.0
			wing_amp = 0.25
			wing_speed = 7.0
			tilt = sin(t * 5.0) * 0.3
			lean = -0.2
			pose("head", Vector3(0, 0, 0))
			pose_cycle("head", Vector3(sin(t * 3.0) * 0.2, sin(t * 4.0) * 0.4, sin(t * 3.0) * 0.3))
			pose("arm_l", Vector3(-0.6, 0, 0.7))
			pose("arm_r", Vector3(-0.6, 0, -0.7))
			pose("forearm_l", Vector3(0.3, 0, 0))
			pose("forearm_r", Vector3(0.3, 0, 0))
			pose_cycle("arm_l", Vector3(0, 0, sin(t * 4.0) * 0.2))
			pose_cycle("arm_r", Vector3(0, 0, -sin(t * 4.0) * 0.2))
			pose_cycle("stinger", Vector3(sin(t * 2.0) * 0.3, 0, 0))
		"recover":
			tilt = sin(t * 9.0) * 0.25
			wing_speed = 50.0
			pose("arm_l", Vector3(-0.35, 0, 0.5))
			pose("arm_r", Vector3(-0.35, 0, -0.5))
			pose("head", Vector3(0.15, 0, 0))
			pose_cycle("head", Vector3(0, sin(t * 6.0) * 0.3, 0))
		_:
			pose("arm_l", Vector3(0.3, 0, 0.1))
			pose("arm_r", Vector3(0.3, 0, -0.1))
	if state != "attack" and state != "dizzy":
		pose("forearm_l", Vector3.ZERO)
		pose("forearm_r", Vector3.ZERO)
	if state != "attack" and state != "windup":
		pose("leg_l", Vector3.ZERO)
		pose("leg_r", Vector3.ZERO)
		pose_cycle("leg_l", Vector3(sin(t * 6.0) * 0.3, 0, 0))
		pose_cycle("leg_r", Vector3(-sin(t * 6.0) * 0.3, 0, 0))
	# Wings: at 30 fps no sampled frame of a 13-19 Hz sine showed a wing (r1). Fast beats now alternate two fixed
	# extremes on frame parity (up 0.5 / down -0.3), which reads as a blur at any capture rate; wings are 1.25x.
	if wing_speed > 30.0:
		var up := (Engine.get_process_frames() % 2) == 0
		var a := 0.5 if up else -0.3
		pose_cycle("wing_l", Vector3(0.0, 0.0, -a), true)
		pose_cycle("wing_r", Vector3(0.0, 0.0, a), true)
	else:
		var f := sin(t * wing_speed) * wing_amp
		pose_cycle("wing_l", Vector3(0.0, 0.0, -f), true)
		pose_cycle("wing_r", Vector3(0.0, 0.0, f), true)
	pose("wing_l", Vector3.ZERO)
	pose("wing_r", Vector3.ZERO)
	if skeleton != null:
		for wn in ["wing_l", "wing_r"]:
			if bone_ids.has(wn):
				skeleton.set_bone_pose_scale(bone_ids[wn], Vector3.ONE * 1.25)


func _defeat_gag(_kind: String, _from_position: Vector3) -> float:
	say_side("Bzzz...ow", Color(1, 0.9, 0.5), 70)
	moment_sfx("enemy_defeat", "bee_down")
	if prev_state == "dizzy":
		stunned(false)
	if _buzz != null:
		var tw := _buzz.create_tween()
		tw.tween_property(_buzz, "pitch_scale", 0.35, 1.1)
		tw.parallel().tween_property(_buzz, "volume_db", -40.0, 1.2)
	velocity = Vector3(0, 2.0, 0)
	return 1.4


func _defeat_process(delta: float) -> void:
	var g := _ground_below(global_position + Vector3(0, 0.3, 0))
	if global_position.y > g + 0.05:
		# Dizzy spiral down: the body corkscrews on a shrinking circle while the wings sputter (fast, then failing),
		# head lolling and gloves limp (the wings froze in the r1 reels and the fall read as a dropped prop).
		velocity.y -= 9.0 * delta
		var st := state_time
		var circ := Vector3(cos(st * 9.0), 0, sin(st * 9.0)) * 1.4 * maxf(0.0, 1.0 - st / 1.1)
		global_position += (velocity + circ) * delta
		spin += delta * 10.0
		global_position.y = maxf(global_position.y, g)
		var fail := clampf(1.0 - st / 0.9, 0.15, 1.0)
		var flap := sin(_anim_t * lerpf(14.0, 55.0, fail)) * 0.6 * fail
		pose_cycle("wing_l", Vector3(0, 0, -flap), true)
		pose_cycle("wing_r", Vector3(0, 0, flap), true)
		pose("head", Vector3(0.2, 0, 0))
		pose_cycle("head", Vector3(0, sin(_anim_t * 7.0) * 0.4, sin(_anim_t * 5.0) * 0.3))
		pose("arm_l", Vector3(0.4, 0, 1.1))
		pose("arm_r", Vector3(0.4, 0, -1.1))
		pose_cycle("stinger", Vector3(sin(_anim_t * 11.0) * 0.4, 0, 0))
		tilt = sin(st * 9.0) * 0.35
	else:
		# Landed on its back, legs wiggling.
		if not has_meta("landed_back"):
			set_meta("landed_back", true)
			EnemyKit.sfx(self, "enemy_land", global_position)
			EnemyKit.fx(get_parent(), "DustPuff", global_position, 0.7)
			kick_squash(0.6)
		tilt = lerpf(tilt, PI, delta * 10.0)
		bob = 0.35
		var t := Time.get_ticks_msec() / 1000.0
		pose("leg_l", Vector3(sin(t * 30.0) * 0.6, 0, 0))
		pose("leg_r", Vector3(-sin(t * 30.0) * 0.6, 0, 0))
		pose("arm_l", Vector3(sin(t * 26.0) * 0.6, 0, 0))
		pose("arm_r", Vector3(-sin(t * 26.0) * 0.6, 0, 0))
	tilt = minf(tilt + delta * 2.0, PI)


func _defeat_burst() -> void:
	if owns("enemy_flee"):
		return
	EnemyKit.fx(get_parent(), "Confetti", global_position + Vector3(0, 0.5, 0), 0.8, Color(1.0, 0.9, 0.45))
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.5, 0), "confetti", [YELLOW, STRIPE, Color(1, 1, 1)], 34, 5.0)

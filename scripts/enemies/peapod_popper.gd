class_name PeapodPopper
extends EnemyBase
## Peapod Popper: a smug pea pod planted in the soil. Puffs up, then lobs a volley of peas in
## readable arcs (a shadow marker shows each landing spot), then pants while it reloads.
## Counter: approach between volleys; stomp, kick or punch. Defeat: pops open, peas scatter.

const POD := Color(0.36, 0.7, 0.24)
const POD_DARK := Color(0.22, 0.5, 0.16)
const PEA := Color(0.55, 0.88, 0.3)
const SOIL := Color(0.42, 0.28, 0.16)

@export var volley: int = 3
@export var volley_gap: float = 0.45
@export var reload_time: float = 2.2

var _shots_left: int = 0
var _shot_t: float = 0.0
var _hmph_t: float = 3.0
var _recoil: float = 0.0
var _peek_snapped: bool = false
## Loose peas (bone index -> world velocity / offset) for the defeat scatter.
var _pea_bones: Array[int] = []
var _pea_vel: Array[Vector3] = []
var _pea_off: Array[Vector3] = []
var _pea_rest: Array[Vector3] = []
var _inhale: float = 0.0
static var _pod_mat_cache: Dictionary = {}
const SHELL_TEX := "res://scenes/enemies/tex/peapod_shell_deepgreen.webp"


## Plain defaults in _init so builder values survive (W2's 5.5 m garden notice radius was discarded, r1 blocker).
func _init() -> void:
	enemy_id = "peapod_popper"
	# Rooted plant: no hop, it shoots up tall on its stalk.
	notice_hop = 0.0
	notice_stretch = 0.22
	notice_len = 0.38
	display_name = "Peapod Popper"
	body_radius = 0.32
	body_height = 0.9
	head_height = 0.95
	notice_radius = 12.0
	lose_radius = 16.0
	contact_damage = false
	acorns_on_defeat = 1
	windup_len = 0.65
	# Planted: snaps to the floor once, then ignores gravity (W2 E02 fell through the world, r1 M2).
	planted = true
	rim_power = 4.0
	# Fix r2: the lowest-contrast enemy in W2 (a capsule at 64 px), so a wide deep-forest ink line and a bright rim
	# carve the pod out of the leaf greens.
	outline_width = 2.2
	outline_color = Color("#0E2618")
	toon_rim = 0.65


func _setup() -> void:
	# Rigged v2 (Blender, enemies track): pod_l/pod_r clamshell hinges, head (face pea), pea_mid/low/tiny, arms, legs, stem.
	if mesh_path == "" and ResourceLoader.exists("res://assets/enemies/peapod_popper/peapod_popper_v2.glb"):
		mesh_path = "res://assets/enemies/peapod_popper/peapod_popper_v2.glb"


func _on_mesh_ready(inst: Node) -> void:
	# Deep blue-green shell (#2F7A55 with #1F4D38 creases) from a recoloured copy of the texture, applied to the pod mesh
	# only, so the pod leaves W2's lime and leaf palette while the peas keep their bright lime (r1 visual major: the
	# whole-material multiply only darkened it to another mid green).
	var shell: Texture2D = load(SHELL_TEX) as Texture2D if ResourceLoader.exists(SHELL_TEX) else null
	for mi in inst.find_children("pod*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in m.mesh.get_surface_count():
			var src := m.get_active_material(si) as StandardMaterial3D
			if src == null:
				continue
			var c: StandardMaterial3D = _pod_mat_cache.get(src.get_instance_id())
			if c == null:
				c = src.duplicate() as StandardMaterial3D
				if shell != null:
					c.albedo_texture = shell
					c.albedo_color = Color(1, 1, 1)
				else:
					c.albedo_color = Color(0.42, 0.66, 0.5)
				_pod_mat_cache[src.get_instance_id()] = c
			m.set_surface_override_material(si, c)
	_pea_bones.clear()
	if skeleton == null:
		var sk := mesh_root.find_children("*", "Skeleton3D", true, false)
		if sk.is_empty():
			return
		skeleton = sk[0] as Skeleton3D
	for bn in ["head", "pea_mid", "pea_low", "pea_tiny"]:
		var i := skeleton.find_bone(bn)
		if i >= 0:
			_pea_bones.append(i)
			_pea_rest.append(skeleton.get_bone_rest(i).origin)


func _build_placeholder(root: Node3D) -> void:
	EnemyKit.ball(root, 0.5, SOIL, Vector3(0, 0.0, 0), Vector3(1.2, 0.35, 1.2))
	for i in 5:
		var a := TAU * float(i) / 5.0
		EnemyKit.ball(root, 0.08, SOIL.darkened(0.2), Vector3(cos(a) * 0.5, 0.06, sin(a) * 0.5), Vector3(1, 0.6, 1))
	var body := EnemyKit.pivot(root, "body", Vector3(0, 0.1, 0))
	EnemyKit.capsule(body, 0.3, 0.95, POD, Vector3(0, 0.42, 0.02), Vector3(-6, 0, 0), Vector3(1.0, 1.0, 0.85))
	# The split seam with peas peeking out.
	EnemyKit.capsule(body, 0.14, 0.62, POD_DARK, Vector3(0, 0.3, -0.2), Vector3(-6, 0, 0), Vector3(1, 1, 0.5))
	for i in 3:
		EnemyKit.ball(body, 0.1, PEA, Vector3(0, 0.1 + 0.17 * float(i), -0.24 + 0.017 * float(i)))
	for side in [-1.0, 1.0]:
		var leaf := EnemyKit.pivot(body, "arm_l" if side < 0 else "arm_r", Vector3(0.24 * side, 0.12, 0))
		EnemyKit.ball(leaf, 0.16, POD_DARK, Vector3(0.14 * side, 0.02, 0), Vector3(1.4, 0.25, 0.7), "", Vector3(0, 0, -20 * side))
	var head := EnemyKit.pivot(body, "head", Vector3(0, 0.75, 0))
	head.set_meta("skin", POD)
	EnemyKit.face(head, Vector3(0, 0.02, -0.22), 0.1, 0.075, Color(0.3, 0.2, 0.1), "smug")
	EnemyKit.mouth(head, Vector3(0.02, -0.14, -0.24), 0.16, "smirk")
	var tail := EnemyKit.pivot(head, "tail", Vector3(0, 0.28, 0.05))
	EnemyKit.ring(tail, 0.05, 0.09, POD_DARK, Vector3(0, 0.06, 0), Vector3(90, 0, 0))
	EnemyKit.cylinder(tail, 0.03, 0.04, 0.12, POD_DARK, Vector3(0, -0.03, 0))


func _initial_state() -> String:
	return "idle"


func _ai(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	match state:
		"idle":
			_hmph_t -= delta
			if _hmph_t < 0.0:
				_hmph_t = _rng.randf_range(3.0, 6.0)
				say("Hmph.", Color(0.85, 1, 0.7), 56)
			if sees_player():
				notice_player("!", "pea_pop")
		"notice":
			face_toward(player_pos(), delta, 8.0)
			# Volley token: at most two pods fire at Mak at once (W2 had five volleys together, r1 fun).
			if state_time > 0.5 and request_attack("volley"):
				set_state("windup")
		"windup":
			face_toward(player_pos(), delta, 8.0)
			if state_time > 0.65:
				_shots_left = volley
				_shot_t = 0.12
				set_state("attack")
		"attack":
			face_toward(player_pos(), delta, 8.0)
			_shot_t -= delta
			if _shot_t <= 0.0 and _shots_left > 0:
				_shot_t = volley_gap
				_shots_left -= 1
				_fire()
			if _shots_left <= 0 and _shot_t <= 0.0:
				set_state("recover")
		"recover":
			if state_time > reload_time:
				if player != null and dist_to_player() < lose_radius:
					if request_attack("volley"):
						set_state("windup")
				else:
					set_state("idle")


## Finish pass (encounter r1 major: a running dive popped the pod in 1.7 s, before it fired a single pea). A dive
## before its first volley bounces off the tough pod and makes it fire back; stomps, punches and later dives land.
func _resolve_hit(kind: String, _from_position: Vector3) -> String:
	if kind == "dive" and (state == "idle" or state == "notice" or state == "windup"):
		_block_text_once = "Hmph! Pop me from above!"
		if state != "windup":
			set_state("windup")
		return "block"
	return "damage"


func _fire() -> void:
	if player == null:
		return
	# Peas come out of the face pea's mouth, not above the stem tip (r1 animation).
	var from := global_position + Vector3(0, 0.62, 0) + forward() * 0.28
	if skeleton != null and not _pea_bones.is_empty():
		from = skeleton.global_transform * skeleton.get_bone_global_pose(_pea_bones[0]).origin + forward() * 0.12
	var pv: Vector3 = player.get("velocity") if player.get("velocity") != null else Vector3.ZERO
	var target := player_pos() + Vector3(pv.x, 0, pv.z) * 0.35
	target += Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6))
	var q := PhysicsRayQueryParameters3D.create(target + Vector3(0, 2, 0), target + Vector3(0, -10, 0))
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		target = hit.position
	var t := clampf(from.distance_to(target) / 7.0, 0.85, 1.5)
	_recoil = 1.0
	juice("enemy_projectile_fire", {"kind": "pea", "direction": (target - from).normalized()}, from)
	var pea := PeaProjectile.new()
	get_parent().add_child(pea)
	pea.global_position = from
	pea.vel = PeaProjectile.flight_velocity(from, target, t)
	pea.marker = EnemyKit.ground_disc(get_parent(), target, 0.55, Color(0.15, 0.25, 0.1, 0.5))
	# Spit: stretch up and forward, then the spring rebounds into the recoil squash.
	squash = -0.25
	squash_vel = 3.0
	moment_sfx("enemy_projectile_fire", "pea_pop")


func _on_enter_state(s: String) -> void:
	if s == "windup":
		EnemyKit.sfx(self, "pea_inhale", global_position)
	if s == "notice":
		say("Oi!", Color(0.85, 1, 0.7), 70)
	if s == "recover":
		say("*pant*", Color(1, 1, 1), 48)


func _animate(delta: float) -> void:
	var t := _anim_t
	bob = 0.0
	lean = 0.0
	tilt = sin(t * 1.3) * 0.06
	spin = 0.0
	_recoil = move_toward(_recoil, 0.0, delta * 3.5)
	# Idle clamshell a little wider so the peas break the bean silhouette (r1 M3).
	var open := 0.16 + sin(t * 2.4) * 0.03
	match state:
		"idle":
			# Smug sway: hips swing, the face pea rolls its head, the stem twirls.
			pose("body", Vector3(sin(t * 1.7) * 0.06, 0, sin(t * 1.1) * 0.08))
			pose("head", Vector3(sin(t * 0.9) * 0.08, sin(t * 0.6) * 0.25, sin(t * 1.1) * 0.1))
			pose("arm_l", Vector3(0, 0, sin(t * 2.0) * 0.12))
			pose("arm_r", Vector3(0, 0, -sin(t * 2.0) * 0.12))
			pose("leg_l", Vector3(maxf(0.0, sin(t * 1.6)) * 0.25, 0, 0))
			pose("leg_r", Vector3.ZERO)
			# Peek beat every ~4.2 s (desynced per pod): the halves crack open, the face pea leans out and
			# glances left-right, then the pod snaps shut with a tiny hop. Reads as a lurking ambusher.
			var cyc := fmod(t + _breath_phase * 2.0, 4.2)
			if cyc < 1.4:
				var u := cyc / 1.4
				var env := sin(u * PI)
				open += env * 0.38
				pose("head", Vector3(-0.18 * env, sin(u * TAU) * 0.55 * env, 0))
				pose("arm_l", Vector3(0, 0, 0.35 * env))
				pose("arm_r", Vector3(0, 0, -0.35 * env))
				if u > 0.88 and _peek_snapped == false:
					_peek_snapped = true
					kick_squash(0.18)
			else:
				_peek_snapped = false
		"notice":
			open = 0.3
			pose("head", Vector3(-0.3, 0, 0))
			pose("arm_l", Vector3(0, 0, 0.5))
			pose("arm_r", Vector3(0, 0, -0.5))
		"windup":
			# Inhale: stretch tall, pod halves pull open, the peas inside quiver.
			var u := clampf(state_time / 0.65, 0.0, 1.0)
			squash = lerpf(squash, -0.22 - sin(t * 30.0) * 0.03, 0.2)
			lean = -0.25 * u
			open = 0.15 + 0.35 * u
			pose("head", Vector3(-0.35 * u, 0, sin(t * 40.0) * 0.05))
			pose("arm_l", Vector3(0, 0, 0.7))
			pose("arm_r", Vector3(0, 0, -0.7))
		"attack":
			# Per shot: a 0.1 s inhale (head back, face pea swells), then a spit snap forward and the recoil squash.
			_inhale = 1.0 if (_shots_left > 0 and _shot_t <= 0.12) else move_toward(_inhale, 0.0, delta * 8.0)
			lean = 0.1 + _recoil * 0.25 - _inhale * 0.1
			open = 0.25 + _recoil * 0.45 + _inhale * 0.15
			pose("body", Vector3(-0.1, 0, 0))
			if _inhale > 0.5:
				pose_snap("head", Vector3(-0.3, 0, 0), 40.0)
			else:
				pose_snap("head", Vector3(0.35 * _recoil, 0, 0), 45.0)
			if skeleton != null and not _pea_bones.is_empty():
				skeleton.set_bone_pose_scale(_pea_bones[0], Vector3.ONE * (1.0 + 0.15 * _inhale))
		"recover":
			# Out of breath: pod sags open, the face pea droops and pants.
			open = 0.22 + sin(t * 9.0) * 0.05
			pose("body", Vector3(0.25 + sin(t * 9.0) * 0.05, 0, 0))
			pose("head", Vector3(0.35 + sin(t * 9.0) * 0.06, 0, 0))
			pose("arm_l", Vector3(0, 0, -0.4))
			pose("arm_r", Vector3(0, 0, 0.4))
		_:
			pose("body", Vector3.ZERO)
	pose("pod_l", Vector3(0, open, 0))
	pose("pod_r", Vector3(0, -open, 0))
	pose("stem", Vector3(sin(t * 2.0) * 0.2, 0, cos(t * 2.0) * 0.2))
	pose("tail", Vector3(0, t * 2.0, 0))
	_apply_peas(delta, false)


## Inner peas jiggle with the pod; on defeat they fly out ballistically.
func _apply_peas(delta: float, flying: bool) -> void:
	if skeleton == null or _pea_bones.is_empty():
		return
	var inv := skeleton.global_transform.basis.inverse()
	for k in _pea_bones.size():
		var off := Vector3.ZERO
		if flying and k < _pea_vel.size():
			_pea_vel[k].y -= 16.0 * delta
			_pea_off[k] += _pea_vel[k] * delta
			var floor_y := -_pea_rest[k].y + 0.08
			if _pea_off[k].y < floor_y:
				_pea_off[k].y = floor_y
				_pea_vel[k] = Vector3(_pea_vel[k].x * 0.5, absf(_pea_vel[k].y) * 0.35, _pea_vel[k].z * 0.5)
			off = inv * _pea_off[k]
		elif k > 0:
			off = Vector3(0, sin(_anim_t * (34.0 if state == "windup" else 3.0) + k) * (0.012 if state == "windup" else 0.004), 0)
		skeleton.set_bone_pose_position(_pea_bones[k], _pea_rest[k] + off)


func _defeat_gag(_kind: String, _from_position: Vector3) -> float:
	say_side("Pfft!", Color(0.85, 1, 0.7), 90)
	moment_sfx("enemy_defeat", "pea_pop", 0.8)
	if not owns("enemy_defeat"):
		EnemyKit.fx(get_parent(), "PeaSplat", global_position + Vector3(0, 0.5, 0), 1.2)
	kick_squash(0.7)
	_pea_vel.clear()
	_pea_off.clear()
	for k in _pea_bones.size():
		var a := TAU * float(k) / maxf(1.0, float(_pea_bones.size())) + _rng.randf() * 0.6
		_pea_vel.append(Vector3(cos(a) * _rng.randf_range(1.6, 2.6), _rng.randf_range(4.5, 6.5), sin(a) * _rng.randf_range(1.6, 2.6)))
		_pea_off.append(Vector3.ZERO)
	return 0.95


func _defeat_process(delta: float) -> void:
	# The pod bursts open like a clam and wilts while the peas bounce away.
	var u := clampf(state_time / 0.95, 0.0, 1.0)
	pose("pod_l", Vector3(0, 1.35, 0.25 * u))
	pose("pod_r", Vector3(0, -1.35, -0.25 * u))
	pose("arm_l", Vector3(0, 0, 1.2))
	pose("arm_r", Vector3(0, 0, -1.2))
	pose("stem", Vector3(0.8 * u, 0, 0))
	if u > 0.5:
		rig.scale = rig.scale.lerp(Vector3(1.25, 0.35, 1.25), delta * 6.0)
	_apply_peas(delta, true)
	if state_time > 0.1 and not has_meta("pea_bits"):
		set_meta("pea_bits", true)
		EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.5, 0), "peas", [PEA, Color(0.8, 1, 0.5)], 20, 6.0)


func _defeat_burst() -> void:
	if owns("enemy_flee"):
		return
	EnemyKit.fx(get_parent(), "PeaSplat", global_position + Vector3(0, 0.3, 0), 1.0)
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.5, 0), "peas", [PEA, POD, Color(0.8, 1, 0.5)], 24, 6.0)

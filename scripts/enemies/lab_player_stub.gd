class_name EnemyLabPlayer
extends CharacterBody3D
## Stand-in player for the enemy lab and the boss arena while res://scenes/player/Player.tscn
## does not exist. Implements the player side of TECH_CONTRACT.md (take_damage, bounce,
## add_impulse, respawn, is_ground_pounding, is_attacking, wind zones, bouncy floors, hazards)
## and can be driven by keyboard or by a test script (drive_to / jump / slam / punch).

signal attacked(kind: String)
signal landed(impact_speed: float)
signal ground_pounded(pos: Vector3)
signal hit_result(kind: String, target: Node, landed_hit: bool)
signal damaged(amount: int, from_position: Vector3)

const GRAVITY := 32.0

@export var run_speed: float = 7.0
@export var jump_velocity: float = 11.5
@export var kill_y: float = -25.0
@export var keyboard: bool = true

var state: String = "ground"
var invuln: float = 0.0
var damage_taken: int = 0
var punch_t: float = 0.0
var slam_t: float = 0.0
var stun_t: float = 0.0
var drive_target: Vector3 = Vector3.INF
var drive_speed: float = 7.0
var input_dir: Vector3 = Vector3.ZERO
var external: Vector3 = Vector3.ZERO
var start_xform: Transform3D
var _was_floor: bool = true
var _hit_this_punch: Array = []
var _attack_area: Area3D
var _sensor: Area3D
var _vis: Node3D
var _jump_queued: bool = false
var _jumps_since_floor: int = 0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1 << 1
	collision_mask = 1
	start_xform = global_transform
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.25
	cs.shape = cap
	cs.position = Vector3(0, 0.625, 0)
	add_child(cs)
	_attack_area = Area3D.new()
	_attack_area.collision_layer = 1 << 5
	_attack_area.collision_mask = 1 << 6
	_attack_area.monitorable = false
	var acs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.6
	acs.shape = sph
	acs.position = Vector3(0, 0.6, -0.55)
	_attack_area.add_child(acs)
	add_child(_attack_area)
	_sensor = Area3D.new()
	_sensor.collision_layer = 0
	_sensor.collision_mask = (1 << 4) | (1 << 7)
	_sensor.monitorable = false
	var scs := CollisionShape3D.new()
	var scap := CapsuleShape3D.new()
	scap.radius = 0.35
	scap.height = 1.25
	scs.shape = scap
	scs.position = Vector3(0, 0.625, 0)
	_sensor.add_child(scs)
	add_child(_sensor)
	_build_visual()


func _build_visual() -> void:
	# A quick toy Mr. Mak so lab captures read correctly (the player workstream owns the real one).
	_vis = Node3D.new()
	_vis.name = "Visual"
	add_child(_vis)
	var cream := Color(0.98, 0.92, 0.84)
	var pink := Color(0.97, 0.66, 0.68)
	EnemyKit.ball(_vis, 0.3, cream, Vector3(0, 0.38, 0), Vector3(1, 1.05, 0.95))
	EnemyKit.ball(_vis, 0.3, cream, Vector3(0, 0.86, -0.02))
	EnemyKit.capsule(_vis, 0.1, 0.2, pink, Vector3(0, 0.8, -0.3), Vector3(90, 0, 0), Vector3(1.3, 1, 1))
	EnemyKit.ball(_vis, 0.03, Color(0.6, 0.3, 0.35), Vector3(-0.045, 0.82, -0.4))
	EnemyKit.ball(_vis, 0.03, Color(0.6, 0.3, 0.35), Vector3(0.045, 0.82, -0.4))
	EnemyKit.face(_vis, Vector3(0, 0.95, -0.24), 0.1, 0.06, Color(0.45, 0.27, 0.12), "happy")
	EnemyKit.ball(_vis, 0.31, Color(0.55, 0.56, 0.6), Vector3(0, 1.0, 0.02), Vector3(1.02, 0.7, 1.02))
	EnemyKit.ball(_vis, 0.08, Color(0.55, 0.56, 0.6), Vector3(0, 1.22, 0.04))
	for s in [-1.0, 1.0]:
		EnemyKit.cone(_vis, 0.08, 0.16, pink, Vector3(0.25 * s, 1.07, 0.0), Vector3(0, 0, -40 * s))
		EnemyKit.capsule(_vis, 0.08, 0.26, cream, Vector3(0.12 * s, 0.1, 0), Vector3.ZERO)
		EnemyKit.ball(_vis, 0.08, Color(0.45, 0.28, 0.16), Vector3(0.12 * s, 0.02, -0.02), Vector3(1, 0.6, 1.2))
		EnemyKit.capsule(_vis, 0.07, 0.3, cream, Vector3(0.32 * s, 0.45, 0), Vector3(0, 0, 25 * s))
	EnemyKit.box(_vis, Vector3(0.36, 0.38, 0.18), Color(0.55, 0.36, 0.2), Vector3(0, 0.5, 0.3))


func _physics_process(delta: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	punch_t = maxf(0.0, punch_t - delta)
	stun_t = maxf(0.0, stun_t - delta)
	var dir := Vector3.ZERO
	if keyboard and drive_target == Vector3.INF:
		var x := Input.get_axis("ui_left", "ui_right")
		var z := Input.get_axis("ui_up", "ui_down")
		if Input.is_key_pressed(KEY_A): x -= 1.0
		if Input.is_key_pressed(KEY_D): x += 1.0
		if Input.is_key_pressed(KEY_W): z -= 1.0
		if Input.is_key_pressed(KEY_S): z += 1.0
		dir = Vector3(x, 0, z)
		if Input.is_action_just_pressed("ui_accept"):
			jump()
		if Input.is_key_pressed(KEY_J) and punch_t <= 0.0:
			punch()
		if Input.is_key_pressed(KEY_K) and not is_on_floor():
			slam()
	elif drive_target != Vector3.INF:
		var d := drive_target - global_position
		d.y = 0
		if d.length() > 0.2:
			dir = d.normalized() * clampf(d.length() / 1.0, 0.2, 1.0)
		else:
			dir = Vector3.ZERO
	else:
		dir = input_dir
	if dir.length() > 1.0:
		dir = dir.normalized()
	var spd := drive_speed if drive_target != Vector3.INF else run_speed
	if stun_t > 0.0:
		dir = Vector3.ZERO
	if state == "slam":
		velocity.x = 0.0
		velocity.z = 0.0
		slam_t += delta
		velocity.y = 0.0 if slam_t < 0.22 else -24.0
	else:
		var accel := 40.0 if is_on_floor() else 18.0
		velocity.x = move_toward(velocity.x, dir.x * spd, accel * delta)
		velocity.z = move_toward(velocity.z, dir.z * spd, accel * delta)
		velocity.y -= GRAVITY * delta
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-14.0 * delta))
	# Wind zones and hazards (contract interfaces).
	var wind := Vector3.ZERO
	for a in _sensor.get_overlapping_areas():
		if a.is_in_group("wind_zone") and a.has_method("get_wind"):
			wind += a.call("get_wind", global_position)
		if a.is_in_group("hazard"):
			take_damage(int(a.get_meta("damage", 1)), a.global_position)
			if a.has_meta("knockback_up"):
				velocity.y = float(a.get_meta("knockback_up"))
	external = external.move_toward(Vector3.ZERO, 12.0 * delta)
	var saved := velocity
	var extra := external + wind * (1.0 if is_on_floor() else 1.4)
	extra.y = 0.0
	velocity += extra
	move_and_slide()
	velocity -= extra
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0
	var on_floor := is_on_floor()
	if on_floor and not _was_floor:
		landed.emit(-saved.y)
		_jumps_since_floor = 0
		if state == "slam":
			ground_pounded.emit(global_position)
			EnemyKit.ground_ring(get_parent(), global_position, 1.6, Color(1, 1, 1, 0.8), 0.4)
		state = "ground"
		for i in get_slide_collision_count():
			var c := get_slide_collision(i).get_collider()
			if Dev.has_arg("debug-bounce"):
				print("[Stub] landed on ", c)
			if c is Node and (c as Node).is_in_group("bouncy"):
				velocity.y = float((c as Node).get_meta("bounce_velocity", 14.0))
				state = "air"
	elif not on_floor and state == "ground":
		state = "air"
	_was_floor = on_floor
	if punch_t > 0.0:
		for a in _attack_area.get_overlapping_areas():
			if a in _hit_this_punch:
				continue
			if a.has_method("hit_by_player"):
				_hit_this_punch.append(a)
				var kind := "punch" if on_floor else "jump_kick"
				var ok: bool = a.call("hit_by_player", kind, global_position)
				var tgt: Node = a.get("enemy") if a.get("enemy") != null else a
				hit_result.emit(kind, tgt, ok)
	if global_position.y < kill_y:
		respawn(start_xform)
	_vis.scale = _vis.scale.lerp(Vector3.ONE, 1.0 - exp(-12.0 * delta))
	_vis.visible = invuln <= 0.0 or int(invuln * 20.0) % 2 == 0


func jump() -> void:
	if is_on_floor():
		velocity.y = jump_velocity
		state = "air"
		_jumps_since_floor += 1
		_vis.scale = Vector3(0.8, 1.25, 0.8)


func slam() -> void:
	if is_on_floor() or state == "slam":
		return
	state = "slam"
	slam_t = 0.0
	_vis.scale = Vector3(1.2, 0.8, 1.2)


func punch() -> void:
	punch_t = 0.25
	_hit_this_punch.clear()
	_vis.scale = Vector3(1.15, 0.9, 1.15)
	attacked.emit("punch" if is_on_floor() else "jump_kick")


func take_damage(amount: int, from_position: Vector3) -> void:
	if invuln > 0.0:
		return
	invuln = 1.2
	damage_taken += amount
	stun_t = 0.35
	var away := global_position - from_position
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	velocity = away * 7.0 + Vector3.UP * 6.0
	state = "air"
	EnemyKit.popup(get_parent(), global_position + Vector3(0, 1.6, 0), "Ouch!", Color(1, 0.5, 0.5), 70, 0.6)
	EnemyKit.game_call(self, "damage", [amount])
	damaged.emit(amount, from_position)


func bounce(up_velocity: float) -> void:
	velocity.y = up_velocity
	state = "air"
	_jumps_since_floor = 1
	_vis.scale = Vector3(0.8, 1.3, 0.8)


func add_impulse(v: Vector3) -> void:
	external += Vector3(v.x, 0, v.z)
	velocity.y = maxf(velocity.y, v.y)


func respawn(at: Transform3D) -> void:
	global_transform = at
	velocity = Vector3.ZERO
	external = Vector3.ZERO
	state = "air"
	reset_physics_interpolation()


func is_ground_pounding() -> bool:
	return state == "slam"


func is_attacking() -> bool:
	return punch_t > 0.0 or state == "slam"


func get_state_name() -> String:
	return state


func teleport(pos: Vector3, yaw: float = 0.0) -> void:
	global_position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO
	external = Vector3.ZERO
	reset_physics_interpolation()

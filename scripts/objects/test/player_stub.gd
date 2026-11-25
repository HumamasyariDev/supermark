class_name ObjPlayerStub
extends CharacterBody3D
## Local stand-in for the real player (Docs/TECH_CONTRACT.md player API), used only by the objects lab and
## scripted object tests. Driven by code: set move_dir, call jump(), ham_slam(), punch(), sniff().
## It implements: group "player", take_damage, bounce, add_impulse, respawn, is_ground_pounding, is_attacking,
## get_state_name, signals jumped/landed/ground_pounded/attacked/died, wind zones, bouncy floors and hazards.

signal jumped(kind: String)
signal landed(impact_speed: float)
signal ground_pounded(position: Vector3)
signal attacked(kind: String)
signal died

@export var gravity: float = 32.0
@export var run_speed: float = 7.0
@export var jump_velocity: float = 11.0

var move_dir := Vector3.ZERO
var external := Vector3.ZERO
var state := "idle"
var hp_hits := 0
var bounces := 0
var last_bounce := 0.0
var wind_seen := Vector3.ZERO
var max_wind_seen := 0.0
var _pounding := false
var _attack_time := 0.0
var _hurt_cool := 0.0
var _was_on_floor := true
var _sensor: Area3D
var _visual: Node3D


func _ready() -> void:
	add_to_group("player")
	collision_layer = ObjSvc.L_PLAYER
	collision_mask = ObjSvc.L_WORLD
	floor_snap_length = 0.2
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.25
	ObjSvc.add_shape(self, cap, Vector3(0, 0.625, 0))
	_sensor = Area3D.new()
	_sensor.collision_layer = 0
	_sensor.collision_mask = ObjSvc.L_TRIGGER | ObjSvc.L_HAZARD
	add_child(_sensor)
	ObjSvc.add_shape(_sensor, cap.duplicate(), Vector3(0, 0.625, 0))
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	# Placeholder piglet so captures read: cream body, pink snout and ears, grey beanie, brown backpack.
	var cream := ObjSvc.mat(Color(0.98, 0.92, 0.84), 0.5)
	var pink := ObjSvc.mat(Color(1.0, 0.62, 0.68), 0.45)
	var grey := ObjSvc.mat(Color(0.55, 0.56, 0.6), 0.85)
	var brown := ObjSvc.mat(Color(0.48, 0.3, 0.16), 0.7)
	var black := ObjSvc.mat(Color(0.08, 0.05, 0.04), 0.3)
	ObjSvc.sphere(_visual, 0.36, cream, Vector3(0, 0.45, 0), Vector3(1.0, 1.05, 0.95))
	ObjSvc.sphere(_visual, 0.32, cream, Vector3(0, 0.95, -0.02))
	ObjSvc.cylinder(_visual, 0.12, 0.13, 0.12, pink, Vector3(0, 0.9, -0.32), Vector3(90, 0, 0))
	ObjSvc.sphere(_visual, 0.025, black, Vector3(-0.04, 0.9, -0.39))
	ObjSvc.sphere(_visual, 0.025, black, Vector3(0.04, 0.9, -0.39))
	for sx in [-1.0, 1.0]:
		ObjSvc.sphere(_visual, 0.05, black, Vector3(sx * 0.12, 1.02, -0.27))
		ObjSvc.cone(_visual, 0.08, 0.16, pink, Vector3(sx * 0.2, 1.22, 0.0), Vector3(0, 0, -sx * 30))
		ObjSvc.sphere(_visual, 0.09, brown, Vector3(sx * 0.18, 0.06, -0.04), Vector3(1, 0.6, 1.3))
	ObjSvc.sphere(_visual, 0.3, grey, Vector3(0, 1.12, 0.02), Vector3(1.05, 0.7, 1.05))
	ObjSvc.sphere(_visual, 0.08, grey, Vector3(0, 1.36, 0.02))
	ObjSvc.soft_box(_visual, Vector3(0.38, 0.4, 0.2), brown, Vector3(0, 0.55, 0.34), Vector3.ZERO, 0.05)


# ------------------------------------------------------------ contract API

func take_damage(amount: int, from_position: Vector3) -> void:
	if _hurt_cool > 0.0:
		return
	_hurt_cool = 0.8
	hp_hits += amount
	var away := global_position - from_position
	away.y = 0.0
	velocity = away.normalized() * 5.0 + Vector3(0, 6.0, 0)
	state = "hurt"
	ObjSvc.call_on("Game", "damage", [amount])


func bounce(up_velocity: float) -> void:
	velocity.y = up_velocity
	_pounding = false
	bounces += 1
	last_bounce = up_velocity
	state = "bounce"
	jumped.emit("bounce")


func add_impulse(v: Vector3) -> void:
	velocity += v


func respawn(at: Transform3D) -> void:
	global_transform = at
	velocity = Vector3.ZERO
	_pounding = false
	reset_physics_interpolation()
	state = "respawn"


func is_ground_pounding() -> bool:
	return _pounding


func is_attacking() -> bool:
	return _attack_time > 0.0


func get_state_name() -> String:
	return state


# ------------------------------------------------------------ scripted inputs

func jump() -> void:
	if is_on_floor():
		velocity.y = jump_velocity
		state = "jump"
		jumped.emit("single")


func ham_slam() -> void:
	_pounding = true
	velocity = Vector3(0, -20.0, 0)
	state = "ground_pound"


func punch(kind: String = "punch") -> int:
	_attack_time = 0.25
	attacked.emit(kind)
	state = kind
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ObjSvc.sphere_shape(0.9)
	q.transform = Transform3D(Basis(), global_position + Vector3(0, 0.6, 0) - global_transform.basis.z * 0.5)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = ObjSvc.L_ENEMY_HURTBOX
	var hits := 0
	for r in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var c: Object = r.collider
		if c != null and c.has_method("hit_by_player"):
			if bool(c.call("hit_by_player", kind, global_position)):
				hits += 1
	return hits


func sniff() -> void:
	state = "sniff"
	var best: Node3D = null
	var best_d := INF
	for t in get_tree().get_nodes_in_group("sniff_target"):
		if t.has_method("is_sniff_active") and not bool(t.call("is_sniff_active")):
			continue
		var d := global_position.distance_to((t as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = t
	if best and best_d < 3.0 and best.has_method("on_sniffed"):
		best.call("on_sniffed", self)


# ------------------------------------------------------------ physics

func _physics_process(delta: float) -> void:
	_hurt_cool = maxf(0.0, _hurt_cool - delta)
	_attack_time = maxf(0.0, _attack_time - delta)
	var wind := Vector3.ZERO
	for a in _sensor.get_overlapping_areas():
		if a.is_in_group("wind_zone") and a.has_method("get_wind"):
			wind += a.call("get_wind", global_position + Vector3(0, 0.6, 0))
		elif a.is_in_group("hazard") and _hurt_cool <= 0.0:
			var dmg := int(a.get_meta("damage", 1))
			take_damage(dmg, (a as Node3D).global_position)
			var ku := float(a.get_meta("knockback_up", 0.0))
			if ku > 0.0:
				velocity.y = ku
	wind_seen = wind
	max_wind_seen = maxf(max_wind_seen, wind.length())
	if not is_on_floor():
		velocity.y -= gravity * delta
	if not _pounding:
		var target := move_dir * run_speed
		velocity.x = move_toward(velocity.x, target.x, 40.0 * delta)
		velocity.z = move_toward(velocity.z, target.z, 40.0 * delta)
	var air_k := 1.0 if is_on_floor() else 1.6
	var push := wind * air_k
	velocity += push
	var fall_speed := -velocity.y
	move_and_slide()
	velocity -= push
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit(fall_speed)
		if _pounding:
			_pounding = false
			ground_pounded.emit(global_position)
			state = "slam_land"
		var col := get_last_slide_collision()
		var floor_body: Object = col.get_collider() if col else null
		if floor_body is Node and (floor_body as Node).is_in_group("bouncy"):
			bounce(float((floor_body as Node).get_meta("bounce_velocity", 12.0)))
			on_floor = false
		elif state in ["jump", "bounce", "hurt", "fall"]:
			state = "idle"
	elif on_floor and _was_on_floor:
		var col2 := get_last_slide_collision()
		var fb: Object = col2.get_collider() if col2 else null
		if fb is Node and (fb as Node).is_in_group("bouncy") and velocity.y <= 0.1:
			bounce(float((fb as Node).get_meta("bounce_velocity", 12.0)))
			on_floor = false
	if not on_floor and velocity.y < 0.0 and state == "idle":
		state = "fall"
	_was_on_floor = on_floor
	if move_dir.length() > 0.1:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-move_dir.x, -move_dir.z), 0.2)

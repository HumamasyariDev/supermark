extends CharacterBody3D
## Stand-in player used by WorldRoot only while res://scenes/player/Player.tscn does not exist.
## A cream capsule with a pink snout, simple run/jump and a follow camera. Implements the
## player interface from TECH_CONTRACT.md so worlds can be tested before the real controller lands.

signal jumped(kind: String)
signal landed(impact_speed: float)
signal died

const SPEED := 8.0
const JUMP := 9.5
const GRAVITY := 28.0

var _cam: Camera3D
var _yaw := 0.0
var _pitch := -0.35
var _was_floor := true


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1 << 1
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.25
	shape.shape = cap
	shape.position.y = 0.625
	add_child(shape)
	var body := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = 0.38
	m.height = 1.1
	body.mesh = m
	body.position.y = 0.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("fbefe0")
	mat.roughness = 0.7
	body.material_override = mat
	add_child(body)
	var snout := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.12
	sm.bottom_radius = 0.14
	sm.height = 0.14
	snout.mesh = sm
	snout.rotation.x = PI * 0.5
	snout.position = Vector3(0, 0.85, -0.4)
	var pink := StandardMaterial3D.new()
	pink.albedo_color = Color("f29bb0")
	snout.material_override = pink
	add_child(snout)
	var hat := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.3
	hm.height = 0.3
	hat.mesh = hm
	hat.position.y = 1.12
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color("8d8f96")
	hat.material_override = grey
	add_child(hat)
	_cam = Camera3D.new()
	_cam.fov = 60
	_cam.top_level = true
	add_child(_cam)
	_cam.make_current()
	_place_camera.call_deferred()


func respawn(at: Transform3D) -> void:
	global_transform = at
	velocity = Vector3.ZERO
	_yaw = at.basis.get_euler().y
	reset_physics_interpolation()
	_place_camera()


func take_damage(amount: int, from_position: Vector3) -> void:
	var game := get_node_or_null("/root/Game")
	if game:
		game.damage(amount)
	var away := (global_position - from_position)
	away.y = 0
	velocity = away.normalized() * 6.0 + Vector3.UP * 6.0


func bounce(up_velocity: float) -> void:
	velocity.y = up_velocity


func add_impulse(v: Vector3) -> void:
	velocity += v


func is_ground_pounding() -> bool:
	return false


func is_attacking() -> bool:
	return false


func get_state_name() -> String:
	return "standin"


func _blocked() -> bool:
	var ui := get_node_or_null("/root/UI")
	return ui != null and ui.is_input_blocked()


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if not _blocked():
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		_yaw -= Input.get_axis("cam_left", "cam_right") * 2.5 * delta
		_pitch = clampf(_pitch - Input.get_axis("cam_up", "cam_down") * 1.5 * delta, -1.2, 0.3)
	var basis_y := Basis(Vector3.UP, _yaw)
	var dir := basis_y * Vector3(input.x, 0, input.y)
	velocity.x = move_toward(velocity.x, dir.x * SPEED, 40.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * SPEED, 40.0 * delta)
	velocity.y -= GRAVITY * delta
	if is_on_floor() and not _blocked() and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP
		jumped.emit("single")
	var fall := velocity.y
	move_and_slide()
	if is_on_floor() and not _was_floor:
		landed.emit(-fall)
	_was_floor = is_on_floor()
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 10.0 * delta)


func _process(_delta: float) -> void:
	_place_camera()


func _place_camera() -> void:
	if _cam == null:
		return
	var target := get_global_transform_interpolated().origin + Vector3(0, 1.2, 0)
	var off := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Vector3(0, 0, 7.5)
	_cam.global_position = target + off
	_cam.look_at(target, Vector3.UP)

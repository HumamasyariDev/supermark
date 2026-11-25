class_name FallingPlatform
extends AnimatableBody3D
## Wobbles when stood on, then drops away and respawns with a pop.

signal fell
signal respawned

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var size: Vector3 = Vector3(2.4, 0.4, 2.4)
@export var theme: PlatformLook.Kind = PlatformLook.Kind.WOOD
@export var wobble_time: float = 0.7
@export var fall_distance: float = 25.0
@export var respawn_time: float = 3.5

enum State { IDLE, WOBBLE, FALLING, GONE }
var state: State = State.IDLE
var _home: Transform3D
var _home_set := false
var _ticks := 0
var _timer := 0.0
var _fall_speed := 0.0
var _visual: Node3D
var _shape: CollisionShape3D
var _sensor: Area3D


func _ready() -> void:
	add_to_group("falling_platform")
	# Enabled on the first physics tick, so a spawner may still move it right after add_child.
	sync_to_physics = false
	collision_layer = ObjSvc.L_WORLD
	collision_mask = 0
	_shape = ObjSvc.add_shape(self, ObjSvc.box_shape(size), Vector3(0, -size.y * 0.5, 0))
	_visual = ObjSvc.ensure_visual(self)
	if not ObjSvc.visual_has_content(_visual):
		PlatformLook.build(_visual, size, theme)
		# Crack marks to telegraph that it is fragile.
		var crack := ObjSvc.mat(Color(0.25, 0.14, 0.07), 0.9)
		ObjSvc.box(_visual, Vector3(size.x * 0.5, 0.012, 0.04), crack, Vector3(-0.1, 0.006, 0.2), Vector3(0, 25, 0))
		ObjSvc.box(_visual, Vector3(size.x * 0.3, 0.012, 0.04), crack, Vector3(0.3, 0.006, -0.25), Vector3(0, -40, 0))
	_sensor = ObjSvc.make_area(self, ObjSvc.box_shape(Vector3(size.x * 0.95, 0.4, size.z * 0.95)), ObjSvc.L_TRIGGER, ObjSvc.L_PLAYER, Vector3(0, 0.2, 0), "Sensor")
	_sensor.body_entered.connect(_on_sensor)
	_home = global_transform


func _on_sensor(body: Node) -> void:
	if state == State.IDLE and ObjSvc.is_player(body):
		state = State.WOBBLE
		_timer = 0.0
		ObjSvc.feedback("object_platform_wobble", global_position, {}, "platform_creak")


func _physics_process(delta: float) -> void:
	if not _home_set:
		# Captured on the second tick (a spawner may move it right after add_child, even inside a physics
		# step); sync_to_physics is switched on only then, otherwise Jolt keeps the stale spawn transform.
		_ticks += 1
		if _ticks < 2:
			return
		_home = global_transform
		_home_set = true
		sync_to_physics = true
	_timer += delta
	match state:
		State.WOBBLE:
			var k := _timer / wobble_time
			_visual.rotation = Vector3(sin(_timer * 40.0) * 0.05 * k, 0, cos(_timer * 34.0) * 0.05 * k)
			_visual.position.y = -absf(sin(_timer * 30.0)) * 0.03
			if _timer >= wobble_time:
				state = State.FALLING
				_timer = 0.0
				_fall_speed = 0.0
				_visual.rotation = Vector3.ZERO
				fell.emit()
				ObjSvc.feedback("object_platform_crumble", global_position, {}, "platform_fall")
		State.FALLING:
			_fall_speed += 22.0 * delta
			global_position.y -= _fall_speed * delta
			_visual.rotation.z += delta * 0.6
			if _home.origin.y - global_position.y > fall_distance:
				state = State.GONE
				_timer = 0.0
				_shape.set_deferred("disabled", true)
				visible = false
		State.GONE:
			if _timer >= respawn_time:
				_respawn()


func _respawn() -> void:
	state = State.IDLE
	global_transform = _home
	reset_physics_interpolation()
	_visual.rotation = Vector3.ZERO
	_visual.position = Vector3.ZERO
	_shape.set_deferred("disabled", false)
	visible = true
	_visual.scale = Vector3.ONE * 0.05
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ObjSvc.burst(get_parent(), global_position, Color(1, 0.95, 0.8), 14, 2.0, 0.25, 0.0, 0.6)
	respawned.emit()

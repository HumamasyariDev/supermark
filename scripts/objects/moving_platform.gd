class_name MovingPlatform
extends Node3D
## Platform that follows a Path3D child named "Path" (built as a straight run along local X if missing).
## The moving part is an AnimatableBody3D ("Body", sync_to_physics) so the player inherits its velocity.

enum Mode { LOOP, PING_PONG }

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var size: Vector3 = Vector3(3.0, 0.4, 3.0)
@export var theme: PlatformLook.Kind = PlatformLook.Kind.WOOD
@export var mode: Mode = Mode.PING_PONG
@export var speed: float = 2.5
@export var pause_at_ends: float = 0.6
@export var travel: Vector3 = Vector3(6, 0, 0)
@export var start_offset: float = 0.0
## Close a missing path into a loop (only used when the path is auto-built).
@export var auto_loop_square: bool = false

var body: AnimatableBody3D
var path: Path3D
var _offset := 0.0
var _dir := 1.0
var _pause := 0.0
var _t := 0.0
var _visual: Node3D


func _ready() -> void:
	add_to_group("moving_platform")
	path = get_node_or_null("Path") as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2:
		if path == null:
			path = Path3D.new()
			path.name = "Path"
			add_child(path)
		var c := Curve3D.new()
		c.add_point(Vector3.ZERO)
		if auto_loop_square:
			c.add_point(Vector3(travel.x, travel.y, 0))
			c.add_point(Vector3(travel.x, travel.y, travel.z if travel.z != 0.0 else travel.x))
			c.add_point(Vector3(0, 0, travel.z if travel.z != 0.0 else travel.x))
			c.add_point(Vector3.ZERO)
		else:
			c.add_point(travel)
		path.curve = c
	body = get_node_or_null("Body") as AnimatableBody3D
	if body == null:
		body = AnimatableBody3D.new()
		body.name = "Body"
		add_child(body)
	body.sync_to_physics = true
	body.collision_layer = ObjSvc.L_WORLD
	body.collision_mask = 0
	ObjSvc.add_shape(body, ObjSvc.box_shape(size), Vector3(0, -size.y * 0.5, 0))
	_visual = get_node_or_null("Visual") as Node3D
	if _visual == null:
		_visual = Node3D.new()
		_visual.name = "Visual"
		body.add_child(_visual)
	elif _visual.get_parent() != body:
		_visual.reparent(body, false)
	ObjSvc.fill_visual(self, _visual)
	if not ObjSvc.visual_has_content(_visual):
		PlatformLook.build(_visual, size, theme)
	_offset = start_offset * path.curve.get_baked_length()
	_place()
	body.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	_t += delta
	var length := path.curve.get_baked_length()
	if length <= 0.001:
		return
	if _pause > 0.0:
		_pause -= delta
	else:
		_offset += speed * _dir * delta
		if mode == Mode.LOOP:
			_offset = fposmod(_offset, length)
		else:
			if _offset >= length:
				_offset = length
				_dir = -1.0
				_pause = pause_at_ends
			elif _offset <= 0.0:
				_offset = 0.0
				_dir = 1.0
				_pause = pause_at_ends
	_place()


func _place() -> void:
	var local := path.curve.sample_baked(_offset, true)
	body.global_position = path.global_transform * local


func _process(_delta: float) -> void:
	# A tiny idle sway on the visual only (collision stays exact).
	if _visual:
		_visual.rotation.z = sin(_t * 1.7) * 0.012
		_visual.rotation.x = sin(_t * 1.3) * 0.01

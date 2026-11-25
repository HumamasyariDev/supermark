class_name RotatingPlatform
extends Node3D
## Windmill-sail style rotor: arms around a hub carry platforms (AnimatableBody3D, sync_to_physics).
## axis VERTICAL_PLANE turns like windmill sails (around local Z); HORIZONTAL turns like a carousel (around Y).
## keep_level keeps each platform upright (a Ferris-wheel ride); otherwise platforms tilt with the arms.

enum Axis { VERTICAL_PLANE, HORIZONTAL }

## Generated mesh for each rotor platform (the hub keeps its own Visual slot): instanced and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var axis: Axis = Axis.VERTICAL_PLANE
@export_range(1, 8) var arm_count: int = 4
@export var radius: float = 5.0
@export var degrees_per_second: float = 20.0
@export var keep_level: bool = true
@export var platform_size: Vector3 = Vector3(2.4, 0.35, 2.0)
@export var platform_theme: PlatformLook.Kind = PlatformLook.Kind.WOOD
@export var sail_color: Color = Color(0.98, 0.94, 0.84)
@export var show_sails: bool = true
## Critique objects r1: the W1 sail steps were primitive boards. Wooden platforms default to the generated W1 hay
## bale (top flush with the step, the bale hanging below it) when no visual_scene is given.
@export var auto_model: bool = true

const HAY_BALE := "res://assets/props/w1/hay_bale/hay_bale.glb"
const HAY_SIZE := Vector3(1.65, 1.127, 1.26)

var platforms: Array[AnimatableBody3D] = []
var _angle := 0.0
var _rotor: Node3D
var _visual: Node3D


func _ready() -> void:
	add_to_group("rotating_platform")
	_visual = get_node_or_null("Visual") as Node3D
	if _visual == null:
		_visual = Node3D.new()
		_visual.name = "Visual"
		add_child(_visual)
	_rotor = Node3D.new()
	_rotor.name = "Rotor"
	add_child(_rotor)
	if not ObjSvc.visual_has_content(_visual):
		_build_hub()
	for i in arm_count:
		var b := AnimatableBody3D.new()
		b.name = "Platform%d" % i
		b.sync_to_physics = true
		b.collision_layer = ObjSvc.L_WORLD
		b.collision_mask = 0
		add_child(b)
		ObjSvc.add_shape(b, ObjSvc.box_shape(platform_size), Vector3(0, -platform_size.y * 0.5, 0))
		var v := Node3D.new()
		v.name = "Visual"
		b.add_child(v)
		if not ObjSvc.fill_visual(self, v):
			if not _hay_visual(v):
				PlatformLook.build(v, platform_size, platform_theme)
		platforms.append(b)
	_place()
	for b in platforms:
		b.reset_physics_interpolation()


func _hay_visual(v: Node3D) -> bool:
	if not auto_model or platform_theme != PlatformLook.Kind.WOOD or not ResourceLoader.exists(HAY_BALE):
		return false
	var ps := load(HAY_BALE) as PackedScene
	if ps == null:
		return false
	var h := ps.instantiate() as Node3D
	h.name = "HayBale"
	var sc := maxf(platform_size.x / HAY_SIZE.x, platform_size.z / HAY_SIZE.z)
	h.scale = Vector3.ONE * sc
	h.position = Vector3(0, -HAY_SIZE.y * sc + 0.04, 0)
	v.add_child(h)
	return true


func _build_hub() -> void:
	var wood := ObjSvc.mat(ObjSvc.WALNUT, 0.7)
	var brass := ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.8)
	var sail := ObjSvc.mat(sail_color, 0.9)
	sail.cull_mode = BaseMaterial3D.CULL_DISABLED
	if axis == Axis.VERTICAL_PLANE:
		ObjSvc.cylinder(_visual, 0.5, 0.6, 0.8, wood, Vector3(0, 0, -0.3), Vector3(90, 0, 0))
		ObjSvc.sphere(_visual, 0.45, brass, Vector3(0, 0, 0.25), Vector3(1, 1, 0.7))
	else:
		ObjSvc.cylinder(_visual, 0.45, 0.55, 1.0, wood, Vector3(0, -0.5, 0))
		ObjSvc.sphere(_visual, 0.45, brass, Vector3(0, 0.1, 0), Vector3(1, 0.6, 1))
	for i in arm_count:
		var arm := Node3D.new()
		_rotor.add_child(arm)
		var a := TAU * float(i) / float(arm_count)
		if axis == Axis.VERTICAL_PLANE:
			arm.rotation.z = a
			ObjSvc.box(arm, Vector3(radius, 0.18, 0.18), wood, Vector3(radius * 0.5, 0, 0.1))
			if show_sails:
				# Lattice sail along each arm, like a windmill.
				ObjSvc.box(arm, Vector3(radius * 0.75, 0.9, 0.04), sail, Vector3(radius * 0.52, 0.55, 0.12))
				for k in 4:
					ObjSvc.box(arm, Vector3(0.06, 1.0, 0.06), wood, Vector3(radius * 0.18 + k * radius * 0.22, 0.55, 0.16))
		else:
			arm.rotation.y = a
			ObjSvc.box(arm, Vector3(radius, 0.2, 0.2), wood, Vector3(radius * 0.5, -0.1, 0))


func _physics_process(delta: float) -> void:
	_angle += deg_to_rad(degrees_per_second) * delta
	_place()


func _process(_delta: float) -> void:
	if axis == Axis.VERTICAL_PLANE:
		_rotor.rotation = Vector3(0, 0, _angle)
	else:
		_rotor.rotation = Vector3(0, -_angle, 0)


func _place() -> void:
	for i in platforms.size():
		var a := _angle + TAU * float(i) / float(arm_count)
		var local_pos: Vector3
		var local_basis := Basis()
		if axis == Axis.VERTICAL_PLANE:
			local_pos = Vector3(cos(a), sin(a), 0) * radius + Vector3(0, 0, 0.6)
			if not keep_level:
				local_basis = Basis(Vector3.BACK, a)
		else:
			local_pos = Vector3(cos(a), 0, -sin(a)) * radius
			if not keep_level:
				local_basis = Basis(Vector3.UP, a)
		platforms[i].global_transform = global_transform * Transform3D(local_basis, local_pos)


func get_rotor_angle() -> float:
	return _angle

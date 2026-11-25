class_name SlamSwitch
extends StaticBody3D
## A big brass button on a carved plinth. A Ham Slam presses it (one-shot, or timed with reset_after > 0).

signal pressed(switch: Node)
signal released(switch: Node)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var button_color: Color = Color(0.9, 0.25, 0.25)
@export var pressed_color: Color = Color(0.35, 0.85, 0.4)
@export var reset_after: float = 0.0
@export var radius: float = 0.9

var is_pressed := false
var _cap: Node3D
var _cap_mat: StandardMaterial3D
var _sensor: SlamSensor
var _timer := 0.0
var _t := 0.0
var _light: OmniLight3D
## Critique objects r1: the switch was a generic red dome on a grey cylinder. Default look: the generated custard-cream
## biscuit (W3 biscuit_platform.glb, a Giant's-kitchen sized biscuit) with a glossy jam drop on top as the target;
## the Ham Slam squishes the biscuit and the jam turns green.
@export var use_default_mesh: bool = true
const BISCUIT := "res://assets/props/w3/biscuit_platform/biscuit_platform.glb"
const BISCUIT_R := 1.25
const BISCUIT_H := 0.72
var _squash: Node3D
var _shape: CollisionShape3D
var _top := 0.35


func _ready() -> void:
	add_to_group("slam_switch")
	collision_layer = ObjSvc.L_WORLD
	collision_mask = 0
	_shape = ObjSvc.add_shape(self, ObjSvc.cyl_shape(radius, 0.35), Vector3(0, 0.175, 0))
	var v := ObjSvc.ensure_visual(self)
	if not ObjSvc.visual_has_content(v) and use_default_mesh and ResourceLoader.exists(BISCUIT):
		_build_biscuit(v)
	if not ObjSvc.visual_has_content(v):
		var stone := ObjSvc.mat(Color(0.62, 0.58, 0.55), 0.85)
		var brass := ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.85)
		ObjSvc.cylinder(v, radius, radius * 1.1, 0.3, stone, Vector3(0, 0.15, 0))
		ObjSvc.torus(v, radius * 0.75, radius * 0.92, brass, Vector3(0, 0.3, 0))
		_cap = Node3D.new()
		_cap.position = Vector3(0, 0.3, 0)
		v.add_child(_cap)
		_cap_mat = ObjSvc.unique_mat(button_color, 0.3, 0.0, button_color, 0.35)
		_cap_mat.clearcoat_enabled = true
		ObjSvc.sphere(_cap, radius * 0.7, _cap_mat, Vector3.ZERO, Vector3(1, 0.4, 1))
		# Arrow marks pointing down: "slam here".
		for i in 4:
			var a := TAU * float(i) / 4.0 + PI * 0.25
			ObjSvc.cone(v, 0.1, 0.18, ObjSvc.mat(ObjSvc.GOLD, 0.4), Vector3(cos(a) * radius * 0.98, 0.2, sin(a) * radius * 0.98), Vector3(180, 0, 0))
	_light = OmniLight3D.new()
	_light.light_color = button_color
	_light.light_energy = 0.6
	_light.omni_range = 2.0
	_light.position = Vector3(0, _top + 0.3, 0)
	add_child(_light)
	_sensor = SlamSensor.create(self, radius, 0.9, Vector3(0, _top - 0.05, 0))
	_sensor.slammed.connect(func(_b: Node) -> void: press())


func _build_biscuit(v: Node3D) -> void:
	var ps := load(BISCUIT) as PackedScene
	if ps == null:
		return
	var sc := radius / BISCUIT_R * 1.05
	_squash = Node3D.new()
	_squash.name = "Squash"
	v.add_child(_squash)
	var b := ps.instantiate() as Node3D
	b.name = "Biscuit"
	b.scale = Vector3.ONE * sc
	_squash.add_child(b)
	_top = BISCUIT_H * sc
	(_shape.shape as CylinderShape3D).height = _top
	_shape.position.y = _top * 0.5
	_cap_mat = ObjSvc.unique_mat(button_color, 0.12, 0.0, button_color, 0.35)
	_cap_mat.clearcoat_enabled = true
	_cap_mat.clearcoat = 1.0
	var jam := Node3D.new()
	jam.name = "Jam"
	jam.position = Vector3(0, _top - 0.02, 0)
	_squash.add_child(jam)
	ObjSvc.sphere(jam, radius * 0.34, _cap_mat, Vector3.ZERO, Vector3(1.0, 0.42, 1.0))
	ObjSvc.sphere(jam, radius * 0.08, ObjSvc.unshaded(Color(1, 1, 1, 0.8)), Vector3(radius * 0.12, radius * 0.1, -radius * 0.1), Vector3(1.4, 0.6, 1.0))


func _set_top(h: float) -> void:
	(_shape.shape as CylinderShape3D).height = h
	_shape.position.y = h * 0.5


## The real player calls this on the floor collider after a Ham Slam impact (and via the attack area).
func hit_by_player(kind: String, _from_position: Vector3) -> bool:
	if kind == "slam" and not is_pressed:
		press()
		return true
	return false


func press() -> void:
	if is_pressed:
		return
	is_pressed = true
	_timer = 0.0
	ObjSvc.feedback("object_switch_press", global_position, {}, "switch_press")
	if _squash:
		var st := create_tween()
		st.tween_property(_squash, "scale", Vector3(1.16, 0.5, 1.16), 0.07).set_ease(Tween.EASE_OUT)
		st.tween_property(_squash, "scale", Vector3(1.06, 0.66, 1.06), 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		st.parallel().tween_method(_set_top, _top, _top * 0.66, 0.1)
	if _cap:
		var tw := create_tween()
		tw.tween_property(_cap, "scale", Vector3(1.3, 0.3, 1.3), 0.08)
		tw.tween_property(_cap, "scale", Vector3(1.1, 0.45, 1.1), 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_cap, "position:y", 0.2, 0.08)
	if _cap_mat:
		_cap_mat.albedo_color = pressed_color
		_cap_mat.emission = pressed_color
	_light.light_color = pressed_color
	_light.light_energy = 1.4
	if not ObjSvc.juice_handles("object_switch_press", "vfx"):
		ObjSvc.burst(get_parent(), global_position + Vector3(0, 0.4, 0), Color(1, 0.9, 0.6), 18, 4.0, 0.16, -8.0, 0.6)
		ObjSvc.fx(self, "DustPuff", global_position + Vector3(0, 0.3, 0))
	pressed.emit(self)


func release() -> void:
	if not is_pressed:
		return
	is_pressed = false
	if _squash:
		var st := create_tween().set_parallel()
		st.tween_property(_squash, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		st.tween_method(_set_top, _top * 0.66, _top, 0.3)
	if _cap:
		var tw := create_tween().set_parallel()
		tw.tween_property(_cap, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_cap, "position:y", 0.3, 0.3)
	if _cap_mat:
		_cap_mat.albedo_color = button_color
		_cap_mat.emission = button_color
	_light.light_color = button_color
	_light.light_energy = 0.6
	released.emit(self)


func _process(delta: float) -> void:
	_t += delta
	if not is_pressed:
		_light.light_energy = 0.5 + 0.3 * sin(_t * 4.0)
	elif reset_after > 0.0:
		_timer += delta
		if _timer >= reset_after:
			release()

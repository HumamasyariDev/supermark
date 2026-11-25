class_name Cage
extends TruffleSpawner
## A wrought-iron birdcage that lifts away when `required` linked SlamSwitches are pressed (all of them by default).
## On opening it releases its contents: children of "Contents" are re-enabled (process + visibility) and, if
## reward_truffle_id is set, a truffle appears at TruffleMarker (W2-2 "Free the Golden Goose").

signal opened

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var switches: Array[NodePath] = []
## 0 means all linked switches.
@export var required: int = 0
@export var radius: float = 1.4
@export var height: float = 2.6
@export var bar_color: Color = Color(0.2, 0.2, 0.24)
## D024 (no primitive stand-ins): with no visual_scene the cage uses the generated W2 goose cage, scaled to `height`
## (the procedural bars remain only as the fallback when the file is missing).
@export var use_default_mesh: bool = true

const DEFAULT_MESH := "res://assets/props/w2/goose_cage/goose_cage.glb"
## goose_cage.glb is 2.5 m tall; W2 shows it at 1.4 for a 3.4 m cage.
const DEFAULT_MESH_HEIGHT := 2.45

var is_open := false
var _cage_body: AnimatableBody3D
var _contents: Node3D
var _switch_nodes: Array[Node] = []
var _lights: Array[MeshInstance3D] = []
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _door: Node3D
var _door_rest := Basis()


func _ready() -> void:
	ObjSvc.ensure_npc_life_auto(self)
	super._ready()
	add_to_group("cage")
	_cage_body = AnimatableBody3D.new()
	_cage_body.name = "CageBody"
	_cage_body.sync_to_physics = false
	_cage_body.collision_layer = ObjSvc.L_WORLD
	add_child(_cage_body)
	# Bars as a ring of thin boxes so the player cannot pass but can see inside.
	for i in 12:
		var a := TAU * float(i) / 12.0
		ObjSvc.add_shape(_cage_body, ObjSvc.box_shape(Vector3(0.2, height, 0.2)), Vector3(cos(a) * radius, height * 0.5, sin(a) * radius))
	ObjSvc.add_shape(_cage_body, ObjSvc.cyl_shape(radius + 0.1, 0.3), Vector3(0, height + 0.15, 0))
	if visual_scene == null and use_default_mesh and ResourceLoader.exists(DEFAULT_MESH):
		visual_scene = load(DEFAULT_MESH) as PackedScene
		if visual_scene != null and is_equal_approx(visual_scale, 1.0):
			visual_scale = height / DEFAULT_MESH_HEIGHT
	var v := ObjSvc.ensure_visual(self)
	v.reparent(_cage_body, false)
	if not ObjSvc.visual_has_content(v):
		_build_placeholder(v)
	else:
		# Generated cage (W2 goose_cage.glb): its CageDoor node swings on its hinge pivot when the cage opens.
		_door = ObjSvc.find_named(v, "CageDoor")
		if _door:
			_door_rest = _door.basis
	_contents = get_node_or_null("Contents") as Node3D
	if _contents:
		_contents.process_mode = Node.PROCESS_MODE_DISABLED
		call_deferred("_liven_contents")
	for p in switches:
		var s := get_node_or_null(p)
		if s and s.has_signal("pressed"):
			_switch_nodes.append(s)
			s.connect("pressed", _on_switch)
			if s.has_signal("released"):
				s.connect("released", _on_switch)
	_build_lamps()


func _build_placeholder(v: Node3D) -> void:
	var iron := ObjSvc.mat(bar_color, 0.35, 0.85)
	var brass := ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.85)
	var base := ObjSvc.mat(ObjSvc.WALNUT, 0.6)
	ObjSvc.cylinder(self, radius + 0.25, radius + 0.35, 0.25, base, Vector3(0, 0.12, 0))
	for i in 16:
		var a := TAU * float(i) / 16.0
		ObjSvc.cylinder(v, 0.04, 0.04, height, iron, Vector3(cos(a) * radius, height * 0.5, sin(a) * radius))
	for y in [0.3, height * 0.55, height]:
		ObjSvc.torus(v, radius - 0.05, radius + 0.05, brass, Vector3(0, y, 0))
	# Domed top with a ring to hang from.
	ObjSvc.sphere(v, radius, iron, Vector3(0, height, 0), Vector3(1, 0.45, 1))
	ObjSvc.torus(v, 0.15, 0.24, brass, Vector3(0, height + radius * 0.5, 0), Vector3(90, 0, 0))
	# Padlock.
	ObjSvc.soft_box(v, Vector3(0.36, 0.32, 0.14), brass, Vector3(0, height * 0.45, -radius - 0.08), Vector3.ZERO, 0.04)
	ObjSvc.torus(v, 0.08, 0.13, iron, Vector3(0, height * 0.45 + 0.2, -radius - 0.08), Vector3(0, 0, 0))


## Little indicator lamps on the base, one per required switch.
func _build_lamps() -> void:
	_lamp_off = ObjSvc.unique_mat(Color(0.35, 0.1, 0.1), 0.4)
	_lamp_on = ObjSvc.unique_mat(Color(0.4, 1.0, 0.5), 0.3, 0.0, Color(0.4, 1.0, 0.5), 1.5)
	var n := _needed()
	for i in n:
		var a := PI * 0.5 + (float(i) - (n - 1) * 0.5) * 0.35
		var lamp := ObjSvc.sphere(self, 0.1, _lamp_off, Vector3(cos(a) * (radius + 0.3), 0.3, -sin(a) * (radius + 0.3)))
		_lights.append(lamp)


## Captive characters (generated GLBs dropped into Contents) breathe, glance and blink even while caged.
func _liven_contents() -> void:
	if _contents == null:
		return
	for c in _contents.get_children():
		if c is Node3D and c.get_script() == null and not (c as Node).find_children("*", "MeshInstance3D", true, false).is_empty():
			var life := NpcLife.attach(c as Node3D)
			life.process_mode = Node.PROCESS_MODE_ALWAYS
			# Captives grip the bars, rattle them when Mak comes near and plead (critique objects r1).
			life.set_caged(true)


func _needed() -> int:
	return required if required > 0 else maxi(_switch_nodes.size(), 1)


func pressed_count() -> int:
	var n := 0
	for s in _switch_nodes:
		if bool(s.get("is_pressed")):
			n += 1
	return n


func _on_switch(_s: Node) -> void:
	var n := pressed_count()
	for i in _lights.size():
		var was_on := _lights[i].material_override == _lamp_on
		_lights[i].material_override = _lamp_on if i < n else _lamp_off
		if i < n and not was_on:
			var lt := create_tween()
			lt.tween_property(_lights[i], "scale", Vector3.ONE * 1.8, 0.08)
			lt.tween_property(_lights[i], "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			ObjSvc.feedback("object_cage_lamp", _lights[i].global_position, {"lit": n, "needed": _needed()})
	if not is_open and n < _needed() and n > 0:
		_rattle(0.25, 2.0)
	if not is_open and n >= _needed():
		open()


## A quick shudder of the whole cage (anticipation, or a hint when a switch is pressed).
func _rattle(dur: float, deg: float) -> void:
	var tw := create_tween()
	var steps := int(dur / 0.05)
	for i in steps:
		var k := 1.0 - float(i) / float(maxi(steps, 1))
		tw.tween_property(_cage_body, "rotation:z", deg_to_rad(deg * k * (1.0 if i % 2 == 0 else -1.0)), 0.05)
	tw.tween_property(_cage_body, "rotation:z", 0.0, 0.05)


func open() -> void:
	if is_open:
		return
	is_open = true
	ObjSvc.feedback("object_cage_rattle", global_position + Vector3(0, height * 0.5, 0), {})
	_rattle(0.35, 3.5)
	var tw := create_tween()
	tw.tween_interval(0.38)
	tw.tween_callback(_open_door)
	tw.tween_interval(0.45 if _door else 0.0)
	tw.tween_callback(_lift_away)


## The door unlatches with a spark at the lock and flings open with an overshoot; the captives are released.
func _open_door() -> void:
	var at := global_position + Vector3(0, height * 0.45, 0)
	if _door:
		at = _door.global_position + Vector3(0, 0.4, 0)
	ObjSvc.feedback("object_cage_open", at, {}, "cage_open")
	if not ObjSvc.juice_handles("object_cage_open", "vfx"):
		ObjFx.flash(get_parent(), at, 1.0, 2.0, Color(1.0, 0.9, 0.5, 0.9), 0.25)
		ObjFx.star_ring(get_parent(), at, 6, 0.9, 0.35, Color(1.0, 0.9, 0.55), 0.4)
	if _door:
		var dt := create_tween()
		dt.tween_method(func(a: float) -> void: _door.basis = Basis(Vector3.UP, deg_to_rad(a)) * _door_rest, 0.0, -125.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		dt.tween_method(func(a: float) -> void: _door.basis = Basis(Vector3.UP, deg_to_rad(a)) * _door_rest, -125.0, -108.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _contents:
		_contents.process_mode = Node.PROCESS_MODE_INHERIT
		for c in _contents.get_children():
			if c.has_method("on_released"):
				c.call("on_released")
			else:
				var life := c.get_node_or_null("NpcLife")
				if life != null and life.has_method("release"):
					life.call("release")
				elif life != null and life.has_method("greet"):
					life.call("greet")
	opened.emit()


## The cage dips, then lifts off into the sky with a spin and vanishes in a sparkle.
func _lift_away() -> void:
	var tw := create_tween()
	tw.tween_property(_cage_body, "position:y", -0.12, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(_cage_body, "position:y", height + 4.0, 1.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_cage_body, "rotation:y", 1.4, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		ObjSvc.feedback("object_cage_vanish", _cage_body.global_position + Vector3(0, height * 0.5, 0), {})
		if not ObjSvc.juice_handles("object_cage_vanish", "vfx"):
			ObjSvc.burst(get_parent(), _cage_body.global_position + Vector3(0, height * 0.5, 0), Color(1, 0.9, 0.5), 30, 4.0, 0.2, -2.0, 1.0)
		_cage_body.visible = false
		for c in _cage_body.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = true)
	if not ObjSvc.juice_handles("object_cage_open", "vfx"):
		ObjSvc.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(1, 0.9, 0.5), 40, 5.0, 0.2, -4.0, 1.2)
	if reward_truffle_id != "":
		var t := create_tween()
		t.tween_interval(0.5)
		t.tween_callback(give_reward)

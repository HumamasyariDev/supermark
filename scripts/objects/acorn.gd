class_name Acorn
extends Area3D
## Acorn pickup: +1 acorn, heals one cake slice. Near the player it leaps into an arc (a homing Bezier that
## rises first, spins up and stretches along its path) and pops with a tiny star burst.
## Uses the Tripo P2 acorn (acorn_v3.glb: acorn_v2 mesh with the darker satin cap) by default. AcornGroup lays out lines, rings and arcs; crates pop_out().

signal picked(value: int)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var value: int = 1
## Extra healing on top of Game.add_acorns (which already restores one cake slice per acorn). Keep 0 normally.
@export var heal_amount: int = 0
@export var magnet_radius: float = 1.8
@export var magnet_speed: float = 9.0
@export var spin_speed: float = 2.6
@export var hover_height: float = 0.45
## Uses the generated acorn mesh when no visual_scene is set and the file exists.
@export var use_default_mesh: bool = true
## Seconds for the magnet arc from where it starts to Mak.
@export var arc_time: float = 0.3

const DEFAULT_MESH := "res://assets/props/pickups/acorn_v3/acorn_v3.glb"
const DEFAULT_MESH_SCALE := 1.15

var is_collected := false
var _t := 0.0
var _visual: Node3D
var _spinner: Node3D
var _vel := Vector3.ZERO
var _popping := false
var _pop_time := 0.0
var _homing := false
var _home_t := 0.0
var _home_from := Vector3.ZERO
var _home_side := Vector3.ZERO


func _ready() -> void:
	add_to_group("acorn")
	collision_layer = ObjSvc.L_PICKUP
	collision_mask = ObjSvc.L_PLAYER
	ObjSvc.add_shape(self, ObjSvc.sphere_shape(0.45), Vector3(0, hover_height, 0))
	if visual_scene == null and use_default_mesh and ResourceLoader.exists(DEFAULT_MESH):
		visual_scene = load(DEFAULT_MESH) as PackedScene
		if is_equal_approx(visual_scale, 1.0):
			visual_scale = DEFAULT_MESH_SCALE
	_visual = ObjSvc.ensure_visual(self)
	_spinner = Node3D.new()
	_spinner.position = Vector3(0, hover_height, 0)
	add_child(_spinner)
	_visual.reparent(_spinner, false)
	if not ObjSvc.visual_has_content(_visual):
		_build_placeholder()
		# Many acorns per world: share one baked mesh (3 surfaces) instead of five meshes each.
		ObjSvc.bake_visual(_visual, "acorn_placeholder")
	else:
		ObjSvc.center_generated(_visual)
	ObjSvc.shadow_blob(self, 0.24, 0.02, 0.55)
	_t = randf() * TAU
	body_entered.connect(_on_body_entered)
	_unbury.call_deferred()


## Lifts the acorn out of world collision a builder buried it in (critique objects r1). Round 1 QA: acorns of one
## ring or line (an AcornGroup, or siblings named <id>_<n>) move together by the largest offset any of them needs,
## so a ring keeps its shape, and the group prints one summary line instead of one warning per acorn.
static var _unbury_sets: Dictionary = {}


func _unbury_key() -> String:
	var par := get_parent()
	if par == null:
		return str(get_instance_id())
	if par is AcornGroup:
		return "g%d" % par.get_instance_id()
	var nm := String(name)
	var cut := nm.rfind("_")
	if cut > 0 and nm.substr(cut + 1).is_valid_int():
		return "p%d:%s" % [par.get_instance_id(), nm.substr(0, cut)]
	return str(get_instance_id())


func _unbury() -> void:
	if not is_inside_tree():
		return
	var key := _unbury_key()
	var set_list: Array = _unbury_sets.get(key, [])
	set_list.append(self)
	_unbury_sets[key] = set_list
	if set_list.size() > 1:
		return  # the first acorn of the set handles all of them
	await get_tree().physics_frame
	var members: Array = _unbury_sets.get(key, [])
	_unbury_sets.erase(key)
	var live: Array[Acorn] = []
	for m in members:
		if is_instance_valid(m) and (m as Acorn).is_inside_tree() and not (m as Acorn)._popping and not (m as Acorn).is_collected:
			live.append(m)
	if live.is_empty():
		return
	if live.size() == 1:
		ObjSvc.unbury(live[0], Vector3(0, live[0].hover_height, 0), 0.16)
		return
	var best := Vector3.ZERO
	var buried := 0
	var stuck := 0
	for a in live:
		var off: Variant = ObjSvc.unbury_offset(a, Vector3(0, a.hover_height, 0), 0.16)
		if off == null:
			stuck += 1
			continue
		if (off as Vector3) != Vector3.ZERO:
			buried += 1
			if (off as Vector3).length() > best.length():
				best = off
	if buried == 0 and stuck == 0:
		return
	if best != Vector3.ZERO:
		for a in live:
			a.global_position += best
			a.reset_physics_interpolation()
	var still := 0
	for a in live:
		if ObjSvc.unbury(a, Vector3(0, a.hover_height, 0), 0.16, 1.5, true) != 0.0:
			still += 1
	push_warning("[ObjSvc] unburied acorn set %s (%s): %d of %d buried, all moved by %s, %d fixed one by one (builders: move it)" % [
		live[0].get_parent().get_path(), key.get_slice(":", 1) if ":" in key else "group", buried + stuck, live.size(),
		str(best.snapped(Vector3.ONE * 0.01)), still])


func _build_placeholder() -> void:
	var nut := ObjSvc.mat(Color(0.78, 0.47, 0.2), 0.35, 0.0, Color(1.0, 0.6, 0.2), 0.15)
	var cap := ObjSvc.mat(Color(0.45, 0.27, 0.12), 0.8)
	ObjSvc.sphere(_visual, 0.16, nut, Vector3(0, -0.03, 0), Vector3(1.0, 1.2, 1.0))
	ObjSvc.cone(_visual, 0.05, 0.08, nut, Vector3(0, -0.24, 0), Vector3(180, 0, 0))
	ObjSvc.sphere(_visual, 0.18, cap, Vector3(0, 0.1, 0), Vector3(1.0, 0.55, 1.0))
	ObjSvc.cylinder(_visual, 0.015, 0.025, 0.1, cap, Vector3(0.02, 0.22, 0), Vector3(0, 0, -20))
	# Specular glint so it reads as a pickup.
	ObjSvc.sphere(_visual, 0.035, ObjSvc.unshaded(Color(1, 1, 0.9, 0.9)), Vector3(0.07, 0.0, 0.13))


## Launch the acorn (from a crate) with a ballistic hop before it settles.
func pop_out(velocity: Vector3) -> void:
	_vel = velocity
	_popping = true
	_pop_time = 0.0
	set_deferred("monitoring", false)


func _process(delta: float) -> void:
	if is_collected:
		return
	_t += delta
	if _homing:
		_spinner.rotation.y += spin_speed * 6.0 * delta
		return
	_spinner.rotation.y += spin_speed * delta
	_spinner.position.y = hover_height + sin(_t * 3.0) * 0.06
	# A small tilt wobble so rows of acorns do not move in lockstep like a machine.
	_spinner.rotation.z = sin(_t * 2.1) * 0.12


func _physics_process(delta: float) -> void:
	if is_collected:
		return
	if _popping:
		_pop_time += delta
		_vel.y -= 20.0 * delta
		global_position += _vel * delta
		var floor_y := _floor_height()
		if global_position.y <= floor_y and _vel.y < 0.0:
			global_position.y = floor_y
			if absf(_vel.y) > 2.5:
				_vel = Vector3(_vel.x * 0.5, -_vel.y * 0.35, _vel.z * 0.5)
			else:
				_popping = false
				monitoring = true
		if _pop_time > 0.35 and not monitoring:
			monitoring = true
		return
	var p := ObjSvc.get_player()
	if p == null:
		return
	var target := ObjSvc.body_pos(p) + Vector3(0, 0.6, 0)
	if _homing:
		_home_step(delta, target)
		return
	var d := target - (global_position + Vector3(0, hover_height, 0))
	if d.length() < magnet_radius:
		_start_homing(target)


func _start_homing(target: Vector3) -> void:
	_homing = true
	_home_t = 0.0
	_home_from = global_position + Vector3(0, hover_height, 0)
	var flat := target - _home_from
	flat.y = 0.0
	# Curl to one side a little, as if flicked toward Mak.
	_home_side = flat.normalized().cross(Vector3.UP) * (0.35 if randf() > 0.5 else -0.35)
	ObjSvc.feedback("object_acorn_magnet", _home_from, {})
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3(1.25, 0.75, 1.25), 0.05)
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.12)


## Quadratic Bezier from the start to Mak's chest: the control point sits above the midpoint, so the acorn hops
## up and drops in. Eased in (slow start, fast arrival); the target follows Mak every tick.
func _home_step(delta: float, target: Vector3) -> void:
	_home_t = minf(1.0, _home_t + delta / maxf(arc_time, 0.05))
	var u := _home_t * _home_t * (1.6 - 0.6 * _home_t)
	var ctrl := (_home_from + target) * 0.5 + Vector3(0, 0.9 + _home_from.distance_to(target) * 0.25, 0) + _home_side
	var a := _home_from.lerp(ctrl, u)
	var b := ctrl.lerp(target, u)
	var pos := a.lerp(b, u)
	var vel := (b - a)
	global_position = pos - Vector3(0, hover_height, 0)
	_spinner.position.y = hover_height
	# Stretch along the flight direction.
	var st := clampf(vel.length() * 0.08, 0.0, 0.35)
	_visual.scale = Vector3(1.0 - st * 0.4, 1.0 + st, 1.0 - st * 0.4)
	if _home_t >= 1.0 or pos.distance_to(target) < 0.25:
		collect()


func _floor_height() -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0), global_position + Vector3(0, -30, 0), ObjSvc.L_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return global_position.y - 100.0
	return (hit.position as Vector3).y


func _on_body_entered(body: Node) -> void:
	if ObjSvc.is_player(body):
		collect()


func collect() -> void:
	if is_collected:
		return
	is_collected = true
	set_deferred("monitoring", false)
	var g := ObjSvc.autoload("Game")
	var h0: int = int(g.get("health")) if g != null and "health" in g else -1
	ObjSvc.call_on("Game", "add_acorns", [value])
	if h0 >= 0 and int(g.get("health")) > h0:
		ObjSvc.feedback("player_heal", Vector3.INF, {"amount": int(g.get("health")) - h0, "node": ObjSvc.get_player()})
	if heal_amount > 0:
		ObjSvc.call_on("Game", "heal", [heal_amount])
	ObjSvc.visit_acorns += value
	get_tree().call_group("acorn_listener", "on_acorn_collected", ObjSvc.acorns_this_visit())
	var sp := _spinner.global_position
	ObjSvc.feedback("object_acorn_collect", sp, {"value": value, "count": ObjSvc.acorns_this_visit()}, "acorn")
	picked.emit(value)
	if not ObjSvc.juice_handles("object_acorn_collect", "vfx"):
		if not ObjSvc.fx(self, "CollectPop", sp):
			ObjSvc.burst(get_parent(), sp, Color(1.0, 0.8, 0.4), 10, 2.5, 0.12, -2.0, 0.5)
		ObjFx.star_ring(get_parent(), sp, 4, 0.55, 0.26, Color(1.0, 0.85, 0.5), 0.3)
		ObjFx.flash(get_parent(), sp, 0.7, 1.4, Color(1.0, 0.85, 0.5, 0.7), 0.18)
	_homing = false
	_visual.scale = Vector3.ONE
	var tw := create_tween()
	tw.tween_property(_spinner, "scale", Vector3.ONE * 1.45, 0.06).set_ease(Tween.EASE_OUT)
	tw.tween_property(_spinner, "scale", Vector3.ONE * 0.01, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

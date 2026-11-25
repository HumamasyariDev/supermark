class_name BellowsMachine
extends StaticBody3D
## A big wolf-built bellows on an iron frame, pumping a linked WindZone in time with its strokes.
## A Ham Slam on the top board breaks it: boards fly apart, the gust stops, `broken` is emitted.
## A BellowsSet (same group_id) spawns a truffle when every bellows in the group is broken.

signal broken(bellows: Node)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var wind_zone_path: NodePath
@export var group_id: String = "bellows"
@export var pump_period: float = 1.6
@export var leather_color: Color = Color(0.55, 0.32, 0.18)
@export var start_broken: bool = false
## Generated busted model swapped in on the Ham Slam. Empty: `<visual_scene>_busted.glb` next to the visual when it
## exists (bellows_machine_v2/_v3 ship one), otherwise the generated model sags and tilts.
@export var busted_scene: PackedScene

var is_broken := false
var _t := 0.0
var _visual: Node3D
var _top: Node3D
var _folds: Array[Node3D] = []
var _nozzle_puff: GPUParticles3D
var _wind: Node
var _sensor: SlamSensor
var _was_blowing := false
var _needle: Node3D
var _wheel: Node3D
## The instanced generated model (null for the primitive placeholder) and its rest transform.
var _gen: Node3D
var _gen_rest := Transform3D()
var _smoke_t := 0.0


func _ready() -> void:
	add_to_group("bellows")
	add_to_group("bellows_" + group_id)
	collision_layer = ObjSvc.L_WORLD
	collision_mask = 0
	ObjSvc.add_shape(self, ObjSvc.box_shape(Vector3(2.4, 1.6, 3.2)), Vector3(0, 0.8, 0))
	_visual = ObjSvc.ensure_visual(self)
	if not ObjSvc.visual_has_content(_visual):
		_build_placeholder()
	else:
		_gen = _visual.get_node_or_null("Generated") as Node3D
		if _gen:
			_gen_rest = _gen.transform
		if busted_scene == null and visual_scene != null and visual_scene.resource_path.ends_with(".glb"):
			var bp := visual_scene.resource_path.trim_suffix(".glb") + "_busted.glb"
			if ResourceLoader.exists(bp):
				busted_scene = load(bp) as PackedScene
	_sensor = SlamSensor.create(self, 1.3, 1.0, Vector3(0, 1.55, 0.2))
	_sensor.slammed.connect(func(_by: Node) -> void: break_bellows())
	if not wind_zone_path.is_empty():
		_wind = get_node_or_null(wind_zone_path)
	if start_broken:
		call_deferred("break_bellows", true)


func _build_placeholder() -> void:
	var iron := ObjSvc.mat(ObjSvc.IRON, 0.4, 0.85)
	var wood := ObjSvc.mat(Color(0.5, 0.3, 0.16), 0.7)
	var leather := ObjSvc.mat(leather_color, 0.85)
	var brass := ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.85)
	var red := ObjSvc.mat(Color(0.75, 0.12, 0.1), 0.5)
	# Iron cradle with riveted legs.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			ObjSvc.cylinder(_visual, 0.08, 0.12, 0.6, iron, Vector3(sx * 1.05, 0.3, sz * 1.3))
	ObjSvc.box(_visual, Vector3(2.3, 0.12, 3.0), iron, Vector3(0, 0.6, 0))
	# Bottom board (fixed), a teardrop-shaped paddle.
	ObjSvc.soft_box(_visual, Vector3(2.0, 0.16, 2.6), wood, Vector3(0, 0.72, 0.1), Vector3.ZERO, 0.06)
	# Leather folds between the boards.
	for i in 3:
		var f := Node3D.new()
		f.position = Vector3(0, 0.88 + i * 0.16, 0.1)
		_visual.add_child(f)
		ObjSvc.sphere(f, 0.5, leather, Vector3.ZERO, Vector3(1.9, 0.26, 2.5))
		_folds.append(f)
	# Top board pivots at the back hinge, near the nozzle end (front is -Z).
	_top = Node3D.new()
	_top.name = "TopBoard"
	_top.position = Vector3(0, 1.32, -1.15)
	_visual.add_child(_top)
	ObjSvc.soft_box(_top, Vector3(2.0, 0.16, 2.6), wood, Vector3(0, 0, 1.25), Vector3.ZERO, 0.06)
	# Handles at the back.
	ObjSvc.cylinder(_top, 0.07, 0.07, 1.4, wood, Vector3(0, 0.0, 2.75), Vector3(0, 0, 90))
	# Wolf emblem plate on top: a red shield with a white wolf head, painted crudely by the henchmen.
	ObjSvc.cylinder(_top, 0.45, 0.45, 0.04, red, Vector3(0, 0.1, 1.3))
	var w := Node3D.new()
	w.position = Vector3(0, 0.13, 1.3)
	_top.add_child(w)
	var white := ObjSvc.mat(Color(0.95, 0.95, 0.95), 0.6)
	ObjSvc.sphere(w, 0.18, white, Vector3.ZERO, Vector3(1, 0.25, 1))
	ObjSvc.cone(w, 0.08, 0.18, white, Vector3(-0.12, 0, -0.18), Vector3(-90, 0, 0))
	ObjSvc.cone(w, 0.08, 0.18, white, Vector3(0.12, 0, -0.18), Vector3(-90, 0, 0))
	ObjSvc.sphere(w, 0.09, white, Vector3(0, 0, 0.2), Vector3(0.8, 0.25, 1.4))
	# Brass nozzle at the front (-Z).
	ObjSvc.cylinder(_visual, 0.12, 0.3, 0.9, brass, Vector3(0, 1.0, -1.6), Vector3(-90, 0, 0))
	ObjSvc.torus(_visual, 0.1, 0.17, brass, Vector3(0, 1.0, -2.05), Vector3(90, 0, 0))
	_nozzle_puff = ObjSvc.sparkles(_visual, Color(1, 1, 1, 0.6), 12, 0.15, 0.45, 0.6, 4.0)
	_nozzle_puff.position = Vector3(0, 1.0, -2.1)
	var pm := _nozzle_puff.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 18.0
	(_nozzle_puff.draw_pass_1 as QuadMesh).material = ObjSvc.sparkle_mat(Color.WHITE)
	# Iron bands and rivets across the top board.
	for bz in [0.45, 2.05]:
		ObjSvc.box(_top, Vector3(2.04, 0.04, 0.14), iron, Vector3(0, 0.09, bz))
		for bx in [-0.85, 0.0, 0.85]:
			ObjSvc.sphere(_top, 0.035, iron, Vector3(bx, 0.12, bz))
	# Wolf ears on the back corners of the top board: the henchmen's idea of decoration.
	var ear := ObjSvc.mat(Color(0.42, 0.42, 0.46), 0.6)
	var ear_in := ObjSvc.mat(Color(0.9, 0.55, 0.55), 0.6)
	for sx in [-1.0, 1.0]:
		ObjSvc.cone(_top, 0.16, 0.36, ear, Vector3(sx * 0.82, 0.25, 2.35), Vector3(-10, 0, -sx * 14))
		ObjSvc.cone(_top, 0.08, 0.22, ear_in, Vector3(sx * 0.82, 0.22, 2.29), Vector3(-10, 0, -sx * 14))
	# A patched leather fold.
	ObjSvc.sphere(_folds[1], 0.16, ObjSvc.mat(leather_color.darkened(0.3), 0.9), Vector3(0.75, 0.08, -0.6), Vector3(1.2, 0.3, 1.0))
	# Pressure gauge on a pipe at the side; the needle jumps on each blast.
	var gauge := Node3D.new()
	gauge.position = Vector3(1.25, 1.25, -0.9)
	_visual.add_child(gauge)
	ObjSvc.cylinder(_visual, 0.04, 0.04, 0.7, iron, Vector3(1.18, 0.9, -0.9))
	ObjSvc.cylinder(gauge, 0.2, 0.2, 0.08, brass, Vector3.ZERO, Vector3(0, 0, 90))
	ObjSvc.cylinder(gauge, 0.17, 0.17, 0.02, ObjSvc.mat(ObjSvc.PAPER, 0.6), Vector3(0.045, 0, 0), Vector3(0, 0, 90))
	ObjSvc.box(gauge, Vector3(0.01, 0.06, 0.02), ObjSvc.mat(ObjSvc.HAZARD_RED, 0.5), Vector3(0.05, 0.1, 0.1), Vector3(-50, 0, 0))
	_needle = Node3D.new()
	_needle.position = Vector3(0.06, 0, 0)
	gauge.add_child(_needle)
	ObjSvc.box(_needle, Vector3(0.012, 0.15, 0.02), ObjSvc.mat(Color(0.1, 0.08, 0.08), 0.4), Vector3(0, 0.07, 0))
	# Crank wheel at the back, turning with the pump.
	_wheel = Node3D.new()
	_wheel.position = Vector3(-1.22, 1.0, 1.0)
	_visual.add_child(_wheel)
	ObjSvc.torus(_wheel, 0.32, 0.4, iron, Vector3.ZERO, Vector3(0, 0, 90))
	for k in 4:
		ObjSvc.box(_wheel, Vector3(0.05, 0.7, 0.05), iron, Vector3.ZERO, Vector3(k * 45.0, 0, 0))
	ObjSvc.sphere(_wheel, 0.08, brass, Vector3.ZERO)
	ObjSvc.cylinder(_wheel, 0.035, 0.035, 0.3, wood, Vector3(-0.15, 0.3, 0), Vector3(0, 0, 90))
	# Warning stripes so it reads as a machine to smash.
	for i in 4:
		ObjSvc.box(_visual, Vector3(0.3, 0.13, 0.05), ObjSvc.mat(Color(1, 0.8, 0.15) if i % 2 else Color(0.15, 0.12, 0.1), 0.6), Vector3(-0.45 + i * 0.3, 0.6, -1.52))


func _process(delta: float) -> void:
	if is_broken:
		_broken_smoke(delta)
		return
	_t += delta
	var ph := fposmod(_t / pump_period, 1.0)
	# Slow lift, fast squeeze: the squeeze is when air blasts out.
	var open := 0.0
	if ph < 0.65:
		open = ease(ph / 0.65, 0.6)
	else:
		open = 1.0 - ease((ph - 0.65) / 0.35, 2.4)
	if _top:
		_top.rotation.x = -open * 0.32
	for i in _folds.size():
		var f := _folds[i]
		f.position.y = 0.88 + i * (0.08 + open * 0.13)
		f.scale = Vector3(1.0 + (1.0 - open) * 0.06, 0.7 + open * 0.6, 1.0)
	var blowing := ph >= 0.65
	if _gen:
		# A one-piece generated machine: the whole cart breathes. It swells on the slow intake, then squeezes flat
		# with a kick back along the nozzle axis on the blast, and settles with a little wobble.
		var sq := 1.0 - (1.0 - open) * 0.07
		var wob := sin(_t * 26.0) * 0.012 * (1.0 if blowing else 0.0) * (1.0 - open)
		var b := _gen_rest.basis.scaled_local(Vector3(1.0 + (1.0 - open) * 0.035, sq + wob, 1.0 + (1.0 - open) * 0.02))
		_gen.transform = Transform3D(b, _gen_rest.origin + Vector3(0, 0, 0.06 * (1.0 - open) * (1.0 if blowing else 0.0)))
	if _needle:
		_needle.rotation.x = lerpf(-1.0, 1.1, open) + (sin(_t * 40.0) * 0.08 if blowing else 0.0)
	if _wheel:
		_wheel.rotation.x = -_t * TAU / pump_period
	if blowing and not _was_blowing:
		ObjSvc.feedback("object_bellows_blast", global_position + Vector3(0, 1.2, 0), {"direction": -global_basis.z}, "bellows_pump")
	_was_blowing = blowing
	if _nozzle_puff:
		_nozzle_puff.emitting = blowing
	if _wind != null:
		_wind.set("drive", 1.0 if blowing else 0.25)


## The real player calls this on the floor collider after a Ham Slam impact.
func hit_by_player(kind: String, _from_position: Vector3) -> bool:
	if kind == "slam" and not is_broken:
		break_bellows()
		return true
	return false


func break_bellows(silent: bool = false) -> void:
	if is_broken:
		return
	is_broken = true
	_smoke_t = 1.2
	if _wind != null:
		if _wind.has_method("set_enabled"):
			_wind.call("set_enabled", false)
		_wind.set("drive", 0.0)
	if _nozzle_puff:
		_nozzle_puff.emitting = false
	if not silent:
		ObjSvc.feedback("object_bellows_break", global_position, {}, "bellows_break")
		if not ObjSvc.juice_handles("object_bellows_break", "vfx"):
			ObjSvc.burst(get_parent(), global_position + Vector3(0, 1.4, 0), Color(0.85, 0.65, 0.4), 30, 6.0, 0.25, -12.0, 1.0)
		ObjSvc.burst(get_parent(), global_position + Vector3(0, 1.2, -1.8), Color(1, 1, 1), 20, 3.0, 0.5, 1.0, 0.9)
		ObjSvc.fx(self, "DustPuff", global_position + Vector3(0, 1.4, 0))
		ObjSvc.fx(self, "HitStars", global_position + Vector3(0, 1.8, 0))
	if _gen:
		_bust_generated(silent)
	# The top board flips off and the leather sags flat.
	if _top:
		var tw := create_tween().set_parallel()
		var dur := 0.01 if silent else 0.7
		tw.tween_property(_top, "rotation", Vector3(-1.9, 0.5, 0.4), dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_top, "position", _top.position + Vector3(0.6, 0.3, -0.5), dur)
		for i in _folds.size():
			tw.tween_property(_folds[i], "scale", Vector3(1.1, 0.25, 1.05), dur * 0.6)
			tw.tween_property(_folds[i], "position:y", 0.82 + i * 0.03, dur * 0.6)
	broken.emit(self)
	get_tree().call_group("bellows_listener", "on_bellows_broken", group_id)


## Generated model: a hard squash on the hit, then the busted model (or a sagging, tilted original) pops in.
func _bust_generated(silent: bool) -> void:
	if silent:
		_swap_busted()
		return
	var tw := create_tween()
	tw.tween_method(_squash_hit, 0.0, 1.0, 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_swap_busted)
	tw.tween_method(_settle_busted, 0.0, 1.0, 0.5)


func _squash_hit(k: float) -> void:
	_gen.transform = Transform3D(_gen_rest.basis.scaled_local(Vector3(1.0 + 0.16 * k, 1.0 - 0.3 * k, 1.0 + 0.1 * k)), _gen_rest.origin)


func _swap_busted() -> void:
	if busted_scene != null:
		var nb := busted_scene.instantiate() as Node3D
		if nb != null:
			nb.name = "GeneratedBusted"
			_gen.queue_free()
			nb.transform = _gen_rest
			_visual.add_child(nb)
			_gen = nb
			_fit_collision_to_wreck()
			return
	_gen.transform = _sagged()
	_fit_collision_to_wreck()


## Critique objects r1: the busted wreck is lower than the working cart, so the collision (ours and any box a builder
## added) shrinks to the wreck's measured top with a springy settle; Mak no longer stands in mid-air above it.
@export var busted_collision_height: float = 0.0


func _fit_collision_to_wreck() -> void:
	var top := busted_collision_height
	if top <= 0.0:
		# Measure only the new shape (the old model is still in the tree until the end of the frame).
		var bb := ObjSvc.local_aabb(_gen)
		var xf := _visual.transform * (_gen_rest if busted_scene != null else _sagged())
		top = (xf * bb).end.y if bb.size.y > 0.1 else 0.0
	if top <= 0.2:
		return
	for c in get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var box := (cs.shape as BoxShape3D).duplicate() as BoxShape3D
		var bottom := cs.position.y - box.size.y * 0.5
		var want := top - bottom
		if want >= box.size.y - 0.02 or want <= 0.1:
			continue
		cs.shape = box
		var from_h := box.size.y
		var tw := create_tween()
		tw.tween_method(func(h: float) -> void:
			box.size.y = h
			cs.position.y = bottom + h * 0.5, from_h, want, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _sensor:
		_sensor.position.y = minf(_sensor.position.y, top)


func _sagged() -> Transform3D:
	return Transform3D(_gen_rest.basis.scaled_local(Vector3(1.04, 0.82, 1.0)) * Basis(Vector3(0, 0, 1), 0.09), _gen_rest.origin)


## Springy settle of the new shape (a decaying squash-and-stretch wobble).
func _settle_busted(k: float) -> void:
	if not is_instance_valid(_gen):
		return
	var s := 1.0 + sin(k * PI * 3.0) * 0.08 * (1.0 - k)
	var rest := _gen_rest if busted_scene != null else _sagged()
	_gen.transform = Transform3D(rest.basis.scaled_local(Vector3(2.0 - s, s, 2.0 - s)), rest.origin)


## A broken machine keeps wheezing: a grey puff from the split leather every second or so.
func _broken_smoke(delta: float) -> void:
	if _gen == null:
		return
	_smoke_t -= delta
	if _smoke_t > 0.0:
		return
	_smoke_t = randf_range(1.05, 1.35)
	if not is_visible_in_tree():
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam and cam.global_position.distance_to(global_position) > 40.0:
		return
	# Critique objects r1: bigger, darker wheezes with a creak and a shudder of the wreck, so it reads as broken
	# but still gasping (not dead).
	var at := global_position + global_basis * Vector3(randf_range(-0.4, 0.4), 1.25 * visual_scale, randf_range(-0.6, 0.6))
	ObjFx.puffs(get_parent(), at, Color(0.36, 0.34, 0.33, 0.78), 5, 0.5, 0.75, 1.3)
	ObjSvc.sfx("platform_creak", at)
	if is_instance_valid(_gen):
		var rest := _gen_rest if busted_scene != null else _sagged()
		var tw := create_tween()
		tw.tween_property(_gen, "transform", Transform3D(rest.basis.scaled_local(Vector3(1.05, 0.93, 1.05)), rest.origin), 0.08)
		tw.tween_property(_gen, "transform", rest, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

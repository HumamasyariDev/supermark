extends Node3D
## W3-8 "The Cauldron's Secret" chain: Ham Slam the cauldron lid -> a steam puff races along the
## liquorice pipe (3 s) -> the Strawberry Syrup Falls stop for `stop_seconds` (warning trickle in the last
## `warn_seconds`) -> the curtain wind zone is off, so the pool-rock jumps into the grotto work.
## Children it expects (built by w3_bake.gd): Lid (Node3D), Curtain (Node3D), Foam (optional),
## and `wind_zone_path` -> WindZone. `pipe_points` are world positions for the puff.

signal falls_changed(running: bool)

@export var wind_zone_path: NodePath
@export var curtain_path: NodePath
@export var lid_path: NodePath
@export var foam_path: NodePath
@export var pipe_points: PackedVector3Array = PackedVector3Array()
@export var lid_top := Vector3(3, 9.9, -29)
@export var stop_seconds := 35.0
@export var warn_seconds := 3.0
@export var puff_seconds := 3.0

var falls_running := true
var _busy := false
var _sensor: SlamSensor


func _ready() -> void:
	_sensor = SlamSensor.create(self, 1.6, 1.0, to_local(lid_top) + Vector3(0, -0.3, 0))
	_sensor.slammed.connect(_on_slam)
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_arg("w3-falls-off"):
		call_deferred("_set_falls", false)


func is_falls_running() -> bool:
	return falls_running


func _on_slam(_by: Node) -> void:
	if _busy:
		return
	_busy = true
	print("[W3] cauldron lid slammed: falls stop chain started")
	ObjSvc.sfx("pop", lid_top)
	var lid := get_node_or_null(lid_path) as Node3D
	if lid:
		var base := lid.position
		var tw := create_tween()
		tw.tween_property(lid, "position", base + Vector3(0, 2.2, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(lid, "rotation_degrees", Vector3(25, 40, 10), 0.35)
		tw.tween_property(lid, "position", base, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(lid, "rotation_degrees", Vector3.ZERO, 0.45)
	await _puff()
	_set_falls(false)
	ObjSvc.call_on("UI", "toast", ["The syrup falls have stopped!"])
	ObjSvc.call_on("UI", "timer_start", ["Falls stopped", stop_seconds])
	await get_tree().create_timer(stop_seconds - warn_seconds, false, true).timeout
	ObjSvc.call_on("UI", "toast", ["The falls are trickling back..."])
	_trickle(true)
	await get_tree().create_timer(warn_seconds, false, true).timeout
	_trickle(false)
	_set_falls(true)
	ObjSvc.call_on("UI", "timer_hide")
	_busy = false


func _puff() -> void:
	if pipe_points.size() < 2:
		await get_tree().create_timer(0.5, false, true).timeout
		return
	var puff := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	puff.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 1.0, 0.85)
	m.emission_enabled = true
	m.emission = Color(0.55, 1.0, 0.8)
	m.emission_energy_multiplier = 2.5
	puff.material_override = m
	add_child(puff)
	var total := 0.0
	for i in pipe_points.size() - 1:
		total += pipe_points[i].distance_to(pipe_points[i + 1])
	var tw := create_tween()
	puff.global_position = pipe_points[0]
	for i in range(1, pipe_points.size()):
		var seg := pipe_points[i - 1].distance_to(pipe_points[i])
		tw.tween_property(puff, "global_position", pipe_points[i], puff_seconds * seg / total)
	await tw.finished
	ObjSvc.burst(self, puff.global_position, Color(0.8, 1.0, 0.9), 30, 4.0, 0.3, -2.0, 1.0)
	ObjSvc.sfx("valve", puff.global_position)
	puff.queue_free()


func _set_falls(on: bool) -> void:
	falls_running = on
	var wz := get_node_or_null(wind_zone_path)
	if wz and wz.has_method("set_enabled"):
		wz.call("set_enabled", on)
	var cur := get_node_or_null(curtain_path) as Node3D
	if cur:
		var tw := create_tween()
		if on:
			cur.visible = true
			tw.tween_property(cur, "scale", Vector3.ONE, 1.2).from(Vector3(1, 0.05, 1))
		else:
			tw.tween_property(cur, "scale", Vector3(1, 0.02, 1), 1.0)
			tw.tween_callback(func() -> void: cur.visible = false)
	var foam := get_node_or_null(foam_path) as Node3D
	if foam:
		foam.visible = on
	print("[W3] falls_state=%s" % ("on" if on else "off"))
	falls_changed.emit(on)


func _trickle(on: bool) -> void:
	var cur := get_node_or_null(curtain_path) as Node3D
	if cur == null:
		return
	if on:
		cur.visible = true
		cur.scale = Vector3(0.25, 1.0, 1.0)
	else:
		cur.scale = Vector3.ONE

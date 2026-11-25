extends AnimatableBody3D
## W3 jelly sinker (R1.2a): squashes 0.15 m on landing; after `sink_after` s of standing it sinks `sink_depth` m
## over 0.3 s and recovers 0.6 s after Mak leaves. Child "Visual" wobbles.

@export var sink_after := 0.8
@export var sink_depth := 0.5
@export var top_local := 0.75
@export var pad := 1.6   ## m, footprint of the stand sensor (R1: 2.4 m cubes)

var _base := Vector3.ZERO
var _stood := 0.0
var _off := 0.0
var _away := 0.0
var _sensor: Area3D
var _wob := 0.0


func _ready() -> void:
	_base = position
	sync_to_physics = false
	_sensor = Area3D.new()
	_sensor.collision_layer = 0
	_sensor.collision_mask = 2
	_sensor.monitorable = false
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(pad, 0.5, pad)
	cs.shape = b
	cs.position = Vector3(0, top_local + 0.25, 0)
	_sensor.add_child(cs)
	add_child(_sensor)
	_sensor.body_entered.connect(func(n: Node) -> void:
		if n.is_in_group("player"):
			_wob = 1.0
			ObjSvc.sfx("jelly_wobble", global_position))


func _physics_process(delta: float) -> void:
	var on := false
	for n in _sensor.get_overlapping_bodies():
		if n.is_in_group("player"):
			on = true
	if on:
		_stood += delta
		_away = 0.0
	else:
		_away += delta
		if _away > 0.6:
			_stood = 0.0
	var target := -sink_depth if _stood > sink_after else 0.0
	_off = move_toward(_off, target, delta * (sink_depth / 0.3 if target < 0.0 else 1.0))
	position = _base + Vector3(0, _off, 0)
	_wob = maxf(0.0, _wob - delta * 1.6)
	var v := get_node_or_null("Visual") as Node3D
	if v:
		var t := Time.get_ticks_msec() * 0.02
		var s := 1.0 + sin(t) * 0.08 * _wob
		v.scale = Vector3(1.0 / sqrt(s), s - 0.1 * float(on), 1.0 / sqrt(s))

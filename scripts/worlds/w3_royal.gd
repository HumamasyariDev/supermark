extends AnimatableBody3D
## W3-3 "The Dunk Run" (R1.5): the Royal Digestive. Moored at its first path point until `release()`, then drifts
## along `points` at `speed`; at the end (the Chocolate Falls lip) it tips over and respawns moored after
## `respawn_s`. Never sags. The W3-3 truffle rides it as a child (added by w3_level.gd).

signal released
signal tipped

@export var points := PackedVector3Array()
@export var speed := 1.6
@export var respawn_s := 5.0

var moving := false
var _d := 0.0
var _len := 0.0
var _cum := PackedFloat32Array()
var _tipping := false


func _ready() -> void:
	sync_to_physics = false
	_cum.append(0.0)
	for i in points.size() - 1:
		_len += points[i].distance_to(points[i + 1])
		_cum.append(_len)
	if points.size() > 0:
		global_position = points[0]


func release() -> void:
	if moving or _tipping:
		return
	moving = true
	_d = 0.0
	print("[W3] royal digestive released")
	released.emit()


func _pos(d: float) -> Vector3:
	for i in points.size() - 1:
		if d <= _cum[i + 1] or i == points.size() - 2:
			var seg := maxf(_cum[i + 1] - _cum[i], 0.001)
			return points[i].lerp(points[i + 1], clampf((d - _cum[i]) / seg, 0.0, 1.0))
	return points[points.size() - 1]


func _physics_process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if not moving:
		if not _tipping and points.size() > 0:
			global_position = points[0] + Vector3(0, sin(t * 1.3) * 0.04, 0)
			rotation_degrees = Vector3(sin(t * 0.9) * 1.2, rotation_degrees.y, cos(t * 1.1) * 1.2)
		return
	_d += speed * delta
	global_position = _pos(_d) + Vector3(0, sin(t * 1.3) * 0.05, 0)
	rotation_degrees.y += 6.0 * delta
	if _d >= _len:
		_tip()


func _tip() -> void:
	moving = false
	_tipping = true
	print("[W3] royal digestive over the falls")
	tipped.emit()
	ObjSvc.call_on("UI", "toast", ["The Royal Digestive went over the falls!"])
	var tw := create_tween()
	tw.tween_property(self, "rotation_degrees:z", 70.0, 0.6)
	tw.parallel().tween_property(self, "global_position", global_position + Vector3(3.0, -14.0, 0.5), 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(respawn_s, false, true).timeout
	rotation_degrees = Vector3.ZERO
	global_position = points[0]
	reset_physics_interpolation()
	_tipping = false

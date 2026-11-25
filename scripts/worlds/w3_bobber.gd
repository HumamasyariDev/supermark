extends Node3D
## W3 ambient motion helper: sine bob, constant spin, gentle sway and horizontal drift with wrap.
## Physics children (gumdrops, platforms) are moved in _physics_process when `physics` is on.

@export var bob_amp := 0.0
@export var bob_period := 3.0
@export var bob_phase_deg := 0.0
@export var spin_deg_per_s := Vector3.ZERO
@export var sway_deg := 0.0
@export var sway_period := 4.0
@export var drift := Vector3.ZERO
@export var drift_wrap := 0.0
@export var physics := false

var _base_pos: Vector3
var _base_rot: Vector3
var _t := 0.0
var _started := false


## Base pose is captured on the first step, so callers may set position after add_child.
func _begin() -> void:
	_started = true
	_base_pos = position
	_base_rot = rotation_degrees
	_t = fposmod(position.x * 0.37 + position.z * 0.61, 10.0)


func _process(delta: float) -> void:
	if not physics:
		_step(delta)


func _physics_process(delta: float) -> void:
	if physics:
		_step(delta)


func _step(delta: float) -> void:
	if not _started:
		_begin()
	_t += delta
	var p := _base_pos
	if bob_amp != 0.0:
		p.y += sin(_t * TAU / bob_period + deg_to_rad(bob_phase_deg)) * bob_amp
	if drift != Vector3.ZERO:
		var off := drift * _t
		if drift_wrap > 0.0:
			off.x = fposmod(off.x + drift_wrap, drift_wrap * 2.0) - drift_wrap
			off.z = fposmod(off.z + drift_wrap, drift_wrap * 2.0) - drift_wrap
		p += off
	position = p
	var r := _base_rot + spin_deg_per_s * _t
	if sway_deg != 0.0:
		r.x += sin(_t * TAU / sway_period) * sway_deg
		r.z += sin(_t * TAU / (sway_period * 1.3) + 1.1) * sway_deg * 0.7
	rotation_degrees = r

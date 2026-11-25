extends Area3D
## H-F bellows updraft beside Book 1 (HUB_amendments R1.6): a wind column (group "wind_zone") that lifts Mak,
## pulls him gently toward its axis so a hands-off rider stays inside, and in the top band pushes him out through
## gate BGATE_updraft onto the gallery. The player sums get_wind() from overlapping wind zones.

@export var axis_xz := Vector2(-9.34, 6.54)
@export var lift := 12.0
@export var centring := 3.0
@export var top_band_y := 5.5
@export var push := Vector3(-2.46, 2.0, 1.72)
var enabled := true


func _ready() -> void:
	add_to_group("wind_zone")
	collision_layer = 1 << 7
	collision_mask = 1 << 1
	monitorable = true
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.3
	cyl.height = 6.4
	cs.shape = cyl
	cs.position = Vector3(axis_xz.x, 4.0, axis_xz.y) - global_position
	add_child(cs)


func set_enabled(on: bool) -> void:
	enabled = on


func get_wind(at: Vector3) -> Vector3:
	if not enabled:
		return Vector3.ZERO
	if at.y >= top_band_y:
		# r1 feel round 2: air control (10.5 m/s^2) beat the old 3 m/s outward push, so holding toward the hall
		# steered Mak back onto the dais. About 9.5 m/s outward now carries him through the gate.
		return Vector3(push.x * 3.2, push.y * 2.0, push.z * 3.2)
	var to_axis := Vector3(axis_xz.x - at.x, 0.0, axis_xz.y - at.z)
	return Vector3(0, lift, 0) + to_axis * centring

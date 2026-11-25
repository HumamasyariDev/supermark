extends Area3D
## W3 Frosting Slide push: frosting has (almost) no friction, so the trough carries Mak downhill.
## Implements the wind_zone contract (group "wind_zone", get_wind(at) -> m/s velocity). The push follows the
## slide's centre line tangent and is strongest on the steep upper part. Collision shapes are added by w3_level.gd.

@export var points := PackedVector3Array()
@export var push_speed := 7.5
@export var max_offset := 2.2


func get_wind(at: Vector3) -> Vector3:
	if points.size() < 2:
		return Vector3.ZERO
	var best := 1e9
	var bi := 0
	for i in range(0, points.size() - 1):
		var d := Vector2(points[i].x - at.x, points[i].z - at.z).length_squared()
		if d < best:
			best = d
			bi = i
	if sqrt(best) > max_offset or absf(at.y - points[bi].y) > 1.6:
		return Vector3.ZERO
	var a := points[bi]
	var b := points[mini(bi + 1, points.size() - 1)]
	var t := b - a
	var flat := Vector3(t.x, 0, t.z)
	if flat.length() < 0.001:
		return Vector3.ZERO
	var slope := clampf(-t.y / flat.length(), 0.0, 1.0)
	return flat.normalized() * push_speed * (0.6 + slope)

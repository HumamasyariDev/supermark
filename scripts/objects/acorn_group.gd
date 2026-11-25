class_name AcornGroup
extends Node3D
## Spawner helper: lays out acorns in a line, ring or arc at runtime.
## LINE runs along local -Z for `length` metres; RING and ARC use `radius` in the local XZ plane.

enum Shape { LINE, RING, ARC }

@export var shape: Shape = Shape.LINE
@export_range(1, 64) var count: int = 8
@export var length: float = 8.0
@export var radius: float = 3.0
@export_range(0.0, 360.0) var arc_degrees: float = 180.0
## For LINE: optional hop (parabola height) so a line can trace a jump arc.
@export var arc_height: float = 0.0


func _ready() -> void:
	for p in points():
		var ps := load(ObjSvc.ACORN_SCENE) as PackedScene
		var a := ps.instantiate() as Node3D
		a.position = p
		add_child(a)


func points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in count:
		var t := float(i) / float(maxi(count - 1, 1))
		match shape:
			Shape.LINE:
				out.append(Vector3(0, sin(t * PI) * arc_height, -t * length))
			Shape.RING:
				var a := TAU * float(i) / float(count)
				out.append(Vector3(cos(a), 0, sin(a)) * radius)
			Shape.ARC:
				var b := deg_to_rad(-arc_degrees * 0.5 + arc_degrees * t)
				out.append(Vector3(sin(b), 0, -cos(b)) * radius)
	return out

class_name GingerbreadSquad
extends Node3D
## Spawns a marching squad of Gingerbread Grenadiers that share one patrol path (offsets from this
## node) and alert each other. Optionally led by Sergeant Snap (bigger, two hits, barks orders).

@export var size: int = 3
@export var spacing: float = 1.1
@export var patrol_points: Array[Vector3] = [Vector3(-3, 0, 0), Vector3(3, 0, 0)]
@export var with_sergeant: bool = false

var members: Array = []


func _ready() -> void:
	var total := size + (1 if with_sergeant else 0)
	for i in total:
		var g := GingerbreadGrenadier.new()
		g.name = "Sergeant_Snap" if (with_sergeant and i == 0) else "Grenadier_%d" % i
		g.formation_index = i
		g.sergeant = with_sergeant and i == 0
		g.patrol_points = patrol_points
		add_child(g)
		g.global_position = global_position + global_transform.basis.x * (float(i) - float(total - 1) * 0.5) * spacing + Vector3(0, 0.05, 0)
		members.append(g)
	for g in members:
		(g as GingerbreadGrenadier).squad = members

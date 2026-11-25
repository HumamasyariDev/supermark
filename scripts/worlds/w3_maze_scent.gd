extends Node3D
## W3-1 maze scent (R1.4): a sniff target (group "sniff_target") that sits on the next scent node of the maze
## solution ahead of Mak. Progress is the furthest node Mak has come within `reach` m of. Visible (and so
## selectable by the Snout Sniff) only while Mak is inside `area` (x0, z0, x1, z1).

@export var nodes := PackedVector3Array()
@export var reach := 2.6
@export var area := Vector4(-60, 5, -32, 28)

var progress := -1


func _ready() -> void:
	add_to_group("sniff_target")


func is_sniff_active() -> bool:
	return visible


func get_sniff_position() -> Vector3:
	return global_position


func get_scent_strength() -> float:
	return 1.0


func on_sniffed(_by: Node = null) -> void:
	pass


func _physics_process(_delta: float) -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null or nodes.is_empty():
		return
	var p := pl.global_position
	for i in range(progress + 1, nodes.size()):
		if Vector2(nodes[i].x - p.x, nodes[i].z - p.z).length() < reach:
			progress = i
	var inside := p.x > area.x and p.x < area.z and p.z > area.y and p.z < area.w
	visible = inside and progress < nodes.size() - 1
	global_position = nodes[mini(progress + 1, nodes.size() - 1)]

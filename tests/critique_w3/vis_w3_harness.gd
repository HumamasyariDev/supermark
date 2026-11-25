extends Node
## Critique W3 round 1 (VISUAL POLISH lens) harness: adds the visual probe under /root, then loads W3.


func _ready() -> void:
	var probe: Node = (load("res://tests/critique_w3/vis_w3_probe.gd") as GDScript).new()
	probe.name = "VisW3Probe"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w3/W3.tscn")

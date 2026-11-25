extends Node
## Critique W2 round 1 (FUN lens, relaunch): adds the goose-chase driver under /root, then loads W2. Read-only for the world.

func _ready() -> void:
	var probe: Node = (load("res://tests/critique_w2/r1_fun_b/goose_chase_driver.gd") as GDScript).new()
	probe.name = "GooseChaseDriver"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w2/W2.tscn")

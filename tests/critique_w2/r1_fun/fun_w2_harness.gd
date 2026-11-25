extends Node
## Critique W2 round 1 (FUN lens): adds the probe under /root, then loads W2 as the current scene. Read-only for the world.
## Run: python tools/godot.py run res://tests/critique_w2/r1_fun/FunW2.tscn --seconds 60 --no-import -- --profile=critw2fun_probe --w2-nointro


func _ready() -> void:
	var probe: Node = (load("res://tests/critique_w2/r1_fun/fun_w2_probe.gd") as GDScript).new()
	probe.name = "FunW2Probe"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w2/W2.tscn")

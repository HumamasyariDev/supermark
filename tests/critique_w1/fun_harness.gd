extends Node
## Critique W1 round 1 (FUN lens) harness: adds the play driver under /root, then loads W1 as the current scene.
## Run: python tools/godot.py run res://tests/critique_w1/FunQA.tscn --seconds 300 -- --profile=critw1fun_x --w1fun=walk --w1fun-out=<abs json>
## Add --spawn=<marker> to start at a mission marker.

const DRIVER := preload("res://tests/critique_w1/fun_driver.gd")


func _ready() -> void:
	var d: Node = DRIVER.new()
	d.name = "W1FunDriver"
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w1/W1.tscn")

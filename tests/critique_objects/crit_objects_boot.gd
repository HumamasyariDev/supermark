extends Node
## Critique OBJECTS r1 (QA lens) bootstrap: adds the runner under /root so it survives Router scene changes,
## then lets the runner drive real worlds through Router.enter_world.
##   python tools/godot.py run res://tests/critique_objects/CritObjectsR1.tscn --headless --seconds 400 --
##       --profile=crit_objects_r1 --suite=world --world=W1 --results=<abs json>


func _ready() -> void:
	var r := Node.new()
	r.name = "CritObjectsRunner"
	r.set_script(load("res://tests/critique_objects/crit_objects_r1.gd"))
	get_tree().root.add_child.call_deferred(r)

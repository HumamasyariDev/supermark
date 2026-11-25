extends Node
## Critique OBJECTS r1 after M3b (visual lens) bootstrap: adds crit_visual_m3b.gd under /root so it survives Router
## scene changes.
##   python tools/godot.py run res://tests/critique_objects/CritVisualM3b.tscn --seconds 400 --
##       --profile=crit_objects_vis --world=W1 --shot_dir=<abs dir>


func _ready() -> void:
	var r := Node.new()
	r.name = "CritVisualRunner"
	r.set_script(load("res://tests/critique_objects/crit_visual_m3b.gd"))
	get_tree().root.add_child.call_deferred(r)

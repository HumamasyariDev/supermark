extends Node
## Critique W1 round 1, visual lens: adds the read-only tour probe under /root, then loads W1.
## Run: python tools/godot.py run res://tests/critique_w1/r1_visual/VisualTour.tscn --seconds 600 -- --profile=crit_w1_r1_visual --tour-out=<abs dir>

const PROBE := preload("res://tests/critique_w1/r1_visual/visual_tour_probe.gd")


func _ready() -> void:
	var probe: Node = PROBE.new()
	probe.name = "W1VisualTour"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w1/W1.tscn")

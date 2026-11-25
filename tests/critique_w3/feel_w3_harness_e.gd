extends Node
## Critique W3 round 1, pass C (game feel, movement and camera lens). Adds feel_w3_probe_e.gd under /root, then loads W3.
## Run (from the entity folder):
##   python tools/godot.py run res://tests/critique_w3/FeelW3c.tscn --seconds 900 -- --profile=critic_w3_feel_c_<utc> \
##       --hide-hud --feel-out=<abs dir> --feel-tag=<tag> [--feel-phases=jelly3,polecandle,...]


func _ready() -> void:
	var probe: Node = (load("res://tests/critique_w3/feel_w3_probe_e.gd") as GDScript).new()
	probe.name = "FeelW3ProbeE"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w3/W3.tscn")

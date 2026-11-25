extends Node
## Critique W3 round 1 (GAME FEEL, MOVEMENT AND CAMERA lens) harness: adds the feel probe under /root, then loads W3
## as the current scene. The probe never edits the world; it teleports Mak, drives the real controller through its
## replay input layer (naive "hold the stick at the target" control, like a first-time player) and samples the camera.
## Run (from the entity folder):
##   python tools/godot.py run res://tests/critique_w3/FeelW3.tscn --seconds 900 -- --profile=critic_w3_feel_<utc> \
##       --hide-hud --feel-out=<abs dir> [--feel-phases=audit,jelly,...]


func _ready() -> void:
	var probe: Node = (load("res://tests/critique_w3/feel_w3_probe.gd") as GDScript).new()
	probe.name = "FeelW3Probe"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w3/W3.tscn")

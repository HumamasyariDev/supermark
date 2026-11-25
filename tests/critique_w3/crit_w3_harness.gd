extends Node
## Critique W3 round 1 (FUN lens) harness: adds the critic's probe under /root, then loads W3 as the current scene.
## The probe attaches the W3 builder's closed-loop bot driver (scripts/worlds/w3_bot.gd, unchanged) to the level
## with a CRITIC plan chosen by --crit-plan=<name> (plans live in crit_w3_probe.gd, not in the world).
## Needs a world-steer replay file (--replay=...) so MakInput accepts the bot's stick and buttons.


func _ready() -> void:
	var probe: Node = (load("res://tests/critique_w3/crit_w3_probe.gd") as GDScript).new()
	probe.name = "CritW3Probe"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w3/W3.tscn")

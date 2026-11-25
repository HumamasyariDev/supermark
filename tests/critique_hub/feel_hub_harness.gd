extends Node
## Harness for the HUB feel critique probe: moves the probe under /root so it survives the scene change to Hub.tscn.


func _ready() -> void:
	var probe: Node = (load("res://tests/critique_hub/feel_hub_probe.gd") as GDScript).new()
	probe.name = "FeelHubProbe"
	get_tree().root.add_child.call_deferred(probe)

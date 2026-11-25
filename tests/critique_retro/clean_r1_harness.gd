extends Node
## Critique RETRO round 1 (image cleanliness and performance) harness: adds clean_r1_probe.gd under /root, which then
## loads the areas itself. Test-only. See README.md in this folder.

const PROBE := preload("res://tests/critique_retro/clean_r1_probe.gd")


func _ready() -> void:
	var probe: Node = PROBE.new()
	probe.name = "CleanR1Probe"
	get_tree().root.add_child.call_deferred(probe)

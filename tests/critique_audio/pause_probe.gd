extends Node
## Scene root of PauseProbe.tscn: puts the monitor (pause_probe_mon.gd) under /root so it survives the Router swap.

func _ready() -> void:
	var mon := Node.new()
	mon.set_script(load("res://tests/critique_audio/pause_probe_mon.gd"))
	mon.name = "PauseProbeMon"
	get_tree().root.add_child.call_deferred(mon)

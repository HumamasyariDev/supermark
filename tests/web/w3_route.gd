extends "res://scripts/worlds/w3_bot.gd"
## Desktop breadcrumb/nest plans joined from the ordinary mission spawn.
var result: Dictionary = {"done": false}

func _ready() -> void:
	pl = get_tree().get_first_node_in_group("player") as Node3D
	var inp: Object = pl.get("inp")
	inp.set("replay_active",true)
	inp.set("steer_world",true)
	var plans: Dictionary = get_parent()._bot_plans()
	var steps: Array = plans["w31"].slice(1,6)
	steps.append_array(plans["w31nest"].slice(2))
	setup("w31-no-teleport",steps,150.0)

func _finish(message: String) -> void:
	super._finish(message)
	if pl:
		pl.get("inp").set("replay_active",false)
	result = {"done":true,"message":message,"frames":_frames,"hurts":_hurts,
		"truffle":Game.has_truffle("W3-1"),"teleports":0,"scope":"first mission"}

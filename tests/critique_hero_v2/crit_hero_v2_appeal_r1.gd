extends Node
## HERO V2 critique round 1, APPEAL AND IDENTITY lens. Test scene only.
## Loads a world, lets the director (on the root) capture the shipped hero v2 with both hats.
##   python tools/godot.py run res://tests/critique_hero_v2/CritHeroV2AppealR1.tscn --seconds 240 -- --profile=crit_hero_v2_r1 \
##       --hide-hud --world=res://scenes/worlds/w1/W1.tscn --tag=w1 --out=<abs dir> [--settle=420]

const DIRECTOR := preload("res://tests/critique_hero_v2/crit_hero_v2_director.gd")


func _ready() -> void:
	var d: Node = DIRECTOR.new()
	d.name = "CritHeroV2Director"
	get_tree().root.add_child.call_deferred(d)
	var world := "res://scenes/worlds/w1/W1.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			world = a.substr(8)
	get_tree().change_scene_to_file.call_deferred(world)

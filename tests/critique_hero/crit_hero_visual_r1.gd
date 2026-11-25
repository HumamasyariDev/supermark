extends Node
## HERO critique round 1, CHARACTER VISUALS lens. Test scene only, not gameplay.
## Loads a real world scene (the director survives the scene change on the root), waits for Mak to settle,
## then saves a battery of native captures of the shipped player model in that world's lighting:
## gameplay camera (with and without HUD), face close-ups, full-body 3/4, profile, back 3/4, a far readability
## view, and the top hat variant. It also prints mesh statistics (triangles, vertex split ratio, materials).
##
##   python tools/godot.py run res://tests/critique_hero/CritHeroVisualR1.tscn --seconds 120 -- --profile=crit_hero_r1 \
##       --world=res://scenes/worlds/w1/W1.tscn --tag=w1 --out=<abs dir> [--spawn=<marker>] [--settle=300]

const DIRECTOR := preload("res://tests/critique_hero/crit_hero_director.gd")


func _ready() -> void:
	var d: Node = DIRECTOR.new()
	d.name = "CritHeroDirector"
	get_tree().root.add_child.call_deferred(d)
	var world := "res://scenes/worlds/w1/W1.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			world = a.substr(8)
	get_tree().change_scene_to_file.call_deferred(world)

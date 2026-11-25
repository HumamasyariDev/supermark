extends Node
## Boot for the BOSS critique r1 probe: parks the probe under /root (it survives the scene change) and loads the
## real arena as the current scene, so Game.respawn_player() and the Router behave exactly as in play.

func _ready() -> void:
	var probe := (load("res://tests/critique_boss/crit_boss_r1.gd") as GDScript).new() as Node
	probe.name = "CritBossProbe"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/boss/WolfRooftop.tscn")

extends Node
## Boot for BOSS critique r1 probe C (see crit_boss_r1c.gd): parks the probe under /root and loads the real arena.

func _ready() -> void:
	var probe := (load("res://tests/critique_boss/crit_boss_r1c.gd") as GDScript).new() as Node
	probe.name = "CritBossProbeC"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/boss/WolfRooftop.tscn")

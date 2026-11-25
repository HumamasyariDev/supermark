extends Node
## Critique W3 r1c: adds bot_watch_r1c.gd under /root, then loads W3 (pass --replay, --w3-bot and --qa-out).


func _ready() -> void:
	var dv := get_node_or_null("/root/Dev")
	var od: String = dv.arg("qa-out", "") if dv else ""
	if od != "":
		DirAccess.make_dir_recursive_absolute(od)
		var lg = (load("res://tests/critique_w3/qa_logger_r1c.gd") as GDScript).new()
		lg.call("open", od.path_join("full_log.txt"))
		OS.add_logger(lg)
	var w: Node = (load("res://tests/critique_w3/bot_watch_r1c.gd") as GDScript).new()
	w.name = "W3BotWatch"
	get_tree().root.add_child.call_deferred(w)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w3/W3.tscn")

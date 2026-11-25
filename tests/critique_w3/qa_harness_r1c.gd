extends Node
## Critique W3 r1c (QA lens) harness: like qa_harness.gd, but loads qa_probe_r1c.gd and can preset the fort's
## static phase-restart record before W3 loads (--qa-fort-preset=<phase>).


func _ready() -> void:
	var dv := get_node_or_null("/root/Dev")
	var od: String = dv.arg("qa-out", "") if dv else ""
	if od != "":
		DirAccess.make_dir_recursive_absolute(od)
		var lg = (load("res://tests/critique_w3/qa_logger_r1c.gd") as GDScript).new()
		lg.call("open", od.path_join("full_log.txt"))
		OS.add_logger(lg)
	var dev := get_node_or_null("/root/Dev")
	var preset := int(dev.arg("qa-fort-preset", "0")) if dev else 0
	if preset > 0:
		var fs := load("res://scripts/worlds/w3_fort.gd") as GDScript
		fs.set("_saved", {"phase": preset, "hits": preset - 2, "msec": Time.get_ticks_msec()})
		print("[QA] fort static preset: ", fs.get("_saved"))
	var probe: Node = (load("res://tests/critique_w3/qa_probe_r1c.gd") as GDScript).new()
	probe.name = "W3QAProbe"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w3/W3.tscn")

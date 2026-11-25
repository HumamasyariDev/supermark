extends Node
## Critique W2 round 1 (QA lens) harness: adds a QA probe under /root, then loads W2 as the current scene.
## Run: python tools/godot.py capture res://tests/critique_w2/W2QA.tscn <out.png> --wait 999999 -- --profile=critic_w2_qa --w2-nointro --qa-out=<abs dir> [--qa-probe=2]


func _ready() -> void:
	var dev := get_node_or_null("/root/Dev")
	var which: String = dev.arg("qa-probe", "1") if dev else "1"
	var path := "res://tests/critique_w2/w2_qa_probe.gd" if which == "1" else "res://tests/critique_w2/w2_qa_probe%s.gd" % which
	var probe: Node = (load(path) as GDScript).new()
	probe.name = "W2QAProbe"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w2/W2.tscn")

extends Node
## Critique W3 round 1 (QA AND TECHNICAL lens) harness: adds the QA probe under /root, then loads W3 as the current scene.
## Run: python tools/godot.py capture res://tests/critique_w3/QaW3.tscn <out.png> --wait 999999 -- --profile=critic_w3_qa --qa-out=<abs dir> [--qa-phases=audit,idle,cams,drops,engage,hits,kitchen]
## (capture mode gives a real 1920x1080 window and suppresses the W3 intro; the probe quits on its own.)


func _ready() -> void:
	var probe: Node = (load("res://tests/critique_w3/qa_probe.gd") as GDScript).new()
	probe.name = "W3QAProbe"
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w3/W3.tscn")

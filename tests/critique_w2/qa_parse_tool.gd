extends SceneTree
## Parse check for the W2 QA probes (critique tooling): python tools/godot.py script res://tests/critique_w2/qa_parse_tool.gd


func _init() -> void:
	for p in ["res://tests/critique_w2/w2_qa_probe6.gd"]:
		var s := load(p) as GDScript
		print("[QAPARSE] ", p, " ok=", s != null and s.can_instantiate())
	quit(0)

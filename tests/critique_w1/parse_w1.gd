extends SceneTree
## Critique W1 r1 (QA): compile every W1 world script plus the W1 critique tests (tools/godot.py check only boots the
## main scene, so a parse error in a dev-only script such as w1_bot.gd never shows there).
## python tools/godot.py script res://tests/critique_w1/parse_w1.gd --no-import


func _init() -> void:
	var bad := 0
	var paths: Array[String] = []
	for dir in ["res://scripts/worlds", "res://tests/critique_w1"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".gd") and (dir.ends_with("critique_w1") or f.begins_with("w1_")):
				paths.append(dir.path_join(f))
	for path in paths:
		var s := load(path) as GDScript
		if s == null or not s.can_instantiate():
			print("[parse_w1] FAIL ", path)
			bad += 1
		else:
			print("[parse_w1] ok ", path)
	print("[parse_w1] failures: ", bad, " of ", paths.size())
	quit(1 if bad > 0 else 0)

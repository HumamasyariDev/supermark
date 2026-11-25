extends SceneTree
## Loads the player/camera scripts and reports whether they compile (player workstream quick check).
## python tools/godot.py script res://tests/parse_check.gd --no-import


func _init() -> void:
	var bad := 0
	for path in ["res://scripts/player/movement_profile.gd", "res://scripts/player/mak_rig_fix.gd",
			"res://scripts/player/rig_adapters.gd", "res://scripts/player/mak_player.gd",
			"res://scripts/player/mak_animator.gd", "res://scripts/camera/mak_camera.gd"]:
		var s := load(path) as GDScript
		if s == null or not s.can_instantiate():
			print("[parse_check] FAIL ", path)
			bad += 1
		else:
			print("[parse_check] ok ", path)
	print("[parse_check] failures: ", bad)
	quit(1 if bad > 0 else 0)

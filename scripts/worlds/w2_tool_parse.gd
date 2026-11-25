extends SceneTree
## W2 builder tool: loads every W2 script so parse errors print with file and line.

func _init() -> void:
	for p in ["w2_mesh", "w2_target", "w2_wind", "w2_caw", "w2_build", "w2_play", "w2_descent", "w2_life", "w2_world", "w2_fix2", "w2_camera", "w2_camera_zone", "w2_goose_wolf", "w2_verify"]:
		var s: Variant = load("res://scripts/worlds/%s.gd" % p)
		print("[W2 parse] %s -> %s" % [p, "ok" if s != null and (s as GDScript).can_instantiate() else "FAIL"])
	quit()

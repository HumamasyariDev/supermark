extends SceneTree
## Dev tool: loads every W3 script to surface parse errors without re-baking.
func _init() -> void:
	for sc in ["w3_level", "w3_world", "w3_bot", "w3_jelly", "w3_candle", "w3_crumble", "w3_maze_scent", "w3_royal", "w3_slide_push",
			"w3_biscuit_lane", "w3_breadcrumbs", "w3_falls", "w3_fort", "w3_bobber", "w3_geo", "w3_bake"]:
		if load("res://scripts/worlds/%s.gd" % sc) == null:
			push_error("[w3_parse] failed: " + sc)
	print("[w3_parse] done")
	quit(0)

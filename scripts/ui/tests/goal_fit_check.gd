extends SceneTree
## UI check (critique UI r1 re-run): every mission goal fits the focused mission-select ribbon without
## clipping a word. Mirrors mission_select.gd: 27 px shrinking to 19 px, width = row width - 220.
##   python tools/godot.py script res://scripts/ui/tests/goal_fit_check.gd
## Prints one line per goal and "[GoalFit] PASS" or "[GoalFit] FAIL n".

const ROW_W := 700.0  # MissionSelect._list width: BOOK_SIZE.x * 0.5 - 120
const MAX_CHARS := 40


func _initialize() -> void:
	var gf := UIStyle.ui_font(600)
	var gmax := ROW_W - 220.0
	var fails := 0
	for w in ["HUB", "W1", "W2", "W3", "BOSS"]:
		for t in WorldRegistry.truffles(w):
			var goal := String(t.get("goal", ""))
			if goal == "":
				continue
			var fs := 27
			while fs > 19 and gf.get_string_size(goal, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > gmax:
				fs -= 1
			var width := gf.get_string_size(goal, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var ok := width <= gmax and goal.length() <= MAX_CHARS
			if not ok:
				fails += 1
			print("[GoalFit] %s %-6s %2d chars %d px at %d px  %s" % ["ok  " if ok else "FAIL", t["id"], goal.length(), int(width), fs, goal])
	print("[GoalFit] PASS" if fails == 0 else "[GoalFit] FAIL %d" % fails)
	quit(1 if fails > 0 else 0)

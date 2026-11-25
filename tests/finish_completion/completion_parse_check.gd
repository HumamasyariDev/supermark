extends SceneTree
## Completion pass: compiles every script this pass touched.
## python tools/godot.py script res://tests/finish_completion/completion_parse_check.gd --no-import
## wolf_boss.gd is not listed: it names the Dev autoload, which a --script run does not load (it compiled and ran in
## the boss bot run of this pass).


func _init() -> void:
	var bad := 0
	for path in ["res://scripts/objects/golden_hat.gd", "res://scripts/core/game_state.gd",
			"res://scripts/boss/boss_bot.gd", "res://scripts/ui/pause_menu.gd", "res://scripts/ui/ui_model_view.gd",
			"res://scripts/ui/settings_menu.gd", "res://scripts/worlds/hub_level.gd", "res://scripts/worlds/hub_autopilot.gd",
			"res://scripts/worlds/w1_level.gd", "res://scripts/worlds/w1_bot.gd", "res://scripts/worlds/w3_level.gd",
			"res://scripts/worlds/w3_bot.gd", "res://tests/finish_completion/completion_hat_probe.gd",
			"res://tests/finish_completion/completion_classic_probe.gd"]:
		var s := load(path) as GDScript
		if s == null or not s.can_instantiate():
			print("[completion_parse] FAIL ", path)
			bad += 1
		else:
			print("[completion_parse] ok ", path)
	print("[completion_parse] failures: ", bad)
	quit(1 if bad > 0 else 0)

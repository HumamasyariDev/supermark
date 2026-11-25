extends Node
## Completion pass: Settings > Display > "Classic textures" check. Opens SettingsMenu, finds the row's CheckButton,
## toggles it off and on through the button (the same toggled signal a click or the accept key fires) and prints
## RetroLook.enabled and the Game setting after each step.
## Run: python tools/godot.py run res://tests/finish_completion/CompletionClassicProbe.tscn --seconds 30 -- --profile=completion_classic


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var menu := (load("res://scenes/ui/SettingsMenu.tscn") as PackedScene).instantiate() as Control
	layer.add_child(menu)
	await get_tree().create_timer(0.4).timeout
	menu.call("open")
	await get_tree().create_timer(0.4).timeout
	var rl := get_node_or_null("/root/RetroLook")
	var g := get_node_or_null("/root/Game")
	var btn: CheckButton = null
	for l in menu.find_children("*", "Label", true, false):
		if (l as Label).text == "Classic textures":
			for c in l.get_parent().find_children("*", "CheckButton", true, false):
				btn = c
	if btn == null:
		print("[CLASSIC] FAIL no Classic textures row")
		get_tree().quit()
		return
	print("[CLASSIC] row found: shows %s, setting %s, RetroLook.enabled %s" % [btn.text, str(g.get_setting("classic_textures")), str(rl.get("enabled"))])
	btn.button_pressed = false
	await get_tree().create_timer(0.3).timeout
	print("[CLASSIC] after Off: shows %s, setting %s, RetroLook.enabled %s" % [btn.text, str(g.get_setting("classic_textures")), str(rl.get("enabled"))])
	btn.button_pressed = true
	await get_tree().create_timer(0.3).timeout
	print("[CLASSIC] after On: shows %s, setting %s, RetroLook.enabled %s" % [btn.text, str(g.get_setting("classic_textures")), str(rl.get("enabled"))])
	get_tree().quit()

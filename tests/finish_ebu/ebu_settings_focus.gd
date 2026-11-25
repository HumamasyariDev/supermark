extends Node
## Finish pass (ENEMIES-BOSS-UI): Settings focus chain check. Opens scenes/ui/SettingsMenu.tscn, presses real
## ui_down key events 40 times and logs every focused control; prints the number of distinct stops reached.
## Run: python tools/godot.py run res://tests/finish_ebu/EbuSettingsFocus.tscn --seconds 60 -- --profile=ebu_settings

var _menu: Control
var _seen := {}
var _order: Array = []


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_menu = (load("res://scenes/ui/SettingsMenu.tscn") as PackedScene).instantiate() as Control
	layer.add_child(_menu)
	await get_tree().create_timer(0.5).timeout
	_menu.call("open")
	await get_tree().create_timer(0.5).timeout
	for i in 40:
		_note()
		var ev := InputEventKey.new()
		ev.keycode = KEY_DOWN
		ev.physical_keycode = KEY_DOWN
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		var up := ev.duplicate() as InputEventKey
		up.pressed = false
		Input.parse_input_event(up)
		await get_tree().create_timer(0.06).timeout
	print("[EBU-SET] distinct stops reached: %d" % _seen.size())
	print("[EBU-SET] order: ", _order)
	var img := get_viewport().get_texture().get_image()
	var p := ProjectSettings.globalize_path("res://").path_join("../Docs/progress/finish/enemies_boss_ui/after_settings_focus_end.png").simplify_path()
	img.save_png(p)
	get_tree().quit()


func _note() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f == null:
		_order.append("-")
		return
	var key := str(f.get_path())
	if not _seen.has(key):
		_seen[key] = true
		var lbl := ""
		var row := f.get_parent()
		if row != null:
			for c in row.get_children():
				if c is Label:
					lbl = (c as Label).text
					break
		if lbl == "" and "text" in f:
			lbl = str(f.get("text"))
		_order.append(lbl if lbl != "" else f.name)

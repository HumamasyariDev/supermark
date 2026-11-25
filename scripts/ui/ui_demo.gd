extends Node
## Scripted UI flow for Movie Maker clips (--ui-demo, started by the UI autoload from the title):
## title -> menu -> New Game -> hub -> book opens -> mission chosen -> W1 entry banner -> HUD events
## (acorns, damage, page, timer) -> TRUFFLE GET -> pause with the wardrobe -> dialog with portraits.
## Input goes through synthetic actions, so the real menus, focus and transitions are exercised.

var _t0 := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _key() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_ENTER
	k.keycode = KEY_ENTER
	k.pressed = true
	Input.parse_input_event(k)
	await get_tree().process_frame
	var u := k.duplicate() as InputEventKey
	u.pressed = false
	Input.parse_input_event(u)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _log(m: String) -> void:
	print("[UIDemo] %.2f %s" % [Time.get_ticks_msec() / 1000.0, m])


func _run() -> void:
	var game := get_node("/root/Game")
	var ui := get_node("/root/UI")
	await _wait(2.2)
	_log("press any key")
	await _key()
	await _wait(1.3)
	# walk the focus to "New Game" whatever the save state (Continue is disabled without a save)
	for i in 4:
		var f := get_viewport().gui_get_focus_owner()
		if f and String(f.get("caption")) == "New Game":
			break
		await _press("ui_down")
		await _wait(0.35)
	_log("new game")
	await _press("ui_accept")
	await _wait(0.6)
	# a save with progress asks for confirmation: "Yes, begin" is focused second; pick it
	var cf := get_viewport().gui_get_focus_owner()
	if cf and String(cf.get("caption")) == "Keep my story":
		await _press("ui_left")
		await _wait(0.3)
		await _press("ui_accept")
	# Router turns the page into the hub
	await _wait(4.9)
	_log("open book W1")
	ui.show_mission_select("W1")
	await _wait(2.2)
	await _press("ui_down")
	await _wait(0.6)
	_log("choose W1-2")
	await _press("ui_accept")
	await _wait(6.0)
	_log("hud events")
	for i in 5:
		game.add_acorns(1)
		await _wait(0.18)
	await _wait(0.6)
	game.damage(1)
	await _wait(1.2)
	game.collect_page("W1", 0)
	await _wait(1.0)
	game.add_acorns(1)
	await _wait(0.8)
	ui.timer_start("Rooftop Relay", 0.0)
	await _wait(2.0)
	ui.timer_stop()
	await _wait(0.6)
	ui.timer_hide()
	_log("truffle get")
	game.collect_truffle("W1-2")
	await _wait(4.0)
	_log("pause + wardrobe")
	game.unlock("top_hat")
	ui.open_pause()
	await _wait(1.0)
	await _press("ui_down")
	await _wait(0.4)
	await _press("ui_right")
	await _wait(0.6)
	await _press("ui_right")
	await _wait(0.5)
	await _press("ui_accept")
	await _wait(1.4)
	await _press("ui_cancel")
	await _wait(1.0)
	_log("dialog")
	ui.show_dialog("Bramwell", [
		"Splendid hat, sir! Most distinguished.",
		{"speaker": "Mr. Mak", "text": "Jolly good. Now, about those truffles..."},
		{"speaker": "Sir Reginald", "text": "Little pig, little pig... you'll never find them all!"},
	])
	await _wait(2.6)
	await _press("interact")
	await _wait(2.4)
	await _press("interact")
	await _wait(3.0)
	await _press("interact")
	_log("done")

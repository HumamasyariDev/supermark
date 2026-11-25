extends SceneTree
## UI fix round 1 checks (critique UI r1 re-run), on the light UITestWorld scene:
##  1. the mission book waits while a dialog is open and opens after it closes
##  2. pause opens nothing while a dialog is open
##  3. the pause menu list wraps and hat cards keep vertical focus to themselves
##  4. the pause confirm footer says Choose / Keep reading, then restores Select / Resume
##  5. Backspace is on ui_cancel
##  6. UI.set_objective shows on the HUD and clears with the scene
##   python tools/godot.py script res://scripts/ui/tests/ui_flow_check.gd -- --profile=ui_check
## Prints "[UIFlow] ok|FAIL <check>" lines and "[UIFlow] PASS" or "[UIFlow] FAIL n".

var _fails := 0


func _initialize() -> void:
	change_scene_to_file.call_deferred("res://scenes/ui/UITestWorld.tscn")
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("[UIFlow] %s %s %s" % ["ok  " if ok else "FAIL", name, detail])


func _wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func _run() -> void:
	await _wait(1.5)
	var ui: Node = root.get_node("UI")
	# 1 + 2: dialog guards
	ui.show_dialog("Bramwell", ["Splendid catch, Master Mak! The bookmark is yours again."])
	await _wait(0.3)
	ui.show_mission_select("W1")
	ui.open_pause()
	await _wait(0.5)
	_check("book_waits_for_dialog", not ui.mission_select.visible, "book visible=%s" % ui.mission_select.visible)
	_check("pause_blocked_by_dialog", not ui.pause_menu.is_open())
	ui.dialog.close()
	await _wait(0.8)
	_check("book_opens_after_dialog", ui.mission_select.visible)
	ui.mission_select.visible = false
	paused = false
	await _wait(0.3)
	# 3: pause focus wiring
	ui.open_pause()
	await _wait(0.6)
	var pm: Node = ui.pause_menu
	var vis: Array = []
	for b in pm._buttons.get_children():
		if (b as Control).visible:
			vis.append(b)
	var last := vis.back() as Control
	var first := vis.front() as Control
	_check("menu_wraps_down", last.get_node_or_null(last.focus_neighbor_bottom) == first)
	_check("menu_wraps_up", first.get_node_or_null(first.focus_neighbor_top) == last)
	var ok_cards := true
	for c in pm._hat_cards:
		var cc := c as Control
		if cc.get_node_or_null(cc.focus_neighbor_top) != cc or cc.get_node_or_null(cc.focus_neighbor_bottom) != cc:
			ok_cards = false
	_check("hat_cards_keep_vertical_focus", ok_cards)
	(vis[vis.size() - 1] as Control).grab_focus()
	await _wait(0.1)
	var hc0 := pm._hat_cards[0] as Control
	_check("hat_left_returns_to_last_button", hc0.get_node_or_null(hc0.focus_neighbor_left) == last)
	# 4: confirm footer
	pm._ask("Close this book?", "Your truffles and pages stay found.", "Return to library", Callable())
	await _wait(0.4)
	_check("confirm_footer", String(pm._footer.items[1][1]) == "Keep reading", str(pm._footer.items))
	pm._close_confirm()
	await _wait(0.2)
	_check("footer_restored", String(pm._footer.items[1][1]) == "Resume", str(pm._footer.items))
	pm._close_silently()
	await _wait(0.2)
	# 5: Backspace
	var bs := false
	for ev in InputMap.action_get_events("ui_cancel"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_BACKSPACE:
			bs = true
	_check("backspace_on_ui_cancel", bs)
	# 6: objective
	ui.set_hud_visible(true)
	ui.set_objective("Catch the sheep to win back the bookmark")
	await _wait(0.3)
	_check("objective_set", ui.hud.objective != "")
	ui.set_gameplay(true)
	_check("objective_clears_with_scene", ui.hud.objective == "")
	print("[UIFlow] PASS" if _fails == 0 else "[UIFlow] FAIL %d" % _fails)
	quit(1 if _fails > 0 else 0)

extends Node
## UI critique round 1 (usability and flow). Drives the REAL boot flow with real device events
## (InputEventKey / InputEventJoypadButton / InputEventJoypadMotion, never InputEventAction):
## title -> New Game -> hub -> book -> cancel -> book -> W1 -> pause -> library -> pause (pad) ->
## quit to title -> settings soft-lock probes -> confirm focus leak -> Continue -> hub.
## Saves a PNG per step at the window resolution and prints [Crit] PASS/FAIL/INFO lines.
## Args (after --): --profile=<p> --crit-out=<abs dir> [--crit-phase=all|flow|settings]

var out_dir := ""
var tag := ""
var _results: Array = []
var _step := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("crit-out", OS.get_user_data_dir()) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Survive scene changes: move under /root, then boot the real game.
	var parent := get_parent()
	parent.remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var vs := get_viewport().get_visible_rect().size
	tag = "%dx%d" % [int(DisplayServer.window_get_size().x), int(DisplayServer.window_get_size().y)]
	print("[Crit] window ", tag, " viewport ", vs)
	get_tree().change_scene_to_file("res://scenes/boot/Boot.tscn")
	await _wait(3.5)
	await _shot("title_press")
	_info("title_state", str(_title_state()))
	# ---------------- Title: any key, then the menu
	await _key(KEY_SPACE)
	await _wait(1.0)
	await _shot("title_menu_fresh")
	var f := _focus()
	_check("title_focus_new_game_on_fresh", _cap(f) == "New Game", "focus=" + _cap(f))
	# Down x3 then down again: does it wrap, stop, or leave the card?
	var path: Array = []
	for i in 4:
		await _key(KEY_DOWN)
		path.append(_cap(_focus()))
	_info("title_down_path", str(path))
	for i in 4:
		await _key(KEY_UP)
	_info("title_after_up4", _cap(_focus()))
	# Disabled Continue: can focus land on it?
	_check("title_disabled_continue_not_focusable", _cap(_focus()) != "Continue", "focus=" + _cap(_focus()))
	await _shot("title_menu_up_top")
	# move to New Game and accept
	_focus_caption("New Game")
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.8)
	var pad_a_title: bool = Router.busy or _title() == null
	_check("pad_A_activates_title_new_game", pad_a_title, "router_busy=%s focus=%s" % [Router.busy, _cap(_focus())])
	if not pad_a_title:
		await _key(KEY_ENTER)
	await _wait_router(30.0)
	await _wait(1.5)
	await _shot("hub_after_new_game")
	_check("new_game_reaches_hub", _world_id() == "HUB", "scene=" + _scene_name())
	_check("hub_hud_visible", _hud_visible())
	_check("hub_input_free", not UI.is_input_blocked())
	# ---------------- Hub: walk into book 1 (teleport the player into the page zone)
	var portal := _find(get_tree().current_scene, "Book_W1")
	var player := _player()
	_check("hub_has_portal_and_player", portal != null and player != null)
	if portal and player:
		var zone := _find(portal, "PageZone") as Node3D
		player.global_position = zone.global_position if zone else portal.global_position + Vector3(0, 3, 0)
		if player.has_method("reset_physics_interpolation"):
			player.reset_physics_interpolation()
	await _wait(2.2)
	await _shot("mission_select_open")
	f = _focus()
	_check("book_opens_with_focus", UI.mission_select.visible and f != null, "focus=" + _cap(f))
	# keyboard down, pad d-pad down, left stick down
	await _key(KEY_DOWN)
	var a1 := _cap(_focus())
	await _pad_button(JOY_BUTTON_DPAD_DOWN)
	var a2 := _cap(_focus())
	await _pad_axis(JOY_AXIS_LEFT_Y, 1.0)
	var a3 := _cap(_focus())
	_info("mission_nav_key_dpad_stick", "%s | %s | %s" % [a1, a2, a3])
	_check("mission_nav_stick", a3 != a2 and a3 != "", "after stick=" + a3)
	await _shot("mission_select_nav")
	# accept during the opening should not matter now; cancel with pad B
	await _pad_button(JOY_BUTTON_B)
	await _wait(1.0)
	_check("mission_cancel_pad_b", not UI.mission_select.visible and not get_tree().paused)
	await _shot("after_mission_cancel")
	# Where is Mak now? Still in the zone? Does a re-entry need walking out?
	if player:
		_info("player_after_cancel", str(player.global_position) + " state=" + str(player.call("get_state_name") if player.has_method("get_state_name") else ""))
	await _wait(1.5)
	_check("no_reopen_loop_after_cancel", not UI.mission_select.visible)
	# re-enter after the 3 s cooldown
	await _wait(1.0)
	var zone2: Area3D = _find(portal, "PageZone") as Area3D if portal else null
	if zone2 and player:
		_info("zone_overlap_after_cancel", str(zone2.get_overlapping_bodies().has(player)))
		var spawn := _find(get_tree().current_scene, "Spawns")
		var away: Node3D = spawn.get_node_or_null("Default") if spawn else null
		player.global_position = away.global_position if away else Vector3(0, 0.2, 11.5)
		await _wait(1.2)
		_info("zone_overlap_when_away", str(zone2.get_overlapping_bodies().has(player)))
		player.global_position = zone2.global_position
		await _wait(0.5)
		_info("book1_route_on_enter_after_cancel", str(portal.get("route_on_enter")) + " visible=" + str(UI.mission_select.visible) + " toast/dialog=" + str(UI.is_dialog_open()))
		await _shot("book1_silent_after_bookmark_steal")
		# the hub's bookmark-chase gag disarms Book 1; re-arm it to continue the flow test
		portal.set("route_on_enter", true)
		player.global_position = away.global_position if away else Vector3(0, 0.2, 11.5)
		await _wait(3.2)
		player.global_position = zone2.global_position
		await _wait(0.3)
		_info("zone_overlap_reentered", str(zone2.get_overlapping_bodies().has(player)) + " cooldown=" + str(portal.get("_cooldown")))
		if not UI.mission_select.visible:
			_info("reentry_direct_enter", "zone did not fire; calling portal.enter()")
			portal.call("enter")
			await _wait(0.2)
	# accept during the opening animation (README promises a skip)
	await _key(KEY_ENTER)
	var t_open := Time.get_ticks_msec()
	while UI.mission_select.get("_state") != "open" and Time.get_ticks_msec() - t_open < 4000:
		await get_tree().process_frame
	_info("book_open_after_enter_ms", str(Time.get_ticks_msec() - t_open))
	await _wait(0.4)
	var fm := _focus()
	_info("mission_reopen_focus", _cap(fm))
	_focus_caption("Straw House Siege")
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.3)
	var pad_a_book: bool = String(UI.mission_select.get("_state")) == "choosing" or not UI.mission_select.visible
	_check("pad_A_chooses_mission", pad_a_book, "state=" + String(UI.mission_select.get("_state")))
	if not pad_a_book:
		await _key(KEY_ENTER)
	await _wait_router(45.0)
	await _wait(2.0)
	await _shot("w1_entered")
	_check("book_enters_w1", _world_id() == "W1", "scene=" + _scene_name())
	_check("w1_hud_visible", _hud_visible())
	# ---------------- W1: keyboard pause, navigate to Return to library
	await _key(KEY_ESCAPE)
	await _wait(0.6)
	await _shot("w1_pause")
	f = _focus()
	_check("pause_focus_resume", _cap(f) == "Resume", "focus=" + _cap(f))
	path = []
	for i in 5:
		await _key(KEY_DOWN)
		path.append(_cap(_focus()))
	_info("pause_down_path", str(path))
	await _key(KEY_RIGHT)
	_info("pause_right_from_bottom", _cap(_focus()))
	await _key(KEY_DOWN)
	_info("pause_hat_down", _cap(_focus()))
	await _key(KEY_UP)
	_info("pause_hat_up", _cap(_focus()))
	await _shot("w1_pause_wardrobe_focus")
	await _key(KEY_LEFT)
	_info("pause_left_back_to_menu", _cap(_focus()))
	await _pad_button(JOY_BUTTON_B)
	await _wait(0.4)
	var b_closed: bool = not UI.pause_menu.is_open()
	_check("pad_B_closes_pause", b_closed)
	if b_closed:
		await _key(KEY_ESCAPE)
		await _wait(0.6)
	_focus_caption("Resume")
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.4)
	var a_resumed: bool = not UI.pause_menu.is_open()
	_check("pad_A_resume_button", a_resumed)
	if a_resumed:
		await _key(KEY_ESCAPE)
		await _wait(0.6)
	_focus_caption("Return to library")
	await _shot("w1_pause_library_focus")
	await _key(KEY_ENTER)
	await _wait_router(30.0)
	await _wait(2.0)
	await _shot("hub_from_library")
	_check("library_returns_hub", _world_id() == "HUB", "scene=" + _scene_name())
	_check("library_no_auto_book", not UI.mission_select.visible)
	_check("library_unpaused", not get_tree().paused)
	if _player():
		_info("hub_spawn_after_library", str(_player().global_position))
	# ---------------- Hub: pad Start, d-pad to Quit to title
	await _pad_button(JOY_BUTTON_START)
	await _wait(0.6)
	f = _focus()
	_check("pad_start_pauses", UI.pause_menu.is_open(), "focus=" + _cap(f))
	await _shot("hub_pause_pad")
	path = []
	for i in 4:
		await _pad_button(JOY_BUTTON_DPAD_DOWN)
		path.append(_cap(_focus()))
	_info("hub_pause_dpad_path", str(path))
	_focus_caption("Quit to title")
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.5)
	if UI.pause_menu.is_open():
		await _key(KEY_ENTER)
	await _wait_router(30.0)
	await _wait(3.0)
	await _shot("title_after_quit")
	_check("quit_reaches_title", _title() != null, "scene=" + _scene_name())
	# ---------------- Title (with progress): pad press, menu
	await _pad_button(JOY_BUTTON_A)
	await _wait(1.0)
	f = _focus()
	_check("title_focus_continue_with_save", _cap(f) == "Continue", "focus=" + _cap(f))
	await _shot("title_menu_with_save")
	# Confirm dialog focus leak
	_focus_caption("New Game")
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.4)
	if _title_state() != "confirm":
		await _key(KEY_ENTER)
		await _wait(0.4)
	f = _focus()
	_info("confirm_initial_focus", _cap(f) + " state=" + _title_state())
	await _shot("title_confirm")
	var leak: Array = []
	for d in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_UP]:
		await _pad_button(d)
		leak.append(_cap(_focus()))
	_info("confirm_dpad_path", str(leak))
	var leaked := false
	for c in leak:
		if c in ["Continue", "New Game", "Settings", "Quit"]:
			leaked = true
	_check("confirm_focus_contained", not leaked, str(leak))
	await _shot("title_confirm_after_dpad")
	await _pad_button(JOY_BUTTON_B)
	await _wait(0.3)
	_check("pad_B_cancels_confirm", _title_state() != "confirm", "state=" + _title_state())
	if _title_state() == "confirm":
		await _key(KEY_ESCAPE)
		await _wait(0.3)
	_info("after_confirm_cancel", "state=%s focus=%s" % [_title_state(), _cap(_focus())])
	# ---------------- Settings probes (pad only)
	_focus_caption("Settings")
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.6)
	if _find_settings() == null:
		await _key(KEY_ENTER)
		await _wait(0.6)
	await _shot("settings_open")
	var settings := _find_settings()
	_check("settings_open", settings != null and settings.visible)
	# walk down with the d-pad until a keyboard binding button gets focus
	var steps := 0
	var hit_kb := false
	var trail: Array = []
	while steps < 40:
		await _pad_button(JOY_BUTTON_DPAD_DOWN)
		steps += 1
		var fo := _focus()
		trail.append(_desc(fo))
		if fo is Button and fo.get_class() == "Button" and not (fo is StoryButton) and fo.get_script() == null and fo.text != "" and not (fo is CheckButton):
			hit_kb = true
			break
	_info("settings_dpad_trail", str(trail))
	await _shot("settings_keyboard_row_focus")
	if hit_kb:
		await _pad_button(JOY_BUTTON_A)
		await _wait(0.2)
		if String(settings.get("_waiting_action")) == "":
			_info("pad_A_on_key_row", "no effect; using Enter to start capture")
			await _key(KEY_ENTER)
			await _wait(0.2)
		await _shot("settings_waiting_key")
		await _pad_button(JOY_BUTTON_B)
		await _wait(0.2)
		await _pad_button(JOY_BUTTON_START)
		await _wait(0.2)
		await _pad_button(JOY_BUTTON_DPAD_DOWN)
		var still_waiting := String(settings.get("_waiting_action")) != ""
		_check("settings_pad_can_escape_key_capture", not still_waiting, "waiting_action=" + String(settings.get("_waiting_action")))
		await _shot("settings_stuck_after_pad_b")
		# recover with the keyboard (Escape cancels capture)
		await _key(KEY_ESCAPE)
		await _wait(0.2)
	# pad binding: press A on a controller row, then B ("cancel" for a pad player)
	var pad_row: Control = null
	for n in _all(settings):
		if n is Button and n.get_script() != null and "waiting" in n:
			pad_row = n
			break
	if pad_row:
		var act := String(pad_row.get("action"))
		pad_row.grab_focus()
		await _wait(0.2)
		var before: int = Game.primary_pad_button(act)
		await _pad_button(JOY_BUTTON_A)
		await _wait(0.2)
		if settings.get("_waiting_pad") == null:
			_info("pad_A_on_pad_row", "no effect; using Enter to start capture")
			await _key(KEY_ENTER)
			await _wait(0.2)
		await _pad_button(JOY_BUTTON_B)
		await _wait(0.3)
		var after: int = Game.primary_pad_button(act)
		_check("pad_rebind_b_cancels", before == after, "%s %d -> %d" % [act, before, after])
		await _shot("settings_pad_row_after_b")
		# Duplicate binding: jump onto X (attack's button)
		Game.rebind_pad("jump", JOY_BUTTON_X)
		var dup := Game.primary_pad_button("jump") == Game.primary_pad_button("attack")
		_check("pad_rebind_prevents_duplicates", not dup, "jump=%d attack=%d" % [Game.primary_pad_button("jump"), Game.primary_pad_button("attack")])
		Game.reset_bindings()
	# close settings with pad B
	await _pad_button(JOY_BUTTON_B)
	await _wait(0.4)
	_check("settings_close_pad_b", settings == null or not settings.visible, "focus=" + _cap(_focus()))
	_info("after_settings_focus", _cap(_focus()))
	# ---------------- Continue
	_focus_caption("Continue")
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.5)
	if not Router.busy and _title() != null:
		await _key(KEY_ENTER)
	await _wait_router(30.0)
	await _wait(2.0)
	await _shot("hub_after_continue")
	_check("continue_reaches_hub", _world_id() == "HUB", "scene=" + _scene_name())
	if _player():
		_info("hub_spawn_after_continue", str(_player().global_position))
	# ---------------- Pause -> Settings -> back focus; pause B resumes
	await _key(KEY_ESCAPE)
	await _wait(0.6)
	_focus_caption("Settings")
	await _key(KEY_ENTER)
	await _wait(0.5)
	await _shot("hub_pause_settings")
	await _key(KEY_BACKSPACE)
	await _wait(0.4)
	_info("pause_settings_back_focus", _cap(_focus()))
	await _pad_button(JOY_BUTTON_B)
	await _wait(0.5)
	_check("pause_b_resumes", not UI.pause_menu.is_open() and not get_tree().paused)
	# ---------------- Locked book feedback (W2 needs 3)
	var p2 := _find(get_tree().current_scene, "Book_W2")
	if p2 and _player():
		var z := _find(p2, "PageZone") as Node3D
		_player().global_position = z.global_position if z else p2.global_position + Vector3(0, 3, 0)
		await _wait(1.0)
		await _shot("hub_locked_book_w2")
		_info("locked_book_dialog_open", str(UI.is_dialog_open()))
		for i in 3:
			await _key(KEY_E)
			await _wait(0.4)
	_finish()


# ---------------------------------------------------------------- helpers

func _finish() -> void:
	var fails := 0
	for r in _results:
		if not r[1]:
			fails += 1
	print("[Crit] DONE %s %d checks, %d failed" % [tag, _results.size(), fails])
	get_tree().quit()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append([name, ok])
	print("[Crit] %s %s %s" % ["PASS" if ok else "FAIL", name, detail])


func _info(name: String, detail: String) -> void:
	print("[Crit] INFO %s %s" % [name, detail])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _wait_router(limit: float) -> void:
	var t0 := 0.0
	while not Router.busy and t0 < 3.0:
		await get_tree().process_frame
		t0 += get_process_delta_time()
	var t := 0.0
	while (Router.busy) and t < limit:
		await get_tree().process_frame
		t += get_process_delta_time()
	print("[Crit] router settled after %.1f s" % t)


func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	await _send(e)
	var u := e.duplicate() as InputEventKey
	u.pressed = false
	await _send(u)
	await _wait(0.12)


func _pad_button(b: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = true
	e.pressure = 1.0
	await _send(e)
	var u := e.duplicate() as InputEventJoypadButton
	u.pressed = false
	u.pressure = 0.0
	await _send(u)
	await _wait(0.12)


func _pad_axis(axis: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = v
	await _send(e)
	await _wait(0.05)
	var u := InputEventJoypadMotion.new()
	u.device = 0
	u.axis = axis
	u.axis_value = 0.0
	await _send(u)
	await _wait(0.12)


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _cap(c: Control) -> String:
	if c == null:
		return "<none>"
	if "caption" in c and String(c.get("caption")) != "":
		return String(c.get("caption"))
	if c is Button and (c as Button).text != "":
		return (c as Button).text
	return c.get_class() + ":" + String(c.name)


func _desc(c: Control) -> String:
	if c == null:
		return "<none>"
	return "%s(%s)" % [c.get_class(), _cap(c)]


func _focus_caption(caption: String) -> void:
	for n in _all(get_tree().root):
		if n is Control and n.is_visible_in_tree() and "caption" in n and String(n.get("caption")) == caption:
			(n as Control).grab_focus()
			return
	print("[Crit] WARN no visible control with caption ", caption)


func _all(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _find(root: Node, nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _player() -> Node3D:
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] as Node3D if ps.size() > 0 else null


func _world_id() -> String:
	var cs := get_tree().current_scene
	if cs and "world_id" in cs:
		return String(cs.get("world_id"))
	return ""


func _scene_name() -> String:
	var cs := get_tree().current_scene
	return cs.scene_file_path if cs else "<none>"


func _hud_visible() -> bool:
	for n in get_tree().get_nodes_in_group("hud"):
		if n is CanvasLayer:
			return (n as CanvasLayer).visible
	return false


func _title() -> Node:
	for n in _all(get_tree().root):
		if n.get_script() and String((n.get_script() as Script).resource_path).ends_with("title_screen.gd"):
			return n
	return null


func _title_state() -> String:
	var t := _title()
	return String(t.get("state")) if t else "<no title>"


func _find_settings() -> Control:
	for n in _all(get_tree().root):
		if n is Control and n.get_script() and String((n.get_script() as Script).resource_path).ends_with("settings_menu.gd") and (n as Control).visible:
			return n
	return null


func _shot(caption: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_step += 1
	var p := "%s/%s__%02d_%s.png" % [out_dir, tag, _step, caption]
	if img:
		img.save_png(p)
	print("[Crit] SHOT ", p)

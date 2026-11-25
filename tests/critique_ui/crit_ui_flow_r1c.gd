extends Node
## UI critique round 1c (usability and flow, after the UI round-2 fix pass).
## Unlike r1, this driver NEVER calls grab_focus() and never re-arms gameplay gates: every menu item is
## reached by real controller events (InputEventJoypadButton / InputEventJoypadMotion), and Book 1 is
## approached step by step so the hub's sheep gag fires exactly as it would for a first-time player.
## Flow: title (pad) -> New Game -> hub -> walk to Book 1 (gag) -> book during chase -> catch -> dialog (pad A)
## -> Book 1 -> mission (pad) -> W1 banner -> Restart at bookmark -> Return to library -> book re-entry
## -> Quit to title -> Continue focus -> Settings scroll/focus audit (pad) -> Continue -> hub
## -> pause Settings back -> unknown-world guard -> device glyph probes.
## Args (after --): --profile=<p> --crit-out=<abs dir>

var out_dir := ""
var tag := ""
var _results: Array = []
var _step := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("crit-out", OS.get_user_data_dir()) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var parent := get_parent()
	parent.remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	tag = "%dx%d" % [int(DisplayServer.window_get_size().x), int(DisplayServer.window_get_size().y)]
	print("[Crit] window ", tag)
	get_tree().change_scene_to_file("res://scenes/boot/Boot.tscn")
	await _wait(3.5)
	await _shot("title_press")
	# ---------------- Title, pad only
	await _pad_button(JOY_BUTTON_A)
	await _wait(1.0)
	_check("pad_A_opens_title_menu", _title_state() == "menu", "state=" + _title_state())
	_check("ui_last_device_gamepad_after_pad", UI.last_device == "gamepad", "last_device=" + UI.last_device)
	await _shot("title_menu_pad")
	_check("title_fresh_focus_new_game", _cap(_focus()) == "New Game", "focus=" + _cap(_focus()))
	var path: Array = []
	for i in 5:
		await _pad_button(JOY_BUTTON_DPAD_DOWN)
		path.append(_cap(_focus()))
	_info("title_dpad_down_path", str(path))
	var ok := await _pad_nav_to("New Game", JOY_BUTTON_DPAD_UP, 6)
	_check("title_pad_reaches_new_game", ok)
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.6)
	if _title_state() == "confirm":
		_info("new_game_confirm_on_fresh_save", "confirm shown on a fresh profile")
		await _pad_button(JOY_BUTTON_A)
	await _wait_router(40.0)
	await _wait(1.0)
	await _shot("hub_first_arrival_t1")
	await _wait(2.0)
	await _shot("hub_first_arrival_t3")
	_check("new_game_reaches_hub", _world_id() == "HUB", "scene=" + _scene_name())
	_check("hub_hud_visible", _hud_visible())
	var player := _player()
	var portal := _find(get_tree().current_scene, "Book_W1")
	var acts := _find_script(get_tree().current_scene, "hub_activities.gd")
	_info("hub_spawn", str(player.global_position) if player else "<no player>")
	# ---------------- Walk to Book 1 (step-teleports along the floor, 0.5 m per 3 frames)
	var zone: Area3D = _find(portal, "PageZone") as Area3D if portal else null
	if player and zone:
		_info("book1_dist_from_spawn", "%.1f m" % _flat(player.global_position, zone.global_position))
		var gag_woke_at := -1.0
		var start := player.global_position
		var goal := zone.global_position
		var d := _flat(start, goal)
		var n := int(ceil(d / 0.5))
		for i in range(1, n + 1):
			var p := start.lerp(goal, float(i) / n)
			p.y = maxf(start.y, goal.y) if i == n else start.y + 0.05
			player.global_position = p
			if player.has_method("reset_physics_interpolation"):
				player.reset_physics_interpolation()
			for k in 3:
				await get_tree().physics_frame
			if acts and gag_woke_at < 0.0 and String(acts.get("_cub_state")) != "rug":
				gag_woke_at = _flat(p, goal)
				await _wait(0.5)
				await _shot("gag_wakes_toast")
		_info("gag_woke_at_dist_to_zone", "%.1f m state=%s" % [gag_woke_at, String(acts.get("_cub_state")) if acts else "?"])
		await _wait(1.2)
		await _shot("book1_entered_during_chase")
		_check("book1_during_chase_gives_feedback", UI.mission_select.visible or UI.is_dialog_open(),
			"mission_select=%s dialog=%s route_on_enter=%s" % [UI.mission_select.visible, UI.is_dialog_open(), str(portal.get("route_on_enter"))])
		# Catch the sheep (gameplay shortcut, the chase itself is the hub track's), then the reward dialog by pad A.
		if acts and String(acts.get("_cub_state")) in ["run", "aim", "windup", "charge", "skid", "dizzy"]:
			acts.call("_catch_cub")
			var t0 := Time.get_ticks_msec()
			while not UI.is_dialog_open() and Time.get_ticks_msec() - t0 < 4000:
				await get_tree().process_frame
			await _wait(0.8)
			await _shot("bramwell_reward_dialog")
			_check("catch_opens_dialog", UI.is_dialog_open())
			var presses := 0
			while UI.is_dialog_open() and presses < 12:
				await _pad_button(JOY_BUTTON_A)
				await _wait(0.35)
				presses += 1
			_check("dialog_pad_A_closes", not UI.is_dialog_open(), "presses=%d" % presses)
		await _wait(0.5)
		_info("book1_armed_after_catch", str(portal.get("route_on_enter")))
		# Step out and back in (cooldown 3 s)
		player.global_position = start
		await _wait(3.3)
		player.global_position = goal
		if player.has_method("reset_physics_interpolation"):
			player.reset_physics_interpolation()
		await _wait(0.6)
		_check("book1_opens_after_catch", UI.mission_select.visible)
	# ---------------- Mission select, pad only
	if UI.mission_select.visible:
		var t1 := Time.get_ticks_msec()
		while String(UI.mission_select.get("_state")) != "open" and Time.get_ticks_msec() - t1 < 4000:
			await get_tree().process_frame
		await _wait(0.3)
		var f := _focus()
		_info("mission_default_focus", _cap(f) + " goal=" + (String(f.get("goal")) if f and "goal" in f else "?"))
		await _shot("mission_open_default_focus")
		path = []
		for i in 9:
			await _pad_axis(JOY_AXIS_LEFT_Y, 1.0)
			path.append(_cap(_focus()))
		_info("mission_stick_down_path", str(path))
		ok = await _pad_nav_to("Straw House Siege", JOY_BUTTON_DPAD_UP, 9)
		_check("mission_pad_reaches_w1_1", ok)
		await _shot("mission_w1_1_focus_goal")
		await _pad_button(JOY_BUTTON_A)
		await _wait_router(45.0)
		await _wait(0.6)
		await _shot("w1_entry_banner")
		await _wait(2.0)
		_check("book_enters_w1", _world_id() == "W1", "scene=" + _scene_name())
		_check("w1_unblocked_after_entry", not UI.is_input_blocked() and not get_tree().paused)
	# ---------------- W1 pause by pad: Restart at bookmark
	if _world_id() == "W1":
		await _pad_button(JOY_BUTTON_START)
		await _wait(0.6)
		_check("w1_pad_start_pauses", UI.pause_menu.is_open(), "focus=" + _cap(_focus()))
		await _shot("w1_pause_pad")
		path = []
		for i in 6:
			await _pad_button(JOY_BUTTON_DPAD_DOWN)
			path.append(_cap(_focus()))
		_info("w1_pause_dpad_path", str(path))
		ok = await _pad_nav_to("Restart at bookmark", JOY_BUTTON_DPAD_UP, 6)
		_check("pause_pad_reaches_restart", ok)
		await _pad_button(JOY_BUTTON_A)
		await _wait(0.5)
		_info("restart_confirm_or_router", "router_busy=%s pause_open=%s" % [Router.busy, UI.pause_menu.is_open()])
		await _wait_router(40.0)
		await _wait(1.5)
		await _shot("w1_after_restart")
		_check("restart_stays_in_w1_unpaused", _world_id() == "W1" and not get_tree().paused and not UI.pause_menu.is_open(), "scene=" + _scene_name())
		# Return to library
		await _pad_button(JOY_BUTTON_START)
		await _wait(0.6)
		var presses := 0
		while _cap(_focus()) != "Return to library" and presses < 6:
			await _pad_button(JOY_BUTTON_DPAD_DOWN)
			presses += 1
		_info("pad_presses_to_return_library", str(presses))
		await _shot("w1_pause_return_focus")
		await _pad_button(JOY_BUTTON_A)
		await _wait_router(40.0)
		await _wait(2.0)
		await _shot("hub_after_return")
		_check("return_library_reaches_hub", _world_id() == "HUB", "scene=" + _scene_name())
		player = _player()
		portal = _find(get_tree().current_scene, "Book_W1")
		if player and portal:
			_info("hub_return_dist_to_book1", "%.1f m" % _flat(player.global_position, portal.global_position))
		_check("hub_return_no_auto_book", not UI.mission_select.visible and not get_tree().paused)
		acts = _find_script(get_tree().current_scene, "hub_activities.gd")
		_info("hub_return_cub_state", String(acts.get("_cub_state")) if acts and acts.get("_cub") != null else "<cub gone>")
		zone = _find(portal, "PageZone") as Area3D if portal else null
		if zone and player:
			var start2 := player.global_position
			player.global_position = start2 + (start2 - zone.global_position).normalized() * 4.0
			await _wait(3.2)
			player.global_position = zone.global_position
			await _wait(0.8)
			_check("book1_reopens_after_return", UI.mission_select.visible)
			await _pad_button(JOY_BUTTON_B)
			await _wait(1.0)
			_check("book_pad_B_closes", not UI.mission_select.visible and not get_tree().paused)
			player.global_position = start2
			await _wait(0.5)
	# ---------------- Hub pause -> Quit to title (pad)
	await _pad_button(JOY_BUTTON_START)
	await _wait(0.6)
	_check("hub_pad_start_pauses", UI.pause_menu.is_open())
	await _shot("hub_pause_pad")
	ok = await _pad_nav_to("Quit to title", JOY_BUTTON_DPAD_DOWN, 7)
	_check("pause_pad_reaches_quit", ok)
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.5)
	_info("quit_confirm_or_router", "router_busy=%s pause_open=%s" % [Router.busy, UI.pause_menu.is_open()])
	await _wait_router(30.0)
	await _wait(3.0)
	_check("quit_reaches_title", _title() != null, "scene=" + _scene_name())
	await _pad_button(JOY_BUTTON_A)
	await _wait(1.0)
	_check("title_with_save_focus_continue", _cap(_focus()) == "Continue", "focus=" + _cap(_focus()))
	await _shot("title_menu_with_save_pad")
	# ---------------- Settings audit by pad
	ok = await _pad_nav_to("Settings", JOY_BUTTON_DPAD_DOWN, 6)
	_check("title_pad_reaches_settings", ok)
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.7)
	var settings := _find_settings()
	_check("settings_open_pad", settings != null)
	if settings:
		await _shot("settings_top_pad")
		var scroll: ScrollContainer = _first_of(settings, "ScrollContainer") as ScrollContainer
		var seen: Array = []
		var off := 0
		var invisible_focus := 0
		var slider_moved := false
		var trail: Array = []
		for i in 60:
			await _pad_button(JOY_BUTTON_DPAD_DOWN)
			await _wait(0.1)
			var fo := _focus()
			if fo == null:
				invisible_focus += 1
				trail.append("<none>")
				continue
			trail.append(_desc(fo))
			if scroll and not scroll.get_global_rect().grow(2).encloses(fo.get_global_rect()) and scroll.is_ancestor_of(fo):
				off += 1
			if fo is Slider and not slider_moved:
				var v0: float = (fo as Slider).value
				await _pad_button(JOY_BUTTON_DPAD_RIGHT)
				var v1: float = (fo as Slider).value
				await _pad_button(JOY_BUTTON_DPAD_LEFT)
				slider_moved = v1 != v0
				_info("slider_dpad_right", "%s %.2f -> %.2f (focus after=%s)" % [fo.name, v0, v1, _desc(_focus())])
			if seen.has(fo) and i > 3:
				_info("settings_wrapped_at", str(i))
				break
			seen.append(fo)
			if i == 10:
				await _shot("settings_mid_pad")
		_info("settings_dpad_trail", str(trail))
		_check("settings_focus_always_on_screen", off == 0, "off_screen_steps=%d" % off)
		_check("settings_focus_never_lost", invisible_focus == 0, "lost=%d" % invisible_focus)
		_check("settings_slider_dpad_adjusts", slider_moved)
		await _shot("settings_bottom_pad")
		# Pad-only rebind: d-pad onto the first controller row, A, then press Y. Did the action move to Y?
		var pad_row: Control = null
		for n2 in _all(settings):
			if n2 is Button and n2.get_script() != null and "waiting" in n2:
				pad_row = n2
				break
		if pad_row:
			var guard := 0
			while _focus() != pad_row and guard < 60:
				await _pad_button(JOY_BUTTON_DPAD_UP if _focus() and _focus().get_global_rect().position.y > pad_row.get_global_rect().position.y else JOY_BUTTON_DPAD_DOWN)
				guard += 1
			var act := String(pad_row.get("action"))
			var before: int = Game.primary_pad_button(act)
			_info("pad_row_reached", "%s steps=%d focus_is_row=%s" % [act, guard, str(_focus() == pad_row)])
			await _pad_button(JOY_BUTTON_A)
			await _wait(0.25)
			var waiting_after_a := settings.get("_waiting_pad") != null
			await _shot("settings_pad_row_after_A")
			await _pad_button(JOY_BUTTON_Y)
			await _wait(0.3)
			var after: int = Game.primary_pad_button(act)
			_check("settings_pad_only_rebind_works", waiting_after_a and after == JOY_BUTTON_Y,
				"%s waiting_after_A=%s %d -> %d" % [act, waiting_after_a, before, after])
			Game.reset_bindings()
		await _pad_button(JOY_BUTTON_B)
		await _wait(0.5)
		_check("settings_pad_B_closes", _find_settings() == null)
		_check("settings_close_returns_focus_to_settings", _cap(_focus()) == "Settings", "focus=" + _cap(_focus()))
	# ---------------- Continue (pad)
	ok = await _pad_nav_to("Continue", JOY_BUTTON_DPAD_UP, 6)
	_check("title_pad_reaches_continue", ok)
	await _pad_button(JOY_BUTTON_A)
	await _wait_router(40.0)
	await _wait(2.0)
	await _shot("hub_after_continue_pad")
	_check("continue_reaches_hub", _world_id() == "HUB", "scene=" + _scene_name())
	# ---------------- Pause -> Settings -> B back to pause
	await _pad_button(JOY_BUTTON_START)
	await _wait(0.6)
	ok = await _pad_nav_to("Settings", JOY_BUTTON_DPAD_DOWN, 6)
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.6)
	_check("pause_settings_opens_pad", _find_settings() != null)
	await _shot("pause_settings_pad")
	await _pad_button(JOY_BUTTON_B)
	await _wait(0.5)
	_check("pause_settings_B_back_to_pause", _find_settings() == null and UI.pause_menu.is_open() and _cap(_focus()) == "Settings",
		"pause_open=%s focus=%s" % [UI.pause_menu.is_open(), _cap(_focus())])
	await _pad_button(JOY_BUTTON_B)
	await _wait(0.5)
	_check("pause_B_resumes", not UI.pause_menu.is_open() and not get_tree().paused)
	# ---------------- NPC talk prompt on a pad
	var talkers: Array = []
	for nd in _all(get_tree().current_scene):
		if nd.get_script() and String((nd.get_script() as Script).resource_path).ends_with("talker.gd"):
			talkers.append("%s:'%s'" % [nd.name, String(nd.get("prompt_text"))])
	_info("hub_talker_prompts_with_pad", str(talkers))
	# ---------------- Unknown world guard (pad dismiss)
	Router.enter_world("W9", "")
	await _wait(2.5)
	await _shot("unknown_world_page")
	await _pad_button(JOY_BUTTON_A)
	await _wait_router(30.0)
	await _wait(1.5)
	_check("unknown_world_returns_hub", _world_id() == "HUB", "scene=" + _scene_name())
	_check("unknown_world_unblocked", not get_tree().paused and not UI.is_input_blocked())
	await _shot("after_unknown_world")
	_finish()


# ---------------------------------------------------------------- helpers

func _pad_nav_to(caption: String, dir: JoyButton, max_steps: int) -> bool:
	if _cap(_focus()) == caption:
		return true
	for i in max_steps:
		await _pad_button(dir)
		if _cap(_focus()) == caption:
			return true
	print("[Crit] WARN pad could not reach ", caption, " (focus=", _cap(_focus()), ")")
	return false


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
	while Router.busy and t < limit:
		await get_tree().process_frame
		t += get_process_delta_time()
	print("[Crit] router settled after %.1f s" % t)


func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


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


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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


func _first_of(root: Node, cls: String) -> Node:
	for n in _all(root):
		if n.get_class() == cls:
			return n
	return null


func _find(root: Node, nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _find_script(root: Node, suffix: String) -> Node:
	for n in _all(root):
		if n.get_script() and String((n.get_script() as Script).resource_path).ends_with(suffix):
			return n
	return null


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
	return _find_script(get_tree().root, "title_screen.gd")


func _title_state() -> String:
	var t := _title()
	return String(t.get("state")) if t else "<no title>"


func _find_settings() -> Control:
	for n in _all(get_tree().root):
		if n is Control and n.get_script() and String((n.get_script() as Script).resource_path).ends_with("settings_menu.gd") and (n as Control).is_visible_in_tree():
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

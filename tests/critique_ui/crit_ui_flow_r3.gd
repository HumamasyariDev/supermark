extends Node
## UI critique round 1 re-review r3 (usability and flow lens), after the UI round-4 fix stage (11:27-12:15 Bangkok).
## Forked from crit_ui_flow_r2.gd. Adds: --crit-size=WxH window, fresh-profile title idle audit (intro hijack),
## first-arrival intro timeline, book-over-dialog guard sampling, mission goal audit, pause wrap trail.
## Never calls grab_focus(): every menu step is a real InputEventJoypadButton / InputEventJoypadMotion / InputEventKey.
## Flow: title (pad) -> Quit confirm audit -> New Game -> hub (pause audit) -> walk to Book 1 (sheep gag) -> catch
## -> dialog -> Book 1 (pad) -> W1 banner -> W1 pause goal -> Restart -> Return to library (confirm focus audit)
## -> hub camera -> book re-entry (keyboard Esc closes) -> Quit to title (confirm) -> Settings (pad) -> Continue
## -> keyboard pause pass -> unknown-world guard. Also measures the smallest on-screen text at this resolution.
## Args (after --): --profile=<p> --crit-out=<abs dir>

var out_dir := ""
var tag := ""
var _results: Array = []
var _step := 0
var _scale := 1.0
var _seg := "0"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	out_dir = dev.arg("crit-out", OS.get_user_data_dir()) if dev else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var sz: String = dev.arg("crit-size", "") if dev else ""
	if sz.contains("x"):
		var wh := sz.split("x")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	var parent := get_parent()
	parent.remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_run.call_deferred()


func _run() -> void:
	for i in 6:
		await get_tree().process_frame
	var ws := DisplayServer.window_get_size()
	tag = "%dx%d" % [ws.x, ws.y]
	_scale = float(ws.y) / 1080.0
	var dev := get_node_or_null("/root/Dev")
	var seg: String = dev.arg("seg", "abcde") if dev else "abcde"
	print("[Crit] window ", tag, " ui_scale ", _scale, " seg ", seg)
	get_tree().change_scene_to_file("res://scenes/boot/Boot.tscn")
	if seg.begins_with("a") or seg.begins_with("e"):
		await _wait(3.5)
		await _shot("title_press")
		if seg.begins_with("e"):
			await _pad_button(JOY_BUTTON_A)
			await _wait(1.0)
	else:
		await _wait_router(40.0)
		await _wait(1.5)
	for s in seg:
		print("[Crit] SEG ", s)
		_seg = s
		match s:
			"a": await _seg_a()
			"b": await _seg_b()
			"c": await _seg_c()
			"d": await _seg_d()
			"e": await _seg_e()
			"f": await _seg_f()
	_finish()


func _seg_a() -> void:
	var player: Node3D = _player()
	var portal: Node = _find(get_tree().current_scene, "Book_W1")
	var acts: Node = _find_script(get_tree().current_scene, "hub_activities.gd")
	var zone: Area3D = null
	var items: Array = []
	var path: Array = []
	var ok := false
	# ---------------- Title idle on a fresh profile (r1 re-run blocker: the intro Wolf hijacked the title camera and HUD)
	var hud_seen := false
	var cam0 := get_viewport().get_camera_3d()
	var cam_changed := ""
	var t_idle := 0.0
	while t_idle < 14.0:
		await _wait(0.5)
		t_idle += 0.5
		if _hud_visible():
			hud_seen = true
		var c := get_viewport().get_camera_3d()
		if c != cam0 and cam_changed == "":
			cam_changed = "%s at %.1f s" % [c.name if c else "<none>", t_idle]
		if is_equal_approx(t_idle, 7.0):
			await _shot("title_idle_7s")
	await _shot("title_idle_14s")
	_check("title_idle_hud_hidden_14s", not hud_seen)
	_check("title_idle_camera_stable_14s", cam_changed == "", cam_changed)
	_check("title_active_flag", UI.is_title_active())
	_info("title_idle_texts", _visible_texts(14))
	# ---------------- Title, pad only
	await _pad_button(JOY_BUTTON_A)
	await _wait(1.0)
	_check("pad_A_opens_title_menu", _title_state() == "menu", "state=" + _title_state())
	_check("ui_last_device_gamepad_after_pad", UI.last_device == "gamepad", "last_device=" + UI.last_device)
	await _shot("title_menu_pad")
	_text_audit("title_menu")
	_check("title_fresh_focus_new_game", _cap(_focus()) == "New Game", "focus=" + _cap(_focus()))
	path = []
	for i in 5:
		await _pad_button(JOY_BUTTON_DPAD_DOWN)
		path.append(_cap(_focus()))
	_info("title_dpad_down_path", str(path))
	# Quit confirm audit
	ok = await _pad_nav_to("Quit", JOY_BUTTON_DPAD_DOWN, 6)
	if ok:
		await _pad_button(JOY_BUTTON_A)
		await _wait(0.6)
		_check("title_quit_confirms", _title_state() == "confirm", "state=" + _title_state())
		_check("title_quit_default_keep_reading", _cap(_focus()) == "Keep reading", "focus=" + _cap(_focus()))
		await _shot("title_quit_confirm")
		_info("title_quit_confirm_texts", _visible_texts(14))
		var leak: Array = []
		for b in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			await _pad_button(b)
			leak.append(_cap(_focus()))
		_info("title_confirm_dpad_trail", str(leak))
		_check("title_confirm_focus_stays_inside", not leak.has("New Game") and not leak.has("Settings") and not leak.has("Quit") and not leak.has("<none>"), str(leak))
		await _pad_button(JOY_BUTTON_B)
		await _wait(0.5)
		_check("title_confirm_B_cancels_to_quit", _title_state() == "menu" and _cap(_focus()) == "Quit",
			"state=%s focus=%s" % [_title_state(), _cap(_focus())])
	ok = await _pad_nav_to("New Game", JOY_BUTTON_DPAD_UP, 6)
	_check("title_pad_reaches_new_game", ok)
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.6)
	if _title_state() == "confirm":
		_info("new_game_confirm_on_fresh_save", "confirm shown on a fresh profile")
		await _pad_button(JOY_BUTTON_A)
	await _wait_router(40.0)
	var blocked_until := -1.0
	var tl: Array = []
	var ta := 0.0
	while ta < 24.0:
		await _wait(0.5)
		ta += 0.5
		var bl := UI.is_input_blocked() or UI.is_dialog_open()
		if bl:
			blocked_until = ta
		if fmod(ta, 2.0) < 0.01:
			tl.append("%.0fs blocked=%s dialog=%s hud=%s cam=%s" % [ta, bl, UI.is_dialog_open(), _hud_visible(), get_viewport().get_camera_3d().name if get_viewport().get_camera_3d() else "-"])
		if ta in [1.0, 3.0, 6.0, 10.0, 16.0]:
			await _shot("hub_first_arrival_t%d" % int(ta))
			_info("hub_first_arrival_texts_t%d" % int(ta), _visible_texts(14))
		if UI.is_dialog_open() and ta > 2.0:
			# advance intro dialog with pad A like a player would
			await _pad_button(JOY_BUTTON_A)
	_info("hub_first_arrival_timeline", str(tl))
	_info("hub_first_arrival_last_blocked", "%.1f s" % blocked_until)
	_text_audit("hub_first_arrival")
	var hudn := _find_script(get_tree().root, "hud.gd")
	_info("hub_objective_tag", String(hudn.get("_objective")) if hudn and "_objective" in hudn else "<n/a>")
	_check("hub_unblocked_after_intro", not UI.is_input_blocked() and not get_tree().paused)
	_check("new_game_reaches_hub", _world_id() == "HUB", "scene=" + _scene_name())
	_check("hub_hud_visible", _hud_visible())
	_info("hub_first_arrival_prompt_or_banner", _visible_texts(14))
	# ---------------- Hub pause audit (fresh save)
	await _pad_button(JOY_BUTTON_START)
	await _wait(0.7)
	_check("hub_pause_opens_pad", UI.pause_menu.is_open())
	items = _pause_items()
	_info("hub_pause_items", str(items))
	_check("hub_pause_hides_restart_and_return", not items.has("Restart at bookmark") and not items.has("Return to library"), str(items))
	_info("hub_pause_goal", _pause_goal())
	await _shot("hub_pause_fresh")
	_text_audit("hub_pause")
	path = []
	for i in 4:
		await _pad_button(JOY_BUTTON_DPAD_DOWN)
		path.append(_cap(_focus()))
	await _pad_button(JOY_BUTTON_DPAD_RIGHT)
	path.append("R:" + _cap(_focus()))
	await _pad_button(JOY_BUTTON_DPAD_RIGHT)
	path.append("R:" + _cap(_focus()))
	await _pad_button(JOY_BUTTON_DPAD_LEFT)
	path.append("L:" + _cap(_focus()))
	await _pad_button(JOY_BUTTON_DPAD_LEFT)
	path.append("L:" + _cap(_focus()))
	_info("hub_pause_nav_trail", str(path))
	await _pad_button(JOY_BUTTON_B)
	await _wait(0.5)
	_check("hub_pause_B_resumes", not UI.pause_menu.is_open() and not get_tree().paused)
	var longg: Array = []
	for w in ["W1", "W2", "W3"]:
		for i in range(1, 9):
			var tid := "%s-%d" % [w, i]
			var g := WorldRegistry.truffle_goal(tid)
			if g.length() > 40:
				longg.append("%s(%d):%s" % [tid, g.length(), g])
	_check("all_goals_le_40_chars", longg.is_empty(), str(longg))
	await get_tree().process_frame

func _seg_b() -> void:
	var player: Node3D = _player()
	var portal: Node = _find(get_tree().current_scene, "Book_W1")
	var acts: Node = _find_script(get_tree().current_scene, "hub_activities.gd")
	var zone: Area3D = null
	var items: Array = []
	var path: Array = []
	var ok := false
	player = _player()
	portal = _find(get_tree().current_scene, "Book_W1")
	acts = _find_script(get_tree().current_scene, "hub_activities.gd")
	_info("hub_spawn", str(player.global_position) if player else "<no player>")
	# ---------------- Walk to Book 1 (step-teleports along the floor, 0.5 m per 3 frames)
	zone = _find(portal, "PageZone") as Area3D if portal else null
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
				await _wait(0.6)
				await _shot("gag_wakes")
				_info("gag_wake_texts", _visible_texts(14))
		_info("gag_woke_at_dist_to_zone", "%.1f m state=%s" % [gag_woke_at, String(acts.get("_cub_state")) if acts else "?"])
		await _wait(1.2)
		await _shot("book1_entered_during_chase")
		_info("book1_during_chase_texts", _visible_texts(14))
		_check("book1_during_chase_gives_feedback", UI.mission_select.visible or UI.is_dialog_open() or _visible_texts(14).to_lower().contains("sheep") or _visible_texts(14).to_lower().contains("book"),
			"mission_select=%s dialog=%s route_on_enter=%s" % [UI.mission_select.visible, UI.is_dialog_open(), str(portal.get("route_on_enter"))])
		if acts and String(acts.get("_cub_state")) in ["waking", "run", "aim", "windup", "charge", "skid", "dizzy"]:
			acts.call("_catch_cub")
			var t0 := Time.get_ticks_msec()
			while not UI.is_dialog_open() and Time.get_ticks_msec() - t0 < 4000:
				await get_tree().process_frame
			var overlap := 0
			for fr in 60:
				await get_tree().process_frame
				if UI.is_dialog_open() and UI.mission_select.visible:
					overlap += 1
			_check("book_never_over_dialog", overlap == 0, "overlap_frames=%d" % overlap)
			await _shot("bramwell_reward_dialog")
			_text_audit("dialog")
			_check("catch_opens_dialog", UI.is_dialog_open())
			var presses := 0
			while UI.is_dialog_open() and presses < 12:
				await _pad_button(JOY_BUTTON_A)
				await _wait(0.35)
				presses += 1
			_check("dialog_pad_A_closes", not UI.is_dialog_open(), "presses=%d" % presses)
			_check("last_device_gamepad_after_pad_only_dialog", UI.last_device == "gamepad", "last_device=" + UI.last_device)
			await _wait(0.6)
			await _shot("after_reward_dialog")
			_info("after_reward_texts", _visible_texts(14))
			_info("book_auto_opens_after_dialog", str(UI.mission_select.visible))
			if UI.mission_select.visible:
				await _wait(1.6)
				await _shot("book_after_dialog_queued")
				await _pad_button(JOY_BUTTON_B)
				await _wait(1.2)
		await _wait(0.5)
		_info("book1_armed_after_catch", str(portal.get("route_on_enter")))
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
		_text_audit("mission_select")
		path = []
		for i in 9:
			await _pad_axis(JOY_AXIS_LEFT_Y, 1.0)
			path.append(_cap(_focus()))
			if i == 3:
				await _shot("mission_row4_goal")
		_info("mission_stick_down_path", str(path))
		_check("mission_footer_gamepad_after_stick", UI.last_device == "gamepad", "last_device=" + UI.last_device)
		await _shot("mission_after_pad_nav_footer")
		ok = await _pad_nav_to("Straw House Siege", JOY_BUTTON_DPAD_UP, 9)
		_check("mission_pad_reaches_w1_1", ok)
		await _pad_button(JOY_BUTTON_A)
		await _wait_router(45.0)
		await _wait(0.6)
		await _shot("w1_entry_banner")
		_info("w1_entry_texts", _visible_texts(14))
		await _wait(2.0)
		_check("book_enters_w1", _world_id() == "W1", "scene=" + _scene_name())
		_check("w1_unblocked_after_entry", not UI.is_input_blocked() and not get_tree().paused)
		await _shot("w1_gameplay_hud")
		_text_audit("w1_hud")
	await get_tree().process_frame

func _seg_c() -> void:
	var player: Node3D = _player()
	var portal: Node = _find(get_tree().current_scene, "Book_W1")
	var acts: Node = _find_script(get_tree().current_scene, "hub_activities.gd")
	var zone: Area3D = null
	var items: Array = []
	var path: Array = []
	var ok := false
	# ---------------- W1 pause by pad
	if _world_id() == "W1":
		await _pad_button(JOY_BUTTON_START)
		await _wait(0.7)
		_check("w1_pad_start_pauses", UI.pause_menu.is_open(), "focus=" + _cap(_focus()))
		items = _pause_items()
		_info("w1_pause_items", str(items))
		_check("w1_pause_shows_goal", _pause_goal() != "", "goal=" + _pause_goal())
		await _shot("w1_pause_pad")
		_text_audit("w1_pause")
		ok = await _pad_nav_to("Restart at bookmark", JOY_BUTTON_DPAD_DOWN, 6)
		_check("pause_pad_reaches_restart", ok)
		await _pad_button(JOY_BUTTON_A)
		await _wait(0.5)
		_info("restart_confirm_or_router", "router_busy=%s pause_open=%s" % [Router.busy, UI.pause_menu.is_open()])
		await _wait_router(40.0)
		await _wait(1.5)
		await _shot("w1_after_restart")
		_check("restart_stays_in_w1_unpaused", _world_id() == "W1" and not get_tree().paused and not UI.pause_menu.is_open(), "scene=" + _scene_name())
		# Return to library with the confirm audit
		await _pad_button(JOY_BUTTON_START)
		await _wait(0.7)
		ok = await _pad_nav_to("Return to library", JOY_BUTTON_DPAD_DOWN, 6)
		_check("pause_pad_reaches_return", ok)
		await _pad_button(JOY_BUTTON_A)
		await _wait(0.6)
		var cf := _pause_confirm_visible()
		_check("return_library_confirms", cf, "focus=" + _cap(_focus()))
		_check("return_confirm_default_keep_reading", _cap(_focus()) == "Keep reading", "focus=" + _cap(_focus()))
		await _shot("w1_return_confirm")
		var trail: Array = []
		for b in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_RIGHT]:
			await _pad_button(b)
			trail.append(_desc(_focus()))
		_info("pause_confirm_dpad_trail", str(trail))
		var leaked := false
		for t in trail:
			if not (String(t).contains("Keep reading") or String(t).contains("Return to library")) or String(t).contains("<none>"):
				leaked = true
		# a "Return to library" entry in the trail could be the menu button behind; check ownership
		var fo := _focus()
		var conf := UI.pause_menu.get("_confirm") as Control
		_check("pause_confirm_focus_stays_inside", not leaked and conf != null and fo != null and conf.is_ancestor_of(fo), str(trail))
		if conf and fo and not conf.is_ancestor_of(fo):
			await _shot("pause_confirm_focus_leaked")
			# put focus back for the rest of the run through B (cancel) and re-ask
		await _pad_button(JOY_BUTTON_B)
		await _wait(0.5)
		_check("pause_confirm_B_cancels_keeps_pause", UI.pause_menu.is_open() and not _pause_confirm_visible(),
			"pause_open=%s focus=%s" % [UI.pause_menu.is_open(), _cap(_focus())])
		_info("focus_after_confirm_cancel", _desc(_focus()))
		ok = await _pad_nav_to("Return to library", JOY_BUTTON_DPAD_DOWN, 6)
		if not ok:
			ok = await _pad_nav_to("Return to library", JOY_BUTTON_DPAD_UP, 6)
		await _pad_button(JOY_BUTTON_A)
		await _wait(0.6)
		await _pad_nav_to("Return to library", JOY_BUTTON_DPAD_LEFT, 2)
		_info("confirm_yes_focus", _desc(_focus()))
		await _pad_button(JOY_BUTTON_A)
		await _wait_router(40.0)
		await _wait(2.0)
		await _shot("hub_after_return")
		_check("return_library_reaches_hub", _world_id() == "HUB", "scene=" + _scene_name())
		player = _player()
		portal = _find(get_tree().current_scene, "Book_W1")
		var cam := get_viewport().get_camera_3d()
		if player and cam:
			_info("hub_return_camera_dist", "%.2f m (cam=%s)" % [cam.global_position.distance_to(player.global_position + Vector3.UP * 0.6), cam.name])
		if player and portal:
			_info("hub_return_dist_to_book1", "%.1f m" % _flat(player.global_position, portal.global_position))
		_check("hub_return_no_auto_book", not UI.mission_select.visible and not get_tree().paused)
		zone = _find(portal, "PageZone") as Area3D if portal else null
		if zone and player:
			var start2 := player.global_position
			player.global_position = start2 + (start2 - zone.global_position).normalized() * 4.0
			await _wait(3.2)
			player.global_position = zone.global_position
			await _wait(0.8)
			_check("book1_reopens_after_return", UI.mission_select.visible)
			# keyboard Esc closes the book
			await _key(KEY_ESCAPE)
			await _wait(1.0)
			_check("book_keyboard_esc_closes", not UI.mission_select.visible and not get_tree().paused)
			_check("book_esc_does_not_open_pause", not UI.pause_menu.is_open())
			if UI.pause_menu.is_open():
				await _pad_button(JOY_BUTTON_B)
				await _wait(0.5)
			player.global_position = start2
			await _wait(0.5)
	await get_tree().process_frame

func _seg_d() -> void:
	var player: Node3D = _player()
	var portal: Node = _find(get_tree().current_scene, "Book_W1")
	var acts: Node = _find_script(get_tree().current_scene, "hub_activities.gd")
	var zone: Area3D = null
	var items: Array = []
	var path: Array = []
	var ok := false
	# ---------------- Hub pause -> Quit to title (pad) through the confirm
	await _pad_button(JOY_BUTTON_START)
	await _wait(0.7)
	_check("hub_pad_start_pauses", UI.pause_menu.is_open())
	items = _pause_items()
	_info("hub_pause_items_after_progress", str(items))
	await _shot("hub_pause_after_reward")
	ok = await _pad_nav_to("Quit to title", JOY_BUTTON_DPAD_DOWN, 7)
	_check("pause_pad_reaches_quit", ok)
	await _pad_button(JOY_BUTTON_A)
	await _wait(0.6)
	_check("quit_title_confirms", _pause_confirm_visible(), "focus=" + _cap(_focus()))
	await _shot("hub_quit_confirm")
	_text_audit("pause_confirm")
	await _pad_button(JOY_BUTTON_DPAD_LEFT)
	_info("quit_confirm_after_left", _desc(_focus()))
	await _pad_button(JOY_BUTTON_A)
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
		_text_audit("settings")
		var labels: Array = []
		for nd in _all(settings):
			if nd is Label and (nd as Label).is_visible_in_tree():
				labels.append((nd as Label).text)
		_check("settings_has_stick_camera_speed", labels.has("Stick camera speed"), "")
		var scroll: ScrollContainer = _first_of(settings, "ScrollContainer") as ScrollContainer
		var seen: Array = []
		var off := 0
		var invisible_focus := 0
		var slider_moved := false
		var strail: Array = []
		for i in 60:
			await _pad_button(JOY_BUTTON_DPAD_DOWN)
			await _wait(0.08)
			var sfo := _focus()
			if sfo == null:
				invisible_focus += 1
				strail.append("<none>")
				continue
			strail.append(_desc(sfo))
			if scroll and scroll.is_ancestor_of(sfo) and not scroll.get_global_rect().grow(2).encloses(sfo.get_global_rect()):
				off += 1
			if sfo is Slider and not slider_moved:
				var v0: float = (sfo as Slider).value
				await _pad_button(JOY_BUTTON_DPAD_RIGHT)
				var v1: float = (sfo as Slider).value
				await _pad_button(JOY_BUTTON_DPAD_LEFT)
				slider_moved = v1 != v0
			if seen.has(sfo) and i > 3:
				_info("settings_wrapped_at", str(i))
				break
			seen.append(sfo)
			if i == 6:
				await _shot("settings_camera_rows_pad")
			if i == 14:
				await _shot("settings_mid_pad")
		_info("settings_dpad_trail", str(strail))
		_check("settings_focus_always_on_screen", off == 0, "off_screen_steps=%d" % off)
		_check("settings_focus_never_lost", invisible_focus == 0, "lost=%d" % invisible_focus)
		_check("settings_slider_dpad_adjusts", slider_moved)
		await _shot("settings_bottom_pad")
		# Pad capture: reach the first controller row, A, screenshot the capture state, then B cancels.
		var pad_row: Control = null
		for n2 in _all(settings):
			if n2 is Button and n2.get_script() != null and "waiting" in n2 and String(n2.get("action")) == "jump":
				pad_row = n2
				break
		if pad_row:
			var guard := 0
			while _focus() != pad_row and guard < 60:
				await _pad_button(JOY_BUTTON_DPAD_UP if _focus() and _focus().get_global_rect().position.y > pad_row.get_global_rect().position.y else JOY_BUTTON_DPAD_DOWN)
				guard += 1
			var act := String(pad_row.get("action"))
			var before: int = Game.primary_pad_button(act)
			await _pad_button(JOY_BUTTON_A)
			await _wait(0.6)
			await _shot("settings_pad_capture_state")
			await _pad_button(JOY_BUTTON_B)
			await _wait(0.4)
			var after: int = Game.primary_pad_button(act)
			_check("settings_pad_capture_B_cancels", after == before and _find_settings() != null, "%s %d -> %d settings_open=%s" % [act, before, after, _find_settings() != null])
			# keyboard row: A then Esc should cancel and keep settings open
			var key_row: Control = null
			for n3 in _all(settings):
				if n3 is Button and (n3 as Button).text == "Space":
					key_row = n3
					break
			if key_row and _find_settings() != null:
				guard = 0
				while _focus() != key_row and guard < 60:
					await _pad_button(JOY_BUTTON_DPAD_UP if _focus() and _focus().get_global_rect().position.y > key_row.get_global_rect().position.y else JOY_BUTTON_DPAD_DOWN)
					guard += 1
				await _key(KEY_ENTER)
				await _wait(0.4)
				await _shot("settings_key_capture_state")
				_info("key_capture_text", (key_row as Button).text)
				await _key(KEY_ESCAPE)
				await _wait(0.4)
				_check("settings_key_capture_esc_cancels", _find_settings() != null and (key_row as Button).text == "Space",
					"text=%s settings_open=%s" % [(key_row as Button).text, _find_settings() != null])
		Game.reset_bindings()
		if _find_settings() != null:
			await _pad_button(JOY_BUTTON_B)
			await _wait(0.5)
		_check("settings_pad_B_closes", _find_settings() == null)
		_check("settings_close_returns_focus_to_settings", _cap(_focus()) == "Settings", "focus=" + _cap(_focus()))
	await get_tree().process_frame

func _seg_e() -> void:
	var player: Node3D = _player()
	var portal: Node = _find(get_tree().current_scene, "Book_W1")
	var acts: Node = _find_script(get_tree().current_scene, "hub_activities.gd")
	var zone: Area3D = null
	var items: Array = []
	var path: Array = []
	var ok := false
	# ---------------- Continue (pad)
	ok = await _pad_nav_to("Continue", JOY_BUTTON_DPAD_UP, 6)
	_check("title_pad_reaches_continue", ok)
	await _pad_button(JOY_BUTTON_A)
	await _wait_router(40.0)
	await _wait(2.0)
	await _shot("hub_after_continue_pad")
	_check("continue_reaches_hub", _world_id() == "HUB", "scene=" + _scene_name())
	player = _player()
	if player:
		_info("continue_spawn", str(player.global_position))
	# ---------------- Keyboard pause pass
	await _key(KEY_ESCAPE)
	await _wait(0.7)
	_check("kb_esc_pauses", UI.pause_menu.is_open())
	await _shot("hub_pause_keyboard_glyphs")
	_info("kb_pause_focus", _desc(_focus()))
	var kpath: Array = []
	for k2 in [KEY_DOWN, KEY_DOWN, KEY_DOWN, KEY_UP, KEY_UP, KEY_LEFT]:
		await _key(k2)
		kpath.append(OS.get_keycode_string(k2) + ":" + _cap(_focus()))
	_info("kb_pause_wardrobe_trap_trail", str(kpath))
	await _shot("hub_pause_focus_after_down_past_bottom")
	ok = await _key_nav_to("Settings", KEY_DOWN, 3)
	if not ok:
		ok = await _key_nav_to("Settings", KEY_UP, 3)
	_check("kb_pause_reaches_settings", ok, "focus=" + _cap(_focus()))
	await _key(KEY_ENTER)
	await _wait(0.6)
	_check("kb_pause_settings_opens", _find_settings() != null)
	await _shot("pause_settings_keyboard")
	await _key(KEY_ESCAPE)
	await _wait(0.5)
	_check("kb_settings_esc_back_to_pause", _find_settings() == null and UI.pause_menu.is_open() and _cap(_focus()) == "Settings",
		"pause_open=%s focus=%s" % [UI.pause_menu.is_open(), _cap(_focus())])
	await _key(KEY_ESCAPE)
	await _wait(0.5)
	_check("kb_esc_resumes", not UI.pause_menu.is_open() and not get_tree().paused)
	# Backspace also documented as menu back
	await _key(KEY_ESCAPE)
	await _wait(0.6)
	await _key(KEY_BACKSPACE)
	await _wait(0.5)
	_check("kb_backspace_resumes", not UI.pause_menu.is_open(), "pause_open=%s" % UI.pause_menu.is_open())
	if UI.pause_menu.is_open():
		await _key(KEY_ESCAPE)
		await _wait(0.5)
	# ---------------- NPC talk prompt on a pad
	var talkers: Array = []
	for nd in _all(get_tree().current_scene):
		if nd.get_script() and String((nd.get_script() as Script).resource_path).ends_with("talker.gd"):
			talkers.append("%s:'%s'" % [nd.name, String(nd.get("prompt_text"))])
	_info("hub_talker_prompts", str(talkers))
	# ---------------- Unknown world guard (pad dismiss)
	Router.enter_world("W9", "")
	await _wait(2.5)
	await _shot("unknown_world_page")
	await _pad_button(JOY_BUTTON_A)
	await _wait_router(30.0)
	await _wait(1.5)
	_check("unknown_world_returns_hub", _world_id() == "HUB", "scene=" + _scene_name())
	_check("unknown_world_unblocked", not get_tree().paused and not UI.is_input_blocked())
	await get_tree().process_frame




## Fresh process, no pad input before: does a pad-only dialog / book flip UI.last_device (prompt glyphs)?
func _seg_f() -> void:
	_info("f_start_last_device", UI.last_device)
	UI.show_dialog("Bramwell", ["First line of a test dialog.", "Second line."])
	await _wait(1.2)
	var presses := 0
	while UI.is_dialog_open() and presses < 8:
		await _pad_button(JOY_BUTTON_A)
		await _wait(0.4)
		presses += 1
	_check("f_dialog_closed_by_pad", not UI.is_dialog_open(), "presses=%d" % presses)
	_check("f_last_device_gamepad_after_pad_dialog", UI.last_device == "gamepad", "last_device=" + UI.last_device)
	UI.show_mission_select("W1")
	await _wait(1.6)
	await _pad_button(JOY_BUTTON_B)
	await _wait(1.0)
	_check("f_book_closed_by_pad_B", not UI.mission_select.visible)
	_check("f_last_device_gamepad_after_pad_book", UI.last_device == "gamepad", "last_device=" + UI.last_device)
	UI.show_mission_select("W1")
	await _wait(1.6)
	await _shot("f_book_footer_after_pad_only_input")
	await _pad_button(JOY_BUTTON_B)
	await _wait(1.0)

# ---------------------------------------------------------------- r2 helpers

func _pause_items() -> Array:
	var out: Array = []
	var bx := UI.pause_menu.get("_buttons") as Node
	if bx:
		for b in bx.get_children():
			if (b as Control).visible:
				out.append(_cap(b as Control))
	return out


func _pause_goal() -> String:
	var gl := UI.pause_menu.get("_goal_label") as Label
	return gl.text if gl and gl.visible else ""


func _pause_confirm_visible() -> bool:
	var c := UI.pause_menu.get("_confirm") as Control
	return c != null and c.visible


## Smallest visible UI text at this window size (effective pixels = authored size * window_h / 1080).
func _text_audit(where: String) -> void:
	var rows: Array = []
	for n in _all(get_tree().root):
		if not (n is Control) or not (n as Control).is_visible_in_tree():
			continue
		var txt := ""
		var fs := 0
		if n is Label:
			txt = (n as Label).text
			fs = (n as Label).get_theme_font_size("font_size")
			var ls := (n as Label).label_settings
			if ls:
				fs = ls.font_size
		elif n is Button:
			txt = (n as Button).text
			fs = (n as Button).get_theme_font_size("font_size")
		elif n is RichTextLabel:
			txt = (n as RichTextLabel).get_parsed_text()
			fs = (n as RichTextLabel).get_theme_font_size("normal_font_size")
		if txt.strip_edges() == "" or fs <= 0:
			continue
		if (n as Control).modulate.a < 0.05:
			continue
		rows.append([fs * _scale, txt.substr(0, 40).replace("\n", " ")])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var top: Array = []
	for i in mini(5, rows.size()):
		top.append("%.1fpx '%s'" % [rows[i][0], rows[i][1]])
	print("[Crit] TEXT %s %s" % [where, str(top)])


func _visible_texts(max_n: int) -> String:
	var out: Array = []
	for n in _all(get_tree().root):
		if out.size() >= max_n:
			break
		if n is Label and (n as Label).is_visible_in_tree() and (n as Label).text.strip_edges() != "":
			out.append((n as Label).text.substr(0, 50).replace("\n", " "))
		elif n is Label3D and (n as Label3D).is_visible_in_tree() and (n as Label3D).text.strip_edges() != "":
			out.append("3D:" + (n as Label3D).text.substr(0, 30).replace("\n", " "))
	return str(out)


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	await _send(e)
	var u := e.duplicate() as InputEventKey
	u.pressed = false
	await _send(u)
	await _wait(0.12)


func _key_nav_to(caption: String, k: Key, max_steps: int) -> bool:
	if _cap(_focus()) == caption:
		return true
	for i in max_steps:
		await _key(k)
		if _cap(_focus()) == caption:
			return true
	return false


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
	return "%s(%s)<%s>" % [c.get_class(), _cap(c), c.get_parent().name if c.get_parent() else ""]


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
	var p := "%s/%s__%s%02d_%s.png" % [out_dir, tag, _seg, _step, caption]
	if img:
		img.save_png(p)
	print("[Crit] SHOT ", p)

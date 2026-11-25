extends Node
## UI showcase driver used for native captures and the save round trip (core workstream only).
##   --screen=hud|dialog|banner|truffle|pause|mission|settings|unwritten|page|timer|transition|damage
##   --roundtrip=write|verify   save/load round trip on the --profile save (prints PASS/FAIL)

static var _done_once := false

var _frame := 0
var screen := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	screen = dev.arg("ui-screen", dev.arg("screen", "hud")) if dev else "hud"
	var rt: String = dev.arg("roundtrip", "") if dev else ""
	if rt != "":
		screen = "none"
		_roundtrip(rt)
	if dev and dev.has_arg("selftest"):
		screen = "none"
		run_selftest.call_deferred()


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 20 and not _done_once:
		_done_once = true
		_setup()
	if _frame == 50 and screen == "damage":
		Game.damage(1)
	if _frame == 70 and screen == "hud":
		Game.add_acorns(1)
		Game.collect_page("W1", 4)


func _setup() -> void:
	print("[Showcase] screen=", screen)
	match screen:
		"none":
			pass
		"hud", "page", "timer", "damage":
			Game.collect_page("W1", 0)
			Game.collect_page("W1", 2)
			Game.collect_page("W1", 3)
			Game.add_acorns(37)
			Game.damage(2)
			if screen == "timer":
				UI.timer_start("Rooftop Relay", 6.5)
			elif screen != "page":
				UI.timer_start("Rooftop Relay", 0.0)
		"dialog_mak":
			Game.unlock("top_hat")
			Game.set_hat("top_hat")
			UI.show_dialog("Mr. Mak", ["Jolly good. Now, about those truffles, I shall need my best hat."])
		"dialog":
			UI.show_dialog("Bramwell", ["Good heavens, Master Mak! The Wolf has huffed every Golden Truffle clean out of the library.", "Do mind the bellows machines in the Hollow, sir. They blow rather hard."])
		"banner":
			UI.show_banner("Top of the Windmill", "Huff & Puff Hollow", 8.0)
			UI.toast("Bookmark saved")
		"banner_long":
			# critique UI r1: the longest mission names must clear the HUD plaques
			UI.set_hud_visible(true)
			UI.show_banner("Lost Pages of the Hollow", "Find all five Lost Pages in the Hollow", 30.0)
		"narrator":
			UI.show_dialog("", ["This book is locked tight. Find more Golden Truffles to loosen its clasp."])
		"bark":
			var who: Node3D = null
			var pl := get_tree().get_nodes_in_group("player")
			if not pl.is_empty():
				who = pl[0] as Node3D
			if who:
				UI.bark(who, "Twelve truffles, piglet, and my door is yours. Ta-ta.", 60.0, {"speaker": "The Wolf", "height": 1.7})
		"pad_capture":
			var s2 := (load("res://scenes/ui/SettingsMenu.tscn") as PackedScene).instantiate()
			UI.pause_menu.get_parent().add_child(s2)
			s2.open()
			var pads2 := s2.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return "action" in b and "waiting" in b)
			if not pads2.is_empty():
				var pb: Button = pads2[0]
				pb.grab_focus.call_deferred()
				pb.pressed.emit.call_deferred()
		"pause_confirm":
			UI.open_pause()
			var pm: Node = UI.pause_menu
			get_tree().create_timer(0.6, true).timeout.connect(func() -> void: pm._ask("Close this book?", "Your truffles and pages stay found.", "Return to library", Callable()))
		"pause_banner":
			UI.show_banner("Straw House Siege", "Knock down the straw house walls", 8.0)
			get_tree().create_timer(0.5, true).timeout.connect(func() -> void: UI.open_pause())
		"truffle":
			Game.collect_truffle("W1-2")
		"pause":
			Game.unlock("top_hat")
			UI.open_pause()
		"mission":
			var tdict: Dictionary = Game.data.get("truffles", {})
			for tid in ["W1-1", "W1-4", "W2-2", "W3-1", "W3-6"]:
				tdict[tid] = {"utc": "showcase"}
			Game.data["truffles"] = tdict
			get_tree().paused = false
			var dv := get_node_or_null("/root/Dev")
			UI.show_mission_select(dv.arg("ui-world", "W1") if dv else "W1")
		"settings":
			var s := (load("res://scenes/ui/SettingsMenu.tscn") as PackedScene).instantiate()
			UI.pause_menu.get_parent().add_child(s)
			s.open()
			var dvs := get_node_or_null("/root/Dev")
			if dvs and dvs.arg("ui-focus", "") == "pad":
				var pads := s.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return "action" in b and "waiting" in b)
				if not pads.is_empty():
					(pads[0] as Control).grab_focus.call_deferred()
		"boss":
			var bb: StorybookBossBar = UI.boss_bar()
			bb.show_bar("Sir Reginald Huffington III", 9)
			bb.set_phase_title("Act II: The Puff")
			get_tree().create_timer(1.2).timeout.connect(func() -> void: bb.set_remaining(6))
		"prompt":
			UI.show_prompt("interact", "Talk to Bramwell")
		"hats":
			Game.unlock("top_hat")
			UI.open_pause()
		"unwritten":
			Router.enter_world("W3", "W3-1")
		"transition":
			Router.reload_at_checkpoint()


func _roundtrip(mode: String) -> void:
	if mode == "write":
		Game.new_game()
		Game.collect_truffle("W1-1")
		Game.collect_truffle("W2-4")
		Game.collect_page("W1", 1)
		Game.unlock("top_hat")
		Game.set_hat("top_hat")
		Game.record_time("W1-7", 42.5)
		Game.set_setting("music_volume", 0.35)
		Game.rebind_key("jump", KEY_K)
		var ok := Game.save_game()
		print("[RoundTrip] write ok=%s path=%s" % [ok, ProjectSettings.globalize_path(Game.save_path())])
	elif mode == "verify":
		var checks := {
			"truffles": Game.truffle_count() == 2 and Game.has_truffle("W1-1") and Game.has_truffle("W2-4"),
			"page": Game.has_page("W1", 1) and Game.page_count("W1") == 1,
			"top_hat": Game.is_unlocked("top_hat") and Game.get_hat() == "top_hat",
			"best_time": absf(Game.best_time("W1-7") - 42.5) < 0.001,
			"music_volume": absf(float(Game.get_setting("music_volume")) - 0.35) < 0.001,
			"rebind": Game.primary_key("jump") == KEY_K,
			"status": Game.last_load_status(),
		}
		var all_ok := true
		for k in checks:
			if k != "status" and not checks[k]:
				all_ok = false
		print("[RoundTrip] verify %s %s" % ["PASS" if all_ok else "FAIL", checks])
	elif mode == "status":
		print("[RoundTrip] status=%s truffles=%d" % [Game.last_load_status(), Game.truffle_count()])


# ---------------------------------------------------------------- scripted interaction self-test
# --selftest : drives the UI with synthetic InputEventAction events and prints PASS/FAIL lines.

var _results: Array = []


func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append([name, ok])
	print("[SelfTest] %s %s %s" % ["PASS" if ok else "FAIL", name, detail])


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
	await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func run_selftest() -> void:
	screen = "none"
	await _wait(1.0)
	var world := get_tree().current_scene
	# HUD mirrors Game
	Game.add_acorns(5)
	Game.health = 3
	await _wait(0.1)
	_check("hud_values", UI.hud.acorns == Game.acorns and UI.hud.health == 3, "acorns=%d health=%d" % [UI.hud.acorns, UI.hud.health])
	Game.add_acorns(2)
	_check("acorns_restore_slices", Game.health == 5, "health=%d" % Game.health)
	# Pause
	await _press("pause")
	_check("pause_opens", UI.pause_menu.is_open() and get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	_check("input_blocked_in_pause", UI.is_input_blocked())
	await _press("pause")
	await _wait(0.35)
	_check("pause_resumes", not UI.pause_menu.is_open() and not get_tree().paused)
	# Pause -> Resume button via ui_accept on the focused first button
	await _press("pause")
	await _wait(0.5)
	await _press("ui_accept")
	await _wait(0.35)
	_check("resume_button", not UI.pause_menu.is_open() and not get_tree().paused)
	# Wardrobe: the top hat stays locked until won, then can be worn from the pause menu
	Game.set_hat("beanie")
	await _press("pause")
	await _wait(0.5)
	await _press("ui_right")
	await _press("ui_right")
	var hf := get_viewport().gui_get_focus_owner()
	await _press("ui_accept")
	var locked_ok := Game.get_hat() == "beanie" if not Game.is_unlocked("top_hat") else true
	_check("wardrobe_locked_top_hat", locked_ok, "hat=%s focus=%s" % [Game.get_hat(), hf])
	Game.unlock("top_hat")
	UI.pause_menu._refresh()
	await _press("ui_accept")
	_check("wardrobe_wear_top_hat", Game.get_hat() == "top_hat", "hat=%s" % Game.get_hat())
	await _press("ui_left")
	await _press("ui_accept")
	_check("wardrobe_back_to_beanie", Game.get_hat() == "beanie", "hat=%s" % Game.get_hat())
	await _press("pause")
	await _wait(0.35)
	_check("wardrobe_closes", not UI.pause_menu.is_open() and not get_tree().paused)
	# Jingle plays on its own bus and only the Music bus ducks (night-01 audio bug)
	var mi := AudioServer.get_bus_index("Music")
	var ji := AudioServer.get_bus_index("Jingle")
	var music_before := AudioServer.get_bus_volume_db(mi)
	var jingle_before := AudioServer.get_bus_volume_db(ji) if ji >= 0 else 0.0
	Audio.play_jingle("truffle_get")
	await _wait(0.5)
	var jp: AudioStreamPlayer = Audio._jingle
	_check("jingle_own_bus", ji >= 0 and jp.bus == "Jingle" and jp.playing, "bus=%s playing=%s" % [jp.bus, jp.playing])
	_check("jingle_ducks_music_only", AudioServer.get_bus_volume_db(mi) < music_before - 10.0 and absf(AudioServer.get_bus_volume_db(ji) - jingle_before) < 0.01, "music %.1f->%.1f jingle %.1f->%.1f" % [music_before, AudioServer.get_bus_volume_db(mi), jingle_before, AudioServer.get_bus_volume_db(ji)])
	# Device detection for button prompts
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	jb.pressed = true
	Input.parse_input_event(jb)
	await get_tree().process_frame
	var pad_glyph := UIPrompts.glyph_for("jump")
	var kb := InputEventKey.new()
	kb.physical_keycode = KEY_F9
	kb.pressed = true
	Input.parse_input_event(kb)
	await get_tree().process_frame
	var key_glyph := UIPrompts.glyph_for("jump")
	_check("prompt_glyphs_follow_device", String(pad_glyph["label"]) == "A" and String(key_glyph["kind"]) == "key", "pad=%s key=%s" % [pad_glyph, key_glyph])
	# Controller rebinding round trip
	Game.rebind_pad("jump", JOY_BUTTON_B)
	var pb_ok: bool = Game.primary_pad_button("jump") == JOY_BUTTON_B and UIPrompts.glyph_for("jump", "gamepad")["label"] == "B"
	Game.reset_bindings()
	_check("pad_rebind", pb_ok and Game.primary_pad_button("jump") == JOY_BUTTON_A, "after reset=%d" % Game.primary_pad_button("jump"))
	# Boss bar API
	var bb: StorybookBossBar = UI.boss_bar()
	bb.show_bar("Test Wolf", 3)
	bb.set_remaining(2)
	_check("boss_bar_api", bb.visible and bb._ctl.remaining == 2.0)
	bb.hide_bar()
	# Dialog: interact and jump advance; finished signal fires
	var done := [false]
	UI.dialog_finished.connect(func() -> void: done[0] = true, CONNECT_ONE_SHOT)
	UI.show_dialog("Bramwell", ["Line one.", "Line two is a little longer."])
	await _wait(0.3)
	_check("dialog_blocks_input", UI.is_input_blocked())
	await _press("interact")  # completes typing or advances
	await _wait(0.6)
	await _press("interact")
	await _wait(0.8)
	await _press("jump")
	await _wait(0.2)
	if UI.is_dialog_open():
		await _press("jump")
		await _wait(0.2)
	_check("dialog_finishes", done[0] and not UI.is_dialog_open())
	# Mission select: opens paused, cancel closes and unpauses
	UI.show_mission_select("W1")
	await _wait(1.6)
	var focused := get_viewport().gui_get_focus_owner()
	_check("mission_select_opens", UI.mission_select.visible and get_tree().paused and focused != null, "focus=%s" % (focused.get("caption") if focused else "none"))
	await _press("ui_down")
	var f2 := get_viewport().gui_get_focus_owner()
	_check("mission_select_navigates", f2 != null and f2 != focused, "focus=%s" % (f2.get("caption") if f2 else "none"))
	await _press("ui_cancel")
	await _wait(0.8)
	_check("mission_select_cancel", not UI.mission_select.visible and not get_tree().paused)
	# Truffle celebration freezes then resumes play
	Game.collect_truffle("W1-3")
	await _wait(0.5)
	_check("truffle_freeze", get_tree().paused and UI.announcer.is_splashing())
	await _wait(3.2)
	_check("truffle_resume", not get_tree().paused and not UI.announcer.is_splashing())
	# Cake empty -> respawn with a full cake
	var p: Node3D = world.player
	p.global_position = Vector3(12, 1, 12)
	Game.damage(10)
	await _wait(1.4)
	_check("cake_empty_respawn", Game.health == Game.max_health and p.global_position.distance_to(world.spawn_transform().origin) < 1.5, "pos=%s" % p.global_position)
	# Fall below kill_y -> respawn at checkpoint bookmark
	var cp := Transform3D(Basis(), Vector3(-5, 0.2, 2))
	Game.set_checkpoint(world.world_id, cp)
	p.global_position = Vector3(0, world.kill_y - 5.0, 0)
	await _wait(0.4)
	_check("kill_y_respawn_at_checkpoint", p.global_position.distance_to(cp.origin) < 1.5, "pos=%s" % p.global_position)
	# Timer API
	UI.timer_start("Test", 0.0)
	await _wait(0.5)
	var tv := UI.timer_stop()
	_check("timer_counts", tv > 0.3 and tv < 1.5, "t=%.2f" % tv)
	UI.timer_hide()
	# Audio never crashes on missing keys
	Audio.play_sfx("definitely_missing_key", Vector3.ZERO)
	Audio.play_music("also_missing")
	_check("audio_missing_keys_no_crash", true, "reached after missing-key calls")
	var fails := 0
	for r in _results:
		if not r[1]:
			fails += 1
	print("[SelfTest] DONE %d checks, %d failed" % [_results.size(), fails])
	get_tree().quit()

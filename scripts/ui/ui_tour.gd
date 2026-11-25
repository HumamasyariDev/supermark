extends Node
## UI evidence tour: one game run, many native captures (each world load costs 4-5 GB, so the UI
## track captures all of its screens in a single run instead of one process per screen).
##   python tools/godot.py run res://scenes/worlds/w1/W1.tscn --seconds 120 -- --profile=ui --ui-tour=<abs dir> [--ui-tour-only=a,b] [--ui-tour-tag=after]
## Saves <dir>/<UTC>__<tag>_<step>.png for each step, prints "[UITour] saved ..." and quits.

var _dir := ""
var _tag := "after"
var _only: PackedStringArray = []
var _stamp := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	_dir = String(dev.arg("ui-tour", "")) if dev else ""
	_tag = String(dev.arg("ui-tour-tag", "after")) if dev else "after"
	var only := String(dev.arg("ui-tour-only", "")) if dev else ""
	if only != "":
		_only = only.split(",")
	_stamp = Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "").replace("T", "T") + "Z"
	DirAccess.make_dir_recursive_absolute(_dir)
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_args().has("--write-movie") and String(dev.arg("ui-tour-size", "")) != "keep":
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(step: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join("%s__%s_%s.png" % [_stamp, _tag, step])
	img.save_png(path)
	print("[UITour] saved ", path, " ", img.get_size())


func _want(step: String) -> bool:
	return _only.is_empty() or _only.has(step)


func _reset() -> void:
	var ui := get_node_or_null("/root/UI")
	if ui.pause_menu.is_open():
		ui.pause_menu._close_silently()
	if ui.dialog.is_open():
		ui.dialog.close()
	if ui.mission_select.visible:
		ui.mission_select.visible = false
	for m in get_tree().get_nodes_in_group("ui_modal"):
		m.queue_free()
	ui.clear_barks()
	ui.announcer.clear_transient()
	ui.hide_prompt()
	var bb: StorybookBossBar = ui._boss_bar
	if bb and is_instance_valid(bb):
		bb.hide_bar()
	get_tree().paused = false
	await _secs(0.6)


func _run_title(title: Node) -> void:
	# press screen, then the menu, the dolly at its widest swing (about 12-14 s), and the Quit confirm
	await _secs(2.5)
	await _shot("title_press")
	title._show_menu()
	await _secs(1.5)
	await _shot("title_menu")
	while title.get("_t") < 12.8:
		await _frames(1)
	await _shot("title_dolly_12s8")
	while title.get("_t") < 14.5:
		await _frames(1)
	await _shot("title_dolly_14s5")
	title._show_confirm("quit")
	await _secs(0.8)
	await _shot("title_quit_confirm")
	print("[UITour] done")
	get_tree().quit()


func _run() -> void:
	await _frames(3)
	var scene := get_tree().current_scene
	if scene and scene.has_method("_show_confirm"):
		await _run_title(scene)
		return
	if _want("entry"):
		# the world's own entry banner (hub: "The Grand Library" + first-visit nudge)
		await _secs(2.2)
		await _shot("entry_banner")
		await _secs(2.6)
	else:
		await _secs(4.0)  # world settles, entry banner passes
	var ui := get_node_or_null("/root/UI")
	ui.set_hud_visible(true)
	await _secs(3.0)
	if _want("hud"):
		Game.add_acorns(37)
		Game.damage(2)
		await _secs(1.6)
		await _shot("hud")
	if _want("objective"):
		ui.set_objective("Catch the sheep to win back the bookmark")
		await _secs(1.0)
		await _shot("hud_objective")
		ui.clear_objective()
	if _want("banner_long"):
		ui.show_banner(WorldRegistry.truffle_name("W1-5"), WorldRegistry.truffle_goal("W1-5"), 30.0)
		await _secs(1.2)
		print("[UITour] banner ", ui.announcer.dbg_banner)
		await _shot("banner_long")
		await _reset()
	if _want("truffle"):
		var ids := WorldRegistry.truffle_ids("W1")
		var tid := ""
		for id in ids:
			if not Game.has_truffle(id):
				tid = id
				break
		if tid != "":
			Game.collect_truffle(tid)
			# the splash runs on scaled time (Juice hit-stop slows it), so wait on the announcer, not the clock
			var ann: Node = ui.announcer
			while ann.is_splashing() and ann.get("_splash_t") < 1.1:
				await _frames(1)
			await _shot("truffle_splash")
			while ann.is_splashing() and ann.get("_splash_t") < 2.62:
				await _frames(1)
			await _shot("truffle_fly")
			while ann.is_splashing():
				await _frames(1)
			await _frames(4)
			await _shot("truffle_landed")
		await _reset()
	if _want("pause_banner"):
		ui.show_banner("Straw House Siege", "Knock down the straw house walls", 8.0)
		await _secs(0.8)
		ui.open_pause()
		await _secs(0.9)
		await _shot("pause_banner_hidden_goal")
		if _want("pause_confirm"):
			ui.pause_menu._ask("Close this book?", "Your truffles and pages stay found.", "Return to library", Callable())
			await _secs(0.7)
			await _shot("pause_confirm")
		await _reset()
	if _want("hats"):
		ui.open_pause()
		await _secs(1.2)
		await _shot("pause_wardrobe")
		await _reset()
	if _want("settings"):
		var s := (load("res://scenes/ui/SettingsMenu.tscn") as PackedScene).instantiate()
		ui.pause_menu.get_parent().add_child(s)
		s.open()
		await _secs(0.8)
		await _shot("settings_top")
		var vs := s.find_children("*", "CheckButton", true, false)
		for c in vs:
			if (c as CheckButton).button_pressed:
				(c as Control).grab_focus()
				break
		await _secs(0.6)
		await _shot("settings_toggle_on")
		var pads := s.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return "action" in b and "waiting" in b)
		if not pads.is_empty():
			(pads[0] as Control).grab_focus()
			await _secs(0.4)
			(pads[0] as Button).pressed.emit()
			await _secs(1.5)
			await _shot("settings_pad_capture")
			s._waiting_pad = null
			pads[0].waiting = false
			(pads.back() as Control).grab_focus()
			await _secs(0.6)
			await _shot("settings_pause_fixed")
		await _reset()
	if _want("dialog"):
		UI.show_dialog("Bramwell", ["Good heavens, Master Mak! The Wolf has huffed every Golden Truffle clean out of the library."])
		await _secs(2.5)
		await _shot("dialog_ribbon_plate")
		await _reset()
	if _want("narrator"):
		UI.show_dialog("", ["This book is locked tight. Find more Golden Truffles to loosen its clasp."])
		await _secs(2.5)
		var pnl: Control = ui.dialog._panel
		print("[UITour] narrator panel rect=", pnl.get_global_rect(), " vis=", pnl.is_visible_in_tree(), " mod=", pnl.modulate, " scale=", pnl.scale, " mat_size=", (pnl.material as ShaderMaterial).get_shader_parameter("size") if pnl.material else null)
		await _shot("dialog_narrator")
		await _reset()
	if _want("bark"):
		var pl := get_tree().get_nodes_in_group("player")
		if not pl.is_empty():
			ui.bark(pl[0], "Twelve truffles, piglet, and my door is yours. Ta-ta.", 30.0, {"speaker": "The Wolf", "height": 1.7})
			await _secs(1.0)
			var cam := get_viewport().get_camera_3d()
			print("[UITour] bark cam=", cam.get_path() if cam else null, " sp=", cam.unproject_position((pl[0] as Node3D).global_position) if cam else null, " barks size=", ui.barks.size, " vp=", get_viewport().get_visible_rect().size)
			await _shot("bark_pill")
		await _reset()
	if _want("boss"):
		var bb: StorybookBossBar = ui.boss_bar()
		ui.timer_start("", 45.0)
		bb.show_bar("Sir Reginald Huffington III", 9)
		bb.set_phase_title("II. The Puff")
		await _secs(1.5)
		await _shot("boss_bar_voice")
		ui.timer_hide()
		await _reset()
	if _want("timer"):
		ui.timer_start("Cloud Hopper", 32.0)
		await _secs(1.2)
		await _shot("timer_plain")
		ui.timer_hide()
		await _reset()
	if _want("mission"):
		ui.show_mission_select("W1")
		for f in [0.35, 0.55, 0.75, 0.95]:
			await _secs(f - (0.0 if f == 0.35 else 0.2))
			await _shot("mission_open_%03d" % int(f * 100))
		await _secs(1.6)
		await _shot("mission_select")
		await _reset()
	print("[UITour] done")
	get_tree().quit()

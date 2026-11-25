extends Node
## UI autoload ("UI"): HUD, dialog, banners, toasts, the TRUFFLE GET! splash, pause menu and
## mission select. Gameplay code should check UI.is_input_blocked() before reading actions.
##
##   UI.show_dialog(speaker, lines) -> emits dialog_finished; lines are Strings or
##        {"speaker": "...", "text": "...", "voice": "<audio key>"}; also awaitable: await UI.dialog_finished
##   UI.show_banner(title, subtitle), UI.toast(text), UI.truffle_get(truffle_id)
##   UI.set_hud_visible(on), UI.timer_start(label, countdown), UI.timer_stop() -> float, UI.timer_hide()
##   UI.show_page_popup(world_id, count), UI.show_mission_select(world_id), UI.open_pause()
##   UI.show_prompt(action, text) / UI.hide_prompt()   contextual button prompt (keyboard or pad glyph)
##   UI.boss_bar() -> StorybookBossBar (show_bar, set_phase_title, set_remaining, hide_bar)
##   UI.last_device ("keyboard" | "gamepad"), signal device_changed(device); UI.note_device(event)
##   UI.bark(node3d, text, seconds, {"height", "speaker"}) / UI.clear_barks(node)   styled world speech bubbles
##   UI.set_objective(text) / UI.clear_objective()   one persistent objective line under the HUD counters
##   UI.is_title_active()   true while the title screen owns the frame (HUD, banners, toasts, barks are held)
## Dev: --ui-screen=<hud|dialog|banner|truffle|pause|mission|settings|boss|prompt|timer|damage> runs the
## showcase over ANY scene (for example a real world); --ui-device=gamepad forces pad glyphs.

signal dialog_finished
signal truffle_splash_finished
signal timer_expired
signal pause_changed(paused: bool)
signal device_changed(device: String)

const HUD_SCENE := "res://scenes/ui/HUD.tscn"
const DIALOG_SCENE := "res://scenes/ui/DialogBox.tscn"
const PAUSE_SCENE := "res://scenes/ui/PauseMenu.tscn"
const MISSION_SCENE := "res://scenes/ui/MissionSelect.tscn"
const ANNOUNCER_SCENE := "res://scenes/ui/Announcer.tscn"

var hud: Control
var dialog: Control
var pause_menu: Control
var mission_select: Control
var announcer: Control

var last_device := "keyboard"
var _boss_bar: StorybookBossBar
var barks: UIBarks
var _hud_layer: CanvasLayer
var _hud_wanted := false
var _gameplay := false
var _title_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	barks = UIBarks.new()
	barks.name = "Barks"
	_layer(8, "").add_child(barks)
	_hud_layer = _layer(10, "hud")
	hud = _inst(HUD_SCENE, _hud_layer)
	var ann_layer := _layer(30, "")
	announcer = _inst(ANNOUNCER_SCENE, ann_layer)
	var dlg_layer := _layer(20, "")
	dialog = _inst(DIALOG_SCENE, dlg_layer)
	var menu_layer := _layer(40, "")
	pause_menu = _inst(PAUSE_SCENE, menu_layer)
	mission_select = _inst(MISSION_SCENE, menu_layer)
	if dialog:
		dialog.finished.connect(func() -> void: dialog_finished.emit())
	if announcer:
		announcer.splash_finished.connect(func() -> void: truffle_splash_finished.emit())
	if hud:
		hud.timer_expired.connect(func() -> void: timer_expired.emit())
	if pause_menu:
		pause_menu.resumed.connect(func() -> void: pause_changed.emit(false))
	_hud_layer.visible = false
	# critique UI r1 re-run: dialogs, the book, pause and settings consume pad input before this autoload's _input,
	# so keyboard glyphs showed after pad-only play. The window's input signal sees every event first (read only).
	get_tree().root.window_input.connect(note_device)
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_method("arg"):
		if dev.arg("ui-device", "") != "":
			last_device = dev.arg("ui-device", "keyboard")
		elif Input.get_connected_joypads().size() > 0:
			last_device = "gamepad"
		if dev.has_arg("ui-demo"):
			var dm := Node.new()
			dm.set_script(load("res://scripts/ui/ui_demo.gd"))
			dm.name = "UIDemo"
			add_child(dm)
		if dev.arg("ui-tour", "") != "":
			var tour := Node.new()
			tour.set_script(load("res://scripts/ui/ui_tour.gd"))
			tour.name = "UITour"
			add_child(tour)
		if dev.arg("ui-screen", "") != "":
			var sc := Node.new()
			sc.set_script(load("res://scripts/ui/ui_showcase.gd"))
			sc.name = "UIShowcase"
			add_child(sc)


func _process(_delta: float) -> void:
	# The HUD steps aside while a menu or the book spread is open.
	var menu_open: bool = (pause_menu != null and pause_menu.is_open()) or (mission_select != null and mission_select.visible)
	if not menu_open:
		# critique UI r1: Settings over a world cut through the HUD plaques
		for m in get_tree().get_nodes_in_group("ui_modal"):
			if (m as CanvasItem).is_visible_in_tree():
				menu_open = true
				break
	var dev := get_node_or_null("/root/Dev")
	var hide_hud: bool = dev != null and dev.has_method("has_arg") and dev.has_arg("hide-hud")
	var want: bool = _hud_wanted and not hide_hud and not menu_open
	if _hud_layer.visible != want:
		_hud_layer.visible = want


func _layer(n: int, group: String) -> CanvasLayer:
	var l := CanvasLayer.new()
	l.layer = n
	if group != "":
		l.add_to_group(group)
	add_child(l)
	return l


func _inst(path: String, parent: Node) -> Control:
	if not ResourceLoader.exists(path):
		push_warning("[UI] missing " + path)
		return null
	var n := (load(path) as PackedScene).instantiate() as Control
	parent.add_child(n)
	return n


# ---------------------------------------------------------------- gameplay state

## The title screen holds this while it is the current scene. Its backdrop is the live hub, whose scripts
## may ask for the gameplay HUD, banners or toasts; none of those may draw over the logo (critique UI r1 blocker).
func set_title_active(on: bool) -> void:
	_title_active = on
	if on:
		_hud_wanted = false
		if _hud_layer:
			_hud_layer.visible = false
		if announcer and announcer.has_method("clear_transient"):
			announcer.clear_transient()
		clear_barks()


func is_title_active() -> bool:
	return _title_active


## WorldRoot calls this when a playable scene starts or ends.
func set_gameplay(on: bool) -> void:
	if _title_active and on:
		return
	_gameplay = on
	clear_objective()  # an objective belongs to one scene
	set_hud_visible(on)


func set_hud_visible(on: bool) -> void:
	if _title_active and on:
		return
	_hud_wanted = on
	var dev := get_node_or_null("/root/Dev")
	var hide_hud: bool = dev != null and dev.has_method("has_arg") and dev.has_arg("hide-hud")
	_hud_layer.visible = on and not hide_hud


## One persistent objective line under the HUD counters ("" clears it). For timed beats such as the
## library sheep chase: UI.set_objective("Catch the sheep to win back the bookmark").
func set_objective(text: String) -> void:
	if hud and hud.has_method("set_objective"):
		hud.set_objective(text)


func clear_objective() -> void:
	set_objective("")


func show_prompt(action: String, text: String) -> void:
	if hud:
		hud.show_prompt(action, text)


func hide_prompt() -> void:
	if hud:
		hud.show_prompt("", "")


func boss_bar() -> StorybookBossBar:
	if _boss_bar == null or not is_instance_valid(_boss_bar):
		_boss_bar = StorybookBossBar.new()
		_boss_bar.name = "BossBar"
		add_child(_boss_bar)
		_boss_bar.visible = false
	return _boss_bar


var _mouse_ms := -100000


func _input(event: InputEvent) -> void:
	note_device(event)
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 0.5:
		_mouse_ms = Time.get_ticks_msec()


## Finish pass (UI usability major: a resting cursor stole pause focus onto a hat card when the menu appeared under
## it): hover takes focus only while the mouse is really moving.
func mouse_active() -> bool:
	return Time.get_ticks_msec() - _mouse_ms < 500


## Track the last input device. Screens that consume input before the autoload sees it (the title)
## call this first (critique UI r1: the first pad press on the title left last_device on keyboard).
func note_device(event: InputEvent) -> void:
	var d := last_device
	if event is InputEventJoypadButton and event.pressed:
		d = "gamepad"
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		d = "gamepad"
	elif event is InputEventKey and event.pressed:
		d = "keyboard"
	elif event is InputEventMouseButton and event.pressed:
		d = "keyboard"
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_method("arg") and dev.arg("ui-device", "") != "":
		return
	if d != last_device:
		last_device = d
		device_changed.emit(d)


func is_input_blocked() -> bool:
	## True while a dialog, menu, splash or page turn owns the input.
	var router := get_node_or_null("/root/Router")
	if router and router.busy:
		return true
	if dialog and dialog.is_open():
		return true
	if pause_menu and pause_menu.is_open():
		return true
	if mission_select and mission_select.visible:
		return true
	if announcer and announcer.is_splashing():
		return true
	return false


# ---------------------------------------------------------------- dialog, banners, toasts

func show_dialog(speaker: String, lines: Array) -> void:
	if dialog == null:
		dialog_finished.emit.call_deferred()
		return
	dialog.open(speaker, lines)


func is_dialog_open() -> bool:
	return dialog != null and dialog.is_open()


func bark(node: Node3D, text: String, seconds: float = 3.0, opts: Dictionary = {}) -> void:
	if _title_active:
		return
	if barks:
		barks.bark(node, text, seconds, opts)


func clear_barks(node: Node3D = null) -> void:
	if barks:
		barks.clear(node)


func show_banner(title: String, subtitle: String = "", duration: float = 3.2) -> void:
	if _title_active:
		return
	if announcer:
		announcer.show_banner(title, subtitle, duration)


func toast(text: String) -> void:
	if _title_active:
		return
	if announcer:
		announcer.toast(text)
	UIFx.event("ui_toast", {"text": text})


func truffle_get(truffle_id: String = "", title: String = "TRUFFLE GET!", duration: float = 3.0) -> void:
	if announcer:
		announcer.truffle_splash(WorldRegistry.truffle_name(truffle_id) if truffle_id != "" else "", title, duration)


func show_page_popup(world_id: String, count: int) -> void:
	if hud:
		hud.show_page_popup(world_id, count)


# ---------------------------------------------------------------- timer

func timer_start(label: String = "", countdown: float = 0.0) -> void:
	if hud:
		hud.timer_start(label, countdown)


func timer_stop() -> float:
	return hud.timer_stop() if hud else 0.0


func timer_hide() -> void:
	if hud:
		hud.timer_hide()


func timer_value() -> float:
	return hud.timer_value if hud else 0.0


# ---------------------------------------------------------------- menus

func show_mission_select(world_id: String) -> void:
	if mission_select == null:
		return
	# critique UI r1 re-run: catching the sheep opened the book over Bramwell's reward dialog. The book waits
	# for the dialog (or the TRUFFLE GET splash) to finish, then opens.
	if (dialog and dialog.is_open()) or (announcer and announcer.is_splashing()):
		var first := _pending_book == ""
		_pending_book = world_id
		if first:
			_open_pending_book()
		return
	mission_select.open_book(world_id)


var _pending_book := ""


func _open_pending_book() -> void:
	while (dialog and dialog.is_open()) or (announcer and announcer.is_splashing()):
		await get_tree().process_frame
	await get_tree().create_timer(0.25, true, false, true).timeout
	var w := _pending_book
	_pending_book = ""
	if w == "" or (pause_menu and pause_menu.is_open()) or (mission_select and mission_select.visible):
		return
	var router := get_node_or_null("/root/Router")
	if router and router.busy:
		return
	mission_select.open_book(w)


func open_pause() -> void:
	if (dialog and dialog.is_open()) or (mission_select and mission_select.visible) or (announcer and announcer.is_splashing()):
		return
	if pause_menu and not pause_menu.is_open():
		pause_menu.open()
		pause_changed.emit(true)


## World exit gates (ExitGate, owner fix 2026-10-19): "Return to the Grand Library?" Yes / No over the paused world,
## the pause menu's own confirm card. Yes = the pause menu's "Return to library"; No / Cancel / Pause resumes play.
func ask_return_to_library() -> void:
	if pause_menu == null or not pause_menu.has_method("open_exit_confirm") or pause_menu.is_open():
		return
	if is_input_blocked() or _title_active:
		return
	pause_menu.open_exit_confirm()
	pause_changed.emit(true)


func _unhandled_input(event: InputEvent) -> void:
	if _gameplay and event.is_action_pressed("reset_checkpoint") and not event.is_echo():
		_reset_to_checkpoint()
		return
	if not _gameplay or not event.is_action_pressed("pause"):
		return
	var router := get_node_or_null("/root/Router")
	if router and router.busy:
		return
	if (dialog and dialog.is_open()) or (mission_select and mission_select.visible) or (announcer and announcer.is_splashing()):
		return
	get_viewport().set_input_as_handled()
	open_pause()


## Finish pass (UI usability major): "R" (reset_checkpoint) was bound but nothing handled it. It now puts Mak back
## at the last bookmark (or the area start), like a fall without the lost slice.
func _reset_to_checkpoint() -> void:
	var router := get_node_or_null("/root/Router")
	if (router and router.busy) or get_tree().paused or is_input_blocked():
		return
	if (dialog and dialog.is_open()) or (mission_select and mission_select.visible) or (announcer and announcer.is_splashing()):
		return
	var game := get_node_or_null("/root/Game")
	if game == null or not game.has_method("respawn_player"):
		return
	get_viewport().set_input_as_handled()
	game.call("respawn_player")
	toast("Back to the bookmark")


func _notification(what: int) -> void:
	# Pause automatically when the window loses focus during play (not during dev captures).
	# Exported builds only, so overnight agent runs on the shared desktop are never interrupted.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _gameplay and OS.has_feature("template"):
		var dev := get_node_or_null("/root/Dev")
		if dev and dev.has_method("is_test_run") and dev.is_test_run():
			return
		if dev and dev.has_method("has_arg") and dev.has_arg("no-autopause"):
			return
		var router := get_node_or_null("/root/Router")
		if router and router.busy:
			return
		if not is_input_blocked():
			open_pause()

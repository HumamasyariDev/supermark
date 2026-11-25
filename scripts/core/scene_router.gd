extends Node
## Router autoload: scene flow with a storybook page-turn transition and threaded loading.
##
## API (TECH_CONTRACT.md): go_to_hub(spawn), enter_world(world_id, mission_id), go_to_title(),
## reload_at_checkpoint(). Also open_book(world_id) for the hub's mission-select spread.
## Missing scenes never crash: a "this chapter is still being written" page appears instead.

signal transition_started(target: String)
signal scene_ready(world_id: String)
signal transition_finished

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const PAGE_SHADER := "res://scenes/ui/shaders/page_turn.gdshader"
const TURN_OUT := 0.85
const TURN_IN := 0.95
const MIN_PAGE_TIME := 0.55

var busy := false
var pending_spawn := ""
var pending_use_checkpoint := false
var current_target := ""

var _layer: CanvasLayer
var _back: ColorRect
var _curl: ColorRect
var _title: Label
var _subtitle: Label
var _note: Label
var _spinner: Control
var _waiting_key := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var shader := load(PAGE_SHADER) as Shader
	_back = ColorRect.new()
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_back.mouse_filter = Control.MOUSE_FILTER_STOP
	var bm := ShaderMaterial.new()
	bm.shader = shader
	bm.set_shader_parameter("progress", 0.0)
	bm.set_shader_parameter("use_tex", false)
	var grain := UIStyle.parchment_texture()
	if grain:
		bm.set_shader_parameter("grain_tex", grain)
		bm.set_shader_parameter("use_grain", true)
	_back.material = bm
	_layer.add_child(_back)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	_back.add_child(box)
	_subtitle = UIStyle.label("", 34, UIStyle.INK_SOFT)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title = UIStyle.label("", 92, UIStyle.RIBBON, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note = UIStyle.label("", 30, UIStyle.INK)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_subtitle)
	box.add_child(_title)
	_spinner = _Spinner.new()
	_spinner.custom_minimum_size = Vector2(0, 90)
	box.add_child(_spinner)
	box.add_child(_note)
	_curl = ColorRect.new()
	_curl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cm := ShaderMaterial.new()
	cm.shader = shader
	if grain:
		cm.set_shader_parameter("grain_tex", grain)
		cm.set_shader_parameter("use_grain", true)
	_curl.material = cm
	_layer.add_child(_curl)
	_back.visible = false
	_curl.visible = false


class _Spinner:
	extends Control
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		for i in 3:
			var ph := t * 4.0 - i * 0.7
			var y := -absf(sin(ph)) * 22.0
			UIDraw.truffle(self, c + Vector2((i - 1) * 64, y), 20.0, true, t + i)


# ---------------------------------------------------------------- public API

func go_to_hub(spawn: String = "") -> void:
	var g := _game()
	if g:
		g.end_visit()
		g.begin_visit("HUB", "")
		g.save_game()
	pending_spawn = spawn
	pending_use_checkpoint = false
	_go("HUB")


func enter_world(world_id: String, mission_id: String = "") -> void:
	if not WorldRegistry.has_world(world_id):
		push_warning("[Router] unknown world " + world_id)
		_show_unwritten_then(world_id)
		return
	var g := _game()
	if g:
		g.begin_visit(world_id, mission_id)
		g.save_game()
	pending_spawn = mission_id
	pending_use_checkpoint = false
	_go(world_id)


func go_to_title() -> void:
	var g := _game()
	if g:
		if g.current_world != "":
			g.save_game()
		g.end_visit()
		g.current_world = ""
	pending_spawn = ""
	_transition(TITLE_SCENE, "SUPER MAK 64", "Closing the book", "")


func reload_at_checkpoint() -> void:
	var g := _game()
	var world_id: String = g.current_world if g else ""
	if world_id == "" or not WorldRegistry.has_world(world_id):
		go_to_title()
		return
	pending_use_checkpoint = true
	pending_spawn = g.current_mission if g else ""
	if g:
		g.full_heal()
	# Reload the scene that is actually running (a world may be loaded directly, e.g. a test arena).
	var path := WorldRegistry.scene_path(world_id)
	var cur := get_tree().current_scene
	if cur and cur.scene_file_path != "" and "world_id" in cur and String(cur.get("world_id")) == world_id:
		path = cur.scene_file_path
	_transition(path, WorldRegistry.display_name(world_id), "Back to the bookmark", world_id)


## Hub books call this: shows the two-page mission spread; choosing a truffle enters the world.
func open_book(world_id: String) -> void:
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("show_mission_select"):
		ui.show_mission_select(world_id)
	else:
		enter_world(world_id, "")


func consume_spawn() -> String:
	var s := pending_spawn
	pending_spawn = ""
	return s


func consume_checkpoint_flag() -> bool:
	var f := pending_use_checkpoint
	pending_use_checkpoint = false
	return f


func is_transitioning() -> bool:
	return busy


# ---------------------------------------------------------------- internals

func _game() -> Node:
	return get_node_or_null("/root/Game")


func _go(world_id: String) -> void:
	var path := WorldRegistry.scene_path(world_id)
	var sub := WorldRegistry.book_title(world_id)
	if world_id == "HUB":
		sub = "Mak Manor"
	var mission := ""
	var g := _game()
	if g and g.current_mission != "":
		mission = WorldRegistry.truffle_name(g.current_mission)
	_transition(path, WorldRegistry.display_name(world_id) if world_id != "HUB" else "The Grand Library", sub, world_id, mission)


func _show_unwritten_then(world_id: String) -> void:
	_transition("", WorldRegistry.display_name(world_id), WorldRegistry.book_title(world_id), world_id)


func _snapshot() -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _turn(rect: ColorRect, from: float, to: float, dur: float) -> void:
	var m := rect.material as ShaderMaterial
	m.set_shader_parameter("aspect", maxf(1.0, rect.size.x) / maxf(1.0, rect.size.y))
	m.set_shader_parameter("progress", from)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("progress", v), from, to, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func _transition(path: String, title: String, subtitle: String, world_id: String, note: String = "") -> void:
	if busy:
		push_warning("[Router] transition already running; ignored " + path)
		return
	busy = true
	current_target = world_id
	transition_started.emit(world_id)
	var headless := DisplayServer.get_name() == "headless"
	_title.text = title
	_subtitle.text = subtitle
	_note.text = note
	_spinner.visible = true
	# 1. Snapshot the current frame and curl it away to reveal the chapter page.
	var snap: Texture2D = await _snapshot()
	(_back.material as ShaderMaterial).set_shader_parameter("aspect", maxf(1.0, _back.size.x) / maxf(1.0, _back.size.y))
	_back.visible = true
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.play_ui("ui_page_turn")
	if snap and not headless:
		var cm := _curl.material as ShaderMaterial
		cm.set_shader_parameter("page_tex", snap)
		cm.set_shader_parameter("use_tex", true)
		_curl.visible = true
		await _turn(_curl, 0.0, 1.0, TURN_OUT)
		_curl.visible = false
	get_tree().paused = true
	var page_time := 0.0
	# Round 4 (web): a device that kept missing the frame budget moves to the Light level before the next area is built.
	var g0 := _game()
	var lightened: bool = OS.has_feature("web") and g0 != null and bool(g0.call("settle_graphics"))
	if OS.has_feature("web") and audio and audio.has_method("release_effect_samples"):
		audio.release_effect_samples()
	# 2. Load (threaded) or show the unwritten-chapter page.
	if OS.has_feature("web"):
		WebRuntime.loading("Opening " + title + "...")
		await get_tree().process_frame
	var packed: PackedScene = null
	if path != "" and ResourceLoader.exists(path):
		var load_t := WebRuntime.trace_start()
		packed = await _load_threaded(path)
		WebRuntime.trace_end("resource_load:" + world_id, load_t)
	if packed == null:
		packed = await _unwritten_page(world_id, path)
	while page_time < MIN_PAGE_TIME:
		await get_tree().process_frame
		page_time += get_process_delta_time()
	# 3. Swap the scene behind the page.
	if OS.has_feature("web"):
		_drop_area_caches()
	get_tree().paused = false
	var scene_t := WebRuntime.trace_start()
	var err := get_tree().change_scene_to_packed(packed)
	WebRuntime.trace_end("scene_instantiate:" + world_id, scene_t)
	if err != OK:
		push_error("[Router] change_scene failed (%s) for %s" % [error_string(err), path])
	await get_tree().process_frame
	WebRuntime.trace_end("scene_add_ready:" + world_id, scene_t)
	await get_tree().process_frame
	if OS.has_feature("web"):
		get_tree().paused = true
		await WebRuntime.warm_scene(get_tree().current_scene)
		get_tree().paused = false
	scene_ready.emit(world_id)
	# 4. Curl the chapter page away to reveal the new scene.
	var page_snap: Texture2D = await _snapshot()
	var cm2 := _curl.material as ShaderMaterial
	if page_snap:
		cm2.set_shader_parameter("page_tex", page_snap)
		cm2.set_shader_parameter("use_tex", true)
	else:
		cm2.set_shader_parameter("use_tex", false)
	_curl.visible = true
	_back.visible = false
	if audio:
		audio.play_ui("ui_page_turn")
	await _turn(_curl, 0.0, 1.0, TURN_IN)
	_curl.visible = false
	busy = false
	if OS.has_feature("web"):
		WebRuntime.loaded()
	transition_finished.emit()
	if lightened:
		var ui_l := get_node_or_null("/root/UI")
		if ui_l and ui_l.has_method("toast"):
			ui_l.toast("Light graphics on for smoother play (Settings > Display)")
	_guard_broken_world(world_id)


## Round 4 (web): the enemy material caches outlive their area and keep its 2048 px fleece, pod and jelly textures
## (12 MB each) in video memory for the rest of the session. The scene being left still holds its own materials until it
## is freed; the next area rebuilds what it needs.
func _drop_area_caches() -> void:
	WoollyWolf._wool_cache.clear()
	PeapodPopper._pod_mat_cache.clear()
	GummyBrute._jelly_cache.clear()


## A world whose root script failed to load (a parse error mid-night) leaves a sky-only void with no
## player, pause or way out (critique UI r1). Detect it and send Mak home with an apology card.
func _guard_broken_world(world_id: String) -> void:
	if world_id == "" or not WorldRegistry.has_world(world_id):
		return
	await get_tree().create_timer(1.5).timeout
	if busy or current_target != world_id:
		return
	var scene := get_tree().current_scene
	var ok := scene != null and scene is WorldRoot
	if ok and not get_tree().get_nodes_in_group("player").is_empty():
		return
	if scene != null and not (scene is WorldRoot) and scene.get_script() != null:
		return  # a custom non-WorldRoot scene (test arena) that manages itself
	push_error("[Router] %s loaded without a WorldRoot or player; returning to safety" % world_id)
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("show_banner"):
		ui.show_banner("This page is still being inked", "Back to the library", 2.4)
	await get_tree().create_timer(1.2).timeout
	if world_id == "HUB":
		go_to_title()
	else:
		go_to_hub("Book_" + world_id)


func _load_threaded(path: String) -> PackedScene:
	var err := ResourceLoader.load_threaded_request(path, "PackedScene", true)
	if err != OK:
		push_warning("[Router] threaded load request failed for %s: %s" % [path, error_string(err)])
		return load(path) as PackedScene
	while true:
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path) as PackedScene
		if st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("[Router] failed to load " + path)
			return null
		await get_tree().process_frame
	return null


func _unwritten_page(world_id: String, path: String) -> PackedScene:
	push_warning("[Router] scene missing: '%s' (%s); showing the unwritten-chapter page" % [path, world_id])
	_spinner.visible = false
	_subtitle.text = WorldRegistry.book_title(world_id) if world_id != "" else "A blank page"
	_title.text = "This chapter is still being written"
	# critique UI r1: never show a raw world id, and speak to the pad player in pad words
	var known: bool = world_id != "" and not WorldRegistry.get_world(world_id).is_empty()
	var ui_n := get_node_or_null("/root/UI")
	var pad: bool = ui_n != null and String(ui_n.get("last_device")) == "gamepad"
	_note.text = "The ink is still wet on %s.\n%s to return." % [WorldRegistry.display_name(world_id) if known else "this page", "Press any button" if pad else "Press any key"]
	_waiting_key = true
	var waited := 0.0
	while _waiting_key and waited < 6.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_waiting_key = false
	_note.text = ""
	_spinner.visible = true
	var fallback := TITLE_SCENE
	var g := _game()
	if world_id != "HUB" and world_id != "" and WorldRegistry.scene_exists("HUB"):
		fallback = WorldRegistry.scene_path("HUB")
		pending_spawn = "Book_" + world_id
		if g:
			g.begin_visit("HUB", "")
	elif g:
		g.end_visit()
		g.current_world = ""
	_title.text = "Turning back..."
	_subtitle.text = ""
	return load(fallback) as PackedScene


func _input(event: InputEvent) -> void:
	if _waiting_key and event.is_pressed() and not event.is_echo():
		if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
			_waiting_key = false
			get_viewport().set_input_as_handled()

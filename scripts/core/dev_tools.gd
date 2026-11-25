extends Node
## Dev tools autoload ("Dev"): command-line capture, story cameras, input replay
## data and timing helpers. Arguments go after "--" on the Godot command line:
##   Godot.exe --path game res://scenes/tests/MoveLab.tscn -- --capture=C:/abs/out.png --wait=90 --cam=StoryCam_A
## Recognised arguments (all optional):
##   --capture=<abs png path>   save the rendered viewport after --wait frames, then quit
##   --wait=<frames>            frames to wait before capture (default 90)
##   --cam=<node name>          make this Camera3D (searched in the current scene) current
##   --hide-hud                 hide CanvasLayers in group "hud" for clean story views
##   --replay=<abs json path>   input replay consumed by the player input layer (see TECH_CONTRACT.md)
##   --trace=<abs json path>    player writes a per-physics-frame state trace here
##   --quit-after-frames=<n>    quit after n rendered frames
##   --timescale=<f>            Engine.time_scale
##   --profile=<name>           save-profile name, so test runs never touch the real save
##   --unlock-all               debug: open every book/door (never counts as progress evidence)
##   --spawn=<marker name>      spawn the player at this Marker3D in the loaded world
##   --mission=<truffle id>     preselect a mission when a world is loaded directly
##   --rea-overlay              dev panel comparing live jumps with the REA-predicted arcs (F3 hides/shows it)

signal capture_saved(path: String)

var args: Dictionary = {}
var frame: int = 0
var replay: Dictionary = {}

var _capture_path := ""
var _capture_wait := 90
var _quit_after_frames := -1
var _cam_name := ""
var _capturing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_capture_path = args.get("capture", "")
	_capture_wait = int(args.get("wait", "90"))
	_quit_after_frames = int(args.get("quit-after-frames", "-1"))
	_cam_name = args.get("cam", "")
	if args.has("timescale"):
		Engine.time_scale = float(args["timescale"])
	if args.has("replay"):
		_load_replay(args["replay"])
	if args.has("rea-overlay"):
		add_child((load("res://scripts/ui/rea_overlay.gd") as GDScript).new())
	if args.size() > 0:
		print("[Dev] args: ", args)
	var normal_input_review := false
	if OS.has_feature("web") and OS.has_feature("web_review"):
		var window := JavaScriptBridge.get_interface("window")
		normal_input_review = window.makReview != null and window.makReview.normalRun == true
	if (args.has("web-review") or normal_input_review) and ResourceLoader.exists("res://tests/web/review.gd"):
		add_child((load("res://tests/web/review.gd") as GDScript).new())


func arg(key: String, default_value: String = "") -> String:
	return args.get(key, default_value)


func has_arg(key: String) -> bool:
	return args.has(key)


func is_test_run() -> bool:
	return args.has("capture") or args.has("replay") or args.has("quit-after-frames")


func _process(_delta: float) -> void:
	frame += 1
	if frame == 3:
		if args.has("hide-hud"):
			for n in get_tree().get_nodes_in_group("hud"):
				if n is CanvasLayer:
					n.visible = false
	# A --goto transition can finish after frame 3. Keep the explicitly requested
	# capture camera active once it exists, including in exported native builds.
	if _cam_name != "" and get_tree().current_scene != null:
		var camera := get_tree().current_scene.find_child(_cam_name, true, false) as Camera3D
		if camera != null and not camera.current:
			camera.make_current()
	if _capture_path != "" and frame >= _capture_wait and not _capturing:
		_capturing = true
		await RenderingServer.frame_post_draw
		save_screenshot(_capture_path)
		get_tree().quit()
	if _quit_after_frames > 0 and frame >= _quit_after_frames:
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
		save_screenshot(OS.get_user_data_dir().path_join("captures/%sZ.png" % stamp))


func save_screenshot(path: String) -> String:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	print("[Dev] screenshot ", "saved " if err == OK else "FAILED ", path, " ", img.get_size())
	capture_saved.emit(path)
	return path


func use_story_camera(cam_name: String) -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var cam := scene.find_child(cam_name, true, false) as Camera3D
	if cam == null:
		push_warning("[Dev] story camera not found: " + cam_name)
		return false
	cam.make_current()
	print("[Dev] story camera: ", cam_name, " at ", cam.global_position)
	return true


func _load_replay(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[Dev] replay not found: " + path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		replay = parsed
		print("[Dev] replay loaded: ", path)
	else:
		push_error("[Dev] replay is not a JSON object: " + path)

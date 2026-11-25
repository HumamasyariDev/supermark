extends Node3D
## PoseLab (player workstream): animation review stage for the real skinned Mr. Mak.
## Freezes the controller, drives MakAnimator through named clip presets frame by frame and saves
## native captures (one PNG per pose and view) plus a labelled contact sheet.
##
##   python tools/godot.py run res://scenes/tests/PoseLab.tscn --seconds 60 -- --profile=hero-pose \
##       --out=C:/abs/dir --poses=idle,run,jab1 --views=side,3q [--proxy-pig] [--toon] [--hat=top_hat] [--sheet=name]
##   Movie mode (Movie Maker; plays each clip in real time while the camera holds a view):
##   python tools/godot.py movie res://scenes/tests/PoseLab.tscn out.avi --frames 900 -- --profile=hero-pose --clips=idle:6,run:3 --views=3q

const PRESETS := {
	# name: state, t (s into the state), plus optional pre (state before), speed (m/s), vy, step, travel, grounded
	"idle": {"s": "idle", "t": 1.2},
	"idle_look": {"s": "idle", "t": 0.6, "idle_var": "look"},
	"idle_yawn": {"s": "idle", "t": 1.0, "idle_var": "yawn"},
	"idle_beanie": {"s": "idle", "t": 0.9, "idle_var": "beanie"},
	"idle_sniffair": {"s": "idle", "t": 0.7, "idle_var": "sniffair"},
	"walk_a": {"s": "walk", "t": 0.50, "speed": 2.2},
	"walk_b": {"s": "walk", "t": 0.80, "speed": 2.2},
	"run_a": {"s": "walk", "t": 0.50, "speed": 7.5},
	"run_b": {"s": "walk", "t": 0.62, "speed": 7.5},
	"skid": {"s": "skid", "t": 0.12, "pre": "walk", "speed": 6.0},
	"jump_rise": {"s": "jump", "t": 0.10, "vy": 9.0, "pre": "walk", "speed": 5.0, "air": true},
	"jump_fall": {"s": "jump", "t": 0.55, "vy": -6.0, "air": true},
	"double_jump": {"s": "double_jump", "t": 0.12, "vy": 11.0, "air": true},
	"triple_a": {"s": "triple_jump", "t": 0.16, "vy": 10.0, "air": true},
	"triple_b": {"s": "triple_jump", "t": 0.34, "vy": 3.0, "air": true},
	"backflip": {"s": "backflip", "t": 0.26, "vy": 7.0, "air": true},
	"side_flip": {"s": "side_flip", "t": 0.24, "vy": 7.0, "air": true},
	"long_jump": {"s": "long_jump", "t": 0.2, "vy": 4.0, "speed": 10.0, "air": true},
	"wall_slide": {"s": "wall_slide", "t": 0.3, "vy": -2.5, "air": true},
	"wall_kick": {"s": "wall_kick", "t": 0.1, "vy": 12.0, "air": true},
	"ham_tuck": {"s": "ham_slam", "t": 0.08, "air": true},
	"ham_spin": {"s": "ham_slam", "t": 0.26, "air": true},
	"ham_drop": {"s": "ham_slam", "t": 0.62, "vy": -14.0, "air": true},
	"slam_land": {"s": "slam_land", "t": 0.04, "pre": "ham_slam"},
	"slam_rise": {"s": "slam_land", "t": 0.22, "pre": "ham_slam"},
	"dive": {"s": "dive", "t": 0.12, "vy": 2.0, "speed": 9.0, "air": true},
	"belly_slide": {"s": "belly_slide", "t": 0.3, "speed": 6.0},
	"rollout": {"s": "rollout", "t": 0.18, "vy": 4.0, "air": true},
	"jab1": {"s": "punch", "t": 0.09, "step": 1},
	"jab2": {"s": "punch", "t": 0.09, "step": 2, "pre": "punch", "pre_step": 1},
	"kick_wind": {"s": "punch", "t": 0.04, "step": 3, "pre": "punch", "pre_step": 2},
	"kick": {"s": "punch", "t": 0.17, "step": 3, "pre": "punch", "pre_step": 2},
	"jump_kick": {"s": "jump_kick", "t": 0.1, "vy": 2.0, "air": true},
	"ledge_hang": {"s": "ledge_hang", "t": 0.6, "air": true},
	"ledge_climb": {"s": "ledge_climb", "t": 0.18, "air": true},
	"crouch": {"s": "crouch", "t": 0.5},
	"crawl": {"s": "crouch", "t": 0.5, "speed": 1.4},
	"crouch_slide": {"s": "crouch_slide", "t": 0.2, "speed": 5.0},
	"pole": {"s": "pole_climb", "t": 0.5, "travel": 0.3, "air": true},
	"hurt_air": {"s": "hurt_air", "t": 0.18, "vy": 4.0, "air": true},
	"hurt_land": {"s": "hurt_land", "t": 0.2},
	"fallout": {"s": "fallout", "t": 0.5, "vy": -12.0, "air": true},
	"celebrate": {"s": "celebrate", "t": 0.45},
	"celebrate_b": {"s": "celebrate", "t": 1.1},
	"sniff": {"s": "sniff", "t": 0.6, "speed": 0.0},
	"sniff_walk": {"s": "sniff", "t": 0.6, "speed": 1.6},
	"slope_slide": {"s": "slope_slide", "t": 0.4, "speed": 5.0},
	"blink": {"s": "idle", "t": 0.5, "blink": true},
	# Hero fix r2 presets.
	"idle_arms_loose": {"s": "idle", "t": 1.2, "idle_arm": 0},
	"idle_arms_hips": {"s": "idle", "t": 1.2, "idle_arm": 1},
	"idle_arms_strap": {"s": "idle", "t": 1.2, "idle_arm": 2},
	"idle_arms_back": {"s": "idle", "t": 1.2, "idle_arm": 3},
	"brake": {"s": "walk", "t": 0.12, "pre": "walk", "speed": 5.0, "braking": true},
	"celebrate_v": {"s": "celebrate", "t": 0.85},
	"celebrate_pump": {"s": "celebrate", "t": 1.12},
	"run_c": {"s": "walk", "t": 0.56, "speed": 7.5},
	"blink_shut": {"s": "idle", "t": 0.5, "blink": true, "blink_frames": 2},
	# Hero v2 chibi overhaul presets.
	"idle_hop": {"s": "idle", "t": 0.5, "idle_var": "hop"},
	"idle_hattip": {"s": "idle", "t": 1.1, "idle_var": "hattip"},
	"idle_tilt": {"s": "idle", "t": 0.7, "idle_var": "tilt"},
	"walk_c": {"s": "walk", "t": 0.65, "speed": 2.2},
	"run_d": {"s": "walk", "t": 0.68, "speed": 7.5},
	"double_spin": {"s": "double_jump", "t": 0.24, "vy": 8.0, "air": true},
}
const VIEWS := {
	"side": Vector3(3.3, 0.75, 0.0),
	"front": Vector3(0.0, 0.8, -3.3),
	"3q": Vector3(2.35, 0.95, -2.35),
	"back": Vector3(0.0, 0.95, 3.3),
	"3qb": Vector3(-2.3, 1.0, 2.3),
	"face": Vector3(0.55, 1.0, -1.35),
}
const DT := 1.0 / 60.0

var player: Node3D
var anim: Node
var cam: Camera3D
var label: Label
var _dev: Node
var _out := ""
var _shots: Array = []


func _ready() -> void:
	_dev = get_tree().root.get_node_or_null("Dev")
	_build_stage()
	var ps := load("res://scenes/player/Player.tscn") as PackedScene
	player = ps.instantiate() as Node3D
	add_child(player)
	player.set_physics_process(false)
	var pc := player.get_node_or_null("MakCamera")
	if pc != null:
		pc.process_mode = Node.PROCESS_MODE_DISABLED
	anim = player.get_node("Animator")
	cam = Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.make_current()
	var cl := CanvasLayer.new()
	add_child(cl)
	label = Label.new()
	label.position = Vector2(14, 10)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05))
	cl.add_child(label)
	_out = _arg("out")
	if _out == "":
		_out = ProjectSettings.globalize_path("user://poselab")
	DirAccess.make_dir_recursive_absolute(_out)
	if _arg("clips") != "":
		_run_clips.call_deferred()
	else:
		_run_stills.call_deferred()


func _arg(k: String) -> String:
	if _dev != null and _dev.has_method("arg"):
		var v := str(_dev.call("arg", k, ""))
		if v == "" and _dev.has_method("has_arg") and bool(_dev.call("has_arg", k)):
			return "1"
		return v
	return ""


func _build_stage() -> void:
	var we := WorldEnvironment.new()
	var env_path := "res://assets/shaders/environments/env_W1.tres"
	if ResourceLoader.exists(env_path):
		we.environment = load(env_path)
	else:
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.8, 0.88, 0.96)
		e.ambient_light_color = Color(0.7, 0.75, 0.8)
		we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.72, 0.42)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	# A soft backdrop so silhouettes read against a plain colour.
	var wall := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(40, 12)
	wall.mesh = wm
	wall.rotation_degrees = Vector3(90, 0, 0)
	wall.position = Vector3(0, 6, 9)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.86, 0.9, 0.95)
	wall.material_override = wmat
	add_child(wall)


func _set_view(v: String) -> void:
	var pos: Vector3 = VIEWS.get(v, VIEWS["3q"])
	var look := Vector3(0, 0.6, 0)
	if v == "face":
		look = Vector3(0, 0.85, 0)
		cam.fov = 26.0
	else:
		cam.fov = 30.0
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	# Keep the backdrop behind the subject.
	pass


func _apply_preset(name: String, cfg: Dictionary, st_name: String, step_field: String) -> void:
	player.set("state", str(cfg.get(st_name, "idle")))
	var sp := float(cfg.get("speed", 0.0))
	player.set("velocity", Vector3(0, float(cfg.get("vy", 0.0)), -sp))
	player.set("vy", float(cfg.get("vy", 0.0)))
	player.set("forward_speed", sp)
	player.set("grounded", not bool(cfg.get("air", false)))
	player.set("combo_step", int(cfg.get(step_field, 1)))
	player.set("pole_climb_travel", float(cfg.get("travel", 0.0)))
	player.set("braking", bool(cfg.get("braking", false)) and st_name == "s")


func _pose(spec: String) -> void:
	var name := spec.get_slice("@", 0)
	var cfg: Dictionary = (PRESETS.get(name, {"s": name, "t": 0.5}) as Dictionary).duplicate()
	if spec.contains("@"):
		cfg["t"] = float(spec.get_slice("@", 1))
	# Pre-roll: idle (or the given previous state) so blends arrive like in play.
	var pre := str(cfg.get("pre", "idle"))
	var pre_cfg := cfg.duplicate()
	pre_cfg["pre_s"] = pre
	_apply_preset(name, pre_cfg, "pre_s", "pre_step")
	if pre == "idle":
		player.set("velocity", Vector3.ZERO)
		player.set("grounded", true)
	for i in 30:
		anim.call("_process", DT)
	_apply_preset(name, cfg, "s", "step")
	if cfg.has("idle_var") and anim.has_method("debug_idle_variation"):
		anim.call("debug_idle_variation", str(cfg["idle_var"]))
	if cfg.has("idle_arm") and anim.has_method("debug_idle_arm"):
		anim.call("debug_idle_arm", int(cfg["idle_arm"]))
	var n := int(round(float(cfg.get("t", 0.5)) / DT))
	var sw := {"punch": "punch", "jump_kick": "jump_kick", "dive": "dive"}
	if sw.has(str(cfg["s"])) and anim.has_method("_on_attacked"):
		anim.call("_on_attacked", "kick" if int(cfg.get("step", 1)) == 3 else str(sw[str(cfg["s"])]))
	for i in n:
		anim.call("_process", DT)
	for c in player.get_node("Visual").get_children():
		if c is MakSwoosh:
			c.set("_t", minf(float(cfg.get("t", 0.1)), c.life * 0.55))
			c.call("_build")
			c.set_process(false)
			c.get_tree().create_timer(0.3).timeout.connect(c.queue_free)
	if bool(cfg.get("blink", false)) and anim.has_method("debug_blink"):
		anim.call("debug_blink")
		for i in int(cfg.get("blink_frames", 3)):
			anim.call("_process", DT)


func _run_stills() -> void:
	anim.set_process(false)
	var poses := _arg("poses").split(",", false)
	if poses.is_empty():
		poses = PackedStringArray(PRESETS.keys())
	var views := _arg("views").split(",", false)
	if views.is_empty():
		views = PackedStringArray(["3q"])
	var prefix := _arg("prefix")
	for v in views:
		for p in poses:
			_set_view(v)
			_pose(p)
			label.text = "%s  (%s)" % [p, v]
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path := _out.path_join("%s%s__%s.png" % [prefix, p, v])
			img.save_png(path)
			_shots.append(path)
			print("[PoseLab] saved ", path)
	var sheet := _arg("sheet")
	if sheet != "":
		_make_sheet(_out.path_join(sheet + ".png"), int(_arg("cols")) if _arg("cols") != "" else 4)
	get_tree().quit()


func _make_sheet(path: String, cols: int) -> void:
	if _shots.is_empty():
		return
	var tw := 480
	var th := 270
	var rows := int(ceil(float(_shots.size()) / float(cols)))
	var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i in _shots.size():
		var im := Image.load_from_file(str(_shots[i]))
		if im == null:
			continue
		im.convert(Image.FORMAT_RGB8)
		im.resize(tw, th, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(im, Rect2i(0, 0, tw, th), Vector2i((i % cols) * tw, (i / cols) * th))
	sheet.save_png(path)
	print("[PoseLab] sheet ", path)


func _run_clips() -> void:
	## Real-time clip reel for Movie Maker: each clip plays for its duration from the view given.
	anim.set_process(false)
	var views := _arg("views").split(",", false)
	if views.is_empty():
		views = PackedStringArray(["3q"])
	var list := _arg("clips").split(",", false)
	var vi := 0
	for entry in list:
		var parts := entry.split(":")
		var nm := parts[0]
		var dur := float(parts[1]) if parts.size() > 1 else 2.0
		var cfg: Dictionary = (PRESETS.get(nm, {"s": nm}) as Dictionary).duplicate()
		if parts.size() > 2:
			cfg["cycle"] = float(parts[2])
		if parts.size() > 3:
			views = PackedStringArray([parts[3]])
			vi = 0
		_set_view(views[vi % views.size()])
		vi += 1
		label.text = nm.replace("_", " ")
		_apply_preset(nm, cfg, "s", "step")
		if cfg.has("idle_var") and anim.has_method("debug_idle_variation"):
			anim.call("debug_idle_variation", str(cfg["idle_var"]))
		var frames := int(dur * 60.0)
		for f in frames:
			# Flips and timed moves restart every cycle so a reel shows the whole action.
			var cyc := float(cfg.get("cycle", 0.0))
			if cyc > 0.0 and f % int(cyc * 60.0) == 0:
				player.set("state", "idle")
				anim.call("_process", DT)
				_apply_preset(nm, cfg, "s", "step")
				if cfg.has("idle_var") and anim.has_method("debug_idle_variation"):
					anim.call("debug_idle_variation", str(cfg["idle_var"]))
				var swk := {"punch": "punch", "jump_kick": "jump_kick", "dive": "dive"}
				if swk.has(str(cfg["s"])):
					anim.call("_on_attacked", "kick" if int(cfg.get("step", 1)) == 3 else str(swk[str(cfg["s"])]))
			anim.call("_process", DT)
			await get_tree().process_frame
	get_tree().quit()

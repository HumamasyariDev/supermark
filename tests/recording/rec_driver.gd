extends Node
## Recording driver for the making-of footage (test-only; launched as the main scene RecDriver.tscn under Movie Maker
## by game/tests/recording/record_final.py). It moves itself to the root, loads the target scene and then:
##   --rec=fly        smooth camera move through the area's story cameras (--rec-cams=A,B,..., --rec-secs, --rec-lift),
##                    HUD hidden; eased Catmull-Rom positions, slerped orientations and FOV.
##   --rec=ab         one fixed camera (--rec-cam=<StoryCam> or "player"), "Classic textures" off for --rec-hold s,
##                    then on for --rec-hold s (Game setting, not persisted; RetroLook follows it live).
##   --rec=title_hub  the title screen, the menu (real key events), New Game, the hub intro, then Mak runs a fixed route
##                    past Bramwell, the hat stand and the lecterns through the real move/jump input actions.
## Common: --rec-scene=<res://...> (target scene), --rec-wait=<s> (build/settle time before the move starts).
## Prints "[Rec] ..." lines with Engine frame numbers so the cut can trim the wait exactly.

var mode := ""
var t := 0.0
var phase := 0
var cam: Camera3D
var keys: Array = []
var segs: Array = []
var total := 0.0
var secs := 16.0
var wait := 3.0
var lift := 0.0
var hold := 4.0
var p: CharacterBody3D
var route: Array = []
var wi := 0
var best_d := 1e9
var stall := 0.0
var jump_left := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node("/root/Dev")
	mode = String(dev.call("arg", "rec", "fly"))
	secs = float(dev.call("arg", "rec-secs", "16"))
	wait = float(dev.call("arg", "rec-wait", "3"))
	lift = float(dev.call("arg", "rec-lift", "0"))
	hold = float(dev.call("arg", "rec-hold", "4"))
	var target := String(dev.call("arg", "rec-scene", "res://scenes/boot/Boot.tscn"))
	_go.call_deferred(target)


func _go(target: String) -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	tree.change_scene_to_file(target)
	print("[Rec] mode %s scene %s frame %d" % [mode, target, Engine.get_frames_drawn()])


func _hide_hud() -> void:
	for n in get_tree().get_nodes_in_group("hud"):
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false


func _process(delta: float) -> void:
	t += delta
	if get_tree().current_scene == null:
		return
	match mode:
		"fly":
			_fly(delta)
		"ab":
			_ab(delta)
		"title_hub":
			_title_hub(delta)


# ------------------------------------------------------------------ fly-through

func _fly(_delta: float) -> void:
	_hide_hud()
	if phase == 0 and t >= wait:
		var names := String(get_node("/root/Dev").call("arg", "rec-cams", "StoryCam_A,StoryCam_B")).split(",")
		for nm in names:
			var c := get_tree().current_scene.find_child(nm, true, false) as Camera3D
			if c == null:
				print("[Rec] missing camera ", nm)
				continue
			keys.append({"p": c.global_position, "q": c.global_transform.basis.get_rotation_quaternion(), "fov": c.fov})
			print("[Rec] key %s pos %s fwd %s fov %.1f" % [nm, str(c.global_position), str(-c.global_transform.basis.z), c.fov])
		if keys.size() < 2:
			print("[Rec] not enough cameras")
			get_tree().quit()
			return
		var lens: Array = []
		var sum := 0.0
		for i in keys.size() - 1:
			var l := maxf(4.0, (keys[i + 1]["p"] as Vector3).distance_to(keys[i]["p"]))
			lens.append(l)
			sum += l
		var acc := 0.0
		for i in lens.size():
			segs.append([acc / sum, (acc + float(lens[i])) / sum])
			acc += float(lens[i])
		cam = Camera3D.new()
		cam.name = "RecFlyCam"
		get_tree().current_scene.add_child(cam)
		cam.global_transform = Transform3D(Basis(keys[0]["q"]), keys[0]["p"])
		cam.fov = keys[0]["fov"]
		cam.make_current()
		phase = 1
		total = 0.0
		print("[Rec] fly start frame %d" % Engine.get_frames_drawn())
	if phase == 1:
		total += _delta
		var g := clampf(total / secs, 0.0, 1.0)
		var s := g * g * g * (g * (g * 6.0 - 15.0) + 10.0)  # smootherstep over the whole move
		var i := 0
		while i < segs.size() - 1 and s > float(segs[i][1]):
			i += 1
		var u := clampf((s - float(segs[i][0])) / maxf(0.0001, float(segs[i][1]) - float(segs[i][0])), 0.0, 1.0)
		var p0: Vector3 = keys[maxi(i - 1, 0)]["p"]
		var p1: Vector3 = keys[i]["p"]
		var p2: Vector3 = keys[i + 1]["p"]
		var p3: Vector3 = keys[mini(i + 2, keys.size() - 1)]["p"]
		var pos := _catmull(p0, p1, p2, p3, u) + Vector3.UP * lift * p1.distance_to(p2) * sin(PI * u)
		var ur := u * u * (3.0 - 2.0 * u)
		var q := (keys[i]["q"] as Quaternion).slerp(keys[i + 1]["q"], ur)
		cam.global_transform = Transform3D(Basis(q), pos)
		cam.fov = lerpf(keys[i]["fov"], keys[i + 1]["fov"], ur)
		if not cam.current:
			cam.make_current()
		if total >= secs + 0.5:
			print("[Rec] fly end frame %d" % Engine.get_frames_drawn())
			get_tree().quit()


func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)


# ------------------------------------------------------------------ Classic textures A/B

func _ab(_delta: float) -> void:
	_hide_hud()
	var game := get_node_or_null("/root/Game")
	if phase == 0 and t >= wait:
		var nm := String(get_node("/root/Dev").call("arg", "rec-cam", "StoryCam_A"))
		if nm != "player":
			var c := get_tree().current_scene.find_child(nm, true, false) as Camera3D
			if c:
				c.make_current()
		game.call("set_setting", "classic_textures", false, false)
		print("[Rec] ab off frame %d" % Engine.get_frames_drawn())
		phase = 1
		t = 0.0
	elif phase == 1 and t >= hold:
		game.call("set_setting", "classic_textures", true, false)
		print("[Rec] ab on frame %d" % Engine.get_frames_drawn())
		phase = 2
		t = 0.0
	elif phase == 2 and t >= hold + 0.3:
		print("[Rec] ab end frame %d" % Engine.get_frames_drawn())
		get_tree().quit()


# ------------------------------------------------------------------ title -> menu -> new game -> hub run

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _title_hub(delta: float) -> void:
	var title := get_tree().get_first_node_in_group("title_screen")
	match phase:
		0:
			if title and t > wait:
				_key(KEY_ENTER, true)
				print("[Rec] title key frame %d" % Engine.get_frames_drawn())
				phase = 1
				t = 0.0
		1:
			if t > 0.1 and t < 0.2:
				_key(KEY_ENTER, false)
			if t > 2.6:
				_key(KEY_ENTER, true)
				print("[Rec] new game key frame %d" % Engine.get_frames_drawn())
				phase = 2
				t = 0.0
		2:
			if t > 0.1 and t < 0.2:
				_key(KEY_ENTER, false)
			if t > 1.5 and title and is_instance_valid(title) and String(title.get("state")) == "menu":
				print("[Rec] menu did not take the key; calling New Game")
				title.call("_on_new_game")
				t = 0.0
			p = get_tree().get_first_node_in_group("player") as CharacterBody3D
			var sc := get_tree().current_scene
			if p and sc and title == null and sc.name.to_lower().contains("hub"):
				phase = 3
				t = 0.0
				print("[Rec] hub loaded frame %d" % Engine.get_frames_drawn())
		3:
			# Wait for the intro to hand control back (player physics on again for 0.6 s).
			if p and p.is_physics_processing() and t > 1.0:
				stall += delta
			else:
				stall = 0.0
			if stall > 0.6:
				phase = 4
				t = 0.0
				stall = 0.0
				route = [
					[Vector3(1.9, 0, 9.4), false], [Vector3(3.7, 0, 11.2), false], [Vector3(1.2, 0, 12.8), false],
					[Vector3(-2.8, 0, 11.8), true], [Vector3(-4.8, 0, 8.9), false], [Vector3(-3.0, 0, 4.2), false],
					[Vector3(0.0, 0, 2.2), true], [Vector3(2.6, 0, 4.6), false], [Vector3(4.4, 0, 6.2), false],
					[Vector3(2.7, 0, 2.5), false], [Vector3(1.0, 0, -2.6), true], [Vector3(0.0, 2.25, -8.25), false],
				]
				print("[Rec] run start frame %d" % Engine.get_frames_drawn())
		4:
			_run_route(delta)


func _run_route(delta: float) -> void:
	_release()
	if jump_left > 0:
		jump_left -= 1
		Input.action_press("jump")
	else:
		Input.action_release("jump")
	if wi >= route.size():
		if t > 1.5:
			print("[Rec] run end frame %d" % Engine.get_frames_drawn())
			get_tree().quit()
		return
	var target: Vector3 = route[wi][0]
	var d3 := target - p.global_position
	d3.y = 0.0
	var d := d3.length()
	if d < best_d - 0.05:
		best_d = d
		stall = 0.0
	else:
		stall += delta
	if d < 0.9 or stall > 1.5:
		if stall > 1.5:
			print("[Rec] waypoint %d skipped (stuck) at %s" % [wi, str(p.global_position)])
		if bool(route[wi][1]):
			jump_left = 12
		wi += 1
		best_d = 1e9
		stall = 0.0
		t = 0.0
		return
	_steer(d3.normalized())


func _steer(dir: Vector3) -> void:
	var yaw := 0.0
	if p.has_method("_camera_yaw"):
		yaw = float(p.call("_camera_yaw"))
	if bool(p.get("_steer_locked")) and p.get("_steer_yaw") != null:
		yaw = float(p.get("_steer_yaw"))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var sx := dir.dot(right)
	var sy := dir.dot(fwd)
	if sx > 0.0:
		Input.action_press("move_right", sx)
	else:
		Input.action_press("move_left", -sx)
	if sy > 0.0:
		Input.action_press("move_forward", sy)
	else:
		Input.action_press("move_back", -sy)


func _release() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)

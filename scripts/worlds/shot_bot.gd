extends Node
## Dev capture helper (--shots=<name>@x,y,z,tx,ty,tz[,fov];... --shots-out=<abs dir> [--shots-hide-player]): after the
## world settles, frames each named view with its own camera and saves <out>/<name>.png, then quits. Added by
## WorldExits.install, so any WorldRoot scene can produce before/after captures of a spot in one run.

var _specs: Array = []
var _out := ""
## false: the exit bot calls run(false) itself (shots first, then its tests, same run).
var auto := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if auto:
		await get_tree().create_timer(4.5).timeout
		await run(true)


func run(quit_after: bool) -> void:
	var dev := get_node_or_null("/root/Dev")
	_out = String(dev.call("arg", "shots-out", ""))
	for part in String(dev.call("arg", "shots", "")).split(";", false):
		var nv := part.split("@")
		if nv.size() != 2:
			continue
		var v := nv[1].split(",")
		if v.size() < 6:
			continue
		_specs.append({"name": nv[0], "pos": Vector3(float(v[0]), float(v[1]), float(v[2])), "at": Vector3(float(v[3]), float(v[4]), float(v[5])), "fov": float(v[6]) if v.size() > 6 else 55.0})
	var prev := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.far = 800.0
	get_tree().root.add_child(cam)
	if dev.call("has_arg", "shots-hide-player"):
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p:
			p.visible = false
	var ui := get_node_or_null("/root/UI")
	if ui and ui.has_method("set_hud_visible"):
		ui.call("set_hud_visible", false)
	var p0 := get_tree().get_first_node_in_group("player") as Node3D
	for s in _specs:
		cam.fov = float(s["fov"])
		cam.global_position = s["pos"]
		cam.look_at(s["at"], Vector3.UP)
		cam.current = true
		for i in 40:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		if img and _out != "":
			img.save_png(_out.path_join(String(s["name"]) + ".png"))
		print("[ShotBot] saved %s" % s["name"])
	cam.queue_free()
	if prev and is_instance_valid(prev):
		prev.current = true
	if p0:
		p0.visible = true
	if ui and ui.has_method("set_hud_visible"):
		ui.call("set_hud_visible", true)
	if quit_after:
		get_tree().quit()

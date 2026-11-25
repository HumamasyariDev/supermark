extends Node3D
## EnemyReview: one Godot run for many review shots or one long reel (the machine runs two game slots for every agent,
## so a run per pose sheet waited 10+ minutes in the queue). Wraps EnemyLab.tscn and drives its _poses/_reel helpers.
##   --review=poses  --families=a,b,... --yaws=0,90 --review-out=<abs dir> [--review-tag=x]   saves <UTC>__poses_<fam>_yaw<y>_<tag>.png
##   --review=reels  --families=a,b,...                                                        every family's scripted reel back to back
##   --review=lineup --review-out=<abs dir>                                                     close lineup of all six families
## Use: python tools/godot.py run res://scenes/enemies/EnemyReview.tscn --seconds 240 -- --review=poses ... --profile=enemies
##      python tools/godot.py movie res://scenes/enemies/EnemyReview.tscn out.avi --frames N -- --review=reels ...

const ALL := ["woolly_wolf", "gingerbread_grenadier", "gummy_brute", "crow_bandit", "peapod_popper", "bumble_bruiser"]

var lab: Node3D


func _ready() -> void:
	lab = (load("res://scenes/enemies/EnemyLab.tscn") as PackedScene).instantiate() as Node3D
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	var fams: Array = ALL.duplicate()
	if Dev.has_arg("families"):
		fams = Array(Dev.arg("families").split(","))
	match Dev.arg("review", "poses"):
		"poses":
			await _do_poses(fams)
		"reels":
			await _do_reels(fams)
		"lineup":
			await _do_lineup()
	print("[Review] done")
	get_tree().quit()


func _out(name: String) -> String:
	var dir := Dev.arg("review-out", OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(dir)
	var ts := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	return "%s/%sZ__%s.png" % [dir, ts, name]


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := _out(name)
	img.save_png(p)
	print("[Review] shot ", p)


func _clear_labels() -> void:
	for c in lab.get_children():
		if c is Label3D:
			c.queue_free()


func _do_poses(fams: Array) -> void:
	var yaws: Array = Array(Dev.arg("yaws", "0,90").split(","))
	var tag := Dev.arg("review-tag", "review")
	for f in fams:
		for y in yaws:
			_clear_labels()
			await get_tree().process_frame
			if String(f) == "sergeant_snap":
				_snap_row()
			else:
				lab.call("_poses", String(f))
			await get_tree().process_frame
			var yaw := deg_to_rad(float(y))
			for k in (lab.get("enemies") as Dictionary).keys():
				var e := (lab.get("enemies") as Dictionary)[k] as EnemyBase
				if is_instance_valid(e):
					e.rotation.y = PI + yaw
					e.set("_last_yaw", e.rotation.y)
			# Wider than the lab's own framing so all six states and their labels fit.
			var off: Vector3 = lab.get("cam_offset")
			lab.set("cam_offset", off * 1.3)
			var fc := lab.get("follow_cam") as Camera3D
			fc.global_position = (lab.get("cam_target") as Vector3) + off * 1.3
			await get_tree().create_timer(0.3).timeout
			for k in (lab.get("enemies") as Dictionary).keys():
				var e := (lab.get("enemies") as Dictionary)[k] as EnemyBase
				if is_instance_valid(e):
					e.rotation.y = PI + yaw
					e.set("_last_yaw", e.rotation.y)
					e.reset_physics_interpolation()
			await get_tree().create_timer(1.9).timeout
			for k in (lab.get("enemies") as Dictionary).keys():
				var e := (lab.get("enemies") as Dictionary)[k] as EnemyBase
				if is_instance_valid(e):
					print("[Review] ", e.name, " yaw ", rad_to_deg(e.rotation.y), " state ", e.state)
			await _shot("poses_%s_yaw%s_%s" % [f, y, tag])


func _do_reels(fams: Array) -> void:
	for f in fams:
		_clear_labels()
		await get_tree().process_frame
		print("[Review] reel ", f)
		var fc := lab.get("follow_cam") as Camera3D
		if fc != null:
			fc.make_current()
		await lab.call("_reel", String(f))


func _do_lineup() -> void:
	lab.call("_lineup")
	var cam := lab.get("follow_cam") as Camera3D
	lab.set("cam_target", Vector3(0, 0.2, 11.0))
	lab.set("cam_offset", Vector3(0, 1.0, 7.8))
	if cam != null:
		cam.global_position = Vector3(0, 1.2, 18.8)
	await get_tree().create_timer(2.5).timeout
	await _shot("lineup_close_" + Dev.arg("review-tag", "review"))


## Sergeant Snap row (the lab's _poses builds plain grunts): one sergeant per state, AI off.
func _snap_row() -> void:
	var en: Dictionary = lab.get("enemies")
	for k in en.keys():
		if is_instance_valid(en[k]):
			(en[k] as Node).queue_free()
	en.clear()
	var states := ["patrol", "notice", "windup", "attack", "sweep", "recover"]
	var gap := 1.9
	var x := -float(states.size() - 1) * 0.5 * gap
	var i := 0
	for st in states:
		var e := GingerbreadGrenadier.new()
		e.sergeant = true
		e.name = "snap_%d" % i
		e.ai_enabled = false
		lab.add_child(e)
		e.global_position = Vector3(x, 0.05, 11.0)
		e.home = e.global_position
		e.state = String(st)
		var l := Label3D.new()
		l.text = String(st)
		l.font_size = 48
		l.outline_size = 12
		l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.add_child(l)
		l.global_position = Vector3(x, 0.12, 12.4)
		en["snap_%d" % i] = e
		x += gap
		i += 1
	lab.set("cam_target", Vector3(0, 0.3, 11.0))
	lab.set("cam_offset", Vector3(0, 1.4, 6.6))

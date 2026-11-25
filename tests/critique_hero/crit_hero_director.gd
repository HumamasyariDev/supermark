extends Node
## Director for CritHeroVisualR1 (see crit_hero_visual_r1.gd). Lives on the root so it survives the scene change.

var _out := ""
var _tag := "world"
var _settle := 300
var _walk_frames := 70
var _frame := 0
var _busy := false
var _player: Node3D = null
var _cam: Camera3D = null
var _stamp := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--walk="):
			_walk_frames = int(a.substr(7))
		elif a.begins_with("--settle="):
			_settle = int(a.substr(9))
	_stamp = Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "") + "Z"


func _process(_d: float) -> void:
	_frame += 1
	if _busy or _frame < _settle:
		return
	_busy = true
	_run()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot(caption: String) -> void:
	await _wait(4)
	var img := get_viewport().get_texture().get_image()
	var path := _out.path_join("%s__r1-%s-%s.png" % [_stamp, _tag, caption])
	DirAccess.make_dir_recursive_absolute(_out)
	var err := img.save_png(path)
	print("[CritHero] ", "saved " if err == OK else "FAILED ", path)


func _head() -> Vector3:
	var skel := _player.find_child("*", true, false) as Skeleton3D
	for s in _player.find_children("*", "Skeleton3D", true, false):
		skel = s as Skeleton3D
		break
	if skel != null and skel.find_bone("head") >= 0:
		var t := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("head"))
		return t.origin + Vector3(0, 0.26, 0)   # the head bone sits at the neck; aim at the face
	return _player.global_position + Vector3(0, 0.85, 0)


## Place the critique camera at polar angle `deg` around the facing direction (0 = in front of Mak).
func _place(deg: float, dist: float, height: float, look: Vector3, fov: float) -> void:
	var vis := _player.get_node_or_null("Visual") as Node3D
	var basis := (vis.global_basis if vis != null else _player.global_basis).orthonormalized()
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	var dir := fwd.rotated(Vector3.UP, deg_to_rad(deg))
	var pos := Vector3(look.x, _player.global_position.y + height, look.z) + dir * dist
	_cam.global_position = pos
	_cam.fov = fov
	_cam.look_at(look, Vector3.UP)
	_cam.make_current()


func _stats() -> void:
	for mi in _player.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null or not (mi as MeshInstance3D).is_visible_in_tree():
			continue
		var tris := 0
		var verts := 0
		var uniq := {}
		var mats := []
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			verts += v.size()
			tris += (idx.size() if idx.size() > 0 else v.size()) / 3
			for p in v:
				uniq[Vector3i(roundi(p.x * 10000), roundi(p.y * 10000), roundi(p.z * 10000))] = true
			var mat: Material = (mi as MeshInstance3D).get_surface_override_material(s)
			if mat == null:
				mat = m.surface_get_material(s)
			var desc := "null"
			if mat is ShaderMaterial:
				desc = "Shader:" + str((mat as ShaderMaterial).shader.resource_path.get_file())
			elif mat is BaseMaterial3D:
				var b := mat as BaseMaterial3D
				desc = "Std(rough=%.2f metal=%.2f tex=%s)" % [b.roughness, b.metallic, b.albedo_texture != null]
			mats.append(desc)
		var skinned := (mi as MeshInstance3D).skin != null
		print("[CritHero] mesh %s tris=%d verts=%d uniq_pos=%d split_ratio=%.2f skinned=%s aabb=%s mats=%s" % [
			mi.get_path(), tris, verts, uniq.size(), float(verts) / maxf(1.0, uniq.size()), skinned,
			(mi as MeshInstance3D).get_aabb().size, mats])


func _run() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		print("[CritHero] no player found")
		get_tree().quit()
		return
	print("[CritHero] world=", _tag, " player at ", _player.global_position, " state=",
		_player.call("get_state_name") if _player.has_method("get_state_name") else "?")
	_stats()
	# 1. the real gameplay camera: at spawn, while running away from it, and settled behind after the run
	await _shot("gameplay-cam-spawn")
	var gp := get_viewport().get_camera_3d()
	if gp != null:
		print("[CritHero] gameplay cam dist=%.2f fov=%.1f" % [gp.global_position.distance_to(_player.global_position), gp.fov])
	var fwd_action := "move_forward" if InputMap.has_action("move_forward") else ""
	if fwd_action != "" and _walk_frames > 0:
		Input.action_press(fwd_action, 1.0)
		await _wait(_walk_frames)
		await _shot("gameplay-cam-running")
		Input.action_release(fwd_action)
		await _wait(50)
		await _shot("gameplay-cam-behind-stopped")
		print("[CritHero] after walk at ", _player.global_position)
	_cam = Camera3D.new()
	_cam.name = "CritHeroCam"
	get_tree().current_scene.add_child(_cam)
	var head := _head()
	var mid := _player.global_position + Vector3(0, 0.55, 0)
	print("[CritHero] face aim height above feet: %.2f" % (head.y - _player.global_position.y))
	# 2. close-ups and turnaround in this world's light
	_place(0.0, 1.25, head.y - _player.global_position.y, head, 34.0)
	await _shot("face-front")
	_place(38.0, 1.3, head.y - _player.global_position.y + 0.05, head, 34.0)
	await _shot("face-3q")
	_place(30.0, 2.7, 0.95, mid, 38.0)
	await _shot("full-3q")
	_place(90.0, 2.6, 0.75, mid, 38.0)
	await _shot("profile")
	_place(150.0, 2.6, 1.0, mid, 38.0)
	await _shot("back-3q")
	_place(180.0, 1.5, 0.9, _player.global_position + Vector3(0, 0.55, 0), 38.0)
	await _shot("back-pack-close")
	# 3. readability at distance (typical play distances, lower and higher than the follow camera)
	_place(165.0, 7.5, 3.2, mid, 60.0)
	await _shot("far-behind-7m")
	_place(70.0, 14.0, 5.0, mid, 55.0)
	await _shot("far-side-14m")
	# 4. top hat variant (calls the player's own set_hat, like Game.hat_changed)
	if _player.has_method("set_hat"):
		_player.call("set_hat", "top_hat")
		await _wait(40)
		head = _head()
		_place(30.0, 1.5, head.y - _player.global_position.y + 0.1, head + Vector3(0, 0.08, 0), 36.0)
		await _shot("tophat-face-3q")
		_place(0.0, 2.7, 0.9, mid + Vector3(0, 0.1, 0), 38.0)
		await _shot("tophat-full-front")
		_place(165.0, 7.5, 3.2, mid, 60.0)
		await _shot("tophat-far-behind-7m")
	print("[CritHero] done ", _tag)
	get_tree().quit()

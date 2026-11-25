extends Node
## Director for CritHeroV2AppealR1. Survives the scene change on the root.
## Captures: gameplay camera (default hat), face front / 3q both sides, reference-matched full 3q (camera at Mak's front-left,
## slightly above, like references/owner_2026-10-18_mak_look.png), profile, back, an idle close-up time series (blinks, idle beats),
## then the same set with the beanie through the player's own set_hat().

var _out := ""
var _tag := "world"
var _settle := 420
var _walk_frames := 70
var _frame := 0
var _busy := false
var _player: Node3D = null
var _cam: Camera3D = null
var _gp: Camera3D = null
var _stamp := ""
var _sweep := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--walk="):
			_walk_frames = int(a.substr(7))
		elif a == "--sweep":
			_sweep = true
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


func _shot(caption: String, settle := 4) -> void:
	await _wait(settle)
	var img := get_viewport().get_texture().get_image()
	var path := _out.path_join("%s__r1-%s-%s.png" % [_stamp, _tag, caption])
	DirAccess.make_dir_recursive_absolute(_out)
	var err := img.save_png(path)
	print("[CritHeroV2] ", "saved " if err == OK else "FAILED ", path)


func _skel() -> Skeleton3D:
	for s in _player.find_children("*", "Skeleton3D", true, false):
		return s as Skeleton3D
	return null


func _head() -> Vector3:
	var skel := _skel()
	if skel != null and skel.find_bone("head") >= 0:
		var t := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("head"))
		return t.origin + Vector3(0, 0.2, 0)
	return _player.global_position + Vector3(0, 0.8, 0)


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


func _wear(hat: String) -> void:
	if _player.has_method("set_hat"):
		_player.call("set_hat", hat)
	await _wait(60)


func _closeups(prefix: String) -> void:
	var head := _head()
	var hy := head.y - _player.global_position.y
	var mid := _player.global_position + Vector3(0, 0.55, 0)
	_place(0.0, 1.7, hy, head, 34.0)
	await _shot(prefix + "-face-front")
	_place(32.0, 1.7, hy + 0.15, head, 34.0)
	await _shot(prefix + "-face-3q-a")
	_place(-32.0, 1.7, hy + 0.15, head, 34.0)
	await _shot(prefix + "-face-3q-b")
	_place(32.0, 2.6, 1.15, mid + Vector3(0, 0.05, 0), 36.0)
	await _shot(prefix + "-full-3q-a")
	_place(-32.0, 2.6, 1.15, mid + Vector3(0, 0.05, 0), 36.0)
	await _shot(prefix + "-full-3q-b")
	_place(90.0, 2.5, 0.7, mid, 36.0)
	await _shot(prefix + "-profile")
	_place(155.0, 2.5, 1.0, mid, 36.0)
	await _shot(prefix + "-back-3q")


func _run() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		print("[CritHeroV2] no player found")
		get_tree().quit()
		return
	print("[CritHeroV2] world=", _tag, " hat=", _player.get("hat"), " hero_v2=", _player.get("hero_v2"),
		" model=", _player.get("rigged_mesh_path"))
	await _shot("tophat-gameplay-spawn")
	_gp = get_viewport().get_camera_3d()
	if _gp != null:
		print("[CritHeroV2] gameplay cam dist=%.2f fov=%.1f" % [_gp.global_position.distance_to(_player.global_position), _gp.fov])
	_cam = Camera3D.new()
	_cam.name = "CritHeroV2Cam"
	get_tree().current_scene.add_child(_cam)
	var sk := _skel()
	if sk != null:
		var hb := sk.find_bone("head")
		var ht := sk.find_bone("head_top")
		print("[CritHeroV2] head bone y=%.3f head_top y=%.3f above feet (height ratio head/total ~ %.2f)" % [
			(sk.global_transform * sk.get_bone_global_pose(hb)).origin.y - _player.global_position.y,
			(sk.global_transform * sk.get_bone_global_pose(ht)).origin.y - _player.global_position.y,
			1.0 - ((sk.global_transform * sk.get_bone_global_pose(hb)).origin.y - _player.global_position.y) / maxf(0.01, (sk.global_transform * sk.get_bone_global_pose(ht)).origin.y - _player.global_position.y)])
	if _sweep:
		await _yaw_sweep()
		get_tree().quit()
		return
	await _closeups("tophat")
	# idle time series at the reference angle: blinks, breathing, idle beats (hat tip, hop, tilt)
	var head := _head()
	for i in 14:
		_place(28.0, 1.7, head.y - _player.global_position.y + 0.05, head + Vector3(0, -0.12, 0), 36.0)
		await _shot("tophat-idle-t%02d" % i, 40)
	await _wear("beanie")
	await _closeups("beanie")
	_place(28.0, 1.7, head.y - _player.global_position.y + 0.05, head + Vector3(0, -0.12, 0), 36.0)
	await _shot("beanie-idle-ref-angle", 30)
	await _wear("top_hat")
	await _gameplay_run("tophat")
	await _wear("beanie")
	await _gameplay_run("beanie")
	await _wear("top_hat")
	print("[CritHeroV2] done ", _tag)
	get_tree().quit()


func _gameplay_run(prefix: String) -> void:
	if _gp != null:
		_gp.make_current()
	await _wait(30)
	await _shot(prefix + "-gameplay-before-run")
	if InputMap.has_action("move_forward") and _walk_frames > 0:
		Input.action_press("move_forward", 1.0)
		await _wait(_walk_frames)
		await _shot(prefix + "-gameplay-running", 0)
		Input.action_release("move_forward")
		await _wait(50)
		await _shot(prefix + "-gameplay-stopped")


## Yaw sweep around the face at the reference elevation (both sides): at which 3/4 angle does the snout hide the far eye?
func _yaw_sweep() -> void:
	var head := _head()
	var hy := head.y - _player.global_position.y
	for deg in [-35, -25, -18, -10, 10, 18, 25, 35]:
		_place(float(deg), 2.0, hy + 0.25, head + Vector3(0, -0.15, 0), 34.0)
		await _shot("sweep-yaw%+03d" % deg, 6)

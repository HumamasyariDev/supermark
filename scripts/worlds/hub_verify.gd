class_name HubVerify
extends Node
## Hub fixer's verification helper (fix round 1, 2026-10-18 night 02). Added by hub_level only when one of its dev
## arguments is present, so it never exists in normal play. One Godot launch gives a whole set of evidence, which
## matters on the shared machine (two run slots, 4-5 GB per instance).
##
## Arguments (after --):
##   --hv-cams=StoryCam_A_v5,StoryCam_B,...  capture each story camera in turn (PNG, viewport size)
##   --hv-out=<abs dir>                      output folder; story cams go to <out>/<cam>/<stamp>.png
##   --hv-stamp=<UTC yyyymmddTHHMMSSZ>       file stamp (default: now)
##   --hv-wait=<s>                           seconds before the first story-cam capture (default 4)
##   --hv-shots=1.5,3,6                      gameplay-view shots at these times (seconds since the hub loaded)
##   --hv-tag=<label>                        file prefix for gameplay shots (<out>/<stamp>__<tag>_t006.0.png)
##   --hv-camlog                             log Mak, camera boom length, pitch and occlusion every 0.25 s
##   --hv-quit=<s>                           quit after this many seconds (default: after the last capture)
## Typical run: python tools/godot.py capture res://scenes/hub/Hub.tscn <out>/last.png --wait 20000 --hide-hud --
##   --profile=hubfix_r1 --hv-cams=StoryCam_B,StoryCam_C --hv-out=<abs> --hv-stamp=20261018T140000Z

var _cams: PackedStringArray = []
var _shots: Array[float] = []
var _out := ""
var _stamp := ""
var _tag := "shot"
var _wait := 4.0
var _quit := -1.0
var _camlog := false
var _t := 0.0
var _cam_i := 0
var _shot_i := 0
var _busy := false
var _log_t := 0.0
var _occluded := 0
var _samples := 0
var _min_boom := 99.0
var _seq := false


static func wanted(dev: Node) -> bool:
	if dev == null:
		return false
	for k in ["hv-cams", "hv-shots", "hv-camlog", "hv-probe-gap"]:
		if bool(dev.call("has_arg", k)):
			return true
	return false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dev := get_node_or_null("/root/Dev")
	var cams := String(dev.call("arg", "hv-cams", ""))
	if cams != "":
		_cams = cams.split(",", false)
	var shots := String(dev.call("arg", "hv-shots", ""))
	for s in shots.split(",", false):
		_shots.append(float(s))
	_out = String(dev.call("arg", "hv-out", OS.get_user_data_dir().path_join("hub_verify")))
	_stamp = String(dev.call("arg", "hv-stamp", ""))
	if _stamp == "":
		_stamp = Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "") + "Z"
	_tag = String(dev.call("arg", "hv-tag", "shot"))
	_wait = float(dev.call("arg", "hv-wait", "4"))
	_quit = float(dev.call("arg", "hv-quit", "-1"))
	_camlog = bool(dev.call("has_arg", "hv-camlog"))
	if bool(dev.call("has_arg", "hub-seq")):
		_seq = true
		var cur := String(HubAutopilot.seq_tests[HubAutopilot.seq_i]) if HubAutopilot.seq_loaded and HubAutopilot.seq_i < HubAutopilot.seq_tests.size() else String(dev.call("arg", "hub-seq", "")).get_slice(",", 0)
		_tag = "%s_%d_%s" % [_tag, HubAutopilot.seq_i, cur.replace("@", "-")]
	print("[HubVerify] cams=%s shots=%s out=%s" % [str(_cams), str(_shots), _out])
	if bool(dev.call("has_arg", "hv-probe-gap")):
		_probe_gap.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	if _camlog:
		_log_t += delta
		if _log_t >= 0.25:
			_log_t = 0.0
			_log_camera()
	if _busy:
		return
	if _shot_i < _shots.size() and _t >= _shots[_shot_i]:
		_busy = true
		_shot("%s/%s__%s_t%05.1f.png" % [_out, _stamp, _tag, _shots[_shot_i]])
		_shot_i += 1
		return
	if _cam_i < _cams.size() and _t >= _wait + float(_cam_i) * 1.2:
		_busy = true
		_story(_cams[_cam_i])
		_cam_i += 1
		return
	var done := _cam_i >= _cams.size() and _shot_i >= _shots.size()
	if _seq:
		return  # the autopilot sequence decides when the game ends
	if (_quit > 0.0 and _t >= _quit) or (_quit <= 0.0 and done and _t > _wait):
		if _camlog:
			print("[HubVerify] camlog summary: samples=%d occluded=%d min_boom=%.2f" % [_samples, _occluded, _min_boom])
		print("[HubVerify] done")
		get_tree().quit()


func _story(cam_name: String) -> void:
	var scene := get_tree().current_scene
	var cam := scene.find_child(cam_name, true, false) as Camera3D if scene else null
	if cam == null:
		print("[HubVerify] MISSING camera %s" % cam_name)
		_busy = false
		return
	cam.make_current()
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var path := "%s/%s/%s.png" % [_out, cam_name, _stamp]
	_save(path)
	_busy = false


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return  # the sequence reloaded the hub while this frame was pending
	_save(path)
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		var st := String(p.call("get_state_name")) if p.has_method("get_state_name") else "?"
		print("[HubVerify] shot %s mak=%s state=%s" % [path.get_file(), p.global_position, st])
	_busy = false


func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	print("[HubVerify] %s %s %s" % ["saved" if err == OK else "FAILED", path, img.get_size()])


func _log_camera() -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	if p == null or cam == null:
		return
	var chest := p.global_position + Vector3(0, 0.7, 0)
	var boom := cam.global_position.distance_to(chest)
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, chest, 1)
	q.exclude = [(p as CollisionObject3D).get_rid()] if p is CollisionObject3D else []
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	var occ := not hit.is_empty()
	# Fix r2 (QA major): the chandelier has no layer-1 collision, so the ray test never saw it fill the spiral
	# frames. Visual-occluder check: the camera-to-chest segment passing through the chandelier's volume (a
	# cylinder r 3.0 about the hall axis, y 8.4-12.6) counts as occluded ("occ=C").
	var vis_occ := false
	var a3 := cam.global_position
	for k in 9:
		var pt := a3.lerp(chest, float(k) / 9.0)
		if Vector2(pt.x, pt.z).length() < 3.0 and pt.y > 8.4 and pt.y < 12.6:
			vis_occ = true
	occ = occ or vis_occ
	var on_screen := not cam.is_position_behind(chest) and get_viewport().get_visible_rect().has_point(cam.unproject_position(chest))
	_samples += 1
	if occ or not on_screen:
		_occluded += 1
	_min_boom = minf(_min_boom, boom)
	var st := String(p.call("get_state_name")) if p.has_method("get_state_name") else "?"
	var r := Vector2(p.global_position.x, p.global_position.z).length()
	var th := fposmod(rad_to_deg(atan2(p.global_position.x, -p.global_position.z)), 360.0)
	print("[HubVerify] cam t=%.2f mak=(%.2f,%.2f,%.2f) r=%.2f th=%.1f state=%s cam=%s boom=%.2f pitch=%.0f occ=%s on=%s" % [
		_t, p.global_position.x, p.global_position.y, p.global_position.z, r, th, st, str(cam.name), boom,
		cam.global_rotation_degrees.x, ("C" if vis_occ else "Y") if occ else "n", "Y" if on_screen else "n"])


## Prints every walkable top between y 7.5 and 9.6 over the HUB-1 gap (theta 138-152, r 12.6-16.4) with its collider,
## so a stray ledge can be traced to its node.
func _probe_gap() -> void:
	for k in 5:
		await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var seen := {}
	var th := 138.0
	while th <= 152.0:
		var r := 12.6
		while r <= 16.4:
			var a := deg_to_rad(th)
			var x := sin(a) * r
			var z := -cos(a) * r
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 10.6, z), Vector3(x, 6.0, z), 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var pos: Vector3 = hit["position"]
				if pos.y > 7.5 and pos.y < 9.6:
					var col := hit["collider"] as Node
					var sname := ""
					if col is CollisionObject3D:
						var co := col as CollisionObject3D
						var owner_id := co.shape_find_owner(int(hit["shape"]))
						var own := co.shape_owner_get_owner(owner_id) as Node
						sname = String(own.name) if own else ""
					var key := "%s:%s|%.1f" % [str(col.get_path()) if col else "?", sname, snappedf(pos.y, 0.1)]
					if not seen.has(key):
						seen[key] = true
						print("[HubVerify] gap-top th=%.1f r=%.1f y=%.2f n=%s collider=%s shape=%d" % [th, r, pos.y, str(hit["normal"]), key, int(hit["shape"])])
			r += 0.2
		th += 0.5
	print("[HubVerify] gap probe done (%d distinct tops)" % seen.size())

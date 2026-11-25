extends Node3D
## Objects workstream verification probe: instances a real world scene and frames one of its objects with a camera
## (not gameplay). Lets the objects track check generated visuals and animations where the world builders placed them.
##   -- --world=res://scenes/hub/Hub.tscn --focus=Wolf_Door --off=0,2.2,7 --aim=0,1.8,0 [--call=open] [--call_at=60]
## --focus finds the first node with that name; --off is the camera offset in the node's local frame, --aim the look
## target (local). --call invokes a method on the node after --call_at physics frames. --fov sets the field of view.

var _target: Node3D
var _frames := 0
var _call := ""
var _call_at := 60


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.split("=", true, 1)[1]
	return d


func _v3(s: String, d: Vector3) -> Vector3:
	var p := s.split(",")
	if p.size() != 3:
		return d
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _ready() -> void:
	var path := _arg("world", "res://scenes/hub/Hub.tscn")
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("[WorldProbe] cannot load " + path)
		return
	var w := ps.instantiate()
	add_child(w)
	_call = _arg("call", "")
	_call_at = int(_arg("call_at", "60"))
	await get_tree().process_frame
	await get_tree().process_frame
	var focus := _arg("focus", "")
	# Builders place some objects late (deferred calls, timers): look for up to ~3 s before giving up.
	for _i in 180:
		_target = w.find_child(focus, true, false) as Node3D if focus != "" else null
		if _target != null or focus == "":
			break
		await get_tree().process_frame
	if _target == null:
		push_warning("[WorldProbe] focus not found: " + focus)
		return
	var cam := Camera3D.new()
	cam.name = "ProbeCam"
	cam.fov = float(_arg("fov", "50"))
	add_child(cam)
	var off := _v3(_arg("off", "0,2,6"), Vector3(0, 2, 6))
	var aim := _v3(_arg("aim", "0,1,0"), Vector3(0, 1, 0))
	var xf := _target.global_transform.orthonormalized()
	cam.global_position = xf * off
	cam.look_at(xf * aim, Vector3.UP)
	cam.make_current()
	print("[WorldProbe] focus ", _target.get_path(), " at ", _target.global_position, " cam ", cam.global_position)


func _process(_d: float) -> void:
	# World intros and the player camera grab "current"; the probe keeps its framing.
	var cam := get_node_or_null("ProbeCam") as Camera3D
	if cam != null and not cam.current:
		cam.make_current()


func _physics_process(_d: float) -> void:
	_frames += 1
	var watch := _arg("watch", "")
	if watch != "" and _target != null and _frames % 20 == 0:
		var wn := _target.get_node_or_null(watch) as Node3D
		if wn:
			print("[WorldProbe] f=%d %s scale=%s vis=%s t=%s" % [_frames, watch, wn.scale, wn.visible, _target.get("_t")])
	if _frames == _call_at and _target != null and _call != "" and _target.has_method(_call):
		print("[WorldProbe] call ", _call)
		_target.call(_call)

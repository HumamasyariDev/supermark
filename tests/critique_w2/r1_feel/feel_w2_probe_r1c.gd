extends "res://tests/critique_w2/r1_feel/feel_w2_probe.gd"
## W2 critique round 1 (feel lens), relaunch r1c (2026-10-18 evening). Read-only. Adds to the r1 probe:
## a second log (--extra-out=<abs jsonl>) per rendered frame with the floor body, inherited platform velocity,
## the Giant's bell angle and plate centre, and, when another camera is current (seed descent, BONG cut), whether
## that camera is inside geometry or has Mak occluded. --ride-bell=<pf>: at that physics frame, wait until the
## bell is within 2 degrees of its east extreme and place Mak on the crown plate (stick neutral).

var _extra: FileAccess
var _ride_pf := -1
var _rode := false


func _ready() -> void:
	super._ready()
	var dev := get_tree().root.get_node_or_null("Dev")
	if dev != null:
		var p := str(dev.call("arg", "extra-out", ""))
		if p != "":
			DirAccess.make_dir_recursive_absolute(p.get_base_dir())
			_extra = FileAccess.open(p, FileAccess.WRITE)
		_ride_pf = int(str(dev.call("arg", "ride-bell", "-1")))


func _process(delta: float) -> void:
	super._process(delta)
	if _player == null or _cam == null:
		return
	var pf := int(_player.get("physics_frame"))
	var life := get_tree().root.find_child("W2Life", true, false)
	var bell: Node3D = life.get("bell") if life != null else null
	var ang := float(life.get("bell_angle")) if life != null else 0.0
	if _ride_pf > 0 and not _rode and pf >= _ride_pf and bell != null and rad_to_deg(ang) > 23.0:
		_rode = true
		var top := bell.global_transform * Vector3(0, -3.0, 0)
		_player.global_position = top + Vector3(0, 0.15, 0)
		if "velocity" in _player:
			_player.set("velocity", Vector3.ZERO)
		print("[FeelW2c] placed on bell plate at ", top, " angle ", rad_to_deg(ang))
	if _extra == null:
		return
	var fc: Variant = _player.get("floor_collider")
	var active := get_viewport().get_camera_3d()
	var row := {"pf": pf, "floor": (str((fc as Node).name) if fc is Node else ""),
		"plat_v": _v(_player.get("last_platform_vel") as Vector3, 0.01),
		"ext_v": _v(_player.get("ext_vel") as Vector3, 0.01),
		"bell_deg": snappedf(rad_to_deg(ang), 0.01)}
	if bell != null:
		row["plate"] = _v(bell.global_transform * Vector3(0, -3.0, 0), 0.01)
	if active != null and active != _cam:
		var pp := _player.global_position + Vector3.UP * 0.6
		var q := PhysicsShapeQueryParameters3D.new()
		var s := SphereShape3D.new()
		s.radius = 0.12
		q.shape = s
		q.transform = Transform3D(Basis.IDENTITY, active.global_position)
		q.collision_mask = 1
		var sp := active.get_world_3d().direct_space_state
		row["other_cam"] = {"name": str(active.name), "p": _v(active.global_position, 0.01),
			"inside": not sp.intersect_shape(q, 1).is_empty(),
			"occ": not sp.intersect_ray(PhysicsRayQueryParameters3D.create(active.global_position, pp, 1, _excl())).is_empty(),
			"dist": snappedf(active.global_position.distance_to(pp), 0.01)}
	_extra.store_line(JSON.stringify(row))


func _exit_tree() -> void:
	super._exit_tree()
	if _extra != null:
		_extra.flush()
		_extra.close()
		_extra = null

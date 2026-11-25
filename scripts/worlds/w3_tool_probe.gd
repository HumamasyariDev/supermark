extends SceneTree
## Dev tool: loads W3, then lists every collider that a 0.35 m sphere touches at a few probe points
## (used to find what blocked the W3-3 bot on the islet's north-east rim).
## Run: python tools/godot.py script res://scripts/worlds/w3_tool_probe.gd

const POINTS := [Vector3(22.3, 2.1, 7.85), Vector3(22.6, 2.1, 7.7), Vector3(22.9, 2.1, 7.5), Vector3(22.3, 2.5, 7.85)]
var _w: Node
var _f := 0


func _init() -> void:
	_w = (load("res://scenes/worlds/w3/W3.tscn") as PackedScene).instantiate()
	root.add_child(_w)


func _physics_process(_d: float) -> bool:
	_f += 1
	if _f < 8:
		return false
	var space := (_w as Node3D).get_world_3d().direct_space_state
	var sh := SphereShape3D.new()
	sh.radius = 0.35
	for p in POINTS:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sh
		q.transform = Transform3D(Basis(), p)
		q.collision_mask = 0xFFFFFFFF
		q.collide_with_areas = false
		var hits := space.intersect_shape(q, 16)
		var names := []
		for h in hits:
			var c: Object = h["collider"]
			names.append("%s (%s)" % [(c as Node).get_path() if c is Node else str(c), c.get_class()])
		print("[probe] %s -> %s" % [p, names])
	quit()
	return true

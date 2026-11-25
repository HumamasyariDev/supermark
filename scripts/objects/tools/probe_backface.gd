extends SceneTree
## Objects tool: how does the physics engine report a ray that starts inside a concave (trimesh) box?

var _n := 0
var _body: StaticBody3D


func _init() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4, 2, 4)
	cs.shape = bm.create_trimesh_shape()
	_body.add_child(cs)
	root3d.add_child(_body)
	physics_frame.connect(_tick)


func _tick() -> void:
	_n += 1
	if _n < 10:
		return
	var space := _body.get_world_3d().direct_space_state
	for bf in [false, true]:
		for dir in [Vector3.UP, Vector3.DOWN]:
			var q := PhysicsRayQueryParameters3D.create(Vector3(0.3, 0.2, 0.1), Vector3(0.3, 0.2, 0.1) + dir * 5.0)
			print("front from outside: ", space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.3, 4, 0.1), Vector3(0.3, -4, 0.1))).get("normal"))
			q.hit_back_faces = bf
			q.hit_from_inside = true
			var r := space.intersect_ray(q)
			print("backfaces=", bf, " dir=", dir, " hit=", r.get("position"), " normal=", r.get("normal"), " face=", r.get("face_index"))
	var q2 := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.2
	q2.shape = sh
	q2.transform = Transform3D(Basis(), Vector3(0.3, 0.2, 0.1))
	print("sphere overlap inside trimesh: ", space.intersect_shape(q2, 1).size())
	quit()

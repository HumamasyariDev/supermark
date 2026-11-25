class_name FxRibbonUtil
extends RefCounted
## Builds camera-facing ribbon strips into an ImmediateMesh (world space).
## UV.x runs 0..1 along the ribbon, UV.y 0..1 across it.


static func draw(im: ImmediateMesh, pts: PackedVector3Array, width: float, cam_pos: Vector3, taper := true) -> void:
	var n := pts.size()
	if n < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var p := pts[i]
		var tangent: Vector3
		if i == 0:
			tangent = pts[1] - pts[0]
		elif i == n - 1:
			tangent = pts[n - 1] - pts[n - 2]
		else:
			tangent = pts[i + 1] - pts[i - 1]
		var to_cam := (cam_pos - p).normalized()
		var side := tangent.cross(to_cam)
		if side.length_squared() < 0.000001:
			side = Vector3.UP
		side = side.normalized()
		var t := float(i) / float(n - 1)
		var w := width * (sin(t * PI) * 0.7 + 0.3 if taper else 1.0)
		im.surface_set_uv(Vector2(t, 0.0))
		im.surface_set_normal(to_cam)
		im.surface_add_vertex(p - side * w * 0.5)
		im.surface_set_uv(Vector2(t, 1.0))
		im.surface_set_normal(to_cam)
		im.surface_add_vertex(p + side * w * 0.5)
	im.surface_end()


static func bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3


static func camera_position(node: Node3D) -> Vector3:
	var vp := node.get_viewport()
	if vp == null:
		return Vector3.ZERO
	var cam := vp.get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO

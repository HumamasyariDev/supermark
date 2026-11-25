extends Node3D
## W1 dev review scene: lines up the W1 generated props for a look (front and side). Not part of the level.

func _ready() -> void:
	var names: Array[String] = ["straw_house", "stick_house", "brick_house", "brick_chimney_shaft", "windmill_body", "windmill_sails", "stone_bridge", "wishing_well", "bellows_machine", "apple_tree", "birch_tree", "hay_bale", "signpost"]
	var side := Dev.has_arg("side") if get_node_or_null("/root/Dev") else false
	var x := 0.0
	for n in names:
		var holder := Node3D.new()
		add_child(holder)
		var v := W1Kit.glb_visual(holder, [n], -1.0, -1.0)
		var a := W1Kit._aabb(holder, Transform3D.IDENTITY)
		holder.position = Vector3(x - a.position.x, 0, 0)
		if side:
			holder.rotation_degrees.y = 90.0
		x += maxf(a.size.x, a.size.z) + 2.0
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.7, 0.8, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	we.environment = e
	add_child(we)
	var cam := Camera3D.new()
	cam.name = "StoryCam_A"
	add_child(cam)
	cam.position = Vector3(x * 0.5, 9, 48)
	cam.look_at(Vector3(x * 0.5, 5, 0))
	cam.fov = 60
	cam.current = true

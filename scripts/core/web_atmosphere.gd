extends Node3D
## Compatibility approximation of local scattering, using the native hall's
## bounds and light directions. Depth fades prevent hard cards through geometry.
var _beams: Array = []
var _haze: MeshInstance3D
var _ending_light: Light3D

func setup(scene: Node, world: String) -> void:
	if world == "HUB":
		_haze = MeshInstance3D.new()
		_haze.mesh = QuadMesh.new()
		_haze.mesh.size = Vector2(2,2)
		_haze.extra_cull_margin = 16384.0
		_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = load("res://assets/shaders/web_hall_haze.gdshader")
		material.render_priority = 90
		_haze.material_override = material
		add_child(_haze)
		for z: float in [-5.0, 3.0]:
			_beam(Vector3(-14.5,9.5,z), Vector3(13.0,2.4,z-7.0), 1.4, 2.8, Color("ffe2b8"), 0.026)
		_beam(Vector3(0,13.5,-15.2),Vector3(0,0.5,-2),0.7,3.0,Color("e9b7ff"),0.018)
	elif world == "BOSS":
		_ending_light = scene.find_child("LT_shaft",true,false) as Light3D
		for x: float in [-9.0,9.0]:
			_beam(Vector3(x,22,-14),Vector3(x-6,0,0),1.4,4.0,Color("ffc86b"),0.025)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _beam(start: Vector3, end: Vector3, narrow: float, wide: float, color: Color, strength: float) -> void:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var length := start.distance_to(end)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-narrow,0,0),Vector3(narrow,0,0),Vector3(wide,length,0),Vector3(-wide,length,0)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/web_light_shaft.gdshader")
	material.set_shader_parameter("color",color)
	material.set_shader_parameter("strength",strength)
	material.render_priority = 80
	node.material_override = material
	add_child(node)
	node.global_position = start
	_beams.append({"node":node,"axis":(end-start).normalized(),"material":material,"strength":strength})

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if _haze:
		_haze.global_position = camera.global_position
	for beam: Dictionary in _beams:
		var node: MeshInstance3D = beam["node"]
		var axis: Vector3 = beam["axis"]
		var side := axis.cross(camera.global_position-node.global_position).normalized()
		if side.length_squared() > 0.1:
			node.global_basis = Basis(side,axis,side.cross(axis))
		if _ending_light:
			beam["material"].set_shader_parameter("strength",beam["strength"] * _ending_light.light_energy / 2.6)

extends Node3D
## WebGL draw-call reduction with the original scene graph left in control.
## Only repeated, opaque, unskinned, unscripted visual leaves are eligible.
## No collisions, gameplay nodes, materials or authored transforms are replaced.

const Source := preload("res://scripts/core/web_batch_source.gd")
const CELL := 24.0
var _groups: Array[Dictionary] = []
var _sources: Array[Dictionary] = []
## Round 4: only these sources follow the camera (visibility ranges); the rest never change on their own.
var _range_sources: Array[Dictionary] = []
var _mesh_keys: Dictionary = {}
var _material_keys: Dictionary = {}
var _last_camera := Vector3(INF, INF, INF)
var _disabled := false
var _stamp: Array = []


func build(scene: Node) -> void:
	name = "WebDrawBatches"
	# Source transforms below already include their own interpolation. Applying
	# MultiMesh physics interpolation again both lags them and uploads twice.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var candidates: Dictionary = {}
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if _actor_visual(mi):
			continue
		if mi.mesh == null or mi.get_script() != null or mi.skin != null or mi.get_blend_shape_count() > 0:
			continue
		if mi.material_overlay != null or mi.layers == 0 or mi.global_basis.determinant() < 0.0:
			continue
		var mats: Array[Material] = []
		var key := _mesh_key(mi.mesh)
		var valid := true
		for surface in mi.mesh.get_surface_count():
			var material := mi.get_active_material(surface)
			var material_key := _material_key(material)
			if material_key.is_empty():
				valid = false
				break
			key += "|" + material_key
			mats.append(material)
		if not valid:
			continue
		var cell := (mi.global_position / CELL).floor()
		key += "|%s|%s|%s" % [cell, mi.layers, mi.cast_shadow]
		if not candidates.has(key):
			candidates[key] = {"mesh": mi.mesh, "materials": mats, "nodes": [], "layers": mi.layers,
				"shadow": mi.cast_shadow}
		candidates[key]["nodes"].append(mi)
	var count := 0
	for candidate: Dictionary in candidates.values():
		var nodes: Array = candidate["nodes"]
		if nodes.size() < 2:
			continue
		var mesh: Mesh = candidate["mesh"].duplicate()
		for surface in mesh.get_surface_count():
			if mesh is ArrayMesh:
				mesh.surface_set_material(surface, candidate["materials"][surface])
			elif mesh is PrimitiveMesh:
				mesh.material = candidate["materials"][surface]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = nodes.size()
		var batch := MultiMeshInstance3D.new()
		batch.set_meta("web_batch", true)
		batch.multimesh = multimesh
		batch.layers = candidate["layers"]
		batch.cast_shadow = candidate["shadow"]
		add_child(batch)
		var group := {"multimesh": multimesh, "node": batch}
		_groups.append(group)
		for index in nodes.size():
			var mi := nodes[index] as MeshInstance3D
			var record := {"node": weakref(mi), "layers": mi.layers, "group": group, "index": index,
				"range_begin": mi.visibility_range_begin, "range_end": mi.visibility_range_end}
			_sources.append(record)
			if record["range_begin"] > 0.0 or record["range_end"] > 0.0:
				_range_sources.append(record)
			mi.layers = 0
			mi.set_script(Source)
			mi.call("observe", self, group, index)
			count += 1
	_stamp = render_stamp()
	Game.settings_changed.connect(_on_settings_changed)
	print("[WebBatches] %d meshes in %d batches" % [count, _groups.size()])


## Round 4: the settings that change materials or shadow casting. Volume, camera and control changes used to
## dissolve every batch for the rest of the visit (several times the draw calls after touching the pause menu).
static func render_stamp() -> Array:
	return [Game.get_setting("classic_textures", true), Game.get_setting("soft_shadows", true), Game.low_graphics()]


func _on_settings_changed() -> void:
	if render_stamp() != _stamp:
		disable()


func _actor_visual(node: Node) -> bool:
	var current := node
	while current != null:
		# Acorn visuals are rigid meshes. The original pickup still animates,
		# attracts, collides and collects; the observer follows its transform.
		if current.is_in_group("acorn"):
			return false
		for role in ["player", "enemy", "boss", "npc", "talker", "pickup", "collectible", "truffle", "acorn", "lost_page", "hazard"]:
			if current.is_in_group(role):
				return true
		current = current.get_parent()
	return false


func _mesh_key(mesh: Mesh) -> String:
	var id := mesh.get_instance_id()
	if _mesh_keys.has(id):
		return _mesh_keys[id]
	var key := str(mesh.get_rid())
	if mesh is PrimitiveMesh:
		var values: Array = [mesh.get_class()]
		for property in mesh.get_property_list():
			if int(property["usage"]) & PROPERTY_USAGE_STORAGE and not String(property["name"]).begins_with("resource_"):
				var value: Variant = mesh.get(property["name"])
				if not value is Object and property["name"] != "material":
					values.append([property["name"], value])
		key = str(values)
	_mesh_keys[id] = key
	return key


func _material_key(material: Material, next_pass: bool = false) -> String:
	if material == null:
		return ""
	var id := "%s:%s" % [material.get_instance_id(), next_pass]
	if _material_keys.has(id):
		return _material_keys[id]
	var values: Array = [material.get_class(), material.render_priority]
	if material is ShaderMaterial:
		var shader: Shader = material.shader
		if shader == null or (not next_pass and shader.code.contains("ALPHA")) or shader.code.contains("instance uniform") or shader.code.contains("INSTANCE_ID"):
			return ""
		values.append(shader.code.sha256_text())
		for uniform in shader.get_shader_uniform_list():
			values.append([uniform["name"], material.get_shader_parameter(uniform["name"])])
	elif material is BaseMaterial3D:
		# Acorn contact shadows all blend black over the ground. Their alpha
		# multiplication commutes, so batching does not change transparent order.
		var black_shadow: bool = material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
			and material.albedo_color.r == 0.0 and material.albedo_color.g == 0.0 and material.albedo_color.b == 0.0 \
			and not material.emission_enabled and not material.vertex_color_use_as_albedo
		if (material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and not black_shadow) or material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
			return ""
		for property in material.get_property_list():
			var property_name := String(property["name"])
			if int(property["usage"]) & PROPERTY_USAGE_STORAGE and not property_name.begins_with("resource_") and property_name != "next_pass":
				values.append([property_name, material.get(property_name)])
	else:
		return ""
	if material.next_pass:
		var following := _material_key(material.next_pass, true)
		if following.is_empty():
			return ""
		values.append(following)
	var key := str(values).sha256_text()
	_material_keys[id] = key
	return key


func update_instance(source: MeshInstance3D, group: Dictionary, index: int) -> void:
	if _disabled or not is_instance_valid(group["node"]):
		return
	var shown := source.is_visible_in_tree()
	var camera := get_viewport().get_camera_3d()
	if shown and camera and (source.visibility_range_begin > 0.0 or source.visibility_range_end > 0.0):
		var distance := camera.global_position.distance_to(source.global_position)
		shown = distance >= source.visibility_range_begin and (source.visibility_range_end <= 0.0 or distance <= source.visibility_range_end)
	if shown:
		var transform := source.global_transform
		if source.is_physics_interpolated_and_enabled():
			transform = source.get_global_transform_interpolated()
		group["multimesh"].set_instance_transform(index, transform)
	else:
		hide_instance(group, index)


func hide_instance(group: Dictionary, index: int) -> void:
	if index >= 0 and is_instance_valid(group.get("node")):
		group["multimesh"].set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


func _process(_delta: float) -> void:
	if _disabled:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_squared_to(_last_camera) < 0.01:
		return
	_last_camera = camera.global_position
	for record in _range_sources:
		var source: MeshInstance3D = record["node"].get_ref()
		if source:
			update_instance(source, record["group"], record["index"])


func disable() -> void:
	if _disabled:
		return
	_disabled = true
	for record in _sources:
		var source: MeshInstance3D = record["node"].get_ref()
		if source:
			source.layers = record["layers"]
			source.call("stop_observing")
			source.set_script(null)
	for group in _groups:
		if is_instance_valid(group["node"]):
			group["node"].queue_free()
	set_process(false)

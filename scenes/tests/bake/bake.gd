extends Node
## Read-only runtime extraction. All changes are confined to this test scene.

const SCENES = {"W1": "res://scenes/worlds/w1/W1.tscn", "HUB": "res://scenes/hub/Hub.tscn",
	"W2": "res://scenes/worlds/w2/W2.tscn", "W3": "res://scenes/worlds/w3/W3.tscn",
	"BOSS": "res://scenes/boss/WolfRooftop.tscn"}
var out_dir = ""
var area_id = ""
var world: Node
var materials = {}
var converted = {}
var textures = {}
var geometry = {}
var mesh_keys = {}
var geometries = []
var collisions = []
var entities = []
var volumes = []
var markers = []
var cameras = []
var lights = []
var labels = []
var special = []
var entity_ids = {}
var entity_nodes = {}
var dynamic_roots = {}
var shaders = {}
var env = {}
var initial = {}
var frame_count = 0
var freeze_info = {}
var characters = []

func argument(key: String, fallback: String = "") -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + key + "="):
			return arg.substr(key.length() + 3)
	return fallback

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() != "headless":
		get_window().position = Vector2i(-32000, -32000)
		get_window().size = Vector2i(1280, 720)
	_run.call_deferred()

func _run() -> void:
	out_dir = argument("bake-out")
	area_id = argument("bake-area", "MAK")
	assert(not out_dir.is_empty(), "Pass --bake-out=<absolute directory>")
	get_tree().node_added.connect(_added)
	var sequence = [area_id]
	if argument("bake-sequence") != "":
		sequence = Array(argument("bake-sequence").split(","))
	elif area_id == "MAK" and argument("bake-single") != "yes":
		sequence = ["MAK", "W1", "HUB", "W2", "W3", "BOSS"]
	for area in sequence:
		area_id = area
		await _bake_one()
		get_tree().current_scene = null
		world.free()
		world = null
		materials.clear()
		converted.clear()
		textures.clear()
		geometry.clear()
		mesh_keys.clear()
		geometries.clear()
		collisions.clear()
		entities.clear()
		volumes.clear()
		markers.clear()
		cameras.clear()
		lights.clear()
		labels.clear()
		special.clear()
		entity_ids.clear()
		entity_nodes.clear()
		dynamic_roots.clear()
		shaders.clear()
		initial.clear()
		characters.clear()
		env.clear()
		get_tree().paused = false
		await get_tree().process_frame
	get_tree().quit()

func _bake_one() -> void:
	for folder in ["characters", "models", "textures", "_raw/" + area_id]:
		DirAccess.make_dir_recursive_absolute(out_dir.path_join(folder))
	seed(1863)
	Engine.max_fps = 60
	PhysicsServer3D.set_active(false)
	if area_id == "MAK":
		world = load("res://scenes/player/Player.tscn").instantiate()
	else:
		world = load(SCENES[area_id]).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	var stable = 0
	var previous = -1
	for frame in range(600):
		await get_tree().process_frame
		frame_count = frame + 1
		_disable_physics(world)
		var count = get_tree().get_node_count()
		stable = stable + 1 if count == previous else 0
		previous = count
		var retro = get_node_or_null("/root/RetroLook")
		var pending = 0
		if retro:
			for key in ["_pending", "_async_groups"]:
				var values = retro.get(key)
				if values is Array:
					pending += values.size()
		if frame >= 120 and stable >= 45 and pending == 0:
			break
	freeze_info = {"frames": frame_count, "stable_node_frames": stable,
		"physics_active": false, "nodes": get_tree().get_node_count(), "seed": 1863}
	var retro = get_node_or_null("/root/RetroLook")
	if retro:
		retro.apply_to(world)
		freeze_info["retro_stats"] = safe(retro.last_stats)
	get_tree().paused = true
	print("[BAKE] settled ", area_id, " ", freeze_info)
	if argument("bake-repair-textures") == "yes":
		if not FileAccess.file_exists(out_dir.path_join("_raw/" + area_id + "/texture_repairs.json")):
			_repair_textures()
		if area_id == "MAK":
			for part in ["top_hat", "beanie", "pack"]:
				if FileAccess.file_exists(out_dir.path_join("characters/mak_" + part + ".glb")):
					continue
				var source = world.get_node("Visual").find_child("Part_" + part, true, false)
				if source:
					_export_character(source, "mak_" + part, true)
			write_json("characters/mak_parts_materials.json", materials)
	if argument("bake-capture-only") == "yes":
		if area_id != "MAK" and not FileAccess.file_exists(out_dir.path_join("_raw/" + area_id + "/instance_repairs.json")):
			_repair_instances()
		if not FileAccess.file_exists(argument("bake-capture").path_join(area_id + "_godot.webp")):
			await _capture()
		return
	if area_id == "MAK":
		var visual = world.get_node("Visual")
		_export_character(visual, "mak", true)
		for part in ["top_hat", "beanie", "pack"]:
			var source = visual.find_child("Part_" + part, true, false)
			if source:
				_export_character(source, "mak_" + part, true)
		write_json("characters/mak_materials.json", materials)
	else:
		_catalog(world)
		_export_scene_characters()
		_walk(world, "")
		write_json("_raw/" + area_id + "/geometry.json", geometry)
		var inventory = {"schema_version": 1, "area": area_id, "source_scene": SCENES[area_id],
			"freeze": freeze_info, "materials": materials, "geometries": geometries, "colliders": collisions,
			"entities": entities, "volumes": volumes, "spawns": markers, "story_cameras": cameras,
			"environment": env, "lights": lights, "labels": labels, "special_nodes": special,
			"world_props": script_props(world), "shader_inventory": shaders, "characters": characters}
		write_json("_raw/" + area_id + "/inventory.json", inventory)
		print("[BAKE] inventory: ", geometries.size(), " visuals, ", collisions.size(), " colliders, ", entities.size(), " entities")
	if argument("bake-capture") != "" and DisplayServer.get_name() != "headless":
		await _capture()
	print("[BAKE] COMPLETE ", area_id)

func _added(n: Node) -> void:
	if n is Node3D:
		initial[n.get_instance_id()] = n.transform
	n.set_physics_process(false)

func _disable_physics(n: Node) -> void:
	n.set_physics_process(false)
	if n is RigidBody3D:
		n.freeze = true
	if n.is_in_group("player"):
		n.set_process(false)
		var anim = n.get_node_or_null("Animator")
		if anim:
			anim.set_process(false)
	for child in n.get_children():
		_disable_physics(child)

func _capture() -> void:
	var base = argument("bake-capture")
	DirAccess.make_dir_recursive_absolute(base)
	if area_id == "MAK":
		return
	var ui = get_node_or_null("/root/UI")
	if ui:
		for layer in ui.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
	var selected = argument("bake-camera", "StoryCam_A")
	for cam in world.find_children("*", "Camera3D", true, false):
		if cam.name != selected:
			continue
		cam.current = true
		# An off-screen Windows window can suppress the normal post-draw signal.
		# Explicit draws preserve the native renderer without showing a window.
		RenderingServer.viewport_set_update_mode(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
		for frame in range(4):
			await get_tree().process_frame
			RenderingServer.force_draw(false, 1.0 / 60.0)
		var img = get_viewport().get_texture().get_image()
		img.save_webp(base.path_join(area_id + "_godot.webp"), false, 0.95)
		write_json("_raw/" + area_id + "/capture_camera.json", camera_spec(cam))
		break

func _canonical_path(value: String) -> String:
	var pattern = RegEx.new()
	pattern.compile("@[A-Za-z0-9_]+@[0-9]+")
	return pattern.sub(value, "@Generated", true)

func _repair_instances() -> void:
	var records = []
	for n in world.find_children("*", "MultiMeshInstance3D", true, false):
		var mm = n.multimesh
		if not mm or not mm.mesh:
			continue
		var signatures = []
		for surface in mm.mesh.get_surface_count():
			var arrays = mm.mesh.surface_get_arrays(surface)
			signatures.append(arrays[Mesh.ARRAY_VERTEX].to_byte_array().hex_encode().sha256_text())
		var mids = []
		for mat in _live_materials(n):
			mids.append(material_id(mat))
		var instances = []
		var count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		for i in count:
			var record = transform_spec(n.global_transform * mm.get_instance_transform(i))
			record["color"] = safe(mm.get_instance_color(i)) if mm.use_colors else [1, 1, 1, 1]
			if mm.use_custom_data:
				record["instance_custom"] = safe(mm.get_instance_custom_data(i))
			instances.append(record)
		records.append({"id": path_of(n), "signatures": signatures, "materials": mids, "instances": instances})
	write_json("_raw/" + area_id + "/instance_repairs.json", {"nodes": records, "materials": materials})
	print("[BAKE] native MultiMesh placement recovery: ", records.size(), " nodes")

func _live_materials(n: Node) -> Array:
	var result = []
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			result.append(n.get_active_material(i))
	elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh:
		for i in n.multimesh.mesh.get_surface_count():
			result.append(n.material_override if n.material_override else n.multimesh.mesh.surface_get_material(i))
	elif n is CSGShape3D and n.is_root_shape():
		var meshes = n.get_meshes()
		if meshes.size() > 1:
			for i in meshes[1].get_surface_count():
				result.append(n.material_override if n.material_override else meshes[1].surface_get_material(i))
	return result

func _repair_textures() -> void:
	# A real renderer can read ImageTextures created by RetroLook; the headless
	# renderer cannot. Match captured node/surface identities, retaining geometry.
	var old = {}
	var visuals = []
	if area_id == "MAK":
		old = JSON.parse_string(FileAccess.get_file_as_string(out_dir.path_join("characters/mak_materials.json")))
		visuals = JSON.parse_string(FileAccess.get_file_as_string(out_dir.path_join("_raw/MAK/material_nodes.json")))
	else:
		var inventory = JSON.parse_string(FileAccess.get_file_as_string(out_dir.path_join("_raw/" + area_id + "/material_nodes.json")))
		old = inventory["materials"]
		visuals = inventory["geometries"]
	var live = {}
	var named = {}
	for n in world.find_children("*", "Node3D", true, false):
		var mats = _live_materials(n)
		if mats.is_empty():
			continue
		live[path_of(n)] = mats
		if not live.has(_canonical_path(path_of(n))):
			live[_canonical_path(path_of(n))] = mats
		for mat in mats:
			if mat and (mat.resource_path != "" or mat.resource_name != ""):
				named[mat.resource_path + "|" + mat.resource_name] = mat
	var matched = {}
	for record in visuals:
		var mats = live.get(record["id"], live.get(_canonical_path(record["id"]), []))
		for i in mini(mats.size(), record["materials"].size()):
			var mid = record["materials"][i]
			if mats[i] and not matched.has(mid):
				matched[mid] = mats[i]
	# Next-pass materials have no independent mesh node but must retain textures too.
	for mid in matched.keys():
		var pass_id = mid
		var pass_mat = matched[mid]
		while old.has(pass_id) and old[pass_id].has("next_pass") and pass_mat.next_pass:
			pass_id = old[pass_id]["next_pass"]
			pass_mat = pass_mat.next_pass
			if matched.has(pass_id):
				break
			matched[pass_id] = pass_mat
	var patches = {}
	var unmatched = []
	for mid in old:
		var mat = matched.get(mid)
		if mat == null:
			mat = named.get(old[mid].get("source", "") + "|" + old[mid].get("name", ""))
		if mat == null:
			unmatched.append(mid)
			continue
		var current = material_id(mat)
		patches[mid] = materials[current]
	write_json("_raw/" + area_id + "/texture_repairs.json", {"materials": patches, "unmatched": unmatched,
		"source": "Native renderer; node path and surface identity, with material resource/name fallback."})
	print("[BAKE] texture repair ", area_id, ": ", patches.size(), " mapped, ", unmatched.size(), " unmatched")

func path_of(n: Node) -> String:
	return str(world.get_path_to(n))

func node_script(n: Node) -> String:
	var script = n.get_script()
	return script.resource_path if script else ""

func _catalog(n: Node) -> void:
	if n != world and n.is_in_group("player"):
		return
	var script = node_script(n)
	var live = script != "" or n is AnimatableBody3D or n is PathFollow3D or n is AnimationPlayer or n is GPUParticles3D or n is CPUParticles3D
	if live:
		entity_ids[n.get_instance_id()] = path_of(n)
		entity_nodes[path_of(n)] = n
		var dynamic = n is CharacterBody3D or n is AnimatableBody3D or n is PathFollow3D
		if script.contains("/objects/"):
			dynamic = true
		if script.contains("/enemies/") or script.contains("/boss/"):
			dynamic = n != world
		var type_name = script.get_file().get_basename()
		if type_name in ["w1_sheep", "w2_goose_wolf", "hub_clock", "hub_drum_art", "hub_spiral", "w3_witch", "w3_cookie", "w3_cook", "w3_cauldron", "w2_bell", "npc_life", "npc_talker"]:
			dynamic = true
		if dynamic and n is Node3D:
			dynamic_roots[n.get_instance_id()] = true
	for child in n.get_children():
		_catalog(child)

func _export_scene_characters() -> void:
	var done = {}
	var candidates = world.find_children("*", "Skeleton3D", true, false)
	for n in world.find_children("*", "Node3D", true, false):
		if n.scene_file_path.ends_with(".glb") and (n.scene_file_path.contains("/characters/") or n.scene_file_path.contains("/enemies/")):
			candidates.append(n)
	for skeleton in candidates:
		if path_of(skeleton).begins_with("Player/"):
			continue
		var source = skeleton as Node3D
		var cursor = skeleton.get_parent()
		while not source.scene_file_path.ends_with(".glb") and cursor != world and cursor is Node3D:
			if cursor.scene_file_path.ends_with(".glb") or cursor.scene_file_path.ends_with(".gltf"):
				source = cursor
				break
			cursor = cursor.get_parent()
		if done.has(source.get_instance_id()):
			continue
		done[source.get_instance_id()] = true
		var name_part = source.scene_file_path.get_file().get_basename().to_snake_case()
		if name_part == "":
			name_part = str(source.name).to_snake_case()
		var char_id = name_part + "_" + area_id.to_lower() + "_" + str(characters.size())
		_export_character(source, char_id, true)
		var record = base_spec(source)
		record["model"] = "characters/" + char_id + ".glb"
		characters.append(record)

func _walk(n: Node, owner_id: String) -> void:
	if n != world and n.is_in_group("player"):
		return
	var id = n.get_instance_id()
	var own = owner_id
	if dynamic_roots.has(id) and owner_id == "":
		own = path_of(n)
	if entity_ids.has(id):
		var e = base_spec(n)
		e["type"] = node_script(n).get_file().get_basename() if node_script(n) != "" else n.get_class().to_snake_case()
		e["script"] = node_script(n)
		e["props"] = script_props(n)
		e["children"] = []
		for child in n.get_children():
			e["children"].append(path_of(child))
		e["visual_owner"] = own
		e["dynamic"] = dynamic_roots.has(id)
		if n is AnimationPlayer:
			e["animations"] = animation_spec(n)
		if n is GPUParticles3D or n is CPUParticles3D:
			e["particle_settings"] = stored_props(n)
		entities.append(e)
	if n is Camera3D and not path_of(n).contains("Player"):
		cameras.append(camera_spec(n))
	if n is Marker3D and path_of(n).begins_with("Spawns"):
		markers.append(base_spec(n))
	if n is WorldEnvironment and n.environment:
		env = stored_props(n.environment)
		if n.environment.sky:
			env["sky"] = stored_props(n.environment.sky)
			if n.environment.sky.sky_material:
				env["sky_material"] = material_id(n.environment.sky.sky_material)
	if n is Light3D:
		var light = base_spec(n)
		light["props"] = stored_props(n)
		lights.append(light)
	if n is Label3D:
		var label = base_spec(n)
		label["props"] = stored_props(n)
		labels.append(label)
	if n is Decal or n is FogVolume or n is ReflectionProbe:
		var item = base_spec(n)
		item["props"] = stored_props(n)
		special.append(item)
	if n is Path3D and n.curve:
		var curve = base_spec(n)
		curve["curve"] = safe(n.curve)
		special.append(curve)
	if n is Area3D:
		var volume = base_spec(n)
		volume["kind"] = kind_of(n, true)
		volume["props"] = script_props(n)
		volume["script"] = node_script(n)
		volume["shapes"] = []
		volume["entity"] = own
		for child in n.get_children():
			if child is CollisionShape3D and child.shape:
				volume["shapes"].append(shape_spec(child))
			elif child is CollisionPolygon3D:
				volume["shapes"].append(polygon_spec(child))
		volumes.append(volume)
	if n is CollisionShape3D and n.shape and n.get_parent() is PhysicsBody3D:
		var col = shape_spec(n)
		col["kind"] = kind_of(n.get_parent(), false)
		col["body"] = path_of(n.get_parent())
		col["entity"] = own
		col["layer"] = n.get_parent().collision_layer
		col["mask"] = n.get_parent().collision_mask
		if n.get_parent() is StaticBody3D and n.get_parent().physics_material_override:
			col["physics_material"] = stored_props(n.get_parent().physics_material_override)
		collisions.append(col)
	if n is CollisionPolygon3D and n.get_parent() is PhysicsBody3D:
		var col = polygon_spec(n)
		col["kind"] = kind_of(n.get_parent(), false)
		col["entity"] = own
		collisions.append(col)
	if n is MeshInstance3D and n.mesh:
		_add_mesh(n, n.mesh, n.global_transform, own)
	elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh:
		var mm = n.multimesh
		var count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		for i in range(count):
			_add_mesh(n, mm.mesh, n.global_transform * mm.get_instance_transform(i), own,
				mm.get_instance_color(i) if mm.use_colors else Color.WHITE, i)
	elif n is CSGShape3D and n.is_root_shape():
		var meshes = n.get_meshes()
		if meshes.size() >= 2 and meshes[1]:
			_add_mesh(n, meshes[1], n.global_transform * meshes[0], own)
			if n.use_collision:
				var faces = meshes[1].get_faces()
				var rel = "_raw/" + area_id + "/csg_" + str(collisions.size()) + ".bin"
				write_bytes(rel, faces.to_byte_array())
				var col = base_spec(n)
				col.merge(transform_spec(n.global_transform * meshes[0]), true)
				col.merge({"shape": "ConcavePolygonShape3D", "faces": rel, "kind": kind_of(n, false), "entity": own, "disabled": false})
				collisions.append(col)
	for child in n.get_children():
		_walk(child, own)

func _add_mesh(n: Node3D, mesh: Mesh, xf: Transform3D, own: String, colour: Color = Color.WHITE, multi_index: int = -1) -> void:
	var mids = []
	for surface in range(mesh.get_surface_count()):
		var mat = mesh.surface_get_material(surface)
		if n is GeometryInstance3D and n.material_override:
			mat = n.material_override
		elif n is MeshInstance3D and n.get_surface_override_material(surface):
			mat = n.get_surface_override_material(surface)
		mids.append(material_id(mat))
	var key = str(mesh.get_instance_id()) + ":" + JSON.stringify(mids)
	if not mesh_keys.has(key):
		var gid = "g_%04d" % mesh_keys.size()
		mesh_keys[key] = gid
		var rec = {"id": gid, "source": mesh.resource_path, "surfaces": []}
		for surface in range(mesh.get_surface_count()):
			var arrays = mesh.surface_get_arrays(surface)
			if arrays.size() == 0:
				continue
			var primitive = mesh.surface_get_primitive_type(surface) if mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
			var s = {"material": mids[surface], "primitive": primitive}
			for pair in [[Mesh.ARRAY_VERTEX, "position", 3], [Mesh.ARRAY_NORMAL, "normal", 3], [Mesh.ARRAY_TEX_UV, "uv", 2],
				[Mesh.ARRAY_COLOR, "color", 4], [Mesh.ARRAY_INDEX, "index", 1], [Mesh.ARRAY_TANGENT, "tangent", 4],
				[Mesh.ARRAY_BONES, "joints", 4], [Mesh.ARRAY_WEIGHTS, "weights", 4]]:
				var arr = arrays[pair[0]]
				if arr != null and arr.size() > 0:
					var rel = "_raw/" + area_id + "/" + gid + "_" + str(surface) + "_" + pair[1] + ".bin"
					write_bytes(rel, arr.to_byte_array())
					s[pair[1]] = {"file": rel, "count": arr.size(), "width": pair[2]}
			rec["surfaces"].append(s)
		geometry[gid] = rec
	var item = base_spec(n)
	item.merge(transform_spec(xf), true)
	item["geometry"] = mesh_keys[key]
	item["entity"] = own
	item["materials"] = mids
	item["color"] = safe(colour)
	item["multi_index"] = multi_index
	item["visible"] = n.is_visible_in_tree()
	if n is MeshInstance3D and n.skin:
		item["skinned"] = true
		var skel = n.get_node_or_null(n.skeleton)
		if skel:
			item["skeleton"] = path_of(skel)
	geometries.append(item)

func material_id(mat: Material) -> String:
	if mat == null:
		mat = StandardMaterial3D.new()
	var rid = mat.get_instance_id()
	if converted.has(rid):
		return converted[rid][0]
	var data = {"name": mat.resource_name, "source": mat.resource_path, "class": mat.get_class()}
	var pbr: StandardMaterial3D
	if mat is BaseMaterial3D:
		pbr = mat.duplicate() as StandardMaterial3D
		if pbr == null:
			pbr = StandardMaterial3D.new()
			pbr.albedo_color = mat.albedo_color
			pbr.albedo_texture = mat.albedo_texture
		data["props"] = stored_props(mat)
	elif mat is ShaderMaterial:
		pbr = StandardMaterial3D.new()
		data["uniforms"] = {}
		data["shader"] = mat.shader.resource_path if mat.shader else ""
		if mat.shader:
			var retro = get_node_or_null("/root/RetroLook")
			var original = retro.get("_variant_src").get(mat.shader, mat.shader) if retro else mat.shader
			data["shader"] = original.resource_path
			var shid = mat.shader.code.sha256_text().substr(0, 12)
			data["shader_id"] = shid
			shaders[shid] = {"path": original.resource_path, "code": mat.shader.code}
			for uniform in mat.shader.get_shader_uniform_list():
				var value = mat.get_shader_parameter(uniform.name)
				data["uniforms"][uniform.name] = safe(value)
		for key in ["albedo", "base_color", "color", "tint", "grass_tint", "color_top", "water_color", "shallow_color"]:
			var value = mat.get_shader_parameter(key)
			if value is Color:
				pbr.albedo_color = value
				break
		for key in ["albedo_texture", "albedo_tex", "base_texture", "texture_albedo", "grass_texture", "tex", "main_texture"]:
			var value = mat.get_shader_parameter(key)
			if value is Texture2D:
				pbr.albedo_texture = reduced_texture(value)
				break
		pbr.roughness = 0.9
		var unif = data.get("uniforms", {})
		if unif.get("use_vertex_color", false) == true:
			pbr.vertex_color_use_as_albedo = true
		if mat.shader and (mat.shader.code.contains("cull_disabled") or mat.shader.code.contains("ALPHA =")):
			pbr.cull_mode = BaseMaterial3D.CULL_DISABLED
		if pbr.albedo_color.a < 0.99:
			pbr.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		pbr = StandardMaterial3D.new()
	pbr.next_pass = null
	for slot in range(BaseMaterial3D.TEXTURE_MAX):
		var tex = pbr.get_texture(slot)
		if tex:
			pbr.set_texture(slot, reduced_texture(tex))
	data["pbr"] = {"color": safe(pbr.albedo_color), "metallic": pbr.metallic, "roughness": pbr.roughness,
		"albedo_texture": safe(pbr.albedo_texture), "double_sided": pbr.cull_mode == BaseMaterial3D.CULL_DISABLED,
		"unlit": pbr.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		"vertex_color": pbr.vertex_color_use_as_albedo, "uv_scale": safe(pbr.uv1_scale), "uv_offset": safe(pbr.uv1_offset),
		"alpha_mode": pbr.transparency, "emission": safe(pbr.emission) if pbr.emission_enabled else [0, 0, 0, 1]}
	if mat.next_pass:
		data["next_pass"] = material_id(mat.next_pass)
	var mid = "mat_" + JSON.stringify(data).sha256_text().substr(0, 14)
	pbr.resource_name = mid
	materials[mid] = data
	converted[rid] = [mid, pbr]
	return mid

func reduced_texture(tex: Texture2D) -> Texture2D:
	var key = str(tex.get_instance_id())
	if textures.has(key):
		return textures[key][0]
	var img = tex.get_image()
	if img == null or img.is_empty():
		return tex
	if img.is_compressed():
		img.decompress()
	if max(img.get_width(), img.get_height()) > 1024:
		var factor = 1024.0 / max(img.get_width(), img.get_height())
		img.resize(max(1, int(img.get_width() * factor)), max(1, int(img.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	var hash_id = img.get_data().hex_encode().sha256_text().substr(0, 18)
	var file = "textures/tex_" + hash_id + ".webp"
	if not FileAccess.file_exists(out_dir.path_join(file)):
		img.save_webp(out_dir.path_join(file), true)
	var reduced = ImageTexture.create_from_image(img)
	textures[key] = [reduced, {"file": file, "source": tex.resource_path, "width": img.get_width(), "height": img.get_height()}]
	textures[str(reduced.get_instance_id())] = textures[key]
	return reduced

func safe(value: Variant, depth: int = 0) -> Variant:
	if depth > 7:
		return {"truncated_type": type_string(typeof(value))}
	if value == null or value is bool or value is int or value is String or value is StringName or value is NodePath:
		return str(value) if value is StringName or value is NodePath else value
	if value is float:
		return value if is_finite(value) else str(value)
	if value is Vector2 or value is Vector2i:
		return [value.x, value.y]
	if value is Vector3 or value is Vector3i:
		return [value.x, value.y, value.z]
	if value is Vector4 or value is Quaternion or value is Vector4i:
		return [value.x, value.y, value.z, value.w]
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is Transform3D:
		return transform_spec(value)
	if value is Basis:
		return [safe(value.x), safe(value.y), safe(value.z)]
	if value is AABB:
		return {"position": safe(value.position), "size": safe(value.size)}
	if value is Array or value is PackedStringArray or value is PackedVector3Array or value is PackedVector2Array or value is PackedFloat32Array or value is PackedInt32Array or value is PackedColorArray or value is PackedFloat64Array:
		var arr = []
		for v in value:
			arr.append(safe(v, depth + 1))
		return arr
	if value is Dictionary:
		var obj = {}
		for key in value:
			obj[str(key)] = safe(value[key], depth + 1)
		return obj
	if value is Node:
		return {"node": path_of(value) if world and (value == world or world.is_ancestor_of(value)) else str(value.get_path())}
	if value is Texture2D:
		reduced_texture(value)
		return textures.get(str(value.get_instance_id()), [null, {"source": value.resource_path}])[1]
	if value is Curve3D:
		var points = []
		for i in range(value.point_count):
			points.append({"position": safe(value.get_point_position(i)), "in": safe(value.get_point_in(i)), "out": safe(value.get_point_out(i)), "tilt": value.get_point_tilt(i)})
		return {"class": "Curve3D", "points": points, "baked_points": safe(value.get_baked_points()), "closed": value.closed}
	if value is Resource:
		var obj = {"class": value.get_class(), "source": value.resource_path, "name": value.resource_name}
		if value is Script:
			return obj
		if value is Material:
			obj["material"] = material_id(value)
		elif not (value is Mesh or value is Shape3D or value is Skin or value is Animation or value is PackedScene or value is Font or value is AudioStream):
			obj["props"] = stored_props(value, depth + 1)
		return obj
	return {"type": type_string(typeof(value)), "value": str(value)}

func script_props(n: Node) -> Dictionary:
	var result = {}
	var script = n.get_script()
	if script:
		for prop in script.get_script_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE or prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				result[prop.name] = safe(n.get(prop.name))
	return result

func stored_props(obj: Object, depth: int = 0) -> Dictionary:
	var result = {}
	for prop in obj.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE and not prop.name in ["script", "owner", "resource_path", "resource_name", "resource_local_to_scene"]:
			result[prop.name] = safe(obj.get(prop.name), depth + 1)
	return result

func transform_spec(xf: Transform3D) -> Dictionary:
	var q = xf.basis.orthonormalized().get_rotation_quaternion()
	return {"position": safe(xf.origin), "quaternion": safe(q), "scale": safe(xf.basis.get_scale()),
		"matrix": [xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, 0, xf.basis.y.x, xf.basis.y.y, xf.basis.y.z, 0,
			xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, 0, xf.origin.x, xf.origin.y, xf.origin.z, 1]}

func base_spec(n: Node) -> Dictionary:
	var spec = {"id": path_of(n), "name": str(n.name), "class": n.get_class(), "parent": path_of(n.get_parent()) if n != world else "",
		"groups": safe(n.get_groups()), "metadata": {}, "scene": n.scene_file_path}
	for key in n.get_meta_list():
		if not str(key).begins_with("_") and not str(key).begins_with("retro_"):
			spec["metadata"][key] = safe(n.get_meta(key))
	if n is Node3D:
		spec.merge(transform_spec(n.global_transform))
		spec["local"] = transform_spec(n.transform)
		spec["visible"] = n.is_visible_in_tree()
	return spec

func shape_spec(n: CollisionShape3D) -> Dictionary:
	var s = base_spec(n)
	s["shape"] = n.shape.get_class()
	s["disabled"] = n.disabled
	s["size"] = {}
	for key in ["size", "radius", "height", "margin", "separation_ray_length", "backface_collision"]:
		var value = n.shape.get(key)
		if value != null:
			s["size"][key] = safe(value)
	if n.shape is ConcavePolygonShape3D:
		var file = "_raw/" + area_id + "/faces_" + str(collisions.size()) + "_" + str(volumes.size()) + ".bin"
		write_bytes(file, n.shape.get_faces().to_byte_array())
		s["faces"] = file
	elif n.shape is ConvexPolygonShape3D:
		s["points"] = safe(n.shape.points)
	elif n.shape is HeightMapShape3D:
		s["size"] = stored_props(n.shape)
	elif n.shape is WorldBoundaryShape3D:
		s["plane"] = {"normal": safe(n.shape.plane.normal), "d": n.shape.plane.d}
	return s

func polygon_spec(n: CollisionPolygon3D) -> Dictionary:
	var s = base_spec(n)
	s.merge({"shape": "CollisionPolygon3D", "polygon": safe(n.polygon), "depth": n.depth,
		"disabled": n.disabled, "build_mode": n.build_mode})
	return s

func kind_of(n: Node, volume: bool) -> String:
	var words = (path_of(n) + " " + node_script(n) + " " + str(n.get_groups())).to_lower()
	for pair in [["kill", "death"], ["death", "death"], ["lava", "lava"], ["chocolate", "lava"], ["hazard", "hazard"],
		["updraft", "wind"], ["wind", "wind"], ["gust", "wind"], ["water", "water"], ["swim", "water"],
		["slipper", "slippery"], ["ice", "slippery"], ["climb", "climbable"], ["ladder", "climbable"],
		["bounce", "bouncy"], ["checkpoint", "checkpoint"], ["portal", "portal"], ["exit_gate", "portal"],
		["camera_zone", "camera"], ["music", "music"], ["one_way", "one_way"], ["hurtbox", "hurtbox"],
		["pickup", "pickup"], ["truffle", "pickup"], ["acorn", "pickup"], ["lost_page", "pickup"]]:
		if pair[0] in words:
			return pair[1]
	return "trigger" if volume else "ground"

func camera_spec(cam: Camera3D) -> Dictionary:
	var data = base_spec(cam)
	data.merge({"fov": cam.fov, "near": cam.near, "far": cam.far, "projection": cam.projection,
		"size": cam.size, "keep_aspect": cam.keep_aspect, "h_offset": cam.h_offset, "v_offset": cam.v_offset})
	return data

func animation_spec(player: AnimationPlayer) -> Array:
	var clips = []
	for name in player.get_animation_list():
		var anim = player.get_animation(name)
		var tracks = []
		for i in range(anim.get_track_count()):
			var keys = []
			for j in range(anim.track_get_key_count(i)):
				keys.append({"time": anim.track_get_key_time(i, j), "value": safe(anim.track_get_key_value(i, j))})
			tracks.append({"path": str(anim.track_get_path(i)), "type": anim.track_get_type(i), "interpolation": anim.track_get_interpolation_type(i), "keys": keys})
		clips.append({"name": name, "length": anim.length, "loop_mode": anim.loop_mode, "tracks": tracks})
	return clips

func _export_character(source: Node3D, char_id: String, reset_pose: bool) -> void:
	var copy = source.duplicate(0)
	copy.name = char_id
	copy.transform = Transform3D.IDENTITY
	copy.visible = true
	get_tree().root.add_child(copy)
	var desc = {"id": char_id, "source": path_of(source), "units": "metres", "up": "+Y", "forward": "-Z",
		"bones": [], "sockets": [], "clips": [], "materials": [], "nodes": [], "procedural_animation": true}
	_clean_character(copy, copy, desc, reset_pose)
	var doc = GLTFDocument.new()
	doc.root_node_mode = GLTFDocument.ROOT_NODE_MODE_KEEP_ROOT
	doc.image_format = "Lossless WebP"
	doc.visibility_mode = GLTFDocument.VISIBILITY_MODE_EXCLUDE
	var state = GLTFState.new()
	var err = doc.append_from_scene(copy, state)
	assert(err == OK, "Character conversion failed")
	err = doc.write_to_filesystem(state, out_dir.path_join("characters/" + char_id + ".glb"))
	assert(err == OK, "Character export failed")
	write_json("characters/" + char_id + ".json", desc)
	copy.free()

func _clean_character(n: Node, root: Node, desc: Dictionary, reset_pose: bool) -> void:
	n.set_script(null)
	n.process_mode = Node.PROCESS_MODE_DISABLED
	if n is Node3D:
		desc["nodes"].append({"path": str(root.get_path_to(n)), "name": str(n.name), "local": transform_spec(n.transform)})
	if n is Skeleton3D:
		if reset_pose:
			n.reset_bone_poses()
		for i in range(n.get_bone_count()):
			desc["bones"].append({"skeleton": str(root.get_path_to(n)), "index": i, "name": n.get_bone_name(i),
				"parent": n.get_bone_parent(i), "rest": transform_spec(n.get_bone_rest(i)), "pose": transform_spec(n.get_bone_pose(i))})
	if n is BoneAttachment3D:
		desc["sockets"].append({"path": str(root.get_path_to(n)), "bone": n.bone_name, "local": transform_spec(n.transform)})
	if n is AnimationPlayer:
		desc["clips"].append_array(animation_spec(n))
	if n is MeshInstance3D and n.mesh:
		for surface in range(n.mesh.get_surface_count()):
			var mat = n.get_active_material(surface)
			var mid = material_id(mat)
			if mat:
				n.set_surface_override_material(surface, converted[mat.get_instance_id()][1])
			if not mid in desc["materials"]:
				desc["materials"].append(mid)
		n.material_override = null
		n.material_overlay = null
	for child in n.get_children():
		if child is CollisionObject3D or child is CollisionShape3D or child is Camera3D or child is GPUParticles3D:
			child.free()
		else:
			_clean_character(child, root, desc, reset_pose)

func write_json(rel: String, data: Variant) -> void:
	var f = FileAccess.open(out_dir.path_join(rel), FileAccess.WRITE)
	assert(f != null, "Cannot write " + rel)
	f.store_string(JSON.stringify(data, "\t", false, true))
	f.close()

func write_bytes(rel: String, bytes: PackedByteArray) -> void:
	var f = FileAccess.open(out_dir.path_join(rel), FileAccess.WRITE)
	assert(f != null, "Cannot write " + rel)
	f.store_buffer(bytes)
	f.close()

extends SceneTree
## W1 builder: bakes the terrain chunks (render mesh + trimesh collision), the stream ribbon and the
## W1.tscn skeleton (WorldRoot contract nodes). Gameplay content is placed at runtime by w1_level.gd
## from res://assets/environment/w1/w1_level.json, so the level data stays one source of truth.
## Run:  python tools/godot.py script res://scripts/worlds/w1_bake.gd
## (first run the data generator: python game/assets/environment/w1/tools/w1_terrain.py)

const OUT_DIR := "res://assets/environment/w1/"
const SCENE_PATH := "res://scenes/worlds/w1/W1.tscn"
const CHUNKS := 4


func _init() -> void:
	if not W1Terrain.ensure_loaded():
		push_error("[w1_bake] terrain data missing")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR + "terrain")
	var mat := _terrain_material()
	ResourceSaver.save(mat, OUT_DIR + "w1_terrain_mat.tres")
	var n := W1Terrain.grid_n()
	var cells := n - 1
	var per := cells / CHUNKS
	for cz in CHUNKS:
		for cx in CHUNKS:
			var res := _chunk(cx * per, cz * per, per)
			ResourceSaver.save(res[0], OUT_DIR + "terrain/chunk_%d_%d.mesh.res" % [cx, cz], ResourceSaver.FLAG_COMPRESS)
			ResourceSaver.save(res[1], OUT_DIR + "terrain/chunk_%d_%d.shape.res" % [cx, cz], ResourceSaver.FLAG_COMPRESS)
	var water := _stream_ribbon()
	ResourceSaver.save(water, OUT_DIR + "w1_stream.mesh.res", ResourceSaver.FLAG_COMPRESS)
	_build_scene()
	print("[w1_bake] done")
	quit(0)


func _terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(OUT_DIR + "w1_terrain.gdshader")
	m.set_shader_parameter("grass_texture", load("res://assets/textures/grass.webp"))
	m.set_shader_parameter("dirt_texture", load("res://assets/textures/dirt_path.webp"))
	m.set_shader_parameter("cobble_texture", load("res://assets/textures/cobblestone.webp"))
	m.set_shader_parameter("rock_texture", load("res://assets/textures/cliff_rock.webp"))
	m.set_shader_parameter("grass_tint", Color(1.0, 1.04, 0.86))
	m.set_shader_parameter("grass_tint_high", Color(1.12, 1.1, 0.82))
	m.set_shader_parameter("dirt_tint", Color(1.08, 0.98, 0.86))
	m.set_shader_parameter("cobble_tint", Color(1.0, 0.97, 0.92))
	m.set_shader_parameter("rock_tint", Color(1.0, 0.95, 0.88))
	return m


func _chunk(x_start: int, z_start: int, per: int) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var step := W1Terrain.grid_step()
	var o := W1Terrain.grid_origin()
	var side := per + 1
	for j in side:
		for i in side:
			var gi := x_start + i
			var gj := z_start + j
			var x := o.x + gi * step
			var z := o.y + gj * step
			verts.append(Vector3(x, W1Terrain.h_at(gi, gj), z))
			var dx := W1Terrain.h_at(gi + 1, gj) - W1Terrain.h_at(gi - 1, gj)
			var dz := W1Terrain.h_at(gi, gj + 1) - W1Terrain.h_at(gi, gj - 1)
			norms.append(Vector3(-dx, 2.0 * step, -dz).normalized())
			cols.append(W1Terrain.mask_at(gi, gj))
	var faces := PackedVector3Array()
	for j in per:
		for i in per:
			var a := j * side + i
			var b := a + 1
			var d := a + side
			var c := d + 1
			idx.append_array([a, b, c, a, c, d])
			faces.append_array([verts[a], verts[b], verts[c], verts[a], verts[c], verts[d]])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, load(OUT_DIR + "w1_terrain_mat.tres"))
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = false
	shape.set_faces(faces)
	return [mesh, shape]


func _stream_ribbon() -> ArrayMesh:
	var s: Array = W1Terrain.level()["_derived"]["stream_samples"]
	var water_y: float = W1Terrain.level()["terrain"]["stream"]["water_y"]
	var half := 3.0 + 0.9
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var along := 0.0
	# Resample densely so the ribbon bends smoothly.
	var pts: Array[Vector2] = []
	for i in range(s.size() - 1):
		var a := Vector2(s[i][0], s[i][1])
		var b := Vector2(s[i + 1][0], s[i + 1][1])
		var k := maxi(1, int(ceil(a.distance_to(b) / 0.75)))
		for t in k:
			pts.append(a.lerp(b, float(t) / k))
	pts.append(Vector2(s[-1][0], s[-1][1]))
	for i in pts.size():
		var p := pts[i]
		var tn := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-tn.y, tn.x)
		if i > 0:
			along += pts[i].distance_to(pts[i - 1])
		for sgn in [-1.0, 1.0]:
			var q: Vector2 = p + nrm * half * sgn
			verts.append(Vector3(q.x, water_y, q.y))
			norms.append(Vector3.UP)
			uvs.append(Vector2(along / 6.0, (sgn + 1.0) * 0.5))
	for i in range(pts.size() - 1):
		var a := i * 2
		idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# Make sure the winding faces up: flip if the first triangle's normal points down.
	var v0 := verts[0]
	var v1 := verts[2]
	var v2 := verts[1]
	var fn := (v1 - v0).cross(v2 - v0)
	if fn.y > 0.0:
		# Godot front faces are clockwise seen from the front; a +Y cross product here means counter-clockwise from above.
		var flipped := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			flipped.append_array([idx[t], idx[t + 2], idx[t + 1]])
		arr[Mesh.ARRAY_INDEX] = flipped
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _own(n: Node, root: Node) -> void:
	if n != root:
		n.owner = root
	for c in n.get_children():
		_own(c, root)


func _build_scene() -> void:
	var lv := W1Terrain.level()
	var root := Node3D.new()
	root.name = "W1"
	root.set_script(load("res://scripts/worlds/w1_world.gd"))
	root.set("world_id", "W1")
	root.set("display_name", "Huff & Puff Hollow")
	root.set("music_key", "music_w1")
	root.set("kill_y", float(lv.get("kill_y", -20.0)))

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = FxEnvironments.make("W1")
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38, -45, 0)
	sun.light_color = Color("ffe2b0")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	root.add_child(sun)

	var terrain := Node3D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	for cz in CHUNKS:
		for cx in CHUNKS:
			var body := StaticBody3D.new()
			body.name = "Chunk_%d_%d" % [cx, cz]
			body.collision_layer = 1
			body.collision_mask = 0
			body.add_to_group("w1_terrain", true)
			terrain.add_child(body)
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.mesh = load(OUT_DIR + "terrain/chunk_%d_%d.mesh.res" % [cx, cz])
			body.add_child(mi)
			var cs := CollisionShape3D.new()
			cs.name = "Shape"
			cs.shape = load(OUT_DIR + "terrain/chunk_%d_%d.shape.res" % [cx, cz])
			body.add_child(cs)

	var water := MeshInstance3D.new()
	water.name = "Stream"
	water.mesh = load(OUT_DIR + "w1_stream.mesh.res")
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wm := ShaderMaterial.new()
	wm.shader = load("res://assets/shaders/water.gdshader")
	wm.set_shader_parameter("flow_along_uv", true)
	wm.set_shader_parameter("flow_speed", 0.5)
	wm.set_shader_parameter("shallow_color", Color("6fd3e0"))
	wm.set_shader_parameter("deep_color", Color("2f7fa3"))
	wm.set_shader_parameter("depth_distance", 0.9)
	wm.set_shader_parameter("foam_distance", 0.18)
	water.material_override = wm
	root.add_child(water)

	var spawns := Node3D.new()
	spawns.name = "Spawns"
	root.add_child(spawns)
	var extra := [
		{"id": "W1-5", "pos": [3.0, 0.4, 19.5], "yaw_deg": -30},
		{"id": "W1-8", "pos": [38.0, 0.6, 9.0], "yaw_deg": -60},
		# Test markers (dev --spawn) next to each truffle goal.
		{"id": "T_W1-1", "pos": [-20.0, 0.4, 34.0], "yaw_deg": 0},
		{"id": "T_W1-2_stage", "pos": [40.0, 17.0, -38.2], "yaw_deg": 0},
		{"id": "T_W1-2_deck", "pos": [40.6, 28.0, -45.4], "yaw_deg": 0},
		{"id": "T_W1-3_deck", "pos": [-44.5, 16.0, -29.0], "yaw_deg": 90},
		{"id": "T_W1-3_sc7", "pos": [-40.6, 14.8, -33.2], "yaw_deg": 90},
		{"id": "T_W1-4", "pos": [2.0, 0.4, 3.0], "yaw_deg": 0},
		{"id": "T_W1-5", "pos": [7.6, 0.35, 12.6], "yaw_deg": 0},
		{"id": "T_W1-6_floor", "pos": [11.3, 12.0, -36.0], "yaw_deg": 0},
		{"id": "T_W1-6_top", "pos": [11.3, 26.1, -36.0], "yaw_deg": 0},
		{"id": "T_W1-7", "pos": [-3.0, 21.0, -36.0], "yaw_deg": -90},
		{"id": "T_W1-8", "pos": [45.0, 0.5, 16.0], "yaw_deg": 0},
		{"id": "T_bridge", "pos": [-6.0, 0.6, 16.5], "yaw_deg": 0},
		{"id": "T_tor", "pos": [34.0, 7.0, 3.0], "yaw_deg": 0},
		{"id": "T_rope", "pos": [-38.0, 15.5, -31.5], "yaw_deg": -90},
		{"id": "T_hill", "pos": [-2.0, 12.0, -36.5], "yaw_deg": -90},
		{"id": "T_ridge", "pos": [47.0, 12.0, -36.0], "yaw_deg": 60},
	]
	for s in lv["spawns"] + extra:
		var m := Marker3D.new()
		m.name = String(s["id"])
		var p: Array = s["pos"]
		var y: float = p[1]
		if String(s["id"]).begins_with("T_") or s in extra:
			y = maxf(y, W1Terrain.height(p[0], p[2]))
		m.position = Vector3(p[0], y + 0.05, p[2])
		m.rotation_degrees = Vector3(0, float(s["yaw_deg"]), 0)
		spawns.add_child(m)

	var cams := Node3D.new()
	cams.name = "StoryCams"
	root.add_child(cams)
	for c in lv["story_cams"]:
		var cam := Camera3D.new()
		cam.name = String(c["id"])
		var pos := Vector3(c["pos"][0], c["pos"][1], c["pos"][2])
		var tgt := Vector3(c["look_at"][0], c["look_at"][1], c["look_at"][2])
		cam.transform = Transform3D(Basis.looking_at(tgt - pos, Vector3.UP), pos)
		cam.fov = float(c["fov_deg"])
		cam.far = 600.0
		cams.add_child(cam)

	var level := Node3D.new()
	level.name = "Level"
	level.set_script(load("res://scripts/worlds/w1_level.gd"))
	root.add_child(level)

	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("[w1_bake] pack failed %d" % err)
		return
	DirAccess.make_dir_recursive_absolute(SCENE_PATH.get_base_dir())
	err = ResourceSaver.save(ps, SCENE_PATH)
	print("[w1_bake] saved ", SCENE_PATH, " err=", err)
	root.free()

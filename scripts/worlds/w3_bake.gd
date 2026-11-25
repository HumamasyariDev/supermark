extends SceneTree
## W3 Gingerbread Grove baker. Deterministic: same plan data, same output.
## Reads data/levels/W3.json (copied to res://scenes/worlds/w3/w3_level.json so the exported game has it),
## bakes terrain, skirt, liquids, cake tiers, frosting slide, liquorice pipe and the lollipop disc into
## res://scenes/worlds/w3/baked/, then writes the W3.tscn skeleton (WorldRoot contract nodes).
## Gameplay content is placed at runtime by w3_level.gd from the same JSON.
## Run: python tools/godot.py script res://scripts/worlds/w3_bake.gd

const OUT := "res://scenes/worlds/w3/baked/"
const SCENE := "res://scenes/worlds/w3/W3.tscn"
const DATA_DST := "res://scenes/worlds/w3/w3_level.json"
const Geo := preload("res://scripts/worlds/w3_geo.gd")

var geo: Geo


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var src := ProjectSettings.globalize_path("res://").path_join("../data/levels/W3.json").simplify_path()
	var f := FileAccess.open(src, FileAccess.READ)
	if f == null:
		push_error("[w3_bake] missing " + src)
		quit(1)
		return
	var txt := f.get_as_text()
	f.close()
	# Night-01 R1 fix round: the world copy (res://scenes/worlds/w3/w3_level.json) now carries the critic-round fixes
	# and is authoritative; the plan copy is only re-imported with "-- --from-plan".
	if OS.get_cmdline_user_args().has("--from-plan") or not FileAccess.file_exists(DATA_DST):
		var o := FileAccess.open(DATA_DST, FileAccess.WRITE)
		o.store_string(txt)
		o.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	geo = Geo.new()
	geo.load_data(DATA_DST)
	geo.bake_heights()
	print("[w3_bake] heights %d ms" % (Time.get_ticks_msec() - t0))
	# Height grid for runtime queries (scatter, hazard): raw float32 file.
	var hf := FileAccess.open(OUT + "heights.bin", FileAccess.WRITE)
	hf.store_buffer(geo.H.to_byte_array())
	hf.close()
	var pf := FileAccess.open(OUT + "pathmask.bin", FileAccess.WRITE)
	pf.store_buffer(geo.path_mask.to_byte_array())
	pf.close()
	_save(geo.terrain_mesh(), "terrain.mesh.res")
	_save(geo.terrain_collision(1), "terrain.shape.res")
	_save(geo.skirt_mesh(), "skirt.mesh.res")
	_bake_liquids()
	_bake_cake()
	_bake_slide()
	_bake_chute()
	_bake_pipe()
	_save(Geo.swirl_disc(4.0, 1.6, 72), "lollipop_disc.mesh.res")
	_build_scene()
	# Parse check of every W3 script (load surfaces parse errors in the bake log).
	for sc in ["w3_level", "w3_world", "w3_bot", "w3_jelly", "w3_candle", "w3_crumble", "w3_maze_scent", "w3_royal", "w3_slide_push",
			"w3_biscuit_lane", "w3_breadcrumbs", "w3_falls", "w3_fort", "w3_bobber"]:
		if load("res://scripts/worlds/%s.gd" % sc) == null:
			push_error("[w3_bake] script failed: " + sc)
	print("[w3_bake] done in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)


func _save(r: Resource, name: String) -> void:
	var err := ResourceSaver.save(r, OUT + name, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("[w3_bake] save failed %s (%d)" % [name, err])


# ---------------------------------------------------------------- liquids

## Grid surface at y 0.3 over every cell whose terrain dips below the surface. `pink` selects the
## Syrup Pool region (safe, pink) versus hot chocolate (everything else). Vertex colour r = shore foam.
func _liquid_mesh(pink: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 1.0
	var y := 0.3
	var pool := Vector2(-44, -33)
	var x := -60.0
	while x < 60.0:
		var z := -55.0
		while z < 55.0:
			var lo := minf(minf(geo.h_at(x, z), geo.h_at(x + step, z)), minf(geo.h_at(x, z + step), geo.h_at(x + step, z + step)))
			var c := Vector2(x + step * 0.5, z + step * 0.5)
			var in_pool := c.distance_to(pool) < 9.0
			if lo < y + 0.05 and in_pool == pink:
				var q := [Vector3(x, y, z), Vector3(x + step, y, z), Vector3(x + step, y, z + step), Vector3(x, y, z + step)]
				var cols := []
				for v in q:
					var h := geo.h_at(v.x, v.z)
					cols.append(Color(1.0 - Geo.smooth(-0.15, 0.25, y - h), 0, 0))
				for k in [0, 1, 2, 0, 2, 3]:
					st.set_normal(Vector3.UP)
					st.set_color(cols[k])
					st.set_uv(Vector2(q[k].x, q[k].z))
					st.add_vertex(q[k])
			z += step
		x += step
	st.index()
	return st.commit()


func _curtain(width: float, top: float, bottom: float, bulge: float, segs_x: int = 12, segs_y: int = 24) -> ArrayMesh:
	## Local curtain: x across (-w/2..w/2), y from top to bottom, bulging outward (+Z) as it falls.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := []
	for j in segs_y + 1:
		var v := float(j) / segs_y
		var yy := lerpf(top, bottom, v)
		var zz := bulge * sqrt(v) + 0.25 * sin(v * PI)
		var row := []
		for i in segs_x + 1:
			var u := float(i) / segs_x
			var xx := (u - 0.5) * width * (1.0 + 0.12 * v)
			row.append([Vector3(xx, yy, zz + 0.15 * sin(u * PI)), Vector2(u, v * (top - bottom) / 6.0)])
		rows.append(row)
	for j in segs_y:
		for i in segs_x:
			var a: Array = rows[j][i]
			var b: Array = rows[j][i + 1]
			var c: Array = rows[j + 1][i + 1]
			var d: Array = rows[j + 1][i]
			for vv in [a, b, c, a, c, d]:
				st.set_normal(Vector3(0, 0.2, 1).normalized())
				st.set_uv(vv[1])
				st.add_vertex(vv[0])
	st.generate_normals()
	return st.commit()


func _bake_liquids() -> void:
	_save(_liquid_mesh(false), "chocolate.mesh.res")
	_save(_liquid_mesh(true), "syrup.mesh.res")
	# Syrup Falls: 6 m wide, from the spout tip (y 16) down to the pool (y 0.3).
	_save(_curtain(6.0, 16.0, 0.2, 1.6), "syrup_falls.mesh.res")
	# Chocolate Falls off the east page edge into the void.
	_save(_curtain(9.0, 0.3, -14.0, 3.0), "choc_falls.mesh.res")


# ---------------------------------------------------------------- cake tiers

func _bake_cake() -> void:
	var i := 0
	for t in geo.data["cake_tiers"]:
		var rx := float(t["r"][0])
		var rz := float(t["r"][1])
		var y0 := float(t["base_y"])
		var y1 := float(t["top_y"])
		var mesh := Geo.cake_tier(rx, rz, y0, y1, Color(String(t["sponge"])), Color(String(t["icing"])), 112, 11 + i * 7)
		_save(mesh, "tier_%s.mesh.res" % String(t["id"]))
		_save(Geo.ellipse_hull(rx, rz, y0, y1, 48), "tier_%s.shape.res" % String(t["id"]))
		i += 1


func _tier_top_at(x: float, z: float) -> float:
	var best := -100.0
	for t in geo.data["cake_tiers"]:
		var dx := (x - float(t["c"][0])) / float(t["r"][0])
		var dz := (z - float(t["c"][1])) / float(t["r"][1])
		if dx * dx + dz * dz <= 1.0:
			best = maxf(best, float(t["top_y"]))
	return best


# ---------------------------------------------------------------- frosting slide

func slide_center() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for q in geo.data["splines"]["frosting_slide"]["points"]:
		pts.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	return Geo.resample(Geo.dense(pts, 12), 0.8)


func _bake_slide() -> void:
	var c := slide_center()
	# R2.9: blue-raspberry frosting so the slide reads against every tier.
	var res: Array = Geo.trough(c, 3.2, 0.8, Color("#8FD0F5"), Color("#5BB0E6"))
	_save(res[0], "slide.mesh.res")
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(res[1])
	sh.backface_collision = true
	_save(sh, "slide.shape.res")
	# Wafer stilts every 4 m where the trough floats more than 0.6 m above the ground or a tier.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var acc := 0.0
	var next := 2.0
	for i in c.size() - 1:
		acc += c[i].distance_to(c[i + 1])
		if acc < next:
			continue
		next += 4.0
		var p := c[i]
		var ground := maxf(geo.h_at(p.x, p.z), _tier_top_at(p.x, p.z))
		if p.y - ground < 0.6:
			continue
		var top := p.y - 0.3
		var bot := ground - 0.3
		var prof := [Vector2(0.42, bot), Vector2(0.36, bot + 0.3), Vector2(0.28, bot + 0.5), Vector2(0.26, top - 0.3), Vector2(0.38, top)]
		var m := Geo.lathe(prof, 10, 1.0, 1.0, [Color("#B57A3F"), Color("#C98A4B"), Color("#C98A4B"), Color("#C98A4B"), Color("#B57A3F")])
		st.append_from(m, 0, Transform3D(Basis(), Vector3(p.x, 0, p.z)))
	_save(st.commit(), "slide_stilts.mesh.res")
	# Points file for runtime (conveyor, acorns, rival sled).
	var f := FileAccess.open(OUT + "slide_center.json", FileAccess.WRITE)
	var arr := []
	for p in c:
		arr.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
	f.store_string(JSON.stringify(arr))
	f.close()


func _bake_chute() -> void:
	if not geo.data["splines"].has("pool_chute"):
		return
	var spl: Dictionary = geo.data["splines"]["pool_chute"]
	var pts := PackedVector3Array()
	for q in spl["points"]:
		pts.append(Vector3(float(q[0]), float(q[1]) + 0.05, float(q[2])))
	var c := Geo.resample(Geo.dense(pts, 10), 0.6)
	var res: Array = Geo.trough(c, float(spl.get("width", 2.6)), float(spl.get("wall_h", 0.6)), Color("#8FD0F5"), Color("#5BB0E6"))
	_save(res[0], "pool_chute.mesh.res")
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(res[1])
	sh.backface_collision = true
	_save(sh, "pool_chute.shape.res")


# ---------------------------------------------------------------- liquorice pipe

func _bake_pipe() -> void:
	var pts := PackedVector3Array()
	for q in geo.data["splines"]["liquorice_pipe"]["points"]:
		pts.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	# Round the corners a little: dense linear with short catmull in corners.
	var d := Geo.resample(Geo.dense(pts, 6), 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(Geo.tube(d, 0.4, 14, Color(0.17, 0.12, 0.18), Color(0.85, 0.2, 0.32), 0.9), 0, Transform3D())
	var acc := 0.0
	var next := 2.5
	for i in d.size() - 1:
		acc += d[i].distance_to(d[i + 1])
		if acc < next:
			continue
		next += 5.0
		var p := d[i]
		var g := geo.h_at(p.x, p.z)
		if p.y - g < 0.8:
			continue
		var prof := [Vector2(0.3, g - 0.2), Vector2(0.22, g + 0.2), Vector2(0.16, p.y - 0.3), Vector2(0.2, p.y)]
		var m := Geo.lathe(prof, 8, 1.0, 1.0, [Color(0.2, 0.14, 0.2), Color(0.25, 0.18, 0.25), Color(0.25, 0.18, 0.25), Color(0.2, 0.14, 0.2)])
		st.append_from(m, 0, Transform3D(Basis(), Vector3(p.x, 0, p.z)))
	_save(st.commit(), "pipe.mesh.res")
	var f := FileAccess.open(OUT + "pipe_points.json", FileAccess.WRITE)
	var arr := []
	for p in d:
		arr.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
	f.store_string(JSON.stringify(arr))
	f.close()


# ---------------------------------------------------------------- scene skeleton

func _own(n: Node, root: Node) -> void:
	n.owner = root
	for c in n.get_children():
		_own(c, root)


func _build_scene() -> void:
	var root := Node3D.new()
	root.name = "W3"
	root.set_script(load("res://scripts/worlds/w3_world.gd"))
	root.set("world_id", "W3")
	root.set("display_name", "Gingerbread Grove")
	root.set("music_key", "music_w3")
	root.set("kill_y", -12.0)
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = load("res://assets/shaders/environments/env_W3.tres")
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38, -45, 0)
	sun.light_color = Color("#FFE3B0")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.light_angular_distance = 1.5
	root.add_child(sun)
	# Terrain.
	var terr := StaticBody3D.new()
	terr.name = "Terrain"
	terr.collision_layer = 1
	terr.collision_mask = 0
	terr.set_meta("surface", "grass")
	root.add_child(terr)
	var tm := MeshInstance3D.new()
	tm.name = "Mesh"
	tm.mesh = load(OUT + "terrain.mesh.res")
	var tmat := ShaderMaterial.new()
	tmat.shader = load("res://assets/environment/w3/w3_terrain.gdshader")
	tm.material_override = tmat
	terr.add_child(tm)
	var tcs := CollisionShape3D.new()
	tcs.name = "Shape"
	tcs.shape = load(OUT + "terrain.shape.res")
	terr.add_child(tcs)
	var sk := MeshInstance3D.new()
	sk.name = "Skirt"
	sk.mesh = load(OUT + "skirt.mesh.res")
	var skm := StandardMaterial3D.new()
	skm.vertex_color_use_as_albedo = true
	skm.roughness = 0.85
	sk.material_override = skm
	sk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terr.add_child(sk)
	# Spawns.
	var sp := Node3D.new()
	sp.name = "Spawns"
	root.add_child(sp)
	for s in geo.data["spawns"]:
		var m := Marker3D.new()
		m.name = String(s["id"])
		m.position = Vector3(float(s["pos"][0]), float(s["pos"][1]) + 0.05, float(s["pos"][2]))
		m.rotation_degrees.y = float(s["rot_y"])
		sp.add_child(m)
	# Extra dev markers (pages, truffles) are added by the level script at runtime.
	var cams := Node3D.new()
	cams.name = "StoryCams"
	root.add_child(cams)
	for c in geo.data["story_cams"]:
		var cam := Camera3D.new()
		cam.name = String(c["id"])
		var pos := Vector3(float(c["pos"][0]), float(c["pos"][1]), float(c["pos"][2]))
		var tgt := Vector3(float(c["look_at"][0]), float(c["look_at"][1]), float(c["look_at"][2]))
		cam.transform = Transform3D(Basis(), pos).looking_at(tgt, Vector3.UP)
		cam.fov = float(c["fov"])
		cam.far = 600.0
		cam.current = false
		cams.add_child(cam)
	var lvl := Node3D.new()
	lvl.name = "Level"
	lvl.set_script(load("res://scripts/worlds/w3_level.gd"))
	root.add_child(lvl)
	for c in root.get_children():
		_own(c, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("[w3_bake] pack failed %d" % err)
		return
	err = ResourceSaver.save(ps, SCENE)
	print("[w3_bake] scene saved err=%d" % err)
	root.free()

class_name FxDresser
extends RefCounted
## One-call "make it alive" pass for world builders: grass and flower scatter on terrain meshes,
## ambient butterflies / falling leaves, and the storybook post-process.
##
##   FxDresser.dress(self, {
##       "terrain": $Terrain,                 # node whose MeshInstance3D descendants get grass (required for grass)
##       "grass_per_m2": 3.0,                 # density on flat, non-path ground
##       "grass_distance": 70.0,              # per-mesh visibility range (split big terrains into chunks)
##       "avoid_channels": Vector4(1, 1, 1, 0),  # vertex colour channels that mean "no grass" (paths, cobble, banks)
##       "max_slope": 32.0, "min_height": -100.0,
##       "flowers": true, "palette": "W1",    # W1 meadow, W2 sky garden, W3 candy (sprinkle-coloured "flowers")
##       "butterflies": [Vector3(...), ...],  # centres of 12 m ambient volumes
##       "leaves": [Vector3(...), ...],       # tree canopy centres
##       "post": true,                        # StorybookPost (ink lines + grade)
##       "seed": 1,
##   })
## Returns the created container node ("FxDressing"). Safe to call once in _ready().

static func dress(root: Node3D, opts: Dictionary) -> Node3D:
	var box := Node3D.new()
	box.name = "FxDressing"
	root.add_child(box)
	var terrain: Node = opts.get("terrain", null)
	var seed_value: int = opts.get("seed", 1)
	if terrain != null:
		var meshes: Array[MeshInstance3D] = []
		_collect(terrain, meshes)
		var palette: String = opts.get("palette", "W1")
		var grass_mat := _grass_for(palette)
		var tuft := FxScatter.make_grass_tuft(0.42, 7, 5)
		var flower_meshes := _flowers_for(palette)
		var fm := FxScatter.flower_material()
		var k := 0
		for mi in meshes:
			var area := _area(mi)
			var g := FxScatter.new()
			g.name = "Grass_%d" % k
			g.auto_build = false
			g.source_mesh = tuft
			g.material = grass_mat
			g.count = int(area * float(opts.get("grass_per_m2", 3.0)))
			g.scatter_seed = seed_value * 100 + k
			g.max_slope_degrees = opts.get("max_slope", 32.0)
			g.min_height = opts.get("min_height", -100.0)
			g.avoid_channels = opts.get("avoid_channels", Vector4(1, 0, 0, 0))
			g.avoid_vertex_red = 0.35
			g.clump_strength = 0.45
			# Grass only near the camera: chunks beyond this distance fade out (keeps triangle counts sane).
			g.visibility_range_end = opts.get("grass_distance", 70.0)
			g.visibility_range_end_margin = 10.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			box.add_child(g)
			g.target_path = g.get_path_to(mi)
			g.build()
			if opts.get("flowers", true):
				for f in flower_meshes.size():
					var fl := FxScatter.new()
					fl.name = "Flowers_%d_%d" % [k, f]
					fl.auto_build = false
					fl.source_mesh = flower_meshes[f]
					fl.material = fm
					fl.count = int(area * 0.03)
					fl.scatter_seed = seed_value * 1000 + k * 10 + f
					fl.max_slope_degrees = 25.0
					fl.min_height = g.min_height
					fl.avoid_channels = g.avoid_channels
					fl.avoid_vertex_red = 0.35
					fl.clump_strength = 0.85
					fl.clump_frequency = 0.2
					fl.scale_range = Vector2(0.8, 1.4)
					box.add_child(fl)
					fl.target_path = fl.get_path_to(mi)
					fl.build()
			k += 1
	for p in opts.get("butterflies", []):
		_fx(box, "butterflies", p)
	for p in opts.get("leaves", []):
		_fx(box, "falling_leaves", p)
	if opts.get("post", true):
		var post := FxPost.new()
		post.name = "StorybookPost"
		box.add_child(post)
	return box


static func _fx(parent: Node3D, preset: String, pos: Vector3) -> void:
	var fx := FxEffect.new()
	fx.preset = preset
	fx.free_when_done = false
	parent.add_child(fx)
	fx.global_position = pos


static func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


static func _area(mi: MeshInstance3D) -> float:
	var aabb := mi.get_aabb()
	var s := mi.global_transform.basis.get_scale()
	return absf(aabb.size.x * s.x * aabb.size.z * s.z)


static func _grass_for(palette: String) -> ShaderMaterial:
	match palette:
		"W2":
			return FxScatter.grass_material(Color(0.22, 0.5, 0.22), Color(0.72, 0.92, 0.45))
		"W3":
			return FxScatter.grass_material(Color(0.35, 0.62, 0.42), Color(0.75, 0.98, 0.8))
		"HUB":
			return FxScatter.grass_material(Color(0.25, 0.4, 0.18), Color(0.6, 0.72, 0.3))
	# W1: matched to the sunny lime meadow of the W1 terrain so tufts blend into the ground.
	return FxScatter.grass_material(Color(0.36, 0.58, 0.15), Color(0.8, 0.93, 0.36))


static func _flowers_for(palette: String) -> Array[Mesh]:
	var cols: Array
	match palette:
		"W2":
			cols = [Color(1, 1, 1), Color(0.75, 0.7, 1.0), Color(1.0, 0.85, 0.35)]
		"W3":
			cols = [Color(1.0, 0.55, 0.75), Color(0.6, 0.95, 0.85), Color(1.0, 0.95, 0.6)]
		_:
			cols = [Color(1.0, 0.85, 0.25), Color(1, 1, 1), Color(1.0, 0.55, 0.7), Color(0.6, 0.65, 1.0)]
	var out: Array[Mesh] = []
	for c in cols:
		out.append(FxScatter.make_flower(c))
	return out

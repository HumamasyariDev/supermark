class_name FxMaterials
extends RefCounted
## Ready-made materials for world builders, saved to res://assets/shaders/materials/*.tres
## (run VFXLab with --build-env). Use them directly or duplicate() and tweak parameters.

const T := "res://assets/textures/"
const DIR := "res://assets/shaders/materials/"


static func toon(color: Color, tex := "", triplanar_scale := 0.0, outline := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/toon.gdshader")
	m.set_shader_parameter("albedo", color)
	if tex != "":
		m.set_shader_parameter("albedo_texture", load(T + tex + ".webp"))
	if triplanar_scale > 0.0:
		m.set_shader_parameter("triplanar", true)
		m.set_shader_parameter("triplanar_scale", triplanar_scale)
	if outline:
		var o := ShaderMaterial.new()
		o.shader = load("res://assets/shaders/outline.gdshader")
		m.next_pass = o
	return m


static func terrain(grass: String, dirt: String, rock: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/terrain.gdshader")
	m.set_shader_parameter("grass_texture", load(T + grass + ".webp"))
	m.set_shader_parameter("dirt_texture", load(T + dirt + ".webp"))
	m.set_shader_parameter("rock_texture", load(T + rock + ".webp"))
	return m


static func library() -> Dictionary:
	var lib := {}
	# Terrains (vertex colour red paints the path layer).
	lib["terrain_meadow"] = terrain("grass", "dirt_path", "cliff_rock")
	lib["terrain_skyway"] = terrain("grass", "cobblestone", "cliff_rock")
	var candy := terrain("frosting", "gingerbread", "chocolate")
	candy.set_shader_parameter("grass_scale", 0.12)
	candy.set_shader_parameter("grass_brightness", 1.0)
	lib["terrain_candy"] = candy
	# Toon props (triplanar so boxes and blockouts never stretch).
	for t in ["brick", "straw_thatch", "wood_planks", "cobblestone", "bark", "candy_stripes", "frosting", "gingerbread",
			"chocolate", "bookshelf_wood", "parchment", "cliff_rock", "dirt_path", "grass", "roof_tiles", "library_carpet",
			"damask_wallpaper", "stained_glass", "beanstalk_skin", "leaf_canopy", "gumdrop_sugar", "plaster_wall", "castle_stone",
			"roof_shingles_slate"]:
		lib["toon_" + t] = toon(Color.WHITE, t, 0.35)
	# Character colours from the art direction (UV-mapped, with outline).
	lib["toon_mak_cream"] = toon(Color(1.0, 0.93, 0.84), "", 0.0, true)
	lib["toon_mak_pink"] = toon(Color(1.0, 0.62, 0.66), "", 0.0, true)
	lib["toon_mak_hoof"] = toon(Color(0.42, 0.27, 0.18), "", 0.0, true)
	var gold := toon(Color(1.0, 0.76, 0.22), "", 0.0, true)
	gold.set_shader_parameter("emission_color", Color(1.0, 0.6, 0.15))
	gold.set_shader_parameter("emission_energy", 0.35)
	gold.set_shader_parameter("spec_strength", 1.2)
	gold.set_shader_parameter("rim_strength", 0.9)
	lib["toon_truffle_gold"] = gold
	var glass := toon(Color.WHITE, "stained_glass", 0.5)
	glass.set_shader_parameter("emission_color", Color(1.0, 0.85, 0.6))
	glass.set_shader_parameter("emission_energy", 0.6)
	lib["toon_stained_glass_glow"] = glass
	# Foliage spheres with the painted leaf texture (tree canopies that sway).
	var canopy := ShaderMaterial.new()
	canopy.shader = load("res://assets/shaders/foliage.gdshader")
	canopy.set_shader_parameter("albedo_texture", load(T + "leaf_canopy.webp"))
	canopy.set_shader_parameter("base_color", Color(0.85, 0.95, 0.85))
	canopy.set_shader_parameter("tip_color", Color(1.1, 1.1, 0.95))
	canopy.set_shader_parameter("sway_height", 7.0)
	canopy.set_shader_parameter("wind_strength", 0.22)
	canopy.set_shader_parameter("flutter", 0.02)
	lib["foliage_tree_canopy_textured"] = canopy
	# Liquids and clouds.
	var w := ShaderMaterial.new()
	w.shader = load("res://assets/shaders/water.gdshader")
	lib["water_stream"] = w
	var wf := ShaderMaterial.new()
	wf.shader = load("res://assets/shaders/water.gdshader")
	wf.set_shader_parameter("flow_along_uv", true)
	wf.set_shader_parameter("flow_speed", 1.2)
	lib["water_stream_ribbon"] = wf
	var cr := ShaderMaterial.new()
	cr.shader = load("res://assets/shaders/hot_chocolate.gdshader")
	cr.set_shader_parameter("edge_mode", 1)
	lib["hot_chocolate_river"] = cr
	var cp := ShaderMaterial.new()
	cp.shader = load("res://assets/shaders/hot_chocolate.gdshader")
	cp.set_shader_parameter("edge_mode", 2)
	cp.set_shader_parameter("round_clip", true)
	lib["hot_chocolate_pool"] = cp
	var cl := ShaderMaterial.new()
	cl.shader = load("res://assets/shaders/cloud.gdshader")
	lib["cloud_platform"] = cl
	# Foliage.
	lib["foliage_grass"] = FxScatter.grass_material()
	lib["foliage_flowers"] = FxScatter.flower_material()
	var leaf := ShaderMaterial.new()
	leaf.shader = load("res://assets/shaders/foliage.gdshader")
	leaf.set_shader_parameter("base_color", Color(0.22, 0.5, 0.2))
	leaf.set_shader_parameter("tip_color", Color(0.5, 0.78, 0.26))
	leaf.set_shader_parameter("sway_height", 7.0)
	leaf.set_shader_parameter("wind_strength", 0.25)
	leaf.set_shader_parameter("flutter", 0.02)
	lib["foliage_tree_canopy"] = leaf
	var beanstalk := leaf.duplicate() as ShaderMaterial
	beanstalk.set_shader_parameter("base_color", Color(0.18, 0.5, 0.18))
	beanstalk.set_shader_parameter("tip_color", Color(0.55, 0.85, 0.3))
	beanstalk.set_shader_parameter("sway_height", 20.0)
	beanstalk.set_shader_parameter("wind_strength", 0.15)
	lib["foliage_beanstalk_leaf"] = beanstalk
	return lib


static func save_library() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var lib := library()
	for k in lib:
		var err := ResourceSaver.save(lib[k], DIR + k + ".tres")
		if err != OK:
			push_warning("[FxMaterials] could not save " + k)
	# Grass and flower meshes for MultiMesh scatter.
	ResourceSaver.save(FxScatter.make_grass_tuft(), DIR + "mesh_grass_tuft.tres")
	ResourceSaver.save(FxScatter.make_flower(Color(1.0, 0.85, 0.25)), DIR + "mesh_flower_yellow.tres")
	ResourceSaver.save(FxScatter.make_flower(Color(1.0, 1.0, 1.0)), DIR + "mesh_flower_white.tres")
	ResourceSaver.save(FxScatter.make_flower(Color(1.0, 0.55, 0.7)), DIR + "mesh_flower_pink.tres")
	print("[FxMaterials] saved ", lib.size(), " materials and 4 meshes to ", DIR)

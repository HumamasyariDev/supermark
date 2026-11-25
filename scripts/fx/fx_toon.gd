class_name FxToon
extends RefCounted
## Converts imported glTF / StandardMaterial3D surfaces under a node to the Super Mak 64 toon look
## (two-tone ramp, coloured shade, rim light, optional ink outline), keeping albedo textures, colours
## and normal maps. Materials are cached, so many instances of one enemy share one toon material.
##
##   FxToon.apply($Visual)                                   # characters, enemies, pickups
##   FxToon.apply($Visual, {"outline": false, "rim": 0.3})   # props / buildings
##   FxToon.flash(mesh_root, 0.12)                           # white hit flash on every toon surface (per instance)
## Options: outline (true), outline_width (2.0), outline_color, rim (0.45), shadow_tint, spec (0.35),
##          normal_strength (0.6), skip_transparent (true).

const TOON := preload("res://assets/shaders/toon.gdshader")
const OUTLINE := preload("res://assets/shaders/outline.gdshader")

static var _cache: Dictionary = {}


static func apply(root: Node, opts: Dictionary = {}) -> int:
	var n := 0
	for mi in _meshes(root):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src: Material = mi.get_surface_override_material(s)
			if src == null:
				src = mesh.surface_get_material(s)
			var toon: Material = to_toon(src, opts)
			if toon != null:
				mi.set_surface_override_material(s, toon)
				n += 1
	return n


static func to_toon(src: Material, opts: Dictionary = {}) -> Material:
	if src is ShaderMaterial and (src as ShaderMaterial).shader == TOON:
		return src
	var base := src as BaseMaterial3D
	if base != null and opts.get("skip_transparent", true) and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return null
	var key := "%s|%s" % [src.get_instance_id() if src != null else 0, str(opts)]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	if base != null:
		m.set_shader_parameter("albedo", base.albedo_color)
		if base.albedo_texture != null:
			m.set_shader_parameter("albedo_texture", base.albedo_texture)
		if base.normal_enabled and base.normal_texture != null:
			m.set_shader_parameter("normal_texture", base.normal_texture)
			m.set_shader_parameter("use_normal_map", true)
			m.set_shader_parameter("normal_strength", opts.get("normal_strength", 0.6))
		if base.emission_enabled:
			m.set_shader_parameter("emission_color", base.emission)
			m.set_shader_parameter("emission_energy", base.emission_energy_multiplier)
		m.set_shader_parameter("use_vertex_color", base.vertex_color_use_as_albedo)
		m.set_shader_parameter("roughness_value", clampf(base.roughness, 0.5, 1.0))
	m.set_shader_parameter("rim_strength", opts.get("rim", 0.45))
	m.set_shader_parameter("spec_strength", opts.get("spec", 0.35))
	if opts.has("shadow_tint"):
		m.set_shader_parameter("shadow_tint", opts["shadow_tint"])
	if opts.get("outline", true):
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("outline_width", opts.get("outline_width", 2.0))
		if opts.has("outline_color"):
			o.set_shader_parameter("outline_color", opts["outline_color"])
		m.next_pass = o
	_cache[key] = m
	return m


## Per-instance white flash (uses the toon shader's instance uniform). Safe on non-toon meshes.
static func flash(root: Node, seconds := 0.12, strength := 1.0) -> void:
	var meshes := _meshes(root)
	if meshes.is_empty():
		return
	if OS.has_feature("web"):
		_flash_web(root, meshes, seconds, strength)
		return
	for mi in meshes:
		mi.set_instance_shader_parameter("flash", strength)
	var tw := root.create_tween()
	tw.tween_method(func(v: float) -> void:
		for mi in meshes:
			if is_instance_valid(mi):
				mi.set_instance_shader_parameter("flash", v), strength, 0.0, seconds)


static func _flash_web(root: Node, meshes: Array[MeshInstance3D], seconds: float, strength: float) -> void:
	var materials: Array[ShaderMaterial] = []
	for mi in meshes:
		prepare_web_flash(mi)
		if mi.material_override is ShaderMaterial and mi.material_override.get_shader_parameter("flash") != null:
			mi.material_override.set_shader_parameter("flash", strength)
			materials.append(mi.material_override)
			continue
		if mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var source := mi.get_active_material(surface) as ShaderMaterial
			if source == null or source.get_shader_parameter("flash") == null:
				continue
			# A local material is needed only for characters that actually flash.
			# The shader stays shared and already compiled.
			var material := source
			material.set_shader_parameter("flash", strength)
			materials.append(material)
	var tween := root.create_tween()
	tween.tween_method(func(value: float) -> void:
		for material in materials:
			material.set_shader_parameter("flash", value), strength, 0.0, seconds)


static func prepare_web_flash(root: Node) -> void:
	if not OS.has_feature("web"):
		return
	for mi in _meshes(root):
		if mi.has_meta("web_flash_ready") or mi.mesh == null:
			continue
		mi.set_meta("web_flash_ready", true)
		if mi.material_override is ShaderMaterial and mi.material_override.get_shader_parameter("flash") != null:
			mi.material_override = mi.material_override.duplicate()
			continue
		for surface in mi.mesh.get_surface_count():
			var source := mi.get_active_material(surface) as ShaderMaterial
			if source != null and source.get_shader_parameter("flash") != null:
				mi.set_surface_override_material(surface, source.duplicate())


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(root, out)
	return out


static func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)

class_name ObjFx
extends RefCounted
## Small one-shot feedback effects owned by the objects workstream (fallbacks under the Juice bus):
## flash discs, star rings, ground shock rings, puffs. Every node frees itself and keeps running while the
## tree is paused (the truffle celebration pauses the game).


static func _additive(color: Color, tex: Texture2D, billboard: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	m.albedo_texture = tex
	m.albedo_color = color
	return m


static func _quad(parent: Node, size: float, m: Material) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(mi)
	return mi


## A bright billboard disc that swells and fades (collect flashes).
static func flash(parent: Node, at: Vector3, size: float = 1.6, grow: float = 2.2, color: Color = Color(1, 0.95, 0.75, 0.9), dur: float = 0.3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var m := _additive(Color(1, 1, 1, 1), ObjSvc.radial_tex(color, Color(color.r, color.g * 0.8, color.b * 0.4, 0.0)))
	var mi := _quad(parent, size, m)
	mi.global_position = at
	mi.scale = Vector3.ONE * 0.3
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * grow, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)


## Four-point stars flying outward in a ring and shrinking away.
static func star_ring(parent: Node, at: Vector3, count: int = 8, dist: float = 1.3, size: float = 0.5, color: Color = Color(1, 0.92, 0.6), dur: float = 0.5) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var m := _additive(color, ObjGlints.star_tex())
	for i in count:
		var mi := _quad(parent, size, m)
		mi.global_position = at
		var a := TAU * float(i) / float(count) + randf() * 0.3
		var dir := Vector3(cos(a), 0.3 + 0.35 * sin(a * 2.0 + 0.5), sin(a))
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "global_position", at + dir * dist * randf_range(0.8, 1.1), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.05, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)


static var _ring_tex: Texture2D


static func ring_tex() -> Texture2D:
	if _ring_tex != null:
		return _ring_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.8, 0.9, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_ring_tex = t
	return t


## A flat ring that expands along the ground (bounce pads, landings, slams, door thuds).
static func ground_ring(parent: Node, at: Vector3, radius: float = 1.5, color: Color = Color(1, 0.95, 0.8, 0.8), dur: float = 0.35) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var m := _additive(color, ring_tex(), false)
	var q := PlaneMesh.new()
	q.size = Vector2(2.0, 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(mi)
	mi.global_position = at + Vector3(0, 0.04, 0)
	mi.scale = Vector3.ONE * radius * 0.3
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * radius, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Soft round puffs (dust, wood dust, paper puff) that drift up and fade. Normal (non-additive) blending.
static func puffs(parent: Node, at: Vector3, color: Color, count: int = 6, spread: float = 0.6, size: float = 0.6, dur: float = 0.7) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for i in count:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.albedo_texture = ObjSvc.radial_tex(Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0))
		m.albedo_color = color
		var mi := _quad(parent, size, m)
		var a := TAU * float(i) / float(count) + randf() * 0.5
		var off := Vector3(cos(a), 0.0, sin(a)) * spread * randf_range(0.4, 1.0)
		mi.global_position = at + off * 0.3
		mi.scale = Vector3.ONE * 0.4
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "global_position", at + off + Vector3(0, randf_range(0.2, 0.6), 0), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(mi, "scale", Vector3.ONE * randf_range(1.0, 1.5), dur).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)

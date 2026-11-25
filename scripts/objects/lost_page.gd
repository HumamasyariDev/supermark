class_name LostPage
extends Area3D
## A torn storybook page fluttering in the air (the generated lost_page.glb, bent by a flutter vertex shader that
## ripples from the torn edge). Five per world; a LostPageSet spawns a truffle when all are found.
## Collect -> Game.collect_page(world_id, page_index).

signal collected(world_id: String, page_index: int)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var world_id: String = ""
@export_range(0, 4) var page_index: int = 0
@export var hover_height: float = 1.1
## Uses the generated page mesh when no visual_scene is set and the file exists.
@export var use_default_mesh: bool = true
@export var flutter_amount: float = 0.045

const DEFAULT_MESH := "res://assets/props/pickups/lost_page/lost_page.glb"
const DEFAULT_MESH_SCALE := 1.5
const FLUTTER_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 tint : source_color = vec4(1.0);
uniform float amp = 0.045;
uniform float speed = 6.0;
uniform float phase = 0.0;
uniform float emission = 0.14;
uniform float glow = 0.0;
uniform float alpha_scissor = 0.5;
void vertex() {
	float t = TIME * speed + phase;
	// Ripples run in from the torn left edge (UV.x = 0); the right edge and corners lift most.
	float w = sin(t + UV.x * 4.2 + UV.y * 1.3) * 0.6 + sin(t * 0.73 + UV.y * 3.1 + UV.x) * 0.4;
	VERTEX.z += w * amp * (0.35 + UV.x * 0.9) * (0.7 + 0.6 * abs(UV.y - 0.5));
}
void fragment() {
	vec4 c = texture(albedo_tex, UV) * tint;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = 0.85;
	EMISSION = c.rgb * (emission + glow);
	BACKLIGHT = vec3(0.35, 0.3, 0.2);
}
"""

static var _flutter_shader: Shader

var is_collected := false
## Already collected on an earlier visit: shown as a translucent ghost (no count, no popup), like owned truffles.
var is_ghost := false
var _t := 0.0
var _visual: Node3D
var _flutter: Node3D
var _page_mat: ShaderMaterial


func _ready() -> void:
	ObjSvc.ensure_npc_life_auto(self)
	add_to_group("lost_page")
	if world_id == "":
		world_id = ObjSvc.current_world()
	collision_layer = ObjSvc.L_PICKUP
	collision_mask = ObjSvc.L_PLAYER
	ObjSvc.add_shape(self, ObjSvc.sphere_shape(0.7), Vector3(0, hover_height, 0))
	_visual = ObjSvc.ensure_visual(self)
	_flutter = Node3D.new()
	_flutter.position = Vector3(0, hover_height, 0)
	add_child(_flutter)
	_visual.reparent(_flutter, false)
	if not ObjSvc.visual_has_content(_visual):
		if use_default_mesh and ResourceLoader.exists(DEFAULT_MESH):
			visual_scene = load(DEFAULT_MESH) as PackedScene
			visual_scale = DEFAULT_MESH_SCALE
			ObjSvc.fill_visual(self, _visual)
	if not ObjSvc.visual_has_content(_visual):
		_build_placeholder()
		_visual.scale = Vector3.ONE * 1.5
	else:
		ObjSvc.center_generated(_visual)
		_apply_flutter_shader()
		_add_halo()
	ObjSvc.shadow_blob(self, 0.4, 0.02, 0.3)
	ObjSvc.twinkles(_flutter, Color(1.0, 0.95, 0.75), 5, 0.5, 0.09, 0.45)
	var gl := ObjGlints.new()
	gl.count = 2
	gl.radius = 0.4
	gl.size = 0.18
	gl.period = 1.8
	gl.color = Color(1.0, 0.93, 0.7)
	_flutter.add_child(gl)
	_t = float(page_index) * 1.3
	if ObjSvc.can("Game", "has_page") and bool(ObjSvc.call_on("Game", "has_page", [world_id, page_index])):
		_apply_ghost()
	body_entered.connect(func(b: Node) -> void:
		if ObjSvc.is_player(b):
			collect())
	_unbury.call_deferred()


func _apply_ghost() -> void:
	is_ghost = true
	# Monitoring stays on: a touch gives a quiet rustle and a flutter (no count, no popup).
	var g := ObjSvc.ghost_mat()
	for mi in _visual.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = g
	_page_mat = null
	for c in _flutter.get_children():
		if c is GPUParticles3D or c is ObjGlints or (c is MeshInstance3D and c.name == "Halo"):
			c.visible = false


func _unbury() -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	if is_inside_tree() and not is_collected:
		ObjSvc.unbury(self, Vector3(0, hover_height, 0), 0.22)


## Swaps the page's StandardMaterial3D for the flutter shader, keeping its parchment texture.
func _apply_flutter_shader() -> void:
	if _flutter_shader == null:
		_flutter_shader = Shader.new()
		_flutter_shader.code = FLUTTER_SHADER
	for mi in _visual.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var src := m.mesh.surface_get_material(0) as StandardMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = _flutter_shader
		if src != null:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			sm.set_shader_parameter("tint", src.albedo_color)
		sm.set_shader_parameter("amp", flutter_amount / maxf(visual_scale, 0.01))
		sm.set_shader_parameter("phase", float(page_index) * 1.7)
		m.material_override = sm
		_page_mat = sm


func _add_halo() -> void:
	var halo := QuadMesh.new()
	halo.size = Vector2(1.3, 1.3)
	var hm := ObjSvc.unshaded(Color(1, 1, 1, 1), true)
	hm.albedo_texture = ObjSvc.radial_tex(Color(1.0, 0.9, 0.6, 0.3), Color(1.0, 0.8, 0.4, 0.0))
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.render_priority = -1
	var hmi := ObjSvc.add_mesh(_flutter, halo, hm)
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hmi.name = "Halo"


func _build_placeholder() -> void:
	# A torn, warm parchment page from the storybook: two leaves at a slight fold, a gold-leaf border,
	# a red illuminated capital, ink lines, a torn bottom edge and a soft golden glow.
	var paper := ObjSvc.unique_mat(Color(1.0, 0.93, 0.76), 0.85, 0.0, Color(1.0, 0.85, 0.55), 0.35)
	paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gold := ObjSvc.mat(ObjSvc.GOLD, 0.3, 0.8, ObjSvc.GOLD, 0.4)
	var ink := ObjSvc.mat(Color(0.3, 0.2, 0.13), 0.9)
	var red := ObjSvc.mat(ObjSvc.BURGUNDY, 0.5, 0.0, ObjSvc.BURGUNDY, 0.2)
	for side in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.position = Vector3(side * 0.16, 0, 0.015 if side > 0 else 0.0)
		leaf.rotation_degrees = Vector3(0, -side * 12.0, 0)
		_visual.add_child(leaf)
		ObjSvc.box(leaf, Vector3(0.32, 0.6, 0.012), paper)
		# Gold border on top and outer edges.
		ObjSvc.box(leaf, Vector3(0.32, 0.018, 0.016), gold, Vector3(0, 0.29, 0))
		ObjSvc.box(leaf, Vector3(0.018, 0.6, 0.016), gold, Vector3(side * 0.152, 0, 0))
		# Torn bottom edge: little paper teeth.
		for k in 5:
			ObjSvc.box(leaf, Vector3(0.05, 0.05, 0.012), paper, Vector3(-0.13 + k * 0.065, -0.31 - (k % 2) * 0.012, 0), Vector3(0, 0, 45))
		if side < 0:
			ObjSvc.box(leaf, Vector3(0.08, 0.08, 0.016), red, Vector3(-0.08, 0.19, 0.004))
			for i in 4:
				ObjSvc.box(leaf, Vector3(0.2 - (i % 2) * 0.05, 0.02, 0.016), ink, Vector3(0.0 + (0.03 if i < 1 else 0.0), 0.1 - i * 0.075, 0.002))
		else:
			for i in 5:
				ObjSvc.box(leaf, Vector3(0.22 - (i % 3) * 0.04, 0.02, 0.016), ink, Vector3(0, 0.17 - i * 0.075, 0.002))
	var num := ObjSvc.label(_visual, str(page_index + 1), Vector3(0.18, -0.2, 0.04), 80, ObjSvc.BURGUNDY, false)
	num.rotation_degrees = Vector3(0, -12, 0)
	num.outline_size = 0
	# Soft glow card behind the page.
	var halo := QuadMesh.new()
	halo.size = Vector2(1.2, 1.2)
	var hm := ObjSvc.unshaded(Color(1, 1, 1, 1), true)
	hm.albedo_texture = ObjSvc.radial_tex(Color(1.0, 0.9, 0.6, 0.4), Color(1.0, 0.8, 0.4, 0.0))
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var hmi := ObjSvc.add_mesh(_visual, halo, hm)
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if is_collected:
		return
	_t += delta
	# Drifts like paper on a draught: a slow bob with a little side-slip, a lazy turn that hesitates, a rocking tilt.
	_flutter.position = Vector3(sin(_t * 0.9) * 0.08, hover_height + sin(_t * 1.7) * 0.15 + sin(_t * 4.1) * 0.02, cos(_t * 0.7) * 0.06) + _touch_off
	_flutter.rotation = Vector3(sin(_t * 2.3) * 0.25, _t * 1.0 + sin(_t * 0.8) * 0.5, sin(_t * 3.1) * 0.18 + sin(_t * 1.3) * 0.08) + _touch_rot


func collect() -> void:
	if is_ghost and not is_collected:
		_ghost_touch()
		return
	if is_collected or is_ghost:
		return
	is_collected = true
	set_deferred("monitoring", false)
	ObjSvc.call_on("Game", "collect_page", [world_id, page_index])
	var at := _flutter.global_position
	ObjSvc.feedback("object_page_collect", at, {"world": world_id, "index": page_index}, "page_collect")
	collected.emit(world_id, page_index)
	get_tree().call_group("lost_page_listener", "on_page_collected", world_id, page_index)
	if not ObjSvc.juice_handles("object_page_collect", "vfx"):
		if not ObjSvc.fx(self, "PageFlutter", at):
			ObjSvc.burst(get_parent(), at, ObjSvc.PAPER, 16, 3.0, 0.15, -1.5, 0.9)
		ObjFx.flash(get_parent(), at, 1.2, 2.0, Color(1.0, 0.93, 0.7, 0.8), 0.25)
		ObjFx.star_ring(get_parent(), at, 5, 0.9, 0.34, Color(1.0, 0.93, 0.7), 0.4)
	# The page snaps flat (flutter stops), flips twice as it rises, and folds away into a sliver.
	if _page_mat:
		_page_mat.set_shader_parameter("amp", 0.0)
		_page_mat.set_shader_parameter("glow", 0.8)
	var tw := create_tween().set_parallel()
	tw.tween_property(_flutter, "position:y", _flutter.position.y + 1.3, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_flutter, "rotation:y", _flutter.rotation.y + TAU * 2.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_flutter, "rotation:x", 0.0, 0.2)
	tw.tween_property(_flutter, "rotation:z", 0.0, 0.2)
	tw.tween_property(_flutter, "scale", Vector3(1.25, 1.25, 1.25), 0.2)
	tw.chain().tween_property(_flutter, "scale", Vector3(0.01, 1.4, 0.01), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


## Round 1 QA: touching a page found on an earlier visit gave no feedback at all. Now a quiet paper rustle and a small
## ghost flutter (a lift, a sway and a shimmer of the ghost), at most once every 2 s; nothing is counted.
var _ghost_touch_at := -10.0
var _touch_off := Vector3.ZERO
var _touch_rot := Vector3.ZERO


func _ghost_touch() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _ghost_touch_at < 2.0:
		return
	_ghost_touch_at = now
	var at := _flutter.global_position
	ObjSvc.feedback_optional("object_page_ghost_touch", at, {"world": world_id, "index": page_index}, "page_turn")
	var tw := create_tween()
	tw.tween_property(self, "_touch_off", Vector3(0, 0.22, 0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "_touch_rot", Vector3(0.25, 0.9, -0.2), 0.18)
	tw.tween_property(self, "_touch_rot", Vector3(-0.15, 0.4, 0.15), 0.22).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "_touch_off", Vector3.ZERO, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "_touch_rot", Vector3.ZERO, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if not ObjSvc.juice_handles("object_page_ghost_touch", "vfx"):
		ObjFx.puffs(get_parent(), at, Color(0.75, 0.85, 1.0, 0.45), 4, 0.3, 0.3, 0.5)

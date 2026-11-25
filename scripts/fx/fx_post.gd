class_name FxPost
extends MeshInstance3D
## Storybook post-process: soft ink lines (depth/normal edges, an alpha overlay that never reads the
## screen, so water refraction stays intact) plus a canvas grade layer (split-tone, vignette, paper grain).
## Drop res://scenes/fx/StorybookPost.tscn anywhere in a world scene (camera-independent).
## The grade layer sits on CanvasLayer -10, under any HUD layer >= 0.

@export_range(0.0, 1.0) var line_strength := 0.45
@export_range(0.0, 1.0) var vignette := 0.18
@export_range(0.0, 0.3) var paper_amount := 0.025
@export var grade_enabled := true

var _mat: ShaderMaterial
var _grade: ShaderMaterial
var _layer: CanvasLayer


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	mesh = q
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/post_storybook.gdshader")
	_mat.render_priority = 127
	material_override = _mat
	if grade_enabled:
		_layer = CanvasLayer.new()
		_layer.layer = -10
		add_child(_layer)
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grade = ShaderMaterial.new()
		_grade.shader = load("res://assets/shaders/post_grade.gdshader")
		_grade.set_shader_parameter("paper_tex", load("res://assets/textures/parchment.webp"))
		rect.material = _grade
		_layer.add_child(rect)
	apply()


func apply() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("line_strength", line_strength)
	if _grade != null:
		var size := get_viewport().get_visible_rect().size
		_grade.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
		_grade.set_shader_parameter("vignette", vignette)
		_grade.set_shader_parameter("paper_amount", paper_amount)

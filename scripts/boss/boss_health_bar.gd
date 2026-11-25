class_name BossHealthBar
extends CanvasLayer
## Storybook boss bar: a parchment name plate with the boss name, the phase title and one
## brass pip per remaining hit. In group "hud" so --hide-hud gives clean story frames.

const PARCHMENT := Color("f6e8c8")
const INK := Color("4a2c17")
const RIBBON := Color("8e1f2f")
const BRASS := Color("d9a93f")
const FONT_UI := "res://assets/fonts/fredoka/Fredoka-Variable.ttf"
const FONT_DISPLAY := "res://assets/fonts/cherryswash/CherrySwash-Bold.ttf"

var _root: Control
var _name: Label
var _phase: Label
var _pips: HBoxContainer
var _total: int = 3


func _ready() -> void:
	layer = 20
	add_to_group("hud")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PARCHMENT
	sb.border_color = INK
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(22)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-330, 28)
	panel.custom_minimum_size = Vector2(660, 0)
	_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_color_override("font_color", RIBBON)
	_name.add_theme_font_size_override("font_size", 40)
	if ResourceLoader.exists(FONT_DISPLAY):
		_name.add_theme_font_override("font", load(FONT_DISPLAY) as Font)
	vb.add_child(_name)
	_phase = Label.new()
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase.add_theme_color_override("font_color", INK)
	_phase.add_theme_font_size_override("font_size", 24)
	if ResourceLoader.exists(FONT_UI):
		_phase.add_theme_font_override("font", load(FONT_UI) as Font)
	vb.add_child(_phase)
	_pips = HBoxContainer.new()
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_pips.add_theme_constant_override("separation", 14)
	vb.add_child(_pips)
	visible = false


func show_bar(boss_name: String, total_hits: int) -> void:
	_name.text = boss_name
	_total = total_hits
	set_remaining(total_hits)
	visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.5)


func set_phase_title(t: String) -> void:
	_phase.text = t


func set_remaining(n: int) -> void:
	for c in _pips.get_children():
		c.queue_free()
	for i in _total:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(46, 22)
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(11)
		s.set_border_width_all(4)
		s.border_color = INK
		s.bg_color = BRASS if i < n else Color(0.75, 0.68, 0.55, 0.5)
		pip.add_theme_stylebox_override("panel", s)
		_pips.add_child(pip)
		if i == n:
			pip.pivot_offset = Vector2(23, 11)
			pip.scale = Vector2(1.5, 1.5)
			pip.create_tween().tween_property(pip, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)


func hide_bar() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void: visible = false)

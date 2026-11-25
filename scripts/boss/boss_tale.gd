class_name BossTale
extends CanvasLayer
## The Wolf's Own Tale on the HUD: a parchment strip under the cake that typewrites the wolf's version
## of events (BOSS_amendments R1.6 / R2.7). In group "hud" so --hide-hud gives clean story frames.

const PARCHMENT := Color("f3e6c4")
const INK := Color("3b2416")
const FONT_UI := "res://assets/fonts/cherryswash/CherrySwash-Bold.ttf"

var _panel: PanelContainer
var _label: Label
var _hide_t := 0.0
var _tw: Tween


func _ready() -> void:
	layer = 19
	add_to_group("hud")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PARCHMENT
	sb.border_color = INK
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 8
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -520
	_panel.offset_right = 520
	_panel.offset_top = -150
	_panel.offset_bottom = -60
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_color_override("font_color", INK)
	_label.add_theme_font_size_override("font_size", 30)
	if ResourceLoader.exists(FONT_UI):
		_label.add_theme_font_override("font", load(FONT_UI) as Font)
	_panel.add_child(_label)
	_panel.modulate.a = 0.0


func say(text: String, seconds: float = 4.5) -> void:
	# Finish pass (boss QA minor: an empty narration panel showed during the POP flash): no text, no panel.
	if text.strip_edges() == "":
		_hide_t = 0.01
		return
	_label.text = text
	_label.visible_ratio = 0.0
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(_panel, "modulate:a", 1.0, 0.2)
	_tw.parallel().tween_property(_label, "visible_ratio", 1.0, clampf(float(text.length()) * 0.025, 0.4, 1.4))
	_hide_t = seconds


func _process(delta: float) -> void:
	if _hide_t > 0.0:
		_hide_t -= delta
		if _hide_t <= 0.0:
			create_tween().tween_property(_panel, "modulate:a", 0.0, 0.4)

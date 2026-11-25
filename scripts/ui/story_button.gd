class_name StoryButton
extends Button
## Storybook menu button: ink text on parchment; focused or hovered it becomes a burgundy
## ribbon with brass edges and a little truffle bullet. Keyboard, mouse and gamepad friendly.

@export var caption: String = "":
	set(v):
		caption = v
		queue_redraw()
@export var font_size: int = 34
@export var hint: String = ""
## Draw a faint parchment chip with an ink outline while unfocused, so a lone choice in a confirm still
## reads as a button (critique UI r1: the unfocused confirm choice was bare text).
@export var chip := false
## 0..1 entrance (slides in from the left and fades); menus tween it for staggered reveals.
var appear := 1.0:
	set(v):
		appear = v
		queue_redraw()
var _press_t := 0.0

var _hl := 0.0
var _t := 0.0


func _init(p_caption: String = "", p_size: int = 34) -> void:
	caption = p_caption
	font_size = p_size
	text = ""
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(380, p_size * 1.75)
	mouse_entered.connect(func() -> void:
		var ui := get_node_or_null("/root/UI")
		if not disabled and (ui == null or not ui.has_method("mouse_active") or bool(ui.call("mouse_active"))):
			grab_focus())
	focus_entered.connect(func() -> void:
		if is_visible_in_tree() and appear > 0.5:
			UIFx.event("ui_move", {"button": caption}))
	pressed.connect(func() -> void:
		_press_t = 1.0
		UIFx.event("ui_accept", {"button": caption}))
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())


func _process(delta: float) -> void:
	var target := 1.0 if (has_focus() and not disabled) else 0.0
	_t += delta
	if _press_t > 0.0:
		_press_t = maxf(0.0, _press_t - delta * 3.0)
		queue_redraw()
	var ma := clampf(appear * 1.6, 0.0, 1.0)
	if absf(modulate.a - ma) > 0.001:
		modulate.a = ma
	if absf(_hl - target) > 0.001 or target > 0.0:
		_hl = move_toward(_hl, target, delta * 7.0)
		queue_redraw()


func _draw() -> void:
	var f := UIStyle.ui_font(650)
	var r := Rect2(Vector2.ZERO, size)
	var e := ease(_hl, -2.0)
	var ap := UIFx.back_out(appear)
	var squash := UIFx.pop(_press_t) * 0.08
	draw_set_transform(Vector2((1.0 - ap) * -90.0, 0) + size * 0.5 * Vector2(squash, -squash), 0.0, Vector2(1.0 - squash, 1.0 + squash))

	if chip and e < 0.99:
		var cb := StyleBoxFlat.new()
		cb.bg_color = Color(UIStyle.PARCHMENT_DARK, 0.4 * (1.0 - e))
		cb.border_color = Color(UIStyle.INK_SOFT, 0.75 * (1.0 - e))
		cb.set_border_width_all(2)
		cb.set_corner_radius_all(int(size.y * 0.3))
		cb.anti_aliasing = true
		draw_style_box(cb, Rect2(18, size.y * 0.12, size.x - 36, size.y * 0.76))
	if e > 0.01:
		var inset := lerpf(size.x * 0.25, 18.0, e)
		var band := Rect2(inset, size.y * 0.1, size.x - inset * 2.0, size.y * 0.8)
		UIDraw.ribbon(self, band, Color(UIStyle.RIBBON, e), Color(UIStyle.BRASS, e))
		var bob := sin(_t * 5.0) * 3.0
		# the generated truffle icon, same art as the HUD and the book (critique UI r1: procedural blob)
		var bt := UIFx.tex("truffle")
		var bc := Vector2(band.position.x + 30, size.y * 0.5 + bob)
		if bt:
			UIFx.draw_icon(self, bt, bc, size.y * 0.46 * (0.6 + 0.4 * e), sin(_t * 2.4) * 0.12, Color(1, 1, 1, e))
		else:
			UIDraw.truffle(self, bc, size.y * 0.2, true, _t)
	var col := UIStyle.INK.lerp(UIStyle.CREAM, e)
	if disabled:
		col = Color(UIStyle.INK, 0.35)
	var fs := int(font_size * (1.0 + 0.06 * e))
	var tw := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2((size.x - tw) * 0.5, (size.y + f.get_ascent(fs) - f.get_descent(fs)) * 0.5)
	if e > 0.01:
		draw_string_outline(f, pos + Vector2(0, 3), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(UIStyle.RIBBON_DARK, e * 0.8))
	draw_string(f, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if hint != "" and e > 0.01:
		var hs := int(fs * 0.5)
		draw_string(UIStyle.ui_font(500), Vector2(pos.x + tw + 14, pos.y), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(UIStyle.BRASS_LIGHT, e))

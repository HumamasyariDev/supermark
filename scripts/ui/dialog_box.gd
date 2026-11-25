extends Control
## Storybook dialog box (v2): parchment panel that pops up from the bottom, a ribbon name plate
## coloured per speaker, a live 3D portrait of the speaker (the real generated GLB, framed on the
## bust, gently bobbing while the line types), typewriter text with soft blips and a button
## prompt (keyboard or controller glyph) when the line is complete.
## Advance with interact or jump (or ui_accept / click). The first press completes the line.

signal finished
signal line_shown(index: int)

const CHARS_PER_SEC := 50.0
var _lines: Array = []
var _index := 0
var _speaker := ""
var _visible_chars := 0.0
var _open := false
var _closing := false
var _panel: PanelContainer
var _text: Label
var _plate: PanelContainer
var _plate_label: Label
var _plate_mat: ShaderMaterial
var _plate_ribbon: _PlateRibbon
var _narrator_icon: _NarratorIcon
var _narrator := false
var _portrait_frame: _Frame
var _portrait: UIModelView
var _prompt: _Prompt
var _t := 0.0
var _blip_acc := 0.0
var _input_grace := 0.0
var _plate_pop := 0.0
var _talk := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIStyle.theme()
	_panel = UIStyle.panel("parchment", 40)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -700
	_panel.offset_right = 800
	_panel.offset_top = -300
	_panel.offset_bottom = -48
	add_child(_panel)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 30)
	m.add_theme_constant_override("margin_left", 190)
	m.add_theme_constant_override("margin_right", 70)
	_panel.add_child(m)
	_text = UIStyle.label("", 38, UIStyle.INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text.custom_minimum_size = Vector2(1160, 170)
	m.add_child(_text)
	# portrait: a gilt oval frame with the speaker's real 3D model
	_portrait_frame = _Frame.new()
	_portrait_frame.anchor_left = 0.5
	_portrait_frame.anchor_right = 0.5
	_portrait_frame.anchor_top = 1.0
	_portrait_frame.anchor_bottom = 1.0
	_portrait_frame.offset_left = -820
	_portrait_frame.offset_right = -500
	_portrait_frame.offset_top = -380
	_portrait_frame.offset_bottom = -40
	add_child(_portrait_frame)
	_portrait = UIModelView.new()
	_portrait.position = Vector2(22, 22)
	_portrait.size = Vector2(276, 296)
	_portrait.bust_fraction = 0.5
	_portrait.sway = 0.22
	_portrait_frame.add_child(_portrait)
	_portrait_frame.view = _portrait
	# name plate
	# critique UI r1: the name plate was a plain rectangle; it is now the tailed ribbon used by the
	# banners, menu focus bars and mission rows, still tinted per speaker
	_plate = PanelContainer.new()
	var psb := StyleBoxEmpty.new()
	psb.content_margin_left = 40
	psb.content_margin_right = 40
	psb.content_margin_top = 10
	psb.content_margin_bottom = 12
	_plate.add_theme_stylebox_override("panel", psb)
	_plate_ribbon = _PlateRibbon.new()
	_plate_ribbon.show_behind_parent = true
	_plate_ribbon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plate_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.anchor_left = 0.5
	_plate.anchor_right = 0.5
	_plate.anchor_top = 1.0
	_plate.anchor_bottom = 1.0
	_plate.offset_left = -500
	_plate.offset_top = -342
	_plate.offset_bottom = -272
	_plate.offset_right = -200
	_plate.grow_horizontal = Control.GROW_DIRECTION_END
	add_child(_plate)
	_plate_label = UIStyle.label("", 40, UIStyle.BRASS_LIGHT, true, 6, UIStyle.RIBBON_DARK)
	_plate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plate.add_child(_plate_label)
	_plate.add_child(_plate_ribbon)
	_plate.move_child(_plate_ribbon, 0)
	# narrator / system lines: a compact centred card with a small open-book mark
	_narrator_icon = _NarratorIcon.new()
	_narrator_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narrator_icon.size = Vector2(64, 48)
	_narrator_icon.visible = false
	_panel.add_child(_narrator_icon)
	_prompt = _Prompt.new()
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = 690
	_prompt.offset_right = 770
	_prompt.offset_top = -126
	_prompt.offset_bottom = -66
	add_child(_prompt)
	visible = false


class _Frame:
	extends Control
	var view: UIModelView
	var tint := Color("8e1f2f")
	var has_model := false
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if not has_model:
			return
		var c := size * 0.5
		var r := Vector2(size.x * 0.5 - 4, size.y * 0.5 - 4)
		draw_colored_polygon(UIDraw.ellipse(c + Vector2(6, 10), r, 48), Color(0.1, 0.05, 0.02, 0.4))
		draw_colored_polygon(UIDraw.ellipse(c, r, 48), UIStyle.INK)
		draw_colored_polygon(UIDraw.ellipse(c, r - Vector2(6, 6), 48), UIStyle.BRASS)
		draw_colored_polygon(UIDraw.ellipse(c, r - Vector2(14, 14), 48), tint.darkened(0.35))
		# soft vignette backdrop inside the oval
		for i in 6:
			draw_colored_polygon(UIDraw.ellipse(c + Vector2(0, -10), (r - Vector2(18, 18)) * (1.0 - i * 0.12), 48), Color(tint.lightened(0.25), 0.12))
		for i in 28:
			var a := TAU * i / 28.0
			draw_circle(c + Vector2(cos(a) * (r.x - 4), sin(a) * (r.y - 4)), 2.4, UIStyle.BRASS_LIGHT, true, -1.0, true)
		UIDraw.sparkle(self, c + Vector2(r.x * 0.62, -r.y * 0.78), 12.0 + 4.0 * sin(_t * 3.0), Color(1, 1, 0.85, 0.9))


class _PlateRibbon:
	extends Control
	var tint := UIStyle.RIBBON

	func _draw() -> void:
		var r := Rect2(Vector2(16, 4), size - Vector2(32, 8))
		UIDraw.ribbon(self, r, tint, UIStyle.BRASS)


class _NarratorIcon:
	extends Control
	# not a Container child: PanelContainer would stretch it, so it is positioned in _process
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		var p := get_parent() as Control
		if p:
			position = Vector2(p.size.x * 0.5 - size.x * 0.5, -size.y * 0.55)
			size = Vector2(64, 48)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c + Vector2(0, 3), 30.0, Color(0.1, 0.05, 0.02, 0.3), true, -1.0, true)
		draw_circle(c, 30.0, UIStyle.INK, true, -1.0, true)
		draw_circle(c, 26.0, UIStyle.BRASS, true, -1.0, true)
		draw_circle(c, 21.0, UIStyle.CREAM, true, -1.0, true)
		# an open book: two pages meeting at the spine
		var l := PackedVector2Array([c + Vector2(-1, -5), c + Vector2(-14, -9), c + Vector2(-14, 7), c + Vector2(-1, 11)])
		var r := PackedVector2Array([c + Vector2(1, -5), c + Vector2(14, -9), c + Vector2(14, 7), c + Vector2(1, 11)])
		draw_colored_polygon(l, UIStyle.PARCHMENT)
		draw_colored_polygon(r, UIStyle.PARCHMENT)
		draw_polyline(PackedVector2Array([c + Vector2(-1, -5), c + Vector2(-14, -9), c + Vector2(-14, 7), c + Vector2(-1, 11), c + Vector2(-1, -5)]), UIStyle.INK, 2.0, true)
		draw_polyline(PackedVector2Array([c + Vector2(1, -5), c + Vector2(14, -9), c + Vector2(14, 7), c + Vector2(1, 11), c + Vector2(1, -5)]), UIStyle.INK, 2.0, true)
		UIDraw.sparkle(self, c + Vector2(22, -20), 6.0 + 2.0 * sin(t * 4.0), Color(UIStyle.BRASS_LIGHT, 0.95))


class _Prompt:
	extends Control
	var t := 0.0
	var amount := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		if amount <= 0.01:
			return
		var y := sin(t * 6.0) * 5.0
		var c := size * 0.5 + Vector2(0, y)
		UIPrompts.draw_glyph(self, c, "interact" if UIPrompts.device() == "gamepad" else "ui_accept", 50.0 * UIFx.back_out(amount), amount)


func is_open() -> bool:
	return _open


func _speaker_info(speaker: String) -> Array:
	return UISpeakers.info(speaker)


func open(speaker: String, lines: Array) -> void:
	_lines = lines.duplicate()
	if _lines.is_empty():
		_lines = ["..."]
	_speaker = speaker
	_index = 0
	_open = true
	_closing = false
	visible = true
	_input_grace = 0.2
	_panel.pivot_offset = Vector2(_panel.size.x * 0.5, _panel.size.y)
	_panel.scale = Vector2(0.85, 0.2)
	_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.12)
	_portrait_frame.modulate.a = 0.0
	_portrait_frame.pivot_offset = _portrait_frame.size * 0.5
	_portrait_frame.scale = Vector2(0.5, 0.5)
	tw.tween_property(_portrait_frame, "modulate:a", 1.0, 0.18).set_delay(0.08)
	tw.tween_property(_portrait_frame, "scale", Vector2.ONE, 0.4).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	UIFx.event("ui_dialog_open", {"speaker": speaker})
	_show_line()


func _show_line() -> void:
	var line: Variant = _lines[_index]
	var speaker := _speaker
	var text := ""
	if line is Dictionary:
		speaker = String(line.get("speaker", _speaker))
		text = String(line.get("text", ""))
		if line.has("voice"):
			var a := get_node_or_null("/root/Audio")
			if a:
				a.play_voice(String(line["voice"]))
	else:
		text = String(line)
	var info := _speaker_info(speaker)
	var col: Color = info[1]
	var has_model := String(info[0]) != "" and _portrait.set_model(String(info[0]), "bust")
	if has_model and String(info[0]).contains("/mak/"):
		# the portrait wears the hat Mak wears in game (critique UI r1: top hat in game, beanie in the portrait)
		var g := get_node_or_null("/root/Game")
		_portrait.apply_mak_hat(String(g.get_hat()) if g and g.has_method("get_hat") else "beanie")
	_portrait.yaw_offset = float(info[2])
	_portrait_frame.has_model = has_model
	_portrait_frame.tint = col
	_portrait.visible = has_model
	var left := -500 if has_model else -680
	_plate.offset_left = left
	_plate.offset_right = left + 300
	# critique UI r1: narrator and system lines (no speaker, no portrait) opened the full 1500 px
	# speaker panel as an empty parchment; they now get a compact centred card
	_narrator = speaker == "" and not has_model
	var mc := _text.get_parent() as MarginContainer
	if _narrator:
		_panel.offset_left = -470
		_panel.offset_right = 470
		_panel.offset_top = -250
		# critique UI r1 polish: the Enter keycap nearly touched the second line; 120 px stay clear on the right
		# (and on the left, so the centred text stays centred)
		mc.add_theme_constant_override("margin_left", 120)
		mc.add_theme_constant_override("margin_right", 120)
		mc.add_theme_constant_override("margin_top", 34)
		_text.add_theme_font_override("font", UIStyle.display_font_regular())
		_text.add_theme_font_size_override("font_size", 36)
		_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_text.custom_minimum_size = Vector2(700, 110)
		_prompt.offset_left = 380
		_prompt.offset_right = 460
	else:
		_panel.offset_left = -700
		_panel.offset_right = 800
		_panel.offset_top = -300
		mc.add_theme_constant_override("margin_left", 190 if has_model else 16)
		mc.add_theme_constant_override("margin_right", 70)
		mc.add_theme_constant_override("margin_top", 30)
		_text.add_theme_font_override("font", UIStyle.ui_font(600))
		_text.add_theme_font_size_override("font_size", 38)
		_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_text.custom_minimum_size = Vector2(1160, 170)
		_prompt.offset_left = 690
		_prompt.offset_right = 770
	_narrator_icon.visible = _narrator
	_plate_ribbon.tint = col
	_plate_ribbon.queue_redraw()
	var changed := speaker != _plate_label.text
	_plate.visible = speaker != ""
	_plate_label.text = speaker
	if changed:
		_plate_pop = 1.0
	_text.text = text
	_text.visible_characters = 0
	_visible_chars = 0.0
	_prompt.amount = 0.0
	line_shown.emit(_index)


func _process(delta: float) -> void:
	if not _open:
		return
	_t += delta
	_input_grace = maxf(0.0, _input_grace - delta)
	_plate_pop = move_toward(_plate_pop, 0.0, delta * 2.5)
	var pp := UIFx.pop(_plate_pop)
	_plate.pivot_offset = _plate.size * 0.5
	_plate.scale = Vector2.ONE * (1.0 + pp * 0.25)
	_plate.rotation = pp * 0.06
	var total := _text.get_total_character_count()
	var typing := _visible_chars < total
	if typing:
		_visible_chars += delta * CHARS_PER_SEC
		_text.visible_characters = int(_visible_chars)
		_blip_acc += delta
		if _blip_acc > 0.075:
			_blip_acc = 0.0
			UIFx.sound("ui_text_blip", randf_range(0.95, 1.12))
	_talk = move_toward(_talk, 1.0 if typing else 0.0, delta * 6.0)
	# the portrait bobs while the speaker "talks"
	if _portrait.pivot:
		_portrait.pivot.position.y = absf(sin(_t * 11.0)) * 0.02 * _talk
		_portrait.pivot.rotation.x = sin(_t * 9.0) * 0.03 * _talk
	_prompt.amount = move_toward(_prompt.amount, 0.0 if typing else 1.0, delta * 5.0)


func advance() -> void:
	var total := _text.get_total_character_count()
	if _visible_chars < total:
		_visible_chars = total
		_text.visible_characters = -1
		return
	_index += 1
	if _index >= _lines.size():
		close()
	else:
		UIFx.event("ui_dialog_advance", {"index": _index})
		_show_line()


func close() -> void:
	if _closing:
		return
	_closing = true
	UIFx.event("ui_dialog_close")
	_open = false
	finished.emit()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2(0.9, 0.0), 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.16)
	tw.tween_property(_portrait_frame, "scale", Vector2(0.4, 0.4), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_portrait_frame, "modulate:a", 0.0, 0.14)
	tw.tween_property(_plate, "modulate:a", 0.0, 0.12)
	tw.tween_property(_prompt, "modulate:a", 0.0, 0.1)
	await tw.finished
	if not _open:
		visible = false
	_plate.modulate.a = 1.0
	_prompt.modulate.a = 1.0
	_closing = false


func _input(event: InputEvent) -> void:
	if not _open or _input_grace > 0.0:
		return
	if event.is_echo():
		return
	var pressed := event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if pressed:
		advance()
		get_viewport().set_input_as_handled()

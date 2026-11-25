extends Control
## Settings: volumes, mouse sensitivity, invert X/Y, fullscreen, vsync and keyboard rebinding.
## Every change applies immediately and is persisted by the Game autoload.

signal closed

const ACTION_NAMES := {
	"move_forward": "Move forward", "move_back": "Move back", "move_left": "Move left", "move_right": "Move right",
	"jump": "Jump", "crouch": "Crouch / Ham Slam", "attack": "Attack", "interact": "Interact / Talk",
	"sniff": "Snout Sniff", "cam_center": "Centre camera", "pause": "Pause",
}

var _first_focus: Control
var _waiting_action := ""
var _waiting_button: Button
var _bind_buttons: Dictionary = {}
var _value_labels: Dictionary = {}
var _shadow_toggle: CheckButton
var _graphics_button: CheckButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIStyle.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("ui_modal")  # the UI autoload hides the HUD while any ui_modal is visible
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.02, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := UIStyle.panel("parchment", 44)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1180, 900)
	panel.offset_left = -590
	panel.offset_right = 590
	panel.offset_top = -450
	panel.offset_bottom = 450
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	panel.add_child(outer)
	var title := UIStyle.title_label("Settings", 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.shadowed(title, Vector2(0, 3), Color(0.4, 0.2, 0.1, 0.25))
	outer.add_child(title)
	# critique UI r1 (art director): rows were sliced mid-glyph at the viewport edge. The list now sits in an
	# alpha mask that fades the top and bottom 40 px, and focus scrolling keeps the focused row clear of the fades.
	_mask = TextureRect.new()
	_mask.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mask.stretch_mode = TextureRect.STRETCH_SCALE
	_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_mask.texture = _fade_texture(600.0)
	_mask.resized.connect(func() -> void: _mask.texture = _fade_texture(_mask.size.y))
	outer.add_child(_mask)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.follow_focus = false
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_mask.add_child(scroll)
	_scroll = scroll
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	_section(list, "Sound")
	_slider(list, "Master volume", "master_volume", 0.0, 1.0, 0.05, true)
	_slider(list, "Music", "music_volume", 0.0, 1.0, 0.05, true)
	_slider(list, "Sound effects", "sfx_volume", 0.0, 1.0, 0.05, true)
	_slider(list, "Voices", "voice_volume", 0.0, 1.0, 0.05, true)
	_section(list, "Camera")
	_slider(list, "Mouse sensitivity", "mouse_sensitivity", 0.2, 3.0, 0.1, false)
	# critique UI r1: pad players had no camera speed; the camera already reads gamepad_sensitivity
	_slider(list, "Stick camera speed", "gamepad_sensitivity", 0.5, 2.0, 0.1, false)
	_toggle(list, "Invert camera X", "invert_x")
	_toggle(list, "Invert camera Y", "invert_y")
	_section(list, "Display")
	_toggle(list, "Fullscreen", "fullscreen")
	_toggle(list, "Vertical sync", "vsync")
	if OS.has_feature("web"):
		_graphics_toggle(list)
	_toggle(list, "Classic textures", "classic_textures")
	# Soft sun shadows (default Soft); Off is the classic blob-only look for slower PCs.
	_shadow_toggle = _toggle(list, "Shadows", "soft_shadows", "Soft", "Off")
	_refresh_shadow_toggle()
	_section(list, "Keyboard")
	var g := _game()
	var actions: Array = g.REBINDABLE_ACTIONS if g else []
	for action in actions:
		_binding(list, action)
	_section(list, "Controller")
	var pad_actions: Array = g.PAD_REBINDABLE_ACTIONS if g and "PAD_REBINDABLE_ACTIONS" in g else []
	for action in pad_actions:
		_pad_binding(list, action)
	var reset := StoryButton.new("Reset controls to defaults", 30)
	reset.pressed.connect(_on_reset)
	list.add_child(reset)
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, FADE_PX)
	list.add_child(tail)
	# one Back affordance (critique UI r1: an in-panel Back repeated the footer's Back): the footer
	# names the button, and a mouse click on the footer closes too
	var hint := UIPrompts.new()
	hint.items = [["ui_accept", "Choose"], ["ui_cancel", "Back"]]
	hint.mouse_filter = Control.MOUSE_FILTER_STOP
	hint.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hint.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close())
	hint.text_color = UIStyle.INK
	hint.outline_color = Color(UIStyle.PARCHMENT, 0.9)
	hint.font_size = 24
	hint.glyph_size = 40.0
	outer.add_child(hint)
	_panel = panel
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_chain_focus(list)


## Finish pass (UI usability blocker: pad and keyboard focus stopped at "Invert camera Y", 7 of 28 stops, because
## geometric focus search skips rows clipped by the scroll mask). Explicit up/down chain through every row in order.
func _chain_focus(list: Control) -> void:
	var stops: Array[Control] = []
	for n in list.find_children("*", "Control", true, false):
		var c := n as Control
		if c.focus_mode == Control.FOCUS_ALL and c.visible:
			stops.append(c)
	for i in stops.size():
		var c := stops[i]
		var up := stops[i - 1] if i > 0 else stops[stops.size() - 1]
		var down := stops[i + 1] if i < stops.size() - 1 else stops[0]
		c.focus_neighbor_top = c.get_path_to(up)
		c.focus_neighbor_bottom = c.get_path_to(down)
		c.focus_previous = c.get_path_to(up)
		c.focus_next = c.get_path_to(down)


func _game() -> Node:
	return get_node_or_null("/root/Game")


var _panel: Control
var _mask: TextureRect
var _scroll: ScrollContainer
var _scroll_tw: Tween
const FADE_PX := 40.0


## A vertical alpha ramp: transparent at both ends, opaque between FADE_PX bands.
func _fade_texture(h: float) -> GradientTexture2D:
	var g := Gradient.new()
	var f := clampf(FADE_PX / maxf(h, 1.0), 0.0, 0.45)
	g.offsets = PackedFloat32Array([0.0, f, 1.0 - f, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 256
	return t


## Scroll so the focused row sits fully inside the opaque band (whole rows, never under a fade).
func _on_focus_changed(c: Control) -> void:
	if not visible or _scroll == null or c == null or not _scroll.is_ancestor_of(c):
		return
	var row: Control = c
	while row.get_parent() != null and row.get_parent().get_parent() != _scroll:
		row = row.get_parent() as Control
	var list := _scroll.get_child(0) as Control
	var top := row.get_global_rect().position.y - list.get_global_rect().position.y
	var bottom := top + row.size.y
	var view_h := _scroll.size.y
	var cur := float(_scroll.scroll_vertical)
	var target := cur
	var pad := FADE_PX + 8.0
	# a section heading just above the row comes along when moving up
	var idx := row.get_index()
	if idx >= 2 and list.get_child(idx - 2) is Label:
		top = (list.get_child(idx - 2) as Control).position.y
	if top < cur + pad:
		target = top - pad
	elif bottom > cur + view_h - pad:
		target = bottom - view_h + pad
	target = clampf(target, 0.0, maxf(0.0, list.size.y - view_h))
	if absf(target - cur) < 1.0:
		return
	if _scroll_tw:
		_scroll_tw.kill()
	_scroll_tw = create_tween()
	_scroll_tw.tween_property(_scroll, "scroll_vertical", int(target), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func open() -> void:
	visible = true
	refresh()
	if _panel:
		_panel.pivot_offset = _panel.size * 0.5
		_panel.scale = Vector2(0.88, 0.88)
		_panel.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.15)
	if _first_focus:
		_first_focus.grab_focus()


func close() -> void:
	if _waiting_action != "":
		return
	visible = false
	UIFx.event("ui_close", {"context": "settings"})
	closed.emit()


func refresh() -> void:
	var g := _game()
	if g == null:
		return
	for action in _bind_buttons.keys():
		(_bind_buttons[action] as Button).text = g.primary_key_name(action)
	# Round 4: the automatic level can change between areas while this menu stays built.
	if _graphics_button != null and g.has_method("low_graphics"):
		_graphics_button.set_pressed_no_signal(bool(g.low_graphics()))
		_graphics_button.text = "Light" if _graphics_button.button_pressed else "Full"
	_refresh_shadow_toggle()


func _section(list: VBoxContainer, text: String) -> void:
	var l := UIStyle.label(text, 40, UIStyle.RIBBON, true)
	l.custom_minimum_size = Vector2(0, 64)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	list.add_child(l)
	var sep := ColorRect.new()
	sep.color = Color(UIStyle.BRASS, 0.7)
	sep.custom_minimum_size = Vector2(0, 3)
	list.add_child(sep)


func _row(list: VBoxContainer, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	var l := UIStyle.label(text, 32, UIStyle.INK)
	l.custom_minimum_size = Vector2(440, 56)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	list.add_child(h)
	return h


func _slider(list: VBoxContainer, text: String, key: String, lo: float, hi: float, step: float, percent: bool) -> void:
	var h := _row(list, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(460, 48)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	var g := _game()
	s.value = float(g.get_setting(key, 1.0)) if g else 1.0
	var v := UIStyle.label("", 30, UIStyle.INK_SOFT)
	v.custom_minimum_size = Vector2(110, 0)
	var fmt := func(x: float) -> String: return ("%d%%" % roundi(x * 100.0)) if percent else ("%.1fx" % x)
	v.text = fmt.call(s.value)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt.call(x)
		var gg := _game()
		if gg:
			gg.set_setting(key, x)
		UIFx.event("ui_settings_change", {"key": key, "value": x}))
	h.add_child(s)
	h.add_child(v)
	_focus_label(h, s)
	if _first_focus == null:
		_first_focus = s


## The row's name turns ribbon-red while its control has focus (critique UI r1: weak slider focus on a TV).
func _focus_label(h: HBoxContainer, c: Control) -> void:
	var l := h.get_child(0) as Label
	c.focus_entered.connect(func() -> void: l.add_theme_color_override("font_color", UIStyle.RIBBON))
	c.focus_exited.connect(func() -> void: l.add_theme_color_override("font_color", UIStyle.INK))


func _toggle(list: VBoxContainer, text: String, key: String, on_text := "On", off_text := "Off") -> CheckButton:
	var h := _row(list, text)
	var c := CheckButton.new()
	c.focus_mode = Control.FOCUS_ALL
	var g := _game()
	c.button_pressed = bool(g.get_setting(key, false)) if g else false
	c.text = on_text if c.button_pressed else off_text
	c.add_theme_font_size_override("font_size", 30)
	c.toggled.connect(func(on: bool) -> void:
		c.text = on_text if on else off_text
		var gg := _game()
		if gg:
			gg.set_setting(key, on))
	h.add_child(c)
	_focus_label(h, c)
	return c


## Round 4 (web): Full / Light graphics. It starts on what the device check chose; touching it stores the player's choice.
func _graphics_toggle(list: VBoxContainer) -> void:
	var h := _row(list, "Graphics")
	var c := CheckButton.new()
	c.focus_mode = Control.FOCUS_ALL
	var g := _game()
	c.button_pressed = g != null and g.has_method("low_graphics") and bool(g.low_graphics())
	c.text = "Light" if c.button_pressed else "Full"
	c.add_theme_font_size_override("font_size", 30)
	c.toggled.connect(func(on: bool) -> void:
		c.text = "Light" if on else "Full"
		var gg := _game()
		if gg:
			gg.set_setting("graphics", "low" if on else "high")
		_refresh_shadow_toggle())
	h.add_child(c)
	_focus_label(h, c)
	_graphics_button = c


## Light draws without dynamic shadows: the Shadows row shows Off and waits until Graphics is Full again.
func _refresh_shadow_toggle() -> void:
	var g := _game()
	if _shadow_toggle == null or g == null:
		return
	var on := bool(g.get_setting("soft_shadows", true))
	_shadow_toggle.set_pressed_no_signal(on)
	_shadow_toggle.text = "Soft" if on else "Off"
	_shadow_toggle.disabled = g.has_method("low_graphics") and bool(g.low_graphics())


func _binding(list: VBoxContainer, action: String) -> void:
	var h := _row(list, ACTION_NAMES.get(action, action))
	var b := Button.new()
	b.custom_minimum_size = Vector2(460, 52)
	b.focus_mode = Control.FOCUS_ALL
	var g := _game()
	b.text = g.primary_key_name(action) if g else "-"
	b.pressed.connect(func() -> void:
		_waiting_action = action
		_waiting_button = b
		b.text = "Press a key (Backspace cancels)" if OS.has_feature("web") else "Press a key (Esc cancels)")
	h.add_child(b)
	_focus_label(h, b)
	_bind_buttons[action] = b


class _PadBind:
	extends Button
	var action := ""
	var waiting := false
	var locked := false
	var wait_left := 0.0
	var wait_len := 6.0
	var _t := 0.0

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		text = ""
		custom_minimum_size = Vector2(460, 56)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if waiting:
			# critique UI r1: red text on the red focus box made the capture invisible. Cream on the
			# ribbon while focused, with a 6 s countdown underline; ribbon text only when unfocused.
			var f := UIStyle.ui_font(700)
			var a := 0.75 + 0.25 * sin(_t * 6.0)
			var txt := "Press a button (B cancels)"
			var fs := 30
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var col := UIStyle.CREAM if has_focus() else UIStyle.RIBBON
			draw_string(f, Vector2((size.x - tw) * 0.5, size.y * 0.5 + 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))
			var k := clampf(wait_left / maxf(wait_len, 0.01), 0.0, 1.0)
			var bw := (size.x - 36.0) * k
			draw_line(Vector2(size.x * 0.5 - bw * 0.5, size.y - 9), Vector2(size.x * 0.5 + bw * 0.5, size.y - 9), UIStyle.GOLD if has_focus() else UIStyle.RIBBON, 4.0, true)
			return
		if locked:
			UIPrompts.draw_glyph(self, Vector2(size.x * 0.5 - 40, size.y * 0.5), action, 42.0, 1.0, "gamepad")
			var lf := UIStyle.ui_font(550)
			draw_string(lf, Vector2(size.x * 0.5 + 4, size.y * 0.5 + 8), "fixed", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIStyle.CREAM if has_focus() else UIStyle.INK_SOFT)
			return
		UIPrompts.draw_glyph(self, size * 0.5, action, 42.0, 1.0, "gamepad")


func _pad_binding(list: VBoxContainer, action: String) -> void:
	var h := _row(list, ACTION_NAMES.get(action, action))
	var b := _PadBind.new()
	b.action = action
	# critique UI r1: Pause could be rebound to a face button, pushing Interact onto Start. Pause stays
	# on Start (Back also pauses), so the row is shown but not capturable.
	b.locked = action == "pause"
	b.pressed.connect(func() -> void:
		if b.locked:
			UIFx.event("ui_back", {"context": "pad_fixed"})
			return
		_waiting_pad = b
		b.waiting = true
		_pad_wait_t = 6.0
		b.wait_left = 6.0)
	h.add_child(b)
	_focus_label(h, b)


var _waiting_pad: _PadBind
var _pad_wait_t := 0.0


func _process(delta: float) -> void:
	if _waiting_pad:
		_pad_wait_t -= delta
		_waiting_pad.wait_left = _pad_wait_t
		if _pad_wait_t <= 0.0:
			_waiting_pad.waiting = false
			_waiting_pad = null


func _redraw_pad_rows() -> void:
	for n in find_children("*", "Button", true, false):
		if n is _PadBind:
			(n as _PadBind).queue_redraw()


func _on_reset() -> void:
	var g := _game()
	if g:
		g.reset_bindings()
	refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _waiting_pad:
		get_viewport().set_input_as_handled()
		if event is InputEventJoypadButton and event.pressed:
			var btn: int = event.button_index
			# B and Start are reserved for back/pause (critique UI r1: B was bound instead of cancelling)
			if btn == JOY_BUTTON_B or btn == JOY_BUTTON_START or btn == JOY_BUTTON_BACK:
				UIFx.event("ui_back")
			else:
				var gp := _game()
				if gp and gp.has_method("rebind_pad"):
					# Game.rebind_pad swaps with the action that already owns the button (no duplicates)
					gp.rebind_pad(_waiting_pad.action, btn)
					UIFx.event("ui_settings_change", {"pad": _waiting_pad.action, "button": btn})
					_redraw_pad_rows()
			_waiting_pad.waiting = false
			var wb := _waiting_pad
			_waiting_pad = null
			wb.grab_focus.call_deferred()
		elif event is InputEventKey and event.pressed and (event.physical_keycode == KEY_ESCAPE or (OS.has_feature("web") and event.physical_keycode == KEY_BACKSPACE)):
			_waiting_pad.waiting = false
			_waiting_pad = null
		return
	if _waiting_action != "":
		if event is InputEventJoypadButton and event.pressed:
			# a pad can cancel a keyboard capture (critique UI r1)
			get_viewport().set_input_as_handled()
			if event.button_index == JOY_BUTTON_B or event.button_index == JOY_BUTTON_START:
				var gc := _game()
				_waiting_button.text = gc.primary_key_name(_waiting_action) if gc else "-"
				_waiting_action = ""
				UIFx.event("ui_back")
				_waiting_button.grab_focus()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			var g := _game()
			if event.physical_keycode == KEY_ESCAPE or (OS.has_feature("web") and event.physical_keycode == KEY_BACKSPACE):
				_waiting_button.text = g.primary_key_name(_waiting_action) if g else "-"
			elif g:
				g.rebind_key(_waiting_action, event.physical_keycode)
				_waiting_button.text = g.primary_key_name(_waiting_action)
			_waiting_action = ""
			_waiting_button.grab_focus()
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_back_game"):
		get_viewport().set_input_as_handled()
		close()

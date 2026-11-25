class_name UIPrompts
extends Control
## Keyboard and controller button prompts. The UI autoload tracks the last used device
## (UI.last_device: "keyboard" or "gamepad"); prompts redraw when it changes.
##
##   var bar := UIPrompts.new()
##   bar.items = [["ui_accept_game", "Jump in"], ["ui_back_game", "Close"]]
##   UIPrompts.draw_glyph(canvas, center, "jump", 40.0)   # one glyph anywhere
##
## Keyboard glyphs are keycaps with the bound key's name (rebinding aware). Gamepad glyphs use the
## generic face-button layout: bottom green A, right red B, left blue X, top yellow Y.

@export var items: Array = []:
	set(v):
		items = v
		_relayout()
@export var font_size: int = 26
@export var text_color: Color = UIStyle.CREAM
@export var outline_color: Color = Color(0.18, 0.08, 0.03, 0.9)
@export var align_center := true
@export var glyph_size := 44.0

var _device := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_relayout()


func _process(_delta: float) -> void:
	var d := device()
	if d != _device:
		_device = d
		_relayout()
		queue_redraw()


static func device() -> String:
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null:
		return "keyboard"
	var ui := ml.root.get_node_or_null("UI")
	if ui and "last_device" in ui:
		return String(ui.last_device)
	return "gamepad" if Input.get_connected_joypads().size() > 0 else "keyboard"


func _relayout() -> void:
	custom_minimum_size.y = maxf(glyph_size, font_size * 1.4)
	custom_minimum_size.x = total_width()
	queue_redraw()


func total_width() -> float:
	var f := UIStyle.ui_font(650)
	var w := 0.0
	for it in items:
		w += glyph_width(String(it[0]), glyph_size) + 10.0 + f.get_string_size(String(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 36.0
	return maxf(0.0, w - 36.0)


func _draw() -> void:
	var f := UIStyle.ui_font(650)
	var x := (size.x - total_width()) * 0.5 if align_center else 0.0
	var cy := size.y * 0.5
	for it in items:
		var gw := glyph_width(String(it[0]), glyph_size)
		draw_glyph(self, Vector2(x + gw * 0.5, cy), String(it[0]), glyph_size)
		x += gw + 10.0
		var txt := String(it[1])
		var base := Vector2(x, cy + (f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5)
		draw_string_outline(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, outline_color)
		draw_string(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		x += f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 36.0


# ---------------------------------------------------------------- glyphs

const PAD_FACE := {
	JOY_BUTTON_A: ["A", Color("4fae4a")],
	JOY_BUTTON_B: ["B", Color("d8452b")],
	JOY_BUTTON_X: ["X", Color("3d7fd6")],
	JOY_BUTTON_Y: ["Y", Color("e8b62c")],
}
const PAD_OTHER := {
	JOY_BUTTON_START: "Menu",
	JOY_BUTTON_BACK: "View",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_DPAD_UP: "Up",
	JOY_BUTTON_DPAD_DOWN: "Down",
	JOY_BUTTON_DPAD_LEFT: "Left",
	JOY_BUTTON_DPAD_RIGHT: "Right",
}


## Returns {"kind": "key"|"face"|"pill"|"stick", "label": String, "color": Color}
static func glyph_for(action: String, dev: String = "") -> Dictionary:
	if dev == "":
		dev = device()
	var synthetic := {"ui_accept": "ui_accept_game", "ui_cancel": "ui_back_game"}
	var act: String = synthetic.get(action, action)
	if action == "move":
		return {"kind": "stick", "label": "L"} if dev == "gamepad" else {"kind": "key", "label": "WASD"}
	if action == "camera":
		return {"kind": "stick", "label": "R"} if dev == "gamepad" else {"kind": "key", "label": "Mouse"}
	if not InputMap.has_action(act):
		return {"kind": "key", "label": action}
	if dev == "gamepad":
		for ev in InputMap.action_get_events(act):
			if ev is InputEventJoypadButton:
				var b: int = ev.button_index
				if PAD_FACE.has(b):
					return {"kind": "face", "label": PAD_FACE[b][0], "color": PAD_FACE[b][1]}
				return {"kind": "pill", "label": PAD_OTHER.get(b, "B%d" % b)}
			if ev is InputEventJoypadMotion:
				var ax: int = ev.axis
				if ax == JOY_AXIS_TRIGGER_LEFT:
					return {"kind": "pill", "label": "LT"}
				if ax == JOY_AXIS_TRIGGER_RIGHT:
					return {"kind": "pill", "label": "RT"}
				return {"kind": "stick", "label": "L" if ax <= JOY_AXIS_LEFT_Y else "R"}
	for ev in InputMap.action_get_events(act):
		if ev is InputEventKey:
			var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			var name := OS.get_keycode_string(code)
			if ev.physical_keycode != 0 and DisplayServer.get_name() != "headless":
				name = OS.get_keycode_string(code if OS.has_feature("web") else DisplayServer.keyboard_get_keycode_from_physical(code))
			return {"kind": "key", "label": _short_key(name)}
	for ev in InputMap.action_get_events(act):
		if ev is InputEventMouseButton:
			return {"kind": "key", "label": ["", "LMB", "RMB", "MMB"][clampi(ev.button_index, 0, 3)]}
	return {"kind": "key", "label": "?"}


static func _short_key(n: String) -> String:
	match n:
		"Escape":
			return "Esc"
		"Space":
			return "Space"
		"Enter":
			return "Enter"
		"Backspace":
			return "Bksp"
	return n


static func glyph_width(action: String, h: float) -> float:
	var g := glyph_for(action)
	match String(g["kind"]):
		"face", "stick":
			return h
		_:
			var f := UIStyle.ui_font(700)
			var fs := int(h * 0.48)
			return maxf(h, f.get_string_size(String(g["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + h * 0.55)


## Draws the glyph for `action` centred at `c`, `h` pixels tall.
static func draw_glyph(ci: CanvasItem, c: Vector2, action: String, h: float, alpha: float = 1.0, dev: String = "") -> void:
	var g := glyph_for(action, dev)
	var f := UIStyle.ui_font(700)
	var label := String(g["label"])
	match String(g["kind"]):
		"face":
			var col: Color = g["color"]
			ci.draw_circle(c + Vector2(0, h * 0.07), h * 0.5, Color(0.1, 0.05, 0.02, 0.45 * alpha), true, -1.0, true)
			ci.draw_circle(c, h * 0.5, Color(UIStyle.INK, alpha), true, -1.0, true)
			ci.draw_circle(c, h * 0.44, Color(col, alpha), true, -1.0, true)
			ci.draw_circle(c + Vector2(-h * 0.12, -h * 0.14), h * 0.16, Color(1, 1, 1, 0.25 * alpha), true, -1.0, true)
			var fs := int(h * 0.56)
			var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var base := c + Vector2(-tw * 0.5, (f.get_ascent(fs) - f.get_descent(fs)) * 0.5)
			ci.draw_string_outline(f, base, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(col.darkened(0.5), alpha))
			ci.draw_string(f, base, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))
		"stick":
			ci.draw_circle(c + Vector2(0, h * 0.07), h * 0.5, Color(0.1, 0.05, 0.02, 0.45 * alpha), true, -1.0, true)
			ci.draw_circle(c, h * 0.5, Color(UIStyle.INK, alpha), true, -1.0, true)
			ci.draw_circle(c, h * 0.44, Color("4b4f58", alpha), true, -1.0, true)
			ci.draw_circle(c, h * 0.3, Color("2c2f36", alpha), true, -1.0, true)
			ci.draw_arc(c, h * 0.3, 0, TAU, 24, Color(1, 1, 1, 0.2 * alpha), 2.0, true)
			var fs2 := int(h * 0.42)
			var tw2 := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			ci.draw_string(f, c + Vector2(-tw2 * 0.5, (f.get_ascent(fs2) - f.get_descent(fs2)) * 0.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 1, alpha))
		_:
			var pill := String(g["kind"]) == "pill"
			var fs3 := int(h * 0.48)
			var w := maxf(h, f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3).x + h * 0.55)
			var r := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
			var sb := StyleBoxFlat.new()
			sb.anti_aliasing = true
			sb.set_corner_radius_all(int(h * (0.5 if pill else 0.22)))
			sb.bg_color = Color(UIStyle.INK, alpha)
			ci.draw_style_box(sb, Rect2(r.position + Vector2(0, h * 0.09), r.size))
			sb.bg_color = Color("3b3f48" if pill else "fff7e6", alpha)
			sb.border_color = Color(UIStyle.INK, alpha)
			sb.set_border_width_all(maxi(2, int(h * 0.06)))
			ci.draw_style_box(sb, r)
			if not pill:
				var hi := StyleBoxFlat.new()
				hi.anti_aliasing = true
				hi.set_corner_radius_all(int(h * 0.16))
				hi.bg_color = Color(UIStyle.PARCHMENT_DARK, 0.55 * alpha)
				ci.draw_style_box(hi, Rect2(r.position + Vector2(h * 0.1, h * 0.62), Vector2(w - h * 0.2, h * 0.24)))
			var tw3 := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3).x
			ci.draw_string(f, c + Vector2(-tw3 * 0.5, (f.get_ascent(fs3) - f.get_descent(fs3)) * 0.5 - h * 0.03), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3, Color(Color.WHITE if pill else UIStyle.INK, alpha))

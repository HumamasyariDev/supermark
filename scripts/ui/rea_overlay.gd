extends CanvasLayer
## REA reference overlay (dev only, for the making-of video). Created by the Dev autoload when the game is
## started with `--rea-overlay`; F3 then hides or shows it. A normal run never creates it.
## It compares Mak's live jump with the arc predicted from the REA research (Docs/MOVEMENT_REFERENCE.md,
## "Predicted arcs": our 30 Hz simulation of the measured rules, converted to Mak's scale). Numbers only.

const PANEL_W := 420.0
const MARGIN := 22.0
const INK := Color("3b2416")
const BG := Color(0.11, 0.07, 0.05, 0.84)
const BRASS := Color("d9a93f")
const BRASS_LIGHT := Color("ffe08a")
const CREAM := Color("fff7e6")
const MUTED := Color(1.0, 0.97, 0.9, 0.62)
const GOOD := Color("7fd6a4")
const WARN := Color("ffb15c")
const FONT_PATH := "res://assets/fonts/fredoka/Fredoka-Variable.ttf"

## Reference apexes (m) from MOVEMENT_REFERENCE "Predicted arcs". Single and double scale with the takeoff
## speed (vertical launch = base + 0.25 x ground speed); the others have no speed term.
const SINGLE_STANDING := 1.89
const SINGLE_V0 := 10.31          # m/s standing launch (42 u/f converted, with the discrete-step correction)
const DOUBLE_RUN := 3.75
const DOUBLE_V0_RUN := 14.535     # m/s launch at full run (52 + 0.25 x 32 u/f, corrected)
const TRIPLE := 4.92
const FLIP := 4.0                 # backflip, side somersault, wall kick
const LONG_APEX := 1.88
const LONG_DIST := 12.2
const NAMES := {
	"jump": "Single jump", "double_jump": "Double jump", "triple_jump": "Triple jump", "backflip": "Backflip",
	"side_flip": "Side somersault", "wall_kick": "Wall kick", "long_jump": "Long jump", "rollout": "Roll-out",
	"bounce": "Bounce", "pole_jump": "Pole jump",
}

var _player: Node3D
var _root: PanelContainer
var _move: Label
var _sub: Label
var _rows := {}
var _bar: Control
var _kind := ""
var _takeoff := Vector3.ZERO
var _speed := 0.0
var _height := 0.0
var _apex := 0.0
var _pred := 0.0
var _airborne := false
var _dist := -1.0
var _font: Font
var _history: Array[String] = []
var _hist_label: Label
var _ground_speed := 0.0
var _past_apex := false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as Font
	_build()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_bind()
		return
	if bool(_player.get("grounded")):
		# Ground speed before takeoff: the reference launch uses it (the jump itself then scales it by 0.8).
		_ground_speed = absf(float(_player.get("forward_speed")))
	if _airborne:
		_height = _player.global_position.y - _takeoff.y
		_apex = maxf(_apex, _height)
		_past_apex = _past_apex or _height < _apex - 0.02
		_refresh()


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	if _player.has_signal("jumped") and not _player.is_connected("jumped", _on_jumped):
		_player.connect("jumped", _on_jumped)
	if _player.has_signal("landed") and not _player.is_connected("landed", _on_landed):
		_player.connect("landed", _on_landed)


func _on_jumped(kind: String) -> void:
	_kind = kind
	_takeoff = _player.global_position
	_speed = _ground_speed
	_past_apex = false
	_height = 0.0
	_apex = 0.0
	_dist = -1.0
	_airborne = true
	_pred = _predict(kind, _speed)
	_refresh()


func _on_landed(_impact: float) -> void:
	if not _airborne:
		return
	_airborne = false
	var d := _player.global_position - _takeoff
	_dist = Vector2(d.x, d.z).length()
	if _pred > 0.0:
		var line := "%s  %.2f m  vs  %.2f m  (%+.1f %%)" % [NAMES.get(_kind, _kind), _apex, _pred, (_apex - _pred) / _pred * 100.0]
		if _kind == "long_jump":
			line += "  dist %.1f m" % _dist
		_history.push_front(line)
		if _history.size() > 4:
			_history.resize(4)
	_refresh()


func _predict(kind: String, speed: float) -> float:
	var s := clampf(speed, 0.0, 7.5)
	match kind:
		"jump":
			return SINGLE_STANDING * pow((SINGLE_V0 + 0.25 * s) / SINGLE_V0, 2.0)
		"double_jump":
			return DOUBLE_RUN * pow((DOUBLE_V0_RUN - 0.25 * (7.5 - s)) / DOUBLE_V0_RUN, 2.0)
		"triple_jump":
			return TRIPLE
		"backflip", "side_flip", "wall_kick":
			return FLIP
		"long_jump":
			return LONG_APEX
	return 0.0


# ------------------------------------------------------------------ view

func _label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 1)
	if _font != null:
		l.add_theme_font_override("font", _font)
	return l


func _build() -> void:
	_root = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = BRASS
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	_root.add_theme_stylebox_override("panel", sb)
	_root.custom_minimum_size = Vector2(PANEL_W, 0)
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.offset_left = -PANEL_W - MARGIN
	_root.offset_right = -MARGIN
	_root.offset_top = MARGIN
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_root.add_child(box)
	box.add_child(_label("REA REFERENCE CHECK", 16, BRASS_LIGHT))
	_move = _label("Jump to compare", 30, CREAM)
	box.add_child(_move)
	_sub = _label("predicted from the reference rules, Mak scale", 15, MUTED)
	box.add_child(_sub)
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", BRASS)
	box.add_child(sep)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	for key in ["Height now", "Apex reached", "REA predicted apex", "Difference"]:
		grid.add_child(_label(key, 19, MUTED))
		var v := _label("-", 23, CREAM, HORIZONTAL_ALIGNMENT_RIGHT)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(v)
		_rows[key] = v
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, 26)
	_bar.draw.connect(_draw_bar)
	box.add_child(_bar)
	var foot := _label("", 14, MUTED)
	box.add_child(foot)
	_rows["foot"] = foot
	_hist_label = _label("", 16, CREAM)
	box.add_child(_hist_label)


func _refresh() -> void:
	if _move == null:
		return
	if _kind == "":
		_move.text = "Jump to compare"
		_sub.text = "predicted from the reference rules, Mak scale"
		return
	_move.text = NAMES.get(_kind, _kind.capitalize())
	var speed_note := ""
	if _kind == "jump" or _kind == "double_jump":
		speed_note = "takeoff speed %.1f m/s, " % _speed
	_sub.text = speed_note + ("in the air" if _airborne else "landed")
	(_rows["Height now"] as Label).text = "%.2f m" % _height if _airborne else "-"
	(_rows["Apex reached"] as Label).text = "%.2f m" % _apex
	var diff := _rows["Difference"] as Label
	if _pred > 0.0:
		(_rows["REA predicted apex"] as Label).text = "%.2f m" % _pred
		var pct := (_apex - _pred) / _pred * 100.0
		var done := not _airborne or _past_apex
		diff.text = "%+.1f %%" % pct if done else "rising..."
		diff.add_theme_color_override("font_color", (GOOD if absf(pct) <= 6.0 else WARN) if done else MUTED)
	else:
		(_rows["REA predicted apex"] as Label).text = "not analysed"
		diff.text = "-"
		diff.add_theme_color_override("font_color", CREAM)
	var foot := _rows["foot"] as Label
	if _kind == "long_jump":
		foot.text = "Distance %s   REA (full run) %.1f m" % [("%.1f m" % _dist) if _dist >= 0.0 else "...", LONG_DIST]
	else:
		foot.text = "REA 6.5.0 analysis  |  1 u = 7.8 mm  |  30 Hz reference"
	_hist_label.text = "
".join(_history)
	_hist_label.visible = not _history.is_empty()
	_bar.queue_redraw()


func _draw_bar() -> void:
	var w := _bar.size.x
	var h := 12.0
	var y := 8.0
	_bar.draw_rect(Rect2(0, y, w, h), Color(1, 1, 1, 0.12), true)
	if _pred <= 0.0:
		return
	var top := _pred * 1.25
	var cur := clampf((_height if _airborne else _apex) / top, 0.0, 1.0)
	var ap := clampf(_apex / top, 0.0, 1.0)
	_bar.draw_rect(Rect2(0, y, w * cur, h), BRASS, true)
	_bar.draw_rect(Rect2(w * ap - 1.5, y - 3, 3, h + 6), CREAM, true)
	var px := w * (_pred / top)
	_bar.draw_rect(Rect2(px - 2, y - 6, 4, h + 12), GOOD, true)

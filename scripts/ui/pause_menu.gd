extends Control
const GoldenHatLib := preload("res://scripts/objects/golden_hat.gd")
## Pause menu (storybook v2): a parchment card with the chapter, truffle medals and the menu
## (Resume, Restart at bookmark, Return to library, Settings, Quit to title) plus the Wardrobe:
## real 3D hats (the generated beanie and top hat GLBs) on velvet cushions. The top hat stays a
## silhouette until the Wolf is beaten. Freezes gameplay (tree pause) and releases the mouse.

signal resumed

const SETTINGS_SCENE := "res://scenes/ui/SettingsMenu.tscn"
const FOOTER_ITEMS := [["ui_accept", "Select"], ["ui_cancel", "Resume"]]
## Every hat the story can award. A card appears only when its GLB exists (no stand-in hats): the hub
## rewards (bowler, tea cosy, deerstalker) join the Wardrobe as soon as their models land.
const HATS := [
	{"id": "beanie", "name": "Knitted Beanie", "model": "res://assets/characters/mak/mak_beanie_v2.glb", "fallback": "res://assets/characters/mak/mak_beanie.glb", "how": ""},
	{"id": "top_hat", "name": "Top Hat", "model": "res://assets/characters/mak/mak_tophat.glb", "fallback": "", "how": ""},
	# Completion pass: the top hat is Mak's default now, so the Wolf awards its gold variant.
	{"id": "golden_top_hat", "name": "Golden Top Hat", "model": "res://assets/characters/mak/mak_tophat.glb", "fallback": "", "how": "Defeat the Wolf to win it", "gold": true},
	{"id": "bowler", "name": "Sensible Bowler", "model": "res://assets/characters/mak/mak_bowler.glb", "fallback": "", "how": "Catch the sheep in the library"},
	{"id": "teacosy", "name": "Tea Cosy", "model": "res://assets/characters/mak/mak_teacosy.glb", "fallback": "", "how": "Win Bramwell's Tea Run"},
	{"id": "deerstalker", "name": "Deerstalker", "model": "res://assets/characters/mak/mak_deerstalker.glb", "fallback": "", "how": "Solve the reading nook"},
]

var _buttons: VBoxContainer
var _library_button: StoryButton
var _settings_button: StoryButton
var _world_label: Label
var _mission_label: Label
var _goal_label: Label
var _restart_button: StoryButton
var _confirm: PanelContainer
var _confirm_title: Label
var _confirm_sub: Label
var _confirm_yes: StoryButton
var _confirm_no: StoryButton
var _confirm_action: Callable
var _confirm_return_focus: Control
var _medals: Control
var _settings: Control
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _open := false
var _closing := false
## Opened by a world exit gate: only the confirm card shows, and No closes the whole overlay.
var _exit_only := false
var _card: Control
var _wardrobe: Control
var _hat_cards: Array = []
var _dim: ColorRect
var _footer: UIPrompts
var _last_menu_focus: Control:
	set(v):
		_last_menu_focus = v
		if v:
			_point_hats_back(v)
var _spread: _Spread


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIStyle.theme()
	_dim = ColorRect.new()
	_dim.color = Color(0.1, 0.05, 0.02, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_spread = _Spread.new()
	_spread.set_anchors_preset(Control.PRESET_FULL_RECT)
	_spread.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_spread)
	# --- menu card
	var card := UIStyle.panel("parchment", 46)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -760
	card.offset_right = -40
	card.offset_top = -430
	card.offset_bottom = 380
	add_child(card)
	_card = card
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var title := UIStyle.title_label("Paused", 88)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_world_label = UIStyle.label("", 34, UIStyle.INK)
	_world_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_world_label)
	_mission_label = UIStyle.label("", 30, UIStyle.RIBBON)
	_mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_mission_label)
	# critique UI r1: the mission goal could only be read on the 3 s entry banner
	_goal_label = UIStyle.label("", 27, UIStyle.INK_SOFT)
	_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_label.custom_minimum_size = Vector2(600, 0)
	v.add_child(_goal_label)
	_medals = _Medals.new()
	_medals.custom_minimum_size = Vector2(600, 96)
	v.add_child(_medals)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 0)
	v.add_child(_buttons)
	_add("Resume", resume)
	_restart_button = _add("Restart at bookmark", func() -> void:
		_close_silently()
		var r := get_node_or_null("/root/Router")
		if r:
			r.reload_at_checkpoint())
	# critique UI r1: leaving a chapter asked nothing; both exits now confirm (default: Keep reading)
	_library_button = _add("Return to library", func() -> void:
		_ask("Close this book?", "Your truffles and pages stay found.", "Return to library", _to_library))
	_settings_button = _add("Settings", _on_settings)
	var to_title := func() -> void:
		_close_silently()
		var r := get_node_or_null("/root/Router")
		if r:
			r.go_to_title()
	_add("Quit to title", func() -> void:
		_ask("Back to the title?", "Your bookmark is saved.", "Quit to title", to_title))
	# --- wardrobe: the facing page of the same open book (critique UI r1: leather vs parchment, edges unaligned)
	var wr := UIStyle.panel("parchment", 34)
	wr.set_anchors_preset(Control.PRESET_CENTER)
	wr.offset_left = 40
	wr.offset_right = 760
	wr.offset_top = -330
	wr.offset_bottom = 250
	add_child(wr)
	_wardrobe = wr
	var wv := VBoxContainer.new()
	wv.alignment = BoxContainer.ALIGNMENT_CENTER
	wv.add_theme_constant_override("separation", 8)
	wr.add_child(wv)
	var wt := UIStyle.title_label("Wardrobe", 64)
	wt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wv.add_child(wt)
	var ws := UIStyle.label("Choose Mr. Mak's hat", 26, UIStyle.INK_SOFT)
	ws.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wv.add_child(ws)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 26)
	wv.add_child(hb)
	for h in HATS:
		if not (ResourceLoader.exists(String(h["model"])) or ResourceLoader.exists(String(h["fallback"]))):
			continue
		var c := _HatCard.new()
		c.hat = h
		c.custom_minimum_size = Vector2(300, 420)
		c.pressed.connect(func() -> void: _choose_hat(c))
		hb.add_child(c)
		_hat_cards.append(c)
	_footer = UIPrompts.new()
	_footer.items = FOOTER_ITEMS
	_footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_footer.offset_left = -400
	_footer.offset_right = 400
	_footer.offset_top = -80
	_footer.offset_bottom = -24
	add_child(_footer)
	# focus: menu <-> wardrobe
	var first_hat: Control = _hat_cards[0]
	for b in _buttons.get_children():
		var bc := b as Control
		bc.focus_neighbor_right = bc.get_path_to(first_hat)
		bc.focus_entered.connect(func() -> void: _last_menu_focus = bc)
	for i in _hat_cards.size():
		var hc := _hat_cards[i] as Control
		# critique UI r1 re-run: Down from "Quit to title" fell into the hat row and Up did nothing there.
		# Cards keep vertical focus to themselves; Left from the first card returns to the last menu button.
		hc.focus_neighbor_top = hc.get_path_to(hc)
		hc.focus_neighbor_bottom = hc.get_path_to(hc)
		if i + 1 < _hat_cards.size():
			hc.focus_neighbor_right = hc.get_path_to(_hat_cards[i + 1])
		else:
			hc.focus_neighbor_right = hc.get_path_to(hc)
		if i > 0:
			hc.focus_neighbor_left = hc.get_path_to(_hat_cards[i - 1])
	if _hat_cards.size() > 2:
		# three or more cards: narrower cards so the row still fits the leather panel
		for c in _hat_cards:
			(c as Control).custom_minimum_size = Vector2(maxf(190.0, 640.0 / _hat_cards.size() - 20.0), 420)
	_build_confirm()
	visible = false


## The menu list wraps (Up from the first visible button goes to the last). Rebuilt on open, because
## the library hides Restart and Return. The first hat card's Left returns to the last focused button.
func _wire_menu_focus() -> void:
	var vis: Array = []
	for b in _buttons.get_children():
		if (b as Control).visible:
			vis.append(b)
	for i in vis.size():
		var b := vis[i] as Control
		b.focus_neighbor_top = b.get_path_to(vis[(i - 1 + vis.size()) % vis.size()])
		b.focus_neighbor_bottom = b.get_path_to(vis[(i + 1) % vis.size()])
	_point_hats_back(vis[0] as Control)


func _point_hats_back(target: Control) -> void:
	if _hat_cards.is_empty() or target == null:
		return
	var first := _hat_cards[0] as Control
	first.focus_neighbor_left = first.get_path_to(target)


## Pause card and Wardrobe are two facing pages: same top and bottom, the card sized to its content.
func _align_pages() -> void:
	var h := maxf(_card.get_combined_minimum_size().y, _wardrobe.get_combined_minimum_size().y) + 24.0
	for p in [_card, _wardrobe]:
		(p as Control).offset_top = -h * 0.5 - 20.0
		(p as Control).offset_bottom = h * 0.5 - 20.0
	if _spread:
		_spread.page_rect = Rect2(Vector2(size.x * 0.5 - 760.0, size.y * 0.5 - h * 0.5 - 20.0), Vector2(1520.0, h))
		_spread.queue_redraw()


func _add(caption: String, cb: Callable) -> StoryButton:
	var b := StoryButton.new(caption, 38)
	b.custom_minimum_size = Vector2(600, 74)
	if cb.is_valid():
		b.pressed.connect(cb)
	_buttons.add_child(b)
	return b


func _to_library() -> void:
	_close_silently()
	var r := get_node_or_null("/root/Router")
	var g := get_node_or_null("/root/Game")
	if r:
		r.go_to_hub("Book_" + (g.current_world if g else ""))


func _build_confirm() -> void:
	_confirm = UIStyle.panel("parchment", 40)
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.offset_left = -470
	_confirm.offset_right = 470
	_confirm.offset_top = -165
	_confirm.offset_bottom = 165
	add_child(_confirm)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm.add_child(cv)
	_confirm_title = UIStyle.label("", 56, UIStyle.RIBBON, true)
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_confirm_title)
	_confirm_sub = UIStyle.label("", 30, UIStyle.INK)
	_confirm_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_confirm_sub)
	var ch := HBoxContainer.new()
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(ch)
	_confirm_yes = StoryButton.new("", 34)
	_confirm_yes.custom_minimum_size = Vector2(410, 70)
	_confirm_yes.chip = true
	_confirm_yes.pressed.connect(func() -> void:
		_confirm.visible = false
		if _confirm_action.is_valid():
			_confirm_action.call())
	_confirm_no = StoryButton.new("Keep reading", 34)
	_confirm_no.custom_minimum_size = Vector2(410, 70)
	_confirm_no.chip = true
	_confirm_no.pressed.connect(_close_confirm)
	ch.add_child(_confirm_yes)
	ch.add_child(_confirm_no)
	_confirm_yes.focus_neighbor_left = _confirm_yes.get_path_to(_confirm_no)
	_confirm_yes.focus_neighbor_right = _confirm_yes.get_path_to(_confirm_no)
	_confirm_no.focus_neighbor_left = _confirm_no.get_path_to(_confirm_yes)
	_confirm_no.focus_neighbor_right = _confirm_no.get_path_to(_confirm_yes)
	for b in [_confirm_yes, _confirm_no]:
		(b as Control).focus_neighbor_top = (b as Control).get_path_to(b)
		(b as Control).focus_neighbor_bottom = (b as Control).get_path_to(b)
	_confirm.visible = false


func _ask(title: String, sub: String, yes: String, action: Callable, from: Control = null) -> void:
	_confirm_title.text = title
	_confirm_sub.text = sub
	_confirm_yes.caption = yes
	_confirm_action = action
	_confirm_return_focus = from if from else get_viewport().gui_get_focus_owner()
	_card.visible = false
	_wardrobe.visible = false
	_confirm.visible = true
	_confirm.pivot_offset = _confirm.size * 0.5
	_confirm.scale = Vector2(0.82, 0.82)
	_confirm.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_confirm, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_confirm, "modulate:a", 1.0, 0.15)
	UIFx.event("ui_open", {"context": "pause_confirm"})
	# critique UI r1 re-run: the footer still said "B Resume" under the confirm
	_footer.items = [["ui_accept", "Choose"], ["ui_cancel", "Keep reading"]]
	_footer.queue_redraw()
	_spread.visible = false
	_confirm_no.grab_focus()


## World exit gates (owner fix 2026-10-19): the same confirm card on its own over the paused, dimmed world.
## Yes runs _to_library (exactly the menu's "Return to library"); No, Cancel or Pause resumes where Mak stands.
func open_exit_confirm() -> void:
	if _open:
		return
	_open = true
	_closing = false
	_exit_only = true
	visible = true
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_dim.modulate.a = 0.0
	create_tween().tween_property(_dim, "modulate:a", 1.0, 0.2)
	_footer.modulate.a = 1.0
	_footer.visible = true
	_confirm_no.caption = "No"
	_ask("Return to the Grand Library?", "Your truffles and pages stay found.", "Yes", _to_library, _confirm_no)
	_footer.items = [["ui_accept", "Choose"], ["ui_cancel", "Stay"]]
	_footer.queue_redraw()


func _close_exit_confirm() -> void:
	UIFx.event("ui_back")
	_close_silently()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.has_feature("web") else _prev_mouse
	resumed.emit()


func _close_confirm() -> void:
	if _exit_only:
		_close_exit_confirm()
		return
	_confirm.visible = false
	_card.visible = true
	_wardrobe.visible = true
	_spread.visible = true
	_footer.items = FOOTER_ITEMS
	_footer.queue_redraw()
	UIFx.event("ui_back")
	if _confirm_return_focus and is_instance_valid(_confirm_return_focus) and _confirm_return_focus.is_visible_in_tree():
		_confirm_return_focus.grab_focus()
	else:
		(_buttons.get_child(0) as Control).grab_focus()


# ---------------------------------------------------------------- truffle medals of this chapter

class _Medals:
	extends Control
	var states: Array = []
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var n := states.size()
		if n == 0:
			return
		var step := 62.0
		var x0 := size.x * 0.5 - step * (n - 1) * 0.5
		for i in n:
			var p := Vector2(x0 + i * step, size.y * 0.45)
			if states[i]:
				UIFx.draw_icon(self, UIFx.tex("truffle"), p, 54.0, sin(_t * 2.0 + i) * 0.07)
			else:
				UIFx.draw_icon(self, UIFx.tex("truffle"), p, 48.0, 0.0, Color(0.42, 0.28, 0.16, 0.25))


# ---------------------------------------------------------------- hat cards

class _HatCard:
	extends Button
	var hat: Dictionary = {}
	var view: UIModelView
	var lock_mark: Control
	var unlocked := true
	var worn := false
	var bump := 0.0
	var _hl := 0.0
	var _t := 0.0

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_ALL
		process_mode = Node.PROCESS_MODE_ALWAYS
		for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())
		mouse_entered.connect(func() -> void:
			var ui := get_node_or_null("/root/UI")
			if ui == null or not ui.has_method("mouse_active") or bool(ui.call("mouse_active")):
				grab_focus())
		focus_entered.connect(func() -> void:
			if is_visible_in_tree():
				UIFx.event("ui_move", {"context": "wardrobe"}))

	func _ready() -> void:
		view = UIModelView.new()
		view.position = Vector2(30, 56)
		view.size = Vector2(240, 210)
		view.sway = 0.0
		view.seat_bottom = true
		view.spin_speed = 0.6
		add_child(view)
		var path: String = hat.get("model", "")
		if not ResourceLoader.exists(path):
			path = hat.get("fallback", "")
		view.set_model(path, "full")
		if bool(hat.get("gold", false)) and view.model:
			# Per-surface gold, so the locked silhouette (material_override) still covers it.
			GoldenHatLib.gild(view.model, true, false)
		if String(hat.get("id", "")) == "beanie":
			view.set_exposure(0.62)
			# critique UI r1: the separate beanie GLB renders near-white; in the world Mak's beanie is
			# blue-grey (ART_V2 #8E949B), so the card tints the model view to match
			view.modulate = Color(0.68, 0.72, 0.78)
		# OPUSLOOK: the padlock is a child drawn after the model view; drawn by the card itself it sat behind the locked
		# hat's dark silhouette and could not be seen.
		lock_mark = Control.new()
		lock_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_mark.size = Vector2(60, 64)
		lock_mark.draw.connect(_draw_lock)
		add_child(lock_mark)

	func _draw_lock() -> void:
		var lc := Vector2(30, 36)
		lock_mark.draw_arc(lc + Vector2(0, -16), 18, PI, TAU, 16, UIStyle.BRASS_DARK, 6.0, true)
		lock_mark.draw_rect(Rect2(lc + Vector2(-26, -14), Vector2(52, 40)), UIStyle.BRASS)
		lock_mark.draw_rect(Rect2(lc + Vector2(-26, -14), Vector2(52, 40)), UIStyle.INK, false, 3.0)
		lock_mark.draw_circle(lc + Vector2(0, 2), 6, UIStyle.INK, true, -1.0, true)

	func refresh(p_unlocked: bool, p_worn: bool) -> void:
		unlocked = p_unlocked
		worn = p_worn
		if view:
			view.silhouette = not unlocked
			view.spin_speed = 0.6 if unlocked else 0.0

	func _process(delta: float) -> void:
		_t += delta
		_hl = move_toward(_hl, 1.0 if has_focus() else 0.0, delta * 7.0)
		bump = move_toward(bump, 0.0, delta * 2.0)
		if view:
			# OPUSLOOK: with three hats each card is about 193 px wide; the fixed 240 px model view spilled the hats past
			# the card edge. The view now fits the card (UIModelView re-frames the hat for the narrower aspect).
			var vw := minf(240.0, size.x - 28.0)
			if not is_equal_approx(view.size.x, vw):
				view.size = Vector2(vw, 210)
			var s := 1.0 + 0.06 * ease(_hl, -2.0) + UIFx.pop(bump) * 0.25
			view.scale = Vector2(s, s)
			view.pivot_offset = view.size * 0.5
			view.position = Vector2((size.x - vw) * 0.5, 56 - 10.0 * ease(_hl, -2.0) + sin(_t * 2.0) * 3.0)
		if lock_mark:
			lock_mark.visible = not unlocked
			lock_mark.position = Vector2(size.x * 0.5 - 30.0, 134.0)
		queue_redraw()

	func _draw() -> void:
		var e := ease(_hl, -2.0)
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = UIStyle.PARCHMENT_DARK.lerp(Color("f3d9a6"), e)
		sb.border_color = UIStyle.INK_SOFT.lerp(UIStyle.RIBBON, e)
		sb.set_border_width_all(4 if e < 0.5 else 6)
		sb.set_corner_radius_all(22)
		sb.anti_aliasing = true
		sb.shadow_color = Color(0.2, 0.08, 0.02, 0.3)
		sb.shadow_size = int(6 + 10 * e)
		draw_style_box(sb, r)
		# velvet cushion with depth (a side band under the top), brass tassels, and a soft contact shadow
		# where the hat sits (critique UI r1: hats floated above flat ellipses)
		var cw := minf(110.0, size.x * 0.4)
		var cc := Vector2(size.x * 0.5, 262)
		draw_colored_polygon(UIDraw.ellipse(cc + Vector2(0, 22), Vector2(cw * 1.04, 22), 32), Color(0.2, 0.08, 0.02, 0.3))
		draw_colored_polygon(UIDraw.ellipse(cc + Vector2(0, 12), Vector2(cw, 26), 32), UIStyle.RIBBON_DARK)
		draw_rect(Rect2(cc + Vector2(-cw, 0), Vector2(cw * 2.0, 12)), UIStyle.RIBBON_DARK)
		draw_colored_polygon(UIDraw.ellipse(cc, Vector2(cw, 26), 32), UIStyle.RIBBON)
		draw_colored_polygon(UIDraw.ellipse(cc + Vector2(-cw * 0.15, -7), Vector2(cw * 0.7, 12), 32), UIStyle.RIBBON.lightened(0.18))
		draw_colored_polygon(UIDraw.ellipse(cc + Vector2(0, -2), Vector2(cw * 0.55, 10), 32), Color(0.15, 0.03, 0.05, 0.45))
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			var tp := cc + Vector2(cos(a) * cw, sin(a) * 26 + 6)
			draw_line(tp, tp + Vector2(0, 12), UIStyle.BRASS_DARK, 3.0, true)
			draw_circle(tp + Vector2(0, 14), 5, UIStyle.BRASS, true, -1.0, true)
		# caption
		var f := UIStyle.ui_font(650)
		var hat_name: String = hat.get("name", "")
		var cap := hat_name if unlocked else "???"
		var fs := 28
		var tw := f.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# OPUSLOOK: names shrink to fit narrow cards ("Knitted Beanie" touched both edges).
		while tw > size.x - 24.0 and fs > 20:
			fs -= 1
			tw = f.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var sub := ""
		var sub_col := UIStyle.RIBBON
		if not unlocked:
			sub = String(hat.get("how", "")) if String(hat.get("how", "")) != "" else "Not yet found"
			sub_col = Color(UIStyle.INK_SOFT, 0.8)
		elif worn:
			sub = "Wearing"
		else:
			sub = "Wear it"
			sub_col = Color(UIStyle.INK_SOFT, 0.7 + 0.3 * e)
		var sf := UIStyle.ui_font(550)
		var lines: Array[String] = [sub]
		if sf.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x > size.x - 24.0 and sub.contains(" "):
			# OPUSLOOK: long hints ("Defeat the Wolf to win it") ran past both card edges; they wrap to two centred lines.
			var mid := int(sub.length() * 0.5)
			var cut := sub.rfind(" ", mid)
			var after := sub.find(" ", mid)
			if cut < 0 or (after >= 0 and after - mid < mid - cut):
				cut = after
			lines = [sub.substr(0, cut), sub.substr(cut + 1)]
		var cap_y := 360.0 if lines.size() == 1 else 350.0
		draw_string(f, Vector2((size.x - tw) * 0.5, cap_y), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIStyle.INK if unlocked else Color(UIStyle.INK, 0.55))
		var line_y := 396.0 if lines.size() == 1 else 380.0
		for line in lines:
			var sw := sf.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			draw_string(sf, Vector2((size.x - sw) * 0.5, line_y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, sub_col)
			line_y += 24.0
		if worn:
			# brass tick medallion in the corner
			var mc := Vector2(size.x - 34, 34)
			draw_circle(mc, 22, UIStyle.INK, true, -1.0, true)
			draw_circle(mc, 18, UIStyle.BRASS, true, -1.0, true)
			draw_polyline(PackedVector2Array([mc + Vector2(-9, 0), mc + Vector2(-2, 7), mc + Vector2(10, -7)]), UIStyle.INK, 4.0, true)


# ---------------------------------------------------------------- open / close

func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_closing = false
	visible = true
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_refresh()
	_wire_menu_focus()
	_align_pages()
	UIFx.event("ui_pause")
	(_buttons.get_child(0) as Control).grab_focus()
	_card.pivot_offset = _card.size * 0.5
	_wardrobe.pivot_offset = _wardrobe.size * 0.5
	_card.position.x = -_card.size.x
	_wardrobe.position.x = size.x
	_dim.modulate.a = 0.0
	_footer.modulate.a = 0.0
	_card.rotation = -0.05
	_wardrobe.rotation = 0.05
	var cx := size.x * 0.5 - 760.0
	var wx := size.x * 0.5 + 40.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.2)
	_spread.modulate.a = 0.0
	tw.tween_property(_spread, "modulate:a", 1.0, 0.3).set_delay(0.12)
	tw.tween_property(_card, "position:x", cx, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "rotation", 0.0, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_wardrobe, "position:x", wx, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.06)
	tw.tween_property(_wardrobe, "rotation", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.06)
	tw.tween_property(_footer, "modulate:a", 1.0, 0.3).set_delay(0.2)


func _refresh() -> void:
	var g := get_node_or_null("/root/Game")
	if g == null:
		return
	var wid: String = g.current_world
	_world_label.text = WorldRegistry.display_name(wid) if wid != "" else ""
	_mission_label.text = WorldRegistry.truffle_name(g.current_mission) if g.current_mission != "" else WorldRegistry.book_title(wid)
	if wid == "HUB" and g.current_mission == "":
		# one name for the hub everywhere (critique UI r1): the page turn and banner say The Grand Library
		_world_label.text = "The Grand Library"
		_mission_label.text = "Mak Manor"
	var goal := WorldRegistry.truffle_goal(g.current_mission) if g.current_mission != "" else ""
	if wid == "HUB" and goal == "":
		goal = "Jump into a storybook to find its Golden Truffles"
	_goal_label.text = goal
	_goal_label.visible = goal != ""
	# critique UI r1: "Restart at bookmark" means nothing in the library
	_restart_button.visible = wid != "HUB" and wid != ""
	var states: Array = []
	for id in WorldRegistry.truffle_ids(wid):
		states.append(g.has_truffle(id))
	(_medals as _Medals).states = states
	_library_button.visible = wid != "HUB"
	for c in _hat_cards:
		var id: String = c.hat["id"]
		c.refresh(_hat_unlocked(g, id), g.get_hat() == id)


func _choose_hat(card: Variant) -> void:
	var g := get_node_or_null("/root/Game")
	if g == null:
		return
	var id: String = card.hat["id"]
	if not _hat_unlocked(g, id):
		card.bump = 1.0
		UIFx.event("ui_back", {"context": "hat_locked"})
		return
	g.set_hat(id)
	card.bump = 1.0
	UIFx.event("ui_hat_change", {"hat": id})
	_refresh()


static func _hat_unlocked(g: Node, id: String) -> bool:
	return id == "beanie" or id == "top_hat" or g.is_unlocked(id) or g.is_unlocked("hat_" + id)


func _on_settings() -> void:
	if _settings == null:
		_settings = (load(SETTINGS_SCENE) as PackedScene).instantiate()
		add_child(_settings)
		_settings.closed.connect(func() -> void:
			_card.visible = true
			_wardrobe.visible = true
			_footer.visible = true
			_spread.visible = true
			_settings_button.grab_focus.call_deferred())
	_card.visible = false
	_wardrobe.visible = false
	_footer.visible = false
	_spread.visible = false
	UIFx.event("ui_open", {"context": "settings"})
	_settings.open()


func resume() -> void:
	if not _open or _closing:
		return
	_closing = true
	UIFx.event("ui_resume")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_card, "position:x", -_card.size.x, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_wardrobe, "position:x", size.x, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_dim, "modulate:a", 0.0, 0.16)
	tw.tween_property(_spread, "modulate:a", 0.0, 0.1)
	tw.tween_property(_footer, "modulate:a", 0.0, 0.1)
	await tw.finished
	_close_silently()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.has_feature("web") else _prev_mouse
	resumed.emit()


func _close_silently() -> void:
	_open = false
	_closing = false
	if _exit_only:
		_exit_only = false
		_confirm_no.caption = "Keep reading"
	visible = false
	if _settings:
		_settings.visible = false
	_card.visible = true
	_wardrobe.visible = true
	_footer.visible = true
	_spread.visible = true
	_footer.items = FOOTER_ITEMS
	if _confirm:
		_confirm.visible = false
	get_tree().paused = false


func _input(event: InputEvent) -> void:
	if not _open or _closing:
		return
	if _settings and _settings.visible:
		return
	if _confirm and _confirm.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_close_confirm()
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume()


# ---------------------------------------------------------------- open-book backing behind the two pages

class _Spread:
	extends Control
	var page_rect := Rect2()

	func _draw() -> void:
		if page_rect.size == Vector2.ZERO:
			return
		var cover := page_rect.grow(22.0)
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0.08, 0.03, 0.01, 0.45)
		sh.set_corner_radius_all(28)
		draw_style_box(sh, Rect2(cover.position + Vector2(0, 12), cover.size))
		var sb := StyleBoxFlat.new()
		sb.bg_color = UIStyle.LEATHER
		sb.border_color = Color("2e140c")
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(26)
		sb.anti_aliasing = true
		draw_style_box(sb, cover)
		var gilt := StyleBoxFlat.new()
		gilt.draw_center = false
		gilt.border_color = Color(UIStyle.BRASS, 0.7)
		gilt.set_border_width_all(2)
		gilt.set_corner_radius_all(20)
		gilt.anti_aliasing = true
		draw_style_box(gilt, cover.grow(-9.0))
		# the gutter between the pages: a soft shadow and a stitched spine
		var cx := page_rect.get_center().x
		for i in 6:
			var w := 40.0 - i * 6.0
			draw_rect(Rect2(cx - w * 0.5, page_rect.position.y + 6, w, page_rect.size.y - 12), Color(0.12, 0.05, 0.02, 0.07))
		var y := page_rect.position.y + 30.0
		while y < page_rect.end.y - 30.0:
			draw_line(Vector2(cx, y), Vector2(cx, y + 12), Color(UIStyle.BRASS, 0.55), 2.0, true)
			y += 24.0

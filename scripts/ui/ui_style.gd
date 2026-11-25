class_name UIStyle
extends RefCounted
## Shared storybook UI tokens: fonts, colours, the theme and small factories.
## Parchment, ribbon and brass. Chunky type that reads at 1280x720 and 1920x1080.

## INK and PARCHMENT follow Docs/ART_V2.md (critique UI r1 polish: the tokens had drifted).
const INK := Color("3b2416")
const INK_SOFT := Color("7a5a3e")
const PARCHMENT := Color("f3e6c4")
const PARCHMENT_DARK := Color("e2c99a")
const RIBBON := Color("8e1f2f")
const RIBBON_DARK := Color("5e1220")
const BRASS := Color("d9a93f")
const BRASS_LIGHT := Color("ffe08a")
const BRASS_DARK := Color("8a6420")
const CREAM := Color("fff7e6")
const GOLD := Color("ffc93c")
const LEATHER := Color("5b2a1c")
const DANGER := Color("d8452b")
const MINT := Color("5fb38a")

const FONT_UI := "res://assets/fonts/fredoka/Fredoka-Variable.ttf"
## Display face (screen titles, banners, the boss name, the title prompt): Lilita One, drawn with the logo
## treatment (cream fill, ribbon-dark rim, ink drop). critique UI r1 (art director): the swash serif did not
## match the puffy rounded logo, so the swash face is kept only for in-book voices (book_font*).
const FONT_DISPLAY := "res://assets/fonts/lilita/LilitaOne-Regular.ttf"
## In-book voices only: the cover-page book title, epigraphs and narrator lines.
const FONT_BOOK := "res://assets/fonts/cherryswash/CherrySwash-Bold.ttf"
const FONT_DISPLAY_REG := "res://assets/fonts/cherryswash/CherrySwash-Regular.ttf"
## Logo treatment for display words (px at 1080p).
const TITLE_FILL := CREAM
const TITLE_RIM := RIBBON_DARK
const TITLE_RIM_PX := 5
const TITLE_DROP_PX := 3
## Numerals and the big reward words: Lilita One echoes the logo's chunky rounded "64"
## (critique UI r1: the swash display face turned "0" into a ringed O and "III" into bars).
const FONT_NUMBER := "res://assets/fonts/lilita/LilitaOne-Regular.ttf"
const PARCHMENT_TEX := "res://assets/textures/parchment.webp"
const PANEL_SHADER := "res://scenes/ui/shaders/ui_panel.gdshader"

static var _cache: Dictionary = {}


static func _font_file(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f:
			return f
	return ThemeDB.fallback_font


static func ui_font(weight: int = 600) -> Font:
	var key := "ui_%d" % weight
	if not _cache.has(key):
		var base := _font_file(FONT_UI)
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_cache[key] = fv
	return _cache[key]


static func display_font() -> Font:
	if not _cache.has("display"):
		_cache["display"] = _font_file(FONT_DISPLAY)
	return _cache["display"]


## Cherry Swash Bold, for in-book voices only (cover-page book titles).
static func book_font() -> Font:
	if not _cache.has("book"):
		_cache["book"] = _font_file(FONT_BOOK)
	return _cache["book"]


## A Label in the display face with the logo treatment: cream fill, 5 px ribbon-dark rim, 3 px ink drop.
static func title_label(text: String, size: int = 64) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TITLE_FILL)
	l.add_theme_constant_override("outline_size", TITLE_RIM_PX * 2)
	l.add_theme_color_override("font_outline_color", TITLE_RIM)
	l.add_theme_color_override("font_shadow_color", Color(INK, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", TITLE_DROP_PX)
	l.add_theme_constant_override("shadow_outline_size", TITLE_RIM_PX * 2)
	return l


## Draws a display word with the logo treatment (see title_label) on any CanvasItem.
static func draw_title(ci: CanvasItem, pos: Vector2, text: String, fs: int, alpha: float = 1.0, f: Font = null) -> void:
	if f == null:
		f = display_font()
	var rim := TITLE_RIM_PX * 2
	ci.draw_string_outline(f, pos + Vector2(0, TITLE_DROP_PX), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, rim, Color(INK, 0.85 * alpha))
	ci.draw_string(f, pos + Vector2(0, TITLE_DROP_PX), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK, 0.85 * alpha))
	ci.draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, rim, Color(TITLE_RIM, alpha))
	ci.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(TITLE_FILL, alpha))


## The face for every numeral (HUD counters, timer, page counts, badges) and the TRUFFLE GET splash.
static func number_font() -> Font:
	if not _cache.has("number"):
		_cache["number"] = _font_file(FONT_NUMBER)
	return _cache["number"]


static func display_font_regular() -> Font:
	if not _cache.has("display_reg"):
		_cache["display_reg"] = _font_file(FONT_DISPLAY_REG)
	return _cache["display_reg"]


static func parchment_texture() -> Texture2D:
	if not _cache.has("parch"):
		_cache["parch"] = load(PARCHMENT_TEX) if ResourceLoader.exists(PARCHMENT_TEX) else null
	return _cache["parch"]


static func theme() -> Theme:
	if _cache.has("theme"):
		return _cache["theme"]
	var t := Theme.new()
	t.default_font = ui_font(600)
	t.default_font_size = 30
	# Labels
	t.set_color("font_color", "Label", INK)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0))
	# Buttons (StoryButton draws itself; these are fallbacks for plain Buttons)
	var bn := _flat(PARCHMENT, INK, 3, 14)
	var bf := _flat(RIBBON, BRASS, 4, 14)
	for s in ["normal", "disabled"]:
		t.set_stylebox(s, "Button", bn)
	for s in ["hover", "pressed", "focus", "hover_pressed"]:
		t.set_stylebox(s, "Button", bf)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", CREAM)
	t.set_color("font_focus_color", "Button", CREAM)
	t.set_color("font_pressed_color", "Button", BRASS_LIGHT)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.4))
	t.set_font_size("font_size", "Button", 30)
	# Sliders
	var track := _flat(PARCHMENT_DARK, INK_SOFT, 2, 8)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track)
	var fill := _flat(BRASS, BRASS_DARK, 2, 8)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(GOLD, RIBBON, 2, 8))
	t.set_icon("grabber", "HSlider", _circle_icon(26, RIBBON, BRASS_LIGHT))
	t.set_icon("grabber_highlight", "HSlider", _circle_icon(30, RIBBON, BRASS_LIGHT))
	# critique UI r1: the focused slider was a 2 px outline; give it the StoryButton highlight band
	var sf := _flat(Color(RIBBON, 0.12), RIBBON, 4, 12)
	sf.expand_margin_left = 14
	sf.expand_margin_right = 14
	sf.expand_margin_top = 8
	sf.expand_margin_bottom = 8
	t.set_stylebox("focus", "HSlider", sf)
	# CheckButton
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_focus_color", "CheckButton", RIBBON)
	t.set_color("font_hover_color", "CheckButton", RIBBON)
	# critique UI r1: a pressed toggle fell back to near-white text on parchment ("On" was invisible)
	t.set_color("font_pressed_color", "CheckButton", INK)
	t.set_color("font_hover_pressed_color", "CheckButton", RIBBON)
	t.set_color("font_focus_color", "CheckButton", RIBBON)
	t.set_color("font_disabled_color", "CheckButton", Color(INK, 0.4))
	var cf := _flat(Color(RIBBON, 0.12), RIBBON, 4, 12)
	cf.expand_margin_left = 10
	cf.expand_margin_right = 10
	cf.expand_margin_top = 4
	cf.expand_margin_bottom = 4
	t.set_stylebox("focus", "CheckButton", cf)
	for s in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(s, "CheckButton", StyleBoxEmpty.new())
	t.set_icon("checked", "CheckButton", _toggle_icon(true))
	t.set_icon("unchecked", "CheckButton", _toggle_icon(false))
	t.set_icon("checked_disabled", "CheckButton", _toggle_icon(true))
	t.set_icon("unchecked_disabled", "CheckButton", _toggle_icon(false))
	t.set_constant("h_separation", "CheckButton", 18)
	# ScrollContainer / panels
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	# storybook scrollbar: parchment-dark track, brass grabber (critique UI r1: default grey line)
	var sb_track := _flat(Color(PARCHMENT_DARK, 0.9), Color(INK_SOFT, 0.5), 1, 6)
	sb_track.content_margin_left = 5
	sb_track.content_margin_right = 5
	sb_track.content_margin_top = 4
	sb_track.content_margin_bottom = 4
	var sb_grab := _flat(BRASS, BRASS_DARK, 2, 6)
	sb_grab.content_margin_left = 5
	sb_grab.content_margin_right = 5
	var sb_grab_hi := _flat(BRASS_LIGHT, BRASS_DARK, 2, 6)
	sb_grab_hi.content_margin_left = 5
	sb_grab_hi.content_margin_right = 5
	t.set_stylebox("scroll", "VScrollBar", sb_track)
	t.set_stylebox("scroll_focus", "VScrollBar", sb_track)
	t.set_stylebox("grabber", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb_grab_hi)
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	t.set_stylebox("panel", "Panel", StyleBoxEmpty.new())
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 12)
	_cache["theme"] = t
	return t


static func _flat(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.anti_aliasing = true
	return s


static func _focus_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = RIBBON
	s.set_border_width_all(3)
	s.set_corner_radius_all(10)
	s.expand_margin_left = 6
	s.expand_margin_right = 6
	s.expand_margin_top = 4
	s.expand_margin_bottom = 4
	return s


static func _toggle_icon(on: bool) -> ImageTexture:
	var w := 88
	var h := 46
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h * 0.5
	var track := RIBBON if on else PARCHMENT_DARK
	var knob_x := w - r if on else r
	for y in h:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(px.x, r, w - r)
			var d := px.distance_to(Vector2(cx, r))
			var a := clampf(r - d, 0.0, 1.0)
			var c := INK if d > r - 3.0 else track
			var kd := px.distance_to(Vector2(knob_x, r))
			if kd < r - 6.0:
				c = CREAM if kd < r - 9.0 else BRASS
				a = 1.0
			img.set_pixel(x, y, Color(c, a))
	return ImageTexture.create_from_image(img)


static func _circle_icon(d: int, fill: Color, rim: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - dist, 0.0, 1.0)
			var c := rim if dist > r - 4.0 else fill
			if dist < r * 0.45 and x < r and y < r:
				c = fill.lightened(0.25)
			img.set_pixel(x, y, Color(c, a))
	return ImageTexture.create_from_image(img)


## A parchment PanelContainer with the storybook panel shader (rounded, inked, gilt, shadowed).
static func panel(kind: String = "parchment", margin: int = 28) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.anti_aliasing = false
	var shadow := 16.0
	sb.expand_margin_left = shadow
	sb.expand_margin_right = shadow
	sb.expand_margin_top = shadow
	sb.expand_margin_bottom = shadow
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.8
	sb.content_margin_bottom = margin * 0.8
	p.add_theme_stylebox_override("panel", sb)
	var mat := ShaderMaterial.new()
	mat.shader = load(PANEL_SHADER)
	var tex := parchment_texture()
	mat.set_shader_parameter("fill_tex", tex)
	mat.set_shader_parameter("use_tex", tex != null)
	match kind:
		"leather":
			mat.set_shader_parameter("use_tex", false)
			mat.set_shader_parameter("fill_color", LEATHER)
			mat.set_shader_parameter("border_color", Color("2e140c"))
			mat.set_shader_parameter("gilt_color", BRASS)
			mat.set_shader_parameter("vignette_color", Color(0.4, 0.2, 0.1))
		"ribbon":
			mat.set_shader_parameter("use_tex", false)
			mat.set_shader_parameter("fill_color", RIBBON)
			mat.set_shader_parameter("border_color", RIBBON_DARK)
			mat.set_shader_parameter("gilt_color", BRASS_LIGHT)
			mat.set_shader_parameter("gilt_inset", 6.0)
			mat.set_shader_parameter("radius", 12.0)
		"brass":
			mat.set_shader_parameter("use_tex", false)
			mat.set_shader_parameter("fill_color", Color("3b2416"))
			mat.set_shader_parameter("border_color", BRASS)
			mat.set_shader_parameter("gilt_color", Color(BRASS_LIGHT, 0.6))
			mat.set_shader_parameter("gilt_inset", 6.0)
			mat.set_shader_parameter("radius", 14.0)
			mat.set_shader_parameter("vignette", 0.2)
		"pill":
			mat.set_shader_parameter("radius", 30.0)
			mat.set_shader_parameter("gilt_inset", 7.0)
			mat.set_shader_parameter("border", 3.5)
	mat.set_shader_parameter("shadow_px", shadow * 0.85)
	p.material = mat
	var upd := func() -> void:
		mat.set_shader_parameter("size", p.size)
		# expand margins shift VERTEX: compensate by drawing in control-local space
	p.resized.connect(upd)
	p.ready.connect(upd)
	return p


static func label(text: String, size: int = 30, color: Color = INK, display: bool = false, outline: int = 0, outline_color: Color = Color.BLACK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font() if display else ui_font(600))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	return l


static func shadowed(l: Label, offset: Vector2 = Vector2(0, 4), color: Color = Color(0, 0, 0, 0.35)) -> Label:
	l.add_theme_color_override("font_shadow_color", color)
	l.add_theme_constant_override("shadow_offset_x", int(offset.x))
	l.add_theme_constant_override("shadow_offset_y", int(offset.y))
	l.add_theme_constant_override("shadow_outline_size", 6)
	return l


## The longest word-boundary prefix of text that fits max_w at fs, with an ellipsis when trimmed.
static func fit_words(f: Font, text: String, fs: int, max_w: float) -> String:
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
		return text
	var words := text.split(" ")
	while words.size() > 1:
		words.remove_at(words.size() - 1)
		var t := " ".join(words).trim_suffix(",") + "…"
		if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
			return t
	return words[0] if not words.is_empty() else ""


static func format_time(seconds: float) -> String:
	if is_inf(seconds) or seconds < 0.0:
		return "--:--.--"
	var m := int(seconds / 60.0)
	var s := fmod(seconds, 60.0)
	return "%02d:%05.2f" % [m, s]

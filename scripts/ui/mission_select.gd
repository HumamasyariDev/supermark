extends Control
## Mission select (storybook v2). The book appears closed with its generated cover, swings open on
## a two-page spread: the left page shows the cover plate, the book title and the 8 truffle medals;
## the right page lists the 8 Golden Truffle missions. Choosing one zooms into the page and enters
## the world with that mission's spawn and banner.

signal chosen(world_id: String, mission_id: String)
signal cancelled

const BOOK_SIZE := Vector2(1640, 880)
## A line from each (public-domain) tale for the left page.
const QUOTES := {
	"W1": "\"Little pig, little pig, let me come in!\"",
	"W2": "\"Up and up the beanstalk grew, right into the sky.\"",
	"W3": "\"Nibble, nibble, like a mouse, who is nibbling at my house?\"",
	"BOSS": "\"Then I'll huff, and I'll puff...\"",
}
const LEATHER := {"W1": Color("7a1f2e"), "W2": Color("1f5a52"), "W3": Color("5a2e1b"), "BOSS": Color("3a2450"), "HUB": Color("5b2a1c")}

var world_id := "W1"
var _book: _Book
var _entries: Array = []
var _list: VBoxContainer
var _footer: UIPrompts
var _dim: ColorRect
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _paused_tree := false
var _state := "closed"  # opening, open, choosing, closing
var _k := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIStyle.theme()
	_dim = ColorRect.new()
	_dim.color = Color(0.08, 0.04, 0.02, 0.62)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_book = _Book.new()
	_book.set_anchors_preset(Control.PRESET_CENTER)
	_book.offset_left = -BOOK_SIZE.x * 0.5
	_book.offset_right = BOOK_SIZE.x * 0.5
	_book.offset_top = -BOOK_SIZE.y * 0.5 - 30
	_book.offset_bottom = BOOK_SIZE.y * 0.5 - 30
	_book.pivot_offset = BOOK_SIZE * 0.5
	add_child(_book)
	_list = VBoxContainer.new()
	_list.position = Vector2(BOOK_SIZE.x * 0.5 + 60, 190)
	_list.size = Vector2(BOOK_SIZE.x * 0.5 - 120, 640)
	_list.add_theme_constant_override("separation", 2)
	_book.add_child(_list)
	_footer = UIPrompts.new()
	_footer.items = [["ui_accept", "Jump into the page"], ["ui_cancel", "Close the book"]]
	_footer.font_size = 28
	_footer.glyph_size = 46.0
	_footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_footer.offset_left = -500
	_footer.offset_right = 500
	_footer.offset_top = -86
	_footer.offset_bottom = -26
	add_child(_footer)
	visible = false


# ---------------------------------------------------------------- entries

class _Entry:
	extends Button
	var number := 1
	var caption := ""
	var collected := false
	var tid := ""
	var goal := ""
	var best := INF
	var flash := 0.0
	var _hl := 0.0
	var _t := 0.0
	var appear := 0.0
	var delay := 0.0

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(700, 78)
		process_mode = Node.PROCESS_MODE_ALWAYS
		for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())
		mouse_entered.connect(func() -> void:
			var ui := get_node_or_null("/root/UI")
			if ui == null or not ui.has_method("mouse_active") or bool(ui.call("mouse_active")):
				grab_focus())
		focus_entered.connect(func() -> void:
			if is_visible_in_tree():
				UIFx.event("ui_move", {"context": "mission", "id": tid}))

	func _process(delta: float) -> void:
		_t += delta
		_hl = move_toward(_hl, 1.0 if has_focus() else 0.0, delta * 7.0)
		flash = move_toward(flash, 0.0, delta * 2.0)
		if delay > 0.0:
			delay -= delta
		else:
			appear = minf(1.0, appear + delta * 4.0)
		queue_redraw()

	func _draw() -> void:
		var a := UIFx.back_out(appear)
		draw_set_transform(Vector2((1.0 - a) * 60.0, 0), 0.0, Vector2.ONE)
		var e := ease(_hl, -2.0)
		var alpha := clampf(appear * 2.0, 0.0, 1.0)
		if e > 0.01:
			var inset := lerpf(size.x * 0.4, 0.0, e)
			var grow := 13.0 if goal != "" else 0.0  # room for the goal line (critique UI r1: cramped at 720p)
			# critique UI r1 (art director): the left tail ran into the gutter and the right one onto the cover.
			# The left end stays inside the page's inner frame; only the right end overhangs, like a bookmark.
			UIDraw.ribbon(self, Rect2(inset + 34, 8 - grow, size.x - inset * 2.0 - 10, size.y - 16 + grow * 2.0), Color(UIStyle.RIBBON, e * alpha), Color(UIStyle.BRASS, e * alpha))
		if flash > 0.0:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 0.95, 0.7, flash * 0.8)
			sb.set_corner_radius_all(12)
			draw_style_box(sb, Rect2(Vector2(0, 4), size - Vector2(0, 8)).grow(6.0 * flash))
		# number medallion
		var c := Vector2(46, size.y * 0.5)
		draw_circle(c + Vector2(0, 4), 28, Color(0.1, 0.05, 0.02, 0.3 * alpha), true, -1.0, true)
		draw_circle(c, 28, Color(UIStyle.INK, alpha), true, -1.0, true)
		draw_circle(c, 24, Color(UIStyle.BRASS, alpha), true, -1.0, true)
		draw_arc(c, 19, 0, TAU, 32, Color(UIStyle.BRASS_LIGHT, 0.8 * alpha), 2.0, true)
		var nf := UIStyle.number_font()
		var ns := str(number)
		var nw := nf.get_string_size(ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
		draw_string(nf, c + Vector2(-nw * 0.5, 11), ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(UIStyle.INK, alpha))
		# name
		var f := UIStyle.ui_font(650)
		var col := UIStyle.INK.lerp(UIStyle.CREAM, e)
		var goal_k := e if goal != "" else 0.0
		var name_pos := Vector2(92 + e * 10.0, size.y * 0.5 + 12 - 15.0 * goal_k)
		var name_fs := int(round(34.0 - 4.0 * goal_k))
		if goal_k > 0.01:
			# the mission objective under the focused name (critique UI r1: missions never stated a goal)
			# 27 px at 1080 (18 px at 720p), 6 px clear of the ribbon's lower gilt rule (critique UI r1)
			var gf := UIStyle.ui_font(600)
			var gfs := 27
			var gmax := size.x - 220.0
			# critique UI r1 re-run: "...off the straw hous" was clipped mid-word. Shrink to 19 px, then trim at
			# a word boundary with an ellipsis; never clip a glyph (registry goals are capped at 40 characters).
			while gfs > 19 and gf.get_string_size(goal, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs).x > gmax:
				gfs -= 1
			var gtxt := UIStyle.fit_words(gf, goal, gfs, gmax)
			draw_string(gf, Vector2(name_pos.x + 2, size.y * 0.5 + 28), gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs, Color(UIStyle.BRASS_LIGHT.lerp(UIStyle.CREAM, 0.6), goal_k * alpha))
		if e > 0.01:
			draw_string_outline(f, name_pos + Vector2(0, 3), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - 210, name_fs, 6, Color(UIStyle.RIBBON_DARK, e * 0.8 * alpha))
		draw_string(f, name_pos, caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - 210, name_fs, Color(col, alpha))
		if best < INF:
			var bf := UIStyle.ui_font(550)
			draw_string(bf, Vector2(size.x - 210, size.y * 0.5 + 9), UIStyle.format_time(best), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UIStyle.BRASS_DARK.lerp(UIStyle.BRASS_LIGHT, e), alpha))
		# truffle medal: the real icon when found, a pencil outline when not
		var tc := Vector2(size.x - 52, size.y * 0.5)
		if collected:
			UIFx.draw_icon(self, UIFx.tex("truffle"), tc + Vector2(0, sin(_t * 3.0) * 3.0 * e), 60.0 * (1.0 + 0.12 * e), sin(_t * 2.0) * 0.08, Color(1, 1, 1, alpha))
		else:
			if e > 0.01:
				# a parchment medal so the unfound truffle still reads on the red ribbon (critique UI r1)
				draw_circle(tc, 34.0 * e, Color(UIStyle.INK, 0.9 * e * alpha), true, -1.0, true)
				draw_circle(tc, 31.0 * e, Color(UIStyle.CREAM, e * alpha), true, -1.0, true)
				draw_arc(tc, 26.0 * e, 0, TAU, 32, Color(UIStyle.BRASS, 0.8 * e * alpha), 2.0, true)
			UIFx.draw_icon(self, UIFx.tex("truffle"), tc, 56.0 - 8.0 * e, 0.0, Color(0.42, 0.28, 0.16, 0.26 * alpha).lerp(Color(0.42, 0.28, 0.16, 0.5 * alpha), e))
			if e > 0.5:
				UIDraw.sparkle(self, tc + Vector2(18, -18), 8.0 + 4.0 * sin(_t * 6.0), Color(UIStyle.BRASS_LIGHT, e))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- the book

class _Book:
	extends Control
	var world_id := "W1"
	var cover: Texture2D
	var leather := Color("7a1f2e")
	var open_k := 0.0  # 0 closed cover .. 1 fully open
	var show_k := 0.0
	var title := ""
	var subtitle := ""
	var quote := ""
	var got := 0
	var total := 8
	var collected: Array = []
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _leather_box(r: Rect2, col: Color, ci: CanvasItem = null) -> void:
		if ci == null:
			ci = self
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.border_color = col.darkened(0.55)
		sb.set_border_width_all(6)
		sb.set_corner_radius_all(22)
		sb.anti_aliasing = true
		ci.draw_style_box(sb, r)
		var g := StyleBoxFlat.new()
		g.draw_center = false
		g.border_color = Color(UIStyle.BRASS, 0.85)
		g.set_border_width_all(3)
		g.set_corner_radius_all(16)
		g.anti_aliasing = true
		ci.draw_style_box(g, r.grow(-16))

	## Stacked page edges with rounded corners (critique UI r1: square rects stair-stepped under the cover).
	func _page_edge(r: Rect2, col: Color, a: float = 1.0) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col, col.a * a)
		sb.set_corner_radius_all(8)
		sb.anti_aliasing = true
		draw_style_box(sb, r)

	func _draw_cover_face(r: Rect2, ci: CanvasItem = null) -> void:
		if ci == null:
			ci = self
		if cover:
			# leather board with the generated cover art inset at its true aspect
			_leather_box(r, leather, ci)
			var inner := r.grow(-22)
			var ts := cover.get_size()
			var k := minf(inner.size.x / ts.x, inner.size.y / ts.y)
			var cs := ts * k
			var cr := Rect2(inner.get_center() - cs * 0.5, cs)
			ci.draw_rect(Rect2(cr.position + Vector2(6, 8), cr.size), Color(0, 0, 0, 0.35))
			ci.draw_texture_rect(cover, cr, false)
			ci.draw_rect(cr, Color(0.1, 0.04, 0.02, 0.9), false, 3.0)
		else:
			_leather_box(r, leather, ci)
			var f := UIStyle.book_font()
			var fs := 64
			var lines := title.split(" ")
			var y := r.position.y + r.size.y * 0.32
			for ln in lines:
				var w := f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				UIFx.draw_outlined(ci, f, Vector2(r.get_center().x - w * 0.5, y), ln, fs, UIStyle.BRASS_LIGHT, Color("2e140c"), 10)
				y += fs * 1.05
			UIDraw.sparkle(ci, r.get_center() + Vector2(0, r.size.y * 0.28), 40.0, UIStyle.BRASS)

	# ------------------------------------------------ the cover in perspective (critique UI r1 art director:
	# the opening was a flat 2D squash with a maroon slab over the left page). The front face is rendered once
	# into a SubViewport; the board then swings around the spine in true perspective, drawn as thin vertical
	# strips (no affine kink), with a marbled endpaper on its inside, a 6 px board edge and a sweeping shadow.
	var _face_vp: SubViewport
	var _face_ctl: Control
	static var _endpaper: Texture2D
	const STRIPS := 24

	func refresh_face() -> void:
		var cs := Vector2i(int(size.x * 0.5 + 30.0), int(size.y + 40.0))
		if cs.x < 8 or cs.y < 8:
			cs = Vector2i(850, 920)
		if _face_vp == null:
			_face_vp = SubViewport.new()
			_face_vp.transparent_bg = true
			_face_vp.disable_3d = true
			_face_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
			add_child(_face_vp)
			_face_ctl = Control.new()
			_face_vp.add_child(_face_ctl)
			_face_ctl.draw.connect(func() -> void: _draw_cover_face(Rect2(Vector2.ZERO, Vector2(_face_vp.size)), _face_ctl))
		_face_vp.size = cs
		_face_ctl.size = Vector2(cs)
		_face_ctl.queue_redraw()
		_face_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	static func endpaper() -> Texture2D:
		if _endpaper:
			return _endpaper
		# procedural marbling: domain-warped noise bands in ribbon reds with brass veins
		var n1 := FastNoiseLite.new()
		n1.seed = 64
		n1.frequency = 0.012
		n1.fractal_octaves = 3
		var n2 := FastNoiseLite.new()
		n2.seed = 7
		n2.frequency = 0.02
		var iw := 192
		var ih := 288
		var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
		var c0 := UIStyle.RIBBON_DARK
		var c1 := UIStyle.RIBBON
		var c2 := Color("b8433f")
		for y in ih:
			for x in iw:
				var wx := float(x) + n2.get_noise_2d(x, y) * 70.0
				var wy := float(y) + n2.get_noise_2d(x + 300, y) * 40.0
				var v := n1.get_noise_2d(wx, wy * 0.45)
				var band := 0.5 + 0.5 * sin(v * 18.0 + wy * 0.05)
				var col := c0.lerp(c1, band).lerp(c2, clampf(v * 2.0, 0.0, 1.0) * 0.5)
				var vein := absf(sin(v * 18.0 + wy * 0.05))
				if vein < 0.08:
					col = col.lerp(UIStyle.BRASS, 0.75 * (1.0 - vein / 0.08))
				img.set_pixel(x, y, col)
		_endpaper = ImageTexture.create_from_image(img)
		return _endpaper

	## The spine sits at x = spine; the board is cw wide and spans y top..top + ch. u 0..1 across the board from the
	## spine, v 0..1 down it; theta 0 closed (lying on the right), PI open (lying on the left).
	func _proj(u: float, v: float, theta: float, spine: float, top: float, cw: float, ch: float) -> Vector2:
		var d := cw * 4.2
		var z := u * cw * sin(theta)
		var k := d / (d - z)
		var cy := top + ch * 0.5
		return Vector2(spine + u * cw * cos(theta) * k, cy + (top + v * ch - cy) * k)

	func _quad_strips(theta: float, spine: float, top: float, cw: float, ch: float, u0: float, u1: float, v0: float, v1: float, tex: Texture2D, tint: Color, flip_u: bool = false) -> void:
		for i in STRIPS:
			var a := lerpf(u0, u1, float(i) / STRIPS)
			var b := lerpf(u0, u1, float(i + 1) / STRIPS)
			var pts := PackedVector2Array([_proj(a, v0, theta, spine, top, cw, ch), _proj(b, v0, theta, spine, top, cw, ch), _proj(b, v1, theta, spine, top, cw, ch), _proj(a, v1, theta, spine, top, cw, ch)])
			var ta := (a - u0) / maxf(u1 - u0, 0.0001)
			var tb := (b - u0) / maxf(u1 - u0, 0.0001)
			if flip_u:
				ta = 1.0 - ta
				tb = 1.0 - tb
			var uvs := PackedVector2Array([Vector2(ta, 0), Vector2(tb, 0), Vector2(tb, 1), Vector2(ta, 1)])
			draw_polygon(pts, PackedColorArray([tint, tint, tint, tint]), uvs, tex)

	func _draw_cover_3d(o: float, spine: float, top: float, cw: float, ch: float) -> void:
		var theta := clampf(o, 0.0, 1.0) * PI
		var st := sin(theta)
		var front := theta < PI * 0.5
		# board edge (6 px thick page-stack side of the board) when it is near edge-on
		var e0 := _proj(1.0, 0.0, theta, spine, top, cw, ch)
		var e1 := _proj(1.0, 1.0, theta, spine, top, cw, ch)
		if front:
			var tint := Color(1, 1, 1).darkened(0.32 * st)
			var tex: Texture2D = _face_vp.get_texture() if _face_vp else null
			if tex:
				_quad_strips(theta, spine, top, cw, ch, 0.0, 1.0, 0.0, 1.0, tex, tint)
			# light glancing off the board as it lifts
			var gl := Color(1, 0.95, 0.8, 0.18 * st * (1.0 - st))
			draw_colored_polygon(PackedVector2Array([_proj(0.0, 0.0, theta, spine, top, cw, ch), e0, e1, _proj(0.0, 1.0, theta, spine, top, cw, ch)]), gl)
		else:
			# inside of the board: leather turn-ins around a marbled endpaper
			var shade := 0.28 * st
			var lc := leather.darkened(0.12 + shade)
			draw_colored_polygon(PackedVector2Array([_proj(0.0, 0.0, theta, spine, top, cw, ch), e0, e1, _proj(0.0, 1.0, theta, spine, top, cw, ch)]), lc)
			_quad_strips(theta, spine, top, cw, ch, 0.04, 0.95, 0.035, 0.965, endpaper(), Color(1, 1, 1).darkened(shade), true)
			var g := Color(UIStyle.BRASS, 0.55)
			var pa := _proj(0.04, 0.035, theta, spine, top, cw, ch)
			var pb := _proj(0.95, 0.035, theta, spine, top, cw, ch)
			var pc := _proj(0.95, 0.965, theta, spine, top, cw, ch)
			var pd := _proj(0.04, 0.965, theta, spine, top, cw, ch)
			draw_polyline(PackedVector2Array([pa, pb, pc, pd, pa]), g, 2.0, true)
		var edge_w := 2.0 + 6.0 * absf(cos(theta * 0.5 + PI * 0.25)) * st + 4.0 * st
		draw_line(e0, e1, leather.darkened(0.5), edge_w, true)
		draw_line(e0 + Vector2(0, 3), e1 - Vector2(0, 3), Color("e8d6ae", 0.8 * st), maxf(1.0, edge_w - 4.0), true)

	## The board's shadow sweeping across the page it is leaving or approaching.
	func _draw_cover_shadow(o: float, spine: float, page_top: float, page_h: float, cw: float) -> void:
		var theta := clampf(o, 0.0, 1.0) * PI
		var st := sin(theta)
		if st < 0.01:
			return
		var reach := cw * absf(cos(theta)) + 70.0 * st
		var dir := 1.0 if theta < PI * 0.5 else -1.0
		var steps := 14
		for i in steps:
			var f0 := float(i) / steps
			var x0 := spine + dir * reach * f0
			var x1 := spine + dir * reach * (f0 + 1.0 / steps)
			var a := 0.34 * st * (1.0 - f0 * 0.75)
			draw_rect(Rect2(minf(x0, x1), page_top, absf(x1 - x0) + 1.0, page_h), Color(0.18, 0.08, 0.03, a))

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cx := w * 0.5
		var appear := UIFx.back_out(show_k)
		var o := clampf(open_k, 0.0, 1.0)
		# the right page reads once the board has lifted clear; the left page settles in as the board lands
		var spread_a := clampf((o - 0.45) / 0.4, 0.0, 1.0)
		var land := clampf((o - 0.9) / 0.1, 0.0, 1.0)
		# shadow
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0.45 * appear)
		sh.set_corner_radius_all(40)
		sh.shadow_color = Color(0, 0, 0, 0.35 * appear)
		sh.shadow_size = 40
		var back_left := lerpf(cx, -24.0, land)
		draw_style_box(sh, Rect2(back_left + 20, 10, w + 24 - back_left, h + 30))
		# back board (right half always; left half once open)
		_leather_box(Rect2(cx - 10, -20, w * 0.5 + 34, h + 40), leather)
		if land > 0.0:
			_leather_box(Rect2(-24.0, -20, w * 0.5 + 34, h + 40), leather)
		# page block (right page always under the cover; left page appears with the opening)
		var parch := UIStyle.parchment_texture()
		var rp := Rect2(cx, 6, w * 0.5 - 14, h - 22)
		for i in 4:
			var oo := float(4 - i) * 3.0
			_page_edge(Rect2(cx, 10 + oo, w * 0.5 - 10 + oo, h - 20), Color("d9c49a").darkened(0.05 * i))
		if parch:
			draw_texture_rect(parch, rp, true, Color(1, 0.98, 0.92))
		else:
			draw_rect(rp, UIStyle.PARCHMENT)
		# the right page's own header fades in under the lifting board
		if spread_a > 0.0 and land <= 0.0:
			draw_rect(rp.grow(-26), Color(UIStyle.INK_SOFT, 0.35 * spread_a), false, 2.0)
			_draw_right_header(rp, spread_a)
		# ribbon bookmark (between the pages, under the board)
		var rx := w - 92.0
		draw_colored_polygon(PackedVector2Array([Vector2(rx, -20), Vector2(rx + 40, -20), Vector2(rx + 40, 150), Vector2(rx + 20, 128), Vector2(rx, 150)]), UIStyle.RIBBON)
		draw_line(Vector2(rx + 5, -20), Vector2(rx + 5, 140), Color(UIStyle.BRASS, 0.8), 2.0)
		if o < 1.0 or land < 1.0:
			_draw_cover_shadow(o, cx - 4.0, 6.0, h - 22.0, w * 0.5 + 30.0)
			_draw_cover_3d(o, cx - 4.0, -20.0, w * 0.5 + 30.0, h + 40.0)
		if land > 0.0:
			var lw := w * 0.5 - 14
			var lp := Rect2(cx - lw, 6, lw, h - 22)
			for i in 4:
				var oo := float(4 - i) * 3.0
				_page_edge(Rect2(cx - lw - oo, 10 + oo, lw, h - 20), Color("d9c49a").darkened(0.05 * i), land)
			if parch:
				draw_texture_rect(parch, lp, true, Color(1, 0.98, 0.92, land))
			else:
				draw_rect(lp, Color(UIStyle.PARCHMENT, land))
			spread_a = land
			# gutter shading
			for i in 24:
				var a := 0.22 * pow(1.0 - i / 24.0, 2.0) * spread_a
				draw_rect(Rect2(cx - i * 3 - 3, 6, 3, h - 22), Color(0.3, 0.18, 0.06, a))
				draw_rect(Rect2(cx + i * 3, 6, 3, h - 22), Color(0.3, 0.18, 0.06, a))
			draw_line(Vector2(cx, 6), Vector2(cx, h - 16), Color(0.3, 0.18, 0.06, 0.6 * spread_a), 2.0)
			draw_rect(Rect2(cx - lw, 6, lw, h - 22).grow(-26), Color(UIStyle.INK_SOFT, 0.35 * spread_a), false, 2.0)
			draw_rect(rp.grow(-26), Color(UIStyle.INK_SOFT, 0.35 * spread_a), false, 2.0)
			_draw_left_page(Rect2(cx - lw, 6, lw, h - 22), spread_a)
			_draw_right_header(rp, spread_a)

	func _draw_left_page(r: Rect2, a: float) -> void:
		if a < 0.6:
			return
		var k := (a - 0.6) / 0.4
		var c := r.get_center()
		var f := UIStyle.book_font()  # the cover-page book title is an in-book voice
		var uf := UIStyle.ui_font(600)
		# subtitle
		var sub := subtitle
		var sw := uf.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(uf, Vector2(c.x - sw * 0.5, r.position.y + 78), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(UIStyle.INK_SOFT, k))
		# cover plate, slightly tilted, with photo corners
		if cover:
			var pw := 300.0
			var ph := pw * cover.get_size().y / cover.get_size().x
			var pc := Vector2(c.x, r.position.y + 110 + ph * 0.5)
			var rot := -0.035 + sin(_t * 0.8) * 0.006
			draw_set_transform(pc, rot, Vector2.ONE)
			draw_rect(Rect2(Vector2(-pw, -ph) * 0.5 + Vector2(8, 10), Vector2(pw, ph)), Color(0.2, 0.1, 0.04, 0.3 * k))
			draw_rect(Rect2(Vector2(-pw, -ph) * 0.5 - Vector2(10, 10), Vector2(pw + 20, ph + 20)), Color(1, 0.98, 0.93, k))
			draw_texture_rect(cover, Rect2(Vector2(-pw, -ph) * 0.5, Vector2(pw, ph)), false, Color(1, 1, 1, k))
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var cp: Vector2 = Vector2(pw * 0.5 + 6, ph * 0.5 + 6) * corner
				var tri := PackedVector2Array([cp, cp - Vector2(46 * corner.x, 0), cp - Vector2(0, 46 * corner.y)])
				draw_colored_polygon(tri, Color(UIStyle.LEATHER, 0.9 * k))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var ty := pc.y + ph * 0.5 + 64
			var fs := 50
			var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if tw > r.size.x - 80:
				fs = int(fs * (r.size.x - 80) / tw)
				tw = f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			UIFx.draw_outlined(self, f, Vector2(c.x - tw * 0.5, ty), title, fs, UIStyle.RIBBON, UIStyle.CREAM, 6, false)
			_draw_medals(Vector2(c.x, ty + 56), k)
		else:
			var fs2 := 64
			var tw2 := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			UIFx.draw_outlined(self, f, Vector2(c.x - tw2 * 0.5, c.y - 40), title, fs2, UIStyle.RIBBON, UIStyle.CREAM, 6, false)
			_draw_medals(Vector2(c.x, c.y + 40), k)

	func _draw_medals(c: Vector2, k: float) -> void:
		var n := collected.size()
		var step := 58.0
		var x0 := c.x - step * (n - 1) * 0.5
		for i in n:
			var got_it: bool = collected[i]
			var p := Vector2(x0 + i * step, c.y)
			if got_it:
				UIFx.draw_icon(self, UIFx.tex("truffle"), p, 48.0, sin(_t * 2.0 + i) * 0.06, Color(1, 1, 1, k))
			else:
				UIFx.draw_icon(self, UIFx.tex("truffle"), p, 44.0, 0.0, Color(0.42, 0.28, 0.16, 0.25 * k))
		var uf := UIStyle.ui_font(650)
		var txt := "Golden Truffles found: %d / %d" % [got, total]
		var tw := uf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(uf, Vector2(c.x - tw * 0.5, c.y + 58), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(UIStyle.BRASS_DARK, k))
		if quote != "":
			var qf := UIStyle.display_font_regular()
			var qw := qf.get_string_size(quote, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
			var qs := 28 if qw < 700 else int(28 * 700 / qw)
			qw = qf.get_string_size(quote, HORIZONTAL_ALIGNMENT_LEFT, -1, qs).x
			draw_string(qf, Vector2(c.x - qw * 0.5, c.y + 118), quote, HORIZONTAL_ALIGNMENT_LEFT, -1, qs, Color(UIStyle.INK_SOFT, 0.85 * k))

	func _draw_right_header(r: Rect2, a: float) -> void:
		if a < 0.6:
			return
		var k := (a - 0.6) / 0.4
		var f := UIStyle.display_font()
		var txt := "Choose a Golden Truffle"
		var fs := 44
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var c := r.get_center()
		UIFx.draw_outlined(self, f, Vector2(c.x - tw * 0.5, r.position.y + 108), txt, fs, UIStyle.INK, UIStyle.CREAM, 6, false)
		var y := r.position.y + 140
		draw_line(Vector2(r.position.x + 170, y), Vector2(c.x - 30, y), Color(UIStyle.BRASS_DARK, 0.7 * k), 2.0, true)
		draw_line(Vector2(c.x + 30, y), Vector2(r.end.x - 170, y), Color(UIStyle.BRASS_DARK, 0.7 * k), 2.0, true)
		UIDraw.sparkle(self, Vector2(c.x, y), 16.0, Color(UIStyle.BRASS, k))


# ---------------------------------------------------------------- open / choose / close

func open_book(p_world_id: String) -> void:
	world_id = p_world_id
	_book.world_id = world_id
	_book.cover = UIFx.tex("cover_" + world_id)
	_book.leather = LEATHER.get(world_id, Color("5b2a1c"))
	_book.title = WorldRegistry.book_title(world_id)
	_book.subtitle = "Book of " + WorldRegistry.display_name(world_id)
	_book.quote = QUOTES.get(world_id, "")
	_book.refresh_face()
	_build_entries()
	visible = true
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_paused_tree = not get_tree().paused
	get_tree().paused = true
	_state = "opening"
	_k = 0.0
	_book.open_k = 0.0
	_book.show_k = 0.0
	_book.scale = Vector2(0.55, 0.55)
	_book.modulate.a = 0.0
	_book.rotation = -0.06
	# the closed book sits centred; it slides left by half a page as it opens
	_book.position.x = _base_x() - BOOK_SIZE.x * 0.25
	_list.visible = false
	_footer.modulate.a = 0.0
	_dim.modulate.a = 0.0
	UIFx.event("ui_book_open", {"world": world_id})
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.3)
	tw.tween_property(_book, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_book, "rotation", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_book, "modulate:a", 1.0, 0.2)
	tw.tween_property(_book, "show_k", 1.0, 0.45)
	tw.chain().tween_interval(0.12)
	tw.chain().tween_callback(func() -> void: UIFx.sound("ui_book_close"))
	# 0.8 s in all: the board swings over (0.58 s), lands with a thud, lifts a hair and settles (back-out feel)
	tw.chain().tween_property(_book, "open_k", 1.0, 0.58).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_book, "position:x", _base_x(), 0.58).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(func() -> void:
		UIFx.sound("ui_book_close", 0.78)  # the board lands: a low thud
		_book.pivot_offset = BOOK_SIZE * 0.5)
	tw.chain().tween_property(_book, "scale", Vector2(1.014, 0.986), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(_book, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_on_opened)


func _base_x() -> float:
	return size.x * 0.5 - BOOK_SIZE.x * 0.5


func _on_opened() -> void:
	_state = "open"
	_list.visible = true
	var i := 0
	for e in _entries:
		e.appear = 0.0
		e.delay = i * 0.045
		i += 1
	create_tween().tween_property(_footer, "modulate:a", 1.0, 0.25)
	if _entries.is_empty():
		return
	var first: Control = _entries[0]
	var g := get_node_or_null("/root/Game")
	if g:
		for e in _entries:
			if not g.has_truffle(e.tid):
				first = e
				break
	first.grab_focus()


func _build_entries() -> void:
	for c in _list.get_children():
		c.queue_free()
	_entries.clear()
	var g := get_node_or_null("/root/Game")
	var ts := WorldRegistry.truffles(world_id)
	var got := 0
	var col: Array = []
	for i in ts.size():
		var e := _Entry.new()
		e.number = i + 1
		e.caption = ts[i]["name"]
		e.tid = ts[i]["id"]
		e.goal = WorldRegistry.truffle_goal(e.tid)
		e.collected = g != null and g.has_truffle(e.tid)
		if g and g.has_method("best_time"):
			e.best = g.best_time(e.tid)
		col.append(e.collected)
		if e.collected:
			got += 1
		var tid: String = e.tid
		e.pressed.connect(func() -> void: _choose(tid, e))
		_list.add_child(e)
		_entries.append(e)
	_book.got = got
	_book.total = ts.size()
	_book.collected = col
	for i in _entries.size():
		var e: Control = _entries[i]
		e.focus_neighbor_top = e.get_path_to(_entries[(i - 1 + _entries.size()) % _entries.size()])
		e.focus_neighbor_bottom = e.get_path_to(_entries[(i + 1) % _entries.size()])


func _choose(mission_id: String, entry: Variant = null) -> void:
	if _state != "open":
		return
	_state = "choosing"
	if entry:
		entry.flash = 1.0
	UIFx.event("ui_mission_choose", {"world": world_id, "mission": mission_id})
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_book, "scale", Vector2(1.18, 1.18), 0.4).set_delay(0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_footer, "modulate:a", 0.0, 0.2)
	await tw.finished
	_close()
	chosen.emit(world_id, mission_id)
	var r := get_node_or_null("/root/Router")
	if r:
		r.enter_world(world_id, mission_id)


func _close() -> void:
	_state = "closed"
	visible = false
	if _paused_tree:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.has_feature("web") else _prev_mouse


func cancel() -> void:
	if _state == "closing" or _state == "choosing":
		return
	_state = "closing"
	UIFx.event("ui_back", {"context": "mission"})
	_list.visible = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_book, "open_k", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_footer, "modulate:a", 0.0, 0.15)
	tw.parallel().tween_property(_book, "position:x", _base_x() - BOOK_SIZE.x * 0.25, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_property(_book, "scale", Vector2(0.6, 0.6), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_book, "modulate:a", 0.0, 0.18)
	tw.parallel().tween_property(_dim, "modulate:a", 0.0, 0.18)
	await tw.finished
	_close()
	cancelled.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_back_game") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		cancel()
	elif _state == "opening" and (event.is_action_pressed("ui_accept") or event.is_action_pressed("jump")):
		# impatient readers skip the opening
		get_viewport().set_input_as_handled()

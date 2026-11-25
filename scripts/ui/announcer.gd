extends Control
## Announcements: ribbon banners (mission names), parchment toasts and the "TRUFFLE GET!" splash.

signal splash_finished

var _banner_title := ""
var _banner_sub := ""
var _banner_t := -1.0
var _banner_len := 3.2

var _toasts: Array = []  # {text, t}

var _splash_t := -1.0
var _splash_len := 3.0
var _splash_title := "TRUFFLE GET!"
var _splash_sub := ""
var _time := 0.0
var _confetti: Array = []
var _covered := 0.0
var dbg_banner := {}
var _landed := false
## Where the HUD draws its truffle icon (hud.gd: plaque at 268,52 + icon offset 52,46), layout units.
const HUD_TRUFFLE := Vector2(320, 98)
const FLY_LEN := 0.62


var _rays: Control
var _front: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The splash draws in three passes: the dim (here), additive light rays, then the truffle and words.
	_rays = Control.new()
	_rays.name = "SplashRays"
	_rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_rays.material = add
	add_child(_rays)
	_rays.draw.connect(_draw_rays)
	_front = Control.new()
	_front.name = "SplashFront"
	_front.set_anchors_preset(Control.PRESET_FULL_RECT)
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_front)
	_front.draw.connect(_draw_splash_front)


var _queued_banner: Array = []
## -1 undecided, 0 top slot, 1 lower third (Mak's head was under the top slot when the banner started).
var _banner_low := -1


## Mr. Mak's on-screen box (feet to the top of his hat, about 1.35 m), in layout units; empty when off screen.
func _player_rect() -> Rect2:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	if p == null or cam == null or not p.is_inside_tree():
		return Rect2()
	var feet3 := p.global_position
	var head3 := feet3 + Vector3.UP * 1.35
	if cam.is_position_behind(head3) or cam.is_position_behind(feet3):
		return Rect2()
	var vs := get_viewport().get_visible_rect().size
	var k := size / vs if vs.x > 0.0 and vs.y > 0.0 else Vector2.ONE
	var head := cam.unproject_position(head3) * k
	var feet := cam.unproject_position(feet3) * k
	var h := absf(feet.y - head.y)
	return Rect2(Vector2(head.x - h * 0.35, minf(head.y, feet.y)), Vector2(h * 0.7, h))


func show_banner(title: String, subtitle: String = "", duration: float = 3.2) -> void:
	if _splash_t >= 0.0:
		_queued_banner = [title, subtitle, duration]
		return
	_banner_title = title
	_banner_sub = subtitle
	_banner_len = duration
	_banner_t = 0.0
	_banner_low = -1
	UIFx.event("ui_banner", {"title": title})


func toast(text: String) -> void:
	# critique UI r1: a new toast replaces an identical one, and at most two stack (a stale
	# "The sheep stole..." stayed on screen over the reward dialog)
	_toasts = _toasts.filter(func(t: Dictionary) -> bool: return t["text"] != text)
	_toasts.append({"text": text, "t": 0.0})
	while _toasts.size() > 2:
		_toasts.pop_front()


## Fade the banner and toasts out quickly (pause opening, a dialog taking the screen).
func clear_transient(fast: bool = true) -> void:
	if _banner_t >= 0.0:
		_banner_t = maxf(_banner_t, _banner_len - (0.15 if fast else 0.45))
	for t in _toasts:
		t["t"] = maxf(float(t["t"]), TOAST_LEN - 0.15)


const TOAST_LEN := 3.4


func truffle_splash(subtitle: String = "", title: String = "TRUFFLE GET!", duration: float = 3.0) -> void:
	_splash_title = title
	_splash_sub = subtitle
	_splash_len = duration
	_splash_t = 0.0
	_banner_t = -1.0
	_landed = false
	UIFx.event("ui_truffle_get", {"name": subtitle})
	_confetti.clear()
	for i in 70:
		_confetti.append({
			"p": Vector2(randf_range(-1.0, 1.0) * 120.0, randf_range(-1.0, 1.0) * 60.0),
			"v": Vector2(randf_range(-1.0, 1.0) * 900.0, randf_range(-1300.0, -300.0)),
			"c": [UIStyle.GOLD, UIStyle.RIBBON, UIStyle.CREAM, UIStyle.MINT, UIStyle.BRASS_LIGHT][i % 5],
			"r": randf_range(5.0, 11.0),
			"a": randf() * TAU,
		})


func is_splashing() -> bool:
	return _splash_t >= 0.0


func _process(delta: float) -> void:
	_time += delta
	if _banner_t >= 0.0:
		_banner_t += delta
		if _banner_t > _banner_len:
			_banner_t = -1.0
	# toasts and the banner hold while a dialog or the pause menu owns the screen (they are hidden then)
	var ui := get_node_or_null("/root/UI")
	var in_dialog: bool = ui != null and ui.dialog != null and ui.dialog.is_open()
	var in_pause: bool = ui != null and ui.pause_menu != null and ui.pause_menu.is_open()
	_covered = move_toward(_covered, 1.0 if in_pause else 0.0, delta * 7.0)
	if in_dialog:
		# a dialog answers whatever the toast said; let it go (critique UI r1: stale toast over the dialog)
		for t in _toasts:
			t["t"] = maxf(float(t["t"]), TOAST_LEN - 0.3)
	if in_pause:
		if _banner_t >= 0.0 and _banner_t < _banner_len - 0.15:
			_banner_t = _banner_len - 0.15
	for t in _toasts:
		t["t"] += 0.0 if in_pause else delta
	_toasts = _toasts.filter(func(t: Dictionary) -> bool: return t["t"] < TOAST_LEN)
	if _splash_t >= 0.0:
		_splash_t += delta
		for c in _confetti:
			c["v"].y += 1500.0 * delta
			c["v"] *= 0.985
			c["p"] += c["v"] * delta
			c["a"] += delta * 6.0
		if not _landed and _splash_t >= _splash_len - 0.03:
			_land_truffle()
		if _splash_t > _splash_len:
			_splash_t = -1.0
			splash_finished.emit()
			if not _queued_banner.is_empty():
				var q := _queued_banner
				_queued_banner = []
				show_banner(q[0], q[1], q[2])
	queue_redraw()
	_rays.queue_redraw()
	_front.queue_redraw()


## The big truffle reaches the HUD counter: the HUD pops its icon and rolls the number now.
func _land_truffle() -> void:
	_landed = true
	var ui := get_node_or_null("/root/UI")
	if ui and ui.hud and ui.hud.has_method("truffle_arrive"):
		ui.hud.truffle_arrive()


func _draw() -> void:
	_draw_banner()
	_draw_toasts()
	_draw_splash()


func _draw_banner() -> void:
	if _banner_t < 0.0:
		return
	var inn := clampf(_banner_t / 0.45, 0.0, 1.0)
	var out := clampf((_banner_len - _banner_t) / 0.45, 0.0, 1.0)
	var k := ease(minf(inn, out), -2.4) * (1.0 - _covered)
	var f := UIStyle.display_font()
	var fs := 64
	var tw := f.get_string_size(_banner_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# critique UI r1: long titles pushed the ribbon tail under the HUD plaques. The ribbon (plus its
	# tails, about 57 px each side) must stay right of the plaques (x 560 + 24 gap): shrink the face
	# from 64 down to 44, and if it still does not fit, drop the banner below the plaques.
	# the acorn and truffle plaques end at x 536; keep a 20 px gap after the 57 px ribbon tails
	var max_w := size.x - 2.0 * (536.0 + 20.0 + 57.0)
	var padx := 140.0
	while fs > 44 and tw + padx > max_w:
		fs -= 2
		padx = 92.0
		tw = f.get_string_size(_banner_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var full_w := maxf(tw + padx, 520.0)
	var w := full_w * lerpf(0.3, 1.0, k)
	var ui0 := get_node_or_null("/root/UI")
	var hud_on: bool = ui0 != null and ui0.get("_hud_layer") != null and ui0._hud_layer.visible
	# critique UI r1 (art director): the banner sat on Mak's head at the W1 spawn. It now pins to the top edge
	# (28 px) unless a plaque owns that slot, and drops to the lower third when Mak's head would fall inside it
	# (decided once per banner, so it never jumps mid-read).
	var top := 28.0 if (full_w <= max_w or not hud_on) else 300.0
	var ui := get_node_or_null("/root/UI")
	if ui and ui.hud and ui.hud.timer_visible:
		top = 250.0  # keep clear of the time-trial plaque
	if ui and ui.get("_boss_bar") != null and is_instance_valid(ui._boss_bar) and ui._boss_bar.is_showing():
		top = 300.0  # and of the boss bar
	var band := Rect2((size.x - full_w) * 0.5 - 60.0, top, full_w + 120.0, 104.0 + (58.0 if _banner_sub != "" else 0.0))
	if _banner_low < 0:
		var low_band := Rect2(band.position.x, size.y * 0.74 - 52.0, band.size.x, band.size.y)
		var fig := _player_rect()
		var o_top := fig.intersection(band.grow(24.0)).get_area() if fig.size != Vector2.ZERO else 0.0
		var o_low := fig.intersection(low_band.grow(24.0)).get_area() if fig.size != Vector2.ZERO else 0.0
		# the lower third only when it covers less of Mak than the top slot
		_banner_low = 1 if o_top > 0.0 and o_low < o_top * 0.5 else 0
	if _banner_low == 1:
		top = size.y * 0.74 - 52.0
	dbg_banner = {"size": size, "max_w": max_w, "full_w": full_w, "fs": fs, "hud_on": hud_on, "top": top, "low": _banner_low}
	var y := lerpf(-140.0, top, k) if _banner_low != 1 else lerpf(size.y + 40.0, top, k)
	var rect := Rect2((size.x - w) * 0.5, y, w, 104)
	var col := Color(UIStyle.RIBBON, k)
	UIDraw.ribbon(self, rect, col, Color(UIStyle.BRASS, k))
	if k > 0.6:
		var a := (k - 0.6) / 0.4
		var pos := Vector2((size.x - tw) * 0.5, rect.position.y + 52 + fs * 0.34)
		UIStyle.draw_title(self, pos, _banner_title, fs, a, f)
		if _banner_sub != "":
			var sf := UIStyle.ui_font(650)
			var sw := sf.get_string_size(_banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			var pill := Rect2((size.x - sw) * 0.5 - 30, rect.end.y + 4, sw + 60, 50)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(UIStyle.PARCHMENT, a)
			sb.border_color = Color(UIStyle.INK, a)
			sb.set_border_width_all(3)
			sb.set_corner_radius_all(25)
			sb.shadow_color = Color(0, 0, 0, 0.25 * a)
			sb.shadow_size = 6
			sb.anti_aliasing = true
			draw_style_box(sb, pill)
			draw_string(sf, Vector2((size.x - sw) * 0.5, pill.position.y + 36), _banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(UIStyle.INK, a))


func _draw_toasts() -> void:
	var y := size.y - 60.0
	var f := UIStyle.ui_font(600)
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Dictionary = _toasts[i]
		var k := ease(clampf(minf(t["t"] / 0.25, (TOAST_LEN - t["t"]) / 0.35), 0.0, 1.0), -2.0) * (1.0 - _covered)
		if k <= 0.001:
			continue
		var tw := f.get_string_size(t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		var w := tw + 90.0
		var r := Rect2(size.x - (w + 40.0) * k, y - 66.0, w, 62.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UIStyle.PARCHMENT, k)
		sb.border_color = Color(UIStyle.INK, k)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(31)
		sb.shadow_color = Color(0, 0, 0, 0.25 * k)
		sb.shadow_size = 6
		draw_style_box(sb, r)
		UIDraw.sparkle(self, r.position + Vector2(34, 31), 14.0, Color(UIStyle.BRASS, k))
		draw_string(f, r.position + Vector2(62, 42), t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(UIStyle.INK, k))
		y -= 74.0


func _draw_splash() -> void:
	if _splash_t < 0.0:
		return
	var fade := clampf((_splash_len - _splash_t) / 0.4, 0.0, 1.0)
	var inn := clampf(_splash_t / 0.35, 0.0, 1.0)
	# dim + opening flash (the dim lifts while the truffle flies to the HUD)
	var lift := 1.0 - _fly_k()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.05, 0.0, 0.38 * fade * inn * lift))
	# critique UI r1 (art director): the full-screen white flash and yellow wash flattened the scene. A 2-frame
	# radial burst behind the truffle (45% of the screen height, 50% alpha) gives the hit without the wash.
	if _splash_t < 0.034:
		var bc := _splash_center() + Vector2(0, -60)
		var br := size.y * 0.45
		for k in 8:
			var rk := br * (1.0 - k / 8.0)
			draw_circle(bc, rk, Color(1.0, 0.95, 0.78, 0.5 / 8.0 * (1.0 + k * 0.2)), true, -1.0, true)


func _splash_center() -> Vector2:
	return size * 0.5 + Vector2(0, -40)


## 0 until the last FLY_LEN seconds, then 0 -> 1 while the truffle flies to the HUD counter.
func _fly_k() -> float:
	if _splash_t < 0.0:
		return 0.0
	return clampf((_splash_t - (_splash_len - FLY_LEN)) / FLY_LEN, 0.0, 1.0)


## Soft light rays (critique UI r1: the rays were flat hard-edged stripes). Each ray is a fan with
## per-vertex alpha, bright at the centre and gone at the tips, drawn additively; a second, thinner
## set counter-rotates so the light shimmers instead of reading as a pinwheel.
func _draw_rays() -> void:
	if _splash_t < 0.0:
		return
	var c := _splash_center() + Vector2(0, -60)
	var fade := clampf((_splash_len - _splash_t) / 0.4, 0.0, 1.0) * (1.0 - _fly_k())
	var inn := ease(clampf(_splash_t / 0.45, 0.0, 1.0), -2.0)
	if fade <= 0.0 or inn <= 0.0:
		return
	var warm := Color(1.0, 0.82, 0.38)
	var rr := size.y * 0.6 * inn  # the rays fade out by 60% of the screen height (no edge-to-edge stripes)
	for set_i in 2:
		var n := 14 if set_i == 0 else 22
		var spin := _time * (0.22 if set_i == 0 else -0.37)
		var wid := (TAU / n) * (0.42 if set_i == 0 else 0.16)
		var a_c := (0.34 if set_i == 0 else 0.22) * fade
		for i in n:
			var a0 := TAU * i / n + spin
			var mid := a0 + wid * 0.5
			var pts := PackedVector2Array([c + Vector2(cos(mid), sin(mid)) * 40.0, c + Vector2(cos(a0), sin(a0)) * rr, c + Vector2(cos(mid), sin(mid)) * rr * 1.04, c + Vector2(cos(a0 + wid), sin(a0 + wid)) * rr])
			var cols := PackedColorArray([Color(warm, a_c), Color(warm, 0.0), Color(warm, 0.0), Color(warm, 0.0)])
			_rays.draw_polygon(pts, cols)
	# a soft radial glow behind the truffle (concentric discs, additive)
	for k in 10:
		var r := lerpf(260.0, 40.0, k / 9.0) * inn
		_rays.draw_circle(c, r, Color(1.0, 0.86, 0.5, 0.05 * fade), true, -1.0, true)


func _draw_splash_front() -> void:
	if _splash_t < 0.0:
		return
	var ci := _front
	var c := _splash_center()
	var fade := clampf((_splash_len - _splash_t) / 0.4, 0.0, 1.0)
	var fk := _fly_k()
	# big golden truffle (generated icon): elastic entrance, wobble, star ring, then a curved flight
	# into the HUD truffle counter (critique UI r1: the reward never connected to the HUD)
	var ent := UIFx.elastic_out(clampf(_splash_t / 0.7, 0.0, 1.0))
	var tc := c + Vector2(0, -70 + sin(_time * 3.0) * 8.0 * (1.0 - fk))
	var tsize := 290.0 * ent
	var trot := sin(_time * 2.2) * 0.08
	if fk > 0.0:
		var e := fk * fk * (3.0 - 2.0 * fk)
		var start := tc + Vector2(0, 10)
		var ctrl := Vector2(lerpf(start.x, HUD_TRUFFLE.x, 0.25), minf(start.y, HUD_TRUFFLE.y) - 220.0)
		var p := start.lerp(ctrl, e).lerp(ctrl.lerp(HUD_TRUFFLE, e), e)
		tc = p - Vector2(0, 10)
		tsize = lerpf(290.0, 96.0, e)
		trot = lerpf(trot, -TAU, e)
		# a little gold trail behind the flight
		for k in 6:
			var tk := clampf(e - 0.05 * (k + 1), 0.0, 1.0)
			var tp := start.lerp(ctrl, tk).lerp(ctrl.lerp(HUD_TRUFFLE, tk), tk)
			UIDraw.sparkle(ci, tp, (16.0 - k * 2.0) * (1.0 - e * 0.5), Color(1, 0.95, 0.7, 0.8 * (1.0 - k / 6.0)))
	var fly_alpha := 1.0 if fk > 0.0 else fade
	if fk <= 0.0:
		UIFx.draw_burst(ci, tc, clampf(_splash_t / 0.9, 0.0, 1.0), 12, 230.0, UIStyle.GOLD, 5)
		UIFx.draw_burst(ci, tc, clampf((_splash_t - 0.15) / 0.9, 0.0, 1.0), 9, 160.0, Color(1, 1, 0.9), 2)
	var tt := UIFx.tex("truffle")
	if tt:
		UIFx.draw_icon(ci, tt, tc + Vector2(0, 10), tsize, trot, Color(1, 1, 1, fly_alpha))
		if fk < 0.5:
			for k in 3:
				var a := _time * 1.7 + k * TAU / 3.0
				UIDraw.sparkle(ci, tc + Vector2(cos(a) * 120.0, sin(a) * 90.0) * (1.0 - fk * 2.0), (14.0 + 8.0 * sin(_time * 5.0 + k)) * ent, Color(1, 1, 0.85, 0.95 * fade))
	else:
		UIDraw.truffle(ci, tc, 92.0 * ent, true, _time)
	# confetti
	for p in _confetti:
		var pos: Vector2 = c + p["p"]
		var s2: float = p["r"]
		var ang: float = p["a"]
		var d := Vector2(cos(ang), sin(ang)) * s2
		ci.draw_colored_polygon(PackedVector2Array([pos - d, pos + d.orthogonal() * 0.5, pos + d, pos - d.orthogonal() * 0.5]), Color(p["c"], fade))
	# title text, letter by letter pop, in the chunky rounded face that echoes the logo's "64"
	var word_a := fade * (1.0 - fk)
	var f := UIStyle.number_font()
	var fs := 132
	var total_w := f.get_string_size(_splash_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := c.x - total_w * 0.5
	for i in _splash_title.length():
		var ch := _splash_title[i]
		var cw := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lt := clampf((_splash_t - 0.15 - i * 0.045) / 0.25, 0.0, 1.0)
		if lt > 0.0 and word_a > 0.0:
			var sc := 1.0 + 0.6 * (1.0 - ease(lt, -3.0))
			var y := c.y + 150.0 + sin(_time * 6.0 + i * 0.6) * 6.0
			var cs := int(fs * sc)
			var off := (f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x - cw) * 0.5
			# the logo's own treatment (critique UI r1 polish): cream fill, maroon rim, ink drop and a gold glint
			ci.draw_string_outline(f, Vector2(x - off, y + 9), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, 26, Color(UIStyle.INK, 0.8 * word_a * lt))
			ci.draw_string_outline(f, Vector2(x - off, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, 22, Color(UIStyle.RIBBON_DARK, word_a * lt))
			ci.draw_string_outline(f, Vector2(x - off, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, 8, Color(UIStyle.BRASS, word_a * lt))
			ci.draw_string(f, Vector2(x - off, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, Color(UIStyle.CREAM, word_a * lt))
			var glint := clampf(1.0 - absf(fmod(_time * 0.9, 2.2) - (0.4 + i * 0.07)) * 6.0, 0.0, 1.0)
			ci.draw_string(f, Vector2(x - off - 2, y - 4), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, Color(UIStyle.GOLD, (0.18 + 0.5 * glint) * word_a * lt))
		x += cw
	if _splash_sub != "" and _splash_t > 0.7 and word_a > 0.0:
		var a := clampf((_splash_t - 0.7) / 0.3, 0.0, 1.0) * word_a
		var sf := UIStyle.ui_font(650)
		var sw := sf.get_string_size(_splash_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
		var r := Rect2(c.x - sw * 0.5 - 50, c.y + 196, sw + 100, 80)
		UIDraw.ribbon(ci, r, Color(UIStyle.RIBBON, a), Color(UIStyle.BRASS, a))
		ci.draw_string(sf, Vector2(c.x - sw * 0.5, r.position.y + 56), _splash_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(UIStyle.CREAM, a))

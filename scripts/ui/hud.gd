extends Control
## In-game HUD (storybook v2): the Victoria-sponge cake meter built from the generated cake art
## (plate + six wedges), truffle and acorn counters with the real icons and rolling numbers, the
## Lost Page card, the time-trial plaque and a contextual button prompt.
## Reads the Game autoload. Layout is authored for 1920x1080 and scales with the canvas.

signal timer_expired

const WEDGE := "res://assets/ui/icon_cake_wedge_%d.png"
const CAKE_C := Vector2(150, 148)
const CAKE_SIZE := 236.0

var health := 6
var max_health := 6
var truffles := 0
var acorns := 0

var _t := 0.0
var _wedges: Array[Texture2D] = []
var _flying: Array = []  # {i, t, dir, spin}
var _arriving: Dictionary = {}  # wedge index -> t (1 -> 0)
var _cake_shake := 0.0
var _cake_glow := 0.0
var _crumbs: Array = []

var _truffle_pop := 0.0
var _truffle_burst := 0.0
var _truffle_shown := 0.0
var _truffle_hold := 0.0  # >0: the grace period before a pop with no splash; -1 while a splash runs
var _acorn_pop := 0.0
var _acorn_shown := 0.0
var _acorn_burst := 0.0
var _acorn_tick_acc := 0.0

var _page_show := 0.0
var _page_timer := 0.0
var _page_world := ""
var _page_count := 0
var _page_new_t := 0.0

var _pill_w := 0.0
var timer_running := false
var timer_visible := false
var timer_value := 0.0
var timer_countdown := 0.0
var timer_label := ""
var _timer_show := 0.0
var _timer_last_sec := -1
var _timer_flash := 0.0

var _prompt_action := ""
var _prompt_text := ""
var _prompt_show := 0.0

var _intro := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 6:
		var p := WEDGE % i
		_wedges.append(load(p) as Texture2D if ResourceLoader.exists(p) else null)
	var g := get_node_or_null("/root/Game")
	if g:
		health = g.health
		max_health = g.max_health
		truffles = g.truffle_count()
		_truffle_shown = truffles
		acorns = g.acorns
		_acorn_shown = acorns
		g.health_changed.connect(_on_health)
		g.acorns_changed.connect(_on_acorns)
		g.truffle_collected.connect(func(_id: String) -> void: _on_truffles(g.truffle_count()))
		g.page_collected.connect(_on_page)
		g.progress_loaded.connect(func() -> void:
			truffles = g.truffle_count()
			_truffle_shown = truffles
			acorns = g.acorns
			_acorn_shown = acorns
			health = g.health)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_intro = 0.0)


# ---------------------------------------------------------------- game events

func _on_health(v: int) -> void:
	v = clampi(v, 0, max_health)
	if v < health:
		for i in range(v, health):
			_flying.append({"i": i, "t": 0.0, "dir": randf_range(-1.0, 1.0), "spin": randf_range(-1.0, 1.0)})
			_arriving.erase(i)
		_cake_shake = 1.0
		for k in 10:
			_crumbs.append({"p": CAKE_C + Vector2(randf_range(-40, 40), randf_range(-20, 30)), "v": Vector2(randf_range(-260, 260), randf_range(-420, -120)), "t": 0.0, "r": randf_range(4, 9)})
		UIFx.event("ui_cake_lose", {"health": v})
		if v <= 2 and v > 0:
			UIFx.event("ui_cake_low", {"health": v})
	elif v > health:
		for i in range(health, v):
			_arriving[i] = 1.0 + (i - health) * 0.18
		_cake_glow = 1.0
		UIFx.event("ui_cake_gain", {"health": v})
	health = v


func _on_acorns(v: int) -> void:
	if v > acorns:
		_acorn_pop = 1.0
		_acorn_burst = 0.001
		UIFx.event("ui_acorn_count", {"value": v})
	acorns = v


func _on_truffles(v: int) -> void:
	if v > truffles:
		# critique UI r1: the count used to change under the splash dim. Hold the old number until the
		# splash truffle flies into this plaque (truffle_arrive); with no splash, pop after a short grace.
		_truffle_hold = 0.3
	truffles = v


## Called by the announcer when the TRUFFLE GET truffle lands on the HUD counter.
func truffle_arrive() -> void:
	_truffle_hold = 0.0
	_truffle_pop = 1.0
	_truffle_burst = 0.001
	UIFx.event("ui_truffle_count", {"value": truffles})


func _on_page(world_id: String, _i: int) -> void:
	var g := get_node_or_null("/root/Game")
	show_page_popup(world_id, g.page_count(world_id) if g else _page_count + 1)


func show_page_popup(world_id: String, count: int) -> void:
	_page_world = world_id
	_page_count = clampi(count, 0, 5)
	_page_timer = 3.6
	_page_new_t = 1.0
	UIFx.event("ui_page_popup", {"world": world_id, "count": count})


## Contextual button prompt above the bottom edge ("" hides it). Example: show_prompt("interact", "Talk").
func show_prompt(action: String, text: String) -> void:
	_prompt_action = action
	_prompt_text = text


# ---------------------------------------------------------------- timer API

func timer_start(label: String = "", countdown: float = 0.0) -> void:
	timer_label = label
	timer_countdown = countdown
	timer_value = countdown if countdown > 0.0 else 0.0
	timer_running = true
	timer_visible = true
	_timer_last_sec = -1
	UIFx.event("ui_timer_start", {"label": label, "countdown": countdown})


func timer_stop() -> float:
	timer_running = false
	_timer_flash = 1.0
	return timer_value


func timer_hide() -> void:
	timer_running = false
	timer_visible = false


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	_t += delta
	_intro = minf(1.0, _intro + delta * 2.2)
	_cake_shake = move_toward(_cake_shake, 0.0, delta * 2.6)
	_cake_glow = move_toward(_cake_glow, 0.0, delta * 1.6)
	for f in _flying:
		f["t"] += delta
	_flying = _flying.filter(func(f: Dictionary) -> bool: return f["t"] < 1.1)
	for k in _arriving.keys():
		_arriving[k] = float(_arriving[k]) - delta * 2.4
		if _arriving[k] <= 0.0:
			_arriving.erase(k)
	for c in _crumbs:
		c["t"] += delta
		c["v"].y += 1400.0 * delta
		c["p"] += c["v"] * delta
	_crumbs = _crumbs.filter(func(c: Dictionary) -> bool: return c["t"] < 0.9)
	_truffle_pop = move_toward(_truffle_pop, 0.0, delta * 1.6)
	_acorn_pop = move_toward(_acorn_pop, 0.0, delta * 2.8)
	if _truffle_burst > 0.0:
		_truffle_burst += delta * 1.5
		if _truffle_burst >= 1.0:
			_truffle_burst = 0.0
	if _acorn_burst > 0.0:
		_acorn_burst += delta * 2.2
		if _acorn_burst >= 1.0:
			_acorn_burst = 0.0
	# rolling numbers (the truffle count waits for the splash truffle to arrive)
	if _truffle_hold != 0.0:
		var ui := get_node_or_null("/root/UI")
		var splashing: bool = ui != null and ui.announcer != null and ui.announcer.is_splashing()
		if splashing:
			_truffle_hold = -1.0
		elif _truffle_hold > 0.0:
			_truffle_hold -= delta
			if _truffle_hold <= 0.0:
				truffle_arrive()
		else:
			truffle_arrive()  # the splash ended without landing (skipped or cut short)
	if _truffle_hold == 0.0:
		_truffle_shown = move_toward(_truffle_shown, truffles, delta * maxf(4.0, absf(truffles - _truffle_shown) * 3.0))
	_acorn_shown = move_toward(_acorn_shown, acorns, delta * maxf(12.0, absf(acorns - _acorn_shown) * 5.0))
	# Lost Page card
	if _page_timer > 0.0:
		_page_timer -= delta
	_page_new_t = move_toward(_page_new_t, 0.0, delta * 1.4)
	_page_show = move_toward(_page_show, 1.0 if _page_timer > 0.0 else 0.0, delta * (3.5 if _page_timer > 0.0 else 2.5))
	# prompt
	_prompt_show = move_toward(_prompt_show, 1.0 if _prompt_text != "" else 0.0, delta * 6.0)
	# timer
	_timer_show = move_toward(_timer_show, 1.0 if timer_visible else 0.0, delta * 4.0)
	_timer_flash = move_toward(_timer_flash, 0.0, delta * 1.5)
	if timer_running and not get_tree().paused:
		if timer_countdown > 0.0:
			timer_value = maxf(0.0, timer_value - delta)
			var sec := int(ceil(timer_value))
			if sec != _timer_last_sec:
				_timer_last_sec = sec
				if sec <= 5 and sec > 0:
					UIFx.event("ui_timer_tick", {"seconds": sec}, 1.0 + (5 - sec) * 0.06)
			if timer_value <= 0.0:
				timer_running = false
				_timer_flash = 1.0
				UIFx.event("ui_timer_end", {"label": timer_label})
				timer_expired.emit()
		else:
			timer_value += delta
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _medallion(c: Vector2, r: float) -> void:
	draw_circle(c + Vector2(0, 7), r, Color(0.12, 0.05, 0.02, 0.35), true, -1.0, true)
	draw_circle(c, r, UIStyle.INK, true, -1.0, true)
	draw_circle(c, r - 5, UIStyle.BRASS_DARK, true, -1.0, true)
	draw_circle(c, r - 9, UIStyle.BRASS, true, -1.0, true)
	draw_circle(c, r - 14, UIStyle.PARCHMENT, true, -1.0, true)
	draw_arc(c, r - 20, 0, TAU, 64, Color(UIStyle.BRASS_DARK, 0.45), 2.0, true)
	# gilt beads around the ring
	for i in 24:
		var a := TAU * i / 24.0
		draw_circle(c + Vector2(cos(a), sin(a)) * (r - 7), 2.2, Color(UIStyle.BRASS_LIGHT, 0.9), true, -1.0, true)


func _plaque(rect: Rect2, fill: Color = UIStyle.PARCHMENT, rim: Color = UIStyle.INK, gilt: Color = UIStyle.BRASS) -> void:
	var rad := int(rect.size.y * 0.5)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0.12, 0.05, 0.02, 0.33)
	sh.set_corner_radius_all(rad)
	sh.anti_aliasing = true
	draw_style_box(sh, Rect2(rect.position + Vector2(0, 7), rect.size))
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = rim
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(rad)
	sb.anti_aliasing = true
	draw_style_box(sb, rect)
	var hi := StyleBoxFlat.new()
	hi.bg_color = Color(1, 1, 1, 0.22)
	hi.set_corner_radius_all(int(rad * 0.7))
	hi.anti_aliasing = true
	draw_style_box(hi, Rect2(rect.position + Vector2(rad * 0.6, 9), Vector2(rect.size.x - rad * 1.2, rect.size.y * 0.28)))
	var inner := StyleBoxFlat.new()
	inner.draw_center = false
	inner.border_color = Color(gilt, 0.85)
	inner.set_border_width_all(2)
	inner.set_corner_radius_all(rad - 8)
	inner.anti_aliasing = true
	draw_style_box(inner, rect.grow(-9))


func _draw() -> void:
	var slide := UIFx.back_out(_intro)
	_draw_cake(Vector2(-260.0 * (1.0 - slide), 0))
	_draw_counters(Vector2(-420.0 * (1.0 - UIFx.back_out(clampf(_intro * 1.2 - 0.15, 0.0, 1.0))), 0))
	_draw_timer()
	_draw_page_card()
	_draw_prompt()
	_draw_objective()


# ---------------------------------------------------------------- objective line (UI.set_objective)

var objective := ""
var _obj_show := 0.0
var _obj_pop := 0.0


func set_objective(text: String) -> void:
	if text == objective:
		return
	objective = text
	if text != "":
		_obj_pop = 1.0


## One persistent objective line under the counters (critique UI r1 re-run: the sheep chase gave no
## lasting instruction, only a toast). A parchment tag with a ribbon bookmark; it pops when it changes.
func _draw_objective() -> void:
	_obj_show = move_toward(_obj_show, 1.0 if objective != "" else 0.0, get_process_delta_time() * 4.0)
	_obj_pop = move_toward(_obj_pop, 0.0, get_process_delta_time() * 2.5)
	if _obj_show <= 0.01 or objective == "":
		return
	var e := UIFx.back_out(_obj_show)
	var f := UIStyle.ui_font(650)
	var fs := 28
	var tw := f.get_string_size(objective, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(Vector2(40.0 - (tw + 120.0) * (1.0 - e), 268), Vector2(tw + 90.0, 54))
	var sc := 1.0 + UIFx.pop(_obj_pop) * 0.06
	draw_set_transform(r.position * (1.0 - sc), 0.0, Vector2(sc, sc))
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0.12, 0.05, 0.02, 0.3)
	sh.set_corner_radius_all(12)
	draw_style_box(sh, Rect2(r.position + Vector2(0, 6), r.size))
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIStyle.PARCHMENT
	sb.border_color = UIStyle.INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.anti_aliasing = true
	draw_style_box(sb, r)
	# ribbon bookmark on the left edge
	var bx := r.position.x + 18.0
	draw_colored_polygon(PackedVector2Array([Vector2(bx, r.position.y - 6), Vector2(bx + 22, r.position.y - 6), Vector2(bx + 22, r.end.y + 10), Vector2(bx + 11, r.end.y + 2), Vector2(bx, r.end.y + 10)]), UIStyle.RIBBON)
	draw_line(Vector2(bx + 4, r.position.y - 6), Vector2(bx + 4, r.end.y + 4), Color(UIStyle.BRASS, 0.8), 2.0)
	draw_string(f, Vector2(r.position.x + 58, r.position.y + 37), objective, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIStyle.INK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_cake(off: Vector2) -> void:
	var c := CAKE_C + off
	var low := health <= 2 and health > 0
	var shake := Vector2(sin(_t * 71.0), cos(_t * 53.0)) * 9.0 * _cake_shake * _cake_shake
	if low:
		shake += Vector2(sin(_t * 31.0), 0) * 1.5
		var pulse := 0.5 + 0.5 * sin(_t * 7.0)
		draw_circle(c, 132 + pulse * 8.0, Color(UIStyle.DANGER, 0.22 + 0.25 * pulse), true, -1.0, true)
	if _cake_glow > 0.0:
		draw_circle(c, 128 + 30 * (1.0 - _cake_glow), Color(1.0, 0.92, 0.55, 0.5 * _cake_glow), true, -1.0, true)
	_medallion(c + shake * 0.3, 126)
	var cc := c + shake
	var plate := UIFx.tex("cake_plate")
	var breathe := 1.0 + (0.03 * sin(_t * 8.0) if low else 0.0)
	UIFx.draw_icon(self, plate, cc + Vector2(0, 4), CAKE_SIZE * breathe)
	for i in 6:
		if i >= health or _wedges[i] == null:
			continue
		var w := _wedges[i]
		if _arriving.has(i):
			var a := clampf(float(_arriving[i]), 0.0, 1.0)
			var k := 1.0 - a
			var drop := Vector2(0, -150.0 * (1.0 - UIFx.back_out(k, 2.4)))
			var sc := lerpf(1.35, 1.0, UIFx.elastic_out(k))
			draw_set_transform(cc + drop, 0.0, Vector2(sc, sc))
			_wedge(i, Vector2.ZERO, CAKE_SIZE * breathe, Color(1, 1, 1, clampf(k * 3.0, 0.0, 1.0)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			_wedge(i, cc, CAKE_SIZE * breathe)
	_wedge_gaps(cc, CAKE_SIZE * breathe)
	# wedges flying off
	for f in _flying:
		var i: int = f["i"]
		if i < 0 or i >= 6 or _wedges[i] == null:
			continue
		var t: float = f["t"]
		var mid := -PI * 0.5 + (i + 0.5) * TAU / 6.0
		var out := Vector2(cos(mid), sin(mid))
		var p := cc + out * 140.0 * t + Vector2(float(f["dir"]) * 60.0 * t, -260.0 * t + 900.0 * t * t)
		var rot := float(f["spin"]) * 5.0 * t
		draw_set_transform(p, rot, Vector2.ONE * (1.0 + 0.25 * sin(minf(t * 3.0, PI))))
		_wedge(i, Vector2.ZERO, CAKE_SIZE, Color(1, 1, 1, clampf(1.6 - t * 1.6, 0.0, 1.0)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for cr in _crumbs:
		var a2 := 1.0 - float(cr["t"]) / 0.9
		draw_circle(cr["p"] + off, cr["r"], Color("e3b066", a2), true, -1.0, true)
		draw_circle(cr["p"] + off + Vector2(-1, -1), cr["r"] * 0.5, Color("fff0c8", a2), true, -1.0, true)
	# 0 slices: an empty plate with a sad crumb
	if health <= 0:
		var f := UIStyle.display_font()
		UIFx.draw_outlined(self, f, cc + Vector2(-58, 14), "Crumbs!", 34, UIStyle.DANGER, UIStyle.CREAM, 8)


## Cake wedges are cut at draw time from the whole generated cake (icon_cake.png), so there are no
## baked ink lines (critique UI r1: divider lines crossed the empty plate and ran onto the jam).
## Wedge i spans -90 + 60 i .. -90 + 60 (i + 1) degrees, clockwise from twelve o'clock.
const CAKE_CENTRE_UV := Vector2(0.5, 0.47)
## The sponge's top face in the cake texture (uv): gaps stop at its edge, never on the jam or plate.
const SPONGE_UV := Vector2(0.5, 0.42)
const SPONGE_R := 0.345

func _wedge(i: int, c: Vector2, sz: float, mod: Color = Color.WHITE) -> void:
	var tex := UIFx.tex("cake")
	if tex == null:
		if i < _wedges.size() and _wedges[i] != null:
			UIFx.draw_icon(self, _wedges[i], c, sz, 0.0, mod)
		return
	var org := c - Vector2(sz, sz) * 0.5
	var o := org + CAKE_CENTRE_UV * sz
	var pts := PackedVector2Array([o])
	var a0 := -PI * 0.5 + i * TAU / 6.0
	var segs := 12
	for k in segs + 1:
		var a := a0 + (TAU / 6.0) * k / segs
		pts.append(o + Vector2(cos(a), sin(a)) * sz * 0.52)
	var uvs := PackedVector2Array()
	for pt in pts:
		uvs.append((pt - org) / sz)
	draw_colored_polygon(pts, mod, uvs, tex)


## Soft cream gaps only between two wedges that are both on the plate, stopping at the sponge's edge.
func _wedge_gaps(c: Vector2, sz: float) -> void:
	if UIFx.tex("cake") == null:
		return
	var o := c - Vector2(sz, sz) * 0.5 + CAKE_CENTRE_UV * sz
	var oc := CAKE_CENTRE_UV - SPONGE_UV
	for k in 6:
		var left := (k + 5) % 6
		var on_l := left < health and not _arriving.has(left)
		var on_r := k < health and not _arriving.has(k)
		if not (on_l and on_r):
			continue
		var a := -PI * 0.5 + k * TAU / 6.0
		var d := Vector2(cos(a), sin(a))
		# distance along d from the cut centre to the sponge rim (ray-circle intersection)
		var b := d.dot(oc)
		var r := (-b + sqrt(maxf(b * b - (oc.length_squared() - SPONGE_R * SPONGE_R), 0.0))) * sz - 3.0
		draw_line(o + d * 6.0 + Vector2(1.2, 1.6), o + d * r + Vector2(1.2, 1.6), Color(0.35, 0.16, 0.05, 0.22), 2.6, true)
		draw_line(o + d * 6.0, o + d * r, Color(1.0, 0.96, 0.86, 0.9), 2.0, true)


func _draw_counters(off: Vector2) -> void:
	var f := UIStyle.number_font()
	# critique UI r1 (art director): fixed-width pills left "x 1" in 60% empty space with unaligned right edges.
	# Both pills share one width sized to the larger count (at least two digits) and grow smoothly.
	var tnum0 := str(int(round(_truffle_shown)))
	var anum0 := str(int(round(_acorn_shown)))
	var tw0 := f.get_string_size(tnum0 if tnum0.length() >= 2 else "00", HORIZONTAL_ALIGNMENT_LEFT, -1, 62).x
	var aw0 := f.get_string_size(anum0 if anum0.length() >= 2 else "00", HORIZONTAL_ALIGNMENT_LEFT, -1, 50).x
	var want_w := maxf(142.0 + tw0 + 36.0, 118.0 + aw0 + 36.0)
	_pill_w = want_w if _pill_w <= 0.0 else lerpf(_pill_w, want_w, 0.18)
	# truffle plaque
	var tr := Rect2(Vector2(268, 52) + off, Vector2(_pill_w, 96))
	_plaque(tr)
	var tp := UIFx.pop(_truffle_pop)
	var tic := tr.position + Vector2(52, 46)
	UIFx.draw_burst(self, tic, _truffle_burst, 8, 70.0, UIStyle.GOLD, 3)
	UIFx.draw_icon(self, UIFx.tex("truffle"), tic + Vector2(0, -tp * 14.0), 96.0 * (1.0 + tp * 0.45), sin(_t * 2.0) * 0.06 + tp * 0.5)
	var sparkle := 0.5 + 0.5 * sin(_t * 3.1)
	UIDraw.sparkle(self, tic + Vector2(30, -30), 7.0 + 6.0 * sparkle, Color(1, 1, 0.85, 0.9))
	var tnum := str(int(round(_truffle_shown)))
	var tfs := int(62 * (1.0 + tp * 0.3))
	_draw_x(tr.position + Vector2(110, 66), tfs)
	# critique UI r1: one rule for both counters, INK digits with a CREAM outline, GOLD only during the pop
	UIFx.draw_outlined(self, f, tr.position + Vector2(142, 76 + tp * 2.0), tnum, tfs, UIStyle.INK.lerp(UIStyle.GOLD, clampf(tp * 1.6, 0.0, 1.0)), UIStyle.CREAM.lerp(UIStyle.INK, clampf(tp * 1.6, 0.0, 1.0)), 10)
	# acorn plaque
	var ar := Rect2(Vector2(268, 162) + off, Vector2(_pill_w, 80))
	_plaque(ar)
	var ap := UIFx.pop(_acorn_pop)
	var aic := ar.position + Vector2(44, 38)
	UIFx.draw_burst(self, aic, _acorn_burst, 6, 50.0, Color("f0b35a"), 1)
	UIFx.draw_icon(self, UIFx.tex("acorn"), aic + Vector2(0, -ap * 10.0), 72.0 * (1.0 + ap * 0.4), -0.12 + ap * 0.6 + sin(_t * 1.7) * 0.05)
	var afs := int(50 * (1.0 + ap * 0.25))
	_draw_x(ar.position + Vector2(90, 54), afs)
	UIFx.draw_outlined(self, f, ar.position + Vector2(118, 61), str(int(round(_acorn_shown))), afs, UIStyle.INK.lerp(UIStyle.GOLD, clampf(ap * 1.6, 0.0, 1.0)), UIStyle.CREAM.lerp(UIStyle.INK, clampf(ap * 1.6, 0.0, 1.0)), 9)


func _draw_x(pos: Vector2, fs: int) -> void:
	var f := UIStyle.ui_font(700)
	var s := int(fs * 0.5)
	draw_string_outline(f, pos, "x", HORIZONTAL_ALIGNMENT_LEFT, -1, s, 8, UIStyle.CREAM)
	draw_string(f, pos, "x", HORIZONTAL_ALIGNMENT_LEFT, -1, s, UIStyle.INK_SOFT)


func _draw_timer() -> void:
	if _timer_show <= 0.01:
		return
	var k := UIFx.back_out(_timer_show)
	var w := 380.0
	var y := lerpf(-130.0, 34.0, k)
	var r := Rect2((size.x - w) * 0.5, y, w, 96)
	# critique UI r1 (art director): the boss bar drew over the timer. While the bar is up, the timer moves
	# beside the bar's right end.
	var ui := get_node_or_null("/root/UI")
	if ui and ui.get("_boss_bar") != null and is_instance_valid(ui._boss_bar) and ui._boss_bar.is_showing():
		# to the right of the bar, on its row: clear of the name ribbon and the phase tag below it
		r = Rect2(size.x * 0.5 + 404.0, lerpf(-130.0, 104.0, k), w * 0.8, 80)
	var small := r.size.y < 90.0
	var warn := timer_countdown > 0.0 and timer_value < 10.0 and timer_running
	var pulse := (0.5 + 0.5 * sin(_t * TAU * 2.0)) if warn else 0.0
	# one material with the counters: a cream pill with a brass ring and ink digits; GOLD only pulses in the last 10 s
	_plaque(r, UIStyle.CREAM.lerp(UIStyle.GOLD, pulse * 0.55), UIStyle.INK, UIStyle.BRASS)
	# stopwatch medallion on the left
	var sc := r.position + Vector2(r.size.y * 0.5, r.size.y * 0.5)
	draw_circle(sc, 34, UIStyle.INK, true, -1.0, true)
	draw_circle(sc, 30, UIStyle.BRASS, true, -1.0, true)
	draw_circle(sc, 24, UIStyle.CREAM, true, -1.0, true)
	draw_rect(Rect2(sc + Vector2(-6, -44), Vector2(12, 10)), UIStyle.BRASS)
	var frac := fmod(timer_value, 60.0) / 60.0
	var ang := -PI * 0.5 + frac * TAU
	draw_line(sc, sc + Vector2(cos(ang), sin(ang)) * 19.0, UIStyle.RIBBON, 3.5, true)
	draw_circle(sc, 3.5, UIStyle.INK, true, -1.0, true)
	# digits with fixed advance so they never jitter
	var txt := UIStyle.format_time(timer_value)
	var f := UIStyle.number_font()
	var fs := int((44 if small else 56) * (1.0 + 0.12 * pulse + 0.25 * UIFx.pop(_timer_flash)))
	var adv := fs * 0.58
	var x := r.position.x + r.size.y
	var col := UIStyle.INK.lerp(UIStyle.DANGER, pulse) if warn else UIStyle.INK
	if _timer_flash > 0.0 and not timer_running:
		col = col.lerp(UIStyle.RIBBON, _timer_flash)
	for ch in txt:
		var cw := adv * (0.45 if ch == ":" or ch == "." else 1.0)
		var gw := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		UIFx.draw_outlined(self, f, Vector2(x + (cw - gw) * 0.5, r.position.y + r.size.y * 0.5 + fs * 0.36), ch, fs, col, UIStyle.CREAM, 8, false)
		x += cw
	if timer_label != "":
		var lf := UIStyle.ui_font(650)
		var lw := lf.get_string_size(timer_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		var rr := Rect2((size.x - lw) * 0.5 - 28, r.end.y + 8, lw + 56, 42)
		UIDraw.ribbon(self, rr, Color(UIStyle.RIBBON, k), Color(UIStyle.BRASS, k))
		draw_string(lf, Vector2((size.x - lw) * 0.5, rr.position.y + 31), timer_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(UIStyle.CREAM, k))


func _draw_page_card() -> void:
	if _page_show <= 0.01:
		return
	var e := UIFx.back_out(_page_show) if _page_timer > 0.0 else ease(_page_show, 0.5)
	var w := 470.0
	var r := Rect2(size.x - (w + 40.0) * e, 300, w, 170)
	_plaque(Rect2(r.position, Vector2(r.size.x + 60, r.size.y)), UIStyle.PARCHMENT, UIStyle.INK, UIStyle.BRASS)
	var f := UIStyle.display_font()
	UIFx.draw_outlined(self, f, r.position + Vector2(42, 62), "Lost Page", 44, UIStyle.RIBBON, UIStyle.CREAM, 8, false)
	var cnt := "%d / 5" % _page_count
	UIFx.draw_outlined(self, UIStyle.number_font(), r.position + Vector2(306, 62), cnt, 46, UIStyle.INK, UIStyle.CREAM, 8, false)
	var pt := UIFx.tex("page")
	for i in 5:
		var pc := r.position + Vector2(70 + i * 84, 118)
		var got := i < _page_count
		var is_new := i == _page_count - 1 and _page_new_t > 0.0
		if got:
			var lift := 0.0
			var sc := 64.0
			var rot := sin(_t * 2.0 + i) * 0.05
			if is_new:
				var k := 1.0 - _page_new_t
				lift = -60.0 * (1.0 - UIFx.back_out(k, 2.0))
				sc = 64.0 * (1.0 + 0.5 * (1.0 - UIFx.elastic_out(k)))
				rot += (1.0 - k) * 2.5
				UIFx.draw_burst(self, pc, k, 6, 46.0, UIStyle.GOLD, i)
			UIFx.draw_icon(self, pt, pc + Vector2(0, lift), sc, rot)
		else:
			UIFx.draw_icon(self, pt, pc, 58.0, 0.0, Color(0.35, 0.22, 0.12, 0.28))


func _draw_prompt() -> void:
	if _prompt_show <= 0.01:
		return
	var e := UIFx.back_out(_prompt_show)
	var f := UIStyle.ui_font(650)
	var fs := 32
	var gh := 52.0
	var gw := UIPrompts.glyph_width(_prompt_action, gh)
	var tw := f.get_string_size(_prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := gw + tw + 70.0
	var r := Rect2((size.x - w) * 0.5, size.y - 150.0 + (1.0 - e) * 80.0, w, 76)
	_plaque(r)
	UIPrompts.draw_glyph(self, r.position + Vector2(24 + gw * 0.5, 38), _prompt_action, gh, e)
	draw_string(f, r.position + Vector2(36 + gw, 50), _prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UIStyle.INK, e))

class_name StorybookBossBar
extends CanvasLayer
## Storybook boss health bar for the boss track. Drop-in API match for BossHealthBar:
##   var bar := StorybookBossBar.new(); add_child(bar)
##   bar.show_bar("Sir Reginald Huffington III", 9); bar.set_phase_title("Act I: The Huff")
##   bar.set_remaining(8); bar.hide_bar()
## Look: a burgundy ribbon name plate, a gilded parchment frame and a jam-red bar split into one
## segment per hit. A hit flashes the lost segment white, shakes the frame and drains a lag bar.
## In group "hud" so --hide-hud gives clean story frames.

var _ctl: _Bar


func _ready() -> void:
	layer = 20
	add_to_group("hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ctl = _Bar.new()
	_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ctl)


func show_bar(boss_name: String, total_hits: int) -> void:
	if _ctl == null:
		_ready()
	_ctl.boss_name = in_voice(boss_name)
	_ctl.total = maxi(1, total_hits)
	_ctl.remaining = float(total_hits)
	_ctl.lag = float(total_hits)
	_ctl.show_k = 0.0
	_ctl.showing = true
	visible = true
	UIFx.event("ui_boss_bar_show", {"name": boss_name, "total": total_hits})


## Storybook voice for numerals (critique UI r1: mixing faces for "III" looked patched):
## "Sir Reginald Huffington III" -> "... the Third", "II. The Puff" -> "Act Two: The Puff".
static func in_voice(text: String) -> String:
	const ORD := {"I": "the First", "II": "the Second", "III": "the Third", "IV": "the Fourth", "V": "the Fifth"}
	const ACT := {"I": "One", "II": "Two", "III": "Three", "IV": "Four", "V": "Five"}
	var t := text.strip_edges()
	for k in ["III", "II", "IV", "I", "V"]:
		for sep in [". ", ": "]:
			if t.begins_with(k + sep):
				return "Act %s: %s" % [ACT[k], t.substr(k.length() + sep.length())]
		if t.begins_with("Act " + k + ":") or t.begins_with("Act " + k + " "):
			return "Act %s%s" % [ACT[k], t.substr(4 + k.length())]
	var words := t.split(" ")
	if words.size() > 1 and ORD.has(words[-1]):
		words[-1] = ORD[words[-1]]
		return " ".join(words)
	return t


func set_phase_title(t: String) -> void:
	if _ctl:
		_ctl.phase = in_voice(t)
		_ctl.phase_t = 0.0


func set_remaining(n: int) -> void:
	if _ctl == null:
		return
	if n < _ctl.remaining:
		_ctl.hit_t = 1.0
		_ctl.hit_index = n
		UIFx.event("ui_boss_hit", {"remaining": n, "total": _ctl.total})
	_ctl.remaining = float(maxi(0, n))


## True while the bar is on screen (showing or still sliding out).
func is_showing() -> bool:
	return visible and _ctl != null and (_ctl.showing or _ctl.show_k > 0.01)


func hide_bar() -> void:
	if _ctl:
		_ctl.showing = false


class _Bar:
	extends Control
	var boss_name := ""
	var phase := ""
	var phase_t := 1.0
	var total := 3
	var remaining := 3.0
	var lag := 3.0
	var show_k := 0.0
	var showing := false
	var hit_t := 0.0
	var hit_index := -1
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		show_k = move_toward(show_k, 1.0 if showing else 0.0, delta * (2.5 if showing else 1.5))
		hit_t = move_toward(hit_t, 0.0, delta * 2.0)
		phase_t = minf(1.0, phase_t + delta * 4.0)
		if hit_t < 0.6:
			lag = move_toward(lag, remaining, delta * 1.8)
		if show_k <= 0.0 and not showing:
			get_parent().visible = false
		queue_redraw()

	func _draw() -> void:
		if show_k <= 0.001:
			return
		var e := UIFx.back_out(show_k) if showing else show_k
		var w := minf(760.0, size.x - 200.0)  # clear of the HUD plaques (x 536)
		var shake := Vector2(sin(_t * 80.0), cos(_t * 63.0)) * 10.0 * hit_t * hit_t
		var top := lerpf(-200.0, 40.0, e)
		var frame := Rect2((size.x - w) * 0.5, top + 84, w, 58)
		frame.position += shake
		# frame
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0.1, 0.04, 0.02, 0.4)
		sh.set_corner_radius_all(31)
		draw_style_box(sh, Rect2(frame.position + Vector2(0, 8), frame.size))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("3b2416")
		sb.border_color = UIStyle.INK
		sb.set_border_width_all(5)
		sb.set_corner_radius_all(31)
		sb.anti_aliasing = true
		draw_style_box(sb, frame)
		var inner := frame.grow(-12)
		var seg := inner.size.x / total
		# lag (cream) then fill (jam)
		var lag_w := inner.size.x * clampf(lag / total, 0.0, 1.0)
		var fill_w := inner.size.x * clampf(remaining / total, 0.0, 1.0)
		var fsb := StyleBoxFlat.new()
		fsb.set_corner_radius_all(19)
		fsb.anti_aliasing = true
		fsb.bg_color = Color("ffe8b0")
		if lag_w > 2.0:
			draw_style_box(fsb, Rect2(inner.position, Vector2(lag_w, inner.size.y)))
		if fill_w > 2.0:
			fsb.bg_color = Color("c8243a")
			draw_style_box(fsb, Rect2(inner.position, Vector2(fill_w, inner.size.y)))
			fsb.bg_color = Color(1, 0.6, 0.6, 0.35)
			draw_style_box(fsb, Rect2(inner.position + Vector2(6, 4), Vector2(maxf(0.0, fill_w - 12), inner.size.y * 0.3)))
		# the segment that was just lost flashes white
		if hit_t > 0.0 and hit_index >= 0:
			var hr := Rect2(inner.position + Vector2(seg * hit_index, 0), Vector2(seg, inner.size.y))
			draw_rect(hr.grow(4.0 * hit_t), Color(1, 1, 1, hit_t))
		# notches between hits
		for i in range(1, total):
			var x := inner.position.x + seg * i
			draw_line(Vector2(x, inner.position.y + 2), Vector2(x, inner.end.y - 2), Color(UIStyle.INK, 0.8), 3.0)
		var gilt := StyleBoxFlat.new()
		gilt.draw_center = false
		gilt.border_color = UIStyle.BRASS
		gilt.set_border_width_all(3)
		gilt.set_corner_radius_all(24)
		gilt.anti_aliasing = true
		draw_style_box(gilt, frame.grow(-5))
		# end caps: brass studs
		for x in [frame.position.x + 4, frame.end.x - 4]:
			var c := Vector2(x, frame.get_center().y)
			draw_circle(c, 20, UIStyle.INK, true, -1.0, true)
			draw_circle(c, 16, UIStyle.BRASS, true, -1.0, true)
			draw_circle(c + Vector2(-4, -4), 5, UIStyle.BRASS_LIGHT, true, -1.0, true)
		# name ribbon
		var f := UIStyle.display_font()
		var fs := 46
		var tw := f.get_string_size(boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# keep the ribbon and its tails clear of the HUD plaques (they end at x 536)
		var max_tw := size.x - 2.0 * (536.0 + 20.0 + 38.0) - 100.0
		while fs > 34 and tw > max_tw:
			fs -= 2
			tw = f.get_string_size(boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rr := Rect2(size.x * 0.5 - tw * 0.5 - 50, top + shake.y, tw + 100, 70)
		UIDraw.ribbon(self, rr, UIStyle.RIBBON, UIStyle.BRASS)
		# logo treatment (cream fill, ribbon-dark rim, ink drop) in the rounded display face
		UIStyle.draw_title(self, Vector2(size.x * 0.5 - tw * 0.5, rr.position.y + 35 + fs * 0.37), boss_name, fs, 1.0, f)
		if phase != "":
			# critique UI r1 (art director): the phase title floated over the world with no plate. It now rides on a
			# parchment tag that drops in from under the bar (0.25 s ease-out-back).
			var pf := UIStyle.display_font()
			var ps := 32
			var pw := pf.get_string_size(phase, HORIZONTAL_ALIGNMENT_LEFT, -1, ps).x
			var pa := UIFx.back_out(phase_t)
			var tag := Rect2(size.x * 0.5 - pw * 0.5 - 26, frame.end.y - 14 + pa * 26.0, pw + 52, 50)
			var tsh := StyleBoxFlat.new()
			tsh.bg_color = Color(0.1, 0.04, 0.02, 0.35 * phase_t)
			tsh.set_corner_radius_all(12)
			draw_style_box(tsh, Rect2(tag.position + Vector2(0, 5), tag.size))
			var tsb := StyleBoxFlat.new()
			tsb.bg_color = Color(UIStyle.PARCHMENT, phase_t)
			tsb.border_color = Color(UIStyle.INK, phase_t)
			tsb.set_border_width_all(3)
			tsb.set_corner_radius_all(12)
			tsb.anti_aliasing = true
			draw_style_box(tsb, tag)
			draw_line(tag.position + Vector2(12, 8), Vector2(tag.end.x - 12, tag.position.y + 8), Color(UIStyle.BRASS, 0.7 * phase_t), 2.0, true)
			draw_string(pf, Vector2(size.x * 0.5 - pw * 0.5, tag.position.y + 36), phase, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, Color(UIStyle.RIBBON, phase_t))

	## The swash display face turns Roman numerals ("III", "II:") into curly T shapes (critique UI r1),
	## so numeral words are drawn in the bold rounded UI face instead.
	func _is_numeral(word: String) -> bool:
		var w := word.trim_suffix(":").trim_suffix(",")
		if w.length() < 2 and w != "I" and w != "V" and w != "X":
			return false
		for ch in w:
			if not "IVXLC".contains(ch):
				return false
		return w.length() > 0

	func _seg_font(base: Font, word: String) -> Font:
		return UIStyle.ui_font(700) if _is_numeral(word) else base

	func _mixed_width(base: Font, text: String, fs: int) -> float:
		var words := text.split(" ")
		var space := base.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var w := 0.0
		for i in words.size():
			w += _seg_font(base, words[i]).get_string_size(words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if i < words.size() - 1:
				w += space
		return w

	func _draw_mixed(base: Font, pos: Vector2, text: String, fs: int, fill: Color, outline: Color) -> void:
		var words := text.split(" ")
		var space := base.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := pos.x
		for word in words:
			var wf := _seg_font(base, word)
			UIFx.draw_outlined(self, wf, Vector2(x, pos.y), word, fs, fill, outline, 8)
			x += wf.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + space

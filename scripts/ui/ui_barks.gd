class_name UIBarks
extends Control
## World speech bubbles in the UI style (critique UI r1: hub Label3D barks drew over the title logo and
## behind dialogs in a default font). A bark follows a 3D node on screen as a parchment pill with an
## ink border, Fredoka text and a small tail pointing at the speaker.
##
##   UI.bark(node, "Twelve truffles, piglet.", 3.0)          # 3 s, 2.2 m above the node's origin
##   UI.bark(node, text, 4.0, {"height": 3.4, "speaker": "Wolf"})
##   UI.clear_barks(node)                                    # or UI.clear_barks() for all
##
## Barks hide while a dialog, menu or the title is on screen, fade with distance (beyond about 18 m)
## and while the speaker is behind the camera. A new bark on the same node replaces the old one.

const FS := 28
const MAX_W := 560.0
const FAR := 18.0

var _barks: Array = []  # {node, text, lines, t, len, height, speaker}
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func bark(node: Node3D, text: String, seconds: float = 3.0, opts: Dictionary = {}) -> void:
	if node == null or text == "":
		return
	clear(node)
	_barks.append({
		"node": node, "text": text, "lines": _wrap(text), "t": 0.0, "len": maxf(seconds, 0.6),
		"height": float(opts.get("height", 2.2)), "speaker": String(opts.get("speaker", "")),
	})


func clear(node: Node3D = null) -> void:
	if node == null:
		_barks.clear()
	else:
		_barks = _barks.filter(func(b: Dictionary) -> bool: return b["node"] != node)


func count() -> int:
	return _barks.size()


func _wrap(text: String) -> PackedStringArray:
	var f := UIStyle.ui_font(600)
	var out := PackedStringArray()
	var line := ""
	for w in text.split(" "):
		var trial := w if line == "" else line + " " + w
		if line != "" and f.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x > MAX_W:
			out.append(line)
			line = w
		else:
			line = trial
	if line != "":
		out.append(line)
	return out


func _process(delta: float) -> void:
	_t += delta
	for b in _barks:
		if not get_tree().paused:
			b["t"] += delta
	_barks = _barks.filter(func(b: Dictionary) -> bool: return is_instance_valid(b["node"]) and b["t"] < b["len"])
	queue_redraw()


func _suppressed() -> bool:
	var ui := get_node_or_null("/root/UI")
	if ui == null:
		return false
	if not ui.get("_gameplay"):
		return true
	return ui.is_input_blocked()


func _draw() -> void:
	if _barks.is_empty() or _suppressed():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# with the canvas_items stretch mode the viewport, the camera projection and this Control all use
	# the 1920x1080 layout space
	var view := get_viewport().get_visible_rect().size
	var f := UIStyle.ui_font(600)
	var nf := UIStyle.ui_font(700)
	for b in _barks:
		var n: Node3D = b["node"]
		if not n.is_visible_in_tree():
			continue
		var wp := n.global_position + Vector3(0, b["height"], 0)
		if cam.is_position_behind(wp):
			continue
		var dist := cam.global_position.distance_to(wp)
		var far_a := clampf((FAR - dist) / 4.0, 0.0, 1.0)
		var t: float = b["t"]
		var inn := UIFx.back_out(clampf(t / 0.25, 0.0, 1.0))
		var out := clampf((float(b["len"]) - t) / 0.3, 0.0, 1.0)
		var a := far_a * minf(clampf(t / 0.12, 0.0, 1.0), out)
		if a <= 0.01:
			continue
		var sp := cam.unproject_position(wp)
		if sp.x < -40.0 or sp.y < -40.0 or sp.x > view.x + 40.0 or sp.y > view.y + 40.0:
			continue  # the speaker is off screen
		var lines: PackedStringArray = b["lines"]
		var w := 0.0
		for ln in lines:
			w = maxf(w, f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x)
		var speaker: String = b["speaker"]
		var line_h := FS * 1.22
		var tab := 12.0 if speaker != "" else 0.0  # room under the speaker's ribbon tab
		var h := lines.size() * line_h + 26.0 + tab
		var pad := 26.0
		var bw := w + pad * 2.0
		var r := Rect2(sp.x - bw * 0.5, sp.y - h - 22.0, bw, h)
		# keep the pill on screen
		r.position.x = clampf(r.position.x, 24.0, maxf(24.0, view.x - bw - 24.0))
		r.position.y = clampf(r.position.y, 24.0, maxf(24.0, view.y - h - 40.0))
		var sc := lerpf(0.6, 1.0, inn)
		var piv := Vector2(clampf(sp.x, r.position.x + 30.0, r.end.x - 30.0), r.end.y)
		draw_set_transform(piv * (1.0 - sc), 0.0, Vector2(sc, sc))
		# critique UI r1 (art director): a flat cream pill with a 16 px tail was off-kit next to the parchment
		# dialog card. Now: a 3 px ink offset shadow, parchment texture, a gilt inner rule and a 28 px tail.
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0.12, 0.05, 0.02, 0.22 * a)
		sh.set_corner_radius_all(22)
		sh.anti_aliasing = true
		draw_style_box(sh, Rect2(r.position + Vector2(0, 8), r.size))
		var hard := StyleBoxFlat.new()
		hard.bg_color = Color(UIStyle.INK, 0.85 * a)
		hard.set_corner_radius_all(22)
		hard.anti_aliasing = true
		draw_style_box(hard, Rect2(r.position + Vector2(3, 3), r.size))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UIStyle.PARCHMENT, 0.97 * a)
		sb.border_color = Color(UIStyle.INK, a)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(22)
		sb.anti_aliasing = true
		# tail toward the speaker
		var tx := clampf(sp.x, r.position.x + 30.0, r.end.x - 30.0)
		var tail := PackedVector2Array([Vector2(tx - 18, r.end.y - 2), Vector2(tx + 18, r.end.y - 2), Vector2(tx + 4, r.end.y + 28)])
		draw_colored_polygon(tail, Color(UIStyle.INK, a))
		draw_style_box(sb, r)
		var ptex := UIStyle.parchment_texture()
		if ptex:
			draw_texture_rect(ptex, r.grow(-8.0), true, Color(1, 1, 1, 0.35 * a))
		var gilt := StyleBoxFlat.new()
		gilt.draw_center = false
		gilt.border_color = Color(UIStyle.BRASS, 0.6 * a)
		gilt.set_border_width_all(2)
		gilt.set_corner_radius_all(16)
		gilt.anti_aliasing = true
		draw_style_box(gilt, r.grow(-6.0))
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 13, r.end.y - 4), Vector2(tx + 13, r.end.y - 4), Vector2(tx + 4, r.end.y + 21)]), Color(UIStyle.PARCHMENT, 0.97 * a))
		var y := r.position.y + 13.0 + tab + FS * 0.95
		for ln in lines:
			var lw := f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
			draw_string(f, Vector2(r.get_center().x - lw * 0.5, y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(UIStyle.INK, a))
			y += line_h
		if speaker != "":
			var sw := nf.get_string_size(speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			var pr := Rect2(r.position.x + 18, r.position.y - 20, sw + 34, 34)
			UIDraw.ribbon(self, pr, Color(UIStyle.RIBBON, a), Color(UIStyle.BRASS, a))
			draw_string(nf, Vector2(pr.position.x + 17, pr.position.y + 25), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UIStyle.CREAM, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

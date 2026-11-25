class_name UIDraw
extends RefCounted
## Procedural storybook icons drawn with CanvasItem calls: golden truffle, acorn, torn page,
## Victoria-sponge cake slices, ribbon banners and sparkles.


static func circle_pts(c: Vector2, r: Vector2, n: int = 32, a0: float = 0.0, a1: float = TAU) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts


## Closed ellipse outline without the duplicated end point (safe for draw_colored_polygon).
static func ellipse(c: Vector2, r: Vector2, n: int = 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts


static func truffle(ci: CanvasItem, c: Vector2, r: float, collected: bool = true, t: float = 0.0) -> void:
	if not collected:
		# empty outline: a dotted ring
		for i in 14:
			var a := TAU * i / 14.0
			ci.draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.82, r * 0.07, Color(UIStyle.INK_SOFT, 0.7), true, -1.0, true)
		return
	# lumpy golden truffle: overlapping bumps
	var shadow := Color(0.35, 0.2, 0.05, 0.35)
	ci.draw_circle(c + Vector2(r * 0.08, r * 0.14), r * 0.95, shadow, true, -1.0, true)
	var base := Color("c98a1b")
	var mid := Color("f2b632")
	var hi := Color("fff0a8")
	ci.draw_circle(c, r * 0.86, base, true, -1.0, true)
	var bumps := [Vector2(-0.42, -0.3), Vector2(0.38, -0.36), Vector2(0.48, 0.28), Vector2(-0.4, 0.38), Vector2(0.0, 0.5), Vector2(0.02, -0.52)]
	for b in bumps:
		ci.draw_circle(c + b * r, r * 0.42, base, true, -1.0, true)
	for b in bumps:
		ci.draw_circle(c + b * r * 0.9 + Vector2(-0.05, -0.06) * r, r * 0.33, mid, true, -1.0, true)
	ci.draw_circle(c + Vector2(-0.08, -0.06) * r, r * 0.55, mid, true, -1.0, true)
	# texture dimples
	for i in 7:
		var a := i * 2.4
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.5, r * 0.06, Color(base, 0.9), true, -1.0, true)
	# highlight
	ci.draw_circle(c + Vector2(-0.32, -0.36) * r, r * 0.17, hi, true, -1.0, true)
	ci.draw_circle(c + Vector2(-0.12, -0.5) * r, r * 0.08, hi, true, -1.0, true)
	# sparkle
	var s := 0.5 + 0.5 * sin(t * 3.0)
	sparkle(ci, c + Vector2(0.62, -0.62) * r, r * (0.22 + 0.12 * s), Color(1, 1, 0.85, 0.9))


static func sparkle(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r < 0.75 or col.a <= 0.005:
		return
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0 - PI * 0.5
		var rr := r if i % 2 == 0 else r * 0.28
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, col)


static func acorn(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c + Vector2(r * 0.08, r * 0.16), r * 0.8, Color(0.3, 0.18, 0.05, 0.3), true, -1.0, true)
	# nut
	var nut := circle_pts(c + Vector2(0, r * 0.18), Vector2(r * 0.62, r * 0.72), 28)
	ci.draw_colored_polygon(nut, Color("c7843a"))
	ci.draw_circle(c + Vector2(-r * 0.22, r * 0.2), r * 0.16, Color("e6a65a"), true, -1.0, true)
	ci.draw_colored_polygon(circle_pts(c + Vector2(0, r * 0.86), Vector2(r * 0.1, r * 0.1), 10), Color("7a4a1c"))
	# cap
	var cap := circle_pts(c + Vector2(0, -r * 0.22), Vector2(r * 0.74, r * 0.42), 28, PI, TAU)
	cap.append(c + Vector2(r * 0.74, -r * 0.12))
	cap.append(c + Vector2(-r * 0.74, -r * 0.12))
	ci.draw_colored_polygon(cap, Color("6b4423"))
	for i in 5:
		var x := lerpf(-0.5, 0.5, i / 4.0) * r
		ci.draw_line(c + Vector2(x - r * 0.1, -r * 0.5), c + Vector2(x + r * 0.1, -r * 0.16), Color("4a2c12"), max(1.5, r * 0.07))
	ci.draw_rect(Rect2(c.x - r * 0.75, c.y - r * 0.2, r * 1.5, r * 0.12), Color("553416"))
	# stem
	ci.draw_line(c + Vector2(0, -r * 0.62), c + Vector2(r * 0.18, -r * 0.95), Color("4a2c12"), max(2.0, r * 0.12))


static func page(ci: CanvasItem, c: Vector2, r: float, collected: bool = true) -> void:
	var w := r * 1.3
	var h := r * 1.7
	var pts := PackedVector2Array([
		c + Vector2(-w * 0.5, -h * 0.5), c + Vector2(w * 0.5, -h * 0.5), c + Vector2(w * 0.5, h * 0.2),
		c + Vector2(w * 0.32, h * 0.32), c + Vector2(w * 0.4, h * 0.42), c + Vector2(w * 0.12, h * 0.5),
		c + Vector2(-w * 0.1, h * 0.38), c + Vector2(-w * 0.3, h * 0.5), c + Vector2(-w * 0.5, h * 0.4)])
	var fill := UIStyle.PARCHMENT if collected else Color(UIStyle.PARCHMENT, 0.25)
	ci.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	ci.draw_polyline(pts, UIStyle.INK if collected else Color(UIStyle.INK_SOFT, 0.6), max(1.5, r * 0.08), true)
	if collected:
		for i in 4:
			var y := c.y - h * 0.3 + i * h * 0.16
			ci.draw_line(Vector2(c.x - w * 0.32, y), Vector2(c.x + w * (0.32 if i < 3 else 0.05), y), Color(UIStyle.INK_SOFT, 0.7), max(1.0, r * 0.05))


## Victoria sponge seen from above at a slight tilt: `filled` of 6 slices present.
## `pop` (0..1) animates the most recently changed slice, `wobble` shakes the cake.
static func cake(ci: CanvasItem, c: Vector2, r: float, filled: int, total: int = 6, pop_index: int = -1, pop: float = 0.0) -> void:
	var tilt := 0.62
	var depth := r * 0.42
	# plate
	var pc := c + Vector2(0, depth * 1.05)
	ci.draw_colored_polygon(circle_pts(pc + Vector2(0, 6), Vector2(r * 1.14, r * 1.14 * tilt), 40), Color(0.2, 0.12, 0.06, 0.3))
	ci.draw_colored_polygon(circle_pts(pc, Vector2(r * 1.12, r * 1.12 * tilt), 40), Color("f3f0ea"))
	ci.draw_polyline(circle_pts(pc, Vector2(r * 1.12, r * 1.12 * tilt), 40), Color("9fb0c4"), 2.0, true)
	ci.draw_colored_polygon(circle_pts(pc, Vector2(r * 0.98, r * 0.98 * tilt), 40), Color("e2e8ef"))
	var step := TAU / total
	var start := -PI * 0.5
	# draw back slices first (painter's order by sin of mid angle)
	var order: Array = []
	for i in total:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return sin(start + (a + 0.5) * step) < sin(start + (b + 0.5) * step))
	for oi in order:
		var i: int = oi
		var present: bool = i < filled
		var a0 := start + i * step
		var a1 := a0 + step
		var mid := (a0 + a1) * 0.5
		var off := Vector2.ZERO
		var scale := 1.0
		if i == pop_index and pop > 0.0:
			off = Vector2(cos(mid), sin(mid) * tilt) * r * 0.5 * pop + Vector2(0, -r * 0.6 * sin(pop * PI))
			scale = 1.0 + 0.15 * sin(pop * PI)
		if not present and not (i == pop_index and pop > 0.0):
			# crumbs where the slice was
			for k in 3:
				var ca := lerpf(a0, a1, (k + 0.5) / 3.0)
				ci.draw_circle(c + Vector2(0, depth) + Vector2(cos(ca), sin(ca) * tilt) * r * (0.4 + 0.15 * k), r * 0.05, Color("d9b277"), true, -1.0, true)
			continue
		_slice(ci, c + off, r * scale, a0, a1, tilt, depth * scale)


static func _slice(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, tilt: float, depth: float) -> void:
	var sponge_top := Color("f3c873")
	var sponge_side := Color("dc9c48")
	var jam := Color("c8243a")
	var cream := Color("fffaf0")
	var n := 10
	# Side wall: only the front-facing part of the outer arc (sin > 0 means toward the viewer).
	var s0 := maxf(a0, 0.0)
	var s1 := minf(a1, PI)
	if s1 - s0 > 0.01:
		var band := func(y0: float, y1: float, col: Color) -> void:
			var pts := PackedVector2Array()
			for i in n + 1:
				var a := lerpf(s0, s1, float(i) / n)
				pts.append(c + Vector2(cos(a) * r, sin(a) * r * tilt + depth * y0))
			for i in range(n, -1, -1):
				var a := lerpf(s0, s1, float(i) / n)
				pts.append(c + Vector2(cos(a) * r, sin(a) * r * tilt + depth * y1))
			ci.draw_colored_polygon(pts, col)
		band.call(0.0, 1.0, sponge_side)
		band.call(0.4, 0.55, cream)
		band.call(0.55, 0.68, jam)
		band.call(0.9, 1.0, sponge_side.darkened(0.15))
	# Cut faces (visible when a neighbouring slice is missing): draw the two radial walls.
	for edge in [a0, a1]:
		if sin(edge) > -0.2:
			var p0 := c
			var p1 := c + Vector2(cos(edge) * r, sin(edge) * r * tilt)
			var wall := PackedVector2Array([p0, p1, p1 + Vector2(0, depth), p0 + Vector2(0, depth)])
			if absf((p1 - p0).x) > 1.0:
				ci.draw_colored_polygon(wall, sponge_side.lightened(0.05))
				ci.draw_colored_polygon(PackedVector2Array([p0 + Vector2(0, depth * 0.4), p1 + Vector2(0, depth * 0.4), p1 + Vector2(0, depth * 0.68), p0 + Vector2(0, depth * 0.68)]), jam)
	# top wedge
	var top := PackedVector2Array([c])
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		top.append(c + Vector2(cos(a) * r, sin(a) * r * tilt))
	ci.draw_colored_polygon(top, sponge_top)
	# icing sugar dusting
	for k in 6:
		var a := lerpf(a0, a1, fmod(k * 0.618 + 0.1, 1.0))
		var rr := r * (0.3 + 0.11 * k)
		ci.draw_circle(c + Vector2(cos(a) * rr, sin(a) * rr * tilt), r * 0.04, Color(1, 1, 1, 0.9), true, -1.0, true)
	# a cream swirl and a strawberry on each slice
	var mid := (a0 + a1) * 0.5
	var sp := c + Vector2(cos(mid), sin(mid) * tilt) * r * 0.72
	ci.draw_circle(sp + Vector2(0, r * 0.04), r * 0.13, cream, true, -1.0, true)
	ci.draw_circle(sp, r * 0.1, Color("e0334a"), true, -1.0, true)
	ci.draw_circle(sp + Vector2(-r * 0.03, -r * 0.03), r * 0.03, Color(1, 0.85, 0.85), true, -1.0, true)
	# slice outline
	top.append(c)
	ci.draw_polyline(top, Color(UIStyle.INK, 0.45), maxf(1.2, r * 0.022), true)


## Ribbon banner with swallow-tail ends, centred on `rect`.
static func ribbon(ci: CanvasItem, rect: Rect2, col: Color = UIStyle.RIBBON, edge: Color = UIStyle.BRASS) -> void:
	var tail := rect.size.y * 0.55
	var notch := rect.size.y * 0.3
	var y0 := rect.position.y
	var y1 := rect.end.y
	var x0 := rect.position.x
	var x1 := rect.end.x
	var dark := col.darkened(0.35)
	# tails (behind)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x0 + tail * 0.4, y0 + 10), Vector2(x0 - tail, y0 + 10), Vector2(x0 - tail + notch, (y0 + y1) * 0.5 + 10), Vector2(x0 - tail, y1 + 10), Vector2(x0 + tail * 0.4, y1 + 10)]), dark)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x1 - tail * 0.4, y0 + 10), Vector2(x1 + tail, y0 + 10), Vector2(x1 + tail - notch, (y0 + y1) * 0.5 + 10), Vector2(x1 + tail, y1 + 10), Vector2(x1 - tail * 0.4, y1 + 10)]), dark)
	# main band
	ci.draw_rect(rect, col)
	ci.draw_line(Vector2(x0, y0 + 5), Vector2(x1, y0 + 5), edge, 2.5)
	ci.draw_line(Vector2(x0, y1 - 5), Vector2(x1, y1 - 5), edge, 2.5)
	ci.draw_rect(Rect2(x0, y0, rect.size.x, rect.size.y * 0.35), Color(1, 1, 1, 0.08))

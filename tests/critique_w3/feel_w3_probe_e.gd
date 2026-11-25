extends "res://tests/critique_w3/feel_w3_probe_c.gd"
## Critique W3 r1 pass C, batch E: Gumdrop Hop trace (position, state and nearest dome every 10 frames) with the stick
## held at the next dome from the first bounce; grumpy domes slammed on the descent.


func _phase_list() -> Array:
	return ["gum3"]


func _ph_gum3() -> Dictionary:
	var tops: Array = []
	for i in range(1, 8):
		tops.append(level.call("_gum", i))
	tops.append(Vector3(20, 24.4, 38))
	await _tp(Vector3(9.4, 2.1, 38.0), -90.0, 20)
	await _goto(Vector3(11.0, 2.0, 38.0), 0.3, 3.0)
	var cur := 0
	var trace: Array = []
	var shots: Array = []
	stick = _toward(tops[0])
	_press("jump", 16)
	var f := 0
	var last_vy := 0.0
	var bounces := 0
	while f < 60 * 20:
		await _frames(1)
		f += 1
		var p := player.global_position
		var vy := float(player.get("vy"))
		# a bounce = vertical speed flips from falling to strongly rising
		if last_vy < -1.0 and vy > 6.0:
			bounces += 1
			var best := -1
			var bd := 9.0
			for k in tops.size():
				var tk: Vector3 = tops[k]
				var dd := Vector2(tk.x - p.x, tk.z - p.z).length()
				if dd < bd and absf(p.y - tk.y) < 1.5:
					bd = dd
					best = k
			trace.append({"bounce": bounces, "dome": best + 1, "at": _v(p), "f": f, "vy": snappedf(vy, 0.1)})
			if best >= 0:
				cur = mini(best + 1, tops.size() - 1)
			if bounces <= 3:
				shots.append(await _cam("gum_bounce_%d" % bounces, true))
		last_vy = vy
		var tgt: Vector3 = tops[cur]
		stick = _toward(tgt)
		var grumpy := cur >= 4 and cur <= 6
		if grumpy and vy < 0.0 and _hdist(tgt) < 0.8 and p.y > tgt.y + 0.6 and _st() != "ham_slam":
			_press("crouch", 4)
		if f % 15 == 0:
			trace.append({"f": f, "p": _v(p), "s": _st(), "heading": cur + 1})
		if cur == tops.size() - 1 and _grounded() and absf(p.y - 24.4) < 0.4:
			trace.append({"saucer": true, "f": f})
			break
		if p.y < 2.6 and f > 40:
			trace.append({"fell": true, "heading_to": cur + 1, "at": _v(p), "f": f})
			break
	stick = Vector2.ZERO
	var r := {"reached_dome": cur, "bounces": bounces, "trace": trace, "shots": shots}
	log_line("gum3 " + JSON.stringify(r).left(4000))
	return r

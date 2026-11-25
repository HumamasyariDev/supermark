class_name WorldExits
extends RefCounted
## Owner fix 2026-10-19 (world exits): "the exit from the location is not closed; you can just jump into the abyss
## through it". Every world's way back (the opening behind the arrival spawn) now holds a closed storybook gate
## (ExitGate) with collision, invisible walls around and above it, and an interact prompt that asks before returning
## to the Grand Library. Called once from WorldRoot._ready (after the level builders). The Hub and the boss rooftop
## have no exit opening (the rooftop's parapet gaps are fight hazards; leaving is the pause menu), so they get none.
## Dev: --exitbot[=<abs results json>] adds the exit-gate test bot (scripts/worlds/exit_gate_bot.gd).

## Per world: gate origin (base centre, world), yaw (degrees; the gate's local +Z faces the world side), style,
## opening width, leaf height, and invisible wall boxes in the gate's local frame ([size, centre]).
static func spec(world_id: String) -> Dictionary:
	match world_id:
		"W1":
			# Page Gate (w1_landmarks.page_gate): book stacks at x +/-3.6 (2 m wide, z 56.5..58.5), arch underside 6.5 m
			# above the base (0, 0.4, 57.5). The gate leaves close the BACK of the arch (z 58.2) so the ST4 sniff stash
			# under the arch (0, 0.4, 57.5, Ham Slam within 1 m) stays reachable. The terrain grid ends at z 60 and the
			# lane runs flat through the arch to the edge. The secret book steps (east stack, up to z 59.9) and the
			# A19 ring on the arch top stay inside: the wall stands just past the grid edge (z 60.1..60.7), x +/-30,
			# up to 40 m, so neither the opening, the arch top nor the banks beside it lead off the page.
			return {
				"pos": Vector3(0, 0.4, 58.2), "yaw": 180.0, "style": "book", "open_w": 5.2, "leaf_h": 6.4,
				"bounds": [
					[Vector3(60.0, 42.0, 0.6), Vector3(0, 19.0, -2.2)],
				],
			}
		"W2":
			# Garden gate posts at x +/-2.2, z 34.6 on the island's south rim (island centre (0, 14), r 22, fence r 20.8
			# with a gap |x| < 3.5). The fence is visual only, so the walls follow the rim as an arc of boxes either
			# side of the gate (built in place below) and one above it. The gate stays low: the opening camera sits
			# just behind it, below eye level (CH0_Gate: pitch +16, 9 m), so the leaves stay under 0.9 m (D034 B4).
			return {
				"pos": Vector3(0, 0.0, 34.6), "yaw": 180.0, "style": "garden", "open_w": 4.3, "leaf_h": 0.85,
				"bounds": [
					[Vector3(7.2, 16.0, 0.5), Vector3(0, 7.0, -0.45)],
				],
				"arc": {"center": Vector2(0, 14), "r": 21.35, "deg_from": 52.0, "deg_to": 128.0, "h": 16.0, "y": -2.0},
			}
		"W3":
			# Arrival lawn: spawn (0, 2.05, 48) facing the candy-cane Storybook Gate (north, into the world). Behind it
			# the page ends at z 55 (cut-cake skirt) with a visual cane fence at z 54.2 for |x| < 16. The exit gate
			# stands in that fence line (w3_level skips the two fence pieces it replaces) with a wall along the fenced lawn
			# (|x| < 17). Low, because the arrival camera sits just behind it.
			return {
				"pos": Vector3(0, 2.0, 54.1), "yaw": 180.0, "style": "ginger", "open_w": 4.6, "leaf_h": 1.5,
				"bounds": [
					[Vector3(34.0, 30.0, 0.6), Vector3(0, 12.0, -0.6)],
				],
			}
	return {}


static func install(root: Node3D, world_id: String) -> Node3D:
	var dev0 := root.get_node_or_null("/root/Dev")
	if dev0 and dev0.has_method("has_arg") and dev0.has_arg("shots") and not dev0.has_arg("exitbot"):
		var sb := Node.new()
		sb.name = "ShotBot"
		sb.set_script(load("res://scripts/worlds/shot_bot.gd"))
		root.add_child(sb)
	var s := spec(world_id)
	# Only in the real world scene (UITestWorld and other test roots reuse WorldRoot with world_id "W1").
	if s.is_empty() or root.scene_file_path != WorldRegistry.scene_path(world_id):
		return null
	var gate := ExitGate.new()
	gate.name = "ExitGate_" + world_id
	gate.style = String(s["style"])
	gate.open_w = float(s["open_w"])
	gate.leaf_h = float(s["leaf_h"])
	gate.bounds = s.get("bounds", [])
	gate.position = s["pos"]
	gate.rotation_degrees.y = float(s["yaw"])
	root.add_child(gate)
	if s.has("arc"):
		_arc_walls(root, s["arc"], gate.open_w * 0.5 + 0.3)
	var dev := root.get_node_or_null("/root/Dev")
	if dev and dev.has_method("has_arg") and dev.has_arg("exitbot"):
		var bot := Node.new()
		bot.name = "ExitGateBot"
		bot.set_script(load("res://scripts/worlds/exit_gate_bot.gd"))
		bot.set("world_id", world_id)
		# On the root, so it survives the page turn to the Hub it is testing.
		root.get_tree().root.add_child.call_deferred(bot)
	return gate


## Rim walls on an arc (W2's round island): boxes on the circle, skipping the stretch the gate itself spans.
static func _arc_walls(root: Node3D, a: Dictionary, gate_half: float) -> void:
	var b := StaticBody3D.new()
	b.name = "ExitRimWalls"
	b.collision_layer = (1 << 2) | (1 << 8)
	b.collision_mask = 0
	b.add_to_group("camera_ignore")
	root.add_child(b)
	var c: Vector2 = a["center"]
	var r := float(a["r"])
	var h := float(a["h"])
	var y0 := float(a["y"])
	var d0 := float(a["deg_from"])
	var d1 := float(a["deg_to"])
	var step := 4.0
	var d := d0
	while d < d1 - 0.01:
		var e := minf(d + step, d1)
		var pa := c + Vector2(cos(deg_to_rad(d)), sin(deg_to_rad(d))) * r
		var pb := c + Vector2(cos(deg_to_rad(e)), sin(deg_to_rad(e))) * r
		var mid := (pa + pb) * 0.5
		d = e
		if absf(mid.x) < gate_half and mid.y > c.y:
			continue
		var seg := pb - pa
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(seg.length() + 0.4, h, 0.5)
		cs.shape = bs
		cs.position = Vector3(mid.x, y0 + h * 0.5, mid.y)
		cs.rotation.y = -atan2(seg.y, seg.x)
		b.add_child(cs)

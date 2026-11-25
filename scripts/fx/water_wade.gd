class_name WaterWade
extends RefCounted
## Shallow walkable water (look polish 2026-10-19, owner: "add a sound for walking in water and water splashes").
## probe(pos) tells Juice whether a footstep or landing at `pos` happens in wadeable water, and where the water surface is,
## so it can swap the footstep sound for a splash step and put ripples and droplets on the surface (no player-code edits).
## Sources, checked in order:
##  - nodes in group "wade_water" (a MeshInstance3D with a CylinderMesh / PlaneMesh / BoxMesh, or any Node3D with meta
##    "wade_radius"): the water surface is the node's global y (meta "water_y" overrides);
##  - W1: the Hollow Stream, wherever the baked terrain lies below the stream's water level (w1_level.json).
## Other worlds have no walkable water: W2 is cloud decks, W3's hot chocolate and syrup are hazards that already splash
## through MakPlayer.splash(), and the hub's fountain and lily pond are vista props behind the windows.

const W1_LEVEL := "res://assets/environment/w1/w1_level.json"

static var _w1_water_y := INF


## {} when `pos` (feet) is not in wadeable water, else {"depth": m below the surface, "surface_y": water level}.
static func probe(tree: SceneTree, pos: Vector3) -> Dictionary:
	if tree == null or pos == Vector3.INF:
		return {}
	for n in tree.get_nodes_in_group("wade_water"):
		var r := _node_probe(n as Node3D, pos)
		if not r.is_empty():
			return r
	var scene := tree.current_scene
	if scene == null or scene.get("world_id") == null or String(scene.get("world_id")) != "W1":
		return {}
	if _w1_water_y == INF:
		var lv: Dictionary = W1Terrain.level()
		_w1_water_y = float(lv.get("terrain", {}).get("stream", {}).get("water_y", -0.35))
	var wy := _w1_water_y
	var ground := W1Terrain.height(pos.x, pos.z)
	if ground < wy - 0.04 and pos.y < wy + 0.1 and pos.y > ground - 0.6:
		return {"depth": wy - pos.y, "surface_y": wy}
	return {}


static func _node_probe(n: Node3D, pos: Vector3) -> Dictionary:
	if n == null or not n.is_inside_tree() or not n.is_visible_in_tree():
		return {}
	var wy := float(n.get_meta("water_y", n.global_position.y))
	if pos.y > wy + 0.1 or pos.y < wy - 1.2:
		return {}
	var local := n.global_transform.affine_inverse() * pos
	var inside := false
	if n.has_meta("wade_radius"):
		inside = Vector2(local.x, local.z).length() <= float(n.get_meta("wade_radius"))
	elif n is MeshInstance3D:
		var m := (n as MeshInstance3D).mesh
		if m is CylinderMesh:
			inside = Vector2(local.x, local.z).length() <= maxf((m as CylinderMesh).top_radius, (m as CylinderMesh).bottom_radius)
		elif m is PlaneMesh:
			var ps := (m as PlaneMesh).size
			inside = absf(local.x) <= ps.x * 0.5 and absf(local.z) <= ps.y * 0.5
		elif m is BoxMesh:
			var bs := (m as BoxMesh).size
			inside = absf(local.x) <= bs.x * 0.5 and absf(local.z) <= bs.z * 0.5
	return {"depth": wy - pos.y, "surface_y": wy} if inside else {}

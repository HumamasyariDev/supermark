extends Node
## Critique OBJECTS round 1 after M3b, VISUAL lens. Enters a real world through Router with the real Player and its
## gameplay camera, stands Mak in front of every object and character, lets the gameplay camera settle behind him and
## takes native viewport shots (gameplay distance, close, and a second close shot 0.75 s later to compare idle motion).
## Read-only towards the objects track. Args: --world=W1|W2|W3|HUB --shot_dir=<abs dir> --dist=4.5 --max_per=3

var world := "W1"
var shot_dir := ""
var max_per := 3
var listing: Array = []


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.split("=", true, 1)[1]
	return d


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = _arg("world", "W1")
	shot_dir = _arg("shot_dir", "")
	max_per = int(_arg("max_per", "3"))
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func until_unpaused(max_frames: int = 900) -> void:
	var i := 0
	while get_tree().paused and i < max_frames:
		await get_tree().process_frame
		i += 1


func player() -> CharacterBody3D:
	return get_tree().get_first_node_in_group("player") as CharacterBody3D


func scene_root() -> Node:
	return get_tree().current_scene


func enter(wid: String) -> bool:
	await until_unpaused()
	if wid == "HUB":
		Router.go_to_hub()
	else:
		Router.enter_world(wid, "")
	var i := 0
	while i < 1800:
		await get_tree().process_frame
		i += 1
		var sr := scene_root()
		if sr != null and "world_id" in sr and String(sr.get("world_id")) == wid and player() != null and not get_tree().paused:
			break
	await frames(int(_arg("intro_frames", "480")))
	await until_unpaused()
	return scene_root() != null


func of_class(cls: Variant) -> Array:
	var out: Array = []
	var stack: Array = [scene_root()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		for c in n.get_children():
			stack.append(c)
		if is_instance_of(n, cls):
			out.append(n)
	return out


func chars_loose() -> Array:
	var out: Array = []
	var pl := player()
	var stack: Array = [scene_root()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node3D and n.scene_file_path.begins_with("res://assets/characters/"):
			if pl != null and pl.is_ancestor_of(n):
				continue
			var p := n.get_parent()
			var owned := false
			while p != null:
				if p is NPCTalker or p is Cage:
					owned = true
					break
				p = p.get_parent()
			if not owned and (n as Node3D).is_visible_in_tree():
				out.append(n)
	return out


func ray_down(from: Vector3, length: float) -> Dictionary:
	var pl := player()
	var space := pl.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * length, 1)
	q.exclude = [pl.get_rid()]
	return space.intersect_ray(q)


func blocked(at: Vector3) -> bool:
	var pl := player()
	var space := pl.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := CapsuleShape3D.new()
	s.radius = 0.35
	s.height = 1.25
	q.shape = s
	q.transform = Transform3D(Basis(), at + Vector3.UP * 0.7)
	q.collision_mask = 1
	q.exclude = [pl.get_rid()]
	return not space.intersect_shape(q, 1).is_empty()


func stand_facing(target: Vector3, dist: float, prefer: Vector3) -> bool:
	var dirs: Array = []
	var p := Vector3(prefer.x, 0, prefer.z)
	if p.length() > 0.01:
		p = p.normalized()
		for k in [0, 1, -1, 2, -2, 3, -3, 4]:
			dirs.append(p.rotated(Vector3.UP, deg_to_rad(40.0 * k)))
	else:
		for k in 8:
			dirs.append(Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(45.0 * k)))
	for d in dirs:
		var at: Vector3 = target + d * dist
		var hit := ray_down(at + Vector3.UP * 4.0, 9.0)
		if hit.is_empty():
			continue
		var floor_p: Vector3 = hit["position"]
		if absf(floor_p.y - target.y) > 3.5 or blocked(floor_p + Vector3.UP * 0.05):
			continue
		var to := target - floor_p
		var yaw := atan2(-to.x, -to.z)
		var pl := player()
		pl.call("respawn", Transform3D(Basis(Vector3.UP, yaw), floor_p + Vector3.UP * 0.05))
		pl.velocity = Vector3.ZERO
		for c in get_tree().root.find_children("*", "Camera3D", true, false):
			if c.has_method("snap_behind"):
				c.call("snap_behind")
		return true
	return false


func snap(caption: String) -> String:
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var utc := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var path := shot_dir + "/%sZ__%s.png" % [utc, caption]
	img.save_png(path)
	print("[CritVis] SHOT ", path)
	return path


func _clean(s: String) -> String:
	var o := ""
	for ch in s:
		o += ch if (ch.is_valid_identifier() or ch.is_valid_int()) else "_"
	return o.substr(0, 40)


func _shoot(n: Node3D, label: String, dist: float, aim_y: float) -> void:
	var t := n.global_position
	var prefer := n.global_basis.z
	if not await stand_facing(t, dist, prefer):
		print("[CritVis] NOSPOT ", label, " ", n.get_path())
		listing.append({"label": label, "path": str(n.get_path()), "spot": false})
		return
	await frames(70)
	var a := await snap("%s_%s_far" % [world, label])
	await stand_facing(t, maxf(2.2, dist * 0.5), prefer)
	await frames(70)
	var b := await snap("%s_%s_near_t0" % [world, label])
	await frames(45)
	var c := await snap("%s_%s_near_t1" % [world, label])
	listing.append({"label": label, "path": str(n.get_path()), "spot": true, "pos": str(t), "shots": [a, b, c]})


func _run() -> void:
	await frames(20)
	Game.new_game()
	if not await enter(world):
		print("[CritVis] could not enter ", world)
		get_tree().quit(2)
		return
	var clip := _arg("clip", "")
	if clip != "":
		await _clip(clip)
		get_tree().quit(0)
		return
	var groups := [
		["npc", NPCTalker, 12, 3.6], ["sign", SignPost, 1, 3.6], ["truffle", Truffle, max_per, 3.6],
		["checkpoint", CheckpointBookmark, 2, 4.0], ["cage", Cage, 2, 5.0], ["bellows", BellowsMachine, 2, 5.0],
		["page", LostPage, 2, 3.4], ["crate", BreakableCrate, 2, 3.6], ["switch", SlamSwitch, 1, 3.6],
		["dig", BuriedTreasure, 1, 3.6], ["bounce", BouncePad, 1, 4.0], ["portal", StorybookPortal, 3, 6.0],
		["wolfdoor", WolfDoor, 1, 7.0], ["acorn", Acorn, 1, 3.0],
	]
	for g in groups:
		var nodes := of_class(g[1])
		var k := 0
		for n in nodes:
			if k >= int(g[2]):
				break
			if not (n as Node3D).is_visible_in_tree():
				continue
			await _shoot(n as Node3D, "%s%d_%s" % [g[0], k, _clean(str((n as Node).name))], float(g[3]), 1.0)
			k += 1
	var loose := chars_loose()
	var seen := {}
	for n in loose:
		var f: String = (n as Node).scene_file_path.get_file().get_basename()
		if seen.has(f):
			continue
		seen[f] = true
		await _shoot(n as Node3D, "char_" + _clean(f), 5.0, 1.0)
	var f := FileAccess.open(shot_dir + "/listing_%s.json" % world, FileAccess.WRITE)
	f.store_string(JSON.stringify(listing, "  "))
	f.close()
	print("[CritVis] DONE ", listing.size())
	get_tree().quit(0)


## Movie clip: Mak starts --clip_dist (6 m) in front of the named node, walks up to it (greeting), stops, talks
## (interact), waits, closes the dialog and idles. Records idle life, greeting, talk gestures from the gameplay camera.
func _clip(node_name: String) -> void:
	var n := scene_root().find_child(node_name, true, false) as Node3D
	if n == null:
		print("[CritVis] clip target not found ", node_name)
		return
	var dist := float(_arg("clip_dist", "6.0"))
	if not await stand_facing(n.global_position, dist, n.global_basis.z):
		print("[CritVis] clip no spot ", node_name)
		return
	await frames(90)
	Input.action_press("move_forward")
	var pl := player()
	var i := 0
	while i < 240 and pl.global_position.distance_to(n.global_position) > 2.2:
		await get_tree().physics_frame
		i += 1
	Input.action_release("move_forward")
	await frames(150)
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(240)
	for k in 4:
		Input.action_press("interact")
		await frames(3)
		Input.action_release("interact")
		await frames(60)
	await frames(240)
	print("[CritVis] clip done ", node_name)

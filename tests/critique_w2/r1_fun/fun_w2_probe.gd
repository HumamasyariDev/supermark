extends Node
## Geometry and encounter facts for the fun critique: where the Leaf Bouncer pads really are, whether Mak can
## stand on them, Captain Caw's state, bud/bee distances, pod counts. Prints [FUN] lines, then quits.

var world: Node
var player: CharacterBody3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func say(s: String) -> void:
	print("[FUN] " + s)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return world.get_world_3d().direct_space_state.intersect_ray(q)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and cs.get("player") != null:
			world = cs
			player = cs.get("player") as CharacterBody3D
			break
		if Time.get_ticks_msec() - t0 > 120000:
			say("TIMEOUT")
			get_tree().quit(2)
			return
	await _wait(2.0)
	var life = world.get("life")
	if life:
		for mv in life.get("movers"):
			say("mover %s base=%s dir=%s amp=%s period=%s phase=%s now=%s" % [(mv[0] as Node).name, mv[1], mv[2], mv[3], mv[4], mv[5], (mv[0] as Node3D).global_position])
	for d in life.get("droops"):
		say("droop %s base=%s now=%s" % [(d[0] as Node).name, d[1], (d[0] as Node3D).global_position])
	say("bodies LB2 id=%s pos_now=%s" % [world.get("builder").bodies.get("LB2"), (world.get("builder").bodies.get("LB2") as Node3D).position])
	var lv := world.find_child("Leaves", true, false)
	for id in ["LB1", "LB2", "LB3", "LB4", "LB5", "BL1", "BL2", "U02", "M05"]:
		var n := lv.get_node_or_null(id) as Node3D if lv else null
		if n == null:
			n = world.find_child(id, true, false) as Node3D
		if n == null:
			say("%s missing" % id)
			continue
		var shapes := []
		for cs in n.find_children("*", "CollisionShape3D", true, false):
			var c := cs as CollisionShape3D
			shapes.append("%s@%s dis=%s" % [c.shape.get_class(), c.global_position, c.disabled])
		var hit := _ray(n.global_position + Vector3(0, 3, 0), n.global_position + Vector3(0, -3, 0))
		say("%s pos=%s layer=%d groups=%s bounce_v=%s shapes=%s ray=%s" % [id, n.global_position, (n as CollisionObject3D).collision_layer if n is CollisionObject3D else -1, n.get_groups(), n.get_meta("bounce_velocity", "-"), shapes, hit.get("position", "none")])
	# Stand Mak on LB2 and watch for 4 s.
	var lb2 := lv.get_node_or_null("LB2") as Node3D
	if lb2:
		player.call("respawn", Transform3D(Basis(), lb2.global_position + Vector3(0, 0.3, 0)))
		for k in 16:
			await _wait(0.25)
			say("on LB2 t=%.2f mak=%s state=%s pad=%s" % [k * 0.25, player.global_position, player.call("get_state_name"), lb2.global_position])
	var caw := world.find_child("E17_CaptainCaw", true, false)
	if caw:
		say("caw stage=%s pos=%s" % [caw.get("stage"), (caw as Node3D).global_position])
	var e10 := world.find_child("E10", true, false) as Node3D
	if e10:
		say("E10 pos=%s notice=%s dist_to_bud=%.2f" % [e10.global_position, e10.get("notice_radius"), e10.global_position.distance_to(Vector3(7.2, 36.1, -6))])
	for id in ["E01", "E02", "E05", "E11", "E12", "E13"]:
		var e := world.find_child(id, true, false) as Node3D
		if e:
			say("%s pos=%s notice=%s defeated=%s" % [id, e.global_position, e.get("notice_radius"), e.get("is_defeated")])
	var tt := world.find_child("CloudHopper", true, false)
	if tt:
		say("CloudHopper time_limit=%s ordered=%s rings=%d" % [tt.get("time_limit"), tt.get("ordered"), tt.get_node("Rings").get_child_count()])
	say("DONE")
	get_tree().quit(0)

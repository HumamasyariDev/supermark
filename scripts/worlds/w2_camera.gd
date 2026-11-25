extends Node
## W2 camera support (fix round 1): builds the camera-hint zones CH0-CH7 from the plan's numbers (plus gate,
## kitchen and checkpoint zones the critics asked for), applies a zone's pivot height to the rig while Mak is
## inside it, and does the TRUNK_FADE job for leaves: a leaf visual that sits between the camera and Mak (or
## within 2 m of the lens) is hidden for that frame so Mak is never behind a blade.

const ZoneScript := preload("res://scripts/worlds/w2_camera_zone.gd")

var world: Node3D
var b
var holder: Node3D
var rig: Node3D
var _default_pivot := -1.0
var _leaf_vis: Array = []     # [Node3D visual, Node3D body]
var _hidden := {}
var _fade_meshes := {}   # visual -> Array of GeometryInstance3D
var _fade := {}          # visual -> current transparency 0..1


func setup(w: Node3D, builder) -> void:
	world = w
	b = builder
	holder = Node3D.new()
	holder.name = "CameraZones"
	world.add_child(holder)
	# CH0 garden gate: look-up framing so the castle and the belfry flower are in the first gameplay frame.
	_box("CH0_Gate", Vector3(-4, -1, 29), Vector3(4, 5, 39), {"fixed_yaw": 0.0, "camera_pitch_deg": 16.0, "camera_distance": 9.0, "pivot_height": 4.0, "camera_blend": 1.6, "camera_priority": 6})
	# CH1 lower stalk (L01-L13, K1) and CH2 middle stalk (M01-M08): camera outside the spiral, slightly low.
	# Fix r2: rings are 4.5 m tall at a 4 m step and now also cover L12-L13 (y 21-25.5) and M08-BL2-UC
	# (y 37.5-46), so no jump apex leaves a zone. Around the decks (L11-L13 under C1, M04-M08 under CC1) the
	# camera rides higher and looks down, so cloud undersides and the next leaf never fill the frame.
	for y0 in [1.0, 5.0, 9.0, 13.0, 17.0, 21.0]:
		_stalk_ring("CH1_%d" % int(y0), y0, 4.5, 7.5, -22.0 if y0 >= 17.0 else -8.0)
	for y0 in [25.5, 29.5, 33.5, 37.5, 41.5]:
		_stalk_ring("CH2_%d" % int(y0), y0, 4.5, 7.5, -22.0 if y0 >= 29.5 else -10.0)
	# CH3 stalk tip, V3 and the bell: pull out to 9 m from the south so the east-west swing reads side-on.
	_box("CH3_Tip", Vector3(-17, 50.5, -20), Vector3(-5, 68, -12), {"fixed_yaw": 0.0, "camera_pitch_deg": -8.0, "camera_distance": 9.0, "camera_priority": 7, "camera_blend": 1.2})
	# CH4 Giant's table, extended over the chair so CP6 retries rise above the backrest.
	_box("CH4_Table", Vector3(-12, 54.0, -38), Vector3(6.5, 60.5, -30), {"fixed_yaw": 45.0, "camera_pitch_deg": -35.0, "camera_distance": 7.0, "camera_priority": 7, "camera_blend": 1.2})
	# Kitchen floor (under the table and along the dresser): look north from the south, a little high.
	_box("CHK_KitchenFloor", Vector3(-16, 49.5, -42), Vector3(7, 53.8, -26.5), {"fixed_yaw": 0.0, "camera_pitch_deg": -18.0, "camera_distance": 6.0, "camera_priority": 3, "camera_blend": 1.2})
	# CH6 Leaf Bouncer: behind the chain (north-east), a little high, so the next pad and Caw's perch read.
	_box("CH6_LeafBouncer", Vector3(-44, 41, -42), Vector3(-21.5, 53, -10.5), {"fixed_yaw": 32.0, "camera_pitch_deg": -16.0, "camera_distance": 8.0, "camera_priority": 6, "camera_blend": 1.2})
	# CH7 courtyard (E16 chase): high, looking north over the oval and the portcullis.
	_box("CH7_Courtyard", Vector3(8, 49.5, -42), Vector3(19.5, 57, -26), {"fixed_yaw": 0.0, "camera_pitch_deg": -38.0, "camera_distance": 9.0, "camera_priority": 6, "camera_blend": 1.2})
	# Castle apron and gate (CP5, dev_castle): high enough to clear the rim cloud dressing behind Mak.
	_box("CHG_CastleGate", Vector3(3, 49.5, -24), Vector3(19, 56, -14.5), {"yaw_free": true, "camera_pitch_deg": -30.0, "camera_distance": 6.0, "camera_priority": 4})
	# Upper Runner and the chair route (U01-U04): pull out a little so the next blade is visible.
	_box("CHU_Runner", Vector3(-8, 44.5, -16), Vector3(6, 52, -3), {"yaw_free": true, "camera_pitch_deg": -22.0, "camera_distance": 6.5, "camera_priority": 2})
	# CP1 (sun leaf) respawn: keep the camera out from under the Cloud Landing (it filled half the frame).
	_box("CHC_SunLeaf", Vector3(2.5, 19.5, -9.5), Vector3(8.5, 23.5, -3.0), {"fixed_yaw": 70.0, "camera_pitch_deg": -24.0, "camera_distance": 6.5, "camera_priority": 6, "camera_blend": 0.9})
	for id in b.bodies.keys():
		var p: Dictionary = b.plat.get(id, {})
		if String(p.get("kind", "")) in ["leaf", "droop_leaf", "moving_leaf", "bouncy_leaf", "bouncy_leaf_swing"]:
			if b.visuals.has(id):
				_leaf_vis.append([b.visuals[id], b.bodies[id]])
	# Fix r2: the six colossus leaves fade too (one sat between the camera and Mak at M06).
	var cl := world.get_node_or_null("Level/Round3/ColossusLeaves")
	if cl == null:
		for n in world.find_children("ColossusLeaves", "", true, false):
			cl = n
	if cl:
		for g in cl.get_children():
			if g is Node3D:
				var probe := Node3D.new()
				probe.name = "FadeProbe"
				(g as Node3D).add_child(probe)
				_leaf_vis.append([g, probe, 3.2])
	for lv in _leaf_vis:
		var meshes: Array = []
		for mi in (lv[0] as Node).find_children("*", "GeometryInstance3D", true, false):
			meshes.append(mi)
		if lv[0] is GeometryInstance3D:
			meshes.append(lv[0])
		_fade_meshes[lv[0]] = meshes
	print("[W2] camera zones: %d, fading leaves: %d" % [holder.get_child_count(), _leaf_vis.size()])


func _zone(n: String, props: Dictionary) -> Area3D:
	var z := Area3D.new()
	z.set_script(ZoneScript)
	z.name = n
	for k in props.keys():
		z.set(k, props[k])
	z.set("builder", b)
	return z


func _box(n: String, lo: Vector3, hi: Vector3, props: Dictionary) -> void:
	var z := _zone(n, props)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = hi - lo
	cs.shape = bs
	z.add_child(cs)
	z.position = (lo + hi) * 0.5
	holder.add_child(z)


func _stalk_ring(n: String, y0: float, h: float, r: float, pitch := 6.0) -> void:
	var c: Vector3 = b.stalk_center(y0 + h * 0.5)
	var z := _zone(n, {"mode": "outside", "camera_pitch_deg": pitch, "camera_distance": 6.5, "camera_blend": 0.9, "camera_priority": 5, "spiral_bias": 30.0})
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = h
	cs.shape = cy
	z.add_child(cs)
	z.position = Vector3(c.x, y0 + h * 0.5, c.z)
	holder.add_child(z)


func _physics_process(_delta: float) -> void:
	if rig == null or not is_instance_valid(rig):
		rig = get_tree().get_first_node_in_group("game_camera") as Node3D
		if rig == null:
			return
		if _default_pivot < 0.0 and rig.get("pivot_height") != null:
			_default_pivot = float(rig.get("pivot_height"))
	if _default_pivot < 0.0:
		return
	var z: Variant = rig.get("zone")
	var want := _default_pivot
	if z is Node and is_instance_valid(z) and (z as Node).get("pivot_height") != null and float((z as Node).get("pivot_height")) > 0.0:
		want = float((z as Node).get("pivot_height"))
	var cur := float(rig.get("pivot_height"))
	if absf(cur - want) > 0.001:
		rig.set("pivot_height", move_toward(cur, want, 2.5 * get_physics_process_delta_time()))


func _process(_delta: float) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var cam := get_viewport().get_camera_3d()
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if cam == null or p == null:
		return
	var cpos := cam.global_position
	var target := p.global_position + Vector3(0, 0.7, 0)
	var seg := target - cpos
	var seg_len := seg.length()
	if seg_len < 0.01:
		return
	var dir := seg / seg_len
	# Fix r2: a soft 0.15 s fade (GeometryInstance3D.transparency) instead of popping whole leaves on and off.
	var step := _delta / 0.15
	for lv in _leaf_vis:
		var vis: Node3D = lv[0]
		if not is_instance_valid(vis):
			continue
		var lp: Vector3 = (lv[1] as Node3D).global_position
		var rad: float = float(lv[2]) if lv.size() > 2 else 1.5
		var hide := false
		if lp.distance_to(target) > 1.8:
			if lp.distance_to(cpos) < 2.2 + rad - 1.5:
				hide = true
			else:
				var s := clampf((lp - cpos).dot(dir), 0.0, seg_len)
				if s < seg_len - 1.0 and (cpos + dir * s).distance_to(lp) < rad:
					hide = true
		var cur: float = float(_fade.get(vis, 0.0))
		var want := 0.85 if hide else 0.0
		if is_equal_approx(cur, want):
			continue
		cur = move_toward(cur, want, step)
		_fade[vis] = cur
		for mi in _fade_meshes.get(vis, []):
			if is_instance_valid(mi):
				(mi as GeometryInstance3D).transparency = cur

class_name WolfDoor
extends Node3D
## The Wolf's Door: a tall red door with an iron wolf-head knocker, gated by Golden Truffles.
## Locked: the knocker rattles and a plate shows the requirement. Unlocked: the door swings open when the
## player approaches; walking through the doorway calls Router.enter_world(target_world).
## Generated visual (hub wolf_door.glb: door_frame > door_leaf > knocker_ring): the door_leaf node swings on its own
## hinge pivot and the door's collision body follows it on a separate pivot, so the frame stays put even when a
## builder reparents Visual under Hinge. The knocker ring rattles on its pivot when the door is locked.

signal opened
signal entered(world_id: String)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var required_truffles: int = 12
@export var target_world: String = "BOSS"
@export var unlock_flag: String = "wolf_door"
@export var door_color: Color = Color(0.72, 0.1, 0.1)
@export var width: float = 2.4
@export var height: float = 4.0
## Off only in tests/labs: emit `entered` without changing scene.
@export var route_on_enter: bool = true

var is_unlocked := false
var is_open := false
var _t := 0.0
var _visual: Node3D
var _hinge: Node3D
var _door_body: AnimatableBody3D
var _knocker: Node3D
var _plate: Node3D
var _near_zone: Area3D
var _enter_zone: Area3D
var _eyes: Array[MeshInstance3D] = []
var _cooldown := 0.0
var _leaf: Node3D
var _leaf_rest := Basis()
var _leaf_sign := 1.0
var _leaf_angle := 0.0
var _body_hinge: Node3D
var _ring: Node3D
var _ring_rest := Basis()
var _ring_kick := 0.0


func _ready() -> void:
	ObjSvc.ensure_npc_life_auto(self)
	add_to_group("wolf_door")
	_visual = ObjSvc.ensure_visual(self)
	# Frame collision (static) and the door leaf (animatable, swings).
	var frame := StaticBody3D.new()
	frame.collision_layer = ObjSvc.L_WORLD
	add_child(frame)
	ObjSvc.add_shape(frame, ObjSvc.box_shape(Vector3(0.4, height + 0.4, 0.6)), Vector3(-width * 0.5 - 0.2, (height + 0.4) * 0.5, 0))
	ObjSvc.add_shape(frame, ObjSvc.box_shape(Vector3(0.4, height + 0.4, 0.6)), Vector3(width * 0.5 + 0.2, (height + 0.4) * 0.5, 0))
	ObjSvc.add_shape(frame, ObjSvc.box_shape(Vector3(width + 0.8, 0.5, 0.6)), Vector3(0, height + 0.25, 0))
	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	_hinge.position = Vector3(-width * 0.5, 0, 0)
	add_child(_hinge)
	_door_body = AnimatableBody3D.new()
	_door_body.sync_to_physics = false
	_door_body.collision_layer = ObjSvc.L_WORLD
	_hinge.add_child(_door_body)
	ObjSvc.add_shape(_door_body, ObjSvc.box_shape(Vector3(width, height, 0.25)), Vector3(width * 0.5, height * 0.5, 0))
	if not ObjSvc.visual_has_content(_visual):
		_build_placeholder()
	else:
		_rig_generated()
	_near_zone = ObjSvc.make_area(self, ObjSvc.box_shape(Vector3(width + 2.0, height, 5.0)), ObjSvc.L_TRIGGER, ObjSvc.L_PLAYER, Vector3(0, height * 0.5, 0), "NearZone")
	_enter_zone = ObjSvc.make_area(self, ObjSvc.box_shape(Vector3(width, height, 0.8)), ObjSvc.L_TRIGGER, ObjSvc.L_PLAYER, Vector3(0, height * 0.5, -0.9), "EnterZone")
	_near_zone.body_entered.connect(_on_near)
	_enter_zone.body_entered.connect(_on_enter)
	is_unlocked = _check_unlocked()
	_refresh()
	# Builders add their "Chains" child right after add_child; dress it once they have.
	_dress_lock.call_deferred()


func _build_placeholder() -> void:
	var red := ObjSvc.mat(door_color, 0.5)
	var dark_red := ObjSvc.mat(door_color.darkened(0.35), 0.6)
	var stone := ObjSvc.mat(Color(0.55, 0.5, 0.48), 0.9)
	var iron := ObjSvc.mat(ObjSvc.IRON, 0.35, 0.9)
	# Stone arch frame with chunky blocks.
	for i in 6:
		var y := 0.35 + i * (height / 6.0)
		ObjSvc.soft_box(_visual, Vector3(0.5, height / 6.0 - 0.04, 0.7), stone, Vector3(-width * 0.5 - 0.25, y, 0), Vector3(0, 0, (i % 2) * 2.0 - 1.0), 0.05)
		ObjSvc.soft_box(_visual, Vector3(0.5, height / 6.0 - 0.04, 0.7), stone, Vector3(width * 0.5 + 0.25, y, 0), Vector3(0, 0, 1.0 - (i % 2) * 2.0), 0.05)
	ObjSvc.soft_box(_visual, Vector3(width + 1.0, 0.55, 0.75), stone, Vector3(0, height + 0.28, 0), Vector3.ZERO, 0.06)
	# Door leaf (parented to the hinge so it swings with the body).
	var leaf := Node3D.new()
	leaf.name = "Leaf"
	_hinge.add_child(leaf)
	ObjSvc.soft_box(leaf, Vector3(width, height, 0.22), red, Vector3(width * 0.5, height * 0.5, 0), Vector3.ZERO, 0.06)
	for i in 4:
		ObjSvc.box(leaf, Vector3(0.06, height - 0.3, 0.05), dark_red, Vector3(0.3 + i * (width - 0.6) / 3.0, height * 0.5, 0.13))
	for y in [0.6, height - 0.6]:
		ObjSvc.box(leaf, Vector3(width - 0.1, 0.14, 0.06), iron, Vector3(width * 0.5, y, 0.14))
		for k in 5:
			ObjSvc.sphere(leaf, 0.045, iron, Vector3(0.2 + k * (width - 0.4) / 4.0, y, 0.18))
	# The iron wolf-head knocker: snout, ears, brows and a ring in its teeth.
	_knocker = Node3D.new()
	_knocker.position = Vector3(width * 0.5, height * 0.58, 0.16)
	leaf.add_child(_knocker)
	ObjSvc.sphere(_knocker, 0.26, iron, Vector3.ZERO, Vector3(1.0, 0.95, 0.6))
	ObjSvc.sphere(_knocker, 0.13, iron, Vector3(0, -0.1, 0.14), Vector3(0.9, 0.7, 1.3))
	ObjSvc.sphere(_knocker, 0.05, ObjSvc.mat(Color(0.05, 0.05, 0.05), 0.3), Vector3(0, -0.06, 0.3))
	ObjSvc.cone(_knocker, 0.1, 0.24, iron, Vector3(-0.17, 0.25, 0), Vector3(0, 0, 18))
	ObjSvc.cone(_knocker, 0.1, 0.24, iron, Vector3(0.17, 0.25, 0), Vector3(0, 0, -18))
	ObjSvc.box(_knocker, Vector3(0.14, 0.03, 0.05), iron, Vector3(-0.09, 0.1, 0.15), Vector3(0, 0, -20))
	ObjSvc.box(_knocker, Vector3(0.14, 0.03, 0.05), iron, Vector3(0.09, 0.1, 0.15), Vector3(0, 0, 20))
	for sx in [-1.0, 1.0]:
		var eye := ObjSvc.sphere(_knocker, 0.035, ObjSvc.unique_mat(Color(1, 0.4, 0.1), 0.3, 0.0, Color(1, 0.35, 0.05), 0.0), Vector3(sx * 0.09, 0.03, 0.15))
		_eyes.append(eye)
	var ring := Node3D.new()
	ring.name = "Ring"
	ring.position = Vector3(0, -0.22, 0.16)
	_knocker.add_child(ring)
	ObjSvc.torus(ring, 0.12, 0.17, ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.9), Vector3(0, -0.15, 0), Vector3(90, 0, 0))
	# Requirement plate on the lintel.
	_plate = Node3D.new()
	_plate.position = Vector3(0, height + 0.28, 0.4)
	_visual.add_child(_plate)
	ObjSvc.soft_box(_plate, Vector3(1.0, 0.4, 0.06), ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.8), Vector3.ZERO, Vector3.ZERO, 0.03)
	ObjSvc.sphere(_plate, 0.09, ObjSvc.mat(ObjSvc.GOLD, 0.3, 0.8, ObjSvc.GOLD, 0.4), Vector3(-0.28, 0, 0.06))
	var l := ObjSvc.label(_plate, "x %d" % required_truffles, Vector3(0.12, 0, 0.05), 72, Color(0.3, 0.12, 0.05), false)
	l.outline_size = 0


## Finds door_leaf / knocker_ring in the generated door and moves the collision leaf onto a pivot at the leaf's hinge.
func _rig_generated() -> void:
	_leaf = ObjSvc.find_named(_visual, "door_leaf")
	_ring = ObjSvc.find_named(_visual, "knocker_ring")
	if _ring:
		_ring_rest = _ring.basis
	if _leaf == null:
		return
	_adopt_leaf_studs()
	_leaf_rest = _leaf.basis
	var to_local := global_transform.affine_inverse()
	var pivot := to_local * _leaf.global_position
	var mi := _leaf as MeshInstance3D
	var c_local := pivot + Vector3(1, 0, 0)
	if mi != null and mi.mesh != null:
		c_local = to_local * (_leaf.global_transform * mi.mesh.get_aabb().get_center())
	var off := c_local - pivot
	# Swing away from the front (toward local -Z, where the enter zone is): sign follows which side the leaf extends.
	_leaf_sign = 1.0 if off.x >= 0.0 else -1.0
	var leaf_w := Vector2(off.x, off.z).length() * 2.0
	_body_hinge = Node3D.new()
	_body_hinge.name = "LeafHinge"
	add_child(_body_hinge)
	_body_hinge.position = pivot
	_door_body.reparent(_body_hinge, false)
	_door_body.transform = Transform3D()
	for c in _door_body.get_children():
		if c is CollisionShape3D:
			var cs := c as CollisionShape3D
			cs.shape = ObjSvc.box_shape(Vector3(maxf(leaf_w, 0.5), height, 0.25))
			cs.position = Vector3(_leaf_sign * leaf_w * 0.5, height * 0.5, 0)


func _set_leaf_angle(deg: float) -> void:
	_leaf_angle = deg
	if _leaf:
		_leaf.basis = Basis(Vector3.UP, deg_to_rad(deg * _leaf_sign)) * _leaf_rest
		if _body_hinge:
			_body_hinge.rotation.y = deg_to_rad(deg * _leaf_sign)
	else:
		_hinge.rotation_degrees.y = deg


func _check_unlocked() -> bool:
	var dev := ObjSvc.autoload("Dev")
	if dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "unlock-all")):
		return true
	if unlock_flag != "" and ObjSvc.can("Game", "is_unlocked") and bool(ObjSvc.call_on("Game", "is_unlocked", [unlock_flag])):
		return true
	return ObjSvc.truffle_count() >= required_truffles


func _refresh() -> void:
	if _plate:
		_plate.visible = not is_unlocked
	for e in _eyes:
		var m := e.material_override as StandardMaterial3D
		m.emission_enabled = true
		m.emission_energy_multiplier = 0.4 if not is_unlocked else 2.5


func _process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	if not is_unlocked and Engine.get_process_frames() % 30 == 0 and _check_unlocked():
		is_unlocked = true
		_refresh()
		_unlock_fx()
	# The sneer closes (UI close animation) once Mak walks away, so it never lingers over the hub.
	if _dialog_mine and Engine.get_process_frames() % 6 == 0:
		_watch_dialog()
	var ring: Node3D = _knocker.get_node_or_null("Ring") as Node3D if _knocker else null
	if ring:
		ring.rotation.x = sin(_t * 1.3) * 0.08
	if _ring:
		# The knocker ring idles with a slight sway; a knock kicks it into a damped swing.
		_ring_kick = move_toward(_ring_kick, 0.0, delta * 1.6)
		var sw := sin(_t * 1.3) * 0.05 + sin(_t * 14.0) * 0.6 * _ring_kick * _ring_kick
		_ring.basis = _ring_rest * Basis(Vector3.RIGHT, sw)
	_sway_lock(delta)


var _dialog_mine := false


func _watch_dialog() -> void:
	var ui := ObjSvc.autoload("UI")
	if ui == null or not ObjSvc.can("UI", "is_dialog_open") or not bool(ObjSvc.call_on("UI", "is_dialog_open")):
		_dialog_mine = false
		return
	var p := ObjSvc.get_player()
	if p != null and ObjSvc.body_pos(p).distance_to(global_position) <= 6.0:
		return
	_dialog_mine = false
	var d: Variant = ui.get("dialog")
	if d is Object and is_instance_valid(d) and (d as Object).has_method("close"):
		(d as Object).call("close")


func _on_near(body: Node) -> void:
	if not ObjSvc.is_player(body):
		return
	if is_unlocked:
		open()
	elif _cooldown <= 0.0:
		_cooldown = 2.5
		ObjSvc.feedback("object_door_locked", global_position + Vector3(0, 2.0, 0), {"need": required_truffles - ObjSvc.truffle_count()}, "knocker_rattle")
		_ring_kick = 1.0
		jangle_lock(1.0)
		if _leaf:
			# The leaf strains against the lock: two little jolts.
			var jt := create_tween()
			for i in 2:
				jt.tween_method(_set_leaf_angle, 0.0, 1.6, 0.05)
				jt.tween_method(_set_leaf_angle, 1.6, 0.0, 0.09)
		var ring: Node3D = _knocker.get_node_or_null("Ring") as Node3D if _knocker else null
		if ring:
			var tw := create_tween()
			for i in 3:
				tw.tween_property(ring, "rotation:x", -0.7, 0.08)
				tw.tween_property(ring, "rotation:x", 0.0, 0.12)
		var need := required_truffles - ObjSvc.truffle_count()
		ObjSvc.show_dialog(["The iron wolf sneers. \"Come back with %d more truffle%s, little piggy.\"" % [need, "" if need == 1 else "s"]], "Wolf's Door")
		_dialog_mine = true


## Unlock beat: the eyes (placeholder) or a gold flash on the knocker, stars, the ring jumps, the leaf cracks ajar.
func _unlock_fx() -> void:
	var at := global_position + Vector3(0, height * 0.55, 0.3)
	if _ring:
		at = _ring.global_position
	ObjSvc.feedback("object_door_unlock", at, {"target": target_world}, "door_unlock")
	_ring_kick = 1.0
	_drop_lock()
	if not ObjSvc.juice_handles("object_door_unlock", "vfx"):
		ObjFx.flash(get_parent(), at, 1.6, 3.0, Color(1.0, 0.8, 0.4, 0.9), 0.4)
		ObjFx.star_ring(get_parent(), at, 10, 1.6, 0.5, Color(1.0, 0.85, 0.45), 0.6)
		ObjSvc.burst(get_parent(), at, Color(1.0, 0.85, 0.45), 30, 4.0, 0.18, -2.0, 1.0)
	var tw := create_tween()
	tw.tween_method(_set_leaf_angle, 0.0, 6.0, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_leaf_angle, 6.0, 2.5, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func open() -> void:
	if is_open:
		return
	is_open = true
	opened.emit()
	_drop_lock()
	ObjSvc.feedback("object_door_open", global_position + Vector3(0, 1.0, 0), {"target": target_world}, "door_open")
	# A creaking start, a heavy swing with a slight overshoot, a bump against the stop.
	var tw := create_tween()
	tw.tween_method(_set_leaf_angle, _leaf_angle, 14.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(_set_leaf_angle, 14.0, 112.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		ObjSvc.feedback("object_door_thud", global_position + Vector3(0, 0.3, -0.5), {})
		if not ObjSvc.juice_handles("object_door_thud", "vfx"):
			ObjFx.puffs(get_parent(), global_position + Vector3(0, 0.2, -0.6), Color(0.7, 0.64, 0.58, 0.7), 8, 1.4, 0.8, 0.9))
	tw.tween_method(_set_leaf_angle, 112.0, 104.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not ObjSvc.juice_handles("object_door_open", "vfx"):
		ObjSvc.burst(get_parent(), global_position + Vector3(0, 0.3, 0), Color(0.6, 0.55, 0.5), 20, 2.0, 0.3, -1.0, 1.0)


## Builders may hang chains and a padlock on the door as a child named "Chains" (or in group "wolf_door_lock").
## On unlock/open they shiver, drop to the floor and shrink away instead of hanging in the open doorway.
func _drop_lock() -> void:
	var locks: Array = []
	var ch := get_node_or_null("Chains") as Node3D
	if ch:
		locks.append(ch)
	for n in get_tree().get_nodes_in_group("wolf_door_lock"):
		if n is Node3D and is_ancestor_of(n) and not locks.has(n):
			locks.append(n)
	for l in locks:
		var lk := l as Node3D
		if not lk.visible or lk.has_meta("dropping"):
			continue
		lk.set_meta("dropping", true)
		var p0 := lk.position
		var tw := create_tween()
		for i in 3:
			tw.tween_property(lk, "position", p0 + Vector3(0.04 if i % 2 == 0 else -0.04, 0, 0), 0.05)
		tw.tween_property(lk, "position", p0, 0.05)
		tw.tween_property(lk, "position", p0 + Vector3(0, -1.6, 0.25), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			ObjSvc.sfx("knocker_rattle", lk.global_position)
			if not ObjSvc.juice_handles("object_door_thud", "vfx"):
				ObjFx.puffs(get_parent(), global_position + Vector3(0, 0.15, 0.6), Color(0.7, 0.64, 0.58, 0.7), 5, 0.9, 0.6, 0.6))
		tw.tween_property(lk, "position", p0 + Vector3(0, -1.45, 0.3), 0.1).set_ease(Tween.EASE_OUT)
		tw.tween_property(lk, "position", p0 + Vector3(0, -1.6, 0.32), 0.12).set_ease(Tween.EASE_IN)
		tw.tween_interval(0.25)
		tw.tween_property(lk, "scale", Vector3.ONE * 0.01, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			lk.visible = false
			lk.scale = Vector3.ONE
			lk.position = p0)


func _on_enter(body: Node) -> void:
	if not ObjSvc.is_player(body) or not is_open:
		return
	entered.emit(target_world)
	if not route_on_enter:
		return
	if ObjSvc.can("Router", "enter_world"):
		ObjSvc.call_on("Router", "enter_world", [target_world, ""])
	else:
		print("[WolfDoor] enter ", target_world, " (no Router handler yet)")


## The generated door's split left some iron studs and strap ends of the leaf in the door_frame mesh, so they hung in
## the air when the leaf swung open. Frame triangles that sit inside the leaf's silhouette (front half of the frame)
## are moved into a mesh that rides on the leaf. Cached per frame mesh; runs once per door.
static var _stud_cache: Dictionary = {}
var studs_moved := 0


func _adopt_leaf_studs() -> void:
	var frame := _leaf.get_parent() as MeshInstance3D
	var leaf_mi := _leaf as MeshInstance3D
	if frame == null or leaf_mi == null or frame.mesh == null or leaf_mi.mesh == null:
		return
	if frame.mesh.get_surface_count() != 1 or leaf_mi.mesh.get_surface_count() < 1:
		return
	var key := frame.mesh.get_rid().get_id()
	if not _stud_cache.has(key):
		_stud_cache[key] = _split_frame(frame.mesh as ArrayMesh, leaf_mi.mesh, _leaf.transform)
	var res: Array = _stud_cache[key]
	if res.is_empty():
		return
	var mat := frame.get_surface_override_material(0)
	if mat == null:
		mat = frame.mesh.surface_get_material(0)
	frame.mesh = res[0]
	var studs := MeshInstance3D.new()
	studs.name = "LeafStuds"
	studs.mesh = res[1]
	_leaf.add_child(studs)
	studs.transform = _leaf.transform.affine_inverse()
	if mat:
		frame.set_surface_override_material(0, mat)
		studs.set_surface_override_material(0, mat)
	studs_moved = int(res[2])


## Round 2 rule (critique objects r1 blocker): the frame mesh is split into welded loose parts. A part moves onto
## the leaf only when it is a small island (stud, ring, strap end) whose footprint lies inside the leaf's XY bounds
## AND a ray cast along the door normal (both ways) from its centre hits a leaf triangle before any other frame
## triangle. Frame arch studs hit the frame first and stay put. Returns [frame_mesh, leaf_studs_mesh, moved, report].
static var split_report: Dictionary = {}


static func _split_frame(fm: ArrayMesh, lm: Mesh, leaf_xf: Transform3D) -> Array:
	if fm == null:
		return []
	var lb := leaf_xf * lm.get_aabb()
	# Leaf triangles in frame space.
	var lt := PackedVector3Array()
	for s in lm.get_surface_count():
		var la := lm.surface_get_arrays(s)
		var lv: PackedVector3Array = la[Mesh.ARRAY_VERTEX]
		var li: PackedInt32Array = la[Mesh.ARRAY_INDEX] if la[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if li.is_empty():
			for v in lv:
				lt.append(leaf_xf * v)
		else:
			for i in li:
				lt.append(leaf_xf * lv[i])
	var fa := fm.surface_get_arrays(0)
	var fv: PackedVector3Array = fa[Mesh.ARRAY_VERTEX]
	var fi: PackedInt32Array = fa[Mesh.ARRAY_INDEX] if fa[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if fi.is_empty():
		return []
	var ntf := fi.size() / 3
	# Weld by position, then union-find the loose parts.
	var weld := {}
	var vid := PackedInt32Array()
	vid.resize(fv.size())
	for i in fv.size():
		var q := Vector3i(roundi(fv[i].x * 1000.0), roundi(fv[i].y * 1000.0), roundi(fv[i].z * 1000.0))
		if not weld.has(q):
			weld[q] = weld.size()
		vid[i] = weld[q]
	var parent := PackedInt32Array()
	parent.resize(weld.size())
	for i in parent.size():
		parent[i] = i
	for t in ntf:
		var r0 := _uf_find(parent, vid[fi[t * 3]])
		for k in [1, 2]:
			var r1 := _uf_find(parent, vid[fi[t * 3 + k]])
			if r1 != r0:
				parent[r1] = r0
	var tri_comp := PackedInt32Array()
	tri_comp.resize(ntf)
	var comp_box := {}
	for t in ntf:
		var r := _uf_find(parent, vid[fi[t * 3]])
		tri_comp[t] = r
		for k in 3:
			var v := fv[fi[t * 3 + k]]
			if comp_box.has(r):
				comp_box[r] = (comp_box[r] as AABB).expand(v)
			else:
				comp_box[r] = AABB(v, Vector3.ZERO)
	# XY bins over the union of both meshes for the ray tests.
	var all_box := lb
	for r in comp_box:
		all_box = all_box.merge(comp_box[r])
	var cell := 0.08
	var gw := int(ceil(all_box.size.x / cell)) + 1
	var gh := int(ceil(all_box.size.y / cell)) + 1
	var leaf_bins: Array = []
	var frame_bins: Array = []
	leaf_bins.resize(gw * gh)
	frame_bins.resize(gw * gh)
	for i in gw * gh:
		leaf_bins[i] = []
		frame_bins[i] = []
	for t in lt.size() / 3:
		_bin_tri(leaf_bins, t, lt[t * 3], lt[t * 3 + 1], lt[t * 3 + 2], all_box.position, cell, gw, gh)
	for t in ntf:
		_bin_tri(frame_bins, t, fv[fi[t * 3]], fv[fi[t * 3 + 1]], fv[fi[t * 3 + 2]], all_box.position, cell, gw, gh)
	var move_comp := {}
	var n_small := 0
	var n_leaf := 0
	var part_info: Array = []
	for r in comp_box:
		var bb: AABB = comp_box[r]
		part_info.append(str(bb))
		if bb.get_longest_axis_size() >= 0.45:
			continue
		n_small += 1
		var c := bb.get_center()
		# Footprint inside the leaf's XY bounds (small margin).
		if c.x < lb.position.x + 0.02 or c.x > lb.end.x - 0.02 or c.y < lb.position.y + 0.02 or c.y > lb.end.y - 0.02:
			continue
		var gx := clampi(int((c.x - all_box.position.x) / cell), 0, gw - 1)
		var gy := clampi(int((c.y - all_box.position.y) / cell), 0, gh - 1)
		var dl := INF
		for t in leaf_bins[gy * gw + gx]:
			var z: Variant = _z_at(lt[t * 3], lt[t * 3 + 1], lt[t * 3 + 2], c.x, c.y)
			if z != null:
				dl = minf(dl, absf(float(z) - c.z))
		var df := INF
		for t in frame_bins[gy * gw + gx]:
			if tri_comp[t] == r:
				continue
			var z2: Variant = _z_at(fv[fi[t * 3]], fv[fi[t * 3 + 1]], fv[fi[t * 3 + 2]], c.x, c.y)
			if z2 != null:
				df = minf(df, absf(float(z2) - c.z))
		part_info[part_info.size() - 1] += " dl=%.3f df=%.3f" % [dl, df]
		if dl < 0.35 and dl + 0.005 < df:
			move_comp[r] = true
			n_leaf += 1
	var keep := PackedInt32Array()
	var move := PackedInt32Array()
	for t in ntf:
		var dst := move if move_comp.has(tri_comp[t]) else keep
		dst.append(fi[t * 3])
		dst.append(fi[t * 3 + 1])
		dst.append(fi[t * 3 + 2])
	var moved := move.size() / 3
	split_report = {"part_info": part_info, "parts": comp_box.size(), "small_parts": n_small, "parts_on_leaf": n_leaf, "tris_moved": moved, "tris": ntf}
	print("[WolfDoor] %d loose parts (%d small); %d ride on the leaf (%d of %d frame triangles)" % [comp_box.size(), n_small, n_leaf, moved, ntf])
	if moved == 0 or moved > ntf / 3:
		return []
	var ka := fa.duplicate()
	ka[Mesh.ARRAY_INDEX] = keep
	var ma := fa.duplicate()
	ma[Mesh.ARRAY_INDEX] = move
	var km := ArrayMesh.new()
	km.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ka)
	km.surface_set_material(0, fm.surface_get_material(0))
	var mm := ArrayMesh.new()
	mm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ma)
	mm.surface_set_material(0, fm.surface_get_material(0))
	return [km, mm, moved]


static func _bin_tri(bins: Array, t: int, a: Vector3, b: Vector3, c: Vector3, origin: Vector3, cell: float, gw: int, gh: int) -> void:
	var x0 := clampi(int((minf(a.x, minf(b.x, c.x)) - origin.x) / cell), 0, gw - 1)
	var x1 := clampi(int((maxf(a.x, maxf(b.x, c.x)) - origin.x) / cell), 0, gw - 1)
	var y0 := clampi(int((minf(a.y, minf(b.y, c.y)) - origin.y) / cell), 0, gh - 1)
	var y1 := clampi(int((maxf(a.y, maxf(b.y, c.y)) - origin.y) / cell), 0, gh - 1)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			(bins[gy * gw + gx] as Array).append(t)


## Z of triangle abc at (x, y) when the point projects inside it (a ray along the door normal), else null.
static func _z_at(a: Vector3, b: Vector3, c: Vector3, x: float, y: float) -> Variant:
	var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(d) < 1e-9:
		return null
	var w0 := ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / d
	var w1 := ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / d
	var w2 := 1.0 - w0 - w1
	if w0 < -1e-4 or w1 < -1e-4 or w2 < -1e-4:
		return null
	return w0 * a.z + w1 * b.z + w2 * c.z


static func _uf_find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i



# ------------------------------------------------------------------ lock dressing (critique objects r1 re-run)
## The builders' chains were black torus links crossing the leaf in a straight X, their ends hanging in the air past
## the frame, and the "12" was a flat square floating on the door. When a builder hangs a "Chains" child, the door
## keeps that node (the builder still shows, hides and drops it) but replaces its contents: four iron eye-bolts on
## the frame, chains of elongated links on a catenary sag from each bolt to the shackle, and a brass padlock body
## with the required count engraved on its face. The chains sway a little at idle and jangle when Mak knocks.
@export var dress_builder_lock: bool = true

var _lock_chains: Array[Node3D] = []
var _lock_axes: Array[Vector3] = []
var _lock_body: Node3D
var _lock_jangle := 0.0


func _dress_lock() -> void:
	var ch := get_node_or_null("Chains") as Node3D
	if ch == null or not dress_builder_lock or ch.has_meta("dressed"):
		return
	ch.set_meta("dressed", true)
	for c in ch.get_children():
		if c is Node3D:
			(c as Node3D).visible = false
	# The builders hang the lock on the +Z face (front of the hub door); keep their depth.
	var z := 0.45
	var iron := ObjSvc.mat(Color(0.2, 0.2, 0.23), 0.42, 0.85)
	var iron_dark := ObjSvc.mat(Color(0.12, 0.12, 0.14), 0.5, 0.8)
	var brass := ObjSvc.mat(ObjSvc.BRASS, 0.32, 0.85)
	var lock_at := Vector3(0, minf(1.95, height * 0.5), z + 0.12)
	var shackle_at := lock_at + Vector3(0, 0.3, 0)
	# Eye-bolts sit on the frame posts' front face (wolf_door.glb: frame outer half-width 1.03, leaf 0.72, face at z 0,
	# times the hub's 1.2 scale): x = +-0.44 * width, low and at three quarters of the height.
	var bx := width * 0.44
	var fz := 0.04
	var anchors := [Vector3(-bx, 0.5, fz), Vector3(bx, 0.5, fz), Vector3(-bx, height * 0.75, fz), Vector3(bx, height * 0.75, fz)]
	var root := Node3D.new()
	root.name = "DoorLock"
	ch.add_child(root)
	for i in anchors.size():
		var a: Vector3 = anchors[i]
		# Eye-bolt: a square iron plate with four rivets and a ring standing off the frame.
		ObjSvc.soft_box(root, Vector3(0.18, 0.18, 0.04), iron_dark, a + Vector3(0, 0, 0.0), Vector3.ZERO, 0.015)
		for k in 4:
			var o := Vector3(0.058 if k % 2 == 0 else -0.058, 0.058 if k < 2 else -0.058, 0.0)
			ObjSvc.sphere(root, 0.017, iron, a + o + Vector3(0, 0, 0.022))
		ObjSvc.cylinder(root, 0.024, 0.024, 0.08, iron, a + Vector3(0, 0, 0.05), Vector3(90, 0, 0))
		var eye := ObjSvc.torus(root, 0.032, 0.068, iron, a + Vector3(0, 0, 0.1), Vector3(0, 90, 0))
		eye.name = "EyeBolt%d" % i
		# Chain from the eye to the shackle: sags under its own weight and steps forward off the frame onto the leaf
		# within the first fifth of its length (so it never cuts through the leaf).
		var start: Vector3 = a + Vector3(0, -0.05, 0.1)
		var end: Vector3 = shackle_at + Vector3(signf(a.x) * 0.07, 0.04 if a.y > shackle_at.y else -0.03, 0)
		var chain := Node3D.new()
		chain.name = "Chain%d" % i
		chain.position = start
		root.add_child(chain)
		var span := end - start
		var flat := Vector2(span.x, span.y).length()
		var sag := clampf(flat * 0.09, 0.08, 0.3)
		var n_links := maxi(8, int(flat / 0.105))
		var pts: Array[Vector3] = []
		for k in n_links + 1:
			var t := float(k) / float(n_links)
			var zf := span.z * (1.0 - pow(1.0 - t, 8.0))
			pts.append(Vector3(span.x * t, span.y * t - sag * 4.0 * t * (1.0 - t), zf))
		for k in range(1, pts.size()):
			var mid := (pts[k] + pts[k - 1]) * 0.5
			var dir := (pts[k] - pts[k - 1]).normalized()
			var link := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.03
			tm.outer_radius = 0.064
			tm.rings = 14
			tm.ring_segments = 8
			link.mesh = tm
			link.material_override = iron
			chain.add_child(link)
			# Torus axis is local Y; lay the ring along the chain, every other link turned 90 degrees, stretched so
			# neighbouring links overlap (link length about 0.2 m on a 0.105 m pitch).
			var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
			# looking_at puts local -Z on the chain; the torus ring (axis local Y) then contains the chain direction.
			var b := Basis.looking_at(dir, up)
			if k % 2 == 0:
				b = b * Basis(Vector3.BACK, PI * 0.5)
			link.transform = Transform3D(b * Basis.from_scale(Vector3(1.0, 1.0, 1.6)), mid)
		_lock_chains.append(chain)
		_lock_axes.append(span.normalized())
	# Padlock: brass body, darker bevel, iron shackle, keyhole, engraved count.
	_lock_body = Node3D.new()
	_lock_body.name = "Padlock"
	_lock_body.position = lock_at
	root.add_child(_lock_body)
	ObjSvc.soft_box(_lock_body, Vector3(0.46, 0.4, 0.16), brass, Vector3.ZERO, Vector3.ZERO, 0.07)
	ObjSvc.soft_box(_lock_body, Vector3(0.38, 0.32, 0.02), ObjSvc.mat(ObjSvc.BRASS.darkened(0.25), 0.4, 0.8), Vector3(0, 0, 0.08), Vector3.ZERO, 0.04)
	ObjSvc.torus(_lock_body, 0.1, 0.15, iron, Vector3(0, 0.27, 0), Vector3(90, 0, 0)).scale = Vector3(1, 1, 1.25)
	ObjSvc.cylinder(_lock_body, 0.022, 0.022, 0.02, iron_dark, Vector3(0, -0.1, 0.092), Vector3(90, 0, 0))
	ObjSvc.box(_lock_body, Vector3(0.016, 0.05, 0.02), iron_dark, Vector3(0, -0.13, 0.092))
	var lab := ObjSvc.label(_lock_body, str(required_truffles), Vector3(0, 0.04, 0.093), 72, Color(0.24, 0.15, 0.06), false)
	lab.name = "Count"
	lab.outline_size = 6
	lab.outline_modulate = Color(1.0, 0.86, 0.5, 0.55)
	lab.pixel_size = 0.0028
	var f := "res://assets/fonts/cherryswash/CherrySwash-Bold.ttf"
	if ResourceLoader.exists(f):
		lab.font = load(f) as Font
	print("[WolfDoor] lock dressed: 4 eye-bolts, %d chains, padlock '%d'" % [_lock_chains.size(), required_truffles])


func _sway_lock(delta: float) -> void:
	if _lock_chains.is_empty():
		return
	_lock_jangle = move_toward(_lock_jangle, 0.0, delta * 1.4)
	for i in _lock_chains.size():
		var ang := sin(_t * 1.4 + float(i) * 1.7) * 0.035 + sin(_t * 17.0 + float(i)) * 0.12 * _lock_jangle * _lock_jangle
		_lock_chains[i].basis = Basis(_lock_axes[i], ang)
	if _lock_body:
		_lock_body.rotation.z = sin(_t * 1.4 + 0.5) * 0.02 + sin(_t * 15.0) * 0.08 * _lock_jangle * _lock_jangle


## Knocks and a locked bump rattle the chains.
func jangle_lock(amount: float = 1.0) -> void:
	_lock_jangle = clampf(maxf(_lock_jangle, amount), 0.0, 1.0)

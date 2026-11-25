class_name CheckpointBookmark
extends Area3D
## Checkpoint: the generated bookmark (a storybook lying open with a tall satin ribbon, clasp and tassel).
## Touching it flips the ribbon (anticipation dip, a full turn with overshoot), lights the clasp and tassel gold,
## and calls Game.set_checkpoint(world_id, respawn transform). Only the latest one stays lit.
## Without the GLB it builds the old primitive bookmark on a brass post.

signal activated(checkpoint: Node)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var world_id: String = ""
## Respawn offset in local space (in front of the post, facing the post's -Z).
@export var respawn_offset: Vector3 = Vector3(0, 0, -1.2)
@export var height: float = 2.6
## Uses the generated bookmark mesh when no visual_scene is set and the file exists.
@export var use_default_mesh: bool = true

const DEFAULT_MESH := "res://assets/props/pickups/bookmark_checkpoint/bookmark_checkpoint.glb"
const DEFAULT_MESH_SCALE := 1.2
const GLOW_GOLD := Color(1.0, 0.79, 0.24)

var is_active := false
var _flipping := false
var _t := 0.0
var _visual: Node3D
var _ribbon_pivot: Node3D
var _ribbon_mat: StandardMaterial3D
var _light: OmniLight3D
var _sparkles: GPUParticles3D
var _tassel: Node3D
var _book: Node3D
var _glow_mats: Array[StandardMaterial3D] = []
var _ribbon_mats: Array[StandardMaterial3D] = []
var _glow := 0.0
var _generated := false


func _ready() -> void:
	ObjSvc.ensure_npc_life_auto(self)
	add_to_group("checkpoint")
	if world_id == "":
		world_id = ObjSvc.current_world()
	collision_layer = ObjSvc.L_TRIGGER
	collision_mask = ObjSvc.L_PLAYER
	ObjSvc.add_shape(self, ObjSvc.cyl_shape(1.0, height), Vector3(0, height * 0.5, 0))
	if visual_scene == null and use_default_mesh and ResourceLoader.exists(DEFAULT_MESH):
		visual_scene = load(DEFAULT_MESH) as PackedScene
		if is_equal_approx(visual_scale, 1.0):
			visual_scale = DEFAULT_MESH_SCALE
	_visual = ObjSvc.ensure_visual(self)
	if not ObjSvc.visual_has_content(_visual):
		_build_placeholder()
	else:
		_rig_generated()
	_light = OmniLight3D.new()
	_light.light_color = ObjSvc.CANDLE
	_light.light_energy = 0.0
	_light.omni_range = 4.0
	_light.position = Vector3(0, height * 0.75 if _light_pos_y < 0.0 else _light_pos_y, 0)
	add_child(_light)
	_sparkles = ObjSvc.twinkles(self, Color(1, 0.85, 0.45), 6, 0.5, 0.12, 0.5)
	_sparkles.position = Vector3(0.35, height * 0.6, 0) if not _generated else Vector3(0, _light_pos_y, 0)
	_sparkles.emitting = false
	_t = randf() * TAU
	body_entered.connect(func(b: Node) -> void:
		if ObjSvc.is_player(b):
			activate())


## Groups the GLB's Ribbon, Clasp and Tassel under a pivot at the ribbon's foot so the ribbon can sway and flip,
## and prepares per-instance glow materials for the clasp and tassel (README: emission #FFC93C, energy 1-2).
func _rig_generated() -> void:
	var gen := _visual.get_node_or_null("Generated") as Node3D
	var ribbon := ObjSvc.find_named(gen, "Ribbon")
	if gen == null or ribbon == null:
		return
	_generated = true
	_book = ObjSvc.find_named(gen, "Book")
	_ribbon_pivot = Node3D.new()
	_ribbon_pivot.name = "RibbonPivot"
	ribbon.get_parent().add_child(_ribbon_pivot)
	_ribbon_pivot.transform = ribbon.transform
	for n in ["Ribbon", "Clasp", "Tassel"]:
		var node := ObjSvc.find_named(gen, n)
		if node != null:
			node.reparent(_ribbon_pivot, true)
	_tassel = ObjSvc.find_named(_ribbon_pivot, "Tassel")
	for n in ["Clasp", "Tassel"]:
		var mi := ObjSvc.find_named(_ribbon_pivot, n) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var base := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if base == null:
			continue
		var m := base.duplicate() as StandardMaterial3D
		m.emission_enabled = true
		m.emission = GLOW_GOLD
		m.emission_energy_multiplier = 0.0
		mi.set_surface_override_material(0, m)
		_glow_mats.append(m)
	var rmi := ribbon as MeshInstance3D
	if rmi != null and rmi.mesh != null and rmi.mesh.surface_get_material(0) is StandardMaterial3D:
		var rm := (rmi.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		rm.emission_enabled = true
		rm.emission = Color(1.0, 0.45, 0.3)
		rm.emission_energy_multiplier = 0.0
		rmi.set_surface_override_material(0, rm)
		_ribbon_mats.append(rm)
	_ribbon_pivot.rotation.x = -0.12  # drooping until touched
	_light_pos_y = 1.4 * visual_scale
	# Critique objects r1: from gameplay distance the unlit bookmark read as a dark stick. A wider parchment base
	# and a soft gold trim glow (below) keep its silhouette readable before it is claimed.
	if _book:
		_book.scale *= 1.3


var _light_pos_y := -1.0


func _build_placeholder() -> void:
	var brass := ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.8)
	var wood := ObjSvc.mat(ObjSvc.WALNUT, 0.7)
	# Book-shaped base: a little stack of two closed books.
	ObjSvc.soft_box(_visual, Vector3(0.9, 0.18, 0.65), ObjSvc.mat(ObjSvc.BURGUNDY, 0.6), Vector3(0, 0.09, 0))
	ObjSvc.box(_visual, Vector3(0.84, 0.14, 0.6), ObjSvc.mat(ObjSvc.PAPER, 0.9), Vector3(0.03, 0.09, 0))
	ObjSvc.soft_box(_visual, Vector3(0.75, 0.16, 0.55), ObjSvc.mat(Color(0.2, 0.36, 0.55), 0.6), Vector3(0.0, 0.26, 0), Vector3(0, 12, 0))
	ObjSvc.cylinder(_visual, 0.05, 0.06, height, brass, Vector3(0, height * 0.5 + 0.2, 0))
	ObjSvc.sphere(_visual, 0.11, brass, Vector3(0, height + 0.25, 0))
	ObjSvc.cylinder(_visual, 0.03, 0.03, 0.75, wood, Vector3(0.36, height + 0.05, 0), Vector3(0, 0, 90))
	# The ribbon pivots at the crossbar so it can flip.
	_ribbon_pivot = Node3D.new()
	_ribbon_pivot.name = "RibbonPivot"
	_ribbon_pivot.position = Vector3(0.36, height + 0.02, 0)
	_visual.add_child(_ribbon_pivot)
	_ribbon_mat = ObjSvc.unique_mat(Color(0.35, 0.5, 0.78), 0.55)
	_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ObjSvc.box(_ribbon_pivot, Vector3(0.55, 1.2, 0.03), _ribbon_mat, Vector3(0, -0.6, 0))
	# Swallowtail notch at the bottom: two angled tips.
	ObjSvc.box(_ribbon_pivot, Vector3(0.24, 0.3, 0.03), _ribbon_mat, Vector3(-0.15, -1.3, 0), Vector3(0, 0, -18))
	ObjSvc.box(_ribbon_pivot, Vector3(0.24, 0.3, 0.03), _ribbon_mat, Vector3(0.15, -1.3, 0), Vector3(0, 0, 18))
	# Emblem: a little golden truffle medallion.
	ObjSvc.cylinder(_ribbon_pivot, 0.14, 0.14, 0.05, ObjSvc.mat(ObjSvc.GOLD, 0.3, 0.8, ObjSvc.GOLD, 0.3), Vector3(0, -0.55, 0.03), Vector3(90, 0, 0))


func _process(delta: float) -> void:
	_t += delta
	if _ribbon_pivot and not _flipping:
		# The ribbon sways like cloth in a breeze; it droops while unclaimed and stands proud once lit.
		var droop := -0.12 if not is_active else 0.0
		_ribbon_pivot.rotation.z = sin(_t * 1.6) * (0.04 if not is_active else 0.07) + sin(_t * 3.7) * 0.012
		_ribbon_pivot.rotation.x = lerpf(_ribbon_pivot.rotation.x, droop + sin(_t * 2.3) * 0.05, clampf(delta * 3.0, 0.0, 1.0))
	if _tassel:
		# The tassel hangs from its knot and swings a beat behind the ribbon.
		_tassel.rotation.z = sin(_t * 1.6 - 0.9) * 0.18
		_tassel.rotation.x = sin(_t * 2.3 - 0.7) * 0.12
	var want_glow := 1.0 if is_active else 0.0
	_glow = move_toward(_glow, want_glow, delta * 1.5)
	for m in _glow_mats:
		m.emission_energy_multiplier = 0.3 + _glow * (1.3 + 0.35 * sin(_t * 3.0))
	for m in _ribbon_mats:
		m.emission_energy_multiplier = _glow * 0.18
	if is_active and _light:
		_light.light_energy = 1.4 + sin(_t * 3.0) * 0.3


func activate() -> void:
	if is_active:
		return
	get_tree().call_group("checkpoint", "_on_other_activated", self)
	is_active = true
	var xf := get_respawn_transform()
	ObjSvc.call_on("Game", "set_checkpoint", [world_id, xf])
	ObjSvc.feedback("object_checkpoint", global_position + Vector3(0, 1.2, 0), {"world": world_id}, "checkpoint")
	activated.emit(self)
	_sparkles.emitting = true
	if _generated:
		_flip_generated()
		return
	ObjSvc.burst(get_parent(), global_position + Vector3(0.36, height * 0.7, 0), Color(1, 0.85, 0.4), 24, 3.5, 0.16, -2.0, 0.9)
	if _ribbon_pivot:
		var tw := create_tween()
		tw.tween_property(_ribbon_pivot, "rotation:y", _ribbon_pivot.rotation.y + TAU, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_ribbon_pivot, "scale", Vector3(1.25, 0.8, 1.0), 0.15)
		tw.tween_property(_ribbon_pivot, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if _ribbon_mat:
		_ribbon_mat.albedo_color = ObjSvc.GOLD
		_ribbon_mat.emission_enabled = true
		_ribbon_mat.emission = Color(1.0, 0.7, 0.25)
		_ribbon_mat.emission_energy_multiplier = 0.6


## The generated bookmark's flip: the book thumps (squash), the ribbon dips, whips a full turn with overshoot and
## springs upright, a gold flash and stars burst from the clasp and a ring runs over the ground.
func _flip_generated() -> void:
	_flipping = true
	var clasp_at := global_position + Vector3(0, 1.1 * visual_scale, 0)
	var tw := create_tween()
	tw.tween_property(_ribbon_pivot, "scale", Vector3(1.15, 0.82, 1.15), 0.08).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_ribbon_pivot, "rotation:x", 0.15, 0.08)
	tw.tween_callback(func() -> void:
		if not ObjSvc.juice_handles("object_checkpoint", "vfx"):
			ObjFx.flash(get_parent(), clasp_at, 1.4, 2.6, Color(1.0, 0.85, 0.45, 0.9), 0.35)
			ObjFx.star_ring(get_parent(), clasp_at, 7, 1.2, 0.42, Color(1.0, 0.88, 0.5), 0.55)
			ObjFx.ground_ring(get_parent(), global_position, 2.2 * visual_scale, Color(1.0, 0.85, 0.5, 0.7), 0.45)
			ObjSvc.burst(get_parent(), clasp_at, Color(1, 0.85, 0.4), 24, 3.5, 0.16, -2.0, 0.9))
	tw.tween_property(_ribbon_pivot, "rotation:y", _ribbon_pivot.rotation.y + TAU, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_ribbon_pivot, "scale", Vector3(0.9, 1.15, 0.9), 0.14)
	tw.parallel().tween_property(_ribbon_pivot, "rotation:x", -0.05, 0.2)
	tw.tween_property(_ribbon_pivot, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		_ribbon_pivot.rotation.y = fposmod(_ribbon_pivot.rotation.y, TAU)
		_flipping = false)
	if _book:
		var bt := create_tween()
		var s0 := _book.scale
		bt.tween_property(_book, "scale", s0 * Vector3(1.08, 0.7, 1.08), 0.07)
		bt.tween_property(_book, "scale", s0, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_glow = 0.0
	var gt := create_tween()
	gt.tween_interval(0.08)
	gt.tween_callback(func() -> void: _glow = 2.2)


## The validated respawn (cached): critique objects r1 found two bookmarks whose fixed offset put Mak past a table
## edge (ledge hang after every fall) or on a slope into a syrup pool. The offset point is used when it has flat
## floor (normal.y > 0.94) within 0.6 m, floor under a 0.35 m ring around it (not an edge) and room for Mak's capsule;
## otherwise 8 directions at 1.2, 0.8 and 0.5 m, then the bookmark base. Mak faces away from the bookmark.
var _safe_xf: Variant = null
var respawn_fallback_used := ""


func get_respawn_transform() -> Transform3D:
	if _safe_xf != null:
		return _safe_xf
	var xf := global_transform
	xf.origin = global_transform * respawn_offset
	if not is_inside_tree():
		return xf
	var space := get_world_3d().direct_space_state
	var base := global_position
	var fwd := (global_transform * respawn_offset) - base
	fwd.y = 0.0
	if fwd.length() < 0.05:
		fwd = -global_basis.z
	var cands: Array = [[global_transform * respawn_offset, "offset"]]
	# Critique objects r1 QA: W1 CP2_grove had every 1.2 m spot inside a bellows gust lane, so the search reaches
	# further out (1.8, 2.6 and 3.5 m) before it gives up on a calm spot.
	for dist in [1.2, 0.8, 0.5, 1.8, 2.6, 3.5]:
		for k in 8:
			var dir := fwd.normalized().rotated(Vector3.UP, TAU * float(k) / 8.0)
			cands.append([base + dir * dist, "dir%d_%.1f" % [k, dist]])
	cands.append([base, "base"])
	# Pass 1 is strict (calm, no hazard, no moving platform); pass 2 only asks for floor and capsule room.
	for strict in [true, false]:
		for c in cands:
			var at: Variant = _probe_spot(space, c[0], strict)
			if at == null:
				continue
			var p: Vector3 = at
			var away := p - base
			away.y = 0.0
			var out := xf
			out.origin = p + Vector3(0, 0.05, 0)
			if str(c[1]) != "offset" and away.length() > 0.05:
				out.basis = Basis.looking_at(away.normalized(), Vector3.UP)
			respawn_fallback_used = str(c[1]) + ("" if strict else "_loose")
			if respawn_fallback_used != "offset":
				push_warning("[Checkpoint] %s: respawn offset unsafe (%s), using %s at %s" % [get_path(), respawn_reject_reason, respawn_fallback_used, out.origin])
			_safe_xf = out
			return out
	push_warning("[Checkpoint] %s: no safe respawn found, keeping the offset" % get_path())
	respawn_fallback_used = "none"
	_safe_xf = xf
	return xf


## Why the configured offset spot was rejected ("" when it was accepted): floor, edge, room, wind, hazard, platform.
var respawn_reject_reason := ""


func _probe_spot(space: PhysicsDirectSpaceState3D, p: Vector3, strict: bool = true) -> Variant:
	var why := _probe_reject(space, p, strict)
	if why != "":
		if respawn_reject_reason == "":
			respawn_reject_reason = why
		return null
	var hit := _floor_ray(space, p)
	return Vector3(p.x, (hit["position"] as Vector3).y, p.z)


func _probe_reject(space: PhysicsDirectSpaceState3D, p: Vector3, strict: bool) -> String:
	var hit := _floor_ray(space, p)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.94:
		return "floor"
	var fy: float = (hit["position"] as Vector3).y
	if absf(fy - p.y) > 0.6:
		return "floor_height"
	if strict and _is_moving_body(hit.get("collider")):
		return "moving_platform"
	# Not on an edge or a slope: flat floor under a ring around the spot at about the same height.
	for k in 4:
		var o := Vector3(0.35, 0, 0).rotated(Vector3.UP, TAU * float(k) / 4.0)
		var h2 := _floor_ray(space, Vector3(p.x, fy, p.z) + o)
		if h2.is_empty() or absf((h2["position"] as Vector3).y - fy) > 0.3:
			return "edge"
		if strict and (h2["normal"] as Vector3).y < 0.85:
			return "slope"
	# Room for Mak's capsule (r 0.35, h 1.25), lifted a little off the floor.
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.25
	q.shape = cap
	q.collision_mask = ObjSvc.L_WORLD
	q.transform = Transform3D(Basis(), Vector3(p.x, fy + 0.625 + 0.08, p.z))
	if not space.intersect_shape(q, 1).is_empty():
		return "room"
	if not strict:
		return ""
	var feet := Vector3(p.x, fy, p.z)
	# Calm air: an idle Mak must not be blown away from the bookmark (peak gust, ignoring pulses and bellows drive,
	# sampled at the feet, the chest and a 0.6 m ring so a lane edge counts too).
	for zone in get_tree().get_nodes_in_group("wind_zone"):
		if not (zone is Node3D) or not zone.is_inside_tree():
			continue
		for s in [Vector3(0, 0.3, 0), Vector3(0, 0.9, 0), Vector3(0.6, 0.5, 0), Vector3(-0.6, 0.5, 0), Vector3(0, 0.5, 0.6), Vector3(0, 0.5, -0.6)]:
			var w := Vector3.ZERO
			if zone.has_method("get_peak_wind"):
				w = zone.call("get_peak_wind", feet + s)
			elif zone.has_method("get_wind"):
				w = zone.call("get_wind", feet + s)
			if w.length() > 1.0:
				return "wind"
	# No hazard volume (thorns, hot chocolate, syrup) under or around the capsule.
	var hq := PhysicsShapeQueryParameters3D.new()
	var hc := CapsuleShape3D.new()
	hc.radius = 0.7
	hc.height = 1.6
	hq.shape = hc
	hq.collide_with_areas = true
	hq.collide_with_bodies = false
	hq.collision_mask = 0xFFFF
	hq.transform = Transform3D(Basis(), feet + Vector3(0, 0.8, 0))
	for r in space.intersect_shape(hq, 16):
		var col: Object = r.get("collider")
		if col is Node and ((col as Node).is_in_group("hazard") or (col as Node).is_in_group("kill_zone")):
			return "hazard"
	return ""


func _is_moving_body(col: Variant) -> bool:
	if not (col is Node):
		return false
	var n := col as Node
	if n is AnimatableBody3D or n is RigidBody3D or n is CharacterBody3D:
		return true
	return n.is_in_group("moving_platform") or n.is_in_group("falling_platform") or n.is_in_group("vanishing_cloud") or n.is_in_group("rotating_platform")


func _floor_ray(space: PhysicsDirectSpaceState3D, p: Vector3) -> Dictionary:
	var rq := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, -1.0, 0), ObjSvc.L_WORLD)
	return space.intersect_ray(rq)


func _on_other_activated(other: Node) -> void:
	if other == self or not is_active:
		return
	is_active = false
	_sparkles.emitting = false
	_light.light_energy = 0.0
	if _ribbon_mat:
		_ribbon_mat.albedo_color = Color(0.35, 0.5, 0.78)
		_ribbon_mat.emission_enabled = false

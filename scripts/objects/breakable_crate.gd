class_name BreakableCrate
extends StaticBody3D
## A sturdy storybook crate (the generated Tripo P2 crate by default). Punch, kick, dive or Ham Slam it: it
## squashes, then bursts into its ten pre-fractured pieces (RigidBody3D debris thrown away from the hit), wood
## splinters and dust, and pops out acorns.
## Also sits on the enemy_hurtbox layer through its SlamSensor, so the player's attack calls hit_by_player().

signal broken(crate: Node)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var size: float = 1.0
@export var acorns: int = 3
@export var reward_truffle_id: String = ""
@export var break_kinds: PackedStringArray = PackedStringArray(["punch", "kick", "jump_kick", "dive", "slide", "slam"])
## Uses the generated crate (and its pre-fractured pieces for the debris) when no visual_scene is set.
@export var use_default_mesh: bool = true
@export var debris_lifetime: float = 2.4

const DEFAULT_MESH := "res://assets/props/pickups/breakable_crate/breakable_crate.glb"
const PIECES_MESH := "res://assets/props/pickups/breakable_crate/breakable_crate_pieces.glb"

var is_broken := false
var _visual: Node3D
var _sensor: SlamSensor
var _shape: CollisionShape3D
var _hit_from := Vector3.INF
var _hit_kind := ""


func _ready() -> void:
	add_to_group("breakable")
	collision_layer = ObjSvc.L_WORLD
	collision_mask = 0
	_shape = ObjSvc.add_shape(self, ObjSvc.box_shape(Vector3.ONE * size), Vector3(0, size * 0.5, 0))
	if visual_scene == null and use_default_mesh and ResourceLoader.exists(DEFAULT_MESH):
		visual_scene = load(DEFAULT_MESH) as PackedScene
		if is_equal_approx(visual_scale, 1.0):
			visual_scale = size
	_visual = ObjSvc.ensure_visual(self)
	if not ObjSvc.visual_has_content(_visual):
		_build_placeholder()
	else:
		ObjSvc.shadow_blob(self, size * 0.8, 0.015, 0.35)
	_sensor = SlamSensor.new()
	_sensor.name = "Hurtbox"
	_sensor.radius = size * 0.75
	_sensor.height = size * 1.4
	_sensor.position = Vector3(0, -0.1, 0)
	add_child(_sensor)
	_sensor.slammed.connect(func(_b: Node) -> void: smash())
	_sensor.struck.connect(_on_struck)


func _build_placeholder() -> void:
	var wood := ObjSvc.mat(Color(0.78, 0.55, 0.3), 0.75)
	var dark := ObjSvc.mat(Color(0.5, 0.32, 0.16), 0.8)
	var iron := ObjSvc.mat(ObjSvc.IRON, 0.4, 0.8)
	var s := size
	ObjSvc.soft_box(_visual, Vector3.ONE * s * 0.96, wood, Vector3(0, s * 0.5, 0), Vector3.ZERO, s * 0.05)
	# Frame edges and a diagonal brace on each face.
	for face in 4:
		var f := Node3D.new()
		f.rotation.y = face * PI * 0.5
		_visual.add_child(f)
		ObjSvc.box(f, Vector3(s * 0.12, s, s * 0.06), dark, Vector3(-s * 0.44, s * 0.5, s * 0.49))
		ObjSvc.box(f, Vector3(s, s * 0.12, s * 0.06), dark, Vector3(0, s * 0.06, s * 0.49))
		ObjSvc.box(f, Vector3(s, s * 0.12, s * 0.06), dark, Vector3(0, s * 0.94, s * 0.49))
		ObjSvc.box(f, Vector3(s * 1.15, s * 0.1, s * 0.05), dark, Vector3(0, s * 0.5, s * 0.5), Vector3(0, 0, 45))
		ObjSvc.sphere(f, s * 0.035, iron, Vector3(-s * 0.44, s * 0.9, s * 0.53))
		ObjSvc.sphere(f, s * 0.035, iron, Vector3(-s * 0.44, s * 0.1, s * 0.53))
	# A painted acorn stencil on top hints at what is inside.
	ObjSvc.sphere(_visual, s * 0.12, ObjSvc.mat(Color(0.85, 0.5, 0.2), 0.6), Vector3(0, s * 0.98, 0), Vector3(1, 0.1, 1.2))
	ObjSvc.shadow_blob(self, s * 0.8, 0.015, 0.35)


func _on_struck(kind: String, from: Vector3) -> void:
	if kind in break_kinds:
		_hit_from = from
		_hit_kind = kind
		smash()


func hit_by_player(kind: String, from_position: Vector3) -> bool:
	if kind in break_kinds:
		_hit_from = from_position
		_hit_kind = kind
		smash()
		return true
	return false


func smash() -> void:
	if is_broken:
		return
	is_broken = true
	_shape.set_deferred("disabled", true)
	collision_layer = 0
	_sensor.set_deferred("monitorable", false)
	var at := global_position + Vector3(0, size * 0.5, 0)
	if _hit_kind == "" and _sensor != null:
		_hit_kind = "slam"
	ObjSvc.feedback("object_crate_break", at, {"kind": _hit_kind, "size": size}, "crate_break")
	broken.emit(self)
	# Anticipation: two frames of squash before it bursts (collision is already off, so play is not held up).
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3(1.12, 0.84, 1.12), 0.05).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_burst)


func _burst() -> void:
	var parent := get_parent()
	var at := global_position + Vector3(0, size * 0.5, 0)
	var away := Vector3.ZERO
	if _hit_from != Vector3.INF and _hit_kind != "slam":
		away = at - _hit_from
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.ZERO
	if not ObjSvc.juice_handles("object_crate_break", "vfx"):
		ObjSvc.burst(parent, at, Color(0.8, 0.58, 0.32), 26, 6.0, 0.22, -16.0, 0.9)
		if not ObjSvc.fx(self, "CrumbBurst", at):
			ObjSvc.burst(parent, at, Color(1, 0.95, 0.85), 12, 2.0, 0.6, 0.5, 0.6)
		ObjSvc.fx(self, "DustPuff", global_position)
		ObjFx.puffs(parent, global_position + Vector3(0, 0.2, 0), Color(0.86, 0.74, 0.58, 0.8), 7, size * 1.1, size * 0.9, 0.8)
		ObjFx.flash(parent, at, size * 1.4, 2.0, Color(1.0, 0.9, 0.7, 0.6), 0.16)
	if not _spawn_piece_debris(parent, away):
		_spawn_plank_debris(parent, at)
	if acorns > 0:
		ObjSvc.spawn_acorns(parent, global_position, acorns)
	if reward_truffle_id != "":
		ObjSvc.spawn_truffle(parent, Transform3D(Basis(), global_position), reward_truffle_id, true)
	_visual.visible = false
	_drop_stacked()
	var t := create_tween()
	t.tween_interval(0.1)
	t.tween_callback(queue_free)


## Crates stacked on this one lose their support: they drop (gravity ease-in) and land with a squash.
func _drop_stacked() -> void:
	for n in get_tree().get_nodes_in_group("breakable"):
		var c := n as Node3D
		if c == null or c == self or not c.has_method("drop_by"):
			continue
		var d := c.global_position - global_position
		if d.y > size * 0.5 and d.y < size * 1.5 and Vector2(d.x, d.z).length() < size * 0.6:
			c.call("drop_by", size)


func drop_by(dist: float) -> void:
	if is_broken:
		return
	var t := sqrt(2.0 * dist / 22.0)
	var tw := create_tween()
	tw.tween_property(self, "global_position:y", global_position.y - dist, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if not ObjSvc.feedback_optional("object_crate_land", global_position, {"impact": dist}, "platform_fall"):
			ObjFx.puffs(get_parent(), global_position + Vector3(0, 0.1, 0), Color(0.86, 0.74, 0.58, 0.7), 6, size, size * 0.7, 0.6))
	tw.tween_property(_visual, "scale", Vector3(1.12, 0.86, 1.12), 0.06)
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_drop_stacked_later(dist)


func _drop_stacked_later(dist: float) -> void:
	# Anything stacked on this crate falls with it (it simply follows the same move next frame).
	for n in get_tree().get_nodes_in_group("breakable"):
		var c := n as Node3D
		if c == null or c == self or not c.has_method("drop_by"):
			continue
		var d := c.global_position - global_position
		if d.y > size * 0.5 and d.y < size * 1.5 and Vector2(d.x, d.z).length() < size * 0.6:
			c.call("drop_by", dist)


## The ten pre-fractured pieces (breakable_crate_pieces.glb) as short-lived RigidBody3D debris. They collide with
## the world only (never the player), tumble, settle and shrink away. Returns false without the GLB.
func _spawn_piece_debris(parent: Node, away: Vector3) -> bool:
	if not ResourceLoader.exists(PIECES_MESH):
		return false
	var ps := load(PIECES_MESH) as PackedScene
	if ps == null:
		return false
	var src := ps.instantiate() as Node3D
	var scl := size
	var base := Transform3D(global_basis.orthonormalized(), global_position)
	if visual_flip_180:
		base = base * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var centre := global_position + Vector3(0, size * 0.5, 0)
	for c in src.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var rb := RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = ObjSvc.L_WORLD
		rb.mass = 0.6
		rb.gravity_scale = 1.6
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.25
		pm.friction = 0.8
		rb.physics_material_override = pm
		var bb := mi.mesh.get_aabb()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = (bb.size * scl).max(Vector3.ONE * 0.05)
		cs.shape = bs
		cs.position = bb.get_center() * scl
		rb.add_child(cs)
		var m2 := MeshInstance3D.new()
		m2.mesh = mi.mesh
		m2.scale = Vector3.ONE * scl
		m2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		rb.add_child(m2)
		parent.add_child(rb)
		rb.global_transform = base * Transform3D(Basis(), mi.position * scl)
		var out := rb.global_position - centre
		out.y = 0.0
		out = out.normalized() if out.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		# Critique objects r1: pieces flew 4 m+ (one at the camera) and big panels littered the floor for 3 s.
		# About 30 % less impulse, and every piece shrinks away from 1.2 s to zero by 1.8 s.
		var v := (out * randf_range(2.2, 4.0) + away * randf_range(2.5, 4.5) + Vector3(0, randf_range(3.5, 6.0), 0)) * 0.7
		if mi.name.begins_with("Panel_pz"):
			v.y += 1.4  # the lid flies highest
		rb.linear_velocity = v
		rb.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
		var life := minf(debris_lifetime, 1.2) + randf() * 0.1
		var tw := rb.create_tween()
		tw.tween_interval(life)
		tw.tween_property(m2, "scale", Vector3.ONE * 0.01, 1.8 - life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(rb.queue_free)
	src.free()
	return true


func _spawn_plank_debris(parent: Node, at: Vector3) -> void:
	# Planks fly apart (placeholder look without the pieces GLB).
	for i in 6:
		var plank := Node3D.new()
		parent.add_child(plank)
		plank.global_position = at
		ObjSvc.box(plank, Vector3(size * 0.7, size * 0.1, size * 0.22), ObjSvc.mat(Color(0.78, 0.55, 0.3), 0.75))
		var dir := Vector3(cos(i * 1.05), 0.0, sin(i * 1.05))
		var tw := plank.create_tween().set_parallel()
		tw.tween_property(plank, "global_position", at + dir * randf_range(1.2, 2.2) + Vector3(0, randf_range(0.8, 1.6), 0), 0.25).set_ease(Tween.EASE_OUT)
		tw.tween_property(plank, "rotation", Vector3(randf() * 6.0, randf() * 6.0, randf() * 6.0), 0.6)
		tw.chain().tween_property(plank, "global_position:y", at.y - size * 0.5, 0.35).set_ease(Tween.EASE_IN)
		tw.chain().tween_property(plank, "scale", Vector3.ONE * 0.01, 0.3).set_delay(0.6)
		tw.chain().tween_callback(plank.queue_free)

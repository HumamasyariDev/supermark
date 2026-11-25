class_name BossChimney
extends StaticBody3D
## A brick chimney on the wolf's rooftop, built from the accepted Tripo P2 meshes (BOSS_amendments R3.2):
## intact `boss_chimney.glb` at visual scale (1.28, 1.0, 1.28) and `boss_chimney_broken.glb` for the stump.
## Collision (layer 1, group `chimney` for the gust shelter ray and `boss_chimney` for the charge):
##   intact: plinth 3.2 x 1.2 x 3.2, stack 2.2 x 2.2 x 2.2 (y 1.2-3.4), crown 2.3 x 1.0 x 2.3 (y 3.4-4.4; R3.2 says 2.7,
##   narrowed so Mak (r 0.35) can stand on the plinth's front strip and jump straight up at the cork belly)
##   broken: plinth 2.8 x 1.0 x 2.8, stump 1.9 x 2.4 x 1.9 (still stops a charge).

const INTACT := "res://assets/props/boss/boss_chimney/boss_chimney.glb"
const BROKEN := "res://assets/props/boss/boss_chimney_broken/boss_chimney_broken.glb"
const VIS_SCALE := Vector3(1.28, 1.0, 1.28)
const BRICK := Color(0.64, 0.27, 0.18)
const SOOT := Color(0.12, 0.1, 0.1)

## Kept for older look-dev scripts (graybox size).
@export var size: Vector3 = Vector3(3.2, 4.4, 3.2)
@export var label: String = "C1"
## Mesh yaw inside the body (variants: C1 0, C2 90, C3 180, C4 270).
@export var mesh_yaw_deg: float = 0.0

var smashed: bool = false
var cracked: bool = false
var _intact_vis: Node3D
var _broken_vis: Node3D
var _intact_shapes: Array[CollisionShape3D] = []
var _broken_shapes: Array[CollisionShape3D] = []
var _smoke: Array[Node3D] = []
var _soot: CPUParticles3D
var _hearth: MeshInstance3D
var _crack: MeshInstance3D


func _ready() -> void:
	add_to_group("boss_chimney")
	add_to_group("chimney")
	collision_layer = 1
	collision_mask = 0
	_intact_shapes.append(_box(Vector3(3.2, 1.2, 3.2), 0.6))
	_intact_shapes.append(_box(Vector3(2.2, 2.2, 2.2), 2.3))
	_intact_shapes.append(_box(Vector3(2.3, 1.0, 2.3), 3.9))
	_broken_shapes.append(_box(Vector3(2.8, 1.0, 2.8), 0.5))
	_broken_shapes.append(_box(Vector3(1.9, 2.4, 1.9), 1.2))
	for s in _broken_shapes:
		s.disabled = true
	_intact_vis = _mesh(INTACT)
	_broken_vis = _mesh(BROKEN)
	_broken_vis.visible = false
	# Smoke from both pots (sockets carried by the GLB, scaled with it).
	for sock_name in ["smoke_socket_a", "smoke_socket_b"]:
		var sock := _intact_vis.find_child(sock_name, true, false) as Node3D
		var at := Vector3(0, 5.4, 0)
		if sock != null:
			at = to_local(sock.global_position) if is_inside_tree() else Vector3(0, 5.4, 0)
		var sm := _make_smoke()
		sm.position = at
		add_child(sm)
		_smoke.append(sm)
	_soot = _make_soot()
	_soot.position = Vector3(0, 5.3, 0)
	add_child(_soot)


func _box(sz: Vector3, cy: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = sz
	cs.shape = b
	cs.position = Vector3(0, cy, 0)
	add_child(cs)
	return cs


func _mesh(path: String) -> Node3D:
	var holder := Node3D.new()
	holder.rotation_degrees.y = 180.0 + mesh_yaw_deg
	holder.scale = VIS_SCALE
	add_child(holder)
	if ResourceLoader.exists(path):
		holder.add_child((load(path) as PackedScene).instantiate())
	else:
		EnemyKit.box(holder, Vector3(2.5, 4.4, 2.5), BRICK, Vector3(0, 2.2, 0))
	return holder


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 3.2
	p.direction = Vector3(0.25, 1, 0)
	p.spread = 12.0
	p.initial_velocity_min = 0.9
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0.9, 0.25, 0.3)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.9
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(0.4, 1.0))
	c.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.5, 0.55, 0.55))
	g.set_color(1, Color(0.4, 0.36, 0.45, 0.0))
	p.color_ramp = g
	var q := SphereMesh.new()
	q.radius = 0.35
	q.height = 0.7
	q.radial_segments = 8
	q.rings = 4
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = m
	p.emitting = true
	return p


func _make_soot() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 1.6
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -0.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(0.08, 0.07, 0.07, 0.9))
	g.set_color(1, Color(0.15, 0.13, 0.13, 0.0))
	p.color_ramp = g
	var q := SphereMesh.new()
	q.radius = 0.4
	q.height = 0.8
	q.radial_segments = 8
	q.rings = 4
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	return p


func is_intact() -> bool:
	return not smashed


## Top of the collision (crown 4.4 intact, stump 2.4 broken).
func top_y() -> float:
	return global_position.y + (2.4 if smashed else 4.4)


## Half extent of the charge-stopping footprint (stack for intact, stump for broken), in the body's frame.
func charge_half() -> float:
	return 1.35 if not smashed else 0.95


## True if a world point (y ignored) is inside the footprint grown by margin.
func footprint_has(p: Vector3, half: float, margin: float = 0.0) -> bool:
	var l := to_local(Vector3(p.x, global_position.y, p.z))
	return absf(l.x) <= half + margin and absf(l.z) <= half + margin


## The wolf hits it head-first: bricks fly, it stays standing (the tail slam finishes it).
func crack(from_dir: Vector3) -> void:
	cracked = true
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 2.2, 0) - from_dir * 1.2, "rubble", [BRICK, BRICK.darkened(0.3), Color(0.85, 0.75, 0.6)], 26, 7.0)
	EnemyKit.poof(get_parent(), global_position + Vector3(0, 2.0, 0) - from_dir * 1.3, 1.6, Color(0.8, 0.7, 0.65))
	if not smashed:
		var tw := create_tween()
		tw.tween_property(_intact_vis, "rotation_degrees:z", 2.5, 0.06)
		tw.tween_property(_intact_vis, "rotation_degrees:z", -1.5, 0.08)
		tw.tween_property(_intact_vis, "rotation_degrees:z", 0.0, 0.12)


func smash() -> void:
	if smashed:
		return
	smashed = true
	_intact_vis.visible = false
	_broken_vis.visible = true
	for s in _intact_shapes:
		s.set_deferred("disabled", true)
	for s in _broken_shapes:
		s.set_deferred("disabled", false)
	for sm in _smoke:
		sm.visible = false
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 3.0, 0), "rubble", [BRICK, BRICK.darkened(0.3), Color(0.85, 0.75, 0.6)], 46, 9.0)
	EnemyKit.poof(get_parent(), global_position + Vector3(0, 2.5, 0), 3.2, Color(0.78, 0.68, 0.62))
	EnemyKit.sfx(self, "chimney_crash", global_position)
	# The stump settles with a little bounce.
	_broken_vis.scale = VIS_SCALE * Vector3(1.0, 1.25, 1.0)
	create_tween().tween_property(_broken_vis, "scale", VIS_SCALE, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func restore() -> void:
	smashed = false
	cracked = false
	_intact_vis.visible = true
	_broken_vis.visible = false
	for s in _intact_shapes:
		s.set_deferred("disabled", false)
	for s in _broken_shapes:
		s.set_deferred("disabled", true)
	for sm in _smoke:
		sm.visible = true


## Black soot from the pots (Chimney Sweep tell, cork pop).
func belch(seconds: float = 1.0) -> void:
	if smashed:
		return
	_soot.restart()
	_soot.emitting = true
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(_soot):
			_soot.emitting = false)

extends Node3D
## W3 biscuit lane: digestive biscuits (AnimatableBody3D) drift along a polyline on the hot chocolate.
## A biscuit dips 0.15 m when stood on, sags 0.4 m after `sag_after` s of continuous standing and sinks
## at `sink_after` s; at the lane end it sinks over 1.5 s. Plan: Docs/levels/W3.md 3.5 and section 5.

@export var points: PackedVector3Array = PackedVector3Array()   # world positions (y = biscuit centre)
@export var speed := 1.4
@export var interval := 3.4
@export var offset := 0.0
@export var radius := 1.3
@export var thickness := 0.3
@export var sag_after := 3.0
@export var sink_after := 4.5
@export var biscuit_mesh: Mesh
@export var biscuit_material: Material
@export var mesh_offset := Vector3.ZERO
@export var mesh_scale := Vector3.ONE

var _length := 0.0
var _cum := PackedFloat32Array()
var _timer := 0.0
var _biscuits: Array[Dictionary] = []


func _ready() -> void:
	_cum.append(0.0)
	for i in points.size() - 1:
		_length += points[i].distance_to(points[i + 1])
		_cum.append(_length)
	# Pre-populate so the lane is already busy when the world loads.
	var gap := speed * interval
	var d := fposmod(-offset * speed, gap)
	while d < _length - 0.5:
		_spawn(d)
		d += gap
	_timer = fposmod(offset, interval)
	#print("[W3] biscuit lane %s: length %.1f m, %d biscuits" % [name, _length, _biscuits.size()])


func _pos_at(d: float) -> Vector3:
	d = clampf(d, 0.0, _length)
	for i in points.size() - 1:
		if d <= _cum[i + 1] or i == points.size() - 2:
			var seg := _cum[i + 1] - _cum[i]
			var t := 0.0 if seg <= 0.0 else (d - _cum[i]) / seg
			return points[i].lerp(points[i + 1], clampf(t, 0.0, 1.0))
	return points[points.size() - 1]


func _spawn(d: float) -> void:
	var body := AnimatableBody3D.new()
	body.name = "Biscuit"
	# sync_to_physics would ignore the per-frame transform writes below (they stay at the origin under Jolt).
	body.sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = thickness
	cs.shape = cyl
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = biscuit_mesh
	if biscuit_material:
		mi.material_override = biscuit_material
	mi.rotation_degrees.y = randf() * 360.0
	mi.position = mesh_offset
	mi.scale = mesh_scale
	body.add_child(mi)
	var sensor := Area3D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = 2
	sensor.monitorable = false
	var ss := CollisionShape3D.new()
	var sc := CylinderShape3D.new()
	sc.radius = radius * 0.95
	sc.height = 0.5
	ss.shape = sc
	ss.position.y = thickness * 0.5 + 0.25
	sensor.add_child(ss)
	body.add_child(sensor)
	add_child(body)
	body.global_position = _pos_at(d)
	body.reset_physics_interpolation()

	_biscuits.append({"body": body, "sensor": sensor, "d": d, "stood": 0.0, "sink": 0.0, "dip": 0.0, "end": 0.0, "spin": randf_range(-8.0, 8.0)})


func _physics_process(delta: float) -> void:
	_timer += delta
	if _timer >= interval:
		_timer -= interval
		_spawn(0.0)
	var dead: Array[Dictionary] = []
	for b in _biscuits:
		var body: AnimatableBody3D = b["body"]
		if not is_instance_valid(body):
			dead.append(b)
			continue
		b["d"] = float(b["d"]) + speed * delta
		var standing := false
		var sensor: Area3D = b["sensor"]
		for o in sensor.get_overlapping_bodies():
			if o.is_in_group("player"):
				standing = true
		if standing:
			b["stood"] = float(b["stood"]) + delta
		else:
			b["stood"] = maxf(0.0, float(b["stood"]) - delta * 2.0)
		var stood: float = b["stood"]
		var target_dip := 0.0
		if standing:
			target_dip = 0.15
		if stood > sag_after:
			target_dip = 0.4
		if stood > sink_after:
			b["sink"] = float(b["sink"]) + delta * 1.2
		b["dip"] = move_toward(float(b["dip"]), target_dip, delta * 1.0)
		if float(b["d"]) >= _length:
			b["end"] = float(b["end"]) + delta / 1.5
		var sink := float(b["sink"]) + float(b["end"]) * 1.2
		var p := _pos_at(float(b["d"]))
		p.y -= float(b["dip"]) + sink + sin(float(b["d"]) * 1.3) * 0.03
		body.global_position = p

		body.rotation_degrees.y += float(b["spin"]) * delta
		body.rotation_degrees.z = sin(float(b["d"]) * 0.9) * 1.5
		if sink > 1.2:
			body.queue_free()
			dead.append(b)
	for b in dead:
		_biscuits.erase(b)

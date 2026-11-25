class_name WindZone
extends Area3D
## Gust volume (group "wind_zone"). The player sums get_wind(position) from overlapping zones each physics frame.
## Wind blows along local `direction` (default local -Z). STEADY or PULSING; strength fades near the far end.
## Swirling streak particles show the flow. Toggle with set_enabled(); BellowsMachine drives `drive` (0..1).

signal toggled(on: bool)

enum Mode { STEADY, PULSING }

@export var size: Vector3 = Vector3(4, 4, 10)
@export var direction: Vector3 = Vector3(0, 0, -1)
@export var strength: float = 9.0
@export var mode: Mode = Mode.STEADY
@export var pulse_period: float = 2.4
@export_range(0.0, 1.0) var pulse_duty: float = 0.55
@export var enabled: bool = true
## Fraction of the zone length over which wind fades out at the far end.
@export_range(0.0, 1.0) var end_falloff: float = 0.3
@export var show_particles: bool = true
@export var streak_color: Color = Color(1, 1, 1, 0.55)
## Adds the vfx workstream's GustSwirl ribbons (res://scenes/fx/GustSwirl.tscn) when it exists.
@export var use_gust_swirl: bool = true

## Calm pockets inside the volume (local-space AABBs): no wind there. For a gust lane that overlaps a house or a
## ledge the builder wants calm (W1 feel critic request "WindZone exclusion AABBs").
@export var calm_boxes: Array[AABB] = []
## Wind shadow (opt-in): physics layers that block the gust. A point whose upwind line to the zone's entry face hits
## one of these bodies is sheltered (wind times `shelter_factor`), so hiding behind a wall, a house or a crate works.
## 0 = off (the default: currents along uneven river beds must not be blocked by their own banks).
@export_flags_3d_physics var shelter_mask: int = 0
@export_range(0.0, 1.0) var shelter_factor: float = 0.0

## External multiplier (bellows pumping sets this each frame). 1 = full.
var drive: float = 1.0
var _t := 0.0
var _particles: GPUParticles3D
var _swirl: GPUParticles3D


func _ready() -> void:
	add_to_group("wind_zone")
	# Critique objects r1: a world's culling pass process-disabled the W1 stream currents, and a disabled
	# CollisionObject3D leaves the physics space by default, so the current never pushed Mak. Keep the volume active.
	disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	collision_layer = ObjSvc.L_TRIGGER
	collision_mask = ObjSvc.L_PLAYER
	monitorable = true
	monitoring = true
	ObjSvc.add_shape(self, ObjSvc.box_shape(size))
	if show_particles:
		_build_particles()
	if use_gust_swirl:
		_add_gust_swirl()
	_apply_enabled()


func _build_particles() -> void:
	var dir := direction.normalized()
	var len_along := absf(size.dot(dir.abs())) if dir != Vector3.ZERO else size.z
	var speed := maxf(strength, 4.0)
	_particles = GPUParticles3D.new()
	_particles.name = "Streaks"
	_particles.amount = int(clampf(size.x * size.y * size.z * 0.35, 24, 160))
	_particles.lifetime = len_along / speed
	_particles.preprocess = _particles.lifetime
	_particles.local_coords = true
	_particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = (size * 0.5) * (Vector3.ONE - dir.abs()) + dir.abs() * 0.2
	pm.direction = dir
	pm.spread = 4.0
	pm.initial_velocity_min = speed * 0.8
	pm.initial_velocity_max = speed * 1.2
	pm.gravity = Vector3.ZERO
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.2, 1))
	curve.add_point(Vector2(0.8, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.color = streak_color
	_particles.process_material = pm
	_particles.position = -dir * len_along * 0.5
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 1.4)
	var m := ObjSvc.unshaded(Color.WHITE, true)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	m.albedo_texture = gt
	m.vertex_color_use_as_albedo = true
	q.material = m
	_particles.draw_pass_1 = q
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_particles)
	# Soft swirl puffs that tumble along with the gust.
	_swirl = ObjSvc.sparkles(self, Color(1, 1, 1, 0.35), int(clampf(size.x * size.y * 0.6, 6, 40)), minf(size.x, size.y) * 0.4, 0.5, len_along / (speed * 0.6), speed * 0.6)
	var spm := _swirl.process_material as ParticleProcessMaterial
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spm.emission_box_extents = pm.emission_box_extents
	spm.direction = dir
	spm.spread = 10.0
	spm.turbulence_enabled = true
	spm.turbulence_noise_strength = 3.0
	spm.turbulence_influence_min = 0.2
	spm.turbulence_influence_max = 0.4
	(_swirl.draw_pass_1 as QuadMesh).material = ObjSvc.sparkle_mat(Color.WHITE)
	_swirl.position = _particles.position
	_swirl.preprocess = _swirl.lifetime


var _gust: Node3D


func _add_gust_swirl() -> void:
	var path := "res://scenes/fx/GustSwirl.tscn"
	if not ResourceLoader.exists(path):
		return
	var ps := load(path) as PackedScene
	if ps == null:
		return
	_gust = ps.instantiate() as Node3D
	if _gust == null:
		return
	var dir := direction.normalized()
	var len_along := absf(size.dot(dir.abs()))
	var cross := (size - dir.abs() * len_along)
	if "length" in _gust:
		_gust.set("length", len_along)
	if "radius" in _gust:
		_gust.set("radius", clampf(minf(maxf(cross.x, cross.y), maxf(cross.y, cross.z)) * 0.3, 0.5, 3.0))
	add_child(_gust)
	# GustSwirl flows along its -Z; start it at the upwind end.
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	_gust.transform = Transform3D(Basis.looking_at(dir, up), -dir * len_along * 0.5)


func set_enabled(on: bool) -> void:
	if enabled == on:
		return
	enabled = on
	_apply_enabled()
	toggled.emit(on)


func _apply_enabled() -> void:
	if _particles:
		_particles.emitting = enabled
	if _swirl:
		_swirl.emitting = enabled
	if _gust and _gust.has_method("set_active"):
		_gust.call("set_active", enabled)


func pulse_factor() -> float:
	if mode == Mode.STEADY:
		return 1.0
	var ph := fposmod(_t / maxf(pulse_period, 0.05), 1.0)
	if ph > pulse_duty:
		return 0.0
	# Smooth on/off ramp inside the active part of the cycle.
	return sin(ph / pulse_duty * PI)


func _physics_process(delta: float) -> void:
	_t += delta
	if _particles and enabled:
		var on := pulse_factor() * drive > 0.15
		if _particles.emitting != on:
			_particles.emitting = on
			if _swirl:
				_swirl.emitting = on
			if _gust and _gust.has_method("set_active"):
				_gust.call("set_active", on)
		_particles.speed_scale = clampf(0.4 + drive * 0.6, 0.2, 1.5)


## Wind velocity (m/s, world space) at a world position. Zero outside the box or when disabled.
func get_wind(at: Vector3) -> Vector3:
	if not enabled:
		return Vector3.ZERO
	var local := global_transform.affine_inverse() * at
	var half := size * 0.5
	if absf(local.x) > half.x or absf(local.y) > half.y or absf(local.z) > half.z:
		return Vector3.ZERO
	var dir := direction.normalized()
	var along := local.dot(dir)
	var half_len := absf(half.dot(dir.abs()))
	var t := (along + half_len) / maxf(half_len * 2.0, 0.01)
	var fall := 1.0
	if end_falloff > 0.0 and t > 1.0 - end_falloff:
		fall = clampf((1.0 - t) / end_falloff, 0.0, 1.0)
	if fall <= 0.0 or _in_calm_box(local):
		return Vector3.ZERO
	var k := shelter_factor if _is_sheltered(at, along, half_len, dir) else 1.0
	return (global_transform.basis * dir).normalized() * strength * pulse_factor() * drive * fall * k


func _in_calm_box(local: Vector3) -> bool:
	for b in calm_boxes:
		if (b as AABB).has_point(local):
			return true
	return false


## True (with `shelter_mask`) when a blocking body stands between `at` and the zone's entry face upwind. Very short
## lines (< 0.3 m) never count.
func _is_sheltered(at: Vector3, along: float, half_len: float, dir: Vector3) -> bool:
	if shelter_mask == 0 or not is_inside_tree():
		return false
	var back := along + half_len
	if back < 0.3:
		return false
	var wdir := (global_transform.basis * dir).normalized()
	var q := PhysicsRayQueryParameters3D.create(at, at - wdir * back, shelter_mask)
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var col: Object = hit.get("collider")
	if col is Node and ((col as Node).is_in_group("player") or (col as Node).is_in_group("no_wind_shelter")):
		return false
	return true


## Strongest wind this zone can blow at a position (ignores pulses, bellows drive and a temporary disable).
## Checkpoints use it to keep respawn spots out of gust lanes.
func get_peak_wind(at: Vector3) -> Vector3:
	var local := global_transform.affine_inverse() * at
	var half := size * 0.5
	if absf(local.x) > half.x or absf(local.y) > half.y or absf(local.z) > half.z:
		return Vector3.ZERO
	var dir := direction.normalized()
	var along := local.dot(dir)
	var half_len := absf(half.dot(dir.abs()))
	var t := (along + half_len) / maxf(half_len * 2.0, 0.01)
	var fall := 1.0
	if end_falloff > 0.0 and t > 1.0 - end_falloff:
		fall = clampf((1.0 - t) / end_falloff, 0.0, 1.0)
	if fall <= 0.0 or _in_calm_box(local):
		return Vector3.ZERO
	var k := shelter_factor if _is_sheltered(at, along, half_len, dir) else 1.0
	return (global_transform.basis * dir).normalized() * strength * fall * k

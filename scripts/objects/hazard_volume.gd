class_name HazardVolume
extends Area3D
## Damage volume (group "hazard", meta damage, meta knockback_up). The player reads the metas on overlap.
## PLAIN is invisible (for thorns or steam vents with their own art); HOT_CHOCOLATE draws a glossy, bubbling,
## steaming chocolate surface on top of the box (W3 river).

enum Look { PLAIN, HOT_CHOCOLATE, THORNS }

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var size: Vector3 = Vector3(6, 1, 6)
@export var damage: int = 1
@export var knockback_up: float = 9.0
@export var look: Look = Look.PLAIN
## Fallback only: hurt the player directly (leave off when the player handles "hazard" itself).
@export var apply_damage_directly: bool = false
@export var repeat_interval: float = 1.0
## Shared vfx material for the chocolate surface (hot_chocolate_river or hot_chocolate_pool); placeholder if missing.
@export var chocolate_material: String = "hot_chocolate_river"

var _t := 0.0
var _surface: MeshInstance3D
var _bubbles: Array[Node3D] = []
var _cool: Dictionary = {}


func _ready() -> void:
	add_to_group("hazard")
	set_meta("damage", damage)
	set_meta("knockback_up", knockback_up)
	collision_layer = ObjSvc.L_HAZARD
	collision_mask = ObjSvc.L_PLAYER
	monitorable = true
	ObjSvc.add_shape(self, ObjSvc.box_shape(size))
	var visual := ObjSvc.ensure_visual(self)
	if not ObjSvc.visual_has_content(visual):
		match look:
			Look.HOT_CHOCOLATE:
				_build_chocolate(visual)
			Look.THORNS:
				_build_thorns(visual)
	body_entered.connect(_on_body)


func _build_chocolate(v: Node3D) -> void:
	# Rough enough not to mirror the blue sky (a glossy flat plane turned mauve); the motion sells the liquid.
	var choc := ObjSvc.unique_mat(Color(0.36, 0.17, 0.06), 0.6, 0.0, Color(0.4, 0.14, 0.03), 0.15)
	choc.metallic_specular = 0.2
	choc.rim_enabled = false
	var pm := PlaneMesh.new()
	pm.size = Vector2(size.x, size.z)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	var shared := ObjSvc.vfx_material(chocolate_material, true)
	_surface = ObjSvc.add_mesh(v, pm, shared if shared != null else choc, Vector3(0, size.y * 0.5 - 0.05, 0))
	if shared is ShaderMaterial:
		# Flow along the longer side; river foam runs along the UV.y edges.
		(shared as ShaderMaterial).set_shader_parameter("flow_direction", Vector2(1.0, 0.15) if size.x >= size.z else Vector2(0.15, 1.0))
	# Darker body so the volume reads as deep liquid from the side.
	ObjSvc.box(v, Vector3(size.x, size.y - 0.1, size.z), ObjSvc.mat(Color(0.28, 0.13, 0.05), 0.6), Vector3(0, -0.05, 0))
	if shared is ShaderMaterial:
		# The shared shader already paints swirls, foam and bubble rings; add only steam.
		_add_steam(v)
		return
	# Cream swirls floating on top.
	var cream := ObjSvc.mat(Color(0.95, 0.85, 0.7), 0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var n := int(clampf(size.x * size.z / 6.0, 3, 24))
	for i in n:
		var b := Node3D.new()
		b.position = Vector3(rng.randf_range(-0.45, 0.45) * size.x, size.y * 0.5 - 0.04, rng.randf_range(-0.45, 0.45) * size.z)
		v.add_child(b)
		if i % 3 == 0:
			ObjSvc.torus(b, 0.15, 0.25, cream, Vector3.ZERO).scale = Vector3(1, 0.3, 1)
		else:
			ObjSvc.sphere(b, rng.randf_range(0.08, 0.16), ObjSvc.mat(Color(0.5, 0.25, 0.1), 0.3), Vector3.ZERO, Vector3(1, 0.6, 1))
		_bubbles.append(b)
	_add_steam(v)


func _add_steam(v: Node3D) -> void:
	var steam := ObjSvc.sparkles(v, Color(1, 1, 1, 0.14), int(clampf(size.x * size.z / 3.0, 6, 40)), 0.5, 0.8, 2.5, 0.6)
	var spm := steam.process_material as ParticleProcessMaterial
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spm.emission_box_extents = Vector3(size.x * 0.45, 0.05, size.z * 0.45)
	spm.turbulence_enabled = true
	steam.position = Vector3(0, size.y * 0.5 + 0.5, 0)
	steam.amount = maxi(4, steam.amount / 2)
	(steam.draw_pass_1 as QuadMesh).material = ObjSvc.sparkle_mat(Color.WHITE)


func _build_thorns(v: Node3D) -> void:
	var stem := ObjSvc.mat(Color(0.35, 0.25, 0.15), 0.8)
	var spike := ObjSvc.mat(ObjSvc.HAZARD_RED, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := int(clampf(size.x * size.z * 1.5, 4, 60))
	for i in n:
		var p := Vector3(rng.randf_range(-0.45, 0.45) * size.x, -size.y * 0.5, rng.randf_range(-0.45, 0.45) * size.z)
		ObjSvc.cylinder(v, 0.04, 0.08, size.y * 0.8, stem, p + Vector3(0, size.y * 0.4, 0), Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)))
		ObjSvc.cone(v, 0.07, 0.25, spike, p + Vector3(0, size.y * 0.85, 0))


func _process(delta: float) -> void:
	_t += delta
	for i in _bubbles.size():
		var b := _bubbles[i]
		b.position.y = size.y * 0.5 - 0.04 + sin(_t * 2.0 + i) * 0.03
		b.rotation.y += delta * (0.3 + 0.1 * float(i % 3))
		var s := 1.0 + 0.25 * sin(_t * 3.0 + i * 1.7)
		b.scale = Vector3(s, 1.0, s)
	if _surface and _surface.material_override is StandardMaterial3D:
		var m := _surface.material_override as StandardMaterial3D
		m.uv1_offset = Vector3(_t * 0.03, _t * 0.02, 0)


func _on_body(body: Node) -> void:
	if not apply_damage_directly or not ObjSvc.is_player(body):
		return
	_hurt(body)


func _physics_process(delta: float) -> void:
	if not apply_damage_directly:
		return
	for k in _cool.keys():
		_cool[k] = float(_cool[k]) - delta
	for b in get_overlapping_bodies():
		if ObjSvc.is_player(b) and float(_cool.get(b.get_instance_id(), 0.0)) <= 0.0:
			_hurt(b)


func _hurt(body: Node) -> void:
	_cool[body.get_instance_id()] = repeat_interval
	if body.has_method("take_damage"):
		body.call("take_damage", damage, global_position)
	if body.has_method("bounce") and knockback_up > 0.0:
		body.call("bounce", knockback_up)
	ObjSvc.feedback("world_cocoa_burn" if look == Look.HOT_CHOCOLATE else "object_hazard_touch", (body as Node3D).global_position, {"look": str(look)}, "hazard_hit")

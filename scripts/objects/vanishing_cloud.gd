class_name VanishingCloud
extends AnimatableBody3D
## A puffy cloud platform: about one second after the player lands it trembles, fades and puffs away,
## then drifts back after respawn_time.

signal vanished
signal returned

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var size: Vector3 = Vector3(3.0, 0.9, 3.0)
@export var vanish_delay: float = 1.0
@export var respawn_time: float = 3.0
@export var drift_amplitude: float = 0.15
## Shortest warning before a touched cloud vanishes (critique objects r1: a readable 0.6 s tell).
@export var min_tell: float = 0.6

enum State { IDLE, ARMED, GONE }
var state: State = State.IDLE
var _timer := 0.0
var _t := 0.0
var _home: Transform3D
var _home_set := false
var _ticks := 0
var _visual: Node3D
var _shape: CollisionShape3D
var _cloud_mat: ShaderMaterial
var _wisp_t := 0.0


func _ready() -> void:
	add_to_group("vanishing_cloud")
	# Enabled on the first physics tick, so a spawner may still move it right after add_child.
	sync_to_physics = false
	collision_layer = ObjSvc.L_WORLD
	collision_mask = 0
	_shape = ObjSvc.add_shape(self, ObjSvc.box_shape(Vector3(size.x * 0.85, size.y * 0.5, size.z * 0.85)), Vector3(0, -size.y * 0.25, 0))
	_visual = ObjSvc.ensure_visual(self)
	if not ObjSvc.visual_has_content(_visual):
		PlatformLook.build(_visual, size, PlatformLook.Kind.CLOUD)
		_cloud_mat = ObjSvc.vfx_material("cloud_platform", true) as ShaderMaterial
		if _cloud_mat:
			# Critique objects r1: safe ground was white on the white cloud sea. Lavender underside, a warm-gold
			# rim on top and a darker base ring give the platform an edge and depth from the gameplay camera.
			_cloud_mat.set_shader_parameter("shade_color", Color(0.6, 0.5, 0.88))
			_cloud_mat.set_shader_parameter("rim_color", Color(1.0, 0.74, 0.32))
			_cloud_mat.set_shader_parameter("rim_strength", 0.75)
			for mi in _visual.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = _cloud_mat
		_add_base_ring()
	var sensor := ObjSvc.make_area(self, ObjSvc.box_shape(Vector3(size.x * 0.85, 0.5, size.z * 0.85)), ObjSvc.L_TRIGGER, ObjSvc.L_PLAYER, Vector3(0, 0.25, 0), "Sensor")
	sensor.body_entered.connect(_on_sensor)
	_home = global_transform
	_t = randf() * TAU


## A soft lavender-grey halo just under the cloud's belly: reads as the platform's edge and contact shadow.
func _add_base_ring() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(size.x * 1.25, size.z * 1.25)
	q.orientation = PlaneMesh.FACE_Y
	var m := ObjSvc.unshaded(Color(1, 1, 1, 1))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = ObjSvc.radial_tex(Color(0.36, 0.3, 0.58, 0.75), Color(0.5, 0.44, 0.76, 0.0), 64)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = -1
	var mi := ObjSvc.add_mesh(_visual, q, m, Vector3(0, -size.y * 0.42, 0))
	mi.name = "BaseRing"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _on_sensor(body: Node) -> void:
	if state == State.IDLE and ObjSvc.is_player(body):
		state = State.ARMED
		_timer = 0.0
		ObjSvc.feedback("object_cloud_step", global_position, {}, "cloud_squish")
		var tw := create_tween()
		tw.tween_property(_visual, "scale", Vector3(1.12, 0.8, 1.12), 0.1)
		tw.tween_property(_visual, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	if not _home_set:
		# Captured on the second tick (a spawner may move it right after add_child, even inside a physics
		# step); sync_to_physics is switched on only then, otherwise Jolt keeps the stale spawn transform.
		_ticks += 1
		if _ticks < 2:
			return
		_home = global_transform
		_home_set = true
		sync_to_physics = true
	_t += delta
	_timer += delta
	match state:
		State.IDLE:
			global_transform = Transform3D(_home.basis, _home.origin + Vector3(0, sin(_t * 1.1) * drift_amplitude, 0))
		State.ARMED:
			# The tell: a growing tremble, the cloud thins and sags, and wisps shed from its edge.
			var delay := maxf(vanish_delay, min_tell)
			var k := clampf(_timer / delay, 0.0, 1.0)
			_visual.position = Vector3(sin(_timer * 50.0), -0.06 * k, cos(_timer * 43.0)) * Vector3(0.05 * k, 1.0, 0.05 * k)
			if _timer > 0.42:
				_visual.scale = Vector3(1.0 + 0.04 * k, 1.0 - 0.18 * k, 1.0 + 0.04 * k)
			if _cloud_mat:
				_cloud_mat.set_shader_parameter("dissolve", 0.22 * k * k)
			_wisp_t -= delta
			if _wisp_t <= 0.0:
				_wisp_t = 0.12
				var a := randf() * TAU
				var at := global_position + Vector3(cos(a) * size.x * 0.45, -size.y * 0.1, sin(a) * size.z * 0.45)
				ObjFx.puffs(get_parent(), at, Color(1.0, 1.0, 1.0, 0.65), 1, 0.15, 0.35 + 0.2 * k, 0.5)
			if _timer >= delay:
				_vanish()
		State.GONE:
			if _timer >= respawn_time:
				_return()


func _vanish() -> void:
	state = State.GONE
	_timer = 0.0
	_shape.set_deferred("disabled", true)
	vanished.emit()
	ObjSvc.feedback("object_cloud_vanish", global_position, {}, "cloud_puff")
	if not ObjSvc.juice_handles("object_cloud_vanish", "vfx"):
		ObjSvc.burst(get_parent(), global_position, Color(1, 1, 1), 30, 3.0, 0.6, 0.5, 0.9)
	var tw := create_tween()
	if _cloud_mat:
		tw.tween_method(func(v: float) -> void: _cloud_mat.set_shader_parameter("dissolve", v), 0.22, 1.0, 0.35)
		tw.parallel().tween_property(_visual, "scale", Vector3(1.25, 0.7, 1.25), 0.35)
	else:
		tw.tween_property(_visual, "scale", Vector3(1.4, 0.2, 1.4), 0.2)
	tw.tween_callback(func() -> void: _visual.visible = false)


func _return() -> void:
	state = State.IDLE
	_visual.visible = true
	_visual.position = Vector3.ZERO
	_visual.scale = Vector3.ONE * 0.1
	_shape.set_deferred("disabled", false)
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if _cloud_mat:
		tw.parallel().tween_method(func(v: float) -> void: _cloud_mat.set_shader_parameter("dissolve", v), 1.0, 0.0, 0.5)
	returned.emit()
	ObjSvc.feedback("object_cloud_return", global_position, {})

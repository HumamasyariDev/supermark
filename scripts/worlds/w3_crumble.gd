extends Node3D
## W3 sugar-glass pillar top (R1.3): cracks `crack_after` s after Mak lands (shake), the top segment drops and
## respawns after `respawn_s`. Expects children "Body" (StaticBody3D with the collision) and "Visual".

@export var crack_after := 0.8
@export var respawn_s := 4.0
@export var top_local := 0.0

var _t := -1.0
var _down := false
var _sensor: Area3D


func _ready() -> void:
	_sensor = Area3D.new()
	_sensor.collision_layer = 0
	_sensor.collision_mask = 2
	_sensor.monitorable = false
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = 0.95
	c.height = 0.5
	cs.shape = c
	cs.position = Vector3(0, top_local + 0.25, 0)
	_sensor.add_child(cs)
	add_child(_sensor)
	_sensor.body_entered.connect(func(n: Node) -> void:
		if n.is_in_group("player") and _t < 0.0 and not _down:
			_t = 0.0
			ObjSvc.sfx("crackle", global_position))


func _physics_process(delta: float) -> void:
	var v := get_node_or_null("Visual") as Node3D
	if _t >= 0.0 and not _down:
		_t += delta
		if v:
			v.position = Vector3(sin(_t * 70.0) * 0.05, 0, cos(_t * 63.0) * 0.05)
		if _t >= crack_after:
			_fall()


func _fall() -> void:
	_down = true
	var body := get_node_or_null("Body") as StaticBody3D
	for c in body.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).set_deferred("disabled", true)
	var v := get_node_or_null("Visual") as Node3D
	ObjSvc.burst(self, global_position + Vector3(0, top_local, 0), Color(0.85, 0.75, 1.0), 26, 4.0, 0.16, -12.0, 0.9)
	ObjSvc.sfx("glass_break", global_position)
	if v:
		var tw := create_tween()
		tw.tween_property(v, "position:y", -12.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void: v.visible = false)
	await get_tree().create_timer(respawn_s, false).timeout
	for c in body.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).set_deferred("disabled", false)
	if v:
		v.position = Vector3.ZERO
		v.visible = true
		v.scale = Vector3(0.2, 0.2, 0.2)
		var tw2 := create_tween()
		tw2.tween_property(v, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_down = false
	_t = -1.0

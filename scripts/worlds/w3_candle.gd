extends StaticBody3D
## W3 birthday candle (R1.2b): striped candle with a wick flame that is lit `lit_s`, out `out_s` (period `period_s`,
## offset `phase_s`). While lit, a hazard Area3D (group "hazard", meta damage/knockback_up) covers the top.
## Relight telegraph: sparks + crackle `telegraph_s` before the flame returns.

@export var period_s := 3.5
@export var lit_s := 2.0
@export var phase_s := 0.0
@export var telegraph_s := 0.4
@export var height := 1.2
@export var radius := 0.7

var _flame: Node3D
var _hazard: Area3D
var _lit := true
var _warned := false
var _t := 0.0   # R1 feel fix: the phase accumulates in _physics_process so pause freezes the wave


func _ready() -> void:
	_flame = get_node_or_null("Flame") as Node3D
	_hazard = Area3D.new()
	_hazard.name = "FlameHazard"
	_hazard.collision_layer = 16
	_hazard.collision_mask = 0
	_hazard.add_to_group("hazard")
	_hazard.set_meta("damage", 1)
	_hazard.set_meta("knockback_up", 6.0)
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius * 0.9
	c.height = 0.9
	cs.shape = c
	cs.position = Vector3(0, height + 0.45, 0)
	_hazard.add_child(cs)
	add_child(_hazard)


func _physics_process(delta: float) -> void:
	_t += delta
	var t := fposmod(_t - phase_s, period_s)
	var lit := t < lit_s
	var warn := (not lit) and t > period_s - telegraph_s
	if lit != _lit:
		_lit = lit
		_hazard.monitorable = lit
		(_hazard.get_child(0) as CollisionShape3D).disabled = not lit
		if _flame:
			var tw := create_tween()
			tw.tween_property(_flame, "scale", Vector3.ONE if lit else Vector3(0.05, 0.05, 0.05), 0.15)
		if not lit:
			ObjSvc.burst(self, global_position + Vector3(0, height + 0.3, 0), Color(0.8, 0.8, 0.85), 8, 1.5, 0.12, 2.0, 0.8)
	if warn and not _warned:
		_warned = true
		ObjSvc.burst(self, global_position + Vector3(0, height + 0.15, 0), Color(1.0, 0.8, 0.3), 10, 2.0, 0.06, -3.0, 0.4)
		ObjSvc.sfx("crackle", global_position)
	if lit:
		_warned = false

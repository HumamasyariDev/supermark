class_name SlamSensor
extends Area3D
## Detects a Ham Slam (ground pound) on top of an object. Three routes, whichever comes first:
## 1) a player overlapping this area while is_ground_pounding() is true,
## 2) the player's ground_pounded(position) signal landing inside the footprint,
## 3) the player's attack calling hit_by_player("slam", ...) on this area (it sits on the enemy_hurtbox layer too).
## Also reports punches/kicks via `struck` so crates can share it.

signal slammed(by: Node)
signal struck(kind: String, by_position: Vector3)

@export var radius: float = 1.0
@export var height: float = 0.8
@export var cooldown: float = 0.5

var _cool := 0.0
var _connected: Dictionary = {}


static func create(parent: Node3D, r: float, h: float, pos: Vector3) -> SlamSensor:
	var s := SlamSensor.new()
	s.radius = r
	s.height = h
	s.position = pos
	s.name = "SlamSensor"
	parent.add_child(s)
	return s


func _ready() -> void:
	collision_layer = ObjSvc.L_TRIGGER | ObjSvc.L_ENEMY_HURTBOX
	collision_mask = ObjSvc.L_PLAYER | ObjSvc.L_PLAYER_ATTACK
	monitorable = true
	if get_child_count() == 0:
		ObjSvc.add_shape(self, ObjSvc.cyl_shape(radius, height), Vector3(0, height * 0.5, 0))


func _physics_process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	for p in get_tree().get_nodes_in_group("player"):
		if not _connected.has(p.get_instance_id()) and p.has_signal("ground_pounded"):
			p.connect("ground_pounded", _on_ground_pounded.bind(p))
			_connected[p.get_instance_id()] = true
	if _cool > 0.0:
		return
	for b in get_overlapping_bodies():
		if ObjSvc.is_player(b) and ObjSvc.player_slamming(b):
			var v: Variant = b.get("velocity")
			if v is Vector3 and (v as Vector3).y > 1.0:
				continue
			_fire(b)
			return


func _on_ground_pounded(at: Vector3, p: Node) -> void:
	if _cool > 0.0 or not is_inside_tree():
		return
	var local := global_transform.affine_inverse() * at
	if Vector2(local.x, local.z).length() <= radius + 0.35 and local.y > -0.5 and local.y < height + 0.6:
		_fire(p)


func _fire(by: Node) -> void:
	_cool = cooldown
	slammed.emit(by)


## Called by the player's attack system (enemy_hurtbox layer contract).
func hit_by_player(kind: String, from_position: Vector3) -> bool:
	if kind == "slam":
		if _cool > 0.0:
			return false
		_fire(ObjSvc.get_player())
		return true
	struck.emit(kind, from_position)
	return struck.get_connections().size() > 0

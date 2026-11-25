class_name EnemyHurtbox
extends Area3D
## Hurtbox on layer 7 (enemy_hurtbox). The player's attack area (layer 6) finds this area and
## calls hit_by_player(kind, from_position) on it or on its owner enemy; both work.

var enemy: Node


func _init() -> void:
	collision_layer = 1 << 6
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group("enemy_hurtbox")


func hit_by_player(kind: String, from_position: Vector3) -> bool:
	if enemy != null and is_instance_valid(enemy) and enemy.has_method("hit_by_player"):
		return enemy.hit_by_player(kind, from_position)
	return false

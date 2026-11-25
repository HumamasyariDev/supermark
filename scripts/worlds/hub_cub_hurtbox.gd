extends Area3D
## Hurtbox for the hub's Woolly Wolf cub gag: forwards player attacks to HubActivities.cub_hit().

var owner_gag: Node


func hit_by_player(kind: String, _from_position: Vector3) -> bool:
	if owner_gag and owner_gag.has_method("cub_hit"):
		return bool(owner_gag.call("cub_hit", kind))
	return false

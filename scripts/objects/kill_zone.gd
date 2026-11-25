class_name KillZone
extends Area3D
## Fall-out volume: a player entering calls Game.player_fell_out(). Without Game, the player is respawned at the
## last activated checkpoint (or at `fallback_respawn`). Invisible by design.

signal player_fell(body: Node)

@export var size: Vector3 = Vector3(200, 4, 200)
@export var fallback_respawn: NodePath


func _ready() -> void:
	add_to_group("kill_zone")
	collision_layer = ObjSvc.L_TRIGGER
	collision_mask = ObjSvc.L_PLAYER
	ObjSvc.add_shape(self, ObjSvc.box_shape(size))
	body_entered.connect(_on_body)


func _on_body(body: Node) -> void:
	if not ObjSvc.is_player(body):
		return
	player_fell.emit(body)
	ObjSvc.feedback("object_kill_zone", Vector3.INF, {}, "fall_out")
	if ObjSvc.can("Game", "player_fell_out"):
		ObjSvc.call_on("Game", "player_fell_out")
		return
	if not body.has_method("respawn"):
		return
	var xf := Transform3D()
	var found := false
	for c in get_tree().get_nodes_in_group("checkpoint"):
		if bool(c.get("is_active")) and c.has_method("get_respawn_transform"):
			xf = c.call("get_respawn_transform")
			found = true
	if not found and not fallback_respawn.is_empty():
		var n := get_node_or_null(fallback_respawn) as Node3D
		if n:
			xf = n.global_transform
			found = true
	if found:
		body.call("respawn", xf)

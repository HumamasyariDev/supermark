class_name TruffleSpawner
extends Node3D
## Base for objects that reward a truffle (lost pages, 100 acorns, bellows, cages, time trials, buried treasure).
## The truffle appears at the child Marker3D named "TruffleMarker" (or at this node).
## If the truffle was already collected on an earlier visit, a ghost truffle is placed at once when show_ghost_if_owned is on.

signal rewarded(id: String)

@export var reward_truffle_id: String = ""
@export var show_ghost_if_owned: bool = false

var reward_given := false


func _ready() -> void:
	if show_ghost_if_owned and reward_truffle_id != "" and ObjSvc.has_truffle(reward_truffle_id):
		call_deferred("_spawn", false)
		reward_given = true


func reward_marker() -> Node3D:
	var m := get_node_or_null("TruffleMarker") as Node3D
	return m if m != null else self


func give_reward() -> Node3D:
	if reward_given or reward_truffle_id == "":
		return null
	reward_given = true
	rewarded.emit(reward_truffle_id)
	return _spawn(true)


func _spawn(reveal: bool) -> Node3D:
	var m := reward_marker()
	return ObjSvc.spawn_truffle(get_parent() if get_parent() != null else self, m.global_transform, reward_truffle_id, reveal)

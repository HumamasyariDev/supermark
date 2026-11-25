class_name BellowsSet
extends TruffleSpawner
## Rewards a truffle when every BellowsMachine with the same group_id is broken (W1-4 "Bust the Bellows").

signal progress(broken: int, total: int)

@export var group_id: String = "bellows"


func _ready() -> void:
	super._ready()
	add_to_group("bellows_listener")


func on_bellows_broken(gid: String) -> void:
	if gid != group_id:
		return
	var all := get_tree().get_nodes_in_group("bellows_" + group_id)
	var n_broken := 0
	for b in all:
		if bool(b.get("is_broken")):
			n_broken += 1
	progress.emit(n_broken, all.size())
	if all.size() > 0 and n_broken >= all.size() and not reward_given:
		give_reward()

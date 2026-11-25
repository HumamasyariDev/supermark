class_name AcornHundred
extends TruffleSpawner
## Spawns a truffle when `required` acorns are collected in one visit to the world.
## The per-visit counter (ObjSvc.visit_acorns) resets when this node enters the tree.

signal progress(count: int, required: int)

@export var required: int = 100
@export var reset_counter_on_ready: bool = true


func _ready() -> void:
	super._ready()
	add_to_group("acorn_listener")
	if reset_counter_on_ready:
		ObjSvc.visit_acorns = 0


func on_acorn_collected(total: int) -> void:
	progress.emit(total, required)
	if total >= required and not reward_given:
		give_reward()

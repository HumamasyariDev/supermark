class_name LostPageSet
extends TruffleSpawner
## Watches LostPage pickups for one world. When `required` distinct pages are found, a truffle appears at TruffleMarker.

signal progress(found: int, required: int)

@export var world_id: String = ""
@export var required: int = 5

var found: Dictionary = {}


func _ready() -> void:
	super._ready()
	add_to_group("lost_page_listener")
	if world_id == "":
		world_id = ObjSvc.current_world()
	# Pages persist per world (Game.collect_page saves them): count the ones found on earlier visits, and pay out
	# a reward that was earned but never collected (critique objects r1: 5/5 pages and no truffle on a revisit).
	if ObjSvc.can("Game", "has_page"):
		for i in maxi(required, 5):
			if bool(ObjSvc.call_on("Game", "has_page", [world_id, i])):
				found[i] = true
	if found.size() >= required and not reward_given:
		if reward_truffle_id != "" and ObjSvc.has_truffle(reward_truffle_id):
			if not show_ghost_if_owned:
				reward_given = true
				call_deferred("_spawn", false)
		else:
			call_deferred("give_reward")


func on_page_collected(page_world: String, page_index: int) -> void:
	if world_id != "" and page_world != "" and page_world != world_id:
		return
	found[page_index] = true
	progress.emit(found.size(), required)
	if found.size() == required:
		ObjSvc.feedback("object_pages_complete", ObjSvc.body_pos(ObjSvc.get_player()) + Vector3(0, 1.0, 0) if ObjSvc.get_player() else Vector3.INF, {"world_id": world_id})
	if found.size() >= required and not reward_given:
		give_reward()

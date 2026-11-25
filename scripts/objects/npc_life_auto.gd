class_name NpcLifeAuto
extends Node
## Fix stage r2 (critique objects r1 re-run, major "world NPCs stand frozen"): one per world scene, added by the first
## interactive object that enters it (ObjSvc.ensure_npc_life_auto). It finds generated characters that world code
## placed (instances of res://assets/characters/...) and gives each one an NpcLife in auto mode: NpcLife watches the
## model for 0.6 s first and only comes alive when nothing else animates it, then steps aside the moment another
## script starts posing it. Characters added later (cage contents, cutscene actors) are picked up through node_added.
## Opt out per model with group `no_npc_life` or meta `npc_life` = false, per scene with meta `npc_life_auto` = false
## on the scene root, or for a whole run with the command-line argument --no-npc-life-auto.

const CHAR_DIR := "res://assets/characters/"

var scene_root: Node
var _pending: Array[Node] = []
var _flush_at := -1.0
var _t := 0.0
var total := 0


func _ready() -> void:
	if scene_root == null:
		scene_root = get_parent()
	get_tree().node_added.connect(_on_node_added)
	# The builders create most of the world in their own _ready and in deferred calls: scan after they settle.
	_flush_at = 0.4


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n.scene_file_path.begins_with(CHAR_DIR):
		_pending.append(n)
		if _flush_at < 0.0:
			_flush_at = _t + 0.3


func _process(delta: float) -> void:
	_t += delta
	if _flush_at >= 0.0 and _t >= _flush_at:
		_flush_at = -1.0
		_scan()


func _scan() -> void:
	if scene_root == null or not is_instance_valid(scene_root):
		return
	if not _scanned_all:
		_scanned_all = true
		_pending.clear()
		total += NpcLife.attach_all(scene_root, {}, [], true).size()
		return
	var batch := _pending.duplicate()
	_pending.clear()
	var parents: Array[Node] = []
	for n in batch:
		if is_instance_valid(n) and (n as Node).is_inside_tree() and scene_root.is_ancestor_of(n):
			var par := (n as Node).get_parent()
			if not parents.has(par):
				parents.append(par)
	for par in parents:
		# Models that already have an NpcLife, or stepped aside before (meta npc_life_skip), are skipped.
		total += NpcLife.attach_all(par, {}, [], true).size()


var _scanned_all := false

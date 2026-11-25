class_name EnemyGroup
extends Node3D
## Mission helper for world builders: watches every EnemyBase below it (any depth) and emits
## `cleared` when all are defeated. With `truffle_id` set it then spawns res://scenes/objects/Truffle.tscn
## at the child Marker3D "TruffleSpot" (or at this node) with the reveal animation, e.g. W1-1 (Woolly
## Wolves at the straw house), W2-6 (five Peapod Poppers), W3-2 (Sergeant Snap's squad).

signal cleared
signal enemy_defeated(enemy: Node, remaining: int)

@export var truffle_id: String = ""
@export var mission_title: String = ""
@export var announce: bool = true

var remaining: int = 0
var _done: bool = false


func _ready() -> void:
	call_deferred("_hook")


func _hook() -> void:
	for n in find_children("*", "CharacterBody3D", true, false):
		if n is EnemyBase:
			remaining += 1
			(n as EnemyBase).defeated.connect(_on_defeated)
	if remaining == 0 and is_inside_tree():
		_finish()


func _on_defeated(e: Node) -> void:
	remaining = maxi(remaining - 1, 0)
	enemy_defeated.emit(e, remaining)
	if remaining > 0 and announce:
		EnemyKit.popup(get_parent(), (e as Node3D).global_position + Vector3(0, 2.2, 0), "%d to go!" % remaining, Color(1, 0.9, 0.5), 80, 1.2)
	if remaining == 0:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	cleared.emit()
	if truffle_id == "" or EnemyKit.game_call(self, "has_truffle", [truffle_id]) == true:
		return
	if not ResourceLoader.exists("res://scenes/objects/Truffle.tscn"):
		return
	var t := (load("res://scenes/objects/Truffle.tscn") as PackedScene).instantiate() as Node3D
	t.set("truffle_id", truffle_id)
	t.set("mission_title", mission_title)
	t.set("spawn_revealed", true)
	var spot := get_node_or_null("TruffleSpot") as Node3D
	get_parent().add_child(t)
	t.global_position = spot.global_position if spot != null else global_position
	EnemyKit.sfx(self, "truffle_appear", t.global_position)

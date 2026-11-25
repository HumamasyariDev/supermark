class_name BossWeakpoint
extends Area3D
## A boss weak point the player's attack and stomp areas can hit (layer 7, "enemy_hurtbox").
## The node's origin sits at the bottom of its shape, because the player only stomps areas whose
## origin is no higher than 0.4 m above its feet. Forwards hits to the owner with a tag.

var owner_node: Node
var tag: String = ""
var shape_node: CollisionShape3D


static func make(owner_n: Node, tag_name: String, radius: float, height: float) -> BossWeakpoint:
	var w := BossWeakpoint.new()
	w.owner_node = owner_n
	w.tag = tag_name
	w.name = "Weak_" + tag_name
	w.collision_layer = 64
	w.collision_mask = 0
	w.monitoring = false
	w.monitorable = false
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	cs.shape = c
	cs.position = Vector3(0, height * 0.5, 0)
	w.add_child(cs)
	w.shape_node = cs
	return w


func set_open(on: bool) -> void:
	set_deferred("monitorable", on)


func hit_by_player(kind: String, from_position: Vector3) -> bool:
	if owner_node != null and owner_node.has_method("weak_hit"):
		return bool(owner_node.call("weak_hit", tag, kind, from_position))
	return false

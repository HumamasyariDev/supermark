extends MeshInstance3D
## Render-only observer. Original nodes, transforms and visibility stay authoritative.
var batch_owner: Node
var batch_group: Dictionary
var batch_index := -1


func observe(owner_node: Node, group: Dictionary, index: int) -> void:
	batch_owner = owner_node
	batch_group = group
	batch_index = index
	set_notify_transform(true)
	visibility_changed.connect(_changed)
	_changed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_changed()
	elif what == NOTIFICATION_EXIT_TREE and is_instance_valid(batch_owner):
		batch_owner.hide_instance(batch_group, batch_index)


func _changed() -> void:
	if is_instance_valid(batch_owner) and batch_index >= 0 and is_inside_tree():
		batch_owner.update_instance(self, batch_group, batch_index)


func stop_observing() -> void:
	set_notify_transform(false)
	visibility_changed.disconnect(_changed)
	batch_owner = null
	batch_index = -1

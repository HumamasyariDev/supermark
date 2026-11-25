extends Node3D
## W3-1 "The Breadcrumb Trail": glowing crumbs along the trail; each crumb collected lights the next five.
## Crumbs listed in `stolen` start hidden (eaten by the crows) and drop back when the crow in
## `crow_paths` (same order as `stolen_groups`) is defeated. At `gate_opens_at` crumbs the hedge gate opens.

signal count_changed(count: int, total: int)
signal gate_opened

@export var crumbs: PackedVector3Array = PackedVector3Array()
@export var stolen: PackedInt32Array = PackedInt32Array()          # crumb indices hidden at start
@export var stolen_groups: PackedInt32Array = PackedInt32Array()   # crow index per stolen crumb
@export var crow_paths: Array[NodePath] = []
@export var gate_path: NodePath
@export var gate_opens_at := 22
@export var lit_ahead := 5

var count := 0
var _nodes: Array[Area3D] = []
var _taken: Array[bool] = []
var _hidden: Array[bool] = []
var _open := false
var _mat_lit: StandardMaterial3D
var _mat_dim: StandardMaterial3D


func _ready() -> void:
	_mat_lit = StandardMaterial3D.new()
	_mat_lit.albedo_color = Color(0.95, 0.72, 0.38)
	_mat_lit.emission_enabled = true
	_mat_lit.emission = Color(1.0, 0.72, 0.3)
	_mat_lit.emission_energy_multiplier = 1.6
	_mat_lit.roughness = 0.6
	_mat_dim = StandardMaterial3D.new()
	_mat_dim.albedo_color = Color(0.82, 0.6, 0.34)
	_mat_dim.roughness = 0.8
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.3
	mesh.radial_segments = 10
	mesh.rings = 5
	for i in crumbs.size():
		var a := Area3D.new()
		a.name = "Crumb%02d" % i
		a.collision_layer = 8
		a.collision_mask = 2
		a.monitorable = false
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.8
		cs.shape = sh
		cs.position.y = 0.4
		a.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		mi.position.y = 0.12
		mi.rotation_degrees = Vector3(randf() * 30.0, randf() * 360.0, 0)
		a.add_child(mi)
		add_child(a)
		a.global_position = crumbs[i]
		var idx := i
		a.body_entered.connect(func(b: Node) -> void: _on_body(idx, b))
		_nodes.append(a)
		_taken.append(false)
		_hidden.append(stolen.has(i))
	for k in crow_paths.size():
		var crow := get_node_or_null(crow_paths[k])
		if crow and crow.has_signal("defeated"):
			var ck := k
			crow.connect("defeated", func(_e: Node) -> void: _drop_stolen(ck))
	_refresh()


func _on_body(i: int, b: Node) -> void:
	if _taken[i] or _hidden[i] or not b.is_in_group("player"):
		return
	_taken[i] = true
	count += 1
	var n := _nodes[i]
	ObjSvc.burst(self, n.global_position + Vector3(0, 0.3, 0), Color(1.0, 0.8, 0.45), 10, 2.5, 0.12, -6.0, 0.6)
	ObjSvc.sfx("acorn", n.global_position)
	n.visible = false
	n.set_deferred("monitoring", false)
	count_changed.emit(count, crumbs.size())
	ObjSvc.call_on("UI", "toast", ["Breadcrumbs %d / %d" % [count, gate_opens_at]])
	print("[W3] breadcrumbs=%d" % count)
	_refresh()
	if count >= gate_opens_at and not _open:
		open_gate()


func _drop_stolen(crow_index: int) -> void:
	for j in stolen.size():
		if j < stolen_groups.size() and stolen_groups[j] == crow_index:
			var i := stolen[j]
			if _hidden[i]:
				_hidden[i] = false
				ObjSvc.burst(self, _nodes[i].global_position + Vector3(0, 0.6, 0), Color(1.0, 0.8, 0.45), 14, 3.0, 0.14, -6.0, 0.7)
	_refresh()


func _refresh() -> void:
	# Light the next `lit_ahead` crumbs after the furthest one taken.
	var furthest := -1
	for i in _taken.size():
		if _taken[i]:
			furthest = i
	for i in _nodes.size():
		var n := _nodes[i]
		if _taken[i]:
			continue
		n.visible = not _hidden[i]
		var mi := n.get_node("Mesh") as MeshInstance3D
		mi.material_override = _mat_lit if (i <= furthest + lit_ahead) else _mat_dim


func open_gate() -> void:
	_open = true
	print("[W3] hedge gate open")
	ObjSvc.call_on("UI", "toast", ["The hedge gate swings open!"])
	ObjSvc.sfx("gate_open")
	var gate := get_node_or_null(gate_path) as Node3D
	if gate == null:
		return
	for c in gate.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).set_deferred("disabled", true)
	var l := gate.get_node_or_null("LeafL") as Node3D
	var r := gate.get_node_or_null("LeafR") as Node3D
	var tw := create_tween().set_parallel(true)
	if l:
		tw.tween_property(l, "rotation_degrees:y", -100.0, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if r:
		tw.tween_property(r, "rotation_degrees:y", 100.0, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	gate_opened.emit()

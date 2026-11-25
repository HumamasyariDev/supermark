extends Area3D
## Local stand-in acorn pickup dropped by defeated enemies, used only until the objects
## workstream provides res://scenes/objects/Acorn.tscn. Layer 4 (pickup), mask 2 (player).

var vel := Vector3.ZERO
var grounded := false
var age := 0.0
var _vis: Node3D


func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = 1 << 1
	monitoring = true
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.45
	cs.shape = s
	add_child(cs)
	_vis = Node3D.new()
	add_child(_vis)
	EnemyKit.ball(_vis, 0.13, Color(0.62, 0.36, 0.16), Vector3(0, 0.14, 0), Vector3(1, 1.2, 1))
	EnemyKit.ball(_vis, 0.15, Color(0.4, 0.24, 0.1), Vector3(0, 0.25, 0), Vector3(1, 0.55, 1))
	EnemyKit.cylinder(_vis, 0.015, 0.02, 0.08, Color(0.3, 0.18, 0.08), Vector3(0, 0.33, 0))
	body_entered.connect(_on_body)


func launch(v: Vector3) -> void:
	vel = v


func _physics_process(delta: float) -> void:
	age += delta
	_vis.rotation.y += delta * 3.0
	if not grounded:
		vel.y -= 20.0 * delta
		var from := global_position
		var to := from + vel * delta
		var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.2, 0), to)
		q.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and vel.y < 0:
			global_position = hit.position
			if vel.y < -3.0:
				vel = Vector3(vel.x * 0.4, -vel.y * 0.35, vel.z * 0.4)
			else:
				grounded = true
		else:
			global_position = to
		if global_position.y < -60.0:
			queue_free()
	else:
		_vis.position.y = 0.08 + sin(age * 4.0) * 0.06
	if age > 25.0:
		queue_free()


func _on_body(b: Node) -> void:
	if age < 0.35 or not b.is_in_group("player"):
		return
	EnemyKit.game_call(self, "add_acorns", [1])
	EnemyKit.sfx(self, "acorn_pickup", global_position)
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.3, 0), "stars", [Color(1, 0.85, 0.3)], 8, 3.0)
	queue_free()

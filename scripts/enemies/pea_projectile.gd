class_name PeaProjectile
extends Area3D
## A lobbed pea: ballistic arc with a shadow marker at the landing point. Hurts the player
## (take_damage) and splats on the world. Layer 5 (hazard) so it reads as a hazard, mask 2 (player).

const GRAVITY := 18.0

var vel: Vector3 = Vector3.ZERO
var marker: MeshInstance3D
var age: float = 0.0
var _vis: MeshInstance3D
var _done: bool = false

## The generated pea (pea_mid from the Tripo P2 peapod) doubles as the projectile, cached once.
static var _pea_mesh: Mesh
static var _pea_looked: bool = false


static func pea_mesh() -> Mesh:
	if _pea_looked:
		return _pea_mesh
	_pea_looked = true
	var path := "res://assets/enemies/peapod_popper/peapod_popper.glb"
	if ResourceLoader.exists(path):
		var inst := (load(path) as PackedScene).instantiate()
		var n := inst.find_child("pea_mid", true, false) as MeshInstance3D
		if n != null:
			_pea_mesh = n.mesh
		inst.free()
	return _pea_mesh


static func flight_velocity(from: Vector3, to: Vector3, t: float) -> Vector3:
	var d := to - from
	return Vector3(d.x / t, (d.y + 0.5 * GRAVITY * t * t) / t, d.z / t)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1
	monitorable = false
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.25
	cs.shape = s
	add_child(cs)
	var pm := pea_mesh()
	if pm != null:
		_vis = MeshInstance3D.new()
		_vis.mesh = pm
		_vis.scale = Vector3.ONE * 2.3
		add_child(_vis)
	else:
		_vis = EnemyKit.ball(self, 0.17, Color(0.45, 0.82, 0.25), Vector3.ZERO)
		EnemyKit.ball(self, 0.05, Color(0.85, 1.0, 0.7), Vector3(0.07, 0.08, -0.1))
	body_entered.connect(_on_body)


func _physics_process(delta: float) -> void:
	if _done:
		return
	age += delta
	vel.y -= GRAVITY * delta
	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position
		_splat()
		return
	global_position = to
	_vis.rotation += Vector3(8, 5, 0) * delta
	if age > 5.0:
		_splat()


func _on_body(b: Node) -> void:
	if _done or not b.is_in_group("player"):
		return
	if b.has_method("take_damage"):
		b.call("take_damage", 1, global_position - vel.normalized())
	_splat()


func _splat() -> void:
	if _done:
		return
	_done = true
	var sfx_owned := EnemyKit.juice_sfx_owns(self, "enemy_projectile_hit")
	if not sfx_owned:
		EnemyKit.sfx(self, "pea_splat", global_position)
	if EnemyKit.juice_handles(self, "enemy_projectile_hit", "vfx"):
		EnemyKit.juice(self, "enemy_projectile_hit", global_position + Vector3(0, 0.05, 0), {"kind": "pea", "family": "peapod_popper", "scale": 0.7, "silent": not sfx_owned})
	else:
		EnemyKit.fx(get_parent(), "PeaSplat", global_position + Vector3(0, 0.05, 0), 0.6)
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.1, 0), "peas", [Color(0.45, 0.82, 0.25), Color(0.7, 0.95, 0.4)], 10, 3.0)
	EnemyKit.ground_ring(get_parent(), global_position, 0.8, Color(0.6, 0.95, 0.4, 0.8), 0.35)
	if marker != null and is_instance_valid(marker):
		marker.queue_free()
	queue_free()

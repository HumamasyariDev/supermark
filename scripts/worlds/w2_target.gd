extends Area3D
## W2 hit target (tea cosy and similar): an Area3D on the enemy-hurtbox layer that the player's attacks
## find through hit_by_player (TECH_CONTRACT attack interface). Emits `hit` for the world scripts.

signal hit(kind: String)

@export var radius := 0.9
@export var height := 1.2


func _ready() -> void:
	collision_layer = 64
	collision_mask = 0
	monitorable = true
	monitoring = false
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = radius
	cy.height = height
	cs.shape = cy
	cs.position = Vector3(0, height * 0.5, 0)
	add_child(cs)


func hit_by_player(kind: String, _from_position: Vector3) -> bool:
	hit.emit(kind)
	return true

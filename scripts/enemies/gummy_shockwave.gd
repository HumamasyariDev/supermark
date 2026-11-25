class_name GummyShockwave
extends Node3D
## Expanding ground ring from a Gummy Brute slam (also used by the boss). Hurts a grounded player
## standing inside the moving band; jumping over the band avoids it.

@export var max_radius: float = 5.0
@export var duration: float = 0.7
@export var band: float = 0.7
@export var color: Color = Color(1.0, 0.45, 0.55, 0.85)

var t: float = 0.0
var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _hit: bool = false


func _ready() -> void:
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.82
	tm.outer_radius = 1.0
	tm.rings = 64
	tm.ring_segments = 8
	_ring.mesh = tm
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = color
	_mat.emission_enabled = true
	_mat.emission = Color(color.r, color.g, color.b)
	_mat.emission_energy_multiplier = 1.4
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring.position.y = 0.12


func _physics_process(delta: float) -> void:
	t += delta
	var u := clampf(t / duration, 0.0, 1.0)
	var r := lerpf(0.4, max_radius, 1.0 - pow(1.0 - u, 2.0))
	_ring.scale = Vector3(r, 2.2, r)
	_mat.albedo_color.a = color.a * (1.0 - u * u)
	if not _hit:
		var p := EnemyKit.find_player(get_tree())
		if p != null:
			var d := p.global_position - global_position
			var flat := Vector2(d.x, d.z).length()
			# The damage band sits on the drawn torus (centre line 0.91 r, half-width 0.09 r + 0.35) and never
			# reaches past the drawn maximum (r1 fun: it hurt ahead of the ring and beyond its 5 m edge).
			var centre := r * 0.91
			if absf(flat - centre) < r * 0.09 + 0.35 and flat < max_radius + 0.1 and d.y < 0.45 and d.y > -0.6:
				_hit = true
				if p.has_method("take_damage"):
					p.call("take_damage", 1, global_position)
	if u >= 1.0:
		queue_free()

class_name BossVent
extends Node3D
## Brass gust vent flush with the roof (B08, r 1.1). In phase III one vent is active at a time: it glows gold,
## whistles, wears a sooty plug with a gold chevron ("gold means slam here"), and a steam column rises.
## The fight logic (WolfBoss) decides what a step or a Ham Slam on the plug does; this node is the look.

const BRASS := Color(0.79, 0.63, 0.29)
const GOLD := Color(1.0, 0.82, 0.35)

var vid: String = "V1"
var active := false
var plug: Node3D
var chevron: MeshInstance3D
var light: OmniLight3D
var steam: CPUParticles3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _t := 0.0
var _flicker := false


func _ready() -> void:
	add_to_group("gust_vent")
	var rim := EnemyKit.cylinder(self, 1.1, 1.15, 0.08, BRASS, Vector3(0, 0.02, 0))
	rim.material_override = EnemyKit.mat(BRASS, 0.32, 0.25, 0.85)
	# OPUSLOOK: the dark well sits 6 mm above the brass rim's top cap. Both tops were at y 0.06 and fought for depth; the
	# web build drew the gold cap over the well, so the vents read as flat gold discs instead of black-and-gold fans.
	EnemyKit.cylinder(self, 0.98, 0.98, 0.06, Color(0.08, 0.06, 0.06), Vector3(0, 0.036, 0))
	# Spiral slats.
	for k in 8:
		var s := EnemyKit.box(self, Vector3(0.9, 0.05, 0.1), BRASS, Vector3(0, 0.07, 0), Vector3(0, float(k) * 22.5, 0))
		s.position = Vector3(cos(float(k) * PI / 4.0), 0, sin(float(k) * PI / 4.0)) * 0.45 + Vector3(0, 0.07, 0)
		s.rotation_degrees = Vector3(0, -float(k) * 45.0 + 30.0, 0)
		s.material_override = rim.material_override
	var hub := EnemyKit.cylinder(self, 0.18, 0.2, 0.1, BRASS, Vector3(0, 0.08, 0))
	hub.material_override = rim.material_override
	_glow = EnemyKit.cylinder(self, 0.95, 0.95, 0.02, GOLD, Vector3(0, 0.1, 0))
	# OPUSLOOK: a material of its own. The cached glow material was shared by all four vents, so the active vent's pulse
	# lit every vent; the disc is also hidden while fully transparent (the web drew the idle disc as solid gold over the
	# slats).
	_glow_mat = EnemyKit.glow_mat(Color(1.0, 0.8, 0.3, 0.0), 2.5).duplicate() as StandardMaterial3D
	_glow.material_override = _glow_mat
	_glow.visible = false
	# Soot plug: a dome cap r 0.6 with a gold rim.
	plug = Node3D.new()
	plug.name = "Plug"
	add_child(plug)
	var dome := EnemyKit.ball(plug, 0.62, Color(0.1, 0.09, 0.09), Vector3(0, 0.05, 0), Vector3(1, 0.45, 1))
	dome.material_override = EnemyKit.mat(Color(0.1, 0.09, 0.09), 0.9, 0.2)
	var prim := EnemyKit.ring(plug, 0.55, 0.68, GOLD, Vector3(0, 0.08, 0))
	prim.material_override = EnemyKit.mat(GOLD, 0.3, 0.3, 0.9)
	chevron = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.7, 0.55, 0.12)
	chevron.mesh = pm
	chevron.rotation_degrees = Vector3(180, 0, 0)
	chevron.position = Vector3(0, 1.4, 0)
	chevron.material_override = EnemyKit.glow_mat(Color(1.0, 0.79, 0.24), 3.0)
	plug.add_child(chevron)
	plug.visible = false
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.82, 0.35)
	light.light_energy = 0.0
	light.omni_range = 6.0
	light.position = Vector3(0, 1.2, 0)
	add_child(light)
	steam = CPUParticles3D.new()
	steam.amount = 40
	steam.lifetime = 1.4
	steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	steam.emission_sphere_radius = 0.7
	steam.direction = Vector3.UP
	steam.spread = 5.0
	steam.initial_velocity_min = 5.0
	steam.initial_velocity_max = 7.0
	steam.gravity = Vector3.ZERO
	steam.scale_amount_min = 0.6
	steam.scale_amount_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.85, 0.5))
	g.set_color(1, Color(1.0, 0.9, 0.8, 0.0))
	steam.color_ramp = g
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	sm.radial_segments = 8
	sm.rings = 4
	steam.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.vertex_color_use_as_albedo = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	steam.material_override = mm
	steam.emitting = false
	add_child(steam)


func set_active(on: bool) -> void:
	active = on
	_flicker = false
	plug.visible = on
	steam.emitting = on
	if on:
		plug.scale = Vector3(0.2, 0.2, 0.2)
		create_tween().tween_property(plug, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		EnemyKit.sfx(self, "gust_whoosh", global_position)


## The next vent flickers gold for its last second of warning.
func set_flicker(on: bool) -> void:
	_flicker = on


## Ham Slam on the plug: it pops in a gold soot burst.
func pop_plug() -> void:
	plug.visible = false
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.4, 0), "stars", [GOLD, Color(1, 1, 0.8)], 30, 9.0)
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.4, 0), "dust", [Color(0.12, 0.1, 0.1), Color(0.25, 0.2, 0.2)], 30, 6.0)
	EnemyKit.ground_ring(get_parent(), global_position + Vector3(0, 0.05, 0), 2.6, GOLD, 0.45)
	EnemyKit.sfx(self, "cloud_puff", global_position)
	EnemyKit.sfx(self, "bellows_break", global_position)


## A plain step: a small "PFT" soot puff.
func dud_puff() -> void:
	EnemyKit.burst(get_parent(), global_position + Vector3(0, 0.5, 0), "dust", [Color(0.15, 0.13, 0.13)], 14, 3.5)
	EnemyKit.popup(get_parent(), global_position + Vector3(0, 1.6, 0), "PFT", Color(0.25, 0.22, 0.22), 70, 0.7)
	EnemyKit.sfx(self, "cloud_puff_2", global_position)


func _process(delta: float) -> void:
	_t += delta
	var target := 0.0
	if active:
		target = 0.75 + 0.25 * sin(_t * TAU * 2.0)
	elif _flicker:
		target = 0.55 if fmod(_t, 0.25) < 0.125 else 0.1
	_glow_mat.albedo_color.a = lerpf(_glow_mat.albedo_color.a, target, 1.0 - exp(-12.0 * delta))
	_glow.visible = _glow_mat.albedo_color.a > 0.01
	light.light_energy = lerpf(light.light_energy, target * 2.2, 1.0 - exp(-10.0 * delta))
	if plug.visible:
		chevron.position.y = 1.35 + sin(_t * TAU * 2.0) * 0.12
		var s := 1.0 + 0.12 * sin(_t * TAU * 2.0)
		chevron.scale = Vector3(s, s, s)
		chevron.rotation_degrees.y += delta * 90.0

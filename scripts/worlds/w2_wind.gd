extends Area3D
## W2 wind volume (group "wind_zone", TECH_CONTRACT duck type get_wind(pos) -> Vector3).
## mode "snore": the sleeping Giant's breathing cycle (inhale pulls, blast pushes along `direction`),
## with lee boxes behind the table objects that cut the wind to 15 %.
## mode "gust": a steady crosswind with periodic gusts (the Leaf Bouncer crosswind).
## Visual streaks come from the VFX GustSwirl scene when it exists.

signal phase_changed(phase: String)

@export var size := Vector3(10, 3.6, 8)
@export var direction := Vector3(1, 0, 0)
@export_enum("snore", "gust") var mode: String = "snore"
## Snore cycle: [phase name, seconds, wind m/s].
var cycle: Array = [["inhale", 2.0, -2.0], ["hold", 0.5, 0.0], ["blast", 1.6, 11.0], ["rest", 1.2, 0.0]]
@export var ground_scale := 0.65
@export var base_wind := 2.5
@export var gust_wind := 4.5
@export var gust_every := 5.0
@export var gust_len := 1.5
## Lee boxes in world space (AABB) where the wind drops to lee_factor.
var lee: Array[AABB] = []
@export var lee_factor := 0.15
## Lee boxes that only shelter during the inhale (west side of the loaf and butter).
var lee_inhale: Array[AABB] = []
@export var show_streaks := true

var t := 0.0
var phase := ""
var _swirl: Node3D


func _ready() -> void:
	add_to_group("wind_zone")
	collision_layer = 128
	collision_mask = 2
	monitorable = true
	monitoring = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	add_child(cs)
	direction = direction.normalized()
	if show_streaks and ResourceLoader.exists("res://scenes/fx/GustSwirl.tscn"):
		_swirl = (load("res://scenes/fx/GustSwirl.tscn") as PackedScene).instantiate() as Node3D
		add_child(_swirl)
		# GustSwirl blows along its -Z.
		_swirl.basis = Basis.looking_at(direction, Vector3.UP)
		_swirl.position = -direction * size.dot(direction.abs()) * 0.5
		if "length" in _swirl:
			_swirl.set("length", size.dot(direction.abs()))
		if "radius" in _swirl:
			_swirl.set("radius", minf(size.y, size.x + size.z - size.dot(direction.abs())) * 0.5)
		if _swirl.has_method("set_active"):
			_swirl.call("set_active", mode == "gust")


func _physics_process(delta: float) -> void:
	t += delta
	var p := current_phase()
	if p != phase:
		phase = p
		phase_changed.emit(phase)
		if _swirl and _swirl.has_method("set_active"):
			_swirl.call("set_active", phase == "blast" or phase == "gust" or (mode == "gust"))


func current_phase() -> String:
	if mode == "gust":
		return "gust" if fmod(t, gust_every) > gust_every - gust_len else "steady"
	var total := 0.0
	for c in cycle:
		total += float(c[1])
	var x := fmod(t, total)
	for c in cycle:
		if x < float(c[1]):
			return String(c[0])
		x -= float(c[1])
	return String(cycle[0][0])


## 0..1 progress through the current snore phase (for animation).
func phase_progress() -> float:
	var total := 0.0
	for c in cycle:
		total += float(c[1])
	var x := fmod(t, total)
	for c in cycle:
		if x < float(c[1]):
			return x / float(c[1])
		x -= float(c[1])
	return 0.0


func strength_now() -> float:
	if mode == "gust":
		var s := base_wind
		var g := fmod(t, gust_every)
		if g > gust_every - gust_len:
			s += gust_wind * sin((g - (gust_every - gust_len)) / gust_len * PI)
		return s
	for c in cycle:
		if String(c[0]) == phase:
			return float(c[2])
	return 0.0


func get_wind(at: Vector3) -> Vector3:
	var s := strength_now()
	if s == 0.0:
		return Vector3.ZERO
	var boxes: Array[AABB] = lee if s > 0.0 else lee_inhale
	for b in boxes:
		if b.has_point(at + Vector3(0, 0.6, 0)):
			s *= lee_factor
			break
	return direction * s

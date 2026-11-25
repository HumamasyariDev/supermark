class_name HubLadder
extends Node3D
## Rolling library ladder for the hub: a Climbable pole along the ladder axis plus an automatic clamber onto
## `exit_point` once Mak reaches the top (the player's pole jump would otherwise throw him back into the hall).
## The generated rolling_ladder.glb is the visual; it is placed by the level script next to this node.

@export var foot: Vector3 = Vector3.ZERO
@export var top: Vector3 = Vector3(0, 4.5, 0)
@export var exit_point: Vector3 = Vector3(0, 4.5, -0.8)
@export var exit_yaw_deg: float = 0.0
## True: keep the Climbable's own beanstalk-vine look (used by the H-E shortcut); false: invisible pole (ladder mesh is separate).
@export var vine_look: bool = false

var climb: Area3D
var _cooldown := 0.0


func _ready() -> void:
	var axis := (top - foot).normalized()
	# Fix r1b: the player clamps pole travel to (height - 1.0), so the 0.35 m extension stopped Mak 0.55 m short of
	# the clamber point and the HUB-1 route stuck on L2 (hub1 autopilot FAIL "climb stuck" at y 7.86). The pole runs
	# 0.95 m past the top again; grabs from the cornice are prevented by `_gate_grab` instead.
	var length := (top - foot).length() + 0.95
	climb = Area3D.new()
	climb.name = "Climb"
	climb.set_script(load("res://scripts/objects/climbable.gd"))
	climb.set("height", length)
	climb.set("pole_radius", 0.12)
	climb.set("grab_radius", 0.55)
	# An empty Visual slot keeps the placeholder vine from being built; the ladder mesh is separate.
	if not vine_look:
		var v := Node3D.new()
		v.name = "Visual"
		var dummy := Node3D.new()
		dummy.name = "Generated"
		v.add_child(dummy)
		climb.add_child(v)
	else:
		climb.set("pole_radius", 0.25)
	# Orient local +Y along the ladder axis.
	var y := axis
	var x := y.cross(Vector3.BACK).normalized()
	if x.length() < 0.01:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	add_child(climb)
	climb.global_transform = Transform3D(Basis(x, y, z), foot)


var _grab_open := true


## r1 feel minor: the ladder top grabbed Mak when he hopped near it on the cornice. A Mak whose feet are at or
## above the exit level (and who is not already on this pole) cannot see the pole at all.
func _gate_grab(player: Node3D) -> void:
	var on_me: bool = player.get("pole") == climb and String(player.call("get_state_name")) == "pole_climb"
	var want: bool = on_me or player.global_position.y < exit_point.y - 0.6
	if want != _grab_open and _cooldown <= 0.0:
		_grab_open = want
		climb.set_deferred("monitorable", want)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if climb == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.has_method("get_state_name"):
		return
	_gate_grab(player)
	if _cooldown > 0.0:
		return
	if String(player.call("get_state_name")) != "pole_climb":
		return
	if player.get("pole") != climb:
		return
	var axis := (top - foot).normalized()
	var t := (player.global_position - foot).dot(axis)
	var tmax := (top - foot).length() + 0.1 - 0.05
	if t >= tmax - 0.15 and player.has_method("respawn"):
		_cooldown = 1.0
		# No re-grab for 0.8 s after the clamber (r1 feel: L2 grabbed Mak again right after the exit).
		climb.set_deferred("monitorable", false)
		climb.set_deferred("monitoring", false)
		get_tree().create_timer(0.8).timeout.connect(func() -> void:
			if is_instance_valid(climb):
				climb.set_deferred("monitorable", _grab_open)
				climb.set_deferred("monitoring", true))
		player.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(exit_yaw_deg)), exit_point + Vector3(0, 0.05, 0)))
		var audio := get_node_or_null("/root/Audio")
		if audio and audio.has_method("play_sfx"):
			audio.call("play_sfx", "ledge_climb", exit_point)

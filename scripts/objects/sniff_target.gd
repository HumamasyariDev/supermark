class_name SniffTarget
extends Node3D
## Something hidden that Snout Sniff can smell (group "sniff_target"). The player's sniff finds the nearest
## active target and draws a golden scent trail to get_sniff_position(); it calls on_sniffed(player) when it
## reaches the target or the player sniffs within `reveal_radius`. A brief golden wisp marks a sniffed spot.

signal sniffed(by: Node)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var scent_strength: float = 1.0
@export var reveal_radius: float = 2.5
@export var active: bool = true
## Reveal when a sniffing player stands within reveal_radius even if the player's own sniff never calls
## on_sniffed (kept as a safety net; tests turn it off to prove the real player path).
@export var proximity_fallback: bool = true

var was_sniffed := false
## Who revealed it, and how ("player" when the player's sniff called on_sniffed, "fallback" for the proximity check).
var last_sniffed_by: Node = null
var reveal_path := ""
var _wisp: GPUParticles3D


func _ready() -> void:
	add_to_group("sniff_target")
	_wisp = ObjSvc.sparkles(self, Color(1.0, 0.85, 0.4, 0.8), 14, 0.4, 0.16, 1.6, 0.8)
	_wisp.emitting = false


func is_sniff_active() -> bool:
	return active


func get_sniff_position() -> Vector3:
	return global_position


func get_scent_strength() -> float:
	return scent_strength


func on_sniffed(by: Node = null) -> void:
	if not active:
		return
	var first := not was_sniffed
	was_sniffed = true
	last_sniffed_by = by
	if reveal_path == "":
		reveal_path = "player"
	_wisp.emitting = true
	if first:
		ObjSvc.feedback("object_sniff_reveal", global_position, {}, "sniff_found")
		sniffed.emit(by)


## Fallback when the player has no sniff support yet: a sniffing player standing close reveals the target.
func _physics_process(_delta: float) -> void:
	if was_sniffed or not active or not proximity_fallback:
		return
	if Engine.get_physics_frames() % 6 != 0:
		return
	var p := ObjSvc.get_player()
	if p == null:
		return
	var st := ObjSvc.player_state(p).to_lower()
	if st.contains("sniff") and p.global_position.distance_to(global_position) <= reveal_radius:
		reveal_path = "fallback"
		on_sniffed(p)

class_name BouncePad
extends StaticBody3D
## Bouncy surface: group "bouncy" with meta bounce_velocity (m/s). The player launches itself on landing.
## Looks: a giant springy leaf, a candy gumdrop, or a drum skin. Squashes and wobbles when bounced.

signal bounced(body: Node)

enum Look { LEAF, GUMDROP, DRUM }

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var look: Look = Look.DRUM
@export var bounce_velocity: float = 16.0
@export var radius: float = 1.2
@export var gumdrop_color: Color = Color(1.0, 0.45, 0.65)
## Fallback only: call player.bounce() directly (leave off when the player handles "bouncy" itself).
@export var call_player_bounce: bool = false
## GUMDROP uses the meshes workstream's gumdrop glb when no visual_scene is set and the file exists.
@export var use_default_mesh: bool = true
@export_enum("pink", "mint", "orange", "violet") var gumdrop_flavour: String = "pink"

const GUMDROP_MESHES := {
	"pink": "res://assets/props/w3/gumdrop/gumdrop.glb",
	"mint": "res://assets/props/w3/gumdrop/gumdrop_mint.glb",
	"orange": "res://assets/props/w3/gumdrop/gumdrop_orange.glb",
	"violet": "res://assets/props/w3/gumdrop/gumdrop_violet.glb",
}
const GUMDROP_NATIVE := Vector2(1.0, 1.48)  # radius, height of the glb

var _visual: Node3D
var _squash: Node3D
var _top_y := 0.6
var _sensor: Area3D
var _squash_tw: Tween


func _ready() -> void:
	add_to_group("bouncy")
	set_meta("bounce_velocity", bounce_velocity)
	collision_layer = ObjSvc.L_WORLD
	collision_mask = 0
	match look:
		Look.LEAF:
			_top_y = 0.25
		Look.GUMDROP:
			_top_y = radius * 1.0
			var path: String = GUMDROP_MESHES.get(gumdrop_flavour, GUMDROP_MESHES["pink"])
			if visual_scene == null and use_default_mesh and ResourceLoader.exists(path):
				visual_scene = load(path) as PackedScene
				visual_scale = radius / GUMDROP_NATIVE.x
				_top_y = GUMDROP_NATIVE.y * visual_scale * 0.97
		Look.DRUM:
			_top_y = 0.75
	ObjSvc.add_shape(self, ObjSvc.cyl_shape(radius, _top_y), Vector3(0, _top_y * 0.5, 0))
	_visual = ObjSvc.ensure_visual(self)
	_squash = Node3D.new()
	_squash.name = "Squash"
	add_child(_squash)
	_visual.reparent(_squash, false)
	if not ObjSvc.visual_has_content(_visual):
		_build_placeholder()
	_sensor = ObjSvc.make_area(self, ObjSvc.cyl_shape(radius * 0.95, 0.5), ObjSvc.L_TRIGGER, ObjSvc.L_PLAYER, Vector3(0, _top_y + 0.2, 0), "Sensor")
	_sensor.body_entered.connect(_on_sensor)


func _build_placeholder() -> void:
	match look:
		Look.LEAF:
			var leaf := Node3D.new()
			leaf.position = Vector3(0, _top_y, 0)
			_visual.add_child(leaf)
			PlatformLook.build(leaf, Vector3(radius * 2.2, 0.3, radius * 2.6), PlatformLook.Kind.LEAF)
			ObjSvc.cylinder(_visual, 0.08, 0.12, _top_y, ObjSvc.mat(ObjSvc.BEAN.darkened(0.2), 0.5), Vector3(0, _top_y * 0.5, 0.3))
		Look.GUMDROP:
			var m := ObjSvc.mat(gumdrop_color, 0.2, 0.0, gumdrop_color, 0.15)
			m.clearcoat_enabled = true
			ObjSvc.sphere(_visual, radius, m, Vector3(0, 0, 0), Vector3(1, 1.0, 1))
			ObjSvc.cylinder(_visual, radius * 0.98, radius, 0.1, m, Vector3(0, 0.05, 0))
			var sugar := ObjSvc.mat(Color(1, 1, 1), 0.9)
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for i in 24:
				var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1), rng.randf_range(-1, 1)).normalized()
				ObjSvc.box(_visual, Vector3.ONE * 0.06, sugar, d * radius, Vector3(rng.randf() * 90, rng.randf() * 90, 0))
		Look.DRUM:
			var red := ObjSvc.mat(ObjSvc.BURGUNDY, 0.5)
			var brass := ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.8)
			var skin := ObjSvc.mat(Color(0.97, 0.92, 0.8), 0.7)
			ObjSvc.cylinder(_visual, radius, radius, _top_y - 0.08, red, Vector3(0, (_top_y - 0.08) * 0.5, 0))
			ObjSvc.torus(_visual, radius - 0.06, radius + 0.06, brass, Vector3(0, _top_y - 0.05, 0))
			ObjSvc.torus(_visual, radius - 0.06, radius + 0.06, brass, Vector3(0, 0.06, 0))
			ObjSvc.cylinder(_visual, radius - 0.04, radius - 0.04, 0.04, skin, Vector3(0, _top_y - 0.04, 0))
			# Zig-zag drum cords.
			for i in 10:
				var a := TAU * float(i) / 10.0
				var cord := ObjSvc.box(_visual, Vector3(0.04, _top_y * 0.9, 0.04), ObjSvc.mat(ObjSvc.PAPER, 0.8), Vector3(cos(a) * (radius + 0.02), _top_y * 0.5, sin(a) * (radius + 0.02)))
				cord.rotation = Vector3(0, -a, 0.35 if i % 2 else -0.35)


func _on_sensor(body: Node) -> void:
	if not ObjSvc.is_player(body):
		return
	var v: Variant = body.get("velocity")
	if v is Vector3 and (v as Vector3).y > 2.0:
		return
	squash()
	bounced.emit(body)
	ObjSvc.feedback("object_bounce_pad", global_position + Vector3(0, _top_y, 0), {"impact": bounce_velocity, "kind": str(["leaf", "gumdrop", "pad"][look])}, "bounce_" + str(["leaf", "gumdrop", "drum"][look]))
	if call_player_bounce and body.has_method("bounce"):
		body.call("bounce", bounce_velocity)


## Squash on the landing frame (wide and flat), spring to a tall stretch as Mak launches, then a damped jiggle.
## The pad's own top keeps its footprint: the squash is anchored at the base (the Squash node sits at y 0).
func squash() -> void:
	if _squash_tw and _squash_tw.is_valid():
		_squash_tw.kill()
	var tw := create_tween()
	_squash_tw = tw
	tw.tween_property(_squash, "scale", Vector3(1.28, 0.55, 1.28), 0.06).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_squash, "scale", Vector3(0.84, 1.24, 0.84), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_squash, "scale", Vector3(1.08, 0.94, 1.08), 0.1)
	tw.tween_property(_squash, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if ObjSvc.juice_handles("object_bounce_pad", "vfx"):
		return
	var top := global_position + Vector3(0, _top_y, 0)
	var col := Color(1, 1, 0.9) if look != Look.GUMDROP else gumdrop_color.lightened(0.4)
	ObjSvc.burst(get_parent(), top, col, 12, 3.0, 0.15, -6.0, 0.5)
	ObjFx.ground_ring(get_parent(), top, radius * 1.9, Color(col.r, col.g, col.b, 0.75), 0.35)
	if look == Look.LEAF:
		ObjSvc.burst(get_parent(), top, Color(0.5, 0.78, 0.3), 8, 3.5, 0.22, -5.0, 0.9)

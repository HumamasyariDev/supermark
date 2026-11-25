class_name NPCTalker
extends Talker
## An NPC that turns to face the player when near and talks with "interact".
## Look: a generated character GLB (`visual_scene`); without one it uses Bramwell's Tripo P2 model (D024: no primitive
## stand-in characters). The primitive tortoise remains only as a last-resort fallback when no GLB exists.
## NpcLife gives the model breathing, blinks, head turns toward Mak, ear/tail life, talking gestures and a greeting.
## Unrigged files with a rigged re-delivery (pip -> pip_v2) are swapped automatically (ObjSvc.RIGGED_UPGRADES).

@export var turn_speed: float = 5.0
@export var idle_bob: float = 0.03
@export var shell_color: Color = Color(0.42, 0.5, 0.25)
@export var skin_color: Color = Color(0.62, 0.74, 0.45)
## Use the default character (Bramwell) when no visual_scene is set.
@export var use_default_character: bool = true
## Swap unrigged character files for their rigged re-deliveries.
@export var upgrade_rigged_models: bool = true

const DEFAULT_CHARACTER := "res://assets/characters/bramwell/bramwell.glb"

var life: NpcLife
var _visual: Node3D
var _head: Node3D
var _home_yaw := 0.0
var _talk_watch := 0.0
var _prompt_h := 2.0
## Mak is greeted when he comes within this distance (2.5-4 m, before the talk zone, so the wave never clips him).
@export var greet_radius: float = 3.6
var _greeted := false


func _ready() -> void:
	ObjSvc.ensure_npc_life_auto(self)
	if visual_scene == null and use_default_character and ResourceLoader.exists(DEFAULT_CHARACTER):
		visual_scene = load(DEFAULT_CHARACTER) as PackedScene
	if upgrade_rigged_models and visual_scene != null:
		var up := ObjSvc.upgrade_character(visual_scene, visual_scale)
		visual_scene = up[0]
		visual_scale = up[1]
	super._ready()
	ObjSvc.add_shape(self, ObjSvc.cyl_shape(0.55, 1.5), Vector3(0, 0.75, 0))
	_visual = ObjSvc.ensure_visual(self)
	if not ObjSvc.visual_has_content(_visual):
		_build_tortoise()
	else:
		var gen := _visual.get_node_or_null("Generated") as Node3D
		life = NpcLife.attach(gen if gen != null else _visual)
		# Prompt bubble just above the character's head, whatever its size.
		# Measure the character only (the prompt bubble is also a child of this node).
		var bb := _visual.transform * ObjSvc.local_aabb(_visual)
		if bb.size.y > 0.2:
			_prompt_h = bb.end.y + 0.3
	_home_yaw = _visual.rotation.y


func _build_tortoise() -> void:
	var skin := ObjSvc.mat(skin_color, 0.55)
	var shell := ObjSvc.mat(shell_color, 0.5)
	var shell_rim := ObjSvc.mat(shell_color.lightened(0.25), 0.55)
	var coat := ObjSvc.mat(ObjSvc.BURGUNDY, 0.55)
	var black := ObjSvc.mat(Color(0.06, 0.05, 0.05), 0.35)
	var white := ObjSvc.mat(Color(1, 1, 1), 0.4)
	var brass := ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.85)
	# Feet and body (standing upright like a butler).
	ObjSvc.sphere(_visual, 0.16, skin, Vector3(-0.2, 0.1, -0.05), Vector3(1, 0.6, 1.4))
	ObjSvc.sphere(_visual, 0.16, skin, Vector3(0.2, 0.1, -0.05), Vector3(1, 0.6, 1.4))
	ObjSvc.capsule(_visual, 0.4, 1.0, coat, Vector3(0, 0.65, 0))
	ObjSvc.sphere(_visual, 0.32, ObjSvc.mat(Color(0.95, 0.9, 0.78), 0.6), Vector3(0, 0.7, -0.17), Vector3(1, 1.25, 0.6))
	for i in 3:
		ObjSvc.sphere(_visual, 0.03, brass, Vector3(0, 0.55 + i * 0.13, -0.36))
	# Shell on the back with plates.
	ObjSvc.sphere(_visual, 0.55, shell, Vector3(0, 0.75, 0.25), Vector3(1.0, 1.15, 0.65))
	ObjSvc.torus(_visual, 0.45, 0.58, shell_rim, Vector3(0, 0.75, 0.2), Vector3(90, 0, 0)).scale = Vector3(1, 1, 1.2)
	for k in 5:
		var a := TAU * float(k) / 5.0
		ObjSvc.sphere(_visual, 0.15, shell_rim, Vector3(cos(a) * 0.28, 0.78 + sin(a) * 0.32, 0.55), Vector3(1, 1, 0.35))
	# Arms (one behind the back, one holding a tiny teacup).
	ObjSvc.capsule(_visual, 0.08, 0.45, skin, Vector3(-0.42, 0.75, -0.05), Vector3(0, 0, -20))
	ObjSvc.capsule(_visual, 0.08, 0.45, skin, Vector3(0.42, 0.8, -0.15), Vector3(-60, 0, 25))
	ObjSvc.cylinder(_visual, 0.07, 0.05, 0.08, white, Vector3(0.48, 0.95, -0.38))
	ObjSvc.cylinder(_visual, 0.11, 0.11, 0.015, white, Vector3(0.48, 0.9, -0.38))
	# Head on a long wrinkly neck, with spectacles and bushy brows.
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 1.38, -0.12)
	_visual.add_child(_head)
	ObjSvc.capsule(_visual, 0.11, 0.35, skin, Vector3(0, 1.2, -0.08), Vector3(-10, 0, 0))
	ObjSvc.sphere(_head, 0.24, skin, Vector3.ZERO, Vector3(1.0, 0.9, 1.1))
	ObjSvc.sphere(_head, 0.15, skin, Vector3(0, -0.06, -0.17), Vector3(1.1, 0.7, 0.8))
	for sx in [-1.0, 1.0]:
		ObjSvc.sphere(_head, 0.07, white, Vector3(sx * 0.1, 0.05, -0.19))
		ObjSvc.sphere(_head, 0.04, black, Vector3(sx * 0.1, 0.05, -0.25))
		ObjSvc.torus(_head, 0.075, 0.095, brass, Vector3(sx * 0.1, 0.05, -0.24), Vector3(90, 0, 0))
		ObjSvc.capsule(_head, 0.025, 0.14, ObjSvc.mat(Color(0.92, 0.92, 0.88), 0.8), Vector3(sx * 0.11, 0.16, -0.2), Vector3(0, 0, 90 + sx * 12))
	ObjSvc.box(_head, Vector3(0.14, 0.015, 0.02), black, Vector3(0, -0.1, -0.29))
	# Bow tie and collar.
	ObjSvc.sphere(_visual, 0.07, black, Vector3(-0.08, 1.08, -0.3), Vector3(1.2, 0.8, 0.6))
	ObjSvc.sphere(_visual, 0.07, black, Vector3(0.08, 1.08, -0.3), Vector3(1.2, 0.8, 0.6))
	ObjSvc.sphere(_visual, 0.035, black, Vector3(0, 1.08, -0.33))


func _prompt_height() -> float:
	return _prompt_h


## Rigged characters: over the head bone (x/z follow the head), at least 0.3 m above the model's top (follows the head as it turns); otherwise above the model's bounds.
func _prompt_anchor() -> Vector3:
	if life != null and life.skel != null and is_inside_tree():
		var hi := life.skel.find_bone("head")
		if hi >= 0:
			var hp := life.skel.global_transform * life.skel.get_bone_global_pose(hi).origin
			var lp := to_local(hp)
			# The head bone sits at the neck; big storybook heads need the model's top, so the bubble never covers
			# the face (r2 clip: it sat on Pip's face).
			return Vector3(lp.x, maxf(lp.y + 0.35, _prompt_h), lp.z)
	return Vector3(0, _prompt_height(), 0)


func _process(delta: float) -> void:
	super._process(delta)
	if _visual == null:
		return
	var target_yaw := _home_yaw
	if player_near != null and is_instance_valid(player_near):
		var to := player_near.global_position - global_position
		to.y = 0.0
		if to.length() > 0.05:
			# Visual faces -Z, so yaw = atan2(-x, -z) in the parent's frame.
			var local := global_transform.basis.inverse() * to
			target_yaw = atan2(-local.x, -local.z)
	# Rigged characters turn the head first (NpcLife), so the body follows more lazily.
	var ts := turn_speed * (0.45 if life != null and life.skel != null else 1.0)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clampf(ts * delta, 0.0, 1.0))
	if life == null:
		_visual.position.y = sin(_t * 2.0) * idle_bob
	if _head:
		_head.rotation.z = sin(_t * 1.3) * 0.06
	_greet_check()
	# Talking gestures last while the dialog box is open.
	if life != null and life.talking:
		_talk_watch += delta
		var open := _talk_watch < 2.5
		if ObjSvc.can("UI", "is_dialog_open"):
			open = _talk_watch < 0.2 or bool(ObjSvc.call_on("UI", "is_dialog_open"))
		if not open:
			life.talking = false


func talk() -> void:
	super.talk()
	_talk_watch = 0.0
	if life != null:
		life.talking = true
	_make_room()


## Critique objects r1 re-run: the talk zone let Mak stand closer than the two models' radii (his snout sank into
## Pip's cheek). On talk start Mak eases back to at least the NPC's footprint radius + 0.55 m along the line between
## them over 0.25 s, and turns to face the NPC (the NPC already turns to him).
## Camera finish pass (owner: "a clear hitch" walking up to the first NPC): both eases now run on physics ticks and the
## walk-in velocity is cleared first. Run on render frames, they set the body between physics ticks while the
## interpolated transform (which the camera and the model follow) still blended from the last tick, and the leftover
## walk velocity pushed Mak back into the NPC each tick: Mak and the camera stuttered for a quarter second.
var _npc_radius := -1.0


func npc_radius() -> float:
	if _npc_radius < 0.0:
		_npc_radius = 0.55
		if _visual != null:
			var bb := _visual.transform * ObjSvc.local_aabb(_visual)
			if bb.size.y > 0.2:
				_npc_radius = maxf(0.55, maxf(maxf(absf(bb.position.x), absf(bb.end.x)), maxf(absf(bb.position.z), absf(bb.end.z))) * 0.8)
	return _npc_radius


func _make_room() -> void:
	var p := ObjSvc.get_player()
	if p == null or not is_instance_valid(p):
		return
	var from := p.global_position
	var d := from - global_position
	d.y = 0.0
	var need := npc_radius() + 0.55
	var dir := d.normalized() if d.length() > 0.05 else global_basis.z.normalized()
	var to_face := -dir
	var yaw := atan2(-to_face.x, -to_face.z)
	if "velocity" in p:
		var v: Vector3 = p.get("velocity")
		p.set("velocity", Vector3(0.0, v.y, 0.0))
	if "facing_yaw" in p:
		var y0: float = p.get("facing_yaw")
		var ft := p.create_tween()
		ft.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		ft.tween_method(func(t: float) -> void:
			if is_instance_valid(p):
				p.set("facing_yaw", lerp_angle(y0, yaw, t)), 0.0, 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if d.length() >= need:
		return
	var target := global_position + dir * need
	target.y = from.y
	# Do not ease Mak into a wall: keep the move only when the capsule fits at the target.
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.2
	q.shape = cap
	q.collision_mask = ObjSvc.L_WORLD
	q.exclude = [get_rid()]
	q.transform = Transform3D(Basis(), target + Vector3(0, 0.7, 0))
	if not space.intersect_shape(q, 1).is_empty():
		return
	var mt := p.create_tween()
	mt.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	mt.tween_method(func(t: float) -> void:
		if is_instance_valid(p):
			p.global_position = from.lerp(target, t), 0.0, 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _talk_event() -> String:
	return "object_npc_talk"


## Greets once when Mak comes within greet_radius; re-arms when he is 2.5 m beyond it.
func _greet_check() -> void:
	if life == null:
		return
	var p := ObjSvc.get_player()
	if p == null:
		return
	var d := ObjSvc.body_pos(p).distance_to(global_position)
	if not _greeted and d < greet_radius:
		_greeted = true
		prewarm_portrait()
		life.greet()
		ObjSvc.feedback("object_npc_greet", global_position + Vector3(0, 1.2, 0), {"speaker": speaker})
	elif _greeted and d > greet_radius + 2.5:
		_greeted = false


func is_facing_player(tolerance_deg: float = 25.0) -> bool:
	if player_near == null:
		return false
	var to := player_near.global_position - global_position
	to.y = 0.0
	var fwd := -_visual.global_transform.basis.z
	fwd.y = 0.0
	return rad_to_deg(fwd.angle_to(to)) < tolerance_deg

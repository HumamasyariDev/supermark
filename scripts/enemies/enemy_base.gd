class_name EnemyBase
extends CharacterBody3D
## Shared enemy body, hit logic, state machine helpers and procedural animation.
##
## Layers: body on layer 3 (enemy) colliding with world (1); hurtbox Area3D on layer 7;
## HeadZone Area3D watches the player (layer 2) for stomps and Ham Slams.
## States used by every family: idle/patrol -> notice -> windup -> attack -> recover,
## plus hurt and defeat. Families add their own (skid, dizzy, perch, ...).
##
## Visual layout (see res://scenes/enemies/README.md):
##   Visual (Node3D, faces -Z)
##     Rig (Node3D: bob, squash, lean, tilt and spin are applied here)
##       Placeholder (procedural smooth-primitive toy, hidden when a mesh exists)
##       Mesh (res://assets/enemies/<id>/<id>.glb, rotated 180 degrees so +Z models face -Z)
## Named parts or bones animated when present: body, head, arm_l, arm_r, leg_l, leg_r, wing_l, wing_r, tail.

signal defeated(enemy: Node)
signal state_changed(from_state: String, to_state: String)
signal hit_taken(kind: String, landed: bool)

const PART_NAMES: Array[String] = ["body", "head", "arm_l", "arm_r", "leg_l", "leg_r", "wing_l", "wing_r", "tail",
	"jaw", "beak", "ear_l", "ear_r", "tail_2", "forearm_l", "forearm_r", "hand_l", "hand_r", "shin_l", "shin_r",
	"hips", "spine_2", "stinger", "pod_l", "pod_r", "stem"]
const GRAVITY := 24.0
## OPUSLOOK: barks are speech for the enemy Mak is dealing with. Further away than the UI barks' range (UIBarks.FAR,
## 18 m, plus a margin) they showed as specks of text through the scenery ("Caw caw!" from 40 m), so they are skipped.
const SAY_RANGE := 22.0

@export var enemy_id: String = "enemy"
@export var display_name: String = "Enemy"
@export var max_hp: int = 1
@export var notice_radius: float = 9.0
@export var lose_radius: float = 16.0
@export var move_speed: float = 2.0
@export var turn_speed: float = 7.0
@export var uses_gravity: bool = true
@export var contact_damage: bool = true
@export var acorns_on_defeat: int = 1
@export var body_radius: float = 0.45
@export var body_height: float = 1.0
@export var head_height: float = 1.0
@export var stomp_bounce: float = 9.0
@export var patrol_points: Array[Vector3] = []
@export var patrol_wait: float = 1.2
@export var ai_enabled: bool = true
@export var mesh_path: String = ""

var block_text: String = "CLANG!"

var state: String = "idle"
var prev_state: String = ""
var state_time: float = 0.0
var hp: int = 1
var home: Vector3 = Vector3.ZERO
var player: Node3D
var is_defeated: bool = false

var visual: Node3D
var rig: Node3D
var placeholder: Node3D
var mesh_root: Node3D
var hurtbox: EnemyHurtbox
var head_zone: Area3D
var body_shape: CollisionShape3D

var parts: Dictionary = {}
var part_rest: Dictionary = {}
var skeleton: Skeleton3D
var bone_ids: Dictionary = {}
var bone_rest: Dictionary = {}
var bone_parent_basis: Dictionary = {}
## Extra bone names accepted for a part (rigs often call the upper leg "thigh").
var bone_aliases: Dictionary = {"leg_l": ["thigh_l", "upperleg_l"], "leg_r": ["thigh_r", "upperleg_r"],
	"arm_l": ["upperarm_l", "shoulder_l"], "arm_r": ["upperarm_r", "shoulder_r"], "body": ["spine", "torso"],
	"wing_l": ["arm_l"], "wing_r": ["arm_r"]}
## Multiplies the squash scale on the rig (inflate gags on static meshes).
var scale_mult: Vector3 = Vector3.ONE
var pose_target: Dictionary = {}
var pose_cur: Dictionary = {}

## Procedural rig channels (radians / metres); families set them in _animate().
var bob: float = 0.0
var lean: float = 0.0
var tilt: float = 0.0
var spin: float = 0.0
var squash: float = 0.0
var squash_vel: float = 0.0
var squash_stiffness: float = 220.0
var squash_damping: float = 11.0
var walk_phase: float = 0.0
var look_target: Vector3 = Vector3.INF

var knockback: Vector3 = Vector3.ZERO
var _hit_cooldown: float = 0.0
var _contact_cooldown: float = 0.0
var _stomp_lock: float = 0.0
var _patrol_index: int = 0
var _patrol_pause: float = 0.0
var _blink_t: float = 2.0
var _eyes: Array[Node3D] = []
var _pupils: Array[Node3D] = []
var _flash: ShaderMaterial
var _flash_rim: float = 0.0
var _flash_tint: Color = Color(1, 1, 1, 0)
var _flash_t: float = 0.0
var _flash_len: float = 0.18
var _flash_peak: float = 0.85
var _flash_us: int = 0
## Notice take per family (finish pass, r1 animation major: all six families shared one 0.22 m hop): hop height (m),
## extra vertical stretch, and length (s).
var notice_hop: float = 0.22
var notice_stretch: float = 0.12
var notice_len: float = 0.42
var _rng := RandomNumberGenerator.new()
## Polish channels (night 01 enemies v2): notice take hop, local hit-stop, turn banking, breathing, blob shadow.
var _take_t: float = 0.0
var _freeze_t: float = 0.0
var _bank: float = 0.0
var _last_yaw: float = 0.0
var _breath_phase: float = 0.0
var _shadow: MeshInstance3D
var _anim_t: float = 0.0
var _toon_applied: bool = false
## Fix round 1 (critique r1): additive cycle channels that bypass the base-pose ease, per-part snap rates for accents,
## directional flinch, lethal-stomp pancake beat, ground snap, fall-out guard, attack tokens.
var pose_add: Dictionary = {}
var pose_add_cur: Dictionary = {}
var pose_add_raw: Dictionary = {}
var pose_rate: Dictionary = {}
var _hit_dir_local: Vector3 = Vector3(0, 0, 1)
var _last_hit_kind: String = ""
var _pancake_t: float = -1.0
var _gag_kind: String = ""
var _gag_from: Vector3 = Vector3.ZERO
var _snap_pending: bool = false
var _snap_tries: int = 0
var _fall_resets: int = 0
var _token_wait: float = 0.0
var _visual_scale_want: float = 1.0
var _block_text_once: String = ""
var _push_cd: float = 0.0
var _yaw_rate: float = 0.0
var _hurt_player_at: float = -10.0
## Rim falloff of the wind-up telegraph overlay (higher = thinner edge glow; thin meshes like the crow need 4).
var rim_power: float = 2.2
## Ink outline width for FxToon (per family: lumpy fleece and feathers freckle at 1.6).
var outline_width: float = 1.3
var outline_color: Color = Color(-1, -1, -1)
## Toon rim strength per family (a brighter rim lifts a cookie off a caramel ramp).
var toon_rim: float = 0.45
## Planted enemies (peapod) snap to the ground once and then ignore gravity.
var planted: bool = false
## Wind-up length per family, so contact only hurts in its last 0.25 s (DESIGN_V2: no damage without a telegraph).
var windup_len: float = 0.85
## Fix round 2 (critique r1 re-check): forward root slide of the rig in metres (thrust lunges), bone scale targets
## (exaggerated gummy fists), time on screen (attacks need 0.4 s inside the camera frustum: no offscreen damage).
var lunge: float = 0.0
var pose_scale_target: Dictionary = {}
var pose_scale_cur: Dictionary = {}
var _onscreen_t: float = 0.0
var _spark_at: Vector3 = Vector3.INF


func _ready() -> void:
	home = global_position
	_rng.seed = hash(name) ^ int(global_position.x * 13.0 + global_position.z * 7.0)
	_blink_t = _rng.randf_range(1.0, 3.5)
	add_to_group("enemy")
	collision_layer = 1 << 2
	collision_mask = 1
	floor_snap_length = 0.3
	_setup()
	hp = max_hp
	_build_collision()
	_build_visual()
	_breath_phase = _rng.randf() * TAU
	_last_yaw = rotation.y
	if not uses_gravity and not planted:
		_build_shadow()
	# Ground walkers and planted enemies wait (no gravity) until a ray finds the floor under them, then snap onto
	# it: world collision can arrive a frame late, which let W2's garden pod E02 fall through the world (r1 M2).
	_snap_pending = uses_gravity or planted
	set_state(_initial_state())


# ------------------------------------------------------------------ virtuals

func _setup() -> void:
	pass


func _initial_state() -> String:
	return "patrol" if patrol_points.size() > 0 else "idle"


func _build_placeholder(_root: Node3D) -> void:
	pass


func _ai(_delta: float) -> void:
	pass


func _animate(_delta: float) -> void:
	pass


## Returns "damage", "block", "bounce" (player bounces, no damage) or "ignore".
func _resolve_hit(_kind: String, _from_position: Vector3) -> String:
	return "damage"


func _contact_active() -> bool:
	return state != "hurt" and state != "dizzy" and state != "stunned"


func _on_hurt_player(_p: Node3D) -> void:
	pass


func _on_enter_state(_s: String) -> void:
	pass


## Plays the defeat gag; return its length in seconds. Default: launched spin.
func _defeat_gag(_kind: String, from_position: Vector3) -> float:
	var away := global_position - from_position
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else -global_transform.basis.z
	velocity = away * 4.0 + Vector3.UP * 7.0
	return 0.9


func _defeat_process(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	global_position += velocity * delta
	spin += delta * 18.0
	rig.scale = rig.scale.lerp(Vector3.ONE * 0.5, delta * 2.0)


func _defeat_burst() -> void:
	EnemyKit.burst(get_parent(), global_position + Vector3(0, head_height * 0.5, 0), "confetti",
		[Color(1, 0.85, 0.3), Color(1, 0.45, 0.5), Color(0.5, 0.8, 1)], 36, 6.0)


# ------------------------------------------------------------------ construction

func _build_collision() -> void:
	body_shape = CollisionShape3D.new()
	body_shape.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = body_radius
	cap.height = maxf(body_height, body_radius * 2.0)
	body_shape.shape = cap
	body_shape.position = Vector3(0, cap.height * 0.5, 0)
	add_child(body_shape)

	hurtbox = EnemyHurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.enemy = self
	var hcs := CollisionShape3D.new()
	var hcap := CapsuleShape3D.new()
	hcap.radius = body_radius + 0.15
	hcap.height = maxf(head_height + 0.2, hcap.radius * 2.0)
	hcs.shape = hcap
	hcs.position = Vector3(0, hcap.height * 0.5, 0)
	hurtbox.add_child(hcs)
	add_child(hurtbox)

	head_zone = Area3D.new()
	head_zone.name = "HeadZone"
	head_zone.collision_layer = 0
	head_zone.collision_mask = 1 << 1
	head_zone.monitorable = false
	var zcs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	# Tight head zone (was body_radius + 0.25 against Mak's whole capsule: side drops counted as stomps, r1 fun).
	cyl.radius = body_radius + 0.05
	cyl.height = 0.6
	zcs.shape = cyl
	zcs.position = Vector3(0, head_height + 0.15, 0)
	head_zone.add_child(zcs)
	add_child(head_zone)


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	rig = Node3D.new()
	rig.name = "Rig"
	visual.add_child(rig)
	placeholder = Node3D.new()
	placeholder.name = "Placeholder"
	rig.add_child(placeholder)
	_build_placeholder(placeholder)
	var path := mesh_path if mesh_path != "" else "res://assets/enemies/%s/%s.glb" % [enemy_id, enemy_id]
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			mesh_root = Node3D.new()
			mesh_root.name = "Mesh"
			mesh_root.rotation_degrees.y = 180.0
			rig.add_child(mesh_root)
			var inst := ps.instantiate()
			mesh_root.add_child(inst)
			placeholder.visible = false
			_on_mesh_ready(inst)
			apply_toon(inst)
	_collect_parts(mesh_root if mesh_root != null else placeholder)
	for n in placeholder.find_children("eye_*", "Node3D", true, false):
		_eyes.append(n as Node3D)
	for n in placeholder.find_children("pupil", "Node3D", true, false):
		_pupils.append(n as Node3D)
	_flash = ShaderMaterial.new()
	_flash.shader = _flash_shader()
	_flash.set_shader_parameter("tint", Color(1, 1, 1, 0))
	_flash.set_shader_parameter("rim_power", rim_power)
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _flash


static var _flash_shader_cache: Shader


## Overlay used for hit flashes (full tint) and telegraphs (rim glow that keeps the face readable:
## the flat orange tint hid the peapod's face during its wind-up, *__peapod windup frames, night 01 r3).
static func _flash_shader() -> Shader:
	if _flash_shader_cache == null:
		_flash_shader_cache = Shader.new()
		_flash_shader_cache.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float rim_only = 0.0;
uniform float rim_power = 2.2;
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float a = tint.a * mix(1.0, clamp(fres * 1.8 + 0.1, 0.0, 1.0), rim_only);
	ALBEDO = tint.rgb;
	ALPHA = a;
}
"""
	return _flash_shader_cache


## Storybook toon look shared with Mak (FxToon: two-tone ramp, rim, ink outline), chosen over raw PBR from the
## side-by-side in Docs/progress/enemies_v2 (*__fxtoon_side_by_side_*). Translucent surfaces (bee wings, gummy
## jelly) are skipped by FxToon. Dev arg --pbr keeps the generated PBR materials for A/B captures.
func apply_toon(inst: Node) -> void:
	if Dev.has_arg("pbr"):
		return
	var opts := {"rim": toon_rim, "outline_width": outline_width}
	if outline_color.r >= 0.0:
		opts["outline_color"] = outline_color
	FxToon.apply(inst, opts)
	_toon_applied = true


## Families adjust materials, attach props or bone sockets here (also called after a mesh swap).
func _on_mesh_ready(_inst: Node) -> void:
	pass


## Soft round contact shadow that follows the ground under flyers, so their height always reads.
func _build_shadow() -> void:
	_shadow = MeshInstance3D.new()
	_shadow.name = "BlobShadow"
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = q
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;\nuniform float alpha = 0.45;\nvoid fragment() {\n\tfloat d = length(UV - vec2(0.5)) * 2.0;\n\tALBEDO = vec3(0.05, 0.04, 0.08);\n\tALPHA = alpha * smoothstep(1.0, 0.35, d);\n}\n"
	m.shader = sh
	_shadow.material_override = m
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)


func _update_shadow() -> void:
	if _shadow == null:
		return
	if is_defeated and state_time > 0.6:
		_shadow.visible = false
		return
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), global_position + Vector3(0, -25, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_shadow.visible = false
		return
	_shadow.visible = true
	var h := global_position.y - (hit.position as Vector3).y
	var sz := body_radius * 2.6 * clampf(1.15 - h * 0.08, 0.45, 1.15)
	_shadow.global_transform = Transform3D(Basis().scaled(Vector3(sz, 1, sz)), (hit.position as Vector3) + Vector3(0, 0.03, 0))
	(_shadow.material_override as ShaderMaterial).set_shader_parameter("alpha", clampf(0.55 - h * 0.05, 0.18, 0.55))


## Sends a semantic feedback event to the Juice autoload (Docs/JUICE.md) with the family id attached.
func juice(event_name: String, params: Dictionary = {}, at: Vector3 = Vector3.INF) -> void:
	var p := params.duplicate()
	p["family"] = enemy_id
	if not p.has("node"):
		p["node"] = self
	# Sounds: the enemy plays its own unless the audio track's JuiceSfx really owns this event (no doubles, no gaps).
	if not EnemyKit.juice_sfx_owns(self, event_name):
		p["silent"] = true
	EnemyKit.juice(self, event_name, global_position + Vector3(0, head_height * 0.6, 0) if at == Vector3.INF else at, p)


## True when Juice spawns the effect for this moment; the enemy then skips its own fallback effect.
func owns(event_name: String) -> bool:
	return EnemyKit.juice_handles(self, event_name, "vfx")


## True when the audio track's JuiceSfx voices this moment.
func owns_sfx(event_name: String) -> bool:
	return EnemyKit.juice_sfx_owns(self, event_name)


## Plays the enemy's own sound for a moment unless JuiceSfx already voices it.
func moment_sfx(event_name: String, key: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not owns_sfx(event_name):
		EnemyKit.sfx(self, key, global_position, pitch, volume_db)


## Dizzy / winded start and end (Juice: orbiting stars loop on the enemy, bonk sound).
func stunned(on: bool) -> void:
	if on:
		juice("enemy_stunned", {}, global_position + Vector3(0, head_height * 0.6, 0))
	else:
		juice("enemy_recover", {})


func _collect_parts(root: Node3D) -> void:
	parts.clear()
	part_rest.clear()
	bone_ids.clear()
	bone_rest.clear()
	bone_parent_basis.clear()
	for pname in PART_NAMES:
		var n := _find_named(root, pname)
		if n != null:
			parts[pname] = n
			part_rest[pname] = n.transform
	skeleton = null
	gait_hip_h = -1.0
	var skels := root.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		skeleton = skels[0] as Skeleton3D
		for pname in PART_NAMES:
			var names: Array = [pname]
			names.append_array(bone_aliases.get(pname, []))
			for cand in names:
				if bone_ids.has(pname):
					break
				for i in skeleton.get_bone_count():
					var bn := skeleton.get_bone_name(i).to_lower()
					if bn == cand or bn.ends_with("_" + cand) or bn.ends_with("." + cand) or bn.ends_with(":" + cand) or bn.ends_with("-" + cand):
						bone_ids[pname] = i
						bone_rest[pname] = skeleton.get_bone_rest(i).basis
						var par := skeleton.get_bone_parent(i)
						bone_parent_basis[pname] = skeleton.get_bone_global_rest(par).basis if par >= 0 else Basis()
						break


func _find_named(root: Node, pname: String) -> Node3D:
	if root == null:
		return null
	for c in root.get_children():
		if c is Node3D:
			var cn := String(c.name).to_lower()
			if cn == pname or cn.begins_with(pname + "_geo") or cn.begins_with(pname + "."):
				return c as Node3D
	for c in root.get_children():
		var r := _find_named(c, pname)
		if r != null:
			return r
	return null


# ------------------------------------------------------------------ loop

func _physics_process(delta: float) -> void:
	_anim_t += delta
	if _freeze_t > 0.0:
		# Local hit-stop: hold the pose, shiver the visual, keep timers frozen.
		_freeze_t -= delta
		if visual != null:
			visual.position = Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0)) * 0.035
		return
	if visual != null and visual.position != Vector3.ZERO:
		visual.position = Vector3.ZERO
	_take_t = maxf(0.0, _take_t - delta)
	_update_shadow()
	_hit_cooldown = maxf(0.0, _hit_cooldown - delta)
	_contact_cooldown = maxf(0.0, _contact_cooldown - delta)
	_stomp_lock = maxf(0.0, _stomp_lock - delta)
	_push_cd = maxf(0.0, _push_cd - delta)
	_token_wait = maxf(0.0, _token_wait - delta)
	_track_onscreen(delta)
	state_time += delta
	if visual != null and absf(visual.scale.x - _visual_scale_want) > 0.001:
		# The enemy owns its Visual scale (measured to spec). A builder rescale compounded it (W3 Snap at 2.02 m, r1 M1).
		push_warning("[%s] Visual scale %.3f set from outside; the enemy keeps its measured %.3f" % [name, visual.scale.x, _visual_scale_want])
		visual.scale = Vector3.ONE * _visual_scale_want
	if is_defeated:
		if _pancake_t >= 0.0:
			_pancake_process(delta)
		else:
			_defeat_process(delta)
		_apply_pose(delta)
		return
	if _snap_pending:
		_try_ground_snap()
		_animate(delta)
		_apply_pose(delta)
		return
	if global_position.y < home.y - 12.0:
		_fall_out_reset()
	player = EnemyKit.find_player(get_tree())
	if state == "hurt":
		_hurt_process(delta)
	elif ai_enabled:
		_ai(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		if not uses_gravity:
			velocity.y = move_toward(velocity.y, 0.0, 20.0 * delta)
	if uses_gravity:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		elif velocity.y < 0.0:
			velocity.y = 0.0
		_ledge_guard()
	move_and_slide()
	_check_head_zone()
	_check_contact()
	_animate(delta)
	_apply_pose(delta)


func _hurt_process(delta: float) -> void:
	velocity.x = knockback.x
	velocity.z = knockback.z
	knockback = knockback.move_toward(Vector3.ZERO, 14.0 * delta)
	if not uses_gravity:
		velocity.y = move_toward(velocity.y, 0.0, 10.0 * delta)
	if state_time > 0.55:
		set_state(_after_hurt_state())


func _after_hurt_state() -> String:
	return "recover"


# ------------------------------------------------------------------ ground, ledges, fall-out (fix round 1)

## Floor height under p (ray from p.y + up down to p.y - down), or NAN when nothing is there.
func floor_y_at(p: Vector3, up: float = 0.5, down: float = 10.0) -> float:
	if not is_inside_tree():
		return NAN
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, up, 0), p + Vector3(0, -down, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else NAN


func _try_ground_snap() -> void:
	velocity = Vector3.ZERO
	_snap_tries += 1
	var near := floor_y_at(global_position, 0.5, 10.0)
	var y := near
	if is_nan(near) or absf(near - global_position.y) > 0.6:
		var high := floor_y_at(global_position, 3.0, 13.0)
		if not is_nan(high):
			y = high
	if is_nan(y):
		if _snap_tries < 150:
			return
		# No floor after 2.5 s: give up the hold (a floating spot is better than falling forever).
		_snap_pending = false
		return
	global_position.y = y + 0.02
	home.y = global_position.y
	reset_physics_interpolation()
	_snap_pending = false
	if planted:
		uses_gravity = false


func _fall_out_reset() -> void:
	# Fell off the map: come back home with a poof instead of falling forever (an EnemyGroup could never clear).
	_fall_resets += 1
	if _fall_resets > 3:
		acorns_on_defeat = 0
		defeat("fall", global_position)
		return
	global_position = home + Vector3(0, 0.3, 0)
	velocity = Vector3.ZERO
	knockback = Vector3.ZERO
	reset_physics_interpolation()
	EnemyKit.poof(get_parent(), home + Vector3(0, 0.4, 0), 0.7)
	set_state(_initial_state())


## Ground enemies never walk, lunge or get knocked off a drop of more than 1.5 m.
func _ledge_guard() -> void:
	if not is_on_floor():
		return
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() < 0.3:
		return
	var probe := global_position + hv.normalized() * (body_radius + 0.3 + hv.length() * 0.05)
	if is_nan(floor_y_at(probe, 0.5, 1.5)):
		velocity.x = 0.0
		velocity.z = 0.0
		knockback = Vector3.ZERO
		_on_ledge()


## Called when the ledge guard stops the enemy at a drop (families add a teeter).
func _on_ledge() -> void:
	pass


## True when there is a drop of more than `drop` metres `dist` metres ahead along dir.
func drop_ahead(dir: Vector3, dist: float, drop: float = 1.5) -> bool:
	var d := Vector3(dir.x, 0, dir.z)
	if d.length() < 0.01:
		return false
	return is_nan(floor_y_at(global_position + d.normalized() * dist, 0.6, drop))


# ------------------------------------------------------------------ attack tokens (fix round 1)

## Asks the shared token pool for an attack slot (at most 2 melee wind-ups and 2 volleys near Mak at once).
## On refusal the enemy holds its "ready" pose and may ask again after 0.3-0.6 s.
func request_attack(kind: String = "melee") -> bool:
	if _token_wait > 0.0:
		return false
	if _onscreen_t < 0.4:
		# No attack starts until the enemy has been on screen for 0.4 s (DESIGN_V2: no damage from offscreen, r1 fun).
		_token_wait = 0.15
		return false
	if EnemyKit.request_attack(self, kind):
		return true
	_token_wait = _rng.randf_range(0.3, 0.6)
	return false


## Seconds this enemy has been inside the current camera's frustum (body centre). Without a camera it counts as seen.
func _track_onscreen(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		_onscreen_t = 9.0
		return
	var c := global_position + Vector3(0, head_height * 0.5, 0)
	if cam.is_position_in_frustum(c) and cam.global_position.distance_to(c) < 60.0:
		_onscreen_t += delta
	else:
		_onscreen_t = 0.0


func on_screen_for() -> float:
	return _onscreen_t


func _resize_collision() -> void:
	if body_shape != null and body_shape.shape is CapsuleShape3D:
		var cap := body_shape.shape as CapsuleShape3D
		cap.radius = body_radius
		cap.height = maxf(body_height, body_radius * 2.0)
		body_shape.position = Vector3(0, cap.height * 0.5, 0)
	if hurtbox != null and hurtbox.get_child_count() > 0:
		var hcs := hurtbox.get_child(0) as CollisionShape3D
		var hcap := hcs.shape as CapsuleShape3D
		hcap.radius = body_radius + 0.15
		hcap.height = maxf(head_height + 0.2, hcap.radius * 2.0)
		hcs.position = Vector3(0, hcap.height * 0.5, 0)
	if head_zone != null and head_zone.get_child_count() > 0:
		var zcs := head_zone.get_child(0) as CollisionShape3D
		(zcs.shape as CylinderShape3D).radius = body_radius + 0.05
		zcs.position = Vector3(0, head_height + 0.15, 0)


## Lowest point Mak's feet may be at for a stomp to count (a drop past the flank is not a stomp).
func stomp_min_y() -> float:
	return global_position.y + head_height * 0.6


# ------------------------------------------------------------------ state helpers

func set_state(s: String) -> void:
	if s == state and state_time < 0.0001:
		return
	prev_state = state
	state = s
	state_time = 0.0
	if s != "windup" and s != "attack" and s != "paw":
		EnemyKit.release_attack(self)
	state_changed.emit(prev_state, s)
	if s == "windup" or s == "paw":
		# Generic attack telegraph that also reads on generated meshes: a hot orange pulse and a glint.
		flash(Color(1.0, 0.5, 0.1), 0.6, 0.95, true)
		if not owns("enemy_windup"):
			EnemyKit.burst(get_parent(), global_position + Vector3(0, head_height + 0.2, 0), "stars", [Color(1, 0.6, 0.2), Color(1, 1, 0.7)], 8, 2.5)
		moment_sfx("enemy_windup", "enemy_windup")
		juice("enemy_windup", {}, global_position + Vector3(0, head_height + 0.1, 0))
	elif s == "attack":
		juice("enemy_attack", {"direction": forward()}, global_position + Vector3(0, head_height * 0.5, 0))
	_on_enter_state(s)


## Tints the whole visual (placeholder or generated mesh) for a moment.
func flash(color: Color, length: float = 0.18, peak: float = 0.85, rim_only: bool = false) -> void:
	if _flash == null:
		return
	_flash_rim = 1.0 if rim_only else 0.0
	_flash.set_shader_parameter("rim_only", _flash_rim)
	_flash_tint = Color(color.r, color.g, color.b, peak)
	_flash.set_shader_parameter("tint", _flash_tint)
	_flash_len = length
	_flash_peak = peak
	_flash_t = length
	_flash_us = Time.get_ticks_usec()


func player_pos() -> Vector3:
	return player.global_position if player != null and is_instance_valid(player) else Vector3.INF


func dist_to_player() -> float:
	if player == null or not is_instance_valid(player):
		return INF
	return global_position.distance_to(player.global_position)


func flat_dist_to_player() -> float:
	if player == null or not is_instance_valid(player):
		return INF
	var d := player.global_position - global_position
	d.y = 0
	return d.length()


func flat_dir_to(p: Vector3) -> Vector3:
	var d := p - global_position
	d.y = 0
	return d.normalized() if d.length() > 0.001 else -global_transform.basis.z


func forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0
	return f.normalized()


func face_toward(p: Vector3, delta: float, speed: float = -1.0) -> void:
	var d := p - global_position
	d.y = 0
	if d.length() < 0.01:
		return
	var target_yaw := atan2(-d.x, -d.z)
	var s := turn_speed if speed < 0.0 else speed
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-s * delta))


func face_dir_instant(d: Vector3) -> void:
	d.y = 0
	if d.length() > 0.01:
		rotation.y = atan2(-d.x, -d.z)


func sees_player(radius: float = -1.0) -> bool:
	var r := notice_radius if radius < 0.0 else radius
	if dist_to_player() > r:
		return false
	var p := player_pos()
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, head_height * 0.8, 0), p + Vector3(0, 0.8, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func notice_player(text: String = "!", voice_key: String = "") -> void:
	set_state("notice")
	# Juice's notice_pop already draws the "!" (two stacked "!" read as a glitch in the r3 reels), so the
	# enemy only adds its own line ("Oi!", "GRR!") and draws the "!" itself only when Juice has no visual.
	var juice_bang := EnemyKit.juice_handles(self, "enemy_notice", "vfx")
	if not juice_bang:
		EnemyKit.popup(get_parent(), global_position + Vector3(0, head_height + 0.75, 0), text, Color(1, 0.84, 0.15), 150, 0.8)
	elif text != "!":
		EnemyKit.popup(get_parent(), global_position + Vector3(0, head_height + 0.55, 0), text.trim_prefix("!"), Color(1, 0.84, 0.15), 96, 0.8)
	if not owns_sfx("enemy_notice"):
		EnemyKit.sfx(self, "enemy_notice", global_position)
		if voice_key != "":
			EnemyKit.sfx(self, voice_key, global_position)
	kick_squash(-0.35 * clampf(notice_stretch / 0.12, 0.3, 1.6))
	_take_t = notice_len
	juice("enemy_notice", {}, global_position + Vector3(0, head_height + 0.3, 0))


func say(text: String, color: Color = Color(1, 1, 1), size: int = 80) -> void:
	if not _in_say_range():
		return
	EnemyKit.popup(get_parent(), global_position + Vector3(0, head_height + 0.55, 0), text, color, size, 1.1)


func _in_say_range() -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam == null or cam.global_position.distance_to(global_position) <= SAY_RANGE


## Walks along patrol_points (relative to home). Returns true while moving.
func patrol_step(delta: float, speed: float = -1.0) -> bool:
	if patrol_points.is_empty():
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		return false
	if _patrol_pause > 0.0:
		_patrol_pause -= delta
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		return false
	var target := home + patrol_points[_patrol_index % patrol_points.size()]
	var d := target - global_position
	d.y = 0
	if d.length() < 0.25:
		_patrol_index += 1
		_patrol_pause = patrol_wait
		return false
	var s := move_speed if speed < 0.0 else speed
	var dir := d.normalized()
	velocity.x = dir.x * s
	velocity.z = dir.z * s
	face_toward(target, delta)
	return true


func steer(dir: Vector3, speed: float, delta: float, accel: float = 14.0) -> void:
	dir.y = 0
	var v := dir.normalized() * speed if dir.length() > 0.001 else Vector3.ZERO
	velocity.x = move_toward(velocity.x, v.x, accel * delta)
	velocity.z = move_toward(velocity.z, v.z, accel * delta)


func kick_squash(amount: float) -> void:
	squash_vel += amount * 12.0


# ------------------------------------------------------------------ hits

func hit_by_player(kind: String, from_position: Vector3) -> bool:
	if is_defeated:
		return false
	var is_stomp := kind == "stomp" or kind == "slam"
	if is_stomp and not _stomp_valid(from_position):
		# A drop past the flank (feet below the head) is not a stomp: the front block and the charge stay honest.
		return false
	if _hit_cooldown > 0.0:
		return is_stomp
	var res := _resolve_hit(kind, from_position)
	# Finish pass: a scripted fight (Sergeant Snap) can gate which hits count. A hit that would not count reads as
	# a bounce (stomp) or a clang (punch) instead of a full hurt that does nothing.
	if res == "damage" and has_meta("hit_gate"):
		var gate: Variant = get_meta("hit_gate")
		if gate is Callable and (gate as Callable).is_valid() and not bool((gate as Callable).call(kind)):
			res = "bounce" if is_stomp else "block"
	match res:
		"ignore":
			hit_taken.emit(kind, false)
			return false
		"block":
			_hit_cooldown = 0.25
			moment_sfx("enemy_block", "enemy_block")
			var btxt := block_text if _block_text_once == "" else _block_text_once
			_block_text_once = ""
			EnemyKit.popup(get_parent(), global_position + Vector3(0, head_height * 0.7, 0) + flat_dir_to(from_position) * 0.6, btxt, Color(0.85, 0.92, 1), 90, 0.6)
			if not owns("enemy_block"):
				EnemyKit.burst(get_parent(), global_position + Vector3(0, head_height * 0.6, 0) + flat_dir_to(from_position) * 0.6, "stars", [Color(1, 1, 0.7)], 10, 4.0)
			kick_squash(0.2)
			juice("enemy_block", {"kind": kind, "direction": flat_dir_to(from_position)}, global_position + Vector3(0, head_height * 0.6, 0) + flat_dir_to(from_position) * 0.6)
			if player != null and player.has_method("add_impulse"):
				var push := from_position - global_position
				push.y = 0
				player.call("add_impulse", push.normalized() * 7.0 + Vector3.UP * 3.0)
			hit_taken.emit(kind, false)
			return false
		"bounce":
			_hit_cooldown = 0.2
			kick_squash(0.95)
			_last_hit_kind = kind
			juice("object_bounce_pad", {"kind": "gumdrop", "impact": stomp_bounce}, global_position + Vector3(0, head_height, 0))
			hit_taken.emit(kind, true)
			# Trampoline: the player applies its own stomp bounce after this returns, so ours is deferred.
			var pl := EnemyKit.find_player(get_tree())
			if pl != null and pl.has_method("bounce"):
				pl.call_deferred("bounce", stomp_bounce)
			return true
	_hit_cooldown = 0.45
	_last_hit_kind = kind
	hp -= 2 if (kind == "slam" and max_hp > 1) else 1
	var lethal := hp <= 0
	# A lethal hit keeps the white pop to one frame so the defeat gag's first pose reads (r1 animation: two
	# pure-white frames hid the start of every gag).
	flash(Color(1, 1, 1), 0.035 if lethal else 0.18, 0.85)
	# Finish pass: no second (scaled-time) toon flash on a lethal hit; it held white through the Juice hit-stop.
	if _toon_applied and mesh_root != null and not lethal:
		FxToon.flash(mesh_root, 0.16)
	var hit_ev := "enemy_defeat" if lethal else "enemy_hurt"
	moment_sfx(hit_ev, "enemy_hit")
	if not EnemyKit.juice_handles(self, hit_ev, "hitstop"):
		# Local hit-stop only when Juice does not freeze the game for this hit.
		_freeze_t = 0.075 if not lethal else 0.11
	_spark_at = spark_pos(from_position, is_stomp)
	if not lethal:
		juice("enemy_hurt", {"kind": kind}, _spark_at)
	var away := global_position - from_position
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else -forward()
	# Flinch along the real hit direction (a punch from behind tips the enemy forward, not toward Mak).
	_hit_dir_local = global_transform.basis.orthonormalized().inverse() * away
	var star_pos := _spark_at
	if not owns(hit_ev) and EnemyKit.fx(get_parent(), "HitStars", star_pos) == null:
		EnemyKit.burst(get_parent(), star_pos, "stars", [Color(1, 0.95, 0.5), Color(1, 1, 1)], 10, 4.5)
	if is_stomp:
		# Pancake: flatten hard on the stomp (the spring then rebounds through a stretch).
		squash = 0.6
		squash_vel = 0.0
		knockback = Vector3.ZERO
	else:
		kick_squash(-0.4)
		knockback = away * 7.0
		if uses_gravity and is_on_floor():
			velocity.y = 3.5
	hit_taken.emit(kind, true)
	if hp <= 0:
		defeat(kind, from_position)
	else:
		set_state("hurt")
	return true


## Where the impact starburst goes: at the contact point beside the body on the camera's side of the hit, or above
## the head for stomps, never over the face (r1 animation: the big starburst covered the head of every defeat).
func spark_pos(from_position: Vector3, is_stomp: bool) -> Vector3:
	var right := Vector3.RIGHT
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		right = cam.global_transform.basis.x
		right.y = 0
		right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var to_hit := from_position - global_position
	to_hit.y = 0
	var side := signf(to_hit.dot(right))
	if side == 0.0:
		side = 1.0
	if is_stomp:
		return global_position + Vector3(0, head_height + 0.3, 0) + right * side * 0.3
	var y := clampf(from_position.y - global_position.y, head_height * 0.3, head_height * 0.6)
	return global_position + Vector3(0, y, 0) + right * side * (body_radius + 0.45)


## Stomps count only from above the head and from a falling, unhurt Mak (exactly one side wins each exchange).
func _stomp_valid(from_position: Vector3) -> bool:
	if from_position.y < stomp_min_y() - 0.05:
		return false
	if _anim_t - _hurt_player_at < 0.7:
		# This enemy just won the exchange (contact hit); the knocked-back Mak cannot also stomp it.
		return false
	var flat := Vector2(from_position.x - global_position.x, from_position.z - global_position.z).length()
	if flat > body_radius + 0.45:
		return false
	var pl := EnemyKit.find_player(get_tree())
	if pl != null and pl.has_method("get_state_name"):
		var st := String(pl.call("get_state_name"))
		if st == "hurt_air" or st == "hurt" or st == "dead":
			return false
	return true


func defeat(kind: String = "punch", from_position: Vector3 = Vector3.INF) -> void:
	if is_defeated:
		return
	is_defeated = true
	if from_position == Vector3.INF:
		from_position = global_position + forward()
	collision_layer = 0
	collision_mask = 0
	hurtbox.set_deferred("monitorable", false)
	head_zone.set_deferred("monitoring", false)
	set_state("defeat")
	var at := _spark_at if _spark_at != Vector3.INF else spark_pos(from_position, kind == "stomp" or kind == "slam")
	var jp := _defeat_juice_params(kind)
	juice("enemy_defeat", jp, at)
	if jp.get("no_vfx", false):
		# The family holds its debris back for the gag's beat; the impact spark still lands on the hit frame, beside
		# the body (never over the face).
		if EnemyKit.fx(get_parent(), "HitSparkBig", at, 0.9) == null:
			EnemyKit.burst(get_parent(), at, "stars", [Color(1, 0.95, 0.5), Color(1, 1, 1)], 10, 4.0)
	_gag_kind = kind
	_gag_from = from_position
	if (kind == "stomp" or kind == "slam") and _wants_pancake():
		# Shared pancake beat before the family gag: flat in 2 frames, hold 0.12 s with a star ring,
		# spring back through a stretch over 0.1 s, then the gag (r1 animation: a lethal stomp showed no squash).
		_pancake_t = 0.0
		velocity = Vector3.ZERO
		EnemyKit.ground_ring(get_parent(), global_position, body_radius * 2.4, Color(1, 0.95, 0.6, 0.8), 0.35)
		if not owns("enemy_defeat"):
			EnemyKit.burst(get_parent(), global_position + Vector3(0, head_height * 0.45, 0), "stars", [Color(1, 0.95, 0.5), Color(1, 1, 1)], 12, 3.0)
		return
	_start_gag()


func _wants_pancake() -> bool:
	return true


## Params for the defeat's Juice event. Families whose gag must play before the debris (grenadier wobble, gummy melt)
## pass no_vfx and spawn their own spark and debris at the right beat.
func _defeat_juice_params(kind: String) -> Dictionary:
	return {"kind": kind}


const PANCAKE_LEN := 0.26


func _pancake_process(delta: float) -> void:
	_pancake_t += delta
	var t := _pancake_t
	var flat := Vector3(1.45, 0.3, 1.45)
	var stretch := Vector3(0.85, 1.25, 0.85)
	var sc: Vector3
	if t < 0.034:
		sc = Vector3.ONE.lerp(flat, t / 0.034)
	elif t < 0.16:
		sc = flat + Vector3(sin(t * 60.0), 0, -sin(t * 60.0)) * 0.03
	elif t < 0.21:
		sc = flat.lerp(stretch, (t - 0.16) / 0.05)
	else:
		sc = stretch.lerp(Vector3.ONE, clampf((t - 0.21) / 0.05, 0.0, 1.0))
	rig.scale = sc * scale_mult
	bob = 0.0
	if t >= PANCAKE_LEN:
		_pancake_t = -1.0
		rig.scale = scale_mult
		squash = 0.0
		squash_vel = -2.0
		state_time = 0.0
		_start_gag()


func _start_gag() -> void:
	var t := _defeat_gag(_gag_kind, _gag_from)
	get_tree().create_timer(t).timeout.connect(_finish_defeat)


func _finish_defeat() -> void:
	if not is_inside_tree():
		return
	# The leave-poof rises from the ground at no more than body height and never covers the final pose's face
	# while it holds (r1 animation: crow and wolf gags were hidden by poofs twice their size).
	var ground := global_position
	var fy := floor_y_at(global_position, 0.5, 4.0)
	if not is_nan(fy):
		ground.y = fy
	var pos := ground + Vector3(0, 0.15, 0)
	var size := clampf(head_height * 0.55, 0.45, 0.9)
	if is_nan(fy) or global_position.y - ground.y > 1.5:
		# Leaving through the air (the wolf zips off): a small puff where the body is.
		pos = global_position + Vector3(0, head_height * 0.4, 0)
		size *= 0.7
	moment_sfx("enemy_flee", "enemy_defeat_poof")
	if owns("enemy_flee"):
		juice("enemy_flee", {"node": get_parent(), "scale": size}, pos)
	elif EnemyKit.fx(get_parent(), "Poof", pos, size) == null:
		EnemyKit.poof(get_parent(), pos, size)
	_defeat_burst()
	var drop_at := global_position
	drop_at.y = maxf(drop_at.y, home.y)
	EnemyKit.drop_acorns(get_parent(), drop_at, acorns_on_defeat)
	defeated.emit(self)
	queue_free()


func _check_head_zone() -> void:
	if _stomp_lock > 0.0 or player == null or not is_instance_valid(player):
		return
	if not head_zone.monitoring or not head_zone.overlaps_body(player):
		return
	var pv: Vector3 = player.get("velocity") if player.get("velocity") != null else Vector3.ZERO
	if pv.y > 0.5:
		return
	if player.global_position.y < stomp_min_y():
		return
	var flat := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	if flat > body_radius + 0.3:
		return
	if player.has_method("get_state_name") and String(player.call("get_state_name")) in ["hurt_air", "hurt", "dead"]:
		return
	var kind := "stomp"
	if player.has_method("is_ground_pounding") and player.call("is_ground_pounding"):
		kind = "slam"
	_stomp_lock = 0.3
	var ok := hit_by_player(kind, player.global_position)
	if ok and player.has_method("bounce"):
		player.call("bounce", stomp_bounce)
		_contact_cooldown = maxf(_contact_cooldown, 0.4)


## True in the last 0.25 s of the wind-up: contact may hurt only once the telegraph has been on screen.
func windup_hot() -> bool:
	return state == "windup" and state_time > windup_len - 0.25


func _check_contact() -> void:
	if player == null or not is_instance_valid(player):
		return
	var d := player.global_position - global_position
	var flat := Vector2(d.x, d.z).length()
	# Bodies touch at body_radius + 0.35 (Mak's radius); 0.38 keeps the reach inside the drawn lane.
	if flat > body_radius + 0.38:
		return
	if d.y > head_height * 0.7 or d.y < -1.25:
		return
	var pv: Vector3 = player.get("velocity") if player.get("velocity") != null else Vector3.ZERO
	if pv.y < 0.0 and d.y > head_height * 0.55:
		# Mak is coming down on the head: the stomp gets this exchange, not the contact.
		return
	if _vaultable() and d.y > head_height * 0.5 and player is CharacterBody3D and not (player as CharacterBody3D).is_on_floor():
		# Jumping over a charge clears it: an airborne Mak whose feet pass the upper half of the head is never hit
		# (r1 fun: every jump height under 1.8 m cost a slice). The HeadZone still awards the stomp from above.
		return
	var hurts := contact_damage and _contact_cooldown <= 0.0 and _contact_active()
	if hurts and player.has_method("is_attacking") and player.call("is_attacking") and _contact_yields_to_attack():
		return
	if hurts and player.has_method("take_damage"):
		player.call("take_damage", 1, global_position)
		_contact_cooldown = 1.2
		_hurt_player_at = _anim_t
		_on_hurt_player(player)
		return
	# Untelegraphed states are solid but harmless: nudge both bodies apart.
	if _push_cd <= 0.0 and not is_defeated and state != "hurt" and contact_damage:
		_push_cd = 0.25
		var away := Vector3(d.x, 0, d.z)
		away = away.normalized() if away.length() > 0.01 else -forward()
		if player.has_method("add_impulse"):
			player.call("add_impulse", away * 3.0)
		if uses_gravity:
			velocity.x -= away.x * 1.5
			velocity.z -= away.z * 1.5


func _contact_yields_to_attack() -> bool:
	return true


## True while a jump over the enemy should clear it (wolf and bee charges).
func _vaultable() -> bool:
	return false


## Heavy hits (gummy slam, Snap's sweep): one slice, but a longer knockback arc and a heavier Juice beat than a graze.
func heavy_hit(p: Node3D, from: Vector3) -> void:
	if p == null or not is_instance_valid(p):
		return
	if p.has_method("take_damage"):
		p.call("take_damage", 1, from)
	var away := p.global_position - from
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else -forward()
	if p.has_method("add_impulse"):
		p.call("add_impulse", away * 5.0 + Vector3.UP * 5.5)
	juice("enemy_slam", {"scale": 0.8}, p.global_position + Vector3(0, 0.1, 0))


# ------------------------------------------------------------------ pose

## Base pose target for a part (eased at 14/s, so state changes blend smoothly).
func pose(part: String, euler: Vector3) -> void:
	pose_target[part] = euler


## Cyclic offset added on top of the eased base pose for this frame only (walk swings, flaps, wags).
## The old single 14/s ease cut every cycle faster than ~2 Hz (wolf charge legs reached 42 % of their swing,
## r1 animation). Cycles go through a light 60/s smoother so a state change cannot pop; raw = no smoothing.
func pose_cycle(part: String, euler: Vector3, raw: bool = false) -> void:
	pose_add[part] = (pose_add.get(part, Vector3.ZERO) as Vector3) + euler
	if raw:
		pose_add_raw[part] = true


## Accent: like pose() but the part reaches the target at `rate` (45/s = about 2 frames) this frame.
func pose_snap(part: String, euler: Vector3, rate: float = 45.0) -> void:
	pose_target[part] = euler
	pose_rate[part] = rate


func _apply_pose(delta: float) -> void:
	# Squash spring.
	squash_vel += (-squash_stiffness * squash - squash_damping * squash_vel) * delta
	squash += squash_vel * delta
	squash = clampf(squash, -0.6, 0.75)
	# Volume-preserving squash and stretch (the old 1 + 0.55 s / 1 - s lost a quarter of the volume and read as shrinking).
	var sy := 1.0 - squash
	var sx := clampf(1.0 / sqrt(maxf(sy, 0.2)), 0.7, 1.8)
	# Idle breathing (fades out while moving fast) and the notice take hop.
	var hv := Vector2(velocity.x, velocity.z).length()
	var breath := sin(_anim_t * 2.4 + _breath_phase) * 0.022 * clampf(1.0 - hv / 3.0, 0.0, 1.0)
	var hop := 0.0
	if _take_t > 0.0:
		var u := clampf((1.0 - _take_t / notice_len) / 0.7, 0.0, 1.0)
		hop = sin(u * PI) * notice_hop
		sy += sin(u * PI) * notice_stretch
	# Bank into turns: the yaw rate tips the body toward the inside of the turn.
	var dyaw := wrapf(rotation.y - _last_yaw, -PI, PI) / maxf(delta, 0.001)
	_last_yaw = rotation.y
	_yaw_rate = dyaw
	_bank = lerpf(_bank, clampf(dyaw * 0.07 * clampf(hv / 2.0, 0.3, 1.0), -0.3, 0.3), 1.0 - exp(-10.0 * delta))
	# Hurt flinch along the hit direction: pitch away from a frontal hit, forward from a hit in the back, roll from the side.
	var flinch_x := 0.0
	var flinch_z := 0.0
	if state == "hurt":
		var u2 := clampf(state_time / 0.55, 0.0, 1.0)
		var f := sin(minf(u2 * 3.0, 1.0) * PI * 0.5) * (1.0 - u2) * 0.45
		flinch_x = f * clampf(_hit_dir_local.z, -1.0, 1.0)
		flinch_z = -f * clampf(_hit_dir_local.x, -1.0, 1.0)
		if _last_hit_kind == "stomp" or _last_hit_kind == "slam":
			flinch_x = 0.0
			flinch_z = 0.0
	if not is_defeated:
		rig.scale = Vector3(sx - breath * 0.5, sy + breath, sx - breath * 0.5) * scale_mult
	rig.position = Vector3(0, bob + hop, -lunge)
	rig.rotation = Vector3(-lean + flinch_x, spin, tilt + _bank + flinch_z)
	# Hit flash: decays in real time (see _flash_step).
	_flash_step()
	# Review-only override: --pose-add=arm_l:0,0,0.6;arm_r:0,0,-0.6 adds offsets on top of the family pose.
	if Dev.has_arg("pose-add"):
		for item in Dev.arg("pose-add").split(";"):
			var kv := item.split(":")
			if kv.size() == 2:
				var c := kv[1].split(",")
				if c.size() == 3:
					pose_target[kv[0]] = (pose_target.get(kv[0], Vector3.ZERO) as Vector3) + Vector3(float(c[0]), float(c[1]), float(c[2]))
	# Parts and bones: ease the base pose toward its target, then add this frame's cycle offsets.
	var k := 1.0 - exp(-14.0 * delta)
	var kc := 1.0 - exp(-60.0 * delta)
	var names: Dictionary = {}
	for pname in pose_target.keys():
		names[pname] = true
	for pname in pose_add.keys():
		names[pname] = true
	for pname in pose_add_cur.keys():
		names[pname] = true
	for pname in names.keys():
		var cur: Vector3 = pose_cur.get(pname, Vector3.ZERO)
		if pose_target.has(pname):
			var kk := k if not pose_rate.has(pname) else 1.0 - exp(-float(pose_rate[pname]) * delta)
			cur = cur.lerp(pose_target[pname], kk)
		pose_cur[pname] = cur
		var add_t: Vector3 = pose_add.get(pname, Vector3.ZERO)
		var add_c: Vector3 = pose_add_cur.get(pname, Vector3.ZERO)
		add_c = add_t if pose_add_raw.has(pname) else add_c.lerp(add_t, kc)
		if add_c.length_squared() < 0.000001 and not pose_add.has(pname):
			pose_add_cur.erase(pname)
		else:
			pose_add_cur[pname] = add_c
		var fin := cur + add_c
		if parts.has(pname):
			var n: Node3D = parts[pname]
			var rest: Transform3D = part_rest[pname]
			n.transform = Transform3D(rest.basis * Basis.from_euler(fin), rest.origin)
		if skeleton != null and bone_ids.has(pname):
			# Offsets are authored in body space (-Z forward); the mesh is turned 180 degrees, so
			# mirror X and Z, then apply the rotation in skeleton space around the bone's joint.
			var r := Basis.from_euler(Vector3(-fin.x, fin.y, -fin.z))
			var pb: Basis = bone_parent_basis[pname]
			var local: Basis = pb.inverse() * r * pb * (bone_rest[pname] as Basis)
			skeleton.set_bone_pose_rotation(bone_ids[pname], local.orthonormalized().get_rotation_quaternion())
	pose_add.clear()
	pose_add_raw.clear()
	pose_rate.clear()
	# Bone scale (exaggeration): eased toward its target, applied to the bone's pose scale.
	if skeleton != null:
		for pname in pose_scale_target.keys():
			if not bone_ids.has(pname):
				continue
			var sc: Vector3 = pose_scale_cur.get(pname, Vector3.ONE)
			sc = sc.lerp(pose_scale_target[pname], k)
			pose_scale_cur[pname] = sc
			skeleton.set_bone_pose_scale(bone_ids[pname], sc)
	_after_pose(delta)
	# Eyes: blink and track the player.
	_blink_t -= delta
	var blink := 1.0
	if _blink_t < 0.0:
		blink = 0.12
		if _blink_t < -0.11:
			_blink_t = _rng.randf_range(1.8, 4.5)
	for e in _eyes:
		if not e.has_meta("rest_scale"):
			e.set_meta("rest_scale", e.scale)
		var rs: Vector3 = e.get_meta("rest_scale")
		e.scale = Vector3(rs.x, rs.y * blink, rs.z)
	var tgt := look_target
	if tgt == Vector3.INF and player != null and is_instance_valid(player):
		tgt = player.global_position + Vector3(0, 0.8, 0)
	for p in _pupils:
		if not p.has_meta("rest_pos"):
			p.set_meta("rest_pos", p.position)
		var rp: Vector3 = p.get_meta("rest_pos")
		var off := Vector3.ZERO
		if tgt != Vector3.INF and not is_defeated:
			var par := p.get_parent() as Node3D
			var local: Vector3 = par.global_transform.affine_inverse() * tgt
			var dir: Vector3 = local.normalized()
			off = Vector3(clampf(dir.x, -1.0, 1.0), clampf(dir.y, -1.0, 1.0), 0) * absf(rp.z) * 0.45
		p.position = p.position.lerp(rp + off, k)


## Bone scale target for a part (eased like pose()); rigs only.
func pose_scale(part: String, sc: Vector3) -> void:
	pose_scale_target[part] = sc


## Called at the end of every pose update, after the bones are set (props aimed in body space, etc.).
func _after_pose(_delta: float) -> void:
	pass


## Advances walk_phase from linear speed plus turning (in-place turns shuffle the feet instead of sliding them).
func walk_cycle(delta: float, speed_scale: float = 1.0) -> float:
	var hv := Vector2(velocity.x, velocity.z).length()
	walk_phase += delta * (hv * 4.0 * speed_scale + absf(_yaw_rate) * 1.2 * clampf(1.0 - hv / 2.0, 0.0, 1.0))
	return hv + absf(_yaw_rate) * 0.3 * clampf(1.0 - hv / 2.0, 0.0, 1.0)


# ------------------------------------------------------------------ gait (LEGS pass, 2026-10-19)
# Owner review: the mobs' legs moved "like steel" (a fixed-length stride whose swing shrank with speed, so feet skated
# at a walk; straight knees; leg cycles eased through pose()). The shared gait below drives the stride phase from the
# ground distance actually covered (no skating, no paddling against a wall), grows the step with speed and turns it
# into a hip swing from the rig's measured hip height (the planted foot keeps pace with the ground), folds the knees
# (shin bones) on the swing, bobs the body twice per stride and fades every channel back to the idle pose on a stop.

## Stride phase (radians; one cycle = left and right steps), walk weight (0 standing .. 1 walking, eased), current hip
## swing (radians) and smoothed ground speed (m/s).
var gait_phase: float = 0.0
var gait_w: float = 0.0
var gait_amp: float = 0.0
var gait_speed: float = 0.0
## Hip height above the soles (m), measured from the rig on first use (reset when the mesh changes).
var gait_hip_h: float = -1.0
var _gait_prev: Vector3 = Vector3.INF
var _gait_knee_l: float = 0.0
var _gait_knee_r: float = 0.0


func gait_hip_height() -> float:
	if gait_hip_h > 0.0:
		return gait_hip_h
	var h := -1.0
	if skeleton != null and bone_ids.has("leg_l"):
		var hip: Vector3 = skeleton.global_transform * skeleton.get_bone_global_rest(int(bone_ids["leg_l"])).origin
		h = hip.y - global_position.y + bob
	elif parts.has("leg_l"):
		h = (parts["leg_l"] as Node3D).global_position.y - global_position.y
	if h > 0.06 and h < 3.0:
		gait_hip_h = h
		return h
	return 0.4


## Advances the gait from the ground distance covered since the last call; call it every frame (on = false fades the
## walk out, e.g. while skidding). stride scales the step length (charges > 1); max_swing caps the hip swing, and the
## step is capped with it so a faster gait raises the cadence instead of skating. Returns this frame's body bob (m):
## highest at mid-stance, twice per stride.
func gait_update(delta: float, on: bool = true, stride: float = 1.0, bob_amt: float = 0.05, max_swing: float = 0.8) -> float:
	var p := global_position
	var d := 0.0
	var dir := 1.0
	if _gait_prev != Vector3.INF:
		var dp := Vector2(p.x - _gait_prev.x, p.z - _gait_prev.z)
		d = dp.length()
		var f := forward()
		# Backing up (knockback, a scatter return) steps backward instead of moonwalking.
		if dp.dot(Vector2(f.x, f.z)) < -0.6 * d:
			dir = -1.0
	_gait_prev = p
	if d > 1.0:
		d = 0.0
	gait_speed = lerpf(gait_speed, d / maxf(delta, 0.0001), 1.0 - exp(-12.0 * delta))
	if not on:
		d = 0.0
	var h := gait_hip_height()
	var turn := absf(_yaw_rate) * clampf(1.0 - gait_speed / 0.6, 0.0, 1.0) if on else 0.0
	var want := clampf(maxf(gait_speed / 0.35, turn * 0.25), 0.0, 1.0) if on else 0.0
	gait_w = move_toward(gait_w, want, delta * (7.0 if want > gait_w else 4.0))
	# Step length (one foot-fall to the next) grows with the Froude speed: a short shuffle slow, a long reach fast.
	var step := h * clampf(0.45 + 0.85 * gait_speed / sqrt(9.8 * h), 0.45, 1.8) * stride
	step = minf(step, 2.0 * h * sin(max_swing))
	gait_phase = wrapf(gait_phase + dir * d / maxf(2.0 * step, 0.05) * TAU + turn * 0.45 * delta, 0.0, TAU * 64.0)
	gait_amp = lerpf(gait_amp, asin(clampf(step / (2.0 * h), 0.0, 0.95)), 1.0 - exp(-10.0 * delta))
	var c := cos(gait_phase)
	return bob_amt * gait_w * clampf(gait_amp / 0.5, 0.3, 1.3) * c * c


## Poses this frame's leg cycle on leg_l/leg_r (+ shin_l/shin_r knee folds on the swing, the thigh lifting with
## them) and an optional arm counter-swing. All offsets go through pose_cycle (additive on the family's base pose).
func gait_legs(knee: float = 1.0, arms: float = 0.0, scale: float = 1.0) -> void:
	var a := gait_amp * gait_w * scale
	if a < 0.0005 and gait_w < 0.001:
		return
	var s := sin(gait_phase)
	var c := cos(gait_phase)
	var kf := knee * (0.3 + 1.2 * gait_amp) * gait_w * scale
	_gait_knee_l = kf * maxf(0.0, c) * maxf(0.0, c)
	_gait_knee_r = kf * maxf(0.0, -c) * maxf(0.0, -c)
	pose_cycle("leg_l", Vector3(a * s + 0.35 * _gait_knee_l, 0, 0))
	pose_cycle("leg_r", Vector3(-a * s + 0.35 * _gait_knee_r, 0, 0))
	pose_cycle("shin_l", Vector3(-_gait_knee_l, 0, 0))
	pose_cycle("shin_r", Vector3(-_gait_knee_r, 0, 0))
	if arms > 0.0:
		pose_cycle("arm_l", Vector3(-a * s * arms, 0, 0))
		pose_cycle("arm_r", Vector3(a * s * arms, 0, 0))


## True on the frame a foot lands (the phase crosses 0 or PI); for footstep sounds in step with the legs.
func gait_footfall(prev_phase: float) -> bool:
	return gait_w > 0.3 and floor(prev_phase / PI) != floor(gait_phase / PI)


## Head pitch (radians, positive = up) that aims the head at Mak from the current position.
func head_pitch_to_player(extra: float = 0.0) -> float:
	if player == null or not is_instance_valid(player):
		return extra
	var d := player.global_position + Vector3(0, 0.7, 0) - (global_position + Vector3(0, head_height * 0.85, 0))
	var flat := Vector2(d.x, d.z).length()
	return clampf(atan2(d.y, maxf(flat, 0.3)), -0.6, 0.6) + extra


## Popup for defeat lines: above the head and sideways away from the camera's view line, so it never covers the gag.
func say_side(text: String, color: Color = Color(1, 1, 1), size: int = 80) -> void:
	if not _in_say_range():
		return
	var off := Vector3.ZERO
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var right := cam.global_transform.basis.x
		right.y = 0
		off = right.normalized() * 0.55 if right.length() > 0.01 else Vector3.ZERO
	EnemyKit.popup(get_parent(), global_position + Vector3(0, head_height + 0.9, 0) + off, text, color, size, 1.0)


## Finish pass (r1 animation major): the hit flash decays in real time, every rendered frame. It used to tick inside
## the physics step, which the local freeze skips and the Juice hit-stop slows, so a defeat held full white 3-7
## frames plus 6 hit-stop frames.
func _flash_step() -> void:
	if _flash == null:
		return
	var now := Time.get_ticks_usec()
	var rd := clampf(float(now - _flash_us) / 1000000.0, 0.0, 0.1)
	_flash_us = now
	if _flash_t > 0.0:
		_flash_t -= rd
		var fa := clampf(_flash_t / _flash_len, 0.0, 1.0) * _flash_peak
		if _flash_rim > 0.5:
			# Telegraph: pulse the rim glow twice while it fades, so the wind-up reads as "charging".
			fa *= 0.65 + 0.35 * cos((1.0 - _flash_t / _flash_len) * TAU * 2.0)
		_flash_tint.a = fa
		_flash.set_shader_parameter("tint", _flash_tint)
	elif _flash_tint.a > 0.0:
		_flash_tint.a = 0.0
		_flash.set_shader_parameter("tint", _flash_tint)


func _process(_delta: float) -> void:
	_flash_step()

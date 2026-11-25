class_name MakPlayer
extends CharacterBody3D
## Mr. Mak, the player controller (Super Mak 64).
##
## Conventions: metres, seconds, Y up, forward = -Z, feet at the origin, 60 Hz physics.
## The controller owns acceleration, air steering, jump impulses and every state transition; the
## CharacterBody3D only resolves collisions. Constants live in MovementProfile (mak_profile.tres).
## Layers: body on 2 (player), collides with 1 (world) and 3 (enemy bodies). AttackArea and StompArea
## are on 6 (player_attack) and scan 7 (enemy_hurtbox). Sensor scans layers 1, 5 and 8 for Area3D
## nodes in the groups "wind_zone", "hazard" and "climbable".
## Interfaces (Docs/TECH_CONTRACT.md): take_damage, bounce, add_impulse, respawn, is_ground_pounding,
## is_attacking, get_state_name, signals jumped / landed / ground_pounded / attacked / died.

signal jumped(kind: String)
signal landed(impact_speed: float)
signal ground_pounded(position: Vector3)
signal attacked(kind: String)
signal died
## Extra signals for the camera, VFX and audio workstreams.
signal state_changed(from_state: String, to_state: String)
signal teleported
signal footstep(foot: int, surface: String)
signal hat_changed(hat_id: String)
signal sniff_target_changed(target: Node3D)

const AIR_STATES := {
	"jump": true, "double_jump": true, "triple_jump": true, "long_jump": true, "backflip": true,
	"side_flip": true, "wall_kick": true, "fall": true, "wall_slide": true, "ham_slam": true,
	"dive": true, "jump_kick": true, "hurt_air": true, "bounce": true, "rollout": true,
	"fallout": true, "dead": true, "celebrate_air": true, "bonk": true,
}
const MANUAL_STATES := {"ledge_hang": true, "ledge_climb": true, "pole_climb": true}
## Air states from which a wall contact (and wall kick) can happen.
const WALL_STATES := {
	"jump": true, "double_jump": true, "triple_jump": true, "long_jump": true, "backflip": true,
	"side_flip": true, "wall_kick": true, "fall": true, "bounce": true, "rollout": true,
}
## Air states from which a ledge can be grabbed.
const LEDGE_STATES := {
	"jump": true, "double_jump": true, "triple_jump": true, "backflip": true, "side_flip": true,
	"wall_kick": true, "fall": true, "bounce": true, "rollout": true, "wall_slide": true, "long_jump": true,
}
## Air states allowing Ham Slam, dive and jump kick.
const AIR_ACTION_STATES := {
	"jump": true, "double_jump": true, "triple_jump": true, "backflip": true, "side_flip": true,
	"wall_kick": true, "fall": true, "bounce": true, "rollout": true,
}
const FX_PATHS := {
	"dust": "res://scenes/fx/DustPuff.tscn",
	"ring": "res://scenes/fx/LandingRing.tscn",
	"slam": "res://scenes/fx/SlamShockwave.tscn",
	"jump_trail": "res://scenes/fx/JumpTrail.tscn",
	"hit_stars": "res://scenes/fx/HitStars.tscn",
	"splash": "res://scenes/fx/Splash.tscn",
	"cocoa_splash": "res://scenes/fx/CocoaSplash.tscn",
	"poof": "res://scenes/fx/Poof.tscn",
	"checkpoint": "res://scenes/fx/CheckpointGlow.tscn",
}
const HAT_IDS := ["beanie", "top_hat"]
## Hero v2 (owner look 2026-10-18): Mak's default hat is the TOP HAT. One-line switch: "beanie" for the grey beanie.
const DEFAULT_HAT := "top_hat"

@export var profile: MovementProfile
@export var hat := DEFAULT_HAT
## Hero v2: the cute chibi Mr. Mak (owner-approved look, game/assets/characters/mak_v2/) through the skeleton adapter.
## The night Tripo hero (characters/mak/mak_v2.glb, rejected as "too mature") and the procedural proxy pig stay only as
## unused fallbacks (missing file or unusable skeleton), or for A/B captures with --night-hero / --proxy-pig.
@export var prefer_rigged_mesh := true
@export var rigged_mesh_path := "res://assets/characters/mak_v2/mak_v2_body_v3.glb"
const RIGGED_FALLBACK_PATH := "res://assets/characters/mak/mak_v2.glb"
const NIGHT_HERO_PATH := "res://assets/characters/mak/mak_v2.glb"
## Hero v2 kit (ATTACH.md): the parts' origins sit on their sockets, so they attach with an identity transform.
const V2_TOPHAT_PATH := "res://assets/characters/mak_v2/mak_v2_tophat.glb"
const V2_BEANIE_PATH := "res://assets/characters/mak_v2/mak_v2_beanie_v3.glb"
const V2_PACK_PATH := "res://assets/characters/mak_v2/mak_v2_backpack_v3.glb"
var hero_v2 := false
## Fallback kill height when the current scene does not export kill_y.
@export var default_kill_y := -60.0

var p: MovementProfile
var inp := MakInput.new()
var state := "idle"
var prev_state := ""
var state_time := 0.0
var sim_time := 0.0
var physics_frame := 0

var facing_yaw := 0.0
var intended_yaw := 0.0
var intended_dir := Vector3.ZERO
var forward_speed := 0.0            ## m/s along facing (negative = backwards)
var side_speed := 0.0               ## m/s to the left of facing (air drift)
var vy := 0.0
var slide_vel := Vector3.ZERO       ## horizontal velocity in free-sliding states
var use_slide_vel := false
var ext_vel := Vector3.ZERO         ## inherited platform momentum and knockback, horizontal
var wind_vel := Vector3.ZERO
var _wind_target := Vector3.ZERO

var grounded := true
var floor_normal := Vector3.UP
var floor_collider: Object = null
var surface := "grass"
var last_platform_vel := Vector3.ZERO
var impact_speed := 0.0
var air_time := 0.0

var jump_buffer := 0.0
var coyote := 0.0
var last_land_time := -10.0
var chain_kind := ""
var jump_cut_done := false
var last_jump_kind := ""
var _air_kick_used := false
var invulnerable := 0.0
var hurt_blink := 0.0               ## s of visible blinking after damage (respawn grace does not blink)
var hurt_from_behind := false       ## REA round 2: the last hit came from behind (Mak thrown forwards)
var hurt_land_duration := 0.4       ## s of the current hurt_land (the animator reads it)
var _hurt_total := 0.0              ## s whole hurt state of the current hit (0: none or a bonk)
var _hurt_at := 0.0                 ## sim_time of the last hit
var _strike_carry := 0.0            ## m/s momentum carried into the current strike

var combo_step := 0
var _combo_queued := false
var attack_kind := ""
var attack_active := false
var _attack_hits := {}
var _stomp_cooldown := 0.0

var wall_normal := Vector3.ZERO
var wall_point := Vector3.ZERO
var _wall_slide_n := Vector3.ZERO
var _wall_slide_d := 0.0
var _kick_wall_n := Vector3.ZERO
var _kick_wall_d := 0.0
var _kick_wall_valid := false

var ledge_cooldown := 0.0
var ledge_point := Vector3.ZERO
var ledge_normal := Vector3.ZERO
var _ledge_body: Node3D = null
var _ledge_prev := Vector3.ZERO
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _climb_time := 0.4

var pole: Node3D = null
var _pole_bottom := Vector3.ZERO
var _pole_axis := Vector3.UP
var _pole_u := Vector3.RIGHT
var _pole_w := Vector3.BACK
var _pole_length := 1.0
var pole_radius := 0.15
var pole_t := 0.0
var pole_angle := 0.0
var pole_climb_travel := 0.0
var pole_cooldown := 0.0

var sniff_target: Node3D = null
var _sniff_scan := 0.0
var _sniff_sfx := 0.0
var _scent: Node3D = null
var _sniffed_ids := {}
const SNIFF_REACH := 2.0

var crouched_shape := false
var spawn_xform := Transform3D.IDENTITY
var _fallback_timer := -1.0
var _celebrate_time := 1.8
var visual_step_offset := 0.0       ## m, eased to zero by the animator after a step-up
var visual_yaw_offset := 0.0        ## rad, eased to zero by the animator (wall kick, side flip)
var _trace: FileAccess = null
var _ending := false
var _fx := {}
var _kill_y := -60.0
var _step_frame := false
var _steep_frames := 0
var _step_grace := 0
var braking := false                ## stick released at speed: hard brake to a stop (reference)
var air_steer := Vector3.ZERO       ## D039: world-space m/s of the owner-requested air steer assist (sideways only)
var _air_steer_tick := false        ## D039: set by _air_physics this tick; otherwise air_steer is dropped
var _land_stop := false             ## D039: touched down with the stick released, stop at land_stop_decel
var _slam_dropping := false
var _snap_next := true
var _fresh_launch := false
var _splash_cd := 0.0
var _fb_log := false
var _in_liquid := {}
## Fix r1 (feel): steering basis lock, contact shadow, ledge grab catch, lip vault.
var _steer_yaw := 0.0
var _steer_locked := false
var _steer_dir := Vector2.ZERO
var _steer_release := 0.0
var blob: Decal = null
var _blob_hidden_for_world := false
var visual_grab_offset := Vector3.ZERO   ## world-space offset handed to the visual on a ledge grab (eased out)
var visual_grab_rate := 28.0             ## 1/s easing of visual_grab_offset (slower for the mantle hop-up)
var mantle_time := -1.0                  ## s since a mantle hop-up started (-1 when none); read by the animator
var pushing_wall := false                ## grounded, stick held into a wall, not moving (animator push pose)
var _push_frames := 0
var _grab_stick_held := false
var _jump_press_time := -10.0
var _wall_in_dir := Vector3.ZERO
var _vault_from := Vector3.ZERO
var _vault_to := Vector3.ZERO
var _vault_time := 0.0

@onready var body_shape: CollisionShape3D = $Body
@onready var visual: Node3D = $Visual
@onready var animator: Node = $Animator
@onready var attack_area: Area3D = $AttackArea
@onready var attack_shape: CollisionShape3D = $AttackArea/Shape
@onready var stomp_area: Area3D = $StompArea
@onready var sensor: Area3D = $Sensor
var camera_rig: Node3D = null
var _capsule: CapsuleShape3D
var _attack_sphere: SphereShape3D


# ------------------------------------------------------------------ setup

func _ready() -> void:
	add_to_group("player")
	if profile == null:
		profile = MovementProfile.new()
	p = profile
	floor_max_angle = deg_to_rad(p.floor_max_angle_deg)
	floor_snap_length = p.floor_snap
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_block_on_wall = true
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	_capsule = (body_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	body_shape.shape = _capsule
	_attack_sphere = (attack_shape.shape as SphereShape3D).duplicate() as SphereShape3D
	attack_shape.shape = _attack_sphere
	facing_yaw = rotation.y
	spawn_xform = global_transform
	camera_rig = get_node_or_null("MakCamera") as Node3D
	var replay: Dictionary = {}
	var dev := _autoload("Dev")
	if dev != null:
		var r: Variant = dev.get("replay")
		if r is Dictionary:
			replay = r
	inp.setup(replay, p.stick_deadzone, p.stick_curve)
	for k in FX_PATHS:
		if ResourceLoader.exists(FX_PATHS[k]):
			_fx[k] = load(FX_PATHS[k])
	_setup_visual()
	var g := _autoload("Game")
	if g != null and g.has_signal("truffle_collected"):
		g.connect("truffle_collected", _on_truffle_collected)
	var dev_hat := ""
	if dev != null and dev.has_method("arg"):
		dev_hat = str(dev.call("arg", "hat", ""))
	if g != null and g.has_method("get_hat") and dev_hat == "":
		var gh: Variant = g.call("get_hat")
		if gh is String and gh != "":
			set_hat(_resolve_saved_hat(gh, g))
	if g != null and g.has_signal("hat_changed"):
		g.connect("hat_changed", set_hat)
	if inp.replay_active and not inp.start.is_empty():
		var sp: Array = inp.start.get("pos", [0, 0, 0])
		var at := Transform3D(Basis(Vector3.UP, deg_to_rad(float(inp.start.get("yaw_deg", 0.0)))), Vector3(float(sp[0]), float(sp[1]), float(sp[2])))
		respawn(at)
		spawn_xform = global_transform
	_open_trace()
	_fb_log = dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "fb-log"))
	var jl := _autoload("Juice")
	if _fb_log and jl != null and jl.has_signal("fired"):
		jl.connect("fired", func(n: String, _p: Vector3, _q: Dictionary) -> void: print("[Juice.fired] f%d %s" % [physics_frame, n]))
	_kill_y = default_kill_y
	call_deferred("_read_world_settings")
	_setup_blob()


## Contact shadow (fix r1): a soft blob straight under Mak in every world (the sun shadow lands 1-2 m to the side at
## jump height). Projects only on visual layer 1 (the world), shrinks and fades with height above the floor.
func _setup_blob() -> void:
	blob = Decal.new()
	blob.name = "PlayerContactShadow"
	blob.top_level = true
	blob.size = Vector3(0.9, 1.2, 0.9)
	blob.texture_albedo = _blob_texture()
	blob.modulate = Color(0.26, 0.2, 0.36, 0.5)
	blob.cull_mask = 1
	blob.normal_fade = 0.4
	blob.upper_fade = 0.15
	blob.lower_fade = 0.4
	add_child(blob)


static var _blob_tex_cache: Texture2D = null


static func _blob_texture() -> Texture2D:
	if _blob_tex_cache != null:
		return _blob_tex_cache
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			# Soft core plus a thin darker rim so the blob reads on busy grass.
			var core := clampf(1.0 - smoothstep(0.3, 0.95, d), 0.0, 1.0) * 0.8
			var rim := exp(-pow((d - 0.8) / 0.07, 2.0)) * 0.35
			img.set_pixel(x, y, Color(1, 1, 1, clampf(core + rim, 0.0, 1.0) * (1.0 - smoothstep(0.92, 1.0, d))))
	_blob_tex_cache = ImageTexture.create_from_image(img)
	return _blob_tex_cache


func _process(_delta: float) -> void:
	_update_blob()


func _update_blob() -> void:
	if blob == null:
		return
	if not _blob_hidden_for_world and Engine.get_process_frames() % 60 == 1:
		# A world that still builds its own Mak shadow (W2's MakBlobShadow) keeps it; no double shadow.
		var sc := get_tree().current_scene
		if sc != null and sc.find_child("MakBlobShadow", true, false) != null:
			_blob_hidden_for_world = true
	if _blob_hidden_for_world or state == "fallout" or state == "dead" or not visual.visible and hurt_blink <= 0.0:
		blob.visible = false
		return
	var gp := get_global_transform_interpolated().origin
	var q := PhysicsRayQueryParameters3D.create(gp + Vector3.UP * 0.3, gp + Vector3.DOWN * 10.0, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		blob.visible = false
		return
	var hp: Vector3 = hit["position"]
	var h := maxf(gp.y - hp.y, 0.0)
	# Fix r2 (feel minor M7): the airborne landing spot must win over the sun shadow, so the blob gets darker and a
	# little wider as Mak rises (alpha 0.42 -> 0.62 over the first 3 m), fading only on very high falls.
	var k := clampf(h / 3.0, 0.0, 1.0)
	var far := clampf((h - 6.0) / 8.0, 0.0, 1.0)
	blob.visible = true
	blob.global_position = hp + Vector3.UP * 0.2
	var sz := lerpf(0.78, 1.0, k) - 0.3 * far
	# Soft shadows on (2026-10-19): Mak casts a real sun shadow, so the grounded blob is a light contact accent only
	# (no double darkening under his feet); in the air it still grows darker to mark the landing spot.
	var g := get_node_or_null("/root/Game")
	var sun_on := g == null or bool(g.call("get_setting", "soft_shadows", true))
	if sun_on:
		sz = lerpf(0.62, 0.95, k) - 0.3 * far
	blob.size = Vector3(sz, 1.2, sz)
	blob.modulate.a = (lerpf(0.2, 0.55, k) if sun_on else lerpf(0.42, 0.62, k)) * (1.0 - 0.6 * far)


func _read_world_settings() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		var k: Variant = scene.get("kill_y")
		if k != null and (k is float or k is int):
			_kill_y = float(k)
		# Per-world hero rim (fix r1): a world root may set metas hero_rim (float) and hero_rim_color (Color) so the
		# cream hero separates from pale palettes (W3's sand path and mint grass).
		if scene.has_meta("hero_rim"):
			for m in _hero_mats:
				m.set_shader_parameter("rim_strength", float(scene.get_meta("hero_rim")))
				if scene.has_meta("hero_rim_color"):
					m.set_shader_parameter("rim_color", scene.get_meta("hero_rim_color"))


## Legacy saves (and new saves until the core default changes) store "beanie" as the default hat. Hero v2 wears the top
## hat by default, so a saved "beanie" only counts when the save marks it as the player's explicit choice
## (data.hat_explicit, the requested core change). Live wardrobe changes arrive through Game.hat_changed and are always explicit.
func _resolve_saved_hat(saved: String, g: Node) -> String:
	if saved != "beanie":
		return saved
	var d: Variant = g.get("data")
	if d is Dictionary and bool((d as Dictionary).get("hat_explicit", false)):
		return saved
	return DEFAULT_HAT


func _setup_visual() -> void:
	var proxy := visual.get_node_or_null("ProxyPig") as Node3D
	var skeleton: Skeleton3D = null
	var dev := _autoload("Dev")
	if dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "proxy-pig")):
		prefer_rigged_mesh = false
	if dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "night-hero")):
		rigged_mesh_path = NIGHT_HERO_PATH
	var mesh_path := rigged_mesh_path if ResourceLoader.exists(rigged_mesh_path) else RIGGED_FALLBACK_PATH
	if prefer_rigged_mesh and ResourceLoader.exists(mesh_path):
		var ps := load(mesh_path) as PackedScene
		if ps != null:
			var model := ps.instantiate() as Node3D
			if model != null:
				var wrap := Node3D.new()
				wrap.name = "Model"
				wrap.rotation.y = PI   # glTF faces +Z; the body faces -Z
				visual.add_child(wrap)
				wrap.add_child(model)
				skeleton = _find_skeleton(model)
				if skeleton == null or skeleton.find_bone("head") < 0 or skeleton.find_bone("hips") < 0:
					push_warning("[MakPlayer] %s has no usable skeleton (bones root/hips/spine/head...); using the proxy pig" % mesh_path)
					wrap.queue_free()
					skeleton = null
				else:
					hero_v2 = skeleton.find_bone("eyelid_l") >= 0 and skeleton.find_bone("head_top") >= 0
					if hero_v2:
						_attach_v2_parts(skeleton)
					else:
						MakRigFix.fix_ear_weights(model, skeleton)
					# Storybook toon look (VFX FxToon: two-tone ramp, rim, ink outline); chosen over raw PBR from
					# the side-by-side in Docs/progress/hero. --pbr keeps the generated PBR materials for A/B.
					var pbr := dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "pbr"))
					var toon := load("res://scripts/fx/fx_toon.gd") if ResourceLoader.exists("res://scripts/fx/fx_toon.gd") else null
					if toon != null and not pbr:
						toon.call("apply", model, {"rim": 0.45, "outline_width": 1.6})
						_tune_toon(model)
						if not (dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "no-hero-silhouette"))):
							_add_occlusion_silhouette(model)
					elif not hero_v2 and not (dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "beanie-raw"))):
						MakRigFix.tint_beanie(model)
					if not hero_v2:
						_fit_beanie(model)
	if skeleton != null and proxy != null:
		# The proxy never ships visibly next to the real model: remove it outright.
		proxy.visible = false
		proxy.queue_free()
		proxy = null
	if animator != null and animator.has_method("setup"):
		animator.set("v2_parts", v2_parts)
		animator.call("setup", self, proxy, skeleton)
		if skeleton != null:
			animator.set("model_root", visual.get_node_or_null("Model"))
	# Mak renders on visual layer 2 (the character layer, see the boss key light): world decals such as the contact
	# shadow use cull_mask 1, so they never print onto him.
	_set_visual_layers(visual, 2)
	if dev != null and dev.has_method("arg") and str(dev.call("arg", "hat", "")) != "":
		hat = str(dev.call("arg", "hat", ""))
	set_hat(hat)


## Hero v2 kit: backpack on backpack_socket, both hats on head_top (identity offsets, ATTACH.md). The animator shows one
## hat (set_hat) and springs the head_top bone for hat jiggle and the backpack bone for pack follow-through.
var v2_parts := {}


func _attach_v2_parts(skeleton: Skeleton3D) -> void:
	var specs := [["PackSocket", "backpack_socket", {"pack": V2_PACK_PATH}],
		["HatSocket", "head_top", {"top_hat": V2_TOPHAT_PATH, "beanie": V2_BEANIE_PATH}]]
	for sp in specs:
		if skeleton.find_bone(str(sp[1])) < 0:
			continue
		var att := BoneAttachment3D.new()
		att.name = str(sp[0])
		att.bone_name = str(sp[1])
		skeleton.add_child(att)
		var parts: Dictionary = sp[2]
		for key in parts:
			var path := str(parts[key])
			if not ResourceLoader.exists(path):
				continue
			var ps := load(path) as PackedScene
			var n := ps.instantiate() as Node3D
			n.name = "Part_" + str(key)
			att.add_child(n)
			if V2_HAT_FIT.has(key):
				n.transform = v2_hat_fit(str(key))
			v2_parts[key] = n


## Hat fit pass (owner 2026-10-19: "the beanie sits very badly, too big, slides forward, you can see its inside").
## The v3 beanie mesh carries a 16 degree back tilt made about the head_top socket (13 cm above the cuff), so its
## cuff stood 7-9 cm off the forehead and sank 5-6 cm into the back of the head (Blender signed-distance check of the
## cuff ring against the head surface, assets_src/hero_v2/fix4/fix_v4_face.blend); from below you looked into the hat.
## This seats it: the 16 degree tilt undone about the socket and 5 degrees of back tilt put back about the head centre
## (30 cm below the socket) = 11 degrees forward plus 2.6 cm back. The cuff now rests on the forehead above the brows
## and on the back of the head, the crown sits between the ears leaning a little back, and the open bottom is closed
## by the head from every camera height (native captures: Docs/progress/finish/hat_fit/).
## Socket space = model space at rest (ATTACH.md). The top hat (and the gold one) already sit on the crown: identity.
const V2_HAT_FIT := {
	"beanie": {"rot_deg": Vector3(11.0, 0.0, 0.0), "pos": Vector3(0.0, -0.001, -0.026), "scale": 1.0},
}


static func v2_hat_fit(id: String) -> Transform3D:
	var f: Dictionary = V2_HAT_FIT.get(id, {})
	if f.is_empty():
		return Transform3D.IDENTITY
	var r: Vector3 = f["rot_deg"]
	var b := Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))).scaled(Vector3.ONE * float(f["scale"]))
	return Transform3D(b, f["pos"])


## Fix r1 (character visuals): per-surface toon tuning on duplicated materials.
## Beanie: knit has no highlight and a neutral shade keeps the grey grey (it rendered as glossy lavender).
## Body and face: a broad soft sheen instead of wet spec dots, and softer cast-shadow edges for close-ups.
var _hero_mats: Array[ShaderMaterial] = []
const HERO_SHADE := Color(0.82, 0.7, 0.72)


func _tune_toon(model: Node) -> void:
	for mi in _meshes_under(model):
		var nm := str(mi.name).to_lower()
		for si in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(si) as ShaderMaterial
			if m == null:
				continue
			var d := m.duplicate() as ShaderMaterial
			if nm.contains("beanie"):
				d.set_shader_parameter("spec_strength", 0.0)
				d.set_shader_parameter("shadow_tint", Color(0.66, 0.64, 0.66))
				d.set_shader_parameter("rim_strength", 0.12)   # fix r2 (m1): 0.25 let W2's sky tint the knit pink
				d.set_shader_parameter("normal_strength", 1.2)
				d.set_shader_parameter("ramp_softness", 0.14)
			elif nm.contains("body") or nm.contains("head") or nm.contains("face"):
				d.set_shader_parameter("spec_strength", 0.12)
				d.set_shader_parameter("spec_size", 0.6)
				# Hero v2 fix r1 (appeal polish): a wider ramp band so a few torso and cheek facets still read under the toon
				# ramp (they washed to flat cream).
				d.set_shader_parameter("ramp_softness", 0.28 if hero_v2 else 0.18)
				# Fix r2 (m3): a shade nearer the skin, so the ear and snout shadows stop printing blotches on the cheeks.
				d.set_shader_parameter("shadow_tint", HERO_SHADE)
			elif nm.contains("tophat"):
				# Hero v2 top hat: neutral shade and a faint rim so the dark silk never turns purple under coloured skies,
				# one hard glossy band for the "silk" read.
				d.set_shader_parameter("spec_strength", 0.35)
				d.set_shader_parameter("spec_size", 0.12)
				d.set_shader_parameter("rim_strength", 0.15)
				d.set_shader_parameter("shadow_tint", Color(0.62, 0.62, 0.64))
			else:
				continue
			mi.set_surface_override_material(si, d)
			if not nm.contains("beanie"):
				_hero_mats.append(d)


## Fix r2 (character visuals M6): occlusion silhouette. A last material pass on every hero surface draws a flat
## hero-pink tint with an ink edge only where Mak is hidden behind geometry (scene depth in front of his own
## depth by more than 35 cm, which also keeps his own hooves from tinting him), so thin props and walls never fully hide him from the gameplay camera.
## Render fix 2026-10-19 (owner: "the backpack shows through Mak ... the inner ear shows through the outer ear"): the
## depth-gap test alone also fired on Mak's own parts whenever his depth spread passed min_gap (high cameras: ears or hat
## in front of the pack and hooves, about 1 m deep), printing the pink ghost of his hidden back parts through his body.
## Now a mark pass (SELF_MARK_SHADER, alpha queue, normal depth test, both faces, invisible) writes stencil SELF_STENCIL wherever one
## of Mak's own surfaces is the visible one, and the silhouette only draws where that mark is absent, i.e. where another
## object covers him. Mak's own overlapping parts can never x-ray each other again.
const SELF_STENCIL := 77
const SELF_MARK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, 77;
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.003;
}
"""
const SILHOUETTE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 77;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 tint : source_color = vec4(0.949, 0.604, 0.639, 0.55);
uniform vec4 ink : source_color = vec4(0.23, 0.12, 0.1, 0.8);
uniform float min_gap = 0.35;
void fragment() {
	float sd = texture(depth_tex, SCREEN_UV).r;
	vec4 a = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, sd, 1.0);
	vec4 b = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, FRAGCOORD.z, 1.0);
	float scene_z = -a.z / a.w;
	float my_z = -b.z / b.w;
	if (my_z - scene_z < min_gap) {
		discard;
	}
	float edge = smoothstep(0.55, 0.85, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	ALBEDO = mix(tint.rgb, ink.rgb, edge);
	ALPHA = mix(tint.a, ink.a, edge);
}
"""
static var _silhouette_mat: ShaderMaterial = null
static var _self_mark_mat: ShaderMaterial = null


func _add_occlusion_silhouette(model: Node) -> void:
	if _silhouette_mat == null:
		var sh := Shader.new()
		sh.code = SILHOUETTE_SHADER
		_silhouette_mat = ShaderMaterial.new()
		_silhouette_mat.shader = sh
		_silhouette_mat.render_priority = 10
		var mk := Shader.new()
		mk.code = SELF_MARK_SHADER
		_self_mark_mat = ShaderMaterial.new()
		_self_mark_mat.shader = mk
		# Drawn first in the alpha queue (after every opaque surface, before the silhouette).
		_self_mark_mat.render_priority = -100
		_self_mark_mat.next_pass = _silhouette_mat
	# The stencil mark keeps Mak's own parts out of the silhouette, so the gap only has to ignore ground contact
	# (hooves sunk a few cm into the floor). Fix r2's 0.8 m hero v2 workaround is gone: 0.35 m catches thin props again.
	_silhouette_mat.set_shader_parameter("min_gap", 0.35)
	# The mark + silhouette pair rides on material_overlay, not at the end of each surface's pass chain, so material
	# swaps on Mak's parts (the Golden Top Hat's material_override, RetroLook's toon twins, hat changes) can never drop
	# the stencil mark (the gold hat printed pink patches when it replaced the chain).
	for mi in _meshes_under(model):
		if mi.material_overlay == null:
			mi.material_overlay = _self_mark_mat


## Fix r1 (character visuals): a dark band showed between the beanie cuff and the forehead (the cuff underside, lifted
## by the 12 mm offset). Seat the beanie 9 mm lower along the head's down axis so the cuff rim sits on the skin.
func _fit_beanie(model: Node) -> void:
	for mi in _meshes_under(model):
		if not str(mi.name).to_lower().contains("beanie"):
			continue
		var par := mi.get_parent() as Node3D
		if par == null:
			continue
		var down_local := (par.global_transform.basis.inverse() * Vector3.DOWN)
		# Fix r2 (visual major M5): 1 cm lower again and the cuff 3 % wider so it overlaps the forehead in every pose.
		mi.position += down_local.normalized() * 0.019 * (1.0 / maxf(par.global_transform.basis.get_scale().y, 0.001))
		mi.scale *= Vector3(1.03, 1.0, 1.03)


func _meshes_under(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(_meshes_under(c))
	return out


func _set_visual_layers(n: Node, mask: int) -> void:
	if n is VisualInstance3D and not (n is Decal):
		(n as VisualInstance3D).layers = mask
	for c in n.get_children():
		_set_visual_layers(c, mask)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null


# ------------------------------------------------------------------ public interface

func take_damage(amount: int, from_position: Vector3, knock_up: float = -1.0) -> void:
	if invulnerable > 0.0 or state == "dead" or state == "fallout":
		return
	# REA round 2: the hurt state lasts 24 / 30 / 80 reference frames by hit strength, Mak is untouchable through
	# it and for 30 frames after it ends (refreshed when hurt_land finishes).
	_hurt_total = p.hurt_time_hard if amount >= 4 else (p.hurt_time_medium if amount >= 2 else p.hurt_time_soft)
	_hurt_at = sim_time
	invulnerable = _hurt_total + p.invulnerable_time
	hurt_blink = invulnerable
	var g := _autoload("Game")
	if g != null and g.has_method("damage"):
		g.call("damage", amount)
	if _fb("player_hurt", {"amount": amount, "from": from_position}):
		_sfx("hurt")
		_spawn_fx("hit_stars", global_position + Vector3.UP * 0.9, 1.0)
	var away := global_position - from_position
	away.y = 0.0
	if away.length() < 0.05:
		away = -dir_from_yaw(facing_yaw)
	away = away.normalized()
	_release_holds()
	_set_crouch_shape(false)
	use_slide_vel = false
	# REA round 2: a source within 90 deg of the facing turns Mak toward it and throws him backwards; a source
	# behind turns him away and throws him forwards. Either way he travels away from it at the knockback speed.
	hurt_from_behind = dir_from_yaw(facing_yaw).dot(-away) < 0.0
	if hurt_from_behind:
		facing_yaw = yaw_from_dir(away)
		forward_speed = p.knockback_speed
	else:
		facing_yaw = yaw_from_dir(-away)
		forward_speed = -p.knockback_speed
	side_speed = 0.0
	vy = knock_up if knock_up >= 0.0 else p.knockback_up
	grounded = false
	_set_state("hurt_air")
	if g != null:
		var hp: Variant = g.get("health")
		if hp != null and int(hp) <= 0:
			_die()


func bounce(up_velocity: float) -> void:
	if state == "dead" or state == "fallout":
		return
	_release_holds()
	_set_crouch_shape(false)
	if use_slide_vel:
		_slide_to_forward()
	vy = up_velocity
	grounded = false
	_fresh_launch = true
	_kick_wall_valid = false
	jump_cut_done = true
	_air_kick_used = false
	_set_state("bounce")
	jumped.emit("bounce")
	if _fb("player_bounce", {"impact": up_velocity}):
		_sfx("jump_2")
	_kick_anim("jump")


func add_impulse(v: Vector3) -> void:
	ext_vel += Vector3(v.x, 0.0, v.z)
	vy += v.y
	if v.y > 0.5 and not is_air_state(state) and not MANUAL_STATES.has(state):
		grounded = false
		if use_slide_vel:
			_slide_to_forward()
		_set_state("fall")


func respawn(at: Transform3D) -> void:
	_release_holds()
	var f := -at.basis.z
	var yaw := facing_yaw if Vector2(f.x, f.z).length() < 0.01 else yaw_from_dir(f)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), at.origin)
	facing_yaw = yaw
	forward_speed = 0.0
	side_speed = 0.0
	vy = 0.0
	ext_vel = Vector3.ZERO
	wind_vel = Vector3.ZERO
	slide_vel = Vector3.ZERO
	use_slide_vel = false
	velocity = Vector3.ZERO
	_fallback_timer = -1.0
	_kick_wall_valid = false
	jump_buffer = 0.0
	coyote = 0.0
	chain_kind = ""
	braking = false
	attack_active = false
	_combo_queued = false
	_fresh_launch = false
	_steep_frames = 0
	_step_grace = 0
	_snap_next = true
	_set_crouch_shape(false)
	grounded = true
	invulnerable = maxf(invulnerable, 0.6)
	spawn_xform = global_transform
	_set_state("idle")
	reset_physics_interpolation()
	if visual != null:
		reset_physics_interpolation()
	teleported.emit()
	if is_inside_tree() and physics_frame > 0 and not inp.replay_active:
		if _fb("player_respawn", {}):
			_spawn_fx("checkpoint", global_position, 0.8)


func is_ground_pounding() -> bool:
	return state == "ham_slam" or (state == "slam_land" and state_time < 0.12)


func is_attacking() -> bool:
	return attack_active or state == "punch" or state == "jump_kick" or state == "dive" or state == "ham_slam" \
		or (state == "belly_slide" and slide_vel.length() > 2.0)


func get_state_name() -> String:
	return state


func celebrate(duration: float = 1.8) -> void:
	if state == "dead" or state == "fallout":
		return
	_release_holds()
	if use_slide_vel:
		_slide_to_forward()
	_celebrate_time = 0.35 if get_tree().paused else duration
	forward_speed = 0.0
	side_speed = 0.0
	if state != "celebrate":
		_fb("player_celebrate", {"paused": get_tree().paused})
	_set_state("celebrate")


func set_hat(hat_id: String) -> void:
	var changed := hat_id != hat
	hat = hat_id
	if animator != null and animator.has_method("set_hat"):
		animator.call("set_hat", hat_id)
	hat_changed.emit(hat_id)
	if changed and is_inside_tree() and physics_frame > 0:
		if _fb("player_hat_change", {"hat": hat_id}):
			_spawn_fx("poof", global_position + Vector3.UP * 1.05, 0.5)


## Called by MakAnimator for purely visual beats (the idle sniff of the air).
func on_anim_event(event_name: String) -> void:
	match event_name:
		"sniff_air":
			if _fb("player_sniff_air", {}):
				_sfx("sniff")


## Liquids: world builders call this (or tag an Area3D with group "liquid" and meta liquid = "water" or
## "cocoa", or a floor body with meta surface = "water" or "cocoa") to splash Mak into water or hot cocoa.
## Liquid kind of an overlapping area ("" when it is not a liquid): group "liquid" or meta "liquid", plus the
## objects track's HazardVolume with the HOT_CHOCOLATE look (cocoa).
func _liquid_kind(a: Area3D) -> String:
	if a.has_meta("liquid"):
		return str(a.get_meta("liquid"))
	if a.is_in_group("liquid"):
		return "water"
	if a.is_in_group("hazard"):
		var look: Variant = a.get("look")
		var sc := a.get_script() as Script
		if look is int and sc != null:
			var looks: Variant = sc.get_script_constant_map().get("Look")
			if looks is Dictionary and (looks as Dictionary).get("HOT_CHOCOLATE", -1) == look:
				return "cocoa"
	return ""


func splash(kind: String = "water") -> void:
	if _splash_cd > 0.0:
		return
	_splash_cd = 0.35
	var cocoa := kind == "cocoa" or kind == "chocolate"
	if _fb("world_cocoa_splash" if cocoa else "world_splash", {"impact": absf(velocity.y), "speed": velocity.length()}):
		_sfx("splash_cocoa" if cocoa else "splash")
		_spawn_fx("cocoa_splash" if cocoa else "splash", global_position + Vector3.UP * 0.1, 1.0)


func is_air_state(s: String) -> bool:
	return AIR_STATES.has(s)


func get_horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


func on_footstep(foot: int) -> void:
	## Called by the animator at each foot contact.
	footstep.emit(foot, surface)
	var fast := forward_speed > p.run_top_speed * 0.8
	# Hero v2 fix r1 (animation blocker): the footstep puffs hid the stubby legs on almost every frame. No footstep VFX
	# below 3 m/s (the sound still plays); at a run only the left hoof puffs, at 0.6 scale, so contacts and the passing
	# pose stay readable.
	var fx_ok := hero_v2 == false or (forward_speed >= 3.0 and foot == 0)
	var fp := {"foot": foot, "surface": surface, "speed": forward_speed}
	if not fx_ok:
		fp["no_vfx"] = true
	elif hero_v2:
		fp["scale"] = 0.6
	if _fb("player_footstep", fp):
		_sfx("footstep_" + surface)
		if fast:
			_spawn_fx("dust", global_position, 0.5)


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if p == null:
		return
	if _snap_next:
		_snap_next = false
		if grounded and not is_on_floor():
			apply_floor_snap()   # spawn markers sit a few cm above the floor; settle without a landing
	inp.sample(_ui_blocks_input())
	if not inp.teleport.is_empty():
		var tp: Dictionary = inp.teleport
		var tpos: Vector3 = tp["pos"]
		respawn(Transform3D(Basis(Vector3.UP, deg_to_rad(float(tp["yaw_deg"]))), tpos))
	match inp.call_request:
		"celebrate":
			celebrate()
		"top_hat", "beanie":
			set_hat(inp.call_request)
	_update_intent()
	_tick_timers(delta)
	if inp.jump_pressed:
		jump_buffer = p.jump_buffer_time
		_jump_press_time = sim_time
	_scan_areas(delta)
	state_time += delta
	sim_time += delta
	attack_active = false
	_step_frame = false
	_run_state(delta)
	if MANUAL_STATES.has(state):
		velocity = Vector3.ZERO
		grounded = false
	else:
		_compose_velocity(delta)
		var pre_vel := velocity
		if grounded and not is_air_state(state) and _try_step_up(delta):
			_step_frame = true
			_step_grace = 8
		move_and_slide()
		_post_move(delta, pre_vel)
	facing_yaw = wrapf(facing_yaw, -PI, PI)
	rotation = Vector3(0.0, facing_yaw, 0.0)
	_process_attacks(delta)
	_check_kill_plane()
	_write_trace()
	physics_frame += 1
	if inp.end_frame >= 0 and physics_frame >= inp.end_frame:
		_finish_replay()


func _run_state(dt: float) -> void:
	match state:
		"idle":
			_st_idle(dt)
		"walk":
			_st_walk(dt)
		"skid":
			_st_skid(dt)
		"crouch":
			_st_crouch(dt)
		"crouch_slide":
			_st_crouch_slide(dt)
		"punch":
			_st_punch(dt)
		"slam_land":
			_st_slam_land(dt)
		"belly_slide":
			_st_belly_slide(dt)
		"slide_getup":
			_st_simple_ground(dt, p.slide_getup_time)
		"slope_slide":
			_st_slope_slide(dt)
		"sniff":
			_st_sniff(dt)
		"celebrate":
			_st_celebrate(dt)
		"hurt_land":
			_st_hurt_land(dt)
		"ledge_hang":
			_st_ledge_hang(dt)
		"ledge_climb":
			_st_ledge_climb(dt)
		"pole_climb":
			_st_pole_climb(dt)
		"ham_slam":
			_st_ham_slam(dt)
		"dive":
			_st_dive(dt)
		"jump_kick":
			_st_jump_kick(dt)
		"wall_slide":
			_st_wall_slide(dt)
		"hurt_air", "fallout", "dead", "bonk":
			_st_passive_air(dt)
		"swim":
			_st_swim(dt)
		_:
			_st_air(dt)


func _tick_timers(dt: float) -> void:
	if mantle_time >= 0.0:
		mantle_time += dt
		if mantle_time > 0.4:
			mantle_time = -1.0
	jump_buffer = maxf(jump_buffer - dt, 0.0)
	coyote = maxf(coyote - dt, 0.0)
	invulnerable = maxf(invulnerable - dt, 0.0)
	hurt_blink = maxf(hurt_blink - dt, 0.0)
	ledge_cooldown = maxf(ledge_cooldown - dt, 0.0)
	pole_cooldown = maxf(pole_cooldown - dt, 0.0)
	_stomp_cooldown = maxf(_stomp_cooldown - dt, 0.0)
	_splash_cd = maxf(_splash_cd - dt, 0.0)
	if _fallback_timer > 0.0:
		_fallback_timer -= dt
		if _fallback_timer <= 0.0:
			_fallback_respawn()


func _update_intent() -> void:
	if inp.stick_mag <= 0.0:
		intended_dir = Vector3.ZERO
		_steer_locked = false
		return
	var yaw := 0.0 if inp.steer_world else _steering_yaw()
	var fwd := dir_from_yaw(yaw)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var d := right * inp.stick.x + fwd * inp.stick.y
	if d.length() < 0.0001:
		intended_dir = Vector3.ZERO
		return
	intended_dir = d.normalized()
	intended_yaw = yaw_from_dir(intended_dir)


## Steering basis lock (fix r1): auto-follow turns the camera fastest while Mak runs sideways, so steering with the
## live camera yaw every tick turned a constant stick into a 2.2 m circle. The basis is captured when the stick
## leaves neutral and kept while the stick stays within 35 degrees of that direction; it blends to the live yaw
## over about 0.4 s when the stick swings further or the player orbits the camera by hand.
func _steering_yaw() -> float:
	var live := _camera_yaw()
	var sd := inp.stick.normalized() if inp.stick.length() > 0.0001 else Vector2.ZERO
	if not _steer_locked:
		_steer_locked = true
		_steer_yaw = live
		_steer_dir = sd
		_steer_release = 0.0
		return live
	if sd != Vector2.ZERO and _steer_dir != Vector2.ZERO and absf(_steer_dir.angle_to(sd)) > deg_to_rad(35.0):
		_steer_dir = sd
		_steer_release = 0.4
	if camera_rig != null and is_instance_valid(camera_rig):
		var mt: Variant = camera_rig.get("_manual_timer")
		if mt != null and float(mt) < 0.05:
			_steer_release = 0.4
	if _steer_release > 0.0:
		_steer_release -= _dt_phys()
		_steer_yaw = lerp_angle(_steer_yaw, live, 1.0 - exp(-9.0 * _dt_phys()))
		if _steer_release <= 0.0:
			_steer_yaw = live if absf(angle_difference(_steer_yaw, live)) < deg_to_rad(4.0) else _steer_yaw
	# Fix r2 (feel minor M3): once the camera has turned more than 20 degrees away from the locked basis, the basis decays
	# toward the live yaw at 60 deg/s, so "right" never ends up pointing into the screen.
	var gap := angle_difference(_steer_yaw, live)
	if absf(gap) > deg_to_rad(20.0):
		_steer_yaw += signf(gap) * minf(absf(gap) - deg_to_rad(20.0), deg_to_rad(60.0) * _dt_phys())
	return _steer_yaw


func _camera_yaw() -> float:
	var cam := get_viewport().get_camera_3d()
	if camera_rig != null and is_instance_valid(camera_rig):
		var rig_cam := camera_rig.get_node_or_null("Camera3D") as Camera3D
		if cam == null or cam == rig_cam:
			var y: Variant = camera_rig.get("yaw")
			if y != null:
				return float(y)
	if cam != null:
		var f := -cam.global_basis.z
		return atan2(-f.x, -f.z)
	return 0.0


func _compose_velocity(dt: float) -> void:
	var h: Vector3
	if use_slide_vel:
		h = slide_vel
	else:
		var fdir := dir_from_yaw(facing_yaw)
		var left := Vector3(-cos(facing_yaw), 0.0, sin(facing_yaw))
		h = fdir * forward_speed + left * side_speed
		if _air_steer_tick:
			h += air_steer
	if not _air_steer_tick:
		air_steer = Vector3.ZERO   # D039: only the steerable air states (those running _air_physics) keep it
	_air_steer_tick = false
	var decel := p.external_ground_decel if grounded else p.external_air_decel
	ext_vel = ext_vel.move_toward(Vector3.ZERO, decel * dt)
	var w := wind_vel * (p.wind_ground_factor if grounded else 1.0)
	velocity = h + ext_vel + Vector3(w.x, 0.0, w.z)
	velocity.y = vy + w.y


func _post_move(_dt: float, pre_vel: Vector3) -> void:
	var on_floor := is_on_floor()
	var pre_vy := pre_vel.y
	wall_normal = Vector3.ZERO
	var best := -2.0
	var fdir := dir_from_yaw(facing_yaw)
	var floor_col: Object = null
	var floor_best := 0.6
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var col := c.get_collider()
		if n.y > floor_best:
			floor_best = n.y
			floor_col = col
		if n.y > 0.6 and pre_vy < -1.0 and is_air_state(state) and state != "hurt_air" and state != "dead":
			if _try_stomp(col):
				return
		if absf(n.y) < 0.4:
			var hn := Vector3(n.x, 0.0, n.z).normalized()
			var d := -hn.dot(fdir)
			if d > best:
				best = d
				wall_normal = hn
				wall_point = c.get_position()
	if is_on_ceiling() and vy > 0.0:
		vy = 0.0
	if is_air_state(state):
		if on_floor and vy <= 0.0:
			floor_collider = floor_col
			_land(pre_vy)
		else:
			grounded = false
			if wall_normal != Vector3.ZERO:
				_reduce_speed_on_wall()
				if WALL_STATES.has(state):
					_air_wall_contact(pre_vel)
	else:
		if on_floor:
			grounded = true
			vy = 0.0
			floor_normal = get_floor_normal()
			if floor_col != null:
				floor_collider = floor_col
			last_platform_vel = get_platform_velocity()
			if has_method("get_platform_angular_velocity"):
				var av: Variant = call("get_platform_angular_velocity")
				if av is Vector3:
					facing_yaw += (av as Vector3).y * _dt_phys()
			_update_surface()
			if wall_normal != Vector3.ZERO:
				_reduce_speed_on_wall()
			# Fix r2 (feel minor M4): stick held into a wall while standing still is a push (animator pose, no walk cycle).
			var hsp := Vector2(velocity.x - ext_vel.x, velocity.z - ext_vel.z).length()
			if state == "walk" and wall_normal != Vector3.ZERO and inp.stick_mag > 0.3 and hsp < 0.5 					and intended_dir.dot(-wall_normal) > cos(deg_to_rad(45.0)):
				_push_frames += 1
			else:
				_push_frames = 0
			var was_pushing := pushing_wall
			pushing_wall = _push_frames > 4
			if pushing_wall and not was_pushing:
				_fb("player_push", {"normal": wall_normal}, wall_point)
			_steep_frames = _steep_frames + 1 if (_floor_angle_deg() > p.steep_slope_angle and _floor_is_steep_below()) else 0
			if _steep_frames >= 4 and state != "belly_slide" and state != "slope_slide" and state != "dead" and state != "celebrate":
				_start_slope_slide()
		elif not _step_frame:
			if _step_grace > 0:
				# Just stepped up: settle onto the riser instead of flickering into a fall.
				_step_grace -= 1
				vy = -3.0
			else:
				_walk_off()


func _dt_phys() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


func _reduce_speed_on_wall() -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z) - ext_vel
	if use_slide_vel:
		slide_vel = hv
		return
	var fdir := dir_from_yaw(facing_yaw)
	var along := hv.dot(fdir)
	if forward_speed > 0.0 and along < forward_speed:
		forward_speed = maxf(along, 0.0)


func _walk_off() -> void:
	grounded = false
	ext_vel += Vector3(last_platform_vel.x, 0.0, last_platform_vel.z)
	vy = minf(vy, 0.0) + maxf(last_platform_vel.y, 0.0)
	coyote = p.coyote_time
	_set_crouch_shape(false)
	if state == "belly_slide":
		_slide_to_forward()
		_set_state("dive")
	elif state == "dead" or state == "celebrate":
		pass
	else:
		if use_slide_vel:
			_slide_to_forward()
		_set_state("fall")


func _land(pre_vy: float) -> void:
	impact_speed = maxf(-pre_vy, 0.0)
	var from := state
	grounded = true
	vy = 0.0
	if from == "dead" or from == "fallout":
		forward_speed = 0.0
		side_speed = 0.0
		return
	floor_normal = get_floor_normal()
	_kick_wall_valid = false
	_air_kick_used = false
	air_time = 0.0
	last_land_time = sim_time
	_steer_locked = false   # fix r2: a landing re-captures the steering basis from the live camera
	# Chain sources (fix r1, Docs/MOVEMENT_REFERENCE.md Jumps table): a freefall landing and a side-flip landing also
	# chain into the double jump.
	if from == "jump" or from == "double_jump":
		chain_kind = from
	elif from == "fall" or from == "side_flip":
		chain_kind = "jump"
	else:
		chain_kind = ""
	_update_surface()
	landed.emit(impact_speed)
	inp.notify("land")
	if floor_collider is Node and (floor_collider as Node).is_in_group("bouncy") and from != "dead":
		var bv := float((floor_collider as Node).get_meta("bounce_velocity", 15.0))
		if from == "ham_slam":
			bv *= 1.2
			ground_pounded.emit(global_position)
		bounce(bv)
		return
	var heavy := impact_speed >= p.heavy_land_speed
	match from:
		"ham_slam":
			_slam_impact()
			return
		"dive":
			slide_vel = dir_from_yaw(facing_yaw) * maxf(forward_speed, 0.0) + ext_vel
			ext_vel = Vector3.ZERO
			use_slide_vel = true
			_set_state("belly_slide")
			if _fb("player_slide_start", {"impact": impact_speed, "surface": surface}):
				_sfx("slide")
				_spawn_fx("dust", global_position, 1.0)
			return
		"hurt_air", "bonk":
			if from == "bonk" or _hurt_total <= 0.0:
				forward_speed = 0.0
				hurt_land_duration = p.hurt_land_time
			else:
				# REA round 2: the knockback slides on after touchdown and the hurt state ends 24 / 30 / 80
				# reference frames after the hit.
				hurt_land_duration = maxf(_hurt_total - (sim_time - _hurt_at), 0.2)
			_set_state("hurt_land")
			if _fb("player_land", {"impact": impact_speed, "heavy": true, "surface": surface, "from": from}):
				_sfx("land_heavy")
			return
		"backflip":
			forward_speed = 0.0
		"triple_jump", "side_flip", "wall_kick", "rollout":
			forward_speed = maxf(forward_speed, 0.0)
	side_speed = 0.0
	if _fb("player_land", {"impact": impact_speed, "heavy": heavy, "surface": surface, "from": from}):
		_sfx("land_heavy" if heavy else "land")
		_spawn_fx("dust", global_position, 1.4 if heavy else 0.8)
		if heavy:
			_spawn_fx("ring", global_position, 1.0)
	if surface == "water" or surface == "cocoa":
		splash(surface)
	if _floor_angle_deg() > p.steep_slope_angle and _floor_is_steep_below():
		_start_slope_slide()
		return
	if from == "celebrate_air":
		_set_state("celebrate")
		return
	if inp.crouch_held and forward_speed < p.crouch_slide_min_speed:
		_set_state("crouch")
	elif inp.stick_mag > 0.0 or forward_speed > 0.3:
		forward_speed = maxf(forward_speed, 0.0) * (p.land_speed_keep if inp.stick_mag > 0.0 else 1.0)
		# D039 (owner request): touching down with the stick released stops Mak at land_stop_decel (a few cm to a
		# few tens of cm from a normal jump, a short skid from a long jump) instead of the walk-release braking.
		_land_stop = inp.stick_mag <= 0.0
		_set_state("walk")
	else:
		forward_speed = 0.0
		_set_state("idle")
	# A buffered jump fires on the landing frame; the chain window starts now. A press up to 0.2 s early that is still
	# held at touchdown counts too (fix r1: presses 7-9 frames early used to be dropped while the button was held).
	if jump_buffer <= 0.0 and inp.jump_held and sim_time - _jump_press_time < 0.2 and _jump_press_time > last_jump_time():
		jump_buffer = 0.001
	if jump_buffer > 0.0:
		_ground_jump_from_input()
		_fresh_launch = is_air_state(state)


# ------------------------------------------------------------------ ground states

var _last_jump_time := -10.0


func last_jump_time() -> float:
	return _last_jump_time


func _ground_common() -> bool:
	if jump_buffer > 0.0:
		_ground_jump_from_input()
		return true
	if inp.attack_pressed:
		if forward_speed >= p.dive_min_speed and inp.stick_mag > 0.75 * 0.75:
			_do_dive(true)
		else:
			_start_punch()
		return true
	if inp.crouch_pressed:
		if forward_speed > p.crouch_slide_min_speed:
			_set_state("crouch_slide")
			if _fb("player_crouch_slide", {"speed": forward_speed}):
				_sfx("slide")
		else:
			_set_state("crouch")
		return true
	if inp.sniff_held and state != "sniff":
		_set_state("sniff")
		return true
	return false


func _ground_jump_from_input() -> void:
	jump_buffer = 0.0
	if inp.crouch_held:
		if not _can_stand():
			return
		if forward_speed > p.long_jump_min_speed:
			_do_long_jump()
		else:
			_do_backflip()
		return
	_do_ground_jump()


func _st_idle(dt: float) -> void:
	forward_speed = move_toward(forward_speed, 0.0, p.stop_decel * dt)
	if _ground_common():
		return
	if inp.stick_mag > 0.0:
		facing_yaw = intended_yaw
		_set_state("walk")


func _st_walk(dt: float) -> void:
	if _ground_common():
		return
	_ground_run(dt, p.run_top_speed)
	if inp.stick_mag <= 0.0 and forward_speed <= p.stop_speed:
		forward_speed = 0.0
		_set_state("idle")


func _ground_run(dt: float, top: float) -> void:
	var target := top * inp.stick_mag
	if inp.stick_mag > 0.0:
		var diff := absf(angle_difference(facing_yaw, intended_yaw))
		if state == "walk" and inp.stick_mag > 0.5 and diff > deg_to_rad(p.skid_angle_deg) \
				and forward_speed >= p.run_top_speed * p.skid_min_speed_ratio:
			_set_state("skid")
			if _fb("player_skid", {"speed": forward_speed}):
				_sfx("skid")
				_spawn_fx("dust", global_position, 0.7)
			return
		var rate := p.turn_rate_deg if forward_speed > p.turn_slow_speed else p.turn_rate_slow_deg
		facing_yaw = _approach_angle(facing_yaw, intended_yaw, deg_to_rad(rate) * dt)
		if forward_speed < target:
			var a := p.walk_accel * (1.0 - p.accel_taper * clampf(forward_speed / p.run_top_speed, 0.0, 1.0))
			forward_speed = minf(forward_speed + a * dt, target)
		else:
			forward_speed = maxf(forward_speed - p.overspeed_decel * dt, target)
	else:
		if not braking and forward_speed >= p.brake_min_speed and state == "walk":
			braking = true
			if _fb("player_brake", {"speed": forward_speed}):
				_sfx("skid")
		var stop_rate := p.brake_decel if braking else p.stop_decel
		if _land_stop:
			stop_rate = maxf(stop_rate, p.land_stop_decel)   # D039
		forward_speed = maxf(forward_speed - stop_rate * dt, 0.0)
	if inp.stick_mag > 0.0 or forward_speed <= 0.0:
		braking = false
		_land_stop = false
	# Slopes: uphill slows, downhill speeds up (walkable slopes only).
	var n := floor_normal
	var s := Vector2(n.x, n.z).length()
	if s > 0.05 and forward_speed > 0.0 and _floor_angle_deg() < p.steep_slope_angle:
		var downhill := Vector3(n.x, 0.0, n.z).normalized()
		var fdir := dir_from_yaw(facing_yaw)
		forward_speed = maxf(forward_speed + downhill.dot(fdir) * s * p.slope_speed_factor * dt, 0.0)
	if forward_speed < 0.0:
		forward_speed = move_toward(forward_speed, 0.0, p.stop_decel * dt)


func _st_skid(dt: float) -> void:
	if jump_buffer > 0.0:
		jump_buffer = 0.0
		_do_side_flip()
		return
	forward_speed = maxf(forward_speed - p.skid_decel * dt, 0.0)
	var reversed := inp.stick_mag > 0.3 and absf(angle_difference(facing_yaw, intended_yaw)) > deg_to_rad(p.skid_angle_deg) * 0.7
	if inp.stick_mag > 0.3 and not reversed:
		_set_state("walk")
		return
	if forward_speed <= 0.0 or state_time > p.skid_max_time:
		if inp.stick_mag > 0.1:
			facing_yaw = intended_yaw
			forward_speed = p.skid_exit_speed
			_set_state("walk")
		else:
			_set_state("idle")


func _st_crouch(dt: float) -> void:
	_set_crouch_shape(true)
	if jump_buffer > 0.0:
		if _can_stand():
			jump_buffer = 0.0
			if forward_speed > p.long_jump_min_speed:
				_do_long_jump()
			else:
				_do_backflip()
		return
	if not inp.crouch_held and _can_stand():
		_set_crouch_shape(false)
		_set_state("walk" if inp.stick_mag > 0.0 else "idle")
		return
	var target := p.crouch_walk_speed * inp.stick_mag
	if inp.stick_mag > 0.0:
		facing_yaw = _approach_angle(facing_yaw, intended_yaw, deg_to_rad(p.turn_rate_slow_deg) * dt)
	forward_speed = move_toward(forward_speed, target, 10.0 * dt)


func _st_crouch_slide(dt: float) -> void:
	_set_crouch_shape(true)
	if jump_buffer > 0.0 and _can_stand():
		jump_buffer = 0.0
		if forward_speed > p.long_jump_min_speed:
			_do_long_jump()
		else:
			_do_backflip()
		return
	forward_speed = maxf(forward_speed - p.crouch_slide_decel * dt, 0.0)
	if inp.stick_mag > 0.0:
		facing_yaw = _approach_angle(facing_yaw, intended_yaw, deg_to_rad(60.0) * dt)
	if forward_speed < 1.0 or state_time > 1.0:
		if inp.crouch_held or not _can_stand():
			_set_state("crouch")
		else:
			_set_crouch_shape(false)
			_set_state("walk")


func _start_punch() -> void:
	combo_step = 1
	_set_state("punch")
	_begin_strike()


func _begin_strike() -> void:
	_attack_hits.clear()
	_combo_queued = false
	state_time = 0.0
	attack_kind = "kick" if combo_step == 3 else "punch"
	_strike_carry = maxf(forward_speed, 0.0)
	forward_speed = maxf(forward_speed, p.strike_lunge)
	_set_attack_shape(attack_kind)
	attacked.emit(attack_kind)
	if _fb("player_kick" if attack_kind == "kick" else "player_punch", {"combo": combo_step}):
		_sfx(attack_kind)


func _st_punch(dt: float) -> void:
	# REA round 2 timing: strike phase, hit window and recovery per strike; attack pressed after the strike phase
	# starts the next strike at once (presses during the strike phase are buffered: our convenience).
	var dur := p.kick_time if combo_step == 3 else (p.punch2_time if combo_step == 2 else p.punch_time)
	var active_from := 0.0 if combo_step == 3 else (p.punch2_active_from if combo_step == 2 else p.strike_active_from)
	var active_to := p.kick_active_to if combo_step == 3 else (p.punch2_active_to if combo_step == 2 else p.strike_active_to)
	var ready := p.punch2_strike_time if combo_step == 2 else p.punch_strike_time
	if state_time >= active_from and state_time <= active_to:
		attack_active = true
	# REA round 2 lunge: 10, 7, 5, 3, 2, 1, 1, 0 u/f over the strike's first 8 reference frames; running momentum
	# carried into the strike still bleeds off at 14 m/s^2.
	_strike_carry = move_toward(_strike_carry, 0.0, 14.0 * dt)
	var fi := int(state_time * 30.0)
	var lunge := p.strike_lunge_table[fi] if fi < p.strike_lunge_table.size() else 0.0
	forward_speed = maxf(_strike_carry, lunge)
	if inp.stick_mag > 0.0:
		facing_yaw = _approach_angle(facing_yaw, intended_yaw, deg_to_rad(360.0) * dt)
	if inp.attack_pressed and combo_step < 3 and state_time > 0.04:
		_combo_queued = true
	if jump_buffer > 0.0:
		_ground_jump_from_input()
		return
	if _combo_queued and combo_step < 3 and state_time >= ready:
		combo_step += 1
		_begin_strike()
		return
	# REA round 2: stick input ends a standing strike (the reference at once; we wait for the hit window to close).
	if inp.stick_mag > 0.5 and state_time > active_to and not _combo_queued:
		_set_state("walk")
		return
	if state_time >= dur - 0.001:
		_set_state("walk" if inp.stick_mag > 0.0 else "idle")


func _st_slam_land(_dt: float) -> void:
	forward_speed = 0.0
	if state_time < 0.1:
		attack_active = true
		attack_kind = "slam"
	if state_time >= p.slam_jump_after and jump_buffer > 0.0:
		_ground_jump_from_input()
		return
	if state_time >= p.slam_land_time:
		_set_state("walk" if inp.stick_mag > 0.0 else "idle")


func _st_belly_slide(dt: float) -> void:
	if jump_buffer > 0.0 or inp.attack_pressed:
		jump_buffer = 0.0
		_do_rollout()
		return
	_slide_physics(dt, p.belly_slide_friction, p.slide_turn_rate_deg, p.slope_slide_accel * 0.6)
	if slide_vel.length() > 2.0:
		attack_active = true
		attack_kind = "slide"
	# REA round 2: a dive slide ends below 8 u/f, and only on a floor flatter than the slope threshold.
	if slide_vel.length() < p.belly_slide_stop_speed and state_time > 0.25 and _floor_angle_deg() < p.slide_flat_angle:
		_slide_to_forward()
		forward_speed = 0.0
		_set_state("slide_getup")


func _st_slope_slide(dt: float) -> void:
	if jump_buffer > 0.0 and state_time >= p.slide_jump_delay - 0.001:   # REA round 2: no slide jump in the first 5 frames
		jump_buffer = 0.0
		_slide_to_forward()
		forward_speed = minf(forward_speed, p.run_top_speed)
		vy = p.jump_velocity
		_enter_air("jump")
		return
	# REA round 2: speed builds by 7 u/f^2 x steepness and loses 8 % per reference frame; the stick along the
	# slide lowers (forward) or raises (back) that loss.
	var along := 0.0
	if inp.stick_mag > 0.0 and slide_vel.length() > 0.2:
		along = cos(intended_yaw - yaw_from_dir(slide_vel)) * inp.stick_mag
	var drag := maxf(p.slope_slide_drag - p.slope_slide_stick_drag * along, 0.0)
	_slide_physics(dt, p.slope_slide_friction, p.slope_slide_turn_deg, p.slope_slide_accel, drag)
	if slide_vel.length() > p.slope_slide_max_speed:
		slide_vel = slide_vel.normalized() * p.slope_slide_max_speed
	# REA round 2: the slide continues on floors steeper than 15 deg; flatter, Mak runs on with his speed (ours).
	if _floor_angle_deg() < p.slide_flat_angle and state_time > 0.15:
		_slide_to_forward()
		_set_state("walk")


func _slide_physics(dt: float, friction: float, turn_deg: float, slope_accel: float, drag: float = 0.0) -> void:
	var n := floor_normal
	var s := Vector2(n.x, n.z).length()
	if s > 0.02:
		slide_vel += Vector3(n.x, 0.0, n.z) * slope_accel * dt
	if drag > 0.0:
		slide_vel *= exp(-drag * dt)
	slide_vel = slide_vel.move_toward(Vector3.ZERO, friction * dt)
	if inp.stick_mag > 0.0 and slide_vel.length() > 0.2:
		var cur := yaw_from_dir(slide_vel)
		var ny := _approach_angle(cur, intended_yaw, deg_to_rad(turn_deg) * inp.stick_mag * dt)
		slide_vel = dir_from_yaw(ny) * slide_vel.length()
	if slide_vel.length() > 0.2:
		facing_yaw = yaw_from_dir(slide_vel)
	forward_speed = slide_vel.length()


func _start_slope_slide() -> void:
	if not use_slide_vel:
		slide_vel = dir_from_yaw(facing_yaw) * maxf(forward_speed, 0.0)
		use_slide_vel = true
	_set_crouch_shape(false)
	_set_state("slope_slide")
	if _fb("player_slide_start", {"kind": "slope"}):
		_sfx("slide")


func _slide_to_forward() -> void:
	if not use_slide_vel:
		return
	var sp := slide_vel.length()
	if sp > 0.05:
		facing_yaw = yaw_from_dir(slide_vel)
	forward_speed = sp
	use_slide_vel = false
	slide_vel = Vector3.ZERO


func _st_hurt_land(dt: float) -> void:
	if _hurt_total > 0.0:
		# REA round 2: the knockback speed keeps 90 % per reference frame on the ground and stops below 1 u/f.
		forward_speed *= pow(p.knockback_ground_keep, dt * 30.0)
		if absf(forward_speed) < 0.234:
			forward_speed = 0.0
	else:
		forward_speed = move_toward(forward_speed, 0.0, p.stop_decel * dt)
	if state_time >= hurt_land_duration:
		_set_state("walk" if inp.stick_mag > 0.0 else "idle")


func _st_simple_ground(dt: float, duration: float) -> void:
	forward_speed = move_toward(forward_speed, 0.0, p.stop_decel * dt)
	if state_time >= duration:
		_set_state("walk" if inp.stick_mag > 0.0 else "idle")


func _st_sniff(dt: float) -> void:
	if not inp.sniff_held:
		_set_sniff_target(null)
		_set_state("walk" if inp.stick_mag > 0.0 else "idle")
		return
	if jump_buffer > 0.0 or inp.attack_pressed or inp.crouch_pressed:
		_set_sniff_target(null)
		_ground_common()
		return
	_ground_run(dt, p.sniff_walk_speed)
	_sniff_scan -= dt
	if _sniff_scan <= 0.0:
		_sniff_scan = 0.25
		_set_sniff_target(_find_sniff_target())
	_update_sniff_reach()
	_sniff_sfx -= dt
	if _sniff_sfx <= 0.0:
		_sniff_sfx = 0.7
		if _fb("player_sniff", {"has_target": sniff_target != null}):
			_sfx("sniff")


func _st_celebrate(dt: float) -> void:
	forward_speed = move_toward(forward_speed, 0.0, p.stop_decel * dt)
	if not grounded:
		vy = maxf(vy - p.gravity * dt, -p.terminal_velocity)
	if state_time >= _celebrate_time:
		_set_state("idle")


func _st_swim(_dt: float) -> void:
	## Swimming is not implemented in night 01; leave the stub so the state name exists.
	_set_state("fall")


# ------------------------------------------------------------------ jumps

func _do_ground_jump() -> void:
	jump_buffer = 0.0
	var kind := "jump"
	var since := sim_time - last_land_time
	if since <= p.chain_window and forward_speed >= p.double_jump_min_speed:
		if chain_kind == "jump":
			kind = "double_jump"
		elif chain_kind == "double_jump" and forward_speed >= p.triple_jump_min_speed:
			kind = "triple_jump"
	var fs := maxf(forward_speed, 0.0)
	match kind:
		"jump":
			vy = p.jump_velocity + p.jump_speed_bonus * fs
		"double_jump":
			vy = p.double_jump_velocity + p.jump_speed_bonus * fs
		"triple_jump":
			vy = p.triple_jump_velocity
	forward_speed = fs * p.jump_forward_mult
	_enter_air(kind)


func _do_long_jump() -> void:
	forward_speed = minf(forward_speed * p.long_jump_speed_mult, p.long_jump_max_speed)
	vy = p.long_jump_velocity
	_set_crouch_shape(false)
	_enter_air("long_jump")


func _do_backflip() -> void:
	forward_speed = -p.backflip_back_speed
	vy = p.backflip_velocity
	_set_crouch_shape(false)
	_enter_air("backflip")


func _do_side_flip() -> void:
	var old := facing_yaw
	facing_yaw = intended_yaw if inp.stick_mag > 0.1 else facing_yaw + PI
	visual_yaw_offset = wrapf(old - facing_yaw, -PI, PI)
	rotation = Vector3(0.0, facing_yaw, 0.0)
	reset_physics_interpolation()
	forward_speed = p.side_flip_speed
	vy = p.side_flip_velocity
	_enter_air("side_flip")


func _do_rollout() -> void:
	_slide_to_forward()
	forward_speed = minf(forward_speed, p.run_top_speed)
	vy = p.rollout_velocity
	_enter_air("rollout")


func _enter_air(kind: String) -> void:
	if use_slide_vel:
		_slide_to_forward()
	ext_vel += Vector3(last_platform_vel.x, 0.0, last_platform_vel.z)
	vy += maxf(last_platform_vel.y, 0.0)
	last_platform_vel = Vector3.ZERO
	grounded = false
	coyote = 0.0
	jump_cut_done = false
	side_speed = 0.0
	_land_stop = false
	last_jump_kind = kind
	_last_jump_time = sim_time
	_set_state(kind)
	jumped.emit(kind)
	inp.notify("jump:" + kind)
	var jev := {"jump": "player_jump_1", "rollout": "player_jump_1", "double_jump": "player_jump_2",
		"triple_jump": "player_jump_3", "long_jump": "player_long_jump", "backflip": "player_backflip",
		"side_flip": "player_side_flip", "wall_kick": "player_wall_kick"}
	var jparams := {"speed": absf(forward_speed), "vy": vy}
	if kind == "wall_kick":
		jparams["normal"] = _kick_wall_n if _kick_wall_n != Vector3.ZERO else -dir_from_yaw(facing_yaw)
	if _fb(str(jev.get(kind, "player_jump_1")), jparams):
		match kind:
			"jump", "rollout":
				_sfx("jump_1")
			"double_jump":
				_sfx("jump_2")
			"triple_jump", "side_flip":
				_sfx("jump_3")
			"long_jump":
				_sfx("long_jump")
			"backflip":
				_sfx("backflip")
			"wall_kick":
				_sfx("wall_kick")
		_spawn_fx("dust", global_position, 0.6)
		if kind == "triple_jump" or kind == "long_jump" or kind == "wall_kick":
			_attach_fx("jump_trail")
	# The VFX JumpTrail ribbon rides on Mak for the double jump (Juice's player_jump_2 is a burst at the feet only;
	# the triple jump gets Juice's attached spin_trail, so it is not doubled there).
	if kind == "double_jump":
		_attach_fx("jump_trail")
	_kick_anim("jump")


func _st_air(dt: float) -> void:
	air_time += dt
	if state == "fall" and coyote > 0.0 and jump_buffer > 0.0:
		_do_ground_jump()
		return
	if AIR_ACTION_STATES.has(state):
		if inp.crouch_pressed:
			_start_ham_slam()
			return
		if inp.attack_pressed:
			if forward_speed >= p.dive_min_speed_air:
				_do_dive(false)
				return
			if not _air_kick_used:
				_start_jump_kick()
				return
	if (state == "jump" or state == "double_jump" or state == "long_jump" or state == "wall_kick") \
			and not jump_cut_done and not inp.jump_held and vy > p.jump_cut_min_velocity and state_time > 0.017:
		# Released while rising fast: the rise is cut instead of applying gravity this tick.
		vy *= p.jump_cut_factor
		_fresh_launch = true
	var cap := p.long_jump_max_speed if state == "long_jump" else p.air_max_speed
	_air_physics(dt, cap, true)
	if LEDGE_STATES.has(state) and vy <= p.ledge_grab_max_rise and forward_speed > -0.5:
		_try_ledge_grab()


func _air_physics(dt: float, cap: float, steer: bool) -> void:
	if _fresh_launch:
		_fresh_launch = false
	else:
		var g := p.long_jump_gravity if state == "long_jump" else p.gravity
		vy = maxf(vy - g * dt, -p.terminal_velocity)
	forward_speed = move_toward(forward_speed, 0.0, p.air_drag * dt)
	side_speed = 0.0
	if steer and inp.stick_mag > 0.0:
		var dyaw := angle_difference(facing_yaw, intended_yaw)
		forward_speed += p.air_accel * cos(dyaw) * inp.stick_mag * dt
		side_speed = p.air_side_speed * inp.stick_mag * sin(dyaw)
		if p.air_turn_rate_deg > 0.0:
			facing_yaw = _approach_angle(facing_yaw, intended_yaw, deg_to_rad(p.air_turn_rate_deg) * dt)
		elif state == "bounce" and p.bounce_turn_rate_deg > 0.0:
			# D039: a bounce (puff clouds, bouncy leaves, pads, stomps) can be turned toward the stick, so a
			# Cloud Hopper bounce that lands facing away from the next puff can still be aimed at it.
			facing_yaw = _approach_angle(facing_yaw, intended_yaw, deg_to_rad(p.bounce_turn_rate_deg) * inp.stick_mag * dt)
	# D039 (owner request, deviation on top of the reference above): the stick also bends the trajectory sideways
	# through a world-space drift that eases toward the stick and back to zero on release; its forward share is
	# dropped so forward arcs and distances stay the reference ones. Pulling back also brakes forward air speed.
	var steer_target := Vector3.ZERO
	if steer and inp.stick_mag > 0.0 and intended_dir != Vector3.ZERO:
		var fdir := dir_from_yaw(facing_yaw)
		var along := intended_dir.dot(fdir)
		var lateral := intended_dir - fdir * along
		steer_target = lateral * p.air_steer_speed * inp.stick_mag
		if along < 0.0 and forward_speed > 0.0:
			forward_speed = maxf(forward_speed - p.air_brake_decel * -along * inp.stick_mag * dt, 0.0)
	air_steer = air_steer.move_toward(steer_target, p.air_steer_accel * dt)
	_air_steer_tick = true
	if forward_speed > cap:
		forward_speed = maxf(forward_speed - p.air_overspeed_decel * dt, cap)
	if forward_speed < -p.air_max_back_speed and state != "backflip":
		forward_speed = minf(forward_speed + p.air_back_decel * dt, -p.air_max_back_speed)


func _st_passive_air(dt: float) -> void:
	air_time += dt
	if grounded and state == "dead":
		forward_speed = move_toward(forward_speed, 0.0, p.stop_decel * dt)
		return
	vy = maxf(vy - p.gravity * dt, -p.terminal_velocity)
	if state != "hurt_air" or _hurt_total <= 0.0:
		forward_speed = move_toward(forward_speed, 0.0, p.air_drag * dt)
	# else REA round 2: the air knockback holds its horizontal speed until touchdown.
	side_speed = 0.0


func _start_ham_slam() -> void:
	forward_speed = 0.0
	side_speed = 0.0
	vy = p.slam_rise_velocity
	ext_vel = Vector3.ZERO
	_slam_dropping = false
	_set_state("ham_slam")
	_fb("player_ham_slam_start", {})


func _st_ham_slam(dt: float) -> void:
	air_time += dt
	forward_speed = 0.0
	side_speed = 0.0
	if state_time < p.slam_rise_time:
		vy = p.slam_rise_velocity * (1.0 - state_time / p.slam_rise_time)
	elif state_time < p.slam_spin_time:
		vy = 0.0
	elif not _slam_dropping:
		_slam_dropping = true
		vy = -p.slam_drop_speed
	else:
		vy = maxf(vy - p.gravity * dt, -p.terminal_velocity)


func _slam_impact() -> void:
	forward_speed = 0.0
	_set_state("slam_land")
	_attack_hits.clear()
	attack_kind = "slam"
	_set_attack_shape("slam")
	ground_pounded.emit(global_position)
	attacked.emit("slam")
	if _fb("player_ham_slam", {"impact": impact_speed, "surface": surface}):
		_sfx("ham_slam")
		_spawn_fx("slam", global_position, 1.0)
		_camera_shake(0.38, 0.32)
	var target := _hittable_of(floor_collider)
	if target != null:
		target.call("hit_by_player", "slam", global_position)
		_attack_hits[target.get_instance_id()] = true


func _do_dive(from_ground: bool) -> void:
	forward_speed = minf(maxf(forward_speed, 0.0) + p.dive_boost, p.dive_max_speed)
	if from_ground:
		vy = p.dive_hop_velocity
		ext_vel += Vector3(last_platform_vel.x, 0.0, last_platform_vel.z)
		grounded = false
	_set_crouch_shape(false)
	_attack_hits.clear()
	attack_kind = "dive"
	_set_attack_shape("dive")
	_set_state("dive")
	attacked.emit("dive")
	if _fb("player_dive", {"from_ground": from_ground, "speed": forward_speed}):
		_sfx("dive")


func _st_dive(dt: float) -> void:
	air_time += dt
	attack_active = true
	attack_kind = "dive"
	_air_physics(dt, p.dive_max_speed, true)


func _start_jump_kick() -> void:
	_air_kick_used = true
	_attack_hits.clear()
	attack_kind = "jump_kick"
	_set_attack_shape("jump_kick")
	vy = p.jump_kick_velocity
	_set_state("jump_kick")
	attacked.emit("jump_kick")
	if _fb("player_jump_kick", {}):
		_sfx("kick")


func _st_jump_kick(dt: float) -> void:
	air_time += dt
	if state_time <= p.jump_kick_active_to:
		attack_active = true
		attack_kind = "jump_kick"
	if inp.crouch_pressed:
		_start_ham_slam()
		return
	_air_physics(dt, p.air_max_speed, true)
	if state_time >= p.jump_kick_time:
		_set_state("fall")


# ------------------------------------------------------------------ walls and ledges

func _air_wall_contact(pre_vel: Vector3) -> void:
	if _try_vault(pre_vel):
		return
	if LEDGE_STATES.has(state) and vy <= p.ledge_grab_max_rise and _try_ledge_grab():
		return
	var into := Vector3(pre_vel.x, 0.0, pre_vel.z).dot(-wall_normal)
	if into < p.wall_contact_min_speed:
		return
	var fdir := dir_from_yaw(facing_yaw)
	if -wall_normal.dot(fdir) < cos(deg_to_rad(p.wall_contact_max_angle_deg)):
		return
	var d := wall_normal.dot(wall_point)
	if into >= p.wall_bonk_speed:
		# Reference rule: hitting a wall head-on at high speed (long jumps) knocks Mak back instead of a soft
		# contact; no damage, a short tumble onto his back.
		forward_speed = -p.wall_bonk_back_speed
		side_speed = 0.0
		vy = minf(vy, p.wall_bonk_up)
		facing_yaw = yaw_from_dir(-wall_normal)
		_set_state("bonk")
		if _fb("player_bonk", {"normal": wall_normal, "impact": into}, wall_point):
			_sfx("bonk")
			_spawn_fx("hit_stars", wall_point + Vector3.UP * 0.2, 0.8)
			_camera_shake(0.18, 0.2)
		return
	if _kick_wall_valid and wall_normal.dot(_kick_wall_n) > 0.95 and absf(d - _kick_wall_d) < 0.35:
		return
	# Fix r2 (feel major M1): no wall slide on a wall whose top is lower than the capsule (1.25 m above the feet);
	# a waist-high wall used to play 6 frames of wall_slide and drop Mak.
	if _wall_top_below(1.25):
		return
	_wall_slide_n = wall_normal
	_wall_slide_d = d
	var hin := Vector3(pre_vel.x, 0.0, pre_vel.z)
	_wall_in_dir = hin.normalized() if hin.length() > 0.5 else -wall_normal
	forward_speed = 0.0
	side_speed = 0.0
	facing_yaw = yaw_from_dir(-wall_normal)
	_set_state("wall_slide")
	if jump_buffer > 0.0:
		_wall_kick()
		_fresh_launch = true


func _st_wall_slide(dt: float) -> void:
	air_time += dt
	if jump_buffer > 0.0:
		_wall_kick()
		return
	if inp.crouch_pressed:
		forward_speed = -p.wall_release_speed
		_set_state("fall")
		return
	vy = maxf(vy - p.gravity * dt, -p.wall_slide_speed)
	forward_speed = 0.5
	side_speed = 0.0
	if vy <= p.ledge_grab_max_rise and _try_ledge_grab():
		return
	if state_time >= p.wall_kick_window:
		forward_speed = -p.wall_release_speed
		_kick_wall_n = _wall_slide_n
		_kick_wall_d = _wall_slide_d
		_kick_wall_valid = true
		_set_state("fall")


func _wall_kick() -> void:
	jump_buffer = 0.0
	var old := facing_yaw
	# Fix r1: kick along the reflection of the approach about the wall plane, clamped to 45 degrees of the normal, so
	# diagonal kicks keep their sideways momentum (zig-zags up a wall work). The speed away from the wall stays 5.6 m/s.
	var n := _wall_slide_n
	var out := n
	if _wall_in_dir != Vector3.ZERO:
		var refl := _wall_in_dir - 2.0 * _wall_in_dir.dot(n) * n
		refl.y = 0.0
		if refl.length() > 0.01 and refl.normalized().dot(n) > 0.0:
			out = refl.normalized()
			var ang := n.signed_angle_to(out, Vector3.UP)
			ang = clampf(ang, -deg_to_rad(45.0), deg_to_rad(45.0))
			out = n.rotated(Vector3.UP, ang)
	facing_yaw = yaw_from_dir(out)
	visual_yaw_offset = wrapf(old - facing_yaw, -PI, PI)
	forward_speed = p.wall_kick_speed / maxf(out.dot(n), 0.7)
	vy = p.wall_kick_velocity
	_kick_wall_n = _wall_slide_n
	_kick_wall_d = _wall_slide_d
	_kick_wall_valid = true
	_air_kick_used = false
	_enter_air("wall_kick")


## Airborne vault (fix r1, convenience logged in MovementProfile.ledge_vault_max): meeting a wall whose top is at most
## 0.5 m above the feet used to give a wall slide, a hang and a climb (about 1 s). Now Mak is set on top and keeps
## running; the visual eases up from where he was over about 0.12 s, like the step-up.
func _try_vault(pre_vel: Vector3) -> bool:
	if p.ledge_vault_max <= 0.0 or not LEDGE_STATES.has(state) or state == "wall_slide" or vy > 3.0:
		return false
	# Fix r2 (feel major M1, ledge dead band): while falling, the band extends up to the grab band's floor
	# (ledge_grab_min_height). Tops above ledge_vault_max play a distinct, slower mantle hop-up.
	var max_h := p.ledge_vault_max
	if vy <= 0.0 and p.ledge_grab_min_height > max_h:
		max_h = p.ledge_grab_min_height
	var hin := Vector3(pre_vel.x, 0.0, pre_vel.z)
	var into := hin.dot(-wall_normal)
	if into < 0.5:
		return false
	var space := get_world_3d().direct_space_state
	var o := global_position
	var dir := -wall_normal
	var ex: Array[RID] = [get_rid()]
	# Open above the vault height in front of Mak.
	var hi := PhysicsRayQueryParameters3D.create(o + Vector3.UP * (max_h + 0.12), o + Vector3.UP * (max_h + 0.12) + dir * 0.75, 1, ex)
	if not space.intersect_ray(hi).is_empty():
		return false
	var wall_dist := (wall_point - o).dot(dir)
	var probe := o + dir * clampf(wall_dist + 0.25, 0.25, 0.8)
	var dq := PhysicsRayQueryParameters3D.create(Vector3(probe.x, o.y + max_h + 0.1, probe.z), Vector3(probe.x, o.y - 0.05, probe.z), 1, ex)
	var top := space.intersect_ray(dq)
	if top.is_empty():
		return false
	var tn: Vector3 = top["normal"]
	if tn.y < 0.8:
		return false
	if _no_ledge_grab(top.get("collider") as Node):
		return false
	var tp: Vector3 = top["position"]
	var rise := tp.y - o.y
	if rise < 0.0 or rise > max_h:
		return false
	var mantle := rise > p.ledge_vault_max
	var stand := Vector3(o.x, tp.y + 0.002, o.z) + dir * clampf(wall_dist + _capsule.radius + 0.04, 0.1, 0.8)
	if not _capsule_free(stand + Vector3.UP * 0.03, 1.25):
		return false
	visual_grab_offset += global_position - stand
	visual_grab_rate = 16.0 if mantle else 28.0
	mantle_time = 0.0 if mantle else -1.0
	global_position = stand
	reset_physics_interpolation()
	grounded = true
	vy = 0.0
	floor_collider = top.get("collider")
	_step_grace = 8
	_snap_next = true
	_kick_wall_valid = false
	forward_speed = maxf(forward_speed, minf(into, p.run_top_speed) * 0.8)
	side_speed = 0.0
	last_land_time = sim_time
	chain_kind = ""
	landed.emit(2.0)
	inp.notify("land")
	if _fb("player_land", {"impact": 2.0, "heavy": false, "surface": surface, "from": "mantle" if mantle else "vault"}):
		_sfx("land")
	if mantle:
		forward_speed = minf(forward_speed, p.run_top_speed * 0.55)
	_set_state("walk" if inp.stick_mag > 0.0 or forward_speed > 0.3 else "idle")
	return true


func _wall_top_below(h: float) -> bool:
	var space := get_world_3d().direct_space_state
	var o := global_position
	var dir := -wall_normal
	var ex: Array[RID] = [get_rid()]
	var wall_dist := maxf((wall_point - o).dot(dir), 0.0)
	var probe := o + dir * (wall_dist + 0.12)
	var q := PhysicsRayQueryParameters3D.create(Vector3(probe.x, o.y + h, probe.z), Vector3(probe.x, o.y - 0.1, probe.z), 1, ex)
	var top := space.intersect_ray(q)
	if top.is_empty():
		return false
	var ty := (top["position"] as Vector3).y
	return (top["normal"] as Vector3).y > 0.8 and ty > o.y + 0.05 and ty < o.y + h - 0.02


func _try_ledge_grab() -> bool:
	if ledge_cooldown > 0.0:
		return false
	var space := get_world_3d().direct_space_state
	var fdir := dir_from_yaw(facing_yaw)
	var o := global_position
	var hit: Dictionary = {}
	var ex: Array[RID] = [get_rid()]
	for h in [p.ledge_grab_min_height - 0.05, (p.ledge_grab_min_height + p.ledge_grab_max_height) * 0.5]:
		var hh := float(h)
		var q := PhysicsRayQueryParameters3D.create(o + Vector3.UP * hh, o + Vector3.UP * hh + fdir * 0.6, 1, ex)
		hit = space.intersect_ray(q)
		if not hit.is_empty():
			break
	if hit.is_empty():
		return false
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.3:
		return false
	var hn := Vector3(n.x, 0.0, n.z).normalized()
	if -hn.dot(fdir) < 0.5:
		return false
	var wp: Vector3 = hit["position"]
	var inner := wp - hn * 0.18
	var q2 := PhysicsRayQueryParameters3D.create(
		Vector3(inner.x, o.y + p.ledge_grab_max_height + 0.05, inner.z),
		Vector3(inner.x, o.y + p.ledge_grab_min_height - 0.05, inner.z), 1, ex)
	var top := space.intersect_ray(q2)
	if top.is_empty():
		return false
	var tn: Vector3 = top["normal"]
	if tn.y < 0.8:
		return false
	# Builders can opt a body out of ledge grabs (group "no_ledge_grab" or meta no_ledge_grab = true on the body
	# or its parent), for example bouncy tops, slippery candy and decorative trims.
	if _no_ledge_grab(top.get("collider") as Node) or _no_ledge_grab(hit.get("collider") as Node):
		return false
	var ly: float = (top["position"] as Vector3).y
	# Headroom on top (a standing capsule) and room to hang.
	var stand := Vector3(wp.x, ly, wp.z) - hn * 0.45
	if not _capsule_free(stand + Vector3.UP * 0.04, 1.25):
		return false
	var hang := Vector3(wp.x, ly - p.ledge_hang_drop, wp.z) + hn * (_capsule.radius + 0.03)
	if not _capsule_free(hang, 1.25):
		return false
	# No ground-level hangs: when the floor is right under the hang spot (a 1 m crate seen from the
	# ground), Mak would dangle with his hooves on the ground; let him land and hop up instead.
	var fq := PhysicsRayQueryParameters3D.create(hang + Vector3.UP * 0.3, hang + Vector3.DOWN * p.ledge_min_drop_clearance, 1, ex)
	if not space.intersect_ray(fq).is_empty():
		return false
	ledge_point = Vector3(wp.x, ly, wp.z)
	ledge_normal = hn
	_ledge_body = top.get("collider") as Node3D
	# Fix r1: the grab used to teleport the body (0.27 m in one tick) and read as a pop. The visual keeps its old
	# place and eases onto the hang over about 0.1 s, so the hooves appear to catch the lip.
	visual_grab_offset += global_position - hang
	global_position = hang
	reset_physics_interpolation()
	_grab_stick_held = inp.stick_mag > 0.3 and intended_dir.dot(-hn) > 0.4
	facing_yaw = yaw_from_dir(-hn)
	rotation = Vector3(0.0, facing_yaw, 0.0)
	if _ledge_body != null:
		_ledge_prev = _ledge_body.global_position
	forward_speed = 0.0
	side_speed = 0.0
	vy = 0.0
	ext_vel = Vector3.ZERO
	_kick_wall_valid = false
	_set_state("ledge_hang")
	if _fb("player_ledge_grab", {}):
		_sfx("ledge_grab")
	return true


func _no_ledge_grab(n: Node) -> bool:
	for k in 2:
		if n == null:
			return false
		if n.is_in_group("no_ledge_grab") or bool(n.get_meta("no_ledge_grab", false)):
			return true
		n = n.get_parent()
	return false


func _follow_ledge_body() -> void:
	## Moving ledges (AnimatableBody3D): carry the hang and the climb path by the body's motion.
	if _ledge_body == null or not is_instance_valid(_ledge_body):
		return
	var now := _ledge_body.global_position
	var delta_pos := now - _ledge_prev
	_ledge_prev = now
	if delta_pos.length_squared() < 1e-10:
		return
	global_position += delta_pos
	ledge_point += delta_pos
	_climb_from += delta_pos
	_climb_to += delta_pos


func _st_ledge_hang(_dt: float) -> void:
	_follow_ledge_body()
	if state_time < 0.1:
		return
	var toward := inp.stick_mag > 0.3 and intended_dir.dot(-ledge_normal) > 0.4
	var away := inp.stick_mag > 0.3 and intended_dir.dot(-ledge_normal) < -0.4
	if jump_buffer > 0.0:
		jump_buffer = 0.0
		_start_ledge_climb(true)
		return
	# Fix r1: when the stick was already held toward the wall at the grab, climb after 0.17 s instead of 0.33 s.
	# Fix r2 (feel minor M6): a held jump or a stick held toward the wall since the grab pops straight up (fast climb
	# after 0.1 s, about 0.36 s from grab to control); a neutral stick keeps the slow hang and climb.
	if inp.jump_held or (_grab_stick_held and toward):
		_start_ledge_climb(true)
		return
	var delay := 0.17 if _grab_stick_held else p.ledge_hang_delay
	if toward and state_time > delay:
		_start_ledge_climb(false)
		return
	if not toward:
		_grab_stick_held = false
	if inp.crouch_pressed or (away and state_time > p.ledge_hang_delay):
		ledge_cooldown = p.ledge_regrab_cooldown
		global_position += ledge_normal * 0.06
		forward_speed = 0.0
		vy = 0.0
		_set_state("fall")


func _start_ledge_climb(fast: bool) -> void:
	_climb_from = global_position
	_climb_to = ledge_point - ledge_normal * 0.45 + Vector3.UP * 0.001
	_climb_time = p.ledge_climb_fast_time if fast else p.ledge_climb_time
	_set_state("ledge_climb")
	_fb("player_ledge_climb", {"fast": fast})


func _st_ledge_climb(_dt: float) -> void:
	_follow_ledge_body()
	var t := clampf(state_time / _climb_time, 0.0, 1.0)
	var up_part := clampf(t / 0.62, 0.0, 1.0)
	var fwd_part := clampf((t - 0.45) / 0.55, 0.0, 1.0)
	up_part = 1.0 - pow(1.0 - up_part, 2.0)
	fwd_part = fwd_part * fwd_part * (3.0 - 2.0 * fwd_part)
	var pos := _climb_from
	pos.y = lerpf(_climb_from.y, _climb_to.y, up_part)
	pos.x = lerpf(_climb_from.x, _climb_to.x, fwd_part)
	pos.z = lerpf(_climb_from.z, _climb_to.z, fwd_part)
	global_position = pos
	if t >= 1.0:
		global_position = _climb_to
		grounded = true
		_snap_next = true
		_step_grace = 8
		vy = 0.0
		forward_speed = 0.0
		_ledge_body = null
		_set_state("walk" if inp.stick_mag > 0.0 else "idle")


func _release_holds() -> void:
	if state == "ledge_hang" or state == "ledge_climb":
		ledge_cooldown = p.ledge_regrab_cooldown
		_ledge_body = null
	if state == "pole_climb":
		pole_cooldown = p.pole_regrab_cooldown
		pole = null


# ------------------------------------------------------------------ poles and vines

func _grab_pole(area: Node3D) -> void:
	var axis := Vector3.UP
	if area.has_method("get_climb_axis"):
		var a: Variant = area.call("get_climb_axis")
		if a is Vector3 and (a as Vector3).length() > 0.01:
			axis = (a as Vector3).normalized()
	var bottom := area.global_position
	var top := area.global_position + axis * 4.0
	if area.has_method("get_climb_bottom") and area.has_method("get_climb_top"):
		bottom = area.call("get_climb_bottom")
		top = area.call("get_climb_top")
	else:
		var hgt := 4.0
		var center := area.global_position
		for c in area.get_children():
			if c is CollisionShape3D:
				var sh := (c as CollisionShape3D).shape
				center = (c as CollisionShape3D).global_position
				if sh is CylinderShape3D:
					hgt = (sh as CylinderShape3D).height
				elif sh is CapsuleShape3D:
					hgt = (sh as CapsuleShape3D).height
				elif sh is BoxShape3D:
					hgt = (sh as BoxShape3D).size.y
				break
		bottom = center - axis * hgt * 0.5
		top = center + axis * hgt * 0.5
	pole = area
	_pole_axis = axis
	_pole_bottom = bottom
	_pole_length = maxf((top - bottom).dot(axis), 0.5)
	var r: Variant = area.get("pole_radius")
	pole_radius = float(r) if r != null else float(area.get_meta("pole_radius", 0.15))
	var ref := Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	_pole_u = axis.cross(ref).normalized()
	_pole_w = axis.cross(_pole_u).normalized()
	var rel := global_position - bottom
	pole_t = clampf(rel.dot(axis), 0.0, maxf(_pole_length - 1.0, 0.0))
	var radial := rel - axis * rel.dot(axis)
	if radial.length() < 0.01:
		radial = -dir_from_yaw(facing_yaw)
	pole_angle = atan2(radial.dot(_pole_w), radial.dot(_pole_u))
	forward_speed = 0.0
	side_speed = 0.0
	vy = 0.0
	ext_vel = Vector3.ZERO
	use_slide_vel = false
	pole_climb_travel = 0.0
	_set_state("pole_climb")
	_place_on_pole()
	if _fb("player_climb_grab", {}):
		_sfx("ledge_grab")


func _place_on_pole() -> void:
	var radial := (_pole_u * cos(pole_angle) + _pole_w * sin(pole_angle)).normalized()
	global_position = _pole_bottom + _pole_axis * pole_t + radial * (pole_radius + 0.3)
	var toward := -radial
	toward.y = 0.0
	if toward.length() > 0.01:
		facing_yaw = yaw_from_dir(toward)


func _st_pole_climb(dt: float) -> void:
	if pole == null or not is_instance_valid(pole):
		_set_state("fall")
		return
	if jump_buffer > 0.0:
		jump_buffer = 0.0
		var radial := (_pole_u * cos(pole_angle) + _pole_w * sin(pole_angle))
		radial.y = 0.0
		facing_yaw = yaw_from_dir(radial if radial.length() > 0.01 else -dir_from_yaw(facing_yaw))
		forward_speed = p.pole_jump_speed
		pole_cooldown = p.pole_regrab_cooldown
		pole = null
		vy = p.pole_jump_velocity
		last_platform_vel = Vector3.ZERO
		_enter_air("jump")
		jumped.emit("pole_jump")
		return
	if inp.crouch_pressed:
		pole_cooldown = p.pole_regrab_cooldown
		pole = null
		forward_speed = -0.47
		_set_state("fall")
		return
	var up_in := inp.stick.y
	var before := pole_t
	if up_in > 0.2:
		pole_t += p.climb_up_speed * up_in * dt
	elif up_in < -0.2:
		pole_t += p.climb_down_speed * up_in * dt
	pole_t = clampf(pole_t, 0.0, maxf(_pole_length - 1.0, 0.0))
	pole_climb_travel += absf(pole_t - before)
	if absf(inp.stick.x) > 0.2:
		pole_angle -= inp.stick.x * deg_to_rad(p.climb_orbit_rate_deg) * dt
		pole_climb_travel += absf(inp.stick.x) * dt * 0.5
	_place_on_pole()
	if pole_t <= 0.0 and up_in < -0.2 and state_time > 0.3:
		pole_cooldown = p.pole_regrab_cooldown
		pole = null
		_set_state("fall")


# ------------------------------------------------------------------ areas, attacks and hazards

func _scan_areas(delta: float) -> void:
	_wind_target = Vector3.ZERO
	var climb: Node3D = null
	var liquids := {}
	for a in sensor.get_overlapping_areas():
		var liquid := _liquid_kind(a)
		if liquid != "":
			liquids[a.get_instance_id()] = true
			if not _in_liquid.has(a.get_instance_id()):
				splash(liquid)
		if a.is_in_group("wind_zone") and a.has_method("get_wind"):
			var w: Variant = a.call("get_wind", global_position)
			if w is Vector3:
				_wind_target += w
		if a.is_in_group("hazard") and invulnerable <= 0.0 and state != "dead" and state != "fallout":
			var src := Vector3(a.global_position.x, global_position.y - 1.0, a.global_position.z)
			take_damage(int(a.get_meta("damage", 1)), src, float(a.get_meta("knockback_up", -1.0)))
		if a.is_in_group("climbable") and climb == null:
			climb = a
	_in_liquid = liquids
	wind_vel = wind_vel.lerp(_wind_target, 1.0 - exp(-p.wind_smoothing * delta))
	# Owner fix 2026-10-19 (endless walking jitter after the W1-6 flue): the exponential ease never reaches zero. After any
	# updraft (stove draught, gust, hub bellows, W2/W3 wind) wind_vel.y decayed to the smallest positive float and stuck
	# there, so velocity.y was above zero on the ground, move_and_slide skipped its floor snap, and Mak alternated walk and
	# fall every frame (a landing squash each time) until the next respawn. Residue under 1 mm/s now snaps to the target.
	if wind_vel.distance_squared_to(_wind_target) < 1e-6:
		wind_vel = _wind_target
	# The eased tail of an updraft Mak has already left must not lift him off the floor either (it gave about 0.8 s of the
	# same walk/fall flicker after every landing from the spout or the flue).
	if grounded and _wind_target.y <= 0.0 and wind_vel.y > 0.0:
		wind_vel.y = 0.0
	if climb != null and pole_cooldown <= 0.0 and state != "pole_climb" and is_air_state(state) \
			and state != "hurt_air" and state != "dead" and state != "fallout" and state != "ham_slam":
		_grab_pole(climb)


func _process_attacks(_delta: float) -> void:
	if is_air_state(state) and vy < -1.0 and state != "hurt_air" and state != "dead" and _stomp_cooldown <= 0.0:
		for a in stomp_area.get_overlapping_areas():
			if a.global_position.y > global_position.y + 0.4:
				continue
			if _try_stomp(a):
				break
	if not attack_active:
		return
	for a in attack_area.get_overlapping_areas():
		var e := _hittable_of(a)
		if e == null:
			continue
		var id := e.get_instance_id()
		if _attack_hits.has(id):
			continue
		_attack_hits[id] = true
		var landed_hit: Variant = e.call("hit_by_player", attack_kind, global_position)
		if landed_hit is bool and bool(landed_hit):
			# Enemies emit enemy_hurt / enemy_defeat themselves; player_hit is for dummies, switches and props.
			var is_enemy := (e as Node).is_in_group("enemy") or (e as Node).is_in_group("boss")
			if not is_enemy and _fb("player_hit", {"kind": attack_kind}, _strike_contact(e)):
				_camera_shake(0.12, 0.12)


## Fix r1: hit feedback spawns at the striking hoof (moved a little toward the target), not at the target's base.
func _strike_contact(e: Object) -> Vector3:
	var tp := (e as Node3D).global_position if e is Node3D else global_position
	if animator != null and animator.has_method("strike_point"):
		var hp: Vector3 = animator.call("strike_point", attack_kind)
		if hp != Vector3.INF:
			var to := Vector3(tp.x, hp.y, tp.z)
			return hp.lerp(to, 0.3)
	return tp + Vector3.UP * 0.5


func _try_stomp(target: Object) -> bool:
	var e := _hittable_of(target)
	if e == null:
		return false
	var kind := "slam" if state == "ham_slam" else "stomp"
	var res: Variant = e.call("hit_by_player", kind, global_position)
	var ok := res is bool and bool(res)
	if ok:
		_stomp_cooldown = 0.12
		attacked.emit(kind)
		if _fb("player_stomp", {"kind": kind}):
			_sfx("land")
		if kind == "slam":
			ground_pounded.emit(global_position)
		bounce(p.stomp_bounce_velocity)
	return ok


func _hittable_of(o: Object) -> Node:
	var n := o as Node
	var depth := 0
	while n != null and depth < 4:
		if n == self:
			return null
		if n.has_method("hit_by_player"):
			return n
		n = n.get_parent()
		depth += 1
	return null


func _set_attack_shape(kind: String) -> void:
	var pos := Vector3(0.0, 0.65, -0.55)
	var r := 0.55
	match kind:
		"kick":
			pos = Vector3(0.0, 0.5, -0.2)   # spin kick: hits all around
			r = 1.0
		"jump_kick":
			pos = Vector3(0.0, 0.55, -0.6)
			r = 0.7
		"dive", "slide":
			pos = Vector3(0.0, 0.35, -0.55)
			r = 0.7
		"slam":
			pos = Vector3(0.0, 0.3, 0.0)
			r = p.slam_radius
	attack_shape.position = pos
	_attack_sphere.radius = r


func _find_sniff_target() -> Node3D:
	var best: Node3D = null
	var best_d := p.sniff_radius
	for n in get_tree().get_nodes_in_group("sniff_target"):
		if n is Node3D and (n as Node3D).is_inside_tree() and (n as Node3D).is_visible_in_tree():
			if n.has_method("is_sniff_active") and not bool(n.call("is_sniff_active")):
				continue
			var d := (_sniff_pos(n as Node3D) - global_position).length()
			if d < best_d:
				best_d = d
				best = n
	return best


func _set_sniff_target(t: Node3D) -> void:
	## Scent trail: res://scenes/fx/ScentTrail.tscn (VFX workstream; child of Mak, set_target(world position),
	## clear_target()) when it exists, otherwise MakScentTrail (own fallback motes).
	if t != sniff_target:
		sniff_target = t
		sniff_target_changed.emit(t)
	if t == null:
		if _scent != null and is_instance_valid(_scent):
			if _scent.has_method("clear_target"):
				_scent.call("clear_target")
			elif "target" in _scent:
				_scent.set("target", null)
		return
	if _scent == null or not is_instance_valid(_scent):
		var path := "res://scenes/fx/ScentTrail.tscn"
		if ResourceLoader.exists(path):
			var ps := load(path) as PackedScene
			if ps != null:
				_scent = ps.instantiate() as Node3D
		if _scent == null:
			_scent = MakScentTrail.new()
		add_child(_scent)
	if _scent.has_method("set_target") and _scent.has_method("clear_target"):
		_scent.call("set_target", _sniff_pos(t))
	else:
		if "source" in _scent:
			_scent.set("source", self)
		if "target" in _scent:
			_scent.set("target", t)


func _sniff_pos(n: Node3D) -> Vector3:
	if n.has_method("get_sniff_position"):
		var v: Variant = n.call("get_sniff_position")
		if v is Vector3:
			return v
	return n.global_position


## The scent reaches its target once Mak sniffs within reach of it: tell the target (once per target).
func _update_sniff_reach() -> void:
	if sniff_target == null or not is_instance_valid(sniff_target):
		return
	if sniff_target.has_method("is_sniff_active") and not bool(sniff_target.call("is_sniff_active")):
		_set_sniff_target(null)
		return
	var reach := SNIFF_REACH
	var rr: Variant = sniff_target.get("reveal_radius")
	if rr is float or rr is int:
		reach = maxf(reach, float(rr))
	if (_sniff_pos(sniff_target) - global_position).length() <= reach:
		var sid := sniff_target.get_instance_id()
		if _sniffed_ids.has(sid):
			return
		_sniffed_ids[sid] = true
		if sniff_target.has_method("on_sniffed"):
			sniff_target.call("on_sniffed", self)
		_fb("player_sniff_found", {"target": sniff_target})


func _check_kill_plane() -> void:
	if state == "fallout" or state == "dead":
		return
	if global_position.y < _kill_y:
		_release_holds()
		_set_state("fallout")
		_fb("player_fall_out", {})
		_fallback_timer = p.fallback_respawn_delay
		var g := _autoload("Game")
		if g != null and g.has_method("player_fell_out"):
			g.call("player_fell_out")


func _die() -> void:
	_set_state("dead")
	_fb("player_death", {})
	_fallback_timer = p.fallback_respawn_delay + 0.8
	died.emit()


func _fallback_respawn() -> void:
	if state != "fallout" and state != "dead":
		return
	var g := _autoload("Game")
	if state == "dead" and g != null and g.has_method("heal"):
		g.call("heal", 6)
	respawn(spawn_xform)


func _on_truffle_collected(_id: Variant = null) -> void:
	celebrate()


# ------------------------------------------------------------------ helpers

func _can_stand() -> bool:
	if not crouched_shape:
		return true
	return _capsule_free(global_position + Vector3.UP * 0.02, 1.25)


func _capsule_free(feet: Vector3, height: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = _capsule.radius - 0.02
	shape.height = height - 0.04
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (height * 0.5))
	q.collision_mask = 1
	var ex: Array[RID] = [get_rid()]
	q.exclude = ex
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _set_crouch_shape(on: bool) -> void:
	if on == crouched_shape:
		return
	crouched_shape = on
	var h := p.crouch_capsule_height if on else 1.25
	_capsule.height = h
	body_shape.position = Vector3(0.0, h * 0.5, 0.0)


func _try_step_up(delta: float) -> bool:
	## Stairs and small ledges: when the next move hits a low riser and there is a walkable top
	## within step_height, lift the body onto it; move_and_slide then carries it forward.
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var dist := h.length() * delta
	if dist < 0.0005:
		return false
	var motion := h * delta
	var dir := h.normalized()
	var xf := global_transform
	var col := KinematicCollision3D.new()
	if not test_move(xf, motion, col):
		return false
	var n := col.get_normal()
	if n.y > 0.7 or n.y < -0.3:
		return false
	var c := col.get_collider()
	if c is Node and ((c as Node).is_in_group("enemy") or (c as Node).is_in_group("no_step")):
		return false
	var up := Vector3(0.0, p.step_height, 0.0)
	if test_move(xf, up):
		return false
	var xf_up := xf.translated(up)
	if test_move(xf_up, motion):
		return false
	var far := dir * maxf(dist, _capsule.radius + 0.05)
	if test_move(xf_up, far):
		return false
	var xf_far := xf_up.translated(far)
	var col2 := KinematicCollision3D.new()
	if not test_move(xf_far, -up, col2):
		return false
	if col2.get_normal().y < 0.7:
		return false
	var rise := (xf_far.origin + col2.get_travel()).y - xf.origin.y
	if rise < 0.02 or rise > p.step_height:
		return false
	global_position.y += rise + 0.005
	visual_step_offset -= rise
	return true


func _floor_is_steep_below() -> bool:
	## Confirms a steep floor under the capsule centre (an edge contact alone is not a slope).
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 0.4, 1)
	var ex: Array[RID] = [get_rid()]
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var n: Vector3 = hit["normal"]
	return rad_to_deg(acos(clampf(n.y, -1.0, 1.0))) > p.steep_slope_angle


func _floor_angle_deg() -> float:
	return rad_to_deg(acos(clampf(floor_normal.y, -1.0, 1.0)))


func _update_surface() -> void:
	surface = "grass"
	if floor_collider is Node:
		var n := floor_collider as Node
		if n.has_meta("surface"):
			surface = str(n.get_meta("surface"))
		elif n.is_in_group("wood"):
			surface = "wood"
		elif n.is_in_group("stone"):
			surface = "stone"


func _set_state(s: String) -> void:
	if s == state:
		return
	if not is_air_state(s):
		_fresh_launch = false
	prev_state = state
	state = s
	state_time = 0.0
	if prev_state == "hurt_land" and _hurt_total > 0.0:
		# REA round 2: 30 more reference frames of invulnerability once the hurt state ends.
		_hurt_total = 0.0
		invulnerable = p.invulnerable_time
		hurt_blink = p.invulnerable_time
	if (prev_state == "belly_slide" or prev_state == "slope_slide") and s != "belly_slide" and s != "slope_slide":
		_fb("player_slide_end", {})
	inp.notify("state:" + s)
	if crouched_shape and s != "crouch" and s != "crouch_slide":
		_set_crouch_shape(false)
	if s != "sniff" and sniff_target != null:
		_set_sniff_target(null)
	if (s == "walk" or s == "idle" or s == "crouch") and use_slide_vel:
		_slide_to_forward()
	state_changed.emit(prev_state, s)


func _approach_angle(from: float, to: float, step: float) -> float:
	var diff := angle_difference(from, to)
	if absf(diff) <= step:
		return to
	return from + signf(diff) * step


static func dir_from_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func yaw_from_dir(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _ui_blocks_input() -> bool:
	var ui := _autoload("UI")
	return ui != null and ui.has_method("is_input_blocked") and bool(ui.call("is_input_blocked"))


func _autoload(n: String) -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(n)


func _sfx(key: String) -> void:
	var a := _autoload("Audio")
	if a != null and a.has_method("play_sfx"):
		a.call("play_sfx", key, global_position)


func _spawn_fx(key: String, at: Vector3, fx_scale: float = 1.0) -> void:
	var ps := _fx.get(key) as PackedScene
	if ps == null:
		return
	var n := ps.instantiate()
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_parent()
	parent.add_child(n)
	if n is Node3D:
		(n as Node3D).global_position = at
		if not is_equal_approx(fx_scale, 1.0) and n.get("fx_scale") != null:
			n.set("fx_scale", fx_scale)
	if n.has_method("play"):
		n.call("play")


## Feedback event (Docs/JUICE.md): sent to Juice.event(name, position, params) with node = Mak and direction = facing.
## Returns true when the player must still play its own direct SFX/VFX: the event is not in the Juice catalogue
## (Juice.has_event false) or Juice is the old stub. Catalogued events are fully owned by Juice, so nothing doubles.
func _fb(event_name: String, params: Dictionary = {}, at: Vector3 = Vector3.INF) -> bool:
	if _fb_log:
		print("[MakPlayer] f%d feedback %s" % [physics_frame, event_name])
	var j := _autoload("Juice")
	if j == null or not j.has_method("event"):
		return true
	if j.has_method("has_event") and not bool(j.call("has_event", event_name)):
		return true
	var pos := global_position if at == Vector3.INF else at
	if not params.has("node"):
		params["node"] = self
	if not params.has("direction"):
		params["direction"] = dir_from_yaw(facing_yaw)
	j.call("event", event_name, pos, params)
	# Juice plays the catalogued VFX, sound, shake and hitstop; the stub (no has_event) leaves them to us.
	return not j.has_method("has_event")


## Effects that ride on Mak (JumpTrail) are parented to the Visual node.
func _attach_fx(key: String) -> void:
	var ps := _fx.get(key) as PackedScene
	if ps == null or visual == null:
		return
	var n := ps.instantiate()
	visual.add_child(n)
	if n is Node3D:
		(n as Node3D).position = Vector3(0.0, 0.55, 0.0)
	if n.has_method("play"):
		n.call("play")


func _camera_shake(strength: float, duration: float) -> void:
	if camera_rig != null and is_instance_valid(camera_rig) and camera_rig.has_method("add_shake"):
		camera_rig.call("add_shake", strength, duration)


func _kick_anim(kind: String) -> void:
	if animator != null and animator.has_method("kick"):
		animator.call("kick", kind)


# ------------------------------------------------------------------ trace (--trace=<path>)

func _open_trace() -> void:
	var dev := _autoload("Dev")
	if dev == null or not dev.has_method("arg"):
		return
	var path := str(dev.call("arg", "trace", ""))
	if path == "":
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_trace = FileAccess.open(path, FileAccess.WRITE)
	if _trace == null:
		push_error("[MakPlayer] cannot open trace " + path)
		return
	var prof := {}
	for prop in p.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			prof[prop["name"]] = p.get(prop["name"])
	var meta := {
		"meta": true, "physics_hz": Engine.physics_ticks_per_second, "max_fps": Engine.max_fps,
		"replay": str(dev.call("arg", "replay", "")), "engine": Engine.get_version_info().get("string", ""),
		"profile": prof, "capsule": {"height": 1.25, "radius": 0.35},
	}
	_trace.store_line(JSON.stringify(meta))


func _write_trace() -> void:
	if _trace == null:
		return
	var gp := global_position
	var row := {
		"f": physics_frame, "t": snappedf(physics_frame * _dt_phys(), 0.0001),
		"p": [snappedf(gp.x, 0.0001), snappedf(gp.y, 0.0001), snappedf(gp.z, 0.0001)],
		"v": [snappedf(velocity.x, 0.001), snappedf(velocity.y, 0.001), snappedf(velocity.z, 0.001)],
		"s": state, "g": grounded, "fs": snappedf(forward_speed, 0.001),
		"yaw": snappedf(rad_to_deg(facing_yaw), 0.01), "inv": snappedf(invulnerable, 0.001),
	}
	if inp.mark != "":
		row["mark"] = inp.mark
	_trace.store_line(JSON.stringify(row))
	if physics_frame % 60 == 0:
		_trace.flush()


func _finish_replay() -> void:
	if _ending:
		return
	_ending = true
	if _trace != null:
		_trace.flush()
		_trace.close()
		_trace = null
	var dev := _autoload("Dev")
	# Movie Maker and capture runs control their own end; plain replays quit here.
	if dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "replay-hold")):
		return
	get_tree().quit()


func _exit_tree() -> void:
	if _trace != null:
		_trace.flush()
		_trace.close()
		_trace = null

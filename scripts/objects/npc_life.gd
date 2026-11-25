class_name NpcLife
extends Node
## Procedural idle life for generated characters (Tripo P2 GLBs), rigged or not.
## Rigged (Skeleton3D with the hero joint names): breathing on spine/chest, head turns toward Mak with a lead
## over the body, blinks (a quick squint of the head bone scale), ear flicks, tail wag, arms relaxed from the
## A-pose, talking gestures (head nods, forearm beats, jaw) and a greeting wave.
## Unrigged: whole-body breathing squash from the feet, a lean toward Mak, a talking bob-and-rock and a greeting hop.
## Add with NpcLife.attach(visual_root) (the node that holds the model; it is scaled and tilted, never moved
## sideways). NPCTalker adds one automatically; set `talking` from outside (Talker does) to gesture.

@export var breath_period: float = 3.4
@export var breath_amount: float = 1.0
@export var look_at_player: bool = true
@export var look_radius: float = 7.0
@export var max_head_yaw: float = 55.0
@export var max_head_pitch: float = 20.0
## Degrees to lower each arm from the file's rest pose (A-pose bipeds); per-model overrides in PROFILES.
@export var arm_lower: float = 22.0

## Per-model tweaks keyed by the GLB file's basename.
## Pose keys (rigged): arm_fwd (upper arms swing forward, deg), fore_down (forearms bend down in the frontal plane),
## fore_fwd (forearms swing forward), head_tilt (a sad/pleading roll). greet: "wave" (default), "bow" (unrigged elders)
## or "hop" (unrigged small characters).
## Pip's rest pose is a V cheer and the rig only allows ~60 deg of lowering, so he wrings his hands in front instead of
## idling with horizontal arms (the "house gone" mood); the authored clips exist only in the source .blend (no clips
## are exported in any character GLB).
const PROFILES := {
	"pip_v2": {"arm_lower": 60.0, "arm_fwd": 28.0, "fore_down": 30.0, "fore_fwd": 62.0, "head_tilt": 7.0},
	"pip_v3": {"arm_lower": 60.0, "arm_fwd": 28.0, "fore_down": 30.0, "fore_fwd": 62.0, "head_tilt": 7.0},
	"bramwell": {"greet": "bow"},
	"bertram": {"arm_lower": 62.0},
	"hazel": {"arm_lower": 62.0},
	"jack": {"arm_lower": 58.0},
	# Snap v1 rests with the arms already ~25 deg from vertical against the belly (55 pushed them through it); v2/v3 raise
	# the rest arms 50 deg so lowering 55 seats them on the belly with the epaulettes on (Docs/ASSETS_TOPUP.md, round 3).
	"sergeant_snap": {"arm_lower": 12.0},
	"sergeant_snap_v2": {"arm_lower": 55.0},
	"sergeant_snap_v3": {"arm_lower": 55.0},
	"foreman": {"arm_lower": 40.0},
	"foreman_underwear": {"arm_lower": 40.0},
	"sleeping_giant": {"look_at_player": false, "breath_period": 4.2, "snore": true},
	"wolf_scarecrow": {"look_at_player": false},
	"real_sheep": {"graze": true},
	"daisy_cow": {"graze": true, "jaw": 16.0},
	"golden_goose": {"bird": true},
	"crow_bandit": {"bird": true, "look_at_player": false},
	# Future W3 cast (asset request): profiles ready for when the models land.
	"mother_treacle": {"arm_lower": 50.0, "greet": "wave"},
	"hansel": {"arm_lower": 55.0},
	"gretel": {"arm_lower": 55.0},
}

var talking := false
var visual: Node3D
var skel: Skeleton3D
var _rest: Dictionary = {}
var _bones: Dictionary = {}
var _t := 0.0
var _seed := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _blink := 0.0
var _next_blink := 2.0
var _ear_flick := 0.0
var _ear_side := 0
var _next_ear := 3.0
var _greet := 0.0
var _talk_t := 0.0
var _base_scale := Vector3.ONE
var _base_rot := Vector3.ZERO
var _base_pos := Vector3.ZERO
var _profile: Dictionary = {}
## Caged behaviour (set by builders through set_caged): grips the bars, rattles them when Mak is within 4 m and tilts
## the head pleadingly. release() ends it with a wave and a happy hop.
var caged := false
var _rattle := 0.0
var _greet_arm := "r"
var _greet_kind := "wave"
var _happy := 0.0

## Auto mode (NpcLifeAuto, fix stage r2): the character came from a world builder, not from an object. NpcLife first
## watches it for `observe_time` seconds without writing anything; if any bone moves on its own in that time another
## script animates it and NpcLife removes itself. While active it keeps checking one bone: when someone else starts
## posing the skeleton (a cutscene, a world poser), NpcLife steps aside and frees itself.
var auto := false
var observe_time := 0.6
var _observing := 0.0
var _obs_poses: Array = []
var _guard_bone := -1
var _guard_q := Quaternion.IDENTITY
## What NpcLife last wrote to the visual root. Any difference at the next frame is motion from another script
## (a world moving or turning the model), which is added to the base instead of being overwritten.
var _wrote := false
var _w_pos := Vector3.ZERO
var _w_rot := Vector3.ZERO
var _w_scale := Vector3.ONE
## LEGS pass (2026-10-19, owner: "legs like steel"): a walk for characters that world code moves around (the W1 sheep
## graze on tweens and used to slide with frozen legs). The stride phase follows the ground distance the model covers;
## quadruped rigs (leg_fl/fr/bl/br) walk a four-beat sequence that blends into a diagonal trot with speed, with the
## hooves lifted on the swing (a short leg-length squash: the legs are single bones); biped rigs (thigh_l/r or
## leg_l/r, shin knees) alternate with a knee fold; leg-less rigs waddle. The body bobs twice per stride and sways,
## and everything fades back to the idle pose on a stop. Leg bones are only touched while the model walks.
var _g_bones: Dictionary = {}
var _g_rest: Dictionary = {}
var _g_prev := Vector3.INF
var _g_yaw := 0.0
var _g_phase := 0.0
var _g_w := 0.0
var _g_amp := 0.0
var _g_speed := 0.0
var _g_hip := 0.35
var _g_dirty := false
var _gait_whole_bob := 0.0


## Critique objects r1 re-run: characters placed by world code stood frozen in their rest pose because no world
## builder attached NpcLife. One call at the end of a build gives every generated character in a subtree its life:
##   NpcLife.attach_all(self)                  # every character GLB instance under the world, once
##   NpcLife.attach_all(self, {"jack": {"caged": true}})   # per-model options: caged, talking
## A character is any node instanced from res://assets/characters/ (or listed in `extra_dirs`) without an NpcLife.
## Enemies and the player are skipped (they own their animation). Returns the NpcLife nodes it added.
static func attach_all(root: Node, per_model: Dictionary = {}, extra_dirs: Array = [], auto_mode: bool = false) -> Array[NpcLife]:
	var out: Array[NpcLife] = []
	if root == null:
		return out
	var dirs: Array = ["res://assets/characters/"] + extra_dirs
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var sf := n.scene_file_path
		var is_char := false
		if sf != "" and n != root and n is Node3D:
			for d in dirs:
				if sf.begins_with(str(d)):
					is_char = true
					break
		if is_char:
			if n.is_in_group("player") or _has_driver(n) or not wants_life(n):
				continue
			var has := false
			for c in n.get_children():
				if c is NpcLife:
					has = true
			if not has:
				var l := NpcLife.new()
				l.name = "NpcLife"
				l.auto = auto_mode
				n.add_child(l)
				var key := sf.get_file().get_basename()
				var opt: Dictionary = per_model.get(key, {})
				# A model inside a builder's cage node (an ancestor named "...Cage...") grips the bars and pleads.
				var caged_by_name := false
				var anc := n.get_parent()
				for _h in 2:
					if anc == null:
						break
					if String(anc.name).to_lower().contains("cage"):
						caged_by_name = true
					anc = anc.get_parent()
				if bool(opt.get("caged", caged_by_name if auto_mode else false)):
					l.set_caged(true)
				out.append(l)
			continue  # never descend into a character
		for c in n.get_children():
			stack.append(c)
	if not out.is_empty():
		var names: Array[String] = []
		for l in out:
			names.append(str(l.get_parent().get_parent().name) + "/" + str(l.get_parent().name))
		print("[NpcLife] attach_all(%s%s): %d characters: %s" % [root.name, ", auto" if auto_mode else "", out.size(), ", ".join(names)])
	return out


## Characters NpcLife never animates on its own: Mak's own models (the player and the hat stand), anything a builder
## opted out (group `no_npc_life`, or meta `npc_life` = false on the model or an ancestor), and models that live
## under an enemy, boss, player, UI or effects script.
const SKIP_DIRS := ["res://assets/characters/mak/", "res://assets/characters/_topup_preview/"]
const DRIVER_SCRIPTS := ["res://scripts/enemies/", "res://scripts/boss/", "res://scripts/player/", "res://scripts/ui/", "res://scripts/fx/"]


static func wants_life(n: Node) -> bool:
	var sf := n.scene_file_path
	for d in SKIP_DIRS:
		if sf.begins_with(str(d)):
			return false
	var p := n
	while p != null:
		if p.is_in_group("no_npc_life") or (p.has_meta("npc_life") and not bool(p.get_meta("npc_life"))) or p.has_meta("npc_life_skip"):
			return false
		var sc: Variant = p.get_script()
		if sc is Script:
			var rp := (sc as Script).resource_path
			for d in DRIVER_SCRIPTS:
				if rp.begins_with(str(d)):
					return false
		p = p.get_parent()
	return true


## True when an ancestor already drives this model (an NPCTalker, an enemy or the player).
static func _has_driver(n: Node) -> bool:
	var p := n.get_parent()
	var hops := 0
	while p != null and hops < 4:
		if p.is_in_group("player") or p.is_in_group("enemy") or p.is_in_group("talker") or p.has_method("hit_by_player"):
			return true
		p = p.get_parent()
		hops += 1
	return false


## Adds an NpcLife under `visual_root` and returns it (or the existing one).
static func attach(visual_root: Node3D) -> NpcLife:
	if visual_root == null:
		return null
	for c in visual_root.get_children():
		if c is NpcLife:
			return c
	var l := NpcLife.new()
	l.name = "NpcLife"
	visual_root.add_child(l)
	return l


func _ready() -> void:
	visual = get_parent() as Node3D
	_seed = randf() * 100.0
	_t = _seed
	_next_blink = randf_range(1.0, 3.0)
	_next_ear = randf_range(2.0, 5.0)
	call_deferred("_bind")


func _bind() -> void:
	if visual == null:
		return
	_base_scale = visual.scale
	_base_rot = visual.rotation
	_base_pos = visual.position
	var sk := visual.find_children("*", "Skeleton3D", true, false)
	if sk.size() > 0:
		skel = sk[0] as Skeleton3D
	var key := _model_key()
	_profile = profile_for(key)
	if _profile.has("arm_lower"):
		arm_lower = float(_profile["arm_lower"])
	if _profile.has("look_at_player"):
		look_at_player = bool(_profile["look_at_player"])
	if _profile.has("breath_period"):
		breath_period = float(_profile["breath_period"])
	_greet_kind = str(_profile.get("greet", "wave"))
	if auto:
		_observing = observe_time
		_obs_poses.clear()
		if skel != null:
			for i in skel.get_bone_count():
				_obs_poses.append(skel.get_bone_pose_rotation(i))
	if skel == null:
		return
	for b in ["hips", "spine", "chest", "body", "neck", "head", "jaw", "ear_l", "ear_r", "tail", "tail_2", "arm_l", "arm_r",
			"forearm_l", "forearm_r", "cap_tip", "can_l", "can_r", "eyelid_l", "eyelid_r"]:
		var i := skel.find_bone(b)
		if i >= 0:
			_bones[b] = i
			_rest[b] = skel.get_bone_pose_rotation(i)
	_g_bones.clear()
	for b in ["leg_fl", "leg_fr", "leg_bl", "leg_br", "thigh_l", "thigh_r", "leg_l", "leg_r", "shin_l", "shin_r"]:
		var gi := skel.find_bone(b)
		if gi >= 0:
			_g_bones[b] = gi
			_g_rest[b] = skel.get_bone_pose_rotation(gi)
	# Hip height above the soles from the first leg bone's rest head (feet at the model origin).
	for b in ["leg_bl", "leg_fl", "thigh_l", "leg_l"]:
		if _g_bones.has(b):
			var hip: Vector3 = skel.global_transform * skel.get_bone_global_rest(int(_g_bones[b])).origin
			var hh := hip.y - visual.global_position.y
			if hh > 0.06 and hh < 3.0:
				_g_hip = hh
			break


## The profile for a model file basename. Re-delivered files (`jack_v2`, `daisy_cow_v2`, `sleeping_giant_v2`, ...) share
## their original's profile unless they have their own entry: without this the AO-baked v2 cast lost their profiles
## (the sleeping giant turned to watch Mak, the cow stopped grazing, the scarecrow tracked him).
static func profile_for(key: String) -> Dictionary:
	if PROFILES.has(key):
		return PROFILES[key]
	var rx := RegEx.create_from_string("_v[0-9]+$")
	var base := rx.sub(key, "")
	if base != key and PROFILES.has(base):
		return PROFILES[base]
	return {}


func _model_key() -> String:
	for n in visual.find_children("*", "Node3D", true, false):
		var sf: String = (n as Node).scene_file_path
		if sf != "":
			return sf.get_file().get_basename()
	if visual.scene_file_path != "":
		return visual.scene_file_path.get_file().get_basename()
	for n in visual.find_children("*", "MeshInstance3D", true, false):
		return str(n.name)
	return ""


## A short wave (rigged; with the arm farther from Mak, skipped when he is closer than 0.9 m so the hand never
## passes through him), a bow (elders) or a hop (unrigged small characters) when Mak arrives.
func greet() -> void:
	var p := ObjSvc.get_player()
	if p != null and visual != null and is_inside_tree():
		var d := ObjSvc.body_pos(p) - visual.global_position
		d.y = 0.0
		if d.length() < 0.9 and skel != null:
			return
		var basis := skel.global_basis if skel != null else visual.global_basis
		var ld: Vector3 = basis.orthonormalized().inverse() * d
		# Model +X is the character's left: Mak on the left -> wave the right arm, and vice versa.
		_greet_arm = "r" if ld.x >= 0.0 else "l"
	_greet = 1.2


## Builders call this on characters shut in a cage.
func set_caged(on: bool) -> void:
	caged = on


## Released from a cage: a wave and a happy hop.
func release() -> void:
	caged = false
	_happy = 1.0
	_greet_arm = "r"
	_greet = 1.2


func _process(delta: float) -> void:
	if visual == null or not visual.is_inside_tree():
		return
	if _observing > 0.0:
		if _driven_elsewhere():
			_step_aside("bones animated by another script")
			return
		_observing -= delta
		if _observing > 0.0:
			return
		# Frozen for the whole window: take the current pose as rest and come alive.
		_base_scale = visual.scale
		_base_rot = visual.rotation
		_base_pos = visual.position
		for b in _bones.keys():
			_rest[b] = skel.get_bone_pose_rotation(int(_bones[b]))
		for b in _g_bones.keys():
			_g_rest[b] = skel.get_bone_pose_rotation(int(_g_bones[b]))
	elif auto and _guard_bone >= 0 and skel != null:
		var q := skel.get_bone_pose_rotation(_guard_bone)
		if absf(q.dot(_guard_q)) < 0.99999:
			_step_aside("skeleton posed by another script")
			return
	_absorb_outside_motion()
	_t += delta
	_talk_t = _talk_t + delta if talking else 0.0
	_greet = maxf(0.0, _greet - delta)
	_happy = maxf(0.0, _happy - delta * 0.8)
	if caged:
		var pl := ObjSvc.get_player()
		var near := pl != null and ObjSvc.body_pos(pl).distance_to(visual.global_position) < 4.0
		_rattle = move_toward(_rattle, 1.0 if near else 0.0, delta * 3.0)
	# Blink timer: a 0.13 s squint.
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 0.13
		_next_blink = randf_range(2.2, 4.8) if randf() > 0.2 else 0.25  # sometimes a double blink
	_blink = maxf(0.0, _blink - delta)
	_next_ear -= delta
	if _next_ear <= 0.0:
		_ear_flick = 0.35
		_ear_side = randi() % 3
		_next_ear = randf_range(2.5, 6.0)
	_ear_flick = maxf(0.0, _ear_flick - delta)
	var breath := sin((_t / breath_period) * TAU) * breath_amount
	_update_look(delta)
	var gait_bob := _gait_step(delta)
	if skel != null and not _bones.is_empty():
		_pose_rig(breath)
		_gait_pose()
		visual.position.y = _base_pos.y + gait_bob
		# A whisper of whole-body breathing on top, anchored at the feet.
		visual.scale = _base_scale * Vector3(1.0 + 0.004 * breath, 1.0 + 0.008 * breath, 1.0 + 0.004 * breath)
		if auto:
			_guard_bone = int(_bones.get("head", _bones.values()[0]))
			_guard_q = skel.get_bone_pose_rotation(_guard_bone)
	else:
		_gait_whole_bob = gait_bob
		_pose_whole(breath)
	_wrote = true
	_w_pos = visual.position
	_w_rot = visual.rotation
	_w_scale = visual.scale


## Motion another script gave the visual root since the last frame goes into the base (x/z tilt, scale, position).
func _absorb_outside_motion() -> void:
	if not _wrote:
		return
	var dp := visual.position - _w_pos
	if dp.length_squared() > 1e-10:
		_base_pos += dp
	var r := visual.rotation
	if absf(r.x - _w_rot.x) > 1e-5 or absf(r.z - _w_rot.z) > 1e-5:
		_base_rot.x += r.x - _w_rot.x
		_base_rot.z += r.z - _w_rot.z
	var sc := visual.scale
	if (sc - _w_scale).length_squared() > 1e-10:
		_base_scale *= Vector3(sc.x / maxf(_w_scale.x, 1e-4), sc.y / maxf(_w_scale.y, 1e-4), sc.z / maxf(_w_scale.z, 1e-4))


func _driven_elsewhere() -> bool:
	if skel == null:
		return false
	var n := mini(_obs_poses.size(), skel.get_bone_count())
	for i in n:
		if absf((skel.get_bone_pose_rotation(i) as Quaternion).dot(_obs_poses[i])) < 0.99999:
			return true
	return false


func _step_aside(why: String) -> void:
	if _wrote:
		visual.position = _base_pos
		visual.rotation = Vector3(_base_rot.x, visual.rotation.y, _base_rot.z)
		visual.scale = _base_scale
	visual.set_meta("npc_life_skip", why)
	print("[NpcLife] auto: %s steps aside (%s)" % [visual.get_path() if visual.is_inside_tree() else visual.name, why])
	set_process(false)
	queue_free()


func _player_head() -> Variant:
	if not look_at_player:
		return null
	var p := ObjSvc.get_player()
	if p == null:
		return null
	var pos := ObjSvc.body_pos(p) + Vector3(0, 0.9, 0)
	if pos.distance_to(visual.global_position) > look_radius:
		return null
	return pos


func _update_look(delta: float) -> void:
	var want_yaw := 0.0
	var want_pitch := 0.0
	var tgt: Variant = _player_head()
	var head_pos := visual.global_position + Vector3(0, 1.0, 0)
	if skel != null and _bones.has("head"):
		head_pos = skel.global_transform * skel.get_bone_global_pose(int(_bones["head"])).origin
	if tgt != null:
		var basis := skel.global_basis if skel != null else visual.global_basis
		var d: Vector3 = basis.orthonormalized().inverse() * ((tgt as Vector3) - head_pos)
		# Models face +Z in their own space.
		want_yaw = clampf(rad_to_deg(atan2(d.x, d.z)), -max_head_yaw, max_head_yaw)
		want_pitch = clampf(rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())), -max_head_pitch, max_head_pitch)
		if absf(rad_to_deg(atan2(d.x, d.z))) > 120.0:
			want_yaw = 0.0  # behind: do not snap the head round, the body turns first
	else:
		# Idle glances.
		want_yaw = sin(_t * 0.37 + _seed) * 14.0 + sin(_t * 0.11) * 8.0
		want_pitch = sin(_t * 0.23 + _seed) * 4.0
	var k := clampf(delta * 4.0, 0.0, 1.0)
	_yaw = lerpf(_yaw, want_yaw, k)
	_pitch = lerpf(_pitch, want_pitch, k)


func _reset(b: String) -> int:
	if not _bones.has(b):
		return -1
	var i: int = _bones[b]
	skel.set_bone_pose_rotation(i, _rest[b])
	return i


## Rotate bone `b` about a model-space axis by `deg` (after its parents are posed).
func _rot(b: String, axis: Vector3, deg: float) -> void:
	if not _bones.has(b) or is_zero_approx(deg):
		return
	var i: int = _bones[b]
	var par := skel.get_bone_parent(i)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var g := skel.get_bone_global_pose(i)
	var nb := Basis(axis.normalized(), deg_to_rad(deg)) * g.basis
	skel.set_bone_pose_rotation(i, (pg.basis.inverse() * nb).get_rotation_quaternion())


func _pose_rig(breath: float) -> void:
	for b in _bones.keys():
		_reset(b)
	var talk := 0.0
	if talking:
		talk = 0.5 + 0.5 * sin(_talk_t * 11.0 + sin(_talk_t * 3.7) * 2.0)
	var snore := bool(_profile.get("snore", false))
	var graze := bool(_profile.get("graze", false))
	# Torso: breathing pitch, a slow sway, a forward lean while talking.
	var torso := "spine" if _bones.has("spine") else ("body" if _bones.has("body") else ("chest" if _bones.has("chest") else ""))
	if torso != "":
		_rot(torso, Vector3.RIGHT, -1.6 * breath + (2.5 * talk if talking else 0.0))
		_rot(torso, Vector3.BACK, sin(_t * 0.6 + _seed) * 1.2)
	if _bones.has("chest") and torso != "chest":
		_rot("chest", Vector3.RIGHT, -1.2 * breath)
	if snore:
		var s := (sin(_t * TAU / breath_period) + 1.0) * 0.5
		_rot("chest", Vector3.RIGHT, -2.5 * s)
		_rot("head", Vector3.RIGHT, -5.0 * s)
		_rot("jaw", Vector3.RIGHT, 4.0 + 14.0 * s)
		_rot("cap_tip", Vector3.BACK, 12.0 * sin(_t * 2.2))
		return
	# Head: look (yaw then pitch), talking nods, grazing dips.
	var nod := 0.0
	if talking:
		nod = sin(_talk_t * 6.3) * 4.0 + sin(_talk_t * 2.1) * 3.0
	if graze:
		var g := clampf(sin(_t * 0.45 + _seed) * 1.6, 0.0, 1.0) if _player_head() == null else 0.0
		_rot("head", Vector3.RIGHT, 32.0 * g + sin(_t * 7.0) * 2.0 * g)
	_rot("head", Vector3.UP, _yaw)
	_rot("head", Vector3.RIGHT, -_pitch + nod - 1.0 * breath)
	var tilt := float(_profile.get("head_tilt", 0.0)) + (12.0 if caged else 0.0)
	_rot("head", Vector3.BACK, tilt + sin(_t * 0.8 + _seed) * 2.5 + (sin(_talk_t * 2.9) * 4.0 if talking else 0.0))
	if _bones.has("eyelid_l") or _bones.has("eyelid_r"):
		# Rigs with lid bones (the hero v2 kit: identity = open, +X 115 deg = closed) blink with real lids; the head
		# squint below is only for lid-less models.
		var lid := sin((1.0 - _blink / 0.13) * PI) if _blink > 0.0 else 0.0
		for b in ["eyelid_l", "eyelid_r"]:
			if _bones.has(b):
				skel.set_bone_pose_rotation(int(_bones[b]), (_rest[b] as Quaternion) * Quaternion(Vector3.RIGHT, deg_to_rad(115.0 * lid)))
	elif _bones.has("head") and _blink > 0.0:
		var bk := sin((1.0 - _blink / 0.13) * PI)
		skel.set_bone_pose_scale(int(_bones["head"]), Vector3(1.0 + 0.02 * bk, 1.0 - 0.06 * bk, 1.0))
	elif _bones.has("head"):
		skel.set_bone_pose_scale(int(_bones["head"]), Vector3.ONE)
	if _bones.has("jaw"):
		# Profile "jaw": degrees at full open (sign = the rig's opening direction). The cow's jaw opens at POSITIVE
		# angles (ASSETS3_CHARS r5: -10 pushed the lip up into the muzzle); daisy_cow_v3 shows its mouth at +12/+20.
		var jaw_open := float(_profile.get("jaw", 14.0))
		var chew := 0.0
		if graze and not talking:
			chew = (0.5 + 0.5 * sin(_t * 9.0)) * 0.45 * clampf(sin(_t * 0.45 + _seed) * 1.6, 0.0, 1.0)
		_rot("jaw", Vector3.RIGHT, jaw_open * maxf(talk, chew))
	# Ears: a soft breathing drift, plus a quick flick now and then (0 = left, 1 = right, 2 = both).
	var flick := sin((1.0 - _ear_flick / 0.35) * PI) * 22.0 if _ear_flick > 0.0 else 0.0
	_rot("ear_l", Vector3.BACK, 2.0 * breath + (flick if _ear_side != 1 else 0.0))
	_rot("ear_r", Vector3.BACK, -2.0 * breath - (flick if _ear_side != 0 else 0.0))
	# Tail: a lazy wag, quicker while greeting or talking.
	var wag_speed := 2.2 if (_greet <= 0.0 and not talking) else 7.0
	_rot("tail", Vector3.UP, sin(_t * wag_speed) * (14.0 if _greet <= 0.0 else 28.0))
	_rot("tail_2", Vector3.UP, sin(_t * wag_speed - 0.8) * 16.0)
	# Arms: relax the A-pose, breathe, gesture while talking, wave on greeting (right arm).
	var gest_l := 0.0
	var gest_r := 0.0
	if talking:
		gest_l = sin(_talk_t * 4.1) * 10.0 + sin(_talk_t * 1.7) * 8.0
		gest_r = sin(_talk_t * 3.3 + 1.0) * 14.0 + 10.0
	var g2 := sin(clampf(_greet / 1.2, 0.0, 1.0) * PI) if _greet > 0.0 else 0.0
	var wave_l := g2 if _greet_arm == "l" else 0.0
	var wave_r := g2 if _greet_arm == "r" else 0.0
	if caged:
		# Grip the bars: both arms forward and up to shoulder height, forearms bent in; a rattle when Mak is near.
		var shake := sin(_t * 26.0) * 6.0 * _rattle
		_rot("arm_l", Vector3.BACK, -arm_lower * 0.4 + 1.5 * breath)
		_rot("arm_r", Vector3.BACK, arm_lower * 0.4 - 1.5 * breath)
		_rot("arm_l", Vector3.UP, -62.0 + shake)
		_rot("arm_r", Vector3.UP, 62.0 - shake)
		_rot("arm_l", Vector3.RIGHT, -35.0 - absf(shake))
		_rot("arm_r", Vector3.RIGHT, -35.0 - absf(shake))
		_rot("forearm_l", Vector3.UP, -30.0)
		_rot("forearm_r", Vector3.UP, 30.0)
		if torso != "":
			_rot(torso, Vector3.RIGHT, 4.0 + absf(shake) * 0.4)
		return
	var arm_fwd := float(_profile.get("arm_fwd", 0.0)) * (1.0 - maxf(wave_l, wave_r))
	_rot("arm_l", Vector3.BACK, -arm_lower * (1.0 - wave_l) + 1.5 * breath + gest_l * 0.6)
	_rot("arm_r", Vector3.BACK, arm_lower * (1.0 - wave_r) - 1.5 * breath - gest_r * 0.6)
	_rot("arm_l", Vector3.UP, -arm_fwd * (1.0 - wave_l))
	_rot("arm_r", Vector3.UP, arm_fwd * (1.0 - wave_r))
	var fd := float(_profile.get("fore_down", 0.0))
	var ff := float(_profile.get("fore_fwd", 0.0))
	# Hand-wringing (profiles with fore_*): a slow fidget so the pose never freezes.
	var fidget := sin(_t * 2.3 + _seed) * 6.0 if ff > 0.0 else 0.0
	_rot("forearm_l", Vector3.BACK, -fd * (1.0 - wave_l))
	_rot("forearm_r", Vector3.BACK, fd * (1.0 - wave_r))
	_rot("forearm_l", Vector3.UP, (-ff - fidget) * (1.0 - wave_l))
	_rot("forearm_r", Vector3.UP, (ff + fidget) * (1.0 - wave_r))
	if wave_r > 0.0:
		_rot("arm_r", Vector3.BACK, -75.0 * wave_r)
		_rot("forearm_r", Vector3.BACK, -25.0 * wave_r * (0.5 + 0.5 * sin(_t * 16.0)))
	else:
		_rot("forearm_r", Vector3.RIGHT, -gest_r)
	if wave_l > 0.0:
		_rot("arm_l", Vector3.BACK, 75.0 * wave_l)
		_rot("forearm_l", Vector3.BACK, 25.0 * wave_l * (0.5 + 0.5 * sin(_t * 16.0)))
	else:
		_rot("forearm_l", Vector3.RIGHT, -gest_l - 6.0)
	# Bird: head bob and peck.
	if bool(_profile.get("bird", false)):
		_rot("head", Vector3.RIGHT, maxf(0.0, sin(_t * 1.3 + _seed) - 0.85) * 120.0)


func _pose_whole(breath: float) -> void:
	# Breathing squash from the feet, a talking bob-and-rock, a greeting hop, a lean toward Mak.
	var sy := 1.0 + 0.018 * breath
	var sxz := 1.0 - 0.008 * breath
	var rock := 0.0
	var hop := 0.0
	if talking:
		var b := absf(sin(_talk_t * 7.0))
		sy += 0.035 * b
		sxz -= 0.015 * b
		rock = sin(_talk_t * 3.5) * 3.0
	var bow := 0.0
	if _greet > 0.0 and _greet_kind == "bow" and _happy <= 0.0:
		# An elder's bow: pitch forward from the feet over 0.5 s, hold, rise; the feet never leave the floor.
		var ub := 1.0 - _greet / 1.2
		bow = 12.0 * (smoothstep(0.0, 0.4, ub) - smoothstep(0.7, 1.0, ub))
	elif _greet > 0.0:
		var u := 1.0 - _greet / 1.2
		if u < 0.12:
			sy -= 0.08 * sin(u / 0.12 * PI)  # anticipation squat
			sxz += 0.04 * sin(u / 0.12 * PI)
		elif u < 0.55:
			hop = sin((u - 0.12) / 0.43 * PI) * 0.16
			sy += 0.05 * sin((u - 0.12) / 0.43 * PI)
		else:
			var land := sin(clampf((u - 0.55) / 0.2, 0.0, 1.0) * PI)
			sy -= 0.05 * land
			sxz += 0.03 * land
	if _blink > 0.0:
		sy -= 0.012 * sin((1.0 - _blink / 0.13) * PI)
	if bool(_profile.get("bird", false)):
		var peck := maxf(0.0, sin(_t * 1.3 + _seed) - 0.85) / 0.15
		visual.rotation.x = _base_rot.x + deg_to_rad(18.0 * peck)
	else:
		visual.rotation.x = _base_rot.x + deg_to_rad(-_pitch * 0.15 + bow)
	visual.rotation.z = _base_rot.z + deg_to_rad(rock + sin(_t * 0.7 + _seed) * 1.2 + _yaw * 0.04)
	visual.scale = _base_scale * Vector3(sxz, sy, sxz)
	if caged:
		# Unrigged and caged: a nervous tremble that grows into a rattle when Mak is near.
		visual.rotation.z += deg_to_rad(sin(_t * 24.0) * (0.6 + 2.2 * _rattle))
	visual.position.y = _base_pos.y + hop + _gait_whole_bob
	visual.rotation.z += deg_to_rad(sin(_g_phase) * 4.0 * _g_w)


# ------------------------------------------------------------------ gait (LEGS pass)

## Advances the walk from the ground distance the model covered since the last frame; returns the body bob (m).
func _gait_step(delta: float) -> float:
	var p := visual.global_position
	var fz := visual.global_basis.z
	var f2 := Vector2(fz.x, fz.z)
	var d := 0.0
	var dir := 1.0
	if _g_prev != Vector3.INF:
		var dp := Vector2(p.x - _g_prev.x, p.z - _g_prev.z)
		d = dp.length()
		# Backing away (the scatter return) steps backward instead of moonwalking. Models face +Z.
		if f2.length() > 0.01 and dp.dot(f2.normalized()) < -0.6 * d:
			dir = -1.0
	_g_prev = p
	if d > 1.0:
		d = 0.0
	var yaw := atan2(fz.x, fz.z)
	var yr := absf(wrapf(yaw - _g_yaw, -PI, PI)) / maxf(delta, 0.0001)
	_g_yaw = yaw
	if yr > 20.0:
		yr = 0.0
	_g_speed = lerpf(_g_speed, d / maxf(delta, 0.0001), 1.0 - exp(-10.0 * delta))
	var h := _g_hip
	var turn := yr * clampf(1.0 - _g_speed / 0.4, 0.0, 1.0)
	var want := clampf(maxf(_g_speed / 0.12, turn * 0.6), 0.0, 1.0)
	_g_w = move_toward(_g_w, want, delta * (6.0 if want > _g_w else 3.0))
	var fr := _g_speed / sqrt(9.8 * h)
	var step := minf(h * clampf(0.45 + 0.85 * fr, 0.45, 1.6), 2.0 * h * sin(0.7))
	_g_phase = fmod(_g_phase + dir * d / maxf(2.0 * step, 0.03) * TAU + turn * 0.5 * delta, TAU * 64.0)
	_g_amp = lerpf(_g_amp, asin(clampf(step / (2.0 * h), 0.0, 0.9)), 1.0 - exp(-8.0 * delta))
	var c := cos(_g_phase * 2.0)
	return h * 0.06 * _g_w * clampf(_g_amp / 0.35, 0.4, 1.2) * (0.5 + 0.5 * c)


func _g_reset(b: String) -> void:
	if _g_bones.has(b):
		var i: int = _g_bones[b]
		skel.set_bone_pose_rotation(i, _g_rest[b])
		skel.set_bone_pose_scale(i, Vector3.ONE)


## Rotates gait bone `b` about a model-space axis (degrees), after its parents are posed.
func _g_rot(b: String, axis: Vector3, deg: float) -> void:
	if not _g_bones.has(b) or is_zero_approx(deg):
		return
	var i: int = _g_bones[b]
	var par := skel.get_bone_parent(i)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var g := skel.get_bone_global_pose(i)
	var nb := Basis(axis.normalized(), deg_to_rad(deg)) * g.basis
	skel.set_bone_pose_rotation(i, (pg.basis.inverse() * nb).get_rotation_quaternion())


## Poses the legs for this frame (after _pose_rig): only while walking or fading out.
func _gait_pose() -> void:
	if _g_w < 0.002:
		if _g_dirty:
			for b in _g_bones.keys():
				_g_reset(b)
			_g_dirty = false
		return
	_g_dirty = true
	var w := _g_w
	var a := rad_to_deg(_g_amp) * w
	var s := sin(_g_phase)
	# Body: a sway in step and a small pitch rock (leg-less rigs keep only this waddle).
	var torso := "body" if _bones.has("body") else ("spine" if _bones.has("spine") else ("hips" if _bones.has("hips") else ""))
	if torso != "":
		_rot(torso, Vector3.BACK, s * 2.5 * w)
		_rot(torso, Vector3.RIGHT, cos(_g_phase * 2.0) * 1.2 * w)
	if _bones.has("head"):
		_rot("head", Vector3.RIGHT, -cos(_g_phase * 2.0) * 2.0 * w)
	for b in _g_bones.keys():
		_g_reset(b)
	if _g_bones.has("leg_fl") or _g_bones.has("leg_bl"):
		# Four-beat walk (hind left, fore left, hind right, fore right) blending into a diagonal trot.
		var trot := clampf((_g_speed / sqrt(9.8 * _g_hip) - 0.35) / 0.3, 0.0, 1.0)
		var offs := {"leg_bl": 0.0, "leg_br": PI, "leg_fl": PI * 0.5 + trot * PI * 0.5, "leg_fr": PI * 1.5 + trot * PI * 0.5}
		for b in offs.keys():
			if not _g_bones.has(b):
				continue
			var ph: float = _g_phase + float(offs[b])
			# +X in model space swings a hanging leg's foot back (models face +Z): a forward swing is negative.
			_g_rot(b, Vector3.RIGHT, -a * sin(ph))
			var lift := maxf(0.0, cos(ph))
			skel.set_bone_pose_scale(int(_g_bones[b]), Vector3(1.0, 1.0 - 0.16 * lift * lift * w, 1.0))
		return
	var hl := "thigh_l" if _g_bones.has("thigh_l") else "leg_l"
	var hr := "thigh_r" if _g_bones.has("thigh_r") else "leg_r"
	var c := cos(_g_phase)
	var kf := (18.0 + 70.0 * _g_amp) * w
	var kl := kf * maxf(0.0, c) * maxf(0.0, c)
	var kr := kf * maxf(0.0, -c) * maxf(0.0, -c)
	_g_rot(hl, Vector3.RIGHT, -a * s - 0.35 * kl)
	_g_rot(hr, Vector3.RIGHT, a * s - 0.35 * kr)
	_g_rot("shin_l", Vector3.RIGHT, kl)
	_g_rot("shin_r", Vector3.RIGHT, kr)

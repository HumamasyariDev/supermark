class_name WolfRig
extends Node3D
## Procedural animator for the rigged Tripo P2 wolf (res://assets/characters/wolf_boss/wolf_boss.glb).
## The GLB has 32 bones and no clips (ATTACH.md), so every state is a recipe (BOSS_amendments R3.11):
## each frame the boss clears the targets, sets bone offsets / bone scales / root offsets / blend
## shapes, and update() eases the skeleton toward them.
##
## Conventions (model space, the model faces +Z, Y up): pose(bone, Vector3(pitch, yaw, roll)) in radians.
##   pitch +  = the bone's tip swings toward the character's front for upward bones (spine, neck, head
##              nod down); for downward bones (legs, arms) use NEGATIVE pitch to swing them forward.
##   yaw +    = turn toward the character's left (+X).
##   roll +   = tip swings toward the character's left (+X); raise arm_l sideways with +roll, arm_r with -roll.
## Rotations are applied about each bone's own joint in model-space axes (conjugated by the rest pose).

const GLB := "res://assets/characters/wolf_boss/wolf_boss.glb"
const CANE := "res://assets/characters/wolf_boss/wolf_cane.glb"
const BONES := ["root", "hips", "spine", "spine_2", "spine_3", "chest", "neck", "head", "jaw", "ear_l", "ear_r",
	"arm_l", "forearm_l", "hand_l", "arm_r", "forearm_r", "hand_r", "thigh_l", "shin_l", "foot_l",
	"thigh_r", "shin_r", "foot_r", "tail", "tail_2", "tail_3", "tail_4", "coat_l", "coat_l_2", "coat_r", "coat_r_2"]

## Root-motion pivot (squash, lean, bob). Child of this node; the model sits under it turned 180 degrees.
var body: Node3D
## Set before adding to the tree to drive another rigged GLB (the crows use this too).
var glb_path: String = GLB
var bone_names: Array = BONES
var with_cane := true
var model: Node3D
var skel: Skeleton3D
var cane: Node3D
var ids: Dictionary = {}
var _rest_local: Dictionary = {}
var _rest_global: Dictionary = {}
var _s_basis := Basis()
var _s_inv := Basis()
var _mi: MeshInstance3D
var _bs_chest := -1
var _bs_cheeks := -1
var meshes: Array[MeshInstance3D] = []

var _tgt: Dictionary = {}
var _cur: Dictionary = {}
var _stgt: Dictionary = {}
var _scur: Dictionary = {}
var root_pos := Vector3.ZERO
var root_rot := Vector3.ZERO
var root_scale := Vector3.ONE
var chest_inflate := 0.0
var cheeks_puff := 0.0
var _rp := Vector3.ZERO
var _rr := Vector3.ZERO
var _rs := Vector3.ONE
var _ci := 0.0
var _cp := 0.0
## Squash spring (kick() it on landings and hits).
var squash := 0.0
var _squash_v := 0.0
## Ease rate (1/s) for bones; states can raise it for snappy moves.
var rate := 14.0
var root_rate := 16.0


func _ready() -> void:
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	if not ResourceLoader.exists(glb_path):
		push_warning("WolfRig: wolf_boss.glb missing")
		return
	var flip := Node3D.new()
	flip.name = "Visual"
	flip.rotation_degrees.y = 180.0
	body.add_child(flip)
	model = (load(glb_path) as PackedScene).instantiate() as Node3D
	flip.add_child(model)
	var sk := model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	skel = sk[0] as Skeleton3D
	# Skeleton basis relative to the model root (in case the armature carries a transform).
	var rel := model.global_transform.affine_inverse() * skel.global_transform
	_s_basis = rel.basis.orthonormalized()
	_s_inv = _s_basis.inverse()
	for b in bone_names:
		var i := skel.find_bone(b)
		if i >= 0:
			ids[b] = i
			_rest_local[b] = skel.get_bone_rest(i)
			_rest_global[b] = skel.get_bone_global_rest(i).basis.orthonormalized()
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		meshes.append(mi)
		if mi.mesh != null and mi.find_blend_shape_by_name("chest_inflate") >= 0:
			_mi = mi
			_bs_chest = mi.find_blend_shape_by_name("chest_inflate")
			_bs_cheeks = mi.find_blend_shape_by_name("cheeks_puff")
	var sock := skel.find_bone("cane_socket_r")
	if with_cane and sock >= 0 and ResourceLoader.exists(CANE):
		var ba := BoneAttachment3D.new()
		ba.name = "CaneSocket"
		ba.bone_name = "cane_socket_r"
		skel.add_child(ba)
		cane = (load(CANE) as PackedScene).instantiate() as Node3D
		ba.add_child(cane)
		for n in cane.find_children("*", "MeshInstance3D", true, false):
			meshes.append(n as MeshInstance3D)


## Bone world position (for sockets: head, hand_r, tail_4 ...).
func bone_world(b: String) -> Vector3:
	if skel == null or not ids.has(b):
		return global_position + Vector3(0, 2.6, 0)
	return skel.global_transform * skel.get_bone_global_pose(int(ids[b])).origin


func attach(b: String, node: Node3D, local := Transform3D.IDENTITY) -> BoneAttachment3D:
	if skel == null or not ids.has(b):
		add_child(node)
		return null
	var ba := BoneAttachment3D.new()
	ba.name = "Socket_" + b
	ba.bone_name = b
	skel.add_child(ba)
	ba.add_child(node)
	node.transform = local
	return ba


func begin() -> void:
	_tgt.clear()
	_stgt.clear()
	root_pos = Vector3.ZERO
	root_rot = Vector3.ZERO
	root_scale = Vector3.ONE
	chest_inflate = 0.0
	cheeks_puff = 0.0


func pose(b: String, e: Vector3) -> void:
	_tgt[b] = (_tgt.get(b, Vector3.ZERO) as Vector3) + e


func bscale(b: String, s: Vector3) -> void:
	_stgt[b] = s


func kick(amount: float) -> void:
	_squash_v += amount * 12.0


func snap() -> void:
	## Jump straight to the targets (after a teleport or for cuts).
	for b in _tgt.keys():
		_cur[b] = _tgt[b]
	_rp = root_pos
	_rr = root_rot
	_rs = root_scale


func update(delta: float) -> void:
	if body == null:
		return
	_squash_v += (-240.0 * squash - 12.0 * _squash_v) * delta
	squash = clampf(squash + _squash_v * delta, -0.5, 0.6)
	var kr := 1.0 - exp(-root_rate * delta)
	_rp = _rp.lerp(root_pos, kr)
	_rr = _rr.lerp(root_rot, kr)
	_rs = _rs.lerp(root_scale, kr)
	body.position = _rp
	body.rotation = _rr
	body.scale = _rs * Vector3(1.0 + squash * 0.5, 1.0 - squash, 1.0 + squash * 0.5)
	var kb := 1.0 - exp(-rate * delta)
	_ci = lerpf(_ci, chest_inflate, kb)
	_cp = lerpf(_cp, cheeks_puff, 1.0 - exp(-18.0 * delta))
	if _mi != null:
		_mi.set_blend_shape_value(_bs_chest, clampf(_ci, 0.0, 1.0))
		if _bs_cheeks >= 0:
			_mi.set_blend_shape_value(_bs_cheeks, clampf(_cp, 0.0, 1.0))
	if skel == null:
		return
	for b in ids.keys():
		var want: Vector3 = _tgt.get(b, Vector3.ZERO)
		var c: Vector3 = _cur.get(b, Vector3.ZERO)
		c = c.lerp(want, kb)
		_cur[b] = c
		var i := int(ids[b])
		var rest: Transform3D = _rest_local[b]
		var g: Basis = _rest_global[b]
		var r_model := Basis.from_euler(c)
		var r_sk := _s_inv * r_model * _s_basis
		var local := rest.basis * (g.inverse() * r_sk * g)
		skel.set_bone_pose_rotation(i, local.get_rotation_quaternion())
		skel.set_bone_pose_position(i, rest.origin)
		var sw: Vector3 = _stgt.get(b, Vector3.ONE)
		var sc: Vector3 = _scur.get(b, Vector3.ONE)
		sc = sc.lerp(sw, kb)
		_scur[b] = sc
		skel.set_bone_pose_scale(i, sc)


## Hit flash / glow on every wolf surface (material overlay).
var _flash_mat: StandardMaterial3D
var _flash_t := 0.0


func flash(color: Color = Color(1, 1, 1), seconds := 0.18) -> void:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for mi in meshes:
			mi.material_overlay = _flash_mat
	_flash_mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	_flash_t = seconds


func _process(delta: float) -> void:
	if _flash_t > 0.0 and _flash_mat != null:
		_flash_t -= delta
		_flash_mat.albedo_color.a = clampf(_flash_t / 0.18, 0.0, 1.0) * 0.85


## Put every wolf mesh on visual layers 1 + 2 (layer 2 = the character key light).
func set_layers(mask: int) -> void:
	for mi in meshes:
		mi.layers = mask

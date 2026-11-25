class_name HubRig
extends RefCounted
## Minimal bone poser for the hub's generated characters (woolly_wolf, woolly_wolf_cub, pip_v2...). It uses the
## same part names, aliases and euler convention as EnemyBase (pose("arm_l", Vector3(x, y, z)) in the parent's
## rest frame), so the clips read the same as the enemy rigs. r1 fun critique: the hub gags slid rest-pose models.

const ALIASES := {"leg_l": ["thigh_l", "upperleg_l"], "leg_r": ["thigh_r", "upperleg_r"], "arm_l": ["upperarm_l", "shoulder_l"],
	"arm_r": ["upperarm_r", "shoulder_r"], "body": ["spine", "torso"]}
const PARTS := ["body", "hips", "head", "jaw", "ear_l", "ear_r", "arm_l", "arm_r", "forearm_l", "forearm_r", "leg_l", "leg_r",
	"shin_l", "shin_r", "tail", "tail_2"]

var skel: Skeleton3D
var ids: Dictionary = {}
var rest: Dictionary = {}
var parent_basis: Dictionary = {}
var _cur: Dictionary = {}


static func attach(root: Node) -> HubRig:
	if root == null:
		return null
	var sk := root.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return null
	var r := HubRig.new()
	r.skel = sk[0] as Skeleton3D
	for part in PARTS:
		var names: Array = [part]
		names.append_array(ALIASES.get(part, []))
		for cand in names:
			if r.ids.has(part):
				break
			for i in r.skel.get_bone_count():
				var bn := r.skel.get_bone_name(i).to_lower()
				if bn == cand or bn.ends_with("_" + cand) or bn.ends_with("." + cand) or bn.ends_with(":" + cand):
					r.ids[part] = i
					r.rest[part] = r.skel.get_bone_rest(i).basis
					var par := r.skel.get_bone_parent(i)
					r.parent_basis[part] = r.skel.get_bone_global_rest(par).basis if par >= 0 else Basis()
					break
	return r


func has(part: String) -> bool:
	return ids.has(part)


## Sets a part's rotation (radians, EnemyBase convention). `ease` > 0 blends toward it at that rate per second.
func set_part(part: String, euler: Vector3, rate := 0.0, delta := 0.0) -> void:
	if not ids.has(part) or skel == null or not is_instance_valid(skel):
		return
	var e := euler
	if rate > 0.0 and delta > 0.0:
		var cur: Vector3 = _cur.get(part, Vector3.ZERO)
		e = cur.lerp(euler, 1.0 - exp(-rate * delta))
	_cur[part] = e
	var r := Basis.from_euler(Vector3(-e.x, e.y, -e.z))
	var pb: Basis = parent_basis[part]
	var local: Basis = pb.inverse() * r * pb * (rest[part] as Basis)
	skel.set_bone_pose_rotation(ids[part], local.orthonormalized().get_rotation_quaternion())


## Applies a whole pose dictionary (part -> euler) with easing; parts not named ease back to rest.
func pose(p: Dictionary, delta: float, rate := 14.0) -> void:
	for part in ids.keys():
		set_part(part, p.get(part, Vector3.ZERO), rate, delta)


## Quadruped-ish biped run cycle used by both wolf models (thigh/shin about 35 deg at `hz`, arm swing, ear flop).
static func run_pose(t: float, hz: float, amp := 1.0) -> Dictionary:
	var ph := t * TAU * hz
	var s := sin(ph) * amp
	var c := cos(ph) * amp
	return {
		"leg_l": Vector3(s * 0.62, 0, 0), "leg_r": Vector3(-s * 0.62, 0, 0),
		"shin_l": Vector3(-maxf(0.0, -c) * 0.7, 0, 0), "shin_r": Vector3(-maxf(0.0, c) * 0.7, 0, 0),
		"arm_l": Vector3(-s * 0.7, 0, 0.55), "arm_r": Vector3(s * 0.7, 0, -0.55),
		"forearm_l": Vector3(-0.35, 0, 0), "forearm_r": Vector3(-0.35, 0, 0),
		"body": Vector3(0.18, sin(ph) * 0.08 * amp, 0),
		"head": Vector3(-0.1 + absf(s) * 0.08, -sin(ph) * 0.06, 0),
		"ear_l": Vector3(-0.3 - absf(c) * 0.4, 0, 0.2), "ear_r": Vector3(-0.3 - absf(s) * 0.4, 0, -0.2),
		"tail": Vector3(-0.6, sin(ph * 2.0) * 0.3, 0), "tail_2": Vector3(0, sin(ph * 2.0 - 0.8) * 0.25, 0),
		"jaw": Vector3(0.15 + absf(s) * 0.1, 0, 0),
	}

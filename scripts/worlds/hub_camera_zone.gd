extends Area3D
## Hub camera hint (HUB_amendments R2.10) for MakCameraRig's "camera_zone" group. The yaw is a live property, so the
## camera sits on the hall side of Mak on curved ledges:
##   "radial"      looks outward from the hall centre at Mak's polar angle (top balcony, shelf ring)
##   "radial_lead" radial, offset 14 deg against Mak's tangential motion so a held stick drifts toward the wall,
##                 never off the inner edge (r1 feel critique: cornice walks)
##   "tangent"     behind Mak along the ledge (yaw_offset round from outward); r1 round 2 cornice walk
##   "fixed"       keeps one yaw (chimney, top balcony, rim drop)
##   "mouth"       looks into the stair nook from the open side
##   "chase"       looks from Mak toward `target` so both stay in frame (phase-2 cub duel)
##   "none"        leaves the yaw to the player and only sets pitch and distance
##   "outside"     fix r2: camera outward of Mak (between him and the shelves), looking in toward the hall axis and
##                 trailing `yaw_offset` degrees behind along the climb; distance shrinks so the camera stays inside
##                 `outer_radius` (Catalogue Spiral: the chandelier is then behind Mak, never in the foreground)

@export var mode := "radial"
@export var fixed_yaw := 0.0
@export var camera_pitch_deg := -18.0
@export var camera_distance := 6.0:
	get:
		if mode == "outside" and is_inside_tree():
			var pl := get_tree().get_first_node_in_group("player") as Node3D
			if pl:
				var r := Vector2(pl.global_position.x, pl.global_position.z).length()
				return clampf(outer_radius - r, min_outside_distance, camera_distance)
		return camera_distance
## "outside" only: the camera stays inside this radius (m from the hall axis).
@export var outer_radius := 12.0
@export var min_outside_distance := 3.2
@export var camera_blend := 3.0
@export var camera_priority := 5
## "radial" only: degrees added to Mak's polar angle, so the view leans ahead along a spiral (CHINT_spiral +30).
@export var yaw_offset := 0.0
var target: Node3D
var _lead := 0.0
var _mouth_side := 0.0  # fix r2 (feel): "mouth" keeps its side until Mak is 1 m past the axis (no flip at the board)

var camera_yaw_deg: float:
	get:
		var p := get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
		if p == null:
			return fixed_yaw
		match mode:
			"radial":
				var th := rad_to_deg(atan2(p.global_position.x, -p.global_position.z))
				return -(th + yaw_offset)
			"radial_lead":
				var th2 := rad_to_deg(atan2(p.global_position.x, -p.global_position.z))
				var v: Vector3 = p.get("velocity") if p.get("velocity") != null else Vector3.ZERO
				var tang := Vector3(cos(deg_to_rad(th2)), 0.0, sin(deg_to_rad(th2)))  # d(polar)/d(theta), clockwise
				var vt := v.dot(tang)
				if absf(vt) > 0.8:
					_lead = lerpf(_lead, 14.0 * signf(vt), 0.08)
				return -(th2 - _lead)
			"tangent":
				# Behind Mak along a curved ledge, looking yaw_offset degrees round from the outward radial (55 looks
				# mostly along the walk with the wall on the right and the hall on the left).
				var th3 := rad_to_deg(atan2(p.global_position.x, -p.global_position.z))
				return -(th3 + yaw_offset)
			"mouth":
				var px := p.global_position.x
				if _mouth_side == 0.0 or absf(px) > 1.0:
					_mouth_side = -1.0 if px < 0.0 else 1.0
				return -90.0 if _mouth_side < 0.0 else 90.0
			"outside":
				var tho := rad_to_deg(atan2(p.global_position.x, -p.global_position.z))
				return -(tho - yaw_offset + 180.0)
			"chase":
				if target and is_instance_valid(target):
					var d := target.global_position - p.global_position
					d.y = 0.0
					if d.length() > 0.5:
						return rad_to_deg(atan2(-d.x, -d.z))
				return NAN
			"none":
				return NAN
		return fixed_yaw


func _ready() -> void:
	add_to_group("camera_zone")
	collision_layer = 1 << 7
	collision_mask = 1 << 1
	monitoring = false
	monitorable = true

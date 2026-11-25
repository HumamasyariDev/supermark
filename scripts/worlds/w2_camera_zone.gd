extends Area3D
## W2 camera hint (W2.json camera_hints CH0-CH7, fix round 1) for MakCameraRig's "camera_zone" group.
## Rig convention: yaw 0 puts the camera south of Mak looking north (+90 = camera east of Mak); negative pitch
## looks down. Modes: "fixed" keeps fixed_yaw; "outside" puts the camera on the far side of Mak from the beanstalk
## axis, turned `spiral_bias` degrees back along the climb so the next leaf stays ahead of him.
## Optional `pivot_height` is applied to the rig by w2_camera.gd while Mak is inside (CH0 look-up framing).

@export var mode := "fixed"
@export var fixed_yaw := 0.0
@export var camera_pitch_deg := -17.0
@export var camera_distance := 5.4
@export var camera_blend := 2.5
@export var camera_priority := 5
@export var pivot_height := -1.0      ## m above the ground reference; < 0 keeps the rig's own value
@export var spiral_bias := 30.0       ## deg, "outside" mode only
@export var yaw_free := false         ## true: only distance/pitch, the yaw stays free

var builder  # w2_build.gd instance (stalk_center)

var camera_yaw_deg: Variant:
	get:
		if yaw_free:
			return null
		if mode == "outside" and builder != null and is_inside_tree():
			var p := get_tree().get_first_node_in_group("player") as Node3D
			if p != null:
				var c: Vector3 = builder.stalk_center(p.global_position.y)
				var out := Vector3(p.global_position.x - c.x, 0.0, p.global_position.z - c.z)
				if out.length() > 0.2:
					out = out.normalized()
					# The spirals climb with decreasing polar angle atan2(z, x): "behind" is the +angle tangent.
					var behind := Vector3(-out.z, 0.0, out.x)
					var d := out * cos(deg_to_rad(spiral_bias)) + behind * sin(deg_to_rad(spiral_bias))
					return rad_to_deg(atan2(d.x, d.z))
		return fixed_yaw


func _ready() -> void:
	add_to_group("camera_zone")
	collision_layer = 1 << 7
	collision_mask = 1 << 1
	monitoring = false
	monitorable = true

class_name Climbable
extends Area3D
## Climbable vine or pole (group "climbable"). The player reads get_climb_axis(), get_pole_radius(),
## get_climb_bottom() and get_climb_top(). Origin at the bottom; the climb runs up local +Y for `height`.

enum Look { VINE, POLE, ROPE }

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var look: Look = Look.VINE
@export var height: float = 6.0
@export var pole_radius: float = 0.18
@export var grab_radius: float = 0.6

var _t := 0.0
var _leaves: Array[Node3D] = []


func _ready() -> void:
	add_to_group("climbable")
	set_meta("pole_radius", pole_radius)
	collision_layer = ObjSvc.L_TRIGGER
	collision_mask = ObjSvc.L_PLAYER
	monitorable = true
	ObjSvc.add_shape(self, ObjSvc.cyl_shape(grab_radius, height), Vector3(0, height * 0.5, 0))
	var v := ObjSvc.ensure_visual(self)
	if not ObjSvc.visual_has_content(v):
		match look:
			Look.VINE:
				if not _build_beanstalk_vine(v):
					_build_vine(v)
			Look.POLE:
				# Critique objects r1 re-run: a plain brass cylinder. In the candy world the pole is a striped candy
				# stick (painted stripe texture, glossy); elsewhere brass with rope wraps at the grips.
				var pole_mat: Material = ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.85)
				if ObjSvc.current_world() == "W3" and ResourceLoader.exists("res://assets/textures/candy_stripes.webp"):
					var cm := StandardMaterial3D.new()
					cm.albedo_texture = load("res://assets/textures/candy_stripes.webp") as Texture2D
					cm.uv1_scale = Vector3(1.0, height / 0.8, 1.0)
					cm.roughness = 0.25
					cm.metallic_specular = 0.7
					pole_mat = cm
				else:
					var rope := ObjSvc.mat(Color(0.8, 0.66, 0.44), 0.9)
					for k in maxi(1, int(height / 1.5)):
						var gy := 0.9 + float(k) * 1.5
						for j in 5:
							ObjSvc.torus(v, pole_radius * 0.72, pole_radius * 1.08, rope, Vector3(0, gy + j * 0.05, 0))
				ObjSvc.cylinder(v, pole_radius * 0.8, pole_radius * 0.8, height, pole_mat, Vector3(0, height * 0.5, 0))
				ObjSvc.sphere(v, pole_radius * 1.6, ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.85), Vector3(0, height, 0))
				ObjSvc.cylinder(v, pole_radius * 2.0, pole_radius * 2.4, 0.2, ObjSvc.mat(ObjSvc.WALNUT_DARK, 0.6), Vector3(0, 0.1, 0))
			Look.ROPE:
				var rope := ObjSvc.mat(Color(0.82, 0.68, 0.45), 0.9)
				var segs := int(height / 0.25)
				for i in segs:
					ObjSvc.capsule(v, pole_radius * 0.6, 0.3, rope, Vector3(0, 0.15 + i * 0.25, 0), Vector3(0, i * 40.0, 12 if i % 2 else -12))


## Critique objects r1: vines were runtime primitives. The generated W2 beanstalk segment, scaled uniformly so its
## stalk matches the pole radius, is stacked up the climb with a twist per segment (leaves keep their proportions).
const BEANSTALK := "res://assets/props/w2/beanstalk_segment/beanstalk_segment.glb"
const BEANSTALK_RADIUS := 1.8
const BEANSTALK_HEIGHT := 10.0


func _build_beanstalk_vine(v: Node3D) -> bool:
	if not ResourceLoader.exists(BEANSTALK):
		return false
	var ps := load(BEANSTALK) as PackedScene
	if ps == null:
		return false
	var sc := pole_radius * 1.1 / BEANSTALK_RADIUS
	var seg_h := BEANSTALK_HEIGHT * sc
	var n := maxi(1, int(ceil(height / seg_h)))
	# Stretch the stack a touch so whole segments end exactly at the top.
	var sy := height / (seg_h * float(n))
	for i in n:
		var seg := ps.instantiate() as Node3D
		seg.name = "Stalk%d" % i
		seg.scale = Vector3(sc, sc * sy, sc)
		seg.position = Vector3(0, float(i) * seg_h * sy, 0)
		seg.rotation.y = float(i) * 2.1
		v.add_child(seg)
	return true


func _build_vine(v: Node3D) -> void:
	var stem := ObjSvc.mat(ObjSvc.BEAN.darkened(0.12), 0.5)
	var stem_light := ObjSvc.mat(ObjSvc.BEAN, 0.5)
	var leaf := ObjSvc.mat(ObjSvc.BEAN.lightened(0.18), 0.45)
	# One smooth, slightly tapered main stalk.
	ObjSvc.cylinder(v, pole_radius * 0.55, pole_radius * 0.85, height, stem, Vector3(0, height * 0.5, 0))
	ObjSvc.sphere(v, pole_radius * 0.6, stem, Vector3(0, height, 0))
	# A thinner runner spiralling around it (overlapping capsules along a helix read as one smooth vine).
	var steps := maxi(8, int(height / 0.18))
	var prev := Vector3(pole_radius * 1.05, 0.0, 0.0)
	for i in range(1, steps + 1):
		var y := height * float(i) / float(steps)
		var a := y * 2.2
		var p := Vector3(cos(a) * pole_radius * 1.05, y, sin(a) * pole_radius * 1.05)
		var mid := (p + prev) * 0.5
		var seg := ObjSvc.capsule(v, pole_radius * 0.38, (p - prev).length() + pole_radius * 0.5, stem_light, mid)
		var dir := (p - prev).normalized()
		var up := Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
		# Local transform: capsule Y axis along the segment.
		seg.transform = Transform3D(Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, PI * 0.5), mid)
		prev = p
	# Heart-shaped bean leaves on short stems, alternating sides.
	var n_leaves := maxi(3, int(height / 0.7))
	for i in n_leaves:
		var y := (float(i) + 0.6) * height / float(n_leaves)
		var lp := Node3D.new()
		lp.position = Vector3(0, y, 0)
		lp.rotation.y = float(i) * 2.4
		v.add_child(lp)
		ObjSvc.capsule(lp, 0.025, 0.3, stem, Vector3(pole_radius + 0.1, 0.02, 0), Vector3(0, 0, 70))
		ObjSvc.sphere(lp, 0.26, leaf, Vector3(pole_radius + 0.42, 0.1, 0.08), Vector3(1.3, 0.18, 0.85)).rotation_degrees = Vector3(0, 18, -12)
		ObjSvc.sphere(lp, 0.26, leaf, Vector3(pole_radius + 0.42, 0.1, -0.08), Vector3(1.3, 0.18, 0.85)).rotation_degrees = Vector3(0, -18, -12)
		_leaves.append(lp)
		if i % 2 == 1:
			ObjSvc.torus(v, 0.05, 0.085, stem_light, Vector3(-pole_radius - 0.12, y + 0.2, 0), Vector3(0, y * 60.0, 90))


func _process(delta: float) -> void:
	_t += delta
	for i in _leaves.size():
		_leaves[i].rotation.z = sin(_t * 1.8 + i) * 0.12


func get_climb_axis() -> Vector3:
	return global_transform.basis.y.normalized()


func get_pole_radius() -> float:
	return pole_radius


func get_climb_bottom() -> Vector3:
	return global_position


func get_climb_top() -> Vector3:
	return global_transform * Vector3(0, height, 0)


## Closest point on the climb axis to a world position (the player snaps to this plus pole_radius).
func get_closest_point(at: Vector3) -> Vector3:
	var a := get_climb_bottom()
	var ax := get_climb_axis()
	var t := clampf((at - a).dot(ax), 0.0, height)
	return a + ax * t

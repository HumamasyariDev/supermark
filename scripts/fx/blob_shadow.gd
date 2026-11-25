class_name BlobShadow
extends MeshInstance3D
## Soft round contact shadow (D032 / D034, Docs/ART_V3_RETRO.md): a projected quad that sits on the ground straight under
## its target, aligned to the floor normal, shrinking and fading with height so jumps and flyers always read.
## Cheap: one transparent quad and at most one ray per physics frame (static pickups re-cast only after they move).
##
## One line to attach (auto radius from the target's visual bounds):
##   BlobShadow.attach(self)
##   BlobShadow.attach(self, 0.45, 0.5)        # radius in metres, max alpha
## Without the global class cache (fresh checkout): preload("res://scripts/fx/blob_shadow.gd").attach(self)
## RetroLook attaches these automatically to nodes in the gameplay groups that have no contact shadow of their own.

const SCENE_PATH := "res://scenes/fx/BlobShadow.tscn"

@export var radius := 0.5
@export var max_alpha := 0.5
## Above this height (metres) the shadow is hidden.
@export var max_height := 9.0
## Physics layers the ray hits (1 = world).
@export_flags_3d_physics var ground_mask := 1

var target: Node3D
var _exclude: Array[RID] = []
var _last_pos := Vector3(INF, INF, INF)
var _idle := 0
var _has_hit := false


static func attach(t: Node3D, r: float = -1.0, alpha: float = 0.5) -> Node3D:
	if t == null or not is_instance_valid(t):
		return null
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		return null
	var b := scene.instantiate()
	if r <= 0.0:
		r = estimate_radius(t)
	b.set("radius", r)
	b.set("max_alpha", alpha)
	b.set("target", t)
	b.name = "RetroBlobShadow"
	t.add_child(b)
	return b


## Half of the larger horizontal extent of the visible meshes under `t`, clamped to a sensible blob size.
static func estimate_radius(t: Node3D) -> float:
	var best := 0.0
	var inv := t.global_transform.affine_inverse()
	var stack: Array[Node] = [t]
	var visited := 0
	while not stack.is_empty() and visited < 200:
		var n: Node = stack.pop_back()
		visited += 1
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and not String(n.name).to_lower().contains("shadow"):
			var mi := n as MeshInstance3D
			var aabb := mi.get_aabb()
			var xf := inv * mi.global_transform
			var box := xf * aabb
			best = maxf(best, maxf(box.size.x, box.size.z) * 0.5)
		for c in n.get_children():
			stack.append(c)
	if best <= 0.0:
		best = 0.4
	return clampf(best * 0.85, 0.2, 2.6)


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	if target == null and get_parent() is Node3D:
		target = get_parent() as Node3D
	_collect_exclude(target)


func _collect_exclude(n: Node) -> void:
	if n == null:
		return
	if n is CollisionObject3D:
		_exclude.append((n as CollisionObject3D).get_rid())
	if _exclude.size() > 16:
		return
	for c in n.get_children():
		if c != self:
			_collect_exclude(c)


func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	if not target.is_visible_in_tree():
		visible = false
		return
	var pos := target.global_position
	# Static pickups and idle NPCs: re-cast only when moved or every 30 frames.
	if _has_hit and pos.distance_squared_to(_last_pos) < 0.0004:
		_idle += 1
		if _idle < 30:
			return
	_idle = 0
	_last_pos = pos
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.4, pos + Vector3.DOWN * max_height, ground_mask, _exclude)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		visible = false
		_has_hit = false
		return
	_has_hit = true
	var hp: Vector3 = hit["position"]
	var nrm: Vector3 = (hit["normal"] as Vector3).normalized()
	if nrm.y < 0.35:
		nrm = Vector3.UP
	var h := maxf(pos.y - hp.y, 0.0)
	var k := clampf(1.0 - h / max_height, 0.0, 1.0)
	var size := radius * (0.55 + 0.45 * k)
	var x := nrm.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = nrm.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(nrm).normalized()
	global_transform = Transform3D(Basis(x, nrm, z).scaled(Vector3(size, 1.0, size)), hp + nrm * 0.035)
	set_instance_shader_parameter("alpha", max_alpha * (0.3 + 0.7 * k * k))
	visible = true

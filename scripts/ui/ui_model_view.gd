class_name UIModelView
extends SubViewportContainer
const GoldenHatLib := preload("res://scripts/objects/golden_hat.gd")
## A real 3D model rendered into the UI (hat wardrobe, dialog portraits). Own World3D, transparent
## background, warm key light and a soft rim, idle sway. Works while the tree is paused.
##
##   var v := UIModelView.new(); v.custom_minimum_size = Vector2(260, 260)
##   v.set_model("res://assets/characters/bramwell/bramwell.glb", "bust")   # or "full"
##
## Framing: "full" fits the whole model, "bust" frames the top `bust_fraction` of its height.

@export var spin_speed := 0.0
@export var sway := 0.18
@export var bust_fraction := 0.42
@export var yaw_offset := 0.0
@export var silhouette := false:
	set(v):
		silhouette = v
		_apply_silhouette()

var viewport: SubViewport
var camera: Camera3D
var pivot: Node3D
var model: Node3D
var model_path := ""
var _t := 0.0
var _framing := "full"
## "full" framing only: anchor the model's base near the bottom of the view instead of centring it.
var seat_bottom := false
static var _clean: Dictionary = {}
var _env: Environment
var _lights: Array[DirectionalLight3D] = []


## Scales all lights and the ambient (1.0 = default). Light-grey props read better at about 0.7.
func set_exposure(k: float) -> void:
	if _env:
		_env.ambient_light_energy = 0.4 * k
	var base := [1.0, 0.9, 0.4]
	for i in _lights.size():
		_lights[i].light_energy = base[i] * k


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.93, 0.85)
	# critique UI r1: portraits and the Wardrobe beanie ran hot against the worlds (same filmic tonemapper,
	# slightly lower key and ambient)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	var key := DirectionalLight3D.new()
	_lights.append(key)
	key.rotation_degrees = Vector3(-38, 32, 0)
	key.light_color = Color(1.0, 0.9, 0.76)
	key.light_energy = 1.0
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	_lights.append(rim)
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_color = Color(1.0, 0.82, 0.55)
	rim.light_energy = 0.9
	viewport.add_child(rim)
	var fill := DirectionalLight3D.new()
	_lights.append(fill)
	fill.rotation_degrees = Vector3(-10, -70, 0)
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.light_energy = 0.4
	viewport.add_child(fill)
	pivot = Node3D.new()
	viewport.add_child(pivot)
	camera = Camera3D.new()
	camera.fov = 30.0
	camera.current = true
	viewport.add_child(camera)


## Camera finish pass (owner: "a clear hitch" talking to the first NPC): the private deep copy of a speaker's GLB was
## read from disk on the frame the dialog opened (55-140 ms frames in the W1 and hub traces). Talkers now start that
## load on a worker thread when Mak walks up (Talker._on_enter, NPCTalker greet); set_model collects it.
static var _pending: Dictionary = {}


static func prewarm(path: String) -> void:
	if path == "" or _clean.has(path) or _pending.has(path) or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_request(path, "", true, ResourceLoader.CACHE_MODE_IGNORE_DEEP) == OK:
		_pending[path] = true


func set_model(path: String, framing: String = "full") -> bool:
	_framing = framing
	if path == model_path and model != null:
		_frame()
		return true
	if model:
		model.queue_free()
		model = null
	model_path = path
	if path == "" or not ResourceLoader.exists(path):
		return false
	# A private deep copy: gameplay scenes may swap materials on the shared imported meshes (toon
	# passes that need the world's lights), which would render black in this isolated viewport.
	if not _clean.has(path) and _pending.has(path):
		_clean[path] = ResourceLoader.load_threaded_get(path)
		_pending.erase(path)
	if not _clean.has(path):
		_clean[path] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var ps := _clean[path] as PackedScene
	if ps == null:
		return false
	model = ps.instantiate() as Node3D
	if model == null:
		return false
	pivot.add_child(model)
	# Imported glTF faces +Z: show its front to the camera on +Z.
	model.rotation.y = yaw_offset
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_silhouette()
	_frame()
	return true


## Mr. Mak's portrait: show the beanie or swap in the real top hat GLB on the head_top bone
## (same socket offsets as the player's MakAnimator.set_hat).
func apply_mak_hat(id: String) -> void:
	if model == null:
		return
	var beanie: Node3D = null
	for n in model.find_children("*", "Node3D", true, false):
		if str(n.name).to_lower().contains("beanie"):
			beanie = n as Node3D
			break
	var socket := model.find_child("UITopHatSocket", true, false) as Node3D
	if GoldenHatLib.is_top_hat(id) and socket == null:
		var skels := model.find_children("*", "Skeleton3D", true, false)
		var path := "res://assets/characters/mak/mak_tophat.glb"
		if not skels.is_empty() and ResourceLoader.exists(path) and (skels[0] as Skeleton3D).find_bone("head_top") >= 0:
			var att := BoneAttachment3D.new()
			att.name = "UITopHatSocket"
			att.bone_name = "head_top"
			(skels[0] as Skeleton3D).add_child(att)
			var h := (load(path) as PackedScene).instantiate() as Node3D
			att.add_child(h)
			h.position = Vector3(0.0, -0.0825, -0.01)
			h.rotation_degrees = Vector3(-5.0, 0.0, 8.0)
			socket = att
	if socket:
		socket.visible = GoldenHatLib.is_top_hat(id)
		GoldenHatLib.gild(socket, GoldenHatLib.is_golden(id))
	if beanie:
		beanie.visible = not GoldenHatLib.is_top_hat(id) or socket == null
	_frame()


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	if n is VisualInstance3D and not (n is Light3D):
		var b := xf * (n as VisualInstance3D).get_aabb()
		box = b
		first = false
	for c in n.get_children():
		if c is Node3D:
			var cb := _aabb(c, xf * (c as Node3D).transform)
			if cb.size != Vector3.ZERO:
				box = cb if first else box.merge(cb)
				first = false
	return box


func _frame() -> void:
	if model == null:
		return
	var box := _aabb(model, model.transform)
	if box.size == Vector3.ZERO:
		return
	var h := box.size.y
	var center := box.get_center()
	var target := center
	var frame_h := h
	if _framing == "bust":
		frame_h = h * bust_fraction
		target = Vector3(center.x, box.end.y - frame_h * 0.5, center.z)
	var frame_w := maxf(box.size.x, box.size.z)
	var aspect := size.x / maxf(1.0, size.y) if size.y > 0 else 1.0
	var half := maxf(frame_h * 0.5, frame_w * 0.5 / maxf(0.5, aspect)) * 1.12
	if seat_bottom and _framing == "full":
		# the model's base sits 8% above the view's bottom edge (a hat seated on its cushion)
		target = Vector3(center.x, box.position.y + half * 0.84, center.z)
	var dist := half / tan(deg_to_rad(camera.fov * 0.5))
	camera.position = target + Vector3(0, frame_h * 0.06, dist + box.size.z * 0.5)
	camera.look_at(target, Vector3.UP)
	camera.near = maxf(0.01, dist * 0.05)
	camera.far = dist * 6.0 + 10.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and model:
		_frame.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	if pivot:
		if spin_speed != 0.0:
			pivot.rotation.y += delta * spin_speed
		else:
			pivot.rotation.y = sin(_t * 0.9) * sway


func _apply_silhouette() -> void:
	if model == null:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if silhouette:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0.23, 0.14, 0.08, 0.92)
			m.material_override = mat
		else:
			m.material_override = null

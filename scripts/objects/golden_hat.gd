extends Node
## (No class_name: other scripts preload it as GoldenHatLib, so no global class cache refresh is needed.)
## The Golden Top Hat (completion pass, boss reward): the same top hat mesh in a gold material with a little sparkle.
## Mak wears the plain top hat by default (hero v2), so beating the Wolf now awards this variant (hat id
## "golden_top_hat", Game.HATS). The player script shows its top hat for any id other than "beanie"; this node,
## attached to the player by Game, turns that hat gold while the golden id is worn and back when it is not.
## Static helpers also gild the Wardrobe card, the dialog portrait and the boss's flying reward hat.

const ID := "golden_top_hat"
const GOLD := Color(1.0, 0.76, 0.22)

static var _mat: StandardMaterial3D

var _player: Node
var _gilded: Node3D


static func is_golden(id: String) -> bool:
	return id == ID


## True for any id that shows the top hat mesh (plain or golden).
static func is_top_hat(id: String) -> bool:
	return id == "top_hat" or id == ID


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = GOLD
		_mat.metallic = 0.85
		_mat.roughness = 0.3
		_mat.metallic_specular = 0.8
		_mat.emission_enabled = true
		_mat.emission = Color(0.45, 0.3, 0.05)
		_mat.emission_energy_multiplier = 0.35
		_mat.rim_enabled = true
		_mat.rim = 0.4
		_mat.rim_tint = 0.6
	return _mat


## Gilds (or restores) every mesh under `root`. `override` uses material_override (wins over the player's own
## surface tuning); otherwise per-surface overrides, so a UI silhouette (material_override) still covers it.
static func gild(root: Node, on: bool, override: bool = true) -> void:
	if root == null:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if override:
			if on:
				if not mi.has_meta("pre_gold"):
					mi.set_meta("pre_gold", mi.material_override)
				mi.material_override = material()
			elif mi.has_meta("pre_gold"):
				mi.material_override = mi.get_meta("pre_gold") as Material
				mi.remove_meta("pre_gold")
		elif mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, material() if on else null)


## A few twinkling glints around the hat (ObjGlints, the pickup sparkle).
static func sparkle(root: Node3D, on: bool, radius: float = 0.22, at: Vector3 = Vector3(0, 0.12, 0)) -> void:
	if root == null:
		return
	var old := root.get_node_or_null("GoldSparkle")
	if not on:
		if old:
			old.queue_free()
		return
	if old:
		return
	var gl := ObjGlints.new()
	gl.name = "GoldSparkle"
	gl.count = 3
	gl.radius = radius
	gl.size = 0.12
	gl.period = 1.6
	gl.color = Color(1.0, 0.9, 0.55)
	gl.center = at
	root.add_child(gl)


## Attached under the player by Game: follows the player's hat_changed signal. The hero kit and RetroLook (which
## swaps materials asynchronously on new meshes) can both land after the first apply, so while the golden hat is
## worn the gold is re-checked twice a second (one cheap material compare per hat mesh).
var _want := false
var _t := 0.0


func _ready() -> void:
	_player = get_parent()
	if _player == null or not _player.has_signal("hat_changed"):
		queue_free()
		return
	_player.connect("hat_changed", _on_hat)
	_on_hat.call_deferred(String(_player.get("hat")))


func _process(delta: float) -> void:
	if not _want:
		return
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	var hat := _hat_node()
	if hat == null:
		return
	var ok := hat == _gilded
	if ok:
		for n in hat.find_children("*", "MeshInstance3D", true, false):
			if (n as MeshInstance3D).material_override != material():
				ok = false
				break
	if not ok:
		_on_hat(ID)


func _hat_node() -> Node3D:
	var parts: Variant = _player.get("v2_parts")
	if parts is Dictionary and (parts as Dictionary).has("top_hat"):
		return (parts as Dictionary)["top_hat"] as Node3D
	return _player.find_child("TopHatSocket", true, false) as Node3D


func _on_hat(id: String) -> void:
	_want = is_golden(id)
	_t = 0.0
	var hat := _hat_node()
	if hat == null:
		return
	if _gilded != null and is_instance_valid(_gilded) and _gilded != hat:
		gild(_gilded, false)
		sparkle(_gilded, false)
	if not _want:
		# Drop RetroLook's or our own override memory cleanly: restore what was there before the gold.
		gild(hat, false)
		sparkle(hat, false)
		_gilded = null
		return
	for n in hat.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override != material() and mi.has_meta("pre_gold"):
			# Something replaced the gold since (RetroLook's async pass): remember that one instead.
			mi.set_meta("pre_gold", mi.material_override)
	gild(hat, true)
	sparkle(hat, true)
	_gilded = hat

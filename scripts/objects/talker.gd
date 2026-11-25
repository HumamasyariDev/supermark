class_name Talker
extends StaticBody3D
## Shared base for Sign and NPCTalker: shows a bobbing parchment speech bubble when the player is near and opens
## UI.show_dialog(lines, speaker) on the "interact" action (or automatically when auto_talk is on).
## Round 2 (critique objects r1):
## - the button glyph comes from the HUD prompt (UI.show_prompt("interact", "Talk")), so pads and rebound keys show the
##   right button; the in-world bubble is parchment with an ink outline and an ink ellipsis, drawn over the scene;
## - a closing press never reopens the dialog: the talker waits for the dialog to finish, then for interact to be
##   released (fresh press), and ignores input while UI.is_input_blocked();
## - when several talk zones overlap, only the talker nearest the player answers and shows its bubble;
## - the dialog closes when Mak walks away (talk_radius + 1.5 m).

signal talked(lines: Array)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var speaker: String = ""
@export_multiline var lines: PackedStringArray = PackedStringArray(["Hello there!"])
@export var talk_radius: float = 2.2
@export var auto_talk: bool = false
## Text in the in-world bubble (the button glyph is shown by the HUD prompt).
@export var prompt_text: String = "..."
## HUD prompt verb.
@export var prompt_verb: String = "Talk"

const PARCHMENT := Color(0.953, 0.902, 0.769)  # #F3E6C4
const INK := Color(0.231, 0.141, 0.086)  # #3B2416

## The talker that currently owns the HUD prompt (one at a time).
static var _prompt_owner: Talker = null

var player_near: Node3D = null
var _t := 0.0
var _prompt: Node3D
var _zone: Area3D
var _cool := 0.0
var _need_release := false
var _dialog_mine := false
var _was_blocked := false
var _prompt_shown := false


func _ready() -> void:
	add_to_group("talker")
	collision_layer = ObjSvc.L_WORLD
	collision_mask = 0
	_zone = ObjSvc.make_area(self, ObjSvc.sphere_shape(talk_radius), ObjSvc.L_TRIGGER, ObjSvc.L_PLAYER, Vector3(0, 1.0, 0), "TalkZone")
	_zone.body_entered.connect(_on_enter)
	_zone.body_exited.connect(_on_exit)
	_prompt = Node3D.new()
	_prompt.name = "Prompt"
	add_child(_prompt)
	_prompt.position = _prompt_anchor()
	_build_bubble()
	_prompt.scale = Vector3.ONE * 0.01
	_prompt.visible = false
	var ui := ObjSvc.autoload("UI")
	if ui != null and ui.has_signal("dialog_finished"):
		ui.connect("dialog_finished", _on_dialog_finished)
	if ui != null and ui.has_signal("device_changed"):
		ui.connect("device_changed", func(_d: String) -> void:
			if _prompt_owner == self:
				_show_hud_prompt(true))


## Parchment speech bubble with an ink outline (inverted hull), a tail and an ink ellipsis. Unshaded, so it never
## blows out against a bright sky, and drawn after the scene so it reads in front of foliage.
func _build_bubble() -> void:
	var paper := StandardMaterial3D.new()
	paper.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paper.albedo_color = PARCHMENT
	paper.render_priority = 2
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = INK
	ink.cull_mode = BaseMaterial3D.CULL_FRONT
	ink.render_priority = 1
	var body := Node3D.new()
	body.name = "Bubble"
	_prompt.add_child(body)
	ObjSvc.sphere(body, 0.2, paper, Vector3.ZERO, Vector3(1.45, 1.0, 0.42))
	ObjSvc.sphere(body, 0.2, ink, Vector3.ZERO, Vector3(1.45, 1.0, 0.42) * 1.1)
	ObjSvc.cone(body, 0.075, 0.17, paper, Vector3(-0.1, -0.21, 0), Vector3(180, 0, 18))
	ObjSvc.cone(body, 0.075, 0.17, ink, Vector3(-0.1, -0.215, 0), Vector3(180, 0, 18)).scale = Vector3(1.25, 1.12, 1.25)
	var l := ObjSvc.label(body, prompt_text, Vector3(0, 0.035, 0.1), 96, INK, true)
	l.outline_size = 0
	l.no_depth_test = true
	l.render_priority = 4
	l.name = "Glyph"
	# The whole bubble faces the camera (the label already billboards).
	body.set_meta("billboard", true)


## Local position of the bubble (above the head). NPCTalker anchors it to the head bone.
func _prompt_anchor() -> Vector3:
	return Vector3(0, _prompt_height(), 0)


func _prompt_height() -> float:
	return 2.2


func _talk_event() -> String:
	return "object_sign_read"


func _on_enter(body: Node) -> void:
	if not ObjSvc.is_player(body):
		return
	player_near = body as Node3D
	prewarm_portrait()
	# A little "hello" wiggle of the whole visual.
	var v := get_node_or_null("Visual") as Node3D
	if v:
		var tw := create_tween()
		tw.tween_property(v, "scale", Vector3(1.06, 0.94, 1.06), 0.08)
		tw.tween_property(v, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if auto_talk and _cool <= 0.0 and _is_nearest():
		talk()


## Camera finish pass: start loading the dialog portrait model off the main thread before the talk (see UIModelView).
func prewarm_portrait() -> void:
	if speaker == "":
		return
	var info := UISpeakers.info(speaker)
	if info.size() > 0 and String(info[0]) != "":
		UIModelView.prewarm(String(info[0]))


func _on_exit(body: Node) -> void:
	if body != player_near:
		return
	player_near = null
	_set_prompt(false)


func _set_prompt(on: bool) -> void:
	if on == _prompt_shown:
		return
	_prompt_shown = on
	if on:
		_prompt.visible = true
		var tw := create_tween()
		tw.tween_property(_prompt, "scale", Vector3.ONE * 1.12, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_prompt, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_SINE)
		_show_hud_prompt(true)
	else:
		var tw2 := create_tween()
		tw2.tween_property(_prompt, "scale", Vector3.ONE * 0.01, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw2.tween_callback(func() -> void:
			if not _prompt_shown:
				_prompt.visible = false)
		_show_hud_prompt(false)


func _show_hud_prompt(on: bool) -> void:
	if on:
		_prompt_owner = self
		ObjSvc.call_on("UI", "show_prompt", ["interact", prompt_verb])
	elif _prompt_owner == self:
		_prompt_owner = null
		ObjSvc.call_on("UI", "hide_prompt")


## True when this talker is the nearest one whose zone contains the player.
func _is_nearest() -> bool:
	if player_near == null or not is_instance_valid(player_near):
		return false
	var pp := ObjSvc.body_pos(player_near)
	var mine := pp.distance_squared_to(global_position)
	for n in get_tree().get_nodes_in_group("talker"):
		if n == self or not (n is Talker):
			continue
		var o := n as Talker
		if o.player_near != null and pp.distance_squared_to(o.global_position) < mine:
			return false
	return true


func _ui_blocked() -> bool:
	if ObjSvc.can("UI", "is_input_blocked"):
		return bool(ObjSvc.call_on("UI", "is_input_blocked"))
	if ObjSvc.can("UI", "is_dialog_open"):
		return bool(ObjSvc.call_on("UI", "is_dialog_open"))
	return false


func _on_dialog_finished() -> void:
	if _dialog_mine:
		_dialog_mine = false
		_cool = maxf(_cool, 0.35)
		_need_release = true


func _process(delta: float) -> void:
	_t += delta
	_cool = maxf(0.0, _cool - delta)
	if _need_release and not (InputMap.has_action("interact") and Input.is_action_pressed("interact")):
		_need_release = false
	var blocked := _ui_blocked()
	var nearest := player_near != null and _is_nearest()
	_set_prompt(nearest and not blocked)
	if _prompt.visible:
		_prompt.position = _prompt_anchor() + Vector3(0, sin(_t * 3.0) * 0.05, 0)
		var b := _prompt.get_node_or_null("Bubble") as Node3D
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if b and cam:
			var to := cam.global_position - b.global_position
			to.y = 0.0
			if to.length() > 0.01:
				# M3b: keep the pop-in scale. Setting a unit global basis cancelled the parent's 0.01 -> 1.12 tween, so
				# the next frame multiplied the bubble by the scale ratio (one frame of a ~30x bubble filling the screen
				# whenever a prompt appeared, seen in the NPC station clip).
				b.basis = Basis.looking_at(_prompt.global_basis.orthonormalized().inverse() * -to.normalized(), Vector3.UP)
			b.rotation.z = sin(_t * 2.1) * 0.06
	# Walked away mid-conversation: close our dialog with the UI's own close animation.
	if _dialog_mine and player_near == null:
		var p := ObjSvc.get_player()
		if p == null or ObjSvc.body_pos(p).distance_to(global_position) > talk_radius + 1.5:
			_close_dialog()
	var pressed := InputMap.has_action("interact") and Input.is_action_just_pressed("interact")
	# A press in the same frame the dialog closed (or while any UI owns input) never reopens it.
	if pressed and nearest and not blocked and not _was_blocked and not _need_release and _cool <= 0.0:
		talk()
	_was_blocked = blocked


func _close_dialog() -> void:
	_dialog_mine = false
	var ui := ObjSvc.autoload("UI")
	if ui == null:
		return
	var d: Variant = ui.get("dialog")
	if d is Object and is_instance_valid(d) and (d as Object).has_method("close") and bool(ObjSvc.call_on("UI", "is_dialog_open")):
		(d as Object).call("close")


func talk() -> void:
	_cool = 1.0
	var arr: Array = []
	for s in lines:
		arr.append(s)
	ObjSvc.feedback(_talk_event(), global_position + Vector3(0, 1.2, 0), {"speaker": speaker}, "talk_blip")
	_dialog_mine = ObjSvc.show_dialog(arr, speaker)
	if not _dialog_mine and ObjSvc.can("UI", "is_dialog_open"):
		_dialog_mine = bool(ObjSvc.call_on("UI", "is_dialog_open"))
	_set_prompt(false)
	talked.emit(arr)


func _exit_tree() -> void:
	if _prompt_owner == self:
		_prompt_owner = null
		ObjSvc.call_on("UI", "hide_prompt")

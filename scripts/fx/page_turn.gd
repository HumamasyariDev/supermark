class_name PageTurn
extends CanvasLayer
## Storybook page-turn transition. The outgoing frame is snapshotted onto a page that curls
## away from the bottom-right corner, revealing the new scene underneath.
##
## Simplest use (for example in the Router):
##   await PageTurn.run(get_tree(), func(): get_tree().change_scene_to_file(path))
## Manual use:
##   var pt := PageTurn.new(); get_tree().root.add_child(pt)
##   await pt.capture()          # freezes the current frame on the page (covers the screen)
##   ...change scene, wait a frame or two...
##   await pt.reveal(1.0)        # curls the page away, then the layer frees itself
## Optional: pt.reveal_alpha = 1.0 shows a dark walnut backdrop instead of the live scene.

signal covered
signal finished

const SHADER := preload("res://assets/shaders/page_turn.gdshader")

var duration := 1.0
var reveal_alpha := 0.0
var free_after := true
var _rect: ColorRect
var _mat: ShaderMaterial


func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


static func run(tree: SceneTree, change: Callable, seconds := 1.0) -> void:
	var pt := PageTurn.new()
	tree.root.add_child(pt)
	await pt.capture()
	change.call()
	await tree.process_frame
	await tree.process_frame
	await pt.reveal(seconds)


func capture() -> void:
	if _rect == null:
		await ready
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var tex := ImageTexture.create_from_image(img)
	set_page_texture(tex)
	covered.emit()


func set_page_texture(tex: Texture2D) -> void:
	var size := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("page_texture", tex)
	_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_mat.set_shader_parameter("progress", 0.0)
	_mat.set_shader_parameter("reveal_alpha", reveal_alpha)
	_rect.visible = true


func set_progress(p: float) -> void:
	_mat.set_shader_parameter("progress", p)


func reveal(seconds := -1.0) -> void:
	if seconds <= 0.0:
		seconds = duration
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(set_progress, 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_rect.visible = false
	finished.emit()
	if free_after:
		queue_free()

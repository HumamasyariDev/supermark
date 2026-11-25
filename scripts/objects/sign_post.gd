class_name SignPost
extends Talker
## A chunky wooden signpost with a painted board. Read with "interact".

@export var board_text: String = "Mak Manor"
@export var board_color: Color = Color(0.86, 0.66, 0.4)
## Critique objects r1: shipped signs were 28 primitives each. The generated W1 signpost (Tripo, blank arrow
## boards) is the default look; the board text is painted on with Label3Ds on both faces of the boards.
@export var use_default_mesh: bool = true
@export var default_mesh_scale: float = 0.85

const DEFAULT_MESH := "res://assets/props/w1/signpost/signpost.glb"


func _ready() -> void:
	ObjSvc.ensure_npc_life_auto(self)
	var slot := get_node_or_null("Visual")
	if visual_scene == null and use_default_mesh and ResourceLoader.exists(DEFAULT_MESH) and (slot == null or slot.get_child_count() == 0):
		visual_scene = load(DEFAULT_MESH) as PackedScene
		visual_scale = default_mesh_scale
	super._ready()
	ObjSvc.add_shape(self, ObjSvc.box_shape(Vector3(1.4, 1.9, 0.3)), Vector3(0, 0.95, 0))
	var v := ObjSvc.ensure_visual(self)
	if ObjSvc.visual_has_content(v) and visual_scene != null and visual_scene.resource_path == DEFAULT_MESH:
		_paint_boards(v)
	if not ObjSvc.visual_has_content(v):
		var wood := ObjSvc.mat(Color(0.55, 0.36, 0.2), 0.8)
		ObjSvc.cylinder(v, 0.09, 0.12, 1.5, wood, Vector3(0, 0.75, 0))
		ObjSvc.soft_box(v, Vector3(1.4, 0.75, 0.12), ObjSvc.mat(board_color, 0.75), Vector3(0, 1.45, 0.05), Vector3(0, 0, 3), 0.05)
		ObjSvc.soft_box(v, Vector3(1.5, 0.12, 0.16), wood, Vector3(0, 1.85, 0.05), Vector3(0, 0, 3), 0.05)
		var nail := ObjSvc.mat(ObjSvc.IRON, 0.4, 0.8)
		ObjSvc.sphere(v, 0.03, nail, Vector3(-0.6, 1.72, 0.13))
		ObjSvc.sphere(v, 0.03, nail, Vector3(0.6, 1.78, 0.13))
		var l := ObjSvc.label(v, board_text, Vector3(0, 1.45, 0.12), 56, Color(0.3, 0.15, 0.07), false)
		l.rotation_degrees = Vector3(0, 0, 3)
		l.outline_size = 0
		l.width = 260.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# A tuft of grass at the foot so it sits in the world.
		var grass := ObjSvc.mat(ObjSvc.MEADOW, 0.6)
		for i in 5:
			ObjSvc.cone(v, 0.06, 0.3, grass, Vector3(cos(i * 1.3) * 0.18, 0.12, sin(i * 1.3) * 0.18), Vector3(cos(i) * 15, 0, sin(i) * 15))


func _prompt_height() -> float:
	return 2.4 if visual_scene == null else 2.375 * visual_scale + 0.35


## Board text on the generated signpost's upper arrow board. Measured in Blender (loose parts, PCA): the board is
## centred at glTF (0.655, 1.734, -0.161), normal (0.26, 0, 0.965), about 0.9 x 0.35 m. After the 180-degree flip the
## text is printed on both faces, in ink, in the storybook font.
## Critique objects r1 re-run: "Mak Manor" ran over the board's top and bottom edges, and the shaded back of the boards
## read as muddy olive. The text is now fitted to the board (one line, or two lines split at the middle space,
## whichever allows the larger font), 2 mm off the face, and the post's materials keep a warm floor in shadow.
const BOARD_CENTER := Vector3(-0.655, 1.734, 0.161)
const BOARD_NORMAL := Vector3(-0.26, 0.0, -0.965)
const BOARD_SIZE := Vector2(0.9, 0.35)
const BOARD_TEXT_AREA := Vector2(0.74, 0.25)  # inside the arrow tip, the nails and the bevel


func _paint_boards(v: Node3D) -> void:
	var sc := visual_scale
	var n := BOARD_NORMAL.normalized()
	var f := "res://assets/fonts/cherryswash/CherrySwash-Bold.ttf"
	var font: Font = load(f) as Font if ResourceLoader.exists(f) else ThemeDB.fallback_font
	var px := 0.004 * sc
	var fit := fit_text(board_text, font, BOARD_TEXT_AREA * sc, px)
	for side in [1.0, -1.0]:
		var nn: Vector3 = n * side
		# The board face sits about 4.5 cm off its centre line; print 2 mm above each face.
		var l := ObjSvc.label(v, String(fit["text"]), (BOARD_CENTER + nn * 0.045) * sc + nn * 0.002, int(fit["size"]), Color("3b2416"), false)
		l.name = "BoardText" if side > 0 else "BoardTextBack"
		l.outline_size = 0
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.line_spacing = -float(fit["size"]) * 0.18
		l.pixel_size = px
		l.font = font
		l.rotation = Vector3(0, atan2(nn.x, nn.z), 0)
	_warm_shadow_side(v)


## Largest font size (px) at which `text` fits `area` (metres) with `pixel_size`, on one line or two lines split at
## the space nearest the middle. Returns {"text": String (with a newline when split), "size": int}.
static func fit_text(text: String, font: Font, area: Vector2, pixel_size: float) -> Dictionary:
	var options: Array = [text]
	var spaces: Array[int] = []
	for i in text.length():
		if text[i] == " ":
			spaces.append(i)
	if not spaces.is_empty():
		var best := spaces[0]
		for i in spaces:
			if absi(i * 2 - text.length()) < absi(best * 2 - text.length()):
				best = i
		options.append(text.substr(0, best) + "
" + text.substr(best + 1))
	var out := {"text": text, "size": 16}
	var best_size := 0
	for opt in options:
		var lines: PackedStringArray = String(opt).split("
")
		# Measure at 100 px and scale (glyph metrics are close to linear).
		var w := 0.0
		for ln in lines:
			w = maxf(w, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x)
		var h := font.get_height(100) * (float(lines.size()) - 0.18 * float(lines.size() - 1))
		var size_w := area.x / pixel_size / maxf(w, 1.0) * 100.0
		var size_h := area.y / pixel_size / maxf(h, 1.0) * 100.0
		var size := int(floor(minf(size_w, size_h)))
		if size > best_size:
			best_size = size
			out = {"text": opt, "size": clampi(size, 12, 96)}
	return out


func _warm_shadow_side(v: Node3D) -> void:
	for n in v.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as StandardMaterial3D
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.emission_enabled = true
			m.emission = Color(1, 1, 1)
			m.emission_texture = src.albedo_texture
			m.emission_energy_multiplier = 0.07
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY if src.albedo_texture == null else BaseMaterial3D.EMISSION_OP_ADD
			mi.set_surface_override_material(i, m)

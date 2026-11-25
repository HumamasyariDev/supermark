class_name StorybookPortal
extends StaticBody3D
## A giant storybook standing open on a carved walnut lectern. Pages flip and glow; jumping into the pages
## opens mission select (UI.open_mission_select(world_id)) or, without a UI, Router.enter_world(world_id).
## Locked books stay shut with a brass plate showing the truffle requirement.
## With a generated lectern (`visual_scene`), a book's worth of glowing pages is laid on the reading desk
## (`page_anchor`, `page_tilt_deg`; measured from the mesh bounds when left at zero) and turns itself: each sheet
## bends as it turns (an inner and an outer half, the outer half lagging), and a soft glow card rises from the pages.

signal entered(world_id: String)
signal unlocked(world_id: String)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
@export var world_id: String = "W1"
@export var book_title: String = "The Three Little Pigs"
@export var required_truffles: int = 0
@export var cover_color: Color = Color(0.55, 0.11, 0.17)
@export var accent_color: Color = Color(1.0, 0.76, 0.22)
@export var page_glow: Color = Color(1.0, 0.88, 0.55)
@export var scale_factor: float = 1.0
## Off only in tests/labs: emit `entered` without opening mission select or changing scene.
@export var route_on_enter: bool = true
## Generated lectern only: where the spine of the turning pages sits (local, metres) and the desk slope.
## Zero = measured from the mesh: centre top, slightly below the highest point.
@export var page_anchor: Vector3 = Vector3.ZERO
@export var page_tilt_deg: float = 22.0
@export var page_size: Vector2 = Vector2(0.5, 0.7)

var is_open := false
var _t := 0.0
var _visual: Node3D
var _book: Node3D
var _cover_l: Node3D
var _cover_r: Node3D
var _flip_pages: Array[Node3D] = []
var _flip_outer: Array[Node3D] = []
var _book_base_y := 2.2
var _generated := false
var _page_glow_card: MeshInstance3D
var _turn_sfx_phase: Array[float] = []
var _plate: Node3D
var _plate_label: Label3D
var _glow: OmniLight3D
var _swirl: GPUParticles3D
var _zone: Area3D
var _cooldown := 0.0


func _ready() -> void:
	ObjSvc.ensure_npc_life_auto(self)
	add_to_group("storybook_portal")
	collision_layer = ObjSvc.L_WORLD
	collision_mask = 0
	var s := scale_factor
	ObjSvc.add_shape(self, ObjSvc.box_shape(Vector3(1.6, 2.2, 1.2) * s), Vector3(0, 1.1, 0) * s)
	_visual = ObjSvc.ensure_visual(self)
	if not ObjSvc.visual_has_content(_visual):
		_build_placeholder()
	else:
		_build_generated_pages()
	if _book:
		_book_base_y = _book.position.y
	_zone = ObjSvc.make_area(self, ObjSvc.box_shape(Vector3(3.0, 1.2, 2.0) * s), ObjSvc.L_TRIGGER, ObjSvc.L_PLAYER, Vector3(0, 3.3, -0.1) * s, "PageZone")
	_zone.body_entered.connect(_on_zone_body)
	_glow = OmniLight3D.new()
	_glow.light_color = page_glow
	_glow.omni_range = 6.0 * s
	_glow.position = Vector3(0, 3.2, -0.6) * s
	add_child(_glow)
	_swirl = ObjSvc.sparkles(self, page_glow, 40, 1.2 * s, 0.16, 2.0, 0.9)
	_swirl.position = Vector3(0, 3.0, 0) * s
	_set_open(_check_unlocked(), false)
	_t = randf() * 10.0


func _build_placeholder() -> void:
	var s := scale_factor
	var wood := ObjSvc.mat(ObjSvc.WALNUT, 0.6)
	var dark := ObjSvc.mat(ObjSvc.WALNUT_DARK, 0.7)
	var brass := ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.8)
	var root := Node3D.new()
	root.scale = Vector3.ONE * s
	_visual.add_child(root)
	# Carved lectern: a round plinth, a turned column with rings and a slanted reading desk.
	ObjSvc.cylinder(root, 0.85, 1.0, 0.3, dark, Vector3(0, 0.15, 0))
	ObjSvc.torus(root, 0.75, 0.95, brass, Vector3(0, 0.32, 0))
	ObjSvc.cylinder(root, 0.32, 0.45, 1.4, wood, Vector3(0, 1.0, 0))
	for y in [0.55, 1.05, 1.55]:
		ObjSvc.torus(root, 0.3, 0.45, dark, Vector3(0, y, 0))
	ObjSvc.sphere(root, 0.42, wood, Vector3(0, 1.75, 0), Vector3(1.6, 0.5, 1.2))
	ObjSvc.soft_box(root, Vector3(2.4, 0.16, 1.5), wood, Vector3(0, 2.05, 0), Vector3(-22, 0, 0), 0.07)
	# The book pivots on the desk.
	_book = Node3D.new()
	_book.name = "Book"
	_book.position = Vector3(0, 2.2, 0)
	_book.rotation_degrees = Vector3(-22, 0, 0)
	root.add_child(_book)
	var cover := ObjSvc.mat(cover_color, 0.55)
	var paper := ObjSvc.mat(ObjSvc.PAPER, 0.85, 0.0, page_glow, 0.35)
	var gold := ObjSvc.mat(accent_color, 0.3, 0.8, accent_color, 0.2)
	# Spine.
	ObjSvc.capsule(_book, 0.12, 1.5, cover, Vector3(0, 0.02, 0), Vector3(90, 0, 0))
	# Left and right page blocks with covers (the covers pivot at the spine).
	_cover_l = Node3D.new()
	_book.add_child(_cover_l)
	ObjSvc.soft_box(_cover_l, Vector3(1.1, 0.06, 1.5), cover, Vector3(-0.58, 0, 0), Vector3.ZERO, 0.03)
	ObjSvc.box(_cover_l, Vector3(1.0, 0.16, 1.38), paper, Vector3(-0.55, 0.1, 0))
	ObjSvc.box(_cover_l, Vector3(0.9, 0.012, 0.06), gold, Vector3(-0.58, -0.035, 0.6))
	_cover_r = Node3D.new()
	_book.add_child(_cover_r)
	ObjSvc.soft_box(_cover_r, Vector3(1.1, 0.06, 1.5), cover, Vector3(0.58, 0, 0), Vector3.ZERO, 0.03)
	ObjSvc.box(_cover_r, Vector3(1.0, 0.16, 1.38), paper, Vector3(0.55, 0.1, 0))
	ObjSvc.box(_cover_r, Vector3(0.9, 0.012, 0.06), gold, Vector3(0.58, -0.035, 0.6))
	# Gold corner guards.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			ObjSvc.sphere(_cover_l if sx < 0 else _cover_r, 0.07, gold, Vector3(sx * 1.08, 0, sz * 0.7))
	# Ink "story lines" printed on the right page.
	var ink := ObjSvc.mat(Color(0.3, 0.2, 0.15), 0.9)
	for i in 6:
		ObjSvc.box(_cover_r, Vector3(0.7 - (i % 3) * 0.12, 0.005, 0.04), ink, Vector3(0.55, 0.185, -0.45 + i * 0.16))
	var title := ObjSvc.label(_cover_l, book_title, Vector3(-0.55, 0.19, 0.0), 40, Color(0.35, 0.18, 0.1), false)
	title.rotation_degrees = Vector3(-90, 0, 0)
	title.width = 180.0
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Flipping pages: thin sheets that bend as they arc over the spine.
	var sheet := ObjSvc.unique_mat(ObjSvc.PAPER, 0.9, 0.0, page_glow, 0.25)
	sheet.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 3:
		_make_sheet(_book, Vector3(0, 0.2, 0), 1.0, 1.36, sheet)
	# Lock plate on the lectern front: a brass plaque with a truffle icon and the requirement.
	_plate = Node3D.new()
	_plate.position = Vector3(0, 1.15, 0.47)
	root.add_child(_plate)
	ObjSvc.soft_box(_plate, Vector3(0.75, 0.42, 0.06), brass, Vector3.ZERO, Vector3.ZERO, 0.03)
	ObjSvc.sphere(_plate, 0.09, ObjSvc.mat(ObjSvc.GOLD, 0.3, 0.8, ObjSvc.GOLD, 0.4), Vector3(-0.2, 0, 0.06))
	_plate_label = ObjSvc.label(_plate, "x %d" % required_truffles, Vector3(0.1, 0, 0.05), 72, Color(0.3, 0.15, 0.05), false)
	_plate_label.outline_size = 0
	# Chain wrapped around the closed book (only while locked).
	var chain := Node3D.new()
	chain.name = "Chain"
	_book.add_child(chain)
	var iron := ObjSvc.mat(ObjSvc.IRON, 0.4, 0.9)
	for i in 7:
		ObjSvc.torus(chain, 0.04, 0.09, iron, Vector3(0.0, 0.42, -0.66 + i * 0.22), Vector3(90 if i % 2 else 0, 0, 90))
	ObjSvc.soft_box(chain, Vector3(0.26, 0.3, 0.12), ObjSvc.mat(ObjSvc.BRASS, 0.3, 0.9), Vector3(0, 0.25, 0.8), Vector3.ZERO, 0.04)
	ObjSvc.torus(chain, 0.06, 0.1, iron, Vector3(0, 0.44, 0.8), Vector3(90, 0, 0))


## One turning sheet: a pivot on the spine holding the inner half, and a second pivot at the middle holding the
## outer half, so the page can curl while it turns.
## Critique objects r1 re-run: the lectern's turning page was a rigid blank card and covered the printed spread. A
## printed sheet (`printed_tex`, the spread's own SubViewport art) is a strip of 6 hinged segments that bends along
## its length; its front shows the page it lies on and its back the page it lands on, mapped exactly like the spread
## below (spread size `spread`), so a resting sheet is invisible against the print. A soft shadow sweeps over the
## spread while a sheet is in the air.
const SHEET_SEGS := 6
var _flip_segs: Array = []  # per sheet: Array[Node3D] of the hinge pivots after the first segment
var _page_shadow: MeshInstance3D
var _page_shadow_mat: StandardMaterial3D
var _sheet_w := 1.0


func _make_sheet(parent: Node3D, at: Vector3, w: float, d: float, m: Material, printed_tex: Texture2D = null, spread: Vector2 = Vector2.ZERO) -> void:
	var pivot := Node3D.new()
	pivot.position = at
	parent.add_child(pivot)
	_sheet_w = w
	if printed_tex == null or spread == Vector2.ZERO:
		ObjSvc.box(pivot, Vector3(w * 0.5, 0.008, d), m, Vector3(w * 0.25, 0, 0))
		var outer := Node3D.new()
		outer.position = Vector3(w * 0.5, 0, 0)
		pivot.add_child(outer)
		ObjSvc.box(outer, Vector3(w * 0.5, 0.008, d * 0.99), m, Vector3(w * 0.25, 0, 0))
		_flip_pages.append(pivot)
		_flip_outer.append(outer)
		_flip_segs.append([outer])
		_turn_sfx_phase.append(0.0)
		return
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = printed_tex
	pm.roughness = 0.92
	pm.emission_enabled = true
	pm.emission = page_glow
	pm.emission_energy_multiplier = 0.05
	pm.cull_mode = BaseMaterial3D.CULL_BACK
	var seg_w := w / float(SHEET_SEGS)
	var holder: Node3D = pivot
	var segs: Array = []
	for j in SHEET_SEGS:
		var mi := MeshInstance3D.new()
		mi.mesh = _sheet_segment(seg_w, d, float(j) * seg_w, spread)
		mi.material_override = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(mi)
		if j < SHEET_SEGS - 1:
			var nxt := Node3D.new()
			nxt.position = Vector3(seg_w, 0, 0)
			holder.add_child(nxt)
			segs.append(nxt)
			holder = nxt
	_flip_pages.append(pivot)
	_flip_outer.append(segs[int(segs.size() * 0.5)] if not segs.is_empty() else pivot)
	_flip_segs.append(segs)
	_turn_sfx_phase.append(0.0)


## A segment of a printed sheet: x in [0, seg_w] (local), z in [-d/2, d/2]. Front (+Y) is mapped like the spread at
## book x = x0 + x, back (-Y) like the spread at book x = -(x0 + x), where the sheet lies after its 180-degree turn.
## Spread mapping (QuadMesh FACE_Y with uv1_scale (-1, -1), uv1_offset (1, 1)): u = 0.5 - x / spread.x, v = 0.5 - z / spread.y.
func _sheet_segment(seg_w: float, d: float, x0: float, spread: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs := [0.0, seg_w]
	var zs := [-d * 0.5, d * 0.5]
	var lift := 0.002
	# Front face (+Y): two triangles, counter-clockwise seen from above.
	var quad := [Vector2(xs[0], zs[0]), Vector2(xs[1], zs[0]), Vector2(xs[1], zs[1]), Vector2(xs[0], zs[1])]
	for tri in [[0, 2, 1], [0, 3, 2]]:
		for k in tri:
			var q: Vector2 = quad[k]
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.5 - (x0 + q.x) / spread.x, 0.5 - q.y / spread.y))
			st.add_vertex(Vector3(q.x, lift, q.y))
	# Back face (-Y): opposite winding; after the turn this point lies at book x = -(x0 + x) with z unchanged.
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for k in tri:
			var q2: Vector2 = quad[k]
			st.set_normal(Vector3.DOWN)
			st.set_uv(Vector2(0.5 + (x0 + q2.x) / spread.x, 0.5 - q2.y / spread.y))
			st.add_vertex(Vector3(q2.x, -lift, q2.y))
	return st.commit()


## Spreads a curl (degrees, the old outer-half angle) along the sheet: later hinges bend more, so the page rolls.
func _curl_sheet(i: int, deg: float) -> void:
	if i >= _flip_segs.size():
		return
	var segs: Array = _flip_segs[i]
	var n := segs.size()
	if n == 0:
		return
	if n == 1:
		(segs[0] as Node3D).rotation_degrees.z = -deg
		return
	var total := 0.0
	for j in n:
		total += pow(float(j + 1), 1.3)
	for j in n:
		var wj := pow(float(j + 1), 1.3) / total
		(segs[j] as Node3D).rotation_degrees.z = -deg * 1.35 * wj


## A soft dark card on the spread that follows the sheet in the air (darkest when the page stands upright).
func _update_page_shadow(ang_deg: float, airborne: bool) -> void:
	if _page_shadow == null:
		return
	var k := sin(deg_to_rad(clampf(ang_deg, 0.0, 180.0))) if airborne else 0.0
	_page_shadow.visible = k > 0.02
	_page_shadow.position.x = cos(deg_to_rad(ang_deg)) * _sheet_w * 0.45
	_page_shadow.scale = Vector3(0.55 + 0.45 * absf(cos(deg_to_rad(ang_deg))), 1.0, 1.0)
	_page_shadow_mat.albedo_color = Color(0.2, 0.12, 0.05, 0.32 * k)


func _add_page_shadow(w: float, d: float) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(w * 0.5, d * 0.95)
	q.orientation = PlaneMesh.FACE_Y
	_page_shadow_mat = StandardMaterial3D.new()
	_page_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_page_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_page_shadow_mat.albedo_texture = ObjSvc.radial_tex(Color(1, 1, 1, 1), Color(1, 1, 1, 0), 64)
	_page_shadow_mat.albedo_color = Color(0.2, 0.12, 0.05, 0.0)
	_page_shadow = ObjSvc.add_mesh(_book, q, _page_shadow_mat, Vector3(0, 0.024, 0))
	_page_shadow.name = "PageShadow"
	_page_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_page_shadow.visible = false


## Turning pages for the generated lectern: three sheets laid on the mesh's own open book, plus a glow card.
## The hub lectern's open book was measured in its glTF space (tools/measure_lectern.gd): page centre
## (0, 2.30, 0.30), slope 28 degrees down toward the front, 1.36 m across both pages, 0.72 m deep.
const LECTERN_FILE := "book_lectern.glb"
const LECTERN_PAGE_CENTER := Vector3(0, 2.33, 0.30)
const LECTERN_TILT := 28.0
const LECTERN_PAGES := Vector2(0.68, 0.72)


func _build_generated_pages() -> void:
	_generated = true
	var gen := _visual.get_node_or_null("Generated") as Node3D
	var anchor := page_anchor
	var tilt := page_tilt_deg
	var w := page_size.x * visual_scale * 2.0
	var d := page_size.y * visual_scale
	if gen != null and visual_scene != null and visual_scene.resource_path.ends_with(LECTERN_FILE):
		if anchor == Vector3.ZERO:
			anchor = global_transform.affine_inverse() * (gen.global_transform * LECTERN_PAGE_CENTER)
		tilt = LECTERN_TILT
		w = LECTERN_PAGES.x * 2.0 * visual_scale
		d = LECTERN_PAGES.y * visual_scale
	elif anchor == Vector3.ZERO:
		var bb := ObjSvc.local_aabb(self)
		anchor = Vector3(bb.get_center().x, bb.end.y - 0.1 * visual_scale, bb.get_center().z)
	_book = Node3D.new()
	_book.name = "Book"
	_book.position = anchor
	# Desk slope: the back edge (local +Z) higher than the front edge (local -Z, toward the reader).
	_book.rotation_degrees = Vector3(-tilt, 0, 0)
	add_child(_book)
	# Critique objects r1: the pages read as a flat blown-out white quad. They are now printed (title in the
	# storybook font, an illuminated capital, ink lines and a vignette in the book's colours), lit like paper with
	# emission kept far below the bloom threshold, and the glow card is fainter.
	var tex := _page_texture()
	var printed := StandardMaterial3D.new()
	printed.albedo_texture = tex
	printed.roughness = 0.92
	printed.emission_enabled = true
	printed.emission = page_glow
	printed.emission_energy_multiplier = 0.06
	printed.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The reader stands at local -Z: rotate the texture 180 degrees so the spread reads upright from there.
	printed.uv1_scale = Vector3(-1, -1, 1)
	printed.uv1_offset = Vector3(1, 1, 0)
	var spread := QuadMesh.new()
	spread.size = Vector2(w * 0.98, d * 0.96)
	spread.orientation = PlaneMesh.FACE_Y
	var sp := ObjSvc.add_mesh(_book, spread, printed, Vector3(0, 0.018, 0))
	sp.name = "PrintedSpread"
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_printed_spread = sp
	var sheet := ObjSvc.unique_mat(ObjSvc.PAPER.darkened(0.04), 0.9, 0.0, page_glow, 0.03)
	sheet.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 3:
		_make_sheet(_book, Vector3(0, 0.03, 0), w * 0.48, d * 0.94, sheet, tex, spread.size)
	_add_page_shadow(w * 0.98, d * 0.96)
	# A soft glow card rising off the open pages.
	var q := QuadMesh.new()
	q.size = Vector2(w * 1.2, w * 1.2)
	var gm := ObjSvc.unshaded(Color(1, 1, 1, 1), true)
	gm.albedo_texture = ObjSvc.radial_tex(Color(page_glow.r, page_glow.g, page_glow.b, 0.16), Color(page_glow.r, page_glow.g, page_glow.b, 0.0))
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.render_priority = -1
	_page_glow_card = ObjSvc.add_mesh(self, q, gm, anchor + Vector3(0, 0.35, 0))
	_page_glow_card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


var _printed_spread: MeshInstance3D
var _page_vp: SubViewport


## Renders the open spread once into a SubViewport (left page: title and capital; right page: ink lines and a
## vignette in the cover colour). Free, no assets: the storybook font from assets/fonts.
func _page_texture() -> Texture2D:
	_page_vp = SubViewport.new()
	_page_vp.name = "PageArt"
	_page_vp.size = Vector2i(1024, 544)
	_page_vp.transparent_bg = false
	_page_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_page_vp.disable_3d = true
	add_child(_page_vp)
	var parchment := Color("f3e6c4")
	var ink := Color("3b2416")
	var bg := ColorRect.new()
	bg.color = parchment
	bg.size = Vector2(1024, 544)
	_page_vp.add_child(bg)
	# Gutter shading and page borders.
	for x in [500.0, 512.0]:
		var g := ColorRect.new()
		g.color = Color(0.78, 0.66, 0.46, 0.55)
		g.position = Vector2(x, 0)
		g.size = Vector2(12, 544)
		_page_vp.add_child(g)
	for px in [24.0, 536.0]:
		var bor := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(0.72, 0.5, 0.18)
		sb.set_border_width_all(5)
		sb.set_corner_radius_all(10)
		bor.add_theme_stylebox_override("panel", sb)
		bor.position = Vector2(px, 24)
		bor.size = Vector2(464, 496)
		_page_vp.add_child(bor)
	var font: Font = null
	for fp in ["res://assets/fonts/cherryswash/CherrySwash-Bold.ttf", "res://assets/fonts/lilita/LilitaOne-Regular.ttf"]:
		if ResourceLoader.exists(fp):
			font = load(fp) as Font
			break
	var title := Label.new()
	title.text = book_title
	title.position = Vector2(48, 52)
	title.size = Vector2(416, 150)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_color_override("font_color", ink)
	title.add_theme_font_size_override("font_size", 50)
	if font:
		title.add_theme_font_override("font", font)
	_page_vp.add_child(title)
	# Illuminated capital in the accent colour on a gold square.
	var cap_bg := ColorRect.new()
	cap_bg.color = Color(0.86, 0.66, 0.22)
	cap_bg.position = Vector2(60, 230)
	cap_bg.size = Vector2(120, 120)
	_page_vp.add_child(cap_bg)
	var cap := Label.new()
	cap.text = book_title.substr(0, 1) if book_title != "" else "O"
	cap.position = Vector2(60, 222)
	cap.size = Vector2(120, 130)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_color", accent_color)
	cap.add_theme_font_size_override("font_size", 110)
	if font:
		cap.add_theme_font_override("font", font)
	_page_vp.add_child(cap)
	# Ink lines (text) on both pages.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world_id + book_title)
	for i in 8:
		var l := ColorRect.new()
		l.color = Color(ink, 0.72)
		var lx := 200.0 if i < 4 else 60.0
		l.position = Vector2(lx, 240.0 + i * 30.0)
		l.size = Vector2(rng.randf_range(0.6, 1.0) * (440.0 - lx), 7)
		_page_vp.add_child(l)
	for i in 6:
		var l2 := ColorRect.new()
		l2.color = Color(ink, 0.72)
		l2.position = Vector2(560, 330.0 + i * 30.0)
		l2.size = Vector2(rng.randf_range(0.55, 1.0) * 400.0, 7)
		_page_vp.add_child(l2)
	# Vignette: a round framed picture in the cover colour with a gold truffle-shaped sun.
	var vig := Panel.new()
	var vs := StyleBoxFlat.new()
	vs.bg_color = cover_color.lightened(0.25)
	vs.border_color = Color(0.72, 0.5, 0.18)
	vs.set_border_width_all(6)
	vs.set_corner_radius_all(130)
	vig.add_theme_stylebox_override("panel", vs)
	vig.position = Vector2(640, 52)
	vig.size = Vector2(260, 260)
	_page_vp.add_child(vig)
	var hill := Panel.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = cover_color.darkened(0.25)
	hs.set_corner_radius_all(120)
	hill.add_theme_stylebox_override("panel", hs)
	hill.position = Vector2(660, 200)
	hill.size = Vector2(220, 110)
	_page_vp.add_child(hill)
	var sun := Panel.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color("ffc93c")
	ss.set_corner_radius_all(40)
	sun.add_theme_stylebox_override("panel", ss)
	sun.position = Vector2(730, 96)
	sun.size = Vector2(80, 72)
	_page_vp.add_child(sun)
	return _page_vp.get_texture()


func _check_unlocked() -> bool:
	if required_truffles <= 0:
		return true
	var dev := ObjSvc.autoload("Dev")
	if dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "unlock-all")):
		return true
	if ObjSvc.can("Game", "is_book_open") and bool(ObjSvc.call_on("Game", "is_book_open", [world_id])):
		return true
	if ObjSvc.can("Game", "is_unlocked") and bool(ObjSvc.call_on("Game", "is_unlocked", ["book_" + world_id])):
		return true
	return ObjSvc.truffle_count() >= required_truffles


func _set_open(open: bool, animate: bool) -> void:
	var was := is_open
	is_open = open
	var dur := 0.9 if animate else 0.0
	if _cover_l:
		# Closed: the left cover folds onto the right page block.
		var rz := 0.0 if open else 180.0
		var py := 0.0 if open else 0.36
		if dur > 0.0:
			var tw := create_tween().set_parallel()
			tw.tween_property(_cover_l, "rotation_degrees:z", rz, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(_cover_l, "position:y", py, dur * 0.8)
		else:
			_cover_l.rotation_degrees.z = rz
			_cover_l.position.y = py
	for p in _flip_pages:
		p.visible = open
	if _page_glow_card:
		_page_glow_card.visible = open
	if _printed_spread:
		_printed_spread.visible = open
	if _plate:
		_plate.visible = not open
	var chain: Node = _book.get_node_or_null("Chain") if _book else null
	if chain:
		chain.visible = not open
	if _glow:
		_glow.light_energy = 2.0 if open else 0.0
	if _swirl:
		_swirl.emitting = open
	if open and not was and animate:
		unlocked.emit(world_id)
		var at := _book.global_position + Vector3(0, 0.4, 0) if _book else global_position + Vector3(0, 3.0, 0) * scale_factor
		ObjSvc.feedback("object_door_unlock", at, {"world": world_id}, "book_unlock")
		if not ObjSvc.juice_handles("object_door_unlock", "vfx"):
			ObjSvc.burst(get_parent(), at, page_glow, 50, 6.0, 0.22, -3.0, 1.4)
			ObjFx.flash(get_parent(), at, 2.0, 3.5, Color(page_glow.r, page_glow.g, page_glow.b, 0.9), 0.5)
			ObjFx.star_ring(get_parent(), at, 12, 2.0, 0.55, page_glow, 0.7)


func _process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	if not is_open:
		if Engine.get_process_frames() % 30 == 0 and _check_unlocked():
			_set_open(true, true)
		if _book and not _generated:
			_book.position.y = _book_base_y + sin(_t * 1.2) * 0.01
		return
	var popup := get_node_or_null("PopUp") as Node3D
	if popup != null and _generated:
		_turn_popup_book(popup)
		return
	# Pages turn right to left in a slow, staggered loop, as if the story is reading itself. Each sheet lifts at its
	# outer corner first (the outer half lags and curls), sweeps over the spine, then settles flat on the left.
	var n := _flip_pages.size()
	for i in n:
		var phase := fposmod(_t * 0.32 + float(i) / float(n), 1.0)
		var u := clampf(phase / 0.5, 0.0, 1.0)
		var ang := ease(u, -2.4) * 180.0
		var curl := sin(u * PI) * 38.0 * (1.0 - 0.4 * u)
		if u < 0.12:
			curl = -sin(u / 0.12 * PI) * 10.0  # the corner lifts before the page lets go
		_flip_pages[i].rotation_degrees.z = ang
		_curl_sheet(i, curl)
		if i == 0 or (phase < 0.5 and u > 0.0):
			_update_page_shadow(ang, phase < 0.5)
		_flip_pages[i].visible = phase < 0.52
		if phase < 0.02 and i < _turn_sfx_phase.size() and _turn_sfx_phase[i] >= 0.02:
			ObjSvc.feedback("object_portal_page_turn", _flip_pages[i].global_position, {"world": world_id})
		if i < _turn_sfx_phase.size():
			_turn_sfx_phase[i] = phase
	if _book and not _generated:
		_book.position.y = _book_base_y + sin(_t * 1.5) * 0.04
	if _glow:
		_glow.light_energy = 2.0 + sin(_t * 2.6) * 0.5


## Pop-up book rhythm (a builder's "PopUp" diorama stands on the pages): every few seconds one page turns; the
## diorama folds flat just before the page sweeps over it and springs back up, with overshoot, once the page lands.
const POPUP_CYCLE := 4.5
const POPUP_TURN := 0.9
var _popup_base_scale := Vector3.ZERO
var _popup_cycle_i := -1
var _popup_seen_t := -1.0
var _folding := false


func _turn_popup_book(popup: Node3D) -> void:
	# The builder may tween the diorama's own scale (the hub pops it up when the book opens): never fight it. Track its
	# scale while it stands, and fold relative to that. Folding starts once the builder has had time to settle.
	if _popup_seen_t < 0.0:
		_popup_seen_t = _t
	var c := fposmod(_t, POPUP_CYCLE)
	var ci := int(floor(_t / POPUP_CYCLE))
	var standing := c >= POPUP_TURN + 0.55
	if standing or _popup_base_scale == Vector3.ZERO or _t - _popup_seen_t < 1.5:
		if _folding:
			popup.scale = _popup_base_scale
			_folding = false
		_popup_base_scale = popup.scale
		for p in _flip_pages:
			p.visible = false
		return
	var u := clampf(c / POPUP_TURN, 0.0, 1.0)
	for i in _flip_pages.size():
		_flip_pages[i].visible = i == 0 and c < POPUP_TURN + 0.05
	if not _flip_pages.is_empty():
		_flip_pages[0].rotation_degrees.z = ease(u, -2.4) * 180.0
		_curl_sheet(0, sin(u * PI) * 38.0 * (1.0 - 0.4 * u))
		_update_page_shadow(ease(u, -2.4) * 180.0, c < POPUP_TURN)
	if ci != _popup_cycle_i:
		_popup_cycle_i = ci
		ObjSvc.feedback("object_portal_page_turn", _book.global_position if _book else global_position, {"world": world_id})
	# Fold: 0..0.3 of the turn folds down; stays flat while the page passes; pops up over 0.55 s after it lands.
	var fold := 1.0
	if c < POPUP_TURN * 0.3:
		fold = 1.0 - ease(c / (POPUP_TURN * 0.3), 0.5)
	elif c < POPUP_TURN:
		fold = 0.0
	else:
		var k := (c - POPUP_TURN) / 0.55
		fold = clampf(1.0 + sin(k * PI * 1.5) * 0.18 * (1.0 - k) - (1.0 - ease(k, 0.35)), 0.0, 1.25)
	_folding = true
	popup.scale = Vector3(_popup_base_scale.x, _popup_base_scale.y * maxf(fold, 0.02), _popup_base_scale.z)


func _on_zone_body(body: Node) -> void:
	if not ObjSvc.is_player(body) or _cooldown > 0.0:
		return
	if not is_open:
		ObjSvc.feedback("object_portal_locked", global_position + Vector3(0, 2.0, 0), {"world": world_id}, "locked")
		var need := required_truffles - ObjSvc.truffle_count()
		ObjSvc.show_dialog(["This book is sealed. %d more Golden Truffle%s will loosen the chain." % [need, "" if need == 1 else "s"]], "")
		_cooldown = 2.0
		return
	enter()


func enter() -> void:
	_cooldown = 3.0
	entered.emit(world_id)
	var at := _book.global_position + Vector3(0, 0.5, 0) if _book else global_position + Vector3(0, 3.0, 0) * scale_factor
	ObjSvc.feedback("object_portal_enter", at, {"world_id": world_id}, "book_enter")
	if not ObjSvc.juice_handles("object_portal_enter", "vfx"):
		ObjSvc.burst(get_parent(), at, page_glow, 40, 5.0, 0.2, -1.0, 1.0)
		ObjFx.flash(get_parent(), at, 2.5, 4.0, Color(page_glow.r, page_glow.g, page_glow.b, 0.95), 0.45)
	# The pages riffle fast as Mak dives in.
	var rt := create_tween()
	rt.tween_method(func(v: float) -> void: _t = v, _t, _t + 3.0, 0.8).set_ease(Tween.EASE_OUT)
	if not route_on_enter:
		return
	if ObjSvc.can("UI", "show_mission_select"):
		ObjSvc.call_on("UI", "show_mission_select", [world_id])
	elif ObjSvc.can("UI", "open_mission_select"):
		ObjSvc.call_on("UI", "open_mission_select", [world_id])
	elif ObjSvc.can("Router", "enter_world"):
		ObjSvc.call_on("Router", "enter_world", [world_id, ""])
	else:
		print("[StorybookPortal] enter ", world_id, " (no UI or Router handler yet)")

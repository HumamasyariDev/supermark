class_name ExitGate
extends Talker
## Owner fix 2026-10-19 (world exits): the way back to the library from a world. A closed storybook gate across the
## world's entrance opening, solid, with invisible walls (ExitBounds, layers 3 + 9: Mak collides, the camera spring arm
## does not) so Mak cannot walk, jump around or jump over it into the void. Walking up shows the HUD interact prompt
## ("E / Y  Return to the library"); interact opens UI.ask_return_to_library(): "Return to the Grand Library?" Yes / No
## over the paused world, the pause menu's own confirm card. Yes = the pause menu's "Return to library" (Router.go_to_hub
## with the world's Book_<id> hub spawn, same save); No / Cancel / Pause resumes where Mak stands.
## Built and placed by WorldExits (scripts/worlds/world_exits.gd). Local frame: the opening spans X, the gate plane is
## z = 0, the world side (where Mak walks up) is +Z, the void side is -Z.

## "book" (W1: closed book-cover double doors), "garden" (W2: ribbon-tied white picket gate),
## "ginger" (W3: gingerbread double gate between candy-cane posts).
@export var style: String = "book"
## Opening width (m) and the height of the gate leaves (m).
@export var open_w: float = 5.2
@export var leaf_h: float = 6.3
## Invisible wall boxes in the gate's local frame: [[size: Vector3, center: Vector3], ...].
var bounds: Array = []

const PROMPT_VERB := "Return to the library"


func _ready() -> void:
	prompt_verb = PROMPT_VERB
	prompt_text = "..."
	talk_radius = maxf(2.8, open_w * 0.5 + 0.9)
	lines = PackedStringArray()
	add_to_group("exit_gate")
	super._ready()
	# The talk zone sits on the world side of the gate.
	if _zone:
		_zone.position = Vector3(0, 1.0, 0.8)
	ObjSvc.add_shape(self, ObjSvc.box_shape(Vector3(open_w + 0.2, leaf_h + 0.1, 0.5)), Vector3(0, (leaf_h + 0.1) * 0.5, 0))
	var v := Node3D.new()
	v.name = "GateVisual"
	add_child(v)
	match style:
		"garden":
			_build_garden(v)
		"ginger":
			_build_ginger(v)
		_:
			_build_book(v)
	_build_bounds()
	_snap_to_ground.call_deferred()


func _prompt_anchor() -> Vector3:
	return Vector3(0, minf(leaf_h, 2.4) + 0.75, 0.7)


func _talk_event() -> String:
	return "object_sign_read"


## Interact: ask, never leave on a single press.
func talk() -> void:
	_cool = 1.0
	_set_prompt(false)
	ObjSvc.feedback(_talk_event(), global_position + Vector3(0, 1.2, 0), {"speaker": ""}, "talk_blip")
	ObjSvc.call_on("UI", "ask_return_to_library")
	talked.emit([])


func _build_bounds() -> void:
	if bounds.is_empty():
		return
	var b := StaticBody3D.new()
	b.name = "ExitBounds"
	# Same layers as the hub balustrade rails: Mak (mask 1 + 3) collides, the camera (layer 1 queries) does not.
	b.collision_layer = (1 << 2) | (1 << 8)
	b.collision_mask = 0
	b.add_to_group("camera_ignore")
	add_child(b)
	for spec in bounds:
		ObjSvc.add_shape(b, ObjSvc.box_shape(spec[0]), spec[1])


## Sits the gate on the ground under it (rays down past its own bodies), within 1.5 m of the placed height.
func _snap_to_ground() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	var bnd := get_node_or_null("ExitBounds") as CollisionObject3D
	if bnd:
		ex.append(bnd.get_rid())
	var best := INF
	for lx in [-open_w * 0.3, 0.0, open_w * 0.3]:
		var p: Vector3 = global_transform * Vector3(lx, 0, 0.0)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.5, 0), p + Vector3(0, -2.5, 0), 1, ex)
		var hit := space.intersect_ray(q)
		if hit.has("position"):
			var y := float((hit["position"] as Vector3).y)
			best = y if best == INF else maxf(best, y)
	if best != INF and absf(best - global_position.y) < 1.5:
		global_position.y = best - 0.03
	print("[ExitGate] %s at %s (ground %s)" % [name, global_position, "none" if best == INF else "%.2f" % best])


# ---------------------------------------------------------------- W1: closed book-cover double doors

func _build_book(v: Node3D) -> void:
	var leather := ObjSvc.mat(Color("7a1f2e"), 0.75)
	var leather_dk := ObjSvc.mat(Color("5e1220"), 0.8)
	var page := ObjSvc.mat(Color("f6ecd6"), 0.9)
	var gilt := ObjSvc.mat(UIStyle.BRASS, 0.4, 0.15)
	var ribbon := ObjSvc.mat(Color("e0b13a"), 0.5)
	var hw := open_w * 0.5
	var lw := hw - 0.06
	var h := leaf_h
	for sx in [-1.0, 1.0]:
		var cx: float = sx * (lw * 0.5 + 0.03)
		# Page block behind the cover (cream edge shows at the top and the outer side), then the cover board.
		ObjSvc.soft_box(v, Vector3(lw - 0.1, h - 0.2, 0.34), page, Vector3(cx, h * 0.5, -0.12), Vector3.ZERO, 0.04)
		ObjSvc.soft_box(v, Vector3(lw, h, 0.16), leather, Vector3(cx, h * 0.5, 0.1), Vector3.ZERO, 0.06)
		# Raised spine bands at the outer edge, like the stacked books of the arch.
		for k in 4:
			ObjSvc.soft_box(v, Vector3(0.24, 0.16, 0.22), leather_dk, Vector3(sx * (hw - 0.16), h * (0.18 + 0.22 * k), 0.12), Vector3.ZERO, 0.05)
		# Gilt frame inset on the cover, and a corner flourish.
		var fx: float = cx
		var iw := lw - 0.5
		var ih := h - 0.7
		ObjSvc.box(v, Vector3(iw, 0.07, 0.03), gilt, Vector3(fx, h * 0.5 + ih * 0.5, 0.195))
		ObjSvc.box(v, Vector3(iw, 0.07, 0.03), gilt, Vector3(fx, h * 0.5 - ih * 0.5, 0.195))
		ObjSvc.box(v, Vector3(0.07, ih, 0.03), gilt, Vector3(fx - iw * 0.5, h * 0.5, 0.195))
		ObjSvc.box(v, Vector3(0.07, ih, 0.03), gilt, Vector3(fx + iw * 0.5, h * 0.5, 0.195))
		for cy in [-1.0, 1.0]:
			for cxs in [-1.0, 1.0]:
				ObjSvc.sphere(v, 0.11, gilt, Vector3(fx + cxs * iw * 0.5, h * 0.5 + cy * ih * 0.5, 0.2), Vector3(1, 1, 0.5))
		# Embossed medallion on each cover.
		ObjSvc.torus(v, 0.32, 0.42, gilt, Vector3(fx, h * 0.62, 0.2), Vector3(90, 0, 0))
		ObjSvc.sphere(v, 0.2, gilt, Vector3(fx, h * 0.62, 0.2), Vector3(1, 1, 0.45))
	# Brass clasp across the seam (the book is shut) with a keyhole plate.
	ObjSvc.soft_box(v, Vector3(1.5, 0.42, 0.12), gilt, Vector3(0, h * 0.45, 0.24), Vector3.ZERO, 0.05)
	ObjSvc.soft_box(v, Vector3(0.5, 0.62, 0.14), gilt, Vector3(0, h * 0.45, 0.28), Vector3.ZERO, 0.05)
	ObjSvc.sphere(v, 0.06, ObjSvc.mat(UIStyle.INK, 0.9), Vector3(0, h * 0.45 + 0.06, 0.36), Vector3(1, 1, 0.4))
	ObjSvc.box(v, Vector3(0.05, 0.16, 0.03), ObjSvc.mat(UIStyle.INK, 0.9), Vector3(0, h * 0.45 - 0.06, 0.36))
	# A gold bookmark ribbon hanging from the top of the seam.
	ObjSvc.box(v, Vector3(0.36, 1.9, 0.04), ribbon, Vector3(0.0, h - 0.95, 0.22))
	ObjSvc.box(v, Vector3(0.2, 0.5, 0.04), ribbon, Vector3(-0.08, h - 2.1, 0.22), Vector3(0, 0, 14))
	ObjSvc.box(v, Vector3(0.2, 0.5, 0.04), ribbon, Vector3(0.08, h - 2.1, 0.22), Vector3(0, 0, -14))
	_plaque(v, Vector3(0, 2.1, 0.24), 1.9, "To the\nGrand Library")


# ---------------------------------------------------------------- W2: ribbon-tied white picket garden gate

func _build_garden(v: Node3D) -> void:
	var paint := ObjSvc.mat(Color("f7f1e3"), 0.7)
	var paint_dk := ObjSvc.mat(Color("e4d8bf"), 0.75)
	var ribbon := ObjSvc.mat(UIStyle.RIBBON, 0.5)
	var hw := open_w * 0.5
	var h := leaf_h
	for sx in [-1.0, 1.0]:
		var x0: float = sx * 0.06
		var x1: float = sx * (hw - 0.05)
		var lw := absf(x1 - x0)
		var cx := (x0 + x1) * 0.5
		# Two rails and a diagonal brace, then rounded pickets rising toward the hinge post (a swag top).
		for ry in [0.3, h - 0.32]:
			ObjSvc.soft_box(v, Vector3(lw, 0.12, 0.08), paint_dk, Vector3(cx, ry, -0.06), Vector3.ZERO, 0.03)
		var brace_len := sqrt(lw * lw + (h - 0.62) * (h - 0.62))
		ObjSvc.soft_box(v, Vector3(brace_len, 0.1, 0.07), paint_dk, Vector3(cx, h * 0.5 - 0.01, -0.06), Vector3(0, 0, rad_to_deg(atan2(h - 0.62, lw)) * -sx), 0.03)
		var n := int(lw / 0.26)
		for k in n:
			var t := (k + 0.5) / float(n)
			var px := lerpf(x0, x1, t)
			var ph := h + 0.06 + 0.22 * t
			ObjSvc.box(v, Vector3(0.13, ph - 0.07, 0.06), paint, Vector3(px, (ph - 0.07) * 0.5, 0.02))
			ObjSvc.sphere(v, 0.068, paint, Vector3(px, ph - 0.07, 0.02), Vector3(1, 1.2, 0.47))
		# The garden's own wooden posts stand at x +/-2.2 (w2_build); short picket wings close the fence gap
		# beyond them (the fence leaves |x| < 3.5 open).
		for k in 5:
			var wx: float = sx * (hw + 0.3 + k * 0.26)
			ObjSvc.box(v, Vector3(0.13, 0.78, 0.06), paint, Vector3(wx, 0.39, -0.1))
			ObjSvc.sphere(v, 0.068, paint, Vector3(wx, 0.78, -0.1), Vector3(1, 1.2, 0.47))
		ObjSvc.box(v, Vector3(1.4, 0.09, 0.06), paint_dk, Vector3(sx * (hw + 0.82), 0.3, -0.16))
		ObjSvc.box(v, Vector3(1.4, 0.09, 0.06), paint_dk, Vector3(sx * (hw + 0.82), 0.62, -0.16))
	# The two leaves tied shut with a red bookmark ribbon bow at the latch.
	var by := h * 0.62
	ObjSvc.box(v, Vector3(0.5, 0.1, 0.16), ribbon, Vector3(0, by, 0.06))
	for sx in [-1.0, 1.0]:
		ObjSvc.sphere(v, 0.17, ribbon, Vector3(sx * 0.2, by + 0.05, 0.1), Vector3(1.3, 0.8, 0.45))
		ObjSvc.box(v, Vector3(0.09, 0.42, 0.03), ribbon, Vector3(sx * 0.1, by - 0.24, 0.1), Vector3(0, 0, sx * 12.0))
	ObjSvc.sphere(v, 0.08, ribbon, Vector3(0, by, 0.14))
	_plaque(v, Vector3(0, h * 0.3, 0.1), 1.25, "To the Library")


# ---------------------------------------------------------------- W3: gingerbread double gate, candy-cane posts

func _build_ginger(v: Node3D) -> void:
	var ginger := ObjSvc.mat(Color("c97b3a"), 0.75)
	var ginger_dk := ObjSvc.mat(Color("8e4e22"), 0.8)
	var icing := ObjSvc.mat(Color("fff7ee"), 0.5)
	var cane_r := ObjSvc.mat(Color("e8344e"), 0.45)
	var cane_w := ObjSvc.mat(Color("fff7ee"), 0.45)
	var gum := [ObjSvc.mat(Color("5fd38a"), 0.35), ObjSvc.mat(Color("ff7faf"), 0.35), ObjSvc.mat(Color("ffd84a"), 0.35)]
	var hw := open_w * 0.5
	var h := leaf_h
	for sx in [-1.0, 1.0]:
		var lw := hw - 0.08
		var cx: float = sx * (lw * 0.5 + 0.04)
		# Gingerbread slab with a darker baked rim and a white icing border, three gumdrop studs.
		ObjSvc.soft_box(v, Vector3(lw, h, 0.2), ginger, Vector3(cx, h * 0.5, 0.0), Vector3.ZERO, 0.08)
		ObjSvc.soft_box(v, Vector3(lw - 0.3, h - 0.3, 0.06), ginger_dk, Vector3(cx, h * 0.5, 0.1), Vector3.ZERO, 0.03)
		var iw := lw - 0.5
		var ih := h - 0.5
		for k in 12:
			var t := (k + 0.5) / 12.0
			ObjSvc.sphere(v, 0.06, icing, Vector3(cx - iw * 0.5 + iw * t, h * 0.5 + ih * 0.5, 0.15), Vector3(1.4, 0.8, 0.6))
			ObjSvc.sphere(v, 0.06, icing, Vector3(cx - iw * 0.5 + iw * t, h * 0.5 - ih * 0.5, 0.15), Vector3(1.4, 0.8, 0.6))
		for k in 8:
			var t2 := (k + 0.5) / 8.0
			ObjSvc.sphere(v, 0.06, icing, Vector3(cx - iw * 0.5, h * 0.5 - ih * 0.5 + ih * t2, 0.15), Vector3(0.8, 1.4, 0.6))
			ObjSvc.sphere(v, 0.06, icing, Vector3(cx + iw * 0.5, h * 0.5 - ih * 0.5 + ih * t2, 0.15), Vector3(0.8, 1.4, 0.6))
		for k in 3:
			ObjSvc.sphere(v, 0.13, gum[k], Vector3(cx, h * (0.25 + 0.25 * k), 0.17), Vector3(1, 0.85, 0.7))
		# Candy-cane post: striped segments and a hooked top.
		var px: float = sx * (hw + 0.12)
		var ph := h + 0.6
		var seg := 8
		for k in seg:
			ObjSvc.cylinder(v, 0.14, 0.14, ph / seg, cane_r if k % 2 == 0 else cane_w, Vector3(px, ph / seg * (k + 0.5), 0.0))
		ObjSvc.torus(v, 0.22, 0.5, cane_r, Vector3(px - sx * 0.36, ph, 0.0), Vector3(90, 0, 0))
		ObjSvc.sphere(v, 0.2, gum[1], Vector3(px, ph + 0.05, 0.0))
	# Icing heart latch across the seam.
	ObjSvc.sphere(v, 0.22, icing, Vector3(-0.1, h * 0.55, 0.2), Vector3(1, 1, 0.5))
	ObjSvc.sphere(v, 0.22, icing, Vector3(0.1, h * 0.55, 0.2), Vector3(1, 1, 0.5))
	ObjSvc.cone(v, 0.27, 0.32, icing, Vector3(0, h * 0.55 - 0.2, 0.2), Vector3(180, 0, 0))
	_plaque(v, Vector3(0, h * 0.27, 0.2), 1.4, "To the Library")


## A small parchment plaque with ink lettering on the world side of the gate.
func _plaque(v: Node3D, at: Vector3, w: float, text: String) -> void:
	var lines_n := text.count("\n") + 1
	var ph := 0.32 + 0.24 * lines_n
	ObjSvc.soft_box(v, Vector3(w + 0.14, ph + 0.14, 0.06), ObjSvc.mat(UIStyle.BRASS_DARK, 0.5, 0.4), at, Vector3.ZERO, 0.03)
	ObjSvc.soft_box(v, Vector3(w, ph, 0.07), ObjSvc.mat(UIStyle.PARCHMENT, 0.9), at + Vector3(0, 0, 0.02), Vector3.ZERO, 0.03)
	var f := UIStyle.FONT_BOOK
	var l := ObjSvc.label(v, text, at + Vector3(0, 0, 0.065), 64, UIStyle.INK, false)
	l.name = "PlaqueText"
	l.outline_size = 0
	l.pixel_size = 0.0042
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.line_spacing = -8.0
	if ResourceLoader.exists(f):
		l.font = load(f) as Font

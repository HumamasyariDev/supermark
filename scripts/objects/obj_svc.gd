class_name ObjSvc
extends RefCounted
## Shared helpers for interactive objects: duck-typed autoload calls (Game, Audio, UI, Router),
## physics layer bits, palettes and smooth-primitive builders for placeholder visuals.
## Every autoload call checks has_method first, so a missing piece never crashes an object.

# Physics layer bits (Docs/TECH_CONTRACT.md).
const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4
const L_PICKUP := 8
const L_HAZARD := 16
const L_PLAYER_ATTACK := 32
const L_ENEMY_HURTBOX := 64
const L_TRIGGER := 128
const L_CAMERA_IGNORE := 256

# Palettes (Docs/DESIGN_V2.md).
const GOLD := Color(1.0, 0.76, 0.22)
const GOLD_DEEP := Color(0.86, 0.55, 0.12)
const WALNUT := Color(0.42, 0.25, 0.14)
const WALNUT_DARK := Color(0.27, 0.15, 0.08)
const BURGUNDY := Color(0.55, 0.11, 0.17)
const BRASS := Color(0.85, 0.66, 0.3)
const CANDLE := Color(1.0, 0.85, 0.5)
const MEADOW := Color(0.44, 0.72, 0.3)
const STRAW := Color(0.95, 0.82, 0.42)
const BRICK := Color(0.72, 0.3, 0.22)
const SKY := Color(0.55, 0.78, 0.98)
const BEAN := Color(0.36, 0.7, 0.27)
const CLOUD := Color(0.98, 0.98, 1.0)
const LAVENDER := Color(0.72, 0.64, 0.92)
const GINGER := Color(0.69, 0.43, 0.2)
const ICING := Color(1.0, 0.97, 0.94)
const CANDY_PINK := Color(1.0, 0.52, 0.7)
const MINT := Color(0.55, 0.93, 0.78)
const CHOCOLATE := Color(0.36, 0.2, 0.11)
const IRON := Color(0.24, 0.24, 0.27)
const PAPER := Color(0.98, 0.94, 0.84)
const HAZARD_RED := Color(0.95, 0.3, 0.18)

## Fallback state used only when the Game autoload lacks the method (labs and tests).
static var local_truffles: Dictionary = {}
static var visit_acorns: int = 0

static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}


# ---------------------------------------------------------------- autoloads

static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func autoload(n: String) -> Node:
	var t := tree()
	if t == null or t.root == null:
		return null
	return t.root.get_node_or_null(n)


static func can(n: String, method: String) -> bool:
	var node := autoload(n)
	return node != null and node.has_method(method)


static func call_on(n: String, method: String, args: Array = []) -> Variant:
	var node := autoload(n)
	if node != null and node.has_method(method):
		return node.callv(method, args)
	return null


## Object sound names -> keys in res://assets/audio/audio_index.json (audio workstream). "" = stay silent
## (for example the truffle jingle is played by WorldRoot, hurt sounds by the player).
const SFX_ALIASES := {
	"acorn": "acorn_collect", "truffle_collect": "", "truffle_appear": "truffle_jingle", "page_collect": "page_collect",
	"checkpoint": "checkpoint", "bellows_break": "bellows_break", "bellows_pump": "bellows_pump", "cloud_puff": "cloud_puff",
	"cloud_squish": "land", "door_unlock": "door_unlock", "door_open": "door_unlock", "book_enter": "book_page_turn",
	"book_unlock": "book_open", "locked": "ui_back", "knocker_rattle": "ui_back", "bounce_leaf": "jump_2",
	"bounce_gumdrop": "gummy_wobble", "bounce_drum": "land_heavy", "crate_break": "gingerbread_crumble",
	"switch_press": "ui_confirm", "cage_open": "door_unlock", "dig_out": "splash", "mud_splat": "splash",
	"hazard_hit": "", "fall_out": "", "platform_creak": "footstep_wood", "platform_fall": "land_heavy",
	"ring": "ui_select", "sniff_found": "ui_accept", "talk_blip": "ui_move", "trial_start": "ui_confirm",
	"trial_success": "ui_accept", "trial_fail": "ui_back",
}


static func sfx(key: String, at: Vector3 = Vector3.INF) -> void:
	var k: String = SFX_ALIASES.get(key, key)
	if k == "":
		return
	call_on("Audio", "play_sfx", [k, at])


## Semantic feedback for every object event: emits Juice.event(event, at, params) (Docs/JUICE.md bus) and plays the
## object's own sound unless the Juice track reports that it owns the sound for this event through
## Juice.handles(event, "sfx") -> bool. Params always carry "source": "objects".
static func feedback(event: String, at: Vector3 = Vector3.INF, params: Dictionary = {}, sfx_key: String = "") -> void:
	var p := params.duplicate()
	p["source"] = "objects"
	call_on("Juice", "event", [event, at, p])
	if sfx_key != "" and not juice_handles(event, "sfx"):
		sfx(sfx_key, at)


## Like feedback(), for object events that are not (yet) in the Juice catalogue: emits only when Juice.has_event()
## knows the name, so an optional event never prints the unknown-event warning. Returns true when Juice took it.
static func feedback_optional(event: String, at: Vector3 = Vector3.INF, params: Dictionary = {}, sfx_key: String = "") -> bool:
	var j := autoload("Juice")
	if j != null and j.has_method("has_event") and bool(j.call("has_event", event)):
		feedback(event, at, params, sfx_key)
		return true
	if sfx_key != "":
		sfx(sfx_key, at)
	return false


## True when the Juice track has taken over a channel ("sfx" or "vfx") for this event, so objects skip their own
## particle bursts and sounds (the object's own motion always plays). Juice.handles(event, channel) when it exists,
## otherwise Juice.has_event(event): every catalogued object_* event carries both an effect and a sound.
static func juice_handles(event: String, channel: String) -> bool:
	var j := autoload("Juice")
	if j == null:
		return false
	if j.has_method("handles"):
		return bool(j.call("handles", event, channel))
	if j.has_method("has_event"):
		return bool(j.call("has_event", event))
	return false


## Characters that were re-delivered rigged: an NPC asking for the left file gets the right one, at the same on-screen height.
## Also the round-3/4 character re-deliveries (Docs/ASSETS_TOPUP.md "Use these files"): AO-baked v2 files with the same
## rig and size, Sergeant Snap v3 (arms-down fix), the sheep at its corrected 1.21 scale and the 2.2 m cow (both are
## the intended sizes, so the factor stays 1.0).
const RIGGED_UPGRADES := {
	"res://assets/characters/pip/pip.glb": ["res://assets/characters/pip_v2/pip_v3.glb", 0.7 / 0.95],
	"res://assets/characters/pip_v2/pip_v2.glb": ["res://assets/characters/pip_v2/pip_v3.glb", 1.0],
	"res://assets/characters/jack/jack.glb": ["res://assets/characters/jack/jack_v2.glb", 1.0],
	"res://assets/characters/hazel/hazel.glb": ["res://assets/characters/hazel/hazel_v2.glb", 1.0],
	"res://assets/characters/bertram/bertram.glb": ["res://assets/characters/bertram/bertram_v2.glb", 1.0],
	"res://assets/characters/foreman/foreman.glb": ["res://assets/characters/foreman/foreman_v2.glb", 1.0],
	"res://assets/characters/foreman/foreman_underwear.glb": ["res://assets/characters/foreman/foreman_underwear_v2.glb", 1.0],
	"res://assets/characters/sergeant_snap/sergeant_snap.glb": ["res://assets/characters/sergeant_snap/sergeant_snap_v3.glb", 1.0],
	"res://assets/characters/sergeant_snap/sergeant_snap_v2.glb": ["res://assets/characters/sergeant_snap/sergeant_snap_v3.glb", 1.0],
	"res://assets/characters/real_sheep/real_sheep.glb": ["res://assets/characters/real_sheep/real_sheep_v2.glb", 1.0],
	# Finish pass: Daisy v3 has a real mouth (lip cut, mouth bag, tongue; ASSETS3_CHARS round 5).
	"res://assets/characters/daisy_cow/daisy_cow.glb": ["res://assets/characters/daisy_cow/daisy_cow_v3.glb", 1.0],
	"res://assets/characters/daisy_cow/daisy_cow_v2.glb": ["res://assets/characters/daisy_cow/daisy_cow_v3.glb", 1.0],
	"res://assets/characters/sleeping_giant/sleeping_giant.glb": ["res://assets/characters/sleeping_giant/sleeping_giant_v2.glb", 1.0],
	"res://assets/characters/wolf_scarecrow/wolf_scarecrow.glb": ["res://assets/characters/wolf_scarecrow/wolf_scarecrow_v2.glb", 1.0],
}


static func upgrade_character(ps: PackedScene, scale_in: float) -> Array:
	if ps == null:
		return [ps, scale_in]
	var up: Variant = RIGGED_UPGRADES.get(ps.resource_path, null)
	if up == null or not ResourceLoader.exists(str(up[0])):
		return [ps, scale_in]
	var ps2 := load(str(up[0])) as PackedScene
	if ps2 == null:
		return [ps, scale_in]
	return [ps2, scale_in * float(up[1])]


## First descendant named `n` (generated GLB node lookup), or null.
static func find_named(root: Node, n: String) -> Node3D:
	if root == null:
		return null
	var found := root.find_child(n, true, false)
	return found as Node3D


static func current_world() -> String:
	var g := autoload("Game")
	if g != null and "current_world" in g:
		return str(g.get("current_world"))
	return ""


static func collect_truffle(id: String) -> void:
	local_truffles[id] = true
	call_on("Game", "collect_truffle", [id])


static func has_truffle(id: String) -> bool:
	if can("Game", "has_truffle"):
		return bool(call_on("Game", "has_truffle", [id]))
	return local_truffles.has(id)


## Acorns collected in the current visit (Game.acorns when the core Game provides it).
static func acorns_this_visit() -> int:
	var g := autoload("Game")
	if g != null and "acorns" in g:
		return int(g.get("acorns"))
	return visit_acorns


static func truffle_count() -> int:
	if can("Game", "truffle_count"):
		return int(call_on("Game", "truffle_count"))
	return local_truffles.size()


static func show_dialog(lines: Array, speaker: String = "") -> bool:
	var ui := autoload("UI")
	if ui != null and ui.has_method("show_dialog"):
		# Core UI signature: show_dialog(speaker: String, lines: Array). Older drafts used (lines[, speaker]).
		var args: Array = []
		for m in ui.get_method_list():
			if m.name == "show_dialog":
				args = m.args
		if args.size() >= 2 and int(args[0].type) == TYPE_STRING:
			ui.call("show_dialog", speaker, lines)
		elif args.size() >= 2:
			ui.call("show_dialog", lines, speaker)
		else:
			ui.call("show_dialog", lines)
		return true
	print("[Dialog] ", speaker, ": ", " / ".join(PackedStringArray(lines)))
	return false


static func is_player(body: Node) -> bool:
	return body != null and body.is_in_group("player")


static func get_player() -> Node3D:
	var t := tree()
	if t == null:
		return null
	return t.get_first_node_in_group("player") as Node3D


## Fix stage r2: the first interactive object that enters a world scene adds one NpcLifeAuto to it, which gives
## frozen world characters (placed by builders, not by objects) their idle life. See npc_life_auto.gd for opt-outs.
static func ensure_npc_life_auto(from: Node) -> void:
	if from == null or not from.is_inside_tree():
		return
	var t := from.get_tree()
	var root: Node = from
	while root.get_parent() != null and root.get_parent() != t.root:
		root = root.get_parent()
	if root == from and root.get_parent() == null:
		return
	if root.has_meta("npc_life_auto_node"):
		return
	if root.has_meta("npc_life_auto") and not bool(root.get_meta("npc_life_auto")):
		return
	if "--no-npc-life-auto" in OS.get_cmdline_user_args():
		return
	var auto := NpcLifeAuto.new()
	auto.name = "NpcLifeAuto"
	auto.scene_root = root
	root.set_meta("npc_life_auto_node", true)
	root.add_child.call_deferred(auto)


static func player_slamming(body: Node) -> bool:
	if body == null or not body.has_method("is_ground_pounding"):
		return false
	return bool(body.call("is_ground_pounding"))


static func player_state(body: Node) -> String:
	if body != null and body.has_method("get_state_name"):
		return str(body.call("get_state_name"))
	return ""


static func body_pos(n: Node3D) -> Vector3:
	return n.get_global_transform_interpolated().origin if n.is_inside_tree() else n.position


# ---------------------------------------------------------------- materials

static func mat(color: Color, rough: float = 0.6, metal: float = 0.0, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%.2f" % [color.to_html(), rough, metal, emission.to_html(), energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cache[key] = m
	return m


static func unique_mat(color: Color, rough: float = 0.6, metal: float = 0.0, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	return mat(color, rough, metal, emission, energy).duplicate() as StandardMaterial3D


## Owned truffles: a translucent blue-glass ghost that keeps the model's shape (shaded, fresnel rim, soft glow).
static func ghost_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.78, 1.0, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.15
	m.metallic = 0.2
	m.metallic_specular = 0.8
	m.emission_enabled = true
	m.emission = Color(0.45, 0.65, 1.0)
	m.emission_energy_multiplier = 0.25
	m.rim_enabled = true
	m.rim = 1.0
	m.rim_tint = 0.2
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


static func unshaded(color: Color, additive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static func radial_tex(inner: Color, outer: Color, size: int = 64) -> Texture2D:
	var key := "r%s%s%d" % [inner.to_html(), outer.to_html(), size]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	_tex_cache[key] = t
	return t


static func sparkle_mat(color: Color) -> StandardMaterial3D:
	var m := unshaded(color, true)
	m.albedo_texture = radial_tex(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	return m


# ---------------------------------------------------------------- builders

static func add_mesh(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func sphere(parent: Node3D, r: float, material: Material, pos: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 24
	m.rings = 12
	return add_mesh(parent, m, material, pos, Vector3.ZERO, scl)


static func cylinder(parent: Node3D, r_top: float, r_bottom: float, h: float, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = 20
	m.rings = 1
	return add_mesh(parent, m, material, pos, rot_deg)


static func capsule(parent: Node3D, r: float, h: float, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = 20
	m.rings = 6
	return add_mesh(parent, m, material, pos, rot_deg)


static func box(parent: Node3D, size: Vector3, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return add_mesh(parent, m, material, pos, rot_deg)


## A soft "rounded box": a box with capsule edges along its four vertical edges and a slightly smaller core,
## which reads as bevelled at gameplay distance.
static func soft_box(parent: Node3D, size: Vector3, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, bevel: float = 0.06) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot_deg
	parent.add_child(n)
	box(n, Vector3(size.x, size.y - bevel * 2.0, size.z), material)
	box(n, Vector3(size.x - bevel * 2.0, size.y, size.z - bevel * 2.0), material)
	# Rounded top and bottom rims.
	for sy in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			capsule(n, bevel, size.z - bevel * 0.0, material, Vector3(sx * (size.x * 0.5 - bevel), sy * (size.y * 0.5 - bevel), 0), Vector3(90, 0, 0))
		for sz in [-1.0, 1.0]:
			capsule(n, bevel, size.x, material, Vector3(0, sy * (size.y * 0.5 - bevel), sz * (size.z * 0.5 - bevel)), Vector3(0, 0, 90))
	return n


static func torus(parent: Node3D, inner: float, outer: float, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 32
	m.ring_segments = 12
	return add_mesh(parent, m, material, pos, rot_deg)


static func cone(parent: Node3D, r: float, h: float, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return cylinder(parent, 0.0, r, h, material, pos, rot_deg)


static func label(parent: Node3D, text: String, pos: Vector3, size: int = 64, color: Color = Color.WHITE, billboard: bool = true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = maxi(8, size / 5)
	l.modulate = color
	l.outline_modulate = Color(0.18, 0.1, 0.05)
	l.pixel_size = 0.005
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = true
	parent.add_child(l)
	return l


static func shadow_blob(parent: Node3D, radius: float, y: float = 0.02, alpha: float = 0.45) -> MeshInstance3D:
	var q := PlaneMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	var m := unshaded(Color(0, 0, 0, 1))
	m.albedo_texture = radial_tex(Color(0.05, 0.03, 0.02, alpha), Color(0, 0, 0, 0))
	var mi := add_mesh(parent, q, m, Vector3(0, y, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func sparkles(parent: Node3D, color: Color, amount: int = 16, radius: float = 0.6, size: float = 0.12, lifetime: float = 1.2, up_speed: float = 0.4) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3.UP
	pm.spread = 30.0
	pm.initial_velocity_min = up_speed * 0.5
	pm.initial_velocity_max = up_speed
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.3, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.color = color
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = sparkle_mat(Color.WHITE)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## Critique objects r1 re-run: the soft round sparkles around truffles and pages read as lens bokeh. Twinkles are
## small 4-point stars (the glint texture), additive, each one popping 0 -> 1 -> 0 over its short life; few at a time.
static func twinkles(parent: Node3D, color: Color, amount: int = 6, radius: float = 0.5, size: float = 0.1, lifetime: float = 0.45) -> GPUParticles3D:
	var p := sparkles(parent, color, mini(amount, 6), radius, size, lifetime, 0.05)
	p.randomness = 0.6
	var pm := p.process_material as ParticleProcessMaterial
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.45, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.angle_min = 0.0
	pm.angle_max = 45.0
	var m := unshaded(Color.WHITE, true)
	m.albedo_texture = ObjGlints.star_tex()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.render_priority = 2
	(p.draw_pass_1 as QuadMesh).material = m
	return p


## One-shot burst (confetti, splinters, mud, puffs). Frees itself.
static func burst(parent: Node, at: Vector3, color: Color, amount: int = 24, speed: float = 4.0, size: float = 0.18, gravity: float = -9.0, lifetime: float = 0.9, always: bool = false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := GPUParticles3D.new()
	if always:
		p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color = color
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := unshaded(Color.WHITE)
	m.albedo_texture = radial_tex(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.draw_pass_1 = q
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	var t := p.create_tween()
	t.tween_interval(lifetime + 0.3)
	t.tween_callback(p.queue_free)


# ---------------------------------------------------------------- vfx workstream hooks (optional)

## Spawns res://scenes/fx/<scene_name>.tscn (vfx workstream) at `at`. Returns false when it does not exist,
## so callers can fall back to ObjSvc.burst().
static func fx(context: Node, scene_name: String, at: Vector3, always: bool = false) -> bool:
	if context == null or not context.is_inside_tree():
		return false
	var path := "res://scenes/fx/%s.tscn" % scene_name
	if not ResourceLoader.exists(path):
		return false
	var ps := load(path) as PackedScene
	if ps == null:
		return false
	var n := ps.instantiate() as Node3D
	if n == null:
		return false
	if "autoplay" in n:
		n.set("autoplay", false)
	if always:
		n.process_mode = Node.PROCESS_MODE_ALWAYS
	var host: Node = context.get_parent() if context.get_parent() != null else context
	host.add_child(n)
	n.global_position = at
	if n.has_method("play"):
		n.call("play")
	return true


## Loads a shared material from res://assets/shaders/materials/<name>.tres (vfx workstream), or null.
static func vfx_material(material_name: String, duplicate_it: bool = false) -> Material:
	var path := "res://assets/shaders/materials/%s.tres" % material_name
	if not ResourceLoader.exists(path):
		return null
	var m := load(path) as Material
	if m != null and duplicate_it:
		m = m.duplicate() as Material
	return m


# ---------------------------------------------------------------- physics helpers

static func make_area(parent: Node3D, shape: Shape3D, layer: int = L_TRIGGER, mask: int = L_PLAYER, pos: Vector3 = Vector3.ZERO, area_name: String = "Area") -> Area3D:
	var a := Area3D.new()
	a.name = area_name
	a.collision_layer = layer
	a.collision_mask = mask
	a.monitorable = true
	a.position = pos
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	parent.add_child(a)
	return a


static func add_shape(body: CollisionObject3D, shape: Shape3D, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation_degrees = rot_deg
	body.add_child(cs)
	return cs


static func box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


static func sphere_shape(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


static func cyl_shape(r: float, h: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return s


static var _bake_cache: Dictionary = {}


## Merges the direct MeshInstance3D children of `v` into one MeshInstance3D (one surface per material) and caches
## the result under `key`, so many copies (acorns) share a single mesh. No shadow casting (objects use blob shadows).
static func bake_visual(v: Node3D, key: String) -> MeshInstance3D:
	var mesh: ArrayMesh = _bake_cache.get(key, null)
	var parts: Array = []
	for c in v.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			parts.append(c)
	if mesh == null:
		var groups: Dictionary = {}
		var order: Array = []
		for mi in parts:
			var m: MeshInstance3D = mi
			var mat: Material = m.material_override
			if not groups.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[mat] = st
				order.append(mat)
			(groups[mat] as SurfaceTool).append_from(m.mesh, 0, m.transform)
		mesh = ArrayMesh.new()
		for mat in order:
			(groups[mat] as SurfaceTool).commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		_bake_cache[key] = mesh
	for mi in parts:
		v.remove_child(mi)
		(mi as Node).queue_free()
	var out := MeshInstance3D.new()
	out.name = "Baked"
	out.mesh = mesh
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(out)
	return out


## True when a Visual slot already holds an authored or generated mesh (so placeholders are skipped).
static func visual_has_content(visual: Node) -> bool:
	return visual != null and visual.get_child_count() > 0


static func ensure_visual(owner_node: Node3D) -> Node3D:
	var v := owner_node.get_node_or_null("Visual") as Node3D
	if v == null:
		v = Node3D.new()
		v.name = "Visual"
		owner_node.add_child(v)
	fill_visual(owner_node, v)
	return v


## Local-space AABB of every MeshInstance3D under `root` (in root's space).
static func local_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := root.global_transform.affine_inverse() * m.global_transform if root.is_inside_tree() else Transform3D()
		var bb := xf * m.mesh.get_aabb()
		if first:
			out = bb
			first = false
		else:
			out = out.merge(bb)
	return out


## Moves a generated mesh so its bounds are centred on the slot origin (for spinning pickups).
static func center_generated(v: Node3D) -> void:
	var g := v.get_node_or_null("Generated") as Node3D
	if g == null:
		return
	var bb := local_aabb(v)
	g.position -= bb.get_center()


## Instances owner.visual_scene into `v` when the slot is empty. Returns true when a generated mesh was placed.
static func fill_visual(owner_node: Node, v: Node3D) -> bool:
	if v == null or v.get_child_count() > 0:
		return false
	var vs: Variant = owner_node.get("visual_scene")
	if not (vs is PackedScene):
		return false
	var inst := (vs as PackedScene).instantiate() as Node3D
	if inst == null:
		return false
	inst.name = "Generated"
	var flip: Variant = owner_node.get("visual_flip_180")
	if flip == null or bool(flip):
		inst.rotation.y = PI
	var sc: Variant = owner_node.get("visual_scale")
	if sc != null:
		inst.scale = Vector3.ONE * float(sc)
	v.add_child(inst)
	return true


const TRUFFLE_SCENE := "res://scenes/objects/Truffle.tscn"
const ACORN_SCENE := "res://scenes/objects/Acorn.tscn"


## Spawns a truffle with a pop-up reveal. Returns the new node (or null).
static func spawn_truffle(parent: Node, xform: Transform3D, id: String, reveal: bool = true) -> Node3D:
	var ps := load(TRUFFLE_SCENE) as PackedScene
	if ps == null or parent == null:
		return null
	var t := ps.instantiate() as Node3D
	t.set("truffle_id", id)
	t.set("spawn_revealed", reveal)
	parent.add_child(t)
	t.global_transform = xform
	t.reset_physics_interpolation()
	return t


static func spawn_acorns(parent: Node, at: Vector3, count: int) -> void:
	var ps := load(ACORN_SCENE) as PackedScene
	if ps == null or parent == null:
		return
	feedback("object_acorn_spill", at + Vector3(0, 0.5, 0), {"count": count})
	for i in count:
		var a := ps.instantiate() as Node3D
		parent.add_child(a)
		a.global_position = at + Vector3(0, 0.4, 0)
		if a.has_method("pop_out"):
			var ang := TAU * float(i) / float(maxi(count, 1)) + randf() * 0.4
			a.call("pop_out", Vector3(cos(ang), 0, sin(ang)) * randf_range(1.2, 2.2) + Vector3(0, 5.5, 0))


## Pickups placed inside world collision (critique objects r1): while a small sphere at the pickup's centre overlaps
## layer 1, step the node up 0.1 m (at most max_up); if that never frees it (a ring of acorns inside a tree trunk),
## push it sideways away from the blocking body, 0.15 m at a time up to 1.2 m. Returns the distance moved (-1 when
## still buried: node restored). Call after one physics frame. Prints the node path so builders can move it.
## Round 1 QA: concave (trimesh) shells do not overlap a sphere fully inside them, so a pickup inside a bridge or a
## chimney is also detected with rays (see `inside_concave`) and lifted to just above that shell's top surface.
static func unbury(n: Node3D, center_local: Vector3, radius: float = 0.18, max_up: float = 1.5, quiet: bool = false) -> float:
	if n == null or not n.is_inside_tree():
		return 0.0
	var off: Variant = unbury_offset(n, center_local, radius, max_up)
	if off == null:
		if not quiet:
			push_warning("[ObjSvc] pickup still inside world collision: %s" % n.get_path())
		return -1.0
	var o: Vector3 = off
	if o == Vector3.ZERO:
		return 0.0
	n.global_position += o
	n.reset_physics_interpolation()
	if not quiet:
		push_warning("[ObjSvc] unburied pickup by %.2f m (%s): %s (builders: move it)" % [o.length(), "up" if absf(o.y) > 0.01 else "sideways", n.get_path()])
	return o.length()


## Dry run of unbury: the world offset that frees the pickup (Vector3.ZERO when it is not buried, null when nothing
## within reach frees it). Nothing moves.
static func unbury_offset(n: Node3D, center_local: Vector3, radius: float = 0.18, max_up: float = 1.5) -> Variant:
	if n == null or not n.is_inside_tree():
		return Vector3.ZERO
	var space := n.get_world_3d().direct_space_state
	var c0 := n.global_transform * center_local
	var shell_top: Variant = inside_concave(space, c0)
	var hits := _sphere_hits(space, c0, radius)
	if hits.is_empty() and shell_top == null:
		return Vector3.ZERO
	if shell_top != null:
		# Lift to just above the shell's top face (concave shells can be taller than max_up: allow up to 3 m).
		var up: float = float(shell_top) - c0.y + radius + 0.08
		if up <= maxf(max_up, 3.0) and _sphere_hits(space, c0 + Vector3(0, up, 0), radius).is_empty() 				and inside_concave(space, c0 + Vector3(0, up, 0)) == null:
			return Vector3(0, up, 0)
	var lift := 0.1
	while lift <= max_up + 0.001:
		var p := c0 + Vector3(0, lift, 0)
		if _sphere_hits(space, p, radius).is_empty() and inside_concave(space, p) == null:
			return Vector3(0, lift, 0)
		lift += 0.1
	var away := Vector3.ZERO
	var blocker: Node3D = null
	if not hits.is_empty():
		blocker = hits[0].get("collider") as Node3D
	if blocker != null:
		away = c0 - blocker.global_position
		away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	var side := 0.15
	while side <= 1.2 + 0.001:
		var p2 := c0 + away * side
		if _sphere_hits(space, p2, radius).is_empty() and inside_concave(space, p2) == null:
			return away * side
		side += 0.15
	return null


static func _sphere_hits(space: PhysicsDirectSpaceState3D, at: Vector3, radius: float) -> Array[Dictionary]:
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius
	q.shape = sh
	q.collision_mask = L_WORLD
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.transform = Transform3D(Basis(), at)
	return space.intersect_shape(q, 1)


## True-ish test for "inside a closed concave shell" without back-face ray hits (Jolt ignores them): a top face
## seen from above (normal up) that a ray from the point upward cannot reach, and a bottom face seen from below
## (normal down) that a ray from the point downward cannot reach, on the same collider. Returns the top face height
## (float) or null. An interior under a one-sided roof is not "inside": the ray down from the point meets its floor.
static func inside_concave(space: PhysicsDirectSpaceState3D, p: Vector3, reach: float = 6.0) -> Variant:
	var a := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, reach, 0), p, L_WORLD))
	if a.is_empty() or (a["normal"] as Vector3).y < 0.3:
		return null
	var top_y: float = (a["position"] as Vector3).y
	var b := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3(0, reach, 0), L_WORLD))
	if not b.is_empty() and (b["position"] as Vector3).y < top_y - 0.01:
		return null
	var c := space.intersect_ray(PhysicsRayQueryParameters3D.create(p - Vector3(0, reach, 0), p, L_WORLD))
	if c.is_empty() or (c["normal"] as Vector3).y > -0.3 or c.get("collider") != a.get("collider"):
		return null
	var bottom_y: float = (c["position"] as Vector3).y
	var d := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - Vector3(0, reach, 0), L_WORLD))
	if not d.is_empty() and (d["position"] as Vector3).y > bottom_y + 0.01:
		return null
	return top_y

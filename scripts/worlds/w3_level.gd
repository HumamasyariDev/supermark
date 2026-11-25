extends Node3D
## W3 Gingerbread Grove runtime level builder. Places everything that is not baked: liquids, cake tiers,
## frosting slide, platforms, landmarks, missions (W3-1..W3-8, W3-100), enemies, NPC, collectibles,
## checkpoints, props and ambient life. Data: res://scenes/worlds/w3/w3_level.json (copy of
## data/levels/W3.json, written by w3_bake.gd). Deterministic: every random choice uses fixed seeds.
## Gameplay surfaces are simple primitives at the plan coordinates; generated meshes are visual only.

const B := "res://scenes/worlds/w3/baked/"
const DATA := "res://scenes/worlds/w3/w3_level.json"
const Geo := preload("res://scripts/worlds/w3_geo.gd")
const G := 28.0   # player rising gravity (MovementProfile.gravity)

const P_COTTAGE := "res://assets/props/w3/gingerbread_cottage/gingerbread_cottage.glb"
const P_CAULDRON := "res://assets/props/w3/cauldron/cauldron.glb"
const P_LID := "res://assets/props/w3/cauldron/cauldron_lid.glb"
const P_CUPCAKE := "res://assets/props/w3/cupcake_tower/cupcake_tower.glb"
const P_CANE := "res://assets/props/w3/candy_cane/candy_cane.glb"
const P_FENCE := "res://assets/props/w3/candy_cane/candy_cane_fence.glb"
const P_ROCK := "res://assets/props/w3/candy_rock/candy_rock.glb"
const P_BISCUIT := "res://assets/props/w3/biscuit_platform/biscuit_platform.glb"
const P_CHOCBAR := "res://assets/props/w3/chocolate_bar_bridge/chocolate_bar_bridge.glb"
const P_GUMDROPS := ["res://assets/props/w3/gumdrop/gumdrop.glb", "res://assets/props/w3/gumdrop/gumdrop_mint.glb",
	"res://assets/props/w3/gumdrop/gumdrop_violet.glb", "res://assets/props/w3/gumdrop/gumdrop_orange.glb"]
const P_LOLLIS := ["res://assets/props/w3/lollipop_tree/lollipop_tree.glb", "res://assets/props/w3/lollipop_tree/lollipop_tree_mint.glb",
	"res://assets/props/w3/lollipop_tree/lollipop_tree_red.glb"]
const P_LOLLI_GRUMPY := "res://assets/props/w3/lollipop_tree/lollipop_tree_grumpy.glb"
const P_MARSH := ["res://assets/props/w3/marshmallow/marshmallow.glb", "res://assets/props/w3/marshmallow/marshmallow_pink.glb",
	"res://assets/props/w3/marshmallow/marshmallow_toasted.glb"]
const E_GRENADIER := "res://scenes/enemies/GingerbreadGrenadier.tscn"
const E_BRUTE := "res://scenes/enemies/GummyBrute.tscn"
const E_CROW := "res://scenes/enemies/CrowBandit.tscn"
const M_GRENADIER := "res://assets/enemies/gingerbread_grenadier/gingerbread_grenadier.glb"
const O := "res://scenes/objects/"
const BALCONY_Z := 34.5

var data: Dictionary = {}
var H := PackedFloat32Array()
var enemies := {}          # id -> enemy node
var _mat_cache := {}
var _scene_cache := {}
var _toon: Shader
var _hot_cd := 0.0
var _hot_fly := false
var _acorn_hundred: Node3D
var _blob_t := 2.0
var _blob_busy := false
var _slide_c := PackedVector3Array()
var _joust: Node3D
var _crumb_cfg := {}
var _gate_open := false
var _drum_skin: MeshInstance3D
var _drum_mats: Array = []


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var hb := FileAccess.get_file_as_bytes(B + "heights.bin")
	H = hb.to_float32_array()
	_toon = load("res://assets/shaders/toon.gdshader")
	var arr: Variant = JSON.parse_string(FileAccess.get_file_as_string(B + "slide_center.json"))
	for q in arr:
		_slide_c.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	_build_liquids()
	_build_cake_peak()
	_build_slide()
	_build_pipe()
	_build_cottage_knoll()
	_build_bridges()
	_build_lagoon()
	_build_lollipop_and_gumdrops()
	_build_fort()
	_build_woods_and_clearing()
	_build_falls_and_grotto()
	_build_glade()
	_build_enemies()
	_build_collectibles()
	_build_checkpoints()
	_build_props()
	_build_ambient()
	_build_horizon()
	_build_entrance_funnel()
	_build_r3_extras()
	_build_camera_zones()
	_apply_world_state()
	_build_dev_markers()
	# R1 QA major (frame spikes in the glade): fade out small OmniLights beyond 45 m (the kitchen set has its own).
	for ol in find_children("*", "OmniLight3D", true, false):
		var o := ol as OmniLight3D
		if o.omni_range <= 6.0:
			o.distance_fade_enabled = true
			o.distance_fade_begin = 40.0
			o.distance_fade_length = 10.0
			o.distance_fade_shadow = 20.0
	print("[W3] level built in %d ms" % (Time.get_ticks_msec() - t0))
	call_deferred("_maybe_intro")
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_method("has_arg") and dev.call("has_arg", "w3-bot"):
		var plan_name := String(dev.call("arg", "w3-bot", ""))
		var plans := _bot_plans()
		if plans.has(plan_name):
			var bot := Node.new()
			bot.name = "W3Bot"
			bot.set_script(load("res://scripts/worlds/w3_bot.gd"))
			add_child(bot)
			bot.call("setup", plan_name, plans[plan_name], 90.0)
			print("[W3 bot] plan %s with %d steps" % [plan_name, plans[plan_name].size()])
		else:
			push_warning("[W3 bot] unknown plan " + plan_name)


# ================================================================ helpers

func h_at(x: float, z: float) -> float:
	var fx := clampf((x - Geo.X0) / Geo.STEP, 0.0, Geo.NX - 1.001)
	var fz := clampf((z - Geo.Z0) / Geo.STEP, 0.0, Geo.NZ - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := H[iz * Geo.NX + ix]
	var b := H[iz * Geo.NX + ix + 1]
	var c := H[(iz + 1) * Geo.NX + ix]
	var d := H[(iz + 1) * Geo.NX + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


static func v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func toon(col: Color, tex: String = "", scale: float = 0.35, vc: bool = false, rough: float = 0.8, emis: Color = Color.BLACK, emis_e: float = 0.0, rim: float = 0.45, spec: float = 0.35) -> ShaderMaterial:
	var key := "%s|%s|%.2f|%s|%.2f|%s|%.2f|%.2f|%.2f" % [col.to_html(), tex, scale, vc, rough, emis.to_html(), emis_e, rim, spec]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _toon
	m.set_shader_parameter("albedo", col)
	if tex != "":
		m.set_shader_parameter("albedo_texture", load("res://assets/textures/%s.webp" % tex))
		m.set_shader_parameter("triplanar", true)
		# R1 visual major: the noisy orange sponge texture covered half the world in micro detail. The gingerbread
		# pattern is now 2.5x larger (soft colour blocks instead of noise).
		m.set_shader_parameter("triplanar_scale", scale * (0.4 if tex == "gingerbread" else 1.0))
	m.set_shader_parameter("use_vertex_color", vc)
	m.set_shader_parameter("shadow_tint", Color(0.44, 0.4, 0.62))   # R1 grade: deeper shadows than the shared pale default
	m.set_shader_parameter("roughness_value", rough)
	m.set_shader_parameter("rim_strength", rim)
	m.set_shader_parameter("spec_strength", spec)
	if emis_e > 0.0:
		m.set_shader_parameter("emission_color", emis)
		m.set_shader_parameter("emission_energy", emis_e)
	_mat_cache[key] = m
	return m


func vc_mat(rough: float = 0.7, spec: float = 0.35) -> ShaderMaterial:
	return toon(Color.WHITE, "", 0.35, true, rough, Color.BLACK, 0.0, 0.45, spec)


func scene(path: String) -> PackedScene:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _scene_cache[path]


## Instances a generated GLB. `face_south` keeps the glTF +Z front toward world +Z (south, toward the camera).
func glb(path: String, pos: Vector3, rot_y: float = 0.0, scl: Variant = 1.0, parent: Node = null, shadows: bool = true) -> Node3D:
	var ps := scene(path)
	var n: Node3D
	if ps == null:
		n = Node3D.new()
	else:
		n = ps.instantiate() as Node3D
	(parent if parent else self).add_child(n)
	n.position = pos
	n.rotation_degrees.y = rot_y
	if scl is Vector3:
		n.scale = scl
	else:
		n.scale = Vector3.ONE * float(scl)
	if not shadows:
		for mi in n.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func mesh_node(m: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, parent: Node = null, nm: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	if nm != "":
		mi.name = nm
	(parent if parent else self).add_child(mi)
	return mi


func body(nm: String, pos: Vector3, parent: Node = null, surface: String = "") -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = nm
	b.collision_layer = 1
	b.collision_mask = 0
	if surface != "":
		b.set_meta("surface", surface)
	(parent if parent else self).add_child(b)
	b.position = pos
	return b


func box_shape(b: CollisionObject3D, size: Vector3, offset: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = offset
	cs.rotation_degrees = rot
	b.add_child(cs)
	return cs


func cyl_shape(b: CollisionObject3D, r: float, h: float, offset: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	cs.shape = s
	cs.position = offset
	b.add_child(cs)
	return cs


## Rounded vertex-coloured box: solid body plus mesh. pos is the box centre.
func rbox(nm: String, pos: Vector3, size: Vector3, top: Color, side: Color, r: float = 0.15, mat: Material = null, parent: Node = null, solid: bool = true) -> Node3D:
	var n: Node3D
	if solid:
		n = body(nm, pos, parent)
		box_shape(n as CollisionObject3D, size)
	else:
		n = Node3D.new()
		n.name = nm
		(parent if parent else self).add_child(n)
		n.position = pos
	mesh_node(Geo.rounded_box(size, r, 3, top, side), mat if mat else vc_mat(), Vector3.ZERO, n)
	return n


## Lathe cylinder (rounded rims) with optional body. pos = base centre.
func rcyl(nm: String, base: Vector3, r: float, h: float, top: Color, side: Color, solid: bool = true, mat: Material = null, parent: Node = null, segs: int = 28) -> Node3D:
	var n: Node3D
	if solid:
		n = body(nm, base, parent)
		cyl_shape(n as CollisionObject3D, r, h, Vector3(0, h * 0.5, 0))
	else:
		n = Node3D.new()
		n.name = nm
		(parent if parent else self).add_child(n)
		n.position = base
	var e := minf(0.12, h * 0.25)
	var prof := [Vector2(r * 0.96, 0.0), Vector2(r, e), Vector2(r, h - e), Vector2(r * 0.94, h - e * 0.2), Vector2(r * 0.6, h), Vector2(0.0, h)]
	var cols := [side.darkened(0.08), side, side, top, top, top]
	mesh_node(Geo.lathe(prof, segs, 1.0, 1.0, cols), mat if mat else vc_mat(), Vector3.ZERO, n)
	return n


func sphere_mesh(r: float, col: Color, rough: float = 0.4) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	mi.material_override = toon(col, "", 0.35, false, rough, Color.BLACK, 0.0, 0.5, 0.6)
	return mi


func inst(path: String, pos: Vector3, parent: Node = null, props: Dictionary = {}) -> Node3D:
	var ps := scene(path)
	if ps == null:
		push_warning("[W3] missing scene " + path)
		return null
	var n := ps.instantiate() as Node3D
	for k in props:
		n.set(k, props[k])
	# R1 QA fix: set the position BEFORE add_child, so _ready() code that records global_position (EnemyBase.home,
	# patrol anchors, object rest points) sees the real spot instead of the world origin.
	var par: Node = parent if parent else self
	if par is Node3D and par.is_inside_tree():
		n.transform.origin = (par as Node3D).global_transform.affine_inverse() * pos
	else:
		n.position = pos
	par.add_child(n)
	n.global_position = pos
	return n


func group_node(nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	add_child(n)
	return n


## Bouncy surface (contract: group "bouncy" + meta bounce_velocity). apex = metres above the top.
func make_bouncy(b: Node, apex: float) -> void:
	b.add_to_group("bouncy")
	b.set_meta("bounce_velocity", sqrt(2.0 * G * apex))
	b.set_meta("surface", "candy")


func squash_on_land(b: Node3D, vis: Node3D, top_local: float, radius: float) -> void:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 2
	a.monitorable = false
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = 0.6
	cs.shape = s
	cs.position = Vector3(0, top_local + 0.3, 0)
	a.add_child(cs)
	b.add_child(a)
	var base := vis.scale
	a.body_entered.connect(func(body_n: Node) -> void:
		if not body_n.is_in_group("player"):
			return
		if b.has_meta("next_dome"):
			_gum_assist(body_n, b.get_meta("next_dome"))
		else:
			_reaim(body_n)
		ObjSvc.sfx("bounce_gumdrop", b.global_position)
		if b.has_meta("slam_bounce_velocity"):
			_grumpy_bounce(b, body_n)
		var tw := vis.create_tween()
		tw.tween_property(vis, "scale", base * Vector3(1.18, 0.72, 1.18), 0.07)
		tw.tween_property(vis, "scale", base * Vector3(0.92, 1.12, 0.92), 0.12)
		tw.tween_property(vis, "scale", base, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))


## Grumpy gumdrop (R1.7): a Ham Slam landing gets the super-bounce; a normal landing gets a weak one and a "Hmph!".
func _grumpy_bounce(b: Node3D, pl: Node) -> void:
	var slam := pl.has_method("is_ground_pounding") and bool(pl.call("is_ground_pounding"))
	var txt := "Oof!" if slam else "Hmph!"
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = 96
	lbl.outline_size = 14
	lbl.modulate = Color("#FFF7EE")
	lbl.outline_modulate = Color("#8A2E2E")
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.006
	add_child(lbl)
	lbl.global_position = b.global_position + Vector3(0, 2.6, 0)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y + 1.2, 0.8)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)
	if not slam:
		return
	var v := float(b.get_meta("slam_bounce_velocity"))
	for k in 20:
		await get_tree().physics_frame
		if not is_instance_valid(pl):
			return
		var st := String(pl.call("get_state_name")) if pl.has_method("get_state_name") else ""
		if st == "bounce" or bool(pl.get("grounded")):
			pl.call("bounce", v)
			ObjSvc.burst(self, b.global_position + Vector3(0, 1.6, 0), Color(1.0, 0.9, 0.5), 24, 6.0, 0.14, -8.0, 0.7)
			print("[W3] grumpy gumdrop super-bounce")
			if b.get_meta("deflates", false):
				# R2.2: deflated for 2 s after a slam-bounce: solid, sagging, not bouncy.
				b.remove_from_group("bouncy")
				var vis := b.get_child(b.get_child_count() - 1) as Node3D
				for c in b.get_children():
					if c is Node3D and c.scene_file_path != "":
						vis = c
				var base := vis.scale
				var dtw := vis.create_tween()
				dtw.tween_property(vis, "scale", base * Vector3(1.15, 0.55, 1.15), 0.2)
				dtw.tween_interval(1.8)
				dtw.tween_property(vis, "scale", base, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
				dtw.tween_callback(func() -> void: b.add_to_group("bouncy"))
			return


## R1 feel fix (Gumdrop Hop overshoot): a bounce kept the full run speed, so holding the stick at the next dome flew
## past it. For one bounce arc, while the stick points within 50 degrees of the next dome, Mak faces that dome and his
## forward speed is set each tick so he arrives over its centre; with the stick released his speed is capped at 3.5 m/s.
func _gum_assist(pl: Node, target: Vector3) -> void:
	var started := false
	var ring: MeshInstance3D = null
	for k in 110:
		await get_tree().physics_frame
		if not is_instance_valid(pl):
			break
		var st := String(pl.call("get_state_name")) if pl.has_method("get_state_name") else ""
		if not started:
			if st == "bounce":
				started = true
				# R1 feel re-check: the first bounce peaked 6.7 m against the designed 4.6 m; clamp the apex.
				var vmax := sqrt(2.0 * 28.125 * 4.6)
				if float(pl.get("vy")) > vmax:
					pl.set("vy", vmax)
				var inp0: Variant = pl.get("inp")
				if inp0 == null or float((inp0 as Object).get("stick_mag")) < 0.2:
					pl.set("forward_speed", minf(float(pl.get("forward_speed")), 3.5))
				ring = _target_ring(target)
			elif k > 12:
				break
			continue
		if st != "bounce" and st != "fall":
			break
		var p := (pl as Node3D).global_position
		var vy := float(pl.get("vy"))
		var dy := p.y - (target.y + 0.05)
		var disc := vy * vy + 2.0 * 28.125 * dy
		if disc < 0.0:
			continue   # cannot reach this dome's height on this arc (weak grumpy bounce)
		var t_rem := (vy + sqrt(disc)) / 28.125
		var to := Vector3(target.x - p.x, 0.0, target.z - p.z)
		var d := to.length()
		var inp: Variant = pl.get("inp")
		if inp == null or float((inp as Object).get("stick_mag")) < 0.2:
			pl.set("forward_speed", minf(float(pl.get("forward_speed")), 3.5))
			continue
		var iy: float = float(pl.get("intended_yaw"))
		var want_yaw := atan2(-to.x, -to.z)
		if absf(angle_difference(iy, want_yaw)) > deg_to_rad(75.0) or d < 0.25:
			continue
		pl.set("facing_yaw", want_yaw)
		pl.set("forward_speed", clampf(d / maxf(t_rem, 0.12), 0.0, 7.5))
	if ring and is_instance_valid(ring):
		var tw := ring.create_tween()
		tw.tween_property(ring, "scale", Vector3(0.2, 0.2, 0.2), 0.2)
		tw.tween_callback(ring.queue_free)


## Gold landing ring on the next gumdrop while Mak is airborne (Gumdrop Hop readability).
func _target_ring(target: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.75
	tm.outer_radius = 0.95
	tm.rings = 24
	tm.ring_segments = 6
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.3, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = target + Vector3(0, 0.12, 0)
	mi.scale = Vector3(1, 0.3, 1)
	return mi


## Bounce re-aim: the controller cannot turn in the air, so a bounce chain that curves (Gumdrop Hop) needs the
## facing to follow the stick at the moment of the bounce. Duck-typed on MakPlayer's facing/intended yaw.
func _reaim(pl: Node) -> void:
	var inp: Variant = pl.get("inp")
	if inp == null or not (inp is Object) or float((inp as Object).get("stick_mag")) < 0.2:
		return
	var iy: Variant = pl.get("intended_yaw")
	if iy is float:
		pl.set("facing_yaw", iy)


func add_fx(scene_name: String, pos: Vector3, parent: Node = null, tint: Variant = null, intensity: float = 1.0) -> Node3D:
	var p := "res://scenes/fx/%s.tscn" % scene_name
	if not ResourceLoader.exists(p):
		return null
	var n := (load(p) as PackedScene).instantiate() as Node3D
	(parent if parent else self).add_child(n)
	n.global_position = pos
	if tint != null and "tint" in n:
		n.set("tint", tint)
	if "intensity" in n:
		n.set("intensity", intensity)
	if n.has_method("set_active"):
		n.call("set_active", true)
	return n


# ================================================================ liquids and hazard

func _liquid_mat(pink: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/environment/w3/w3_liquid.gdshader")
	if pink:
		m.set_shader_parameter("dark_color", Color(0.86, 0.27, 0.48))
		m.set_shader_parameter("mid_color", Color(1.0, 0.45, 0.64))
		m.set_shader_parameter("cream_color", Color(1.0, 0.86, 0.92))
		m.set_shader_parameter("pop_amount", 0.0)
		m.set_shader_parameter("self_glow", 0.25)
	else:
		# R1 visual major: the river read mauve-grey and mottled. Satin milk chocolate: #5A2E1B -> #7A4128 with a
		# low-frequency swirl, softer caramel highlights.
		m.set_shader_parameter("dark_color", Color("#5A2E1B"))
		m.set_shader_parameter("mid_color", Color("#7A4128"))
		m.set_shader_parameter("cream_color", Color("#C98A55"))
		m.set_shader_parameter("swirl_scale", 0.16)
		m.set_shader_parameter("gloss", 0.65)
		m.set_shader_parameter("self_glow", 0.12)
	return m


func _curtain_mat(pink: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/environment/w3/w3_liquid_curtain.gdshader")
	if pink:
		# Night-01 beauty pass: the falls read as a flat white slab in StoryCam A and D (cream streaks plus gloss
		# under the warm key), so the curtain is a saturated raspberry with fewer cream streaks.
		m.set_shader_parameter("dark_color", Color(0.78, 0.16, 0.42))
		m.set_shader_parameter("mid_color", Color(0.96, 0.36, 0.6))
		m.set_shader_parameter("cream_color", Color(1.0, 0.68, 0.82))
		m.set_shader_parameter("pop_amount", 0.0)
		m.set_shader_parameter("self_glow", 0.12)
		m.set_shader_parameter("gloss", 0.45)
	m.set_shader_parameter("curtain_speed", 1.8)
	return m


func _build_liquids() -> void:
	var choc := mesh_node(load(B + "chocolate.mesh.res"), _liquid_mat(false), Vector3.ZERO, self, "HotChocolate")
	choc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var syr := mesh_node(load(B + "syrup.mesh.res"), _liquid_mat(true), Vector3.ZERO, self, "SyrupPool")
	syr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Chocolate Falls off the east page edge (x 60) into the candyfloss void.
	var cf := mesh_node(load(B + "choc_falls.mesh.res"), _curtain_mat(false), Vector3(60.2, 0.0, 22.0), self, "ChocolateFalls")
	cf.rotation_degrees.y = 90.0
	cf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Steam over the hot chocolate (reads as hot).
	for p in [Vector3(-30, 0.4, -14), Vector3(-14, 0.4, 1), Vector3(12, 0.4, 7), Vector3(26, 0.4, 13), Vector3(40, 0.4, 15), Vector3(52, 0.4, 20)]:
		add_fx("ChimneySmoke", p, self, Color(1.0, 0.93, 0.88, 0.5), 0.6)


## Hot chocolate is a hazard (damage + knockback toward the nearest bank); the pink Syrup Pool is safe.
func _physics_process(delta: float) -> void:
	_hot_cd = maxf(0.0, _hot_cd - delta)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	var p := pl.global_position
	if _acorn_hundred:
		var mk := _acorn_hundred.get_node_or_null("TruffleMarker") as Node3D
		if mk:
			mk.global_position = p + Vector3(0, 1.8, 0)
	_hot_grace = maxf(0.0, _hot_grace - delta)
	if _hot_fly:
		# R1 feel fix: one splash = one hit. R1 re-check (the throw looped in the lagoon, 4 hits in 6 s): the throw lasts
		# until Mak stands on real bank (h >= 0.6), then 1.0 s of grace; landing in the river again re-throws him with
		# no damage, and hot chocolate deals at most 1 damage per 2.0 s.
		if (pl as CharacterBody3D).is_on_floor():
			if h_at(p.x, p.z) >= 0.6:
				_hot_fly = false
				_hot_grace = 1.0
			elif p.y < 0.6 and _hot_cd <= 0.0:
				_hot_cd = 0.5
				_hot_splash(pl, p, false)
	# W3-3 fairness pass: a ridden biscuit's top is 0.7 - 0.15 dip - 0.03 bob - up to 0.045 tilt at the rim, about
	# 0.48, so Mak standing near a biscuit's edge read as "in the chocolate" (p.y < 0.5) and was burned and thrown.
	# Standing on something above 0.40 is safe; a sagged biscuit (top about 0.3) still burns.
	var hot_y := 0.40 if (pl as CharacterBody3D).is_on_floor() else 0.5
	if not _hot_fly and _hot_cd <= 0.0 and _hot_grace <= 0.0 and p.y < hot_y and p.x > -60.0 and p.x < 60.0 and p.z > -55.0 and p.z < 55.0:
		if h_at(p.x, p.z) < 0.28 and Vector2(p.x + 44.0, p.z + 33.0).length() > 9.0:
			_hot_cd = 0.9
			_hot_splash(pl, p, Time.get_ticks_msec() - _hot_last_dmg >= 2000)
	_pole_step(pl)
	_blob_step(delta, p)
	_maze_step(p)
	_kitchen_step(delta, p)
	_slab_step(delta, pl)
	_spire_step(delta, pl)


var _pole_oriented := false


## R1 feel blocker: the pole jump leaves radially away from the pole, so a player who climbed from the lift side was
## thrown 13 m off the cake. On grabbing CandyPoleD, Mak is turned to the side facing tier D (back to tier D), so the
## jump always lands on tier D's bare east icing (the candles now flank that landing spot).
func _pole_step(pl: Node3D) -> void:
	var st := String(pl.call("get_state_name")) if pl.has_method("get_state_name") else ""
	if st != "pole_climb":
		_pole_oriented = false
		return
	var pole: Variant = pl.get("pole")
	if pole is Node and is_instance_valid(pole) and String((pole as Node).name) == "CandyPoleD":
		# Held every frame (orbit locked): a stick held toward tier D with a north-facing camera reads as "orbit"
		# and used to swing Mak round to the wrong side (bot w3pole, 12:10 Bangkok).
		_pole_oriented = true
		pl.set("pole_angle", 0.0)   # radial = -X (toward tier D); see MakPlayer._grab_pole basis (u = -X, w = +Z)


## R1 feel fix (hot chocolate drained 3-4 health): the first splash deals 1 damage and throws Mak on a ballistic arc
## that lands about 1.2 m inside the nearest safe bank (terrain above 0.6 m), so he never walks the river bed.
var _hot_grace := 0.0
var _hot_last_dmg := -100000


func _hot_splash(pl: Node3D, p: Vector3, hurt: bool = true) -> void:
	var best := Vector3.INF
	var best_d := 1e9
	for k in 32:
		var a := TAU * float(k) / 32.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var r := 0.5
		while r < 18.0 and r < best_d:
			var q := p + dir * r
			if h_at(q.x, q.z) > 0.6:
				var t := q + dir * 2.2
				if h_at(t.x, t.z) > 0.8 and r < best_d:
					best_d = r
					best = Vector3(t.x, h_at(t.x, t.z), t.z)
				break
			r += 0.5
	if best == Vector3.INF:
		best = Vector3(p.x, 1.0, p.z + 3.0)
	var to := Vector3(best.x - p.x, 0.0, best.z - p.z)
	var dist := to.length()
	var dirn := to.normalized() if dist > 0.01 else Vector3(0, 0, 1)
	if hurt and pl.has_method("take_damage"):
		_hot_last_dmg = Time.get_ticks_msec()
		pl.call("take_damage", 1, p - dirn * 2.0, 11.0)
	if pl.get("state") != "hurt_air" and pl.has_method("_set_state"):
		pl.set("grounded", false)
		pl.call("_set_state", "hurt_air")
	var g := 28.125
	var vy := 11.0 if dist < 7.0 else 13.0
	var dy := best.y + 0.2 - p.y
	var disc := vy * vy - 2.0 * g * dy
	if disc < 0.0:
		vy = sqrt(2.0 * g * maxf(dy, 0.5)) + 1.5
		disc = vy * vy - 2.0 * g * dy
	var t_f := (vy + sqrt(maxf(disc, 0.0))) / g
	var spd := clampf((dist + 0.5 * 2.46 * t_f * t_f) / maxf(t_f, 0.2), 2.0, 17.0)
	pl.set("facing_yaw", atan2(dirn.x, dirn.z))   # face away from the bank: Mak is thrown backwards onto it
	pl.set("forward_speed", -spd)
	pl.set("vy", vy)
	_hot_fly = true
	ObjSvc.burst(self, p + Vector3(0, 0.3, 0), Color(1.0, 0.55, 0.25), 18, 4.0, 0.16, -9.0, 0.6)
	ObjSvc.sfx("hot_splash", p)


# ================================================================ Frosting Peak

func _build_cake_peak() -> void:
	var peak := group_node("FrostingPeak")
	for t in data["cake_tiers"]:
		var id := String(t["id"])
		var b := body(id, Vector3(float(t["c"][0]), 0, float(t["c"][1])), peak, "frosting")
		var cs := CollisionShape3D.new()
		cs.shape = load(B + "tier_%s.shape.res" % id)
		b.add_child(cs)
		mesh_node(load(B + "tier_%s.mesh.res" % id), vc_mat(0.45, 0.5), Vector3.ZERO, b)
		if id == "tier_E_summit":
			# R1 feel fix: the taller candy pole must not let a ledge grab skip the candle wave.
			b.add_to_group("no_ledge_grab")
			b.set_meta("no_ledge_grab", true)
	# Sprinkles on tier tops (decor) and six lit candles on tier B.
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cap := CapsuleMesh.new()
	cap.radius = 0.06
	cap.height = 0.34
	cap.radial_segments = 6
	cap.rings = 2
	mm.mesh = cap
	var xs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var pal := [Color("#FF7FAF"), Color("#7FE0C2"), Color("#FFE07A"), Color("#8FB8FF"), Color("#FFFFFF"), Color("#E8435A")]
	for t in data["cake_tiers"]:
		var c := Vector2(float(t["c"][0]), float(t["c"][1]))
		var r := Vector2(float(t["r"][0]), float(t["r"][1]))
		var top := float(t["top_y"]) + 0.07
		var n := int(PI * r.x * r.y * 0.3)
		for i in n:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * 0.95
			var p := Vector3(c.x + cos(a) * r.x * d, top, c.y + sin(a) * r.y * d)
			if _covered_by_higher_tier(p, float(t["top_y"])):
				continue
			var bs := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5)
			xs.append(Transform3D(bs, p))
			cols.append(pal[rng.randi() % pal.size()])
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Sprinkles"
	mmi.multimesh = mm
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 0.35
	mmi.material_override = sm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	peak.add_child(mmi)
	var tb: Dictionary = data["cake_tiers"][1]
	for i in 6:
		var a := TAU * (float(i) + 0.5) / 6.0 + 0.4
		var p := Vector3(float(tb["c"][0]) + cos(a) * float(tb["r"][0]) * 0.86, float(tb["top_y"]), float(tb["c"][1]) + sin(a) * float(tb["r"][1]) * 0.86)
		if _covered_by_higher_tier(p, float(tb["top_y"])):
			continue
		var cn := rcyl("Candle%d" % i, p, 0.22, 1.5, Color("#FFF7EE"), Color("#FF9EC4") if i % 2 == 0 else Color("#8FD6FF"), false, null, peak, 12)
		var fl := sphere_mesh(0.16, Color(1.0, 0.75, 0.3))
		fl.material_override = toon(Color(1.0, 0.8, 0.35), "", 0.35, false, 0.5, Color(1.0, 0.6, 0.2), 4.0)
		fl.position = Vector3(0, 1.72, 0)
		fl.scale = Vector3(1, 1.6, 1)
		cn.add_child(fl)
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.75, 0.4)
		ol.light_energy = 0.8
		ol.omni_range = 3.0
		ol.position = Vector3(0, 1.9, 0)
		cn.add_child(ol)
	# Glace cherry on the summit (solid).
	var gc: Dictionary = _plat("glace_cherry")
	var cb := body("GlaceCherry", v3(gc["pos"]), peak)
	var ss := SphereShape3D.new()
	ss.radius = 1.2
	var csc := CollisionShape3D.new()
	csc.shape = ss
	cb.add_child(csc)
	var ch := sphere_mesh(1.2, Color("#D61F3C"), 0.15)
	ch.material_override = toon(Color("#E0213F"), "", 0.35, false, 0.12, Color(0.6, 0.0, 0.1), 0.25, 0.7, 1.2)
	cb.add_child(ch)
	var stem := MeshInstance3D.new()
	var stm := CylinderMesh.new()
	stm.top_radius = 0.07
	stm.bottom_radius = 0.1
	stm.height = 1.4
	stem.mesh = stm
	stem.material_override = toon(Color(0.45, 0.25, 0.12))
	stem.position = Vector3(0.25, 1.65, 0)
	stem.rotation_degrees = Vector3(0, 0, -20)
	cb.add_child(stem)
	# Peak traversal pieces. R1.2a jelly sinkers (jump, jump, double before they sink).
	var jcols := {"jelly_step_1": [Color("#C6F27A"), Color("#8ED44E")], "jelly_step_2": [Color("#FF8FB0"), Color("#E8435A")]}
	for id in ["jelly_step_1", "jelly_step_2"]:
		var p: Dictionary = _plat(id)
		var sz := v3(p["size"])
		var jb := AnimatableBody3D.new()
		jb.name = id
		jb.collision_layer = 1
		jb.collision_mask = 0
		jb.set_meta("surface", "jelly")
		jb.set_script(load("res://scripts/worlds/w3_jelly.gd"))
		jb.set("top_local", sz.y * 0.5)
		jb.set("pad", sz.x - 0.2)
		jb.set("sink_after", float(p.get("sink_after_s", 0.8)))
		jb.position = v3(p["pos"])
		jb.rotation_degrees.y = float(p.get("rot_y", 0))
		box_shape(jb, sz)
		var jv := Node3D.new()
		jv.name = "Visual"
		jb.add_child(jv)
		var jc: Array = jcols[id]
		var jm := mesh_node(Geo.rounded_box(sz, 0.3, 3, jc[0], jc[1]), toon(Color.WHITE, "", 0.35, true, 0.12, jc[1], 0.25, 0.9, 1.4), Vector3.ZERO, jv)
		jm.position.y = 0.0
		peak.add_child(jb)
	var pp: Dictionary = _plat("peppermint_pillar")
	var ppb := rbox("peppermint_pillar", v3(pp["pos"]), v3(pp["size"]), Color("#FFF7EE"), Color("#FF5C7A"), 0.3, toon(Color.WHITE, "candy_stripes", 0.5, true, 0.3), peak)
	if ppb is CollisionObject3D:
		(ppb as CollisionObject3D).collision_layer = 4   # R1 feel: the camera arm passes through the MA2 pillar
	var mb: Dictionary = _plat("marshmallow_bouncer")
	var mpos := v3(mb["pos"])
	var mbody := body("marshmallow_bouncer", mpos - Vector3(0, 0.4, 0), peak)
	cyl_shape(mbody, 0.9, 0.8, Vector3(0, 0.4, 0))
	make_bouncy(mbody, 5.8)
	var mv := glb(P_MARSH[2], Vector3.ZERO, 0.0, Vector3(1.55, 0.7, 1.55), mbody)
	squash_on_land(mbody, mv, 0.8, 0.85)
	# Chocolate-bar lift on tier B (16.3 -> 20.3).
	var lift := _make_lift("choc_lift", Vector3(51.0, 16.0, -41.0), 4.0, 2.0, 1.0, peak, true)
	lift.name = "ChocLift"
	# Candy-cane pole C -> D (R1.2c: y 20 -> 23).
	var pd: Dictionary = _plat("candy_pole_D")
	var pdp := v3(pd["pos"])
	var pdh := float(pd["size"][1])
	var pole := inst(O + "Climbable.tscn", pdp - Vector3(0, pdh * 0.5, 0), peak, {"look": 1, "height": pdh, "pole_radius": 0.35})
	if pole:
		pole.name = "CandyPoleD"
		_stripe_pole(pole, pdh, 0.36)
	# Landing biscuit on tier D where the pole jump lands (between candles 1 and 2).
	var lbm := MeshInstance3D.new()
	var lcm := CylinderMesh.new()
	lcm.top_radius = 0.9
	lcm.bottom_radius = 0.95
	lcm.height = 0.08
	lcm.radial_segments = 32
	lbm.mesh = lcm
	lbm.material_override = toon(Color("#F3C77A"), "", 0.35, false, 0.6, Color(1.0, 0.75, 0.3), 0.25)
	peak.add_child(lbm)
	lbm.position = Vector3(43.3, 24.04, -42.0)
	# R1.2b candle wave: three striped birthday candles whose flames go out in a travelling wave.
	var wax := [Color("#FFE07A"), Color("#FF8FB8"), Color("#7FE0C2")]
	var ci := 0
	for p in data["platforms"]:
		if String(p["kind"]) != "flame_candle":
			continue
		var pos := v3(p["pos"])
		var sz := v3(p["size"])
		var cyc: Dictionary = p.get("cycle", {})
		var cnd := StaticBody3D.new()
		cnd.name = String(p["id"])
		cnd.collision_layer = 1
		cnd.collision_mask = 0
		cnd.set_script(load("res://scripts/worlds/w3_candle.gd"))
		cnd.set("height", sz.y)
		cnd.set("radius", sz.x * 0.5)
		cnd.set("phase_s", float(p.get("phase_s", 0.0)))
		cnd.set("period_s", float(cyc.get("period_s", 3.5)))
		cnd.set("lit_s", float(cyc.get("lit_s", 2.0)))
		cnd.position = pos - Vector3(0, sz.y * 0.5, 0)
		cyl_shape(cnd, sz.x * 0.5, sz.y, Vector3(0, sz.y * 0.5, 0))
		var cm := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = sz.x * 0.5
		cyl.bottom_radius = sz.x * 0.5
		cyl.height = sz.y
		cyl.radial_segments = 24
		cm.mesh = cyl
		cm.material_override = toon(wax[ci % 3], "candy_stripes", 0.7, false, 0.35, Color.BLACK, 0.0, 0.5, 0.8)
		cm.position = Vector3(0, sz.y * 0.5, 0)
		cnd.add_child(cm)
		var wick := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.05
		wm.bottom_radius = 0.05
		wm.height = 0.3
		wick.mesh = wm
		wick.material_override = toon(Color(0.15, 0.1, 0.1))
		wick.position = Vector3(0, sz.y + 0.15, 0)
		cnd.add_child(wick)
		var fl := Node3D.new()
		fl.name = "Flame"
		cnd.add_child(fl)
		fl.position = Vector3(0, sz.y + 0.2, 0)
		var fm := sphere_mesh(0.34, Color(1.0, 0.8, 0.35))
		fm.material_override = toon(Color(1.0, 0.85, 0.4), "", 0.35, false, 0.5, Color(1.0, 0.55, 0.15), 5.0)
		fm.scale = Vector3(1, 1.9, 1)
		fm.position = Vector3(0, 0.35, 0)
		fl.add_child(fm)
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.7, 0.35)
		ol.light_energy = 1.2
		ol.omni_range = 4.0
		ol.position = Vector3(0, 0.6, 0)
		fl.add_child(ol)
		peak.add_child(cnd)
		ci += 1
	# R1.9 cherry on top: flat collider cap (side somersault or standing double from the summit).
	var cc: Dictionary = _plat("glace_cherry_cap")
	var ccb := body("CherryCap", v3(cc["pos"]), peak, "candy")
	cyl_shape(ccb, float(cc["size"][0]) * 0.5, float(cc["size"][1]))
	# Wafer bridge over the Sugar Ravine.
	var wb: Dictionary = _plat("wafer_bridge_peak")
	_wafer(v3(wb["pos"]), v3(wb["size"]), "WaferBridge")


func _covered_by_higher_tier(p: Vector3, top: float) -> bool:
	for t in data["cake_tiers"]:
		if float(t["top_y"]) <= top + 0.01:
			continue
		var dx := (p.x - float(t["c"][0])) / (float(t["r"][0]) + 0.4)
		var dz := (p.z - float(t["c"][1])) / (float(t["r"][1]) + 0.4)
		if dx * dx + dz * dz < 1.0:
			return true
	return false


func _plat(id: String) -> Dictionary:
	for p in data["platforms"]:
		if String(p["id"]) == id:
			return p
	push_warning("[W3] no platform " + id)
	return {"pos": [0, 0, 0], "size": [1, 1, 1]}


func _wafer(center: Vector3, size: Vector3, nm: String, parent: Node = null) -> Node3D:
	var b := rbox(nm, center, size, Color("#F3D08F"), Color("#D9A65E"), 0.12, toon(Color(1.0, 0.95, 0.85), "gingerbread", 0.6, true, 0.8), parent)
	b.set_meta("surface", "wood")
	# Wafer grid ribs on top.
	var n := int(size.x / 0.6)
	var ribs := Node3D.new()
	b.add_child(ribs)
	var m := toon(Color("#E8B96F"))
	for i in n:
		var r := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.05, size.z * 0.96)
		r.mesh = bm
		r.material_override = m
		r.position = Vector3(-size.x * 0.5 + (i + 0.5) * size.x / n, size.y * 0.5 + 0.02, 0)
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ribs.add_child(r)
	return b


func _stripe_pole(pole: Node3D, h: float, r: float) -> void:
	var v := pole.get_node_or_null("Visual") as Node3D
	if v:
		for c in v.get_children():
			c.queue_free()
	else:
		v = Node3D.new()
		v.name = "Visual"
		pole.add_child(v)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = toon(Color.WHITE, "candy_stripes", 0.9, false, 0.25, Color.BLACK, 0.0, 0.5, 0.8)
	mi.position = Vector3(0, h * 0.5, 0)
	v.add_child(mi)
	var top := sphere_mesh(r * 1.5, Color("#FF5C7A"), 0.2)
	top.position = Vector3(0, h + 0.1, 0)
	v.add_child(top)


## AnimatableBody3D lift: rises `travel` m over `move_s`, waits `wait_s` at each end. base = top surface at the low end.
func _make_lift(nm: String, base_top: Vector3, travel: float, move_s: float, wait_s: float, parent: Node, called: bool = false) -> AnimatableBody3D:
	var b := AnimatableBody3D.new()
	b.name = nm
	b.sync_to_physics = false
	b.collision_layer = 1
	b.collision_mask = 0
	parent.add_child(b)
	b.global_position = base_top - Vector3(0, 0.15, 0)
	box_shape(b, Vector3(2.2, 0.3, 2.2))
	var bar := glb(P_CHOCBAR, Vector3(0, -0.25, 0), 0.0, Vector3(0.275, 1.0, 0.76), b)
	bar.rotation_degrees.y = 90.0
	# Liquorice post.
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.22
	cm.height = travel + 1.4
	post.mesh = cm
	post.material_override = toon(Color(0.17, 0.12, 0.18), "", 0.35, false, 0.3)
	parent.add_child(post)
	post.global_position = base_top + Vector3(1.25, (travel + 1.4) * 0.5 - 0.3, 0)
	if called:
		# R2.8 called lift: waits at the bottom until Mak boards, rises, waits, returns after he steps off.
		var sensor := Area3D.new()
		sensor.collision_layer = 0
		sensor.collision_mask = 2
		sensor.monitorable = false
		b.add_child(sensor)
		box_shape(sensor, Vector3(2.0, 0.6, 2.0), Vector3(0, 0.45, 0))
		var low := b.position.y
		b.set_meta("busy", false)
		sensor.body_entered.connect(func(n: Node) -> void:
			if not n.is_in_group("player") or bool(b.get_meta("busy")):
				return
			b.set_meta("busy", true)
			var t1 := b.create_tween()
			t1.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			t1.tween_property(b, "position:y", low + travel, move_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			t1.tween_interval(wait_s)
			t1.tween_callback(func() -> void:
				var t2 := b.create_tween()
				t2.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
				t2.tween_property(b, "position:y", low, move_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(1.0)
				t2.tween_callback(func() -> void: b.set_meta("busy", false))))
		return b
	var tw := b.create_tween().set_loops()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_interval(wait_s)
	tw.tween_property(b, "position:y", b.position.y + travel, move_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(wait_s)
	tw.tween_property(b, "position:y", b.position.y, move_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return b


# ================================================================ frosting slide (W3-4)

func _build_slide() -> void:
	var g := group_node("FrostingSlide")
	var b := body("SlideTrough", Vector3.ZERO, g, "frosting")
	var cs := CollisionShape3D.new()
	cs.shape = load(B + "slide.shape.res")
	b.add_child(cs)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://assets/environment/w3/w3_frosting.gdshader")
	mesh_node(load(B + "slide.mesh.res"), fm, Vector3.ZERO, b)
	var st := mesh_node(load(B + "slide_stilts.mesh.res"), toon(Color.WHITE, "gingerbread", 0.8, true, 0.85), Vector3.ZERO, g, "Stilts")
	st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Conveyor: frosting has no friction, modelled as a downhill push along the trough (wind_zone contract).
	_add_push(g, _slide_c, 7.5, "SlideConveyor")
	# R3.2 The Sled Joust: Corporal Crumb, the W3-4 truffle in his basket and two sled grenadiers (w3_joust.gd).
	_joust = Node3D.new()
	_joust.name = "SledJoust"
	_joust.set_script(load("res://scripts/worlds/w3_joust.gd"))
	g.add_child(_joust)
	_joust.call("setup", _slide_c)
	# Marshmallow pile at the runout.
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	var end := _slide_c[_slide_c.size() - 1]
	for i in 9:
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.6, 4.2)
		var p := end + Vector3(cos(a) * d, 0, sin(a) * d)
		if absf(a - 2.2) < 0.6:
			continue
		p.y = h_at(p.x, p.z) - 0.1
		glb(P_MARSH[2] if i % 3 != 0 else P_MARSH[0], p, rng.randf() * 360.0, rng.randf_range(0.8, 1.3), g)


func _add_push(parent: Node, pts: PackedVector3Array, speed: float, nm: String, width: float = 3.0, max_off: float = 2.2) -> Area3D:
	var conv := Area3D.new()
	conv.name = nm
	conv.collision_layer = 128
	conv.collision_mask = 0
	conv.monitoring = false
	conv.add_to_group("wind_zone")
	conv.set_script(load("res://scripts/worlds/w3_slide_push.gd"))
	conv.set("points", pts)
	conv.set("push_speed", speed)
	conv.set("max_offset", max_off)
	parent.add_child(conv)
	var acc := 0.0
	var next := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var c := pts[i + 1]
		acc += a.distance_to(c)
		if acc < next:
			continue
		next += 2.0
		var cs2 := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(width, 2.0, 3.0)
		cs2.shape = bx
		cs2.position = (a + c) * 0.5 + Vector3(0, 0.9, 0)
		cs2.rotation.y = atan2(c.x - a.x, c.z - a.z)
		conv.add_child(cs2)
	return conv


# ================================================================ liquorice pipe

func _build_pipe() -> void:
	var pm := mesh_node(load(B + "pipe.mesh.res"), vc_mat(0.25, 0.9), Vector3.ZERO, self, "LiquoricePipe")
	pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ================================================================ cottage, cauldron, knoll (W3-6, W3-8 start)

func _build_cottage_knoll() -> void:
	var k := group_node("Knoll")
	# Cottage: generated mesh at 1.4x, door gable facing south. Measured (w3_tool_measure.gd): ridge along z at
	# local x 0, ridge top 7.9 m, eaves 3.5 m at x +-3.82, chimney x 0.18..2.68 z -1.75..0.25 top 9.0.
	var s := 1.4
	var c := Vector3(-6, 8, -29)
	glb(P_COTTAGE, c, 0.0, s, k)
	var hx := 3.82 * s
	var hz := 3.75 * s
	var eave := c.y + 3.5 * s
	var ridge := c.y + 7.9 * s
	# One convex hull (walls + gables + 49-degree roof): too steep to stand on, so a miss slides off.
	var house := body("CottageHull", c, k, "wood")
	var hull := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	var ex := hx - 0.1
	var ez := hz - 0.1
	for zz in [-ez, ez]:
		pts.append_array([Vector3(-ex, 0, zz), Vector3(ex, 0, zz), Vector3(-ex, eave - c.y, zz), Vector3(ex, eave - c.y, zz), Vector3(0, ridge - c.y - 0.05, zz)])
	hull.points = pts
	var hcs := CollisionShape3D.new()
	hcs.shape = hull
	house.add_child(hcs)
	var rc := body("RidgeCap", c, k, "wood")
	box_shape(rc, Vector3(1.3, 0.4, hz * 2.0 - 0.4), Vector3(0, ridge - c.y - 0.2, 0))
	var chim := body("Chimney", c, k, "stone")
	var ch_top := c.y + 9.0 * s
	box_shape(chim, Vector3(2.5 * s - 0.2, ch_top - ridge + 1.0, 2.0 * s - 0.1), Vector3(1.43 * s, ch_top - c.y - (ch_top - ridge + 1.0) * 0.5, -0.75 * s))
	var chim_pos := Vector3(c.x + 1.43 * s, ch_top, c.z - 0.75 * s)
	var csm := add_fx("ChimneySmoke", chim_pos + Vector3(0.6, 0.2, -0.4), k, Color(0.88, 0.7, 0.95, 0.85), 2.2)
	if csm:
		csm.scale = Vector3.ONE * 2.2   # R1 visual minor: the smoke column read tiny from the story cams
		set_meta("chimney_smoke", csm)
		set_meta("chimney_smoke_pos", chim_pos + Vector3(0.6, 0.2, -0.4))
	# R1.1 chimney cap: Ham Slam it to drop down the chimney into the kitchen pocket set (W3-6 truffle is inside).
	var capm := MeshInstance3D.new()
	capm.mesh = Geo.rounded_box(Vector3(2.4, 0.25, 2.0), 0.08, 2, Color("#E2B77A"), Color("#B8733A"))
	capm.material_override = toon(Color.WHITE, "gingerbread", 0.8, true, 0.6, Color(1.0, 0.85, 0.5), 0.15)
	k.add_child(capm)
	capm.global_position = chim_pos + Vector3(0, 0.08, 0)
	var cap_s := SlamSensor.create(capm, 1.3, 0.8, Vector3(0, 0.1, 0))
	cap_s.slammed.connect(func(by: Node) -> void: _enter_kitchen(by, capm))
	_build_kitchen()
	# R2.5 nibble the house: four biscuit tiles at shoulder height (snapped onto the cottage hull faces). A punch or
	# kick chips one off once per visit (3 acorns) and a voice calls from the flue (smoke pulse).
	var nib_lines := {"nibble_tile_S": "Gretel: \"Nibble, nibble, little mouse... oh, it's not the wolf? HELP, we're in the kitchen!\"",
		"nibble_tile_W": "Hansel: \"Who's nibbling our house? ...Please be a hero. Please be a hero.\"",
		"nibble_tile_E": "Gretel: \"Down the CHIMNEY, Mister Pig! That's how villains do it!\"",
		"nibble_tile_N": "Hansel: \"He's stolen our crumbs AND our story!\""}
	for id in nib_lines:
		var tdat: Dictionary = _plat(id)
		var tpos := v3(tdat["pos"])
		var tsz := v3(tdat["size"])
		if absf(tsz.x) < 0.5:
			tpos.x = c.x + signf(tpos.x - c.x) * (hx + 0.12)
		else:
			tpos.z = c.z + signf(tpos.z - c.z) * (hz + 0.12)
		var tile := Node3D.new()
		tile.name = id
		k.add_child(tile)
		tile.global_position = tpos
		var tmi := MeshInstance3D.new()
		tmi.mesh = Geo.rounded_box(tsz, 0.12, 2, Color("#E2B77A"), Color("#B8733A"))
		tmi.material_override = toon(Color.WHITE, "gingerbread", 0.8, true, 0.7)
		tile.add_child(tmi)
		var icing := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.28
		tor.outer_radius = 0.34
		icing.mesh = tor
		icing.material_override = toon(Color("#FFF7EE"))
		icing.rotation_degrees = Vector3(90, 0, 0) if absf(tsz.x) >= 0.5 else Vector3(0, 0, 90)
		tile.add_child(icing)
		var ss := SlamSensor.create(tile, 0.7, 1.0, Vector3(0, -0.5, 0))
		var line: String = nib_lines[id]
		ss.struck.connect(func(_kind: String, _from: Vector3) -> void:
			if tile.get_meta("chipped", false):
				return
			tile.set_meta("chipped", true)
			tmi.visible = false
			icing.visible = false
			ObjSvc.burst(self, tile.global_position, Color(0.85, 0.6, 0.35), 24, 4.0, 0.12, -10.0, 0.7)
			for a in 3:
				var ac := inst(O + "Acorn.tscn", tile.global_position + Vector3(0, 0.2, 0), self)
				if ac and ac.has_method("pop_out"):
					ac.call("pop_out", Vector3(randf_range(-2, 2), 5.0, randf_range(-2, 2)))
			add_fx("ChimneySmoke", chim_pos + Vector3(0, 0.4, 0), self, Color(0.95, 0.8, 1.0, 0.9), 1.6)
			ObjSvc.call_on("UI", "toast", [line])
			print("[W3] nibble %s" % id))
	# Porch awning over the door (bouncy, launches onto the ridge).
	var door_z := c.z + hz
	var aw := body("PorchAwning", Vector3(c.x, 11.0, door_z + 0.75), k)
	box_shape(aw, Vector3(3.4, 0.4, 2.0))
	make_bouncy(aw, 9.2)
	var awv := Node3D.new()
	aw.add_child(awv)
	for i in 7:
		var stripe := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(3.4 / 7.0, 0.22, 1.9)
		stripe.mesh = bm
		stripe.material_override = toon(Color("#FF7FAF") if i % 2 == 0 else Color("#FFF7EE"), "", 0.35, false, 0.5)
		stripe.position = Vector3(-1.7 + (i + 0.5) * 3.4 / 7.0, 0.12, 0)
		stripe.rotation_degrees.x = 12.0
		awv.add_child(stripe)
	for sx in [-1.55, 1.55]:
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.1
		cm.height = 3.0
		post.mesh = cm
		post.material_override = toon(Color.WHITE, "candy_stripes", 1.2, false, 0.3)
		post.position = Vector3(sx, -1.5, 0.7)
		awv.add_child(post)
	squash_on_land(aw, awv, 0.2, 1.4)
	# Cocoa tin step (route start) and the sign.
	var tin: Dictionary = _plat("cocoa_tin_step")
	var tp := v3(tin["pos"])
	var tinb := rcyl("CocoaTin", Vector3(c.x, 8.0, door_z + 3.15), 0.7, 1.25, Color("#C9A27A"), Color("#8A2E2E"), true, null, k)
	tinb.set_meta("surface", "metal")
	# Courtyard crates.
	# Cauldron (generated) at 1.3x with the separate lid; rim y 10.6, lid top about 11.2.
	var cs := 1.3
	var cc := Vector3(3, 8, -29)
	glb(P_CAULDRON, cc, 0.0, cs, k)
	var cb := body("Cauldron", cc, k, "metal")
	cyl_shape(cb, 1.1 * cs, 2.0 * cs, Vector3(0, cs, 0))
	var lid_node := Node3D.new()
	lid_node.name = "CauldronLid"
	k.add_child(lid_node)
	lid_node.position = cc + Vector3(0, 1.952 * cs, 0)
	glb(P_LID, Vector3.ZERO, 0.0, cs, lid_node)
	var lidb := body("LidBody", Vector3.ZERO, lid_node, "metal")
	cyl_shape(lidb, 0.9 * cs, 0.3, Vector3(0, 0.3, 0))
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 1.0, 0.6)
	glow.light_energy = 1.6
	glow.omni_range = 6.0
	glow.position = cc + Vector3(0, 3.2, 0)
	k.add_child(glow)
	add_fx("ChimneySmoke", cc + Vector3(0, 3.3, 0), k, Color(0.6, 1.0, 0.7, 0.8), 0.9)
	var fw: Dictionary = _plat("firewood_step")
	var fwp := v3(fw["pos"])
	_firewood(Vector3(fwp.x, 8.0, cc.z + 1.1 * cs + 0.9), k)
	# Gingerbread picket fence along the knoll rim (visual, plus a low collider on the south drop).
	for i in 9:
		var x := -16.0 + i * 2.4
		if x > -9.0 and x < 0.0:
			continue
		glb(P_FENCE, Vector3(x, h_at(x, -14.6), -14.6), 0.0, 1.0, k)


func _firewood(top_center: Vector3, parent: Node) -> void:
	var b := body("Firewood", top_center + Vector3(0, 0.5, 0), parent, "wood")
	box_shape(b, Vector3(1.4, 1.0, 1.0))
	for i in 5:
		var log_mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 0.2
		cm.height = 1.4
		log_mi.mesh = cm
		log_mi.material_override = toon(Color.WHITE, "candy_stripes", 1.6, false, 0.35)
		log_mi.rotation_degrees = Vector3(0, 0, 90)
		log_mi.position = Vector3(0, -0.3 + (i / 3) * 0.38, -0.25 + (i % 3) * 0.25)
		b.add_child(log_mi)


# ================================================================ kitchen pocket set (W3-6, R1.1 + R2.1)

var _kitchen_cam: Camera3D
var _prev_cam: Camera3D
var _oven_t := 0.0
var _oven_state := "cold"
var _oven_hz: Area3D
var _oven_push: Area3D
var _oven_glow: OmniLight3D
var _oven_door: MeshInstance3D
var _cage_open := false


func _build_kitchen() -> void:
	var kroot := Node3D.new()
	kroot.name = "Kitchen"
	add_child(kroot)
	# R1 visual major: plain darker gingerbread walls (no sponge noise); the floor gets biscuit tiles below.
	var wall_mat := toon(Color.WHITE, "", 0.35, true, 0.8, Color.BLACK, 0.0, 0.5, 0.3)
	var biscuit := toon(Color.WHITE, "", 0.35, true, 0.8)
	for id in ["kitchen_floor", "kitchen_wall_W", "kitchen_wall_E", "kitchen_wall_N", "kitchen_ceiling", "kitchen_oven", "kitchen_pantry_W", "kitchen_pantry_E", "kitchen_table"]:
		var d: Dictionary = _plat(id)
		var pos := v3(d["pos"])
		var sz := v3(d["size"])
		var top := Color("#E2B77A")
		var side := Color("#9A5A2C")
		var m: Material = wall_mat
		match id:
			"kitchen_floor":
				m = biscuit
				top = Color("#F3D08F")
			"kitchen_oven":
				top = Color("#5A3A26")
				side = Color("#3B2416")
				m = toon(Color.WHITE, "", 0.35, true, 0.4, Color.BLACK, 0.0, 0.5, 0.8)
			"kitchen_pantry_W", "kitchen_pantry_E":
				top = Color("#C97B3A")
				side = Color("#8E4E22")
			"kitchen_table":
				top = Color("#F3D08F")
				side = Color("#8E4E22")
		rbox(id, pos, sz, top, side, 0.12, m, kroot)
	# South wall: collision on the enemy layer (3) so Mak collides but the camera spring arm (layer 1 only) does not.
	var sw := StaticBody3D.new()
	sw.name = "kitchen_wall_S"
	sw.collision_layer = 4
	sw.collision_mask = 0
	kroot.add_child(sw)
	sw.global_position = Vector3(-6, 103, -24.3)
	box_shape(sw, Vector3(5.2, 6, 0.6), Vector3(-3.4, 0, 0))
	box_shape(sw, Vector3(5.2, 6, 0.6), Vector3(3.4, 0, 0))
	box_shape(sw, Vector3(1.6, 3.6, 0.6), Vector3(0, 1.2, 0))
	var door_bar := StaticBody3D.new()
	door_bar.name = "DoorBar"
	door_bar.collision_layer = 4
	door_bar.collision_mask = 0
	kroot.add_child(door_bar)
	door_bar.global_position = Vector3(-6, 101.2, -24.3)
	box_shape(door_bar, Vector3(1.6, 2.4, 0.6))
	var bar_mi := MeshInstance3D.new()
	bar_mi.mesh = Geo.rounded_box(Vector3(1.8, 0.25, 0.2), 0.06, 2, Color("#8E4E22"), Color("#5A3221"))
	bar_mi.material_override = vc_mat()
	bar_mi.position = Vector3(0, 0.2, 0.35)
	door_bar.add_child(bar_mi)
	# Storybook-page proscenium around the opening (fills the KitchenCam overscan, no sky).
	var frame_mat := toon(Color("#F3E2C4"), "parchment", 0.4, false, 0.9)
	for fr in [[Vector3(-6, 108.0, -23.95), Vector3(18, 4.0, 0.2)], [Vector3(-6, 98.5, -23.95), Vector3(18, 3.0, 0.2)], [Vector3(-14.35, 103, -23.95), Vector3(5.3, 6.0, 0.2)], [Vector3(2.35, 103, -23.95), Vector3(5.3, 6.0, 0.2)]]:
		var fm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = fr[1]
		fm.mesh = bm
		fm.material_override = frame_mat
		kroot.add_child(fm)
		fm.global_position = fr[0]
	# Oven door glow + blast lane (cycle 4 s: 2.0 cold, 1.0 glow telegraph, 1.0 blast).
	_oven_door = MeshInstance3D.new()
	_oven_door.mesh = Geo.rounded_box(Vector3(2.0, 1.6, 0.12), 0.2, 2, Color("#FF8A3D"), Color("#C9541F"))
	_oven_door.material_override = toon(Color.WHITE, "", 0.35, true, 0.3, Color(1.0, 0.45, 0.1), 0.2)
	kroot.add_child(_oven_door)
	_oven_door.global_position = Vector3(-6, 101.1, -31.75)
	_oven_glow = OmniLight3D.new()
	_oven_glow.light_color = Color(1.0, 0.6, 0.3)
	_oven_glow.light_energy = 1.0
	_oven_glow.omni_range = 9.0
	kroot.add_child(_oven_glow)
	_oven_glow.global_position = Vector3(-6, 101.6, -30.6)
	var amb := OmniLight3D.new()
	amb.light_color = Color(1.0, 0.85, 0.7)
	amb.light_energy = 1.4
	amb.omni_range = 14.0
	kroot.add_child(amb)
	amb.global_position = Vector3(-6, 105.3, -27.5)
	_oven_hz = Area3D.new()
	_oven_hz.name = "OvenBlast"
	_oven_hz.collision_layer = 16
	_oven_hz.collision_mask = 0
	_oven_hz.set_meta("damage", 1)
	_oven_hz.set_meta("knockback_up", 6.0)
	kroot.add_child(_oven_hz)
	_oven_hz.global_position = Vector3(-6, 101.1, -28.2)
	box_shape(_oven_hz, Vector3(3.4, 2.2, 7.2))
	_oven_push = Area3D.new()
	_oven_push.name = "OvenPush"
	_oven_push.collision_layer = 128
	_oven_push.collision_mask = 0
	_oven_push.monitoring = false
	_oven_push.add_to_group("wind_zone")
	_oven_push.set_script(load("res://scripts/worlds/w3_slide_push.gd"))
	_oven_push.set("points", PackedVector3Array([Vector3(-6, 100.6, -31.6), Vector3(-6, 100.6, -24.8)]))
	_oven_push.set("push_speed", 0.0)
	_oven_push.set("max_offset", 1.8)
	kroot.add_child(_oven_push)
	box_shape(_oven_push, Vector3(3.4, 2.2, 7.2), Vector3(-6, 101.1, -28.2))
	# Cleat on the oven top (west corner), rope over the ceiling to the cage.
	var clp := v3(_plat("cage_release_cleat")["pos"])
	var cleat := Node3D.new()
	cleat.name = "Cleat"
	kroot.add_child(cleat)
	cleat.global_position = clp
	var cm := MeshInstance3D.new()
	cm.mesh = Geo.rounded_box(Vector3(0.5, 0.3, 0.3), 0.08, 2, Color("#B8733A"), Color("#7A4523"))
	cm.material_override = vc_mat()
	cleat.add_child(cm)
	var cage_pos := v3(_plat("kids_cage")["pos"])
	var rope := Geo.tube(PackedVector3Array([clp + Vector3(0, 0.2, 0), Vector3(clp.x, 105.9, clp.z), Vector3(cage_pos.x, 105.9, cage_pos.z), cage_pos + Vector3(0, 0.95, 0)]), 0.05, 6, Color(0.17, 0.12, 0.18), Color(0.3, 0.2, 0.3), 0.0)
	var rope_mi := mesh_node(rope, vc_mat(), Vector3.ZERO, kroot, "CageRope")
	# The kids' cage. Hansel and Gretel use their Tripo P2 models when they exist (requested); until then the closest
	# real cast models stand in (Jack and Hazel).
	var cage := Node3D.new()
	cage.name = "KidsCage"
	kroot.add_child(cage)
	cage.global_position = cage_pos
	for i in 10:
		var a := TAU * i / 10.0
		var bar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.05
		cyl.height = 1.9
		bar.mesh = cyl
		bar.material_override = toon(Color.WHITE, "candy_stripes", 2.0, false, 0.3)
		bar.position = Vector3(cos(a) * 0.8, 0, sin(a) * 0.8)
		cage.add_child(bar)
	for yy in [-0.95, 0.95]:
		var ring := MeshInstance3D.new()
		var cyl2 := CylinderMesh.new()
		cyl2.top_radius = 0.85
		cyl2.bottom_radius = 0.85
		cyl2.height = 0.1
		ring.mesh = cyl2
		ring.material_override = toon(Color("#E8435A"))
		ring.position = Vector3(0, yy, 0)
		cage.add_child(ring)
	var kid_paths := ["res://assets/characters/hansel/hansel.glb", "res://assets/characters/gretel/gretel.glb"]
	var fallback := ["res://assets/characters/jack/jack.glb", "res://assets/characters/jack/jack_v2.glb"]   # never hazel (a pig) as Gretel; real meshes requested
	for i in 2:
		var kp: String = kid_paths[i] if ResourceLoader.exists(kid_paths[i]) else fallback[i]
		var kid := glb(kp, Vector3(-0.3 + i * 0.6, -0.9, 0), (i * 2 - 1) * 20.0, 0.72, cage)
		kid.name = ["Hansel", "Gretel"][i]
		if i == 1 and not ResourceLoader.exists(kid_paths[1]):
			_tint_glb(kid, Color("#C98A4B"))   # stand-in Gretel reads ginger-caramel, apart from Hansel
	# Flour sacks, hearth ash, recipe card.
	var fsb := rbox("FlourSacks", v3(_plat("flour_sacks")["pos"]), v3(_plat("flour_sacks")["size"]), Color("#FFF7EE"), Color("#E8D6B5"), 0.3, null, kroot)
	_dress_kitchen(kroot, fsb)
	var ash := MeshInstance3D.new()
	ash.mesh = Geo.rounded_box(Vector3(2.0, 0.3, 2.0), 0.12, 2, Color("#6E6268"), Color("#4A3F45"))
	ash.material_override = vc_mat()
	kroot.add_child(ash)
	ash.global_position = Vector3(-2.4, 100.15, -29)
	add_fx("ChimneySmoke", Vector3(-2.4, 100.4, -29), kroot, Color(0.6, 0.55, 0.6, 0.6), 0.5)
	var card := Label3D.new()
	card.text = "PIGLET PIE\n1 piglet (plump)\ncustard to taste\n  - R.H. III"
	card.font_size = 40
	card.modulate = Color("#5A3221")
	card.outline_size = 6
	card.outline_modulate = Color("#FFF7EE")
	card.pixel_size = 0.005
	kroot.add_child(card)
	card.global_position = Vector3(-3.45, 102.2, -31.75)
	# Cleat hit -> cage drops onto the flour sacks, opens, truffle appears, door unbarred.
	var cs := SlamSensor.create(cleat, 0.5, 0.8, Vector3(0, -0.2, 0))
	var release := func() -> void:
		if _cage_open:
			return
		_cage_open = true
		print("[W3] kitchen cage released")
		rope_mi.visible = false
		var tw := cage.create_tween()
		tw.tween_property(cage, "global_position:y", cage_pos.y - 2.4, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			ObjSvc.burst(self, cage.global_position, Color(1, 1, 1), 50, 4.0, 0.3, -2.0, 1.2)
			for c in cage.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).visible = false
			ObjSvc.call_on("UI", "toast", ["Gretel: \"The wolf said we'd taste better with custard!\""])
			ObjSvc.spawn_truffle(self, Transform3D(Basis(), Vector3(-8.6, 100.8, -27.6)), "W3-6", true)
			door_bar.queue_free())
	cs.struck.connect(func(_k: String, _f: Vector3) -> void: release.call())
	cs.slammed.connect(func(_b: Node) -> void: release.call())
	# Door: walking into the opened doorway leaves the kitchen to the courtyard.
	var door := Area3D.new()
	door.collision_layer = 0
	door.collision_mask = 2
	door.monitorable = false
	kroot.add_child(door)
	door.global_position = Vector3(-6, 101.2, -24.0)
	box_shape(door, Vector3(1.6, 2.4, 0.5))
	door.body_entered.connect(func(n: Node) -> void:
		if _cage_open and n.is_in_group("player") and n.has_method("respawn"):
			n.call("respawn", Transform3D(Basis(Vector3.UP, PI), Vector3(-6, 8.05, -21.8)))
			print("[W3] left the kitchen"))
	# Fixed dollhouse camera (R2.1), active while Mak is inside the room.
	_kitchen_cam = Camera3D.new()
	_kitchen_cam.name = "KitchenCam"
	_kitchen_cam.fov = 50.0
	kroot.add_child(_kitchen_cam)
	_kitchen_cam.global_transform = Transform3D(Basis(), Vector3(-6, 104.4, -21.0)).looking_at(Vector3(-6, 101.0, -29.4), Vector3.UP)


## R1 visual major (the kitchen was a single-texture box): checkered biscuit floor, icing trims, cloth flour sacks,
## a round glowing oven window, shelves of jars, hanging pans, a rolling pin and cupcakes, and a cool window fill
## against the warm hearth.
func _dress_kitchen(kroot: Node3D, flour_box: Node3D) -> void:
	# Checkered biscuit floor tiles (top of the floor at y 100.0).
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Geo.rounded_box(Vector3(1.12, 0.04, 1.12), 0.04, 1, Color.WHITE, Color.WHITE)
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	for ix in 9:
		for iz in 7:
			xs.append(Transform3D(Basis(), Vector3(-6.0 - 4.8 + ix * 1.2, 100.02, -29.0 - 3.6 + iz * 1.2)))
			cs.append(Color("#F3D08F") if (ix + iz) % 2 == 0 else Color("#C98A4B"))
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cs[i])
	var tiles := MultiMeshInstance3D.new()
	tiles.multimesh = mm
	var tm := StandardMaterial3D.new()
	tm.vertex_color_use_as_albedo = true
	tm.roughness = 0.7
	tiles.material_override = tm
	kroot.add_child(tiles)
	# Icing trims along the wall tops and the oven.
	var icing := toon(Color("#FFF7EE"), "", 0.35, false, 0.4)
	for t in [[Vector3(-11.35, 105.7, -29), Vector3(0, 0, 90), 9.2], [Vector3(-0.65, 105.7, -29), Vector3(0, 0, 90), 9.2], [Vector3(-6, 105.7, -33.35), Vector3(0, 90, 90), 11.6]]:
		var tr := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.12
		cm.height = float(t[2])
		cm.radial_segments = 8
		tr.mesh = cm
		tr.material_override = icing
		kroot.add_child(tr)
		tr.position = t[0]
		tr.rotation_degrees = Vector3(90, 0, 0) if t[1] == Vector3(0, 0, 90) else Vector3(0, 0, 90)
	# Round glowing oven window on the door.
	var win := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.42
	wm.bottom_radius = 0.42
	wm.height = 0.06
	wm.radial_segments = 32
	win.mesh = wm
	win.material_override = toon(Color("#FF5A3C"), "", 0.35, false, 0.2, Color(1.0, 0.35, 0.12), 2.2)
	kroot.add_child(win)
	win.global_position = Vector3(-6, 101.25, -31.66)
	win.rotation_degrees = Vector3(90, 0, 0)
	var wrim := MeshInstance3D.new()
	var wrm := TorusMesh.new()
	wrm.inner_radius = 0.42
	wrm.outer_radius = 0.54
	wrim.mesh = wrm
	wrim.material_override = toon(Color("#C9A24B"), "", 0.35, false, 0.3, Color.BLACK, 0.0, 0.6, 1.2)
	kroot.add_child(wrim)
	wrim.global_position = Vector3(-6, 101.25, -31.64)
	wrim.rotation_degrees = Vector3(90, 0, 0)
	# Cloth flour sacks with tied tops (the collision box stays, hidden).
	for c in flour_box.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
	var sack_cols := [Color("#FFF7EE"), Color("#F3E6CC"), Color("#FFF1DC")]
	for k in 3:
		var sp := Vector3(-9.4 + [-0.5, 0.5, 0.0][k], 100.0, -26.0 + [-0.45, -0.3, 0.5][k])
		var sh: float = [0.95, 0.85, 1.05][k]
		var sack := mesh_node(Geo.lathe([Vector2(0.38, 0.0), Vector2(0.5, 0.15), Vector2(0.52, sh * 0.5), Vector2(0.42, sh * 0.8), Vector2(0.16, sh * 0.92), Vector2(0.2, sh), Vector2(0.0, sh + 0.04)], 20, 1.0, 0.9,
			[sack_cols[k], sack_cols[k], sack_cols[k], sack_cols[k], Color("#C98A4B"), sack_cols[k], sack_cols[k]], false, false, 0.04, 5), vc_mat(0.95, 0.1), sp, kroot, "Sack%d" % k)
		sack.rotation.y = k * 1.1
		var lb := Label3D.new()
		lb.text = "FLOUR"
		lb.font_size = 40
		lb.modulate = Color("#8E4E22")
		lb.pixel_size = 0.004
		sack.add_child(lb)
		lb.position = Vector3(0, sh * 0.5, 0.48)
	# Shelves of jars between the pantries, hanging pans, a rolling pin and cupcakes on the table.
	var jar_cols := [Color("#FF7FAF"), Color("#7FE0C2"), Color("#FFE07A"), Color("#B48CF2"), Color("#FF8A3D")]
	for row in 2:
		rbox("Shelf%d" % row, Vector3(-6, 104.0 + row * 0.9, -33.1), Vector3(3.2, 0.12, 0.6), Color("#E2B77A"), Color("#8E4E22"), 0.04, null, kroot, false)
		for j in 5:
			var jar := rcyl("Jar", Vector3(-7.3 + j * 0.65, 104.06 + row * 0.9, -33.1), 0.2, 0.45, Color("#FFF7EE"), jar_cols[(j + row * 2) % 5], false, null, kroot, 14)
	for j in 3:
		var pan := MeshInstance3D.new()
		var pmm := CylinderMesh.new()
		pmm.top_radius = 0.35 - j * 0.05
		pmm.bottom_radius = 0.3 - j * 0.05
		pmm.height = 0.1
		pmm.radial_segments = 20
		pan.mesh = pmm
		pan.material_override = toon(Color("#C9A24B"), "", 0.35, false, 0.25, Color.BLACK, 0.0, 0.7, 1.4)
		kroot.add_child(pan)
		pan.global_position = Vector3(-0.75, 104.3 - j * 0.15, -30.5 + j * 0.9)
		pan.rotation_degrees = Vector3(0, 0, 90)
	var pin := MeshInstance3D.new()
	var pnm := CapsuleMesh.new()
	pnm.radius = 0.09
	pnm.height = 1.0
	pin.mesh = pnm
	pin.material_override = toon(Color("#E2B77A"))
	kroot.add_child(pin)
	pin.global_position = Vector3(-2.4, 101.0, -25.7)
	pin.rotation_degrees = Vector3(0, 20, 90)
	for j in 2:
		glb(P_CUPCAKE, Vector3(-1.6 - j * 0.6, 100.9, -26.0 + j * 0.3), j * 40.0, 0.18, kroot)
	# Cool window fill against the warm hearth.
	var cool := OmniLight3D.new()
	cool.light_color = Color(0.7, 0.8, 1.0)
	cool.light_energy = 0.8
	cool.omni_range = 9.0
	kroot.add_child(cool)
	cool.global_position = Vector3(-1.5, 104.5, -26.0)


func _enter_kitchen(by: Node, cap: Node3D) -> void:
	if by == null or not by.has_method("respawn"):
		return
	ObjSvc.burst(self, cap.global_position, Color(0.3, 0.28, 0.3), 40, 5.0, 0.3, -4.0, 1.0)
	ObjSvc.call_on("UI", "toast", ["Down the chimney!"])
	print("[W3] chimney cap slammed: into the kitchen")
	await get_tree().create_timer(0.35, false, true).timeout
	by.call("respawn", Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(-2.4, 104.5, -29)))


func _kitchen_step(delta: float, p: Vector3) -> void:
	if _oven_hz == null:
		return
	_oven_t = fposmod(_oven_t + delta, 4.0)
	var st := "cold" if _oven_t < 2.0 else ("glow" if _oven_t < 3.0 else "blast")
	if st != _oven_state:
		_oven_state = st
		var blast := st == "blast"
		if blast:
			_oven_hz.add_to_group("hazard")
		else:
			_oven_hz.remove_from_group("hazard")
		_oven_push.set("push_speed", 8.0 if blast else 0.0)
		if blast and p.y > 99.0:
			ObjSvc.burst(self, Vector3(-6, 101.0, -31.0), Color(1.0, 0.55, 0.2), 40, 7.0, 0.25, 0.0, 0.6)
	var glow := 0.15
	if st == "glow":
		glow = 0.6 + 0.4 * sin(_oven_t * 30.0)
	elif st == "blast":
		glow = 1.6
	_oven_glow.light_energy = 0.8 + glow * 2.0
	(_oven_door.material_override as ShaderMaterial).set_shader_parameter("emission_energy", glow)
	var inside := p.y > 99.0 and p.y < 107.0 and p.x > -11.6 and p.x < -0.4 and p.z > -33.6 and p.z < -24.0
	if inside and not _kitchen_cam.current:
		_prev_cam = get_viewport().get_camera_3d()
		_kitchen_cam.make_current()
	elif not inside and _kitchen_cam.current:
		if _prev_cam and is_instance_valid(_prev_cam):
			_prev_cam.make_current()
		else:
			_kitchen_cam.current = false


# ================================================================ bridges, docks, pier

func _build_bridges() -> void:
	var g := group_node("Bridges")
	# Pretzel Bridge: 8 deck segments along the arc (ends top 1.3 at z 12.5 / -3.5, apex top 2.4 at z 4.5).
	var x := -6.0
	var z0 := 12.5
	var z1 := -3.5
	var n := 8
	var deck_mat := toon(Color(1.0, 0.92, 0.82), "gingerbread", 0.5, true, 0.55, Color.BLACK, 0.0, 0.5, 0.6)
	var bb := body("PretzelBridge", Vector3.ZERO, g, "wood")
	var use_glb := ResourceLoader.exists("res://assets/props/w3/pretzel_bridge/pretzel_bridge.glb")
	if use_glb:
		glb("res://assets/props/w3/pretzel_bridge/pretzel_bridge.glb", Vector3(x, -0.15, 4.5), 0.0, 1.0, g)
	var rail_pts_l := PackedVector3Array()
	var rail_pts_r := PackedVector3Array()
	for i in n:
		var za := lerpf(z0, z1, float(i) / n)
		var zb := lerpf(z0, z1, float(i + 1) / n)
		var ya := _arch_y(za)
		var yb := _arch_y(zb)
		var mid := Vector3(x, (ya + yb) * 0.5 - 0.25, (za + zb) * 0.5)
		var ln := Vector2(za - zb, yb - ya).length() + 0.08
		var ang := rad_to_deg(atan2(yb - ya, za - zb))
		box_shape(bb, Vector3(3.6, 0.5, ln), mid, Vector3(ang, 0, 0))
		if use_glb:
			continue
		var seg := MeshInstance3D.new()
		seg.mesh = Geo.rounded_box(Vector3(3.6, 0.5, ln + 0.05), 0.14, 3, Color("#C97B3A"), Color("#8E4E22"))
		seg.material_override = deck_mat
		seg.position = mid
		seg.rotation_degrees = Vector3(ang, 0, 0)
		bb.add_child(seg)
	for i in 33:
		var z := lerpf(z0, z1, float(i) / 32.0)
		var y := _arch_y(z) + 0.75 + 0.18 * sin(float(i) * 1.6)
		rail_pts_l.append(Vector3(x - 1.65, y, z))
		rail_pts_r.append(Vector3(x + 1.65, y, z))
	var pretzel := Color("#9A5426")
	for pts in ([] if use_glb else [rail_pts_l, rail_pts_r]):
		var tm := Geo.tube(pts, 0.13, 10, pretzel, pretzel.lightened(0.12), 3.0)
		mesh_node(tm, toon(Color.WHITE, "", 0.35, true, 0.3, Color.BLACK, 0.0, 0.5, 0.9), Vector3.ZERO, g)
		for i in 9:
			var z := lerpf(z0, z1, float(i) / 8.0)
			var px: float = pts[0].x
			var post := Geo.tube(PackedVector3Array([Vector3(px, _arch_y(z) - 0.1, z), Vector3(px, _arch_y(z) + 0.85, z)]), 0.11, 8, pretzel, pretzel, 0.0)
			mesh_node(post, toon(Color.WHITE, "", 0.35, true, 0.3), Vector3.ZERO, g)
	# Rail colliders (low walls) so the bridge is safe to run.
	box_shape(bb, Vector3(0.25, 1.0, 16.0), Vector3(x - 1.65, 2.2, 4.5))
	box_shape(bb, Vector3(0.25, 1.0, 16.0), Vector3(x + 1.65, 2.2, 4.5))
	# Pretzel-knot piers.
	for pz in ([] if use_glb else [1.0, 8.0]):
		var pier := rcyl("Pier", Vector3(x, -0.8, pz), 0.7, _arch_y(pz) + 0.5, Color("#B8733A"), Color("#8E4E22"), true, deck_mat, g, 16)
		(pier.get_child(1) as Node3D).scale = Vector3(1.6, 1, 1)
	# Lost Page 2 shelf beside the north pier.
	var sh: Dictionary = _plat("bridge_page_shelf")
	_wafer(v3(sh["pos"]), v3(sh["size"]), "PageShelf", g)
	# Docks and piers.
	for id in ["biscuit_dock", "wafer_pier_north"]:
		var p: Dictionary = _plat(id)
		_wafer(v3(p["pos"]), v3(p["size"]), id, g)
		var pp := v3(p["pos"])
		var sz := v3(p["size"])
		for sx in [-1, 1]:
			for sz2 in [-1, 1]:
				rcyl("Leg", Vector3(pp.x + sx * sz.x * 0.4, -0.8, pp.z + sz2 * sz.z * 0.4), 0.18, pp.y + 0.6, Color("#D9A65E"), Color("#B8733A"), false, null, g, 10)
	# Biscuit balcony over the void (Lost Page 5).
	var bal: Dictionary = _plat("biscuit_balcony")
	# The river carve leaves z 24..31 at the page edge as hot chocolate, so the run-up and balcony sit at z 33.5.
	_wafer(v3(bal["pos"]), v3(bal["size"]), "BiscuitBalcony", g)
	var balp := v3(bal["pos"])
	for i in 4:
		var cx := balp.x - 2.0 + i * 1.35
		glb(P_CANE, Vector3(cx, 2.0, balp.z + 1.15), 0.0, 0.7, g)
	# R1.9: it snapped off the page and hangs from a candyfloss cloud on a liquorice rope.
	for sx in [-1.8, 1.8]:
		var rp := Geo.tube(PackedVector3Array([Vector3(balp.x + sx, 2.0, balp.z), Vector3(balp.x + sx * 0.6, 6.0, balp.z), Vector3(balp.x, 10.0, balp.z)]), 0.07, 6, Color(0.17, 0.12, 0.18), Color(0.85, 0.2, 0.32), 2.0)
		mesh_node(rp, toon(Color.WHITE, "", 0.35, true, 0.3), Vector3.ZERO, g)
	var cl := Node3D.new()
	cl.set_script(load("res://scripts/worlds/w3_bobber.gd"))
	cl.set("bob_amp", 0.25)
	cl.set("bob_period", 4.0)
	g.add_child(cl)
	cl.position = Vector3(balp.x, 10.6, balp.z)
	var cmat := toon(Color(1.0, 0.86, 0.93), "", 0.35, false, 0.9, Color(1.0, 0.8, 0.9), 0.25, 0.6, 0.2)
	for k in 6:
		var sp := sphere_mesh(1.0 + 0.3 * sin(k * 2.3), Color(1, 0.86, 0.93))
		sp.material_override = cmat
		sp.position = Vector3(cos(k * 1.1) * 1.4, sin(k * 1.7) * 0.4, sin(k * 1.1) * 0.9)
		cl.add_child(sp)


func _arch_y(z: float) -> float:
	var t := (z - 4.5) / 8.0
	return 1.3 + 1.1 * (1.0 - t * t)


# ================================================================ lagoon (W3-3)

func _build_lagoon() -> void:
	var g := group_node("Lagoon")
	var bmesh: Mesh = null
	var bscene := scene(P_BISCUIT)
	if bscene:
		var tmp := bscene.instantiate()
		var mis := tmp.find_children("*", "MeshInstance3D", true, false)
		if mis.size() > 0:
			bmesh = (mis[0] as MeshInstance3D).mesh
		tmp.free()
	for ln in data["splines"]["biscuit_lanes"]:
		var lane := Node3D.new()
		lane.name = String(ln["id"])
		lane.set_script(load("res://scripts/worlds/w3_biscuit_lane.gd"))
		var pts := PackedVector3Array()
		for q in ln["points"]:
			pts.append(Vector3(float(q[0]), 0.35, float(q[1])))
		lane.set("points", pts)
		lane.set("speed", float(ln["speed"]))
		lane.set("interval", float(ln["spawn_every_s"]))
		lane.set("offset", float(ln["offset_s"]))
		lane.set("thickness", 0.7)
		var br := 1.3
		if lane.name == "lane_E":
			# W3-3 fairness pass (2026-10-19): the convoy biscuits were 2.6 m wide with a 2.6 m edge gap (5.2 m at
			# 2.6 m/s, every 2.0 s), so every hop needed a run-up of under 1.9 m on a moving biscuit. Now 3.4 m wide,
			# every 1.75 s: spacing 4.55 m, edge gap 1.15 m, about 2.7 m of run-up. A short running hop lands in a
			# 3.4 m deep window. Overrides the JSON (spawn_every_s 2.0); same speed and sag rule.
			br = 1.7
			lane.set("interval", 1.75)
		lane.set("radius", br)
		lane.set("biscuit_mesh", bmesh)
		lane.set("mesh_offset", Vector3(0, -0.35, 0))
		lane.set("mesh_scale", Vector3(1.04 * br / 1.3, 0.97, 1.04 * br / 1.3))
		g.add_child(lane)
	# Marshmallows ring the islet shore.
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.3
		# Keep the north-east rim free: it is the J45 boarding point for lane E (R3.1); a marshmallow at
		# (23.2, 7.5) blocked it.
		if absf(a - 0.15) < 0.5 or (a > 5.2 and a < 6.2):
			continue
		var p := Vector3(21 + cos(a) * 2.6, 0, 9 + sin(a) * 2.6)
		p.y = h_at(p.x, p.z) - 0.2
		glb(P_MARSH[2] if i % 2 == 0 else P_MARSH[0], p, float(i) * 47.0, 0.7, g)
	# R1.5 The Dunk Run: the Royal Digestive is moored east of the islet with the W3-3 truffle aboard.
	var rd: Dictionary = _plat("royal_digestive")
	var rpts := PackedVector3Array()
	for q in data["splines"]["royal_digestive"]["points"]:
		rpts.append(Vector3(float(q[0]), 0.55, float(q[1])))
	var royal := AnimatableBody3D.new()
	royal.name = "RoyalDigestive"
	royal.collision_layer = 1
	royal.collision_mask = 0
	royal.set_meta("surface", "wood")
	royal.set_script(load("res://scripts/worlds/w3_royal.gd"))
	royal.set("points", rpts)
	royal.set("speed", float(data["splines"]["royal_digestive"].get("speed", 1.6)))
	cyl_shape(royal, 1.6, 0.4)
	var rv := glb(P_BISCUIT, Vector3(0, -0.45, 0), 0.0, Vector3(1.28, 0.9, 1.28), royal)
	_tint_glb(rv, Color(1.0, 0.86, 0.45))
	var crown := Label3D.new()
	crown.text = "ROYAL"
	crown.font_size = 72
	crown.modulate = Color("#FFC93C")
	crown.outline_size = 10
	crown.outline_modulate = Color("#7A4523")
	crown.rotation_degrees = Vector3(-90, 0, 0)
	crown.position = Vector3(0, 0.23, 0.9)
	crown.pixel_size = 0.006
	royal.add_child(crown)
	g.add_child(royal)
	var rtr := inst(O + "Truffle.tscn", royal.global_position + Vector3(0, 1.0, 0), royal, {"truffle_id": "W3-3"})
	# Mooring post with the lagoon crow, biscuit barrel on the shore.
	var mp: Dictionary = _plat("mooring_post")
	var mpp := v3(mp["pos"])
	var msz := v3(mp["size"])
	var mbase := mpp.y - msz.y * 0.5
	var post := rcyl("MooringPost", Vector3(mpp.x, mbase, mpp.z), msz.x * 0.5, msz.y, Color("#E8435A"), Color(0.17, 0.12, 0.18), true, null, g, 12)
	var knob := sphere_mesh(0.42, Color("#FF5C7A"), 0.25)
	knob.position = Vector3(0, msz.y + 0.1, 0)
	post.add_child(knob)
	var r0 := rpts[0]
	var rope := Geo.tube(PackedVector3Array([Vector3(mpp.x, mbase + msz.y - 0.3, mpp.z), (Vector3(mpp.x, 0.9, mpp.z) + r0) * 0.5, r0 + Vector3(0, 0.25, 0)]), 0.04, 6, Color(0.9, 0.8, 0.6), Color(0.8, 0.7, 0.5), 0.0)
	var rope_mi := mesh_node(rope, toon(Color.WHITE, "", 0.35, true), Vector3.ZERO, g, "MooringRope")
	var bar: Dictionary = _plat("biscuit_barrel")
	var bp := v3(bar["pos"])
	# Visual only (plan: decor_spawner). As a solid tipped cylinder it walled off the north-east rim (J45 to lane E).
	var barrel := rcyl("BiscuitBarrel", Vector3(bp.x, h_at(bp.x, bp.z) - 0.1, bp.z), 0.7, 1.5, Color("#F3D08F"), Color("#B8733A"), false, toon(Color.WHITE, "gingerbread", 0.6, true), g, 18)
	barrel.rotation_degrees = Vector3(0, 30, 75)
	# Release: Mak boards a lane_S biscuit or lands on the islet while the royal is moored.
	var rel := Area3D.new()
	rel.name = "RoyalRelease"
	rel.collision_layer = 0
	rel.collision_mask = 2
	rel.monitorable = false
	g.add_child(rel)
	rel.global_position = Vector3(21, 1.6, 9)
	cyl_shape(rel, 3.2, 2.0, Vector3(0, 0.8, 0))
	# Lane E launch stretch (25, 5.4) -> (35.4, 8.5): a hop from lane N's end onto lane E also releases (R3.1).
	box_shape(rel, Vector3(11.5, 1.6, 3.0), Vector3(9.2, -0.6, -2.0), Vector3(0, -16.4, 0))
	rel.body_entered.connect(func(n: Node) -> void:
		if not n.is_in_group("player") or bool(royal.get("moving")):
			return
		_release_royal(royal, rope_mi))
	royal.connect("tipped", func() -> void:
		rope_mi.visible = true)


func _release_royal(royal: Node, rope: Node3D) -> void:
	var crow: Node3D = enemies.get("crow_lagoon")
	if crow and is_instance_valid(crow):
		if crow.has_method("say"):
			crow.call("say", "Caw caw! Bon voyage!", Color(1, 0.9, 0.5), 80)
	await get_tree().create_timer(0.8, false, true).timeout
	rope.visible = false
	ObjSvc.sfx("rope_snap", royal.global_position)
	royal.call("release")
	ObjSvc.call_on("UI", "toast", ["The crow cut the rope! Catch the Royal Digestive!"])


# ================================================================ Great Lollipop and Gumdrop Hop (W3-7)

func _build_lollipop_and_gumdrops() -> void:
	var g := group_node("GumdropHop")
	var c := Vector3(20, 2, 38)
	var stick := body("LollipopStick", c, g, "candy")
	cyl_shape(stick, 0.7, 13.5, Vector3(0, 6.75, 0))
	var sm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.7
	cm.bottom_radius = 0.75
	cm.height = 17.0
	cm.radial_segments = 20
	sm.mesh = cm
	sm.material_override = toon(Color.WHITE, "candy_stripes", 0.45, false, 0.25, Color.BLACK, 0.0, 0.5, 0.8)
	sm.position = Vector3(0, 8.5, 0)
	stick.add_child(sm)
	var disc := body("LollipopDisc", c + Vector3(0, 17.5, 0), g, "candy")
	var dcs := CollisionShape3D.new()
	var dsh := CylinderShape3D.new()
	dsh.radius = 4.0
	dsh.height = 1.6
	dcs.shape = dsh
	dcs.rotation_degrees = Vector3(90, 0, 0)
	disc.add_child(dcs)
	var swm := ShaderMaterial.new()
	swm.shader = load("res://assets/environment/w3/w3_swirl.gdshader")
	swm.set_shader_parameter("c1", Color("#FF7FAF"))
	swm.set_shader_parameter("c2", Color("#FFF7EE"))
	swm.set_shader_parameter("c3", Color("#7FE0C2"))
	swm.set_shader_parameter("c4", Color("#FFE07A"))
	swm.set_shader_parameter("spin_speed", 0.25)
	mesh_node(load(B + "lollipop_disc.mesh.res"), swm, Vector3.ZERO, disc)
	var sa: Dictionary = _plat("lollipop_saucer")
	var sp := v3(sa["pos"])
	var sau := rcyl("LollipopSaucer", sp - Vector3(0, 0.45, 0), 2.0, 0.9, Color("#FFF7EE"), Color("#FF8FB8"), true, null, g, 32)
	sau.set_meta("surface", "candy")
	inst(O + "Truffle.tscn", Vector3(20, 25.2, 38), g, {"truffle_id": "W3-7"})
	# Gumdrops: happy ones bounce (apex 4.6), grumpy ones (R1.7) give a weak 2 m bounce unless Ham Slammed (7 m).
	var i := 0
	var prev := Vector3(9.0, 2.0, 38.5)
	for p in data["platforms"]:
		if String(p["kind"]) != "bouncy_gumdrop":
			continue
		i += 1
		var pos := v3(p["pos"])
		var top := float(p["top_y"])
		var col := Color(String(p["color"]))
		var grumpy := String(p.get("face", "happy")) == "grumpy"
		var holder := Node3D.new()
		holder.name = "Gumdrop%d" % i
		g.add_child(holder)
		holder.position = Vector3(pos.x, 0, pos.z)
		var gb := body("Body", Vector3(0, top - 1.6, 0), holder, "candy")
		cyl_shape(gb, 1.25, 1.6, Vector3(0, 0.8, 0))
		make_bouncy(gb, float(p["bounce_apex_m"]) + 0.3)
		if grumpy:
			gb.set_meta("slam_bounce_velocity", sqrt(2.0 * G * (float(p.get("slam_bounce_apex_m", 7.0)) + 0.3)))
			if String(p["id"]) in ["gumdrop_6", "gumdrop_7"]:
				gb.set_meta("deflates", true)
		var vis := glb(P_GUMDROPS[i % 4], Vector3.ZERO, 0.0, Vector3(1.3, 1.08, 1.3), gb)
		_tint_glb(vis, col)
		# Face toward the approach (previous gumdrop, or the spawn for the first and the tutorial one).
		var from := prev if String(p["id"]) != "gumdrop_8" else Vector3(4.0, 2.0, 36.0)
		_gum_face(vis, Vector3(from.x - pos.x, 0, from.z - pos.z), grumpy)
		var nid := String(p["id"])
		if nid == "gumdrop_8":
			gb.set_meta("next_dome", _gum(1) + Vector3(0, 0, 0))
		elif nid == "gumdrop_7":
			gb.set_meta("next_dome", Vector3(20.0, 24.4, 38.0))
		else:
			gb.set_meta("next_dome", _gum(int(nid.trim_prefix("gumdrop_")) + 1))
		squash_on_land(gb, vis, 1.6, 1.2)
		# R1 visual minor (the gumdrops read as stray balls): a twisted liquorice stalk holds each one up.
		var gy := h_at(pos.x, pos.z)
		var base_y := top - 1.6
		if base_y - gy > 0.6:
			var spts := PackedVector3Array()
			for k in 6:
				var u := float(k) / 5.0
				spts.append(Vector3(sin(u * 5.0 + i) * 0.12, gy - 0.2 + (base_y + 0.3 - gy + 0.2) * u, cos(u * 5.0 + i) * 0.12))
			var stalk := mesh_node(Geo.tube(spts, 0.16, 8, Color(0.17, 0.1, 0.15), Color(0.82, 0.16, 0.26), 3.0), toon(Color.WHITE, "", 0.35, true, 0.3, Color.BLACK, 0.0, 0.5, 0.9), Vector3.ZERO, holder, "Stalk")
			stalk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var shadow := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.1
		cyl.bottom_radius = 1.1
		cyl.height = 0.02
		shadow.mesh = cyl
		var shm := StandardMaterial3D.new()
		shm.albedo_color = Color(col.r, col.g, col.b, 0.22)
		shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shadow.material_override = shm
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(shadow)
		shadow.position = Vector3(0, h_at(pos.x, pos.z) + 0.03, 0)
		if top - h_at(pos.x, pos.z) > 3.0:
			add_fx("Sparkle", Vector3(pos.x, top - 0.8, pos.z), holder, col.lightened(0.4), 0.6)
		if not grumpy:
			var bob := Node3D.new()
			bob.set_script(load("res://scripts/worlds/w3_bobber.gd"))
			bob.set("bob_amp", 0.12)
			bob.set("bob_period", 2.6)
			bob.set("bob_phase_deg", i * 50.0)
			bob.set("physics", true)
			holder.add_child(bob)
			gb.reparent(bob, false)
		if String(p["id"]) != "gumdrop_8":
			prev = Vector3(pos.x, top, pos.z)
	var tut := inst(O + "SignPost.tscn", Vector3(6.5, h_at(6.5, 33.0), 33.0), g, {"board_text": "Grumpy!", "lines": PackedStringArray(["Grumpy gumdrops need a firm hand: Ham Slam!", "(Jump, then press Ham Slam in the air. They hate that. They love that.)"])})
	if tut:
		tut.rotation_degrees.y = -100.0
	# Spawn hint sign.
	var sgn := inst(O + "SignPost.tscn", Vector3(10.5, 2.0, 40.5), g, {"board_text": "Gumdrop Hop", "lines": PackedStringArray(["Bounce round the Great Lollipop, anticlockwise.", "Steer in the air. Do not look down. (You looked down.)"])})
	if sgn:
		sgn.rotation_degrees.y = -60.0


## Simple sculpted face on a gumdrop dome: eyes with glints, brows (grumpy) and a mouth arc.
func _gum_face(vis: Node3D, dir: Vector3, grumpy: bool) -> void:
	var f := Node3D.new()
	f.name = "Face"
	vis.add_child(f)
	f.rotation.y = atan2(dir.x, dir.z) - vis.rotation.y
	var black := toon(Color(0.12, 0.08, 0.1), "", 0.35, false, 0.2, Color.BLACK, 0.0, 0.3, 1.0)
	var white := toon(Color(1, 1, 1), "", 0.35, false, 0.2, Color(1, 1, 1), 0.6)
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.11
		sm.height = 0.24
		e.mesh = sm
		e.material_override = black
		e.position = Vector3(sx * 0.24, 0.78, 0.66)
		f.add_child(e)
		var gl := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.035
		gm.height = 0.07
		gl.mesh = gm
		gl.material_override = white
		gl.position = Vector3(sx * 0.24 + 0.04, 0.82, 0.76)
		f.add_child(gl)
		if grumpy:
			var br := MeshInstance3D.new()
			var bm := CapsuleMesh.new()
			bm.radius = 0.035
			bm.height = 0.26
			br.mesh = bm
			br.material_override = black
			br.position = Vector3(sx * 0.24, 0.95, 0.64)
			br.rotation_degrees = Vector3(0, 0, 90 - sx * 25.0)
			f.add_child(br)
	for k in 5:
		var t := (float(k) / 4.0 - 0.5)
		var m := MeshInstance3D.new()
		var mm := SphereMesh.new()
		mm.radius = 0.035
		mm.height = 0.07
		m.mesh = mm
		m.material_override = black
		var curve := 0.08 * (1.0 - 4.0 * t * t)
		m.position = Vector3(t * 0.3, 0.56 + (curve if grumpy else -curve) + (0.0 if grumpy else 0.06), 0.7)
		f.add_child(m)


func _tint_glb(n: Node, col: Color) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			if src is StandardMaterial3D:
				var dup := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.albedo_color = col.lightened(0.15)
				m.set_surface_override_material(s, dup)


# ================================================================ Gingerbread Barracks (W3-2, page 4)

func _build_fort() -> void:
	var g := group_node("Fort")
	# R1 visual: plain baked gingerbread colour blocks (vertex colours, no sponge noise) with piped icing trims.
	var wall_mat := toon(Color.WHITE, "", 0.35, true, 0.8, Color.BLACK, 0.0, 0.5, 0.3)
	var icing_mat := toon(Color("#FFF7EE"), "", 0.35, false, 0.4)
	var top_y := 5.6
	var base_y := 2.0
	var hgt := top_y - base_y
	# Walls x 37..55, z 36..50, 1.6 thick; west gate gap z 41..45.
	var segs := [
		[Vector3(46, 0, 36.8), Vector3(18, hgt, 1.6)],
		[Vector3(46, 0, 49.2), Vector3(18, hgt, 1.6)],
		[Vector3(54.2, 0, 43), Vector3(1.6, hgt, 11.2)],
		[Vector3(37.8, 0, 39.3), Vector3(1.6, hgt, 3.4)],
		[Vector3(37.8, 0, 47.3), Vector3(1.6, hgt, 2.6)],
	]
	var k := 0
	for sgm in segs:
		var p: Vector3 = sgm[0]
		var s: Vector3 = sgm[1]
		var w := rbox("FortWall%d" % k, Vector3(p.x, base_y + hgt * 0.5, p.z), s, Color("#FFF7EE"), Color("#B8733A"), 0.2, wall_mat, g)
		w.set_meta("surface", "wood")
		# Piped icing lines: a wavy trim under the crenellations and one near the base, on both faces.
		for ty in [hgt * 0.5 - 0.35, -hgt * 0.5 + 0.45]:
			var tr := MeshInstance3D.new()
			var tm := CapsuleMesh.new()
			tm.radius = 0.09
			tm.height = maxf(s.x, s.z) - 0.2
			tm.radial_segments = 8
			tm.rings = 2
			tr.mesh = tm
			tr.material_override = icing_mat
			w.add_child(tr)
			tr.position = Vector3(0, ty, 0)
			tr.rotation_degrees = Vector3(0, 0, 90) if s.x > s.z else Vector3(90, 0, 0)
			tr.scale = Vector3(1, 1, 1)
			var thick := (minf(s.x, s.z) * 0.5 + 0.03)
			for side in [-1.0, 1.0]:
				var tr2 := tr.duplicate() as MeshInstance3D
				w.add_child(tr2)
				tr2.position = Vector3(0, ty, side * thick) if s.x > s.z else Vector3(side * thick, ty, 0)
			tr.queue_free()
		# Icing crenellations.
		var along_x := s.x > s.z
		var ln := s.x if along_x else s.z
		var cnt := int(ln / 1.6)
		for j in cnt:
			var o := -ln * 0.5 + (j + 0.5) * ln / cnt
			if j % 2 == 1:
				continue
			var cp := Vector3(p.x + (o if along_x else 0.0), top_y + 0.3, p.z + (0.0 if along_x else o))
			var cr := MeshInstance3D.new()
			cr.mesh = Geo.rounded_box(Vector3(0.8 if along_x else s.x, 0.6, s.z if along_x else 0.8), 0.15, 2, Color("#FFF7EE"), Color("#FFE4EE"))
			cr.material_override = vc_mat(0.5)
			g.add_child(cr)
			cr.position = cp
		k += 1
	# Gate arch over the west opening.
	var arch := rbox("GateArch", Vector3(37.8, 5.2, 43), Vector3(1.8, 0.8, 5.2), Color("#FF7FAF"), Color("#B8733A"), 0.2, wall_mat, g)
	for gz in [40.8, 45.2]:
		glb(P_CANE, Vector3(36.8, 2.0, gz), 90.0 if gz < 43 else -90.0, 2.4, g)
	# NE tower x 52..55.4, z 36..39.4, top 9.2 with a candy pinwheel.
	var tw := rbox("Tower", Vector3(53.7, 5.6, 37.7), Vector3(3.4, 7.2, 3.4), Color("#FFF7EE"), Color("#B8733A"), 0.3, wall_mat, g)
	var roof := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.4
	cm.height = 2.4
	cm.radial_segments = 16
	roof.mesh = cm
	roof.material_override = toon(Color("#FF7FAF"), "", 0.35, false, 0.4)
	roof.position = Vector3(54.9, 10.6, 36.5)
	g.add_child(roof)
	var pin := Node3D.new()
	pin.set_script(load("res://scripts/worlds/w3_bobber.gd"))
	pin.set("spin_deg_per_s", Vector3(0, 0, 160))
	g.add_child(pin)
	pin.position = Vector3(54.9, 12.2, 36.2)
	for j in 4:
		var blade := MeshInstance3D.new()
		var bm := PrismMesh.new()
		bm.size = Vector3(0.7, 0.9, 0.05)
		blade.mesh = bm
		blade.material_override = toon([Color("#FF7FAF"), Color("#7FE0C2"), Color("#FFE07A"), Color("#8FB8FF")][j], "", 0.35, false, 0.4)
		blade.rotation_degrees = Vector3(0, 0, j * 90.0)
		blade.position = Vector3(0.45, 0, 0).rotated(Vector3.BACK, deg_to_rad(j * 90.0))
		pin.add_child(blade)
	# Generated corner towers (gingerbread_tower.glb) at three corners and both gate sides (the NE tower stays
	# procedural because Lost Page 4 sits on its 9.2 m walk-top).
	var TW := "res://assets/props/w3/gingerbread_tower/gingerbread_tower.glb"
	if ResourceLoader.exists(TW):
		for tp in [[Vector3(37.6, 2.0, 36.6), 225.0], [Vector3(37.6, 2.0, 49.4), 315.0], [Vector3(54.4, 2.0, 49.4), 45.0], [Vector3(36.6, 2.0, 39.6), 270.0], [Vector3(36.6, 2.0, 46.4), 270.0]]:
			var tpos: Vector3 = tp[0]
			glb(TW, tpos, float(tp[1]), 0.85, g)
			var tb := body("TowerBody", tpos, g, "wood")
			cyl_shape(tb, 1.45, 4.2, Vector3(0, 2.1, 0))
	# Pennants along the north wall.
	for j in 6:
		var fx := 38.5 + j * 3.2
		var flag := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.7, 0.9, 0.04)
		flag.mesh = pm
		flag.material_override = toon(Color("#FF7FAF") if j % 2 == 0 else Color("#7FE0C2"), "", 0.35, false, 0.5)
		flag.rotation_degrees = Vector3(0, 0, -90)
		var holder := Node3D.new()
		holder.set_script(load("res://scripts/worlds/w3_bobber.gd"))
		holder.set("sway_deg", 9.0)
		holder.set("sway_period", 1.6 + j * 0.1)
		g.add_child(holder)
		holder.position = Vector3(fx, top_y + 1.6, 49.6)
		holder.add_child(flag)
		flag.position = Vector3(0.45, 0, 0)
		var stick_mi := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.04
		sc.bottom_radius = 0.04
		sc.height = 1.8
		stick_mi.mesh = sc
		stick_mi.material_override = toon(Color(0.95, 0.95, 0.95))
		stick_mi.position = Vector3(fx, top_y + 0.9, 49.6)
		g.add_child(stick_mi)
	# R1 fun major (the yard read as an empty box): bunting strings across the yard and a snare stand by Snap.
	var flag_cols := [Color("#FF7FAF"), Color("#FFE07A"), Color("#7FE0C2"), Color("#8FB8FF"), Color("#FF8A3D")]
	for bx in [40.5, 46.0, 51.5]:
		var a := Vector3(bx, top_y + 1.3, 37.6)
		var b := Vector3(bx, top_y + 1.3, 48.4)
		var n := 14
		var line_pts := PackedVector3Array()
		for j in n + 1:
			var u := float(j) / n
			var q := a.lerp(b, u)
			q.y -= sin(u * PI) * 1.1
			line_pts.append(q)
		mesh_node(Geo.tube(line_pts, 0.03, 5, Color("#FFF7EE"), Color("#FFF7EE")), vc_mat(0.6), Vector3.ZERO, g)
		for j in n:
			var q := line_pts[j].lerp(line_pts[j + 1], 0.5)
			var fl := MeshInstance3D.new()
			var pm2 := PrismMesh.new()
			pm2.size = Vector3(0.45, 0.55, 0.03)
			fl.mesh = pm2
			fl.material_override = toon(flag_cols[(j + int(bx)) % flag_cols.size()], "", 0.35, false, 0.5)
			fl.rotation_degrees = Vector3(180, 90, 0)
			g.add_child(fl)
			fl.position = q + Vector3(0, -0.3, 0)
	var stand := rcyl("SnareStand", Vector3(47.6, top_y, 36.8), 0.35, 0.9, Color("#FFF1DC"), Color("#E8435A"), false, null, g, 20)
	# Sugar cubes up to the walkway (W3-2 / page 4 route) and the fort pole to the tower.
	for id in ["sugar_cube_1", "sugar_cube_2"]:
		var p: Dictionary = _plat(id)
		rbox(id, v3(p["pos"]), v3(p["size"]), Color("#FFFFFF"), Color("#EDF2FF"), 0.08, toon(Color.WHITE, "", 0.35, true, 0.6, Color(0.6, 0.7, 1.0), 0.15, 0.6, 0.9), g)
	var pole := inst(O + "Climbable.tscn", Vector3(51.4, 5.6, 37.0), g, {"look": 1, "height": 4.6, "pole_radius": 0.35})
	if pole:
		pole.name = "FortPole"
		_stripe_pole(pole, 4.6, 0.32)
	# Parade drum (solid) with the W3-2 encounter controller.
	var dr: Dictionary = _plat("parade_drum")
	var dp := v3(dr["pos"])
	var drum := rcyl("ParadeDrum", Vector3(dp.x, 2.0, dp.z), 1.2, 1.0, Color("#FFF1DC"), Color("#E8435A"), true, null, g, 28)
	for j in 12:
		var a := TAU * j / 12.0
		var cord := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.95, 0.05)
		cord.mesh = bm
		cord.material_override = toon(Color("#FFF7EE"))
		cord.position = Vector3(cos(a) * 1.22, 0.5, sin(a) * 1.22)
		cord.rotation = Vector3(0, -a, 0.4 if j % 2 else -0.4)
		drum.add_child(cord)
	# R1.6 drum slam: Ham Slam the drum top while armed -> shockwave r 7 m topples (defeats) nearby squad
	# grenadiers; Sergeant Snap within 3 m takes a hit. Rearms after 6 s (drumskin glows when ready).
	var skin := MeshInstance3D.new()
	var skm := CylinderMesh.new()
	skm.top_radius = 1.12
	skm.bottom_radius = 1.12
	skm.height = 0.04
	skin.mesh = skm
	skin.position = Vector3(0, 1.03, 0)
	drum.add_child(skin)
	var armed_mat := toon(Color(1.0, 0.95, 0.8), "", 0.35, false, 0.5, Color(1.0, 0.7, 0.3), 1.2)
	var spent_mat := toon(Color(0.9, 0.85, 0.75), "", 0.35, false, 0.7)
	skin.material_override = armed_mat
	var ds := SlamSensor.create(drum, 1.2, 0.8, Vector3(0, 1.0, 0))
	_drum_skin = skin
	_drum_mats = [armed_mat, spent_mat]
	for ry in [0.06, 0.98]:
		var rim := MeshInstance3D.new()
		var rtm := TorusMesh.new()
		rtm.inner_radius = 1.17
		rtm.outer_radius = 1.3
		rtm.rings = 40
		rtm.ring_segments = 8
		rim.mesh = rtm
		rim.material_override = toon(Color("#E0B04A"), "", 0.35, false, 0.25, Color.BLACK, 0.0, 0.7, 1.4)
		drum.add_child(rim)
		rim.position = Vector3(0, ry, 0)
	# R2.3: the W3-2 controller (w3_fort.gd) owns the drum rules (topple, rearm, phase-4 BOOM).
	ds.slammed.connect(func(_by: Node) -> void:
		var fort := get_node_or_null("FortEncounter")
		if fort and fort.has_method("on_drum_slam"):
			fort.call("on_drum_slam", drum.global_position + Vector3(0, 1.0, 0)))


# ================================================================ woods, breadcrumbs, hidden clearing (W3-1)

func _build_woods_and_clearing() -> void:
	var g := group_node("Woods")
	# Hedge ring (liquorice bramble) r 8 around (-48, -1), gap 3.5 m at the south (z +7).
	var cc := Vector3(-48, 4, -1)
	var hb := body("Hedge", cc, g, "plant")
	var vis := Node3D.new()
	hb.add_child(vis)
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var gap_half := asin(1.9 / 8.0)
	var n := 28
	for i in n:
		var a := PI * 0.5 + gap_half + (TAU - 2.0 * gap_half) * (float(i) + 0.5) / n
		var p := Vector3(cos(a) * 8.0, 0, sin(a) * 8.0)
		var cs := box_shape(hb, Vector3(1.4, 10.0, 2.0), p + Vector3(0, 4.0, 0), Vector3(0, -rad_to_deg(a), 0))
		cs.name = "HedgeShape%d" % i
		# Twisted liquorice ropes.
		for j in 3:
			var col := Color(0.17, 0.11, 0.17) if (i + j) % 3 != 0 else Color(0.78, 0.13, 0.22)
			var pts := PackedVector3Array()
			var a0 := a + rng.randf_range(-0.12, 0.12)
			for kk in 6:
				var y := float(kk) * 0.85
				var w := 0.35 * sin(kk * 1.3 + j * 2.0 + i)
				pts.append(Vector3(cos(a0) * (8.0 + w), y - 0.3, sin(a0) * (8.0 + w)) + Vector3(-sin(a0), 0, cos(a0)) * (float(j) - 1.0) * 0.45)
			mesh_node(Geo.tube(pts, 0.3, 8, col, col.lightened(0.15), 2.0), toon(Color.WHITE, "", 0.35, true, 0.25, Color.BLACK, 0.0, 0.5, 0.9), Vector3.ZERO, vis)
		if i % 2 == 0:
			var berry := sphere_mesh(0.22, Color("#FF5C9A"), 0.2)
			berry.position = Vector3(cos(a) * 8.3, 2.6 + rng.randf() * 1.5, sin(a) * 8.3)
			vis.add_child(berry)
	# Gate in the south gap: two candy-cane leaves with a shared collider (disabled when the gate opens).
	var gate := Node3D.new()
	gate.name = "HedgeGate"
	g.add_child(gate)
	gate.position = cc + Vector3(0, 0, 8.0)
	var gb := body("GateBody", Vector3.ZERO, gate)
	box_shape(gb, Vector3(3.8, 10.0, 0.6), Vector3(0, 4.0, 0))
	for side in [-1, 1]:
		var leaf := Node3D.new()
		leaf.name = "LeafL" if side < 0 else "LeafR"
		gate.add_child(leaf)
		leaf.position = Vector3(side * 1.9, 0, 0)
		for j in 4:
			var cane := glb(P_CANE, Vector3(-side * (0.3 + j * 0.42), 0, 0), 90.0 * side, Vector3(1.0, 1.7, 1.0), leaf)
		var rail := MeshInstance3D.new()
		rail.mesh = Geo.rounded_box(Vector3(1.8, 0.25, 0.18), 0.06, 2, Color("#FFF7EE"), Color("#FF7FAF"))
		rail.material_override = vc_mat(0.4)
		rail.position = Vector3(-side * 0.95, 1.3, 0)
		leaf.add_child(rail)
	var lock := sphere_mesh(0.35, Color("#E2B77A"), 0.6)
	lock.position = Vector3(0, 1.4, 0.15)
	lock.scale = Vector3(1, 1, 0.4)
	gate.add_child(lock)
	# Wafer stump with the truffle, ringed by acorns (acorns placed with the groups).
	_build_crow_nest(g)
	# R1.4 tutorial crumbs: 10 glowing crumbs along the approach to the maze (no count gate).
	var pts := PackedVector3Array()
	for p in data["splines"]["paths"]:
		if String(p["id"]) == "path_breadcrumb":
			for q in p["points"]:
				pts.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	var dense := Geo.resample(Geo.dense(pts, 8), 2.7)
	var crumbs := PackedVector3Array()
	for i in mini(10, dense.size()):
		var c := dense[i]
		crumbs.append(Vector3(c.x, h_at(c.x, c.z) + 0.15, c.z))
	_crumb_cfg = {"crumbs": crumbs, "stolen": PackedInt32Array(), "groups": PackedInt32Array()}
	# R1.4 liquorice maze: 21 hedge boxes from the JSON, each with a thorn crown hazard on top.
	var mz := Node3D.new()
	mz.name = "Maze"
	g.add_child(mz)
	var hedge_mat := toon(Color.WHITE, "", 0.35, true, 0.3, Color.BLACK, 0.0, 0.55, 0.9)
	var thorn_mm := MultiMesh.new()
	thorn_mm.transform_format = MultiMesh.TRANSFORM_3D
	thorn_mm.use_colors = true
	var pm := PrismMesh.new()
	pm.size = Vector3(0.22, 0.5, 0.22)
	thorn_mm.mesh = pm
	var txs: Array[Transform3D] = []
	var tcols: Array[Color] = []
	var trng := RandomNumberGenerator.new()
	trng.seed = 41
	for p in data["platforms"]:
		if String(p["kind"]) != "hedge_wall":
			continue
		var pos := v3(p["pos"])
		var sz := v3(p["size"])
		var hb2 := body(String(p["id"]), pos, mz, "plant")
		box_shape(hb2, sz)
		hb2.add_to_group("camera_exclude")
		# R1 feel fix: hedges on layer 3 (value 4): Mak still collides (player mask 5) but the camera arm (layer 1 only)
		# passes through, so the maze camera no longer wedges against the walls. R1 visual: mint gummy, not meadow green.
		hb2.collision_layer = 4
		mesh_node(Geo.rounded_box(sz + Vector3(0.1, 0, 0.1), 0.45, 3, Color("#8FE3C6"), Color("#5FBF9F")), hedge_mat, Vector3.ZERO, hb2)
		# Spearmint topiary on liquorice-stick frames: only the black corner posts show (R2.7).
		var long_x := sz.x > sz.z
		var ln := maxf(sz.x, sz.z)
		for e in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pbm := BoxMesh.new()
			pbm.size = Vector3(0.3, sz.y + 0.3, 0.3)
			post.mesh = pbm
			post.material_override = toon(Color(0.14, 0.1, 0.14), "", 0.35, false, 0.3)
			post.position = Vector3(e * (sz.x * 0.5) if long_x else 0.0, 0.15, 0.0 if long_x else e * (sz.z * 0.5))
			hb2.add_child(post)
		# Leafy bumps along the top (topiary read).
		var nb := int(ln / 1.3)
		for k in nb:
			var o := -ln * 0.5 + (k + 0.5) * ln / nb
			var bump := sphere_mesh(0.62, Color("#A8EDD5"), 0.7)
			bump.material_override = toon(Color("#B4F0DA"), "", 0.35, false, 0.3, Color.BLACK, 0.0, 0.5, 0.6)
			bump.position = Vector3(o if long_x else 0.0, sz.y * 0.5 - 0.05, 0.0 if long_x else o)
			bump.scale = Vector3(1.0, 0.55, 1.0)
			bump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hb2.add_child(bump)
		# Thorn crown: hazard volume + spikes and red berries.
		var hz := Area3D.new()
		hz.collision_layer = 16
		hz.collision_mask = 0
		hz.add_to_group("hazard")
		hz.set_meta("damage", 1)
		hz.set_meta("knockback_up", 6.0)
		mz.add_child(hz)
		hz.global_position = pos + Vector3(0, sz.y * 0.5 + 0.6, 0)
		box_shape(hz, Vector3(sz.x + 0.2, 1.2, sz.z + 0.2))
		var cnt := int(ln / 0.45)
		for k in cnt:
			var o2 := -ln * 0.5 + (k + 0.5) * ln / cnt
			var tp := pos + Vector3(o2 if long_x else trng.randf_range(-0.3, 0.3), sz.y * 0.5 + 0.2, trng.randf_range(-0.3, 0.3) if long_x else o2)
			txs.append(Transform3D(Basis(Vector3(trng.randf_range(-0.4, 0.4), 0, trng.randf_range(-0.4, 0.4)).normalized() if trng.randf() < 0.5 else Vector3.UP, trng.randf_range(0.0, 0.5)), tp))
			tcols.append(Color("#2B1E2E") if k % 3 != 0 else Color("#FF5A3C"))
	thorn_mm.instance_count = txs.size()
	for i in txs.size():
		thorn_mm.set_instance_transform(i, txs[i])
		thorn_mm.set_instance_color(i, tcols[i])
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = thorn_mm
	var tm := StandardMaterial3D.new()
	tm.vertex_color_use_as_albedo = true
	tm.roughness = 0.3
	tmi.material_override = tm
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mz.add_child(tmi)
	# Snout Sniff scent along the solution.
	var sc := Node3D.new()
	sc.name = "MazeScent"
	sc.set_script(load("res://scripts/worlds/w3_maze_scent.gd"))
	var nodes := PackedVector3Array()
	for q in data["maze"]["scent_nodes"]:
		nodes.append(v3(q))
	sc.set("nodes", nodes)
	mz.add_child(sc)
	# Signs: at the entrance, and the wolf's rewritten page in the far dead end.
	inst(O + "SignPost.tscn", Vector3(-33.5, h_at(-33.5, 26.0), 26.0), g, {"board_text": "The Maze", "lines": PackedStringArray(["The crows ate the trail. Hold Sniff and follow your snout.", "(Thorns on top. Do not climb the hedges. Yes, you.)"])})
	var note := Label3D.new()
	note.text = "The crumbs were DELICIOUS.
  R.H. III"
	note.font_size = 48
	note.modulate = Color("#5A3221")
	note.outline_size = 8
	note.outline_modulate = Color("#FFF7EE")
	note.pixel_size = 0.005
	mz.add_child(note)
	note.global_position = Vector3(-56, 5.4, 8.6)
	_build_maze_mist(mz)


## R2.7 candyfloss mist (cheap version without volumetric fog): soft pink puffs just above the hedge tops that
## fade out near the camera (distance fade 8 -> 16 m), so Mak's cell and its neighbours read while the far half of
## the maze, including the exit, is hidden from the entrance. From StoryCam B/D the maze reads as a pink cloud bank.
func _build_maze_mist(mz: Node3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mm.mesh = sm
	var xs: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 512
	for c in 7:
		for r in 5:
			for k in 2:
				var x := -58.0 + 4.0 * c + rng.randf_range(-1.2, 1.2)
				var z := 8.0 + 4.0 * r + rng.randf_range(-1.2, 1.2)
				var y := 7.6 + rng.randf_range(-0.3, 0.6)
				var sc := Vector3(rng.randf_range(2.0, 2.8), rng.randf_range(0.8, 1.2), rng.randf_range(2.0, 2.8))
				xs.append(Transform3D(Basis.from_scale(sc), Vector3(x, y, z)))
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "CandyflossMist"
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.97, 0.83, 0.89, 0.82)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.roughness = 1.0
	m.rim_enabled = true
	m.rim = 0.6
	m.emission_enabled = true
	m.emission = Color(1.0, 0.86, 0.92)
	m.emission_energy_multiplier = 0.35
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 8.0
	m.distance_fade_max_distance = 16.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mz.add_child(mi)


## R3.6 W3-1 finale: the crows' nest on a twisted liquorice lollipop trunk. Only a bounce off the stalker's back
## (6 m apex) reaches it; the trunk refuses wall kicks and ledge grabs, the nest rim is a forgiving ledge.
func _build_crow_nest(g: Node3D) -> void:
	var floor_y := h_at(-48, -1)
	var trunk := body("crow_nest_trunk", Vector3(-48, floor_y - 0.2, -1), g, "candy")
	cyl_shape(trunk, 0.6, 10.6 - floor_y + 0.2, Vector3(0, (10.6 - floor_y + 0.2) * 0.5, 0))
	for k in ["no_ledge_grab", "no_wall_kick"]:
		trunk.add_to_group(k)
		trunk.set_meta(k, true)
	var tpts := PackedVector3Array()
	for i in 9:
		var y := float(i) / 8.0 * (10.8 - floor_y + 0.2)
		tpts.append(Vector3(sin(i * 0.9) * 0.08, y, cos(i * 0.9) * 0.08))
	for j in 3:
		var off := Vector3(cos(j * TAU / 3.0), 0, sin(j * TAU / 3.0)) * 0.28
		var pts := PackedVector3Array()
		for i in tpts.size():
			var a := j * TAU / 3.0 + float(i) * 0.7
			pts.append(tpts[i] + Vector3(cos(a), 0, sin(a)) * 0.3)
		var col := Color(0.16, 0.1, 0.15) if j != 1 else Color(0.82, 0.16, 0.26)
		mesh_node(Geo.tube(pts, 0.3, 10, col, col.lightened(0.18), 1.5), toon(Color.WHITE, "", 0.35, true, 0.25, Color.BLACK, 0.0, 0.55, 0.9), Vector3.ZERO, trunk)
	# The nest: a woven biscuit-twig bowl (top 11.0, r 1.6) full of stolen crumbs and wrappers.
	var nest := body("crow_nest", Vector3(-48, 10.6, -1), g, "wood")
	cyl_shape(nest, 1.6, 0.4, Vector3(0, 0.2, 0))
	mesh_node(Geo.lathe([Vector2(0.5, -0.35), Vector2(1.4, -0.1), Vector2(1.85, 0.3), Vector2(1.75, 0.62), Vector2(1.45, 0.55), Vector2(1.3, 0.42), Vector2(0.0, 0.42)], 32, 1.0, 1.0,
		[Color("#8A5228"), Color("#B8733A"), Color("#D9A05B"), Color("#F3D08F"), Color("#C98A4B"), Color("#9A6232"), Color("#E8C27A")], false, false, 0.06, 7),
		toon(Color.WHITE, "gingerbread", 0.6, true, 0.85), Vector3.ZERO, nest)
	var rng := RandomNumberGenerator.new()
	rng.seed = 97
	for i in 22:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.35, 1.8)
		var tw := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.06
		cm.height = rng.randf_range(0.7, 1.2)
		cm.radial_segments = 6
		tw.mesh = cm
		tw.material_override = toon(Color("#A8693A") if i % 3 else Color("#F3D08F"))
		nest.add_child(tw)
		tw.position = Vector3(cos(a) * r, 0.45, sin(a) * r)
		tw.rotation = Vector3(PI * 0.5, a + rng.randf_range(-0.6, 0.6), rng.randf_range(-0.3, 0.3))
	for i in 7:
		var a := rng.randf() * TAU
		var cr := sphere_mesh(0.14, Color(1.0, 0.82, 0.45))
		cr.material_override = toon(Color(1.0, 0.82, 0.45), "", 0.35, false, 0.5, Color(1.0, 0.7, 0.3), 1.6)
		nest.add_child(cr)
		cr.position = Vector3(cos(a) * rng.randf_range(0.3, 1.0), 0.48, sin(a) * rng.randf_range(0.3, 1.0))
	for i in 3:
		var wr := MeshInstance3D.new()
		wr.mesh = Geo.rounded_box(Vector3(0.35, 0.05, 0.22), 0.02, 1, [Color("#FF7FAF"), Color("#7FE0C2"), Color("#FFE07A")][i], Color.WHITE)
		wr.material_override = vc_mat(0.3)
		nest.add_child(wr)
		wr.position = Vector3(cos(i * 2.1) * 0.8, 0.47, sin(i * 2.1) * 0.8)
		wr.rotation.y = i * 1.3
	# A lollipop canopy behind the nest makes the tree read from StoryCam B/D (no collision).
	var cand := MeshInstance3D.new()
	var cdm := CylinderMesh.new()
	cdm.top_radius = 1.7
	cdm.bottom_radius = 1.7
	cdm.height = 0.45
	cdm.radial_segments = 40
	cand.mesh = cdm
	cand.material_override = toon(Color("#FF8FB8"), "candy_stripes", 0.5, false, 0.3, Color.BLACK, 0.0, 0.5, 0.8)
	nest.add_child(cand)
	cand.position = Vector3(0, 2.2, -1.9)
	cand.rotation_degrees = Vector3(90, 0, 0)
	inst(O + "Truffle.tscn", Vector3(-48, 11.8, -1), g, {"truffle_id": "W3-1"})
	# Hint sign at the gate: the nest is out of reach without help.
	var lb := Label3D.new()
	lb.text = "CAW! Our nest. Our crumbs.
No pigs. (Not even bouncy ones.)"
	lb.font_size = 40
	lb.modulate = Color("#3B2416")
	lb.outline_size = 8
	lb.outline_modulate = Color("#FFF7EE")
	lb.pixel_size = 0.005
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nest.add_child(lb)
	lb.position = Vector3(0, -2.4, 0.9)


# ================================================================ falls, pool, grotto, cliff (W3-8, page 1)

func _build_falls_and_grotto() -> void:
	var g := group_node("Falls")
	var rock_mat := toon(Color(1.0, 0.72, 0.86), "", 0.35, false, 0.2, Color(1.0, 0.5, 0.75), 0.15, 0.7, 1.2)
	# Rock-candy pillars to the cliff (MA4 / page 1) and pool rocks (W3-8).
	for p in data["platforms"]:
		var id := String(p["id"])
		if not (id.begins_with("rock_candy_pillar") or id.begins_with("pool_rock")):
			continue
		var pos := v3(p["pos"])
		var sz := v3(p["size"])
		var r := sz.x * 0.5
		var base := pos.y - sz.y * 0.5
		var glass := String(p["kind"]) == "falling_platform"
		var prof := [Vector2(r * 1.15, 0.0), Vector2(r, 0.4), Vector2(r * 0.97, sz.y - 0.35), Vector2(r * 0.8, sz.y - 0.05), Vector2(0.0, sz.y)]
		var cols := [Color("#D98AD9"), Color("#FF9EC4"), Color("#FFB3D1"), Color("#FFE4F0"), Color("#FFF2F8")]
		var pm := toon(Color.WHITE, "", 0.35, true, 0.2, Color(1.0, 0.5, 0.75), 0.12, 0.7, 1.2)
		if glass:
			# Sugar-glass pillar: static stump + a 1.6 m crumbling top segment (w3_crumble.gd).
			var stump_h := sz.y - 1.6
			var sb := body(id + "_stump", Vector3(pos.x, base, pos.z), g, "candy")
			cyl_shape(sb, r * 0.8, stump_h, Vector3(0, stump_h * 0.5, 0))
			mesh_node(Geo.lathe([Vector2(r * 1.1, 0.0), Vector2(r * 0.8, 0.4), Vector2(r * 0.78, stump_h)], 7, 1.0, 1.0, [Color("#B58AE0"), Color("#C9A6F2"), Color("#D9C2FF")]), pm, Vector3.ZERO, sb)
			var top := Node3D.new()
			top.name = id
			top.set_script(load("res://scripts/worlds/w3_crumble.gd"))
			top.set("top_local", 1.6)
			top.position = Vector3(pos.x, base + stump_h, pos.z)
			var tb := body("Body", Vector3.ZERO, top, "candy")
			cyl_shape(tb, r, 1.6, Vector3(0, 0.8, 0))
			var tv := Node3D.new()
			tv.name = "Visual"
			top.add_child(tv)
			var gm := toon(Color.WHITE, "", 0.35, true, 0.08, Color(0.75, 0.55, 1.0), 0.35, 0.9, 1.5)
			mesh_node(Geo.lathe([Vector2(r, 0.0), Vector2(r * 1.02, 1.2), Vector2(r * 0.85, 1.55), Vector2(0.0, 1.6)], 7, 1.0, 1.0, [Color("#C9A6F2"), Color("#E2D0FF"), Color("#F4ECFF"), Color("#FFFFFF")]), gm, Vector3.ZERO, tv)
			g.add_child(top)
			continue
		var b := body(id, Vector3(pos.x, base, pos.z), g, "candy")
		cyl_shape(b, r, sz.y, Vector3(0, sz.y * 0.5, 0))
		var m := Geo.lathe(prof, 7, 1.0, 1.0, cols)
		var mi := mesh_node(m, pm, Vector3.ZERO, b)
		mi.rotation_degrees.y = float(id.hash() % 60)
	# Grotto behind the falls: floor top 5.0 (x -46..-42, z -40.5..-37.5), side walls, roof at 8.5.
	var gr := body("Grotto", Vector3(-44, 0, -39), g, "candy")
	box_shape(gr, Vector3(4.4, 5.0, 3.2), Vector3(0, 2.5, 0))
	box_shape(gr, Vector3(0.8, 3.6, 3.2), Vector3(-2.4, 6.8, 0))
	box_shape(gr, Vector3(0.8, 3.6, 3.2), Vector3(2.4, 6.8, 0))
	box_shape(gr, Vector3(5.6, 0.8, 3.4), Vector3(0, 8.9, -0.1))
	for spec in [[Vector3(-44, 5.0, -39), Vector3(2.2, 2.0, 1.6)], [Vector3(-46.6, 5.0, -38.6), Vector3(1.2, 2.6, 1.2)], [Vector3(-41.4, 5.0, -38.6), Vector3(1.2, 2.6, 1.2)], [Vector3(-44, 8.4, -39), Vector3(2.2, 0.8, 1.4)]]:
		var rk := glb(P_ROCK, spec[0] - Vector3(0, spec[1].y * 0.9, 0), float(int(spec[0].x * 13.0) % 360), spec[1], g)
	var fl := mesh_node(Geo.rounded_box(Vector3(4.4, 0.6, 3.2), 0.2, 3, Color("#FFD1E4"), Color("#E89AC0")), vc_mat(0.3, 0.8), Vector3(-44, 4.7, -39), g)
	# R1.8 three sugar geodes: sniff makes the right one glow, punch/kick cracks it (wrong ones burst into acorns).
	var gd: Dictionary = _plat("grotto_geodes")
	var members: Array = gd["members"]
	var right := int(Time.get_ticks_usec() % members.size())
	var dev0 := get_node_or_null("/root/Dev")
	if dev0 and dev0.has_method("has_arg") and dev0.call("has_arg", "w3-bot"):
		right = 1
	for gi in members.size():
		var gp := v3(members[gi])
		var geo_n := Node3D.new()
		geo_n.name = "Geode%d" % gi
		g.add_child(geo_n)
		geo_n.global_position = gp
		var gm2 := sphere_mesh(0.48, Color(0.95, 0.8, 1.0), 0.2)
		gm2.material_override = toon(Color(0.96, 0.86, 1.0), "", 0.35, false, 0.15, Color(0.8, 0.5, 1.0), 0.2, 0.9, 1.4)
		gm2.scale = Vector3(1.0, 1.1, 0.7)
		geo_n.add_child(gm2)
		for k2 in 5:
			var cr := MeshInstance3D.new()
			var pmm := PrismMesh.new()
			pmm.size = Vector3(0.18, 0.45, 0.18)
			cr.mesh = pmm
			cr.material_override = toon(Color(1.0, 0.7, 0.9), "", 0.35, false, 0.1, Color(1.0, 0.4, 0.8), 0.4, 0.9, 1.4)
			cr.position = Vector3(cos(k2 * 1.3) * 0.32, 0.3 + sin(k2 * 2.1) * 0.15, 0.25)
			cr.rotation_degrees = Vector3(20 * sin(k2), k2 * 70.0, 25 * cos(k2))
			geo_n.add_child(cr)
		var is_right := gi == right
		if is_right:
			var sn := Node3D.new()
			sn.set_script(load("res://scripts/objects/sniff_target.gd"))
			geo_n.add_child(sn)
			sn.connect("sniffed", func(_by: Node) -> void:
				var tw := gm2.create_tween().set_loops(6)
				tw.tween_property(gm2, "scale", Vector3(1.2, 1.3, 0.85), 0.25)
				tw.tween_property(gm2, "scale", Vector3(1.0, 1.1, 0.7), 0.25)
				var ol := OmniLight3D.new()
				ol.light_color = Color(1.0, 0.85, 0.4)
				ol.light_energy = 2.0
				ol.omni_range = 3.0
				geo_n.add_child(ol)
				print("[W3] geode sniffed"))
		var ss2 := SlamSensor.create(geo_n, 0.7, 1.1, Vector3(0, -0.4, 0.2))
		ss2.struck.connect(func(_kind: String, _from: Vector3) -> void: _crack_geode(geo_n, is_right))
		ss2.slammed.connect(func(_by: Node) -> void: _crack_geode(geo_n, is_right))
	# Syrup spout (wafer gutter) and the falls curtain (node at the spout tip, mesh hangs down).
	# R1.8 pool chute: frosting trough on the north half of the pool path (fast belly-slide line).
	if ResourceLoader.exists(B + "pool_chute.mesh.res"):
		var chb := body("PoolChute", Vector3.ZERO, g, "frosting")
		var chs := CollisionShape3D.new()
		chs.shape = load(B + "pool_chute.shape.res")
		chb.add_child(chs)
		mesh_node(load(B + "pool_chute.mesh.res"), vc_mat(0.35, 0.6), Vector3.ZERO, chb)
		var cpts := PackedVector3Array()
		for q in data["splines"]["pool_chute"]["points"]:
			cpts.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
		# R1 fun blocker (W3-8): the push used to run to the lip and throw Mak at 7.5 m/s into pool_rock_1, and its 2.2 m
		# reach also caught the walking route on the south half. Now it stops 2.5 m before the lip, only acts inside
		# the 2.6 m trough (1.1 m reach), and a 3 m wafer run-out at y 1.0 (no frosting, normal friction) brakes Mak
		# 1.5 m short of pool_rock_1, facing the rocks.
		var chute := Geo.resample(Geo.dense(cpts, 10), 0.8)
		var lip := cpts[cpts.size() - 1]
		var trimmed := PackedVector3Array()
		for q in chute:
			if Vector2(q.x - lip.x, q.z - lip.z).length() > 2.5:
				trimmed.append(q)
		_add_push(g, trimmed, 6.0, "ChutePush", 2.2, 1.1)
		var ro := _wafer(Vector3(-37.6, 0.7, -33.95), Vector3(3.0, 0.6, 2.6), "ChuteRunout", g)
		ro.set_meta("surface", "wood")
	var sp: Dictionary = _plat("syrup_spout")
	_wafer(v3(sp["pos"]), v3(sp["size"]), "SyrupSpout", g)
	var cur := Node3D.new()
	cur.name = "FallsCurtain"
	g.add_child(cur)
	cur.position = Vector3(-44, 16.0, -37.2)
	var cm := mesh_node(load(B + "syrup_falls.mesh.res"), _curtain_mat(true), Vector3(0, -16.0, 0), cur)
	cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var foam := add_fx("WaterfallFoam", Vector3(-44, 0.4, -35.8), g, Color(1.0, 0.8, 0.9), 1.0)
	# Curtain wind zone (down and out), disabled for 35 s by the cauldron lid.
	# Wider and stronger than the plan's 1.6 m slab: crossing it is short, and the player smooths wind in over ~0.2 s.
	var wz := inst(O + "WindZone.tscn", Vector3(-44, 8.5, -36.7), g, {"size": Vector3(6.4, 17, 3.0), "direction": Vector3(0, -20, 7).normalized(), "strength": Vector3(0, -20, 7).length(), "show_particles": false})
	if wz:
		wz.name = "FallsWind"
	# Chain controller (lid -> pipe puff -> falls stop).
	var ctl := Node3D.new()
	ctl.name = "FallsChain"
	ctl.set_script(load("res://scripts/worlds/w3_falls.gd"))
	var pipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(B + "pipe_points.json"))
	var pp := PackedVector3Array()
	for q in pipe:
		pp.append(Vector3(float(q[0]), float(q[1]) + 0.1, float(q[2])))
	ctl.set("pipe_points", pp)
	ctl.set("lid_top", Vector3(3, 8.0 + 2.45 * 1.3, -29))
	ctl.set("stop_seconds", 18.0)   # R1.8: 18 s from the valve shutting (after the 3 s puff)
	add_child(ctl)
	ctl.set("wind_zone_path", ctl.get_path_to(wz) if wz else NodePath())
	ctl.set("curtain_path", ctl.get_path_to(cur))
	ctl.set("lid_path", ctl.get_path_to(get_node("Knoll/CauldronLid")))
	if foam:
		ctl.set("foam_path", ctl.get_path_to(foam))
	# Rock-candy crystal clusters along the cliff face (hide the steep heightmap wall, read as candy rock).
	var rr := RandomNumberGenerator.new()
	rr.seed = 516
	var cx := -59.0
	while cx < -30.0:
		if absf(cx + 44.0) > 4.5:
			var sc := rr.randf_range(2.2, 3.6)
			var zf := -41.0 + rr.randf_range(-0.6, 0.8)
			var rk1 := glb(P_ROCK, Vector3(cx, rr.randf_range(-0.5, 5.0), zf), rr.randf() * 360.0, Vector3(sc, sc * rr.randf_range(1.2, 2.2), sc), g)
			_tint_glb(rk1, [Color("#FF9EC4"), Color("#C9A6F2"), Color("#FFC2DD")][int(cx) % 3])
		cx += rr.randf_range(3.0, 4.5)
	cx = -31.0
	var cz := -54.0
	while cz < -42.0:
		var sc2 := rr.randf_range(2.0, 3.2)
		var rk2 := glb(P_ROCK, Vector3(cx + rr.randf_range(-0.5, 0.5), rr.randf_range(0.0, 5.0), cz), rr.randf() * 360.0, Vector3(sc2, sc2 * rr.randf_range(1.2, 2.0), sc2), g)
		_tint_glb(rk2, [Color("#FF9EC4"), Color("#C9A6F2"), Color("#FFC2DD")][int(absf(cz)) % 3])
		cz += rr.randf_range(3.0, 4.2)
	# Giant cupcake on the cliff top (landmark; acorn ring hides behind it) and Lost Page 1 beside it.
	var cup := glb(P_CUPCAKE, Vector3(-50, 16.0, -48), 200.0, 0.75, g)
	var cupb := body("CupcakeBody", Vector3(-50, 16.0, -48), g)
	cyl_shape(cupb, 1.8, 6.0, Vector3(0, 3.0, 0))


func _crack_geode(n: Node3D, right: bool) -> void:
	if n.get_meta("cracked", false):
		return
	n.set_meta("cracked", true)
	ObjSvc.burst(self, n.global_position, Color(1.0, 0.85, 0.95), 34, 5.0, 0.18, -10.0, 0.9)
	ObjSvc.sfx("glass_break", n.global_position)
	for c in n.get_children():
		if c is Node3D:
			(c as Node3D).visible = false
	if right:
		print("[W3] geode cracked: W3-8")
		ObjSvc.spawn_truffle(self, Transform3D(Basis(), Vector3(-44, 5.8, -39.6)), "W3-8", true)
	else:
		for k in 2:
			inst(O + "Acorn.tscn", n.global_position + Vector3(k * 0.6 - 0.3, 0.2, 0.8), self)


# ================================================================ glade (spawn, gate, lectern, NPC)

func _build_glade() -> void:
	var g := group_node("Glade")
	# Storybook Gate: two giant candy canes framing the path, an open-book sign between them.
	glb(P_CANE, Vector3(-3.6, 2.0, 40), 0.0, 5.0, g)
	glb(P_CANE, Vector3(3.6, 2.0, 40), 180.0, 5.0, g)
	var gpost := body("GatePosts", Vector3(0, 2, 40), g)
	cyl_shape(gpost, 0.4, 7.0, Vector3(-3.6, 3.5, 0))
	cyl_shape(gpost, 0.4, 7.0, Vector3(3.6, 3.5, 0))
	var book := Node3D.new()
	book.set_script(load("res://scripts/worlds/w3_bobber.gd"))
	book.set("sway_deg", 3.0)
	book.set("sway_period", 3.5)
	g.add_child(book)
	book.position = Vector3(0, 7.2, 40)
	for side in [-1, 1]:
		var pg := MeshInstance3D.new()
		pg.mesh = Geo.rounded_box(Vector3(1.9, 1.3, 0.12), 0.05, 2, Color("#FFF7EE"), Color("#F2E3C8"))
		pg.material_override = vc_mat(0.8)
		pg.position = Vector3(side * 0.95, 0, 0)
		pg.rotation_degrees.y = side * -12.0
		book.add_child(pg)
	var cover := MeshInstance3D.new()
	cover.mesh = Geo.rounded_box(Vector3(4.1, 1.45, 0.1), 0.05, 2, Color("#8A2E2E"), Color("#6B1F22"))
	cover.material_override = vc_mat(0.6)
	# OPUSLOOK: behind the deepest point of the angled pages (z -0.26 at the spine). At z -0.12 the cover's face poked
	# through a 0.66 m band between the pages and split the title ("Gingerbr | ead Grove").
	cover.position = Vector3(0, 0, -0.32)
	book.add_child(cover)
	var lbl := Label3D.new()
	lbl.text = "Gingerbread Grove"
	lbl.font_size = 64
	lbl.outline_size = 10
	lbl.modulate = Color("#7A4523")
	lbl.outline_modulate = Color("#FFF7EE")
	# In front of the angled pages (at z 0.12 their outer edges clipped "Gin" and "ove").
	lbl.position = Vector3(0, 0.02, 0.42)
	lbl.pixel_size = 0.0052
	book.add_child(lbl)
	# Page Lectern with the W3-5 reward marker (LostPageSet).
	var lec := rbox("Lectern", Vector3(6, 2.6, 44), Vector3(1.0, 1.2, 0.8), Color("#C97B3A"), Color("#8E4E22"), 0.12, toon(Color.WHITE, "gingerbread", 0.6, true), g)
	var open_book := MeshInstance3D.new()
	open_book.mesh = Geo.rounded_box(Vector3(1.3, 0.1, 0.9), 0.04, 2, Color("#FFF7EE"), Color("#E8D6B5"))
	open_book.material_override = vc_mat(0.8)
	open_book.position = Vector3(0, 0.65, 0)
	open_book.rotation_degrees.x = 15.0
	lec.add_child(open_book)
	var ps := inst(O + "LostPageSet.tscn", Vector3(6, 3.3, 44), g, {"world_id": "W3", "reward_truffle_id": "W3-5", "required": 5})
	if ps:
		(ps.get_node("TruffleMarker") as Node3D).global_position = Vector3(6, 2.7, 45.0)
		ps.connect("rewarded", func(id: String) -> void: print("[W3] lost pages complete: %s appears at the lectern" % id))
	# W3-100: the 100-acorn truffle appears above Mak.
	_acorn_hundred = inst(O + "AcornHundred.tscn", Vector3(0, 3, 45), g, {"reward_truffle_id": "W3-100", "required": 100})
	if _acorn_hundred:
		_acorn_hundred.connect("rewarded", func(id: String) -> void: print("[W3] 100 acorns: %s appears above Mak" % id))
	# Pip (real generated model) as the hint-giver at the gate.
	var pip := inst(O + "NPCTalker.tscn", Vector3(-4.2, 2.0, 44.5), g, {"speaker": "Pip",
		"visual_scene": scene("res://assets/characters/pip/pip.glb"), "visual_scale": 1.0, "visual_flip_180": false,
		"lines": PackedStringArray([
			"Cousin Mak! The Gingerbread Guard took the witch's cottage. They march about as if they own the place.",
			"Follow the breadcrumbs west to find the hidden clearing. The crows keep eating them. Bonk a crow, get your crumbs back.",
			"The lid on that cauldron up the hill is loose. Something about the pipe and the pink waterfall. Ham Slam it and run!",
			"Corporal Crumb pinched a truffle and sits on it at the top of the Frosting Slide. Bump his sled, dear. He's only a biscuit.",
		])})
	if pip:
		pip.rotation_degrees.y = 200.0
	# Mother Treacle, the evicted cottage baker (R1.9). The Tripo P2 model is requested; until it lands she uses
	# the closest real cast model (Bramwell).
	var mt_path := "res://assets/characters/mother_treacle/mother_treacle.glb"
	if not ResourceLoader.exists(mt_path):
		mt_path = "res://assets/characters/bramwell/bramwell.glb"
	var mt := inst(O + "NPCTalker.tscn", Vector3(-10.0, h_at(-10.0, 16.5), 16.5), g, {"speaker": "Mother Treacle",
		"visual_scene": scene(mt_path), "visual_scale": 1.0, "visual_flip_180": false,
		"lines": PackedStringArray([
			"Evicted! By biscuits! Forty years I baked in that cottage, and now a tin soldier sleeps in my oven.",
			"Lost the crumb trail, dearie? Use that splendid snout.",
			"Grumpy gumdrops only listen to a firm Ham Slam.",
			"The cauldron lid and the pink falls are connected by that liquorice pipe. Slam it, then RUN.",
		])})
	if mt:
		mt.rotation_degrees.y = 160.0
		mt.name = "MotherTreacle"


# ================================================================ enemies

func _build_enemies() -> void:
	var g := group_node("Enemies")
	var squad: Array = []
	for e in data["enemies"]:
		var id := String(e["id"])
		var typ := String(e["type"])
		if e.has("spawn_on_event"):
			continue
		if id.begins_with("sled_"):
			continue   # R1 QA: the joust builds its own sled riders; the data entries must not walk the summit
		var patrol: Array = e.get("patrol", [])
		if id == "sentry_cottage":
			patrol = [[-10.5, 8.0, -18.2], [-1.5, 8.0, -18.2]]
		var start := v3(patrol[0]) if patrol.size() > 0 else (v3(e["perch"]) if e.has("perch") else Vector3.ZERO)
		var path := E_GRENADIER
		match typ:
			"gummy_brute":
				path = E_BRUTE
			"crow_bandit":
				path = E_CROW
				if e.has("perch"):
					start = v3(e["perch"])
		var props := {}
		var pts: Array[Vector3] = []
		for q in patrol:
			pts.append(v3(q) - start)
		if typ != "crow_bandit":
			props["patrol_points"] = pts
		if typ == "gingerbread_grenadier_sergeant":
			if ResourceLoader.exists("res://assets/characters/sergeant_snap/sergeant_snap.glb"):
				props["mesh_path"] = "res://assets/characters/sergeant_snap/sergeant_snap.glb"
			props["max_hp"] = 3
			props["display_name"] = "Sergeant Snap"
			props["acorns_on_defeat"] = 5
		if not typ.begins_with("crow"):
			start.y = maxf(start.y, h_at(start.x, start.z)) + 0.05
		var en := inst(path, start, g, props)
		if en == null:
			continue
		en.name = id
		if "home" in en:
			en.set("home", start)
		enemies[id] = en
		if id == "brute_clearing":
			# R2.7/R3.6/R3.7: the maze stalker. Its back bounce reaches a 6 m apex (the nest, J96/J97); it stays still
			# until Mak reaches junction (3,2) (stalker_ramp).
			en.set("variant", "stalker")
			en.set("stomp_bounce", 18.6)
			en.set("ai_enabled", false)
		elif id.begins_with("grenadier_tierA"):
			en.set("variant", "lobber")
		elif id == "crow_ravine":
			# R1 QA minor: the crow hit Mak the instant he reached Page 3. It now waits until he has stood on the
			# spire top for 0.5 s (see _spire_step).
			en.set("ai_enabled", false)
		elif id == "crow_lagoon":
			en.set("lose_radius", 8.0)   # R1 QA minor: it drifted 13 m from its mooring post
			# W3-3 fairness pass (2026-10-19): the generic crow dive (notice 10 m) hit Mak on lane E 3.9 m from the post,
			# mid run-up, and knocked him into the hot chocolate. Neither R1.5 (no attack) nor R2.6 (pecks biscuits,
			# never Mak; not implemented) asks for that, so it stays perched and only caws the release.
			en.set("ai_enabled", false)
		if typ == "gingerbread_grenadier_sergeant":
			en.set_meta("w3_sergeant", true)
		if id.begins_with("squad_"):
			squad.append(en)
	for i in squad.size():
		squad[i].set("formation_index", i)
		squad[i].set("squad", squad)
	# W3-2 encounter controller (paths are absolute so _ready can wire signals on add_child).
	var fort := Node3D.new()
	fort.name = "FortEncounter"
	fort.set_script(load("res://scripts/worlds/w3_fort.gd"))
	fort.set("reward_truffle_id", "W3-2")
	fort.set("drum_skin", _drum_skin)
	if _drum_mats.size() == 2:
		fort.set("drum_armed_mat", _drum_mats[0])
		fort.set("drum_spent_mat", _drum_mats[1])
	fort.position = Vector3(46, 2.0, 43)
	var mk := Marker3D.new()
	mk.name = "TruffleMarker"
	mk.position = Vector3(0, 1.8, 0)
	fort.add_child(mk)
	var sp: Array[NodePath] = []
	for en in squad:
		sp.append((en as Node).get_path())
	fort.set("squad_paths", sp)
	if enemies.has("sergeant_snap"):
		fort.set("snap_path", (enemies["sergeant_snap"] as Node).get_path())
	add_child(fort)
	# W3-1 breadcrumbs (needs the crows and the hedge gate).
	var bc := Node3D.new()
	bc.name = "Breadcrumbs"
	bc.set_script(load("res://scripts/worlds/w3_breadcrumbs.gd"))
	bc.set("crumbs", _crumb_cfg["crumbs"])
	bc.set("stolen", _crumb_cfg["stolen"])
	bc.set("stolen_groups", _crumb_cfg["groups"])
	bc.set("gate_opens_at", 999)   # R1.4: the gate opens by proximity (see _maze_step)
	var cp: Array[NodePath] = []
	for id in ["crow_woods_A", "crow_woods_B"]:
		if enemies.has(id):
			cp.append((enemies[id] as Node).get_path())
	bc.set("crow_paths", cp)
	for id in ["crow_woods_A", "crow_woods_B"]:
		if enemies.has(id) and (enemies[id] as Node).has_signal("defeated"):
			var cr: Node3D = enemies[id]
			cr.connect("defeated", func(_e: Node) -> void: _crow_crumbs(cr))
	bc.set("gate_path", get_node("Woods/HedgeGate").get_path())
	get_node("Woods").add_child(bc)


var _stalker_awake := false


func _maze_step(p: Vector3) -> void:
	if not _stalker_awake and Vector2(p.x + 44.0, p.z - 18.0).length() < 3.2 and p.y > 3.0:
		_stalker_awake = true
		if enemies.has("brute_clearing") and is_instance_valid(enemies["brute_clearing"]):
			var br0: Node = enemies["brute_clearing"]
			br0.set("ai_enabled", true)
			br0.set("_hop_t", 2.0)
			if br0.has_method("say"):
				br0.call("say", "HRRAAH! Piggy in my maze!", Color(1.0, 0.45, 0.55), 96)
	if _gate_open:
		return
	if Vector2(p.x + 48.0, p.z - 7.0).length() < 4.0 and p.z > 6.5 and p.y > 3.0:
		_gate_open = true
		var bc := get_node_or_null("Woods/Breadcrumbs")
		if bc and bc.has_method("open_gate"):
			bc.call("open_gate")
		if enemies.has("brute_clearing"):
			var br: Node = enemies["brute_clearing"]
			if is_instance_valid(br):
				br.set("ai_enabled", true)
				br.set("home", Vector3(-48, 4.05, 5))
				if br.has_method("say"):
					br.call("say", "GRAAH! Get off my crows' lawn!", Color(1.0, 0.4, 0.5), 110)
			_stalker_awake = true
		ObjSvc.call_on("UI", "show_banner", ["The Crows' Nest", "Bait the brute under the nest, then bounce off its back!", 3.0])


## R1.4: a punched maze crow bursts out 6 eaten crumbs that glow on the next two solution cells for 15 s.
func _crow_crumbs(crow: Node3D) -> void:
	var sc := get_node_or_null("Woods/Maze/MazeScent")
	var nodes: PackedVector3Array = sc.get("nodes") if sc else PackedVector3Array()
	var start := int(sc.get("progress")) + 1 if sc else 0
	var g := Node3D.new()
	add_child(g)
	for k in 6:
		var i := clampi(start + k / 3, 0, nodes.size() - 1)
		var j := clampi(i + 1, 0, nodes.size() - 1)
		var pos := nodes[i].lerp(nodes[j], float(k % 3) / 3.0)
		pos.y = h_at(pos.x, pos.z) + 0.15
		var m := sphere_mesh(0.2, Color(1.0, 0.8, 0.45))
		m.material_override = toon(Color(1.0, 0.8, 0.45), "", 0.35, false, 0.5, Color(1.0, 0.7, 0.3), 2.5)
		g.add_child(m)
		m.global_position = crow.global_position
		var tw := m.create_tween()
		tw.tween_property(m, "global_position", pos, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ObjSvc.call_on("UI", "toast", ["The crow dropped your breadcrumbs!"])
	var t := get_tree().create_timer(15.0, false, true)
	t.timeout.connect(func() -> void: g.queue_free())


# ================================================================ camera zones (R1 feel/visual fixes)

## MakCameraRig camera_zone volumes (layer 8; metas camera_yaw_deg / camera_pitch_deg / camera_distance /
## camera_blend / camera_priority; unset keeps the free camera's value). Yaw 0 = camera south of Mak looking north,
## 90 = camera east looking west, -90 = camera west looking east, 180 = camera north looking south.
func _build_camera_zones() -> void:
	var g := group_node("CameraZones")
	var slide_yaw := 0.0
	if _slide_c.size() > 3:
		var sd := _slide_c[3] - _slide_c[0]
		slide_yaw = rad_to_deg(atan2(-sd.x, -sd.z))
	var zones := [
		# Maze: MazeCam's high north-facing view (R2.7) with the existing API; hedges no longer block the arm.
		{"name": "CamZone_maze", "pos": Vector3(-46, 6.0, 16), "size": Vector3(25, 6, 17), "camera_yaw_deg": 0.0, "camera_pitch_deg": -50.0, "camera_distance": 7.5, "camera_blend": 3.0, "camera_priority": 2},
		# Frosting Peak rings: camera outside the cake looking in.
		{"name": "CamZone_tierA_south", "pos": Vector3(42, 13.5, -27.0), "size": Vector3(26, 3.4, 6.6), "camera_yaw_deg": 0.0, "camera_pitch_deg": -26.0, "camera_distance": 5.5, "camera_priority": 1},
		# MA2 wall-kick chimney between the peppermint pillar and tier B: side-on view of both walls (R1 feel re-check).
		{"name": "CamZone_MA2", "pos": Vector3(40, 14.5, -28.3), "size": Vector3(4, 6, 3.4), "camera_yaw_deg": 90.0, "camera_pitch_deg": -10.0, "camera_distance": 7.0, "camera_blend": 2.0, "camera_priority": 3},
		# Islet: look along lane E toward the royal and the falls (R1 feel/fun: the release happened off-screen).
		{"name": "CamZone_islet", "pos": Vector3(22.5, 2.5, 8.5), "size": Vector3(6, 4, 6), "camera_yaw_deg": -110.0, "camera_pitch_deg": -25.0, "camera_distance": 6.0, "camera_priority": 2},
		{"name": "CamZone_tierA_east", "pos": Vector3(54.6, 13.5, -36.0), "size": Vector3(3.6, 3.4, 14.0), "camera_yaw_deg": 90.0, "camera_pitch_deg": -22.0, "camera_distance": 6.5, "camera_priority": 1},
		{"name": "CamZone_tierB_east", "pos": Vector3(51.5, 17.6, -40.0), "size": Vector3(5.0, 3.4, 12.0), "camera_yaw_deg": 90.0, "camera_pitch_deg": -22.0, "camera_distance": 6.5, "camera_priority": 1},
		{"name": "CamZone_tierC_pole", "pos": Vector3(46.8, 22.5, -42.0), "size": Vector3(4.4, 5.0, 8.0), "camera_yaw_deg": 90.0, "camera_pitch_deg": -16.0, "camera_distance": 7.0, "camera_priority": 2},
		# Candle wave on tier D's east ring.
		{"name": "CamZone_candles", "pos": Vector3(43.3, 26.5, -41.5), "size": Vector3(4.2, 5.0, 8.6), "camera_yaw_deg": 90.0, "camera_pitch_deg": -22.0, "camera_distance": 7.0, "camera_priority": 3},
		# Summit slide gate: look along the slide's first segment.
		{"name": "CamZone_summit", "pos": Vector3(39, 29.6, -42), "size": Vector3(6.4, 3.2, 6.4), "camera_yaw_deg": slide_yaw, "camera_pitch_deg": -28.0, "camera_distance": 6.0, "camera_priority": 2},
		# Fort yard: high three-quarter view from the west gate (squad, drum and Snap in one frame).
		{"name": "CamZone_fort_yard", "pos": Vector3(46, 3.6, 43), "size": Vector3(17, 5, 13), "camera_yaw_deg": -90.0, "camera_pitch_deg": -30.0, "camera_distance": 10.0, "camera_blend": 3.0, "camera_priority": 1},
		# W3-8 grotto: camera out through the (non-solid) curtain so the payoff reads.
		{"name": "CamZone_grotto", "pos": Vector3(-44, 6.6, -39), "size": Vector3(4.6, 3.2, 3.4), "camera_yaw_deg": 0.0, "camera_pitch_deg": -24.0, "camera_distance": 5.5, "camera_blend": 4.0, "camera_priority": 3},
		# Syrup Pool rocks: face the grotto from the south bank.
		{"name": "CamZone_pool", "pos": Vector3(-42, 2.5, -35), "size": Vector3(8, 5, 6), "camera_yaw_deg": 0.0, "camera_pitch_deg": -20.0, "camera_distance": 8.0, "camera_priority": 1},
		# Page 1 spire top on the cliff.
		{"name": "CamZone_page1", "pos": Vector3(-51, 17.2, -50.5), "size": Vector3(4, 3, 4), "camera_yaw_deg": 0.0, "camera_pitch_deg": -40.0, "camera_distance": 7.8, "camera_priority": 3},
		# Gumdrop Hop: slightly upward view so the spiral above reads.
		{"name": "CamZone_gumdrops", "pos": Vector3(20, 12, 38), "size": Vector3(18, 22, 18), "camera_pitch_deg": 6.0, "camera_distance": 8.0, "camera_priority": 1},
	]
	# R1 feel major: on the slide the camera trailed Mak's velocity by 25-33 degrees on the bends. Zones every 8 m along
	# the slide centre line set the yaw from the spline tangent (distance 7, 1.5 s blend).
	if _slide_c.size() > 6:
		var dense := Geo.resample(_slide_c, 8.0)
		for i in range(1, dense.size() - 1):
			var tan := dense[mini(i + 1, dense.size() - 1)] - dense[i - 1]
			tan.y = 0.0
			if tan.length() < 0.1:
				continue
			zones.append({"name": "CamZone_slide_%d" % i, "pos": dense[i] + Vector3(0, 1.5, 0), "size": Vector3(7, 5, 7),
				"camera_yaw_deg": rad_to_deg(atan2(-tan.x, -tan.z)), "camera_pitch_deg": -20.0, "camera_distance": 7.0,
				"camera_blend": 1.5, "camera_priority": 2})
	for h in zones:
		var a := Area3D.new()
		a.name = String(h["name"])
		a.add_to_group("camera_zone")
		a.collision_layer = 128
		a.collision_mask = 0
		a.monitoring = false
		a.monitorable = true
		for k in h:
			if k not in ["name", "pos", "size"]:
				a.set_meta(k, h[k])
		g.add_child(a)
		a.global_position = h["pos"]
		box_shape(a, h["size"])


# ================================================================ collectibles

func _build_collectibles() -> void:
	var g := group_node("Acorns")
	var n := 0
	for a in data["acorn_groups"]:
		var kind := String(a["kind"])
		var pts: Array[Vector3] = []
		match kind:
			"ring":
				var c := v3(a["center"])
				for i in int(a["count"]):
					var t := TAU * float(i) / float(a["count"])
					pts.append(c + Vector3(cos(t), 0, sin(t)) * float(a["radius"]))
			"line":
				var f := v3(a["from"])
				var t2 := v3(a["to"])
				var cnt := int(a["count"])
				for i in cnt:
					pts.append(f.lerp(t2, float(i) / maxf(cnt - 1, 1)))
			"points":
				for q in a["points"]:
					pts.append(v3(q))
			"crate":
				var cp := v3(a["pos"])
				cp.y = maxf(cp.y, h_at(cp.x, cp.z))
				inst(O + "BreakableCrate.tscn", cp, g, {"acorns": int(a["count"])})
				n += int(a["count"])
				continue
		for p in pts:
			# Keep ground-level acorns above the terrain.
			var floor_y := h_at(p.x, p.z) + 0.5
			if p.y < floor_y and String(a["id"]).find("slide") < 0 and String(a["id"]).find("lane") < 0:
				p.y = floor_y
			_acorn_queue.append(p)
			n += 1
	# Lost Pages (plan indices 1-5 -> page_index 0-4). R1 QA: +0.5 m so no page bottom clips into its floor.
	for pg in data["pages"]:
		var idx := int(pg["index"])
		var pos := v3(pg["pos"])
		inst(O + "LostPage.tscn", pos - Vector3(0, 0.6, 0), g, {"world_id": "W3", "page_index": idx - 1})
	print("[W3] acorns queued=%d" % n)
	_place_acorns.call_deferred(g)


var _acorn_queue: Array[Vector3] = []


## R1 QA major (16 acorns buried or lifted by ObjSvc on every load): acorns are spawned two physics frames after the
## level is built, each one snapped by ray and overlap tests against world collision to a 0.6 m hover, so ObjSvc
## never has to unbury one.
func _place_acorns(g: Node3D) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var sph := SphereShape3D.new()
	sph.radius = 0.32
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sph
	q.collision_mask = 1 | 4
	var ex: Array[RID] = []
	for id in enemies:
		var en: Variant = enemies[id]
		# Finishing pass (W3 QA r1c major): a fort phase restart frees the squad before this runs; testing `is` on a
		# freed instance raised a SCRIPT ERROR here and no loose acorn was placed (0 of 186). Validity first.
		if not is_instance_valid(en):
			continue
		if en is CollisionObject3D:
			ex.append((en as CollisionObject3D).get_rid())
	q.exclude = ex
	var fixed := 0
	for p0 in _acorn_queue:
		var p := p0
		q.transform = Transform3D(Basis(), p)
		var inside := not space.intersect_shape(q, 1).is_empty()
		var rq := PhysicsRayQueryParameters3D.create(p, p - Vector3(0, 0.62, 0), 1 | 4, ex)
		var near_floor := space.intersect_ray(rq)
		if inside or not near_floor.is_empty():
			var top := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.5, 0), p - Vector3(0, 1.5, 0), 1 | 4, ex)
			var hit := space.intersect_ray(top)
			if not hit.is_empty():
				p.y = (hit["position"] as Vector3).y + 0.62
			for k in 8:
				q.transform = Transform3D(Basis(), p)
				if space.intersect_shape(q, 1).is_empty():
					break
				p.y += 0.4
			if p != p0:
				fixed += 1
		inst(O + "Acorn.tscn", p, g)
	print("[W3] acorns placed=%d (snapped %d)" % [_acorn_queue.size(), fixed])
	_acorn_queue.clear()


func _build_checkpoints() -> void:
	var g := group_node("Checkpoints")
	# R1 visual major: the bookmark stood between the camera and Mak at respawns. Each bookmark now stands 1.4 m to the
	# side and 0.8 m behind the respawn spot (which stays at the data position), and faces along the route.
	var slide_yaw := 0.0
	if _slide_c.size() > 3:
		var sd := _slide_c[3] - _slide_c[0]
		slide_yaw = atan2(-sd.x, -sd.z)
	var yaws := {"CP9_summit": slide_yaw, "CP11_fort_yard": deg_to_rad(-90.0), "CP6_fort_gate": deg_to_rad(-90.0),
		"CP1_woods_fork": deg_to_rad(15.0), "CP4_tier_A": deg_to_rad(-90.0), "CP10_islet": deg_to_rad(-70.0)}
	var off := Vector3(-1.4, 0, -0.8)
	for c in data["checkpoints"]:
		var p := v3(c["pos"])
		var yaw: float = float(yaws.get(String(c["id"]), deg_to_rad(float(c.get("rot_y", 0.0)))))
		var bpos := p - Basis(Vector3.UP, yaw) * off
		bpos.y = maxf(p.y, h_at(bpos.x, bpos.z))
		var cp := inst(O + "Checkpoint.tscn", bpos, g, {"world_id": "W3", "respawn_offset": off})
		if cp:
			cp.name = String(c["id"])
			cp.rotation.y = yaw


# ================================================================ props scatter

func _in_poly(p: Vector2, poly: Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var a := Vector2(float(poly[i][0]), float(poly[i][1]))
		var b := Vector2(float(poly[j][0]), float(poly[j][1]))
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside


func _path_near(x: float, z: float, margin: float) -> bool:
	for p in data["splines"]["paths"]:
		var pts: Array = p["points"]
		var w := float(p["width"]) * 0.5 + margin
		for i in pts.size() - 1:
			var a := Vector2(float(pts[i][0]), float(pts[i][2]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][2]))
			var ab := b - a
			var t := clampf((Vector2(x, z) - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			if (a + ab * t).distance_to(Vector2(x, z)) < w:
				return true
	return false


func _blocked(x: float, z: float) -> bool:
	if Vector2(x + 48, z + 1).length() < 9.5:   # hidden clearing
		return true
	if Vector2(x - 20, z - 38).length() < 9.0:   # gumdrop ring
		return true
	if x > 36 and x < 56 and z > 35 and z < 51:  # fort
		return true
	if x > -13 and x < 10 and z > -36 and z < -15:  # knoll yard
		return true
	if h_at(x, z) < 0.9:   # river bank / water
		return true
	if Vector2(x - 42, z + 36).length() < 20.0:   # peak base
		return true
	# Slide corridor.
	for i in range(0, _slide_c.size(), 3):
		if Vector2(_slide_c[i].x - x, _slide_c[i].z - z).length() < 3.5:
			return true
	return false


func _build_props() -> void:
	var g := group_node("Props")
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var trees := 0
	for zone in data["props_zones"]:
		if String(zone.get("type", "")) != "scatter":
			continue
		var poly: Array = zone["polygon"]
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for q in poly:
			mn = Vector2(minf(mn.x, float(q[0])), minf(mn.y, float(q[1])))
			mx = Vector2(maxf(mx.x, float(q[0])), maxf(mx.y, float(q[1])))
		var area := (mx.x - mn.x) * (mx.y - mn.y)
		var items: Dictionary = zone["items"]
		for item in items:
			var dens := float(items[item])
			var cnt := int(area * dens * (0.55 if item in ["lollipop_tree"] else 0.35))
			if item in ["candy_corn_tuft", "icing_flower"]:
				continue   # ground cover is the FxScatter pass below
			for i in cnt:
				var x := rng.randf_range(mn.x, mx.x)
				var z := rng.randf_range(mn.y, mx.y)
				if not _in_poly(Vector2(x, z), poly) or _blocked(x, z) or _path_near(x, z, 1.5):
					continue
				var y := h_at(x, z)
				match item:
					"lollipop_tree":
						var s := rng.randf_range(1.0, 1.75)
						var path: String = P_LOLLIS[rng.randi() % 3]
						if rng.randf() < 0.05:
							path = P_LOLLI_GRUMPY
						# Finishing pass (D034 B4, lollipop clutter): plant every other tree (the RNG draws are kept so
						# every later prop keeps its tested spot); the grumpy tree always stays.
						if i % 2 == 1 and path != P_LOLLI_GRUMPY:
							rng.randf_range(2.8, 3.8)
							rng.randf_range(-40, 40)
							continue
						# R1 visual minor (no motion): each lollipop sways 2 degrees at about 0.3 Hz.
						var holder := Node3D.new()
						holder.set_script(load("res://scripts/worlds/w3_bobber.gd"))
						holder.set("sway_deg", 2.0)
						holder.set("sway_period", rng.randf_range(2.8, 3.8))
						g.add_child(holder)
						holder.position = Vector3(x, y - 0.05, z)
						glb(path, Vector3.ZERO, rng.randf_range(-40, 40) + (180.0 if z < 30 else 0.0), s, holder)
						var tb := body("Trunk", Vector3(x, y, z), g)
						cyl_shape(tb, 0.16 * s, 2.6 * s, Vector3(0, 1.3 * s, 0))
						trees += 1
					"gumdrop_bush":
						var s2 := rng.randf_range(0.35, 0.7)
						glb(P_GUMDROPS[rng.randi() % 4], Vector3(x, y - 0.05, z), rng.randf() * 360.0, s2, g)
					"peppermint_rock", "chocolate_chip_boulder", "rock_candy_cluster":
						glb(P_ROCK, Vector3(x, y - 0.2, z), rng.randf() * 360.0, rng.randf_range(0.3, 0.6), g)
	# Fences: candy-cane fences along the glade-to-bridge path and the south edge.
	var fence_runs := [[Vector3(-3.4, 0, 47), Vector3(-5.4, 0, 22)], [Vector3(3.2, 0, 36.5), Vector3(-2.0, 0, 21.5)], [Vector3(-58, 0, 54.2), Vector3(58, 0, 54.2)]]
	for fr in fence_runs:
		var a: Vector3 = fr[0]
		var b: Vector3 = fr[1]
		var ln := Vector2(b.x - a.x, b.z - a.z).length()
		var cnt := int(ln / 2.4)
		var yaw := rad_to_deg(atan2(b.x - a.x, b.z - a.z)) + 90.0
		for i in cnt:
			var p := a.lerp(b, (i + 0.5) / cnt)
			if absf(p.x) < 3.0 and absf(p.z - 40.0) < 3.0:
				continue
			# Finishing pass (D034 B4, cane fences): the south-edge run spanned the whole 116 m rim; it now only frames
			# the arrival lawn (|x| < 16), and the path runs skip every third segment so they read as a garden border.
			if p.z > 54.0 and absf(p.x) > 16.0:
				continue
			# Owner fix 2026-10-19 (world exits): the two middle pieces give way to the exit gate (WorldExits, W3).
			if p.z > 54.0 and absf(p.x) < 2.5:
				continue
			if p.z <= 54.0 and i % 3 == 2:
				continue
			p.y = h_at(p.x, p.z) - 0.05
			glb(P_FENCE, p, yaw, 1.0, g)
	# Ground cover (grass tufts and flowers) with the VFX scatter tool on the terrain.
	var terr := get_node_or_null("../Terrain/Mesh") as MeshInstance3D
	if terr and ResourceLoader.exists("res://scripts/fx/fx_scatter.gd"):
		var FxS: Script = load("res://scripts/fx/fx_scatter.gd")
		# Candy-corn tufts in mint and lemon, icing flowers in three colours.
		var specs := [["mesh_grass_tuft", 4200, 7, FxS.call("grass_material", Color(0.42, 0.72, 0.5), Color(0.86, 0.98, 0.78))],
			["mesh_flower_pink", 900, 8, FxS.call("flower_material")], ["mesh_flower_white", 800, 9, FxS.call("flower_material")],
			["mesh_flower_yellow", 600, 10, FxS.call("flower_material")]]
		for sp in specs:
			var mesh_path := "res://assets/shaders/materials/%s.tres" % sp[0]
			if not ResourceLoader.exists(mesh_path):
				continue
			var sc := MultiMeshInstance3D.new()
			sc.set_script(FxS)
			sc.name = "Scatter_%s" % sp[0]
			sc.set("auto_build", false)
			sc.set("source_mesh", load(mesh_path))
			sc.set("material", sp[3])
			sc.set("count", sp[1])
			sc.set("scatter_seed", sp[2])
			sc.set("max_slope_degrees", 22.0)
			sc.set("min_height", 1.1)
			sc.set("avoid_channels", Vector4(1, 1, 1, 0))
			g.add_child(sc)
			sc.set("target_path", sc.get_path_to(terr))
			sc.call("build")
			sc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("[W3] props: lollipop trees=%d" % trees)


# ================================================================ ambient life

func _build_ambient() -> void:
	var g := group_node("Ambient")
	for p in [Vector3(-2, 2.5, 46), Vector3(8, 2.5, 34), Vector3(-30, 4.5, 30), Vector3(-44, 5, 18), Vector3(22, 3, 46), Vector3(-20, 3.5, 44)]:
		add_fx("Butterflies", p, g)
	for p in [Vector3(-40, 5, 34), Vector3(-26, 4, 42), Vector3(-52, 5, 10)]:
		add_fx("FallingLeaves", p, g, Color(1.0, 0.6, 0.8))
	# Candyfloss clouds below the page edge.
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(1.0, 0.82, 0.9)
	cloud_mat.roughness = 1.0
	cloud_mat.emission_enabled = true
	cloud_mat.emission = Color(1.0, 0.75, 0.86)
	cloud_mat.emission_energy_multiplier = 0.35
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 46:
		var a := TAU * float(i) / 46.0
		var r := rng.randf_range(95.0, 140.0)
		var c := Node3D.new()
		c.set_script(load("res://scripts/worlds/w3_bobber.gd"))
		c.set("bob_amp", rng.randf_range(0.3, 0.9))
		c.set("bob_period", rng.randf_range(5.0, 9.0))
		g.add_child(c)
		c.position = Vector3(cos(a) * r, rng.randf_range(-24.0, -14.0), sin(a) * r * 0.9)
		for j in 4:
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var rr := rng.randf_range(5.0, 10.0)
			sm.radius = rr
			sm.height = rr * 1.4
			sm.radial_segments = 16
			sm.rings = 8
			s.mesh = sm
			s.material_override = cloud_mat
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			s.position = Vector3(rng.randf_range(-8, 8), rng.randf_range(-1, 2), rng.randf_range(-8, 8))
			c.add_child(s)


func _relight_crumbs() -> void:
	var pts := PackedVector3Array()
	for p in data["splines"]["paths"]:
		if String(p["id"]) == "path_breadcrumb":
			for q in p["points"]:
				pts.append(v3(q))
	for q in data["maze"]["scent_nodes"]:
		pts.append(v3(q))
	pts.append(Vector3(-48, 4, 7))
	var dense := Geo.resample(Geo.dense(pts, 6), 1.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.18
	sm.radial_segments = 8
	sm.rings = 4
	mm.mesh = sm
	mm.instance_count = dense.size()
	for i in dense.size():
		var c := dense[i]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, i * 1.7), Vector3(c.x, h_at(c.x, c.z) + 0.1, c.z)))
	var mi := MultiMeshInstance3D.new()
	mi.name = "RelitCrumbs"
	mi.multimesh = mm
	mi.material_override = toon(Color(1.0, 0.82, 0.45), "", 0.35, false, 0.5, Color(1.0, 0.7, 0.3), 1.8)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group_node("WorldState").add_child(mi)
	print("[W3] world_state: crumbs relit (%d)" % dense.size())


# ================================================================ entrance funnel (R1 fun major)

## A first-time player who held forward from the gate walked into the river; the Pretzel Bridge sits to the left.
## A candy-cane rail now follows the south bank from the bridge mouth eastwards, a pointing sign stands where the path
## meets the bank, and three acorns lead onto the bridge.
func _build_entrance_funnel() -> void:
	var g := group_node("EntranceFunnel")
	var rail_mat := toon(Color.WHITE, "candy_stripes", 0.5, false, 0.35, Color.BLACK, 0.0, 0.5, 0.8)
	var post_mat := toon(Color("#FF5C7A"), "", 0.35, false, 0.35)
	var pts: Array[Vector3] = []
	var x := -3.4
	while x <= 12.5:
		var z := 30.0
		while z > 5.0 and h_at(x, z) >= 1.05:
			z -= 0.25
		pts.append(Vector3(x, h_at(x, z + 0.7), z + 0.7))
		x += 1.6
	for i in pts.size():
		var a := pts[i]
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.09
		pm.bottom_radius = 0.11
		pm.height = 1.15
		pm.radial_segments = 10
		post.mesh = pm
		post.material_override = post_mat
		g.add_child(post)
		post.position = a + Vector3(0, 0.55, 0)
		var knob := sphere_mesh(0.14, Color("#FFF7EE"))
		g.add_child(knob)
		knob.position = a + Vector3(0, 1.17, 0)
		if i == pts.size() - 1:
			break
		var b := pts[i + 1]
		var mid := (a + b) * 0.5
		var ln := Vector2(b.x - a.x, b.z - a.z).length()
		var yaw := atan2(b.x - a.x, b.z - a.z)
		var rb := StaticBody3D.new()
		rb.collision_layer = 1
		rb.collision_mask = 0
		g.add_child(rb)
		rb.position = mid
		rb.rotation.y = yaw
		box_shape(rb, Vector3(0.25, 1.1, ln), Vector3(0, 0.55, 0))
		for hy in [0.55, 0.95]:
			var rail := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.06
			cm.bottom_radius = 0.06
			cm.height = ln
			cm.radial_segments = 8
			rail.mesh = cm
			rail.material_override = rail_mat
			rb.add_child(rail)
			rail.position = Vector3(0, hy + (b.y - a.y) * 0.0, 0)
			rail.rotation_degrees = Vector3(90, 0, 0)
	var sp := Vector3(-2.6, 0, 16.2)
	sp.y = h_at(sp.x, sp.z)
	var sgn := inst(O + "SignPost.tscn", sp, g, {"board_text": "<- Pretzel Bridge", "lines": PackedStringArray(["Hot chocolate ahead. HOT.", "Cross by the Pretzel Bridge, to your left."])})
	if sgn:
		sgn.rotation_degrees.y = 25.0
	for q in [Vector3(-3.6, 0, 15.6), Vector3(-4.8, 0, 14.2), Vector3(-5.8, 0, 12.6)]:
		_acorn_queue.append(Vector3(q.x, h_at(q.x, q.z) + 0.6, q.z))


# ================================================================ horizon (R1 visual: hide the slab edges, fill the sky)

## A ring of chunky gingerbread hills with thick icing caps just outside the play bounds (north, west and the east
## behind the cake; the south stays open for StoryCam_A), plus slow floating set pieces in the sky.
func _build_horizon() -> void:
	var g := group_node("Horizon")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var spots: Array = []
	for i in 9:   # north
		spots.append(Vector3(-72.0 + i * 18.0 + rng.randf_range(-4, 4), 0, -70.0 - rng.randf_range(0, 10)))
	for i in 6:   # west
		spots.append(Vector3(-76.0 - rng.randf_range(0, 10), 0, -48.0 + i * 17.0 + rng.randf_range(-3, 3)))
	for i in 3:   # east, behind the cake
		spots.append(Vector3(78.0 + rng.randf_range(0, 8), 0, -50.0 + i * 16.0))
	for i in 4:   # far east, beyond the floating balcony (behind StoryCam_C)
		spots.append(Vector3(96.0 + rng.randf_range(0, 10), 0, 2.0 + i * 18.0))
	for i in 8:   # south, behind StoryCam_A (seen from B, D and the balcony)
		spots.append(Vector3(-70.0 + i * 20.0 + rng.randf_range(-4, 4), 0, 78.0 + rng.randf_range(0, 10)))
	# Key art 07_w3_grove: chocolate-brown hills under thick white icing caps.
	var sponges := [Color("#8A4E26"), Color("#6B3A24"), Color("#9A5A2C"), Color("#7A4128")]
	var icings := [Color("#FFFFFF"), Color("#FFF7EE"), Color("#FFFFFF"), Color("#FFE4EE")]
	var mat := vc_mat(0.75, 0.25)
	for k in spots.size():
		var at: Vector3 = spots[k]
		var R := rng.randf_range(10.0, 16.0)
		var h := rng.randf_range(32.0, 46.0)
		var sp: Color = sponges[k % sponges.size()]
		var ic: Color = icings[(k * 3) % icings.size()]
		var prof := [Vector2(R * 1.05, 0.0), Vector2(R, h * 0.35), Vector2(R * 0.9, h * 0.7), Vector2(R * 0.88, h * 0.74),
			Vector2(R * 0.72, h * 0.84), Vector2(R * 0.44, h * 0.94), Vector2(R * 0.12, h * 0.995), Vector2(0.0, h)]
		var cols := [sp.darkened(0.3), sp, sp.lightened(0.06), ic.darkened(0.03), ic, ic, ic, ic]
		var mi := mesh_node(Geo.lathe(prof, 40, 1.0, rng.randf_range(0.8, 1.15), cols, false, false, 0.05, 6), mat, Vector3(at.x, -24.0, at.z), g, "Hill%d" % k)
		mi.rotation.y = rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Icing drips under the cap.
		for d in 7:
			var a := TAU * float(d) / 7.0 + rng.randf() * 0.4
			var dr := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = rng.randf_range(0.9, 1.6)
			cm.height = rng.randf_range(4.0, 8.0)
			cm.radial_segments = 10
			cm.rings = 4
			dr.mesh = cm
			dr.material_override = toon(ic, "", 0.35, false, 0.4)
			dr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.add_child(dr)
			dr.position = Vector3(cos(a) * R * 0.88, h * 0.7, sin(a) * R * 0.88)
	# Floating set pieces, slowly bobbing and turning (painterly sky depth).
	var pieces := [[P_CUPCAKE, Vector3(-40, 44, -95), 3.2], [P_LOLLIS[0], Vector3(55, 48, -92), 4.0], [P_GUMDROPS[0], Vector3(-95, 38, -20), 7.0],
		[P_GUMDROPS[1], Vector3(30, 56, -110), 8.0], [P_LOLLIS[1], Vector3(-88, 52, 30), 3.6]]
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(1.0, 0.9, 0.95)
	cloud_mat.roughness = 1.0
	cloud_mat.emission_enabled = true
	cloud_mat.emission = Color(1.0, 0.85, 0.92)
	cloud_mat.emission_energy_multiplier = 0.4
	for pc in pieces:
		var holder := Node3D.new()
		holder.set_script(load("res://scripts/worlds/w3_bobber.gd"))
		holder.set("bob_amp", 1.6)
		holder.set("bob_period", rng.randf_range(7.0, 11.0))
		holder.set("spin_deg_per_s", Vector3(0, rng.randf_range(2.0, 4.0), 0))
		g.add_child(holder)
		holder.position = pc[1]
		if ResourceLoader.exists(String(pc[0])):
			var n := glb(String(pc[0]), Vector3.ZERO, 0.0, float(pc[2]), holder, false)
			if n:
				n.position = Vector3(0, -2.0, 0)
		# Candyfloss cloud cradle under each piece.
		for j in 5:
			var cs := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var rr := rng.randf_range(3.5, 6.5)
			sm.radius = rr
			sm.height = rr * 1.2
			sm.radial_segments = 16
			sm.rings = 8
			cs.mesh = sm
			cs.material_override = cloud_mat
			cs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(cs)
			cs.position = Vector3(rng.randf_range(-6, 6), rng.randf_range(-4.0, -2.0), rng.randf_range(-6, 6))


# ================================================================ cauldron blobs (hazard)

func _blob_step(delta: float, pp: Vector3) -> void:
	if _blob_busy:
		return
	var origin := Vector3(3, 11.4, -29)
	if pp.distance_to(origin) > 22.0:
		return
	_blob_t -= delta
	if _blob_t > 0.0:
		return
	_blob_t = 4.5
	_blob_busy = true
	var rng_a := fposmod(Time.get_ticks_msec() * 0.0013, TAU)
	var target := Vector3(origin.x + cos(rng_a) * 4.5, 8.0, origin.z + sin(rng_a) * 4.5)
	# Aim near the player if they are in the yard.
	if pp.y > 7.5 and pp.y < 12.0 and Vector2(pp.x - origin.x, pp.z - origin.z).length() < 7.0:
		target = Vector3(pp.x, 8.0, pp.z)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.15
	ring.mesh = tm
	ring.material_override = toon(Color(1.0, 0.25, 0.2), "", 0.35, false, 0.5, Color(1.0, 0.2, 0.1), 2.0)
	add_child(ring)
	ring.global_position = target + Vector3(0, 0.08, 0)
	var blob := sphere_mesh(0.45, Color(0.45, 1.0, 0.55), 0.2)
	blob.material_override = toon(Color(0.5, 1.0, 0.55), "", 0.35, false, 0.2, Color(0.3, 1.0, 0.4), 1.5)
	add_child(blob)
	blob.global_position = origin
	ObjSvc.sfx("pop", origin)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		var p := origin.lerp(target, t)
		p.y += sin(t * PI) * 4.0
		blob.global_position = p, 0.0, 1.0, 1.0)
	tw.tween_callback(func() -> void:
		ObjSvc.burst(self, target + Vector3(0, 0.3, 0), Color(0.5, 1.0, 0.55), 20, 4.0, 0.16, -9.0, 0.6)
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		if pl and pl.global_position.distance_to(target) < 1.3 and pl.has_method("take_damage"):
			pl.call("take_damage", 1, target, -1.0)
		blob.queue_free()
		ring.queue_free()
		_blob_busy = false)


# ================================================================ dev markers

## Extra spawn markers for tests: one next to each truffle and page, plus route checkpoints.
func _build_dev_markers() -> void:
	var sp := get_node_or_null("../Spawns") as Node3D
	if sp == null:
		return
	var sy := 0.0
	if _slide_c.size() > 3:
		var sd := _slide_c[3] - _slide_c[0]
		sy = rad_to_deg(atan2(-sd.x, -sd.z))
	var extra := {
		"T_W3-1": [Vector3(-48, 4.1, 2.5), 180.0], "T_W3-3": [Vector3(16, 1.6, 21.0), 0.0], "Balcony": [Vector3(58.5, 2.1, 30.0), -90.0], "MazeIn": [Vector3(-35.5, 4.1, 27.0), 0.0], "T_W3-6": [Vector3(-6.0, 19.2, -25.0), 0.0],
		"T_W3-6b": [Vector3(-6.0, 11.5, -22.9), 0.0], "T_W3-7": [Vector3(20, 24.5, 39.2), 0.0], "T_W3-8": [Vector3(-44, 5.1, -38.0), 0.0],
		"T_W3-8b": [Vector3(4.0, 11.4, -29.0), 0.0], "T_W3-2": [Vector3(42, 2.1, 43), -90.0], "T_W3-4": [_slide_c[2] + Vector3(0, 0.3, 0), 180.0],
		"Summit": [Vector3(38.5, 28.2, -41.0), sy], "Page1": [Vector3(-51, 16.2, -50.5), 0.0], "Page2": [Vector3(-2.9, 1.0, 2.0), 0.0],
		"Page4": [Vector3(53.7, 9.3, 37.7), 0.0], "Page5": [Vector3(71.0, 1.6, BALCONY_Z), 90.0], "Pool": [Vector3(-38, 1.0, -33), 90.0],
		"TierA": [Vector3(34, 12.1, -27.5), 0.0], "Islet": [Vector3(21, 1.7, 10.5), 0.0],
	}
	for k in extra:
		var m := Marker3D.new()
		m.name = k
		sp.add_child(m)
		m.global_position = extra[k][0]
		m.rotation_degrees.y = extra[k][1]


# ================================================================ test bot plans (dev only, --w3-bot=<plan>)

func _gum(i: int) -> Vector3:
	var k := 0
	for p in data["platforms"]:
		if String(p["kind"]) == "bouncy_gumdrop":
			k += 1
			if k == i:
				return Vector3(float(p["pos"][0]), float(p["top_y"]), float(p["pos"][2]))
	return Vector3.ZERO


func _bot_plans() -> Dictionary:
	var plans := {}
	var w37: Array = [
		{"do": "teleport", "at": Vector3(9.4, 2.05, 38.0), "yaw": -90.0},
		{"do": "wait", "frames": 10},
		{"do": "goto", "at": Vector3(11.0, 2.0, 38.0), "tol": 0.25},
		{"do": "press", "action": "jump", "frames": 16, "stick": Vector2(1, 0)},
	]
	for i in range(1, 8):
		var nxt := _gum(i + 1) if i < 7 else Vector3(20, 24.4, 38)
		w37.append({"do": "hop", "at": _gum(i), "next": nxt, "slam": i >= 5})
	w37.append({"do": "hop", "at": Vector3(20, 24.4, 38), "next": Vector3(20, 24.4, 38)})
	w37.append({"do": "until_truffle", "id": "W3-7", "max_s": 6.0})
	plans["w37"] = w37
	plans["w33_old"] = [
		{"do": "teleport", "at": Vector3(16, 1.5, 21.5), "yaw": 0.0},
		{"do": "wait", "frames": 10},
		{"do": "goto", "at": Vector3(16, 1.4, 19.3), "tol": 0.3, "stop": true},
		{"do": "wait_node", "path": "Lagoon/lane_S", "xmin": 13.2, "xmax": 14.4, "z": 16.0},
		{"do": "press", "action": "jump", "frames": 10, "stick": Vector2(0, 1)},
		{"do": "hop", "node": true, "top_off": 0.35},
		{"do": "ride", "x_until": 19.6},
		{"do": "press", "action": "jump", "frames": 16, "stick": Vector2(0.2, 1)},
		{"do": "hop", "at": Vector3(21, 1.6, 11.0)},
		{"do": "goto", "at": Vector3(21, 1.6, 9.2), "tol": 1.0},
		{"do": "press", "action": "jump", "frames": 10, "stick": Vector2(0, 0.6)},
		{"do": "until_truffle", "id": "W3-3", "max_s": 4.0},
	]
	plans["w31"] = [
		{"do": "teleport", "at": Vector3(-12, 2.1, 40.5), "yaw": 69.4},
		{"do": "wait", "frames": 10},
		{"do": "goto", "at": Vector3(-14, 2, 40), "tol": 0.6},
		{"do": "goto", "at": Vector3(-24, 2.6, 36), "tol": 0.6},
		{"do": "goto", "at": Vector3(-32, 3.4, 28), "tol": 0.6},
		{"do": "goto", "at": Vector3(-36, 4.0, 25.5), "tol": 0.6, "stop": true},
		{"do": "sniff", "frames": 50},
		{"do": "follow_scent", "until": Vector3(-48, 4.0, 7.5)},
		{"do": "goto", "at": Vector3(-48, 4.0, 2.2), "tol": 0.5, "stop": true},
		{"do": "press", "action": "jump", "frames": 14, "stick": Vector2(0, 0.7)},
		{"do": "until_truffle", "id": "W3-1", "max_s": 4.0},
	]
	# R3.6 finale (fix round 1): maze, gate, then the stalker as the ladder into the crows' nest.
	plans["w31nest"] = [
		{"do": "teleport", "at": Vector3(-36, 4.1, 25.5), "yaw": 0.0},
		{"do": "wait", "frames": 10},
		{"do": "sniff", "frames": 50},
		{"do": "follow_scent", "until": Vector3(-48, 4.0, 7.5)},
		{"do": "goto", "at": Vector3(-48, 4.0, 1.4), "tol": 0.5, "stop": true},
		{"do": "mark", "text": "in the clearing under the nest"},
		{"do": "brute_bounce", "id": "brute_clearing", "to": Vector3(-48, 11.0, -1), "max_s": 45.0},
		# Completion pass: the bounce now clears the rim and lands on its edge; walk in to the truffle (it was left
		# standing on the edge and slid off).
		{"do": "goto", "at": Vector3(-48, 11.0, -1), "tol": 0.35, "stop": true, "max_s": 4.0},
		{"do": "until_truffle", "id": "W3-1", "max_s": 4.0},
	]
	# R1 feel blockers re-check: climb candy_pole_D from the lift side, hold the stick toward tier D (the naive input),
	# pole jump; the auto-orient must land Mak on tier D's bare icing, clear of the candles.
	plans["w3pole"] = [
		{"do": "teleport", "at": Vector3(48.6, 20.1, -42.0), "yaw": 90.0},
		{"do": "wait", "frames": 20},
		{"do": "press", "action": "jump", "frames": 10, "stick": Vector2(-1, 0)},
		{"do": "steer", "stick": Vector2(-1, 0), "frames": 40},
		{"do": "mark", "text": "on the pole?"},
		{"do": "steer", "stick": Vector2(-0.7, 0.7), "frames": 120},
		{"do": "steer", "stick": Vector2(0, 1), "frames": 90},
		{"do": "steer", "stick": Vector2(-1, 0), "frames": 60},
		{"do": "mark", "text": "top of the pole, naive stick toward tier D"},
		{"do": "press", "action": "jump", "frames": 10, "stick": Vector2(-1, 0)},
		{"do": "until_grounded", "stick": Vector2(-1, 0)},
		{"do": "wait", "frames": 30},
		{"do": "mark", "text": "landed"},
	]
	plans["w38"] = [
		{"do": "teleport", "at": Vector3(3.0, 8.05, -23.4), "yaw": 0.0},
		{"do": "wait", "frames": 10},
		{"do": "goto", "at": Vector3(3.0, 8.0, -25.4), "tol": 0.25},
		{"do": "press", "action": "jump", "frames": 10, "stick": Vector2(0, 0.6)},
		{"do": "hop", "at": Vector3(3.0, 9.0, -26.65)},
		{"do": "press", "action": "jump", "frames": 14, "stick": Vector2(0, 0.6)},
		{"do": "hop", "at": Vector3(3.0, 11.0, -29.0), "slam": true, "slam_h": 0.25, "aim_h": 0.4, "end_on_slam": true},
		{"do": "mark", "text": "slammed lid: sprint"},
		{"do": "goto", "at": Vector3(4.5, 8.0, -36.0), "tol": 1.0},
		{"do": "goto", "at": Vector3(-14.0, 8.0, -36.0), "tol": 1.0},
		{"do": "goto", "at": Vector3(-17.0, 8.0, -32.4), "tol": 1.0},
		{"do": "goto", "at": Vector3(-31.0, 2.6, -33.7), "tol": 1.2},
		{"do": "goto", "at": Vector3(-38.5, 0.0, -33.5), "tol": 0.6, "stop": true},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(-1, 0)},
		{"do": "hop", "at": Vector3(-41.5, 1.0, -33.5)},
		# Completion pass: the stick left over from the landing correction pointed back, so this jump was a side flip,
		# and a side flip does not chain into a double jump. Jump toward rock 2.
		{"do": "press", "action": "jump", "frames": 14, "stick": Vector2(-0.62, 0.79)},
		# Completion pass: since the movement retune (single jump peak 1.81 m, ledge grab 0.78-1.25 m, falling only)
		# rock 2 (top 2.8) to the grotto floor (5.0) needs the chained double jump a player uses: land on rock 2 already
		# moving toward the grotto and jump again inside the 0.25 s chain window (double jump peak 2.74 m).
		{"do": "hop", "at": Vector3(-43.0, 2.8, -35.4), "next": Vector3(-44.0, 5.0, -38.7), "preaim": 0.3},
		{"do": "press", "action": "jump", "frames": 16, "stick": Vector2(-0.29, 0.96)},
		{"do": "hop", "at": Vector3(-44.0, 5.0, -38.7)},
		{"do": "goto", "at": Vector3(-44.0, 5.0, -39.4), "tol": 0.35, "stop": true},
		{"do": "sniff", "frames": 50},
		{"do": "steer", "stick": Vector2(0, 0.3), "frames": 4},
		{"do": "press", "action": "attack", "frames": 6},
		{"do": "until_truffle", "id": "W3-8", "max_s": 3.0},
	]
	# Negative test: the same sprint and hops with the falls still running (no lid slam).
	var neg: Array = [{"do": "teleport", "at": Vector3(4.5, 8.05, -34.0), "yaw": 180.0}, {"do": "wait", "frames": 20}]
	var w38: Array = plans["w38"]
	for k in range(8, 19):
		neg.append(w38[k])
	neg.append({"do": "mark", "text": "UNEXPECTED: reached the grotto with the falls running"})
	plans["w38neg"] = neg
	plans["w34"] = [
		{"do": "teleport", "at": _slide_c[0] + Vector3(0, 0.25, 0) - (_slide_c[3] - _slide_c[0]).normalized() * 2.6, "yaw": rad_to_deg(atan2(-(_slide_c[3] - _slide_c[0]).x, -(_slide_c[3] - _slide_c[0]).z))},
		{"do": "wait", "frames": 50},
		{"do": "goto", "at": _slide_c[0] + Vector3(0, 0.1, 0), "tol": 0.6},
		{"do": "follow_slide", "ahead": 5, "boost": true},
		{"do": "wait", "frames": 100},
		{"do": "goto", "at": Vector3(30.5, 2.3, 34.5), "tol": 0.4, "stop": true},
		{"do": "until_truffle", "id": "W3-4", "max_s": 4.0},
	]
	# R3.2 pass test 2: a clean run with no boosts loses the joust (crumb_escape, page turn to CP9).
	plans["w34clean"] = [
		{"do": "teleport", "at": _slide_c[0] + Vector3(0, 0.25, 0) - (_slide_c[3] - _slide_c[0]).normalized() * 2.6, "yaw": rad_to_deg(atan2(-(_slide_c[3] - _slide_c[0]).x, -(_slide_c[3] - _slide_c[0]).z))},
		{"do": "wait", "frames": 50},
		{"do": "goto", "at": _slide_c[0] + Vector3(0, 0.1, 0), "tol": 0.6},
		{"do": "follow_slide", "ahead": 5, "lat": 0.0, "end_on_escape": true},
		{"do": "until_y_above", "y": 27.5, "max_s": 2.0},
	]
	var w35: Array = []
	for pg in get_tree().get_nodes_in_group("lost_page"):
		pass
	for n in find_children("*", "LostPage", true, false):
		w35.append({"do": "teleport", "at": (n as Node3D).global_position + Vector3(0, 0.1, 0), "yaw": 0.0})
		w35.append({"do": "wait", "frames": 30})
	w35.append({"do": "teleport", "at": Vector3(6.0, 2.1, 47.0), "yaw": 0.0})
	w35.append({"do": "wait", "frames": 20})
	w35.append({"do": "goto", "at": Vector3(6.0, 2.0, 45.2), "tol": 0.3, "stop": true})
	w35.append({"do": "press", "action": "jump", "frames": 14})
	w35.append({"do": "until_truffle", "id": "W3-5", "max_s": 4.0})
	plans["w35"] = w35
	var w100: Array = [{"do": "collect_acorns", "n": 100}]
	w100.append({"do": "wait", "frames": 70})
	w100.append({"do": "press", "action": "jump", "frames": 14})
	w100.append({"do": "until_truffle", "id": "W3-100", "max_s": 4.0})
	plans["w3100"] = w100
	plans["w36"] = [
		{"do": "teleport", "at": Vector3(-6.0, 8.05, -18.4), "yaw": 0.0},
		{"do": "wait", "frames": 10},
		{"do": "goto", "at": Vector3(-6.0, 8.0, -19.6), "tol": 0.25},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(0, 1)},
		{"do": "hop", "at": Vector3(-6.0, 9.25, -20.6)},
		{"do": "press", "action": "jump", "frames": 14, "stick": Vector2(0, 1)},
		{"do": "hop", "at": Vector3(-6.0, 11.2, -23.0)},
		{"do": "until_grounded", "stick": Vector2(0, 1.0)},
		{"do": "goto", "at": Vector3(-6.0, 19.06, -29.6), "tol": 0.3, "stop": true},
		{"do": "wait", "frames": 6},
		{"do": "press", "action": "jump", "frames": 16, "stick": Vector2(1, 0)},
		{"do": "hop", "at": Vector3(-4.0, 20.6, -30.05)},
		{"do": "goto", "at": Vector3(-4.0, 20.6, -30.05), "tol": 0.3, "stop": true},
		{"do": "wait", "frames": 8},
		{"do": "press", "action": "jump", "frames": 14, "stick": Vector2(0, 0)},
		{"do": "hop", "at": Vector3(-4.0, 20.6, -30.05), "slam": true, "slam_h": 0.8, "aim_h": 1.2, "end_on_slam": true},
		{"do": "until_y_above", "y": 99.0, "max_s": 3.0},
		{"do": "until_grounded"},
		{"do": "goto", "at": Vector3(-6.0, 100.0, -28.6), "tol": 0.3, "stop": true},
		{"do": "wait_oven_cold"},
		{"do": "goto", "at": Vector3(-6.0, 100.0, -29.9), "tol": 0.2, "stop": true},
		{"do": "steer", "stick": Vector2(0, -0.25), "frames": 5},
		{"do": "steer", "stick": Vector2(0, 0), "frames": 3},
		{"do": "backflip"},
		{"do": "until_grounded"},
		{"do": "mark", "text": "on the oven top?"},
		{"do": "goto", "at": Vector3(-7.0, 103.4, -32.6), "tol": 0.3, "stop": true},
		{"do": "steer", "stick": Vector2(-0.3, 0.3), "frames": 4},
		{"do": "press", "action": "attack", "frames": 6},
		{"do": "wait", "frames": 50},
		{"do": "goto", "at": Vector3(-6.0, 103.4, -30.6), "tol": 0.4},
		{"do": "until_grounded"},
		{"do": "goto", "at": Vector3(-8.6, 100.0, -27.6), "tol": 0.4},
		{"do": "until_truffle", "id": "W3-6", "max_s": 4.0},
	]
	plans["w32"] = [
		{"do": "teleport", "at": Vector3(40.5, 2.05, 43.0), "yaw": -90.0},
		{"do": "wait", "frames": 150},
		{"do": "goto", "at": Vector3(44.3, 2.0, 43.0), "tol": 0.3, "stop": true},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(1, 0)},
		{"do": "hop", "at": Vector3(45.6, 3.0, 43.0)},
		{"do": "wait", "frames": 40},
		{"do": "press", "action": "jump", "frames": 14},
		{"do": "hop", "at": Vector3(45.6, 3.0, 43.0), "slam": true, "slam_h": 0.6, "aim_h": 1.0, "end_on_slam": true},
		{"do": "wait", "frames": 60},
		{"do": "stomp_enemy", "id": "squad_1", "head": 1.35},
		{"do": "stomp_enemy", "id": "squad_2", "head": 1.35},
		{"do": "stomp_enemy", "id": "squad_3", "head": 1.35},
		{"do": "stomp_enemy", "id": "squad_4", "head": 1.35},
		{"do": "stomp_enemy", "id": "sergeant_snap", "head": 1.8, "max_s": 60.0},
		{"do": "goto", "at": Vector3(44.6, 2.0, 43.0), "tol": 0.4, "stop": true},
		{"do": "press", "action": "jump", "frames": 14, "stick": Vector2(1, 0)},
		{"do": "until_truffle", "id": "W3-2", "max_s": 4.0},
	]
	# R2.3 four-phase Sergeant Snap fight (fix round 1). Phase 3's climb is a teleport onto the walkway (the J50-J52
	# sugar-cube climb is covered by its own jump-table checks); everything else is played.
	plans["w32phases"] = [
		{"do": "teleport", "at": Vector3(40.5, 2.05, 43.0), "yaw": -90.0},
		{"do": "wait", "frames": 150},
		{"do": "goto", "at": Vector3(44.3, 2.0, 43.0), "tol": 0.3, "stop": true},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(1, 0)},
		{"do": "hop", "at": Vector3(45.6, 3.0, 43.0)},
		{"do": "wait", "frames": 40},
		{"do": "press", "action": "jump", "frames": 14},
		{"do": "hop", "at": Vector3(45.6, 3.0, 43.0), "slam": true, "slam_h": 0.6, "aim_h": 1.0, "end_on_slam": true},
		{"do": "wait", "frames": 20},
		{"do": "stomp_enemy", "id": "squad_1", "head": 1.35},
		{"do": "stomp_enemy", "id": "squad_2", "head": 1.35},
		{"do": "stomp_enemy", "id": "squad_3", "head": 1.35},
		{"do": "stomp_enemy", "id": "squad_4", "head": 1.35},
		{"do": "fort_wait", "phase": 2, "subs": ["fight"], "max_s": 8.0},
		{"do": "mark", "text": "PHASE 2: Snap in the yard"},
		{"do": "dive_trip", "id": "sergeant_snap", "max_s": 40.0},
		{"do": "stomp_until", "id": "sergeant_snap", "phase": 3, "max_s": 6.0},
		{"do": "fort_wait", "phase": 3, "subs": ["lob"], "max_s": 8.0},
		{"do": "mark", "text": "PHASE 3: Snap lobbing from the walkway; teleport up (climb tested separately)"},
		{"do": "teleport", "at": Vector3(42.0, 5.65, 36.6), "yaw": -90.0},
		{"do": "stomp_until", "id": "sergeant_snap", "phase": 4, "max_s": 20.0},
		{"do": "fort_wait", "phase": 4, "subs": ["to_mark", "tell"], "max_s": 8.0},
		{"do": "mark", "text": "PHASE 4: Snap heads for the drum"},
		{"do": "goto", "at": Vector3(47.9, 2.0, 43.0), "tol": 0.35, "stop": true},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(-1, 0)},
		{"do": "hop", "at": Vector3(46.5, 3.0, 43.0)},
		{"do": "fort_wait", "phase": 4, "subs": ["tell", "roll"], "max_s": 12.0},
		{"do": "press", "action": "jump", "frames": 14},
		{"do": "hop", "at": Vector3(46.5, 3.0, 43.0), "slam": true, "slam_h": 0.6, "aim_h": 1.0, "end_on_slam": true},
		{"do": "fort_wait", "phase": 4, "subs": ["flipped"], "max_s": 2.0},
		{"do": "stomp_until", "id": "sergeant_snap", "phase": 99, "max_s": 6.0},
		# Finishing pass: stomp_until left the stick held toward the defeated Snap, who is launched west, so Mak ran
		# 26 m away during the old 3 s wait. Walk straight back to the drum and hop onto the truffle instead.
		# Completion pass: the truffle floats over the drum (46, 3.8, 43); stick (0, 1) is world -Z, which jumped AWAY
		# from the drum. Hop onto the drum top from its south side instead.
		{"do": "goto", "at": Vector3(46.0, 2.0, 41.4), "tol": 0.4, "stop": true},
		{"do": "wait", "frames": 30},
		{"do": "press", "action": "jump", "frames": 14, "stick": Vector2(0, -1)},
		{"do": "hop", "at": Vector3(46.0, 3.0, 43.0)},
		{"do": "until_truffle", "id": "W3-2", "max_s": 6.0},
	]
	plans["w35lj"] = [
		{"do": "teleport", "at": Vector3(47.0, 2.05, BALCONY_Z), "yaw": -90.0},
		{"do": "wait", "frames": 20},
		{"do": "long_jump", "dir": Vector2(1, 0), "at": Vector3(59.4, 2.0, BALCONY_Z)},
		{"do": "until_grounded", "stick": Vector2(0.3, 0)},
		{"do": "mark", "text": "landed after the long jump out"},
		{"do": "goto", "at": Vector3(72.0, 1.0, BALCONY_Z), "tol": 0.4, "stop": true},
		{"do": "wait", "frames": 30},
		{"do": "goto", "at": Vector3(70.9, 1.0, BALCONY_Z), "tol": 0.3, "stop": true},
		{"do": "steer", "stick": Vector2(1, 0), "frames": 14},
		{"do": "press", "action": "jump", "frames": 14, "stick": Vector2(1, 0)},
		{"do": "hop", "at": Vector3(74.5, 2.0, BALCONY_Z)},
		{"do": "until_y_above", "y": 6.0, "max_s": 3.0},
		{"do": "steer", "stick": Vector2(-1, 0), "frames": 200},
		{"do": "until_grounded", "stick": Vector2(-1, 0)},
		{"do": "mark", "text": "home after the gumdrop bounce and breeze"},
	]
	plans["w35p3"] = [
		{"do": "teleport", "at": Vector3(15.0, 8.25, -24.6), "yaw": 0.0},
		{"do": "wait", "frames": 20},
		{"do": "sniff", "frames": 40},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(-0.3, 1)},
		{"do": "hop", "at": Vector3(14.4, 9.2, -27.4)},
		{"do": "press", "action": "jump", "frames": 12},
		{"do": "hop", "at": Vector3(16.6, 10.2, -28.8)},
		{"do": "press", "action": "jump", "frames": 12},
		{"do": "hop", "at": Vector3(14.4, 11.2, -30.2)},
		{"do": "press", "action": "jump", "frames": 12},
		{"do": "hop", "at": Vector3(16.6, 12.2, -31.6)},
		{"do": "press", "action": "jump", "frames": 14},
		{"do": "hop", "at": Vector3(15.4, 13.0, -33.6)},
		{"do": "wait", "frames": 40},
		{"do": "mark", "text": "on the ravine spire with page 3"},
	]
	plans["w33"] = [
		{"do": "teleport", "at": Vector3(16, 1.5, 21.5), "yaw": 0.0},
		{"do": "wait", "frames": 10},
		# Fairness pass: from z 19.6 (1 m back from the dock tip) the standing hop came down 1.9 m south of the biscuit
		# centre, in the chocolate, and the splash throw carried Mak on (1 hurt). Stand at the tip like a player.
		{"do": "goto", "at": Vector3(16, 1.4, 18.95), "tol": 0.15, "stop": true},
		{"do": "wait_node", "path": "Lagoon/lane_S", "xmin": 14.0, "xmax": 15.0, "z": 16.0},
		{"do": "press", "action": "jump", "frames": 10, "stick": Vector2(0, 1)},
		{"do": "hop", "node": true, "top_off": 0.35},
		# Boarding at the dock tip (x about 15.4) and riding to 19.6 stood 3.2 s: the biscuit sagged (3.0 s rule) and burned.
		{"do": "ride", "x_until": 18.4},
		# Fairness pass: the jump used to leave facing east (riding), so the push north was side speed (2.3 m/s cap), it
		# landed 1.6 m short in the chocolate and only the splash throw reached the islet. Turn and step north first.
		{"do": "wait", "frames": 14, "stick": Vector2(0.35, 0.8)},
		{"do": "press", "action": "jump", "frames": 16, "stick": Vector2(0.2, 1)},
		{"do": "hop", "at": Vector3(21, 1.6, 11.0)},
		# R3 barrel stack (x 22.8..24.4, z 8.2..12.2): go round its north-west corner to the north-east rim.
		{"do": "goto", "at": Vector3(21.9, 1.6, 7.7), "tol": 0.4},
		{"do": "goto", "at": Vector3(23.6, 1.6, 7.4), "tol": 0.4, "stop": true},
		# Completion pass: a standing jump from the rim covers about 2.1 m before it lands, and a biscuit picked at
		# x 25.3 had moved 2.6 m/s on to x 27.2, so Mak came down 1.6 m short in the hot chocolate (hurt, then
		# dunked). Take the biscuit about 1 m earlier, and lean toward it from the take-off.
		{"do": "wait_node", "path": "Lagoon/lane_E", "xmin": 24.2, "xmax": 25.2, "z": 5.6},
		{"do": "press", "action": "jump", "frames": 12, "stick": Vector2(0.8, 0.6)},
		{"do": "hop", "node": true, "top_off": 0.35},
		{"do": "mark", "text": "on lane E"},
		{"do": "ride", "x_until": 29.0},
		# Fairness pass (2026-10-19): the "walk off the side" was the hot-chocolate check burning Mak while he stood on
		# the biscuit's rim (p.y 0.49 < 0.5). With that fixed and the wider lane E biscuits (r 1.7, every 1.75 s),
		# leapfrog like a player: step back to the rear rim, run forward along the lane, jump from the front rim.
		{"do": "leapfrog", "lane": "Lagoon/lane_E", "wait_s": 0.45, "back_r": 1.15, "front_r": 1.0, "runup_s": 0.7},
		{"do": "until_truffle", "id": "W3-3", "max_s": 3.0},
	]
	return plans


# ================================================================ intro cameo (R2.10)

## First W3 entry only (skippable with jump): Sir Reginald on the cottage chimney sniffs "PIE", inflates and floats off
## north-east; then a pan from the gumdrop spiral to the fort. `--w3-intro` forces it (captures, video).
func _maybe_intro() -> void:
	var dev := get_node_or_null("/root/Dev")
	var forced := dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "w3-intro"))
	if not forced:
		if dev != null and dev.has_method("has_arg") and (dev.call("has_arg", "capture") or dev.call("has_arg", "replay") or dev.call("has_arg", "w3-bot")):
			return
		if ObjSvc.can("Game", "is_unlocked") and bool(ObjSvc.call_on("Game", "is_unlocked", ["w3_intro_seen"])):
			return
	ObjSvc.call_on("Game", "unlock", ["w3_intro_seen"])
	var chim := Vector3(-4.0, 20.6, -30.05)
	var wolf := glb("res://assets/characters/wolf_boss/wolf_boss.glb", chim + Vector3(0, 0.0, 0), 25.0, 1.0, self)
	var smoke := get_node_or_null("Knoll/ChimneySmoke") as Node3D
	if smoke:
		smoke.visible = false
	wolf.name = "SirReginaldCameo"
	# R1 visual major: an icing cap on the chimney so the perch reads as part of the gingerbread house.
	var cap := mesh_node(Geo.lathe([Vector2(0.95, -0.25), Vector2(1.0, 0.0), Vector2(0.92, 0.18), Vector2(0.6, 0.24), Vector2(0.0, 0.24)], 28, 1.0, 1.0,
		[Color("#FFE4EE"), Color("#FFF7EE"), Color("#FFF7EE"), Color("#FFFFFF"), Color("#FFFFFF")], false, false, 0.08, 6), vc_mat(0.4), chim + Vector3(0, -0.1, 0), self, "ChimneyIcing")
	var cam := Camera3D.new()
	cam.name = "IntroCam"
	cam.fov = 31.0
	add_child(cam)
	var prev := get_viewport().get_camera_3d()
	cam.global_transform = Transform3D(Basis(), chim + Vector3(4.2, 0.6, 12.0)).looking_at(chim + Vector3(0, 2.6, 0), Vector3.UP)
	cam.make_current()
	var line := Label3D.new()
	line.text = "\"Mmm. I smell... PIE.\""
	line.font_size = 72
	line.outline_size = 12
	line.modulate = Color("#FFF7EE")
	line.outline_modulate = Color("#6B1F22")
	line.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	line.pixel_size = 0.006
	add_child(line)
	line.global_position = chim + Vector3(0.6, 4.0, 0.8)
	line.visible = false
	var skip := [false]
	var t := 0.0
	var phase := 0
	var puffed := false
	while t < 6.3 and not skip[0]:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		if Input.is_action_just_pressed("jump") and t > 0.3:
			skip[0] = true
		if t < 3.8:
			line.visible = t > 0.5 and t < 2.6
			if t < 1.6:
				# The sniff: head tilt, a 1.5 Hz bob, nose up.
				wolf.rotation_degrees = Vector3(-6.0 + sin(t * TAU * 1.5) * 4.0, 25.0 + sin(t * 2.0) * 8.0, sin(t * 3.1) * 6.0)
				wolf.global_position = chim + Vector3(0, absf(sin(t * TAU * 1.5)) * 0.12, 0)
			elif t < 2.6:
				# The 1.0 s chest inflate (wider on X/Z, a little taller), with a wobble.
				var k := (t - 1.6) / 1.0
				var e := 1.0 - pow(1.0 - k, 3.0)
				var wob := sin(k * 18.0) * 0.03 * (1.0 - k)
				wolf.scale = Vector3(1.0 + e * 0.25 + wob, 1.0 + e * 0.08, 1.0 + e * 0.25 + wob)
				wolf.rotation_degrees = Vector3(-10.0 * e, 25.0, 0)
			else:
				# Float-off on his own breath, north-east over Frosting Peak.
				if not puffed:
					puffed = true
					ObjSvc.burst(self, chim + Vector3(0, 0.5, 0), Color(1.0, 0.95, 0.9), 30, 4.0, 0.3, -2.0, 1.0)
					ObjSvc.sfx("gust_whoosh", chim)
				var k := (t - 2.6) / 1.2
				wolf.global_position = chim + Vector3(k * k * 7.0, k * 5.5 + k * k * 2.0, -k * k * 4.0)
				wolf.rotation_degrees.z = sin(k * 9.0) * 8.0
				cam.look_at(wolf.global_position + Vector3(0, 1.8, 0), Vector3.UP)
		else:
			if phase == 0:
				phase = 1
				line.visible = false
				wolf.visible = false
				cam.fov = 50.0
			var k2 := clampf((t - 3.8) / 2.5, 0.0, 1.0)
			var tgt := Vector3(26, 10, 38).lerp(Vector3(46, 4, 43), k2 * k2 * (3.0 - 2.0 * k2))
			cam.global_transform = Transform3D(Basis(), Vector3(10, 3.5, 52)).looking_at(tgt, Vector3.UP)
	wolf.queue_free()
	line.queue_free()
	if smoke:
		smoke.visible = true
	if prev and is_instance_valid(prev):
		prev.make_current()
	cam.queue_free()


# ================================================================ round-3 additions and generic statics

var _sniff_slabs: Array[MeshInstance3D] = []
var _slab_glow := 0.0


func _build_r3_extras() -> void:
	var g := group_node("R3")
	# Ids built by dedicated sections (or deliberately not built: the crows' nest needs the enemies' brute-bounce rule).
	var skip := ["crow_nest_trunk", "crow_nest", "cottage_dormer_top", "cottage_ridge_cap", "cottage_chimney", "cottage_roof_slopes",
		"firewood_step", "cocoa_tin_step", "kitchen_wall_S"]
	for p in data["platforms"]:
		var id := String(p["id"])
		var kind := String(p["kind"])
		if id in skip:
			continue
		var pos := v3(p["pos"])
		var sz := v3(p["size"])
		match kind:
			"static_box":
				if id == "islet_barrel_stack":
					var bs := body(id, pos, g, "wood")
					box_shape(bs, sz)
					for k in 3:
						var br := rcyl("Barrel", Vector3(0, -sz.y * 0.5 + 0.75 + k * 1.35, -1.2 + k * 1.2), 0.75, 1.5, Color("#F3D08F"), Color("#B8733A"), false, toon(Color.WHITE, "gingerbread", 0.6, true), bs, 16)
						br.rotation_degrees = Vector3(0, k * 40.0, 80.0 - k * 20.0)
			"static_cylinder":
				if id == "ravine_spire":
					var base := pos.y - sz.y * 0.5
					var sb := body(id, Vector3(pos.x, base, pos.z), g, "candy")
					cyl_shape(sb, sz.x * 0.5, sz.y, Vector3(0, sz.y * 0.5, 0))
					var r := sz.x * 0.5
					mesh_node(Geo.lathe([Vector2(r * 1.3, 0.0), Vector2(r, 1.0), Vector2(r * 0.95, sz.y - 0.6), Vector2(r * 1.15, sz.y - 0.1), Vector2(0.0, sz.y)], 7, 1.0, 1.0,
						[Color("#C9A6F2"), Color("#E2B6F5"), Color("#FFB3D1"), Color("#FFE4F0"), Color("#FFF2F8")]), toon(Color.WHITE, "", 0.35, true, 0.15, Color(1.0, 0.5, 0.8), 0.15, 0.8, 1.3), Vector3.ZERO, sb)
			"sniff_reveal_platform":
				# R3.5 sugar-glass slab: always solid, nearly invisible; Snout Sniff within 14 m makes it glow amber for 6 s.
				var sl := body(id, pos, g, "candy")
				box_shape(sl, sz)
				var mi := MeshInstance3D.new()
				mi.mesh = Geo.rounded_box(sz, 0.08, 2, Color.WHITE, Color.WHITE)
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.9, 0.95, 1.0, 0.08)
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.roughness = 0.05
				m.metallic_specular = 1.0
				m.emission_enabled = true
				m.emission = Color(1.0, 0.7, 0.25)
				m.emission_energy_multiplier = 0.0
				mi.material_override = m
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				sl.add_child(mi)
				_sniff_slabs.append(mi)
	# R3.3 balcony breeze: a westward wind band above the gap (y 4.5..11) carries a gumdrop bounce home.
	for h in data["hazards"]:
		if String(h["id"]) == "balcony_breeze":
			var bc: Array = h.get("box_center", [67.5, 7.75, 34.5])
			var bsz: Array = h.get("box_size", [17, 6.5, 4])
			var wv: Array = h.get("wind", [-10, 0, 0])
			# Tuned: the plan's -10 m/s let a bounce fall short of the page edge (bot run); -17 lands about x 56-59.
			var w := Vector3(float(wv[0]), float(wv[1]), float(wv[2])) * 1.7
			var bz := inst(O + "WindZone.tscn", v3(bc), g, {"size": v3(bsz), "direction": w.normalized(), "strength": w.length(), "show_particles": true, "streak_color": Color(1.0, 0.7, 0.85, 0.6)})
			if bz:
				bz.name = "BalconyBreeze"
	# Cloud holding the balcony rope (decor) is built with the balcony; the flour mark in the kitchen:
	var fm: Dictionary = _plat("backflip_flour_mark")
	var fmi := MeshInstance3D.new()
	fmi.mesh = Geo.rounded_box(Vector3(1.2, 0.03, 1.2), 0.01, 1, Color("#FFFFFF"), Color("#F2EEE6"))
	fmi.material_override = vc_mat(0.9)
	add_child(fmi)
	fmi.global_position = v3(fm["pos"])
	var hoof := Label3D.new()
	hoof.text = "o o"
	hoof.font_size = 64
	hoof.modulate = Color("#C9B9A0")
	hoof.rotation_degrees = Vector3(-90, 0, 0)
	hoof.pixel_size = 0.006
	fmi.add_child(hoof)
	hoof.position = Vector3(0, 0.03, 0)


var _spire_t := 0.0


func _spire_step(delta: float, pl: Node3D) -> void:
	if _spire_t < 0.0 or not enemies.has("crow_ravine"):
		return
	var p := pl.global_position
	if Vector2(p.x - 15.4, p.z + 33.6).length() < 2.6 and p.y > 12.5 and (pl as CharacterBody3D).is_on_floor():
		_spire_t += delta
		if _spire_t > 0.5:
			_spire_t = -1.0
			var cr: Node = enemies["crow_ravine"]
			if is_instance_valid(cr):
				cr.set("ai_enabled", true)
	else:
		_spire_t = 0.0


func _slab_step(delta: float, pl: Node3D) -> void:
	if _sniff_slabs.is_empty():
		return
	var sniffing := pl.has_method("get_state_name") and String(pl.call("get_state_name")) == "sniff" and pl.global_position.distance_to(Vector3(15.5, 10.5, -30.0)) < 14.0
	if sniffing:
		if _slab_glow <= 0.0:
			print("[W3] sniff reveals the sugar-glass stair")
		_slab_glow = 6.0
	_slab_glow = maxf(0.0, _slab_glow - delta)
	var k := clampf(_slab_glow / 1.0, 0.0, 1.0)
	var glint := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.00314)
	for mi in _sniff_slabs:
		var m := mi.material_override as StandardMaterial3D
		m.albedo_color = Color(1.0, 0.85, 0.55, lerpf(0.08 + glint * 0.04, 0.75, k))
		m.emission_energy_multiplier = lerpf(glint * 0.15, 1.6, k)


# ================================================================ R3.8 the tale repairs itself (world_state)

## Read on world load from Game.has_truffle(). All truffles stay live; only scenery, NPCs and hints change.
## Implemented: W3-6 (Hansel and Gretel leave the cage and join Mother Treacle with rhyming hints; sentry_cottage
## gone) and W3-1 + W3-6 + W3-8 (the family goes home to the cottage doorway, chimney smoke turns warm white).
## Not yet: the W3-1 permanent crumb relight and the W3-2 parade band.
func _apply_world_state() -> void:
	var g: Node = get_node_or_null("/root/Game")
	if g == null or not g.has_method("has_truffle"):
		return
	var has6 := bool(g.call("has_truffle", "W3-6"))
	var home := has6 and bool(g.call("has_truffle", "W3-1")) and bool(g.call("has_truffle", "W3-8"))
	# Dev preview for captures and tests: --w3-state=rescued | home
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_method("has_arg") and bool(dev.call("has_arg", "w3-state")):
		var ws := String(dev.call("arg", "w3-state", "home"))
		has6 = true
		home = ws == "home"
	# R3.8 W3-1: the breadcrumb trail and the maze solution are relit for good (soft gold crumbs).
	var dev_ws := dev != null and dev.has_method("has_arg") and bool(dev.call("has_arg", "w3-state"))
	if bool(g.call("has_truffle", "W3-1")) or dev_ws:
		_relight_crumbs()
	if not has6:
		return
	var states := PackedStringArray(["W3-6"])
	if enemies.has("sentry_cottage") and is_instance_valid(enemies["sentry_cottage"]):
		(enemies["sentry_cottage"] as Node).queue_free()
		enemies.erase("sentry_cottage")
	var cage := find_child("KidsCage", true, false) as Node3D
	if cage:
		for kn in ["Hansel", "Gretel"]:
			var kid := cage.get_node_or_null(kn) as Node3D
			if kid:
				kid.visible = false
	var lines := {}
	for n in data["npcs"]:
		if n.has("post_rescue_lines") and n["post_rescue_lines"] != null:
			lines[String(n["id"])] = PackedStringArray(n["post_rescue_lines"])
	var kid_paths := ["res://assets/characters/hansel/hansel.glb", "res://assets/characters/gretel/gretel.glb"]
	var fallback := ["res://assets/characters/jack/jack.glb", "res://assets/characters/jack/jack_v2.glb"]   # never hazel (a pig) as Gretel; real meshes requested
	var spots := [Vector3(-11.2, 0.0, 17.0), Vector3(-8.8, 0.0, 17.0)]
	if home:
		spots = [Vector3(-8.0, 8.0, -22.6), Vector3(-4.0, 8.0, -22.6)]
	var grp := group_node("WorldState")
	for i in 2:
		var kp: String = kid_paths[i] if ResourceLoader.exists(kid_paths[i]) else fallback[i]
		var at: Vector3 = spots[i]
		at.y = maxf(at.y, h_at(at.x, at.z))
		var nm: String = ["hansel", "gretel"][i]
		var kid := inst(O + "NPCTalker.tscn", at, grp, {"speaker": nm.capitalize(), "visual_scene": scene(kp),
			"visual_scale": 0.72, "visual_flip_180": false,
			"lines": lines.get(nm, PackedStringArray(["Thank you, Mister Pig!"]))})
		if kid:
			kid.name = nm.capitalize()
			kid.rotation_degrees.y = 180.0 if home else 160.0
	if home:
		states.append("home")
		var mt := find_child("MotherTreacle", true, false) as Node3D
		if mt:
			mt.global_position = Vector3(-6.0, maxf(8.0, h_at(-6.0, -23.2)), -23.2)
			mt.rotation_degrees.y = 180.0
		if has_meta("chimney_smoke"):
			var old := get_meta("chimney_smoke") as Node3D
			if is_instance_valid(old):
				old.visible = false
			add_fx("ChimneySmoke", get_meta("chimney_smoke_pos"), self, Color("#FFF4E0"), 1.2)
	print("[W3] world_state applied: %s" % ", ".join(states))

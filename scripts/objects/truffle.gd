class_name Truffle
extends Area3D
## Golden Truffle: the main collectible. Bobs, spins, glows and sparkles over a soft ground shadow.
## Collecting calls Game.collect_truffle(truffle_id). Already-collected truffles show as a translucent ghost
## (still collectable for the replay fanfare, but they do not count twice: Game decides).

signal collected(id: String)

## Generated mesh to use instead of the placeholder: instanced under Visual and turned 180 degrees about Y
## (glTF faces +Z, objects face -Z). Leave empty for the primitive placeholder.
@export var visual_scene: PackedScene
@export var visual_scale: float = 1.0
@export var visual_flip_180: bool = true
## Uses the generated golden truffle mesh (meshes workstream) when no visual_scene is set and the file exists.
@export var use_default_mesh: bool = true
@export var truffle_id: String = "W1-1"
@export var mission_title: String = ""
@export var bob_height: float = 0.18
@export var bob_speed: float = 2.2
@export var spin_speed: float = 1.6
@export var glow_energy: float = 1.6
@export var light_range: float = 3.5
## Set by spawners: plays a rise-and-pop reveal when the truffle appears.
@export var spawn_revealed: bool = false
## Height of the truffle centre above the node origin (the origin sits on the ground).
@export var hover_height: float = 0.9
## Warm grade for the generated gold: metal reflecting a blue sky reads olive, so the albedo is pushed toward orange
## and a faint warm self-glow keeps it reading as gold under every world's light.
@export var gold_tint: Color = Color(1.0, 0.8, 0.5)
@export var gold_glow: float = 0.38  # M3b: 0.22 read olive in shade on the W1 windmill deck
## Truffle-skin warts (object-space cells per metre) and their bump. M3b: the 30 / 1.7 warts were about 3 cm across and
## read as a foam of gold bubbles (a "gold raspberry") from the play camera; finer, softer warts let the big lobes and
## the gold carry the silhouette while close-ups still show a tuber skin.
@export var wart_scale: float = 56.0
@export var wart_bump: float = 0.95
## 0..1: pulls the model's round lobes toward a lumpy tuber shell (vertex shader; the sprout is untouched).
@export_range(0.0, 1.0) var lobe_soften: float = 0.6

const DEFAULT_MESH := "res://assets/props/pickups/golden_truffle_v2/golden_truffle_v2.glb"
const FALLBACK_MESH := "res://assets/props/pickups/golden_truffle/golden_truffle.glb"
const DEFAULT_MESH_SCALE := 1.4

var is_collected := false
var is_ghost := false
var _t := 0.0
var _visual: Node3D
var _spinner: Node3D
var _light: OmniLight3D
var _sparkles: GPUParticles3D
var _shadow: MeshInstance3D
var _glints: ObjGlints
var _spin_boost := 0.0
## False while a spawned truffle plays its reveal, so a player standing on the spot (a dug patch, a cage, the
## 100-acorn reward above Mak) sees it rise before it is taken. Re-armed after `reveal_grace` seconds.
var _armed := true
@export var reveal_grace: float = 0.85


func _ready() -> void:
	ObjSvc.ensure_npc_life_auto(self)
	add_to_group("truffle")
	add_to_group("sniff_target")
	collision_layer = ObjSvc.L_PICKUP
	collision_mask = ObjSvc.L_PLAYER
	monitoring = true
	ObjSvc.add_shape(self, ObjSvc.sphere_shape(0.75), Vector3(0, hover_height, 0))
	if visual_scene == null and use_default_mesh:
		var path := DEFAULT_MESH if ResourceLoader.exists(DEFAULT_MESH) else FALLBACK_MESH
		if ResourceLoader.exists(path):
			visual_scene = load(path) as PackedScene
		if visual_scene != null and is_equal_approx(visual_scale, 1.0):
			visual_scale = DEFAULT_MESH_SCALE
	_visual = ObjSvc.ensure_visual(self)
	_spinner = Node3D.new()
	_spinner.name = "Spinner"
	_spinner.position = Vector3(0, hover_height, 0)
	add_child(_spinner)
	_visual.reparent(_spinner, false)
	if not ObjSvc.visual_has_content(_visual):
		_build_placeholder()
	else:
		ObjSvc.center_generated(_visual)
		_warm_gold()
		_add_halo(1.7)
	_glints = ObjGlints.new()
	_glints.radius = 0.36
	_glints.size = 0.2  # critique r1 re-run: smaller, crisper twinkles (was 0.42)
	_glints.count = 3
	_spinner.add_child(_glints)
	_shadow = ObjSvc.shadow_blob(self, 0.55)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.8, 0.35)
	_light.light_energy = glow_energy
	_light.omni_range = light_range
	_light.position = Vector3(0, hover_height, 0)
	_light.shadow_enabled = false
	add_child(_light)
	_sparkles = ObjSvc.twinkles(_spinner, Color(1.0, 0.9, 0.55), 6, 0.5, 0.11, 0.45)
	_t = randf() * TAU
	body_entered.connect(_on_body_entered)
	is_ghost = ObjSvc.has_truffle(truffle_id)
	if is_ghost:
		_apply_ghost()
		remove_from_group("sniff_target")
	if spawn_revealed:
		_reveal()


func _build_placeholder() -> void:
	var gold := ObjSvc.mat(ObjSvc.GOLD, 0.28, 0.85, Color(1.0, 0.7, 0.2), 0.55)
	var deep := ObjSvc.mat(ObjSvc.GOLD_DEEP, 0.35, 0.8, Color(0.9, 0.5, 0.1), 0.35)
	# A lumpy, knobbly truffle body: a main sphere plus smooth bumps.
	ObjSvc.sphere(_visual, 0.34, gold, Vector3.ZERO, Vector3(1.0, 0.92, 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 64
	for i in 14:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.8, 1), rng.randf_range(-1, 1)).normalized()
		ObjSvc.sphere(_visual, rng.randf_range(0.09, 0.14), gold if i % 3 else deep, dir * 0.29)
	# A little sprig of leaves on top, so it reads as a precious truffle and not a nugget.
	var leaf := ObjSvc.mat(Color(0.35, 0.68, 0.25), 0.5)
	ObjSvc.sphere(_visual, 0.09, leaf, Vector3(0.07, 0.36, 0), Vector3(1.6, 0.35, 0.8)).rotation_degrees = Vector3(0, 0, 25)
	ObjSvc.sphere(_visual, 0.08, leaf, Vector3(-0.07, 0.35, 0.02), Vector3(1.5, 0.35, 0.8)).rotation_degrees = Vector3(0, 30, -25)
	# Soft halo card behind the truffle.
	var halo := QuadMesh.new()
	halo.size = Vector2(1.5, 1.5)
	var hm := ObjSvc.unshaded(Color(1, 1, 1, 1), true)
	hm.albedo_texture = ObjSvc.radial_tex(Color(1.0, 0.8, 0.35, 0.55), Color(1.0, 0.7, 0.2, 0.0))
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var hmi := ObjSvc.add_mesh(_visual, halo, hm)
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hmi.name = "Halo"


## Critique objects r1 re-run: golden_truffle_v2 read as a gold raspberry (smooth glossy lobes). Until a new tuber
## model lands, a truffle-skin shader goes over the same textures: fine pyramidal warts (3D cellular noise in
## object space, bump-mapped from screen derivatives), dark cocoa-gold crevices between the warts and in the AO of
## the big lobes, rougher valleys and brighter gold-leaf tops. The green sprout keeps its plain look.
const TRUFFLE_SKIN := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_orm = false;
uniform bool has_normal = false;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform vec4 crevice : source_color = vec4(0.46, 0.25, 0.06, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.6, 0.16, 1.0);
uniform float glow_energy = 0.22;
uniform float wart_scale = 30.0;
uniform float bump = 1.7;
uniform float ao_strength = 1.6;
// M3b: soften the round lobes toward an irregular potato-like tuber (the deep round lobes are what read as a raspberry).
uniform float lobe_soften = 0.0;
uniform vec3 body_center = vec3(0.0, 0.26, 0.0);
uniform vec3 body_radii = vec3(0.3, 0.26, 0.32);
uniform vec2 sprout_y = vec2(0.46, 0.52);
varying vec3 obj_pos;

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

vec2 cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = hash3(i + g);
				float d = length(g + o - f);
				if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) { f2 = d; }
			}
		}
	}
	return vec2(f1, f2);
}

void vertex() {
	obj_pos = VERTEX;
	if (lobe_soften > 0.0) {
		vec3 d = VERTEX - body_center;
		vec3 dir = normalize(d / body_radii);
		// The ellipsoid radius along this direction, made lumpy with a few broad, irregular swells.
		float lump = sin(dir.x * 3.1 + 1.7) * sin(dir.y * 2.3 + 0.4) * sin(dir.z * 2.9 + 2.2) * 0.09
			+ sin(dir.x * 5.3 - dir.z * 4.1 + 0.9) * 0.035;
		vec3 shell = body_center + dir * body_radii * (1.0 + lump);
		float k = lobe_soften * (1.0 - smoothstep(sprout_y.x, sprout_y.y, VERTEX.y));
		VERTEX = mix(VERTEX, shell, k);
		vec3 sn = normalize(dir / body_radii);
		NORMAL = normalize(mix(NORMAL, sn, k * 0.85));
	}
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	float green = smoothstep(0.02, 0.12, a.g - a.r);
	vec2 c = cells(obj_pos * wart_scale);
	vec2 c2 = cells(obj_pos * wart_scale * 2.3 + 7.1);
	float edge = smoothstep(0.0, 0.42, c.y - c.x);
	float h = (1.0 - c.x) * 0.9 + (1.0 - c2.x) * 0.1;
	float ao = has_orm ? texture(orm_tex, UV).r : 1.0;
	float ao_k = clamp(pow(ao, ao_strength), 0.0, 1.0);
	// Fix r2: thin seams between the warts (the r1 fix drew a dark crackle net that read as granola from afar).
	float seam = 1.0 - edge;
	float valley = seam * seam * seam * 0.25 + (1.0 - ao_k) * 0.85;
	valley = clamp(valley, 0.0, 1.0) * (1.0 - green);
	vec3 gold = a.rgb * tint.rgb;
	ALBEDO = mix(gold * (0.95 + 0.3 * (1.0 - c.x)), crevice.rgb, valley * 0.6);
	vec3 n = NORMAL;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.6;
	}
	// Bump from screen-space derivatives of the wart height (no tangents needed).
	float hb = h * (1.0 - green);
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(hb);
	float dhdy = dFdy(hb);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	NORMAL = normalize(abs(det) * n - grad * bump * 0.02);
	METALLIC = mix(0.92, 0.0, green);
	ROUGHNESS = mix(mix(0.22, 0.6, valley), 0.6, green);
	EMISSION = glow.rgb * glow_energy * (1.0 - valley) * (1.0 - green) * a.rgb;
#ifdef GHOST
	// Already-owned truffle: the same softened shape as a pale blue glass ghost (ObjSvc.ghost_mat look).
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = vec3(0.62, 0.78, 1.0) * (0.85 + 0.15 * (1.0 - valley));
	METALLIC = 0.2;
	ROUGHNESS = 0.15;
	EMISSION = vec3(0.45, 0.65, 1.0) * (0.25 + 0.6 * rim);
	ALPHA = 0.4 + 0.3 * rim;
#endif
}
"""
static var _skin_shader: Shader
static var _ghost_shader: Shader


func _warm_gold() -> void:
	# A/B captures: -- --truffle-soften=0 shows the raw model lobes.
	var dev := ObjSvc.autoload("Dev")
	if dev != null and dev.has_method("arg"):
		var o := str(dev.call("arg", "truffle-soften", ""))
		if o != "" and o.is_valid_float():
			lobe_soften = clampf(float(o), 0.0, 1.0)
	if _skin_shader == null:
		_skin_shader = Shader.new()
		_skin_shader.code = TRUFFLE_SKIN
	for n in _visual.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			if src.albedo_texture != null:
				var sm := ShaderMaterial.new()
				sm.shader = _skin_shader
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				var orm: Texture2D = src.ao_texture if src.ao_texture != null else src.roughness_texture
				sm.set_shader_parameter("has_orm", orm != null)
				if orm != null:
					sm.set_shader_parameter("orm_tex", orm)
				sm.set_shader_parameter("has_normal", src.normal_enabled and src.normal_texture != null)
				if src.normal_texture != null:
					sm.set_shader_parameter("normal_tex", src.normal_texture)
				# The v2 texture is already gold: the fallback tint (for plain materials) made it orange here.
				sm.set_shader_parameter("tint", gold_tint.lerp(Color(1.0, 0.93, 0.72), 0.7))
				sm.set_shader_parameter("glow_energy", gold_glow)
				sm.set_shader_parameter("wart_scale", wart_scale)
				sm.set_shader_parameter("bump", wart_bump)
				if lobe_soften > 0.0:
					var bb := mi.mesh.get_aabb()
					var body_h := bb.size.y * 0.78
					sm.set_shader_parameter("lobe_soften", lobe_soften)
					sm.set_shader_parameter("body_center", Vector3(bb.get_center().x, bb.position.y + body_h * 0.5, bb.get_center().z))
					sm.set_shader_parameter("body_radii", Vector3(bb.size.x * 0.5, body_h * 0.5, bb.size.z * 0.5) * 0.97)
					sm.set_shader_parameter("sprout_y", Vector2(bb.position.y + bb.size.y * 0.66, bb.position.y + bb.size.y * 0.76))
					sm.set_shader_parameter("ao_strength", 0.9)
				# The wart size is set in object space: about 1.2 cm warts on the 0.6 m model.
				mi.set_surface_override_material(i, sm)
				continue
			var m := src.duplicate() as StandardMaterial3D
			m.albedo_color = src.albedo_color * gold_tint
			m.emission_enabled = true
			m.emission = Color(1.0, 0.6, 0.16)
			m.emission_energy_multiplier = gold_glow
			mi.set_surface_override_material(i, m)


## Soft additive glow card behind the generated truffle (the placeholder builds its own).
func _add_halo(sz: float) -> void:
	var halo := QuadMesh.new()
	halo.size = Vector2(sz, sz)
	var hm := ObjSvc.unshaded(Color(1, 1, 1, 1), true)
	hm.albedo_texture = ObjSvc.radial_tex(Color(1.0, 0.78, 0.3, 0.32), Color(1.0, 0.7, 0.2, 0.0))
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.render_priority = -1
	var hmi := ObjSvc.add_mesh(_spinner, halo, hm)
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hmi.name = "Halo"


func _apply_ghost() -> void:
	var g := ObjSvc.ghost_mat()
	for mi in _visual.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "Halo":
			continue
		var m := mi as MeshInstance3D
		# Skin-shaded surfaces keep their softened tuber shape as a ghost (a plain override would show the raw lobes).
		var used_skin := false
		if m.mesh != null:
			for i in m.mesh.get_surface_count():
				var sm := m.get_surface_override_material(i) as ShaderMaterial
				if sm != null and sm.shader == _skin_shader:
					if _ghost_shader == null:
						_ghost_shader = Shader.new()
						_ghost_shader.code = TRUFFLE_SKIN.replace("shader_type spatial;", "shader_type spatial;\n#define GHOST")
					var gm := sm.duplicate() as ShaderMaterial
					gm.shader = _ghost_shader
					m.set_surface_override_material(i, gm)
					used_skin = true
		if not used_skin:
			m.material_override = g
	_light.light_color = Color(0.7, 0.8, 1.0)
	_light.light_energy = glow_energy * 0.4
	_sparkles.amount = 6
	if _glints:
		_glints.visible = false
	var halo := _spinner.get_node_or_null("Halo") as MeshInstance3D
	if halo:
		halo.visible = false


func _reveal() -> void:
	_spinner.scale = Vector3.ONE * 0.01
	var start_y := _spinner.position.y
	_spinner.position.y = start_y - 0.8
	var tw := create_tween().set_parallel()
	tw.tween_property(_spinner, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_spinner, "position:y", start_y, 0.9).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	ObjSvc.burst(get_parent(), global_position + Vector3(0, hover_height, 0), Color(1, 0.85, 0.4), 30, 4.5, 0.2, -3.0, 1.2)
	ObjSvc.feedback("object_truffle_appear", global_position + Vector3(0, hover_height, 0), {"id": truffle_id}, "truffle_appear")
	_spin_boost = 14.0
	_armed = false
	get_tree().create_timer(reveal_grace, false).timeout.connect(_arm)


func _arm() -> void:
	_armed = true
	if is_collected or not monitoring:
		return
	for b in get_overlapping_bodies():
		if ObjSvc.is_player(b):
			collect()
			return


func _process(delta: float) -> void:
	if is_collected:
		return
	_t += delta
	# Bob with a soft hang at the top and a quicker dip, so it floats rather than oscillates.
	var ph := _t * bob_speed
	var bob := sin(ph) + 0.18 * sin(ph * 2.0 + 0.6)
	_spinner.position.y = hover_height + bob * bob_height
	# Spin breathes too: a touch faster on the way down; spawner reveals start with a fast whirl that settles.
	_spin_boost = move_toward(_spin_boost, 0.0, delta * 9.0)
	_spinner.rotation.y += (spin_speed * (1.0 + 0.25 * cos(ph)) + _spin_boost) * delta
	_spinner.rotation.z = sin(ph * 0.5) * 0.08
	# Gentle breathing squash (stretch on the rise, squash at the bottom) so it never looks static.
	var s := 1.0 - cos(ph) * 0.035
	_visual.scale = Vector3(2.0 - s, s, 2.0 - s)
	if _shadow:
		var k := 1.0 - (_spinner.position.y - hover_height + bob_height) / (bob_height * 4.0)
		_shadow.scale = Vector3.ONE * clampf(k, 0.6, 1.0)
	_light.light_energy = (glow_energy * (0.4 if is_ghost else 1.0)) * (0.85 + 0.15 * sin(_t * 3.1))


func _on_body_entered(body: Node) -> void:
	if _armed and ObjSvc.is_player(body):
		collect()


func collect() -> void:
	if is_collected:
		return
	is_collected = true
	remove_from_group("sniff_target")
	set_deferred("monitoring", false)
	# WorldRoot pauses the tree for the truffle celebration; keep the pop and burst animating through it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	ObjSvc.collect_truffle(truffle_id)
	var at := _spinner.global_position
	ObjSvc.feedback("object_truffle_collect", at, {"id": truffle_id, "ghost": is_ghost}, "truffle_collect")
	collected.emit(truffle_id)
	if _glints:
		_glints.visible = false
	# Anticipation: a quick squash toward the touch, then the whirl-up, flash and burst into stars.
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3(1.3, 0.7, 1.3), 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", Vector3(0.82, 1.3, 0.82), 0.09).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_on_pop_start)
	tw.set_parallel()
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_spinner, "position:y", _spinner.position.y + 1.3, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_spinner, "rotation:y", _spinner.rotation.y + TAU * 3.0, 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_spinner, "scale", Vector3.ONE * 1.35, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_callback(_on_pop_end)
	tw.tween_property(_spinner, "scale", Vector3.ONE * 0.01, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.9)
	tw.tween_callback(queue_free)
	if _light:
		var lt := create_tween()
		lt.tween_property(_light, "light_energy", glow_energy * 3.5, 0.16)
		lt.tween_property(_light, "light_energy", 0.0, 0.7)
	if _shadow:
		create_tween().tween_property(_shadow, "scale", Vector3.ONE * 0.01, 0.4)


func _on_pop_start() -> void:
	var sp := _spinner.global_position
	if ObjSvc.juice_handles("object_truffle_collect", "vfx"):
		return
	if not ObjSvc.fx(self, "TruffleBurst", sp, true):
		ObjSvc.burst(get_parent(), sp, Color(1, 0.85, 0.35), 40, 6.0, 0.22, -4.0, 1.1, true)
	_flash(sp)


func _on_pop_end() -> void:
	var sp := _spinner.global_position
	ObjSvc.feedback("object_truffle_burst", sp, {"id": truffle_id})
	if ObjSvc.juice_handles("object_truffle_burst", "vfx"):
		return
	ObjSvc.burst(get_parent(), sp, Color(1.0, 0.95, 0.7), 24, 3.5, 0.16, -1.0, 0.8, true)
	ObjFx.star_ring(get_parent(), sp, 8, 1.3, 0.5, Color(1.0, 0.92, 0.6))


## A bright expanding flash disc at the moment of collection.
func _flash(at: Vector3) -> void:
	ObjFx.flash(get_parent(), at, 1.6, 2.2, Color(1.0, 0.95, 0.75, 0.9))


## Sniff support (group "sniff_target").
func is_sniff_active() -> bool:
	return not is_collected and not is_ghost


func get_sniff_position() -> Vector3:
	return global_position + Vector3(0, hover_height, 0)


var _sniff_cool := 0.0


## Called by the player's Snout Sniff when the scent trail reaches this truffle (hero-track contract). The truffle
## answers with a bright twinkle and a little hop so a hidden one is easy to spot. Rate-limited, never collects.
func on_sniffed(_by: Node = null) -> void:
	if not is_sniff_active():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _sniff_cool:
		return
	_sniff_cool = now + 1.5
	ObjSvc.feedback("object_sniff_reveal", _spinner.global_position, {"id": truffle_id})
	_spin_boost = 10.0
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3(1.2, 0.8, 1.2), 0.07)
	tw.tween_property(_visual, "scale", Vector3(0.9, 1.15, 0.9), 0.1)
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if not ObjSvc.juice_handles("object_sniff_reveal", "vfx"):
		ObjFx.star_ring(get_parent(), _spinner.global_position, 6, 0.9, 0.4, Color(1.0, 0.9, 0.55), 0.45)

class_name EnemyKit
extends RefCounted
## Static helpers shared by every enemy and the boss: smooth-primitive "toy" parts,
## cartoon faces, popup labels, defeat-gag particle bursts and duck-typed calls into
## the Game and Audio autoloads (which may still be stubs while other workstreams build them).

const OUTLINE_DARK := Color(0.12, 0.08, 0.06)

static var _mat_cache: Dictionary = {}


# ---------------------------------------------------------------- materials

static func mat(color: Color, roughness: float = 0.55, rim: float = 0.35, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), roughness, rim, metallic]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.4
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_mat_cache[key] = m
	return m


static func glow_mat(color: Color, energy: float = 1.5) -> StandardMaterial3D:
	var key := "glow|%s|%.2f" % [color.to_html(), energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m


static var _feather_shader: Shader


static func feather_mat(color: Color) -> ShaderMaterial:
	var key := "feather|%s" % color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	if _feather_shader == null:
		_feather_shader = Shader.new()
		_feather_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform vec4 col : source_color = vec4(0.17, 0.18, 0.27, 1.0);
void fragment() {
	vec2 uv = UV;
	float w = 0.48 * pow(max(sin(uv.y * 3.14159), 0.0), 0.7) * (0.75 + 0.25 * uv.y);
	float dx = abs(uv.x - 0.5);
	if (dx > w || uv.y < 0.04) { discard; }
	float quill = 1.0 - smoothstep(0.015, 0.04, dx);
	float vane = 0.85 + 0.15 * sin((uv.y * 22.0) + dx * 30.0);
	ALBEDO = mix(col.rgb * vane, col.rgb * 1.9 + vec3(0.12), quill);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _feather_shader
	m.set_shader_parameter("col", color)
	_mat_cache[key] = m
	return m


static var _star_shader: Shader


static func star_mat(color: Color) -> ShaderMaterial:
	var key := "star|%s" % color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	if _star_shader == null:
		_star_shader = Shader.new()
		_star_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform vec4 col : source_color = vec4(1.0, 0.92, 0.35, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 q = UV - vec2(0.5);
	float r = length(q);
	float a = atan(q.x, -q.y);
	float edge = 0.2 + 0.28 * pow(0.5 + 0.5 * cos(5.0 * a), 2.2);
	if (r > edge) { discard; }
	float ink = smoothstep(edge - 0.07, edge - 0.04, r);
	vec3 c = mix(col.rgb * 1.25 + vec3(0.12), col.rgb, smoothstep(0.0, 0.25, r));
	ALBEDO = mix(c, vec3(0.32, 0.18, 0.05), ink);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _star_shader
	m.set_shader_parameter("col", color)
	_mat_cache[key] = m
	return m


static func unshaded(color: Color) -> StandardMaterial3D:
	var key := "unshaded|%s" % color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = m
	return m


# ---------------------------------------------------------------- primitive parts

static func _mi(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot_deg: Vector3, scl: Vector3, part_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	if part_name != "":
		mi.name = part_name
	parent.add_child(mi)
	return mi


static func ball(parent: Node3D, radius: float, color: Color, pos: Vector3, scl: Vector3 = Vector3.ONE, part_name: String = "", rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 32
	m.rings = 16
	return _mi(parent, m, color, pos, rot_deg, scl, part_name)


static func capsule(parent: Node3D, radius: float, height: float, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, part_name: String = "") -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = 24
	m.rings = 8
	return _mi(parent, m, color, pos, rot_deg, scl, part_name)


static func cylinder(parent: Node3D, top: float, bottom: float, height: float, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, part_name: String = "") -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 24
	return _mi(parent, m, color, pos, rot_deg, Vector3.ONE, part_name)


static func cone(parent: Node3D, radius: float, height: float, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, part_name: String = "") -> MeshInstance3D:
	return cylinder(parent, 0.0, radius, height, color, pos, rot_deg, part_name)


static func ring(parent: Node3D, inner: float, outer: float, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, part_name: String = "") -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 32
	m.ring_segments = 12
	return _mi(parent, m, color, pos, rot_deg, Vector3.ONE, part_name)


static func box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, part_name: String = "") -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mi(parent, m, color, pos, rot_deg, Vector3.ONE, part_name)


static func pivot(parent: Node3D, part_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = part_name
	n.position = pos
	parent.add_child(n)
	return n


## Builds one cartoon eye (white, iris/pupil, highlight, lid brow) facing -Z.
## mood: "angry", "smug", "worried", "determined", "happy", "neutral".
static func eye(parent: Node3D, pos: Vector3, radius: float, iris: Color, mood: String, left: bool) -> Node3D:
	var root := pivot(parent, "eye_l" if left else "eye_r", pos)
	ball(root, radius, Color(0.98, 0.97, 0.94), Vector3.ZERO, Vector3(1.0, 1.15, 0.75))
	var pupil_root := pivot(root, "pupil", Vector3(0, 0, -radius * 0.55))
	ball(pupil_root, radius * 0.55, iris, Vector3.ZERO, Vector3(1, 1.1, 0.5))
	ball(pupil_root, radius * 0.32, Color(0.05, 0.04, 0.05), Vector3(0, 0, -radius * 0.18), Vector3(1, 1.1, 0.5))
	var hl := ball(pupil_root, radius * 0.14, Color(1, 1, 1), Vector3(radius * 0.18, radius * 0.22, -radius * 0.32))
	hl.material_override = unshaded(Color(1, 1, 1))
	# Brow: a chunky dark bar whose tilt sells the attitude.
	var side := -1.0 if left else 1.0
	var tilt := 0.0
	var lift := radius * 1.05
	match mood:
		"angry":
			tilt = -24.0
			lift = radius * 0.85
		"determined":
			tilt = -14.0
		"smug":
			tilt = 10.0
			lift = radius * 1.15
		"worried":
			tilt = 22.0
			lift = radius * 1.2
		"happy":
			tilt = 6.0
			lift = radius * 1.25
	var brow := capsule(root, radius * 0.2, radius * 1.5, OUTLINE_DARK, Vector3(0, lift, -radius * 0.45), Vector3(0, 0, 90 + tilt * side), Vector3.ONE, "brow")
	brow.set_meta("base_rot", brow.rotation_degrees)
	if mood == "smug":
		# Half-closed lid gives the smug look.
		var lid := ball(root, radius * 1.02, parent.get_meta("skin", Color(0.6, 0.6, 0.6)) as Color, Vector3(0, radius * 0.45, -radius * 0.05), Vector3(1.05, 0.6, 0.8), "lid")
		lid.rotation_degrees = Vector3(-10, 0, 0)
	return root


static func face(parent: Node3D, center: Vector3, spacing: float, radius: float, iris: Color, mood: String) -> Array[Node3D]:
	var l := eye(parent, center + Vector3(-spacing, 0, 0), radius, iris, mood, true)
	var r := eye(parent, center + Vector3(spacing, 0, 0), radius, iris, mood, false)
	return [l, r]


## A grin, smirk or "o" mouth built from a half torus or a ball.
static func mouth(parent: Node3D, pos: Vector3, width: float, kind: String, color: Color = Color(0.25, 0.06, 0.08)) -> Node3D:
	var root := pivot(parent, "mouth", pos)
	match kind:
		"o":
			ball(root, width * 0.35, color, Vector3.ZERO, Vector3(1, 1.2, 0.5))
		"smirk":
			var t := ring(root, width * 0.42, width * 0.55, color, Vector3.ZERO, Vector3(90, 0, 0))
			t.scale = Vector3(1.0, 1.0, 0.55)
			t.rotation_degrees = Vector3(90, 0, -18)
		"toothy":
			ball(root, width * 0.5, color, Vector3.ZERO, Vector3(1.0, 0.45, 0.4))
			box(root, Vector3(width * 0.18, width * 0.16, width * 0.08), Color(1, 1, 0.96), Vector3(-width * 0.16, width * 0.12, -width * 0.12))
			box(root, Vector3(width * 0.18, width * 0.16, width * 0.08), Color(1, 1, 0.96), Vector3(width * 0.16, width * 0.12, -width * 0.12))
		_:
			ball(root, width * 0.5, color, Vector3.ZERO, Vector3(1.0, 0.35, 0.4))
	return root


# ---------------------------------------------------------------- popups and FX

static func popup(parent: Node, pos: Vector3, text: String, color: Color = Color(1, 0.86, 0.2), size: int = 96, life: float = 1.0) -> Label3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = int(size * 0.28)
	l.modulate = color
	l.outline_modulate = Color(0.1, 0.05, 0.05)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.0042
	l.render_priority = 10
	l.outline_render_priority = 9
	parent.add_child(l)
	l.global_position = pos
	l.scale = Vector3.ONE * 0.2
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.1)
	tw.parallel().tween_property(l, "position", l.position + Vector3(0, 0.35, 0), life).set_trans(Tween.TRANS_SINE)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)
	return l


## One-shot particle burst. kind: "confetti", "feathers", "crumbs", "peas", "dust", "stars", "jelly", "wool", "rubble".
static func burst(parent: Node, pos: Vector3, kind: String, colors: Array, amount: int = 28, speed: float = 5.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for c in colors:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = maxi(4, int(amount / maxi(1, colors.size())))
		p.lifetime = 1.1
		p.explosiveness = 0.95
		p.direction = Vector3.UP
		p.spread = 80.0
		p.initial_velocity_min = speed * 0.5
		p.initial_velocity_max = speed
		p.gravity = Vector3(0, -12, 0)
		p.angular_velocity_min = -360
		p.angular_velocity_max = 360
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.3
		p.damping_min = 0.5
		p.damping_max = 2.0
		var mesh: Mesh
		match kind:
			"feathers", "confetti":
				var q := QuadMesh.new()
				q.size = Vector2(0.09, 0.18) if kind == "feathers" else Vector2(0.08, 0.08)
				mesh = q
				p.gravity = Vector3(0, -3.5, 0)
				p.damping_min = 3.0
				p.damping_max = 5.0
				p.lifetime = 1.8
				p.particle_flag_rotate_y = true
			"crumbs":
				# Faceted cookie nuggets (a squat 5-sided low-poly lump, randomly scaled per particle): not cubes (r1
				# animation) and not flat wedges, which read as paper confetti triangles from most angles (fix r2).
				var pr := SphereMesh.new()
				pr.radius = 0.055
				pr.height = 0.072
				pr.radial_segments = 5
				pr.rings = 3
				mesh = pr
				p.scale_amount_min = 0.5
				p.scale_amount_max = 1.5
			"rubble":
				var b := BoxMesh.new()
				b.size = Vector3(0.25, 0.2, 0.25)
				mesh = b
			"wool":
				# Fleece tufts: squashed cream puffs that spin, drift and hang in the air with drag (r1 animation: the
				# rip threw hard-shadowed spheres that read as bubbles).
				var wm := SphereMesh.new()
				wm.radius = 0.09
				wm.height = 0.12
				wm.radial_segments = 12
				wm.rings = 6
				mesh = wm
				p.gravity = Vector3(0, -2.2, 0)
				p.damping_min = 4.0
				p.damping_max = 7.0
				p.lifetime = 1.3
				p.spread = 70.0
				p.scale_amount_min = 0.6
				p.scale_amount_max = 1.6
				var wc := Curve.new()
				wc.add_point(Vector2(0, 0.7))
				wc.add_point(Vector2(0.15, 1.0))
				wc.add_point(Vector2(0.75, 0.9))
				wc.add_point(Vector2(1, 0.0))
				p.scale_amount_curve = wc
			"jelly":
				# Jelly droplets: flattened blobs that splat wider as they fall (gummy melt).
				var jm := SphereMesh.new()
				jm.radius = 0.075
				jm.height = 0.09
				jm.radial_segments = 8
				jm.rings = 4
				mesh = jm
				p.scale_amount_min = 0.5
				p.scale_amount_max = 1.4
				var jc := Curve.new()
				jc.add_point(Vector2(0, 1.0))
				jc.add_point(Vector2(0.7, 1.15))
				jc.add_point(Vector2(1, 0.0))
				p.scale_amount_curve = jc
			"dust":
				var sd := SphereMesh.new()
				sd.radius = 0.16
				sd.height = 0.32
				mesh = sd
				p.gravity = Vector3(0, 1.0, 0)
				p.spread = 180.0
				p.damping_min = 6.0
				p.damping_max = 9.0
				p.lifetime = 0.7
				var curve := Curve.new()
				curve.add_point(Vector2(0, 0.6))
				curve.add_point(Vector2(0.3, 1.0))
				curve.add_point(Vector2(1, 0.0))
				p.scale_amount_curve = curve
			"stars":
				# Billboard cartoon stars with an ink rim (prisms read as triangle confetti, impl3 bonk frames).
				var sq := QuadMesh.new()
				sq.size = Vector2(0.2, 0.2)
				mesh = sq
				p.gravity = Vector3(0, -4, 0)
			_:
				var sp := SphereMesh.new()
				sp.radius = 0.07 if kind != "peas" else 0.09
				sp.height = sp.radius * 2.0
				sp.radial_segments = 12
				sp.rings = 6
				mesh = sp
		p.mesh = mesh
		var m: StandardMaterial3D = mat(c as Color, 0.5, 0.2)
		if kind == "dust":
			# Soft dust: callers pass a lower alpha for puffs that must not hide legs (r1: opaque balls read as rocks).
			m = mat(Color(c.r, c.g, c.b, minf((c as Color).a, 0.85)), 1.0, 0.0)
			if (c as Color).a < 0.99:
				p.lifetime = 0.4
		if kind == "feathers" or kind == "confetti":
			m = unshaded(c as Color)
		if kind == "wool":
			# Soft, no hard shadows, a little self-lit so the cream never turns blue-grey in shade.
			m = mat(c as Color, 1.0, 0.6)
			m.emission_enabled = true
			m.emission = (c as Color) * 0.35
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind == "jelly":
			m = mat(c as Color, 0.12, 0.6)
			m.emission_enabled = true
			m.emission = (c as Color) * 0.25
		if kind == "crumbs":
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.material_override = m
		if kind == "stars":
			p.material_override = star_mat(c as Color)
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind == "feathers":
			# Leaf-shaped feather with a pale quill (a plain quad read as a dark rectangle, impl3 crow reel).
			p.material_override = feather_mat(c as Color)
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(p)
		p.global_position = pos
		p.emitting = true
		p.finished.connect(p.queue_free)
## Cartoon "poof" cloud: a few white puff balls that swell and fade.
static func poof(parent: Node, pos: Vector3, scale_mult: float = 1.0, color: Color = Color(1, 1, 1)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	for i in 9:
		var a := TAU * float(i) / 9.0
		var off := Vector3(cos(a), 0.3 * sin(a * 2.0), sin(a)) * 0.45 * scale_mult
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 1.0
		m.rim_enabled = true
		m.rim = 0.6
		var b := ball(root, 0.32 * scale_mult, color, off * 0.3)
		b.material_override = m
		b.scale = Vector3.ONE * 0.3
		var tw := b.create_tween()
		tw.set_parallel(true)
		tw.tween_property(b, "scale", Vector3.ONE * randf_range(1.0, 1.5), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "position", off + Vector3(0, 0.25, 0), 0.5).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.45).set_delay(0.3)
	parent.get_tree().create_timer(1.0).timeout.connect(root.queue_free)


## A flat ring on the ground that grows and fades (stomp rings, landing telegraphs).
static func ground_ring(parent: Node, pos: Vector3, radius: float, color: Color, life: float = 0.5) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var r := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.85
	t.outer_radius = 1.0
	t.rings = 48
	t.ring_segments = 6
	r.mesh = t
	var m := unshaded(color).duplicate() as StandardMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r.material_override = m
	parent.add_child(r)
	r.global_position = pos + Vector3(0, 0.05, 0)
	r.scale = Vector3(radius * 0.2, 0.15, radius * 0.2)
	var tw := r.create_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "scale", Vector3(radius, 0.15, radius), life).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(r.queue_free)
	return r


# ---------------------------------------------------------------- autoload bridges

static func _autoload(tree: SceneTree, n: String) -> Node:
	if tree == null:
		return null
	return tree.root.get_node_or_null(n)


## Enemy sound keys -> [key, pitch, volume_db] candidates. The first key the Audio bank has wins, so
## dedicated takes replace the stand-ins automatically when the audio track adds them.
const SFX_ALIASES := {
	"enemy_windup": [["enemy_windup", 1.0, 0.0], ["gust_whoosh", 1.55, -7.0]],
	"enemy_block": [["enemy_block", 1.0, 0.0], ["wall_kick", 1.35, -1.0]],
	"enemy_bonk": [["enemy_bonk", 1.0, 0.0], ["land_heavy", 1.3, 0.0]],
	"enemy_skid": [["enemy_skid", 1.0, 0.0], ["skid", 0.95, 0.0]],
	"enemy_land": [["enemy_land", 1.0, 0.0], ["land", 0.85, -3.0]],
	"enemy_step": [["enemy_step", 1.0, 0.0], ["footstep_grass", 1.25, -10.0]],
	"enemy_flap": [["enemy_flap", 1.0, 0.0], ["cloud_puff", 1.9, -14.0]],
	"enemy_hurt": [["enemy_hurt", 1.0, 0.0], ["enemy_hit", 1.25, -3.0]],
	"enemy_defeat_poof": [["enemy_defeat_poof", 1.0, 0.0]],
	"wolf_growl": [["wolf_growl", 1.0, 0.0], ["wolf_cub_baa", 0.55, 0.0]],
	"wolf_cub_growl": [["wolf_cub_growl", 1.0, 0.0], ["wolf_growl", 1.15, 0.0]],
	"crow_hurt": [["crow_hurt", 1.0, 0.0], ["crow_caw", 1.4, -2.0]],
	"wolf_cub_yelp": [["wolf_cub_yelp", 1.0, 0.0], ["wolf_cub_baa", 1.7, 0.0]],
	"wolf_charge": [["wolf_charge", 1.0, 0.0], ["gust_whoosh", 1.15, -2.0]],
	"costume_rip": [["costume_rip", 1.0, 0.0], ["cloud_puff", 0.8, 2.0]],
	"crow_dive": [["crow_dive", 1.0, 0.0], ["crow_swoop", 1.0, 0.0]],
	"crow_steal": [["crow_steal", 1.0, 0.0], ["acorn_collect", 0.75, 0.0]],
	"crow_cackle": [["crow_cackle", 1.0, 0.0], ["crow_caw", 1.25, -2.0]],
	"pea_inhale": [["pea_inhale", 1.0, 0.0], ["gust_whoosh", 2.1, -9.0]],
	"pea_splat": [["pea_splat", 1.0, 0.0], ["splash", 1.9, -7.0]],
	"pea_pop": [["pea_pop", 1.0, 0.0]],
	"bee_charge": [["bee_charge", 1.0, 0.0], ["dive", 1.35, 0.0]],
	"bee_down": [["bee_down", 1.0, 0.0], ["land", 1.35, 0.0]],
	"gingerbread_march": [["gingerbread_march", 1.0, 0.0], ["footstep_wood", 1.35, -6.0]],
	"gingerbread_halt": [["gingerbread_halt", 1.0, 0.0], ["footstep_wood", 0.85, -1.0]],
	"lance_ready": [["lance_ready", 1.0, 0.0], ["switch_press", 1.25, -2.0]],
	"lance_thrust": [["lance_thrust", 1.0, 0.0], ["kick", 1.2, 0.0]],
	"gummy_jump": [["gummy_jump", 1.0, 0.0], ["gumdrop_bounce", 0.6, 0.0]],
	"gummy_slam": [["gummy_slam", 1.0, 0.0], ["land_heavy", 0.7, 2.0]],
	"gummy_boing": [["gummy_boing", 1.0, 0.0], ["gumdrop_bounce", 0.95, 0.0]],
	"gummy_melt": [["gummy_melt", 1.0, 0.0], ["gummy_wobble", 0.6, 0.0]],
}


## Plays an enemy sound through the Audio autoload, resolving SFX_ALIASES; pitch multiplies the bank pitch.
static func sfx(node: Node, key: String, at: Vector3 = Vector3.INF, pitch: float = 1.0, volume_db: float = 0.0) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	var a := _autoload(node.get_tree(), "Audio")
	if a == null or not a.has_method("play_sfx"):
		if OS.is_debug_build() and node.get_tree().root.has_meta("enemy_sfx_log"):
			print("[sfx] ", key)
		return null
	var use_key := key
	var p := pitch
	var v := volume_db
	if a.has_method("has_key"):
		var cands: Array = SFX_ALIASES.get(key, [[key, 1.0, 0.0]])
		use_key = ""
		for c in cands:
			if bool(a.call("has_key", String(c[0]))):
				use_key = String(c[0])
				p = pitch * float(c[1])
				v = volume_db + float(c[2])
				break
		if use_key == "":
			use_key = key
	var pl: Variant = a.call("play_sfx", use_key, at, 0.07, v)
	if pl is Node and absf(p - 1.0) > 0.001:
		(pl as Node).set("pitch_scale", maxf(0.05, float((pl as Node).get("pitch_scale")) * p))
	return pl as Node


## Semantic feedback event for the Juice autoload (Docs/JUICE.md). Params always carry the family id.
static func juice(node: Node, event_name: String, pos: Vector3 = Vector3.INF, params: Dictionary = {}) -> void:
	if node == null or not node.is_inside_tree():
		return
	var j := _autoload(node.get_tree(), "Juice")
	if j != null and j.has_method("event"):
		j.call("event", event_name, pos, params)


## True when the Juice table (Docs/JUICE.md) has data for the event, so it already plays that moment's
## effect, sound, shake and hitstop; callers then skip their own fallback spawn or sound.
static func juice_owns(node: Node, event_name: String) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var j := _autoload(node.get_tree(), "Juice")
	return j != null and j.has_method("has_event") and bool(j.call("has_event", event_name))


## Uniformly scales an imported model so its visual height is h metres (props carried by enemies).
static func fit_height(n: Node3D, h: float) -> void:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var bb := m.get_aabb()
		var xf := n.global_transform.affine_inverse() * m.global_transform if n.is_inside_tree() else m.transform
		bb = xf * bb
		box = bb if first else box.merge(bb)
		first = false
	if not first and box.size.y > 0.001:
		n.scale = Vector3.ONE * (h / box.size.y)


## True when the Juice table plays this channel ("vfx", "sfx", "shake", "hitstop") for the event.
static func juice_handles(node: Node, event_name: String, channel: String) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var j := _autoload(node.get_tree(), "Juice")
	if j == null:
		return false
	if j.has_method("handles"):
		return bool(j.call("handles", event_name, channel))
	return j.has_method("has_event") and bool(j.call("has_event", event_name))


## True only when the audio track's JuiceSfx will really voice the event. Its "owns" hand-off stays silent until
## Juice exposes owns(); until then enemies play their own sounds and mark their Juice events silent.
static func juice_sfx_owns(node: Node, event_name: String) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var s := node.get_tree().root.get_node_or_null("Juice/JuiceSfx")
	return s != null and s.has_method("has_event") and bool(s.call("has_event", event_name))


## Spawns one of the vfx track's effect scenes (res://scenes/fx/<scene_name>.tscn) under parent.
## Returns null when the scene is missing so callers can fall back to burst().
static func fx(parent: Node, scene_name: String, pos: Vector3, intensity: float = 1.0, tint: Color = Color(1, 1, 1, 1)) -> Node3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var path := "res://scenes/fx/%s.tscn" % scene_name
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var n := packed.instantiate() as Node3D
	if n == null:
		return null
	if "autoplay" in n:
		n.set("autoplay", false)
	if "intensity" in n:
		n.set("intensity", intensity)
	if "tint" in n:
		n.set("tint", tint)
	parent.add_child(n)
	n.global_position = pos
	if n.has_method("play"):
		n.call("play")
	return n


## Spawns a VFX-track particle preset by name (FxPresets / fx_presets_juice.gd, e.g. "wool_burst") at pos.
## Used for family gags that are not a Juice event of their own (the wolf's costume rip). Returns null if missing.
static func preset(parent: Node, preset_name: String, pos: Vector3, intensity: float = 1.0, tint: Color = Color(1, 1, 1, 1), size: float = 1.0) -> Node3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var fx := FxEffect.new()
	fx.preset = preset_name
	fx.autoplay = false
	fx.intensity = intensity
	fx.tint = tint
	parent.add_child(fx)
	fx.global_position = pos
	if absf(size - 1.0) > 0.001:
		fx.fx_scale = size
	fx.play()
	return fx


static func voice(node: Node, key: String) -> void:
	if node == null or not node.is_inside_tree():
		return
	var a := _autoload(node.get_tree(), "Audio")
	if a != null and a.has_method("play_voice"):
		a.call("play_voice", key)
	elif a != null and a.has_method("play_sfx"):
		a.call("play_sfx", key)


static func game_call(node: Node, method: String, args: Array = []) -> Variant:
	if node == null or not node.is_inside_tree():
		return null
	var g := _autoload(node.get_tree(), "Game")
	if g != null and g.has_method(method):
		return g.callv(method, args)
	return null


static func game_get(node: Node, prop: String, default_value: Variant = null) -> Variant:
	if node == null or not node.is_inside_tree():
		return default_value
	var g := _autoload(node.get_tree(), "Game")
	if g == null:
		return default_value
	var v: Variant = g.get(prop)
	return default_value if v == null else v


static func find_player(tree: SceneTree) -> Node3D:
	if tree == null:
		return null
	return tree.get_first_node_in_group("player") as Node3D


## Spawns n acorns at pos: the objects workstream's Acorn scene when present, else a local stand-in.
static func drop_acorns(parent: Node, pos: Vector3, n: int) -> void:
	if parent == null or not parent.is_inside_tree() or n <= 0:
		return
	var scene: PackedScene = null
	for path in ["res://scenes/objects/Acorn.tscn", "res://scenes/objects/acorn.tscn"]:
		if ResourceLoader.exists(path):
			scene = load(path) as PackedScene
			break
	for i in n:
		var node: Node3D
		if scene != null:
			node = scene.instantiate() as Node3D
		else:
			node = (load("res://scripts/enemies/acorn_drop.gd") as GDScript).new() as Node3D
		parent.add_child(node)
		var a := TAU * float(i) / float(n) + randf() * 0.5
		node.global_position = pos + Vector3(cos(a) * 0.3, 0.6, sin(a) * 0.3)
		var v := Vector3(cos(a) * 2.2, 5.5, sin(a) * 2.2)
		if node.has_method("pop_out"):
			node.call("pop_out", v)
		elif node.has_method("launch"):
			node.call("launch", v)


# ---------------------------------------------------------------- telegraphs

## A pulsing flat disc on the ground (landing spots, slam zones). Caller frees it.
static func ground_disc(parent: Node, pos: Vector3, radius: float, color: Color = Color(1, 0.35, 0.15, 0.55)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.02
	c.radial_segments = 40
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.04, 0)
	var tw := mi.create_tween().set_loops()
	tw.tween_property(mi, "scale", Vector3(1.12, 1, 1.12), 0.18)
	tw.tween_property(mi, "scale", Vector3(0.92, 1, 0.92), 0.18)
	return mi


## A flat arrow strip on the ground from pos along dir (charge lines). Caller frees it.
static func ground_strip(parent: Node, pos: Vector3, dir: Vector3, length: float, width: float, color: Color = Color(1, 0.3, 0.12, 0.45)) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos + Vector3(0, 0.05, 0)
	dir.y = 0
	if dir.length() > 0.001:
		root.rotation.y = atan2(-dir.x, -dir.z)
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(width, 0.02, length)
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0, -length * 0.5)
	root.add_child(mi)
	var head := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(width * 2.0, width * 1.6, 0.02)
	head.mesh = pm
	head.material_override = m
	head.rotation_degrees = Vector3(-90, 0, 0)
	head.position = Vector3(0, 0, -length - width * 0.7)
	root.add_child(head)
	mi.scale = Vector3(1, 1, 0.05)
	var tw := root.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.35).set_ease(Tween.EASE_OUT)
	return root


static func fade_free(node: Node3D, t: float = 0.2) -> void:
	if node == null or not is_instance_valid(node):
		return
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3(node.scale.x, node.scale.y * 0.1, node.scale.z), t)
	tw.tween_callback(node.queue_free)


# ---------------------------------------------------------------- attack tokens (fix round 1)

## Active attack tokens: enemy instance id -> {"kind": "melee"|"volley", "node": enemy, "until": msec}.
static var _tokens: Dictionary = {}
const TOKEN_LIMIT := 2
const TOKEN_RADIUS := 14.0


## At most TOKEN_LIMIT melee wind-ups and TOKEN_LIMIT projectile volleys near Mak at once (r1 fun: whole squads
## and crow pairs struck on the same frame). Enemies far from Mak never compete for a slot.
static func request_attack(enemy: Node3D, kind: String = "melee") -> bool:
	if enemy == null or not enemy.is_inside_tree():
		return false
	var now := Time.get_ticks_msec()
	var id := enemy.get_instance_id()
	for k in _tokens.keys():
		var tk: Dictionary = _tokens[k]
		if not is_instance_valid(tk["node"]) or int(tk["until"]) < now:
			_tokens.erase(k)
	if _tokens.has(id):
		_tokens[id]["until"] = now + 4000
		return true
	var pl := find_player(enemy.get_tree())
	if pl == null or enemy.global_position.distance_to(pl.global_position) > TOKEN_RADIUS:
		_tokens[id] = {"kind": kind, "node": enemy, "until": now + 4000}
		return true
	var n := 0
	for k in _tokens.keys():
		var tk: Dictionary = _tokens[k]
		if String(tk["kind"]) == kind and (tk["node"] as Node3D).global_position.distance_to(pl.global_position) <= TOKEN_RADIUS:
			n += 1
	if n >= TOKEN_LIMIT:
		return false
	_tokens[id] = {"kind": kind, "node": enemy, "until": now + 4000}
	return true


static func release_attack(enemy: Node) -> void:
	if enemy != null:
		_tokens.erase(enemy.get_instance_id())


## The real generated teacup (W2 giant teacup prop) scaled to height h, toon-shaded; null if the asset is missing.
static func teacup(h: float) -> Node3D:
	var path := "res://assets/props/w2/giant_teacup/giant_teacup.glb"
	if not ResourceLoader.exists(path):
		return null
	var holder := Node3D.new()
	var m := (load(path) as PackedScene).instantiate() as Node3D
	holder.add_child(m)
	fit_height(m, h)
	FxToon.apply(m, {"rim": 0.45, "outline_width": 1.0})
	return holder

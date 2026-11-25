class_name MakRigFix
extends RefCounted
## Runtime fixes for the rigged Tripo P2 Mr. Mak (res://assets/characters/mak/mak_v2.glb), applied by the
## player when the model loads. Nothing in game/assets is modified.
##  1. Ear weights: the generated skin lets ear_l / ear_r pull most of the face (2,100+ front-face vertices,
##     up to 0.85 weight), so ear springs dragged the brows and eyes. Ear influence is kept only on the ear
##     flaps (measured along each ear bone's axis) and the removed weight goes to `head`.
##  2. Eyelids: the model has no blend shapes, so two skin-coloured lid shells ride on the head bone. Each
##     lid is a sphere fitted to the eye surface (least squares on a front ray-cast of the mesh, +9 mm) whose
##     visible band is cut by `close` (0 open, 1 shut) and tilted by `tilt` for expressions.

const EYE_CENTERS := [Vector3(0.1063, 0.8326, 0.1742), Vector3(-0.1032, 0.8337, 0.172)]  ## model space (+Z forward)
const LID_RADIUS := 0.084
const OPEN_EDGE := 1.08     ## rad, lid edge elevation (above the eye) when open
const SHUT_EDGE := -0.74    ## rad, lid edge elevation (below the eye) when shut
const SKIN := Color(0.96, 0.82, 0.73)
const LASH := Color(0.353, 0.208, 0.125)   ## #5A3520

static var _fixed_meshes := {}

const LID_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_disabled;
#include "res://assets/shaders/inc/stylized_light.gdshaderinc"
uniform vec4 skin : source_color = vec4(0.97, 0.82, 0.69, 1.0);
uniform vec4 lash : source_color = vec4(0.353, 0.208, 0.125, 1.0);
uniform float close_amount = 0.0;
uniform float open_edge = 1.08;
uniform float shut_edge = -0.74;
uniform float meet_edge = -0.3;
uniform float tilt = 0.0;
uniform float side = 1.0;
// Same toon ramp as the hero body (FxToon defaults tuned in MakPlayer._tune_toon).
uniform float ramp_threshold = 0.05;
uniform float ramp_softness = 0.18;
uniform vec4 shadow_tint : source_color = vec4(0.82, 0.7, 0.72, 1.0);   // MakPlayer.HERO_SHADE
uniform float spec_strength = 0.0;
uniform float spec_size = 0.6;
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
void fragment() {
	// Elevation of this point around the eye's X axis (0 = straight forward, +90 deg = up).
	float c = cos(tilt * side);
	float s = sin(tilt * side);
	vec3 q = vec3(c * lp.x - s * lp.y, s * lp.x + c * lp.y, lp.z);
	float ang = atan(q.y, q.z);
	float cl = clamp(close_amount, 0.0, 1.0);
	// The upper lid comes down to just below the eye's middle and a small lower lid rises to meet it, so a shut eye
	// is a curved lash line across the eye (it used to be one blank disc with the lash hidden under the eye).
	float edge = mix(open_edge, meet_edge, cl);
	float low_edge = mix(-1.7, meet_edge - 0.02, smoothstep(0.35, 1.0, cl));
	bool lower = ang < low_edge;
	if ((ang < edge && !lower) || lp.z < -0.03) {
		discard;
	}
	// Fix r2 (visual major M1): a lit lid with a real lash crescent. The lash line thickens as the lid closes
	// (about 0.06 rad when shut, #5A3520) and is darkest in the middle of the eye, thinning to the corners.
	float corner = 1.0 - smoothstep(0.035, 0.075, abs(q.x));
	float lash_w = mix(0.03, 0.09, smoothstep(0.55, 1.0, cl)) * mix(0.45, 1.0, corner);
	float band = smoothstep(lash_w * 0.6, lash_w, ang - edge);
	vec3 col = mix(lash.rgb, skin.rgb, band);
	// A soft crease a little above the lash line.
	col *= 1.0 - 0.1 * (1.0 - smoothstep(lash_w + 0.06, lash_w + 0.22, ang - edge)) * band;
	if (lower) {
		// Lower lid: skin, a touch darker toward the lash line.
		col = skin.rgb * (0.9 + 0.1 * smoothstep(0.0, 0.25, low_edge - ang));
	}
	ALBEDO = col;
	ROUGHNESS = 0.8;
}
void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0) * ATTENUATION;
	} else {
		sm_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, ramp_threshold, ramp_softness,
			shadow_tint.rgb, spec_strength, spec_size, DIFFUSE_LIGHT, SPECULAR_LIGHT);
	}
}
"""


static func fix_ear_weights(model: Node, skel: Skeleton3D) -> int:
	var mi := _find_body_mesh(model)
	if mi == null or mi.mesh == null or skel == null:
		return 0
	var key := mi.mesh.resource_path + "#" + str(mi.mesh.get_rid().get_id())
	if _fixed_meshes.has(mi.mesh.resource_path) and mi.mesh.resource_path != "":
		mi.mesh = _fixed_meshes[mi.mesh.resource_path]
		return -1
	var bind_of := {}
	if mi.skin != null:
		for b in mi.skin.get_bind_count():
			var bn := str(mi.skin.get_bind_name(b))
			if bn == "":
				var bi := mi.skin.get_bind_bone(b)
				if bi >= 0:
					bn = skel.get_bone_name(bi)
			bind_of[bn] = b
	else:
		for i in skel.get_bone_count():
			bind_of[skel.get_bone_name(i)] = i
	if not bind_of.has("head") or not bind_of.has("ear_l") or not bind_of.has("ear_r"):
		return 0
	var head_b: int = bind_of["head"]
	var to_model := (skel.global_transform.affine_inverse() * mi.global_transform)
	var ears := []
	for side in ["l", "r"]:
		var e0 := skel.find_bone("ear_" + side)
		var e1 := skel.find_bone("ear_%s_2" % side)
		if e0 < 0 or e1 < 0:
			return 0
		var h := skel.get_bone_global_rest(e0).origin
		var d := (skel.get_bone_global_rest(e1).origin - h).normalized()
		var bset := {}
		bset[bind_of["ear_" + side]] = true
		if bind_of.has("ear_%s_2" % side):
			bset[bind_of["ear_%s_2" % side]] = true
		ears.append({"h": h, "d": d, "binds": bset})
	var src := mi.mesh as ArrayMesh
	if src == null:
		return 0
	var out := ArrayMesh.new()
	var changed := 0
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones_v: Variant = arrays[Mesh.ARRAY_BONES]
		var weights_v: Variant = arrays[Mesh.ARRAY_WEIGHTS]
		if bones_v == null or weights_v == null:
			out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays)
			out.surface_set_material(s, src.surface_get_material(s))
			continue
		var bones: PackedInt32Array = bones_v
		var weights: PackedFloat32Array = weights_v
		var n := verts.size()
		var k := bones.size() / maxi(n, 1)
		for vi in n:
			var p := to_model * verts[vi]
			var moved := 0.0
			var head_slot := -1
			for j in k:
				var bi := bones[vi * k + j]
				var w := weights[vi * k + j]
				if bi == head_b:
					head_slot = j
				if w <= 0.0:
					continue
				for e in ears:
					if (e["binds"] as Dictionary).has(bi):
						var t: float = (p - (e["h"] as Vector3)).dot(e["d"] as Vector3)
						var m := smoothstep(0.015, 0.07, t)
						if p.z > 0.11:
							m = 0.0
						if m < 1.0:
							moved += w * (1.0 - m)
							weights[vi * k + j] = w * m
			if moved <= 0.0:
				continue
			changed += 1
			if head_slot < 0:
				# Reuse the weakest slot for the head.
				var lo := 0
				for j in k:
					if weights[vi * k + j] < weights[vi * k + lo]:
						lo = j
				head_slot = lo
				moved += weights[vi * k + lo]
				bones[vi * k + lo] = head_b
				weights[vi * k + lo] = 0.0
			weights[vi * k + head_slot] += moved
			var sum := 0.0
			for j in k:
				sum += weights[vi * k + j]
			if sum > 0.0:
				for j in k:
					weights[vi * k + j] /= sum
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var flags := 0
		if k == 8:
			flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays, [], {}, flags)
		out.surface_set_material(s, src.surface_get_material(s))
		out.surface_set_name(s, src.surface_get_name(s))
	mi.mesh = out
	if src.resource_path != "":
		_fixed_meshes[src.resource_path] = out
	print("[MakRigFix] ear weights moved to head on %d vertices (%s)" % [changed, key])
	return changed


## Fix r2: the lid colour is sampled from the body's albedo just above each eye (nearest vertex UV, then the texel), so
## the closed lid matches the painted skin under the same lighting. Falls back to SKIN.
static var _lid_skin_cache := {}


static func sample_lid_skin(model: Node) -> Array:
	var out := [SKIN, SKIN]
	var mi := _find_body_mesh(model)
	if mi == null or not (mi.mesh is ArrayMesh):
		return out
	var key := mi.mesh.resource_path
	if key != "" and _lid_skin_cache.has(key):
		return _lid_skin_cache[key]
	out = _sample_lid_skin(mi)
	if key != "":
		_lid_skin_cache[key] = out
	print("[MakRigFix] lid skin sampled %s %s" % [out[0].to_html(false), out[1].to_html(false)])
	return out


static func _sample_lid_skin(mi: MeshInstance3D) -> Array:
	var out := [SKIN, SKIN]
	var tex: Texture2D = null
	var mat := mi.get_active_material(0)
	if mat is ShaderMaterial:
		tex = (mat as ShaderMaterial).get_shader_parameter("albedo_texture") as Texture2D
	elif mat is BaseMaterial3D:
		tex = (mat as BaseMaterial3D).albedo_texture
	if tex == null:
		return out
	var img := tex.get_image()
	if img == null or img.is_empty():
		return out
	if img.is_compressed():
		if img.decompress() != OK:
			return out
	var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if uvs.size() != verts.size():
		return out
	for e in 2:
		var acc := Color(0, 0, 0, 0)
		var n := 0
		for off in [Vector3(0.0, 0.075, 0.012), Vector3(0.025, 0.07, 0.012), Vector3(-0.025, 0.07, 0.012)]:
			var target: Vector3 = (EYE_CENTERS[e] as Vector3) + (off as Vector3)
			var best := -1
			var bd := 1e9
			for vi in verts.size():
				var d := verts[vi].distance_squared_to(target)
				if d < bd:
					bd = d
					best = vi
			if best < 0 or bd > 0.03 * 0.03:
				continue
			var uv := uvs[best]
			var px := Vector2i(clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1), clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1))
			acc += img.get_pixelv(px)
			n += 1
		if n > 0:
			var c := acc / float(n)
			out[e] = Color(c.r, c.g, c.b, 1.0)
	return out


static func add_eyelids(skel: Skeleton3D, skins: Array = []) -> Array[ShaderMaterial]:
	var mats: Array[ShaderMaterial] = []
	var hb := skel.find_bone("head")
	if hb < 0:
		return mats
	var att := BoneAttachment3D.new()
	att.name = "EyelidSocket"
	att.bone_name = "head"
	skel.add_child(att)
	var rest_inv := skel.get_bone_global_rest(hb).affine_inverse()
	var sh := Shader.new()
	sh.code = LID_SHADER
	var mesh := SphereMesh.new()
	mesh.radius = LID_RADIUS
	mesh.height = LID_RADIUS * 2.0
	mesh.radial_segments = 40
	mesh.rings = 24
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.name = "Eyelid_" + ("L" if i == 0 else "R")
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("skin", skins[i] if skins.size() == 2 else SKIN)
		m.set_shader_parameter("lash", LASH)
		m.set_shader_parameter("open_edge", OPEN_EDGE)
		m.set_shader_parameter("shut_edge", SHUT_EDGE)
		m.set_shader_parameter("side", 1.0 if i == 0 else -1.0)
		mi.material_override = m
		att.add_child(mi)
		mi.transform = rest_inv * Transform3D(Basis.IDENTITY, EYE_CENTERS[i])
		mi.visible = false
		mats.append(m)
	return mats


static func _find_body_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and str(n.name).to_lower().contains("body") and (n as MeshInstance3D).skin != null:
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_body_mesh(c)
		if r != null:
			return r
	if n is MeshInstance3D and str(n.name).to_lower().contains("body"):
		return n as MeshInstance3D
	return null


## The v2 beanie's colour map averages #7C7C8A (spec #8E949B); under the blue skies it reads blue-violet.
## A gentle warm lift on a duplicated material brings it back to the approved knitted grey.
static func tint_beanie(model: Node, mult: Color = Color(1.16, 1.12, 1.03)) -> void:
	for mi in _meshes_named(model, "beanie"):
		for si in mi.mesh.get_surface_count():
			var m := mi.get_active_material(si) as BaseMaterial3D
			if m == null:
				continue
			var d := m.duplicate() as BaseMaterial3D
			d.albedo_color = Color(m.albedo_color.r * mult.r, m.albedo_color.g * mult.g, m.albedo_color.b * mult.b, m.albedo_color.a)
			mi.set_surface_override_material(si, d)


static func _meshes_named(n: Node, key: String) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and str(n.name).to_lower().contains(key) and (n as MeshInstance3D).mesh != null:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(_meshes_named(c, key))
	return out


## Fix r2 (visual minor m2): the generated tail is a flat forked ribbon. Its bones are scaled to nothing (the wire
## collapses into the rump) and a procedural curly tail takes its place: a 1.5-turn tapered helix tube (coil radius
## 3.5 cm, tube radius 1.8 cm at the root, hero pink #F29AA3, toon shaded) on a hips attachment at the tail root.
## MakAnimator swings its pivot with the existing tail spring. Returns the pivot (or null when the rig has no tail).
static func add_curly_tail(skel: Skeleton3D) -> Node3D:
	var tb := skel.find_bone("tail")
	var hb := skel.find_bone("hips")
	if tb < 0 or hb < 0:
		return null
	skel.set_bone_pose_scale(tb, Vector3.ONE * 0.001)
	var att := BoneAttachment3D.new()
	att.name = "CurlyTailSocket"
	att.bone_name = "hips"
	skel.add_child(att)
	var base := skel.get_bone_global_rest(hb).affine_inverse() * skel.get_bone_global_rest(tb)
	var pivot := Node3D.new()
	pivot.name = "CurlyTail"
	pivot.transform = Transform3D(base.basis.orthonormalized(), base.origin)
	att.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.name = "CurlyTailMesh"
	mi.mesh = _helix_mesh(1.5, 0.035, 0.018, 0.075, 64, 10)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.949, 0.604, 0.639)
	m.roughness = 0.8
	mi.material_override = null
	mi.set_surface_override_material(0, m)
	pivot.add_child(mi)
	var fx := load("res://scripts/fx/fx_toon.gd")
	if fx != null:
		fx.call("apply", mi, {"rim": 0.35, "outline_width": 1.4, "spec": 0.1, "shadow_tint": Color(0.82, 0.62, 0.68)})
	return pivot


## Tube along a helix around +Y (bone axis): `turns` turns, coil radius rc, tube radius rt tapering to 40 %, height h.
static func _helix_mesh(turns: float, rc: float, rt: float, h: float, segs: int, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var u := float(i) / float(segs)
		var a := u * turns * TAU
		# The coil starts on the axis at the rump (a short stem), then opens into the spiral.
		var open := smoothstep(0.0, 0.18, u)
		pts.append(Vector3(cos(a) * rc * open, u * h, sin(a) * rc * open))
	var rings: Array = []
	for i in pts.size():
		var tng := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := tng.cross(Vector3.UP if absf(tng.y) < 0.95 else Vector3.RIGHT).normalized()
		var bin := tng.cross(nrm).normalized()
		var u := float(i) / float(segs)
		var r := rt * lerpf(1.0, 0.4, u)
		var ring: Array = []
		for k in sides:
			var a := float(k) / float(sides) * TAU
			var n := (nrm * cos(a) + bin * sin(a)).normalized()
			ring.append([pts[i] + n * r, n])
		rings.append(ring)
	for i in rings.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var q := [rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k], rings[i + 1][k2], rings[i][k2]]
			for v in q:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	# Round tip cap.
	var tip: Vector3 = pts[pts.size() - 1]
	var last: Array = rings[rings.size() - 1]
	var tdir := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	for k in sides:
		var k2 := (k + 1) % sides
		st.set_normal(tdir)
		st.add_vertex(tip + tdir * rt * 0.4)
		st.set_normal(last[k2][1])
		st.add_vertex(last[k2][0])
		st.set_normal(last[k][1])
		st.add_vertex(last[k][0])
	return st.commit()


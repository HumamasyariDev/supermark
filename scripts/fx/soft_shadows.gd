class_name SoftShadows
extends RefCounted
## Soft dynamic shadows (owner request 2026-10-19: "light, not hard, ordinary dynamic shadows ... not super realistic,
## dynamic, simple, maybe not very sharp"). Game setting "soft_shadows" (Settings > Display > Shadows: Soft / Off,
## default Soft). RetroLook calls apply_light() for every light of the current scene (scene change, lights added later,
## setting changes); characters, enemies, NPCs and the boss cast through RetroLook's actor list (see actor_cast()).
##
## Soft: every light that the scene authored with shadows keeps them, and the sun gets one soft rule: a wider PCF blur,
## a per-area distance and split count (the near split stays dense for the characters; far splits are in
## the fog anyway). The shadow term already steps into the toon shade band in toon.gdshader / the terrain shaders
## (sm_light: lit *= smoothstep(0.05, 0.6, ATTENUATION), then mix(shadow_tint, 1, lit)), so a cast shadow is the same
## tinted shade as an object's own dark side, never a second black layer.
## Off: every light's shadow is switched off (the classic blob-only look; slower PCs).
## The authored values are kept on the light (meta "ss_orig"), so toggling is lossless.

const META := "ss_orig"
## Sun shadow per area: [max distance m, splits (2 or 4), blur]. The hub's room fits 2 splits over 42 m (QA fix r2).
## Perf pass: 80 m (was 140 m in the worlds; beyond that the fog hides shadows anyway), no blended splits, and a blur
## of 2 on top of the worlds' PCSS (light_angular_distance), which keeps the edge soft without the wide-kernel cost.
const SUN := {
	"HUB": [42.0, 2, 2.0], "W1": [80.0, 4, 2.0], "W2": [80.0, 4, 2.0], "W3": [80.0, 4, 2.0], "BOSS": [70.0, 4, 2.0],
	"": [80.0, 4, 2.0]}
## Grounded blob alpha multiplier while the sun shadow is on (the blob still marks the landing spot in the air).
const BLOB_GROUND_K := 0.5
## OPUSLOOK: the web renderer (Compatibility) draws each shadow-casting light in a pass of its own and adds it to the
## frame after sRGB encoding, so a lit surface shows S(base) + S(light) where the desktop shows S(base + light). Sunlit
## ground came out 10-15 % brighter than on the desktop while the sky matched, and the earlier fix (a darker global grade)
## dimmed the sky with it. On the web these lights keep WEB_SHADOWED_ENERGY of their energy, which brings the sum back
## to the desktop's for typical values (ambient part 0.02-0.1, light part 0.1-0.6 linear: ideal factor 0.25-0.55).
const WEB_SHADOWED_ENERGY := {"W1": 0.38, "W3": 0.38, "BOSS": 0.45, "": 0.5}
const WEB_SCALED := "ss_web_scaled"


static func enabled_setting(tree: SceneTree) -> bool:
	var game := tree.root.get_node_or_null("Game")
	if game and game.has_method("get_setting"):
		return bool(game.call("get_setting", "soft_shadows", true))
	return true


## Applies the current setting to one light (DirectionalLight3D, OmniLight3D or SpotLight3D).
static func apply_light(l: Light3D, on: bool, world: String) -> void:
	if l == null or not is_instance_valid(l):
		return
	if not l.has_meta(META):
		var o := {"shadow": l.shadow_enabled, "blur": l.shadow_blur}
		if l is DirectionalLight3D:
			var d := l as DirectionalLight3D
			o["dist"] = d.directional_shadow_max_distance
			o["mode"] = d.directional_shadow_mode
		l.set_meta(META, o)
	var orig: Dictionary = l.get_meta(META)
	if not bool(orig["shadow"]):
		return
	if not on:
		l.shadow_enabled = false
		_web_energy(l, false, world)
		return
	l.shadow_enabled = true
	if l is DirectionalLight3D:
		var d := l as DirectionalLight3D
		# Fill lights (sky-only or weak) never cast; only the key sun gets the soft rule.
		if d.sky_mode == DirectionalLight3D.SKY_MODE_SKY_ONLY:
			return
		var cfg: Array = SUN.get(world, SUN[""])
		d.directional_shadow_max_distance = minf(float(orig["dist"]), float(cfg[0])) if float(orig["dist"]) > 0.0 else float(cfg[0])
		d.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(cfg[1]) == 2 \
			else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		d.shadow_blur = maxf(float(orig["blur"]), float(cfg[2]))
	else:
		# Local key lights (hub chandelier, stained-glass spot): a softer edge too.
		l.shadow_blur = maxf(float(orig["blur"]), 2.0)
	_web_energy(l, true, world)


## Web only: scales a shadow-casting light down while its shadow is on (and back when the setting turns it off).
static func _web_energy(l: Light3D, shadowed: bool, world: String) -> void:
	if not OS.has_feature("web") or bool(l.get_meta(WEB_SCALED, false)) == shadowed:
		return
	var k := float(WEB_SHADOWED_ENERGY.get(world, WEB_SHADOWED_ENERGY[""]))
	l.set_meta(WEB_SCALED, shadowed)
	l.light_energy *= k if shadowed else 1.0 / k


## The factor a script multiplies into an energy it sets on a light that SoftShadows has already scaled (1 elsewhere).
static func web_energy(l: Light3D, world: String) -> float:
	if l == null or not bool(l.get_meta(WEB_SCALED, false)):
		return 1.0
	return float(WEB_SHADOWED_ENERGY.get(world, WEB_SHADOWED_ENERGY[""]))


## Every light under `root`.
static func apply_tree(root: Node, on: bool, world: String) -> int:
	if root == null:
		return 0
	var n := 0
	for l in root.find_children("*", "Light3D", true, false):
		apply_light(l as Light3D, on, world)
		n += 1
	return n


## Cast setting for an actor mesh (hero, enemy, boss, NPC) whose authored setting was `orig`.
static func actor_cast(orig: int, on: bool) -> int:
	if not on:
		return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if orig == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else orig

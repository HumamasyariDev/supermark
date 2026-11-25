class_name FxPresetsJuice
extends RefCounted
## Juice-stage presets (night 01, juice track): every gameplay event in juice_vfx.json has a premium
## stylised effect here or in FxPresets. FxPresets.get_preset() falls back to this table.
## Layer dictionaries use the same keys as FxPresets (see make_particles / make_ring / make_arc / make_shock).
## Helpers below build the common layer types so each preset stays readable.

const GOLD := Color(1.0, 0.8, 0.28)
const GOLD_HDR := Color(1.7, 1.3, 0.45)
const DUST := Color(0.98, 0.9, 0.76)
const CREAM := Color(1.0, 0.97, 0.9)
## Juice fix r3: small ground dust is a warm tan, a step darker than the cream puffs, so it reads against both the grass
## and the hero v2's white legs (cream dust merged with his legs from the gameplay camera).
const DUST_TAN := Color(0.88, 0.78, 0.62)
const WHITE_HOT := Color(1.6, 1.55, 1.4)
## Juice fix r4: the storybook ink (#3B2416) and the celebration palette (gold, cream, burgundy, brass).
const INK := Color(0.231, 0.141, 0.086)
const CELEBRATE_GOLD := Color(1.0, 0.788, 0.235)

## Juice fix r4 (VFX art critic r2, surface issue): ground layers are recoloured per surface, one step darker than the
## ground (ART_V2 world colours). Juice appends "@<surface>" to presets flagged `surface` in the catalogue; layers that
## carry "ground": true take these colours (dust crescents, pebbles, the slam splat). "grass" also keeps its flecks.
const SURFACES := {
	"grass": {"dust": Color("#C9A66B"), "pebble": Color("#8F7350"), "splat": Color("#8A6A44")},
	"dirt": {"dust": Color("#B98A55"), "pebble": Color("#7E5A36"), "splat": Color("#7E5A36")},
	"cloud": {"dust": Color("#F6F4FF"), "pebble": Color("#C9C2EE"), "splat": Color("#8C7FC9")},
	"candy": {"dust": Color("#A86F4C"), "pebble": Color("#E58AA0"), "splat": Color("#8A4E36")},
	"jelly": {"dust": Color("#E7A0B2"), "pebble": Color("#D9708C"), "splat": Color("#C2506E")},
	"wood": {"dust": Color("#A88360"), "pebble": Color("#7A5638"), "splat": Color("#6E4A30")},
	"stone": {"dust": Color("#B3A592"), "pebble": Color("#857868"), "splat": Color("#6E6458")},
	"metal": {"dust": Color("#B3A592"), "pebble": Color("#857868"), "splat": Color("#6E6458")},
	"roof": {"dust": Color("#B88068"), "pebble": Color("#8E4A36"), "splat": Color("#7A3E2E")},
}


# ---------------------------------------------------------------- layer helpers

static func puffs(amount: int, col: Color, size: Vector2, vel: Vector2, life: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"tex": "puff", "amount": amount, "lifetime": life, "emit": "sphere", "radius": 0.2, "dir": Vector3(0, 1, 0), "spread": 180.0,
		"vel": vel, "damping": Vector2(4, 6), "size": size, "curve": "puff", "spin": 90.0,
		"colors": [[0.0, col], [0.6, Color(col, col.a * 0.85)], [1.0, Color(col, 0.0)]]}
	d.merge(extra, true)
	return d


static func sparks(amount: int, col: Color, vel: Vector2, life: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"streak": true, "amount": amount, "lifetime": life, "emit": "point", "dir": Vector3(0, 1, 0), "spread": 180.0, "vel": vel,
		"damping": Vector2(6, 9), "size": Vector2(0.05, 0.08), "curve": "shrink", "stretch": 3.0, "taper": 0.9, "add": true,
		"colors": [[0.0, col], [1.0, Color(col, 0.0)]]}
	d.merge(extra, true)
	return d


static func stars(amount: int, vel: Vector2, life: float, extra: Dictionary = {}) -> Dictionary:
	# Juice fix r4: the rounded inked cream star_ink (the airbrushed gold star was the collectible colour plus a banned motif).
	var d := {"tex": "star_ink", "amount": amount, "lifetime": life, "emit": "point", "dir": Vector3(0, 1, 0), "spread": 90.0, "vel": vel,
		"gravity": Vector3(0, -6, 0), "damping": Vector2(2, 4), "size": Vector2(0.16, 0.24), "curve": "pop", "spin": 400.0,
		"colors": [[0.0, CREAM], [0.7, CREAM], [1.0, Color(CREAM, 0.0)]]}
	d.merge(extra, true)
	return d


static func glints(amount: int, radius: float, vel: Vector2, life: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"tex": "sparkle_ink", "amount": amount, "lifetime": life, "emit": "sphere", "radius": radius, "spread": 180.0, "vel": vel,
		"damping": Vector2(2, 4), "size": Vector2(0.14, 0.26), "curve": "pop", "colors": [[0.0, GOLD_HDR], [1.0, Color(GOLD, 0.0)]]}
	d.merge(extra, true)
	return d


static func flash(size: float, col: Color, life: float = 0.2, extra: Dictionary = {}) -> Dictionary:
	var d := {"tex": "soft_dot", "amount": 1, "lifetime": life, "emit": "point", "size": Vector2(size, size), "curve": "pop", "add": true,
		"colors": [[0.0, col], [1.0, Color(col, 0.0)]]}
	d.merge(extra, true)
	return d


static func chunks(amount: int, mesh: String, mesh_size: float, c0: Color, c1: Color, vel: Vector2, extra: Dictionary = {}) -> Dictionary:
	var d := {"mesh": mesh, "mesh_size": mesh_size, "amount": amount, "lifetime": 1.0, "emit": "sphere", "radius": 0.3, "dir": Vector3(0, 1, 0),
		"spread": 60.0, "vel": vel, "gravity": Vector3(0, -18, 0), "size": Vector2(0.6, 1.3), "curve": "late_shrink", "tumble": true,
		"shaded": true, "colors": [[0.0, c0], [1.0, c1]]}
	d.merge(extra, true)
	return d


static func ring(size: float, col: Color, time: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"kind": "ring", "size": size, "time": time, "color": col, "start": 0.15}
	d.merge(extra, true)
	return d


## Juice fix r4 (critic r2: rings read as solid plates): ground rings are thin (0.12), 70% opaque and unbroken.
static func shock(size: float, time: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"kind": "shock", "size": size, "time": time, "thickness": 0.12, "opacity": 0.7, "breakup": 0.0}
	d.merge(extra, true)
	return d


## Effect flash light. Juice fix r1: warm white (not lemon), half the old energy, at most 3 m unless it is a
## scene-scale light (lightning, the boss pop): it lights the hero, not a flat yellow ellipse on the path.
static func light(col: Color, energy: float, rng: float, time: float) -> Dictionary:
	var big := rng >= 10.0
	# Juice fix r3 (D034 restraint): 0.35x energy (was 0.5x); warm light on W1 grass still left a lime-yellow ground disc.
	# The colour leans to a near-neutral warm white: a yellow light on green grass is what reads as lime.
	return {"kind": "light", "color": col.lerp(Color(1.0, 0.96, 0.9), 0.85), "energy": energy * 0.35, "range": rng if big else minf(rng, 3.0),
		"time": minf(time, 0.3)}


static func arc(radius: float, width: float, degrees: float, time: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"kind": "arc", "radius": radius, "width": width, "degrees": degrees, "time": time}
	d.merge(extra, true)
	return d


## Juice fix r1: celebration and pickup glints of our own (no five-point stars). Big inked four-point glints
## (glint_ink) plus small soft sparkles, both with a twinkle scale-pulse.
static func twinkles(amount: int, radius: float, vel: Vector2, life: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"tex": "glint_ink", "amount": amount, "lifetime": life, "emit": "sphere", "radius": radius, "dir": Vector3(0, 1, 0), "spread": 180.0,
		"vel": vel, "damping": Vector2(2.5, 4.0), "size": Vector2(0.16, 0.26), "curve": "twinkle", "spin": 40.0,
		"colors": [[0.0, GOLD_HDR], [0.75, GOLD_HDR], [1.0, Color(GOLD, 0.0)]]}
	d.merge(extra, true)
	return d


## Tiny gold truffle silhouettes (truffle_mini): the game's own collectible motif for the big celebrations.
static func truffle_bits(amount: int, vel: Vector2, life: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"tex": "truffle_mini", "amount": amount, "lifetime": life, "emit": "sphere", "radius": 0.25, "dir": Vector3(0, 1, 0), "spread": 70.0,
		"vel": vel, "gravity": Vector3(0, -6, 0), "damping": Vector2(1.5, 2.5), "size": Vector2(0.14, 0.22), "curve": "pop_long", "spin": 160.0,
		"colors": [[0.0, Color(1.45, 1.1, 0.42)], [0.8, Color(1.45, 1.1, 0.42)], [1.0, Color(1.2, 0.9, 0.35, 0.0)]]}
	d.merge(extra, true)
	return d


## Fluttering gold-leaf flakes (gold_leaf).
static func leaf_flakes(amount: int, vel: Vector2, life: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"tex": "gold_leaf", "flutter": "flip", "amount": amount, "lifetime": life, "emit": "sphere", "radius": 0.3, "dir": Vector3(0, 1, 0),
		"spread": 60.0, "vel": vel, "gravity": Vector3(0, -2.2, 0), "damping": Vector2(1.5, 2.5), "size": Vector2(0.12, 0.2), "curve": "late_shrink",
		"spin": 200.0, "turbulence": 1.5, "colors": [[0.0, Color(1.35, 1.05, 0.45)], [1.0, Color(1.2, 0.92, 0.4)]]}
	d.merge(extra, true)
	return d


## Juice fix r2: the hit impact star (impact_star: 7 irregular spikes, white fill, gold rim, ink outline). Frame 1 at
## 60%, frame 2 at 110%, frames 3-4 erode hollow from the centre (fx_inked.gdshader), gone by frame 5-6. Depth-tested
## (not on_top): the catalogue pulls it 0.25 m toward the camera so the target stays readable around it.
static func impact(size: float, col: Color = Color(1, 1, 1), life: float = 0.1, extra: Dictionary = {}) -> Dictionary:
	var d := {"tex": "impact_star", "amount": 1, "lifetime": life, "emit": "point", "size": Vector2(size, size), "curve": "impact",
		"spin": 1.0, "angle": 25.0, "colors": [[0.0, col], [0.3, col], [1.0, Color(col, 0.0)]]}
	d.merge(extra, true)
	return d


## Juice fix r2: low ground dust (dust_crescent). Spawns 0.12 m up on a small ring, launch directions flattened into the
## ground plane (flat 1.0), heavy drag, upright crescents (small tilt), eroded away by 60% of life. Replaces the
## chest-high cream puff balls on landings, jumps, skids and slams.
static func ground_dust(amount: int, col: Color, size: Vector2, vel: Vector2, life: float, extra: Dictionary = {}) -> Dictionary:
	# The visible bottom of the crescent sits about 0.19 of the sprite below its centre; it is lifted a further 0.08 m so
	# W1's 3D grass (about 0.2 m tall) does not swallow small dust (footsteps and soft landings vanished in the grass).
	var d := {"tex": "dust_crescent", "ground": true, "amount": amount, "lifetime": life, "emit": "ring", "radius": 0.22, "offset": Vector3(0, 0.13 + size.y * 0.22, 0),
		"dir": Vector3(1, 0, 0), "spread": 180.0, "flat": 1.0, "vel": vel, "damping": Vector2(5, 7), "gravity": Vector3(0, 0.15, 0),
		"size": size, "curve": "dust", "angle": 12.0, "spin": 0.0,
		"colors": [[0.0, Color(col, 0.82)], [0.15, Color(col, 0.82)], [0.6, Color(col, 0.0)], [1.0, Color(col, 0.0)]]}
	d.merge(extra, true)
	return d


## Hot-chocolate droplets (cocoa_drop: baked brown with a cream highlight and ink outline), velocity-aligned.
static func cocoa_drops(amount: int, vel: Vector2, life: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"tex": "cocoa_drop", "amount": amount, "lifetime": life, "emit": "ring", "radius": 0.2, "dir": Vector3(0, 1, 0), "spread": 35.0,
		"vel": vel, "gravity": Vector3(0, -14, 0), "size": Vector2(0.12, 0.2), "curve": "late_shrink", "angle": 20.0,
		"colors": [[0.0, Color(1, 1, 1)], [0.7, Color(1, 1, 1)], [1.0, Color(1, 1, 1, 0.0)]]}
	d.merge(extra, true)
	return d


## Cream impact shards (blended streaks, not gold: gold means collectible).
static func shards(amount: int, vel: Vector2, life: float, extra: Dictionary = {}) -> Dictionary:
	var d := sparks(amount, Color(1.0, 0.96, 0.86), vel, life, {"add": false, "size": Vector2(0.07, 0.1), "stretch": 3.5, "taper": 0.6,
		"colors": [[0.0, Color(1.0, 0.96, 0.86)], [0.7, Color(1.0, 0.96, 0.86)], [1.0, Color(1.0, 0.96, 0.86, 0.0)]]})
	d.merge(extra, true)
	return d


## Juice fix r4: a value anchor for gameplay-critical bursts (critic r2, D034 in W3): a 1-2 frame dark ink pop ring
## behind frame 1, so a light burst on light ground still has an edge.
static func ink_pop(size: float, time: float = 0.08, extra: Dictionary = {}) -> Dictionary:
	var d := {"kind": "shock", "size": size, "time": time, "billboard": true, "height": 0.0, "thickness": 0.3, "opacity": 0.8, "breakup": 0.0,
		"ink": 0.0, "color": INK, "glow": INK}
	d.merge(extra, true)
	return d


## Juice fix r4: the warm beat of a ground impact without an effect light (the OmniLight stepped into a 5-6 m bright
## rectangle on the RetroLook terrain): a soft warm ground decal, about 0.25 alpha, 0.15 s. It cannot step or leak.
static func ground_glow(size: float, col: Color = Color(1.0, 0.9, 0.7, 0.25), time: float = 0.15) -> Dictionary:
	return {"kind": "ring", "size": size, "time": time, "color": col, "start": 0.7, "tex": "soft_dot"}


## Juice fix r4: inked crumbs (gingerbread grenadier defeat, crates in W3): 0.1-0.18 m crumb cards with a white icing
## edge and an ink rim, plus two gumdrop buttons; a 1.5 m spread that settles by about 0.7 s.
static func crumbs(amount: int, vel: Vector2, extra: Dictionary = {}) -> Dictionary:
	var d := {"tex": "crumb", "amount": amount, "lifetime": 0.75, "emit": "sphere", "radius": 0.2, "dir": Vector3(0, 1, 0), "spread": 55.0,
		"vel": vel, "gravity": Vector3(0, -14, 0), "damping": Vector2(1.5, 2.5), "size": Vector2(0.1, 0.18), "curve": "late_shrink", "spin": 360.0,
		"colors": [[0.0, Color(1, 1, 1)], [0.8, Color(1, 1, 1)], [1.0, Color(1, 1, 1, 0.0)]]}
	d.merge(extra, true)
	return d


## Builds "<preset>@<surface>": the preset with every "ground" layer recoloured for that surface ("only" lists keep a
## layer on some surfaces, such as grass flecks on grass).
static func surface_variant(def: Dictionary, surf: String) -> Dictionary:
	if def.is_empty():
		return def
	var pal: Dictionary = SURFACES.get(surf, SURFACES["grass"])
	var out := def.duplicate()
	var layers: Array = []
	for layer_v in def.get("layers", []):
		var layer: Dictionary = layer_v
		if layer.has("only") and not (surf in (layer["only"] as Array)):
			continue
		if layer.get("ground", false):
			layer = layer.duplicate()
			if layer.get("kind", "particles") == "ring":
				var rc: Color = pal["splat"]
				layer["color"] = Color(rc.r, rc.g, rc.b, (layer.get("color", Color.WHITE) as Color).a)
			elif layer.has("mesh"):
				var pc: Color = pal["pebble"]
				layer["colors"] = [[0.0, pc], [1.0, pc.darkened(0.12)]]
			elif layer.has("colors"):
				var dc: Color = pal["dust"]
				var stops: Array = []
				for st in layer["colors"]:
					stops.append([st[0], Color(dc.r, dc.g, dc.b, (st[1] as Color).a)])
				layer["colors"] = stops
		layers.append(layer)
	out["layers"] = layers
	return out


# ---------------------------------------------------------------- presets

static func get_preset(name: String) -> Dictionary:
	var at := name.find("@")
	if at > 0:
		return surface_variant(FxPresets.get_preset(name.substr(0, at)), name.substr(at + 1))
	match name:
		# ---------------- movement
		"footstep_dust":
			# r2: three small dust crescents that puff out from the heel and hold for about 8 frames before eroding (the same
			# layer as the soft landing, which reads from the hero camera; a single static crescent vanished in the grass).
			# r3: four tan crescents that spread to both sides of the foot (they sat behind Mak's legs from the gameplay camera).
			return {"one_shot": true, "layers": [ground_dust(4, DUST_TAN, Vector2(0.26, 0.34), Vector2(1.0, 1.5), 0.45, {"radius": 0.22})]}
		"footstep_grass":
			# r2: dust crescents plus two grass blades flicked up.
			return {"one_shot": true, "layers": [
				ground_dust(4, DUST_TAN, Vector2(0.26, 0.34), Vector2(1.0, 1.5), 0.45, {"radius": 0.22}),
				{"tex": "leaf", "flutter": "flip", "only": ["grass"], "amount": 2, "lifetime": 0.5, "emit": "ring", "radius": 0.1, "dir": Vector3(0, 1, 0), "spread": 30.0,
					"vel": Vector2(1.6, 2.4), "gravity": Vector3(0, -8, 0), "size": Vector2(0.12, 0.15), "curve": "late_shrink", "spin": 500.0,
					"colors": [[0.0, Color(0.48, 0.78, 0.3)], [1.0, Color(0.4, 0.68, 0.26)]]},
			]}
		"wade_step":
			# Look polish 2026-10-19: a step in shallow water (Juice swaps it in through WaterWade): a ripple ring on the
			# waterline, a little crown of droplets and a puff of white foam.
			return {"one_shot": true, "layers": [
				{"kind": "ring", "size": 1.1, "time": 0.6, "color": Color(0.92, 0.98, 1.0, 0.8), "start": 0.22},
				{"mesh": "sphere", "mesh_size": 0.05, "amount": 9, "lifetime": 0.45, "emit": "ring", "radius": 0.16, "dir": Vector3(0, 1, 0),
					"spread": 32.0, "vel": Vector2(1.8, 3.0), "gravity": Vector3(0, -15, 0), "size": Vector2(0.6, 1.1), "curve": "late_shrink",
					"colors": [[0.0, Color(0.88, 0.97, 1.0)], [1.0, Color(0.62, 0.86, 1.0)]]},
				{"tex": "puff", "amount": 3, "lifetime": 0.35, "emit": "ring", "radius": 0.15, "dir": Vector3(0, 1, 0), "spread": 50.0,
					"vel": Vector2(0.5, 1.0), "damping": Vector2(3, 4), "size": Vector2(0.2, 0.3), "curve": "puff",
					"colors": [[0.0, Color(1, 1, 1, 0.9)], [1.0, Color(0.9, 0.97, 1.0, 0.0)]]},
			]}
		"wade_land":
			# Landing in shallow water: two rings (the second later and wider), a tall crown of droplets and foam.
			return {"one_shot": true, "layers": [
				{"kind": "ring", "size": 2.0, "time": 0.55, "color": Color(1, 1, 1, 0.9), "start": 0.18},
				{"kind": "ring", "size": 3.0, "time": 0.9, "color": Color(0.85, 0.95, 1.0, 0.6), "start": 0.3},
				{"mesh": "sphere", "mesh_size": 0.07, "amount": 22, "lifetime": 0.75, "emit": "ring", "radius": 0.28, "dir": Vector3(0, 1, 0),
					"spread": 28.0, "vel": Vector2(3.2, 5.5), "gravity": Vector3(0, -16, 0), "size": Vector2(0.6, 1.3), "curve": "late_shrink",
					"colors": [[0.0, Color(0.88, 0.97, 1.0)], [1.0, Color(0.6, 0.86, 1.0)]]},
				{"tex": "puff", "amount": 7, "lifetime": 0.55, "emit": "ring", "radius": 0.3, "dir": Vector3(0, 1, 0), "spread": 60.0,
					"vel": Vector2(0.9, 1.8), "damping": Vector2(3, 4), "size": Vector2(0.32, 0.5), "curve": "puff",
					"colors": [[0.0, Color(1, 1, 1, 0.95)], [1.0, Color(0.9, 0.97, 1.0, 0.0)]]},
			]}
		"footstep_candy":
			return {"one_shot": true, "layers": [
				ground_dust(2, Color(1.0, 0.88, 0.93), Vector2(0.18, 0.24), Vector2(0.6, 1.0), 0.34, {"radius": 0.1}),
				# r4: sugar sprinkles (four-point glints mean a pickup, D034).
				{"tex": "sprinkle", "amount": 4, "lifetime": 0.45, "emit": "ring", "radius": 0.12, "dir": Vector3(0, 1, 0), "spread": 35.0, "vel": Vector2(1.2, 2.0),
					"gravity": Vector3(0, -9, 0), "size": Vector2(0.07, 0.1), "curve": "late_shrink", "spin": 300.0, "palette": "candy"},
			]}
		"footstep_wood":
			return {"one_shot": true, "layers": [ground_dust(3, Color(0.94, 0.88, 0.78), Vector2(0.17, 0.22), Vector2(0.5, 0.9), 0.32, {"radius": 0.1})]}
		"jump_puff":
			# r4 (critic r2: no visible puff at 5 m): the soft-landing tan crescents at 0.7x, pushed off the ground.
			return {"one_shot": true, "layers": [ground_dust(5, DUST_TAN, Vector2(0.24, 0.3), Vector2(1.4, 2.0), 0.4, {"radius": 0.3})]}
		"jump2_burst":
			return {"one_shot": true, "layers": [
				shock(1.8, 0.3, {"opacity": 0.6}),
				ground_dust(7, DUST_TAN, Vector2(0.3, 0.4), Vector2(2.0, 2.8), 0.5),
				glints(6, 0.3, Vector2(0.6, 1.6), 0.5, {"curve": "twinkle", "offset": Vector3(0, 0.5, 0)}),
			]}
		"jump3_burst":
			# r2: ground ring and low dust crescents at the feet; inked gold glints and sparks burst 0.5 m up around Mak.
			return {"one_shot": true, "layers": [
				shock(3.0, 0.3, {"ink": 0.85}),
				ground_dust(8, DUST_TAN, Vector2(0.32, 0.44), Vector2(2.6, 3.6), 0.5),
				twinkles(6, 0.2, Vector2(2.5, 4.0), 0.65, {"spread": 50.0, "size": Vector2(0.26, 0.36), "gravity": Vector3(0, -4, 0), "offset": Vector3(0, 0.5, 0)}),
				glints(8, 0.3, Vector2(1.0, 2.4), 0.55, {"curve": "twinkle", "offset": Vector3(0, 0.5, 0)}),
				sparks(10, Color(1.4, 1.2, 0.7), Vector2(4, 7), 0.35, {"spread": 40.0, "damping": Vector2(7, 9), "offset": Vector3(0, 0.4, 0)}),
			]}
		"spin_trail":
			# Attached to Mak for the triple-jump somersault and the flips: a warm, thicker ribbon of glints and cream wisps.
			return {"one_shot": true, "layers": [
				{"tex": "sparkle_ink", "amount": 34, "lifetime": 0.65, "explosiveness": 0.0, "emit": "sphere_surface", "radius": 0.55, "vel": Vector2(0.05, 0.3),
					"size": Vector2(0.2, 0.32), "curve": "twinkle", "world": true, "colors": [[0.0, Color(1.8, 1.25, 0.5)], [0.6, Color(1.6, 0.95, 0.4)], [1.0, Color(1.2, 0.6, 0.3, 0.0)]]},
				{"tex": "puff", "amount": 18, "lifetime": 0.45, "explosiveness": 0.0, "emit": "sphere_surface", "radius": 0.5, "vel": Vector2(0.1, 0.4), "keep_puff": true,
					"damping": Vector2(2, 3), "size": Vector2(0.16, 0.26), "curve": "shrink", "spin": 90.0, "colors": [[0.0, Color(1, 0.94, 0.8, 0.85)], [1.0, Color(1, 0.88, 0.7, 0.0)]]},
			]}
		"long_jump_streaks":
			# r1: white inked speed lines (blended, not additive, so they stay white on grass instead of pale green).
			return {"one_shot": true, "layers": [
				# r4 (critic r2: faint white hairlines): tan crescents kicked back along the ground and thick tan ground streaks.
				ground_dust(6, DUST_TAN, Vector2(0.3, 0.4), Vector2(2.0, 3.0), 0.45, {"dir": Vector3(0, 0, 1), "spread": 35.0, "radius": 0.2}),
				sparks(10, DUST_TAN, Vector2(6, 9), 0.32, {"emit": "box", "extents": Vector3(0.35, 0.15, 0.1), "dir": Vector3(0, 0, 1), "spread": 5.0, "ground": true,
					"damping": Vector2(4, 6), "size": Vector2(0.12, 0.16), "stretch": 6.0, "offset": Vector3(0, 0.25, 0), "add": false,
					"colors": [[0.0, Color(DUST_TAN, 0.95)], [0.7, Color(DUST_TAN, 0.8)], [1.0, Color(DUST_TAN, 0.0)]]}),
			]}
		"land_heavy":
			# r2: no chest-high puff balls: a ground ring, low dust crescents rolling out and a few rounded tan pebbles.
			return {"one_shot": true, "layers": [
				shock(3.0, 0.3, {"ink": 0.85}),
				ground_dust(8, DUST_TAN, Vector2(0.38, 0.52), Vector2(3.0, 4.2), 0.55),
				chunks(6, "pebble", 0.06, Color(0.78, 0.66, 0.5), Color(0.68, 0.56, 0.42), Vector2(2.5, 4.0), {"lifetime": 0.6, "spread": 45.0, "ground": true}),
			]}
		"land_soft":
			# r2: the most frequent action (hops, short drops, 3-7 m/s) now shows three small dust crescents.
			# r3: five tan crescents, wider ring (the 4 cream ones hid behind the hero's legs at gameplay distance).
			return {"one_shot": true, "layers": [ground_dust(5, DUST_TAN, Vector2(0.3, 0.38), Vector2(1.8, 2.6), 0.45, {"radius": 0.42})]}
		"skid_burst":
			# Local -Z = Mak's travel direction. r2: dust crescents and grass flecks spray forward along the ground.
			return {"one_shot": true, "layers": [
				# r4 (critic r2: nothing readable at 5 m): 8 tan crescents and 3 pebbles, recoloured per surface.
				ground_dust(8, DUST_TAN, Vector2(0.34, 0.44), Vector2(2.4, 3.6), 0.5, {"dir": Vector3(0, 0, -1), "spread": 55.0, "radius": 0.2}),
				chunks(3, "pebble", 0.06, Color(0.78, 0.66, 0.5), Color(0.68, 0.56, 0.42), Vector2(2.5, 3.5), {"lifetime": 0.5, "spread": 30.0, "ground": true,
					"dir": Vector3(0, 0.5, -1), "radius": 0.15}),
				{"tex": "leaf", "flutter": "flip", "only": ["grass"], "amount": 4, "lifetime": 0.45, "emit": "ring", "radius": 0.15, "dir": Vector3(0, 0.6, -1), "spread": 30.0,
					"vel": Vector2(2.0, 3.2), "gravity": Vector3(0, -9, 0), "size": Vector2(0.1, 0.14), "curve": "late_shrink", "spin": 500.0,
					"colors": [[0.0, Color(0.5, 0.78, 0.3)], [1.0, Color(0.42, 0.68, 0.26)]]},
			]}
		"wall_kick_burst":
			# Local +Y = wall normal (Juice align "normal"). r2: the ring sits 0.12 m off the wall (it was inside the brick),
			# an inked impact star slaps the wall and cream shards spray out; the soft-depth puffs that vanished are gone.
			return {"one_shot": true, "layers": [
				shock(2.0, 0.28, {"thickness": 0.14, "height": 0.12, "ink": 0.9}),
				impact(0.6, Color(1, 1, 1), 0.12, {"offset": Vector3(0, 0.18, 0), "on_top": true}),
				shards(8, Vector2(3.5, 5.5), 0.28, {"dir": Vector3(0, 1, 0), "spread": 55.0, "offset": Vector3(0, 0.15, 0)}),
				glints(5, 0.15, Vector2(2.5, 3.5), 0.45, {"spread": 60.0, "curve": "twinkle", "offset": Vector3(0, 0.2, 0)}),
			]}
		"ham_slam_spin":
			# Attached to Mak. Apex (about 0.2 s): an inked glint pop and a tight spiral ring. Then the drop: vertical speed
			# streaks streaming up past him (local space, so they ride with Mak as he falls).
			return {"one_shot": true, "layers": [
				{"tex": "glint_ink", "amount": 1, "lifetime": 0.24, "emit": "point", "size": Vector2(0.75, 0.75), "curve": "bang", "spin": 1.0,
					"local": true, "offset": Vector3(0, 0.75, 0), "colors": [[0.0, GOLD_HDR], [0.8, GOLD_HDR], [1.0, Color(GOLD, 0.0)]]},
				{"kind": "shock", "size": 1.7, "time": 0.22, "billboard": true, "height": 0.6, "thickness": 0.14, "refraction": 0.0, "ink": 0.7,
					"color": Color(1, 0.97, 0.88), "glow": Color(1.0, 0.8, 0.4)},
				glints(10, 0.45, Vector2(0.4, 1.0), 0.35, {"emit": "sphere_surface", "local": true, "orbit": Vector2(2.2, 2.8), "curve": "twinkle"}),
				# Juice fix r3: the drop streaks start when the drop does (slam_spin_time 0.5 s in MovementProfile; they fired at
				# 0.2 s, mid-hover) and live 0.12 s from shoulder height, so no white sticks rise above Mak after the impact.
				{"tex": "speed_line", "amount": 6, "lifetime": 0.1, "explosiveness": 0.0, "emit": "box", "extents": Vector3(0.38, 0.1, 0.38),
					"offset": Vector3(0, 1.0, 0), "dir": Vector3(0, 1, 0), "spread": 0.0, "vel": Vector2(6, 9), "local": true, "delay": 0.5, "add": true,
					"size": Vector2(0.32, 0.45), "curve": "late_shrink", "colors": [[0.0, Color(1, 1, 1, 0.7)], [1.0, Color(1, 1, 1, 0.0)]]},
			]}
		"ham_slam":
			# The signature impact (r2). Frames 1-2: an inked radial splat in the ground colour, a fast thin ring and a slow
			# thick ring, a brief gold flash; low dust crescents and rounded pebbles roll out along the ground; nothing at
			# chest height covers Mak.
			return {"one_shot": true, "layers": [
				# r4: the rounded 8-lobe splat (was 16 saw-tooth spikes: a dirt sun), surface-tinted, gone by 0.5 s; thin rings;
				# a soft warm ground glow instead of the effect light (it stepped into a 5-6 m bright rectangle).
				ring(3.2, Color(0.6, 0.47, 0.33, 0.88), 0.5, {"tex": "splat_ink", "start": 0.6, "ground": true}),
				ground_glow(3.0),
				shock(6.0, 0.28, {"thickness": 0.08, "ink": 0.9}),
				shock(4.0, 0.5, {"thickness": 0.14, "ink": 0.8, "delay": 0.03}),
				ground_dust(8, DUST_TAN, Vector2(0.4, 0.56), Vector2(4.5, 6.5), 0.55, {"radius": 0.45, "damping": Vector2(7, 9)}),
				chunks(8, "pebble", 0.08, Color(0.72, 0.6, 0.44), Color(0.62, 0.5, 0.36), Vector2(4.0, 6.5), {"lifetime": 0.7, "radius": 0.4, "spread": 50.0, "ground": true}),
				twinkles(5, 0.3, Vector2(3, 5), 0.55, {"spread": 70.0, "size": Vector2(0.18, 0.26), "offset": Vector3(0, 0.3, 0)}),
				sparks(14, Color(1.5, 1.25, 0.7), Vector2(6, 10), 0.3, {"emit": "ring", "radius": 0.3, "dir": Vector3(0, 0.25, 0), "spread": 80.0}),
				# r3: a smaller, fainter additive flash (gold added to W1 grass read as a lime disc around the splat).
				flash(1.3, Color(1, 0.88, 0.6, 0.34), 0.07, {"offset": Vector3(0, 0.45, 0)}),
			]}
		"dive_whoosh":
			# Local -Z = dive direction. r2: no billboard bubble ring; additive white speed lines (0.09 m) trail backwards
			# and a short puff of air sinks at the take-off.
			return {"one_shot": true, "layers": [
				# r4: fewer, thicker cream speed lines (0.09 m white hairlines vanished at 5 m).
				sparks(10, Color(1, 0.97, 0.9, 0.95), Vector2(4, 7), 0.34, {"emit": "box", "extents": Vector3(0.4, 0.4, 0.1), "dir": Vector3(0, 0, 1), "spread": 6.0,
					"damping": Vector2(4, 6), "size": Vector2(0.13, 0.16), "stretch": 6.0, "add": false, "offset": Vector3(0, 0.55, 0),
					"colors": [[0.0, Color(1, 0.97, 0.9, 0.95)], [0.6, Color(1, 0.97, 0.9, 0.8)], [1.0, Color(1, 0.97, 0.9, 0.0)]]}),
				{"tex": "wind_curl", "amount": 2, "lifetime": 0.45, "emit": "sphere", "radius": 0.2, "dir": Vector3(0, 0, 1), "spread": 15.0, "vel": Vector2(1.5, 2.2),
					"damping": Vector2(2, 3), "size": Vector2(0.45, 0.6), "curve": "vanish", "spin": 120.0, "offset": Vector3(0, 0.6, 0),
					"colors": [[0.0, Color(1, 1, 1, 0.85)], [1.0, Color(1, 1, 1, 0.0)]]},
				puffs(4, Color(1, 1, 1, 0.8), Vector2(0.2, 0.3), Vector2(0.6, 1.0), 0.25, {"dir": Vector3(0, 0, 1), "spread": 40.0, "gravity": Vector3(0, -1.5, 0)}),
			]}
		"slide_trail":
			# Continuous belly-slide trail; attach to Mak (Juice loop), stop with player_slide_end. r1: denser, rounded grit.
			return {"one_shot": false, "layers": [
				{"tex": "puff", "amount": 30, "lifetime": 0.6, "explosiveness": 0.0, "emit": "sphere", "radius": 0.22, "dir": Vector3(0, 1, 0), "spread": 50.0,
					"vel": Vector2(0.5, 1.4), "gravity": Vector3(0, -0.4, 0), "damping": Vector2(2, 3), "size": Vector2(0.28, 0.44), "curve": "puff", "spin": 50.0,
					"colors": [[0.0, DUST], [0.45, Color(DUST, 0.6)], [1.0, Color(DUST, 0.0)]]},
				{"mesh": "pebble", "mesh_size": 0.035, "amount": 16, "lifetime": 0.5, "explosiveness": 0.0, "emit": "sphere", "radius": 0.15, "dir": Vector3(0, 1, 0),
					"spread": 35.0, "vel": Vector2(1.2, 2.4), "gravity": Vector3(0, -10, 0), "size": Vector2(0.6, 1.2), "curve": "late_shrink", "tumble": true,
					"colors": [[0.0, Color(0.55, 0.72, 0.32)], [1.0, Color(0.45, 0.6, 0.26)]]},
			]}
		"ledge_dust":
			return {"one_shot": true, "layers": [
				puffs(4, DUST, Vector2(0.12, 0.2), Vector2(0.4, 0.9), 0.45, {"emit": "box", "extents": Vector3(0.3, 0.02, 0.05), "dir": Vector3(0, -0.4, 0), "spread": 60.0,
					"gravity": Vector3(0, -1.5, 0)}),
				chunks(4, "box", 0.025, Color(0.62, 0.5, 0.36), Color(0.5, 0.4, 0.28), Vector2(0.4, 1.0), {"lifetime": 0.6, "radius": 0.2, "dir": Vector3(0, -1, 0), "spread": 30.0, "shaded": false}),
			]}
		"respawn_sparkle":
			# r2: gold glints and two fluttering pages only (no light: it drew a lime disc on the ground; no puff).
			return {"one_shot": true, "layers": [
				{"tex": "glint_ink", "amount": 16, "lifetime": 1.0, "explosiveness": 0.5, "emit": "ring", "radius": 0.45, "dir": Vector3(0, 1, 0), "spread": 4.0,
					"vel": Vector2(1.6, 3.2), "damping": Vector2(0.6, 1.0), "size": Vector2(0.2, 0.34), "curve": "twinkle", "spin": 40.0,
					"colors": [[0.0, CREAM], [0.7, CREAM], [1.0, Color(CREAM, 0.0)]]},
				# r4: cream glints (gold means a collectible) and a quicker page flutter: Mak is re-drawn onto the page.
				glints(12, 0.5, Vector2(1.0, 2.6), 0.9, {"emit": "ring", "dir": Vector3(0, 1, 0), "spread": 8.0, "curve": "twinkle",
					"colors": [[0.0, CREAM], [1.0, Color(CREAM, 0.0)]]}),
				{"tex": "page", "flutter": "flip", "amount": 4, "lifetime": 1.3, "emit": "ring", "radius": 0.5, "dir": Vector3(0, 1, 0), "spread": 20.0,
					"vel": Vector2(1.8, 2.6), "gravity": Vector3(0, -1.0, 0), "damping": Vector2(1.0, 1.5), "size": Vector2(0.3, 0.38), "curve": "late_shrink",
					"colors": [[0.0, Color(1, 1, 1)], [1.0, Color(1, 1, 1)]], "spin": 90.0, "turbulence": 1.0},
			]}
		"sniff_puff":
			# r2: three gold scent wisps (wind_curl, 0.35 m, 0.8 alpha) that travel about 0.6 m from the snout, plus a few motes.
			return {"one_shot": true, "layers": [
				{"tex": "wind_curl", "amount": 3, "lifetime": 0.8, "emit": "sphere", "radius": 0.08, "dir": Vector3(0, 0.35, -1), "spread": 25.0, "vel": Vector2(1.1, 1.4),
					"damping": Vector2(0.9, 1.2), "size": Vector2(0.42, 0.5), "curve": "pop", "spin": 90.0,
					"colors": [[0.0, Color(1.3, 1.0, 0.45, 0.0)], [0.2, Color(1.3, 1.0, 0.45, 0.8)], [0.75, Color(1.3, 1.0, 0.45, 0.8)], [1.0, Color(1.3, 1.0, 0.45, 0.0)]]},
				{"tex": "soft_dot", "amount": 6, "lifetime": 0.8, "emit": "sphere", "radius": 0.12, "dir": Vector3(0, 0.5, -1), "spread": 30.0, "vel": Vector2(0.6, 1.2),
					"damping": Vector2(1, 2), "size": Vector2(0.14, 0.22), "curve": "pop", "add": true, "turbulence": 0.6,
					"colors": [[0.0, Color(1.2, 0.95, 0.4, 0.0)], [0.3, Color(1.2, 0.95, 0.4, 0.8)], [1.0, Color(1, 0.8, 0.3, 0.0)]]},
			]}
		# ---------------- combat
		"swish_punch":
			# r2: the arc plus an air pop at the fist (a small inked ring 0.9 m ahead at punch height) and forward speed lines,
			# so the jab reads from behind Mak where the arc is seen edge-on.
			return {"one_shot": true, "layers": [
				# r4 (critic r2: a 1-2 frame thin cream arc at 5 m): 1.3x width, an ink edge, held 4 frames.
				arc(1.3, 1.04, 140.0, 0.27, {"height": 0.75, "tilt": -28.0, "draw": 0.05, "hold": 0.067, "ink": 0.8}),
				{"kind": "shock", "size": 0.8, "time": 0.18, "billboard": true, "offset": Vector3(0.1, 0.8, -0.9), "thickness": 0.16, "opacity": 0.8, "ink": 0.9, "delay": 0.04},
				sparks(6, Color(1.3, 1.25, 1.1), Vector2(4.5, 6.0), 0.2, {"dir": Vector3(0, 0, -1), "spread": 18.0, "offset": Vector3(0, 0.8, -0.5), "stretch": 5.0, "delay": 0.03}),
			]}
		"swish_punch_l":
			return {"one_shot": true, "layers": [
				arc(1.3, 1.04, 140.0, 0.27, {"height": 0.8, "reverse": true, "tilt": 28.0, "draw": 0.05, "hold": 0.067, "ink": 0.8}),
				{"kind": "shock", "size": 0.8, "time": 0.18, "billboard": true, "offset": Vector3(-0.1, 0.85, -0.9), "thickness": 0.16, "opacity": 0.8, "ink": 0.9, "delay": 0.04},
				sparks(6, Color(1.3, 1.25, 1.1), Vector2(4.5, 6.0), 0.2, {"dir": Vector3(0, 0, -1), "spread": 18.0, "offset": Vector3(0, 0.85, -0.5), "stretch": 5.0, "delay": 0.03}),
			]}
		"swish_kick":
			# Spin kick: a full 360-degree smear ring plus a dust kick-up.
			return {"one_shot": true, "layers": [
				arc(1.6, 0.95, 360.0, 0.3, {"height": 0.5, "tilt": -10.0, "draw": 0.08, "hold": 0.067, "edge": Color(1.0, 0.72, 0.35), "ink": 0.8}),
				puffs(7, DUST, Vector2(0.2, 0.3), Vector2(1.6, 2.6), 0.45, {"emit": "ring", "radius": 0.45, "dir": Vector3(0, 0.15, 0), "spread": 80.0}),
			]}
		"swish_jump_kick":
			# r2: tilted 32 degrees (was 62: a flat card from the side and from behind), wider, with an air pop at the foot.
			return {"one_shot": true, "layers": [
				arc(1.6, 1.0, 180.0, 0.28, {"height": 0.55, "tilt": 32.0, "draw": 0.05, "hold": 0.067, "edge": Color(1.0, 0.72, 0.35), "ink": 0.8}),
				{"kind": "shock", "size": 1.0, "time": 0.2, "billboard": true, "offset": Vector3(0, 0.5, -1.0), "thickness": 0.16, "opacity": 0.8, "ink": 0.9, "delay": 0.05},
				sparks(7, Color(1.3, 1.25, 1.1), Vector2(4.5, 6.5), 0.22, {"dir": Vector3(0, -0.2, -1), "spread": 20.0, "offset": Vector3(0, 0.5, -0.6), "stretch": 5.0, "delay": 0.04}),
			]}
		"swish_wolf":
			# Boss paw swipe: big, hazard red-orange edge and inner gradient.
			# Juice fix r3: radius 3.5 m, 1.9 m wide (the 2.9 m arc covered only half the 3.2 m wolf's reach from the gameplay camera).
			return {"one_shot": true, "layers": [arc(3.5, 1.9, 160.0, 0.34, {"height": 1.6, "draw": 0.07, "hold": 0.07, "color": Color(1.0, 0.92, 0.85),
				"edge": Color(1.0, 0.45, 0.28), "inner": Color(0.95, 0.3, 0.2), "ink": 0.75})]}
		"hit_spark":
			# r2: a 0.45 m inked impact star (pops, erodes hollow, gone by frame 5-6) that the catalogue places 0.25 m toward
			# the camera, a small ring and a short flash; only the sparks and glints draw on top of the target.
			return {"one_shot": true, "layers": [
				impact(0.45),
				# r4: a thin ring (0.3 thick read as a glass disc), 70% opaque.
				{"kind": "shock", "size": 0.9, "time": 0.16, "billboard": true, "height": 0.0, "thickness": 0.14, "opacity": 0.75, "ink": 0.9, "breakup": 0.0},
				flash(0.6, Color(1, 1, 0.9, 0.8), 0.06),
				sparks(12, Color(1.6, 1.4, 0.8), Vector2(6, 9), 0.22, {"damping": Vector2(9, 12), "on_top": true}),
				glints(4, 0.1, Vector2(2.5, 4.0), 0.4, {"curve": "twinkle", "on_top": true, "size": Vector2(0.14, 0.22)}),
			]}
		"hit_spark_big":
			# r2: 0.8 m impact star, cream impact shards instead of gold five-point stars (gold means collectible).
			return {"one_shot": true, "layers": [
				# r4: a 1-2 frame ink pop ring behind frame 1 (value anchor: the burst keeps an edge on light W3 ground), and a
				# thin 1.2 m ring (was a 1.7 m, 0.3-thick glass disc).
				ink_pop(1.1, 0.07),
				impact(0.8, Color(1, 1, 1), 0.12),
				{"kind": "shock", "size": 1.2, "time": 0.22, "billboard": true, "height": 0.0, "thickness": 0.14, "opacity": 0.75, "ink": 0.9, "breakup": 0.0},
				flash(1.0, Color(1, 1, 0.9, 0.85), 0.08),
				sparks(18, Color(1.7, 1.4, 0.75), Vector2(8, 13), 0.28, {"damping": Vector2(8, 11), "size": Vector2(0.07, 0.11), "on_top": true}),
				shards(8, Vector2(3.5, 6.0), 0.4, {"gravity": Vector3(0, -8, 0), "damping": Vector2(3, 5)}),
				# r3: no effect light (every defeat lit a 3 m lime disc on the W1 grass; the star and flash carry the beat).
			]}
		"clang":
			# Blocked hit (grenadier lance, metal): cold white-blue sparks and a sharp ring, no stars.
			return {"one_shot": true, "layers": [
				# r4 (critic r2: a pale blue-white soap bubble): a small orange-white impact star, an inked white-orange spark fan
				# and a short flat "tink" ring.
				impact(0.4, Color(1.0, 0.9, 0.72), 0.08),
				{"kind": "shock", "size": 0.9, "time": 0.12, "billboard": true, "height": 0.0, "thickness": 0.1, "opacity": 0.85, "ink": 0.9, "breakup": 0.0,
					"color": Color(1.0, 0.95, 0.85), "glow": Color(1.0, 0.65, 0.3)},
				sparks(12, Color(1.6, 1.15, 0.6), Vector2(5, 9), 0.26, {"gravity": Vector3(0, -14, 0), "damping": Vector2(2, 4), "spread": 55.0, "add": false,
					"size": Vector2(0.06, 0.09), "colors": [[0.0, Color(1.0, 0.92, 0.75)], [0.5, Color(1.0, 0.62, 0.3)], [1.0, Color(1.0, 0.55, 0.25, 0.0)]]}),
			]}
		"hurt_burst":
			# Mak takes damage (r2): a pink-white impact star toward the camera, small pink-red stars (allowed for hurt, <= 0.25 m)
			# and pink sparks; readable from the gameplay camera.
			return {"one_shot": true, "layers": [
				impact(0.7, Color(1.0, 0.82, 0.86), 0.12),
				flash(0.9, Color(1, 0.8, 0.82, 0.8), 0.08),
				stars(6, Vector2(2.5, 4.0), 0.6, {"spread": 120.0, "size": Vector2(0.18, 0.25), "colors": [[0.0, Color(1.7, 0.7, 0.75)], [0.7, Color(1.5, 0.6, 0.65)], [1.0, Color(1, 0.4, 0.45, 0.0)]]}),
				sparks(10, Color(1.6, 0.9, 0.95), Vector2(4, 7), 0.24, {"on_top": true}),
			]}
		"heal_sparkle":
			# Attached ring of pink glints rising around Mak (the cake slice itself is heal_cake, placed toward the camera).
			return {"one_shot": true, "layers": [
				{"tex": "sparkle_ink", "amount": 18, "lifetime": 1.0, "emit": "ring", "radius": 0.5, "dir": Vector3(0, 1, 0), "spread": 10.0, "vel": Vector2(1.4, 2.6),
					"damping": Vector2(1, 2), "size": Vector2(0.2, 0.34), "curve": "twinkle", "colors": [[0.0, Color(1.7, 1.1, 1.2)], [1.0, Color(1.0, 0.7, 0.8, 0.0)]]},
			]}
		"heal_cake":
			# r2: a 0.55 m cake slice pops in front of Mak's face (the catalogue pulls it 0.4 m toward the camera) and floats up.
			return {"one_shot": true, "layers": [
				{"tex": "cake_slice", "amount": 1, "lifetime": 0.9, "emit": "point", "dir": Vector3(0, 1, 0), "spread": 0.0,
					"vel": Vector2(0.7, 0.7), "damping": Vector2(1.2, 1.2), "size": Vector2(0.55, 0.55), "curve": "bang",
					"colors": [[0.0, Color(1, 1, 1)], [0.85, Color(1, 1, 1)], [1.0, Color(1, 1, 1, 0.0)]]},
				glints(6, 0.25, Vector2(0.8, 1.6), 0.6, {"curve": "twinkle", "colors": [[0.0, Color(1.7, 1.1, 1.2)], [1.0, Color(1.0, 0.7, 0.8, 0.0)]]}),
			]}
		"notice_pop":
			# r1: threat red-orange (#FF5A3C, ART_V2 hazards) with the dark ink outline and white highlight of the sprite;
			# the catalogue clamps it near the camera (near_clamp) so it never runs off the top of the frame.
			return {"one_shot": true, "layers": [
				{"tex": "exclaim", "amount": 1, "lifetime": 0.8, "emit": "point", "dir": Vector3(0, 1, 0), "spread": 0.0, "offset": Vector3(0, 0.45, 0),
					"vel": Vector2(1.6, 1.6), "damping": Vector2(7.0, 7.0), "size": Vector2(0.5, 0.5), "curve": "bang", "add": false,
					"colors": [[0.0, Color(1.25, 0.42, 0.28)], [0.85, Color(1.25, 0.42, 0.28)], [1.0, Color(1.25, 0.42, 0.28, 0.0)]]},
				{"kind": "shock", "size": 0.8, "time": 0.2, "billboard": true, "height": 0.0, "thickness": 0.14, "opacity": 0.85, "breakup": 0.0, "ink": 0.7,
					"color": Color(1, 1, 1), "glow": Color(1, 0.55, 0.35)},
				sparks(5, Color(1.3, 1.25, 1.1), Vector2(3.5, 4.5), 0.28, {"dir": Vector3(0, 1, 0), "spread": 45.0, "damping": Vector2(10, 12), "size": Vector2(0.05, 0.07),
					"stretch": 4.0, "taper": 0.3, "add": false, "colors": [[0.0, Color(1, 1, 1)], [0.7, Color(1, 1, 1)], [1.0, Color(1, 1, 1, 0.0)]]}),
			]}
		"windup_glint":
			return {"one_shot": true, "layers": [
				{"tex": "sparkle_ink", "amount": 1, "lifetime": 0.35, "emit": "point", "size": Vector2(0.7, 0.7), "curve": "pop", "spin": 180.0,
					"colors": [[0.0, Color(1.0, 0.75, 0.45)], [1.0, Color(1, 0.6, 0.3, 0.0)]]},
				flash(0.9, Color(1, 0.6, 0.3, 0.6), 0.25),
			]}
		"dizzy_stars":
			# Loop: stars orbit above a stunned head (winded boss, dizzy bee, bonked wolf cub). Attach and stop via Juice loops.
			return {"one_shot": false, "layers": [
				# r4: cream inked stars with a lavender cast (gold is the collectible colour).
				{"tex": "star_ink", "amount": 5, "lifetime": 1.2, "explosiveness": 0.0, "emit": "ring", "radius": 0.45, "dir": Vector3(0, 1, 0), "spread": 0.0,
					"vel": Vector2(0.0, 0.0), "local": true, "orbit": Vector2(0.9, 0.9), "size": Vector2(0.22, 0.26), "curve": "ambient", "spin": 120.0,
					"colors": [[0.0, Color(0.98, 0.95, 1.0)], [1.0, Color(0.98, 0.95, 1.0)]], "preprocess": 1.2},
			]}
		"sweat_drops":
			return {"one_shot": true, "layers": [
				{"mesh": "sphere", "mesh_size": 0.05, "amount": 4, "lifetime": 0.6, "emit": "point", "dir": Vector3(0, 1, 0), "spread": 55.0, "vel": Vector2(2.0, 3.0),
					"gravity": Vector3(0, -10, 0), "size": Vector2(0.8, 1.2), "curve": "late_shrink", "shaded": true,
					"colors": [[0.0, Color(0.7, 0.9, 1.0)], [1.0, Color(0.55, 0.8, 1.0)]]},
			]}
		# ---------------- enemy gags
		"wool_burst":
			# r2: 13 larger fluttering wool tufts (read at 8 m) and glints.
			return {"one_shot": true, "layers": [
				# r4 (critic r2: beige potatoes, sleepy ghost faces): the redrawn 6-lobe fleece tuft (white with a lavender-grey
				# band, no interior strokes); 8 tufts flutter down and settle by about 0.8 s; 3 tiny cream glints at the ground end it.
				{"tex": "tuft", "flutter": "flip", "amount": 8, "lifetime": 0.85, "emit": "sphere", "radius": 0.3, "dir": Vector3(0, 1, 0), "spread": 75.0,
					"vel": Vector2(2.6, 4.0), "gravity": Vector3(0, -5, 0), "damping": Vector2(3, 4), "size": Vector2(0.3, 0.42), "curve": "late_shrink",
					"spin": 220.0, "turbulence": 1.0, "colors": [[0.0, Color(1, 1, 1)], [1.0, Color(1, 1, 1)]]},
				glints(3, 0.35, Vector2(0.2, 0.5), 0.35, {"curve": "twinkle", "delay": 0.7, "offset": Vector3(0, -0.3, 0), "size": Vector2(0.12, 0.16),
					"colors": [[0.0, CREAM], [1.0, Color(CREAM, 0.0)]]}),
			]}
		"defeat_poof":
			# r2: the inked cartoon poof that keeps a defeat on screen for 300-400 ms (6-8 puffs outward with drag, vanish curve).
			return {"one_shot": true, "layers": [
				puffs(7, Color(1, 0.99, 0.96), Vector2(0.6, 0.85), Vector2(2.6, 3.6), 0.4, {"radius": 0.2, "damping": Vector2(6, 8), "curve": "vanish", "keep_puff": true,
					"gravity": Vector3(0, -0.3, 0)}),
			]}
		"bee_burst":
			# r1: the boxing gloves and goggles pop off and tumble; small striped bits and a buzz-off swirl of motes.
			return {"one_shot": true, "layers": [
				puffs(7, Color(1.0, 0.92, 0.55), Vector2(0.26, 0.4), Vector2(2.0, 3.2), 0.5),
				# r4 (critic r2: the gloves read as red pills): two inked boxing-glove cards tumble off.
				{"tex": "glove", "amount": 2, "lifetime": 1.1, "emit": "sphere", "radius": 0.2, "dir": Vector3(0, 1, 0), "spread": 55.0, "vel": Vector2(3.0, 4.5),
					"gravity": Vector3(0, -12, 0), "damping": Vector2(0.5, 1.0), "size": Vector2(0.3, 0.34), "curve": "late_shrink", "spin": 420.0,
					"colors": [[0.0, Color(1, 1, 1)], [1.0, Color(1, 1, 1)]]},
				{"tex": "soft_dot", "amount": 10, "lifetime": 1.0, "emit": "sphere", "radius": 0.2, "spread": 180.0, "vel": Vector2(1.0, 2.0), "orbit": Vector2(1.2, 1.6),
					"gravity": Vector3(0, 1.5, 0), "size": Vector2(0.08, 0.12), "curve": "pop", "palette": "bee"},
			]}
		"gummy_splat":
			return {"one_shot": true, "layers": [
				ring(2.2, Color(0.95, 0.4, 0.52, 0.8), 0.45, {"tex": "splat_ink", "start": 0.5}),
				# r4 (critic r2: 16 glossy pink spheres, a ball pit): 10 squashed translucent jelly blobs with an ink rim, <= 0.2 m.
				{"tex": "jelly", "amount": 10, "lifetime": 0.8, "emit": "sphere", "radius": 0.25, "dir": Vector3(0, 1, 0), "spread": 65.0,
					"vel": Vector2(2.0, 3.5), "gravity": Vector3(0, -12, 0), "damping": Vector2(0.5, 1.0), "size": Vector2(0.12, 0.2), "curve": "late_shrink", "spin": 120.0,
					"colors": [[0.0, Color(1.0, 0.5, 0.6)], [0.8, Color(1.0, 0.5, 0.6)], [1.0, Color(1.0, 0.5, 0.6, 0.0)]]},
				puffs(5, Color(1, 0.85, 0.88), Vector2(0.28, 0.42), Vector2(1.5, 2.5), 0.45),
			]}
		"enemy_slam_ring":
			return {"one_shot": true, "layers": [
				shock(4.5, 0.4, {"thickness": 0.12, "glow": Color(1.0, 0.55, 0.4)}),
				puffs(14, DUST, Vector2(0.35, 0.6), Vector2(3.5, 5.0), 0.7, {"emit": "ring", "radius": 0.5, "dir": Vector3(0, 0.15, 0), "spread": 88.0}),
			]}
		"block_wobble":
			# r4 (critic r2: six identical clangs with no hint to go around): from the second consecutive block a dust skid at the
			# grenadier's feet and a shield-wobble glint; the catalogue adds it through params.repeat.
			return {"one_shot": true, "layers": [
				ground_dust(5, DUST_TAN, Vector2(0.28, 0.36), Vector2(1.6, 2.4), 0.4, {"radius": 0.3, "offset": Vector3(0, -0.75, 0)}),
				{"tex": "sparkle_ink", "amount": 2, "lifetime": 0.3, "emit": "point", "size": Vector2(0.28, 0.34), "curve": "twinkle", "spin": 200.0,
					"offset": Vector3(0.25, 0.15, 0), "colors": [[0.0, Color(1, 0.97, 0.9)], [1.0, Color(1, 0.97, 0.9, 0.0)]]},
			]}
		"grenadier_crumbs":
			# r4 (critic r2: 18-40 flat orange pucks flung 3-4 m that lie like coins, and CPU crumb particles): 9 inked crumb
			# cards with an icing edge and 2 gumdrop buttons, a 1.5 m spread, settled by about 0.7 s (GPU, one draw each).
			return {"one_shot": true, "layers": [
				crumbs(9, Vector2(2.0, 3.2)),
				chunks(2, "gumdrop", 0.1, Color(0.95, 0.35, 0.4), Color(0.85, 0.3, 0.35), Vector2(2.2, 3.0), {"lifetime": 0.7, "spread": 45.0, "size": Vector2(1.0, 1.0),
					"palette": "candy"}),
				puffs(4, Color(0.95, 0.85, 0.7), Vector2(0.28, 0.4), Vector2(1.0, 1.8), 0.4),
			]}
		"gummy_jelly":
			# r4: the gummy melt's droplets as inked translucent jelly cards (tint with the gummy colour).
			return {"one_shot": true, "layers": [
				{"tex": "jelly", "amount": 10, "lifetime": 0.8, "emit": "sphere", "radius": 0.3, "dir": Vector3(0, 1, 0), "spread": 70.0,
					"vel": Vector2(2.0, 3.5), "gravity": Vector3(0, -12, 0), "damping": Vector2(0.5, 1.0), "size": Vector2(0.12, 0.2), "curve": "late_shrink", "spin": 120.0,
					"colors": [[0.0, Color(1.0, 0.5, 0.6)], [0.8, Color(1.0, 0.5, 0.6)], [1.0, Color(1.0, 0.5, 0.6, 0.0)]]},
			]}
		"hit_spark_kit":
			# r4: the enemy kit's defeat fallback (EnemyKit.fx "HitSparkBig" on no_vfx defeats). Juice now plays the impact star
			# itself on those defeats (impact_vfx), so the fallback only adds cream shards and never a second star.
			return {"one_shot": true, "layers": [
				shards(6, Vector2(3.0, 5.0), 0.35, {"gravity": Vector3(0, -8, 0), "damping": Vector2(3, 5)}),
			]}
		# ---------------- boss
		"boss_inhale":
			# r4 (critic r2: an outward pincushion of needles through the wolf's body). Align "direction" (-Z = toward Mak): air
			# is born on a 2.5-3.5 m disc in front of the mouth and flows back INTO it. 4 thick curled wind ribbons, 10 short
			# streaks and 9 leaves and roof grit; everything fades out before the last 0.6 m, so nothing pierces the body.
			return {"one_shot": true, "layers": [
				{"tex": "wind_curl", "amount": 4, "lifetime": 0.55, "explosiveness": 0.0, "emit": "box", "extents": Vector3(1.3, 0.9, 0.3),
					"offset": Vector3(0, 0, -3.0), "dir": Vector3(0, 0, 1), "spread": 10.0, "vel": Vector2(4.2, 5.0), "size": Vector2(1.0, 1.4),
					"curve": "breathe", "spin": 260.0, "colors": [[0.0, Color(1, 1, 1, 0.0)], [0.25, Color(0.96, 0.97, 1.0, 0.85)], [0.75, Color(0.96, 0.97, 1.0, 0.7)],
					[0.9, Color(1, 1, 1, 0.0)], [1.0, Color(1, 1, 1, 0.0)]]},
				{"streak": true, "amount": 10, "lifetime": 0.5, "explosiveness": 0.0, "emit": "box", "extents": Vector3(1.4, 1.0, 0.4), "offset": Vector3(0, 0, -3.0),
					"dir": Vector3(0, 0, 1), "spread": 12.0, "vel": Vector2(5.0, 6.0), "size": Vector2(0.14, 0.18), "curve": "breathe", "stretch": 5.0, "taper": 0.7,
					"add": false, "colors": [[0.0, Color(1, 1, 1, 0.0)], [0.25, Color(0.94, 0.96, 1.0, 0.9)], [0.85, Color(0.94, 0.96, 1.0, 0.6)], [1.0, Color(1, 1, 1, 0.0)]]},
				# r4: a second wave, so the suction streams for the whole ~1.2 s wind-up.
				{"tex": "wind_curl", "amount": 4, "delay": 0.55, "lifetime": 0.55, "explosiveness": 0.0, "emit": "box", "extents": Vector3(1.3, 0.9, 0.3),
					"offset": Vector3(0, 0, -3.0), "dir": Vector3(0, 0, 1), "spread": 10.0, "vel": Vector2(4.2, 5.0), "size": Vector2(1.0, 1.4),
					"curve": "breathe", "spin": 260.0, "colors": [[0.0, Color(1, 1, 1, 0.0)], [0.25, Color(0.96, 0.97, 1.0, 0.85)], [0.75, Color(0.96, 0.97, 1.0, 0.7)],
					[0.9, Color(1, 1, 1, 0.0)], [1.0, Color(1, 1, 1, 0.0)]]},
				{"streak": true, "amount": 10, "delay": 0.55, "lifetime": 0.5, "explosiveness": 0.0, "emit": "box", "extents": Vector3(1.4, 1.0, 0.4), "offset": Vector3(0, 0, -3.0),
					"dir": Vector3(0, 0, 1), "spread": 12.0, "vel": Vector2(5.0, 6.0), "size": Vector2(0.14, 0.18), "curve": "breathe", "stretch": 5.0, "taper": 0.7,
					"add": false, "colors": [[0.0, Color(1, 1, 1, 0.0)], [0.25, Color(0.94, 0.96, 1.0, 0.9)], [0.85, Color(0.94, 0.96, 1.0, 0.6)], [1.0, Color(1, 1, 1, 0.0)]]},
				{"tex": "leaf", "flutter": "flip", "amount": 9, "lifetime": 0.6, "explosiveness": 0.0, "emit": "box", "extents": Vector3(1.5, 1.0, 0.4),
					"offset": Vector3(0, -0.3, -3.2), "dir": Vector3(0, 0.1, 1), "spread": 14.0, "vel": Vector2(4.5, 5.2), "size": Vector2(0.2, 0.28),
					"curve": "ambient", "palette": "leaves", "spin": 400.0},
				chunks(6, "pebble", 0.07, Color(0.72, 0.4, 0.3), Color(0.62, 0.34, 0.26), Vector2(4.5, 5.2), {"lifetime": 0.55, "emit": "box",
					"extents": Vector3(1.2, 0.2, 0.3), "offset": Vector3(0, -1.0, -3.0), "dir": Vector3(0, 0.35, 1), "spread": 10.0, "gravity": Vector3(0, -2, 0),
					"radius": 0.0, "tumble": true}),
			]}
		"boss_huff_blast":
			# Local -Z = blast direction. r1: a cone (3-5 m wide) of spiral wind curls (style image 05), white speed
			# streaks and tumbling leaves; no single cumulus ball.
			return {"one_shot": true, "layers": [
				{"kind": "shock", "size": 3.4, "time": 0.28, "billboard": true, "height": 0.0, "thickness": 0.12, "opacity": 0.7, "breakup": 0.0, "ink": 0.5},
				# Juice fix r3: bigger, wider curls (the gust read as a 1.5 m puff of curls by the wolf's head from the gameplay
				# camera; the critic asks for at least 3 m).
				{"tex": "wind_curl", "amount": 18, "lifetime": 1.0, "emit": "sphere", "radius": 0.8, "dir": Vector3(0, 0, -1), "spread": 24.0, "vel": Vector2(10, 15),
					"damping": Vector2(1.3, 2.2), "size": Vector2(1.4, 2.3), "curve": "vanish", "spin": 140.0,
					"colors": [[0.0, Color(1, 1, 1, 0.9)], [0.6, Color(0.95, 0.97, 1.0, 0.7)], [1.0, Color(0.95, 0.97, 1.0, 0.0)]]},
				sparks(40, Color(1, 1, 1, 0.9), Vector2(13, 20), 0.55, {"dir": Vector3(0, 0, -1), "spread": 18.0, "damping": Vector2(1, 2), "size": Vector2(0.09, 0.13),
					"stretch": 9.0, "emit": "sphere", "radius": 0.9, "add": false}),
				puffs(6, Color(1, 1, 1, 0.8), Vector2(0.5, 0.8), Vector2(6, 9), 0.45, {"dir": Vector3(0, 0, -1), "spread": 16.0, "damping": Vector2(3, 4)}),
				{"tex": "leaf", "flutter": "flip", "amount": 12, "lifetime": 1.2, "emit": "sphere", "radius": 0.6, "dir": Vector3(0, 0, -1), "spread": 25.0, "vel": Vector2(8, 13),
					"damping": Vector2(1.5, 2.5), "size": Vector2(0.18, 0.26), "curve": "ambient", "palette": "leaves", "spin": 400.0},
			]}
		"brick_debris":
			return {"one_shot": true, "layers": [
				puffs(18, Color(0.88, 0.78, 0.7), Vector2(0.6, 1.2), Vector2(2.5, 4.5), 1.2, {"radius": 0.8, "damping": Vector2(2.5, 3.5), "gravity": Vector3(0, 0.4, 0), "curve": "smoke"}),
				chunks(18, "box", 0.22, Color(0.72, 0.32, 0.22), Color(0.6, 0.26, 0.18), Vector2(4.0, 8.0), {"lifetime": 1.3, "radius": 0.7, "spread": 55.0,
					"gravity": Vector3(0, -20, 0), "size": Vector2(0.6, 1.4)}),
				chunks(14, "box", 0.07, Color(0.8, 0.72, 0.62), Color(0.66, 0.58, 0.5), Vector2(3.0, 6.0), {"lifetime": 1.0, "radius": 0.6}),
			]}
		"boss_stomp":
			# r1, sized for the 3.2 m wolf: an inked roof-brick dust splat (7-8 m), a fast thin ring and a slow thick ring,
			# a 2-frame ground flash, rounded brick chips and dust that rolls along the roof.
			return {"one_shot": true, "layers": [
				ring(4.4, Color(0.79, 0.54, 0.42, 0.9), 0.5, {"tex": "splat_ink", "start": 0.55, "ground": true}),
				shock(8.0, 0.3, {"thickness": 0.08, "ink": 0.9, "color": Color(1.0, 0.9, 0.8), "glow": Color(0.95, 0.6, 0.45)}),
				shock(6.0, 0.55, {"thickness": 0.14, "ink": 0.7, "delay": 0.04, "color": Color(0.9, 0.7, 0.58), "glow": Color(0.85, 0.5, 0.38)}),
				flash(4.5, Color(1, 0.9, 0.75, 0.8), 0.07, {"offset": Vector3(0, 0.3, 0)}),
				chunks(12, "pebble", 0.16, Color(0.7, 0.35, 0.25), Color(0.6, 0.3, 0.2), Vector2(4.0, 7.0), {"lifetime": 0.9, "radius": 0.8, "ground": true}),
				puffs(16, Color(0.86, 0.66, 0.55), Vector2(0.6, 1.0), Vector2(6.0, 9.0), 0.85, {"emit": "ring", "radius": 1.2, "dir": Vector3(0, 0.05, 0), "spread": 88.0,
					"damping": Vector2(4, 5)}),
			]}
		"balloon_pop":
			# r2 (fires at 0.60 s with the balloon sound): the pop flash and the wolf's silhouette own the first frames; then
			# cream puffs in a ring around the body, confetti, glints and gold-leaf flakes (no yellow truffle blobs).
			return {"one_shot": true, "layers": [
				{"kind": "shock", "size": 7.0, "time": 0.45, "billboard": true, "height": 0.0, "thickness": 0.1, "opacity": 0.75, "breakup": 0.0, "ink": 0.85},
				flash(4.0, Color(1, 0.93, 0.78, 0.5), 0.14),
				{"mesh": "confetti", "amount": 140, "lifetime": 3.4, "emit": "sphere", "radius": 1.2, "dir": Vector3(0, 1, 0), "spread": 180.0, "vel": Vector2(7, 13),
					"gravity": Vector3(0, -5, 0), "damping": Vector2(2.0, 3.0), "size": Vector2(2.0, 3.2), "curve": "late_shrink", "palette": "celebrate", "tumble": true, "turbulence": 2.5},
				twinkles(14, 1.0, Vector2(5, 9), 1.2, {"size": Vector2(0.3, 0.5)}),
				leaf_flakes(14, Vector2(5, 8), 2.0, {"spread": 120.0, "size": Vector2(0.18, 0.26)}),
				puffs(10, Color(1, 0.97, 0.9), Vector2(1.1, 1.9), Vector2(2.5, 4.0), 0.9, {"emit": "ring", "radius": 1.6, "dir": Vector3(0, 0.3, 0), "spread": 60.0,
					"damping": Vector2(3, 4), "delay": 0.12}),
				# r4: no effect light (one-shot impact lights stepped into bright rectangles on the RetroLook terrain).
			]}
		"hat_pop":
			# r2 punchline at 0.90 s (the hat_pop sound): the wolf's top hat flies up spinning out of a small puff with glints.
			return {"one_shot": true, "layers": [
				{"tex": "top_hat", "amount": 1, "lifetime": 1.6, "emit": "point", "dir": Vector3(0.25, 1, 0), "spread": 6.0, "vel": Vector2(7.5, 7.5),
					"gravity": Vector3(0, -7, 0), "damping": Vector2(0.4, 0.4), "size": Vector2(1.1, 1.1), "curve": "late_shrink", "spin": 260.0,
					"colors": [[0.0, Color(1, 1, 1)], [0.9, Color(1, 1, 1)], [1.0, Color(1, 1, 1, 0.0)]]},
				puffs(6, Color(1, 0.99, 0.96), Vector2(0.6, 0.9), Vector2(2.0, 3.0), 0.4, {"radius": 0.3, "damping": Vector2(6, 8), "curve": "vanish", "keep_puff": true}),
				twinkles(6, 0.4, Vector2(2.5, 4.0), 0.7, {"size": Vector2(0.26, 0.36)}),
			]}
		"lightning_flash":
			return {"one_shot": true, "layers": [light(Color(0.85, 0.85, 1.0), 14.0, 60.0, 0.35)]}
		"phase_burst":
			return {"one_shot": true, "layers": [
				{"kind": "shock", "size": 6.0, "time": 0.5, "billboard": true, "height": 1.5, "thickness": 0.1, "opacity": 0.75, "breakup": 0.0, "ink": 0.8,
					"glow": Color(1.0, 0.5, 0.35)},
				puffs(10, Color(1.0, 0.95, 0.88), Vector2(0.5, 0.9), Vector2(3.5, 6.0), 0.7, {"radius": 0.8}),
				{"tex": "wind_curl", "amount": 8, "lifetime": 0.8, "emit": "sphere", "radius": 0.8, "spread": 180.0, "vel": Vector2(4, 7), "damping": Vector2(3, 4),
					"size": Vector2(0.7, 1.1), "curve": "vanish", "spin": 160.0, "colors": [[0.0, Color(1, 0.9, 0.85, 0.9)], [1.0, Color(1, 0.85, 0.8, 0.0)]]},
				sparks(20, Color(1.6, 0.9, 0.6), Vector2(7, 11), 0.35),
			]}
		"brick_fall":
			# r2 second beat of the chimney smash (0.3 s, the roof-tile sound): brick chunks and dust rain down from above.
			return {"one_shot": true, "layers": [
				chunks(10, "box", 0.2, Color(0.72, 0.32, 0.22), Color(0.6, 0.26, 0.18), Vector2(0.5, 1.5), {"lifetime": 1.0, "emit": "box",
					"extents": Vector3(1.0, 0.3, 1.0), "offset": Vector3(0, 3.0, 0), "dir": Vector3(0, -1, 0), "spread": 25.0, "gravity": Vector3(0, -20, 0)}),
				chunks(10, "box", 0.07, Color(0.8, 0.72, 0.62), Color(0.66, 0.58, 0.5), Vector2(0.5, 1.5), {"lifetime": 0.9, "emit": "box",
					"extents": Vector3(1.2, 0.3, 1.2), "offset": Vector3(0, 3.2, 0), "dir": Vector3(0, -1, 0), "spread": 30.0, "gravity": Vector3(0, -16, 0)}),
			]}
		# ---------------- objects and pickups
		"acorn_pop":
			return {"one_shot": true, "layers": [
				{"kind": "shock", "size": 1.0, "time": 0.22, "billboard": true, "height": 0.4, "thickness": 0.12, "opacity": 0.8, "breakup": 0.0, "ink": 0.45,
					"color": Color(1, 0.95, 0.8), "glow": Color(1.0, 0.75, 0.35)},
				glints(10, 0.15, Vector2(1.5, 3.0), 0.5, {"dir": Vector3(0, 1, 0), "damping": Vector2(3, 5), "offset": Vector3(0, 0.4, 0), "curve": "twinkle"}),
				twinkles(2, 0.1, Vector2(2, 3.2), 0.5, {"offset": Vector3(0, 0.4, 0), "size": Vector2(0.14, 0.2)}),
			]}
		"truffle_appear":
			# r1: a rising column of inked glints and two fluttering pages; no white pillow left on the ground.
			return {"one_shot": true, "layers": [
				{"tex": "glint_ink", "amount": 18, "lifetime": 1.3, "explosiveness": 0.3, "emit": "ring", "radius": 0.7, "dir": Vector3(0, 1, 0), "spread": 4.0,
					"vel": Vector2(2.0, 3.6), "damping": Vector2(0.5, 1.0), "size": Vector2(0.2, 0.34), "curve": "twinkle", "spin": 40.0,
					"colors": [[0.0, GOLD_HDR], [0.7, GOLD_HDR], [1.0, Color(GOLD, 0.0)]]},
				{"tex": "sparkle_ink", "amount": 30, "lifetime": 1.4, "explosiveness": 0.3, "emit": "ring", "radius": 0.9, "dir": Vector3(0, 1, 0), "spread": 4.0,
					"vel": Vector2(2.0, 4.0), "damping": Vector2(0.5, 1.0), "size": Vector2(0.16, 0.3), "curve": "twinkle", "colors": [[0.0, GOLD_HDR], [1.0, Color(GOLD, 0.0)]]},
				shock(3.0, 0.5, {"ink": 0.5, "color": Color(1, 0.95, 0.8), "glow": Color(1.0, 0.8, 0.35)}),
				{"tex": "page", "flutter": "flip", "amount": 2, "lifetime": 1.4, "emit": "ring", "radius": 0.6, "dir": Vector3(0, 1, 0), "spread": 20.0,
					"vel": Vector2(2.0, 2.8), "gravity": Vector3(0, -1.0, 0), "damping": Vector2(1.0, 1.5), "size": Vector2(0.3, 0.38), "curve": "late_shrink",
					"colors": [[0.0, Color(1, 1, 1)], [1.0, Color(1, 1, 1)]], "spin": 90.0, "turbulence": 1.0},
			]}
		"truffle_rays":
			# r4 (critic r2: a generic lens flare, soft additive rays and a white-hot streak): one inked sunburst card of 9 tapered
			# gold rays with a darker gold-orange core (#C9822A) and ink edges, turning slowly behind the truffle. Its centre is
			# empty out to 0.36 of its radius (0.58 m at 3.2 m), so no ray crosses the truffle or the hero's face; no halo, no streak.
			return {"one_shot": true, "layers": [
				{"tex": "sunburst", "amount": 1, "lifetime": 1.8, "emit": "point", "dir": Vector3(0, 1, 0), "spread": 0.0, "vel": Vector2(0, 0),
					"size": Vector2(3.2, 3.2), "curve": "ambient", "spin": 18.0,
					"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.08, Color(1, 1, 1, 0.85)], [0.85, Color(1, 1, 1, 0.85)], [1.0, Color(1, 1, 1, 0.0)]]},
			]}
		"page_get":
			return {"one_shot": true, "layers": [
				{"tex": "page", "flutter": "flip", "amount": 9, "lifetime": 1.8, "emit": "sphere", "radius": 0.3, "dir": Vector3(0, 1, 0), "spread": 50.0,
					"vel": Vector2(2.5, 4.0), "gravity": Vector3(0, -1.6, 0), "damping": Vector2(1.5, 2.0), "size": Vector2(0.35, 0.5), "curve": "late_shrink",
					"colors": [[0.0, Color(1, 1, 1)], [1.0, Color(1, 1, 1)]], "spin": 120.0, "turbulence": 1.5},
				{"kind": "shock", "size": 2.0, "time": 0.3, "billboard": true, "height": 0.5, "thickness": 0.12, "opacity": 0.8, "breakup": 0.0, "ink": 0.85,
					"color": Color(1.0, 0.79, 0.24), "glow": Color(1.0, 0.8, 0.4)},
				glints(16, 0.4, Vector2(0.8, 2.2), 0.8, {"curve": "twinkle"}),
			]}
		"portal_swirl":
			# Jumping into a storybook: parchment pages and glints spiral inward and up into a gold vortex ring (r2: gold ring
			# with an ink rim and an additive gold glow, not pale beige).
			return {"one_shot": true, "layers": [
				# r4 (critic r2: pages lay on the ground as litter): pages spiral up and out of frame (upward gravity) and fade at the top.
				{"tex": "page", "flutter": "flip", "amount": 16, "lifetime": 1.2, "emit": "ring", "radius": 1.6, "dir": Vector3(0, 1, 0), "spread": 10.0,
					"vel": Vector2(2.5, 3.5), "local": true, "orbit": Vector2(0.9, 1.3), "radial": Vector2(-1.4, -1.0), "size": Vector2(0.3, 0.42), "curve": "ambient",
					"gravity": Vector3(0, 2.5, 0), "colors": [[0.0, Color(1, 1, 1)], [0.7, Color(1, 1, 1)], [1.0, Color(1, 1, 1, 0.0)]], "spin": 160.0},
				glints(30, 1.4, Vector2(0.5, 1.5), 1.2, {"emit": "ring", "radius": 1.4, "local": true, "orbit": Vector2(1.0, 1.5), "radial": Vector2(-1.2, -0.8),
					"dir": Vector3(0, 1, 0), "spread": 10.0, "curve": "twinkle"}),
				# r4 (critic r2: an opaque flat gold disc on frame 2): the ring only, thin, no flash fill.
				{"kind": "shock", "size": 3.6, "time": 0.5, "billboard": true, "height": 1.0, "thickness": 0.1, "opacity": 0.8, "breakup": 0.0, "ink": 0.85,
					"color": Color(1.0, 0.79, 0.24), "glow": Color(1.0, 0.72, 0.25)},
				# r3: no effect light (it lit a lime disc on the grass under the portal).
			]}
		"switch_press":
			return {"one_shot": true, "layers": [
				shock(2.2, 0.3, {"glow": Color(1.0, 0.8, 0.4)}),
				sparks(12, Color(1.5, 1.25, 0.6), Vector2(4, 7), 0.3, {"emit": "ring", "radius": 0.4, "dir": Vector3(0, 1, 0), "spread": 40.0, "gravity": Vector3(0, -8, 0), "damping": Vector2(2, 3)}),
				puffs(6, DUST, Vector2(0.2, 0.32), Vector2(1.4, 2.2), 0.45, {"emit": "ring", "radius": 0.4, "spread": 85.0}),
				ground_glow(2.0),
			]}
		"cage_open":
			return {"one_shot": true, "layers": [
				{"kind": "shock", "size": 3.5, "time": 0.45, "billboard": true, "height": 1.0, "thickness": 0.1, "opacity": 0.75, "breakup": 0.0, "ink": 0.4},
				glints(36, 0.9, Vector2(1.5, 4.0), 1.2, {"offset": Vector3(0, 1.0, 0)}),
				{"mesh": "confetti", "amount": 40, "lifetime": 2.2, "emit": "sphere", "radius": 0.5, "dir": Vector3(0, 1, 0), "spread": 50.0, "vel": Vector2(4, 7),
					"gravity": Vector3(0, -6, 0), "damping": Vector2(2.5, 3.5), "size": Vector2(0.8, 1.2), "curve": "late_shrink", "palette": "celebrate", "tumble": true, "turbulence": 2.0},
				ground_glow(3.0),
			]}
		"crate_break":
			return {"one_shot": true, "layers": [
				chunks(10, "plank", 0.5, Color(0.72, 0.5, 0.3), Color(0.6, 0.4, 0.24), Vector2(3.5, 6.5), {"lifetime": 1.2, "radius": 0.4, "spread": 70.0, "size": Vector2(0.7, 1.2)}),
				chunks(12, "pebble", 0.06, Color(0.78, 0.58, 0.38), Color(0.66, 0.48, 0.3), Vector2(3.0, 5.0), {"lifetime": 0.8, "radius": 0.35}),
				puffs(10, Color(0.95, 0.88, 0.76), Vector2(0.35, 0.6), Vector2(2.0, 3.5), 0.6, {"radius": 0.4}),
			]}
		"cloud_puff":
			# r1: a vanish that reads as a vanish: puffs burst outward in 0.1 s, then shrink and erode, gone by 0.6 s.
			return {"one_shot": true, "layers": [
				puffs(14, Color(1, 1, 1), Vector2(0.7, 1.1), Vector2(2.5, 4.0), 0.6, {"emit": "box", "extents": Vector3(1.1, 0.2, 1.1), "dir": Vector3(0, 0.3, 0),
					"spread": 90.0, "damping": Vector2(5, 7), "curve": "vanish", "spin": 40.0}),
				glints(6, 1.0, Vector2(0.4, 1.0), 0.6, {"curve": "twinkle", "colors": [[0.0, Color(1.4, 1.4, 1.5)], [1.0, Color(1, 1, 1, 0.0)]]}),
			]}
		"cloud_step":
			return {"one_shot": true, "layers": [
				puffs(8, Color(1, 1, 1, 0.9), Vector2(0.3, 0.55), Vector2(1.2, 2.0), 0.6, {"emit": "ring", "radius": 0.35, "dir": Vector3(0, 0.15, 0), "spread": 85.0}),
			]}
		"bounce_burst":
			return {"one_shot": true, "layers": [
				shock(2.6, 0.3),
				ring(1.6, Color(1, 1, 1, 0.7), 0.3, {"delay": 0.06}),
				sparks(12, Color(1.3, 1.25, 1.1), Vector2(6, 9), 0.3, {"emit": "ring", "radius": 0.45, "dir": Vector3(0, 1, 0), "spread": 8.0, "stretch": 5.0}),
				puffs(6, Color(1, 1, 1, 0.9), Vector2(0.2, 0.34), Vector2(1.2, 2.0), 0.45, {"emit": "ring", "radius": 0.45, "spread": 80.0}),
			]}
		"leaf_bounce":
			return {"one_shot": true, "layers": [
				shock(2.4, 0.3, {"glow": Color(0.7, 1.0, 0.45)}),
				{"tex": "leaf", "flutter": "flip", "amount": 8, "lifetime": 1.4, "emit": "ring", "radius": 0.5, "dir": Vector3(0, 1, 0), "spread": 40.0, "vel": Vector2(2.5, 4.0),
					"gravity": Vector3(0, -2.0, 0), "damping": Vector2(1.5, 2.5), "size": Vector2(0.14, 0.22), "curve": "ambient", "spin": 300.0,
					"colors": [[0.0, Color(0.5, 0.82, 0.3)], [1.0, Color(0.45, 0.75, 0.28)]]},
				sparks(8, Color(1.1, 1.3, 0.9), Vector2(6, 8), 0.28, {"emit": "ring", "radius": 0.45, "spread": 8.0, "stretch": 5.0}),
			]}
		"gumdrop_bounce":
			return {"one_shot": true, "layers": [
				shock(2.4, 0.3, {"glow": Color(1.0, 0.55, 0.75)}),
				glints(14, 0.5, Vector2(2.0, 4.0), 0.7, {"emit": "ring", "dir": Vector3(0, 1, 0), "spread": 40.0, "gravity": Vector3(0, -6, 0),
					"colors": [[0.0, Color(1.7, 1.2, 1.5)], [1.0, Color(1, 0.6, 0.85, 0.0)]]}),
				{"mesh": "box", "mesh_size": 0.04, "amount": 12, "lifetime": 0.8, "emit": "ring", "radius": 0.4, "dir": Vector3(0, 1, 0), "spread": 45.0, "vel": Vector2(2.5, 4.5),
					"gravity": Vector3(0, -12, 0), "size": Vector2(0.7, 1.2), "curve": "late_shrink", "tumble": true, "palette": "candy", "shaded": true},
			]}
		"wind_gust":
			# Local -Z = wind direction. r1: spiral wind curls (translucent white) plus streaks and leaves.
			return {"one_shot": true, "layers": [
				{"tex": "wind_curl", "amount": 6, "lifetime": 0.9, "emit": "box", "extents": Vector3(1.4, 0.9, 0.5), "dir": Vector3(0, 0, -1), "spread": 10.0,
					"vel": Vector2(6, 9), "damping": Vector2(0.8, 1.2), "size": Vector2(0.6, 0.9), "curve": "ambient", "spin": 120.0,
					"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.25, Color(1, 1, 1, 0.55)], [1.0, Color(1, 1, 1, 0.0)]]},
				sparks(16, Color(1, 1, 1, 0.7), Vector2(9, 14), 0.6, {"emit": "box", "extents": Vector3(1.5, 1.0, 0.5), "dir": Vector3(0, 0, -1), "spread": 8.0,
					"damping": Vector2(0.5, 1.0), "size": Vector2(0.05, 0.08), "stretch": 8.0, "add": false}),
				{"tex": "leaf", "flutter": "flip", "amount": 7, "lifetime": 1.2, "emit": "box", "extents": Vector3(1.5, 1.0, 0.5), "dir": Vector3(0, 0.1, -1), "spread": 15.0,
					"vel": Vector2(6, 9), "damping": Vector2(1, 2), "size": Vector2(0.16, 0.22), "curve": "ambient", "palette": "leaves", "spin": 400.0},
			]}
		"cocoa_burn":
			# r1: hot means hazard red-orange (#FF5A3C). r2: inked cocoa droplets with a cream highlight (no brown meatballs).
			return {"one_shot": true, "layers": [
				shock(2.2, 0.34, {"thickness": 0.14, "ink": 0.8, "color": Color(1.0, 0.45, 0.3), "glow": Color(1.0, 0.36, 0.24)}),
				cocoa_drops(12, Vector2(3.0, 4.5), 0.8),
				puffs(4, Color(1, 0.98, 0.95, 0.7), Vector2(0.35, 0.55), Vector2(1.0, 1.8), 1.0, {"dir": Vector3(0, 1, 0), "spread": 20.0, "curve": "smoke",
					"gravity": Vector3(0, 1.4, 0), "damping": Vector2(1, 2), "soft": true}),
				sparks(10, Color(1.8, 0.8, 0.85), Vector2(3, 5), 0.32, {"dir": Vector3(0, 1, 0), "spread": 60.0, "offset": Vector3(0, 0.7, 0)}),
			]}
		"hazard_burst":
			# Damaging volume touched (not hot chocolate): hazard red-orange pop and ring plus Mak's pink ouch sparks.
			return {"one_shot": true, "layers": [
				{"kind": "shock", "size": 1.6, "time": 0.22, "billboard": true, "height": 0.7, "thickness": 0.14, "opacity": 0.8, "breakup": 0.0, "ink": 0.7,
					"color": Color(1.0, 0.5, 0.35), "glow": Color(1.0, 0.36, 0.24)},
				flash(1.6, Color(1.0, 0.45, 0.3, 0.8), 0.12, {"offset": Vector3(0, 0.7, 0)}),
				stars(4, Vector2(2.5, 3.5), 0.5, {"offset": Vector3(0, 0.9, 0), "colors": [[0.0, Color(1.7, 0.7, 0.75)], [0.7, Color(1.5, 0.6, 0.65)], [1.0, Color(1, 0.4, 0.45, 0.0)]]}),
				sparks(8, Color(1.8, 0.6, 0.4), Vector2(4, 6), 0.25, {"offset": Vector3(0, 0.7, 0)}),
			]}
		"dig_burst":
			return {"one_shot": true, "layers": [
				chunks(16, "box", 0.08, Color(0.45, 0.3, 0.18), Color(0.38, 0.25, 0.15), Vector2(3.0, 6.0), {"lifetime": 1.0, "spread": 40.0}),
				puffs(12, Color(0.75, 0.6, 0.45), Vector2(0.4, 0.75), Vector2(2.0, 3.5), 0.8),
				glints(14, 0.4, Vector2(1.5, 3.5), 0.9),
			]}
		"platform_crumble":
			return {"one_shot": true, "layers": [
				chunks(12, "box", 0.1, Color(0.72, 0.6, 0.45), Color(0.6, 0.5, 0.36), Vector2(0.5, 1.5), {"lifetime": 1.2, "emit": "box", "extents": Vector3(1.0, 0.1, 1.0),
					"dir": Vector3(0, -1, 0), "spread": 30.0}),
				puffs(10, DUST, Vector2(0.4, 0.7), Vector2(0.5, 1.2), 0.9, {"emit": "box", "extents": Vector3(1.0, 0.1, 1.0)}),
			]}
		"door_unlock":
			return {"one_shot": true, "layers": [
				glints(40, 1.2, Vector2(0.8, 2.5), 1.4, {"emit": "box", "extents": Vector3(1.2, 1.6, 0.2), "offset": Vector3(0, 1.6, 0), "curve": "twinkle"}),
				puffs(8, DUST, Vector2(0.3, 0.5), Vector2(1.0, 2.0), 0.6, {"emit": "box", "extents": Vector3(1.2, 0.1, 0.3), "dir": Vector3(0, 0.2, 0)}),
			]}
		"ring_burst":
			# Time-trial ring passed: a gold ring flash and glints.
			return {"one_shot": true, "layers": [
				{"kind": "shock", "size": 2.8, "time": 0.3, "billboard": true, "height": 0.0, "thickness": 0.12, "opacity": 0.8, "breakup": 0.0, "ink": 0.55,
					"color": Color(1.0, 0.88, 0.5), "glow": Color(1.0, 0.75, 0.3)},
				flash(1.8, Color(1, 0.88, 0.5, 0.7), 0.12),
				glints(16, 0.9, Vector2(1.5, 3.0), 0.7, {"emit": "ring", "radius": 1.0, "curve": "twinkle"}),
			]}
		"glint_burst":
			return {"one_shot": true, "layers": [
				glints(16, 0.35, Vector2(1.2, 2.6), 0.7, {"size": Vector2(0.16, 0.3)}),
				flash(1.0, Color(1, 0.88, 0.55, 0.38), 0.18),
			]}
		"hat_poof":
			return {"one_shot": true, "layers": [
				puffs(10, Color(1, 1, 1), Vector2(0.28, 0.45), Vector2(1.4, 2.4), 0.5, {"radius": 0.25}),
				twinkles(5, 0.2, Vector2(2, 3.5), 0.6, {"spread": 120.0}),
				glints(10, 0.3, Vector2(0.8, 1.8), 0.6, {"curve": "twinkle"}),
			]}
		"mission_fanfare":
			return {"one_shot": true, "layers": [
				{"mesh": "confetti", "amount": 80, "lifetime": 3.0, "emit": "sphere", "radius": 0.5, "dir": Vector3(0, 1, 0), "spread": 40.0, "vel": Vector2(6, 10),
					"gravity": Vector3(0, -6, 0), "damping": Vector2(2.0, 3.0), "size": Vector2(1.0, 1.5), "curve": "late_shrink", "palette": "celebrate", "tumble": true, "turbulence": 2.5},
				leaf_flakes(12, Vector2(5, 8), 2.2),
				twinkles(10, 0.4, Vector2(5, 8), 1.0, {"spread": 60.0, "size": Vector2(0.22, 0.34)}),
			]}
		# ---------------- ambient (continuous drop-ins; size with FxEffect.area)
		"pollen":
			return {"one_shot": false, "layers": [
				{"tex": "soft_dot", "amount": 60, "lifetime": 8.0, "explosiveness": 0.0, "preprocess": 8.0, "emit": "box", "extents": Vector3(10, 2.0, 10),
					"dir": Vector3(1, 0.3, 0.2), "spread": 180.0, "vel": Vector2(0.05, 0.2), "gravity": Vector3(0.05, 0.02, 0), "size": Vector2(0.06, 0.1),
					"curve": "ambient", "add": true, "turbulence": 0.8, "turb_scale": 3.0, "world": true,
					"colors": [[0.0, Color(1.3, 1.1, 0.55, 0.0)], [0.15, Color(1.3, 1.1, 0.55, 0.85)], [0.85, Color(1.3, 1.1, 0.55, 0.85)], [1.0, Color(1.3, 1.1, 0.55, 0.0)]]},
				{"tex": "puff", "amount": 14, "lifetime": 9.0, "explosiveness": 0.0, "preprocess": 9.0, "emit": "box", "extents": Vector3(10, 2.0, 10),
					"dir": Vector3(1, 0.2, 0), "spread": 180.0, "vel": Vector2(0.1, 0.3), "gravity": Vector3(0.08, 0.0, 0), "size": Vector2(0.1, 0.16),
					"curve": "ambient", "turbulence": 0.6, "world": true, "spin": 30.0, "soft": true,
					"colors": [[0.0, Color(1, 1, 0.95, 0.0)], [0.2, Color(1, 1, 0.95, 0.9)], [0.8, Color(1, 1, 0.95, 0.9)], [1.0, Color(1, 1, 0.95, 0.0)]]},
			]}
		"fireflies":
			return {"one_shot": false, "layers": [
				{"tex": "soft_dot", "amount": 26, "lifetime": 6.0, "explosiveness": 0.0, "preprocess": 6.0, "emit": "box", "extents": Vector3(6, 1.5, 6),
					"dir": Vector3(0, 1, 0), "spread": 180.0, "vel": Vector2(0.05, 0.25), "size": Vector2(0.12, 0.18), "curve": "firefly", "add": true,
					"turbulence": 1.2, "turb_scale": 2.0, "world": true,
					"colors": [[0.0, Color(1.6, 1.25, 0.5, 0.0)], [0.2, Color(1.6, 1.25, 0.5, 1.0)], [0.35, Color(1.6, 1.25, 0.5, 0.2)], [0.55, Color(1.6, 1.25, 0.5, 1.0)],
						[0.8, Color(1.6, 1.25, 0.5, 0.3)], [1.0, Color(1.6, 1.25, 0.5, 0.0)]]},
				{"tex": "soft_dot", "amount": 26, "lifetime": 6.0, "explosiveness": 0.0, "preprocess": 6.0, "emit": "box", "extents": Vector3(6, 1.5, 6),
					"dir": Vector3(0, 1, 0), "spread": 180.0, "vel": Vector2(0.05, 0.25), "size": Vector2(0.35, 0.5), "curve": "firefly", "add": true,
					"turbulence": 1.2, "turb_scale": 2.0, "world": true,
					"colors": [[0.0, Color(1, 0.7, 0.25, 0.0)], [0.2, Color(1, 0.7, 0.25, 0.18)], [0.35, Color(1, 0.7, 0.25, 0.03)], [0.55, Color(1, 0.7, 0.25, 0.18)],
						[0.8, Color(1, 0.7, 0.25, 0.05)], [1.0, Color(1, 0.7, 0.25, 0.0)]]},
			]}
		"dust_motes":
			# Hub light-shaft dust: tiny warm specks drifting slowly, visible where light hits them.
			return {"one_shot": false, "layers": [
				{"tex": "soft_dot", "amount": 90, "lifetime": 10.0, "explosiveness": 0.0, "preprocess": 10.0, "emit": "box", "extents": Vector3(3, 4, 3),
					"dir": Vector3(0.2, -0.1, 0.1), "spread": 180.0, "vel": Vector2(0.02, 0.08), "size": Vector2(0.04, 0.07), "curve": "ambient", "add": true,
					"turbulence": 0.4, "turb_scale": 2.5, "world": true,
					"colors": [[0.0, Color(1.2, 1.0, 0.75, 0.0)], [0.2, Color(1.2, 1.0, 0.75, 0.6)], [0.8, Color(1.2, 1.0, 0.75, 0.6)], [1.0, Color(1.2, 1.0, 0.75, 0.0)]]},
			]}
		"cloud_wisps":
			# W2: slow translucent cloud wisps drifting past platforms (large soft sprites, low alpha).
			return {"one_shot": false, "layers": [
				# r4 (critic r2: a milky smear column across the beanstalk): low-lying (1 m box), smaller wisps at 0.2 alpha.
				{"tex": "puff", "amount": 14, "lifetime": 14.0, "explosiveness": 0.0, "preprocess": 14.0, "emit": "box", "extents": Vector3(14, 1, 14),
					"dir": Vector3(1, 0, 0.2), "spread": 15.0, "vel": Vector2(0.4, 0.9), "size": Vector2(2.0, 3.4), "curve": "ambient", "spin": 6.0, "world": true, "soft": true,
					"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.25, Color(1, 0.98, 1.0, 0.2)], [0.75, Color(1, 0.98, 1.0, 0.2)], [1.0, Color(1, 1, 1, 0.0)]],
					"aabb": AABB(Vector3(-24, -8, -24), Vector3(48, 16, 48))},
			]}
		"candy_sparkles":
			# r4 (critic r2: white four-point glints all over the grass dilute "sparkle = collectible", D034): tiny round sugar
			# dots and sprinkles in the W3 palette at alpha 0.5 or less. The four-point glint is reserved for pickups.
			return {"one_shot": false, "layers": [
				{"tex": "sprinkle", "amount": 40, "lifetime": 3.0, "explosiveness": 0.0, "preprocess": 3.0, "emit": "box", "extents": Vector3(8, 2.0, 8),
					"dir": Vector3(0, -1, 0), "spread": 30.0, "vel": Vector2(0.05, 0.15), "gravity": Vector3(0, -0.05, 0), "size": Vector2(0.06, 0.09), "curve": "ambient",
					"spin": 90.0, "world": true, "palette": "candy", "colors": [[0.0, Color(1, 1, 1, 0.0)], [0.2, Color(1, 1, 1, 0.5)], [0.8, Color(1, 1, 1, 0.5)], [1.0, Color(1, 1, 1, 0.0)]]},
				{"tex": "soft_dot", "amount": 30, "lifetime": 2.6, "explosiveness": 0.0, "preprocess": 3.0, "emit": "box", "extents": Vector3(8, 2.0, 8),
					"dir": Vector3(0, 1, 0), "spread": 180.0, "vel": Vector2(0.02, 0.08), "size": Vector2(0.07, 0.11), "curve": "pop", "world": true,
					"palette": "candy", "colors": [[0.0, Color(1, 1, 1, 0.0)], [0.3, Color(1, 1, 1, 0.45)], [1.0, Color(1, 1, 1, 0.0)]]},
			]}
		"cocoa_steam":
			return {"one_shot": false, "layers": [
				{"tex": "puff", "amount": 16, "lifetime": 4.0, "explosiveness": 0.0, "preprocess": 4.0, "emit": "box", "extents": Vector3(4, 0.1, 1.5),
					"dir": Vector3(0, 1, 0), "spread": 10.0, "vel": Vector2(0.3, 0.6), "gravity": Vector3(0.1, 0.1, 0), "size": Vector2(0.6, 1.0), "curve": "smoke", "spin": 20.0,
					"turbulence": 0.5, "world": true, "soft": true,
					"colors": [[0.0, Color(1, 0.97, 0.94, 0.0)], [0.2, Color(1, 0.97, 0.94, 0.35)], [1.0, Color(1, 0.97, 0.94, 0.0)]]},
			]}
		"fire_embers":
			return {"one_shot": false, "layers": [
				{"streak": true, "amount": 24, "lifetime": 2.2, "explosiveness": 0.0, "preprocess": 2.0, "emit": "box", "extents": Vector3(0.7, 0.1, 0.3),
					"dir": Vector3(0, 1, 0), "spread": 15.0, "vel": Vector2(0.8, 1.6), "gravity": Vector3(0, 0.3, 0), "size": Vector2(0.02, 0.035), "curve": "ambient",
					"stretch": 2.0, "taper": 0.5, "turbulence": 1.5, "turb_scale": 1.5, "world": true,
					"colors": [[0.0, Color(2.0, 1.1, 0.4)], [0.6, Color(1.8, 0.6, 0.2)], [1.0, Color(1, 0.3, 0.1, 0.0)]]},
			]}
		"petals":
			return {"one_shot": false, "layers": [
				{"tex": "leaf", "flutter": "flip", "amount": 18, "lifetime": 8.0, "explosiveness": 0.0, "preprocess": 8.0, "emit": "box", "extents": Vector3(7, 0.5, 7),
					"dir": Vector3(0.3, -1, 0), "spread": 20.0, "vel": Vector2(0.2, 0.5), "gravity": Vector3(0.3, -0.25, 0), "size": Vector2(0.1, 0.16),
					"curve": "ambient", "palette": "petals", "spin": 90.0, "turbulence": 1.5, "world": true},
			]}
	return {}

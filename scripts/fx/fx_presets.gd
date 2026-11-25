class_name FxPresets
extends RefCounted
## Data-driven definitions for every FxEffect preset, plus the builders that turn a layer
## dictionary into GPUParticles3D / ring meshes. Shared materials are cached per layer signature.

const TEX := "res://assets/textures/fx/"
const GOLD := Color(1.0, 0.8, 0.28)
const GOLD_HOT := Color(1.0, 0.93, 0.6)
## Over-bright gold for small inked sprites (stars, sparkles) so they stay gold after mipmapping and glow a little.
const GOLD_HDR := Color(1.7, 1.3, 0.45)
const DUST := Color(0.98, 0.9, 0.76)
const CREAM := Color(1.0, 0.97, 0.9)

static var _mat_cache: Dictionary = {}
## Sprites drawn with fx_inked.gdshader (erosion instead of fade). Juice fix r4: the inked puffs, star, crumb and jelly
## (assets/textures/_src/make_fx_textures_r4.py) join them, so every one-shot sprite is one inked flat-fill family.
const INKED := ["impact_star", "dust_crescent", "cocoa_drop", "puff_ink", "puff_ink_b", "puff_ink_c", "star_ink", "crumb", "jelly"]
## Juice fix r4: inked sprites that get the 5 cm soft depth fade (they touch the ground or bodies).
const INKED_DEPTH := ["dust_crescent", "puff_ink", "puff_ink_b", "puff_ink_c", "jelly"]
const PUFF_INK := ["puff_ink", "puff_ink_b", "puff_ink_c"]


static func get_preset(name: String) -> Dictionary:
	match name:
		"dust_puff":
			# Juice fix r2: low ground dust crescents that roll out along the ground and erode by 60% of life (no puff balls
			# at chest height).
			return {"one_shot": true, "layers": [FxPresetsJuice.ground_dust(7, DUST, Vector2(0.3, 0.42), Vector2(1.8, 2.8), 0.5)]}
		"run_dust":
			return {"one_shot": false, "layers": [
				{"tex": "puff", "amount": 14, "lifetime": 0.6, "explosiveness": 0.0, "emit": "sphere", "radius": 0.12, "dir": Vector3(0, 1, 0), "spread": 40.0,
					"vel": Vector2(0.4, 1.0), "gravity": Vector3(0, 0.5, 0), "damping": Vector2(2, 3), "size": Vector2(0.18, 0.32),
					"curve": "puff", "colors": [[0.0, DUST], [1.0, Color(DUST, 0.0)]], "spin": 40.0, "world": true},
			]}
		"landing_ring":
			return {"one_shot": true, "layers": [
				{"kind": "ring", "size": 1.8, "time": 0.38, "color": Color(1, 0.98, 0.92, 0.85), "start": 0.2},
				FxPresetsJuice.ground_dust(4, DUST, Vector2(0.22, 0.3), Vector2(1.4, 2.0), 0.4),
			]}
		"slam_shockwave":
			return {"one_shot": true, "layers": [
				{"kind": "ring", "size": 3.2, "time": 0.5, "color": Color(0.6, 0.47, 0.33, 0.88), "start": 0.6, "tex": "splat_ink", "ground": true},
				{"kind": "ring", "size": 5.0, "time": 0.4, "color": Color(1, 0.95, 0.8, 0.7), "start": 0.1},
				FxPresetsJuice.ground_dust(8, DUST, Vector2(0.36, 0.5), Vector2(4.0, 6.0), 0.55, {"radius": 0.5}),
				{"mesh": "pebble", "mesh_size": 0.09, "amount": 12, "lifetime": 0.8, "emit": "sphere", "radius": 0.4, "dir": Vector3(0, 1, 0), "spread": 50.0,
					"vel": Vector2(4.0, 7.0), "gravity": Vector3(0, -18, 0), "size": Vector2(0.6, 1.3), "curve": "late_shrink", "shaded": true,
					"colors": [[0.0, Color(0.62, 0.48, 0.34)], [1.0, Color(0.5, 0.38, 0.26)]], "tumble": true, "ground": true},
				{"tex": "glint_ink", "amount": 5, "lifetime": 0.55, "emit": "sphere", "radius": 0.2, "dir": Vector3(0, 1, 0), "spread": 70.0,
					"vel": Vector2(3, 5), "gravity": Vector3(0, -6, 0), "size": Vector2(0.16, 0.24), "curve": "twinkle",
					"colors": [[0.0, GOLD_HDR], [1.0, Color(GOLD, 0.0)]], "spin": 40.0},
				# Juice fix r4: no effect light on one-shot ground impacts (it stepped into a bright rectangle on RetroLook terrain).
				FxPresetsJuice.ground_glow(3.0),
			]}
		"jump_trail":
			return {"one_shot": true, "layers": [
				{"tex": "puff", "amount": 14, "lifetime": 0.5, "explosiveness": 0.0, "emit": "sphere", "radius": 0.12, "dir": Vector3(0, -1, 0), "spread": 25.0,
					"vel": Vector2(0.3, 0.8), "damping": Vector2(2, 3), "size": Vector2(0.16, 0.26), "curve": "shrink", "world": true, "spin": 90.0,
					"colors": [[0.0, Color(1, 1, 1, 0.9)], [1.0, Color(0.85, 0.92, 1.0, 0.0)]]},
				{"tex": "sparkle_ink", "amount": 8, "lifetime": 0.55, "explosiveness": 0.0, "emit": "sphere", "radius": 0.3, "vel": Vector2(0.1, 0.5),
					"size": Vector2(0.14, 0.22), "curve": "pop", "world": true, "colors": [[0.0, GOLD_HDR], [1.0, Color(GOLD, 0.0)]]},
			]}
		"sparkle":
			return {"one_shot": false, "layers": [
				{"tex": "sparkle_ink", "amount": 14, "lifetime": 1.0, "explosiveness": 0.0, "emit": "sphere_surface", "radius": 0.65, "dir": Vector3(0, 1, 0),
					"spread": 180.0, "vel": Vector2(0.05, 0.25), "gravity": Vector3(0, 0.3, 0), "size": Vector2(0.16, 0.3), "curve": "pop",
					"colors": [[0.0, Color(GOLD_HDR, 0.0)], [0.2, GOLD_HDR], [1.0, Color(GOLD, 0.0)]], "spin": 90.0},
				{"tex": "soft_dot", "amount": 3, "lifetime": 1.4, "explosiveness": 0.0, "emit": "point", "size": Vector2(1.4, 1.8), "curve": "breathe", "add": true,
					"colors": [[0.0, Color(GOLD, 0.0)], [0.5, Color(GOLD, 0.22)], [1.0, Color(GOLD, 0.0)]]},
			]}
		"collect_pop":
			return {"one_shot": true, "layers": [
				{"kind": "ring", "size": 1.1, "time": 0.3, "color": Color(1, 0.9, 0.55, 0.9), "start": 0.2, "billboard": true},
				{"tex": "soft_dot", "amount": 1, "lifetime": 0.25, "emit": "point", "size": Vector2(1.6, 1.6), "curve": "pop", "add": true,
					"colors": [[0.0, Color(1, 0.9, 0.55, 0.8)], [1.0, Color(1, 0.8, 0.4, 0.0)]]},
				{"tex": "sparkle_ink", "amount": 12, "lifetime": 0.55, "emit": "sphere", "radius": 0.15, "dir": Vector3(0, 1, 0), "spread": 180.0,
					"vel": Vector2(1.5, 3.0), "damping": Vector2(3, 5), "size": Vector2(0.18, 0.32), "curve": "twinkle",
					"colors": [[0.0, GOLD_HDR], [1.0, Color(GOLD, 0.0)]], "spin": 180.0},
				{"tex": "glint_ink", "amount": 4, "lifetime": 0.6, "emit": "point", "dir": Vector3(0, 1, 0), "spread": 60.0, "vel": Vector2(2, 3.5),
					"gravity": Vector3(0, -4, 0), "size": Vector2(0.16, 0.24), "curve": "twinkle", "colors": [[0.0, GOLD_HDR], [0.6, GOLD_HDR], [1.0, Color(GOLD, 0.0)]], "spin": 40.0},
			]}
		"truffle_burst":
			# r1: the game's key moment without borrowed five-point stars. Inked four-point glints in two sizes with a twinkle,
			# tiny gold truffle silhouettes and gold-leaf flakes; every piece stays smaller than the truffle itself.
			return {"one_shot": true, "layers": [
				# Juice fix r2: rings 3.0/2.0 m (were 4.0/2.6: overdraw and a white-gold disc over the truffle), HDR capped at 1.3.
				# Juice fix r3 (D034: the truffle is the gameplay layer, the burst frames it): rings 2.6/1.8 m, both gold (the
				# near-white inner ring and the 2.2 m flash stacked into a white-gold disc over the truffle at f12-f24).
				# Juice fix r4 (critic r2: light gold on a light caramel path, a haze with no edge in W3): an ink pop ring behind
				# frame 1 is the value anchor; the rings are blended gold-orange (the additive billboard rings washed to white).
				FxPresetsJuice.ink_pop(1.4, 0.08),
				{"kind": "ring", "size": 2.6, "time": 0.5, "color": Color(0.79, 0.51, 0.16, 0.8), "start": 0.15, "billboard": true, "tex": "ring"},
				{"kind": "ring", "size": 1.8, "time": 0.42, "color": Color(1, 0.79, 0.24, 0.7), "start": 0.2, "billboard": true, "delay": 0.12, "tex": "ring"},
				{"tex": "glint_ink", "amount": 14, "lifetime": 1.4, "emit": "sphere", "radius": 0.3, "dir": Vector3(0, 1, 0), "spread": 180.0,
					"vel": Vector2(3.5, 6.5), "gravity": Vector3(0, -4, 0), "damping": Vector2(1.8, 2.6), "size": Vector2(0.22, 0.34), "curve": "twinkle",
					"colors": [[0.0, GOLD_HDR], [0.75, GOLD_HDR], [1.0, Color(GOLD, 0.0)]], "spin": 60.0},
				{"tex": "gold_leaf", "flutter": "flip", "amount": 10, "lifetime": 2.0, "emit": "sphere", "radius": 0.3, "dir": Vector3(0, 1, 0), "spread": 70.0,
					"vel": Vector2(3.0, 5.5), "gravity": Vector3(0, -2.2, 0), "damping": Vector2(1.5, 2.5), "size": Vector2(0.12, 0.18), "curve": "late_shrink",
					"spin": 200.0, "turbulence": 1.5, "colors": [[0.0, Color(1.35, 1.05, 0.45)], [1.0, Color(1.2, 0.92, 0.4)]]},
				{"tex": "sparkle_ink", "amount": 20, "lifetime": 1.2, "emit": "sphere", "radius": 0.6, "spread": 180.0, "vel": Vector2(1.0, 4.0),
					"damping": Vector2(2, 4), "size": Vector2(0.16, 0.26), "curve": "twinkle", "colors": [[0.0, Color(1.0, 0.79, 0.24)], [1.0, Color(1.0, 0.79, 0.24, 0.0)]]},
				{"mesh": "confetti", "amount": 50, "lifetime": 2.2, "emit": "sphere", "radius": 0.3, "dir": Vector3(0, 1, 0), "spread": 50.0,
					"vel": Vector2(4.5, 7.5), "gravity": Vector3(0, -7, 0), "damping": Vector2(2.5, 3.5), "size": Vector2(0.8, 1.2), "curve": "late_shrink",
					"palette": "celebrate", "tumble": true, "turbulence": 2.0, "delay": 0.05},
			]}
		"page_flutter":
			return {"one_shot": true, "layers": [
				{"tex": "page", "flutter": "flip", "amount": 7, "lifetime": 1.8, "emit": "sphere", "radius": 0.3, "dir": Vector3(0, 1, 0), "spread": 50.0,
					"vel": Vector2(2.5, 4.0), "gravity": Vector3(0, -1.6, 0), "damping": Vector2(1.5, 2.0), "size": Vector2(0.35, 0.5), "curve": "late_shrink",
					"colors": [[0.0, Color(1, 0.96, 0.86)], [1.0, Color(1, 0.96, 0.86)]], "spin": 120.0, "turbulence": 1.5},
				{"tex": "sparkle_ink", "amount": 14, "lifetime": 0.8, "emit": "sphere", "radius": 0.4, "spread": 180.0, "vel": Vector2(0.8, 2.0),
					"size": Vector2(0.16, 0.26), "curve": "pop", "colors": [[0.0, GOLD_HDR], [1.0, Color(GOLD, 0.0)]]},
			]}
		"confetti":
			return {"one_shot": true, "layers": [
				{"mesh": "confetti", "amount": 100, "lifetime": 2.6, "emit": "sphere", "radius": 0.3, "dir": Vector3(0, 1, 0), "spread": 45.0,
					"vel": Vector2(4.5, 7.5), "gravity": Vector3(0, -6, 0), "damping": Vector2(2.5, 3.5), "size": Vector2(1.1, 1.7), "curve": "late_shrink",
					"palette": "celebrate", "tumble": true, "turbulence": 2.5},
				{"tex": "puff", "amount": 6, "lifetime": 0.6, "emit": "sphere", "radius": 0.2, "spread": 180.0, "vel": Vector2(1, 2), "damping": Vector2(4, 5),
					"size": Vector2(0.3, 0.45), "curve": "puff", "colors": [[0.0, CREAM], [1.0, Color(CREAM, 0.0)]]},
			]}
		"feather_burst":
			return {"one_shot": true, "layers": [
				# Juice fix r3 (D034 hierarchy): 14 smaller slate feathers that stay near the body (was 22 near-black 0.32-0.5 m
				# feathers flung 4 m: at 1.3x scale they became metre-wide dark blades across the gameplay frame).
				{"tex": "feather", "flutter": "flip", "amount": 14, "lifetime": 1.6, "emit": "sphere", "radius": 0.25, "dir": Vector3(0, 1, 0), "spread": 120.0,
					"vel": Vector2(1.4, 2.8), "gravity": Vector3(0, -1.4, 0), "damping": Vector2(2.5, 3.5), "size": Vector2(0.2, 0.3), "curve": "late_shrink",
					"colors": [[0.0, Color(0.36, 0.36, 0.5)], [1.0, Color(0.42, 0.41, 0.56)]], "spin": 200.0, "turbulence": 1.2},
				{"tex": "puff", "amount": 7, "lifetime": 0.55, "emit": "sphere", "radius": 0.2, "spread": 180.0, "vel": Vector2(1.5, 2.5), "damping": Vector2(4, 5),
					"size": Vector2(0.35, 0.5), "curve": "puff", "colors": [[0.0, Color(0.95, 0.95, 1.0)], [1.0, Color(0.9, 0.9, 1.0, 0.0)]]},
			]}
		"crumb_burst":
			# Juice fix r4 (critic r2: flat orange pucks that lie like coins, terrain-coloured in W3): 9 inked crumb cards with a
			# white icing edge, 2 gumdrop buttons and a small dust puff; 1.5 m spread, settled by about 0.7 s.
			return {"one_shot": true, "layers": [
				FxPresetsJuice.crumbs(9, Vector2(2.0, 3.2)),
				{"mesh": "gumdrop", "mesh_size": 0.1, "amount": 2, "lifetime": 0.7, "emit": "sphere", "radius": 0.2, "dir": Vector3(0, 1, 0), "spread": 50.0,
					"vel": Vector2(2.2, 3.0), "gravity": Vector3(0, -14, 0), "size": Vector2(1.0, 1.0), "curve": "late_shrink", "tumble": true, "palette": "candy", "shaded": true},
				{"tex": "puff", "amount": 5, "lifetime": 0.45, "emit": "sphere", "radius": 0.25, "spread": 180.0, "vel": Vector2(1.0, 1.8), "damping": Vector2(4, 5),
					"size": Vector2(0.28, 0.4), "curve": "puff", "colors": [[0.0, Color(0.92, 0.78, 0.6)], [1.0, Color(0.92, 0.78, 0.6, 0.0)]]},
			]}
		"pea_splat":
			return {"one_shot": true, "layers": [
				# Juice fix r4: a blended green ring (the additive billboard ring read as a soap bubble).
				{"kind": "ring", "size": 1.2, "time": 0.26, "color": Color(0.45, 0.75, 0.25, 0.85), "start": 0.2, "billboard": true, "tex": "ring"},
				{"mesh": "sphere", "mesh_size": 0.09, "amount": 12, "lifetime": 0.8, "emit": "sphere", "radius": 0.15, "dir": Vector3(0, 1, 0), "spread": 90.0,
					"vel": Vector2(2.5, 4.5), "gravity": Vector3(0, -14, 0), "size": Vector2(0.7, 1.3), "curve": "late_shrink",
					"colors": [[0.0, Color(0.45, 0.8, 0.25)], [1.0, Color(0.35, 0.7, 0.2)]], "shaded": true},
				{"tex": "puff", "amount": 6, "lifetime": 0.45, "emit": "sphere", "radius": 0.1, "spread": 180.0, "vel": Vector2(1.5, 2.5), "damping": Vector2(5, 6),
					"size": Vector2(0.25, 0.4), "curve": "puff", "colors": [[0.0, Color(0.75, 0.95, 0.5)], [1.0, Color(0.7, 0.9, 0.45, 0.0)]]},
			]}
		"hit_stars":
			# Bonk (face-first into a wall): small dizzy stars are allowed here, at 0.25 m or less.
			return {"one_shot": true, "layers": [
				{"tex": "soft_dot", "amount": 1, "lifetime": 0.18, "emit": "point", "size": Vector2(1.4, 1.4), "curve": "pop", "add": true,
					"colors": [[0.0, Color(1, 1, 0.9, 0.9)], [1.0, Color(1, 0.9, 0.6, 0.0)]]},
				# Juice fix r4: rounded inked cream stars (gold is the collectible colour) and inked glints.
				{"tex": "star_ink", "amount": 6, "lifetime": 0.55, "emit": "point", "dir": Vector3(0, 1, 0), "spread": 100.0, "vel": Vector2(3.0, 4.5),
					"damping": Vector2(5, 7), "size": Vector2(0.18, 0.25), "curve": "pop", "colors": [[0.0, Color(1.0, 0.97, 0.9)], [1.0, Color(1.0, 0.97, 0.9, 0.0)]], "spin": 540.0},
				{"tex": "sparkle_ink", "amount": 6, "lifetime": 0.3, "emit": "point", "dir": Vector3(0, 1, 0), "spread": 180.0, "vel": Vector2(4, 6), "damping": Vector2(8, 10),
					"size": Vector2(0.14, 0.22), "curve": "pop", "colors": [[0.0, Color.WHITE], [1.0, Color(1, 1, 1, 0.0)]]},
			]}
		"splash":
			return {"one_shot": true, "layers": [
				{"kind": "ring", "size": 2.2, "time": 0.5, "color": Color(1, 1, 1, 0.9), "start": 0.15},
				{"mesh": "sphere", "mesh_size": 0.07, "amount": 26, "lifetime": 0.8, "emit": "ring", "radius": 0.25, "dir": Vector3(0, 1, 0), "spread": 30.0,
					"vel": Vector2(3.5, 6.0), "gravity": Vector3(0, -16, 0), "size": Vector2(0.6, 1.3), "curve": "late_shrink",
					"colors": [[0.0, Color(0.85, 0.97, 1.0)], [1.0, Color(0.6, 0.88, 1.0)]]},
				{"tex": "puff", "amount": 8, "lifetime": 0.6, "emit": "ring", "radius": 0.3, "dir": Vector3(0, 1, 0), "spread": 60.0, "vel": Vector2(1.0, 2.0),
					"damping": Vector2(3, 4), "size": Vector2(0.35, 0.55), "curve": "puff", "colors": [[0.0, Color(1, 1, 1, 0.95)], [1.0, Color(0.9, 0.97, 1.0, 0.0)]]},
			]}
		"cocoa_splash":
			return {"one_shot": true, "layers": [
				{"kind": "ring", "size": 1.8, "time": 0.45, "color": Color(0.55, 0.3, 0.15, 0.85), "start": 0.15},
				FxPresetsJuice.cocoa_drops(16, Vector2(3.0, 5.0), 0.9),
				{"tex": "puff", "amount": 5, "lifetime": 1.0, "emit": "sphere", "radius": 0.2, "dir": Vector3(0, 1, 0), "spread": 20.0, "vel": Vector2(0.6, 1.2),
					"size": Vector2(0.35, 0.5), "curve": "smoke", "soft": true, "colors": [[0.0, Color(1, 0.97, 0.92, 0.0)], [0.2, Color(1, 0.97, 0.92, 0.6)], [1.0, Color(1, 0.97, 0.92, 0.0)]]},
			]}
		"poof":
			# r1: bursts out and shrinks away fast (no lingering cotton), with a couple of glints instead of stars.
			return {"one_shot": true, "layers": [
				{"tex": "puff", "amount": 12, "lifetime": 0.55, "emit": "sphere", "radius": 0.35, "dir": Vector3(0, 1, 0), "spread": 180.0,
					"vel": Vector2(2.5, 4.0), "damping": Vector2(6, 8), "size": Vector2(0.5, 0.8), "curve": "vanish", "spin": 120.0,
					"colors": [[0.0, Color(1, 1, 1)], [0.6, Color(0.97, 0.96, 0.94, 0.9)], [1.0, Color(0.95, 0.94, 0.92, 0.0)]]},
				{"tex": "glint_ink", "amount": 3, "lifetime": 0.5, "emit": "point", "dir": Vector3(0, 1, 0), "spread": 90.0, "vel": Vector2(2.5, 3.5),
					"damping": Vector2(4, 5), "size": Vector2(0.14, 0.2), "curve": "twinkle", "colors": [[0.0, GOLD_HDR], [1.0, Color(GOLD, 0.0)]], "spin": 40.0},
			]}
		"checkpoint_glow":
			return {"one_shot": true, "layers": [
				{"kind": "ring", "size": 2.4, "time": 0.6, "color": Color(1, 0.9, 0.6, 0.9), "start": 0.2},
				{"tex": "sparkle_ink", "amount": 30, "lifetime": 1.4, "explosiveness": 0.4, "emit": "ring", "radius": 0.8, "dir": Vector3(0, 1, 0), "spread": 5.0,
					"vel": Vector2(1.5, 3.0), "damping": Vector2(0.5, 1.0), "size": Vector2(0.16, 0.28), "curve": "twinkle", "colors": [[0.0, GOLD_HDR], [1.0, Color(GOLD, 0.0)]]},
				{"tex": "soft_dot", "amount": 1, "lifetime": 0.6, "emit": "point", "size": Vector2(2.5, 2.5), "curve": "pop", "add": true,
					"colors": [[0.0, Color(1, 0.85, 0.5, 0.6)], [1.0, Color(1, 0.8, 0.4, 0.0)]]},
				FxPresetsJuice.ground_glow(2.4),
			]}
		"butterflies":
			return {"one_shot": false, "layers": [
				{"tex": "butterfly", "flutter": "flap", "amount": 9, "lifetime": 9.0, "explosiveness": 0.0, "preprocess": 9.0, "emit": "box", "extents": Vector3(6, 1.0, 6),
					"dir": Vector3(1, 0.2, 0), "spread": 180.0, "vel": Vector2(0.4, 0.9), "size": Vector2(0.22, 0.32), "curve": "ambient",
					"palette": "butterfly", "turbulence": 3.0, "turb_scale": 2.0, "world": true},
			]}
		"falling_leaves":
			return {"one_shot": false, "layers": [
				{"tex": "leaf", "flutter": "flip", "amount": 22, "lifetime": 7.0, "explosiveness": 0.0, "preprocess": 7.0, "emit": "box", "extents": Vector3(7, 0.5, 7),
					"dir": Vector3(0.3, -1, 0), "spread": 20.0, "vel": Vector2(0.3, 0.6), "gravity": Vector3(0.25, -0.35, 0), "size": Vector2(0.16, 0.24),
					"curve": "ambient", "palette": "leaves", "spin": 90.0, "turbulence": 1.5, "world": true},
			]}
		"chimney_smoke":
			return {"one_shot": false, "layers": [
				{"tex": "puff", "amount": 14, "lifetime": 3.6, "explosiveness": 0.0, "preprocess": 4.0, "emit": "sphere", "radius": 0.2, "dir": Vector3(0, 1, 0), "spread": 12.0,
					"vel": Vector2(0.9, 1.3), "gravity": Vector3(0.45, 0.15, 0.1), "damping": Vector2(0.1, 0.2), "size": Vector2(0.5, 0.8), "curve": "smoke",
					"colors": [[0.0, Color(0.92, 0.9, 0.88, 0.0)], [0.1, Color(0.92, 0.9, 0.88, 0.9)], [0.7, Color(0.78, 0.78, 0.82, 0.55)], [1.0, Color(0.75, 0.76, 0.8, 0.0)]],
					"spin": 25.0, "turbulence": 0.6, "world": true, "shaded": false, "soft": true},
			]}
		"waterfall_foam":
			return {"one_shot": false, "layers": [
				{"tex": "puff", "amount": 30, "lifetime": 1.3, "explosiveness": 0.0, "preprocess": 2.0, "emit": "box", "extents": Vector3(1.2, 0.1, 0.4), "dir": Vector3(0, 1, 0.3),
					"spread": 35.0, "vel": Vector2(1.0, 2.0), "gravity": Vector3(0, -1.5, 0), "damping": Vector2(1, 2), "size": Vector2(0.45, 0.8), "curve": "puff",
					"colors": [[0.0, Color(1, 1, 1, 0.95)], [1.0, Color(0.9, 0.97, 1.0, 0.0)]], "spin": 40.0, "world": true},
				{"tex": "soft_dot", "amount": 40, "lifetime": 0.9, "explosiveness": 0.0, "emit": "box", "extents": Vector3(1.2, 0.1, 0.4), "dir": Vector3(0, 1, 0.4), "spread": 45.0,
					"vel": Vector2(2.5, 4.0), "gravity": Vector3(0, -9, 0), "size": Vector2(0.06, 0.12), "curve": "shrink", "add": true,
					"colors": [[0.0, Color(1, 1, 1, 0.9)], [1.0, Color(0.8, 0.95, 1.0, 0.0)]], "world": true},
			]}
		"gust_motes":
			return {"one_shot": false, "layers": [
				{"tex": "streak", "amount": 10, "lifetime": 1.0, "explosiveness": 0.0, "emit": "box", "extents": Vector3(1.5, 1.2, 1.5), "dir": Vector3(1, 0, 0), "spread": 8.0,
					"vel": Vector2(5, 8), "size": Vector2(0.5, 0.9), "curve": "breathe", "add": true,
					"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.4, Color(1, 1, 1, 0.5)], [1.0, Color(1, 1, 1, 0.0)]]},
				{"tex": "leaf", "flutter": "flip", "amount": 4, "lifetime": 1.4, "explosiveness": 0.0, "emit": "box", "extents": Vector3(1.5, 1.0, 1.5), "dir": Vector3(1, 0.2, 0),
					"spread": 15.0, "vel": Vector2(4, 6), "size": Vector2(0.14, 0.2), "curve": "ambient", "palette": "leaves", "spin": 300.0},
			]}
	return FxPresetsJuice.get_preset(name)


# ---------------------------------------------------------------- builders

static func _curve(kind: String) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 2.0
	match kind:
		"puff":
			# Juice fix r1: peak at 25% of life, then shrink (it used to keep growing into cotton balls).
			c.add_point(Vector2(0, 0.45)); c.add_point(Vector2(0.25, 1.0)); c.add_point(Vector2(0.7, 0.62)); c.add_point(Vector2(1, 0.3))
		"vanish":
			# Burst out fast, then shrink away (cloud vanish, defeat poofs).
			c.add_point(Vector2(0, 0.7)); c.add_point(Vector2(0.12, 1.1)); c.add_point(Vector2(0.3, 0.9)); c.add_point(Vector2(1, 0.0))
		"twinkle":
			# Glints: pop in, then a scale-pulse twinkle while fading.
			c.add_point(Vector2(0, 0.0)); c.add_point(Vector2(0.08, 1.25)); c.add_point(Vector2(0.22, 0.65)); c.add_point(Vector2(0.38, 1.05))
			c.add_point(Vector2(0.56, 0.55)); c.add_point(Vector2(0.74, 0.85)); c.add_point(Vector2(1, 0.0))
		"pop":
			c.add_point(Vector2(0, 0.0)); c.add_point(Vector2(0.15, 1.15)); c.add_point(Vector2(0.35, 1.0)); c.add_point(Vector2(1, 0.0))
		"pop_long":
			c.add_point(Vector2(0, 0.0)); c.add_point(Vector2(0.1, 1.2)); c.add_point(Vector2(0.25, 1.0)); c.add_point(Vector2(0.8, 0.8)); c.add_point(Vector2(1, 0.0))
		"shrink":
			c.add_point(Vector2(0, 1.0)); c.add_point(Vector2(1, 0.0))
		"late_shrink":
			c.add_point(Vector2(0, 1.0)); c.add_point(Vector2(0.75, 1.0)); c.add_point(Vector2(1, 0.0))
		"bang":
			# Cartoon pop-in with an elastic settle, hold, quick shrink (the "!" over a noticing enemy).
			c.add_point(Vector2(0, 0.0)); c.add_point(Vector2(0.07, 1.35)); c.add_point(Vector2(0.15, 0.9)); c.add_point(Vector2(0.22, 1.06))
			c.add_point(Vector2(0.3, 1.0)); c.add_point(Vector2(0.82, 1.0)); c.add_point(Vector2(1, 0.0))
		"breathe":
			c.add_point(Vector2(0, 0.6)); c.add_point(Vector2(0.5, 1.0)); c.add_point(Vector2(1, 0.6))
		"smoke":
			c.add_point(Vector2(0, 0.3)); c.add_point(Vector2(1, 1.8))
		"ambient":
			c.add_point(Vector2(0, 0.0)); c.add_point(Vector2(0.06, 1.0)); c.add_point(Vector2(0.94, 1.0)); c.add_point(Vector2(1, 0.0))
		"firefly":
			c.add_point(Vector2(0, 0.0)); c.add_point(Vector2(0.15, 1.0)); c.add_point(Vector2(0.35, 0.7)); c.add_point(Vector2(0.55, 1.0)); c.add_point(Vector2(0.85, 0.8)); c.add_point(Vector2(1, 0.0))
		"impact":
			# Juice fix r2 hit star: frame 1 at 60%, frame 2 overshoots to 110%, then holds while it erodes hollow.
			c.add_point(Vector2(0, 0.6)); c.add_point(Vector2(0.2, 1.1)); c.add_point(Vector2(0.45, 1.0)); c.add_point(Vector2(1, 0.96))
		"dust":
			# Ground dust crescent: puffs up fast, then settles a little while the shader erodes it away.
			c.add_point(Vector2(0, 0.5)); c.add_point(Vector2(0.18, 1.0)); c.add_point(Vector2(1, 0.85))
		_:
			c.add_point(Vector2(0, 1.0)); c.add_point(Vector2(1, 1.0))
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _gradient(stops: Array, tint: Color) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append((s[1] as Color) * tint)
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.use_hdr = true
	t.gradient = g
	return t


static func _palette(kind: Variant) -> GradientTexture1D:
	var cols: Array
	match kind:
		"butterfly":
			cols = [Color(1.0, 0.86, 0.3), Color(1, 1, 1), Color(1.0, 0.62, 0.75), Color(0.55, 0.75, 1.0), Color(1.0, 0.6, 0.3)]
		"leaves":
			cols = [Color(0.95, 0.62, 0.22), Color(0.88, 0.4, 0.2), Color(0.98, 0.8, 0.3), Color(0.55, 0.72, 0.28)]
		"bee":
			cols = [Color(1.0, 0.82, 0.2), Color(0.2, 0.17, 0.15), Color(1.0, 0.9, 0.5), Color(1, 1, 1)]
		"candy":
			cols = [Color(1.0, 0.55, 0.7), Color(0.55, 0.92, 0.75), Color(1.0, 0.95, 0.95), Color(1.0, 0.75, 0.35), Color(0.75, 0.6, 1.0)]
		"candy_glow":
			cols = [Color(1.7, 1.1, 1.4), Color(1.1, 1.7, 1.4), Color(1.7, 1.6, 1.5), Color(1.6, 1.4, 0.8)]
		"petals":
			cols = [Color(1.0, 0.85, 0.92), Color(1, 1, 1), Color(0.95, 0.8, 1.0), Color(1.0, 0.95, 0.7)]
		"celebrate":
			# Juice fix r4 (critic r2: pastel cyan, sky-blue and pink confetti competed with the gold motif): gold #FFC93C,
			# cream #F3E6C4, burgundy #7A1F2E, brass #C9A04A and one accent (storybook rose).
			cols = [Color("#FFC93C"), Color("#F3E6C4"), Color("#7A1F2E"), Color("#C9A04A"), Color("#FFC93C"), Color("#E58A9A")]
		_:
			cols = [Color(1.0, 0.82, 0.25), Color(0.95, 0.35, 0.45), Color(0.4, 0.75, 1.0), Color(0.55, 0.88, 0.45), Color(1.0, 0.6, 0.85), Color(1, 1, 1)]
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	var pc := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / cols.size())
		pc.append(cols[i])
	g.offsets = offs
	g.colors = pc
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _sprite_material(tex: String, additive: bool, flutter: String, align: bool, soft: bool = false, on_top: bool = false) -> Material:
	var key := "%s|%s|%s|%s|%s|%s" % [tex, additive, flutter, align, soft, on_top]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: Material
	if tex in INKED and not additive and flutter == "":
		# Juice fix r2: inked sprites that erode instead of fading (fx_inked.gdshader). impact_star goes hollow from the
		# centre (mode 0, no soft depth so it sits cleanly in front of the target); dust and drops erode from the edge.
		var im := ShaderMaterial.new()
		im.shader = load("res://assets/shaders/fx_inked_top.gdshader" if on_top else "res://assets/shaders/fx_inked.gdshader")
		im.set_shader_parameter("sprite", load(TEX + tex + ".webp"))
		im.set_shader_parameter("mode", 0 if tex == "impact_star" else 1)
		im.set_shader_parameter("use_depth", tex in INKED_DEPTH)
		if on_top:
			im.render_priority = 10
		m = im
	elif tex == "puff" and not additive and not soft and flutter == "":
		# Juice stage: cartoon toon-shaded puffs that erode instead of fading (fx_puff.gdshader).
		var pm := ShaderMaterial.new()
		pm.shader = load("res://assets/shaders/fx_puff.gdshader")
		m = pm
	elif flutter != "":
		var sm := ShaderMaterial.new()
		sm.shader = load("res://assets/shaders/fx_flutter.gdshader")
		sm.set_shader_parameter("sprite", load(TEX + tex + ".webp"))
		sm.set_shader_parameter("flip_mode", flutter == "flip")
		sm.set_shader_parameter("flap_amount", 0.85 if flutter == "flap" else 0.9)
		sm.set_shader_parameter("flap_speed", 16.0 if flutter == "flap" else 4.0)
		if tex == "page":
			# Parchment pages: never below mid-tone, never fully edge-on, a gold glint as they turn to camera.
			sm.set_shader_parameter("lift", 0.3)
			sm.set_shader_parameter("glint", 0.5)
			sm.set_shader_parameter("min_width", 0.35)
		m = sm
	else:
		var s := StandardMaterial3D.new()
		s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		s.vertex_color_use_as_albedo = true
		# Particle colours are authored in sRGB; convert so gold stays gold after tonemapping.
		s.vertex_color_is_srgb = true
		s.albedo_texture = load(TEX + tex + ".webp")
		s.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		s.billboard_keep_scale = true
		s.cull_mode = BaseMaterial3D.CULL_DISABLED
		s.disable_receive_shadows = true
		s.proximity_fade_enabled = not additive and not on_top
		s.proximity_fade_distance = 0.25
		if on_top:
			# Contact sparks read through the target's body (the camera sits behind Mak).
			s.no_depth_test = true
			s.render_priority = 10
		m = s
	_mat_cache[key] = m
	return m


static func _mesh_for(layer: Dictionary) -> Mesh:
	var shaded: bool = layer.get("shaded", false)
	var kind: String = layer.get("mesh", "")
	var mesh: PrimitiveMesh
	var sz: float = layer.get("mesh_size", 0.1)
	match kind:
		"box", "pebble":
			# Juice fix r1: rounded low-poly pebble instead of a razor-edged cube (ART_V2: no razor edges).
			var pb := SphereMesh.new()
			pb.radius = sz * 0.6
			pb.height = sz * 0.85
			pb.radial_segments = 7
			pb.rings = 3
			mesh = pb
		"biscuit":
			# Gingerbread crumb chunk: a bevelled, slightly irregular biscuit puck.
			var bc := CylinderMesh.new()
			bc.top_radius = sz * 0.5
			bc.bottom_radius = sz * 0.58
			bc.height = sz * 0.42
			bc.radial_segments = 7
			bc.rings = 1
			mesh = bc
		"gumdrop":
			var gd := CylinderMesh.new()
			gd.top_radius = sz * 0.3
			gd.bottom_radius = sz * 0.55
			gd.height = sz * 0.7
			gd.radial_segments = 10
			gd.rings = 2
			mesh = gd
		"sphere":
			var s := SphereMesh.new()
			s.radius = sz
			s.height = sz * 2.0
			s.radial_segments = 10
			s.rings = 6
			mesh = s
		"plank":
			var pl := BoxMesh.new()
			pl.size = Vector3(sz * 0.22, sz * 0.08, sz)
			mesh = pl
		"confetti":
			var c := BoxMesh.new()
			c.size = Vector3(0.15, 0.008, 0.09)
			mesh = c
			shaded = true
		_:
			var q := QuadMesh.new()
			q.size = Vector2.ONE
			mesh = q
	if layer.get("streak", false):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		q.material = _streak_material(layer.get("stretch", 3.0), layer.get("taper", 0.85), layer.get("add", true))
		if layer.get("on_top", false):
			var om := (q.material as ShaderMaterial).duplicate() as ShaderMaterial
			om.render_priority = 10
			q.material = om
		return q
	if kind != "":
		var key := "mesh|%s" % shaded
		var m: StandardMaterial3D
		if _mat_cache.has(key):
			m = _mat_cache[key]
		else:
			m = StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.roughness = 0.6
			if not shaded:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.rim_enabled = shaded
			m.rim = 0.4
			_mat_cache[key] = m
		mesh.material = m
	else:
		mesh.material = _sprite_material(layer.get("tex", "soft_dot"), layer.get("add", false), layer.get("flutter", ""), layer.get("align", false), layer.get("soft", false), layer.get("on_top", false))
	return mesh


static func _streak_material(stretch: float, taper: float, additive: bool) -> Material:
	var key := "streak|%s|%s|%s" % [stretch, taper, additive]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/fx_streak_mix.gdshader" if not additive else "res://assets/shaders/fx_streak.gdshader")
	sm.set_shader_parameter("stretch", stretch)
	sm.set_shader_parameter("taper", taper)
	_mat_cache[key] = sm
	return sm


static func make_particles(layer: Dictionary, intensity: float, tint: Color, one_shot_effect: bool) -> GeometryInstance3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	var looping: bool = not one_shot_effect
	p.one_shot = not looping
	p.emitting = false
	p.amount = maxi(1, int(round(layer.get("amount", 8) * clampf(intensity, 0.3, 3.0))))
	p.lifetime = layer.get("lifetime", 1.0)
	p.explosiveness = layer.get("explosiveness", 1.0)
	p.randomness = 0.3
	p.preprocess = layer.get("preprocess", 0.0)
	# World-space simulation by default: emitted particles stay where they were born.
	# "local": true keeps them in the effect's space (orbiting dizzy stars, attached auras).
	p.local_coords = layer.get("local", false)
	# Only big chunks (planks, bricks) cast shadows; confetti, crumbs and beads are redrawn in every cascade for nothing.
	var big_mesh: bool = layer.get("mesh", "") != "" and layer.get("mesh", "") != "confetti" and float(layer.get("mesh_size", 0.1)) >= 0.15
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if big_mesh or layer.get("shadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = layer.get("aabb", AABB(Vector3(-8, -4, -8), Vector3(16, 12, 16)))
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	match layer.get("emit", "point"):
		"sphere":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = layer.get("radius", 0.2) * intensity
		"sphere_surface":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
			pm.emission_sphere_radius = layer.get("radius", 0.5) * intensity
		"ring":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = layer.get("radius", 0.3) * intensity
			pm.emission_ring_inner_radius = layer.get("radius", 0.3) * intensity * 0.7
			pm.emission_ring_height = 0.05
		"box":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = layer.get("extents", Vector3.ONE)
		_:
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	# Juice fix r1, the cotton-ball blocker: one-shot toon puffs are smaller, sink instead of floating past Mak's head,
	# and erode from about 40% of life (alpha 0.6 by 45%). Loops, ambient and soft smoke keep their own look.
	if layer.get("tex", "") == "puff" and one_shot_effect and not layer.get("soft", false) and not layer.get("keep_puff", false):
		layer = layer.duplicate()
		var ps: Vector2 = layer.get("size", Vector2(0.3, 0.5))
		layer["size"] = ps * 0.66
		var g: Vector3 = layer.get("gravity", Vector3.ZERO)
		layer["gravity"] = Vector3(g.x, minf(g.y, 0.0) - 0.6, g.z)
		if layer.has("colors"):
			layer["colors"] = _puff_alpha(layer["colors"])
	# Juice fix r4 (VFX art critic r2: two style families): every non-soft puff is drawn with the inked lobed puff cards
	# (three variants, picked per layer), eroded by fx_inked like the dust crescents. Soft smoke and wisps keep the soft puff.
	if layer.get("tex", "") == "puff" and not layer.get("soft", false):
		layer = layer.duplicate()
		layer["tex"] = PUFF_INK[absi(hash(str(layer.get("amount", 0)) + str(layer.get("size", Vector2.ZERO)))) % PUFF_INK.size()]
	pm.direction = layer.get("dir", Vector3.UP)
	pm.spread = layer.get("spread", 45.0)
	var vel: Vector2 = layer.get("vel", Vector2(1, 2))
	pm.initial_velocity_min = vel.x * sqrt(intensity)
	pm.initial_velocity_max = vel.y * sqrt(intensity)
	pm.gravity = layer.get("gravity", Vector3.ZERO)
	var damp: Vector2 = layer.get("damping", Vector2.ZERO)
	pm.damping_min = damp.x
	pm.damping_max = damp.y
	var sz: Vector2 = layer.get("size", Vector2(0.3, 0.5))
	pm.scale_min = sz.x * intensity
	pm.scale_max = sz.y * intensity
	pm.scale_curve = _curve(layer.get("curve", ""))
	var spin: float = layer.get("spin", 0.0)
	if spin > 0.0:
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -spin
		pm.angular_velocity_max = spin
	if layer.has("angle"):
		# Juice fix r2: a limited initial tilt (ground dust crescents stay upright).
		pm.angle_min = -float(layer["angle"])
		pm.angle_max = float(layer["angle"])
	if layer.has("flat"):
		# 1.0 keeps the launch directions in the emitter's XZ plane (ground-hugging dust).
		pm.flatness = float(layer["flat"])
	if layer.has("colors"):
		pm.color_ramp = _gradient(layer["colors"], tint)
	if layer.has("palette"):
		pm.color_initial_ramp = _palette(layer["palette"])
		if not layer.has("colors"):
			pm.color_ramp = _gradient([[0.0, Color.WHITE], [1.0, Color.WHITE]], tint)
	if layer.get("tumble", false):
		pm.particle_flag_rotate_y = true
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -540.0
		pm.angular_velocity_max = 540.0
		pm.particle_flag_align_y = layer.get("mesh", "") == "confetti"
	if layer.has("orbit"):
		var ob: Vector2 = layer["orbit"]
		pm.orbit_velocity_min = ob.x
		pm.orbit_velocity_max = ob.y
	if layer.has("radial"):
		var rv: Vector2 = layer["radial"]
		pm.radial_velocity_min = rv.x
		pm.radial_velocity_max = rv.y
	if layer.has("tangential"):
		var tv: Vector2 = layer["tangential"]
		pm.tangential_accel_min = tv.x
		pm.tangential_accel_max = tv.y
	if layer.get("streak", false):
		pm.particle_flag_align_y = true
		pm.angle_min = 0.0
		pm.angle_max = 0.0
		pm.angular_velocity_min = 0.0
		pm.angular_velocity_max = 0.0
	var turb: float = layer.get("turbulence", 0.0)
	if turb > 0.0:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = turb
		pm.turbulence_noise_scale = layer.get("turb_scale", 4.0)
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
	p.position = layer.get("offset", Vector3.ZERO)
	p.process_material = pm
	p.draw_pass_1 = _mesh_for(layer)
	if OS.has_feature("web"):
		# Compatibility sorts GPU particles by reading them back to the CPU.
		# Opaque depth-tested meshes and additive light commute: sorting those
		# layers adds a GPU stall without changing their compositing. Keep view
		# sorting for every alpha-blended puff, leaf and feather.
		var draw_material := p.draw_pass_1.surface_get_material(0)
		var order_independent := false
		if draw_material is BaseMaterial3D:
			order_independent = draw_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
				or draw_material.blend_mode == BaseMaterial3D.BLEND_MODE_ADD
		elif draw_material is ShaderMaterial and draw_material.shader != null:
			order_independent = draw_material.shader.code.contains("blend_add")
		if order_independent:
			p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
		var adapter := preload("res://scripts/fx/web_cpu_particles.gd")
		if adapter.supported(pm):
			var cpu := adapter.new()
			cpu.setup(p)
			p.free()
			return cpu
		# ROUND3: the emitters left on the GPU (turbulence, radial velocity) were still sorted by view depth, which reads
		# each of them back from the GPU every frame and makes the browser wait for the GPU each time (W3: 12,362
		# readbacks in 15 s at the gameplay camera). Emission order needs no readback; overlapping alpha puffs now
		# blend in the order they were emitted instead of back to front.
		p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	return p


## Re-samples a puff colour ramp so alpha (which drives the erosion holes) reads 1.0, 0.85 at 20%, 0.6 at 45%,
## 0.25 at 75% and 0 at the end: the ball breaks up early instead of staying opaque.
static func _puff_alpha(stops: Array) -> Array:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for st in stops:
		offs.append(float(st[0]))
		cols.append(st[1] as Color)
	g.offsets = offs
	g.colors = cols
	var out: Array = []
	for pair in [[0.0, 1.0], [0.2, 0.85], [0.45, 0.6], [0.75, 0.25], [1.0, 0.0]]:
		var c: Color = g.sample(pair[0])
		var a0: Color = g.sample(0.0)
		c.a = minf(a0.a, 1.0) * float(pair[1])
		out.append([pair[0], c])
	return out


static func make_ring(layer: Dictionary, _intensity: float, _tint: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var billboard: bool = layer.get("billboard", false)
	if not billboard:
		q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.position = Vector3(0, 0.06, 0) if not billboard else Vector3(0, 0.4, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if billboard else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = load(TEX + String(layer.get("tex", "ring")) + ".webp")
	if layer.has("tex"):
		# Decal-style rings (the Ham Slam splat) are blended, not added, so the ink reads on bright ground.
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.render_priority = 1
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Flat annulus sector for smear arcs (fx_swish.gdshader). Layer keys: radius (outer, m), width (m),
## degrees (sweep), tilt (degrees about the forward axis; 0 = horizontal, 90 = vertical), yaw (degrees),
## height (m), color, edge, time, tail, reverse (sweep right-to-left).
static func make_arc(layer: Dictionary, intensity: float, tint: Color) -> MeshInstance3D:
	var outer: float = layer.get("radius", 1.0) * intensity
	var inner: float = maxf(outer - float(layer.get("width", 0.5)) * intensity, 0.02)
	var deg: float = layer.get("degrees", 160.0)
	var segs := 24
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rev: bool = layer.get("reverse", false)
	for i in segs:
		var u0 := float(i) / segs
		var u1 := float(i + 1) / segs
		var a0 := deg_to_rad(-deg * 0.5 + deg * (u0 if not rev else 1.0 - u0))
		var a1 := deg_to_rad(-deg * 0.5 + deg * (u1 if not rev else 1.0 - u1))
		# Angle 0 points along -Z (forward); positive angles sweep to +X (right).
		var d0 := Vector3(sin(a0), 0, -cos(a0))
		var d1 := Vector3(sin(a1), 0, -cos(a1))
		var v := [d0 * inner, d0 * outer, d1 * outer, d1 * inner]
		var uv := [Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, layer.get("height", 0.7), 0)
	mi.rotation_degrees = Vector3(0, layer.get("yaw", 0.0), layer.get("tilt", 0.0))
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/fx_swish.gdshader")
	m.set_shader_parameter("color", (layer.get("color", Color(1.0, 0.97, 0.88)) as Color) * tint)
	m.set_shader_parameter("edge_color", (layer.get("edge", Color(1.0, 0.82, 0.4)) as Color) * tint)
	m.set_shader_parameter("inner_color", (layer.get("inner", Color(0.95, 0.6, 0.64)) as Color) * tint)
	m.set_shader_parameter("ink", layer.get("ink", 0.6))
	m.set_shader_parameter("speed_lines", layer.get("speed_lines", 1.0))
	m.set_shader_parameter("tail", layer.get("tail", 0.55))
	m.set_shader_parameter("opacity", layer.get("opacity", 0.95))
	m.set_shader_parameter("progress", 0.0)
	mi.material_override = m
	return mi


## Expanding stylised shock ring (fx_shock_ring.gdshader). Layer keys: size (diameter, m), time, color, glow,
## ink, thickness, refraction, billboard, height.
static func make_shock(layer: Dictionary, intensity: float, tint: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	var size: float = layer.get("size", 4.0) * intensity
	q.size = Vector2(size, size)
	var billboard: bool = layer.get("billboard", false)
	if not billboard:
		q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	# Juice fix r2: `offset` places the ring anywhere in the effect frame (an air pop at the fist, 0.9 m ahead).
	mi.position = layer.get("offset", Vector3(0, layer.get("height", 0.08), 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	var sh_path := "res://assets/shaders/fx_shock_ring_bb.gdshader" if billboard else "res://assets/shaders/fx_shock_ring.gdshader"
	if billboard and layer.get("on_top", false):
		sh_path = "res://assets/shaders/fx_shock_ring_bb_top.gdshader"
	m.shader = load(sh_path)
	if layer.get("on_top", false):
		m.render_priority = 10
	# Juice fix r2: warm cream #FFF4DC bands with an ink #3B2416 outer lip (no neutral grey anywhere in ART_V2).
	m.set_shader_parameter("color", (layer.get("color", Color(1.0, 0.957, 0.863)) as Color) * tint)
	m.set_shader_parameter("glow_color", (layer.get("glow", Color(1.0, 0.78, 0.4)) as Color) * tint)
	m.set_shader_parameter("ink_color", layer.get("ink_color", Color(0.231, 0.141, 0.086)))
	m.set_shader_parameter("ink", maxf(float(layer.get("ink", 0.8)), 0.8) if float(layer.get("ink", 0.8)) > 0.0 else 0.0)
	m.set_shader_parameter("thickness", layer.get("thickness", 0.22))
	m.set_shader_parameter("refraction", layer.get("refraction", 0.025))
	m.set_shader_parameter("breakup", layer.get("breakup", 0.45))
	m.set_shader_parameter("opacity", layer.get("opacity", 0.95))
	m.set_shader_parameter("seed", randf())
	m.set_shader_parameter("progress", 0.0)
	mi.material_override = m
	return mi

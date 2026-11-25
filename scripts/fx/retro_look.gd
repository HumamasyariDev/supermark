extends Node
## RetroLook autoload (D032 + D034, Docs/ART_V3_RETRO.md): clean retro "64-bit era" texture style plus the visual hierarchy
## pass ("not a cheap mobile demo"). Everything is applied at runtime and is fully reversible, so the setting can be toggled live.
##
## What it does once per material / texture:
##  - Texture filter: NEAREST_WITH_MIPMAPS on StandardMaterial3D surfaces. The custom shaders (toon, terrain, water, foliage,
##    hot chocolate) switch to a "#define RETRO_LOOK" variant; the world shaders listed in WORLD_SHADERS (W1/W3 terrain,
##    W3 frosting, W2 cloud decks, hub rugs ...) get a generated variant with nearest-mipmap samplers, optional world-space
##    texel snapping and a matte finish. cloud.gdshader is left untouched (round-1 blocker: the variant greyed the clouds).
##  - Environment budget (fix round 1, D034 B1): every environment surface goes through retro_calm() at the end of its fragment
##    shader (or the same maths on StandardMaterial3D colours and textures): saturation capped at ENV_SAT_TOP on walkable tops and
##    ENV_SAT_WALL on walls, a per-world value multiplier (W2/W3 are darkened, the gameplay layer is not). The world grade no
##    longer desaturates the whole frame, so the gameplay layer keeps its colour.
##  - Texture size and palette: albedo textures are downscaled in memory to the category size and palette-reduced.
##    Tileable textures with an offline "<name>_retro.png" (tools/retro_textures.py: low-res originals) use that file instead.
##    Results are cached on disk in user://retro_cache/. Characters keep near-authored detail (512 px, 64 colours) so faces
##    do not stair-step; truffles are mapped onto a fixed gold ramp. Textures for nodes spawned mid-game are reduced on a
##    worker thread and swapped in when ready (no main-thread hitch).
##  - Matte pass (D034) on environment materials: roughness 0.9-1, specular near 0, metallic 0, no rim, clearcoat or normal
##    maps. Gold, brass, glass and water keep their shine.
##  - Gameplay pop (D034), through node groups only: nodes in player / enemy / boss / npc / talker / pickup / collectible /
##    truffle / acorn / lost_page get a rim pass (retro_pop.gdshader, gated to the shadow side; a complementary rim per
##    world and an off-palette enemy accent), one thin outline rule (D037: OUTLINE_PX at the real viewport height for the
##    hero, enemies, boss and pickups; none on NPCs and the environment), truffles a gold glint plus cool twinkles
##    (retro_glint.gdshader), and a BlobShadow under every moving actor and pickup (their own sun shadow is switched off).
##  - One shading model (D037): lit, opaque StandardMaterial3D surfaces switch to toon twins of toon.gdshader (see
##    _toonable for the exceptions), so GLB imports no longer read as "casual PBR" next to the toon props.
##  - Per-world grade preset (fog pushed back off the playfield, restrained bloom; PRESETS below).
## State is stored on each resource (metadata "retro_state"), so it is freed with the scene; the autoload keeps WeakRefs only.
## Toggle: Game setting "classic_textures" (default true) and the dev argument --retro=0/1. --retro-vertex=1 also switches
## environment StandardMaterial3D surfaces to per-vertex shading (A/B option). --retro-pop=0 disables the gameplay pop layer.
## Evidence mode: --retro-shots=<abs dir> [--retro-cams=StoryCam_A,StoryCam_B] [--retro-wait=150] [--retro-areas=...]
## captures frozen retro off/on pairs (gameplay camera first, then story cameras, then close-ups), a gameplay mask and a
## frame-time comparison at 1920x1080 with the HUD hidden, then quits.

signal applied(stats: Dictionary)

## Our own shaders with "#ifdef RETRO_LOOK" blocks (cloud.gdshader is deliberately absent).
const RETRO_SHADER_PATHS := [
	"res://assets/shaders/toon.gdshader", "res://assets/shaders/terrain.gdshader", "res://assets/shaders/water.gdshader",
	"res://assets/shaders/foliage.gdshader", "res://assets/shaders/hot_chocolate.gdshader"]
## World shaders owned by other tracks: RetroLook generates the retro variant itself (no edits to their files).
## wpos: the world-position varying to snap to a texel grid (tpm texels per metre); matte: force roughness/specular;
## val: extra value multiplier for that surface; emission: multiplier on EMISSION (sheen); calm: apply the saturation budget.
const WORLD_SHADERS := {
	"res://assets/environment/w1/w1_terrain.gdshader": {"matte": true},
	"res://assets/environment/w1/w1_patchwork.gdshader": {"matte": true},
	"res://assets/environment/w3/w3_terrain.gdshader": {"wpos": "v_wpos", "tpm": 32.0, "matte": true, "sat_top": 0.4},
	"res://assets/environment/w3/w3_frosting.gdshader": {"wpos": "wpos", "tpm": 32.0, "matte": true, "emission": 0.45},
	"res://assets/environment/w3/w3_swirl.gdshader": {"matte": true},
	"res://assets/environment/w3/w3_liquid.gdshader": {"val": 0.85},
	"res://assets/environment/w2/w2_cloud_deck.gdshader": {"matte": true, "val": 0.9, "calm": false},
	"res://assets/environment/hub/hub_rug.gdshader": {"matte": true},
	"res://assets/environment/hub/hub_tapestry.gdshader": {"matte": true},
	"res://assets/environment/hub/hub_pennant.gdshader": {"matte": true}}
## Retro texel density (fix round 1): tile scales of the terrain shaders while the look is on, so the 64 px authored tiles
## land at about 16 texels per metre on grass and rock (they were 6-14 m per tile). Path tiles keep their authored scale.
## Look polish 2026-10-19 (owner: "the stones are stylized terribly ... why are the patterns so large, so pixelated and
## broken?"): terrain rock tiles every 2 m (was 5 m: 13 texels/m, crack lines 8 cm stair-steps), matching ROCK_TILE_M.
## OPUSLOOK (Stefan: "textures consistent"): grass, dirt paths and cobbles tile every 2 m as well, so all ground lands at
## 32 texels per metre like the rock and the UV-mapped props (PROP_TPM). Grass was 16, paths 12.8 (pebbles about 1 m
## across next to a 1 m hero) and cobbles 22.4; W3's painted ground snaps at the same 32 per metre (was 12).
const TERRAIN_SCALES := {"grass_scale": 0.5, "rock_scale": 0.5, "dirt_scale": 0.5, "cobble_scale": 0.5}
## World-space texel density (look polish 2026-10-19). Triplanar rock and stone textures on props (kit boulders, cleft
## walls, tor pillars) tile at most every ROCK_TILE_M metres, so their 64 px retro tiles land at ~32 texels/m like the
## terrain rock instead of 1 m cells with 5-10 cm stair-stepped cracks.
const ROCK_TILE_M := 2.0
const ROCK_WORDS := ["cliff_rock", "cobblestone", "castle_stone"]
## UV-mapped environment props (GLB imports): the texture budget follows the mesh's world size and UV layout, so big props
## (trees, houses, the stick hut) do not get 10-25 cm texels from a fixed 256 px atlas. PROP_TPM texels per metre, the
## result clamped to [PROP_TEX_MIN, PROP_TEX_MAX] and to the source size.
const PROP_TPM := 32.0
const PROP_TEX_MIN := 256
const PROP_TEX_MAX := 1024
## Untextured foliage and stone blobs (sphere puffs: hedges, willow and kit tree crowns, dry-stone wall, kit boulders)
## read as smooth plain spheres next to the textured trees: their toon twin gets a world-space detail texture (the leaf or
## rock retro tile reduced to a value-only modulation), so they band and break up like the rest of the set.
const LEAF_DETAIL := "res://assets/textures/leaf_canopy_retro.png"
const STONE_DETAIL := "res://assets/textures/cliff_rock_retro.png"
const LEAF_TILE_M := 1.7
const STONE_TILE_M := 1.2
const LEAF_WORDS := ["hedge", "leaf", "leaves", "canopy", "bush", "willow", "puff", "crown", "foliage", "shrub", "tree", "topiary"]
const STONE_WORDS := ["stone", "rock", "boulder", "cairn", "pebble", "grotto"]
const CANOPY_WORDS := ["canopy", "leaves", "foliage", "crown", "hedge", "bush"]
const POP_SHADER_PATH := "res://assets/shaders/retro_pop.gdshader"
const GLINT_SHADER_PATH := "res://assets/shaders/retro_glint.gdshader"
const OUTLINE_SHADER_PATH := "res://assets/shaders/outline.gdshader"
const BLOB_SCRIPT_PATH := "res://scripts/fx/blob_shadow.gd"
const CACHE_DIR := "user://retro_cache/"
const WEB_CACHE := "res://web_cache/retro/"
## Bump whenever TEX_RULES, palettize or the gold ramp change (the key also holds the source file's modification time).
const CACHE_VERSION := "r3"
const META := "retro_state"
const ENV_META := "retro_env_orig"

## Environment saturation budget (HSV saturation in sRGB, 0-1): walkable tops / walls and cliffs (D034 B1).
const ENV_SAT_TOP := 0.45
const ENV_SAT_WALL := 0.35
## Gameplay colour boost (StandardMaterial3D colours and toon albedo of enemies, NPCs and pickups).
const GAME_SAT_BOOST := 1.18

## Gameplay groups and the role each one gets (aliases cover the groups the current scenes actually use).
const GROUP_ROLES := {"player": "hero", "enemy": "enemy", "boss": "boss", "npc": "npc", "talker": "npc",
	"truffle": "truffle", "pickup": "pickup", "collectible": "pickup", "acorn": "pickup", "lost_page": "pickup",
	"hazard": "hazard"}
## Texture category -> [max size px, palette colours, saturation multiplier, saturation cap (1 = none)].
const TEX_RULES := {
	"env_tile": [128, 24, 0.72, ENV_SAT_TOP], "env_prop": [256, 32, 0.72, ENV_SAT_TOP],
	"hero": [512, 64, 1.0, 1.0], "enemy": [256, 48, 1.25, 1.0], "boss": [512, 64, 1.15, 1.0],
	"npc": [512, 64, 1.08, 1.0], "pickup": [128, 32, 1.25, 1.0], "truffle": [128, 6, 1.0, 1.0],
	"hazard": [256, 40, 1.15, 1.0], "face": [512, 64, 1.0, 1.0]}
## Words in a material / texture name that mark surfaces allowed to shine (D034).
const SHINY_WORDS := ["gold", "brass", "truffle", "water", "glass", "coin", "gem", "metal_trim"]
## Surfaces that keep their own colour and finish (sky-lit clouds, light sources): only the texture filter changes.
const KEEP_WORDS := ["cloud", "sky", "glow", "lamp", "flame", "fire", "candle", "window", "stained", "lantern"]

## Pop pass per role: rim strength, shadow-side gate, outline (add if missing), outline width (px at 1080p), max outline
## world width (m), outline fade by projected radius, distance fade, glint, lift.
const POP := {
	"hero": {"rim_strength": 0.25, "gate": 1.0, "outline": false, "width": 2.0, "max_w": 0.03, "fade_px": 0.0, "far": 60.0,
		"glint": 0.0, "lift": 0.0},
	"enemy": {"rim_strength": 0.55, "gate": 0.6, "outline": true, "width": 2.4, "max_w": 0.05, "fade_px": 0.0, "far": 90.0,
		"glint": 0.0, "lift": 0.0},
	"boss": {"rim_strength": 0.6, "gate": 0.5, "outline": true, "width": 2.8, "max_w": 0.07, "fade_px": 0.0, "far": 140.0,
		"glint": 0.0, "lift": 0.0},
	"npc": {"rim_strength": 0.35, "gate": 0.8, "outline": false, "strip_outline": true, "width": 2.0, "max_w": 0.045, "fade_px": 0.0, "far": 70.0,
		"glint": 0.0, "lift": 0.0},
	"pickup": {"rim_strength": 0.45, "gate": 0.4, "outline": true, "width": 2.0, "max_w": 0.012, "fade_px": 16.0, "far": 60.0,
		"outline_far": 25.0, "glint": 0.0, "lift": 0.0},
	"truffle": {"rim_strength": 0.6, "gate": 0.3, "outline": true, "width": 2.2, "max_w": 0.03, "fade_px": 10.0, "far": 80.0,
		"glint": 1.0, "lift": 0.3}}
## Rim per world (LOOK finish pass): a soft rim colour for the hero, NPCs and pickups, and an off-palette enemy accent
## ("enemy") that is the complement of the world's dominant hue, so enemies separate from their world (D034 B2): violet on
## W1's pale grass, magenta on W2's greens, teal-blue on W3's orange gingerbread, cyan on the boss's red chimneys.
## The dark "ink" rim of fix round 1 is retired: it turned thin lances into black poles, laid ragged dark patches on
## faceted NPCs and cancelled the gummy's jelly rim.
const WORLD_RIM := {
	"HUB": {"rim": Color(0.74, 0.86, 1.0), "enemy": Color(0.45, 0.85, 1.0), "ink": false},
	"W1": {"rim": Color(0.7, 0.84, 1.0), "enemy": Color(0.66, 0.42, 1.0), "ink": false},
	"W2": {"rim": Color(0.86, 0.62, 1.0), "enemy": Color(1.0, 0.36, 0.78), "ink": false},
	"W3": {"rim": Color(0.5, 0.72, 1.0), "enemy": Color(0.18, 0.72, 0.9), "ink": false},
	"BOSS": {"rim": Color(0.62, 0.9, 1.0), "enemy": Color(0.4, 0.95, 1.0), "ink": false}}
const TRUFFLE_RIM := Color(1.0, 0.92, 0.55)
## D037: the one outline width (px at the real viewport height) for every gameplay outline.
const OUTLINE_PX := 2.0
## Fixed truffle gold ramp (dark umber to pale gold), indexed by luminance (D034 M3: gold-yellow, not orange).
const GOLD_RAMP := [Color8(84, 46, 12), Color8(160, 98, 18), Color8(222, 162, 26), Color8(250, 206, 52),
	Color8(255, 232, 120), Color8(255, 249, 206)]
const TRUFFLE_ALBEDO := Color(1.0, 0.84, 0.2)

## Per-world grade presets layered on the world's own Environment while the retro look is on (Docs/ART_V3_RETRO.md D034).
## sat/contrast/glow/exposure/brightness are multipliers; fog_* are absolute; ambient_add is added to the ambient energy;
## env_val darkens environment surfaces only (the gameplay layer keeps its value).
const PRESETS := {
	# LOOK finish: the hall read varnished orange with crushed blacks (floor mean RGB 80/44/40, 5th-percentile luma 20).
	"HUB": {"sat": 1.0, "contrast": 0.93, "glow": 0.6, "bloom": 0.02, "exposure": 1.2, "brightness": 1.06,
		"ambient_add": 0.3, "env_val": 1.12, "env_sat": 0.26},
	"W1": {"sat": 1.0, "contrast": 1.04, "glow": 0.55, "bloom": 0.02, "fog_begin": 90.0, "fog_end": 320.0, "aerial": 0.35,
		"env_val": 0.9, "bg_dist": 130.0},
	# LOOK finish: W2/W3 were high-key and busy (frame mean luma 148/170, the W3 ground 185) under their own strong
	# grades (W3 saturation 1.3, contrast 1.28); the environment comes down, the gameplay layer keeps its boost.
	"W2": {"sat": 0.92, "contrast": 0.95, "glow": 0.5, "bloom": 0.02, "fog_begin": 70.0, "fog_end": 280.0, "aerial": 0.4,
		"env_val": 0.8, "env_sat": 0.4},
	"W3": {"sat": 0.86, "contrast": 0.9, "glow": 0.5, "bloom": 0.02, "fog_begin": 70.0, "fog_end": 280.0, "aerial": 0.4,
		"env_val": 0.76, "env_sat": 0.38},
	# LOOK finish: the roof read as a hot-pink wash in phase 3 (Mak and the wolf had no value gap): darker, calmer roof.
	"BOSS": {"sat": 0.94, "contrast": 1.05, "glow": 0.6, "bloom": 0.02, "aerial": 0.5, "exposure": 1.05, "env_val": 0.8,
		"wall_val": 1.12,
		"bg_dist": 24.0, "env_sat": 0.26}}
const ENV_KEYS := ["adjustment_enabled", "adjustment_saturation", "adjustment_contrast", "adjustment_brightness",
	"glow_intensity", "glow_bloom", "fog_depth_begin", "fog_depth_end", "fog_aerial_perspective", "ssr_enabled",
	"tonemap_exposure", "ambient_light_energy"]

## Uniforms and helper injected into every retro shader variant, right before fragment().
const CALM_CODE := """
uniform float retro_sat_top = 1.0;
uniform float retro_sat_wall = 1.0;
uniform float retro_val = 1.0;
uniform float retro_wall_val = 1.0;
uniform float retro_boost = 1.0;
uniform vec4 retro_calm_tint : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float retro_calm_tint_mix = 0.0;
vec3 retro_rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 retro_hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
// D034 environment budget: cap HSV saturation (in sRGB) on tops / walls and scale the value; retro_boost > 1 lifts the
// gameplay layer instead. Yellows (straw, hay, sand) keep a little more chroma so they never turn olive, and decorative
// reds drift to raspberry (red-orange is reserved for hazards). Defaults are a no-op.
vec3 retro_calm(vec3 lin, float up) {
	if (retro_sat_top >= 0.999 && retro_sat_wall >= 0.999 && retro_val == 1.0 && retro_wall_val == 1.0 && retro_boost == 1.0) {
		return lin;
	}
	vec3 c = sqrt(max(lin, vec3(0.0)));
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = max(vec3(l) + (c - vec3(l)) * retro_boost, vec3(0.0));
	float top = smoothstep(0.45, 0.8, up);
	vec3 hsv = retro_rgb2hsv(c);
	float yel = 1.0 - smoothstep(0.03, 0.06, abs(hsv.x - 0.14));
	float smax = mix(retro_sat_wall, retro_sat_top, top) + 0.12 * yel;
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float d = mx - mn;
	if (smax < 0.999 && mx > 0.0001 && d / mx > smax) {
		float den = d - smax * (mx - l);
		float k = den > 0.0001 ? clamp(smax * l / den, 0.0, 1.0) : 1.0;
		c = vec3(l) + (c - vec3(l)) * k;
		vec3 tint = retro_calm_tint.rgb * (l / max(dot(retro_calm_tint.rgb, vec3(0.299, 0.587, 0.114)), 0.001));
		c = mix(c, tint, retro_calm_tint_mix * (1.0 - k));
		float hd = min(hsv.x, 1.0 - hsv.x);
		if (hd < 0.045 && hsv.y > 0.3) {
			vec3 h2 = retro_rgb2hsv(c);
			c = retro_hsv2rgb(vec3(mix(0.965, h2.x < 0.5 ? h2.x + 1.0 : h2.x, smoothstep(0.02, 0.045, hd)), h2.y, h2.z));
		}
	}
	c *= mix(retro_wall_val, retro_val, top);
	return c * c;
}
"""

## True when the classic texture style should be applied (setting "Classic textures", dev argument --retro=0/1).
var enabled := true
var vertex_shading := false
var pop_enabled := true
var last_stats: Dictionary = {}

var _variants: Dictionary = {}      # source Shader -> retro variant Shader
var _variant_src: Dictionary = {}   # variant Shader -> source Shader
var _mats: Dictionary = {}          # material instance id -> WeakRef (state lives in the material's "retro_state" meta)
var _node_overrides: Array = []     # [WeakRef node, surface (-1 = material_override), previous Material]
var _shadow_offs: Array = []        # [WeakRef GeometryInstance3D, previous cast_shadow, casts with soft shadows on]
## Soft shadows setting (Game "soft_shadows", default on; scripts/fx/soft_shadows.gd). Applied even with the look off.
var _soft := true
var _lights_pending: Array = []
var _decal_boosts: Array = []       # [WeakRef Decal, previous modulate]
var _tex: Dictionary = {}           # "id|cat" -> Texture2D (cleared on scene change; the disk cache makes re-entry cheap)
var _tex_targets: Dictionary = {}   # "id|cat" -> [[WeakRef material, property, source texture]] while an async job runs
var _tex_jobs: Array = []           # pending in-memory texture jobs for the current batch
var _async_groups: Array = []       # [{"gid": int, "jobs": Array}]
var _async := false
var _keep_ctx := false              # the geometry being processed is a cloud / sky prop (by node name)
var _bg_ctx := false                # the geometry being processed is background (far from the playfield)
var _ctx_mi: MeshInstance3D = null   # mesh + surface being processed (UV texel-density budget for env props)
var _ctx_surf := -1
var _blob_ctx := ""                 # "sphere" when the geometry is a SphereMesh puff, plus its leaf/stone name hint
var _details: Dictionary = {}       # detail-texture key -> [ImageTexture, mean value]
var _budgets: Dictionary = {}       # "mesh rid|surface|scale" -> texture size
var _spawn_pos := Vector3.ZERO
var _popped: Dictionary = {}        # node instance id -> WeakRef
var _pop_mats: Array = []           # WeakRef of the pop materials (rim colour / light direction follow the world)
var _outline_saves: Array = []     # [WeakRef outline ShaderMaterial, {param: original}] (D037 one outline rule)
var _blobs: Array = []              # WeakRef of BlobShadow nodes we attached
var _envs: Array = []               # WeakRef of Environments we graded
var _pending: Array = []
var _scene: Node = null
var _world := ""
var _scan_t := 0.0
var _pop_shader: Shader
var _glint_shader: Shader
var _outline_shader: Shader
var _toon_shader: Shader
## "source id|game/env" -> toon twin (D037). Static, like FxToon's cache, so the twins outlive the scene's instances at
## exit (freeing them with the nodes tripped the renderer); _prune drops twins nothing uses any more.
static var _toon_cache: Dictionary = {}
var _uniforms: Dictionary = {}       # Shader -> uniform names (D037: hundreds of toon twins per scene)
## D037: StandardMaterial3D surfaces switch to the toon shader (--retro-toon=0 keeps them PBR-matte for an A/B).
var toon_all := true
## Look polish 2026-10-19 texel-density pass (rock tile cap, prop texture budgets, foliage/stone detail). --retro-texel=0
## restores the earlier fixed-size reduction for A/B captures.
var texel_fix := true
var _shooting := false
var _web_baking := false
var _web_manifest: Dictionary = {}
var _web_misses: Dictionary = {}
var _released: Dictionary = {}      # Round 4 (web): texture instance id -> [WeakRef Texture2D, path] (see _web_release)
var _revived: Array = []            # reloads whose GPU data moved into a released texture (their RID is gone: kept)
var _shader_textures: Dictionary = {}  # Shader -> its sampler uniform names


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_web_baking = OS.get_cmdline_user_args().has("--web-bake")
	if OS.has_feature("web") or _web_baking:
		var manifest_path := WEB_CACHE + "manifest.json"
		if FileAccess.file_exists(manifest_path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			if parsed is Dictionary:
				_web_manifest = parsed
	var game := get_node_or_null("/root/Game")
	if game and game.has_method("get_setting"):
		enabled = bool(game.get_setting("classic_textures", true))
		_soft = bool(game.get_setting("soft_shadows", true))
		if game.has_signal("settings_changed"):
			game.settings_changed.connect(_on_settings_changed)
	var dev := get_node_or_null("/root/Dev")
	if dev and dev.has_method("has_arg"):
		if dev.has_arg("retro"):
			enabled = String(dev.arg("retro", "1")) != "0"
		vertex_shading = String(dev.arg("retro-vertex", "0")) == "1"
		pop_enabled = String(dev.arg("retro-pop", "1")) != "0"
		toon_all = String(dev.arg("retro-toon", "1")) != "0"
		texel_fix = String(dev.arg("retro-texel", "1")) != "0"
	_pop_shader = load(POP_SHADER_PATH) as Shader
	_glint_shader = load(GLINT_SHADER_PATH) as Shader
	_outline_shader = load(OUTLINE_SHADER_PATH) as Shader
	_toon_shader = load("res://assets/shaders/toon.gdshader") as Shader
	get_tree().node_added.connect(_on_node_added)
	print("[RetroLook] enabled=%s vertex=%s pop=%s" % [enabled, vertex_shading, pop_enabled])
	if dev and dev.has_method("has_arg") and dev.has_arg("retro-shots"):
		_run_shots.call_deferred(String(dev.arg("retro-shots", "")))
	# Look-polish evidence (test only): gameplay-camera shots at fixed spots, see game/tests/look_polish/look_shots.gd.
	if dev and dev.has_method("has_arg") and dev.has_arg("look-shots") \
			and ResourceLoader.exists("res://tests/look_polish/look_shots.gd"):
		add_child((load("res://tests/look_polish/look_shots.gd") as GDScript).new())
	# Render-fix evidence (test only): see game/tests/render_fix/render_shots.gd.
	if dev and dev.has_method("has_arg") and dev.has_arg("render-shots") \
			and ResourceLoader.exists("res://tests/render_fix/render_shots.gd"):
		add_child((load("res://tests/render_fix/render_shots.gd") as GDScript).new())


func _exit_tree() -> void:
	# Worker groups must be waited on once, or their task (and the images it holds) leak at exit.
	for g in _async_groups:
		WorkerThreadPool.wait_for_group_task_completion(int(g["gid"]))
	_async_groups.clear()
	_tex_targets.clear()
	_tex.clear()
	_details.clear()
	_budgets.clear()
	_uniforms.clear()
	_variants.clear()
	_variant_src.clear()


func _on_settings_changed() -> void:
	if _shooting:
		return
	var game := get_node_or_null("/root/Game")
	if game == null:
		return
	var want := bool(game.get_setting("classic_textures", true))
	if want != enabled:
		set_enabled(want)
	var soft := bool(game.get_setting("soft_shadows", true))
	if soft != _soft:
		_apply_soft(soft)


## Turns the look on or off live (re-applies or fully reverts the current scene).
func set_enabled(on: bool) -> void:
	enabled = on
	if on:
		apply_to(get_tree().current_scene)
	else:
		revert_all()


## Applies the retro look to every material under `root` (also runs automatically on every scene change and for nodes
## added later, such as spawned enemies and pickups).
func apply_to(root: Node) -> void:
	if not enabled or root == null:
		return
	var t0 := Time.get_ticks_usec()
	_world = String(root.get("world_id")) if root.get("world_id") != null else ""
	var sp := root.find_child("Default", true, false) as Node3D
	_spawn_pos = sp.global_position if sp != null else Vector3.ZERO
	var geoms: Array = []
	_collect_geoms(root, geoms)
	_async = false
	_process_batch(geoms)
	_apply_env(root)
	_refresh_world_params()
	_scan_groups()
	_web_release()
	last_stats["apply_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	last_stats["geometry"] = geoms.size()
	last_stats["materials"] = _mats.size()
	last_stats["textures"] = _tex.size()
	last_stats["variants"] = _variants.size()
	print("[RetroLook] applied to %s: %d geometry, %d materials, %d textures in %.1f ms" % [root.name, geoms.size(),
		_mats.size(), _tex.size(), last_stats["apply_ms"]])
	applied.emit(last_stats)


func _on_node_added(n: Node) -> void:
	if enabled and n is GeometryInstance3D:
		_pending.append(n)
	elif n is Light3D:
		_lights_pending.append(weakref(n))


func _process(delta: float) -> void:
	_poll_async()
	var cs := get_tree().current_scene
	if cs != _scene:
		_scene = cs
		_pending.clear()
		_lights_pending.clear()
		_prune()
		if cs != null:
			_apply_soft(_soft)
		if enabled and cs != null:
			apply_to(cs)
		return
	if not _lights_pending.is_empty():
		# Lights spawned mid-scene (title diorama, boss phases): configured by their owner first, then the soft rule.
		var wid: Variant = cs.get("world_id") if cs != null else null
		for w in _lights_pending:
			var l: Object = (w as WeakRef).get_ref()
			if l != null and cs != null and cs.is_ancestor_of(l as Node):
				SoftShadows.apply_light(l as Light3D, _soft, String(wid) if wid != null else "")
		_lights_pending.clear()
	if not enabled:
		_pending.clear()
		return
	if not _pending.is_empty():
		var batch := _pending
		_pending = []
		_async = true
		_process_batch(batch)
		_async = false
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.5
		_async = true
		_scan_groups()
		_async = false


## Drops every reference to resources of scenes that are gone (round-1 major: texture memory grew by 226-540 MB).
func _prune() -> void:
	var live := {}
	for id in _mats:
		if (_mats[id] as WeakRef).get_ref() != null:
			live[id] = _mats[id]
	_mats = live
	_node_overrides = _node_overrides.filter(func(e: Array) -> bool: return (e[0] as WeakRef).get_ref() != null)
	_shadow_offs = _shadow_offs.filter(func(e: Array) -> bool: return (e[0] as WeakRef).get_ref() != null)
	_decal_boosts = _decal_boosts.filter(func(e: Array) -> bool: return (e[0] as WeakRef).get_ref() != null)
	_blobs = _blobs.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
	_outline_saves = _outline_saves.filter(func(e: Array) -> bool: return (e[0] as WeakRef).get_ref() != null)
	_pop_mats = _pop_mats.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
	_envs = _envs.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
	var pl := {}
	for id in _popped:
		if (_popped[id] as WeakRef).get_ref() != null:
			pl[id] = _popped[id]
	_popped = pl
	var keep := {}
	for k in _toon_cache:
		# The cache's own reference plus this loop's: anything above means a surface still uses the twin.
		if (_toon_cache[k] as RefCounted).get_reference_count() > 2:
			keep[k] = _toon_cache[k]
	_toon_cache = keep
	if _async_groups.is_empty():
		_tex.clear()
		_tex_targets.clear()


# ------------------------------------------------------------------ materials

func _collect_geoms(n: Node, out: Array) -> void:
	if n is GeometryInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_geoms(c, out)


func _process_batch(geoms: Array) -> void:
	_tex_jobs.clear()
	for g in geoms:
		if is_instance_valid(g):
			_process_geom(g as GeometryInstance3D)
	_run_tex_jobs()
	_web_revive(geoms)


func _skip_geom(g: GeometryInstance3D) -> bool:
	return g is GPUParticles3D or g is CPUParticles3D or g is SpriteBase3D or g is Label3D or g.has_meta("retro_skip") \
		or not g.is_inside_tree()


func _process_geom(g: GeometryInstance3D) -> void:
	if OS.has_feature("web") and g.has_meta("web_batch"):
		return
	if g == null or _skip_geom(g):
		return
	var role := _role_of(g)
	_keep_ctx = _keep_node(g)
	_bg_ctx = role == "env" and _is_background(g)
	_blob_ctx = _blob_hint(g) if role == "env" else ""
	_ctx_mi = g as MeshInstance3D if g is MeshInstance3D and (g as MeshInstance3D).mesh != null else null
	_ctx_surf = 0
	if g.material_override != null:
		var m2 := _handle(g.material_override, role)
		_ctx_mi = null
		if m2 != g.material_override:
			_node_overrides.append([weakref(g), -1, g.material_override])
			g.material_override = m2
		return
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		if mi.mesh == null:
			return
		for s in mi.mesh.get_surface_count():
			var ov := mi.get_surface_override_material(s)
			var m: Material = ov if ov != null else mi.mesh.surface_get_material(s)
			if m == null:
				continue
			_ctx_surf = s
			var r := _handle(m, role)
			if r != m:
				_node_overrides.append([weakref(mi), s, ov])
				mi.set_surface_override_material(s, r)
		_ctx_mi = null
	elif g is MultiMeshInstance3D:
		_ctx_mi = null
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm and mm.mesh:
			for s in mm.mesh.get_surface_count():
				var m3 := mm.mesh.surface_get_material(s)
				if m3 != null:
					_handle(m3, role)
	elif "material" in g:
		var m4: Variant = g.get("material")
		if m4 is Material:
			_handle(m4 as Material, role)


func _role_of(n: Node) -> String:
	var p := n
	var depth := 0
	while p != null and depth < 24:
		for grp in GROUP_ROLES:
			if p.is_in_group(grp):
				return GROUP_ROLES[grp]
		if p == _scene:
			break
		p = p.get_parent()
		depth += 1
	return "env"


static func _is_game(role: String) -> bool:
	return role != "env"


## Look polish: "leaf" / "stone" / "sphere" for SphereMesh puffs (hint from the node and its parents' names), else "".
func _blob_hint(g: GeometryInstance3D) -> String:
	var m: Mesh = null
	if g is MeshInstance3D:
		m = (g as MeshInstance3D).mesh
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
		m = (g as MultiMeshInstance3D).multimesh.mesh
	if not (m is SphereMesh):
		return ""
	var names := ""
	var p: Node = g
	for i in 3:
		if p == null or p == _scene:
			break
		names += String(p.name).to_lower() + " "
		p = p.get_parent()
	for w in LEAF_WORDS:
		if names.contains(w):
			return "leaf"
	for w in STONE_WORDS:
		if names.contains(w):
			return "stone"
	return "sphere"


func _canopy_name(b: BaseMaterial3D) -> bool:
	var nm := String(b.resource_name).to_lower()
	if b.albedo_texture != null:
		nm += " " + b.albedo_texture.resource_path.to_lower()
	for w in CANOPY_WORDS:
		if nm.contains(w):
			return true
	return false


## Which detail texture an untextured environment puff gets ("" = none): green or vertex-coloured leaf puffs, neutral or
## vertex-coloured stones, and any other green sphere (moss caps, kit tree crowns).
func _detail_kind(b: BaseMaterial3D) -> String:
	if b.albedo_texture != null:
		# Flat-coloured generated canopies (the apple tree's crown texture is one green fill): the leaf detail on top.
		return "leaf" if _canopy_name(b) else ""
	if _blob_ctx == "":
		return ""
	var c := b.albedo_color
	var green := c.s > 0.22 and c.h > 0.16 and c.h < 0.47 and c.v > 0.12
	var vc := b.vertex_color_use_as_albedo
	match _blob_ctx:
		"leaf":
			return "leaf" if green or vc else ""
		"stone":
			if green:
				return "leaf"
			return "stone" if vc or c.s < 0.4 else ""
		"sphere":
			return "leaf" if green else ""
	return ""


## Sets the detail uniforms of the toon variant (after _convert swapped the shader in).
func _apply_detail(t: ShaderMaterial) -> void:
	if not t.has_meta("retro_detail"):
		return
	var kind := String(t.get_meta("retro_detail"))
	var dt := _detail_tex(kind)
	if dt.is_empty():
		return
	t.set_shader_parameter("use_detail", true)
	t.set_shader_parameter("detail_texture", dt[0])
	t.set_shader_parameter("detail_scale", 1.0 / (LEAF_TILE_M if kind == "leaf" else STONE_TILE_M))


## Value-only detail tile (the leaf or rock retro tile, luminance remapped to [lo, 1]) and its mean, cached per kind.
func _detail_tex(kind: String) -> Array:
	if _details.has(kind):
		return _details[kind]
	if OS.has_feature("web"):
		var entry: Dictionary = _web_manifest.get("detail:" + kind, {})
		if not entry.is_empty():
			var baked := load(WEB_CACHE + String(entry["file"])) as Texture2D
			baked.set_meta("retro", true)
			_details[kind] = [baked, float(entry["mean"])]
			return _details[kind]
		push_error("[RetroLook] missing baked detail " + kind)
		_details[kind] = []
		return []
	var src := load(LEAF_DETAIL if kind == "leaf" else STONE_DETAIL) as Texture2D
	var img: Image = src.get_image() if src != null else null
	if img == null or img.is_empty():
		_details[kind] = []
		return []
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var lo := 0.6 if kind == "leaf" else 0.74
	var data := img.get_data()
	var n := img.get_width() * img.get_height()
	var lum := PackedFloat32Array()
	lum.resize(n)
	var lmin := 1.0
	var lmax := 0.0
	for i in n:
		var l := (0.299 * data[i * 4] + 0.587 * data[i * 4 + 1] + 0.114 * data[i * 4 + 2]) / 255.0
		lum[i] = l
		lmin = minf(lmin, l)
		lmax = maxf(lmax, l)
	var span := maxf(lmax - lmin, 0.01)
	var sum := 0.0
	for i in n:
		var v := lo + (1.0 - lo) * (lum[i] - lmin) / span
		var b8 := clampi(roundi(v * 255.0), 0, 255)
		data[i * 4] = b8
		data[i * 4 + 1] = b8
		data[i * 4 + 2] = b8
		data[i * 4 + 3] = 255
		sum += v
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	tex.set_meta("retro", true)
	tex.resource_name = kind + "_detail_retro"
	_details[kind] = [tex, sum / n]
	if _web_baking:
		_write_web_texture("detail:" + kind, img, {"mean": sum / n})
	return _details[kind]


## Texture size for a UV-mapped environment prop surface: PROP_TPM texels per metre over the mesh's world area per UV
## area (sampled triangles, cached per mesh, surface and scale). Never below `fallback` (the category size).
func _prop_budget(mi: MeshInstance3D, s: int, fallback: int) -> int:
	if mi == null or mi.mesh == null or s >= mi.mesh.get_surface_count() or not mi.is_inside_tree():
		return fallback
	var b := mi.global_transform.basis
	var sc := b.get_scale()
	var key := "%d|%d|%.2f" % [mi.mesh.get_rid().get_id(), s, (sc.x + sc.y + sc.z) / 3.0]
	if _budgets.has(key):
		return int(_budgets[key])
	var arr := mi.mesh.surface_get_arrays(s)
	var size := fallback
	if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_TEX_UV] is PackedVector2Array and arr[Mesh.ARRAY_VERTEX] is PackedVector3Array:
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var has_idx := idx.size() > 0
		var tris := idx.size() / 3 if has_idx else verts.size() / 3
		var step := maxi(1, tris / 4000)
		var wa := 0.0
		var ua := 0.0
		if uvs.size() == verts.size():
			for t in range(0, tris, step):
				var i0 := idx[t * 3] if has_idx else t * 3
				var i1 := idx[t * 3 + 1] if has_idx else t * 3 + 1
				var i2 := idx[t * 3 + 2] if has_idx else t * 3 + 2
				var v0 := b * verts[i0]
				wa += (b * verts[i1] - v0).cross(b * verts[i2] - v0).length()
				var e1 := uvs[i1] - uvs[i0]
				var e2 := uvs[i2] - uvs[i0]
				ua += absf(e1.x * e2.y - e1.y * e2.x)
		if wa > 1e-6 and ua > 1e-8:
			var need := PROP_TPM * sqrt(wa / ua)
			size = PROP_TEX_MIN
			while size < need and size < PROP_TEX_MAX:
				size *= 2
			size = maxi(size, fallback)
	_budgets[key] = size
	return size


func _track(m: Material) -> void:
	_mats[m.get_instance_id()] = weakref(m)


## Returns the material the surface should use: the same object (converted in place) or a duplicate when a shared material
## is used by both the environment and a gameplay node.
func _handle(m: Material, role: String) -> Material:
	if m == null or m.has_meta("retro_pop"):
		return m
	if m.has_meta(META):
		var st: Dictionary = m.get_meta(META)
		if not _mats.has(m.get_instance_id()):
			_track(m)
		if _is_game(String(st["role"])) == _is_game(role):
			return m
		var dk := "retro_dup_game" if _is_game(role) else "retro_dup_env"
		if m.has_meta(dk):
			return m.get_meta(dk)
		var d := m.duplicate() as Material
		for k in [META, "retro_dup_game", "retro_dup_env"]:
			if d.has_meta(k):
				d.remove_meta(k)
		_restore_props(d, st["orig"])
		d.set_meta("retro_dup", true)
		var r: Material = d
		if d is BaseMaterial3D and _toonable(d as BaseMaterial3D, role):
			r = _to_toon(d as BaseMaterial3D, role)
		else:
			_convert(d, role)
		m.set_meta(dk, r)
		return r
	if m is BaseMaterial3D and _toonable(m as BaseMaterial3D, role):
		return _to_toon(m as BaseMaterial3D, role)
	if not _convert(m, role):
		# Mark untouched materials too, so they are not inspected again.
		m.set_meta(META, {"role": role, "orig": {}, "untouched": true})
		_track(m)
	return m


## D037 (one shading model): lit, opaque, single-sided StandardMaterial3D surfaces (GLB imports, procedural props,
## buildings, NPCs) switch to the toon shader the styled props already use. Exceptions stay as they are: unshaded and
## transparent surfaces (VFX, UI, glass, foliage cards), double-sided or billboard cards, sky / cloud / light sources
## (KEEP_WORDS), shiny metal / gold / water (SHINY_WORDS) and the truffle's own gold finish.
func _toonable(b: BaseMaterial3D, role: String) -> bool:
	if not toon_all or role == "truffle":
		return false
	if b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return false
	# Double-sided GLB characters are closed meshes, so they take the single-sided toon shader too; double-sided
	# environment cards (leaves, flags, paper) stay as they are.
	if b.cull_mode == BaseMaterial3D.CULL_FRONT or b.cull_mode == BaseMaterial3D.CULL_DISABLED and not _is_game(role) 			and not (texel_fix and _canopy_name(b)):
		# (Look polish: generated tree canopies are closed blobs exported double-sided; they take the toon twin too.)
		return false
	if b.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return false
	if b.albedo_texture is ViewportTexture or b.next_pass != null and not (b.next_pass is ShaderMaterial 			and (b.next_pass as ShaderMaterial).shader == _outline_shader):
		return false
	if _keep(b) or _shiny(b):
		return false
	return true


## The toon twin of a StandardMaterial3D (cached on the source, one per environment / gameplay use). The source is never
## modified, so turning the look off only restores the surface override.
func _to_toon(b: BaseMaterial3D, role: String) -> Material:
	var detail := _detail_kind(b) if not _is_game(role) and texel_fix else ""
	var key := "%d|%s|%s" % [b.get_instance_id(), "game" if _is_game(role) else "env", detail]
	var c: Material = _toon_cache.get(key, null)
	if c != null:
		if not c.has_meta(META):
			_convert(c, role)
			_apply_detail(c as ShaderMaterial)
		return c
	var t := ShaderMaterial.new()
	t.shader = _toon_shader
	t.resource_name = b.resource_name
	t.set_shader_parameter("albedo", b.albedo_color)
	if b.albedo_texture != null:
		t.set_shader_parameter("albedo_texture", b.albedo_texture)
	t.set_shader_parameter("use_vertex_color", b.vertex_color_use_as_albedo)
	if b.uv1_triplanar:
		t.set_shader_parameter("triplanar", true)
		var tsc := b.uv1_scale.x
		if b.albedo_texture != null and not _is_game(role) and texel_fix:
			var tp := b.albedo_texture.resource_path
			for w in ROCK_WORDS:
				if tp.contains(w):
					tsc = maxf(tsc, 1.0 / ROCK_TILE_M)
		t.set_shader_parameter("triplanar_scale", tsc)
	else:
		t.set_shader_parameter("uv_scale", Vector2(b.uv1_scale.x, b.uv1_scale.y))
	if detail != "":
		var dt := _detail_tex(detail)
		if not dt.is_empty():
			var mean := maxf(float(dt[1]), 0.5)
			var ac := b.albedo_color
			t.set_shader_parameter("albedo", Color(ac.r / mean, ac.g / mean, ac.b / mean, ac.a))
			t.set_meta("retro_detail", detail)
			if detail == "leaf":
				# Foliage reads like the textured trees: a crisper two-tone ramp and a cool green shade.
				t.set_shader_parameter("ramp_softness", 0.03)
				t.set_shader_parameter("shadow_tint", Color(0.46, 0.58, 0.64))
	if b.emission_enabled:
		t.set_shader_parameter("emission_color", b.emission)
		t.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
	t.set_shader_parameter("roughness_value", clampf(b.roughness, 0.5, 1.0))
	if _is_game(role):
		t.set_shader_parameter("rim_strength", 0.35)
		t.set_shader_parameter("spec_strength", 0.25)
		if b.normal_enabled and b.normal_texture != null:
			t.set_shader_parameter("normal_texture", b.normal_texture)
			t.set_shader_parameter("use_normal_map", true)
	t.next_pass = b.next_pass
	t.set_meta("retro_toon_src", true)
	_toon_cache[key] = t
	_convert(t, role)
	_apply_detail(t)
	if not _is_game(role) and t.has_meta(META):
		# Generated PBR assets were authored for metallic shading; under the toon ramp their light albedo washes out.
		var st: Dictionary = t.get_meta(META)
		st["rule_val"] = 0.86
		if bool(st.get("calm", false)):
			_calm_shader(t, st)
	return t


func _name_of(m: Material) -> String:
	var s := (String(m.resource_name) + " " + m.resource_path).to_lower()
	if m is BaseMaterial3D:
		var bm := m as BaseMaterial3D
		if bm.albedo_texture != null:
			s += " " + bm.albedo_texture.resource_path.to_lower()
	elif m is ShaderMaterial:
		var t: Variant = (m as ShaderMaterial).get_shader_parameter("albedo_texture")
		if t is Texture2D:
			s += " " + (t as Texture2D).resource_path.to_lower()
	return s


func _shiny(m: Material) -> bool:
	var s := _name_of(m)
	for w in SHINY_WORDS:
		if s.contains(w):
			return true
	# Real metals (brass rings, lamp fittings) keep their shine; the original metallic value is the tell.
	# D037: a metallic texture means a generated PBR asset (Tripo exports metallic 1.0 with an ORM map), not real metal.
	if m is BaseMaterial3D and (m as BaseMaterial3D).metallic_texture != null:
		return false
	if m is BaseMaterial3D and m.has_meta(META) and (m.get_meta(META) as Dictionary)["orig"].has("metallic"):
		return float((m.get_meta(META) as Dictionary)["orig"]["metallic"]) >= 0.5
	return m is BaseMaterial3D and (m as BaseMaterial3D).metallic >= 0.5


## Background layer (D034): environment geometry whose centre lies farther than the world's BG distance from the Default
## spawn. It keeps its rim light (back-lit masses read as soft silhouettes, critic M7) and drifts toward the fog colour.
func _is_background(g: GeometryInstance3D) -> bool:
	var dist := float((PRESETS.get(_world, {}) as Dictionary).get("bg_dist", 0.0))
	if dist <= 0.0 or not (g is MeshInstance3D) or (g as MeshInstance3D).mesh == null:
		return false
	var c := (g.global_transform * (g as MeshInstance3D).get_aabb()).get_center()
	return Vector2(c.x - _spawn_pos.x, c.z - _spawn_pos.z).length() > dist


## Cloud and sky props named as such keep their lighting (round-1 blocker: the boss's purple clouds went near-black).
func _keep_node(n: Node) -> bool:
	var p := n
	for i in 4:
		if p == null or p == _scene:
			break
		var nm := String(p.name).to_lower()
		if nm.contains("cloud") or nm.contains("sky") or nm.contains("puff"):
			# Look polish 2026-10-19: hedge and bush puffs are foliage, not sky props (they stayed plain smooth spheres).
			if texel_fix and (nm.contains("hedge") or nm.contains("bush") or nm.contains("leaf")):
				return false
			return true
		p = p.get_parent()
	return false


func _keep(m: Material) -> bool:
	if _keep_ctx:
		return true
	var s := _name_of(m)
	for w in KEEP_WORDS:
		if s.contains(w):
			return true
	return false


func _save(st: Dictionary, obj: Object, key: String) -> void:
	if not st["orig"].has(key):
		var v: Variant = obj.get(key)
		if v is ViewportTexture:
			return
		st["orig"][key] = v


func _save_param(st: Dictionary, sm: ShaderMaterial, pname: String) -> void:
	var key := "shader_parameter/" + pname
	if not st["orig"].has(key):
		var v: Variant = sm.get_shader_parameter(pname)
		if v is ViewportTexture:
			return
		st["orig"][key] = v


func _restore_props(m: Material, orig: Dictionary) -> void:
	# The shader goes first so the shader parameters land on the right uniforms.
	if orig.has("shader"):
		m.set("shader", orig["shader"])
	for k in orig:
		if k == "shader" or orig[k] is ViewportTexture:
			continue
		if String(k).begins_with("shader_parameter/"):
			(m as ShaderMaterial).set_shader_parameter(String(k).substr(17), orig[k])
		else:
			m.set(k, orig[k])


func _convert(m: Material, role: String) -> bool:
	if m is BaseMaterial3D:
		return _convert_base(m as BaseMaterial3D, role)
	if m is ShaderMaterial:
		return _convert_shader(m as ShaderMaterial, role)
	return false


## Colour maths shared with retro_calm(): optional boost, HSV saturation cap, value multiplier (sRGB colour in, sRGB out).
static func calm_color(c: Color, sat_cap: float, val: float, boost: float = 1.0) -> Color:
	var l := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	var r := maxf(l + (c.r - l) * boost, 0.0)
	var g := maxf(l + (c.g - l) * boost, 0.0)
	var b := maxf(l + (c.b - l) * boost, 0.0)
	var h0 := c.h
	var hd := minf(h0, 1.0 - h0)
	if sat_cap < 0.999:
		# Yellows keep a little more chroma (straw never turns olive); see retro_calm() in CALM_CODE.
		sat_cap += 0.12 * (1.0 - smoothstep(0.03, 0.06, absf(h0 - 0.14)))
	var mx := maxf(r, maxf(g, b))
	var mn := minf(r, minf(g, b))
	var d := mx - mn
	if mx > 0.0001 and d / mx > sat_cap:
		var den := d - sat_cap * (mx - l)
		var k := clampf(sat_cap * l / den, 0.0, 1.0) if den > 0.0001 else 1.0
		r = l + (r - l) * k
		g = l + (g - l) * k
		b = l + (b - l) * k
		if hd < 0.045 and c.s > 0.3:
			var cc := Color(r, g, b)
			var h2 := cc.h if cc.h > 0.5 else cc.h + 1.0
			cc = Color.from_hsv(fmod(lerpf(0.965, h2, smoothstep(0.02, 0.045, hd)), 1.0), cc.s, cc.v)
			r = cc.r
			g = cc.g
			b = cc.b
	return Color(clampf(r * val, 0.0, 1.0), clampf(g * val, 0.0, 1.0), clampf(b * val, 0.0, 1.0), c.a)


## Saturation cap for environment surfaces in the current world (warm-lit interiors and the sunset arena get a lower one,
## because their key light already tints every surface).
func _env_sat(top: bool) -> float:
	var cap := float((PRESETS.get(_world, {}) as Dictionary).get("env_sat", ENV_SAT_TOP))
	return minf(cap, ENV_SAT_TOP) if top else ENV_SAT_WALL * minf(cap, ENV_SAT_TOP) / ENV_SAT_TOP


## Value multiplier on walls (the boss arena lifts its dark chimney brick toward the floor value, critic M7).
func _wall_val() -> float:
	return float((PRESETS.get(_world, {}) as Dictionary).get("wall_val", 0.94))


func _env_val() -> float:
	return float((PRESETS.get(_world, {}) as Dictionary).get("env_val", 1.0))


func _cat_for(t: Texture2D, role: String, tile: bool) -> String:
	if _is_face(t) and role != "truffle":
		return "face"
	if _is_game(role):
		return role
	return "env_tile" if tile else "env_prop"


func _convert_base(m: BaseMaterial3D, role: String) -> bool:
	if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return false
	var st := {"role": role, "orig": {}}
	m.set_meta(META, st)
	_track(m)
	var game := _is_game(role)
	var shiny := _shiny(m)
	var keep := _keep(m)
	_save(st, m, "texture_filter")
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if keep:
		st["keep"] = true
		return true
	if m.albedo_texture != null and not (m.albedo_texture is ViewportTexture):
		var cat := _cat_for(m.albedo_texture, role, m.albedo_texture.resource_path.begins_with("res://assets/textures/"))
		var nt := _retro_tex(m.albedo_texture, cat, m, "albedo_texture")
		if nt != m.albedo_texture:
			_save(st, m, "albedo_texture")
			m.albedo_texture = nt
	for k in ["roughness", "metallic", "metallic_specular", "specular_mode", "clearcoat_enabled", "rim_enabled",
			"normal_enabled", "albedo_color", "emission_enabled", "emission", "emission_energy_multiplier"]:
		_save(st, m, k)
	m.clearcoat_enabled = false
	m.normal_enabled = false
	if role == "truffle":
		if m.albedo_texture == null:
			m.albedo_color = TRUFFLE_ALBEDO
		m.emission_enabled = true
		m.emission = Color(1.0, 0.78, 0.25)
		m.emission_energy_multiplier = 0.4
		m.roughness = clampf(m.roughness, 0.35, 0.6)
		return true
	if not game and not shiny:
		m.roughness = maxf(m.roughness, 0.92)
		m.metallic = 0.0
		m.metallic_specular = minf(m.metallic_specular, 0.08)
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		if _bg_ctx:
			st["bg"] = true
		else:
			m.rim_enabled = false
		st["calm"] = true
		_calm_base(m, st)
		if vertex_shading and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			_save(st, m, "shading_mode")
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	elif shiny:
		m.roughness = maxf(m.roughness, 0.35)
	else:
		m.roughness = maxf(m.roughness, 0.6)
		m.metallic = minf(m.metallic, 0.2)
		m.metallic_specular = minf(m.metallic_specular, 0.3)
		if role != "hero" and role != "hazard":
			m.albedo_color = calm_color(st["orig"]["albedo_color"], 1.0, 1.0, GAME_SAT_BOOST)
	return true


## Environment StandardMaterial3D colour budget, recomputed from the original colour (also on world change).
func _calm_base(m: BaseMaterial3D, st: Dictionary) -> void:
	var oc: Color = st["orig"].get("albedo_color", m.albedo_color)
	var nm := _name_of(m)
	var wall := _env_sat(not (nm.contains("wall") or nm.contains("brick") or nm.contains("rock") or nm.contains("cliff")))
	var is_wall := nm.contains("wall") or nm.contains("brick") or nm.contains("rock") or nm.contains("cliff")
	m.albedo_color = calm_color(oc, wall, _env_val() * (_wall_val() if is_wall else 1.0))
	if bool(st.get("bg", false)):
		var fog := _fog_color()
		m.albedo_color = m.albedo_color.lerp(Color(fog.r, fog.g, fog.b, m.albedo_color.a), 0.35)


## Shader code of the retro variant: the RETRO_LOOK define, the calm helper and (for world shaders) nearest samplers,
## texel snapping and the matte finish.
func _variant(sh: Shader) -> Shader:
	if _variant_src.has(sh):
		return sh
	if _variants.has(sh):
		return _variants[sh]
	var code := sh.code
	var rule: Dictionary = WORLD_SHADERS.get(sh.resource_path, {})
	var own := RETRO_SHADER_PATHS.has(sh.resource_path)
	var idx := code.find("shader_type")
	var eol := code.find("\n", idx) if idx >= 0 else -1
	var fi := code.find("void fragment()")
	if eol < 0 or fi < 0:
		return null
	if not own:
		code = _nearest_samplers(code)
	fi = code.find("void fragment()")
	var ob := code.find("{", fi)
	var cb := _match_brace(code, ob)
	if ob < 0 or cb < 0:
		return null
	var body := code.substr(ob + 1, cb - ob - 1)
	var head := ""
	var wpos := String(rule.get("wpos", ""))
	if wpos != "":
		var re := RegEx.new()
		re.compile("\\b" + wpos + "\\b")
		body = re.sub(body, "_retro_wp", true)
		head = "\n\tvec3 _retro_wp = (floor(%s * %.3f) + 0.5) / %.3f;" % [wpos, float(rule.get("tpm", 12.0)), float(rule.get("tpm", 12.0))]
	var tail := "\n\tALBEDO = retro_calm(ALBEDO, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);\n"
	if bool(rule.get("matte", false)):
		tail += "\tROUGHNESS = max(ROUGHNESS, 0.9);\n\tSPECULAR = min(SPECULAR, 0.05);\n"
		if body.contains("RIM ="):
			tail += "\tRIM = 0.0;\n"
		if body.contains("CLEARCOAT ="):
			tail += "\tCLEARCOAT = 0.0;\n"
	if rule.has("emission") and body.contains("EMISSION"):
		tail += "\tEMISSION *= %.3f;\n" % float(rule["emission"])
	code = code.substr(0, ob + 1) + head + body + tail + code.substr(cb)
	fi = code.find("void fragment()")
	var calm_code := CALM_CODE
	if OS.has_feature("web"):
		# Compatibility supplies sRGB material values; Forward+ supplies linear.
		# The authored saturation/value budget is defined in sRGB in both cases.
		calm_code = calm_code.replace("vec3 c = sqrt(max(lin, vec3(0.0)));", "vec3 c = max(lin, vec3(0.0));")
		calm_code = calm_code.replace("return c * c;", "return c;")
	code = code.substr(0, fi) + calm_code + "\n" + code.substr(fi)
	idx = code.find("shader_type")
	eol = code.find("\n", idx)
	var v := Shader.new()
	v.code = code.substr(0, eol + 1) + "#define RETRO_LOOK\n" + code.substr(eol + 1)
	v.resource_name = sh.resource_path.get_file().get_basename() + "_retro"
	_variants[sh] = v
	_variant_src[v] = sh
	return v


static func _match_brace(code: String, ob: int) -> int:
	if ob < 0:
		return -1
	var depth := 0
	for i in range(ob, code.length()):
		var ch := code[i]
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				return i
	return -1


## Colour samplers of foreign world shaders switch to nearest-mipmap filtering (screen/depth/normal samplers stay).
static func _nearest_samplers(code: String) -> String:
	var lines := code.split("\n")
	for i in lines.size():
		var ln := lines[i]
		if not (ln.contains("uniform sampler2D") and ln.contains("source_color")):
			continue
		var done := false
		for f in ["filter_linear_mipmap_anisotropic", "filter_nearest_mipmap_anisotropic", "filter_linear_mipmap", "filter_linear"]:
			if ln.contains(f):
				ln = ln.replace(f, "filter_nearest_mipmap")
				done = true
				break
		if not done and not ln.contains("filter_nearest"):
			ln = ln.replace("source_color", "source_color, filter_nearest_mipmap")
		lines[i] = ln
	return "\n".join(lines)


func _convert_shader(m: ShaderMaterial, role: String) -> bool:
	var sh := m.shader
	if sh == null:
		return false
	var src: Shader = _variant_src.get(sh, sh)
	var world_rule := WORLD_SHADERS.has(src.resource_path)
	if not RETRO_SHADER_PATHS.has(src.resource_path) and not world_rule:
		return false
	var v := _variant(src)
	if v == null:
		return false
	var st := {"role": role, "orig": {}}
	m.set_meta(META, st)
	_track(m)
	var game := _is_game(role)
	var shiny := _shiny(m)
	var kind := src.resource_path.get_file().get_basename()
	# Keep every uniform value across the shader swap.
	var vals := {}
	if not _uniforms.has(src):
		var names: Array = []
		for u in src.get_shader_uniform_list():
			names.append(String(u["name"]))
		_uniforms[src] = names
	for un in _uniforms[src]:
		vals[un] = m.get_shader_parameter(un)
	_save(st, m, "shader")
	m.shader = v
	for un in vals:
		if vals[un] != null:
			m.set_shader_parameter(un, vals[un])
	# Textures.
	var triplanar: bool = vals.get("triplanar") == true
	for tn in vals:
		var t: Variant = vals[tn]
		if not (t is Texture2D) or t is ViewportTexture or String(tn).contains("normal") or String(tn).contains("noise"):
			continue
		var tile := world_rule or kind != "toon" or triplanar or (t as Texture2D).resource_path.begins_with("res://assets/textures/")
		var cat := _cat_for(t as Texture2D, role, tile)
		var nt := _retro_tex(t as Texture2D, cat, m, "shader_parameter/" + String(tn))
		if nt != t:
			_save_param(st, m, tn)
			m.set_shader_parameter(tn, nt)
	if kind == "terrain" or kind == "w1_terrain":
		for pn in TERRAIN_SCALES:
			if vals.has(pn):
				_save_param(st, m, pn)
				m.set_shader_parameter(pn, TERRAIN_SCALES[pn] if texel_fix or pn != "rock_scale" else 0.2)
	if world_rule:
		var rule: Dictionary = WORLD_SHADERS[src.resource_path]
		st["calm"] = bool(rule.get("calm", true))
		st["rule_val"] = float(rule.get("val", 1.0))
		st["sat_top"] = float(rule.get("sat_top", ENV_SAT_TOP))
		_calm_shader(m, st)
		return true
	# Matte pass / gameplay finish.
	match kind:
		"toon":
			for pn in ["spec_strength", "rim_strength", "roughness_value", "retro_specular", "albedo", "emission_color",
					"emission_energy"]:
				_save_param(st, m, pn)
			if role == "truffle":
				m.set_shader_parameter("albedo", TRUFFLE_ALBEDO)
				m.set_shader_parameter("emission_color", Color(1.0, 0.8, 0.28))
				m.set_shader_parameter("emission_energy", maxf(_num(vals.get("emission_energy"), 0.0), 0.4))
				m.set_shader_parameter("retro_specular", 0.5)
			elif game:
				m.set_shader_parameter("retro_specular", 0.3)
				if role != "hero" and role != "hazard":
					m.set_shader_parameter("retro_boost", GAME_SAT_BOOST)
			elif shiny:
				m.set_shader_parameter("retro_specular", 0.5)
			elif not _keep(m):
				m.set_shader_parameter("spec_strength", 0.0)
				m.set_shader_parameter("rim_strength", minf(_num(vals.get("rim_strength"), 0.45), 0.05))
				m.set_shader_parameter("roughness_value", 1.0)
				m.set_shader_parameter("retro_specular", 0.03)
				st["calm"] = true
				_calm_shader(m, st)
				# D037: one outline rule; the environment carries no ink outline (only the gameplay layer does).
				if m.next_pass is ShaderMaterial and (m.next_pass as ShaderMaterial).shader == _outline_shader:
					_save(st, m, "next_pass")
					m.next_pass = null
		"hot_chocolate":
			_save_param(st, m, "gloss")
			m.set_shader_parameter("gloss", minf(_num(vals.get("gloss"), 0.9), 0.5))
		"terrain", "foliage":
			if not game:
				st["calm"] = true
				_calm_shader(m, st)
		"water":
			# LOOK finish: the W1 river was the most saturated thing in every wide shot; it keeps its shine but joins
			# the environment colour budget.
			if not game:
				st["calm"] = true
				_calm_shader(m, st)
	return true


## Environment budget uniforms of a retro shader variant (recomputed on world change).
func _calm_shader(m: ShaderMaterial, st: Dictionary) -> void:
	var val := _env_val() * float(st.get("rule_val", 1.0))
	m.set_shader_parameter("retro_val", val)
	m.set_shader_parameter("retro_wall_val", val * _wall_val())
	if bool(st.get("calm", true)):
		m.set_shader_parameter("retro_sat_top", minf(float(st.get("sat_top", ENV_SAT_TOP)), _env_sat(true)))
		m.set_shader_parameter("retro_sat_wall", _env_sat(false))
		# Tinting toward the fog hue turned yellows olive (sky blue + straw = green): kept at 0.
		m.set_shader_parameter("retro_calm_tint_mix", 0.0)
		var fog := _fog_color()
		m.set_shader_parameter("retro_calm_tint", fog)


func _fog_color() -> Color:
	if _scene != null:
		var envs: Array = []
		_find_envs(_scene, envs)
		for we in envs:
			var e: Environment = (we as WorldEnvironment).environment
			if e != null and e.fog_enabled:
				return e.fog_light_color
	return Color(0.62, 0.68, 0.8)


## Per-world uniforms: environment value and fog tint on every live environment material, rim colour and sun direction on
## the pop passes.
func _refresh_world_params() -> void:
	for id in _mats:
		var m: Object = (_mats[id] as WeakRef).get_ref()
		if m == null or not m.has_meta(META):
			continue
		var st: Dictionary = m.get_meta(META)
		if not st.has("calm"):
			continue
		if m is ShaderMaterial and _variant_src.has((m as ShaderMaterial).shader):
			_calm_shader(m as ShaderMaterial, st)
		elif m is BaseMaterial3D and bool(st["calm"]):
			_calm_base(m as BaseMaterial3D, st)
	var sun := _sun_dir()
	var wr: Dictionary = WORLD_RIM.get(_world, WORLD_RIM["W1"])
	for w in _pop_mats:
		var p := (w as WeakRef).get_ref() as ShaderMaterial
		if p == null:
			continue
		p.set_shader_parameter("light_dir", sun)
		if String(p.get_meta("retro_role", "")) == "truffle":
			continue
		p.set_shader_parameter("rim_color", _rim_for(String(p.get_meta("retro_role", "")), wr))
		p.set_shader_parameter("ink", 1.0 if bool(wr["ink"]) else 0.0)


## Direction toward the sun (world space), from the scene's first shadow-casting DirectionalLight3D.
func _sun_dir() -> Vector3:
	if _scene != null:
		for l in _scene.find_children("*", "DirectionalLight3D", true, false):
			var dl := l as DirectionalLight3D
			if dl.visible:
				return dl.global_transform.basis.z.normalized()
	return Vector3(0.4, 0.8, 0.45).normalized()


## Uniforms never set on the material read back as null (the shader default applies).
static func _num(v: Variant, fallback: float) -> float:
	if v is float or v is int:
		return float(v)
	return fallback


static func _is_face(t: Texture2D) -> bool:
	var p := t.resource_path.to_lower()
	return p.contains("face") or p.contains("eye")


# ------------------------------------------------------------------ textures

## Returns the retro texture for `t`. In async mode (nodes spawned mid-game) a texture that still needs work is returned
## unchanged and swapped into `mat.prop` when its worker job finishes.
func _retro_tex(t: Texture2D, cat: String, mat: Material = null, prop: String = "") -> Texture2D:
	if t == null:
		return t
	if t.has_meta("retro"):
		return t
	var rule: Array = TEX_RULES.get(cat, TEX_RULES["env_prop"])
	var tsize := int(rule[0])
	if cat == "env_prop" and _ctx_mi != null and texel_fix:
		tsize = mini(_prop_budget(_ctx_mi, _ctx_surf, tsize), maxi(maxi(t.get_width(), t.get_height()), int(rule[0])))
	var key := "%d|%s" % [t.get_instance_id(), cat] if tsize == int(rule[0]) else "%d|%s|%d" % [t.get_instance_id(), cat, tsize]
	if _tex.has(key):
		if _tex_targets.has(key):
			if mat != null:
				(_tex_targets[key] as Array).append([weakref(mat), prop, t])
			return t
		return _tex[key]
	var path := t.resource_path
	if path.begins_with("res://assets/textures/") and not path.contains("::"):
		var rp := path.get_basename() + "_retro.png"
		if ResourceLoader.exists(rp):
			var off := load(rp) as Texture2D
			if off != null:
				off.set_meta("retro", true)
				_tex[key] = off
				return off
	# Only file/image textures can be read back; viewport, gradient and noise textures stay as they are.
	if not (t is CompressedTexture2D or t is ImageTexture or t is PortableCompressedTexture2D):
		_tex[key] = t
		return t
	var web_key := "%s|%s|%d|%s" % [path if path != "" else t.resource_name, cat, tsize, CACHE_VERSION]
	if cat == "face" and maxi(t.get_width(), t.get_height()) <= int(rule[0]):
		_tex[key] = t
		return t
	if OS.has_feature("web"):
		var entry: Dictionary = _web_manifest.get(web_key, {})
		if not entry.is_empty():
			var baked := load(WEB_CACHE + String(entry["file"])) as Texture2D
			baked.set_meta("retro", true)
			_tex[key] = baked
			last_stats["web_cache_hits"] = int(last_stats.get("web_cache_hits", 0)) + 1
			return baked
		# Never perform a readback, palette reduction or worker job in the browser.
		# The export verifier treats this diagnostic as a failed cache-coverage gate.
		if not _web_misses.has(web_key):
			_web_misses[web_key] = true
			push_error("[RetroLook] missing baked texture " + web_key)
		_tex[key] = t
		return t
	var img := t.get_image()
	if img == null or img.is_empty():
		_tex[key] = t
		return t
	var w := img.get_width()
	var h := img.get_height()
	if maxi(w, h) <= int(rule[0]) and cat == "face":
		_tex[key] = t
		return t
	var out := ImageTexture.new()
	out.set_meta("retro", true)
	out.resource_name = path.get_file().get_basename() + "_retro"
	var cache_file := ""
	if path != "":
		var src_file := path.split("::")[0]
		var mt := FileAccess.get_modified_time(src_file) if FileAccess.file_exists(src_file) else 0
		var ck := cat if tsize == int(rule[0]) else "%s%d" % [cat, tsize]
		cache_file = CACHE_DIR + ("%s|%d|%d|%s|%s|%d" % [path, w, h, ck, CACHE_VERSION, mt]).md5_text() + ".png"
	var job := {"img": img, "size": tsize, "colors": int(rule[1]), "sat": float(rule[2]), "cap": float(rule[3]),
		"gold": cat == "truffle", "cache": cache_file, "out": out, "result": null, "key": key}
	if _web_baking:
		job["web_key"] = web_key
	_tex_jobs.append(job)
	_tex[key] = out
	if _async:
		_tex_targets[key] = [] if mat == null else [[weakref(mat), prop, t]]
		return t
	return out


func _run_tex_jobs() -> void:
	if _tex_jobs.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var jobs := _tex_jobs
	_tex_jobs = []
	var gid := WorkerThreadPool.add_group_task(func(i: int) -> void: _tex_job(jobs[i]), jobs.size(), -1, true, "RetroLook textures")
	if _async and not _web_baking:
		_async_groups.append({"gid": gid, "jobs": jobs, "t0": Time.get_ticks_usec()})
		return
	var t0 := Time.get_ticks_usec()
	WorkerThreadPool.wait_for_group_task_completion(gid)
	_finish_jobs(jobs, t0)


func _poll_async() -> void:
	if _async_groups.is_empty():
		return
	var left: Array = []
	for g in _async_groups:
		if WorkerThreadPool.is_group_task_completed(int(g["gid"])):
			WorkerThreadPool.wait_for_group_task_completion(int(g["gid"]))
			_finish_jobs(g["jobs"], int(g["t0"]))
		else:
			left.append(g)
	_async_groups = left


func _finish_jobs(jobs: Array, t0: int) -> void:
	var hits := 0
	for j in jobs:
		var res: Image = j["result"]
		if j.get("cached", false):
			hits += 1
		var ok := res != null and not res.is_empty()
		if ok:
			(j["out"] as ImageTexture).set_image(res)
			if _web_baking:
				_write_web_texture(String(j["web_key"]), res)
				# A pickup can also appear as a static prop in story cinematics.
				# Bake that role from the same source pixels without waiting for the
				# whole cinematic to play in a headless export run.
				var pieces := String(j["web_key"]).split("|")
				var prop_key := "%s|env_prop|256|%s" % [pieces[0], CACHE_VERSION]
				if not _web_manifest.has(prop_key):
					var rule: Array = TEX_RULES["env_prop"]
					var extra := {"img": j["img"], "size": int(rule[0]), "colors": int(rule[1]),
						"sat": float(rule[2]), "cap": float(rule[3]), "gold": false, "cache": ""}
					_tex_job(extra)
					_write_web_texture(prop_key, extra["result"])
		var key: String = j["key"]
		if _tex_targets.has(key):
			for tg in _tex_targets[key]:
				var mat: Object = (tg[0] as WeakRef).get_ref()
				if mat == null or not ok or not enabled:
					continue
				if mat.get(String(tg[1])) == tg[2]:
					var st: Dictionary = mat.get_meta(META, {})
					if not st.is_empty() and not st["orig"].has(String(tg[1])):
						st["orig"][String(tg[1])] = tg[2]
					mat.set(String(tg[1]), j["out"])
			_tex_targets.erase(key)
		if not ok:
			_tex[key] = null
			_tex.erase(key)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	last_stats["tex_ms"] = float(last_stats.get("tex_ms", 0.0)) + ms
	last_stats["tex_jobs"] = int(last_stats.get("tex_jobs", 0)) + jobs.size()
	last_stats["tex_cache_hits"] = int(last_stats.get("tex_cache_hits", 0)) + hits
	print("[RetroLook] %d textures processed in %.1f ms (%d from disk cache)" % [jobs.size(), ms, hits])


func _write_web_texture(key: String, img: Image, metadata: Dictionary = {}) -> void:
	DirAccess.make_dir_recursive_absolute(WEB_CACHE + "textures")
	var file := "textures/" + key.sha256_text() + ".png"
	var result := img.save_png(WEB_CACHE + file)
	if result != OK:
		push_error("[RetroLook] cannot write baked texture " + file)
		return
	var entry := metadata.duplicate()
	entry["file"] = file
	entry["width"] = img.get_width()
	entry["height"] = img.get_height()
	_web_manifest[key] = entry
	var manifest := FileAccess.open(WEB_CACHE + "manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify(_web_manifest, "\t", true))


static func _tex_job(j: Dictionary) -> void:
	var cf: String = j["cache"]
	if cf != "" and FileAccess.file_exists(cf):
		var ci := Image.load_from_file(cf)
		if ci != null and not ci.is_empty():
			ci.generate_mipmaps()
			j["result"] = ci
			j["cached"] = true
			return
	var img: Image = (j["img"] as Image).duplicate()
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var target: int = j["size"]
	var w := img.get_width()
	var h := img.get_height()
	var s := float(target) / float(maxi(w, h))
	var has_alpha := img.detect_alpha() != Image.ALPHA_NONE
	if s < 1.0:
		if has_alpha:
			# Straight alpha would bleed the dark RGB of transparent texels into the edges: premultiply first.
			img.premultiply_alpha()
		var nw := maxi(1, roundi(w * s))
		var nh := maxi(1, roundi(h * s))
		# Repeated halving approximates a box filter (no aliasing from one big bilinear step).
		while img.get_width() >= nw * 2 and img.get_height() >= nh * 2:
			img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		if img.get_width() != nw or img.get_height() != nh:
			img.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
		if has_alpha:
			_unpremultiply(img)
	if bool(j.get("gold", false)):
		gold_ramp(img)
	else:
		palettize(img, j["colors"], j["sat"], float(j.get("cap", 1.0)))
	if cf != "":
		img.save_png(cf)
	img.generate_mipmaps()
	j["result"] = img


static func _unpremultiply(img: Image) -> void:
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var a := data[i + 3]
		if a > 0 and a < 255:
			data[i] = mini(255, data[i] * 255 / a)
			data[i + 1] = mini(255, data[i + 1] * 255 / a)
			data[i + 2] = mini(255, data[i + 2] * 255 / a)
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## Truffle textures: luminance mapped onto the fixed 6-tone gold ramp (no grain, never orange).
static func gold_ramp(img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var n := data.size() / 4
	var lo := 255.0
	var hi := 0.0
	for i in n:
		var l := 0.299 * data[i * 4] + 0.587 * data[i * 4 + 1] + 0.114 * data[i * 4 + 2]
		lo = minf(lo, l)
		hi = maxf(hi, l)
	var span := maxf(hi - lo, 1.0)
	for i in n:
		var o := i * 4
		var l2 := (0.299 * data[o] + 0.587 * data[o + 1] + 0.114 * data[o + 2] - lo) / span
		var c: Color = GOLD_RAMP[clampi(int(l2 * 5.0 + 0.5), 0, 5)]
		data[o] = c.r8
		data[o + 1] = c.g8
		data[o + 2] = c.b8
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## Limited palette (popularity palette on a 12-bit histogram, near-duplicate colours merged, histogram weighted by alpha),
## with an optional saturation multiplier and HSV saturation cap applied first. The darkest cluster is always kept, so grout
## and outline colours survive. Alpha is kept. Public so offline tools and tests can reuse it.
static func palettize(img: Image, colors: int, sat: float = 1.0, cap: float = 1.0) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var n := data.size() / 4
	var cnt := PackedInt32Array()
	cnt.resize(4096)
	var sr := PackedInt32Array()
	sr.resize(4096)
	var sg := PackedInt32Array()
	sg.resize(4096)
	var sb := PackedInt32Array()
	sb.resize(4096)
	var do_sat := absf(sat - 1.0) > 0.001 or cap < 0.999
	var darkest := -1
	var dark_l := 1 << 20
	var seen := PackedByteArray()
	seen.resize(4096)
	for i in n:
		var o := i * 4
		var r := data[o]
		var g := data[o + 1]
		var b := data[o + 2]
		if do_sat:
			var c := calm_color(Color8(r, g, b), cap, 1.0, sat)
			r = c.r8
			g = c.g8
			b = c.b8
			data[o] = r
			data[o + 1] = g
			data[o + 2] = b
		var k := ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)
		var wgt := 1 if data[o + 3] > 16 else 0
		seen[k] = 1
		cnt[k] += wgt
		sr[k] += r * wgt
		sg[k] += g * wgt
		sb[k] += b * wgt
		if wgt > 0:
			var lum := r * 3 + g * 6 + b
			if lum < dark_l:
				dark_l = lum
				darkest = k
	var bins: Array = []
	for k in 4096:
		if cnt[k] > 0:
			bins.append(k)
	if bins.is_empty():
		return
	var counts := cnt
	bins.sort_custom(func(a: int, c: int) -> bool: return counts[a] > counts[c])
	var pr := PackedInt32Array()
	var pg := PackedInt32Array()
	var pb := PackedInt32Array()
	# The darkest occupied bin goes in first (dark grout / ink lines are rare but carry the shapes).
	if darkest >= 0 and cnt[darkest] > 0:
		pr.append(sr[darkest] / cnt[darkest])
		pg.append(sg[darkest] / cnt[darkest])
		pb.append(sb[darkest] / cnt[darkest])
	for thr in [520, 180, 40]:
		for k in bins:
			if pr.size() >= colors:
				break
			var c := cnt[k]
			var r2 := sr[k] / c
			var g2 := sg[k] / c
			var b2 := sb[k] / c
			var ok := true
			for p in pr.size():
				var dr := r2 - pr[p]
				var dg := g2 - pg[p]
				var db := b2 - pb[p]
				if dr * dr + dg * dg + db * db < thr:
					ok = false
					break
			if ok:
				pr.append(r2)
				pg.append(g2)
				pb.append(b2)
		if pr.size() >= colors:
			break
	var lut := PackedInt32Array()
	lut.resize(4096)
	for k in 4096:
		if seen[k] == 0:
			continue
		var r3: int
		var g3: int
		var b3: int
		if cnt[k] > 0:
			r3 = sr[k] / cnt[k]
			g3 = sg[k] / cnt[k]
			b3 = sb[k] / cnt[k]
		else:
			r3 = ((k >> 8) & 15) * 16 + 8
			g3 = ((k >> 4) & 15) * 16 + 8
			b3 = (k & 15) * 16 + 8
		var best := 0
		var bd := 1 << 30
		for p in pr.size():
			var dr2 := r3 - pr[p]
			var dg2 := g3 - pg[p]
			var db2 := b3 - pb[p]
			var d := dr2 * dr2 * 3 + dg2 * dg2 * 4 + db2 * db2 * 2
			if d < bd:
				bd = d
				best = p
		lut[k] = best
	for i in n:
		var o2 := i * 4
		var k2 := ((data[o2] >> 4) << 8) | ((data[o2 + 1] >> 4) << 4) | (data[o2 + 2] >> 4)
		var pi := lut[k2]
		data[o2] = pr[pi]
		data[o2 + 1] = pg[pi]
		data[o2 + 2] = pb[pi]
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


# ------------------------------------------------------------------ gameplay pop and blob shadows

func _scan_groups() -> void:
	if not enabled or not pop_enabled:
		return
	for grp in GROUP_ROLES:
		var role: String = GROUP_ROLES[grp]
		if not POP.has(role):
			continue
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node3D and not _popped.has(n.get_instance_id()) and n.is_inside_tree():
				_pop_node(n as Node3D, role)
	_run_tex_jobs()


func _pop_node(n: Node3D, role: String) -> void:
	_popped[n.get_instance_id()] = weakref(n)
	# Make sure the node's own materials went through the gameplay path first (duplicates shared environment materials).
	var geoms: Array = []
	_collect_geoms(n, geoms)
	for g in geoms:
		if is_instance_valid(g):
			_process_geom(g as GeometryInstance3D)
	var cfg: Dictionary = POP[role]
	var meshes: Array = []
	for g in geoms:
		if not (g is MeshInstance3D) or not is_instance_valid(g) or _skip_geom(g) or _shadow_like(g as MeshInstance3D):
			continue
		var mi := g as MeshInstance3D
		if mi.mesh == null:
			continue
		meshes.append(mi)
		var radius := mi.get_aabb().size.length() * 0.5 * mi.global_transform.basis.get_scale().x
		if role == "enemy" or role == "boss" or role == "npc":
			var thin := _thin_radius(mi)
			if thin > 0.0 and mi.material_override == null:
				_pop_thin(mi, role, cfg, radius, thin)
				continue
		if mi.material_override != null:
			_add_pop(mi.material_override, role, cfg, radius)
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s)
			if m == null:
				m = mi.mesh.surface_get_material(s)
			if m != null:
				_add_pop(m, role, cfg, radius)
	if role == "hero":
		# Round-1 major M8: the hero's own contact-shadow decal did not read on the W1 path; make it a solid blob.
		for dc in n.find_children("*", "Decal", true, false):
			var d := dc as Decal
			if String(d.name).to_lower().contains("shadow") and d.modulate.a < 0.75:
				_decal_boosts.append([weakref(d), d.modulate])
				d.modulate = Color(0.16, 0.11, 0.22, 0.78)
	# Soft shadows (2026-10-19): characters, enemies, NPCs and the boss cast a real soft sun shadow while the setting is
	# on (their blob is lightened so the two never double-darken); with shadows off they are blob-only as before.
	if _casts(role):
		_cast_rule(meshes, true)
	if not _wants_blob(n, role) or _has_shadow(n):
		return
	var bs: Script = load(BLOB_SCRIPT_PATH)
	if bs == null:
		return
	var alpha := 0.45 if role == "hero" else (0.4 if role == "pickup" or role == "truffle" else 0.5)
	var b: Variant = bs.call("attach", n, -1.0, alpha)
	if b is Node:
		var bn := b as Node
		bn.set_meta("retro_skip", true)
		bn.process_mode = Node.PROCESS_MODE_ALWAYS
		if role == "pickup" or role == "truffle":
			bn.set("max_height", 4.0)
		bn.set_meta("ss_alpha", alpha)
		bn.set_meta("ss_caster", _casts(role))
		_blobs.append(weakref(bn))
		if _soft and _casts(role):
			bn.set("max_alpha", alpha * SoftShadows.BLOB_GROUND_K)
		# Pickups and truffles stay blob-only (small spinning casters flicker; round-1 minor: 46 of 53 doubled).
		if not _casts(role):
			_cast_rule(meshes, false)


func _cast_rule(meshes: Array, caster: bool) -> void:
	for mi2 in meshes:
		var gi := mi2 as GeometryInstance3D
		_shadow_offs.append([weakref(gi), gi.cast_shadow, caster])
		gi.cast_shadow = SoftShadows.actor_cast(gi.cast_shadow, _soft) if caster \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _casts(role: String) -> bool:
	return role == "hero" or role == "enemy" or role == "boss" or role == "npc"


## Soft shadows setting changed (or a scene was entered): lights, actor casters and blob strength follow it.
func _apply_soft(on: bool) -> void:
	_soft = on
	var cs := get_tree().current_scene
	if cs != null:
		var wid: Variant = cs.get("world_id")
		SoftShadows.apply_tree(cs, on, String(wid) if wid != null else "")
	for e in _shadow_offs:
		var gi: Object = (e[0] as WeakRef).get_ref()
		if gi != null:
			(gi as GeometryInstance3D).cast_shadow = SoftShadows.actor_cast(int(e[1]), on) if bool(e[2]) \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for w in _blobs:
		var b: Object = (w as WeakRef).get_ref()
		if b != null and b.has_meta("ss_alpha"):
			var k := SoftShadows.BLOB_GROUND_K if on and bool(b.get_meta("ss_caster", false)) else 1.0
			b.set("max_alpha", float(b.get_meta("ss_alpha")) * k)


## Blobs go under moving actors and pickups, never under signposts and other static talkers.
static func _wants_blob(n: Node, role: String) -> bool:
	if role == "hero":
		return true
	if role == "npc":
		var nm := String(n.name).to_lower()
		if nm.contains("sign") or n is StaticBody3D:
			return false
		return n is CharacterBody3D or not n.find_children("*", "Skeleton3D", true, false).is_empty() \
			or not n.find_children("*", "AnimationPlayer", true, false).is_empty()
	return true


## Half the smallest world-space extent of a thin part (lance, stalk, antenna), or 0 when the part is not thin.
static func _thin_radius(mi: MeshInstance3D) -> float:
	var sz := mi.get_aabb().size * mi.global_transform.basis.get_scale()
	var mn := minf(absf(sz.x), minf(absf(sz.y), absf(sz.z)))
	var mx := maxf(absf(sz.x), maxf(absf(sz.y), absf(sz.z)))
	if mn <= 0.0 or mn > 0.16 or mx < mn * 4.0:
		return 0.0
	return mn * 0.5


## Thin parts share their colour material with the body (EnemyKit caches by colour), so they get their own copy whose
## outline is capped to a fraction of the part's radius (LOOK finish: lances no longer turn into thick black poles).
func _pop_thin(mi: MeshInstance3D, role: String, cfg: Dictionary, radius: float, thin: float) -> void:
	for s in mi.mesh.get_surface_count():
		var m := mi.get_surface_override_material(s)
		var prev := m
		if m == null:
			m = mi.mesh.surface_get_material(s)
		if m == null or not m.has_meta(META):
			continue
		var st: Dictionary = m.get_meta(META)
		var base_next: Material = m.next_pass
		if st.has("popped"):
			base_next = st["orig"].get("next_pass", null)
		var d := m.duplicate() as Material
		var st2 := {"role": st["role"], "orig": {}}
		d.set_meta(META, st2)
		if base_next is ShaderMaterial and (base_next as ShaderMaterial).shader == _outline_shader:
			var o := base_next.duplicate() as ShaderMaterial
			o.set_shader_parameter("thin_radius", thin)
			d.next_pass = o
		else:
			d.next_pass = base_next
		_node_overrides.append([weakref(mi), s, prev])
		mi.set_surface_override_material(s, d)
		_add_pop(d, role, cfg, radius, thin)


func _add_pop(m: Material, role: String, cfg: Dictionary, radius: float, thin := 0.0) -> void:
	if m.has_meta("retro_pop") or not m.has_meta(META):
		return
	if m is BaseMaterial3D and (m as BaseMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return
	if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return
	if m is ShaderMaterial and not _variant_src.has((m as ShaderMaterial).shader):
		# Foreign shaders get the pop only on truffles (their skin shader is built in code; round-1 M3: the truffle was
		# not the hero of the frame), and never on unshaded or additive FX surfaces.
		var sh := (m as ShaderMaterial).shader
		if role != "truffle" or sh == null or sh.code.contains("unshaded") or sh.code.contains("blend_add"):
			return
	var st: Dictionary = m.get_meta(META)
	if not _is_game(String(st["role"])) or st.has("popped"):
		return
	st["popped"] = true
	_save(st, m, "next_pass")
	var wr: Dictionary = WORLD_RIM.get(_world, WORLD_RIM["W1"])
	var p := ShaderMaterial.new()
	p.shader = _pop_shader
	p.set_meta("retro_pop", true)
	p.set_meta("retro_role", role)
	p.set_shader_parameter("rim_color", _rim_for(role, wr))
	p.set_shader_parameter("ink", 0.0 if role == "truffle" or not bool(wr["ink"]) else 1.0)
	p.set_shader_parameter("rim_strength", cfg["rim_strength"])
	p.set_shader_parameter("shadow_gate", cfg["gate"])
	p.set_shader_parameter("light_dir", _sun_dir())
	p.set_shader_parameter("fade_far", cfg["far"])
	_pop_mats.append(weakref(p))
	var chain: Material = p
	if float(cfg["glint"]) > 0.0 or float(cfg["lift"]) > 0.0:
		var gl := ShaderMaterial.new()
		gl.shader = _glint_shader
		gl.set_meta("retro_pop", true)
		gl.set_shader_parameter("glint_strength", cfg["glint"])
		gl.set_shader_parameter("lift", cfg["lift"])
		gl.set_shader_parameter("fade_far", cfg["far"])
		p.next_pass = gl
		chain = gl
	var nxt: Material = m.next_pass
	if nxt is ShaderMaterial and (nxt as ShaderMaterial).shader == _outline_shader:
		if bool(cfg.get("strip_outline", false)):
			# D037: NPCs carry no ink outline (Cousin Pip's read as a bold maroon halo); m.next_pass was saved above.
			nxt = null
		else:
			_normalize_outline(nxt as ShaderMaterial, cfg, radius, thin)
	if nxt == null and cfg["outline"]:
		var o := ShaderMaterial.new()
		o.shader = _outline_shader
		o.set_meta("retro_pop", true)
		o.set_shader_parameter("outline_width", OUTLINE_PX)
		o.set_shader_parameter("max_world_width", cfg["max_w"])
		o.set_shader_parameter("exact_px", true)
		o.set_shader_parameter("viewport_height", float(get_viewport().get_visible_rect().size.y))
		o.set_shader_parameter("object_radius", radius)
		o.set_shader_parameter("fade_px", cfg["fade_px"])
		o.set_shader_parameter("fade_far", float(cfg.get("outline_far", 0.0)))
		o.set_shader_parameter("thin_radius", thin)
		o.set_shader_parameter("outline_color", Color(0.16, 0.08, 0.1) if role != "truffle" else Color(0.3, 0.15, 0.03))
		nxt = o
	chain.next_pass = nxt
	m.next_pass = p


## D037 one outline rule: every gameplay outline (FxToon's per-object widths of 1.0-2.4 px included) becomes the same
## exact screen-space width with the role's world cap; the originals are restored on revert.
func _normalize_outline(o: ShaderMaterial, cfg: Dictionary, radius: float, thin: float) -> void:
	if o.has_meta("retro_outline_norm"):
		if thin > 0.0:
			o.set_shader_parameter("thin_radius", thin)
		return
	var orig := {}
	for k in ["outline_width", "max_world_width", "exact_px", "viewport_height", "object_radius", "fade_px", "fade_far",
			"thin_radius"]:
		orig[k] = o.get_shader_parameter(k)
	_outline_saves.append([weakref(o), orig])
	o.set_meta("retro_outline_norm", true)
	o.set_shader_parameter("outline_width", OUTLINE_PX)
	o.set_shader_parameter("max_world_width", cfg["max_w"])
	o.set_shader_parameter("exact_px", true)
	o.set_shader_parameter("viewport_height", float(get_viewport().get_visible_rect().size.y))
	o.set_shader_parameter("object_radius", radius)
	o.set_shader_parameter("fade_px", cfg["fade_px"])
	o.set_shader_parameter("fade_far", float(cfg.get("outline_far", 0.0)))
	o.set_shader_parameter("thin_radius", thin)


static func _rim_for(role: String, wr: Dictionary) -> Color:
	if role == "truffle":
		return TRUFFLE_RIM
	if role == "enemy" or role == "boss":
		return wr.get("enemy", wr["rim"])
	return wr["rim"]


static func _shadow_like(mi: MeshInstance3D) -> bool:
	if String(mi.name).to_lower().contains("shadow"):
		return true
	if (mi.mesh is PlaneMesh or mi.mesh is QuadMesh) and mi.mesh.get_surface_count() > 0:
		var m := mi.material_override if mi.material_override != null else mi.get_active_material(0)
		if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
		if m is ShaderMaterial:
			return true
	return false


## True when `n` already has a visible contact shadow of its own (a Decal or a shadow card that is actually shown).
static func _has_shadow(n: Node) -> bool:
	var stack: Array = [[n, 0]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var c: Node = e[0]
		if c != n:
			if c is Decal and (c as Decal).visible:
				return true
			if c is MeshInstance3D and _shadow_like(c as MeshInstance3D) and (c as MeshInstance3D).visible:
				return true
		if int(e[1]) < 3:
			for k in c.get_children():
				stack.append([k, int(e[1]) + 1])
	return false


# ------------------------------------------------------------------ environment grade

func _apply_env(root: Node) -> void:
	var preset: Dictionary = PRESETS.get(_world, {"sat": 1.0, "contrast": 1.04, "glow": 0.6, "bloom": 0.02})
	var envs: Array = []
	_find_envs(root, envs)
	for we in envs:
		var e: Environment = (we as WorldEnvironment).environment
		if e == null:
			continue
		var orig: Dictionary
		if e.has_meta(ENV_META):
			orig = e.get_meta(ENV_META)
		else:
			orig = {}
			for k in ENV_KEYS:
				orig[k] = e.get(k)
			e.set_meta(ENV_META, orig)
			_envs.append(weakref(e))
		var adj: bool = orig["adjustment_enabled"]
		e.adjustment_enabled = true
		e.adjustment_saturation = (orig["adjustment_saturation"] if adj else 1.0) * float(preset.get("sat", 1.0))
		e.adjustment_contrast = (orig["adjustment_contrast"] if adj else 1.0) * float(preset.get("contrast", 1.0))
		e.adjustment_brightness = (orig["adjustment_brightness"] if adj else 1.0) * float(preset.get("brightness", 1.0))
		e.glow_intensity = orig["glow_intensity"] * float(preset.get("glow", 1.0))
		e.glow_bloom = minf(orig["glow_bloom"], float(preset.get("bloom", 1.0)))
		if preset.has("fog_begin") and e.fog_enabled and e.fog_mode == Environment.FOG_MODE_DEPTH:
			# Round-1 major: the old preset pulled the fog onto the playfield; it now only ever pushes it back.
			e.fog_depth_begin = maxf(orig["fog_depth_begin"], float(preset["fog_begin"]))
			e.fog_depth_end = maxf(orig["fog_depth_end"], float(preset["fog_end"]))
		if preset.has("aerial") and e.fog_enabled:
			e.fog_aerial_perspective = minf(orig["fog_aerial_perspective"], float(preset["aerial"]))
		e.ssr_enabled = false
		e.tonemap_exposure = orig["tonemap_exposure"] * float(preset.get("exposure", 1.0))
		e.ambient_light_energy = orig["ambient_light_energy"] + float(preset.get("ambient_add", 0.0))
		if OS.has_feature("web"):
			# Compatibility tonemaps the base and additive light passes separately.
			# Grading overrides compared with the unchanged Forward+ story cameras. The UI uses
			# its own canvas and retains its authored colors.
			# OPUSLOOK: brightness and exposure are back at 1. The colour-space fix (inc/web_color.gdshaderinc) and the
			# shadowed-light scale (SoftShadows.WEB_SHADOWED_ENERGY) correct the lit surfaces themselves; the darker
			# grade had dimmed the sky and the unlit backdrops with them. Saturation is re-measured on the new frames.
			var grade: Array = {"": [0.97,0.77,1.0], "HUB": [0.92,0.9,0.92],
				"W1": [1.0,1.0,1.0], "W2": [0.95,1.0,1.0],
				"W3": [1.0,1.02,1.0], "BOSS": [0.95,1.07,1.0]}.get(_world,[1.0,1.0,1.0])
			e.adjustment_brightness *= float(grade[0])
			e.adjustment_saturation *= float(grade[1])
			e.tonemap_exposure *= float(grade[2])


func _find_envs(n: Node, out: Array) -> void:
	if n is WorldEnvironment:
		out.append(n)
	for c in n.get_children():
		if c is WorldEnvironment or c.get_child_count() > 0:
			_find_envs(c, out)


# ------------------------------------------------------------------ revert

## Restores every material, texture, environment and node override, removes the pop passes and blob shadows we added.
# ------------------------------------------------------------------ web: PBR maps the toon look never draws (Round 4)

## Round 4 (web): generated props keep their PBR source material on the mesh while the toon twin draws, so their ORM
## and NormalGL maps stayed in video memory as uncompressed RGB8 (4 MB each at 1024 px with mipmaps), although the
## twins never read ORM and only game-role twins read normals. After a scene is converted, an imported ORM, roughness,
## metallic, AO or normal map that only replaced materials reference keeps its Texture2D, path and size but gets
## 1 x 1 pixel data (RenderingServer.texture_replace): neutral ORM (no occlusion, rough, not metallic) or a flat normal,
## so a material that still reads one looks a little plainer, never broken. A map that an active material needs again
## (a spawned enemy's twin, the classic look turned off) is reloaded from the pack first. Albedo maps are never
## released: a stray reader would show a flat colour.
const WEB_RELEASE := ["normal_texture", "orm_texture", "roughness_texture", "metallic_texture", "ao_texture"]


func _web_release() -> void:
	if not OS.has_feature("web") or _web_baking or not enabled:
		return
	var t0 := Time.get_ticks_usec()
	var drawn := {}
	var seen := {}
	var replaced: Array = []
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var g := n as GeometryInstance3D
		if g == null:
			continue
		for m in _drawn_materials(g):
			_note_textures(m, drawn, seen)
		var mi := g as MeshInstance3D
		if mi != null and mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var own := mi.mesh.surface_get_material(s)
				if own != null and own != mi.get_active_material(s):
					replaced.append(own)
	for e in _node_overrides:
		if e[2] is Material:
			replaced.append(e[2])
	var count := 0
	var mb := 0.0
	for m in replaced:
		if not (m is BaseMaterial3D):
			continue
		for prop in WEB_RELEASE:
			if not (prop in m):
				continue
			var t := m.get(prop) as CompressedTexture2D
			if t == null or t.resource_path == "" or t.get_width() < 256 or drawn.has(t.get_instance_id()) \
					or _released.has(t.get_instance_id()):
				continue
			mb += t.get_width() * t.get_height() * 4.0 / 1048576.0
			var pixel := Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
			pixel.set_pixel(0, 0, Color(0.5, 0.5, 1.0) if prop == "normal_texture" else Color(1.0, 1.0, 0.0))
			_released[t.get_instance_id()] = [weakref(t), t.resource_path]
			RenderingServer.texture_replace(t.get_rid(), RenderingServer.texture_2d_create(pixel))
			count += 1
	if count > 0:
		print("[RetroLook] web: released %d PBR maps no drawn material reads (about %.0f MB) in %.1f ms" % [count, mb,
			(Time.get_ticks_usec() - t0) / 1000.0])


## Released maps that the geometry of a new batch draws with come back before its first frame.
func _web_revive(geoms: Array) -> void:
	if _released.is_empty():
		return
	var used := {}
	var seen := {}
	for g in geoms:
		if is_instance_valid(g) and g is GeometryInstance3D:
			for m in _drawn_materials(g as GeometryInstance3D):
				_note_textures(m, used, seen)
	for id in used:
		if _released.has(id):
			_web_reload(id)


func _web_reload(id: int) -> void:
	var entry: Array = _released[id]
	_released.erase(id)
	var t := (entry[0] as WeakRef).get_ref() as Texture2D
	if t == null:
		return
	var fresh := ResourceLoader.load(String(entry[1]), "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if fresh == null:
		push_error("[RetroLook] web: could not reload " + String(entry[1]))
		return
	RenderingServer.texture_replace(t.get_rid(), fresh.get_rid())
	_revived.append(fresh)


## Every material a geometry draws with: overrides, surfaces, multimesh and particle meshes, next passes.
func _drawn_materials(g: GeometryInstance3D) -> Array:
	var out: Array = []
	if g.material_override != null:
		out.append(g.material_override)
	if g.material_overlay != null:
		out.append(g.material_overlay)
	var meshes: Array = []
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		if mi.mesh != null and g.material_override == null:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				if m != null:
					out.append(m)
	elif g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm != null:
			meshes.append(mm.mesh)
	elif g is GPUParticles3D:
		var p := g as GPUParticles3D
		for i in p.draw_passes:
			meshes.append(p.get_draw_pass_mesh(i))
		if p.process_material != null:
			out.append(p.process_material)
	elif g is CPUParticles3D:
		meshes.append((g as CPUParticles3D).mesh)
	elif "material" in g and g.get("material") is Material:
		out.append(g.get("material"))
	for mesh in meshes:
		if mesh is Mesh:
			for s in (mesh as Mesh).get_surface_count():
				var m2 := (mesh as Mesh).surface_get_material(s)
				if m2 != null:
					out.append(m2)
	var i := 0
	while i < out.size() and i < 64:
		var following := (out[i] as Material).next_pass
		if following != null:
			out.append(following)
		i += 1
	return out


func _note_textures(m: Material, into: Dictionary, seen: Dictionary) -> void:
	if m == null or seen.has(m.get_instance_id()):
		return
	seen[m.get_instance_id()] = true
	if m is BaseMaterial3D:
		for i in BaseMaterial3D.TEXTURE_MAX:
			var t := (m as BaseMaterial3D).get_texture(i)
			if t != null:
				into[t.get_instance_id()] = true
	elif m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		var shader := (m as ShaderMaterial).shader
		if not _shader_textures.has(shader):
			var names: Array = []
			for u in shader.get_shader_uniform_list():
				if int(u["type"]) == TYPE_OBJECT:
					names.append(String(u["name"]))
			_shader_textures[shader] = names
		for uniform in _shader_textures[shader]:
			var v: Variant = (m as ShaderMaterial).get_shader_parameter(uniform)
			if v is Texture:
				into[(v as Object).get_instance_id()] = true


func revert_all() -> void:
	# The source materials draw again: every map released on the web comes back first.
	for id in _released.keys():
		_web_reload(id)
	for g in _async_groups:
		WorkerThreadPool.wait_for_group_task_completion(int(g["gid"]))
	_async_groups.clear()
	_tex_targets.clear()
	for id in _mats:
		var m: Object = (_mats[id] as WeakRef).get_ref()
		if m == null or not m.has_meta(META):
			continue
		var st: Dictionary = m.get_meta(META)
		_restore_props(m as Material, st["orig"])
		for k in [META, "retro_dup_game", "retro_dup_env"]:
			if m.has_meta(k):
				m.remove_meta(k)
	_mats.clear()
	for e in _node_overrides:
		var node: Object = (e[0] as WeakRef).get_ref()
		if node == null:
			continue
		if int(e[1]) < 0:
			(node as GeometryInstance3D).material_override = e[2]
		else:
			(node as MeshInstance3D).set_surface_override_material(int(e[1]), e[2])
	_node_overrides.clear()
	for e in _outline_saves:
		var ol: Object = (e[0] as WeakRef).get_ref()
		if ol != null:
			for k in e[1]:
				(ol as ShaderMaterial).set_shader_parameter(k, e[1][k])
			ol.remove_meta("retro_outline_norm")
	_outline_saves.clear()
	for e in _shadow_offs:
		var gi: Object = (e[0] as WeakRef).get_ref()
		if gi != null:
			(gi as GeometryInstance3D).cast_shadow = e[1]
	_shadow_offs.clear()
	for e in _decal_boosts:
		var dc: Object = (e[0] as WeakRef).get_ref()
		if dc != null:
			(dc as Decal).modulate = e[1]
	_decal_boosts.clear()
	for w in _envs:
		var env: Object = (w as WeakRef).get_ref()
		if env != null and env.has_meta(ENV_META):
			var orig: Dictionary = env.get_meta(ENV_META)
			for k in orig:
				env.set(k, orig[k])
			env.remove_meta(ENV_META)
	_envs.clear()
	for w in _blobs:
		var b: Object = (w as WeakRef).get_ref()
		if b != null:
			(b as Node).queue_free()
	_blobs.clear()
	_popped.clear()
	_pop_mats.clear()
	_pending.clear()
	_tex.clear()


# ------------------------------------------------------------------ evidence mode (--retro-shots)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run_shots(dir: String) -> void:
	if dir == "":
		return
	_shooting = true
	var dev := get_node_or_null("/root/Dev")
	var wait := int(dev.arg("retro-wait", "150")) if dev else 150
	get_window().size = Vector2i(1920, 1080)
	# --retro-areas=res://a.tscn,res://b.tscn: after the first scene, load each listed scene in turn (one launch, one slot).
	var areas: Array = []
	if dev and dev.has_arg("retro-areas"):
		for a in String(dev.arg("retro-areas", "")).split(",", false):
			areas.append(a)
	await _frames(wait)
	await _shots_for_scene(dir, dev)
	for a in areas:
		print("[RetroLook] next area ", a)
		get_tree().paused = false
		get_tree().change_scene_to_file(a)
		await _frames(wait)
		await _shots_for_scene(dir, dev)
	get_tree().quit()


## Hides every CanvasLayer (HUD, banners, dialogue) and Label3D (barks) for clean captures; returns what to restore.
func _hide_overlays() -> Array:
	var saved: Array = []
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		saved.append([cl, (cl as CanvasLayer).visible])
		(cl as CanvasLayer).visible = false
	for lb in get_tree().root.find_children("*", "Label3D", true, false):
		saved.append([lb, (lb as Node3D).visible])
		(lb as Node3D).visible = false
	return saved


static func _restore_vis(saved: Array) -> void:
	for s in saved:
		if is_instance_valid(s[0]):
			s[0].visible = s[1]


func _shots_for_scene(dir: String, dev: Node) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var area := String(scene.get("world_id")) if scene.get("world_id") != null else String(scene.name)
	area = area.to_lower()
	var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "") + "Z"
	DirAccess.make_dir_recursive_absolute(dir)
	var cams := String(dev.arg("retro-cams", "StoryCam_A,StoryCam_B,StoryCam_C,StoryCam_D") if dev else "StoryCam_A").split(",")
	var report := {"area": area, "stamp": stamp, "shots": [], "stats_first_apply": last_stats.duplicate()}
	# Frozen pairs: the tree is paused (RetroLook and its blobs keep processing), so off/on frames match.
	get_tree().paused = true
	var overlays := _hide_overlays()
	var game_cam := get_viewport().get_camera_3d()
	var cam_pos := game_cam.global_position if game_cam != null else Vector3.ZERO
	if game_cam != null:
		await _shoot_set(dir, "%s__retro_%s_gameplay" % [stamp, area], report)
	for cn in cams:
		var cam := scene.find_child(cn, true, false) as Camera3D
		if cam == null:
			continue
		cam.make_current()
		await _shoot_set(dir, "%s__retro_%s_%s" % [stamp, area, cn.to_lower()], report)
	var roles := ["hero", "enemy", "truffle"]
	if dev and dev.has_arg("retro-closeup-npc"):
		roles.append("npc")
	for role in roles:
		var tgt := _closeup_target(role, cam_pos)
		if tgt == null:
			continue
		var c := Camera3D.new()
		c.fov = 40.0
		scene.add_child(c)
		var box := _visual_box(tgt)
		var center := box.get_center()
		# Frame the target from its front (glTF models face +Z inside a Visual rotated to -Z: the body's -Z is the front).
		var fwd := -tgt.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 0.01:
			fwd = Vector3.FORWARD
		var hgt := maxf(box.size.y, 0.4)
		var dist := clampf(hgt * 1.25 / tan(deg_to_rad(20.0)), 1.6, 9.0)
		if role == "npc" and dev.has_arg("retro-debug"):
			_debug_chain(tgt)
		if role == "npc":
			# A wider "spot" shot: the NPC plus the building or props behind it (D037 shading-consistency check).
			dist *= 2.4
		c.global_position = center + fwd.normalized() * dist + Vector3.UP * hgt * 0.35
		c.look_at(center, Vector3.UP)
		c.make_current()
		await _shoot_set(dir, "%s__retro_%s_closeup_%s" % [stamp, area, role], report)
		c.queue_free()
	_restore_vis(overlays)
	get_tree().paused = false
	var first := scene.find_child(cams[0], true, false) as Camera3D
	if first:
		first.make_current()
	var ft0: Dictionary = await _measure(false)
	var ft1: Dictionary = await _measure(true)
	report["frame_ms"] = {"retro0": ft0, "retro1": ft1}
	report["stats"] = last_stats.duplicate()
	var f := FileAccess.open(dir.path_join("%s__retro_%s_report.json" % [stamp, area]), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("[RetroLook] shots done (%s): %s" % [area, JSON.stringify(report["frame_ms"])])


func _shoot_set(dir: String, base: String, report: Dictionary) -> void:
	# Keep the shot's camera: re-applying the look can hand "current" back to a gameplay camera (close-ups missed).
	var cam := get_viewport().get_camera_3d()
	set_enabled(false)
	await _frames(12)
	if cam and is_instance_valid(cam):
		cam.make_current()
	await _save_shot(dir.path_join(base + "_retro0.png"))
	set_enabled(true)
	await _frames(20)
	if cam and is_instance_valid(cam):
		cam.make_current()
		await _frames(2)
	await _save_shot(dir.path_join(base + "_retro1.png"))
	await _shoot_mask(dir.path_join(base + "_mask.png"))
	report["shots"].append(base)


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[RetroLook] shot ", path)


## Gameplay mask: gameplay nodes white, everything else black, sky black. Used for the greyscale separation metric.
func _shoot_mask(path: String) -> void:
	var scene := get_tree().current_scene
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	var white := black.duplicate() as StandardMaterial3D
	white.albedo_color = Color.WHITE
	var saved: Array = []
	var geoms: Array = []
	_collect_geoms(scene, geoms)
	for g in geoms:
		var gi := g as GeometryInstance3D
		var role := _role_of(gi)
		var game := _is_game(role) and role != "hazard" and not (gi is MeshInstance3D and _shadow_like(gi as MeshInstance3D)) \
			and not (gi is GPUParticles3D or gi is CPUParticles3D)
		saved.append([gi, gi.material_override, gi.visible, gi.material_overlay])
		gi.material_overlay = null
		if gi is GPUParticles3D or gi is CPUParticles3D or gi is SpriteBase3D or gi is Label3D:
			gi.visible = false
		elif not game and _foreign_shader(gi):
			# Post-process quads, FX ribbons and backdrop shaders would paint over the mask.
			gi.visible = false
		if gi.material_override is ShaderMaterial:
			# Scripts cast these overrides back to ShaderMaterial every frame (contact shadows, hazards): never replace them.
			if game:
				gi.material_overlay = white
			else:
				gi.visible = false
			continue
		gi.material_override = white if game else black
	var envs: Array = []
	_find_envs(scene, envs)
	var env_saved: Array = []
	for we in envs:
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color.BLACK
		e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env_saved.append([we, we.environment])
		we.environment = e
	await _frames(3)
	await _save_shot(path)
	for s in saved:
		if is_instance_valid(s[0]):
			(s[0] as GeometryInstance3D).material_override = s[1]
			(s[0] as GeometryInstance3D).visible = s[2]
			(s[0] as GeometryInstance3D).material_overlay = s[3]
	for s in env_saved:
		(s[0] as WorldEnvironment).environment = s[1]
	await _frames(2)


func _foreign_shader(gi: GeometryInstance3D) -> bool:
	var m: Material = gi.material_override
	if m == null and gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null and (gi as MeshInstance3D).mesh.get_surface_count() > 0:
		m = (gi as MeshInstance3D).get_active_material(0)
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		if sh == null:
			return true
		var src: Shader = _variant_src.get(sh, sh)
		return not (RETRO_SHADER_PATHS.has(src.resource_path) or WORLD_SHADERS.has(src.resource_path)
			or src.resource_path == "res://assets/shaders/cloud.gdshader")
	return false


## Close-up target: the visible node of the role's groups nearest to the gameplay camera (round-1 minor: the old pick
## framed the wrong thing).
func _closeup_target(role: String, from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	# --retro-closeup=<name part>: the enemy close-up prefers enemies whose node or script name contains it.
	var dev := get_node_or_null("/root/Dev")
	var want := String(dev.arg("retro-closeup", "")).to_lower() if dev and role == "enemy" else ""
	if dev and role == "npc":
		want = String(dev.arg("retro-closeup-npc", "")).to_lower()
	for grp in GROUP_ROLES:
		if GROUP_ROLES[grp] != role:
			continue
		for n in get_tree().get_nodes_in_group(grp):
			if want != "":
				var sc: Script = n.get_script()
				var label := (String(n.name) + " " + (sc.resource_path if sc else "")).to_lower()
				if not label.contains(want):
					continue
			if n is Node3D and (n as Node3D).is_visible_in_tree():
				var d := (n as Node3D).global_position.distance_squared_to(from)
				if d < bd:
					bd = d
					best = n
	return best


func _debug_chain(n: Node) -> void:
	var gs: Array = []
	_collect_geoms(n, gs)
	for g in gs:
		var gi := g as GeometryInstance3D
		var line := "[RetroLook dbg] %s scale=%s ovr=%s overlay=%s" % [gi.name, gi.global_transform.basis.get_scale(), gi.material_override, gi.material_overlay]
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			var mi := gi as MeshInstance3D
			for si in mi.mesh.get_surface_count():
				var m: Material = mi.get_active_material(si)
				var chain := ""
				while m != null:
					var nm := m.get_class()
					if m is ShaderMaterial and (m as ShaderMaterial).shader:
						nm = (m as ShaderMaterial).shader.resource_path.get_file()
						if nm == "outline.gdshader":
							var sm := m as ShaderMaterial
							nm += "(w=%s cap=%s ex=%s vh=%s)" % [sm.get_shader_parameter("outline_width"), sm.get_shader_parameter("max_world_width"), sm.get_shader_parameter("exact_px"), sm.get_shader_parameter("viewport_height")]
					if m is BaseMaterial3D:
						var bm := m as BaseMaterial3D
						var st0: Dictionary = bm.get_meta(META, {})
						nm += "(cull=%d tr=%d met=%.2f shiny=%s keep=%s name=%s role=%s orig_met=%s)" % [bm.cull_mode, bm.transparency, bm.metallic, _shiny(bm), _keep(bm), _name_of(bm), st0.get("role", "-"), (st0.get("orig", {}) as Dictionary).get("metallic", "-")]
					chain += nm + " > "
					m = m.next_pass
				line += "
   s%d: %s" % [si, chain]
		print(line)


func _visual_box(n: Node3D) -> AABB:
	var geoms: Array = []
	_collect_geoms(n, geoms)
	var have := false
	var box := AABB(n.global_position, Vector3(0.6, 1.0, 0.6))
	for g in geoms:
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null and not _shadow_like(g as MeshInstance3D) \
				and (g as MeshInstance3D).is_visible_in_tree():
			var b := (g as MeshInstance3D).global_transform * (g as MeshInstance3D).get_aabb()
			box = b if not have else box.merge(b)
			have = true
	return box


func _visual_center(n: Node3D) -> Vector3:
	return _visual_box(n).get_center()


func _measure(on: bool) -> Dictionary:
	set_enabled(on)
	await _frames(40)
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(10)
	var gpu := 0.0
	var cpu := 0.0
	var proc := 0.0
	var frames := 120
	var t0 := Time.get_ticks_usec()
	var worst := 0.0
	var last := t0
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return {"gpu_ms": gpu / frames, "render_cpu_ms": cpu / frames, "process_ms": proc / frames,
		"wall_frame_ms": (Time.get_ticks_usec() - t0) / 1000.0 / frames, "worst_frame_ms": worst,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}

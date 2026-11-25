# Super Mak 64 VFX, shaders and look development (vfx workstream)

Everything here is owned by the vfx workstream. Other areas use it through the scenes,
resources and static helpers below; request changes in DEVLOG or a report.

## Tests

`python tools/godot.py run res://scenes/fx/FxSelfTest.tscn --seconds 7 -- --profile=vfx` instantiates every effect scene,
plays it and checks that one-shots free themselves and continuous effects stay (25/25 PASS at 02:30 Bangkok).
VFXLab `--perf` prints frame time: 3.7 to 4.2 ms at 1600x900 on the RTX 4070 SUPER with 14k grass tufts and all effects.

## Look in one minute

Run `python tools/godot.py capture res://scenes/fx/VFXLab.tscn out.png --cam StoryCam_A -- --profile=vfx`
(cams: `StoryCam_A` overview, `StoryCam_B` hero, `StoryCam_C` effect row, `StoryCam_D` liquids/candy, plus review cams
`SkyCam` and `ToonCam`). Lab args after `--`: `--env=W1|W2|W3|HUB|BOSS`, `--fxfocus` (fire every one-shot together),
`--pageturn=0.45` (freeze a transition), `--build-env` (re-save the environment and material libraries, then quit).

## Environments (tonemap, glow, SSAO, depth haze, sky)

- Saved: `res://assets/shaders/environments/env_HUB|W1|W2|W3|BOSS.tres` (Environment with the painterly sky shader).
- Runtime, from a world script: `FxEnvironments.apply(self, "W1")` sets the scene's `WorldEnvironment` and tunes the
  first `DirectionalLight3D` (angle, colour, energy, soft shadows). `FxEnvironments.sun_settings(id)` returns the numbers.
- Sky colours live in `FxEnvironments.sky_params(id)`; rebuild the .tres files with `--build-env` after edits.

## Materials (`res://assets/shaders/materials/*.tres`)

| Material | Use |
| --- | --- |
| `terrain_meadow`, `terrain_skyway`, `terrain_candy` | Triplanar terrain: grass on flats, rock on slopes (normal.y below ~0.62), path layer from **vertex colour red** |
| `toon_<texture>` (brick, straw_thatch, wood_planks, cobblestone, bark, candy_stripes, frosting, gingerbread, chocolate, bookshelf_wood, parchment, cliff_rock, dirt_path, grass) | Props and blockouts; world-space triplanar, so boxes never stretch. Set `triplanar_scale` (tiles per metre) |
| `toon_mak_cream`, `toon_mak_pink`, `toon_mak_hoof`, `toon_truffle_gold` | Character-style toon with ink outline (next_pass). For textured glTF characters, set `albedo_texture` and keep `triplanar` off |
| `water_stream`, `water_stream_ribbon` | Stylized water; ribbon version flows along UV.x. Needs a flat plane or ribbon with UVs |
| `hot_chocolate_river` (foam at UV.y edges), `hot_chocolate_pool` (round, on a PlaneMesh) | Opaque glossy cocoa; damage is gameplay's job (hazard Area3D) |
| `cloud_platform` | Puffy breathing cloud surface for sphere clusters; animate `dissolve` 0 to 1 for vanishing clouds |
| `foliage_grass`, `foliage_flowers`, `foliage_tree_canopy`, `foliage_beanstalk_leaf` | Wind sway. Optional `pusher` (Vector4 world xyz + radius) bends grass away from Mak |
| `mesh_grass_tuft`, `mesh_flower_*` | Meshes for MultiMesh scatter |

Toon shader parameters worth knowing: `flash` is a per-instance uniform for hit flashes
(`mesh.set_instance_shader_parameter("flash", 1.0)` then tween to 0), plus `rim_strength`, `shadow_tint`, `emission_energy`.

## Toon conversion for imported models (`FxToon`)

`FxToon.apply($Visual)` swaps every StandardMaterial3D surface under a node for the toon shader, keeping albedo
texture/colour, normal map and emission, and adds the ink outline. Cached per source material.
Options: `{"outline": false}` for props and buildings, `outline_width`, `rim`, `shadow_tint`, `spec`.
`FxToon.flash(node, 0.12)` gives a per-instance white hit flash. Preview: `res://scenes/fx/ToonPreview.tscn`
(enemy roster, PBR back row vs toon front row).

## World dressing in one call (`FxDresser`)

`FxDresser.dress(self, {"terrain": $Terrain, "avoid_channels": Vector4(1, 1, 1, 0), "palette": "W1", "butterflies": [...],
"leaves": [...], "post": true})` scatters grass and flowers on every MeshInstance3D under `terrain` (skipping painted
paths, slopes and banks, with a 70 m per-chunk fade), adds ambient effects and the StorybookPost. Preview on the
live W1 scene: `res://scenes/fx/W1DressPreview.tscn`.

## Storybook post-process

`res://scenes/fx/StorybookPost.tscn` (`FxPost`): soft ink lines from depth/normal edges (an overlay that never reads the
screen, so water refraction keeps working) plus a CanvasLayer -10 grade (split-tone, vignette, paper grain).
Knobs: `line_strength`, `vignette`, `paper_amount`, `grade_enabled`.

## Scatter tool

`FxScatter` (`res://scripts/fx/fx_scatter.gd`, a `MultiMeshInstance3D`, `@tool`): set `target_path` (a MeshInstance3D),
`source_mesh`, `material`, `count`, `scatter_seed`; filters: `max_slope_degrees`, `min_height`/`max_height`,
`avoid_vertex_red` (keeps paths bare), `mask_texture` + `mask_rect` (world XZ) + `mask_channel`, clumping. Call `build()`
(or leave `auto_build` on). Deterministic per seed. Example in `vfx_lab.gd::_build_terrain()`.

## Effects (`res://scenes/fx/*.tscn`)

One-shots free themselves when done. Spawn with:

```gdscript
FxEffect.spawn(self, "res://scenes/fx/DustPuff.tscn", global_position)
```

| Scene | Kind | Suggested trigger |
| --- | --- | --- |
| DustPuff | one-shot | landing (`landed` with impact speed), skid start |
| RunDust | continuous; `set_active(bool)` | parent at Mak's feet; active while grounded and running |
| LandingRing | one-shot | hard landing |
| SlamShockwave | one-shot | `ground_pounded(position)` (Ham Slam) |
| JumpTrail | one-shot (0.45 s of trail) | parent to Mak on double/triple jump, long jump |
| Sparkle | continuous | child of each Golden Truffle |
| CollectPop | one-shot | acorn pickup |
| TruffleBurst | one-shot | truffle collected (before the fanfare) |
| PageFlutter | one-shot | Lost Page collected |
| Confetti | one-shot | Woolly Wolf / Gummy defeat, mission complete |
| FeatherBurst | one-shot | Crow Bandit defeat |
| CrumbBurst | one-shot | Gingerbread Grenadier defeat, crate break |
| PeaSplat | one-shot | pea projectile impact, Peapod Popper defeat |
| HitStars | one-shot | any confirmed hit on an enemy or Mak |
| Splash, CocoaSplash | one-shot | Mak or an object hits water / hot chocolate |
| Poof | one-shot | cartoon appear/vanish (enemy flees, Bramwell teleports, crate vanishes) |
| CheckpointGlow | one-shot | checkpoint bookmark touched, respawn |
| Butterflies, FallingLeaves | ambient continuous | place in meadows / under trees (they cover about 12 m) |
| ChimneySmoke | ambient continuous | chimney tops (wind leans +X) |
| WaterfallFoam | ambient continuous | base of waterfalls and the candy waterfall |
| GustSwirl | continuous; `set_active(bool)` | gust zones, bellows blasts, boss huff. Rotate so **-Z** points along the wind; `length`, `radius` |
| GustMotes | continuous | extra streaks and leaves (already inside GustSwirl) |
| ScentTrail | continuous; `set_target(world_pos)`, `clear_target()` | Snout Sniff: child of Mak, target the nearest hidden truffle |

Every FxEffect has `play()`/`emit()`, `stop()`, `set_active(bool)`, `intensity` (size and count) and `tint`. Presets
are data in `fx_presets.gd`; particle colours are sRGB, gold uses over-bright values so it glows a little.

## Page-turn transition

`await PageTurn.run(get_tree(), func(): get_tree().change_scene_to_file(path), 1.0)` snapshots the current frame,
swaps the scene underneath and curls the old page away from the bottom-right corner. Manual control:
`capture()`, `set_progress(p)`, `reveal(seconds)`; `reveal_alpha = 1.0` shows a walnut backdrop instead of the live scene.
Shader: `res://assets/shaders/page_turn.gdshader`.

## Textures

`res://assets/textures/*.webp`: 14 seamless 1024 px stylized textures (fal.ai nano-banana-2, receipts and prompts in
`assets/textures/_src/`, seam fix in `make_seamless.py`, 2x2 checks in `_src/tilecheck/`). Particle sprites in
`assets/textures/fx/` are procedural (`_src/make_fx_textures.py`).

## RetroLook (retro track, D032 + D034)

- `retro_look.gd` (autoload `RetroLook`): runtime retro texture style plus the visual-hierarchy pass. Full description in
  its header. Toggle with the Game setting `classic_textures` or `--retro=0/1`; `--retro-pop=0`, `--retro-vertex=1`.
- Fix round 1 (2026-10-18): cloud.gdshader is no longer converted; world shaders of other tracks (W1/W3 terrain, W3
  frosting/liquid/swirl, W2 cloud decks, hub rugs) get a generated retro variant (`WORLD_SHADERS`) without edits to their
  files; every environment surface runs through `retro_calm()` (saturation budget 0.45 tops / 0.35 walls, per-world value);
  state lives in each material's `retro_state` metadata (no leaks across scenes); textures for mid-game spawns are reduced
  on a worker thread and swapped in later; rims are blended and gated to the shadow side (`retro_pop.gdshader`), truffles
  get `retro_glint.gdshader`; blob shadows go under moving actors and pickups only and switch off their sun shadow.
- Evidence: `--retro-shots=<abs dir>` (frozen pairs, gameplay camera first, HUD hidden, 1920x1080), then
  `python tools/retro_textures.py --analyze <dir>` (sat ratio, luminance gap, env/gameplay saturation, D034 gate).
- `blob_shadow.gd` / `scenes/fx/BlobShadow.tscn`: `BlobShadow.attach(node)`.
- Offline tiles: `python tools/retro_textures.py` authors the 64 px `game/assets/textures/*_retro.png` originals
  (`--downscale` restores the old palette-reduced downscales).

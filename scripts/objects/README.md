# Interactive objects (objects workstream)

Reusable scenes in `res://scenes/objects/`. Drop them into a world scene, set the exports, done.
Every object builds a smooth-primitive placeholder in the area palettes at runtime. To use a generated mesh,
set `visual_scene` (a glTF/PackedScene; it is instanced under `Visual` and turned 180° so +Z glTF faces -Z)
and `visual_scale`, or put your own children under the `Visual` node (then the placeholder is skipped).
The Truffle uses the meshes workstream's `golden_truffle.glb` by default (`use_default_mesh`).

All autoload calls are duck-typed through `ObjSvc` (`obj_svc.gd`), so a missing Game/UI/Audio/Router method never
crashes an object. Effects from the vfx workstream (`res://scenes/fx/*.tscn`, `assets/shaders/materials/*.tres`) are
used when present, with built-in fallbacks.

## Scenes and key exports

| Scene | Root | Key exports | Contract / notes |
| --- | --- | --- | --- |
| Truffle | Area3D | `truffle_id`, `hover_height`, `bob_*`, `spin_speed`, `use_default_mesh` | `Game.collect_truffle(id)`; owned ids show as a blue ghost; groups `truffle`, `sniff_target` |
| Acorn | Area3D | `value`, `magnet_radius`, `heal_amount` (extra; Game.add_acorns already heals) | `Game.add_acorns`; `pop_out(velocity)` for crates |
| AcornGroup | Node3D | `shape` LINE/RING/ARC, `count`, `length`, `radius`, `arc_degrees`, `arc_height` | spawns Acorns at ready |
| AcornHundred | Node3D | `required` (100), `reward_truffle_id`, child `TruffleMarker` | counts `Game.acorns` this visit |
| LostPage | Area3D | `world_id` (defaults to Game.current_world), `page_index` 0–4 | `Game.collect_page(world, i)` |
| LostPageSet | Node3D | `world_id`, `required` (5), `reward_truffle_id`, `TruffleMarker` | truffle when all pages found |
| Checkpoint | Area3D | `world_id`, `respawn_offset` (local, default 1.2 m in front along -Z) | `Game.set_checkpoint(world, xform)`; only the latest stays lit |
| StorybookPortal | StaticBody3D | `world_id`, `book_title`, `required_truffles`, `cover_color`, `route_on_enter` | open if `Game.is_book_open(id)` / `is_unlocked("book_"+id)` / count; jump into the pages (zone 3.3 m up) → `UI.show_mission_select(id)` else `Router.enter_world(id)` |
| WolfDoor | Node3D | `required_truffles` (12), `target_world` (BOSS), `unlock_flag`, `route_on_enter` | swings open near the player when unlocked; walking through → `Router.enter_world` |
| MovingPlatform | Node3D | `size`, `theme`, `mode` LOOP/PING_PONG, `speed`, `pause_at_ends`, `travel` or child `Path` (Path3D) | moving part `Body` is AnimatableBody3D (sync_to_physics) |
| RotatingPlatform | Node3D | `axis` VERTICAL_PLANE (windmill) / HORIZONTAL, `arm_count`, `radius`, `degrees_per_second`, `keep_level`, `show_sails` | platforms are AnimatableBody3D |
| FallingPlatform | AnimatableBody3D | `size`, `theme`, `wobble_time`, `fall_distance`, `respawn_time` | |
| VanishingCloud | AnimatableBody3D | `size`, `vanish_delay` (1 s), `respawn_time`, `drift_amplitude` | uses `cloud_platform` shader dissolve when available |
| BouncePad | StaticBody3D | `look` LEAF/GUMDROP/DRUM, `bounce_velocity`, `radius` | group `bouncy` + meta `bounce_velocity`; the player launches itself |
| WindZone | Area3D | `size`, `direction` (local), `strength`, `mode` STEADY/PULSING, `pulse_period`, `enabled`, `end_falloff` | group `wind_zone`, `get_wind(pos)`, `set_enabled(bool)`, `drive` (0–1, set by bellows); streaks + GustSwirl |
| BellowsMachine | StaticBody3D | `wind_zone_path`, `group_id`, `pump_period`, `start_broken` | pumps the zone; Ham Slam breaks it (`broken`) |
| BellowsSet | Node3D | `group_id`, `reward_truffle_id`, `TruffleMarker` | truffle when every bellows of the group is broken |
| HazardVolume | Area3D | `size`, `damage`, `knockback_up`, `look` PLAIN/HOT_CHOCOLATE/THORNS, `chocolate_material` | group `hazard`, metas `damage`, `knockback_up` |
| KillZone | Area3D | `size`, `fallback_respawn` | `Game.player_fell_out()` |
| Climbable | Area3D | `look` VINE/POLE/ROPE, `height`, `pole_radius`, `grab_radius` | group `climbable`, `get_climb_axis()`, `get_pole_radius()`, `get_climb_bottom/top()`; origin at the bottom |
| SignPost | StaticBody3D | `board_text`, `speaker`, `lines`, `talk_radius`, `auto_talk` | `UI.show_dialog(speaker, lines)` on `interact` |
| NPCTalker | StaticBody3D | same as SignPost + `turn_speed` | turns its `Visual` to face the player; placeholder is Bramwell the tortoise butler |
| TrialRing | Area3D | `radius`, `color`, `active` | `passed` signal |
| TimeTrial | Node3D | `time_limit`, `ordered`, `trial_label`, `trial_key`, `reward_truffle_id`; children `StartGate`, `Rings/*`, `FinishGate`, `TruffleMarker` | `UI.timer_start/stop/hide`, `Game.record_time`; resets on timeout or missed rings |
| BreakableCrate | StaticBody3D | `size`, `acorns`, `reward_truffle_id`, `break_kinds` | `hit_by_player(kind, from)`; punch/kick/dive/slide/slam |
| SlamSwitch | StaticBody3D | `button_color`, `pressed_color`, `reset_after` (0 = stays down) | Ham Slam only; `pressed`/`released` |
| Cage | Node3D | `switches` (NodePaths), `required` (0 = all), `reward_truffle_id`; children `Contents`, `TruffleMarker` | lifts away, enables `Contents` (calls `on_released()` on them) |
| SniffTarget | Node3D | `reveal_radius`, `active` | group `sniff_target`; `on_sniffed(by)`; also reveals when a player in state `sniff` is within `reveal_radius` |
| BuriedTreasure | Node3D | `truffle_id`, `require_sniff`, `patch_radius` | sniff, then Ham Slam → truffle |

Ham Slam detection (`SlamSensor`): a player overlapping the sensor while `is_ground_pounding()`, the player's
`ground_pounded(position)` signal inside the footprint, or `hit_by_player("slam", …)` on the object or its sensor.

Spawned truffles appear at the spawner's `TruffleMarker` with a rise-and-pop reveal.
Place objects in the scene before they enter the tree (as a .tscn does). Moving bodies with `sync_to_physics` ignore
a `global_position` set after `add_child`.

## Labs and tests

- `res://scenes/objects/ObjectsLab.tscn`: every object, lighting, `StoryCam_A`–`D` plus close-up cams
  (`StoryCam_E_row_a_right`, `StoryCam_F_books`, `StoryCam_G_bellows_hazards`, `StoryCam_H_truffles_close`).
  Uses the real Player.tscn when it exists. `-- --profile=objects_lab --demo` runs a scripted Movie Maker demo with the
  local stub player.
- `res://scenes/objects/ObjectsTest.tscn`: 56 scripted checks with `ObjPlayerStub` (`test/player_stub.gd`).
- `res://scenes/objects/ObjectsPlayerTest.tscn`: 17 checks with the real `Player.tscn` driven through input actions.

```
python tools/godot.py run res://scenes/objects/ObjectsTest.tscn --headless --seconds 120 -- --profile=objects --results=<abs>.json
python tools/godot.py run res://scenes/objects/ObjectsPlayerTest.tscn --headless --seconds 120 -- --profile=objects --results=<abs>.json
python game/scripts/objects/tools/capture_lab.py StoryCam_A:"caption"      (captures into Docs/progress/objects)
python game/scripts/objects/tools/gen_scenes.py   /   gen_lab.py            (regenerate object scenes / the lab)
```

## Night 01 M3: real models, feedback and verification

- **Real models by default:** Truffle `golden_truffle_v2.glb` (fallback v1), Acorn `acorn_v2.glb`, Checkpoint `bookmark_checkpoint.glb`,
  BreakableCrate `breakable_crate.glb` + `breakable_crate_pieces.glb` (debris), LostPage `lost_page.glb`, NPCTalker Bramwell; bounce pads use
  the W3 gumdrops; `ObjSvc.RIGGED_UPGRADES` swaps `pip.glb` for the rigged `pip_v2.glb`. World builders pass other GLBs through `visual_scene`.
- **Feedback bus:** every object event goes through `ObjSvc.feedback(event, at, params, sfx_key)` -> `Juice.event` (Docs/JUICE.md). The
  object's own particles and sound play only when Juice does not handle that channel (`ObjSvc.juice_handles`). Events not yet in the Juice
  catalogue use `ObjSvc.feedback_optional` (no unknown-event warning; plays the object sound instead). Currently: `object_crate_land`.
- **NPC life:** `NpcLife` (`npc_life.gd`) is attached by NPCTalker to every generated character: breathing, blinks, head turns toward Mak,
  ear flicks, arms lowered out of the A-pose, talking gestures, greeting wave; per-model profiles (graze, snore, bird) in `PROFILES`.
- **Truffle:** a spawned truffle (dig, cage, pages, 100 acorns) is not collectable for `reveal_grace` (0.85 s) so its rise is seen even when
  Mak stands on the spot; it is collected at the end of the grace if Mak is still inside.
- **SniffTarget / BuriedTreasure:** the player's sniff calls `on_sniffed(self)` and skips targets whose `is_sniff_active()` is false.
  `proximity_fallback` (default on) keeps the old "sniffing player within reveal_radius" reveal; `reveal_path` records which path fired.
  ObjectsPlayerTest turns the fallback off and proves the real path (`player_sniff_targets_patch`, `player_sniff_reveals_patch`,
  `player_sniff_ignores_dug_patch`).
- **BellowsMachine with a generated model:** the whole cart breathes with the pump (swell on intake, squash and kick on the blast). On the
  Ham Slam it squashes, then swaps to `busted_scene` (auto: `<visual>_busted.glb`, shipped for bellows_machine_v2/_v3) with a springy settle,
  or sags and tilts when no busted model exists (v1), and keeps wheezing grey puffs.
- **WolfDoor with the hub GLB:** `door_leaf` swings on its own pivot; frame triangles that belonged to the leaf (studs and strap ends left in
  `door_frame` by the split) are moved onto the leaf at load (`_adopt_leaf_studs`, prints the count; 692 of 2671 for wolf_door.glb).

### Verification scenes and tools

- `res://scenes/objects/ObjectsShowcase.tscn` (`showcase.gd`): every object with its real model under a world environment, plus a Mak
  stand-in (real `mak_v2.glb` with NpcLife) walking scripted paths. Stations: pickups, checkpoint, crate, npcs, door, portal, cage, wind, dig.
  `python game/scripts/objects/tools/record_showcase.py <station> <Cam_Name> --seconds 9 --size 1280x720 --tag <t>` records a Movie Maker
  clip into `Recordings/night01/M3/` and a frame sheet into `Docs/progress/objects/`.
- `res://scenes/objects/ObjectsWorldProbe.tscn` (`world_probe.gd`): loads a real world and frames one named node, optionally calling a method:
  `python tools/godot.py capture res://scenes/objects/ObjectsWorldProbe.tscn <out.png> --wait 150 -- --profile=objects_probe
  --world=res://scenes/hub/Hub.tscn --focus=Wolf_Door --off=2.5,2.4,7 --aim=0,1.8,0 --call=open --call_at=60`
- `tools/dump_door.gd` (`python tools/godot.py script res://scripts/objects/tools/dump_door.gd`): wolf_door.glb hierarchy and bounds.

## Night 01 fix stage, round 1 critiques (2026-10-18)

- **Talker (signs and NPCs):** parchment speech bubble with an ink outline and ellipsis (drawn over the scene); the button glyph
  comes from the HUD prompt (`UI.show_prompt("interact", prompt_verb)`), never a hard-coded key. A closing press never reopens the
  dialog (waits for `UI.dialog_finished`, then a released `interact`; ignores input while `UI.is_input_blocked()`). Overlapping zones:
  only the nearest talker answers. Walking away (talk_radius + 1.5 m) closes the dialog with the UI's close animation.
  NPCTalker anchors the bubble over the head bone, at least 0.3 m above the model's top; greets at `greet_radius` (3.6 m).
- **NpcLife:** pose profiles (`arm_fwd`, `fore_down`, `fore_fwd`, `head_tilt`); Pip wrings his hands (no T-pose; no GLB carries
  exported clips). `greet: "bow"` for Bramwell (unrigged elders); the wave uses the arm farther from Mak and is skipped closer
  than 0.9 m. `set_caged(true)` grips the bars, rattles them when Mak is within 4 m, pleading head tilt; `release()` waves.
  Cage calls both for characters in `Contents`. `ObjSvc.RIGGED_UPGRADES` now points Pip at `pip_v3.glb` (AO bake).
- **WolfDoor:** a builder's `Chains` child (or nodes in group `wolf_door_lock`) shiver, drop and shrink away on unlock/open.
  The frame/leaf split now moves only small loose parts whose centre ray along the door normal hits the leaf first
  (`split_report`): 4 hinge-strap parts, 692 triangles, the frame keeps everything else.
- **LostPage / LostPageSet:** pages saved on earlier visits show as ghosts (no count, no popup); the set seeds `found` from
  `Game.has_page` and pays out an earned but uncollected reward.
- **Pickups:** Acorn and LostPage lift themselves out of world collision after one physics frame (`ObjSvc.unbury`, 0.1 m steps,
  max 1.5 m) and print the node path so builders can move them.
- **TimeTrial / TrialRing:** the timer hides 2.5 s after success (also during the truffle pause), on `_exit_tree`, and a
  `Game.player_respawned` mid-trial fails the trial. Rings: thick gold hoop, emissive core, amber ink rim; reset kills the pass tween.
- **BellowsMachine:** after the bust every box collision shrinks to the wreck's measured top (or `busted_collision_height`);
  darker wheezes every ~1.2 s with a creak and a shudder.
- **Checkpoint:** `get_respawn_transform()` validates and caches the respawn (flat floor within 0.6 m, not an edge, capsule room),
  else 8 directions at 1.2/0.8/0.5 m, then the base (`respawn_fallback_used`). Unlit: wider base, soft gold trim glow.
- **WindZone:** `disable_mode = KEEP_ACTIVE`, so a culling pass that process-disables it no longer removes it from physics.
- **VanishingCloud:** lavender underside, warm-gold rim, a soft base ring; a tell of at least `min_tell` (0.6 s): tremble,
  thinning, sag, shedding wisps.
- **Real models by default:** SignPost uses `w1/signpost/signpost.glb` with the board text on both faces of the upper board;
  SlamSwitch is a squishy custard-cream biscuit (`w3/biscuit_platform.glb`) with a jam-drop target; RotatingPlatform wooden steps
  are the W1 hay bale; Climbable VINE stacks the W2 beanstalk segment at the pole radius.
- **StorybookPortal:** printed pages rendered once in a SubViewport (title in Cherry Swash, illuminated capital, ink lines,
  vignette), emission far below bloom, fainter glow card.
- **BuriedTreasure:** soft mud decals, a lumpy rim, pebbles and a stick X; wiggles and puffs when sniffed; leaves a crater.
- **BreakableCrate:** 30 % less debris impulse; pieces shrink away from 1.2 s to 1.8 s.
- Showcase: `--demo=tour` plays door, sky, cage_close, wind, dig, portal and sign stations back to back in one clip
  (`python game/scripts/objects/tools/record_showcase.py tour Cam_Door_Oblique --seconds 63.5 --size 1280x720 --sheet-every 1.0`).

## Night 01 M3b (resume after the owner's pause, 2026-10-18 evening Bangkok)

- **Current asset files:** Acorn loads `acorn_v3.glb` (swap H6); the showcase bellows is `bellows_machine_v5` (swap #6, busted twin
  automatic); the showcase Mak stand-in wears whatever hero model `Player.tscn` uses (`showcase.gd::player_mesh_path()`), so the
  hero track's new Mak appears without edits here.
- **Character upgrades:** `ObjSvc.RIGGED_UPGRADES` maps every superseded character file to its current one (jack, hazel, bertram,
  foreman, foreman_underwear -> `_v2` AO bakes; sergeant_snap / _v2 -> `_v3`; real_sheep -> `_v2` at its corrected 1.21 scale;
  daisy_cow -> `_v2` (2.2 m, jaw bone); sleeping_giant -> `_v2`; wolf_scarecrow -> `_v2`). NPCTalker applies it to `visual_scene`.
  Builders who instance characters themselves should load the current files directly (see Docs/ASSETS_TOPUP.md).
- **NpcLife profiles follow re-deliveries:** `NpcLife.profile_for(key)` falls back from `name_vN` to `name`, so `sleeping_giant_v2`
  keeps snoring (it no longer turns to watch Mak), `daisy_cow_v2` grazes, `wolf_scarecrow_v2` stays still. Snap v1 lowers its arms
  12 degrees (55 pushed them into the belly), v2/v3 55. Profile key `jaw` sets the opening angle and direction: the cow opens at -10
  (its lip line stretches past -15) and chews while grazing.
- **WindZone calm pockets and wind shadow:** `calm_boxes` (local AABBs, no wind inside) and opt-in `shelter_mask` /
  `shelter_factor` (a point whose upwind line to the zone's entry face hits a body on those layers gets `shelter_factor` of the
  wind; bodies in group `no_wind_shelter` never shelter). Both also apply to `get_peak_wind`, so checkpoints treat a sheltered
  spot as calm. Example for a gust lane that clips a house: `shelter_mask = 1` (world) on the zone.
- **Truffle reads as a truffle:** the skin shader pulls the model's round lobes toward a lumpy ellipsoid shell in the vertex stage
  (`lobe_soften`, default 0.6; the sprout is untouched; `-- --truffle-soften=0` for A/B) with finer warts (`wart_scale` 56,
  `wart_bump` 0.95) and a warmer self-glow (`gold_glow` 0.38, it read olive in shade). Owned truffles keep the same shape as a glass
  ghost (a `#define GHOST` variant of the skin shader instead of a plain override).
- **Talk bubble pop-in:** the bubble used to set a unit global basis, cancelling the parent's 0.01 -> 1.12 pop-in scale, so the next
  frame scaled it by the tween ratio (a 2-frame screen-filling bubble at every prompt). It now sets a local rotation only.
- **NpcLife blinks with real lids** on rigs that have `eyelid_l/r` bones (the new hero kit: +X 115 degrees = closed); lid-less models
  keep the head squint.
- **Cage** defaults to the generated `w2/goose_cage.glb` (scaled to `height`) when a builder passes no visual (D024).
- **Showcase:** a pre-owned ghost truffle (`Cam_Ghost_Close`), Jack in the cage is `jack_v2`, `-- --mak=<glb>` previews another hero
  file; `record_showcase.py --extra="--mak=..."` passes extra game args. `ObjectsWorldProbe` waits up to 180 frames for a late focus.

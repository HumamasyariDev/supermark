# Enemies and boss: scene contract (night 01)

Owner: enemies workstream. Scripts in `res://scripts/enemies/` and `res://scripts/boss/`.

## Scenes

| Scene | Script | Notes |
| --- | --- | --- |
| `WoollyWolf.tscn` | `woolly_wolf.gd` (`WoollyWolf`) | W1. Sheep disguise, charge, skid |
| `CrowBandit.tscn` | `crow_bandit.gd` (`CrowBandit`) | W1, W2, W3, boss minions. Place the node AT the perch point (it flies). `aggressive = true` skips perching |
| `PeapodPopper.tscn` | `peapod_popper.gd` (`PeapodPopper`) | W2. Planted; lobs `PeaProjectile` volleys |
| `BumbleBruiser.tscn` | `bumble_bruiser.gd` (`BumbleBruiser`) | W2. Place on the ground; it hovers `hover_height` above. Put walls behind its line for the dizzy gag |
| `GingerbreadGrenadier.tscn` | `gingerbread_grenadier.gd` (`GingerbreadGrenadier`) | W3. Squads: give each member the same `patrol_points`, set `formation_index` and assign `squad` (Array of the members) |
| `GummyBrute.tscn` | `gummy_brute.gd` (`GummyBrute`) | W3. 2 hits; slam shockwave `GummyShockwave` |
| `GingerbreadSquad.tscn` | `gingerbread_squad.gd` (`GingerbreadSquad`) | Spawns `size` grenadiers on a shared patrol; `with_sergeant` adds Sergeant Snap (1.3x, 2 hits) |
| `EnemyGroup.tscn` | `enemy_group.gd` (`EnemyGroup`) | Mission helper: put enemies (or squads) under it; emits `cleared`, and with `truffle_id` spawns that Truffle at child Marker3D `TruffleSpot` (W1-1, W2-6, W3-2) |
| `EnemyLab.tscn` | `enemy_lab.gd` + `enemy_lab_test.gd` | Test pens, StoryCams, scripted test; `--lineup`, `--grouptest`, `--realstomp` |
| `MeshProbe.tscn` | `mesh_probe.gd` | Dev: prints the bones of every enemy GLB |
| `../boss/WolfBoss.tscn` | `wolf_boss.gd` (`WolfBoss`) | Must be a child of the arena root (it reads chimneys, vents, checkpoint from its parent) |
| `../boss/WolfRooftop.tscn` | `wolf_rooftop.gd` (`WolfRooftop extends WorldRoot`) | Boss arena graybox; spawns the boss |

Exports shared by every enemy (`EnemyBase`): `patrol_points` (offsets from the spawn point), `notice_radius`,
`lose_radius`, `move_speed`, `acorns_on_defeat`, `ai_enabled`, `mesh_path` (override for the GLB).

## Interfaces (TECH_CONTRACT.md)

- Body: `CharacterBody3D`, layer 3 (enemy), mask 1 (world). Group `"enemy"`.
- `Hurtbox` (`EnemyHurtbox`, Area3D) on layer 7. The player may call `hit_by_player(kind, from_position) -> bool`
  on the hurtbox area or on the enemy root; kinds `punch kick jump_kick dive slide stomp slam`.
  Returns true when the hit landed (or when a stomp/slam should bounce the player, e.g. the Gummy Brute trampoline).
  Blocked hits (Grenadier lance from the front, Gummy punches outside the winded window) return false and push the player back with `add_impulse`.
- `HeadZone` (Area3D, mask 2) does stomp detection itself: a falling player above the head gets
  `hit_by_player("stomp" | "slam")` and then `player.bounce(stomp_bounce)`. If the player also reports the stomp,
  the second call within 0.45 s returns true without double damage.
- Contact damage: `player.take_damage(1, enemy_position)` only in the telegraphed attack states (no damage from idle grazing etc.).
- Defeat drops acorns through `res://scenes/objects/Acorn.tscn` (`pop_out(velocity)`), with a local stand-in if absent.
- Crow Bandit hits call `Game.spend_acorns(n)` (up to 3) and return them (+1) when defeated.
- Boss: `Game.set_checkpoint("BOSS", Spawns/Default)` and `Game.set_meta("wolf_boss_phase", n)` at each phase start, so a reload resumes the phase;
  defeat calls `Game.unlock("top_hat")`, spawns `Truffle.tscn` with `truffle_id = "BOSS-1"` and drops his top hat prop.
  Dev args: `--boss-phase=1..3`, `--bosstest`.

SFX keys (Audio.play_sfx): `enemy_notice enemy_hit enemy_block enemy_bonk enemy_skid enemy_defeat_poof acorn_pickup
wolf_cub_baa wolf_cub_yelp wolf_growl wolf_charge costume_rip crow_caw crow_dive crow_steal pea_pop pea_inhale pea_splat
bee_buzz bee_charge bee_down gingerbread_march gingerbread_halt gingerbread_crumble lance_ready lance_thrust
gummy_wobble gummy_jump gummy_slam gummy_boing gummy_melt chimney_smash boss_crash wolf_gust wolf_pant great_truffle_appear`.
Voice keys (Audio.play_voice): `wolf_huff wolf_laugh wolf_curses wolf_little_pig`.

## Meshes: how a generated model plugs in (for the meshes workstream)

Drop the model at `res://assets/enemies/<id>/<id>.glb` with ids
`woolly_wolf`, `crow_bandit`, `peapod_popper`, `bumble_bruiser`, `gingerbread_grenadier`, `gummy_brute`, and `wolf_boss`.
On `_ready` the enemy instances it under `Visual/Rig/Mesh` (rotated 180 degrees about Y, because glTF models face +Z
and the body faces -Z) and hides the procedural `Placeholder`.

- Scale: real size, origin at the feet / base centre. Heights: wolf cub 1.1 m, crow 0.75 m (body only; it flies),
  peapod 1.0 m including the soil mound, bee 0.9 m, grenadier 1.3 m with hat, gummy 1.6 m, wolf boss 3.2 m without the hat (3.9 m with it).
- Procedural animation drives `Rig` (bob, squash and stretch, lean, tilt, spin) for every model, rigged or not.
- Optional named parts are rotated around their own origin when present. Name nodes (or Skeleton3D bones)
  exactly: `body`, `head`, `arm_l`, `arm_r`, `leg_l`, `leg_r`, `wing_l`, `wing_r`, `tail`.
  Node names may also be `head_geo...` or `head.001`; bone names may carry a prefix (`DEF-head`, `Armature_head`, `mixamorig:head`).
  Put each part's pivot at its joint (shoulder, hip, neck, tail root), because the code rotates parts in place.
- Which parts each family uses: wolf cub body/head/arm/leg/tail; crow body/head/wing/leg/tail; peapod body/head/arm (leaves)/tail (tendril);
  bee body/head/arm/leg/wing; grenadier body/head/arm/leg (lance rides in arm_r); gummy body/head/arm/leg; wolf boss body/head/arm/leg/tail
  plus `chest` (scaled for the inhale) and `hat` (detached at defeat). Missing parts are simply skipped.
- Bone aliases: `leg_*` also matches `thigh_*`, `arm_*` matches `upperarm_*`, `body` matches `spine`, and `wing_*` falls back to `arm_*`
  (the crow rig's wings are its arms). Offsets are applied in skeleton space around each joint, mirrored for the 180-degree mesh turn.
- Woolly Wolf swaps `woolly_wolf.glb` (sheep disguise) for `res://assets/enemies/woolly_wolf_cub/woolly_wolf_cub.glb` when it rips the costume off;
  without the cub mesh it falls back to the procedural cub in red shorts.
- Wolf boss uses `res://assets/characters/wolf_boss/wolf_boss.glb` (rigged, see ATTACH.md): blend shapes `chest_inflate` (inhale, balloon defeat)
  and `cheeks_puff` (huff), the top hat on a BoneAttachment3D at `head` (exports `hat_lift`, `hat_scale`), the cane at `cane_socket_r`.
- Skeletal animation clips are not required. If an AnimationPlayer is present it is left alone; do not autoplay a clip that fights the rig.

## Tests

    python tools/godot.py run res://scenes/enemies/EnemyLab.tscn --seconds 160 -- --labtest --quit-when-done --profile=enemies
    python tools/godot.py run res://scenes/boss/WolfRooftop.tscn --seconds 160 -- --bosstest --quit-when-done --profile=enemies

Optional: `--only=woolly_wolf,crow_bandit`, `--shots=<abs dir>`, `--labtest-out=<abs json>`, `--bosstest-out=<abs json>`.
Both tests use `EnemyLabPlayer` (`res://scripts/enemies/lab_player_stub.gd`), a contract-compatible stand-in, because
`res://scenes/player/Player.tscn` did not exist yet. `--real-player` makes the lab spawn the real player for manual play.
Keyboard on the stub: WASD or arrows, Space jump, J punch, K Ham Slam in the air.

## Night 01 polish pass (enemies v2, 2026-10-18)

- **Real models everywhere:** every family instances its Tripo P2 GLB; the procedural placeholder stays hidden (the wolf's
  placeholder costume balls are freed when the mesh is present). New rigged files made by this track with Blender 5.1
  (`res://assets/enemies/_rig_v2_src/rig_v2.py`, analytic weights, no paid calls):
  `bumble_bruiser/bumble_bruiser_v2.glb` (spine, head, arm_l/r, leg_l/r, wing_l/r, stinger) and
  `peapod_popper/peapod_popper_v2.glb` (pod_l/pod_r clamshell hinges, head = face pea, pea_mid/low/tiny, arm_l/r, leg_l/r, stem).
  Families pick the `_v2` file automatically when it exists. Grenadiers carry `characters/sergeant_snap/snap_lance.glb` on a
  `BoneAttachment3D` (hand_r); Sergeant Snap uses `sergeant_snap.glb` at 1.125 scale (1.8 m).
- **Look:** `FxToon` (toon ramp, rim, ink outline) is applied to every enemy mesh like Mak's, chosen from the side-by-side
  `Docs/progress/enemies_v2/*__fxtoon_side_by_side_*`; `--pbr` keeps the raw PBR. Bee wings and the gummy's jelly are
  translucent overrides (FxToon skips transparent surfaces). Flyers get a soft blob shadow.
- **Motion (every family):** idle personality loops, notice take (hop + stretch + "!"), wind-up anticipation, attack, recover,
  hurt flinch, turn banking, breathing, bone-driven defeat gags (wolf underpants spin, crow feather tumble, pod bursts open
  and peas bounce away, bee spirals down and wiggles on its back, grenadier wobbles then crumbles and drops its lance,
  gummy melts into a jelly puddle). Extra bones now addressable through `pose()`: jaw, beak, ear_l/r, tail_2, forearm_l/r,
  hand_l/r, shin_l/r, hips, spine_2, stinger, pod_l/r, stem.
- **Juice:** every enemy moment emits the Docs/JUICE.md event (`enemy_notice`, `enemy_windup`, `enemy_attack` with
  `direction`, `enemy_hurt`, `enemy_block`, `enemy_stunned`/`enemy_recover`, `enemy_slam`, `enemy_defeat`, `enemy_flee`,
  `enemy_projectile_fire/_hit`, `object_bounce_pad` for the gummy trampoline) with `family` and `node`. When Juice has
  data for an event the enemy skips its own fallback sound/effect/hitstop for that moment (`EnemyBase.owns()`), so nothing
  doubles; family extras (baa, caws, flaps, footfalls, bee buzz loop, costume rip) stay in the enemy code.
- **Audio:** `EnemyKit.sfx` resolves `SFX_ALIASES` (dedicated key first, then a pitched stand-in from the bank), so every
  enemy event is audible today and upgrades automatically when the audio track adds the dedicated take. The bee's buzz is
  a looping `AudioStreamPlayer3D` whose pitch follows the state (it no longer spams the loop through the SFX pool).
- **Review tools:** `EnemyLab.tscn -- --poses=<family> [--pose-yaw=90] [--pose-states=a,b]` (one copy per state, AI off),
  `--lineup --lineup-close`; `EnemyWorldCheck.tscn -- --world=<res://...> --family=<id> [--place] [--sergeant]` frames
  one enemy in a real world, provokes it with the real player and forces a defeat (use with `godot.py capture/movie`).

## Night 01 polish pass, round 3 (2026-10-18 06:00-07:45 Bangkok)

- **Telegraph overlay:** `EnemyBase.flash(color, length, peak, rim_only)` now drives a small overlay shader. Hits stay a full
  white pop (plus `FxToon.flash`); the wind-up uses `rim_only = true`, an orange fresnel rim that pulses twice, so the face stays
  readable (the old flat tint turned the whole peapod yellow, `Docs/progress/enemies_v2/*__before_after_peapod_windup_*`).
- **Notice "!":** when the Juice table draws `notice_pop` for `enemy_notice`, the enemy no longer adds its own "!" (two
  stacked marks read as a glitch); custom lines ("Oi!", "GRR!") still show as a smaller popup.
- **Crow flight pose:** legs trail back in flight and the notice is a startled wing flare; talons come forward only in the
  snatching dive.
- **Sergeant Snap:** scale is measured from the mesh to reach 1.8 m (the 06:05 r1c re-delivery is already 1.80 m, so the
  fixed 1.125 factor would have made him 2.0 m), and he wears `snap_drum.glb` on the left hip (BoneAttachment3D `DrumSocket`).

## Fix round 1 after critique r1 (2026-10-18 07:40-11:45 Bangkok)

- **Builder values survive.** Every family sets its plain defaults in `_init()` (runs at `instantiate()`), so
  `node.set("notice_radius", ...)` and friends between `instantiate()` and `add_child()` now stick. `_setup()` in
  `_ready()` keeps only flag- and rng-dependent setup (sergeant, v2 mesh choice, timers) and never resets tunables.
- **Pose channels.** `pose(part, euler)` is the eased base pose (14/s). New: `pose_cycle(part, euler, raw := false)`
  adds a per-frame cyclic offset after easing (walk swings, flaps, wags keep their full amplitude; 60/s smoother, `raw`
  for bee wings) and `pose_snap(part, euler, rate := 45.0)` for 2-frame accents (thrusts, takes, spits). Squash and
  stretch preserve volume. The hurt flinch follows the real hit direction. `walk_cycle` adds turn rate so in-place turns
  shuffle the feet. `head_pitch_to_player()` aims notice and wind-up heads at Mak.
- **Stomps.** `stomp_min_y()` = origin + 0.6 x head_height; `hit_by_player("stomp"|"slam", from)` returns false when
  Mak's feet are below it, when he is more than body_radius + 0.45 off centre, when he is in `hurt_air`/`hurt`, or
  within 0.7 s of this enemy's own contact hit (exactly one side wins each exchange). HeadZone radius is
  body_radius + 0.05. A lethal stomp plays a shared pancake beat (flat in 2 frames, 0.12 s hold, stretch, 0.26 s) before
  the family gag. Defeat poofs rise from the ground at no more than body height after the gag's hold.
- **Contact.** Damage only in `attack` and the last 0.25 s of `windup` (`windup_hot()`, per-family `windup_len`), plus the
  gummy's landing; elsewhere bodies are solid and push apart. Reach is body_radius + 0.38. Frontal punches on a charging
  wolf or bee now `block` with "Too fast!".
- **Ground.** Gravity enemies hold still until a ray finds the floor and snap onto it; planted enemies (`planted`, peapod)
  then switch gravity off. `_ledge_guard()` stops any walk, lunge or knockback at a drop of more than 1.5 m; the wolf
  teeters at the lip, the gummy picks a landing on its own level (`_safe_landing`). Below home - 12 m an enemy returns
  home with a poof (defeated without drops after 3 returns).
- **Attack tokens.** `EnemyKit.request_attack(enemy, "melee"|"volley")`: at most 2 melee wind-ups and 2 volleys within
  14 m of Mak; refused enemies hold a ready pose and retry after 0.3-0.6 s. Tokens are released on any state other than
  windup/attack. Grenadier squads alert in a 0.25 s ripple, take line-abreast slots (-1.4/0/+1.4 m, separation 1.6 m),
  lunge in formation order, abort into squadmates or ledges, and only the leader shouts the lines.
- **Sizes.** Grunt grenadiers are measured to 1.3 m, Snap to 1.8 m (socket props excluded); hit boxes follow
  (`_resize_collision()`). `mesh_path == sergeant_snap.glb` implies `sergeant`. The enemy owns `Visual.scale`: an outside
  rescale is undone with a warning (W3 still sets 1.125).
- **Variants.** Grenadier `variant = "lobber"` (no lance, no block, gobstopper every 2.5 s on a 1.0 s arc with a red ring);
  gummy `variant = "stalker"` (hops at Mak every 5 s without line of sight, 6.5 m arcs over hedges, 3 HP, melts and reforms
  at home 10 s later). Until W3 passes `variant`, ids `grenadier_tierA_*` and `brute_clearing` select them.
  Sergeant Snap: lance sweep (1.0 s disc, a 0.6 s spin at 0.6-1.4 m; dive or belly-slide into his boots to trip him for
  2.5 s), cooldown 5 s.
- **Look.** Per-family outline widths (wolf, crow 1.0; grenadier 2.0 in dark chocolate; others 1.3), telegraph rim power
  (crow, peapod 4.0), cooler wolf fleece (interim tint until the texture repaint), deep-green peapod shell with lime peas,
  raspberry gummy with an opaque core and an ink outline pass, real teacups for the boss and its tornado, FxToon on the boss.

## Implementation stage, night 02 (impl3, 2026-10-18 20:50 Bangkok onward)

- **Review tool:** `EnemyReview.tscn` (`enemy_review.gd`) runs many shots in one Godot run (the machine has two game slots
  for every agent): `--review=poses --families=a,b --yaws=0,90 --review-out=<abs dir> [--review-tag=x]` (front and side pose
  sheets; family `sergeant_snap` builds a Snap row), `--review=reels --families=...` (every family's scripted reel back to back,
  use with `godot.py movie`), `--review=lineup`. `EnemyWorldCheck` now keeps its review camera current after the provoke beat.
- **Rig convention (measured with `--pose-add` on the side sheets):** in `pose()` body space, +X swings a hanging arm forward
  and up and tips a head up. The bee had every sign inverted (jabs went into its belly, its head looked down in the charge) and
  the gummy's notice reached backward; both are fixed. Head compensation for a lean: add `lean` (a forward lean tips the face
  down).
- **Sergeant Snap v3:** `sergeant_snap.glb` (the path W3 passes) is upgraded to `sergeant_snap_v3.glb` with the matte
  `snap_lance_v2.glb` and `snap_drum_v2.glb`; the v3 rest pose has raised arms, so every arm pose is lowered by
  `ARM_DROP_V3` (0.87 rad) in `GingerbreadGrenadier.pose()/pose_snap()`.
- **Lance:** near-horizontal lance aims are pre-tilted by the rig's lean, so the wind-up and the thrust stay level (the lance
  tipped 13 degrees up in the wind-up and dipped into the turf on the thrust); recover holds it up and out, not across the face.
- **FX:** `EnemyKit.preset(parent, name, pos, intensity, tint, size)` spawns a VFX-track preset by name. The wolf's costume rip
  uses two small `wool_burst` presets tinted back to fleece white (the CPU spheres read as bubbles). CPU `stars` are inked
  billboard cartoon stars and CPU `feathers` are leaf-shaped feathers with a quill (prisms and plain quads read as triangle
  confetti and dark rectangles). The crow's tumble trickle uses `FeatherBurst`.
- **Motion:** the wolf wind-up crouch no longer sinks the feet (bob -0.18 to -0.05); the skid keeps the face forward with
  windmilling arms; the bee's defeat corkscrews down with sputtering wings and a lolling head; the gummy wind-up squashes 13 %
  while it loads and its jelly is alpha 0.62 over a darker core 9 cm inside, with a pale rim (`--gummy-alpha=<a>` for A/B).
- **Audio:** the cub growls with `wolf_cub_growl` (the adult `wolf_growl` stays for the boss) and the crow's defeat squawk is
  `crow_hurt`; both have pitched fallbacks in `EnemyKit.SFX_ALIASES`.
- **Facing check:** every enemy GLB (including Snap v1-v3 and the rigged `_v2` bee and peapod) faces glTF +Z by its joint
  layout (beak, face pea and arms at +Z, stinger and tails at -Z; character left = +X).

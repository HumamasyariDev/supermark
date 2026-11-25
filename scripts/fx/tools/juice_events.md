### Player (emitted by game/scripts/player/)

| Event | Params | When | VFX | Feel |
| --- | --- | --- | --- | --- |
| `player_footstep` | surface (grass|wood|stone|candy|cloud), speed (m/s) | Each planted foot while walking or running (the animator's footstep signal). Small puff that grows with speed. | footstep_dust, varies by surface | - |
| `player_jump_1` | speed (m/s, horizontal) | First jump of the chain leaves the ground. | jump_puff | - |
| `player_jump_2` | speed | Second (double) jump. | jump2_burst | shake 0.05/0.12s |
| `player_jump_3` | speed, node (Mak, for the attached spin trail) | Third (triple) jump: somersault. Ground shock ring, stars and a gold spin trail on Mak. | jump3_burst, spin_trail (attached) | shake 0.12/0.18s, rumble, FOV +3.0 deg |
| `player_long_jump` | direction (travel), node | Long jump take-off: speed streaks trail behind. | long_jump_streaks (align yaw) | - |
| `player_backflip` | node | Backflip take-off. | jump2_burst, spin_trail (attached) | shake 0.06/0.14s |
| `player_side_flip` | direction, node | Side somersault out of a skid. | skid_burst (align yaw), spin_trail (attached) | - |
| `player_wall_kick` | normal (wall normal, required for the wall ring), node | Kick off a wall. The ring lies flat on the wall and the puff sprays out of it. | wall_kick_burst (align normal) | shake 0.08/0.12s, hitstop 25 ms, rumble |
| `player_land` | impact (m/s, downward speed at touchdown) | Touchdown. Tiers by impact: small dust crescents (3 to 7 m/s), dust and ring (7 to 12), heavy shock with pebbles (12+). | tiers by impact | - |
| `player_skid` | direction (travel before the skid), node | Skid turn starts (sharp reversal). | skid_burst (align yaw) | - |
| `player_ham_slam_start` | node | Ham Slam hover twirl begins in the air. | ham_slam_spin (attached) | - |
| `player_ham_slam` | impact (fall speed), surface | Ham Slam hits the ground (same moment as ground_pounded). | ham_slam | shake 0.38/0.32s, hitstop 70 ms, rumble, FOV -4.0 deg |
| `player_dive` | direction (dive direction), node | Dive starts (on the ground or in the air). | dive_whoosh (align direction) | - |
| `player_slide_start` | node (required: the trail attaches to Mak) | Belly slide begins (after a dive lands, or a steep-slope slide). Starts a continuous dust trail. | slide_trail (loop 'slide') | - |
| `player_slide_end` | node | Belly slide or slope slide ends (roll-out, stop, jump). Stops the trail. | stops loop 'slide' | - |
| `player_punch` | direction (facing), node, combo (1|2) | Jab swing starts (whiff or hit). | swish_punch (align yaw), varies by combo | - |
| `player_kick` | direction, node | Third combo hit: spin kick. | swish_kick (align yaw) | - |
| `player_jump_kick` | direction, node | Air kick. | swish_jump_kick (align yaw) | - |
| `player_hit` | kind (punch|kick|jump_kick|dive|slide|stomp|slam), node (the enemy) | Mak's attack landed on something (when the attack code knows; enemies also emit enemy_hurt). Gives the hitstop. | hit_spark, varies by kind | shake 0.12/0.12s, hitstop 55 ms, rumble |
| `player_hurt` | from (Vector3 attacker position), amount | Mak takes damage (knockback starts). | hurt_burst | shake 0.30/0.25s, hitstop 70 ms, rumble, FOV +2.5 deg |
| `player_heal` | amount | Cake slice restored (acorn, heal pickup). | heal_sparkle (attached), heal_cake | - |
| `player_ledge_grab` | node | Grabs a ledge. | ledge_dust (align yaw) | - |
| `player_climb_grab` | node | Grabs a vine or pole. | cloud_step | - |
| `player_bounce` | impact (launch speed m/s) | Mak is launched by a bouncy surface or a stomp rebound (when no object event fires). | bounce_burst | - |
| `player_sniff` | node, direction | Snout Sniff pulse (every ~0.7 s while held). | sniff_puff (align yaw) | - |
| `player_fall_out` | - | Mak falls below kill_y (before respawn). | Poof | - |
| `player_respawn` | - | Mak reappears at a checkpoint or spawn. | respawn_sparkle | - |
| `player_celebrate` | node | Celebration pose (truffle get, mission complete). | spin_trail (attached) | - |

### Enemies (emitted by game/scripts/enemies/)

| Event | Params | When | VFX | Feel |
| --- | --- | --- | --- | --- |
| `enemy_notice` | family (woolly_wolf|crow_bandit|peapod_popper|bumble_bruiser|gingerbread_grenadier|gummy_brute), node | Enemy spots Mak (the '!' moment). Emit at the head position. | notice_pop | - |
| `enemy_windup` | family (woolly_wolf|crow_bandit|peapod_popper|bumble_bruiser|gingerbread_grenadier|gummy_brute) | Attack telegraph starts (glint). Optional: enemies already flash orange. | windup_glint | - |
| `enemy_attack` | family (woolly_wolf|crow_bandit|peapod_popper|bumble_bruiser|gingerbread_grenadier|gummy_brute), direction | The committed attack (charge, dive, slam) begins. | dive_whoosh (align direction), varies by family | - |
| `enemy_slam` | family (woolly_wolf|crow_bandit|peapod_popper|bumble_bruiser|gingerbread_grenadier|gummy_brute) | Ground-slam impact of an enemy (Gummy Brute bounce-slam). | enemy_slam_ring | shake 0.22/0.20s |
| `enemy_hurt` | family (woolly_wolf|crow_bandit|peapod_popper|bumble_bruiser|gingerbread_grenadier|gummy_brute), kind (punch|kick|stomp|slam|...) | Enemy takes a hit but survives. | hit_spark, varies by kind | shake 0.12/0.12s, hitstop 60 ms, rumble |
| `enemy_block` | family (woolly_wolf|crow_bandit|peapod_popper|bumble_bruiser|gingerbread_grenadier|gummy_brute) | Hit is blocked (Grenadier lance from the front). Clang sparks, no damage. | clang, varies by repeat | shake 0.08/0.10s, hitstop 35 ms |
| `enemy_stunned` | family (woolly_wolf|crow_bandit|peapod_popper|bumble_bruiser|gingerbread_grenadier|gummy_brute), node | Enemy is dizzy or winded (skid bonk, bee wall bonk). Starts orbiting stars on node. | dizzy_stars (loop 'dizzy') | - |
| `enemy_recover` | family (woolly_wolf|crow_bandit|peapod_popper|bumble_bruiser|gingerbread_grenadier|gummy_brute), node | Stun ends. Stops the dizzy stars. | stops loop 'dizzy' | - |
| `enemy_defeat` | family (woolly_wolf|crow_bandit|peapod_popper|bumble_bruiser|gingerbread_grenadier|gummy_brute), node | Enemy defeated: the per-family cartoon gag plus a hit spark and hitstop. | hit_spark_big, defeat_poof, Confetti, varies by family | shake 0.20/0.18s, hitstop 90 ms, rumble, FOV -2.5 deg |
| `enemy_flee` | family (woolly_wolf|crow_bandit|peapod_popper|bumble_bruiser|gingerbread_grenadier|gummy_brute) | Defeated enemy leaves the stage (Woolly Wolf spins away in its underwear). | Poof | - |
| `enemy_projectile_hit` | kind (pea), surface | A projectile hits the ground or Mak. | PeaSplat | - |
| `enemy_projectile_fire` | kind (pea), direction | A projectile is launched. | cloud_step | - |

### Boss (emitted by game/scripts/boss/)

| Event | Params | When | VFX | Feel |
| --- | --- | --- | --- | --- |
| `boss_intro` | node | Huffington's entrance. | phase_burst, phase_burst | shake 0.25/0.40s |
| `boss_inhale` | node (mouth bone or head), direction | Huff wind-up: air streams into his mouth (about 1.2 s). | boss_inhale (align direction) | rumble |
| `boss_huff` | direction (gust direction) | Each huff gust leaves his mouth. | boss_huff_blast (align direction) | shake 0.30/0.35s, rumble |
| `boss_winded` | node (head) | Panting window after the huffs: sweat drops and dizzy stars. | sweat_drops, dizzy_stars (loop 'boss_dizzy') | - |
| `boss_recover` | node | Winded or stuck window ends. | stops loop 'boss_dizzy' | - |
| `boss_charge_start` | direction | Puff phase charge begins (paw scrape done). | skid_burst (align yaw) | shake 0.15/0.20s |
| `boss_footstep` | - | Heavy footfall while charging or walking. | footstep_dust | shake 0.08/0.10s |
| `boss_stomp` | - | A stomp or landing slam. | boss_stomp | shake 0.35/0.30s, rumble |
| `boss_chimney_smash` | - | Charge smashes a chimney or the parapet. | brick_debris, hit_spark_big, brick_fall | shake 0.50/0.45s, hitstop 80 ms, rumble |
| `boss_stuck` | node | Stuck in rubble (tail exposed). | dizzy_stars (loop 'boss_dizzy'), DustPuff | - |
| `boss_swipe` | direction | Paw swipe arc (emit at the wolf's feet; the arc is already boss-sized). Reserved: not emitted on night 01. | swish_wolf (align yaw) | - |
| `boss_hit` | kind (stomp|slam|tail), node | Huffington takes damage. | hit_spark_big, HitStars, defeat_poof | shake 0.50/0.35s, hitstop 140 ms, rumble, FOV -6.0 deg |
| `boss_phase` | phase (2|3) | Phase change. | phase_burst, phase_burst | shake 0.35/0.50s |
| `boss_tornado_spawn` | - | Hurricane tornado appears. | phase_burst, wind_gust | shake 0.20/0.40s |
| `boss_tornado_end` | - | The hurricane tornado winds down and disappears. | phase_burst | shake 0.10/0.30s |
| `boss_defeat` | node | Final hit: he balloons up and puffs away. Huge celebration pop. | hit_spark_big, truffle_rays, Confetti, balloon_pop, phase_burst, hat_pop | shake 0.90/0.80s, hitstop 200 ms, rumble |

### Objects and pickups (emitted by game/scripts/objects/)

| Event | Params | When | VFX | Feel |
| --- | --- | --- | --- | --- |
| `object_acorn_collect` | - | Acorn picked up. | acorn_pop | - |
| `object_acorn_spill` | count | Acorns pop out (crate, crow loot, enemy drop). | acorn_pop, Poof | - |
| `object_truffle_appear` | - | A mission truffle spawns (group cleared, cage opened, 100 acorns, pages complete). | truffle_appear | shake 0.15/0.30s |
| `object_truffle_collect` | id | Golden Truffle collected: burst, sunburst rays, confetti. Runs during the TRUFFLE GET pause. | TruffleBurst, truffle_rays | shake 0.25/0.30s, hitstop 90 ms, rumble, FOV -5.0 deg |
| `object_page_collect` | index | Lost Page collected. | page_get | hitstop 30 ms |
| `object_pages_complete` | - | Fifth page: the set is complete. | mission_fanfare | - |
| `object_checkpoint` | - | Checkpoint bookmark touched. | CheckpointGlow, truffle_appear | - |
| `object_portal_enter` | world_id | Mak jumps into a storybook (before the page turn). | portal_swirl, glint_burst | - |
| `object_door_unlock` | - | A locked door or book opens (Wolf's Door, book gate). | door_unlock | shake 0.15/0.40s |
| `object_bounce_pad` | impact (launch speed), kind (pad|leaf|gumdrop) | Launch from a bounce pad. | bounce_burst, varies by kind | shake 0.08/0.12s |
| `object_crate_break` | - | Breakable crate smashed. | crate_break | shake 0.15/0.15s, hitstop 40 ms, rumble |
| `object_switch_press` | - | Slam switch pressed. | switch_press | shake 0.12/0.15s, hitstop 30 ms |
| `object_cage_open` | - | Cage opens (goose freed). | cage_open | shake 0.20/0.30s |
| `object_cloud_step` | - | Mak lands on a cloud platform. | cloud_step | - |
| `object_cloud_vanish` | - | A cloud platform puffs away. | cloud_puff | - |
| `object_cloud_return` | - | A vanished cloud reforms. | cloud_step | - |
| `object_platform_crumble` | - | A falling platform starts to drop. | platform_crumble | - |
| `object_bellows_blast` | direction (wind) | A bellows machine pumps a gust. | wind_gust (align direction), cloud_step | - |
| `object_bellows_break` | - | A bellows machine is Ham Slammed and breaks. | crate_break, hit_spark_big | shake 0.30/0.30s, hitstop 80 ms, rumble |
| `object_dig` | - | Buried treasure or sniff spot dug up. | dig_burst | shake 0.15/0.20s |
| `object_sniff_reveal` | - | A sniff target is found. | truffle_appear | - |
| `object_ring_pass` | index | Time-trial ring passed. | ring_burst | - |
| `object_trial_start` | - | Time trial starts. | ring_burst | - |
| `object_trial_complete` | - | Time trial finished in time. | mission_fanfare | - |
| `object_trial_fail` | - | Time trial ran out. | Poof | - |
| `object_mission_complete` | - | A mission's goal is met (before the truffle). Reserved: not emitted on night 01. | mission_fanfare | - |

### World and hazards (emitted by world scripts, objects or the player)

| Event | Params | When | VFX | Feel |
| --- | --- | --- | --- | --- |
| `world_splash` | impact, scale | Something enters water. | Splash | - |
| `world_cocoa_splash` | impact | Something enters hot chocolate (no damage). | CocoaSplash | - |
| `world_cocoa_burn` | - | Mak touches hot chocolate and is hurt (pair with player_hurt). | cocoa_burn | - |
| `world_wind_gust` | direction | A visible gust burst (bellows, snore, storm). Reserved: not emitted on night 01. | wind_gust (align direction) | - |
| `world_lightning` | - | Lightning strike flash (put it far away, toward the strike). | lightning_flash | shake 0.10/0.40s |
| `world_debris` | - | Generic rubble burst (falling ornaments, broken props). Reserved: not emitted on night 01. | brick_debris | shake 0.12/0.20s |
| `world_enter` | world_id | A world finished loading (Mak appears). | respawn_sparkle | - |

### Integration additions (names already emitted by the player, objects and enemy tracks)

| Event | Params | When | VFX | Feel |
| --- | --- | --- | --- | --- |
| `player_brake` | speed, direction | Hard stop from a run (no reversal). | skid_burst (align yaw) | - |
| `player_crouch_slide` | speed, direction | Crouch slide from a run. | skid_burst (align yaw) | - |
| `player_ledge_climb` | fast (bool) | Pull-up from a ledge hang. | ledge_dust | - |
| `player_stomp` | kind (stomp|slam), node | Mak bounces off an enemy's head (pair with the enemy's own event). | hit_spark, DustPuff | shake 0.10/0.10s, hitstop 35 ms, rumble |
| `player_death` | - | Cake ran out (before the respawn). | Poof, hurt_burst, page_flutter | shake 0.30/0.40s, hitstop 120 ms, rumble |
| `player_sniff_found` | target | Snout Sniff locks onto a hidden truffle. | glint_burst | - |
| `player_hat_change` | hat | Hat swapped (pause menu): a magician's poof on Mak's head. | hat_poof | - |
| `player_bonk` | normal (wall normal), impact (m/s into the wall) | Mak runs or dives face-first into a wall and bounces back (the bonk state). Stars and a dust slap on the wall. | hit_stars, wall_kick_burst (align normal) | shake 0.18/0.20s, hitstop 40 ms, rumble |
| `object_crate_land` | impact (drop height m) | A pushed or knocked crate lands after a drop. | DustPuff | shake 0.08/0.12s |
| `player_sniff_air` | node, direction | Idle animation beat: Mak sniffs the air (MakAnimator sniff_air). A tiny snout puff. | sniff_puff (align yaw) | - |
| `object_acorn_magnet` | - | Acorns start homing to Mak. | glint_burst | - |
| `object_truffle_burst` | id | Truffle bursts out on collection (objects' own moment; the celebration is object_truffle_collect). | truffle_appear | - |
| `object_cage_lamp` | lit, needed | One of the cage's switch lamps lights. | switch_press | - |
| `object_cage_rattle` | - | Mak bumps the locked cage. | clang | - |
| `object_cage_vanish` | - | The cage poofs away. | Poof, glint_burst | - |
| `object_dig_splash` | - | Mud splat while digging. | dig_burst | - |
| `object_door_locked` | need | Locked door knocked (not enough truffles). | clang, clang | - |
| `object_door_open` | target | A door swings open. | door_unlock | shake 0.12/0.30s |
| `object_door_thud` | - | The door hits its stop. | land_heavy | shake 0.15/0.20s |
| `object_hazard_touch` | look | Mak touches a damaging volume (not hot chocolate). | hazard_burst | - |
| `object_kill_zone` | - | Mak falls into a kill zone (no effect; the player emits player_fall_out). | none (sound only) | - |
| `object_npc_greet` | speaker | An NPC notices Mak. | notice_pop | - |
| `object_npc_talk` | speaker | Dialogue opens with an NPC. | none (sound only) | - |
| `object_sign_read` | - | A sign is read. | none (sound only) | - |
| `object_platform_wobble` | - | A falling platform starts to wobble. | footstep_dust | - |
| `object_portal_locked` | world | A locked storybook is touched. | clang | - |
| `object_portal_page_turn` | world | A page flips on an open storybook (idle flourish). | glint_burst | - |

### UI (emitted by game/scripts/ui/; sound only, no position)

| Event | Params | When | VFX | Feel |
| --- | --- | --- | --- | --- |
| `ui_move` | - | Cursor moves. | none (sound only) | - |
| `ui_select` | - | Confirm. | none (sound only) | - |
| `ui_back` | - | Back or cancel. | none (sound only) | - |
| `ui_page_turn` | - | Storybook page turn (mission select, transitions). | none (sound only) | - |
| `ui_pause` | - | Pause menu opens. | none (sound only) | - |
| `ui_unpause` | - | Pause menu closes. | none (sound only) | - |
| `ui_truffle_get` | - | TRUFFLE GET! banner appears. | none (sound only) | - |
| `ui_mission_banner` | - | Mission name banner slides in. | none (sound only) | - |

Aliases (accepted, resolved to the canonical name): `player_jump` -> `player_jump_1`, `player_jump_single` -> `player_jump_1`, `player_jump_double` -> `player_jump_2`, `player_jump_triple` -> `player_jump_3`, `player_jump_long` -> `player_long_jump`, `player_jump_backflip` -> `player_backflip`, `player_jump_side_flip` -> `player_side_flip`, `player_jump_side` -> `player_side_flip`, `player_jump_wall` -> `player_wall_kick`, `player_ground_pound` -> `player_ham_slam`, `player_attack_punch` -> `player_punch`, `player_attack_kick` -> `player_kick`, `player_attack_jump_kick` -> `player_jump_kick`, `player_attack_dive` -> `player_dive`, `player_damaged` -> `player_hurt`, `object_truffle` -> `object_truffle_collect`, `object_acorn` -> `object_acorn_collect`, `enemy_hit` -> `enemy_hurt`, `enemy_die` -> `enemy_defeat`, `boss_damage` -> `boss_hit`.

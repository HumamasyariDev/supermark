"""Source of truth for the Juice event catalogue (juice track, night 01).

Writes:
  game/scripts/fx/juice_vfx.json          read by the Juice autoload at runtime
  game/scripts/fx/tools/juice_events.md   the event tables pasted into Docs/JUICE.md (between markers)

Run:  python game/scripts/fx/tools/juice_catalogue.py
Each event: emitter, params (doc string), doc (when to emit), vfx list, optional shake [strength 0..1, seconds],
hitstop_ms, rumble [weak, strong, seconds], scale_by, tiers, by_param, cooldown, and a fallback `sfx`
(Audio keys used only when the audio track's juice_sfx.json has no entry for the event).
"""
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
FX = HERE.parent
ENTITY = FX.parents[2]


def P(preset, **kw):
    d = {"preset": preset}
    d.update(kw)
    return d


def S(scene, **kw):
    d = {"scene": scene}
    d.update(kw)
    return d


E = {}
GROUPS = []


def group(title):
    GROUPS.append((title, []))


def ev(name, emitter, params, doc, **kw):
    e = {"emitter": emitter, "params": params, "doc": doc}
    e.update(kw)
    E[name] = e
    GROUPS[-1][1].append(name)


IMPACT = {"param": "impact", "in": [3.0, 17.0], "out": [0.7, 1.5]}
# Juice fix r2: small, frequent feedback grows a little with camera distance (1.0 at 4 m, 1.35 at the 5.4 m hero camera).
GP = [4.0, 1.6]

# ------------------------------------------------------------------ player
group("Player (emitted by game/scripts/player/)")
ev("player_footstep", "player", "surface (grass|wood|stone|candy|cloud), speed (m/s)",
   "Each planted foot while walking or running (the animator's footstep signal). Small puff that grows with speed.",
   vfx=[P("footstep_dust", scale=0.9, cam_scale=GP, toward_camera=0.3, lift=0.0, flat_toward=True, surface=True)], scale_by={"param": "speed", "in": [1.0, 7.5], "out": [0.7, 1.15]}, cooldown=0.06,
   by_param={"param": "surface", "map": {
       "grass": {"vfx": [P("footstep_grass", cam_scale=GP, toward_camera=0.3, lift=0.0, flat_toward=True, surface=True)]}, "candy": {"vfx": [P("footstep_candy", cam_scale=GP, toward_camera=0.3, lift=0.0, flat_toward=True, surface=True)]},
       "wood": {"vfx": [P("footstep_wood", cam_scale=GP, toward_camera=0.3, lift=0.0, flat_toward=True, surface=True)]}, "cloud": {"vfx": [P("cloud_step", scale=0.45, cam_scale=GP)]}}},
   sfx={"keys": ["footstep_grass"], "volume_db": -2})
ev("player_jump_1", "player", "speed (m/s, horizontal)", "First jump of the chain leaves the ground.",
   vfx=[P("jump_puff", cam_scale=GP, toward_camera=0.3, lift=0.0, flat_toward=True, surface=True)], sfx={"keys": ["jump_1"], "pitch": [0.97, 1.03]})
ev("player_jump_2", "player", "speed", "Second (double) jump.",
   vfx=[P("jump2_burst", surface=True)], shake=[0.05, 0.12], sfx={"keys": ["jump_2"], "pitch": [0.98, 1.04]})
ev("player_jump_3", "player", "speed, node (Mak, for the attached spin trail)",
   "Third (triple) jump: somersault. Ground shock ring, stars and a gold spin trail on Mak.",
   vfx=[P("jump3_burst", surface=True), P("spin_trail", attach=True, offset=[0, 0.6, 0])], shake=[0.12, 0.18], rumble=[0.25, 0.1, 0.12],
   fov=[3.0, 0.35], sfx={"keys": ["jump_3"]})
ev("player_long_jump", "player", "direction (travel), node", "Long jump take-off: speed streaks trail behind.",
   vfx=[P("long_jump_streaks", align="yaw", surface=True)], sfx={"keys": ["long_jump"]})
ev("player_backflip", "player", "node", "Backflip take-off.",
   vfx=[P("jump2_burst"), P("spin_trail", attach=True, offset=[0, 0.6, 0])], shake=[0.06, 0.14], sfx={"keys": ["backflip"]})
ev("player_side_flip", "player", "direction, node", "Side somersault out of a skid.",
   vfx=[P("skid_burst", align="yaw", scale=0.8, surface=True), P("spin_trail", attach=True, offset=[0, 0.6, 0])], sfx={"keys": ["backflip"]})
ev("player_wall_kick", "player", "normal (wall normal, required for the wall ring), node",
   "Kick off a wall. The ring lies flat on the wall and the puff sprays out of it.",
   vfx=[P("wall_kick_burst", align="normal", offset=[0, 0.0, 0], cam_scale=GP)], shake=[0.08, 0.12], hitstop_ms=25, rumble=[0.2, 0.15, 0.08],
   sfx={"keys": ["wall_kick"]})
ev("player_land", "player", "impact (m/s, downward speed at touchdown)",
   "Touchdown. Tiers by impact: small dust crescents (3 to 7 m/s), dust and ring (7 to 12), heavy shock with pebbles (12+).",
   vfx=[], scale_by=IMPACT,
   tiers={"param": "impact", "steps": [
       {"min": 0.0},
       {"min": 3.0, "vfx": [P("land_soft", cam_scale=GP, toward_camera=0.3, lift=0.0, flat_toward=True, surface=True)]},
       {"min": 7.0, "vfx": [P("dust_puff", surface=True), P("landing_ring", surface=True)], "shake": [0.06, 0.12]},
       {"min": 12.0, "vfx": [P("land_heavy", surface=True)], "shake": [0.18, 0.2], "rumble": [0.3, 0.35, 0.12]}]},
   sfx={"keys": ["land", "land_2"]})
ev("player_skid", "player", "direction (travel before the skid), node", "Skid turn starts (sharp reversal).",
   vfx=[P("skid_burst", align="yaw", cam_scale=GP, toward_camera=0.3, lift=0.0, flat_toward=True, surface=True)], cooldown=0.15, sfx={"keys": ["skid"]})
ev("player_ham_slam_start", "player", "node", "Ham Slam hover twirl begins in the air.",
   vfx=[P("ham_slam_spin", attach=True)], sfx={"keys": ["dive"], "pitch": [1.2, 1.25], "volume_db": -6})
ev("player_ham_slam", "player", "impact (fall speed), surface", "Ham Slam hits the ground (same moment as ground_pounded).",
   vfx=[P("ham_slam", surface=True)], scale_by={"param": "impact", "in": [8.0, 18.0], "out": [0.9, 1.25]},
   shake=[0.38, 0.32], hitstop_ms=70, rumble=[0.5, 0.8, 0.22], fov=[-4.0, 0.3], sfx={"keys": ["ham_slam"]})
ev("player_dive", "player", "direction (dive direction), node", "Dive starts (on the ground or in the air).",
   vfx=[P("dive_whoosh", align="direction")], sfx={"keys": ["dive"]})
ev("player_slide_start", "player", "node (required: the trail attaches to Mak)",
   "Belly slide begins (after a dive lands, or a steep-slope slide). Starts a continuous dust trail.",
   vfx=[P("slide_trail", loop="slide", offset=[0, 0.1, 0])], sfx={"keys": ["slide"]})
ev("player_slide_end", "player", "node", "Belly slide or slope slide ends (roll-out, stop, jump). Stops the trail.",
   stop_loop="slide", vfx=[])
ev("player_punch", "player", "direction (facing), node, combo (1|2)", "Jab swing starts (whiff or hit).",
   vfx=[P("swish_punch", align="yaw")], by_param={"param": "combo", "map": {"2": {"vfx": [P("swish_punch_l", align="yaw")]}}},
   sfx={"keys": ["punch", "punch_2"]})
ev("player_kick", "player", "direction, node", "Third combo hit: spin kick.",
   vfx=[P("swish_kick", align="yaw")], sfx={"keys": ["kick", "kick_2"]})
ev("player_jump_kick", "player", "direction, node", "Air kick.",
   vfx=[P("swish_jump_kick", align="yaw")], sfx={"keys": ["kick"]})
ev("player_hit", "player", "kind (punch|kick|jump_kick|dive|slide|stomp|slam), node (the enemy)",
   "Mak's attack landed on something (when the attack code knows; enemies also emit enemy_hurt). Gives the hitstop.",
   vfx=[P("hit_spark", toward_camera=0.25, lift=0.0)], shake=[0.12, 0.12], hitstop_ms=55, rumble=[0.35, 0.3, 0.08],
   suppress_after=["enemy_hurt", "enemy_defeat", "enemy_block", "enemy_stunned", "boss_hit", "object_crate_break", "object_bellows_break",
                   "object_switch_press"],
   by_param={"param": "kind", "map": {"stomp": {"vfx": [P("hit_spark", toward_camera=0.25, lift=0.0), S("DustPuff", scale=0.6)], "hitstop_ms": 40},
                                       "slam": {"hitstop_ms": 70, "shake": [0.2, 0.15]}}},
   sfx={"keys": ["enemy_hit", "enemy_hit_2", "enemy_hit_3"]})
ev("player_hurt", "player", "from (Vector3 attacker position), amount", "Mak takes damage (knockback starts).",
   vfx=[P("hurt_burst", offset=[0, 0.8, 0], toward_camera=0.4, lift=0.0)], shake=[0.3, 0.25], hitstop_ms=70, rumble=[0.6, 0.6, 0.25],
   fov=[2.5, 0.3], sfx={"keys": ["hurt"]})
ev("player_heal", "player or objects", "amount", "Cake slice restored (acorn, heal pickup).",
   vfx=[P("heal_sparkle", attach=True), P("heal_cake", toward_camera=0.4, lift=0.85)], sfx={"keys": ["cake_slice_gained"]})
ev("player_ledge_grab", "player", "node", "Grabs a ledge.", vfx=[P("ledge_dust", offset=[0, 1.1, -0.3], align="yaw")],
   sfx={"keys": ["ledge_grab"]})
ev("player_climb_grab", "player", "node", "Grabs a vine or pole.", vfx=[P("cloud_step", scale=0.3)], sfx={"keys": ["ledge_grab"], "pitch": [1.1, 1.2]})
ev("player_bounce", "player", "impact (launch speed m/s)", "Mak is launched by a bouncy surface or a stomp rebound (when no object event fires).",
   vfx=[P("bounce_burst", scale=0.7)], suppress_after=["player_stomp", "object_bounce_pad"], sfx={"keys": ["bounce_leaf"]})
ev("player_sniff", "player", "node, direction", "Snout Sniff pulse (every ~0.7 s while held).",
   vfx=[P("sniff_puff", offset=[0, 0.55, -0.3], align="yaw", cam_scale=GP, toward_camera=0.35, lift=0.0, flat_toward=True)], cooldown=0.5, sfx={"keys": ["sniff"]})
ev("player_fall_out", "player", "", "Mak falls below kill_y (before respawn).", vfx=[S("Poof", scale=1.2)],
   sfx={"keys": ["vo_mak_whoa"]})
ev("player_respawn", "player or core", "", "Mak reappears at a checkpoint or spawn.", vfx=[P("respawn_sparkle")],
   sfx={"keys": ["checkpoint"], "pitch": [1.1, 1.1]})
ev("player_celebrate", "player", "node", "Celebration pose (truffle get, mission complete).",
   vfx=[P("spin_trail", attach=True, offset=[0, 0.6, 0], pause_proof=True)], sfx=None)

# ------------------------------------------------------------------ enemies
group("Enemies (emitted by game/scripts/enemies/)")
FAM = "family (woolly_wolf|crow_bandit|peapod_popper|bumble_bruiser|gingerbread_grenadier|gummy_brute)"
# Juice fix r2: defeat layers grow with camera distance like the sparks, so wool, feathers and crumbs read at 8 m.
CS = [8.0, 2.0]
BIG = P("hit_spark_big", toward_camera=0.25, lift=0.0)
POOF = P("defeat_poof", cam_scale=CS)
ev("enemy_notice", "enemies", FAM + ", node", "Enemy spots Mak (the '!' moment). Emit at the head position.",
   vfx=[P("notice_pop", scale=1.25, near_clamp=4.0)], cooldown=0.4, sfx={"keys": ["enemy_notice"]})
ev("enemy_windup", "enemies", FAM, "Attack telegraph starts (glint). Optional: enemies already flash orange.",
   vfx=[P("windup_glint")], sfx=None)
ev("enemy_attack", "enemies", FAM + ", direction", "The committed attack (charge, dive, slam) begins.",
   vfx=[P("dive_whoosh", align="direction", scale=0.8)],
   by_param={"param": "family", "map": {"gummy_brute": {"vfx": []}, "peapod_popper": {"vfx": [P("cloud_step", scale=0.4, tint="#c8f0a0")]}}},
   sfx=None)
ev("enemy_slam", "enemies", FAM, "Ground-slam impact of an enemy (Gummy Brute bounce-slam).",
   vfx=[P("enemy_slam_ring")], shake=[0.22, 0.2], sfx={"keys": ["gummy_wobble"]})
ev("enemy_hurt", "enemies", FAM + ", kind (punch|kick|stomp|slam|...)", "Enemy takes a hit but survives.",
   vfx=[P("hit_spark", toward_camera=0.25, lift=0.0)], shake=[0.12, 0.12], hitstop_ms=60, rumble=[0.35, 0.3, 0.08],
   by_param={"param": "kind", "map": {"slam": {"hitstop_ms": 80, "shake": [0.22, 0.16]}}},
   sfx={"keys": ["enemy_hit", "enemy_hit_2", "enemy_hit_3"]})
ev("enemy_block", "enemies", FAM, "Hit is blocked (Grenadier lance from the front). Clang sparks, no damage.",
   vfx=[P("clang")], shake=[0.08, 0.1], hitstop_ms=35, sfx={"keys": ["enemy_hit_3"], "pitch": [1.4, 1.5]},
   # Juice fix r4: consecutive blocks escalate (params.repeat): a dust skid and a shield-wobble glint from the second one,
   # a bigger shake from the third.
   repeat={"window": 2.5},
   by_param={"param": "repeat", "map": {"1": {}, "2": {"vfx": [P("clang", scale=1.1), P("block_wobble")]},
                                         "_default": {"vfx": [P("clang", scale=1.2), P("block_wobble", scale=1.2)], "shake": [0.12, 0.12]}}})
ev("enemy_stunned", "enemies", FAM + ", node", "Enemy is dizzy or winded (skid bonk, bee wall bonk). Starts orbiting stars on node.",
   vfx=[P("dizzy_stars", loop="dizzy", offset=[0, 1.2, 0])], sfx=None)
ev("enemy_recover", "enemies", FAM + ", node", "Stun ends. Stops the dizzy stars.", stop_loop="dizzy", vfx=[])
ev("enemy_defeat", "enemies", FAM + ", node", "Enemy defeated: the per-family cartoon gag plus a hit spark and hitstop.",
   vfx=[P("hit_spark_big", toward_camera=0.25, lift=0.0), P("defeat_poof", cam_scale=CS), S("Confetti", scale=1.3, cam_scale=CS)],
   shake=[0.2, 0.18], hitstop_ms=90, rumble=[0.45, 0.45, 0.15], fov=[-2.5, 0.25], flash_node=[0.034, 1.0],
   # Juice fix r4: families that hold their debris for the gag's beat pass no_vfx; the impact star still plays on the hit frame.
   impact_vfx=[P("hit_spark_big", toward_camera=0.25, lift=0.0)],
   by_param={"param": "family", "map": {
       "woolly_wolf": {"vfx": [BIG, POOF, P("wool_burst", scale=1.3, cam_scale=CS)]},
       "crow_bandit": {"vfx": [BIG, POOF, S("FeatherBurst", scale=1.1, cam_scale=[8.0, 1.5])]},
       "peapod_popper": {"vfx": [BIG, POOF, S("PeaSplat", scale=1.6, cam_scale=CS)]},
       "bumble_bruiser": {"vfx": [BIG, POOF, P("bee_burst", scale=1.3, cam_scale=CS)]},
       "gingerbread_grenadier": {"vfx": [BIG, POOF, S("CrumbBurst", scale=1.5, cam_scale=CS)]},
       "gummy_brute": {"vfx": [P("hit_spark_big", scale=1.1, toward_camera=0.25, lift=0.0), POOF, P("gummy_splat", scale=1.3, cam_scale=CS)]}}},
   sfx={"keys": ["enemy_defeat_poof"]})
ev("enemy_flee", "enemies", FAM, "Defeated enemy leaves the stage (Woolly Wolf spins away in its underwear).",
   vfx=[S("Poof")], sfx=None)
ev("enemy_projectile_hit", "enemies", "kind (pea), surface", "A projectile hits the ground or Mak.",
   vfx=[S("PeaSplat")], sfx={"keys": ["pea_pop"], "pitch": [0.9, 1.1]})
ev("enemy_projectile_fire", "enemies", "kind (pea), direction", "A projectile is launched.",
   vfx=[P("cloud_step", scale=0.35, tint="#d8f5b0")], sfx={"keys": ["pea_pop"]})

# ------------------------------------------------------------------ boss
group("Boss (emitted by game/scripts/boss/)")
ev("boss_intro", "boss", "node", "Huffington's entrance.", vfx=[P("phase_burst"), P("phase_burst", scale=0.6, delay=0.4, offset=[0, 1.0, 0])],
   shake=[0.25, 0.4], sfx=None)
ev("boss_inhale", "boss", "node (mouth bone or head), direction", "Huff wind-up: air streams into his mouth (about 1.2 s).",
   vfx=[P("boss_inhale", align="direction")], rumble=[0.15, 0.0, 1.0], sfx={"keys": ["boss_inhale"]})
ev("boss_huff", "boss", "direction (gust direction)", "Each huff gust leaves his mouth.",
   vfx=[P("boss_huff_blast", align="direction")], shake=[0.3, 0.35], shake_falloff=False, rumble=[0.4, 0.6, 0.3],
   sfx={"keys": ["boss_huff_blast"]})
ev("boss_winded", "boss", "node (head)", "Panting window after the huffs: sweat drops and dizzy stars.",
   vfx=[P("sweat_drops"), P("dizzy_stars", loop="boss_dizzy", offset=[0, 0.4, 0], scale=1.8)], sfx={"keys": ["vo_wolf_panting"]})
ev("boss_recover", "boss", "node", "Winded or stuck window ends.", stop_loop="boss_dizzy", vfx=[])
ev("boss_charge_start", "boss", "direction", "Puff phase charge begins (paw scrape done).",
   vfx=[P("skid_burst", align="yaw", scale=2.2)], shake=[0.15, 0.2], sfx={"keys": ["boss_charge"]})
ev("boss_footstep", "boss", "", "Heavy footfall while charging or walking.", vfx=[P("footstep_dust", scale=2.6, surface=True)],
   shake=[0.08, 0.1], cooldown=0.12, sfx={"keys": ["boss_stomp"], "volume_db": -6})
ev("boss_stomp", "boss", "", "A stomp or landing slam.", vfx=[P("boss_stomp", surface=True)], shake=[0.35, 0.3], rumble=[0.5, 0.7, 0.2],
   sfx={"keys": ["boss_stomp"]})
ev("boss_chimney_smash", "boss or world", "", "Charge smashes a chimney or the parapet.",
   vfx=[P("brick_debris"), P("hit_spark_big", offset=[0, 1.0, 0]), P("brick_fall", delay=0.3)], shake=[0.5, 0.45], shake_falloff=False, hitstop_ms=80,
   rumble=[0.7, 0.9, 0.3], sfx={"keys": ["chimney_crash"]})
ev("boss_stuck", "boss", "node", "Stuck in rubble (tail exposed).",
   vfx=[P("dizzy_stars", loop="boss_dizzy", offset=[0, 3.0, 0], scale=1.8), S("DustPuff", scale=2.0, delay=0.2)], sfx={"keys": ["vo_wolf_getback"]})
ev("boss_swipe", "boss", "direction", "Paw swipe arc (emit at the wolf's feet; the arc is already boss-sized). Reserved: not emitted on night 01.", vfx=[P("swish_wolf", align="yaw")], sfx={"keys": ["kick"], "pitch": [0.6, 0.65]})
ev("boss_hit", "boss", "kind (stomp|slam|tail), node", "Huffington takes damage.",
   # Juice fix r3: boss-sized (the 1 m hit star read small on the 3.2 m wolf from the gameplay camera); a fur poof keeps
   # the hit on screen for about 0.4 s.
   vfx=[P("hit_spark_big", scale=1.8, cam_scale=[8.0, 2.5], toward_camera=1.0, lift=0.0), S("HitStars", scale=1.4, cam_scale=[8.0, 2.0]),
        P("defeat_poof", scale=1.6, toward_camera=0.6, lift=0.0, tint="#f3dcc4")], shake=[0.5, 0.35], hitstop_ms=140, rumble=[0.8, 0.9, 0.3],
   fov=[-6.0, 0.35],
   shake_falloff=False, sfx={"keys": ["enemy_hit_3"], "pitch": [0.7, 0.75]})
ev("boss_phase", "boss", "phase (2|3)", "Phase change.", vfx=[P("phase_burst"), P("phase_burst", scale=0.7, delay=0.25, offset=[0, 1.2, 0])],
   shake=[0.35, 0.5], shake_falloff=False,
   sfx={"keys": ["vo_wolf_laugh"]})
ev("boss_tornado_spawn", "boss", "", "Hurricane tornado appears.", vfx=[P("phase_burst", scale=0.8), P("wind_gust", scale=1.5)],
   shake=[0.2, 0.4], sfx={"keys": ["gust_whoosh"]})
ev("boss_tornado_end", "boss", "", "The hurricane tornado winds down and disappears.",
   vfx=[P("phase_burst", scale=0.6, offset=[0, 1.0, 0])], shake=[0.1, 0.3], sfx={"keys": ["gust_whoosh"], "pitch": [0.8, 0.85], "volume_db": -4})
ev("boss_defeat", "boss", "node", "Final hit: he balloons up and puffs away. Huge celebration pop.",
   vfx=[P("hit_spark_big", offset=[0, 2.2, 0], scale=1.6, cam_scale=[8.0, 2.0], priority=3),
        P("truffle_rays", offset=[0, 2.2, 0], scale=1.4, delay=0.18, priority=3),
        S("Confetti", offset=[0, 3.2, 0], scale=2.0, delay=0.42, priority=3),
        P("balloon_pop", offset=[0, 2.0, 0], delay=0.6, priority=3), P("phase_burst", offset=[0, 1.0, 0], delay=0.62, priority=3),
        P("hat_pop", offset=[0, 3.4, 0], delay=0.9, priority=3)],
   shake=[0.9, 0.8], shake_falloff=False, hitstop_ms=200, rumble=[1.0, 1.0, 0.6],
   sfx={"keys": ["vo_wolf_curses"]})

# ------------------------------------------------------------------ objects
group("Objects and pickups (emitted by game/scripts/objects/)")
ev("object_acorn_collect", "objects", "", "Acorn picked up.", vfx=[P("acorn_pop", scale=1.5)], cooldown=0.02,
   sfx={"keys": ["acorn_collect", "acorn_collect_2"], "pitch": [0.97, 1.08]})
ev("object_acorn_spill", "objects or enemies", "count", "Acorns pop out (crate, crow loot, enemy drop).",
   vfx=[P("acorn_pop", scale=1.3), S("Poof", scale=0.6)], sfx={"keys": ["pea_pop"], "pitch": [1.2, 1.3]})
ev("object_truffle_appear", "objects", "", "A mission truffle spawns (group cleared, cage opened, 100 acorns, pages complete).",
   vfx=[P("truffle_appear")], shake=[0.15, 0.3], shake_falloff=False, sfx={"keys": ["sfx_truffle_get"], "pitch": [0.8, 0.8], "volume_db": -4})
ev("object_truffle_collect", "objects", "id", "Golden Truffle collected: burst, sunburst rays, confetti. Runs during the TRUFFLE GET pause.",
   vfx=[S("TruffleBurst", pause_proof=True, priority=3), P("truffle_rays", pause_proof=True, priority=3, offset=[0, 0.4, 0])],
   shake=[0.25, 0.3], shake_falloff=False, hitstop_ms=90, rumble=[0.6, 0.6, 0.3], fov=[-5.0, 0.4], sfx={"keys": ["sfx_truffle_get"]})
ev("object_page_collect", "objects", "index", "Lost Page collected.", vfx=[P("page_get")], hitstop_ms=30,
   sfx={"keys": ["page_collect"]})
ev("object_pages_complete", "objects", "", "Fifth page: the set is complete.", vfx=[P("mission_fanfare")], sfx={"keys": ["page_turn"]})
ev("object_checkpoint", "objects", "", "Checkpoint bookmark touched.", vfx=[S("CheckpointGlow"), P("truffle_appear", scale=0.6)],
   sfx={"keys": ["checkpoint"]})
ev("object_portal_enter", "objects", "world_id", "Mak jumps into a storybook (before the page turn).",
   vfx=[P("portal_swirl", pause_proof=True, priority=3), P("glint_burst", offset=[0, 1.0, 0], delay=0.15, pause_proof=True, priority=3)],
   sfx={"keys": ["book_open"]})
ev("object_door_unlock", "objects", "", "A locked door or book opens (Wolf's Door, book gate).", vfx=[P("door_unlock")],
   shake=[0.15, 0.4], shake_falloff=False, sfx={"keys": ["door_unlock"]})
ev("object_bounce_pad", "objects", "impact (launch speed), kind (pad|leaf|gumdrop)", "Launch from a bounce pad.",
   vfx=[P("bounce_burst", scale=1.3)], scale_by={"param": "impact", "in": [8.0, 20.0], "out": [0.85, 1.25]}, shake=[0.08, 0.12],
   by_param={"param": "kind", "map": {"leaf": {"vfx": [P("leaf_bounce", scale=1.3)], "sfx": {"keys": ["bounce_leaf", "leaf_bounce"]}},
                                       "gumdrop": {"vfx": [P("gumdrop_bounce", scale=1.3)], "sfx": {"keys": ["bounce_gumdrop", "gumdrop_bounce"]}}}},
   sfx={"keys": ["bounce_leaf"]})
ev("object_crate_break", "objects", "", "Breakable crate smashed.", vfx=[P("crate_break")], shake=[0.15, 0.15], hitstop_ms=40,
   rumble=[0.3, 0.4, 0.1], sfx={"keys": ["crate_break"]})
ev("object_switch_press", "objects", "", "Slam switch pressed.", vfx=[P("switch_press")], shake=[0.12, 0.15], hitstop_ms=30,
   sfx={"keys": ["switch_press"]})
ev("object_cage_open", "objects", "", "Cage opens (goose freed).", vfx=[P("cage_open")], shake=[0.2, 0.3], shake_falloff=False,
   sfx={"keys": ["door_unlock"], "pitch": [1.1, 1.1]})
ev("object_cloud_step", "objects", "", "Mak lands on a cloud platform.", vfx=[P("cloud_step")], cooldown=0.2, sfx={"keys": ["cloud_puff"], "volume_db": -6})
ev("object_cloud_vanish", "objects", "", "A cloud platform puffs away.", vfx=[P("cloud_puff")],
   sfx={"keys": ["cloud_puff", "cloud_puff_2"]})
ev("object_cloud_return", "objects", "", "A vanished cloud reforms.", vfx=[P("cloud_step", scale=1.6)], sfx={"keys": ["cloud_puff"], "pitch": [1.2, 1.3], "volume_db": -8})
ev("object_platform_crumble", "objects", "", "A falling platform starts to drop.", vfx=[P("platform_crumble")], sfx={"keys": ["crate_break"], "pitch": [0.7, 0.8], "volume_db": -4})
ev("object_bellows_blast", "objects", "direction (wind)", "A bellows machine pumps a gust.",
   vfx=[P("wind_gust", align="direction"), P("cloud_step", scale=0.6)], cooldown=0.3, sfx={"keys": ["bellows_pump"]})
ev("object_bellows_break", "objects", "", "A bellows machine is Ham Slammed and breaks.",
   vfx=[P("crate_break", scale=1.3), P("hit_spark_big")], shake=[0.3, 0.3], hitstop_ms=80, rumble=[0.5, 0.6, 0.2],
   sfx={"keys": ["bellows_break"]})
ev("object_dig", "objects", "", "Buried treasure or sniff spot dug up.", vfx=[P("dig_burst")], shake=[0.15, 0.2], sfx={"keys": ["ground_pound"]})
ev("object_sniff_reveal", "objects", "", "A sniff target is found.", vfx=[P("truffle_appear", scale=0.5)], sfx={"keys": ["sniff"], "pitch": [1.2, 1.2]})
ev("object_ring_pass", "objects", "index", "Time-trial ring passed.", vfx=[P("ring_burst")], sfx={"keys": ["acorn_collect"], "pitch": [1.2, 1.4]})
ev("object_trial_start", "objects", "", "Time trial starts.", vfx=[P("ring_burst", scale=1.4)], sfx={"keys": ["checkpoint"]})
ev("object_trial_complete", "objects", "", "Time trial finished in time.", vfx=[P("mission_fanfare")], sfx={"keys": ["page_turn"]})
ev("object_trial_fail", "objects", "", "Time trial ran out.", vfx=[S("Poof", scale=1.4)], sfx={"keys": ["vo_mak_blast"]})
ev("object_mission_complete", "objects or core", "", "A mission's goal is met (before the truffle). Reserved: not emitted on night 01.", vfx=[P("mission_fanfare")], sfx=None)

# ------------------------------------------------------------------ world
group("World and hazards (emitted by world scripts, objects or the player)")
ev("world_splash", "player or objects", "impact, scale", "Something enters water.", vfx=[S("Splash")],
   scale_by={"param": "impact", "in": [2.0, 14.0], "out": [0.6, 1.3]}, cooldown=0.1, sfx={"keys": ["splash", "splash_2"]})
ev("world_cocoa_splash", "player or objects", "impact", "Something enters hot chocolate (no damage).", vfx=[S("CocoaSplash")],
   scale_by={"param": "impact", "in": [2.0, 14.0], "out": [0.6, 1.3]}, cooldown=0.1, sfx={"keys": ["splash"], "pitch": [0.8, 0.85]})
ev("world_cocoa_burn", "objects (hot chocolate hazard)", "", "Mak touches hot chocolate and is hurt (pair with player_hurt).",
   vfx=[P("cocoa_burn")], cooldown=0.3, sfx={"keys": ["splash"], "pitch": [0.75, 0.8]})
ev("world_wind_gust", "world or objects", "direction", "A visible gust burst (bellows, snore, storm). Reserved: not emitted on night 01.",
   vfx=[P("wind_gust", align="direction")], cooldown=0.2, sfx={"keys": ["gust_whoosh"]})
ev("world_lightning", "world (boss storm)", "", "Lightning strike flash (put it far away, toward the strike).",
   vfx=[P("lightning_flash")], shake=[0.1, 0.4], shake_falloff=False, cull_distance=400, sfx=None)
ev("world_debris", "world", "", "Generic rubble burst (falling ornaments, broken props). Reserved: not emitted on night 01.", vfx=[P("brick_debris", scale=0.6)],
   shake=[0.12, 0.2], sfx={"keys": ["crate_break"], "pitch": [0.7, 0.8]})
ev("world_enter", "core or world", "world_id", "A world finished loading (Mak appears).", vfx=[P("respawn_sparkle")], sfx=None)

# ------------------------------------------------------------------ integration additions
group("Integration additions (names already emitted by the player, objects and enemy tracks)")
ev("player_brake", "player", "speed, direction", "Hard stop from a run (no reversal).", vfx=[P("skid_burst", align="yaw", scale=0.7)],
   cooldown=0.25, sfx={"keys": ["skid"], "volume_db": -4})
ev("player_crouch_slide", "player", "speed, direction", "Crouch slide from a run.", vfx=[P("skid_burst", align="yaw", scale=0.8)],
   cooldown=0.25, sfx={"keys": ["slide"]})
ev("player_ledge_climb", "player", "fast (bool)", "Pull-up from a ledge hang.", vfx=[P("ledge_dust", offset=[0, 0.05, 0])],
   sfx={"keys": ["ledge_grab"], "pitch": [1.05, 1.15]})
ev("player_stomp", "player", "kind (stomp|slam), node", "Mak bounces off an enemy's head (pair with the enemy's own event).",
   vfx=[P("hit_spark", offset=[0, 0.1, 0], scale=1.2, toward_camera=0.5), S("DustPuff", scale=0.7)], shake=[0.1, 0.1], hitstop_ms=35, rumble=[0.3, 0.2, 0.08],
   sfx={"keys": ["enemy_hit", "enemy_hit_2"], "pitch": [1.1, 1.2]})
ev("player_death", "player", "", "Cake ran out (before the respawn).", vfx=[S("Poof", scale=1.5), P("hurt_burst", offset=[0, 0.8, 0], scale=1.3),
                                                                           P("page_flutter", offset=[0, 0.8, 0], delay=1.1)],
   shake=[0.3, 0.4], hitstop_ms=120, rumble=[0.7, 0.7, 0.4], sfx={"keys": ["vo_mak_blast"]})
ev("player_sniff_found", "player", "target", "Snout Sniff locks onto a hidden truffle.", vfx=[P("glint_burst")],
   sfx={"keys": ["sniff"], "pitch": [1.25, 1.3]})
ev("player_hat_change", "player", "hat", "Hat swapped (pause menu): a magician's poof on Mak's head.",
   vfx=[P("hat_poof", offset=[0, 1.25, 0], pause_proof=True, priority=3)], sfx={"keys": ["cloud_puff"], "pitch": [1.2, 1.3]})
ev("player_bonk", "player", "normal (wall normal), impact (m/s into the wall)",
   "Mak runs or dives face-first into a wall and bounces back (the bonk state). Stars and a dust slap on the wall.",
   vfx=[P("hit_stars", offset=[0, 0.2, 0], scale=0.8), P("wall_kick_burst", align="normal", scale=0.6)],
   scale_by={"param": "impact", "in": [3.0, 12.0], "out": [0.8, 1.25]}, shake=[0.18, 0.2], hitstop_ms=40, rumble=[0.4, 0.3, 0.12],
   cooldown=0.2, sfx={"keys": ["bonk"]})
ev("object_crate_land", "objects", "impact (drop height m)", "A pushed or knocked crate lands after a drop.",
   vfx=[S("DustPuff", scale=1.1)], scale_by={"param": "impact", "in": [0.5, 4.0], "out": [0.7, 1.4]}, shake=[0.08, 0.12],
   cooldown=0.15, sfx={"keys": ["land_heavy"], "pitch": [0.9, 1.0], "volume_db": -3})
ev("player_sniff_air", "player", "node, direction", "Idle animation beat: Mak sniffs the air (MakAnimator sniff_air). A tiny snout puff.",
   vfx=[P("sniff_puff", offset=[0, 0.8, -0.32], align="yaw", scale=0.45, tint="#e6e0d6")], cooldown=1.0, sfx={"keys": ["sniff"], "pitch": [0.9, 0.95], "volume_db": -6})
ev("object_acorn_magnet", "objects", "", "Acorns start homing to Mak.", vfx=[P("glint_burst", scale=0.5)], cooldown=0.15, sfx=None)
ev("object_truffle_burst", "objects", "id", "Truffle bursts out on collection (objects' own moment; the celebration is object_truffle_collect).",
   vfx=[P("truffle_appear", scale=0.6)], sfx=None)
ev("object_cage_lamp", "objects", "lit, needed", "One of the cage's switch lamps lights.", vfx=[P("switch_press", scale=0.6)],
   sfx={"keys": ["switch_press"], "pitch": [1.3, 1.4], "volume_db": -4})
ev("object_cage_rattle", "objects", "", "Mak bumps the locked cage.", vfx=[P("clang", scale=0.8)], cooldown=0.4,
   sfx={"keys": ["enemy_hit_3"], "pitch": [1.5, 1.6], "volume_db": -6})
ev("object_cage_vanish", "objects", "", "The cage poofs away.", vfx=[S("Poof", scale=1.6), P("glint_burst")], sfx={"keys": ["cloud_puff"]})
ev("object_dig_splash", "objects", "", "Mud splat while digging.", vfx=[P("dig_burst", scale=0.7)], sfx={"keys": ["splash"], "pitch": [0.7, 0.8]})
ev("object_door_locked", "objects", "need", "Locked door knocked (not enough truffles).", vfx=[P("clang", scale=0.7), P("clang", scale=0.5, delay=0.2)], cooldown=0.5,
   sfx={"keys": ["enemy_hit_3"], "pitch": [0.8, 0.85]})
ev("object_door_open", "objects", "target", "A door swings open.", vfx=[P("door_unlock", scale=0.8)], shake=[0.12, 0.3], sfx={"keys": ["door_unlock"]})
ev("object_door_thud", "objects", "", "The door hits its stop.", vfx=[P("land_heavy", scale=0.8)], shake=[0.15, 0.2], sfx={"keys": ["land_heavy"]})
ev("object_hazard_touch", "objects", "look", "Mak touches a damaging volume (not hot chocolate).", vfx=[P("hazard_burst")], cooldown=0.3,
   sfx=None)
ev("object_kill_zone", "objects", "", "Mak falls into a kill zone (no effect; the player emits player_fall_out).", vfx=[], sfx=None)
ev("object_npc_greet", "objects", "speaker", "An NPC notices Mak.", vfx=[P("notice_pop", scale=1.0, near_clamp=4.0)], cooldown=1.0, sfx=None)
ev("object_npc_talk", "objects", "speaker", "Dialogue opens with an NPC.", vfx=[], sfx=None)
ev("object_sign_read", "objects", "", "A sign is read.", vfx=[], sfx=None)
ev("object_platform_wobble", "objects", "", "A falling platform starts to wobble.", vfx=[P("footstep_dust", scale=1.6)], cooldown=0.3, sfx=None)
ev("object_portal_locked", "objects", "world", "A locked storybook is touched.", vfx=[P("clang", scale=0.8)], cooldown=0.6, sfx=None)
ev("object_portal_page_turn", "objects", "world", "A page flips on an open storybook (idle flourish).", vfx=[P("glint_burst", scale=0.4)],
   cooldown=0.1, sfx=None)

# ------------------------------------------------------------------ ui
group("UI (emitted by game/scripts/ui/; sound only, no position)")
for n, key, doc in [("ui_move", "ui_move", "Cursor moves."), ("ui_select", "ui_select", "Confirm."), ("ui_back", "ui_back", "Back or cancel."),
                    ("ui_page_turn", "ui_page_turn", "Storybook page turn (mission select, transitions)."),
                    ("ui_pause", "ui_page_turn", "Pause menu opens."), ("ui_unpause", "ui_back", "Pause menu closes."),
                    ("ui_truffle_get", "jingle_truffle_get", "TRUFFLE GET! banner appears."),
                    ("ui_mission_banner", "page_turn", "Mission name banner slides in.")]:
    ev(n, "ui", "", doc, vfx=[], sfx={"keys": [key], "positional": False})

ALIASES = {
    "player_jump": "player_jump_1",
    "player_jump_single": "player_jump_1", "player_jump_double": "player_jump_2", "player_jump_triple": "player_jump_3",
    "player_jump_long": "player_long_jump", "player_jump_backflip": "player_backflip", "player_jump_side_flip": "player_side_flip",
    "player_jump_side": "player_side_flip", "player_jump_wall": "player_wall_kick", "player_ground_pound": "player_ham_slam",
    "player_attack_punch": "player_punch", "player_attack_kick": "player_kick", "player_attack_jump_kick": "player_jump_kick",
    "player_attack_dive": "player_dive", "player_damaged": "player_hurt", "object_truffle": "object_truffle_collect",
    "object_acorn": "object_acorn_collect", "enemy_hit": "enemy_hurt", "enemy_die": "enemy_defeat", "boss_damage": "boss_hit",
}

out = {
    "_about": "Juice VFX table (juice track). Generated by game/scripts/fx/tools/juice_catalogue.py; edit that file, then re-run. "
              "Schema and event catalogue: Docs/JUICE.md. Sounds: res://assets/audio/juice_sfx.json (audio track); `sfx` here is a fallback.",
    "version": 1,
    "defaults": {"cull_distance": 70.0},
    "aliases": ALIASES,
    "events": {},
}
for name, e in E.items():
    rec = dict(e)
    if rec.get("sfx") is None:
        rec.pop("sfx", None)
    out["events"][name] = rec
(FX / "juice_vfx.json").write_text(json.dumps(out, indent=1), encoding="utf-8")


def fx_names(e):
    names = []
    for v in e.get("vfx", []):
        n = v.get("preset") or v.get("scene")
        extra = []
        if v.get("attach"):
            extra.append("attached")
        if v.get("loop"):
            extra.append("loop '%s'" % v["loop"])
        if v.get("align", "none") != "none":
            extra.append("align " + v["align"])
        names.append(n + (" (" + ", ".join(extra) + ")" if extra else ""))
    if e.get("tiers"):
        names.append("tiers by " + e["tiers"]["param"])
    if e.get("by_param"):
        names.append("varies by " + e["by_param"]["param"])
    if e.get("stop_loop"):
        names.append("stops loop '%s'" % e["stop_loop"])
    return ", ".join(names) or "none (sound only)"


def feel(e):
    bits = []
    if e.get("shake"):
        bits.append("shake %.2f/%.2fs" % tuple(e["shake"]))
    if e.get("hitstop_ms"):
        bits.append("hitstop %d ms" % e["hitstop_ms"])
    if e.get("rumble"):
        bits.append("rumble")
    if e.get("fov"):
        bits.append("FOV %+.1f deg" % e["fov"][0])
    return ", ".join(bits) or "-"


lines = []
for title, names in GROUPS:
    lines.append("### " + title)
    lines.append("")
    lines.append("| Event | Params | When | VFX | Feel |")
    lines.append("| --- | --- | --- | --- | --- |")
    for n in names:
        e = E[n]
        lines.append("| `%s` | %s | %s | %s | %s |" % (n, e["params"] or "-", e["doc"], fx_names(e), feel(e)))
    lines.append("")
lines.append("Aliases (accepted, resolved to the canonical name): " + ", ".join("`%s` -> `%s`" % kv for kv in ALIASES.items()) + ".")
md = "\n".join(lines) + "\n"
(HERE / "juice_events.md").write_text(md, encoding="utf-8")

doc = ENTITY / "Docs" / "JUICE.md"
if doc.exists():
    t = doc.read_text(encoding="utf-8")
    a, b = "<!-- EVENTS:BEGIN -->", "<!-- EVENTS:END -->"
    if a in t and b in t:
        t = re.sub(re.escape(a) + ".*?" + re.escape(b), lambda _m: a + "\n\n" + md + "\n" + b, t, flags=re.S)
        doc.write_text(t, encoding="utf-8")
print("events:", len(E), "aliases:", len(ALIASES))

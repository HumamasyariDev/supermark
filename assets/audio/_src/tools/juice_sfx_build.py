"""Write game/assets/audio/juice_sfx.json: the sound side of every Juice event (Docs/JUICE.md) plus the names the player,
objects and UI scripts emit today. Edit this file, not the JSON. Usage: python juice_sfx_build.py

Event fields (read by juice_sfx.gd):
  layers: [{key, fallback[], delay, delay_jitter, chance, volume_db, volume_jitter_db, pitch, pitch_jitter, cooldown,
            cooldown_id, voice, priority, gap, loop_id, max_time, fade_in, attenuation, positional, volume_by, pitch_by}]
  cases: [{when: {param: value | [op, value]}, ...overrides}]   first match replaces fields (usually layers)
  cooldown (s, per event; cooldown_scope = a param name to keep separate cooldowns, e.g. family)
  max_per_second, positional, attenuation, chain {window, semitones, max_steps}, stop [loop ids], handoff
Keys may hold {param} templates (footstep_{surface}); fallback keys are tried in order when a key is missing.
handoff "owns" (unused since the fix stage): JuiceSfx stays silent for such an event until Juice exposes owns(). The boss
dropped it in the fix stage (critique r1 blocker): wolf_boss.gd asks Juice.handles(event, "sfx") per moment and skips its
own sound, and the table leaves out what the wolf still plays itself (its voice lines, the charge growl).
Fix-stage fields: skip_if_lethal (Game.health <= 0: the death event owns the moment), skip_after_scene (s after a scene
change), duck_music {db, attack, hold, release}, music {stop, after_jingles}, bed_phase_param / bed_phase_set (boss bed),
allow_stack (layer may start twice within defaults.same_key_gap). "states", "proximity" and "ambience.worlds" are
polled by juice_sfx.gd (see the README).
The player has no handoff any more: mak_player.gd `_fb()` skips its own sound whenever Juice.has_event() is true,
so without an entry here the player would only get juice_vfx.json's one-key fallback (night 01 implementation fix).
"""
import json
from pathlib import Path

AUD = Path(__file__).resolve().parents[2]


def L(key, **kw):
    d = {"key": key}
    d.update(kw)
    return d


def V(key, chance=1.0, cooldown=4.0, priority=1, delay=0.0, **kw):
    """Voice layer: Voice bus, priority queue, per-line cooldown."""
    d = {"key": key, "voice": True, "chance": chance, "cooldown": cooldown, "priority": priority}
    if delay:
        d["delay"] = delay
    d.update(kw)
    return d


FOOT = L("footstep_{surface}", fallback=["footstep_grass"], volume_jitter_db=1.5, pitch_jitter=0.07)
E = {}

# ------------------------------------------------------------------ player (2D: Mak is always mid-frame)
P = {"positional": False}


def player(name, layers=None, **kw):
    d = dict(P)
    if layers is not None:
        d["layers"] = layers
    d.update(kw)
    E[name] = d


player("player_footstep", [dict(FOOT, volume_by={"param": "speed", "range": [1.5, 7.5], "db": [-5.0, 0.0]})],
       cooldown=0.09, max_per_second=14)
JUMP_CASES = [
    {"when": {"kind": ["in", ["double_jump", "double", "2"]]},
     "layers": [L("jump_2", pitch_jitter=0.03), V("voice_mak_jump2", chance=0.45, cooldown=2.5)]},
    {"when": {"kind": ["in", ["triple_jump", "triple", "3"]]},
     "layers": [L("jump_3"), L("slam_spin", delay=0.12, volume_db=-6.0, pitch=1.15), V("voice_mak_jump3", chance=0.6, cooldown=3.0, priority=2)]},
    {"when": {"kind": ["in", ["long_jump", "long"]]},
     "layers": [L("long_jump"), L("swish", volume_db=-5.0, pitch=0.8), V("voice_mak_wahey", chance=0.25, cooldown=8.0)]},
    {"when": {"kind": "backflip"}, "layers": [L("backflip"), L("side_flip", delay=0.1, volume_db=-6.0), V("voice_mak_jump2", chance=0.35, cooldown=3.0)]},
    {"when": {"kind": ["in", ["side_flip", "side"]]}, "layers": [L("side_flip"), L("jump_2", volume_db=-6.0, pitch=1.1), V("voice_mak_jump3", chance=0.3, cooldown=3.0)]},
    {"when": {"kind": ["in", ["wall_kick", "wall"]]}, "layers": [L("wall_kick"), L("jump_2", volume_db=-4.0, pitch=1.08), V("voice_mak_jump1", chance=0.3, cooldown=2.0)]},
    {"when": {"kind": "pole_jump"}, "layers": [L("jump_2", pitch=1.05), L("climb_shimmy", volume_db=-4.0)]},
    {"when": {"kind": "rollout"}, "layers": [L("jump_1", pitch=1.08), L("roll", volume_db=-5.0)]},
    {"when": {"kind": "bounce"}, "silent": True},  # player_bounce plays it
]
player("player_jump", [L("jump_1", pitch_jitter=0.04), V("voice_mak_jump1", chance=0.2, cooldown=2.5)], cases=JUMP_CASES, cooldown=0.05)
for alias, kind in [("player_jump_1", "jump"), ("player_jump_2", "double_jump"), ("player_jump_3", "triple_jump"),
                    ("player_long_jump", "long_jump"), ("player_backflip", "backflip"), ("player_side_flip", "side_flip"),
                    ("player_wall_kick", "wall_kick")]:
    case = next((c for c in JUMP_CASES if c["when"].get("kind") == kind or (isinstance(c["when"].get("kind"), list) and kind in c["when"]["kind"][1])), None)
    player(alias, case["layers"] if case else E["player_jump"]["layers"], cooldown=0.05)
player("player_land", [dict(FOOT, volume_db=-3.0)], cooldown=0.06, cases=[
    {"when": {"heavy": True}, "layers": [L("land_heavy"), dict(FOOT, volume_db=2.0), L("slam_impact", volume_db=-8.0, pitch=1.2)]},
    {"when": {"impact": [">=", 12.0]}, "layers": [L("land_heavy", volume_db=-3.0), dict(FOOT, volume_db=2.0)]},
    {"when": {"impact": [">=", 7.0]}, "layers": [L("land", volume_db=-2.0), dict(FOOT, volume_db=1.0)]},
])
SLAM = [L("ham_slam"), L("slam_impact", volume_db=-3.0), dict(FOOT, volume_db=3.0)]
# r8: player_slam, player_attack, player_damaged, player_fallout, player_pole_grab, player_belly_slide, enemy_die and
# boss_damage were dead duplicates (nothing emits them; the player emits player_ham_slam, player_punch/kick, player_hurt,
# player_fall_out, player_climb_grab; enemies enemy_defeat; the boss boss_hit) and are gone
player("player_ham_slam", SLAM, cooldown=0.2)
# critique r1: the "Ham slam!" call peaks 0.73 s into the file, so it starts with the 0.5 s spin and lands on the impact
player("player_ham_slam_start", [L("slam_spin"), V("voice_mak_hamslam", chance=0.3, cooldown=8.0)], cooldown=0.2)
ATTACK_CASES = [
    {"when": {"kind": "kick"}, "layers": [L("spin_kick"), V("voice_mak_jump3", chance=0.2, cooldown=3.0)]},
    {"when": {"kind": "jump_kick"}, "layers": [L("jump_kick")]},
    {"when": {"kind": "dive"}, "layers": [L("dive"), V("voice_mak_wahey", chance=0.2, cooldown=6.0)]},
    {"when": {"kind": "slide"}, "layers": [L("slide")]},
    {"when": {"step": 2}, "layers": [L("swish", pitch=1.12)]},
]
player("player_punch", [L("swish")], cases=[{"when": {"combo": 2}, "layers": [L("swish", pitch=1.12)]}], cooldown=0.06)
player("player_kick", [L("spin_kick")], cooldown=0.06)
player("player_jump_kick", [L("jump_kick")], cooldown=0.06)
player("player_dive", [L("dive"), V("voice_mak_wahey", chance=0.2, cooldown=6.0)], cooldown=0.1)
player("player_hit", [L("punch"), L("enemy_hit", volume_db=-4.0)], cooldown=0.05, cases=[
    {"when": {"kind": ["in", ["kick", "jump_kick"]]}, "layers": [L("kick"), L("enemy_hit", volume_db=-4.0)]},
    {"when": {"kind": ["in", ["dive", "slide"]]}, "layers": [L("enemy_hit"), L("roll", volume_db=-6.0)]},
    {"when": {"kind": ["in", ["stomp", "slam"]]}, "layers": [L("enemy_hit"), L("gummy_boing", volume_db=-6.0, pitch=1.2)]},
])
player("player_stomp", [L("gummy_boing", pitch=1.25, volume_db=-3.0), L("enemy_hit")], cooldown=0.08,
       cases=[{"when": {"kind": "slam"}, "layers": [L("enemy_hit"), L("slam_impact", volume_db=-4.0)]}])
# critique r1: the HUD owns the cake-slice sound (ui_cake_lose / ui_cake_gain), so the player events no longer layer it;
# a lethal hit skips the hurt layers and the death event plays alone with a short music duck
player("player_hurt", [L("hurt"), V("voice_mak_hurt", chance=0.85, cooldown=1.2, priority=3)], cooldown=0.3, skip_if_lethal=True)
# r8: the "Blast!" line starts at 0.4 s with the fall (it used to land after the respawn sting at 1.1 s); a respawn
# or scene change cancels it if it is still pending (cancel_on, and every delayed layer is dropped on a scene change)
player("player_death", [L("death"), V("voice_mak_blast", delay=0.4, priority=4, cooldown=3.0, cancel_on=["player_respawn"])], cooldown=1.0,
       duck_music={"db": -14.0, "attack": 0.05, "hold": 1.4, "release": 1.2}, marks_death=True)
FALL = [L("fall_out"), V("voice_mak_whoa", chance=0.8, priority=3, cooldown=3.0)]
player("player_fall_out", FALL, cooldown=1.0)
player("player_respawn", [L("respawn")], cooldown=0.5, skip_after_scene=1.5)  # world entry places Mak with respawn()
player("player_bonk", [L("bonk"), L("land", volume_db=-6.0, pitch=0.9), V("voice_mak_oof", chance=0.7, cooldown=2.5, priority=2, delay=0.05)],
       cooldown=0.3)
player("player_skid", [L("skid", volume_jitter_db=1.0)], cooldown=0.3)
player("player_brake", [L("skid", volume_db=-5.0, pitch=1.1)], cooldown=0.4)
# critique r1: the loop stopped after 2.5 s (the W3 slide runs about 8 s). It now runs until player_slide_end or until
# the player leaves the slide states; juice_sfx.gd sets its pitch and volume from the slide speed ("states.slide")
# r8 (critique r1b major 4): per-surface slide loops (slide_loop_{grass,wood,candy,stone}); other surfaces map to the
# nearest one through surface_map; belly_slide_loop is the last fallback
SURF_MAP = {"carpet": "wood", "jelly": "candy", "metal": "stone", "cloud": "grass", "water": "grass", "cocoa": "candy", "sand": "stone"}
SLIDE_LOOP = dict(key="slide_loop_{surface}", fallback=["belly_slide_loop"], surface_map=SURF_MAP)
SLIDE = [L("slide"), dict(SLIDE_LOOP, loop_id="slide", max_time=20.0, fade_in=0.1, volume_db=-2.0)]
player("player_slide_start", SLIDE, cooldown=0.15)
player("player_slide_end", [], stop=["slide"], stop_fade=0.2)
player("player_slope_slide", [dict(SLIDE_LOOP, loop_id="slide", max_time=20.0, volume_db=-2.0)], cooldown=0.3)
# polled states (juice_sfx.gd _poll_player): climb steps while moving on a pole, a soft pulse at one slice of cake
player("player_climb_step", [L("climb_shimmy", volume_jitter_db=1.5, pitch_jitter=0.06)], cooldown=0.18)
player("player_low_health", [L("low_health", volume_db=-13.0, pitch_jitter=0.0)], cooldown=1.0)
player("player_crouch_slide", [L("slide", volume_db=-3.0, pitch=1.1)], cooldown=0.2)
player("player_ledge_grab", [L("ledge_grab"), L("pole_grab", volume_db=-6.0)], cooldown=0.15)
player("player_ledge_climb", [L("ledge_climb")], cooldown=0.2)
player("player_climb_grab", [L("pole_grab")], cooldown=0.15)
player("player_bounce", [L("gumdrop_bounce"), L("jump_2", volume_db=-6.0, pitch=1.15)], cooldown=0.12,
       volume_by={"param": "velocity", "range": [6.0, 20.0], "db": [-4.0, 1.0]})
player("player_sniff", [L("sniff"), V("voice_mak_sniff", chance=0.2, cooldown=25.0)], cooldown=0.6)
player("player_sniff_air", [L("sniff", volume_db=-3.0, pitch=1.05)], cooldown=0.6)
player("player_sniff_found", [L("sniff_found"), V("voice_mak_gotit", chance=0.5, cooldown=10.0, delay=0.4)], cooldown=1.0)
player("player_splash", [L("splash")], cooldown=0.25, cases=[{"when": {"liquid": "cocoa"}, "layers": [L("hot_splash")]}])
player("player_hat_change", [L("hat_on")], cooldown=1.0,
       cases=[{"when": {"hat": "top_hat"}, "layers": [L("hat_on"), V("voice_mak_tophat", delay=0.5, priority=3, cooldown=30.0)]}])
player("player_celebrate", [V("voice_mak_cheer", chance=1.0, delay=0.35, cooldown=4.0, priority=2)], cooldown=1.0)
E["player_heal"] = {"positional": False, "layers": [L("heal")], "cooldown": 0.15}

# ------------------------------------------------------------------ enemies (3D) and boss
FAM = ["woolly_wolf", "crow_bandit", "peapod_popper", "bumble_bruiser", "gingerbread_grenadier", "gummy_brute"]


def fam_cases(m):
    return [{"when": {"family": f}, "layers": ls} for f, ls in m.items()]


def enemy(name, base, m=None, **kw):
    # no handoff: the enemy code asks JuiceSfx.has_event() per moment (EnemyKit.juice_sfx_owns) and skips its own sound
    # when this table voices it. Family extras the enemy code always plays itself (costume rip, pea inhale, gummy boing,
    # caws, flaps, footfalls, bee buzz) are left out here so nothing doubles.
    d = {"attenuation": "default", "cooldown_scope": "family", "layers": base}
    if m:
        d["cases"] = fam_cases(m)
    d.update(kw)
    E[name] = d


enemy("enemy_notice", [L("enemy_notice")], {
    "woolly_wolf": [L("enemy_notice", volume_db=-4.0), L("wolf_cub_growl", delay=0.05)],
    "crow_bandit": [L("enemy_notice", volume_db=-4.0), L("crow_caw", delay=0.05)],
    "peapod_popper": [L("enemy_notice", volume_db=-4.0), L("pea_notice", delay=0.04)],
    "bumble_bruiser": [L("enemy_notice", volume_db=-4.0), L("bee_charge", delay=0.05, volume_db=-6.0, pitch=1.15)],
    "gingerbread_grenadier": [L("enemy_notice", volume_db=-4.0), L("gingerbread_notice", delay=0.04)],
    "gummy_brute": [L("enemy_notice", volume_db=-4.0), L("gummy_notice", delay=0.05)],
}, cooldown=1.5)
enemy("enemy_windup", [L("enemy_windup")], {
    "gingerbread_grenadier": [L("lance_ready")], "gummy_brute": [L("gummy_wobble"), L("enemy_windup", volume_db=-6.0)],
    "peapod_popper": [L("enemy_windup", volume_db=-8.0, pitch=1.2)], "crow_bandit": [L("crow_caw", pitch=1.1), L("enemy_windup", volume_db=-6.0)],
    "woolly_wolf": [L("wolf_cub_growl", pitch=1.1), L("enemy_windup", volume_db=-6.0)],
}, cooldown=0.5)
enemy("enemy_attack", [L("swish")], {
    "woolly_wolf": [L("wolf_charge")], "crow_bandit": [L("crow_dive")], "peapod_popper": [L("pea_pop")],
    "bumble_bruiser": [L("bee_charge")], "gingerbread_grenadier": [L("lance_thrust")], "gummy_brute": [L("gummy_jump")],
}, cooldown=0.3)
enemy("enemy_slam", [L("gummy_slam"), L("slam_impact", volume_db=-5.0, pitch=0.85)], attenuation="far", cooldown=0.3)
enemy("enemy_hurt", [L("enemy_hit")], {
    "woolly_wolf": [L("enemy_hit"), L("wolf_cub_yelp", delay=0.03)], "crow_bandit": [L("enemy_hit"), L("crow_hurt", delay=0.03)],
    "peapod_popper": [L("enemy_hit"), L("pea_notice", delay=0.03, pitch=1.2)], "bumble_bruiser": [L("enemy_hit"), L("bee_down", volume_db=-6.0)],
    "gingerbread_grenadier": [L("enemy_hit_metal"), L("gingerbread_crumble", volume_db=-5.0)],  # the metallic ring is theirs only
    "gummy_brute": [L("enemy_hit"), L("gummy_notice", delay=0.08, pitch=1.15, volume_db=-3.0)],
}, cooldown=0.08)
E["enemy_hit"] = dict(E["enemy_hurt"])
enemy("enemy_block", [L("enemy_block")], cooldown=0.1)
enemy("enemy_stunned", [L("enemy_bonk")], {"bumble_bruiser": [L("enemy_bonk"), L("bee_down", delay=0.15)]}, cooldown=0.5)
enemy("enemy_recover", [L("enemy_windup", volume_db=-8.0, pitch=1.2)], cooldown=0.5)
enemy("enemy_defeat", [L("enemy_defeat_poof")], {
    "woolly_wolf": [L("wolf_cub_yelp", delay=0.05), L("enemy_defeat_poof", delay=0.05, volume_db=-3.0)],
    "crow_bandit": [L("crow_hurt"), L("enemy_defeat_poof", delay=0.08), L("acorn_chain", delay=0.3, volume_db=-6.0)],
    "peapod_popper": [L("pop"), L("pea_splat", delay=0.06), L("enemy_defeat_poof", delay=0.08, volume_db=-3.0)],
    "bumble_bruiser": [L("bee_down"), L("enemy_defeat_poof", delay=0.5, volume_db=-3.0)],
    "gingerbread_grenadier": [L("gingerbread_crumble"), L("enemy_defeat_poof", delay=0.08, volume_db=-4.0)],
    "gummy_brute": [L("gummy_melt"), L("enemy_defeat_poof", delay=0.25, volume_db=-3.0)],
}, cooldown=0.1)
enemy("enemy_flee", [L("swish", pitch=0.85)], {"woolly_wolf": [L("wolf_cub_yelp", pitch=1.15), L("wolf_charge", delay=0.1, volume_db=-4.0)]}, cooldown=0.5)
enemy("enemy_projectile_fire", [L("pea_pop")], cooldown=0.06)
enemy("enemy_projectile_hit", [L("pea_splat")], cooldown=0.06)
enemy("pea_splat", [L("pea_splat")], cooldown=0.06)


def boss(name, layers, **kw):
    d = {"attenuation": "far", "layers": layers}
    d.update(kw)
    E[name] = d


# phase 1 is a dry sunset: no thunder until the storm rolls in (phase 2)
boss("boss_intro", [L("boss_growl"), L("drum_boom", delay=0.4, volume_db=-8.0)], cooldown=2.0)
boss("boss_inhale", [L("boss_inhale")], cooldown=0.8)
boss("boss_huff", [L("boss_huff_blast"), L("wolf_gust", delay=0.05, volume_db=-4.0)], cooldown=0.3)
boss("boss_winded", [V("voice_wolf_panting", priority=2, cooldown=6.0)], cooldown=2.0)
boss("boss_recover", [L("boss_growl", volume_db=-4.0)], cooldown=1.0)
boss("boss_charge_start", [L("boss_charge")], cooldown=0.5)  # the wolf plays its own growl when Juice owns the charge sound
boss("boss_footstep", [L("boss_stomp", volume_db=-9.0, pitch=1.1, pitch_jitter=0.08)], cooldown=0.12)
boss("boss_stomp", [L("boss_stomp"), L("roof_tiles", delay=0.12, chance=0.6, volume_db=-6.0)], cooldown=0.2)
boss("boss_chimney_smash", [L("chimney_smash"), L("boss_crash", volume_db=-2.0), L("roof_tiles", delay=0.3, volume_db=-4.0)], cooldown=0.5)
boss("boss_stuck", [L("enemy_bonk", pitch=0.7), L("boss_hurt", delay=0.2, volume_db=-3.0)], cooldown=1.0)
boss("boss_swipe", [L("swish", pitch=0.6, volume_db=2.0)], cooldown=0.2)
boss("boss_hit", [L("punch", pitch=0.7, volume_db=3.0), L("boss_hurt", delay=0.05)], cooldown=0.2,
     cases=[{"when": {"kind": "tail"}, "layers": [L("punch", pitch=0.7, volume_db=3.0), L("enemy_bonk", pitch=0.75, delay=0.04, volume_db=-4.0)]}])
# (the wolf speaks its tail line itself, so the table plays only the impact)
# phase change: growl, a drum stinger and thunder; the bed follows the phase (ambience.worlds.BOSS phases)
boss("boss_phase", [L("boss_growl", volume_db=2.0), L("drum_boom", delay=0.08, volume_db=-4.0), L("thunder", delay=0.25)], cooldown=2.0,
     bed_phase_param="phase")
boss("boss_tornado_spawn", [L("gust_whoosh"), L("boss_tornado_loop", loop_id="tornado", max_time=120.0, fade_in=0.8, attenuation="huge")], cooldown=1.0)
boss("boss_tornado_end", [L("gust_whoosh", pitch=0.8, volume_db=-4.0)], stop=["tornado"], stop_fade=1.0)
# the defeat: battle music fades, the storm calms (bed phase 4) and a calm cue follows the victory jingles
boss("boss_defeat", [L("boss_hurt", volume_db=2.0), L("boss_balloon", delay=0.6), L("hat_pop", delay=0.9)], cooldown=3.0,
     music={"stop": 2.0, "after_jingles": {"key": "music_hub_lively", "fade_s": 3.0, "min_s": 4.0, "max_s": 16.0}}, bed_phase_set=4,
     stop=["tornado"], stop_fade=2.0)

# ------------------------------------------------------------------ objects and pickups (3D; objects defer to Juice)
def obj(name, layers, **kw):
    d = {"attenuation": "default", "layers": layers}
    d.update(kw)
    E[name] = d


obj("object_acorn_collect", [L("acorn_collect", pitch_jitter=0.0)], attenuation="near", positional=False,
    chain={"window": 0.7, "semitones": 1.0, "max_steps": 10}, cooldown=0.03)
obj("object_acorn_magnet", [], silent=True)
obj("object_acorn_spill", [L("pop"), L("acorn_chain", delay=0.12, volume_db=-4.0)], cooldown=0.2)
obj("object_truffle_appear", [L("truffle_appear"), L("great_truffle_appear", delay=0.1, volume_db=-6.0)], attenuation="far", cooldown=1.0)
obj("object_truffle_burst", [L("sniff_found", volume_db=-3.0)], cooldown=0.5)
obj("object_truffle_collect", [L("truffle_get", delay=0.08, volume_db=-6.0)], positional=False, cooldown=1.0)  # under the jingle (critique r1)
obj("object_page_collect", [L("page_collect", pitch_jitter=0.0)], positional=False, pitch_by={"param": "index", "semitones": 2.0, "max": 1.6}, cooldown=0.2)
obj("object_pages_complete", [L("trial_success")], positional=False, cooldown=1.0)
obj("object_checkpoint", [L("checkpoint"), L("book_page_turn", delay=0.1, volume_db=-6.0)], cooldown=1.0)
obj("object_portal_enter", [L("book_enter"), V("voice_mak_tallyho", chance=0.7, delay=0.15, cooldown=20.0, priority=2)], positional=False, cooldown=1.0)
obj("object_portal_locked", [L("locked")], cooldown=0.8)
obj("object_portal_page_turn", [L("book_page_turn", volume_db=-7.0, pitch_jitter=0.06, chance=0.65, delay_jitter=0.8)], attenuation="near", cooldown=0.3)  # r1: jitter and skips break the clockwork period  # idle flourish; mix critique r2: too sharp and loud
obj("object_door_unlock", [L("door_unlock"), L("book_unlock", delay=0.15, volume_db=-4.0)], attenuation="far", cooldown=1.0)
obj("object_door_open", [L("door_open")], cooldown=0.8)
obj("object_door_locked", [L("knocker_rattle"), L("locked", delay=0.2, volume_db=-4.0)], cooldown=0.8)
obj("object_door_thud", [L("land_heavy", pitch=0.85)], cooldown=0.5)
obj("object_bounce_pad", [L("gummy_boing")], cooldown=0.1, volume_by={"param": "impact", "range": [8.0, 22.0], "db": [-3.0, 1.0]}, cases=[
    {"when": {"kind": "leaf"}, "layers": [L("leaf_boing"), L("leaf_creak", volume_db=-8.0)]},
    {"when": {"kind": "gumdrop"}, "layers": [L("gumdrop_bounce"), L("jelly_wobble", delay=0.05, volume_db=-6.0)]},
    {"when": {"kind": "drum"}, "layers": [L("bounce_drum")]},
])
obj("object_crate_break", [L("crate_break"), L("pop", delay=0.05, volume_db=-6.0)], cooldown=0.1)
obj("object_switch_press", [L("switch_press"), L("ui_confirm_big", delay=0.12, volume_db=-8.0)], cooldown=0.3)
obj("object_cage_open", [L("cage_open")], attenuation="far", cooldown=1.0)
obj("object_cage_rattle", [L("knocker_rattle", pitch=0.9)], cooldown=0.5)
obj("object_cage_lamp", [L("chime", volume_db=-4.0)], cooldown=0.3)
obj("object_cage_vanish", [L("cloud_puff")], cooldown=0.5)
obj("object_cloud_step", [L("cloud_squish")], attenuation="near", cooldown=0.15)
obj("object_cloud_vanish", [L("cloud_puff")], cooldown=0.15)
obj("object_cloud_return", [L("cloud_squish", pitch=1.2, volume_db=-6.0)], cooldown=0.15)
obj("object_platform_crumble", [L("platform_fall")], cooldown=0.3)
obj("object_platform_wobble", [L("platform_creak")], cooldown=0.4)
obj("object_bellows_blast", [L("bellows_pump"), L("gust_whoosh", delay=0.08, volume_db=-4.0)], cooldown=0.3)
obj("object_bellows_break", [L("bellows_break"), L("crate_break", volume_db=-4.0)], attenuation="far", cooldown=0.5)
obj("object_dig", [L("dig_out")], cooldown=0.3)
obj("object_dig_splash", [L("mud_splat")], cooldown=0.2)
obj("object_sniff_reveal", [L("sniff_found")], cooldown=0.5)
obj("object_ring_pass", [L("ring", pitch_jitter=0.0)], positional=False, pitch_by={"param": "index", "semitones": 1.0, "max": 1.9}, cooldown=0.05)
obj("object_trial_start", [L("trial_start")], positional=False, cooldown=1.0)
obj("object_trial_complete", [L("trial_success")], positional=False, cooldown=1.0)
obj("object_trial_fail", [L("trial_fail")], positional=False, cooldown=1.0)
obj("object_mission_complete", [L("trial_success")], positional=False, cooldown=1.0)
obj("object_kill_zone", [], silent=True)  # the player's own fall-out event plays the whistle
# NPC voices by speaker (round 6): a non-verbal greeting vocal per voice type plus a soft chime, and the talk blip
# pitched to the voice. Unknown speakers (Bramwell, signs, the telescope) keep the chime.
PIGLETS = ["Pip", "Cousin Pip", "Cousin Hazel", "Cousin Bertram", "Hazel", "Bertram"]
VOICE_OF = [(PIGLETS, "npc_greet_piglet", 1.25), (["Daisy"], "npc_greet_cow", 0.75), (["Jack"], "npc_greet_boy", 1.12),
            (["Mother Treacle"], "npc_greet_granny", 0.95), (["Bramwell"], None, 0.8)]
obj("object_npc_talk", [L("talk_blip", pitch_jitter=0.08)], cooldown=0.4,
    cases=[{"when": {"speaker": ["in", names]}, "layers": [L("talk_blip", pitch=pt, pitch_jitter=0.06)]} for names, _, pt in VOICE_OF])
obj("object_sign_read", [L("book_page_turn", volume_db=-3.0, pitch=1.1)], cooldown=0.5)
obj("object_hazard_touch", [L("hazard_hit"), L("hurt", volume_db=-8.0, pitch=1.15)], cooldown=0.4)
obj("object_crate_land", [L("land_heavy", volume_db=-4.0, pitch=1.15)], cooldown=0.15,
    volume_by={"param": "impact", "range": [0.5, 4.0], "db": [-8.0, 0.0]})
obj("object_npc_greet", [L("chime", volume_db=-8.0)], cooldown=2.0, cooldown_scope="speaker",
    cases=[{"when": {"speaker": ["in", names]}, "layers": [L(k, pitch_jitter=0.04, volume_jitter_db=1.0), L("chime", volume_db=-12.0, delay=0.05)]}
           for names, k, _ in VOICE_OF if k])

# ------------------------------------------------------------------ world
obj("world_splash", [L("splash")], cooldown=0.15)
obj("world_cocoa_splash", [L("hot_splash")], cooldown=0.15)
obj("world_cocoa_burn", [L("hazard_hit"), L("hot_splash", volume_db=-4.0)], cooldown=0.4)
obj("world_wind_gust", [L("gust_whoosh")], attenuation="far", cooldown=0.3)
obj("world_lightning", [L("thunder", delay=0.25, delay_jitter=0.9)], positional=False, cooldown=1.0)
obj("world_debris", [L("roof_tiles")], attenuation="far", cooldown=0.2)
obj("world_enter", [L("respawn", volume_db=-4.0)], positional=False, cooldown=1.0)

# ------------------------------------------------------------------ UI (2D). ui_fx.gd plays its own sounds and sets ui_sfx.
def ui(name, layers, **kw):
    d = {"positional": False, "layers": layers, "skip_if_param": "ui_sfx"}
    d.update(kw)
    E[name] = d


ui("ui_move", [L("ui_move", pitch_jitter=0.03)], cooldown=0.03)
ui("ui_select", [L("ui_select", pitch_jitter=0.02)], cooldown=0.05)
ui("ui_accept", [L("ui_select", pitch_jitter=0.02)], cooldown=0.05)
ui("ui_back", [L("ui_back", pitch_jitter=0.02)], cooldown=0.05)
ui("ui_page_turn", [L("book_page_turn")], cooldown=0.15)
ui("ui_pause", [L("ui_pause")], cooldown=0.2)
ui("ui_unpause", [L("ui_unpause")], cooldown=0.2)
ui("ui_resume", [L("ui_unpause")], cooldown=0.2)
ui("ui_truffle_get", [], silent=True)  # WorldRoot plays the truffle jingle
ui("ui_mission_banner", [L("book_page_turn", volume_db=-4.0)], cooldown=0.5)
ui("ui_text_blip", [L("ui_text_blip", pitch_jitter=0.12, volume_jitter_db=1.0, allow_stack=True)], cooldown=0.035, max_per_second=30)
# ui_fx.gd plays nothing for ui_cake_low (fired by the HUD at 2 slices or fewer), so this table voices it
E["ui_cake_low"] = {"positional": False, "layers": [L("low_health", volume_db=-6.0, pitch_jitter=0.0)], "cooldown": 2.0}

ALIASES = {
    "player_jump_single": "player_jump_1", "player_jump_double": "player_jump_2", "player_jump_triple": "player_jump_3",
    "player_jump_long": "player_long_jump", "player_jump_backflip": "player_backflip", "player_jump_side_flip": "player_side_flip",
    "player_jump_side": "player_side_flip", "player_jump_wall": "player_wall_kick", "player_ground_pound": "player_ham_slam",
    "player_attack_punch": "player_punch", "player_attack_kick": "player_kick", "player_attack_jump_kick": "player_jump_kick",
    "player_attack_dive": "player_dive", "object_truffle": "object_truffle_collect", "object_acorn": "object_acorn_collect",
}

# ------------------------------------------------------------------ area beds, polled states, proximity loops (fix stage r1)
# Bed layers: index level (-30 LUFS each) + volume_db here. Layer lengths are co-prime-ish (A 20.5 s, B 13.7-17.3 s, the old
# single loops 5.9-8 s), so the combined pattern does not come round for many minutes. Scatter: one-shots around the camera.
AMBIENCE = {
    "_about": "juice_sfx.gd plays the layered bed for the current WorldRoot.world_id when the world sets no ambience_key "
              "(or an old single loop listed in upgrade) on its own players, crossfades between worlds, holds it through scene "
              "swaps and checkpoint reloads, and fades it out when no world is left. BOSS layers carry per-phase dB "
              "(phase 1 sunset wind, 2 rain, 3 storm, 4 after the defeat).",
    "upgrade": ["amb_storm_loop", "amb_storm"],
    # r8: a sting under the page curl into the boss (the W3 -> boss swap had 1.5 s of flat silence); when the curl heads to
    # the title (or any non-world), the bed, scatter tails and proximity loops fade during the curl, not after arrival
    "curl_stings": {"BOSS": [{"key": "drum_roll", "volume_db": -10.0, "delay": 0.0}, {"key": "thunder", "volume_db": -12.0, "delay": 0.35},
                             {"key": "drum_boom", "volume_db": -6.0, "delay": 1.1}]},
    "poll_s": 0.25, "fade_s": 2.0, "crossfade_out_s": 1.2, "exit_fade_s": 1.5, "curl_fade_s": 0.9, "phase_fade_s": 3.0,
    "beds": {"HUB": "amb_hub", "W1": "amb_w1", "W2": "amb_w2", "W3": "amb_w3", "BOSS": "amb_boss"},  # single-file versions (tests, previews)
    "worlds": {
        # hub: fire up front, the clock far away (layer B is low-passed at 4 kHz and sits 8 dB lower than before), a page
        # turning now and then, a soft distant chime
        "HUB": {"layers": [{"key": "amb_hub_la", "volume_db": -1.0}, {"key": "amb_hub_lb", "volume_db": -17.0},
                           {"key": "amb_fire_loop", "volume_db": -12.0}],
                # r8: crackles come from the fireplace flames (hub_level.gd group hub_flame) when one is within 25 m
                "scatter": [{"keys": ["crackle"], "interval": [3.5, 9.0], "volume_db": -16.0, "distance": [6.0, 12.0], "height": 1.0, "pitch": [0.85, 1.1],
                             "anchor_group": "hub_flame", "max_anchor_distance": 25.0, "anchor_jitter": 0.6, "anchor_only": True},
                            {"keys": ["book_page_turn"], "interval": [16.0, 38.0], "volume_db": -20.0, "distance": [8.0, 16.0], "height": 2.0, "pitch": [0.8, 0.95]},
                            {"keys": ["bell"], "interval": [55.0, 110.0], "volume_db": -24.0, "distance": [18.0, 26.0], "height": 4.0, "pitch": [0.5, 0.52],
                             "anchor_group": "audio_anchor_clock", "max_anchor_distance": 60.0, "anchor_jitter": 0.3}]},
        "W1": {"layers": [{"key": "amb_w1_la", "volume_db": -1.5}, {"key": "amb_w1_lb", "volume_db": -5.0},
                          {"key": "amb_meadow_loop", "volume_db": -9.0}],
               "scatter": [{"keys": ["amb_bird"], "interval": [4.0, 11.0], "volume_db": -10.0, "distance": [15.0, 30.0], "height": 6.0, "pitch": [0.92, 1.1]}]},
        "W2": {"layers": [{"key": "amb_w2_la", "volume_db": -1.0}, {"key": "amb_w2_lb", "volume_db": -8.0},
                          {"key": "amb_sky_loop", "volume_db": -6.0}],
               "scatter": [{"keys": ["chime"], "interval": [7.0, 16.0], "volume_db": -20.0, "distance": [15.0, 28.0], "height": 3.0, "pitch": [1.3, 1.9]}]},
        "W3": {"layers": [{"key": "amb_w3_la", "volume_db": -2.0}, {"key": "amb_w3_lb", "volume_db": -6.0},
                          {"key": "hot_choc_bubble_loop", "volume_db": -14.0}, {"key": "amb_candy_forest_loop", "volume_db": -13.0}],
               # r8: plops come from Marker3D nodes in group audio_anchor_cocoa (requested from the W3 builder) once
               # they exist; until then the random placement stays
               "scatter": [{"keys": ["amb_plop"], "interval": [2.5, 7.0], "volume_db": -12.0, "distance": [10.0, 25.0], "height": 0.5, "pitch": [0.85, 1.15],
                            "anchor_group": "audio_anchor_cocoa", "max_anchor_distance": 35.0, "anchor_jitter": 2.5}]},
        "BOSS": {"start_phase": 1,
                 # r8: phases 1 and 4 now ride two procedural wind layers (19.7 s and 13.9 s); the old 5.65 s loop sits 8 dB under
                 "layers": [{"key": "amb_boss_wind_a", "volume_db": -1.0, "phases": [0.0, -2.0, -5.0, -1.0]},
                            {"key": "amb_boss_wind_b", "volume_db": -4.0, "phases": [0.0, 0.0, -3.0, -2.0]},
                            {"key": "amb_wind_loop", "volume_db": -8.0, "phases": [0.0, -3.0, -8.0, -4.0]},
                            {"key": "amb_sky_loop", "volume_db": -8.0, "phases": [0.0, -6.0, -60.0, 0.0]},
                            {"key": "amb_boss_la", "volume_db": -1.0, "phases": [-60.0, -7.0, 0.0, -60.0]},
                            {"key": "amb_boss_lb", "volume_db": -4.0, "phases": [-60.0, -12.0, 0.0, -60.0]}],
                 "scatter": [{"keys": ["thunder"], "interval": [14.0, 30.0], "volume_db": -14.0, "distance": [40.0, 70.0], "height": 25.0,
                              "unit_size": 40.0, "pitch": [0.8, 1.0], "phases": [3]}]},
    },
    # per-world space on the SFX and Voice buses (voice gets voice_scale of the wet level)
    "reverb": {
        "HUB": {"room_size": 0.55, "damping": 0.6, "wet": 0.18, "predelay_ms": 25.0, "hipass": 0.12, "voice_scale": 0.6},
        "W1": {"room_size": 0.25, "damping": 0.75, "wet": 0.06, "predelay_ms": 60.0, "predelay_feedback": 0.15, "hipass": 0.25, "voice_scale": 0.5},
        "W2": {"room_size": 0.2, "damping": 0.8, "wet": 0.04, "predelay_ms": 70.0, "predelay_feedback": 0.1, "hipass": 0.3, "voice_scale": 0.5},
        "W3": {"room_size": 0.3, "damping": 0.7, "wet": 0.07, "predelay_ms": 50.0, "predelay_feedback": 0.15, "hipass": 0.25, "voice_scale": 0.5},
        "BOSS": {"room_size": 0.22, "damping": 0.7, "wet": 0.05, "predelay_ms": 65.0, "predelay_feedback": 0.12, "hipass": 0.3, "voice_scale": 0.4},
    },
}
STATES = {
    "wall_slide": {"key": "wall_slide_loop", "states": ["wall_slide"], "speed_range": [0.5, 6.0], "db": [-12.0, 0.0], "pitch": [0.92, 1.08],
                   "volume_db": -1.0, "still_db": 8.0, "grace_s": 0.12},
    # r8: the loop follows the floor (slide_loop_{surface}, crossfaded when the surface changes mid-slide); the wider
    # pitch range moves the 6-14 Hz bump rate with speed (about 8-12 Hz at full speed)
    "slide": {"key": "slide_loop_{surface}", "fallback": ["belly_slide_loop"], "surface_map": SURF_MAP, "states": ["belly_slide", "slope_slide"],
              "speed_range": [2.0, 12.0], "db": [-7.0, 0.0], "pitch": [0.82, 1.22], "volume_db": -2.0, "still_db": 10.0, "grace_s": 0.25},
    "climb": {"event": "player_climb_step", "states": ["pole_climb"], "min_speed": 0.4, "interval": 0.34},
    "low_health": {"event": "player_low_health", "health_max": 1, "interval": 3.4, "first_delay": 1.5},
}
PROXIMITY = [
    {"group": "truffle", "key": "truffle_sparkle_loop", "radius": 12.0, "max": 2, "volume_db": -3.0, "attenuation": "near"},
    {"group": "wind_zone", "key": "gust_loop", "radius": 22.0, "max": 2, "volume_db": -4.0, "attenuation": "default", "worlds": ["W2", "HUB", "BOSS"]},
]

# every key referenced must exist in the audio index
idx = json.loads((AUD / "audio_index.json").read_text())
keys = {e["key"] for e in idx["entries"]}
missing = set()
for n, e in E.items():
    for ls in [e.get("layers", [])] + [c.get("layers", []) for c in e.get("cases", [])]:
        for l in ls:
            k = l["key"]
            if "{" in k:
                for s in ["grass", "wood", "stone", "candy", "carpet", "jelly", "metal", "cloud"]:
                    s2 = l.get("surface_map", {}).get(s, s)
                    if k.replace("{surface}", s2) not in keys:
                        missing.add(k.replace("{surface}", s2))
            elif k not in keys:
                missing.add(f"{n}:{k}")
assert not missing, sorted(missing)

out = {
    "_about": "Sound side of the Juice event bus (Docs/JUICE.md), played by res://assets/audio/juice_sfx.gd (installed by Juice). "
              "Generated by assets/audio/_src/tools/juice_sfx_build.py; edit that file. Keys resolve through audio_index.json.",
    "version": 1,
    "fallback_to_audio_keys": True,
    "defaults": {
        "cooldown": 0.03, "max_per_second": 12, "pitch_jitter": 0.05, "volume_jitter_db": 1.0, "voice_gap": 0.25,
        "same_key_gap": 0.06, "external_voice_priority": 4,
        "attenuation": {
            "near": {"unit_size": 8.0, "max_distance": 45.0, "filter_hz": 10000.0, "filter_db": -12.0},
            "default": {"unit_size": 6.0, "max_distance": 60.0, "filter_hz": 9000.0, "filter_db": -18.0},
            "far": {"unit_size": 12.0, "max_distance": 110.0, "filter_hz": 7000.0, "filter_db": -18.0},
            "huge": {"unit_size": 20.0, "max_distance": 160.0, "filter_hz": 6000.0, "filter_db": -20.0},
        },
    },
    "mix": {
        "music_duck_under_voice": {"sidechain": "Voice", "threshold_db": -28.0, "ratio": 3.0, "attack_us": 8000.0, "release_ms": 350.0},
        "master_limiter": {"ceiling_db": -0.5, "pre_gain_db": 0.0},
        "sfx_limiter": {"ceiling_db": -2.0},  # critique r1: the SFX bus peaked above 0 dBFS before the master limiter
        "pause": {"lowpass_hz": 900.0, "db": -6.0},
    },
    "states": STATES,
    "proximity": PROXIMITY,
    "ambience": AMBIENCE,
    "surface_world_default": {"HUB": "wood", "W3": "candy", "BOSS": "stone"},
    # r8 (QA minor): W2 cloud decks (bodies under CloudDecks) and VanishingCloud carry no surface meta and played grass
    "surface_name_hints": {"W2": [["cloud", "cloud"]]},
    "aliases": ALIASES,
    "events": E,
}
(AUD / "juice_sfx.json").write_text(json.dumps(out, indent=1), encoding="utf-8")
print(len(E), "events,", len(ALIASES), "aliases")

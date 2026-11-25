"""Write game/assets/audio/audio_index.json (format read by scripts/core/audio_manager.gd).

Night 01 M3 mix: every key's volume_db comes from measured loudness (_src/reports/loudness.json, ffmpeg ebur128):
  one-shots and voice: L100 (max 100 ms K-weighted loudness, short_loudness.py; ebur128's 400 ms momentary window
  underestimates sub-0.4 s sounds) + volume_db = the target of the key's mix group, capped so the peak stays <= -1 dBFS
  music, jingles, ambience: integrated loudness (I) + volume_db = the group target
Lists are random variants (the volume uses the mean of their loudness). Extra fields (group, att, M_after) are
ignored by the Audio autoload; juice_sfx.json and the README use them.
Run mix_analyze.py first. Usage: python make_index.py
"""
import json, re
from pathlib import Path

AUD = Path(__file__).resolve().parents[2]
LOUD = json.loads((AUD / "_src" / "reports" / "loudness.json").read_text())

# group: (measure, target, attenuation preset). Targets sit 4 dB under a -16 LUFS reference so level-matched files
# (L100 -16) need no positive gain; the whole game then mixes to roughly -20 LUFS with headroom for stacked impacts.
GROUPS = {
    "music": ("I", -24.0, None), "jingle": ("I", -19.0, None), "ambience": ("I", -30.0, None),
    "voice": ("L", -16.0, None), "impact": ("L", -15.0, "far"), "action": ("L", -19.0, "near"),
    "foley": ("L", -24.0, "near"), "footstep": ("L", -25.5, "near"), "pickup": ("L", -17.0, "near"),
    "reward": ("L", -15.0, "default"), "enemy": ("L", -18.0, "default"), "enemy_loop": ("I", -30.0, "default"),
    "boss": ("L", -15.0, "far"), "boss_voice": ("L", -15.0, "far"), "world": ("L", -19.0, "default"),
    "world_big": ("L", -17.0, "huge"), "loop": ("I", -29.0, "near"), "ui": ("L", -21.0, None),
    "ui_soft": ("L", -25.0, None), "ui_blip": ("L", -28.0, None),
}

GROUP_OF = {}
def grp(g, *keys):
    for k in keys:
        GROUP_OF[k] = g

grp("impact", "ham_slam", "land_heavy", "slam_impact", "crate_break", "bellows_break", "chimney_crash", "chimney_smash",
    "boss_crash", "boss_stomp", "boss_huff_blast", "wolf_gust", "drum_boom", "gummy_slam", "platform_fall", "roof_tiles", "glass_break")
grp("action", "jump_1", "jump_2", "jump_3", "long_jump", "backflip", "side_flip", "land", "punch", "kick", "swish", "spin_kick",
    "jump_kick", "dive", "slide", "wall_kick", "slam_spin", "roll", "hurt", "death", "respawn", "hat_on", "fall_out", "splash",
    "gust_whoosh", "cloud_puff", "leaf_bounce", "gumdrop_bounce", "bounce_drum", "leaf_boing", "jelly_wobble", "hot_splash",
    "cloud_squish", "hazard_hit", "pop", "mud_splat", "dig_out")
grp("foley", "ledge_grab", "ledge_climb", "pole_grab", "climb_shimmy", "crouch", "skid", "sniff", "platform_creak", "leaf_creak")
grp("pickup", "acorn_collect", "acorn_chain", "page_collect", "cake_slice_gained", "cake_slice_lost", "heal", "checkpoint",
    "low_health", "sniff_found", "ring", "switch_press")
grp("reward", "truffle_get", "truffle_appear", "great_truffle_appear", "trial_success", "trial_fail", "trial_start", "chest_open",
    "book_unlock", "book_enter", "door_unlock")
grp("enemy", "enemy_notice", "enemy_hit", "enemy_defeat_poof", "enemy_block", "enemy_bonk", "enemy_skid", "enemy_windup",
    "wolf_cub_baa", "wolf_cub_growl", "wolf_cub_yelp", "wolf_charge", "costume_rip", "crow_caw", "crow_swoop", "crow_dive",
    "crow_steal", "crow_hurt", "pea_pop", "pea_inhale", "pea_splat", "pea_notice", "bee_charge", "bee_down",
    "gingerbread_crumble", "gingerbread_march", "gingerbread_halt", "gingerbread_notice", "lance_ready", "lance_thrust",
    "gummy_wobble", "gummy_jump", "gummy_boing", "gummy_melt", "gummy_notice")
grp("enemy", "npc_greet_piglet", "npc_greet_cow", "npc_greet_boy", "npc_greet_granny")  # round 6
grp("impact", "door_slam")  # round 6b
grp("action", "seed_whoosh")
grp("enemy", "enemy_flap")
grp("enemy", "enemy_hit_metal")  # fix stage r1: the metallic take, gingerbread only
grp("footstep", "enemy_step")  # fix stage r1: soft low-passed steps for enemies (was footstep_grass everywhere)
grp("enemy_loop", "bee_buzz_loop")
grp("enemy", "bee_buzz_once")  # r8: the W2 charge tell plays a one-shot (w2_life.gd calls the key "bee_buzz")
grp("boss", "boss_inhale", "boss_charge", "hat_pop", "boss_balloon", "thunder")
grp("boss_voice", "boss_hurt", "boss_growl")
grp("world", "bell", "chime", "crackle", "drum_roll", "gate_open", "goose_honk", "rope_snap", "valve", "cage_open", "door_open",
    "knocker_rattle", "locked", "bellows_pump", "book_open", "book_page_turn")
grp("world_big", "giant_inhale", "giant_sneeze", "giant_snore")
grp("loop", "truffle_sparkle_loop", "gust_loop", "hot_choc_bubble_loop", "wall_slide_loop", "belly_slide_loop", "boss_tornado_loop")
SLIDE_SURFACES = ["grass", "wood", "candy", "stone"]
grp("loop", *[f"slide_loop_{s}" for s in SLIDE_SURFACES])  # r8: per-surface belly-slide loops (juice_sfx.json states.slide)
grp("ui", "ui_select", "ui_confirm_big", "ui_pause", "ui_unpause", "ui_error")
grp("ui_soft", "ui_move", "ui_back")
grp("ui_blip", "ui_text_blip")
LOOPS = {"truffle_sparkle_loop", "gust_loop", "hot_choc_bubble_loop", "wall_slide_loop", "belly_slide_loop", "boss_tornado_loop"} | {f"slide_loop_{s}" for s in SLIDE_SURFACES}

E = {}
REPORT = []


def measure(files, how):
    fld = {"I": "I", "M": "M_max", "L": "L100"}[how]
    vals = [LOUD[f][fld] for f in files if f in LOUD and LOUD[f].get(fld) is not None]
    vals = [v for v in vals if v > -70]
    return sum(vals) / len(vals) if vals else None


def add(key, files, bus, group, loop=False, aliases=(), trim_db=0.0):
    files = files if isinstance(files, list) else [files]
    how, target, att = GROUPS[group]
    m = measure(files, how)
    tps = [LOUD[f]["tp"] for f in files if f in LOUD and LOUD[f].get("tp") is not None]
    cap = min(8.0, -1.0 - max(tps)) if tps else 8.0
    vol = 0.0 if m is None else max(-30.0, min(cap, target - m + trim_db))
    e = {"bus": bus, "volume_db": round(vol, 1), "loop": loop, "group": group}
    if att:
        e["att"] = att
    if len(files) > 1:
        e["files"] = files
    else:
        e["file"] = files[0]
    for k in (key, *aliases):
        assert k not in E, k
        E[k] = e
    REPORT.append((key, group, m, e["volume_db"], len(files)))


# ---------------------------------------------------------------- music and jingles
for key, f, al in [("music_title", "title_storybook_overture", ("title", "TITLE")), ("music_hub", "hub_grand_library", ("hub", "HUB")),
                   ("music_w1", "w1_huff_puff_hollow", ("w1", "W1")), ("music_w2", "w2_beanstalk_skyway", ("w2", "W2", "w2_beanstalk")),
                   ("music_w3", "w3_gingerbread_grove", ("w3", "W3")), ("music_boss", "boss_huffington", ("boss", "BOSS"))]:
    # fix stage r1: real play measured hub -24.4 LUFS and boss -17.7 LUFS (6.7 LU apart); trims pull both toward -20
    add(key, f"music/{f}.ogg", "Music", "music", True, al, trim_db={"music_hub": 2.0, "music_boss": -2.5}.get(key, 0.0))
add("music_hub_lively", "music/hub_lively.ogg", "Music", "music", True, ("hub_lively",))
add("music_victory", "music/victory.ogg", "Music", "jingle", False, ("victory", "jingle_victory"))
add("music_truffle_get", "music/truffle_get.ogg", "Music", "jingle", False, ("jingle_truffle_get", "truffle_jingle"))
add("music_menu_sting", "music/menu_sting.ogg", "Music", "jingle", False, ("menu_sting", "jingle_menu"))

# ---------------------------------------------------------------- sfx (stem + _N variants)
ALIAS = {"ui_select": ("ui_accept", "ui_confirm"), "seed_whoosh": ("sfx_seed_whoosh",), "ham_slam": ("ground_pound",),
         "truffle_get": ("sfx_truffle_get", "truffle_collect"), "enemy_defeat_poof": ("enemy_defeat",), "leaf_bounce": ("bounce_leaf",),
         "gumdrop_bounce": ("bounce_gumdrop", "bounce"), "acorn_collect": ("acorn", "acorn_pickup"), "enemy_bonk": ("bonk",),
         "wolf_cub_growl": ("wolf_growl",), "ui_text_blip": ("talk_blip",),
         # UI keys that game/scripts/ui/ui_fx.gd tries first
         "ui_unpause": ("ui_resume",), "hat_on": ("ui_hat_change",), "trial_fail": ("ui_timer_end",),
         "drum_boom": ("ui_boss_bar_show",), "acorn_chain": ("ui_truffle_count",),
         # names other scripts call (enemy kit, player, hub, W1)
         "land": ("enemy_land",), "enemy_hit": ("enemy_hurt",), "crow_steal": ("crow_cackle",), "hot_splash": ("splash_cocoa",),
         "ring": ("ring_pass",),
         # r8 (critique r1b major): keys world scripts call that had no entry (hub Book 1 pad, W2 cloud drop, W2 bee dart)
         "cloud_puff": ("cloud_poof",), "gust_whoosh": ("whoosh",), "chime": ("truffle_sparkle",), "platform_creak": ("crate_creak",), "book_page_turn": ("ui_page_turn", "page_turn", "ui_page_flip", "ui_book_close")}
SKIP_PREFIX = ("footstep_", "amb_", "ui_text_blip", "enemy_step", "bee_buzz")
stems = sorted(f.stem for f in (AUD / "sfx").glob("*.ogg"))
stemset = set(stems)
variants = {}
for st in stems:
    m = re.match(r"^(.*)_(\d+)$", st)
    if m and m.group(1) in stemset:
        variants.setdefault(m.group(1), []).append(st)
for k in stems:
    if k.startswith(SKIP_PREFIX):
        continue
    m = re.match(r"^(.*)_(\d+)$", k)
    if m and m.group(1) in stemset:
        add(k, f"sfx/{k}.ogg", "SFX", GROUP_OF.get(m.group(1), "world"))
        continue
    files = [f"sfx/{k}.ogg"] + [f"sfx/{v}.ogg" for v in variants.get(k, [])]
    if k not in GROUP_OF:
        print("WARN no group for", k)
    add(k, files, "SFX", GROUP_OF.get(k, "world"), k in LOOPS, ALIAS.get(k, ()))
add("ui_text_blip", sorted(f"sfx/{f.name}" for f in (AUD / "sfx").glob("ui_text_blip_*.ogg")), "SFX", "ui_blip", False, ALIAS["ui_text_blip"])

# footsteps: round-5b shaped single takes (r1..r4) plus the round-1 takes that have a clear transient
OLD_KEEP = {"wood": ["footstep_wood_2", "footstep_wood_4"], "stone": ["footstep_stone_2"], "candy": ["footstep_candy_1"]}
for surf in ["grass", "wood", "stone", "candy", "carpet", "jelly", "metal", "cloud"]:
    files = sorted(f"sfx/{f.name}" for f in (AUD / "sfx").glob(f"footstep_{surf}_r*.ogg")) + [f"sfx/{s}.ogg" for s in OLD_KEEP.get(surf, [])]
    add(f"footstep_{surf}", files, "SFX", "footstep", False, ("footstep",) if surf == "grass" else ())
for f in sorted((AUD / "sfx").glob("footstep_*_[0-9].ogg")):  # round-1 single keys kept for old callers
    add(f.stem, f"sfx/{f.name}", "SFX", "footstep")
# r8 (critique r1b major 1): w2_life.gd plays "bee_buzz" through Audio.play_sfx (a pool player at a fixed spot), so the
# key is the one-shot charge tell; the looping wing buzz (bumble_bruiser.gd loads the file directly) keeps bee_buzz_loop
add("bee_buzz", "sfx/bee_buzz_once.ogg", "SFX", "enemy", False, ("bee_buzz_once",))
add("bee_buzz_loop", "sfx/bee_buzz.ogg", "SFX", "enemy_loop", True)
add("enemy_step", sorted(f"sfx/{f.name}" for f in (AUD / "sfx").glob("enemy_step*.ogg")), "SFX", "footstep", False, (), trim_db=-3.0)

# ---------------------------------------------------------------- ambience
for k in ["amb_fire_loop", "amb_wind_loop", "amb_meadow_loop", "amb_stream_loop", "amb_sky_loop", "amb_storm_loop", "amb_candy_forest_loop"]:
    add(k, f"sfx/{k}.ogg", "Ambience", "ambience", True, (k.replace("_loop", ""),))
for area, al in [("hub", ("amb_HUB", "ambience_hub")), ("w1", ("amb_W1", "ambience_w1")), ("w2", ("amb_W2", "ambience_w2")),
                 ("w3", ("amb_W3", "ambience_w3")), ("boss", ("amb_BOSS", "ambience_boss"))]:
    add(f"amb_{area}", f"sfx/amb_{area}_bed.ogg", "Ambience", "ambience", True, (f"amb_{area}_bed",) + al)
    # fix stage r1: the bed's layers as separate loops with co-prime lengths (juice_sfx.gd plays and balances them)
    add(f"amb_{area}_la", f"sfx/amb_{area}_la.ogg", "Ambience", "ambience", True)
    add(f"amb_{area}_lb", f"sfx/amb_{area}_lb.ogg", "Ambience", "ambience", True)
# r8: procedural rooftop wind layers for boss phases 1 and 4 (co-prime 19.7 s and 13.9 s)
add("amb_boss_wind_a", "sfx/amb_boss_wind_a.ogg", "Ambience", "ambience", True)
add("amb_boss_wind_b", "sfx/amb_boss_wind_b.ogg", "Ambience", "ambience", True)
# scatter one-shots on the Ambience bus (juice_sfx.json ambience.scatter): W1 bird phrases, W3 chocolate plops
add("amb_bird", sorted(f"sfx/{f.name}" for f in (AUD / "sfx").glob("amb_bird*.ogg")), "Ambience", "world", False)
add("amb_plop", sorted(f"sfx/{f.name}" for f in (AUD / "sfx").glob("amb_plop*.ogg")), "Ambience", "world", False)

# ---------------------------------------------------------------- voice
mak = ["tallyho", "splendid", "jollygood", "righto", "jump1", "jump2", "jump3", "oof", "blast", "truffle", "sniff", "hamslam", "wahey",
       "cheerio", "ouch", "whoa", "tophat", "gotit"]
for k in mak:
    # fix stage r1: grunts were 4.2-4.4 dB under the voice target (trim -4); -2.5 keeps them under the lines but audible.
    # The triple-jump call has two offline takes (+1 / -0.8 semitones) besides the original.
    fl = [f"voice/mak_{k}.ogg"] + ([f"voice/mak_jump3{v}.ogg" for v in "bc"] if k == "jump3" else [])
    add(f"voice_mak_{k}", fl if len(fl) > 1 else fl[0], "Voice", "voice", False, (f"vo_mak_{k}",),
        trim_db=(-0.5 if k in ("jump1", "jump2") else -2.5) if k.startswith("jump") else (-2.0 if k in ("oof", "ouch", "whoa") else 0.0))
add("voice_mak_cheer", [f"voice/mak_{k}.ogg" for k in ["tallyho", "splendid", "jollygood", "righto", "wahey", "cheerio", "truffle"]], "Voice", "voice")  # r1: cheerio and truffle were unused
add("voice_mak_hurt", [f"voice/mak_{k}.ogg" for k in ["oof", "ouch"]], "Voice", "voice", trim_db=-2.0)
add("voice_mak_jump", [f"voice/mak_jump{i}.ogg" for i in (1, 2)], "Voice", "voice", trim_db=-2.5)
WOLF_AL = {"huffpuff": ("wolf_huff",), "littlepig": ("wolf_little_pig",), "laugh": ("wolf_laugh",), "curses": ("wolf_curses",),
           "panting": ("wolf_pant",)}
for k in ["littlepig", "huffpuff", "curses", "notlast", "laugh", "inhale", "panting", "tail", "blownaway", "delicious", "getback"]:
    add(f"voice_wolf_{k}", f"voice/wolf_{k}.ogg", "Voice", "voice", False, (f"vo_wolf_{k}",) + WOLF_AL.get(k, ()))
add("voice_butler_welcome", "voice/butler_welcome.ogg", "Voice", "voice", False, ("vo_butler_welcome",))
add("voice_butler_hint_wolf", "voice/butler_hint.ogg", "Voice", "voice", False, ("vo_butler_hint_wolf", "voice_butler_hint"))
for k, key in [("truffle", "voice_butler_truffle"), ("book2", "voice_butler_book2_needs3"), ("book3", "voice_butler_book3_needs7"),
               ("wolfdoor", "voice_butler_wolfdoor_needs12"), ("tea", "voice_butler_tea")]:
    add(key, f"voice/butler_{k}.ogg", "Voice", "voice", False, ("vo_" + key[6:],))

missing = [k for k, e in E.items() for f in (e.get("files") or [e.get("file")]) if not (AUD / f).exists()]
assert not missing, missing
idx = {"_about": "Super Mak 64 audio bank (night 01, audio workstream). Keys -> files relative to res://assets/audio/. Lists are random "
                 "variants. volume_db is the measured mix (make_index.py: ebur128 loudness to per-group targets). Extra fields: group "
                 "(mix group), att (3D attenuation preset in juice_sfx.json). Provenance: assets/audio/_src and Docs/LICENSES.md.",
       "version": 2, "entries": [{"key": k, **e} for k, e in E.items()]}
(AUD / "audio_index.json").write_text(json.dumps(idx, indent=1), encoding="utf-8")
(AUD / "_src" / "reports" / "mix_table.json").write_text(json.dumps(
    [{"key": k, "group": g, "measured": None if m is None else round(m, 2), "volume_db": v, "files": n} for k, g, m, v, n in REPORT], indent=1))
print(len(E), "keys,", len({f for e in E.values() for f in (e.get("files") or [e["file"]])}), "files")

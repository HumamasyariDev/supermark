"""Round 5 (M3 audio implementation): coverage for every key the gameplay scripts call, per-surface footsteps,
enemy and boss vocalisations, UI, and long two-layer ambience beds. Writes _src/jobs/round5_spec.json.
Endpoint: fal-ai/elevenlabs/sound-effects/v2 at $0.002 per second (fal pricing API, checked 2026-10-17T20:25Z).
Run: python _src/tools/gen_audio.py _src/jobs/round5_spec.json --workers 8
"""
import json
from pathlib import Path

SRC = Path(__file__).resolve().parents[1]
EP = "fal-ai/elevenlabs/sound-effects/v2"
PFX = "Cartoon video game sound effect, clean, isolated, no music, no voice: "
PFX_V = "Cartoon video game creature vocalisation, clean, isolated, no music, no words: "
PFX_A = "Game ambience recording, seamless, no music, no voice, no melody: "

# name: (prompt, seconds, takes, kind)  kind: s = sfx, v = vocal, a = ambience loop, l = sfx loop, q = sequence to slice
J = {
    # ---- footsteps: sequences, sliced into single steps by onset detection
    "seq_step_grass": ("a small cartoon piglet in little leather shoes walking briskly across soft grass, eight separate light footsteps with short gaps between them", 4.5, 1, "q"),
    "seq_step_wood": ("a small cartoon piglet in little leather shoes walking briskly across hollow wooden floorboards, eight separate light footsteps with short gaps between them", 4.5, 1, "q"),
    "seq_step_stone": ("a small cartoon piglet in little leather shoes walking briskly across stone cobbles, eight separate light footsteps with short gaps between them", 4.5, 1, "q"),
    "seq_step_candy": ("a small cartoon piglet walking briskly across crunchy hard candy and sugar crust, eight separate light crunchy footsteps with short gaps between them", 4.5, 1, "q"),
    "seq_step_carpet": ("a small cartoon piglet in little shoes walking briskly across a thick soft carpet rug, eight separate muffled soft footsteps with short gaps between them", 4.5, 1, "q"),
    "seq_step_jelly": ("a small cartoon piglet walking across wobbly jelly, eight separate squishy wet footsteps with short gaps between them", 4.5, 1, "q"),
    "seq_step_metal": ("a small cartoon piglet in little shoes walking briskly across a thin metal sheet, eight separate light clanky footsteps with short gaps between them", 4.5, 1, "q"),
    "seq_step_cloud": ("a small cartoon piglet walking across fluffy cotton clouds, eight separate soft pillowy puff footsteps with short gaps between them", 4.5, 1, "q"),
    "seq_ui_blip": ("eight very short soft wooden marimba blips at slightly different pitches, like dialogue text appearing, with short gaps between them", 3.0, 1, "q"),
    # ---- player actions
    "swish": ("a quick small swish of a little fist through the air", 0.5, 2, "s"),
    "spin_kick": ("a fast spinning kick, swirling whoosh ending in a light thwack", 0.7, 2, "s"),
    "jump_kick": ("a flying kick, airy whoosh with a light padded thwack", 0.6, 2, "s"),
    "side_flip": ("a quick sideways flip, curved whoosh with a light flutter of cloth", 0.7, 2, "s"),
    "slam_spin": ("a quick twirling midair flip, rising spin whoosh that stops suddenly", 0.6, 2, "s"),
    "ledge_climb": ("a small character clambers up onto a ledge, quick cloth rustle and a soft hand slap on stone", 0.6, 2, "s"),
    "pole_grab": ("small hands grab a wooden pole firmly, a soft grippy thump", 0.5, 2, "s"),
    "climb_shimmy": ("small hands shimmy up a leafy vine, short leafy rustle and grip", 0.5, 2, "s"),
    "wall_slide_loop": ("continuous cloth friction sliding down a rough wall, steady scraping rustle", 3.0, 1, "l"),
    "belly_slide_loop": ("continuous sliding on a belly across grass, steady soft swish and rustle", 3.0, 1, "l"),
    "roll": ("a quick tumbling forward roll on grass, soft thuds and rustle", 0.6, 2, "s"),
    "crouch": ("a short soft cloth rustle as a small character crouches", 0.5, 1, "s"),
    "respawn": ("a magical poof as a small character reappears, soft puff with fluttering paper pages and a tiny sparkle", 1.2, 2, "s"),
    "death": ("a cartoon dizzy faint, descending slide whistle then a soft thud", 1.6, 1, "s"),
    "hat_on": ("a dapper top hat pops onto a head with a soft cork pop and a bright sparkle", 0.9, 1, "s"),
    "slam_impact": ("a heavy cartoon belly flop ground pound, deep punchy thump with a dusty crumble", 0.8, 2, "s"),
    # ---- enemies
    "enemy_block": ("a hit is blocked by a hard candy shield, hollow clonk with a sugary clink", 0.5, 2, "s"),
    "enemy_bonk": ("a cartoon creature bumps its head into a wall, comic bonk with a tiny dizzy tweet", 0.8, 2, "s"),
    "enemy_skid": ("a small creature skids to a stop on dirt, short scraping slide", 0.7, 2, "s"),
    "enemy_windup": ("a cartoon wind-up before an attack, short rising stretchy creak", 0.6, 2, "s"),
    "wolf_cub_growl": ("a small cartoon wolf pup gives a playful little growl", 0.9, 2, "v"),
    "wolf_cub_yelp": ("a small cartoon wolf pup yelps in surprise, short high yip", 0.6, 2, "v"),
    "wolf_charge": ("claws scrabbling on grass and a quick rushing whoosh as a small animal charges", 0.9, 2, "s"),
    "costume_rip": ("woolly fabric tearing apart quickly, comic rip with a puff of fluff", 0.8, 2, "s"),
    "crow_dive": ("a crow folds its wings and dives fast, two wing flaps then a sharp descending whoosh", 0.9, 2, "s"),
    "crow_steal": ("a cheeky crow snatches something with a quick cackling caw and a little coin jingle", 1.0, 2, "v"),
    "crow_hurt": ("a crow squawks in surprise and pain with ruffled feathers", 0.6, 2, "v"),
    "pea_inhale": ("a plant pod sucks in air, comic rising inhale with a leafy rustle", 0.7, 2, "s"),
    "pea_splat": ("a small soft pea splats on the ground, tiny wet comic splat", 0.5, 2, "s"),
    "pea_notice": ("a leafy plant pod springs up alert, quick leafy rustle and a squeaky pop", 0.6, 2, "v"),
    "bee_charge": ("an angry bumblebee revs up and zooms forward, rising buzz into a whoosh", 1.0, 2, "s"),
    "bee_down": ("a dazed bumblebee, buzzing winds down, soft bonk and a little fall", 1.2, 2, "s"),
    "gingerbread_march": ("one crisp crunchy step of a tiny gingerbread toy soldier with a tiny drum tap", 0.5, 2, "s"),
    "gingerbread_halt": ("a tiny toy whistle blast and a crisp heel click", 0.6, 2, "s"),
    "gingerbread_notice": ("a tiny toy trumpet plays a quick two-note alarm", 0.6, 2, "s"),
    "lance_ready": ("a candy cane lance swings into position, short swish and a sugary clink", 0.6, 2, "s"),
    "lance_thrust": ("a quick forward thrust swish with a crunchy jab", 0.5, 2, "s"),
    "gummy_jump": ("a big rubbery gummy creature jumps, stretchy wobbling boing", 0.8, 2, "s"),
    "gummy_slam": ("a heavy gelatin body slams the ground, deep wet thud with a wobble", 1.0, 2, "s"),
    "gummy_boing": ("a springy rubber trampoline boing, bright and bouncy", 0.6, 2, "s"),
    "gummy_melt": ("a gummy candy melts into goo, squelchy gloop that descends in pitch", 1.2, 1, "s"),
    "gummy_notice": ("a big jelly monster gives a deep gloopy grunt", 0.8, 2, "v"),
    # ---- boss
    "boss_crash": ("a huge wolf crashes into a brick chimney, heavy impact with bricks tumbling down", 1.6, 2, "s"),
    "chimney_smash": ("a brick chimney bursts apart, bricks clattering and dust", 1.8, 1, "s"),
    "wolf_gust": ("a powerful blast of breath, roaring gust of wind from huge lungs", 1.6, 1, "s"),
    "boss_hurt": ("a big cartoon wolf yelps in comic pain, a deep owowow howl", 1.1, 2, "v"),
    "boss_growl": ("a big cartoon villain wolf gives a menacing rumbling growl", 1.4, 2, "v"),
    "boss_tornado_loop": ("a swirling tornado of wind, whirling roar with flapping debris", 6.0, 1, "l"),
    "hat_pop": ("a top hat shoots off a head with a loud cork pop and a whistling spin", 0.9, 1, "s"),
    "boss_balloon": ("a balloon inflates rapidly then flies away with a long squeaky deflating whistle", 2.5, 1, "s"),
    "roof_tiles": ("clay roof tiles clatter and slide, a few tiles falling", 1.2, 2, "s"),
    "great_truffle_appear": ("a magical golden reveal, rising harp glissando with sparkles and a bright shimmering swell", 2.5, 1, "s"),
    "thunder": ("a distant rolling thunder clap", 3.0, 2, "s"),
    # ---- objects and worlds
    "bell": ("a small brass bell rings once, clear ding", 1.2, 1, "s"),
    "chest_open": ("a wooden treasure chest creaks open with a magical sparkle", 1.5, 1, "s"),
    "chime": ("a gentle wind chime tinkle", 1.5, 1, "s"),
    "crackle": ("a candle flame flares up with a crackle and a soft whoomph", 1.0, 1, "s"),
    "drum_boom": ("a big festive bass drum boom", 1.0, 1, "s"),
    "drum_roll": ("a snare drum roll building up", 2.0, 1, "s"),
    "gate_open": ("a gingerbread gate creaks open, crunchy wooden creak", 1.2, 1, "s"),
    "giant_inhale": ("a sleeping giant takes a huge deep rumbling inhale", 2.0, 1, "v"),
    "giant_sneeze": ("a giant's enormous comic sneeze", 2.0, 1, "v"),
    "giant_snore": ("a sleeping giant's deep rumbling snore with a whistle on the out-breath", 3.0, 1, "v"),
    "glass_break": ("sugar glass shattering, bright tinkly crash", 1.0, 2, "s"),
    "goose_honk": ("a goose honks twice", 0.8, 2, "v"),
    "hot_splash": ("a splash into thick hot chocolate, gloopy plop with a sizzle", 0.9, 2, "s"),
    "jelly_wobble": ("a big jelly wobbling, squishy boing wobble", 0.8, 2, "s"),
    "leaf_boing": ("a giant leaf springs like a trampoline, bouncy boing with leafy rustle", 0.7, 2, "s"),
    "leaf_creak": ("a giant beanstalk leaf bends with a fibrous creak", 1.0, 1, "s"),
    "pop": ("a comic cork pop", 0.5, 2, "s"),
    "rope_snap": ("a rope snaps with a whip crack", 0.6, 1, "s"),
    "valve": ("a squeaky metal valve wheel turns then a short steam hiss", 1.2, 1, "s"),
    "cage_open": ("a metal cage rattles and lifts away, clanky chains", 1.2, 1, "s"),
    "dig_out": ("digging in soft earth, a quick scoop and dirt spray", 0.8, 1, "s"),
    "mud_splat": ("a wet mud splat", 0.5, 1, "s"),
    "platform_creak": ("a wooden platform creaks and wobbles under weight", 1.0, 1, "s"),
    "platform_fall": ("a wooden platform drops away with a creak and a falling whoosh", 1.2, 1, "s"),
    "ring": ("a bright magical chime as you fly through a hoop", 0.8, 1, "s"),
    "trial_start": ("a quick race start whistle", 0.8, 1, "s"),
    "trial_success": ("a happy bright success chime, ascending bells", 1.5, 1, "s"),
    "trial_fail": ("a sad comic deflating trombone wah-wah", 1.5, 1, "s"),
    "sniff_found": ("a magical discovery, twinkly rising chime", 1.0, 1, "s"),
    "cloud_squish": ("a soft fluffy cloud squish, pillowy puff", 0.5, 2, "s"),
    "door_open": ("a heavy ornate wooden door swings open with a long creak", 1.5, 1, "s"),
    "knocker_rattle": ("a brass door knocker rattles on a locked door", 0.7, 1, "s"),
    "locked": ("a locked door handle jiggles, denied clunk", 0.6, 1, "s"),
    "book_enter": ("a magical whoosh into a storybook, fluttering pages and sparkle", 1.5, 1, "s"),
    "book_unlock": ("a magical book clasp clicks open with a glowing chime", 1.2, 1, "s"),
    "truffle_appear": ("a magical golden item appears, sparkling rising shimmer", 1.5, 1, "s"),
    "hazard_hit": ("a quick hot sizzle burn, comic", 0.6, 1, "s"),
    "fall_out": ("a long cartoon falling whistle, descending", 1.3, 1, "s"),
    "bounce_drum": ("a big drum skin bounce, deep boom with a boing", 0.7, 1, "s"),
    "acorn_chain": ("a bright little pickup chime, wooden acorn tick with a sparkle", 0.5, 2, "s"),
    "heal": ("a warm soft healing chime with a gentle sparkle", 0.9, 1, "s"),
    "low_health": ("a soft muted heartbeat double thump, warning", 1.0, 1, "s"),
    # ---- UI
    "ui_pause": ("a storybook closes gently with a soft thump and a quiet chime", 0.8, 1, "s"),
    "ui_unpause": ("a storybook opens with a quick page flutter", 0.7, 1, "s"),
    "ui_error": ("a soft wooden tok tok, denied", 0.5, 1, "s"),
    "ui_confirm_big": ("a magical sparkle confirm chime, warm and bright", 0.9, 1, "s"),
    # ---- ambience beds (two layers per area, 22 s, mixed offline into the area bed)
    "amb_w1_a": ("a sunny countryside meadow, many songbirds singing near and far, gentle breeze in the grass", 22.0, 1, "a"),
    "amb_w1_b": ("soft summer breeze rustling leaves of trees and tall grass, distant sheep and insects", 22.0, 1, "a"),
    "amb_w2_a": ("high altitude wind above the clouds, soft airy whistling wind, calm and open", 22.0, 1, "a"),
    "amb_w2_b": ("distant gentle wind chimes tinkling slowly in a light breeze, airy", 22.0, 1, "a"),
    "amb_w3_a": ("thick hot chocolate bubbling slowly in a big river, gloopy bubbles and plops, warm", 22.0, 1, "a"),
    "amb_w3_b": ("a candy forest, occasional soft crunching of hard candy, sugar crystals tinkling, gentle breeze", 22.0, 1, "a"),
    "amb_hub_a": ("a cosy fireplace crackling and popping in a quiet library room", 22.0, 1, "a"),
    "amb_hub_b": ("a slow grandfather clock ticking steadily in a quiet wooden room", 22.0, 1, "a"),
    "amb_boss_a": ("a stormy night on a rooftop, howling gusting wind and steady rain on roof tiles", 22.0, 1, "a"),
    "amb_boss_b": ("distant rolling thunder and heavy wind gusts in a storm", 22.0, 1, "a"),
}


def main():
    jobs = []
    for name, (txt, sec, takes, kind) in J.items():
        pfx = {"v": PFX_V, "a": PFX_A}.get(kind, PFX)
        for t in range(takes):
            key = f"r5_{name}" + (f"_t{t + 1}" if takes > 1 else "")
            inp = {"text": pfx + txt, "duration_seconds": sec, "prompt_influence": 0.6 if kind != "a" else 0.45,
                   "output_format": "mp3_44100_192"}
            if kind in ("a", "l"):
                inp["loop"] = True
            jobs.append({"key": key, "endpoint": EP, "input": inp, "quoted_unit": "second @ $0.002",
                         "quoted_qty": sec, "estimated_usd": round(sec * 0.002, 4),
                         "max_reserved_usd": round(max(0.004, sec * 0.002 * 1.25), 4)})
    spec = {"phase": "night01-audio-m3-round5", "jobs": jobs}
    out = SRC / "jobs" / "round5_spec.json"
    out.write_text(json.dumps(spec, indent=1), encoding="utf-8")
    tot = sum(j["max_reserved_usd"] for j in jobs)
    print(len(jobs), "jobs, max reserved", round(tot, 3), "USD")


if __name__ == "__main__":
    main()

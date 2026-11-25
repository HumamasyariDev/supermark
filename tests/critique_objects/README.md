# Critique OBJECTS, round 1 (QA lens)

Test driver for the objects critique. It loads the real worlds through `Router.enter_world` with the real
`Player.tscn`, so every check runs against objects where the world builders placed them. It never edits
objects-track files.

`CritObjectsR1.tscn` (boot) adds `crit_objects_r1.gd` under `/root`, so the runner survives scene changes.

```
python tools/godot.py run res://tests/critique_objects/CritObjectsR1.tscn --headless --seconds 700 -- \
    --profile=crit_objects_r1_W1 --suite=world --world=W1 --results=<abs json>
```

| `--suite` | What it does |
| --- | --- |
| `world` (W1/W2/W3) | inventory, truffle ids against WorldRegistry, pickups inside solid collision, acorn supply against AcornHundred, checkpoint respawn points (floor, capsule) and touch, fall-out, respawn for every bookmark, bouncy launches with the real player, wind push, W1 bellows by real Ham Slam plus the W1-4 reward, W2 cage and switches, vanishing cloud, time trial (rings, reward, HUD timer after success, HUD timer after leaving the world), truffle collect, save file, ghost on revisit, no double count, lost pages across two visits |
| `hub` | portal thresholds against the registry, locked and open books, mission select, wolf door unlock at 12, open and enter BOSS |
| `misc` | overlapping talk zones, dialog dismiss with `interact` (reopen loop), crate spill, W1 spout lift to W1-4, W2 switch S2 |
| `shots` (windowed) | native captures of the issues into `Docs/progress/critique/objects/r1_qa/` (`--shot_dir=<abs>`) |
| `clip` (`--clip=cp6` or `talker`) | scripted scenes for `tools/godot.py movie` |
| `probe`, `stream` | collision probes for lost pages and the W1 stream current |
| `trace` (W1) | round 1b recheck: CP2_grove respawn trace (position, floor, wind), Gust_bellows_B1 trace, first acorn touch, stream current push |

Each run writes a JSON with `results` (name, pass, detail), `inventory` and `notes`. Logs and JSON from round 1 are in
`Docs/progress/critique/objects/r1_qa/logs/` (first pass) and `logs_r1b/` (recheck after the round 2 fixes).

## Round 1 after M3b, visual lens (2026-10-18 16:00 UTC)

`CritVisualM3b.tscn` (boot) adds `crit_visual_m3b.gd` under `/root`. It enters a world through Router with the real Player and
gameplay camera, stands Mak in front of every NPC and object type (NPCTalker, SignPost, Truffle, Checkpoint, Cage, Bellows,
LostPage, Crate, SlamSwitch, BuriedTreasure, BouncePad, Portal, WolfDoor, Acorn, loose character GLBs) and saves far/near
native captures. `--clip=<NodeName>` instead walks Mak up to that NPC and talks (for `tools/godot.py movie`).

```
python tools/godot.py run res://tests/critique_objects/CritVisualM3b.tscn --seconds 600 -- --profile=crit_objects_vis_W1 \
    --world=W1|W2|W3|HUB --shot_dir=<abs dir> [--intro_frames=480]
python tools/godot.py movie res://tests/critique_objects/CritVisualM3b.tscn <out.avi> --frames 2700 --size 1280x720 -- \
    --profile=crit_objects_clip --world=W3 --clip=MotherTreacle --clip_dist=6.0
```

Known limits: `move_forward` is camera-relative, so the clip walk can miss the NPC (Daisy); truffles on high perches get no spot.
Captures and audits: `Docs/progress/critique/objects/r1_visual/m3b/`.

## Round 1c (after objects M3b)

| Added | What it does |
| --- | --- |
| `crit_objects_r1c_audit.gd` | `python tools/godot.py script tests/critique_objects/crit_objects_r1c_audit.gd -- --out=<abs json>`. Checks the height and NpcLife profile of each `RIGGED_UPGRADES` pair, the default cage visual against its bar ring, and the WindZone shelter (meadow at foot height, wall, scaled zone) |
| `--suite=r1c_w2` | W2 page 4 is held in the bluebell bud: held before it opens, released in place, reachable, W2-5 paid, ghost on revisit |
| misc dismiss | presses `interact` until the dialog closes (typewriter lines need 2 presses), then watches for a reopen |
| hub | marks `hub_intro_seen` first (`--intro=1` keeps the intro), and logs Book 1 portal diagnostics (zone monitoring, bodies in the box) |

Logs: `Docs/progress/critique/objects/r1_qa/logs_r1c/`.

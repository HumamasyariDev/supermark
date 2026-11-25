# Boss: Sir Reginald Huffington III ("The Wolf's Own Tale")

Arena `res://scenes/boss/WolfRooftop.tscn` (`WolfRooftop`, a `WorldRoot` with `world_id = "BOSS"`). The hub's Wolf's Door
reaches it through `Router.enter_world("BOSS")` (WorldRegistry path). Design: `Docs/levels/BOSS.md` + `BOSS_amendments.md` (R1-R3).

| File | What |
| --- | --- |
| `wolf_rooftop.gd` | Arena builder (Tripo P2 chimneys, tea trolley + teapot, throne, parasol, dormer, parapet gaps, vents, sky page, storm, rain, lights, StoryCams `_v2`), colour script per phase, lightning, rim-prop fade when they block the gameplay camera |
| `wolf_boss.gd` | The fight: P1 Huff, P2 Puff, P3 Hurricane, defeat (swell, wedge, belly slam, pop), BOSS-1 and the top hat. Emits the Juice `boss_*` events (Docs/JUICE.md) and skips only the fallback channels Juice owns |
| `wolf_rig.gd`, `wolf_recipes.gd` | Procedural animation on the rigged `wolf_boss.glb` (no clips): one recipe per state (R3.11), blend shapes `chest_inflate` / `cheeks_puff` |
| `boss_director.gd` | BossFraming (camera_zone override on the player's MakCamera: wolf-to-Mak line, rim-aware boom, chimney-aware yaw), cinematics, hit punctuation (hitstop through Juice), slow motion |
| `boss_chimney.gd`, `boss_vent.gd`, `boss_tornado.gd`, `boss_crow.gd`, `boss_weakpoint.gd`, `boss_health_bar.gd`, `boss_tale.gd` | Arena pieces, Teapot Typhoon, Crow Bandits (real rigged crow), weak points, bar, HUD narration |
| `boss_bot.gd` | Scripted REAL player (drives `Player.tscn` through MakInput replay mode) through the whole fight |
| `boss_entry_test.gd` | Hub -> Wolf's Door -> arena test with the real Router and player |

## Dev arguments

- `--boss-phase=1|2|3` start at a phase; `--no-cine` skip cinematics; `--boss-stay` stay in the arena after the outro.
- `--bosstest` run the scripted player; `--bosstest-timeout=<s>`; `--bosstest-hold` (do not quit; Movie Maker);
  `--bosstest-pop` (try Pop the Bellows in P1), `--bosstest-chimney` (Down the Chimney in P2); `--bosstest-debug` (trace).

## Tests

```
python tools/godot.py run res://scenes/boss/WolfRooftop.tscn --headless --seconds 400 -- --bosstest --profile=boss_test
python tools/godot.py movie res://scenes/boss/WolfRooftop.tscn Recordings/night01/M3/<UTC>__boss.avi --frames 4500 --fps 30 -- --bosstest --bosstest-hold --boss-stay --profile=boss_movie
python tools/godot.py run res://scenes/boss/BossEntryTest.tscn --seconds 100 -- --unlock-all --profile=boss_entry
```

Results: `Docs/progress/boss/<UTC>__bosstest_realplayer_results.json` (8 checks) and `<UTC>__entry_from_hub_results.json`.

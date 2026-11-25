# Movement tests: replay and trace formats

Owner: player workstream. Everything here drives the real production controller
(`res://scenes/player/Player.tscn`) inside the MoveLab course (`res://scenes/tests/MoveLab.tscn`).

## Running

From the entity folder:

    python game/tests/run_movement_tests.py            # all cases, one Godot process at a time (machine limits)
    python game/tests/run_movement_tests.py jump_run_full long_jump   # selected cases

Each case writes `game/tests/replays/<case>.json`, runs Godot headless through `tools/godot.py run`
with `--replay`, `--trace` and `--profile=player-tests`, then parses the trace. Results go to
`game/tests/results/movement_<UTC>.json` and `game/tests/results/latest.json`.

## Dev arguments used

| Argument | Effect |
| --- | --- |
| `--replay=<abs json>` | The player reads input from the replay instead of the devices (Dev.replay). |
| `--trace=<abs jsonl>` | The player writes one JSON line per physics frame (format below). |
| `--replay-hold` | Do not quit when the replay ends (Movie Maker and capture runs). |
| `--rea-overlay` | Dev panel comparing each jump with the REA-predicted arc (F3 toggles). Clip: `python game/tests/record_rea_overlay.py`. |
| `--render-fps=<n>` | MoveLab caps the render loop (`Engine.max_fps`) for the consistency test. |
| `--profile=<name>` | Save-profile name; tests never touch the real save. |

## Replay format (JSON)

    {
      "fps": 60,                       // physics frames per second the frame numbers refer to
      "steer": "world",                // "world": stick up = world -Z, right = +X. "camera": camera-relative
      "start": {"pos": [x, y, z], "yaw_deg": 0},   // optional teleport before frame 0
      "end_frame": 300,                // quit (after flushing the trace) at this physics frame
      "events": [
        {"f": 0, "stick": [0, 1]},              // move stick (x right, y up/forward), persists
        {"f": 0, "cam": [0.5, 0]},              // camera stick, persists
        {"f": 30, "press": "jump"},             // hold until released
        {"f": 50, "release": "jump"},
        {"f": 60, "tap": "attack"},             // held for exactly one physics frame
        {"f": 70, "hold": "crouch", "frames": 20},
        {"t": 2.5, "press": "sniff"},           // "t" in seconds instead of "f"
        {"f": 90, "teleport": [x, y, z], "yaw_deg": 90},
        {"f": 95, "mark": "label"},             // copied into the trace row
        {"on": "land", "nth": 1, "delay": 0, "hold": "jump", "frames": 20},
        {"on": "state:wall_slide", "nth": 2, "delay": 2, "tap": "jump"},
        {"f": 400, "end": true}
      ]
    }

Actions: `jump`, `crouch`, `attack`, `sniff`, `cam_center`, `interact`. Frame 0 is the player's first
physics frame. Yaw 0 faces -Z; yaw -90 faces +X.

Reactive events (`"on"`) fire `delay` frames after the `nth` notification of a tag. Tags: `land`
(any landing), `state:<name>` (entering a state), `jump:<kind>` (a jump of that kind). They model a
player reacting to what happens, so timing tests do not depend on predicted airtimes.

## Trace format (JSON lines)

Line 1 is metadata: `{"meta": true, "physics_hz": 60, "max_fps": 0, "replay": "...", "engine": "...", "profile": {...}}`
(the profile holds every MovementProfile value used). Every following line is one physics frame:

    {"f": 12, "t": 0.2, "p": [x, y, z], "v": [vx, vy, vz], "s": "jump", "g": false, "fs": 7.5, "yaw": -90.0, "mark": "..."}

`p` is the body origin (feet), `v` the velocity after the collision solve, `s` the action state,
`g` grounded, `fs` the controller's forward speed along facing, `yaw` facing in degrees. `inv` is the remaining invulnerability in seconds.

## Cases

See `CASES` in `run_movement_tests.py`. Each case lists its measured values and the profile-derived
expectation with a tolerance. The expectation is the profile's own arithmetic (for example apex =
v^2 / 2g); passing means the controller does what the profile says, not that it matches the reference
game. Reference parity is a separate question (Docs/MOVEMENT_REFERENCE.md).

## Hero animation review (night 01, hero pass 2)

- `res://scenes/tests/PoseLab.tscn` freezes the controller and drives `MakAnimator` through named presets
  (`PRESETS` in `pose_lab.gd`, `name@seconds` overrides the time into the state), saving one native PNG per pose
  and view plus a contact sheet:

      python tools/godot.py run res://scenes/tests/PoseLab.tscn --seconds 60 -- --profile=hero-pose \
          --out=C:/abs/dir --poses=idle,jab1@0.09,kick --views=3q,side,front,face --sheet=name --cols=6
      # A/B: --proxy-pig (fallback pig), --pbr (raw generated materials), --hat=top_hat

  Movie Maker clip reel (real time, each clip `name:seconds:cycle:view`):

      python tools/godot.py movie res://scenes/tests/PoseLab.tscn out.avi --frames 1500 -- --profile=hero-reel \
          --clips=walk_a:2:0:side,jab1:1.2:0.4:3q,celebrate:2:0:front

- `python game/tests/record_showcase.py [--name ...] [-- --cam-distance=3.6 --cam-pitch=-13]` records the gameplay
  moveset showcase (`replays/showcase_moveset.json`, rebuilt by `make_showcase_replays.py` from the movement-test
  traces) in chunks cut at segment teleports, converts each AVI to MP4 at once (low disk use), trims the pre-roll and
  writes `Recordings/night01/M3/<UTC>__<name>.mp4`.
- `--fb-log` prints every feedback event the player sends and every `Juice.fired` event with its physics frame.

## Hero pass 3 (night 01, restarted hero track)

- **Foot-slip probe** `res://tests/foot_slip/FootSlipProbe.tscn` instances MoveLab, plays a replay on the real
  controller and samples the skinned model's `foot_l`/`foot_r` bones. A foot is planted while Mak is grounded in
  walk/run and the foot is within 1.5 cm of its lowest height in the speed band; its horizontal world speed over
  windows of at least one physics tick is the slide (0 = clean contact). Output per speed band: median, mean, p90,
  signed along-travel and sideways means.

      python tools/godot.py run res://tests/foot_slip/FootSlipProbe.tscn --seconds 40 -- --profile=hero-footslip \
          --replay=<abs>/game/tests/replays/foot_slip.json --slip-out=<abs json> [--no-gait-lock] [--side-cam]

  `--no-gait-lock` restores the old blended legs for A/B; `--side-cam` adds a low side camera (Movie Maker clips).
  Results: `results/foot_slip/<UTC>__footslip_A.json` (before) and `__footslip_D.json` (after).
- New movement cases: `ledge_opt_out` (MoveLab `--lab-no-ledge-grab` puts every lab body in group `no_ledge_grab`;
  no hang) and `cocoa_splash` (MoveLab `--lab-cocoa` adds a hot-chocolate HazardVolume on the run track; one
  `world_cocoa_splash` feedback event on entry, plus the hurt). Replays may carry `"args": [...]`, extra Godot
  arguments the runner appends.
- The runner now runs one case at a time (TECH_CONTRACT machine limits) and allows 900 s per case on top of the replay time, because
  `tools/godot.py` caps the whole machine at 3 concurrent Godot runs and the cases queue behind other agents.

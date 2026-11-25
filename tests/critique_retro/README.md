# RETRO track critique tests

Round 1, IMAGE CLEANLINESS AND PERFORMANCE lens. Test scenes only, never part of gameplay. They read RetroLook state but
never change the track's files.

- `CleanR1.tscn` with `clean_r1_harness.gd` adds `clean_r1_probe.gd` under `/root`; the probe then loads the areas itself.
  - `--clean-mode=perf` (default) visits HUB, W1, W2, W3, BOSS, HUB, W1 at a 1920x1080 window with vsync off. Per area it
    records the scene-entry frame times, the RetroLook apply stats, memory and RetroLook cache sizes, and frame times from a
    frozen copy of the gameplay camera. With `--retro=1` it also runs a live A/B/A/B toggle, measures blob-shadow ground fit
    (floating or buried rims, double shadows under a shadowed sun) with close-ups, and takes a grazing off/on capture pair.
    W1 gets a first-spawn hitch test (two enemy scenes instantiated in front of the camera).
  - `--clean-mode=movie` loads W1 and flies a scripted camera from StoryCam_C twice, first with the look off, then on,
    for a Movie Maker shimmer comparison. Frame markers go into `clean_r1_movie_<tag>.json`.
- `shimmer_r1.py <movie> <marks json> <out dir> <stamp>` measures temporal shimmer (second temporal difference of luma per
  screen band) for both passes and writes a magnified 6-frame far-field strip.

Examples (from the entity folder):

    python tools/godot.py run res://tests/critique_retro/CleanR1.tscn --seconds 1200 -- --profile=critic_retro_clean_r1 \
        --hide-hud --retro=1 --clean-tag=perf_retro1 --clean-out=<abs>/Docs/progress/critique/retro/r1_clean
    python tools/godot.py movie res://tests/critique_retro/CleanR1.tscn Recordings/night01/M3/<name>.avi --frames 1000 -- \
        --profile=critic_retro_clean_r1 --hide-hud --retro=1 --clean-mode=movie --clean-tag=movie_w1 --clean-out=<abs dir>

The report is `Docs/progress/critique/retro/r1_clean/REPORT.md`.

# critique_w2 (test files only)

Round 1 visual-lens critic tour for W2. Not part of the game.

    python tools/godot.py run res://tests/critique_w2/visual_tour.tscn --seconds 240 -- --profile=critic_w2_r1_visual --w2-nointro --tour-out=<abs dir> [--tour-only=story|route|chars|audit]

Outputs PNGs (story cams, gameplay-camera route, character close-ups), a motion metric and an audit JSON
(primitive meshes, meshes without material) into --tour-out.

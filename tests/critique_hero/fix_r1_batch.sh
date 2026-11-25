#!/usr/bin/env bash
# HERO fix stage r1: verification batch (one Godot run at a time, machine limits).
# Usage: bash game/tests/critique_hero/fix_r1_batch.sh <step...>   steps: anim poses feel moves visual
set -u
E="C:/GIT/mr-mak/workspace/2026-10-18_rea-super-mario-64"
cd "$E"
OUT="$E/Docs/progress/hero/fix_r1"
mkdir -p "$OUT"
for step in "$@"; do
  echo "=== $step $(date -u +%H:%M:%S)"
  case "$step" in
    anim)
      python game/tests/critique_hero/record_r1.py --view side --only 0 1 2 --name _fixr1 ;;
    anim3q)
      python game/tests/critique_hero/record_r1.py --view 3q --only 0 2 --name _fixr1 ;;
    poses)
      python tools/godot.py run res://scenes/tests/PoseLab.tscn --seconds 90 -- --profile=hero-pose \
        --out="$OUT/poses" --poses=ledge_hang,ledge_climb,pole,slam_land,run_a,run_b,celebrate_b \
        --views=3q,side --sheet=fixr1-poses --cols=7 ;;
    feel)
      python game/tests/critique_hero/fix_r1_feel.py lip_sweep wallkick_angles cam_tour ;;
    moves)
      python game/tests/run_movement_tests.py jump_stand_tap double_jump triple_jump chain_late side_flip wall_kick \
        ledge_grab_climb ledge_blocked crate_no_ground_hang ledge_opt_out long_jump backflip run_accel_stop pole stairs ;;
    visual)
      python tools/godot.py run res://tests/critique_hero/CritHeroVisualR1.tscn --seconds 200 --no-import -- \
        --profile=crit_hero_r1 --hide-hud --settle=480 --walk=70 --world=res://scenes/worlds/w1/W1.tscn --tag=w1fix \
        --out="$OUT/visual" ;;
  esac
done
echo "=== done $(date -u +%H:%M:%S)"

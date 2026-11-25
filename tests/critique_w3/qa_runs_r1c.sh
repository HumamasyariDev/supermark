#!/bin/bash
# W3 critique r1c QA (21:00 Bangkok pass on the post-pause build): QA probe r1c groups, one at a time, through
# "godot.py run" (no 300 s capture cap; the probe resizes the window to 1920x1080 itself and quits on its own).
# usage: qa_runs_r1c.sh "tag:phases:preset:seconds" ...
cd "$(dirname "$0")/../../.."
for grp in "$@"; do
  IFS=: read tag ph preset secs <<< "$grp"
  R="Docs/progress/critique/w3/r1_qa/r1c/probe_$tag"; mkdir -p "$R"
  O="$(pwd -W)/$R"
  timeout 3600 python tools/godot.py run res://tests/critique_w3/QaW3c.tscn --seconds ${secs:-600} -- --profile=critic_w3_qa_r1c_$tag --qa-out="$O" --qa-phases=$ph --qa-fort-preset=${preset:-0} > "$R/run.log" 2>&1
  echo "$tag exit=$? json=$(ls $R/w3_qa_probe.json 2>/dev/null) $(grep -c 'SCRIPT ERROR' $R/run.log) script-error-lines"
done

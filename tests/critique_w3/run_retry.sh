#!/bin/bash
# Retry a W3 critic run until the level actually loads (the machine-wide RunGovernor can time a run out).
# usage: run_retry.sh <label> <seconds> <replay.json> <crit-plan> [extra args]
cd "$(dirname "$0")/../../.."
R=Docs/progress/critique/w3/r1_fun
L=$1; S=$2; RP=$3; P=$4; shift 4
for i in 1 2 3 4 5 6; do
  rm -f $R/_$L.trace.jsonl
  timeout 1500 python tools/godot.py run res://tests/critique_w3/CritW3.tscn --seconds $S -- --replay=$(pwd)/$RP --trace=$(pwd)/$R/_$L.trace.jsonl --profile=critw3fun_${L}_$i --crit-plan=$P "$@" > $R/_$L.log 2>&1
  if grep -q "level built" $R/_$L.log; then echo "DONE $L try $i"; exit 0; fi
  echo "RETRY $L try $i"
done
echo "GAVEUP $L"

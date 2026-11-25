#!/bin/bash
# W3 critique r1 QA: run the QA probe in short phase groups (each under the 300 s capture timeout), one at a time.
cd "$(dirname "$0")/../../.."
for grp in ${QA_GROUPS:-"c1:audit,cams,views" "c2:audit,drops" "c3:audit,engage,kitchen" "c4:audit,hits,joust"} ${EXTRA_GROUPS}; do
  tag=${grp%%:*}; ph=${grp#*:}
  O="$(pwd -W)/Docs/progress/critique/w3/r1_qa/probe_$tag"; mkdir -p "$O"
  python tools/godot.py capture res://tests/critique_w3/QaW3.tscn "Docs/progress/critique/w3/r1_qa/probe_$tag/_unused.png" --wait 999999 -- --profile=critic_w3_qa_$tag --qa-out="$O" --qa-phases=$ph > "Docs/progress/critique/w3/r1_qa/probe_$tag/run.log" 2>&1
  echo "$tag $(grep -c '== exit' Docs/progress/critique/w3/r1_qa/probe_$tag/run.log) $(tail -2 Docs/progress/critique/w3/r1_qa/probe_$tag/run.log | head -1)"
done

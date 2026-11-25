#!/bin/bash
# Gameplay-camera stills for the W3 fun critique (round 1). Retries when the machine-wide run cap times a run out.
cd "$(dirname "$0")/../../.."
R=Docs/progress/critique/w3/r1_fun
for spec in "T_W3-2:400:fort-yard-squad-closing" "TierA:240:tier-a-route-read" "Islet:200:dunk-run-islet-view" "Page2:200:bridge-page2-shelf"; do
  IFS=: read sp w cap <<< "$spec"
  for i in 1 2 3 4; do
    S=$(date -u +%Y%m%dT%H%M%SZ)
    out=$R/${S}__${cap}.png
    timeout 900 python tools/godot.py capture res://scenes/worlds/w3/W3.tscn $out --wait $w -- --profile=critw3fun_cap_$S --spawn=$sp > $R/_cap_${cap}.log 2>&1
    if [ -f $out ]; then echo "OK $out"; break; fi
    echo "RETRY $cap"
  done
done

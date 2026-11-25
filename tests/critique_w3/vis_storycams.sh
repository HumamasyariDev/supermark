#!/bin/bash
# Visual critique W3 r1: the four fixed story cams (fresh captures). No outer timeout: godot.py itself waits for RAM and
# run slots on a contended machine (a 600 s outer timeout killed every attempt during those waits).
cd "$(dirname "$0")/../../.."
for c in ${CAMS:-A B C D}; do
  for i in 1 2; do
    S=$(date -u +%Y%m%dT%H%M%SZ)
    out=Docs/progress/_world/W3/StoryCam_$c/$S.png
    timeout 2400 python tools/godot.py capture res://scenes/worlds/w3/W3.tscn $out --cam StoryCam_$c --hide-hud --wait 150 -- --profile=critw3vis_$c > Docs/progress/critique/w3/r1_visual/r1b/_cap_$c.log 2>&1
    if [ -f $out ]; then echo "OK $out"; break; fi
    echo "RETRY $c"
  done
done
echo ALLDONE

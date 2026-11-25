"""W3 critic r1 visual lens: append evidence rows (data/evidence.jsonl) for the given capture paths (entity-relative)."""
import sys, json, hashlib, re, datetime as dt
from pathlib import Path
E = Path(__file__).resolve().parents[3]
OBS = {
 "start": "Spawn frame: cream Mak on butter-yellow path (low contrast); bookmark ribbon beside hero; sky top greyish; val_std 0.100 vs key art 0.194.",
 "Page2": "Chocolate river reads maroon with glowing orange rings; gingerbread cliff texture streaked/stretched; icing lip is a sawtooth band.",
 "TierA": "Cake tier and rim backdrop: rim domes visibly faceted and identical; flat drip band.",
 "Summit": "Summit acorn ring oversized and crowded around hero; wafer stilts thin bright orange scaffolding; strong postcard of river and fort.",
 "T_W3-4": "Slide top: flat blue slide, empty grey-blue sky band and identical rim domes; val_std 0.097.",
 "Islet": "Islet: marshmallows good; bookmark ribbon overlaps Mak; orange speckled caramel blocks read hot/hazard; river maroon.",
 "T_W3-3": "Glowing orange caramel plank under Mak reads as lava; biscuits match key art; cliffs streaked.",
 "T_W3-2": "Snap arena interior: flat untextured orange walls, desaturated grass, floating SLAM! text; grenadiers real GLBs.",
 "Balcony": "Rim domes dominate right half; rectangular seam visible in the river surface near the gold item.",
 "Page5": "Camera inside cake strata layers with backfaces; red pole occludes Mak; blocky artifact at top of falls curtain.",
 "Page4": "Pink cone tent and flat white marshmallow block; rim domes fill right side.",
 "T_W3-7": "Best vista: falls, cottage, cake tower, slide, river from the Great Lollipop; still milky (val_std 0.119).",
 "MazeIn": "Mint box hedges with black posts; candyfloss mist smears hedge tops; bookmark beside hero.",
 "T_W3-1": "Liquorice nest trees: jagged stair-stepped red/black patches, reads broken.",
 "Pool": "Magenta pool flat with white dots; camera near-clips cliff (blurry smear bottom right).",
 "T_W3-8": "Camera inside the syrup falls: whole frame pink, hero invisible (val 0.933).",
 "T_W3-8b": "Cauldron smoke as opaque grey spheres; liquorice rail stair-stepped; rim dome fence right behind the plateau.",
 "T_W3-6b": "Cottage GLB excellent; acorn embedded inside a caramel block (left).",
 "T_W3-6": "Roof: crow Yoink gag reads well; plain chimney top; rim domes.",
 "Page1": "Camera pitched straight down at the page; rock-candy mound fine.",
 "char_CorporalCrumb": "Crumb = grenadier GLB on a squashed biscuit platform plus 18 visible primitive meshes (torus goggles, 7 box scarf segments, cylinder stalk); reads as a plain grenadier.",
 "char_MotherTreacle": "Mother Treacle is bramwell.glb (the hub tortoise butler), not a badger baker.",
 "char_sergeant_snap": "Snap (sergeant_snap_v3.glb) on the fort wall; arena walls flat orange slabs with white box caps.",
 "char_Hansel": "Probe teleport landed Mak on a rim dome top (kids are in the kitchen set at y 102): rim domes are crude up close, sky flat grey-blue.",
}
rows = []
for f in sys.argv[1:]:
    p = E / f
    m = re.search(r"(\d{8}T\d{6}Z)", p.name)
    utc = dt.datetime.strptime(m.group(1), "%Y%m%dT%H%M%SZ").strftime("%Y-%m-%dT%H:%M:%SZ")
    lab = re.sub(r".*__vis_", "", p.stem)
    obs = OBS.get(lab, "")
    if "StoryCam" in f:
        lab = f.split("/")[-2]
        obs = "Fresh fixed story cam for the W3 critic r1 visual lens; RetroLook partly active (blob shadows)."
    elif "kitchencam" in p.name:
        lab, obs = "KitchenCam", "Kitchen interior (W3-6)."
    elif not obs:
        obs = "Character close-up audit (vis_w3_chars.json)." if lab.startswith("char_") else "W3 visual route capture."
    rows.append({"utc": utc, "timezone": "Asia/Bangkok", "run": "night02", "milestone": "critique", "feature": "critique-w3-r1-visual",
                 "capture_type": "native_viewport", "file": f, "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
                 "caption": "W3 critic r1 visual polish: " + lab, "observed": obs, "reviewed": True})
with open(E / "data" / "evidence.jsonl", "a", encoding="utf-8") as fh:
    for r in rows:
        fh.write(json.dumps(r, ensure_ascii=False) + "\n")
print(len(rows), "rows")

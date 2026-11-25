"""Generate stylized tileable textures for Super Mak 64 via fal.ai nano-banana-2.
Logs reservation rows to data/costs.jsonl BEFORE submit and billed rows after.
Usage: python gen_textures.py [name ...]   (no args = all missing)"""
import json, os, sys, time, hashlib, datetime, urllib.request
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

HERE = Path(__file__).resolve().parent
ENTITY = HERE.parents[3]
ROOT = ENTITY.parents[1]
COSTS = ENTITY / 'data' / 'costs.jsonl'
ENDPOINT = 'fal-ai/nano-banana-2'
UNIT_USD = 0.08

for line in (ROOT / '.env').read_text(encoding='utf-8').splitlines():
    if line.startswith('FALAI_KEY='):
        os.environ['FAL_KEY'] = line.split('=', 1)[1].strip().strip('"')
import fal_client

STYLE = ("Seamless tileable square texture, flat orthographic top-down view, even soft lighting, no shadows from a light "
         "direction, no perspective, no vignette, no border, no text, edges continue seamlessly on all four sides. "
         "Stylized hand-painted game texture in the style of a premium cozy storybook 3D platformer: soft painterly "
         "brush strokes, chunky readable shapes, saturated but harmonious warm colours, low contrast micro detail, "
         "no photographic noise.")

PROMPTS = {
    'grass': "Lush meadow grass ground: rich warm green with soft clumps of painted grass blades, a few tiny yellow and white flower specks.",
    'dirt_path': "Packed earth country path: warm ochre-brown dirt with small rounded pebbles and soft painted cracks.",
    'cliff_rock': "Cliff rock face: chunky rounded stone slabs in warm grey with slight lavender and moss-green tints, broad planes.",
    'brick': "Red brick wall: rounded chunky terracotta bricks in a running bond with cream mortar, slightly irregular, cosy.",
    'straw_thatch': "Straw thatch roof: bundled golden straw layered in soft rows, warm yellow with honey shading.",
    'wood_planks': "Wooden floor planks: warm honey-brown planks running vertically with painted grain, soft knots and dark seams.",
    'cobblestone': "Cobblestone pavement: rounded plump cobbles in warm grey and beige with soft dark gaps.",
    'bark': "Tree bark: thick vertical ridges of warm brown bark with chunky rounded furrows.",
    'candy_stripes': "Peppermint sugar surface: even diagonal stripes of cherry red and cream white, soft sugary sheen, painted look.",
    'frosting': "White icing frosting: soft swirled thick cream-white frosting with pale pink and mint sprinkles.",
    'gingerbread': "Gingerbread cookie surface: warm golden brown baked dough with tiny pores and a slight sugar dusting.",
    'chocolate': "Cocoa fudge tiles: a grid of rounded square fudge pieces in rich warm brown with soft glossy highlights, like a dessert in a storybook bakery.",
    'bookshelf_wood': "Polished walnut wood: deep reddish-brown varnished walnut grain running horizontally, rich and warm.",
    'parchment': "Old parchment paper: warm cream paper with subtle tea-stain blotches and soft fibres, very gentle.",
    # Batch 2: hub, beanstalk, castle and boss surfaces.
    'roof_tiles': "Clay roof tiles: overlapping rounded terracotta roof shingles in neat rows, warm orange-red with soft shading.",
    'library_carpet': "Library carpet: deep burgundy wool rug with a subtle gold damask pattern, soft and cosy.",
    'damask_wallpaper': "Wallpaper: rich burgundy and brass-gold damask pattern, elegant English manor, gentle painted texture.",
    'stained_glass': "Stained glass: jewel-toned rounded glass pieces in amber, ruby, emerald and sapphire with dark lead lines, glowing.",
    'beanstalk_skin': "Giant beanstalk stem surface: vertical fibrous green stalk with lighter ribbed lines and tiny leaf buds, fresh and vibrant.",
    'leaf_canopy': "Leafy tree canopy: dense clusters of rounded overlapping green leaves with lighter sunlit tops and darker gaps.",
    'gumdrop_sugar': "Sugar-coated gumdrop surface: translucent mint-green candy with tiny sparkling sugar crystals.",
    'plaster_wall': "Cottage plaster wall: warm cream lime plaster with soft uneven patches and faint hairline cracks.",
    'castle_stone': "Castle floor flagstones: large rounded light grey and lavender stone slabs with soft cracks, fairy-tale giant's castle.",
    'roof_shingles_slate': "Slate roof shingles: overlapping rounded blue-grey slate tiles in rows, stormy and moody but stylized.",
}

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def log(row):
    with open(COSTS, 'a', encoding='utf-8') as f:
        f.write(json.dumps(row) + '\n')

def gen(name):
    raw = HERE / f'{name}_raw.png'
    rec = HERE / f'{name}_receipt.json'
    if raw.exists():
        return name, 'exists'
    prompt = PROMPTS[name] + ' ' + STYLE
    args = {'prompt': prompt, 'num_images': 1, 'aspect_ratio': '1:1', 'resolution': '1K', 'output_format': 'png'}
    log({'utc': now(), 'phase': 'night01-vfx-textures', 'provider': 'fal.ai', 'model': ENDPOINT, 'job_id': None,
         'asset': f'texture:{name}', 'quoted_unit': 'image', 'quoted_unit_usd': UNIT_USD, 'quantity': 1,
         'max_reserved_usd': UNIT_USD, 'billed_usd': None, 'state': 'reserved'})
    h = fal_client.submit(ENDPOINT, arguments=args)
    rid = h.request_id
    rec.write_text(json.dumps({'endpoint': ENDPOINT, 'request_id': rid, 'arguments': args, 'submitted_utc': now()}, indent=2))
    res = h.get()
    url = res['images'][0]['url']
    urllib.request.urlretrieve(url, raw)
    sha = hashlib.sha256(raw.read_bytes()).hexdigest()
    rec.write_text(json.dumps({'endpoint': ENDPOINT, 'request_id': rid, 'arguments': args, 'completed_utc': now(),
                               'output_file': raw.name, 'sha256': sha, 'description': res.get('description')}, indent=2))
    log({'utc': now(), 'phase': 'night01-vfx-textures', 'provider': 'fal.ai', 'model': ENDPOINT, 'job_id': rid,
         'asset': f'texture:{name}', 'quoted_unit': 'image', 'quoted_unit_usd': UNIT_USD, 'quantity': 1,
         'max_reserved_usd': UNIT_USD, 'billed_usd': UNIT_USD, 'billed_basis': 'fal list price per image; confirm in fal billing', 'state': 'completed'})
    return name, 'ok'

if __name__ == '__main__':
    names = sys.argv[1:] or list(PROMPTS)
    with ThreadPoolExecutor(5) as ex:
        for r in ex.map(lambda n: _safe(n), names) if False else ex.map(gen, names):
            print(r, flush=True)

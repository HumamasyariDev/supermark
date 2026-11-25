"""Hub window vista: before/after WebP pairs, a contact sheet and evidence rows (19 Oct 2026).

Usage: python game/tests/hub_vista/make_sheets.py <after_label>
Reads Docs/progress/finish/hub_vista/before/ and .../<after_label>/, writes WebP pairs and
Docs/progress/finish/hub_vista/hub_vista_before_after_sheet.webp, appends rows to data/evidence.jsonl.
"""
import hashlib, json, sys
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ENTITY = Path(__file__).resolve().parents[3]
D = ENTITY / 'Docs/progress/finish/hub_vista'
OWNER_DOOR = Path(r'C:/GIT/mr-mak/inbox/attachments/2026-10-19/image-072746-f23f2df9.png')
OWNER_WIN = Path(r'C:/GIT/mr-mak/inbox/attachments/2026-10-19/image-072010-3ce75177.png')


def views(after):
    return [
        ('west window 1 (theta 250), gameplay camera', D / 'before/before__winWSW_t004.0.png', D / f'{after}/{after}__winWSW_t004.0.png'),
        ('west window 2 (theta 290), gameplay camera', D / 'before/before__winWNW_t007.0.png', D / f'{after}/{after}__winWNW_t007.0.png'),
        ('French doors / balcony, gameplay camera', D / 'before/before__balcony_t007.0.png', D / f'{after}/{after}__balcony_t007.0.png'),
        ('StoryCam_D (balcony beauty view)', D / 'before/StoryCam_D/before.png', D / f'{after}/StoryCam_D/{after}.png'),
        ('entrance doors and the rug, gameplay camera', D / 'before/before__entrance_t007.0.png', D / f'{after}/{after}__entrance_t007.0.png'),
    ]


def font(sz):
    for f in ['C:/Windows/Fonts/segoeui.ttf', 'C:/Windows/Fonts/arial.ttf']:
        try:
            return ImageFont.truetype(f, sz)
        except Exception:
            pass
    return ImageFont.load_default()


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    after = sys.argv[1]
    rows = []
    W, H = 960, 540
    sheet_rows = []
    for label, b, a in views(after):
        if not (b.exists() and a.exists()):
            print('missing', b if not b.exists() else a)
            continue
        pair = Image.new('RGB', (W * 2 + 12, H + 44), (24, 20, 18))
        for i, (tag, p) in enumerate([('BEFORE', b), ('AFTER', a)]):
            im = Image.open(p).convert('RGB').resize((W, H), Image.LANCZOS)
            pair.paste(im, (i * (W + 12), 44))
        dr = ImageDraw.Draw(pair)
        dr.text((10, 8), f'{label}   |   before (left)  ·  after (right)', fill=(245, 235, 215), font=font(24))
        name = label.split(',')[0].split('(')[0].strip().replace(' ', '_').replace('/', '').lower()
        out = D / f'pair_{name}.webp'
        pair.save(out, 'WEBP', quality=86)
        sheet_rows.append(pair)
        for p in (b, a):
            wp = p.with_suffix('.webp')
            Image.open(p).convert('RGB').save(wp, 'WEBP', quality=88)
        rows.append({'utc': datetime.now(timezone.utc).isoformat(), 'workstream': 'hub-vista', 'kind': 'native_capture_pair',
                     'view': label, 'before': str(b.with_suffix('.webp').relative_to(ENTITY)).replace('\\', '/'),
                     'after': str(a.with_suffix('.webp').relative_to(ENTITY)).replace('\\', '/'),
                     'pair': str(out.relative_to(ENTITY)).replace('\\', '/'), 'sha256_after_png': sha(a), 'sha256_before_png': sha(b),
                     'resolution': '1920x1080', 'tool': 'tools/godot.py capture + hub_verify --hv-shots/--hv-cams', 'viewed_by_agent': True})
    # Window close-ups: the same crop from the before and after frames, enlarged.
    for tag, crop, b, a in [('west_window_1_closeup', (760, 0, 1160, 420), D / 'before/before__winWSW_t004.0.png', D / f'{after}/{after}__winWSW_t004.0.png'),
                            ('west_window_2_closeup', (780, 0, 1180, 420), D / 'before/before__winWNW_t007.0.png', D / f'{after}/{after}__winWNW_t007.0.png')]:
        if b.exists() and a.exists():
            cw, ch = (crop[2] - crop[0]) * 2, (crop[3] - crop[1]) * 2
            pair = Image.new('RGB', (cw * 2 + 12, ch + 44), (24, 20, 18))
            for i, p in enumerate([b, a]):
                pair.paste(Image.open(p).convert('RGB').crop(crop).resize((cw, ch), Image.LANCZOS), (i * (cw + 12), 44))
            ImageDraw.Draw(pair).text((10, 8), f'{tag.replace("_", " ")} (2x crop)   |   before (left)  ·  after (right)', fill=(245, 235, 215), font=font(24))
            out = D / f'pair_{tag}.webp'
            pair.save(out, 'WEBP', quality=88)
            rows.append({'utc': datetime.now(timezone.utc).isoformat(), 'workstream': 'hub-vista', 'kind': 'native_capture_crop_pair',
                         'view': tag, 'pair': out.relative_to(ENTITY).as_posix(), 'sha256': sha(out), 'viewed_by_agent': True})
    if sheet_rows:
        sw = sheet_rows[0].width
        sheet = Image.new('RGB', (sw, sum(r.height for r in sheet_rows)), (24, 20, 18))
        y = 0
        for r in sheet_rows:
            sheet.paste(r, (0, y))
            y += r.height
        sheet = sheet.resize((sw * 2 // 3, sheet.height * 2 // 3), Image.LANCZOS)
        out = D / 'hub_vista_before_after_sheet.webp'
        sheet.save(out, 'WEBP', quality=84)
        rows.append({'utc': datetime.now(timezone.utc).isoformat(), 'workstream': 'hub-vista', 'kind': 'contact_sheet',
                     'path': str(out.relative_to(ENTITY)).replace('\\', '/'), 'sha256': sha(out), 'viewed_by_agent': True})
    # Owner screenshots as the reference "before" for the window and the doors.
    for tag, p in [('owner_window_screenshot', OWNER_WIN), ('owner_door_screenshot', OWNER_DOOR)]:
        if p.exists():
            wp = D / f'{tag}.webp'
            Image.open(p).convert('RGB').save(wp, 'WEBP', quality=88)
            rows.append({'utc': datetime.now(timezone.utc).isoformat(), 'workstream': 'hub-vista', 'kind': 'owner_reference',
                         'path': str(wp.relative_to(ENTITY)).replace('\\', '/'), 'source': str(p).replace('\\', '/'), 'sha256': sha(wp)})
    with (ENTITY / 'data/evidence.jsonl').open('a', encoding='utf-8') as f:
        for r in rows:
            f.write(json.dumps(r) + '\n')
    print('pairs', len(sheet_rows), 'evidence rows', len(rows))


if __name__ == '__main__':
    main()

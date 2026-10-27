"""Validate/apply only the eleven supplied v1.2 repair PNGs, with immutable backup.

The older v1.1 audit remains historical evidence; this records the authorized delta.
Use --apply once (or repeatedly, idempotently); omit it for read-only verification.
"""
import argparse
import base64
import hashlib
import html
from io import BytesIO
import json
from pathlib import Path, PurePosixPath
import zipfile

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
OLD_PREFIX = 'SISYPHUS_mastery_assets_v1_1_GREEK_RESTORED/'
NEW_PREFIX = 'SISYPHUS_mastery_assets_v1_2_PATCH_ONLY/'
ASSET_PREFIX = 'assets/ui/mastery/'
ALLOWED = {ASSET_PREFIX + f'character/sisyphus_push_{i:02}.png' for i in range(1, 6)}
ALLOWED |= {ASSET_PREFIX + 'character/sisyphus_push_sheet.png'}
ALLOWED |= {ASSET_PREFIX + f'special/special_placeholder_{i:02}.png' for i in range(1, 6)}
DOCS = ROOT / 'docs/mastery/patch-v12'
OUTPUT = ROOT / 'tests/mastery/results/v12-patch/asset_audit.json'


def sha(blob):
    return hashlib.sha256(blob).hexdigest()


def changed_count(difference):
    pixels = difference.tobytes()
    return sum(any(pixels[i:i + 4]) for i in range(0, len(pixels), 4))


def image_info(blob):
    image = Image.open(BytesIO(blob))
    image.load()
    rgba = image.convert('RGBA')
    hist = rgba.getchannel('A').histogram()
    return {'width': image.width, 'height': image.height, 'mode': image.mode,
            'bytes': len(blob), 'sha256': sha(blob),
            'alpha_bbox': rgba.getchannel('A').getbbox(),
            'transparent_pixels': hist[0], 'opaque_pixels': hist[255],
            'partial_alpha_pixels': sum(hist[1:255])}


def read_archive(path, prefix, patch=False):
    with zipfile.ZipFile(path) as archive:
        names = [item.filename for item in archive.infolist() if not item.is_dir()]
        if len(names) != len(set(names)):
            raise ValueError('Duplicate archive members')
        result = {}
        for name in names:
            if not name.startswith(prefix):
                raise ValueError('Unexpected archive root: ' + name)
            relative = name[len(prefix):]
            parsed = PurePosixPath(relative)
            if parsed.is_absolute() or '..' in parsed.parts or '\\' in relative:
                raise ValueError('Unsafe archive path: ' + relative)
            if relative.startswith(ASSET_PREFIX) and relative.lower().endswith('.png'):
                if patch and relative not in ALLOWED:
                    raise ValueError('Unexpected patch PNG: ' + relative)
                result[relative] = archive.read(name)
            elif patch and relative != 'PATCH_NOTES_v1_2_FIXED.md':
                raise ValueError('Unexpected patch payload: ' + relative)
        if patch and set(result) != ALLOWED:
            raise ValueError('Patch must contain exactly the eleven authorized PNGs')
        notes = archive.read(prefix + 'PATCH_NOTES_v1_2_FIXED.md') if patch else None
        return result, notes


def audit(original_archive, patch_archive, apply=False):
    original, _ = read_archive(original_archive, OLD_PREFIX)
    patched, notes = read_archive(patch_archive, NEW_PREFIX, patch=True)
    if len(original) != 131:
        raise ValueError('Original runtime PNG inventory must contain 131 files')
    checks = []

    def check(name, ok):
        checks.append({'name': name, 'pass': bool(ok)})

    current = {}
    replacements = []
    unknown = []
    for name, old in original.items():
        path = (ROOT / name).resolve()
        if not path.is_relative_to((ROOT / ASSET_PREFIX).resolve()):
            raise ValueError('Resolved path escapes asset root')
        if not path.is_file():
            unknown.append(name + ':missing')
            continue
        current[name] = path.read_bytes()
        valid = current[name] == old or (name in patched and current[name] == patched[name])
        if not valid:
            unknown.append(name + ':unexpected bytes')
        if name in patched:
            old_info, new_info = image_info(old), image_info(patched[name])
            same_size = (old_info['width'], old_info['height']) == (new_info['width'], new_info['height'])
            check('dimensions_preserved:' + name, same_size)
            a, b = Image.open(BytesIO(old)).convert('RGBA'), Image.open(BytesIO(patched[name])).convert('RGBA')
            differences = ImageChops.difference(a, b)
            pixels = changed_count(differences)
            visible_black = ImageChops.difference(Image.alpha_composite(Image.new('RGBA', a.size, 'black'), a), Image.alpha_composite(Image.new('RGBA', b.size, 'black'), b))
            visible_white = ImageChops.difference(Image.alpha_composite(Image.new('RGBA', a.size, 'white'), a), Image.alpha_composite(Image.new('RGBA', b.size, 'white'), b))
            visible_difference = ImageChops.lighter(visible_black, visible_white)
            visible_pixels = changed_count(visible_difference)
            replacements.append({'path': name, 'before': old_info, 'after': new_info,
                                 'changed_pixels': pixels,
                                 'visible_changed_pixels_black_or_white_background': visible_pixels,
                                 'hidden_or_quantized_rgb_only_changed_pixels': pixels - visible_pixels,
                                 'changed_bbox': differences.getbbox(alpha_only=False),
                                 'before_apply': 'already_patched' if current[name] == patched[name] else 'original'})
    # Full preflight happens before creating/replacing any asset.
    if unknown or not all(item['pass'] for item in checks):
        raise ValueError('Refusing unknown asset state: ' + repr(unknown))

    DOCS.mkdir(parents=True, exist_ok=True)
    backup = DOCS / 'originals.zip'
    if not backup.exists() and apply:
        # Exclusive creation; an existing backup is never replaced or appended.
        with zipfile.ZipFile(backup, 'x', compression=zipfile.ZIP_STORED) as archive:
            for name in sorted(ALLOWED):
                archive.writestr(name, original[name])
    backup_valid = False
    if backup.exists():
        with zipfile.ZipFile(backup) as archive:
            backup_valid = set(archive.namelist()) == ALLOWED and all(archive.read(name) == original[name] for name in ALLOWED)
        if not backup_valid:
            raise ValueError('Immutable original backup failed verification')
    elif apply:
        raise ValueError('Original backup is required before replacement')
    check('immutable_original_backup', backup_valid)

    replaced = []
    if apply:
        for name in sorted(ALLOWED):
            path = ROOT / name
            if path.read_bytes() != patched[name]:
                path.write_bytes(patched[name])
                replaced.append(name)
        # Keep the supplied notes verbatim; do not interpret them as extra authority.
        note_path = DOCS / 'PATCH_NOTES_v1_2_FIXED.md'
        if note_path.exists() and note_path.read_bytes() != notes:
            raise ValueError('Existing patch notes differ; refusing overwrite')
        if not note_path.exists():
            note_path.write_bytes(notes)

    for name, old in sorted(original.items()):
        check(('patched_exact:' if name in patched else 'unchanged_exact:') + name,
              (ROOT / name).read_bytes() == patched.get(name, old))
    sheet = Image.open(BytesIO(patched[ASSET_PREFIX + 'character/sisyphus_push_sheet.png'])).convert('RGBA')
    first_cell = sheet.crop((0, 0, 248, 200))
    idle = Image.open(BytesIO(original[ASSET_PREFIX + 'character/sisyphus_idle.png'])).convert('RGBA')
    check('sheet_cell0_idle_alpha_preserved', first_cell.getchannel('A').tobytes() == idle.getchannel('A').tobytes())
    sheet_idle_difference = changed_count(ImageChops.difference(first_cell, idle))
    for index in range(1, 6):
        frame = Image.open(BytesIO(patched[ASSET_PREFIX + f'character/sisyphus_push_{index:02}.png'])).convert('RGBA')
        check(f'sheet_cell{index}_matches_individual_push', sheet.crop((248 * index, 0, 248 * (index + 1), 200)).tobytes() == frame.tobytes())

    report = {'pass': all(item['pass'] for item in checks), 'checks': checks,
              'check_count': len(checks), 'failed': [item for item in checks if not item['pass']],
              'original_archive_sha256': sha(original_archive.read_bytes()),
              'patch_archive_sha256': sha(patch_archive.read_bytes()),
              'original_runtime_png_count': len(original), 'authorized_replacements': len(patched),
              'unaffected_pngs': len(original) - len(patched),
              'applied_this_run': replaced,
              'backup': backup.relative_to(ROOT).as_posix(),
              'backup_sha256': sha(backup.read_bytes()) if backup.exists() else None,
              'comparisons': replacements,
              'sheet_note': 'First sheet cell contains idle alpha, not an empty slot; five following cells match push01..05. Current mastery gate uses individual frames and idle PNG, not this sheet.',
              'sheet_idle_cell_changed_pixels_vs_separate_idle': sheet_idle_difference,
              'alpha_interpretation': 'PNG review must honor alpha. Old special01 bottom text-like RGB at y110+ has zero alpha and was invisible; replacement corrects icon framing, not a proven rendered text leak.',
              'scope': 'Only supplied eleven PNG bytes replaced; no resizing, re-encoding, name changes, physics/economy/save code or historical v1.1/v1.2 results modified.'}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    # Self-contained comparison displays original/patch PNG bytes unchanged.
    blocks = ['<!doctype html><meta charset="utf-8"><title>SISYPHUS v1.2 asset patch proof</title>',
              '<style>body{background:#242424;color:#ead7b5;font:16px sans-serif;margin:24px}section{margin-bottom:36px}img{max-width:100%;background:repeating-conic-gradient(#555 0% 25%,#333 0% 50%) 0/20px 20px}figure{display:inline-block;vertical-align:top;margin:8px}pre{white-space:pre-wrap}</style>',
              '<h1>Original v1.1 → supplied v1.2 patch</h1><p>PNG files embedded byte-identically. Checkerboard is HTML background only. Runtime uses individual push frames. Sheet first cell contains the original idle alpha; other cells match the five push frames. Hidden RGB artifacts at alpha zero are not visible defects.</p>']
    for item in replacements:
        name = item['path']
        blocks.append('<section><h2>' + html.escape(name) + '</h2>')
        for caption, blob in [('Original, backed up', original[name]), ('Supplied patch, applied', patched[name])]:
            blocks.append('<figure><figcaption>' + caption + '</figcaption><img src="data:image/png;base64,' + base64.b64encode(blob).decode('ascii') + '"></figure>')
        blocks.append('<pre>' + html.escape(json.dumps(item, ensure_ascii=False, indent=2)) + '</pre></section>')
    (DOCS / 'comparison.html').write_text('\n'.join(blocks), encoding='utf-8')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original', type=Path, default=Path('C:/Users/PMS/Downloads/SISYPHUS_mastery_assets_v1_1_GREEK_RESTORED.zip'))
    parser.add_argument('--patch', type=Path, default=Path('C:/Users/PMS/Downloads/SISYPHUS_mastery_assets_v1_2_PATCH_ONLY.zip'))
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    result = audit(args.original, args.patch, args.apply)
    print(json.dumps({key: result[key] for key in ['pass', 'check_count', 'failed', 'authorized_replacements', 'unaffected_pngs', 'applied_this_run']}, ensure_ascii=False))
    raise SystemExit(0 if result['pass'] else 1)

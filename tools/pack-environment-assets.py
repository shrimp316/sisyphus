"""Crop/resize/pad generated RGBA images to the user-specified game formats.

No synthetic replacement art, recoloring, masking or background removal.
Generated alpha is preserved; only format normalization is performed.
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'docs/image-prompts-environment.json'
SOURCE_MAP = ROOT / '.tools/environment-sources.json'
FLAT = {'rock_ground', 'gravel_ground', 'mud_ground', 'wet_rock', 'snow_ground'}


def normalize(entry, source_map):
    source_path = source_map.get(entry['name'], entry['source'])
    source = Image.open(source_path).convert('RGBA')
    alpha = source.getchannel('A')
    if alpha.getextrema()[0] != 0:
        raise ValueError(f"No genuinely transparent pixels: {entry['name']}")
    bounds = alpha.point(lambda a: 255 if a > 8 else 0).getbbox()
    if not bounds:
        raise ValueError(f"Empty source: {entry['name']}")
    art = source.crop(bounds)
    category, name = entry['category'], entry['name']
    if category == 'boulder':
        art.thumbnail((352, 352), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (384, 384))
        offset = ((384-art.width)//2, (384-art.height)//2)
        meta = {'pivot': [192,192], 'collision_radius': 176}
    elif category == 'props':
        art.thumbnail((352, 328), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (384, 384))
        offset = ((384-art.width)//2, 352-art.height)
        meta = {'pivot': [192,352], 'baseline_y': 352}
    else:
        flat = name in FLAT
        art = art.resize((512, 176 if flat else 208), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (512,256))
        offset = (0,64 if flat else 32)
        meta = {'pivot': [0,64 if flat else 32], 'nominal_walk_y': 64 if flat else None,
                'usage': 'flat_strip_path_warp' if flat else 'authored_profile_preview_or_matching_collision'}
    canvas.alpha_composite(art, offset)
    destination = ROOT / 'assets' / category / (name + '.png')
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination)
    final_alpha = canvas.getchannel('A')
    meta.update({'file': destination.relative_to(ROOT).as_posix(), 'size': list(canvas.size),
                 'alpha_extrema': list(final_alpha.getextrema()), 'visible_bounds': list(final_alpha.getbbox())})
    if category == 'terrain':
        profile = []
        for x in list(range(0,512,16)) + [511]:
            samples = [y for y in range(256) if final_alpha.getpixel((x,y)) >= 128]
            profile.append([x, min(samples) if samples else None])
        meta['walk_surface_profile'] = profile
        if name in {'ledge', 'foothold_rest_platform', 'small_stone_step'}:
            meta['pivot'] = [256, next(y for x,y in profile if x == 256)]
            meta['usage'] = 'local_surface_decoration_with_explicit_pivot'
        meta['profile_note'] = 'Visible top alpha contour sampled every16px; artwork guide, not automatic physics replacement.'
    return meta


def main():
    entries = json.loads(MANIFEST.read_text(encoding='utf-8-sig'))['assets']
    source_map = json.loads(SOURCE_MAP.read_text(encoding='utf-8-sig')) if SOURCE_MAP.exists() else {}
    assets = {entry['name']: normalize(entry, source_map) for entry in entries}
    destination = ROOT / 'assets/metadata/environment_assets.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps({'schema_version':1, 'generator':'built-in image_gen', 'assets':assets}, ensure_ascii=False, indent=2), encoding='utf-8')
    for name, asset in assets.items():
        print(name, asset['size'], asset['alpha_extrema'], asset['visible_bounds'])


if __name__ == '__main__':
    main()

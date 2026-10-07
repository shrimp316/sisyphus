"""Normalize generated UI cutouts to fixed canvases without painting artwork.

Usage: python tools/pack-ui-assets.py [source-manifest.json]
The manifest is a JSON list of {name, source} entries from built-in image_gen.
Only alpha-bound cropping, proportional resizing and transparent padding occur.
"""
from pathlib import Path
import json
import sys
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ICONS = ['stamina_icon', 'slip_icon', 'brace_icon', 'push_burst_icon',
         'checkpoint_icon', 'height_marker_icon', 'warning_wind_icon',
         'warning_rockfall_icon']
MARKERS = ['previous_record_marker', 'event_marker', 'rest_point_marker']


def main():
    manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / '.tools/ui-generated-sources.json'
    sources = {item['name']: Path(item['source']) for item in json.loads(manifest.read_text(encoding='utf-8'))}
    metadata = {'generator': 'built-in image_gen', 'format': 'RGBA PNG',
                'processing': 'alpha crop, proportional resize, transparent padding only',
                'prompts': 'docs/image-prompts-ui.json', 'icons': [], 'markers': []}
    for name in ICONS + MARKERS:
        source = Image.open(sources[name]).convert('RGBA')
        alpha = source.getchannel('A')
        if alpha.getextrema()[0] != 0:
            raise ValueError(f'{name}: missing transparent background')
        bounds = alpha.getbbox()
        if not bounds:
            raise ValueError(f'{name}: empty image')
        crop = source.crop(bounds)
        is_icon = name in ICONS
        size = 128 if is_icon else 256
        max_size = (116, 116) if is_icon else (224, 216)
        crop.thumbnail(max_size, Image.Resampling.LANCZOS)
        x = (size - crop.width) // 2
        y = (size - crop.height) // 2 if is_icon else 232 - crop.height
        canvas = Image.new('RGBA', (size, size))
        canvas.alpha_composite(crop, (x, y))
        group = 'icons' if is_icon else 'markers'
        relative = f'assets/ui/{group}/{name}.png'
        destination = ROOT / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(destination, optimize=True)
        metadata[group].append({'name': name, 'file': relative, 'frame_size': [size, size],
                                'pivot_x': size // 2, 'pivot_y': size // 2 if is_icon else 232,
                                'baseline_y': None if is_icon else 232,
                                'alpha_bounds': list(canvas.getchannel('A').getbbox()),
                                'recommended_display_size': 64 if is_icon else 128})
    metadata_path = ROOT / 'assets/metadata/ui_assets.json'
    metadata_path.parent.mkdir(parents=True, exist_ok=True)
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    # Review-only contact sheet shows true in-game icon scale on light/dark backgrounds.
    proof = Image.new('RGB', (768, 392), '#303336')
    draw = ImageDraw.Draw(proof)
    for i, name in enumerate(ICONS):
        x = i * 96 + 16
        icon = Image.open(ROOT / f'assets/ui/icons/{name}.png').convert('RGBA')
        icon = icon.resize((64, 64), Image.Resampling.LANCZOS)
        proof.paste(icon, (x, 16), icon)
        draw.rectangle((x - 8, 100, x + 72, 180), fill='#b4afa6')
        proof.paste(icon, (x, 108), icon)
        draw.text((i * 96 + 4, 188), name.replace('_icon', ''), fill='white')
    for i, name in enumerate(MARKERS):
        marker = Image.open(ROOT / f'assets/ui/markers/{name}.png').convert('RGBA')
        marker.thumbnail((128, 128), Image.Resampling.LANCZOS)
        proof.paste(marker, (i * 240 + 40, 224), marker)
        draw.text((i * 240 + 24, 366), name, fill='white')
    proof.save(ROOT / '.tools/ui-assets-review.png')
    print(f'Packed {len(ICONS)} icons and {len(MARKERS)} markers; alpha verified; marker baseline 232.')


if __name__ == '__main__':
    main()

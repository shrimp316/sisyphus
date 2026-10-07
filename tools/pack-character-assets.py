"""Pack generated, transparent animation sheets into the requested game format.

Only crops, uniformly resizes and pads existing RGBA pixels; no artwork is drawn.
Usage: python tools/pack-character-assets.py .tools/character-sources.json
"""
import json
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sources = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
metadata = {'frame_size': [512, 512], 'pivot_x': 256, 'pivot_y': 464,
            'baseline_y': 464, 'animations': []}
for source in sources:
    name = source['name']
    count = 8 if name == 'push' else 6
    cols = 4 if name == 'push' else 3
    src = Image.open(source['path']).convert('RGBA')
    frames = []
    for i in range(count):
        col, row = i % cols, i // cols
        cell = src.crop((round(col*src.width/cols), round(row*src.height/2),
                         round((col+1)*src.width/cols), round((row+1)*src.height/2)))
        bbox = cell.getchannel('A').point(lambda a: 255 if a > 16 else 0).getbbox()
        if not bbox:
            raise ValueError(f'{name} frame {i+1} has no artwork')
        frames.append(cell.crop(bbox))
    # Use one scale per animation to preserve pose/size differences, never fit each frame independently.
    target_height = {'idle': 396, 'push': 318, 'heavy_push': 292, 'brace': 348, 'exhausted': 310}[name]
    scale = min(target_height / max(f.height for f in frames), 432 / max(f.width for f in frames))
    folder = ROOT / 'assets/character/sisyphus' / name
    folder.mkdir(parents=True, exist_ok=True)
    sheet = Image.new('RGBA', (512*cols, 1024))
    bounds = []
    for i, frame in enumerate(frames):
        frame = frame.resize((round(frame.width*scale), round(frame.height*scale)), Image.Resampling.LANCZOS)
        x = 440-frame.width if name in ('push', 'heavy_push') else (512-frame.width)//2
        y = 464-frame.height
        canvas = Image.new('RGBA', (512, 512))
        canvas.alpha_composite(frame, (x, y))
        canvas.save(folder / f'{name}_{i+1:02}.png', optimize=True)
        sheet.alpha_composite(canvas, ((i%cols)*512, (i//cols)*512))
        bounds.append([x,y,x+frame.width,y+frame.height])
    sheet_folder = ROOT / 'assets/character/sisyphus/spriteframes'
    sheet_folder.mkdir(parents=True, exist_ok=True)
    sheet.save(sheet_folder/f'sisyphus_{name}_sheet.png', optimize=True)
    metadata['animations'].append({'animation_name': name, 'frame_count': count,
        'fps': 6 if name in ('idle','exhausted') else 8, 'loop': True,
        'frame_size': [512,512], 'pivot_x':256,'pivot_y':464,'baseline_y':464,
        'sheet_columns':cols, 'sheet_rows':2, 'bounds':bounds,
        'sheet':f'res://assets/character/sisyphus/spriteframes/sisyphus_{name}_sheet.png'})
    print(name, count, 'frames', 'scale', round(scale,3), 'bounds', bounds)
dest = ROOT / 'assets/metadata'
dest.mkdir(parents=True,exist_ok=True)
(dest/'sisyphus_animations.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
prompts = [{'asset':s['name'],'prompt':s['prompt'],'tool':'built-in image_gen'} for s in sources]
(ROOT/'docs/image-prompts-character.json').write_text(json.dumps(prompts,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

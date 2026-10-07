"""Crop generated six-cell RGBA FX sheets and pack consistent 256px frames."""
import json
import sys
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sources=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
meta=[]
for source in sources:
    name=source['name']
    src=Image.open(source['path']).convert('RGBA')
    folder=ROOT/'assets/fx'/name
    folder.mkdir(parents=True,exist_ok=True)
    sheet=Image.new('RGBA',(768,512))
    for i in range(6):
        c,r=i%3,i//3
        frame=src.crop((round(c*src.width/3),round(r*src.height/2),round((c+1)*src.width/3),round((r+1)*src.height/2)))
        frame=frame.resize((256,256),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',(256,256))
        canvas.alpha_composite(frame,(0,0 if name in ('wind','breath') else 4))
        canvas.save(folder/f'{name}_{i+1:02}.png',optimize=True)
        sheet.alpha_composite(canvas,(c*256,r*256))
    sheet.save(folder/f'{name}_sheet.png',optimize=True)
    fps={'dust':10,'gravel':12,'impact':14,'wind':6,'breath':6,'snow':8}[name]
    meta.append({'animation_name':name,'frame_count':6,'fps':fps,'frame_size':[256,256],
        'pivot_x':128,'pivot_y':128 if name in ('wind','breath') else 224,
        'loop':name != 'impact','sheet_columns':3,'sheet_rows':2,'source_alpha_preserved':True})
    print(name,'6 frames + sheet')
(ROOT/'assets/metadata/fx_animations.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8')
(ROOT/'docs/image-prompts-fx.json').write_text(json.dumps([{'asset':s['name'],'prompt':s['prompt'],'tool':'built-in image_gen'} for s in sources],indent=2)+'\n',encoding='utf-8')

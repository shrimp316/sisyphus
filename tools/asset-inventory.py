"""Validate the delivered art format and write a portable, hashed file inventory."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
expected={}
animations={'idle':6,'push':8,'heavy_push':6,'brace':6,'exhausted':6}
for name,count in animations.items():
    for i in range(1,count+1):
        expected[f'assets/character/sisyphus/{name}/{name}_{i:02}.png']=(512,512)
    expected[f'assets/character/sisyphus/spriteframes/sisyphus_{name}_sheet.png']=(2048 if count==8 else 1536,1024)
for name in ['default','rough','wet','snow']:
    expected[f'assets/boulder/boulder_{name}.png']=(384,384)
for name in ['rock_ground','gravel_ground','mud_ground','wet_rock','snow_ground','steep_slope_up','convex_slope_up','concave_slope_down','ledge','foothold_rest_platform','small_stone_step']:
    expected[f'assets/terrain/{name}.png']=(512,256)
for name in ['cairn_checkpoint','broken_signpost','dead_tree','small_tree','ruin_pillar','shrine_fragment','simple_arch_ruin']:
    expected[f'assets/props/{name}.png']=(384,384)
for name in ['dust','gravel','impact','wind','breath','snow']:
    for i in range(1,7):
        expected[f'assets/fx/{name}/{name}_{i:02}.png']=(256,256)
    expected[f'assets/fx/{name}/{name}_sheet.png']=(768,512)
for name in ['stamina','slip','brace','push_burst','checkpoint','height_marker','warning_wind','warning_rockfall']:
    expected[f'assets/ui/icons/{name}_icon.png']=(128,128)
for name in ['previous_record','event','rest_point']:
    expected[f'assets/ui/markers/{name}_marker.png']=(256,256)

records=[]
errors=[]
for path,size in expected.items():
    file=ROOT/path
    if not file.is_file():
        errors.append(f'Missing: {path}')
        continue
    image=Image.open(file)
    if image.mode!='RGBA' or image.size!=size:
        errors.append(f'Incorrect format: {path}: {image.mode}, {image.size}')
        continue
    alpha=image.getchannel('A')
    hist=alpha.histogram()
    if hist[0]==0 or alpha.getextrema()[1]<32:
        errors.append(f'Missing transparent background or visible pixels: {path}')
    if '/character/' in path and '/spriteframes/' not in path:
        bounds=alpha.point(lambda a:255 if a>32 else 0).getbbox()
        if abs(bounds[3]-464)>2:
            errors.append(f'Foot baseline moved: {path} {bounds}')
    records.append({'path':path,'size':list(size),'bytes':file.stat().st_size,
        'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),
        'transparent_pixel_fraction':round(hist[0]/(image.width*image.height),4),
        'alpha_bounds':list(alpha.getbbox())})
if errors:
    print('\n'.join(errors))
    raise SystemExit(1)
for name,count in animations.items():
    hashes=[r['sha256'] for r in records if r['path'].startswith(f'assets/character/sisyphus/{name}/')]
    if len(set(hashes))!=count:
        raise SystemExit(f'Duplicate animation frame: {name}')
manifest={'schema_version':1,'asset_count':len(records),'individual_pngs':101,'spritesheets':11,
          'total_bytes':sum(r['bytes'] for r in records),'files':records}
(ROOT/'assets/metadata/asset_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print(f'PASS: {len(records)} RGBA PNGs; sizes, transparency, character baselines and distinct frames verified.')
print(f'Total PNG bytes: {manifest["total_bytes"]:,}')

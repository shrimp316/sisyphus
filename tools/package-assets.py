"""Create a self-contained Godot preview project for the delivered asset pack."""
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'assets/metadata/asset_manifest.json').read_text(encoding='utf-8'))
files={root/record['path'] for record in manifest['files']}
for folder in ['assets/metadata','godot/resources/spriteframes','godot/scenes/preview']:
    files.update(p for p in (root/folder).rglob('*') if p.is_file() and p.suffix!='.import')
files.update(root/p for p in ['scripts/asset_visuals.gd','scripts/asset_preview.gd','README_ASSETS.md'])
files.update((root/'docs').glob('image-prompts-*.json'))
files.add(root/'tools/generate-godot-assets.gd')
project='''config_version=5

[application]
config/name="SISYPHUS Art Pack Preview"
run/main_scene="res://godot/scenes/preview/character_preview.tscn"
config/features=PackedStringArray("4.5", "GL Compatibility")

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'''
output=root/'builds/SISYPHUS-ArtPack-v0.2.zip'
output.parent.mkdir(parents=True,exist_ok=True)
with ZipFile(output,'w',ZIP_DEFLATED,compresslevel=6) as archive:
    archive.writestr('SISYPHUS-ArtPack/project.godot',project)
    for file in sorted(files):
        archive.write(file,'SISYPHUS-ArtPack/'+file.relative_to(root).as_posix())
print(f'{output}: {output.stat().st_size:,} bytes, {len(files)+1} files')

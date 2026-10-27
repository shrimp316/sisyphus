"""Export only the independent tablet preview; never alter the game or its presets."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', default='builds/mastery-unlock-150-400-700')
    parser.add_argument('--results', default='tests/mastery/results/unlock-150-400-700/preview-web')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = root / args.output_dir
    results = root / args.results
    output.mkdir(parents=True, exist_ok=True)
    results.mkdir(parents=True, exist_ok=True)
    engine = root / '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
    template = root / '.tools/export-templates/web_nothreads_debug.zip'
    start = time.perf_counter()
    with tempfile.TemporaryDirectory(prefix='sisyphus-mastery-v12-') as folder:
        project = Path(folder)
        for relative in ['assets/fonts', 'assets/ui/mastery', 'ui/themes',
                         'godot/scenes/mastery', 'scripts/mastery']:
            shutil.copytree(root / relative, project / relative)
        (project / 'data/mastery').mkdir(parents=True)
        for name in ['mastery_node_layout_v12.csv', 'mastery_node_layout_v12.csv.import',
                     'mastery_greek_inscriptions_v12.json', 'mastery_preview_fixtures.json',
                     'mastery_act_schema_v12.json']:
            shutil.copyfile(root / 'data/mastery' / name, project / 'data/mastery' / name)
        # This existing model runs in memory only; no main scene or save code is packaged.
        shutil.copyfile(root / 'scripts/progression.gd', project / 'scripts/progression.gd')
        source_sha256 = {p.relative_to(project).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                         for folder_name in ['scripts', 'godot', 'data']
                         for p in sorted((project / folder_name).rglob('*'))
                         if p.is_file() and p.suffix in {'.gd', '.tscn', '.json', '.csv', '.import'}}
        (project / 'project.godot').write_text('''config_version=5
[application]
config/name="SISYPHUS Mastery Isolated Preview v1.2"
run/main_scene="res://godot/scenes/mastery/mastery_preview.tscn"
config/features=PackedStringArray("4.5", "GL Compatibility")
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
''', encoding='utf-8')
        (project / 'export_presets.cfg').write_text('''[preset.0]
name="Mastery Preview Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="*.csv,*.json"
exclude_filter=""
script_export_mode=2
[preset.0.options]
custom_template/debug="%s"
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
''' % template.as_posix(), encoding='utf-8')
        commands = [
            [str(engine), '--headless', '--editor', '--path', str(project), '--import'],
            [str(engine), '--headless', '--path', str(project), '--export-debug',
             'Mastery Preview Web', str(output / 'index.html')],
        ]
        for name, command in zip(['import', 'export'], commands):
            completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, encoding='utf-8', errors='replace', timeout=240)
            (results / f'{name}.txt').write_text(completed.stdout, encoding='utf-8')
            if completed.returncode or 'SCRIPT ERROR:' in completed.stdout or '\nERROR:' in completed.stdout:
                raise RuntimeError(f'{name} failed; see {results / (name + ".txt")}')
    for source in [root / 'assets/fonts/OFL.txt', *sorted((root / 'assets/fonts/licenses').glob('*OFL*')),
                   root / 'third_party/godot/LICENSE.txt', root / 'third_party/godot/COPYRIGHT.txt']:
        if source.is_file():
            target = output / 'licenses' / (source.parent.name + '-' + source.name)
            target.parent.mkdir(exist_ok=True)
            shutil.copyfile(source, target)
    manifest = {
        'kind': 'isolated_preview_debug_export', 'engine': 'Godot 4.5.1',
        'duration_seconds': round(time.perf_counter() - start, 3),
        'production_project_or_presets_changed': False,
        'source_sha256': source_sha256,
        'files': {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                  for p in sorted(output.glob('index.*')) if p.is_file()},
        'browser_runtime': 'recorded separately; export success alone is not runtime PASS',
    }
    (results / 'build_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()

"""Export the isolated glyph sample without changing the playable MVP or saves."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', default='builds/typography-sample')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    engine = root / '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
    template = (root / '.tools/export-templates/web_nothreads_debug.zip').as_posix()
    output = root / args.output_dir
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='sisyphus-typography-') as temp:
        project = Path(temp)
        shutil.copytree(root / 'assets/fonts', project / 'assets/fonts')
        shutil.copytree(root / 'ui/themes', project / 'ui/themes')
        shutil.copyfile(root / 'tests/mvp/typography_sample.tscn', project / 'typography_sample.tscn')
        (project / 'project.godot').write_text('''config_version=5
[application]
config/name="SISYPHUS typography sample"
run/main_scene="res://typography_sample.tscn"
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
name="Typography Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
script_export_mode=2
[preset.0.options]
custom_template/debug="%s"
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/canvas_resize_policy=2
''' % template, encoding='utf-8')
        subprocess.run([str(engine), '--headless', '--editor', '--path', str(project), '--quit'], check=True)
        with (project / 'project.godot').open('a', encoding='utf-8') as settings:
            settings.write('\n[gui]\ntheme/custom="res://ui/themes/sisyphus_theme.tres"\n')
        subprocess.run([str(engine), '--headless', '--path', str(project), '--export-debug',
                        'Typography Web', str(output / 'index.html')], check=True)
    print(output / 'index.html')


if __name__ == '__main__':
    main()

"""Export the isolated MVP; never deploy or touch the production Web preset."""
import argparse
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='.tools/godot/Godot_v4.5.1-stable_win64_console.exe')
    parser.add_argument('--qa', action='store_true', help='Include local synthetic save controls')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    engine = Path(args.godot)
    if not engine.is_absolute():
        engine = root / engine
    output = root / 'builds/mvp-web'
    output.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(engine), '--headless', '--path', str(root), '--export-debug',
                    'MVP Web', str(output / 'index.html')], check=True)
    for source, destination in [
        ('third_party/godot/LICENSE.txt', 'GODOT-LICENSE.txt'),
        ('third_party/godot/COPYRIGHT.txt', 'GODOT-COPYRIGHT.txt'),
        ('assets/fonts/OFL.txt', 'FONT-LICENSE.txt'),
    ]:
        shutil.copyfile(root / source, output / destination)
    if args.qa:
        shutil.copyfile(root / 'tests/mvp/web_qa.html', output / 'qa.html')
        shutil.copytree(root / 'tests/mvp/fixtures/web', output / 'fixtures', dirs_exist_ok=True)
    print(output / 'index.html')


if __name__ == '__main__':
    main()

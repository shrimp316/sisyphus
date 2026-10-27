"""Archive focused existing MVP regression without replacing prior evidence."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'tests/mastery/results/v12-patch/verification'
ENGINE = ROOT / '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    historical = ROOT / 'tests/mvp/results/ui-components.json'
    old = historical.read_bytes() if historical.exists() else None
    suites = ['test_mastery_progression', 'test_mastery_save', 'test_save_contract', 'test_mvp_ui', 'test_mvp_integration']
    results = []
    try:
        for suite in suites:
            command = [str(ENGINE), '--headless', '--path', str(ROOT), '--script', f'res://tests/mvp/{suite}.gd']
            if suite == 'test_mvp_integration':
                command += ['--', '--save-path=user://mvp-integration-patch-' + uuid.uuid4().hex + '.json']
            result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
            output = result.stdout + result.stderr
            (OUTPUT / (suite + '.txt')).write_text(output, encoding='utf-8')
            parsed = None
            for line in output.splitlines():
                try:
                    candidate = json.loads(line)
                except ValueError:
                    continue
                if isinstance(candidate, dict) and 'checks' in candidate and 'failures' in candidate:
                    parsed = candidate
            if parsed is None:
                matches = re.findall(r'(\d+) checks (\d+) failures', output)
                if matches:
                    parsed = {'checks': int(matches[-1][0]), 'failures': int(matches[-1][1])}
            passed = result.returncode == 0 and parsed is not None and not parsed['failures'] and not re.search(r'SCRIPT ERROR:|\bERROR:', output)
            results.append({'suite': suite, 'exit': result.returncode, 'passed': passed, 'summary': parsed,
                            'command': command, 'log_sha256': hashlib.sha256(output.encode()).hexdigest()})
            print(suite, 'PASS' if passed else 'FAIL', parsed, flush=True)
    finally:
        if old is not None:
            historical.write_bytes(old)
        elif historical.exists():
            historical.unlink()
    before = json.loads((OUTPUT / 'protected_before.json').read_text(encoding='utf-8'))
    changes = [name for name, digest in before.items() if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest]
    allowed_changes = [name for name in changes if name == 'export_presets.cfg']
    unexpected_changes = [name for name in changes if name != 'export_presets.cfg']
    report = {'suites': results, 'protected_files_checked': len(before), 'protected_files_changed': changes,
              'approved_export_only_changes': allowed_changes, 'unexpected_protected_changes': unexpected_changes,
              'historical_ui_result_preserved': old is None or historical.read_bytes() == old,
              'passed': all(s['passed'] for s in results) and not unexpected_changes,
              'scope': 'These existing UI tests exercise the retained old board scene; new live board is tested separately.'}
    (OUTPUT / 'existing_regression.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

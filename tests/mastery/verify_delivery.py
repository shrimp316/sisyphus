"""Check protected files, exported source identity, browser evidence and local report links."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'tests/mastery/results/v12'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    before = json.loads((OUT / 'protected_before.json').read_text(encoding='utf-8'))
    changed = [name for name, digest in before['tracked_files'].items()
               if not (ROOT / name).exists() or sha(ROOT / name) != digest]
    build = json.loads((OUT / 'web/build_manifest.json').read_text(encoding='utf-8'))
    source_changes = [name for name, digest in build['source_sha256'].items() if sha(ROOT / name) != digest]
    logs = json.loads((OUT / 'web/final-browser-console.json').read_text(encoding='utf-8'))
    states = [json.loads(x['message'].split(' ', 1)[1]) for x in logs
              if x['message'].startswith('MASTERY_PREVIEW_STATE ')]
    expected = {'zero': 0, '250': 10, '500': 20, '750': 30, 'first_summit': 30, 'next_run': 35}
    observed = {key: any(s['fixture'] == key and s['eligible'] == value for s in states)
                for key, value in expected.items()}
    errors = [x for x in logs if x['level'] == 'error']
    browser = {
        'engine': 'Godot 4.5.1 WebGL2 single-threaded debug export',
        'browser': 'Codex in-app Chromium',
        'node_count_35': any(x['message'] == 'MASTERY_PREVIEW_READY nodes=35' for x in logs),
        'six_fixture_expected_eligibility': expected,
        'six_fixture_log_pass': observed,
        'console_errors_final_run': errors,
        'manual_observations': [
            'Clicked all five milestone/run buttons after initial zero state; captured each.',
            'Selected special01 after next_run; unknown effect/cost and disabled purchase visible.',
            'Selected strength01 then clicked purchase after selection rendered: EXP600 unchanged, points6->5, ranks0->1.',
            'Clicked disabled purchased button again: points5 and rank1 unchanged.',
            'Tab and Enter changed selected strength01 to strength02, confirmed console.',
            'Escape hid screen; milestone button reopened screen, preview controls remained usable.',
            'Clicked animation skip and continued using UI.',
        ],
        'screenshots': {p.name: {'size': list(Image.open(p).size), 'sha256': sha(p)}
                        for p in sorted((OUT / 'web').glob('*.png'))},
        'limitations': ['No Firefox or Linux run.', 'Browser capture946x884 with letterboxed board; other sizes tested native only.',
                        'Loadtime, FPS, GPU/process memory and Godot Profiler memory not measured.'],
    }
    browser['pass'] = browser['node_count_35'] and all(observed.values()) and not errors
    (OUT / 'web/browser_review.json').write_text(json.dumps(browser, indent=2, ensure_ascii=False), encoding='utf-8')
    tracked = set(before['tracked_files'])
    owned = [ROOT / p for p in ['scripts/mastery', 'godot/scenes/mastery', 'docs/mastery', 'tests/mastery']]
    files = [p for folder in owned for p in folder.rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    files += [p for p in (ROOT / 'data/mastery').glob('mastery_*') if p.is_file()]
    # Include the generated inventories themselves, which are first created below.
    files += [ROOT / 'docs/mastery/changed_files_v12.md', OUT / 'delivery_review.json']
    additions = sorted({p.relative_to(ROOT).as_posix() for p in files if p.relative_to(ROOT).as_posix() not in tracked})
    lines = ['# v1.2 추가 파일 전체 목록', '',
             '기존 추적 파일 수정: 0개. 기존 미추적 PNG131개는 원래 위치에서 그대로 재사용하며 이 목록의 신규 생성 파일에 포함하지 않는다.', '',
             '자동 생성된 `.uid`와 새 CSV의 keep import sidecar를 포함한다. `builds/mastery-v12/`의 export는 Git ignore 대상이며 build_manifest에서 별도 목록/크기/해시를 제공한다.', '']
    lines += [f'- [{name}](../../{name})' for name in additions]
    (ROOT / 'docs/mastery/changed_files_v12.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    broken = []
    link_count = 0
    for path in (ROOT / 'docs/mastery').glob('*.md'):
        for target in re.findall(r'\]\(([^)]+)\)', path.read_text(encoding='utf-8')):
            if target.startswith(('http:', 'https:', '#')):
                continue
            link_count += 1
            destination = (path.parent / target.split('#')[0]).resolve()
            if not destination.exists() and destination != OUT / 'delivery_review.json':
                broken.append({'file': path.name, 'target': target})
    report = {
        'baseline_head': before['head'],
        'current_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'branch': subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip(),
        'protected_tracked_file_count': len(tracked), 'protected_tracked_files_changed': changed,
        'build_source_count': len(build['source_sha256']), 'build_source_mismatches': source_changes,
        'new_file_count': len(additions), 'local_document_links_checked': link_count, 'broken_links': broken,
        'browser_pass': browser['pass'],
        'pass': not changed and not source_changes and not broken and browser['pass'],
    }
    (OUT / 'delivery_review.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if report['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

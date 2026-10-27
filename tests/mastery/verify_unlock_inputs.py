"""Verify that the authorized unlock change touches milestone fields, not layout/art/economy."""
import csv
import hashlib
from io import StringIO
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'tests/mastery/results/unlock-150-400-700/preview/input_integrity.json'
ORIGINAL = Path('C:/Users/PMS/Downloads/SISYPHUS_mastery_assets_v1_1_GREEK_RESTORED.zip')
PATCH = Path('C:/Users/PMS/Downloads/SISYPHUS_mastery_assets_v1_2_PATCH_ONLY.zip')
SOURCE_ROOT = 'SISYPHUS_mastery_assets_v1_1_GREEK_RESTORED/'
PATCH_ROOT = 'SISYPHUS_mastery_assets_v1_2_PATCH_ONLY/'


def main():
    checks = []

    def check(label, value):
        checks.append({'name': label, 'pass': bool(value)})

    source_bytes = (ROOT / 'data/mastery/mastery_node_layout_v12.csv').read_bytes()
    current = list(csv.DictReader(StringIO(source_bytes.decode('utf-8-sig'))))
    mapping = {'250': '150', '500': '400', '750': '700'}
    with zipfile.ZipFile(ORIGINAL) as original:
        before = list(csv.DictReader(StringIO(original.read(SOURCE_ROOT + 'mastery_greek_node_mapping_v11.csv').decode('utf-8-sig'))))
        check('35 unchanged logical node IDs/order', len(current) == 35 and [x['node_id'] for x in current] == [x['node_id'] for x in before])
        changed = []
        for old, new in zip(before, current):
            expected = dict(old)
            if old['track'] != 'special':
                expected['milestone_m'] = mapping[old['milestone_m']]
            check('only authorized milestone field differs: ' + new['node_id'], new == expected)
            changed.extend({'node_id': new['node_id'], 'field': field, 'before': old[field], 'after': new[field]}
                           for field in old if old[field] != new[field])
        check('exactly 30 normal milestone fields changed', len(changed) == 30 and all(x['field'] == 'milestone_m' for x in changed))
        with zipfile.ZipFile(PATCH) as patch:
            replacements = {name[len(PATCH_ROOT):]: patch.read(name) for name in patch.namelist() if name.endswith('.png')}
        asset_count = 0
        for name in original.namelist():
            relative = name[len(SOURCE_ROOT):]
            if relative.startswith('assets/ui/mastery/') and relative.endswith('.png'):
                asset_count += 1
                check('PNG preserved from approved baseline/patch: ' + relative,
                      (ROOT / relative).read_bytes() == replacements.get(relative, original.read(name)))
        check('all 131 approved PNGs checked', asset_count == 131)
    fixtures = json.loads((ROOT / 'data/mastery/mastery_preview_fixtures.json').read_text(encoding='utf-8'))
    check('six current fixture IDs', [x['id'] for x in fixtures] == ['zero', '150', '400', '700', 'first_summit', 'next_run'])
    expected = {'zero': (0, 0, 0), '150': (150, 90, 10), '400': (400, 240, 20), '700': (700, 420, 30),
                'first_summit': (1000, 600, 30), 'next_run': (0, 600, 35)}
    for fixture in fixtures:
        check('existing XP rule and new eligibility: ' + fixture['id'],
              (fixture['current_distance'], fixture['total_xp'], fixture['expected_eligible']) == expected[fixture['id']])
    schema = json.loads((ROOT / 'data/mastery/mastery_act_schema_v12.json').read_text(encoding='utf-8'))
    check('act1 schema milestones', schema['acts'][0]['normal_unlock_milestones'] == [150, 400, 700])
    for act in schema['acts'][1:]:
        check('future act remains unspecified: ' + str(act['act']),
              not act['implemented'] and all(act[key] is None for key in ['layout', 'effects', 'costs', 'gates']))
    result = {'passed': all(x['pass'] for x in checks), 'checks': len(checks),
              'failures': [x['name'] for x in checks if not x['pass']], 'changed_csv_fields': changed,
              'mapping_sha256': hashlib.sha256(source_bytes).hexdigest(), 'png_count': asset_count,
              'scope': 'Compare current layout against supplied original CSV with only explicit milestone substitution; all authorized patched/unpatched PNG bytes retained.'}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: result[key] for key in ['passed', 'checks', 'failures', 'png_count']}, ensure_ascii=False))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

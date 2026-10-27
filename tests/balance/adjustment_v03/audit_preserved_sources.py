"""Read-only comparison against recorded v0.2/v0.3 hashes."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "tests/balance/results/act1-adjustment-v03"


def resolve(label):
    path = Path(label)
    if path.exists():
        return path
    normalized = str(label).replace("\\", "/")
    if "/tests/" in normalized:
        return ROOT / ("tests/" + normalized.split("/tests/", 1)[1])
    return ROOT / normalized


def main():
    checks = []

    def check(group, label, expected):
        path = resolve(label)
        actual = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
        checks.append(dict(group=group, path=str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path), expected=expected, actual=actual, match=expected == actual))

    current = json.loads((OUTPUT / "factors-pilot/manifest.json").read_text(encoding="utf-8"))
    for name, expected in current["code_sha256"].items():
        check("v03_factor_start_source_snapshot", name, expected)
    old_root = ROOT / "tests/balance/results/act1-adjustment-v02"
    old = json.loads((old_root / "manifest.json").read_text(encoding="utf-8"))
    for item in old["input_files"]:
        check("v02_recorded_raw_dataset", item["jsonl"], item["sha256"])
    for name, expected in old["output_csv_sha256"].items():
        check("v02_recorded_csv", old_root / name, expected)
    for group, values in [("v02_recorded_analysis_source", old["analysis_code_sha256"]), ("v02_recorded_evidence", old["evidence_artifacts"])]:
        for name, expected in values.items():
            check(group, name, expected)
    # Latest v02 route source manifest catches its standalone helpers as well.
    previous = json.loads((old_root / "gate-route-campaigns-ledge-aware/manifest.json").read_text(encoding="utf-8"))
    for name, expected in previous["code_sha256"].items():
        check("v02_route_recorded_source", name, expected)
    payload = {"checks": len(checks), "failures": sum(not item["match"] for item in checks), "results": checks,
               "scope": "All files covered by the listed recorded manifests; this does not claim a complete directory snapshot of unrelated user UI/design/untracked files."}
    (OUTPUT / "preserved-source-audit.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: payload[key] for key in ("checks", "failures")}))
    for item in checks:
        if not item["match"]:
            print(json.dumps(item, ensure_ascii=False))
    return 1 if payload["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())

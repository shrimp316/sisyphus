"""Run the current MVP regression suites using only the Python standard library.

Example: python tests/mvp/run_checks.py --godot .tools/godot/Godot_v4.5.1-stable_win64_console.exe --snapshot
Logs always go to a new run directory. --snapshot also archives measured sources.
The old source-instrumentation refusal is expected, not counted as passing tests.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r"(?:SCRIPT ERROR:|\bERROR:|Parse Error:|^\s*FAIL(?:\s|:))", re.MULTILINE)
GUARD_ERROR = "ERROR: Production controller changed; v02 scalar instrumentation refuses an unaudited source"
GUARD_FAILURE = "FAIL production SHA and unique anchors permit exact scalar instrumentation"
LEGACY_INVALID_JSON = "ERROR: Parse JSON failed. Error at line 0: Expected key"
NEW_SUITES = [
    ("mastery_progression", "test_mastery_progression.gd", 113),
    ("mastery_save", "test_mastery_save.gd", 109),
    ("mastery_physics", "test_mastery_physics.gd", 155),
    ("save_contract", "test_save_contract.gd", 167),
    ("ui", "test_mvp_ui.gd", 186),
    ("integration", "test_mvp_integration.gd", 242),
    ("storage_faults", "test_storage_faults.gd", 18),
    ("s190_verify", "s190_verify.gd", 15),
]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources() -> dict[str, str]:
    files = [ROOT / "project.godot", ROOT / "main.tscn", Path(__file__)]
    for folder, patterns in [("scripts", ("*.gd",)), ("data", ("*.json", "*.tres")),
                             ("scenes", ("*.tscn",)), ("tests", ("*.gd",))]:
        for pattern in patterns:
            files.extend((ROOT / folder).rglob(pattern))
    files.extend((ROOT / "tests/balance").rglob("policies.json"))
    # Generated evidence/source archives are outputs, never new runtime inputs.
    return {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(set(files))
            if "results" not in p.relative_to(ROOT).parts}


def summary(text: str) -> tuple[int | None, int | None]:
    for line in reversed(text.splitlines()):
        try:
            obj = json.loads(line)
        except (ValueError, TypeError):
            continue
        if isinstance(obj, dict) and isinstance(obj.get("checks"), int) and "failures" in obj:
            failures = obj["failures"]
            return obj["checks"], len(failures) if isinstance(failures, list) else int(failures)
    matches = re.findall(r"(\d+)\s+checks[,;\s]+(\d+)\s+failures", text)
    return tuple(map(int, matches[-1])) if matches else (None, None)


def suites(run_id: str) -> list[dict]:
    phase_b = json.loads((ROOT / "tests/mvp/results/phase-b-independent.json").read_text(encoding="utf-8-sig"))
    baseline = json.loads((ROOT / "tests/mvp/results/baseline.json").read_text(encoding="utf-8-sig"))
    original = {row["name"]: row for row in baseline["suites"]}
    result = []
    for row in phase_b["suites"]:
        if row["name"] == "mastery_physics":
            continue
        command = original[row["name"]]["command"]
        extra = command[command.index("--") + 1:] if "--" in command else []
        result.append({"name": row["name"], "script": row["script"], "args": extra,
                       "minimum_checks": row["passed_checks"],
                       "expected_rejection": row["expected_guard_rejection"], "legacy": True})
    for name, script, count in NEW_SUITES:
        extra = ["--save-path=user://mvp-integration-regression-" + run_id + ".json"] if name == "integration" else []
        result.append({"name": name, "script": "tests/mvp/" + script, "args": extra,
                       "minimum_checks": count, "expected_rejection": False, "legacy": False})
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / ".tools/godot/Godot_v4.5.1-stable_win64_console.exe")
    parser.add_argument("--output", type=Path, default=ROOT / "tests/mvp/results/final-regression.json")
    parser.add_argument("--logs-dir", type=Path, default=ROOT / "tests/mvp/results/final-regression-logs")
    parser.add_argument("--timeout", type=float, default=300, help="Per-suite timeout in seconds")
    parser.add_argument("--snapshot", action="store_true", help="Archive exact measured sources alongside logs")
    args = parser.parse_args()
    godot = args.godot.resolve()
    if not godot.is_file():
        parser.error("Godot executable not found: " + str(godot))
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:8]
    logs = args.logs_dir.resolve() / run_id
    logs.mkdir(parents=True, exist_ok=False)
    before = sources()
    if args.snapshot:
        for relative in before:
            target = logs / "source" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
    report = {"run_id": run_id, "started_at_utc": datetime.now(timezone.utc).isoformat(),
              "godot": str(godot), "source_sha256_before": before, "suites": [],
              "source_snapshot": str(logs / "source") if args.snapshot else None}
    for suite in suites(run_id):
        command = [str(godot), "--headless", "--path", str(ROOT), "--script", suite["script"]]
        if suite["args"]:
            command += ["--", *suite["args"]]
        start = time.monotonic()
        timed_out = False
        try:
            process = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     timeout=args.timeout, encoding="utf-8", errors="replace")
            code, output = process.returncode, process.stdout
        except subprocess.TimeoutExpired as error:
            code, timed_out = None, True
            output = error.output or b""
            if isinstance(output, bytes): output = output.decode("utf-8", errors="replace")
        log = logs / (suite["name"] + ".txt")
        log.write_text(output, encoding="utf-8")
        checks, failures = summary(output)
        errors = [line for line in output.splitlines() if ERROR.search(line)]
        expected_diagnostics = []
        # The legacy web test deliberately loads malformed JSON from both
        # backends. Only its two exact diagnostics are expected; script/parser
        # errors, extra copies, or any other ERROR still fail the suite.
        if suite["name"] == "web" and errors.count(LEGACY_INVALID_JSON) == 2:
            expected_diagnostics = [LEGACY_INVALID_JSON, LEGACY_INVALID_JSON]
            errors = [line for line in errors if line != LEGACY_INVALID_JSON]
        if suite["expected_rejection"]:
            passed = code == 1 and not timed_out and errors == [GUARD_ERROR, GUARD_FAILURE]
            status = "expected_rejection" if passed else "unexpected_guard_result"
            checks = 0
        else:
            passed = code == 0 and not timed_out and not errors and failures == 0 and checks is not None and checks >= suite["minimum_checks"]
            status = "passed" if passed else "failed"
        result = {**suite, "status": status, "expectation_met": passed, "exit_code": code,
                  "timed_out": timed_out, "verified_checks": checks, "failures": failures,
                  "error_lines": errors, "expected_diagnostics": expected_diagnostics,
                  "command": command, "seconds": round(time.monotonic()-start, 3),
                  "log": str(log), "log_sha256": sha(log)}
        report["suites"].append(result)
        print(f"{suite['name']}: {status}, checks={checks}, exit={code}", flush=True)
    after = sources()
    report["source_sha256_after"] = after
    report["changed_sources"] = [key for key in sorted(set(before) | set(after)) if before.get(key) != after.get(key)]
    report["all_expectations_met"] = not report["changed_sources"] and all(row["expectation_met"] for row in report["suites"])
    report["legacy_checks_passed"] = sum(row["verified_checks"] or 0 for row in report["suites"] if row["legacy"] and row["status"] == "passed")
    report["current_checks_passed"] = sum(row["verified_checks"] or 0 for row in report["suites"] if row["status"] == "passed")
    report["expected_rejections"] = sum(row["status"] == "expected_rejection" for row in report["suites"])
    report["archived_checks_not_executed"] = 21
    report["completed_at_utc"] = datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    args.output.write_text(encoded, encoding="utf-8")
    (logs / "report.json").write_text(encoded, encoding="utf-8")
    print(f"All expectations met: {report['all_expectations_met']}; checks: {report['current_checks_passed']}; report: {args.output}")
    return 0 if report["all_expectations_met"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

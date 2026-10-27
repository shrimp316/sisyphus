#!/usr/bin/env python3
"""Independent discrete resource-budget audit and actual-controller boundary fixtures."""
import argparse
import hashlib
import json
import math
import os
import subprocess
from fractions import Fraction
from pathlib import Path


def resource_check(capacity):
    # Exact arithmetic. This is a relaxed PUSH-ONLY schedule check, not an
    # exhaustive controller search; the algebra covers other resource losses.
    unit = Fraction(17, 6000)
    count = math.ceil(Fraction(capacity, 1) / unit)
    best_at = [-1] * (count + 15)
    best_at[0] = 0
    best = 0
    for spent in range(count):
        if best_at[spent] < 0:
            continue
        remaining = capacity * 6000 - 17 * spent
        weight = 100 if 2 * remaining >= capacity * 6000 else (85 if 5 * remaining >= capacity * 6000 else 65)
        for quantum in (4, 5, 12, 15):
            score = best_at[spent] + quantum * weight
            if spent + quantum >= count:
                best = max(best, score)
            else:
                best_at[spent + quantum] = max(best_at[spent + quantum], score)
    actual = best * unit / 100
    upper = Fraction(885, 1000) * capacity + Fraction(51, 1200)
    return {"capacity": capacity, "exact_relaxed_push_budget": str(actual), "relaxed_push_budget": float(actual),
            "certificate_bound": float(upper), "margin": float(upper - actual), "passes": actual <= upper}


def main():
    project = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, default=project / ".tools/godot/Godot_v4.5.1-stable_win64_console.exe")
    parser.add_argument("--output-dir", type=Path, default=project / "tests/balance/results/act1-adjustment-v02")
    parser.add_argument("--certificate", type=Path, default=project / "tests/balance/results/act1-adjustment-v02/gate-bound-123.json")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    step_path = output / "proof-review-step.json"
    command = [str(args.engine.resolve()), "--headless", "--path", str(project), "--script",
               "tests/balance/adjustment_v02/verify_proof_review.gd", "--", "--output", str(step_path)]
    process = subprocess.run(command, cwd=project, capture_output=True, text=True, encoding="utf-8", errors="replace",
                             creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0, timeout=600)
    (output / "proof-review-step.log").write_text(process.stdout + process.stderr, encoding="utf-8")
    if process.returncode or "SCRIPT ERROR:" in process.stdout + process.stderr:
        raise RuntimeError("Controller boundary audit failed; inspect proof-review-step.log")
    step = json.loads(step_path.read_text(encoding="utf-8"))
    original = json.loads(args.certificate.read_text(encoding="utf-8"))
    source = project / "scripts/boulder_controller.gd"
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    if step["source_sha256"] != source_hash or original["source_sha256"] != source_hash:
        raise RuntimeError("Proof/controller source hashes disagree")
    checks = [resource_check(capacity) for capacity in (100, 116, 118, 120)]
    certificate = next(item for item in original["certificates"] if item["ranks"] == {"strength": 0, "endurance": 0})
    if step["failures"] or not all(item["passes"] for item in checks) or not certificate["zero_input_space_certificate"]:
        raise RuntimeError("Independent checks did not support conditional gate certificate")
    artifacts = [source, Path(__file__).resolve(), Path(__file__).with_suffix(".gd").resolve(), args.certificate.resolve(),
                 project / "tests/balance/results/act1-adjustment-v02/generated_controller.gd"]
    payload = {"review_status": "conditional_acceptance", "source_controller_sha256": source_hash,
               "gate_certificate": certificate, "one_step_boundary_audit": step, "weighted_stamina_exact_DP": checks,
               "reproduction_command": command,
               "artifact_sha256": {str(path.relative_to(project)).replace("\\", "/"): hashlib.sha256(path.read_bytes()).hexdigest() for path in artifacts},
               "DP_assumptions": "Exact push-only relaxed schedules use quanta [4,5,12,15]*(17/6000); no recovery. This corroborates the analytic bound, not an exhaustive audit of non-push losses or all physics states.",
               "excluded_claims": ["No conclusion about original game or A/B/C without the no-recovery gate", "Entry fixtures do not establish full-route or human reachability", "No proof of safe retreat or campaign duration", "IEEE floating-point formal verification not performed"]}
    (output / "proof-review.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"review_status": payload["review_status"], "boundary_checks": step["checks"], "failures": step["failures"], "resource_DP_checks": len(checks)}))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Independent exact-rational checks of the proposed v0.3 resource certificate."""
from fractions import Fraction as F
from pathlib import Path
import hashlib
import json
import math
import random

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "tests/balance/results/act1-adjustment-v03"
Q = F(17, 400)  # largest nominal push drain, 3*1.7/120


def rho(stamina, capacity):
    return F(1) if stamina >= capacity / 2 else F(17, 20) if stamina >= capacity / 5 else F(13, 20) if stamina > 0 else F(0)


def primitive(stamina, capacity):
    return F(13, 20) * min(stamina, capacity / 5) + F(17, 20) * min(max(stamina - capacity / 5, F(0)), 3 * capacity / 10) + max(stamina - capacity / 2, F(0))


def energy(stamina, capacity):
    return primitive(stamina + Q, capacity) - primitive(Q, capacity)


def verify():
    comparisons, schedules, overdraws = 0, 0, 0
    rng = random.Random(73031)
    drains = [F(17, 1500), F(17, 1200), F(17, 500), Q]
    for capacity in map(F, (100, 112, 116, 120)):
        assert energy(capacity, capacity) == F(177, 200) * capacity + F(7, 20) * Q
        locations = {F(0), F(1), capacity}
        for center in (Q, capacity / 5, capacity / 2, capacity / 5 - Q, capacity / 2 - Q):
            locations.update(center + epsilon for epsilon in (F(-1, 10**9), F(0), F(1, 10**9)))
        for stamina in sorted(locations):
            if not 0 <= stamina <= capacity:
                continue
            for drain in drains:
                if stamina >= drain:
                    assert energy(stamina, capacity) - energy(stamina - drain, capacity) >= rho(stamina, capacity) * drain
                elif stamina > 0:
                    assert rho(stamina, capacity) * drain <= energy(stamina, capacity) + F(13, 20) * Q
                comparisons += 1
            for added in (F(0), F(1, 10**9), F(7, 120), F(1), F(80)):
                after = min(capacity, stamina + added)
                assert energy(after, capacity) - energy(stamina, capacity) <= after - stamina
                comparisons += 1
        for _ in range(30):
            stamina, recovered, weighted, overdraw_count = capacity, F(0), F(0), 0
            for step in range(2000):
                choice = rng.randrange(8)
                if choice < 4 and stamina > 0:
                    drain = drains[choice]
                    weighted += rho(stamina, capacity) * drain
                    overdraw_count += int(drain > stamina)
                    stamina = max(F(0), stamina - drain)
                elif choice in (4, 5) and stamina >= 1 and recovered < 80:
                    actual = min(capacity - stamina, F(rng.randrange(1, 101), 10), 80 - recovered)
                    stamina += actual
                    recovered += actual
                elif choice == 6:
                    stamina = max(F(0), stamina - F(17, 300))  # brace loss
                elif choice == 7 and rng.randrange(100) == 0:
                    stamina = max(F(0), stamina - 8)  # an arbitrary non-propulsive loss
                assert weighted <= energy(capacity, capacity) + recovered + F(13, 20) * Q
                assert overdraw_count <= 1
            # Drain the remaining resource to exercise the final overdraw case.
            while stamina > 0:
                weighted += rho(stamina, capacity) * Q
                overdraw_count += int(Q > stamina)
                stamina = max(F(0), stamina - Q)
                assert weighted <= energy(capacity, capacity) + recovered + F(13, 20) * Q
                assert overdraw_count <= 1
            schedules += 1
            overdraws += overdraw_count
    ratio = F(143, 50) * (F(6, 5) + F(143, 50) / 120) / F(34, 25)
    resource = F(177, 200) * 100 + 80 + Q
    supplied = float(ratio * resource + F(81, 50))
    c = 3 * math.sin(math.pi / 4) + 0.2
    required = c * (190 - 1.8 / 120)
    observed = json.loads((OUTPUT / "recovery-bound-search.json").read_text(encoding="utf-8"))["certificates"][0]
    assert abs(supplied - observed["supply_upper"]) < 1e-9
    assert abs(required - observed["necessary_work_lower"]) < 1e-9
    return {"resource_boundary_checks": comparisons, "exact_random_schedules": schedules,
            "random_steps_per_schedule": 2000, "final_push_until_exhausted": True,
            "observed_single_final_overdraws": overdraws,
            "ratio_exact": str(ratio), "resource_exact": str(resource), "supply_upper": supplied,
            "necessary_work_lower": required, "shortage": required - supplied,
            "meaning": "Exact rational corroboration of the shifted-resource proof, not exhaustive floating-point dynamics or human-play evidence"}


if __name__ == "__main__":
    checks = verify()
    extensions = []
    extra_files = []
    long_case = OUTPUT / "recovery-bound-long-search.json"
    if long_case.exists():
        certificate = json.loads(long_case.read_text(encoding="utf-8"))["certificates"][0]
        assert certificate["ranks"] == {"strength": 0, "endurance": 0, "recovery": 0}
        supplied = float(F(1050049, 408000) * (F(177, 200) * 100 + 140 + Q) + F(81, 50))
        required = (3 * math.sin(math.pi / 4) + .2) * (255 - 1.8 / 120)
        assert abs(supplied - certificate["supply_upper"]) < 1e-9
        assert abs(required - certificate["necessary_work_lower"]) < 1e-9
        extensions.append({"length_m": 255, "recovery_upper": 140, "supply_upper": supplied,
                           "necessary_work_lower": required, "shortage": required - supplied,
                           "scope": "Same source-equation conditions with min_stamina=1. Arithmetic extension; not a separate geometry or full-route validation."})
        extra_files.append(long_case)
    angle_checks = []
    angle_case = OUTPUT / "angle-bound-verification.json"
    if angle_case.exists():
        for certificate in json.loads(angle_case.read_text(encoding="utf-8"))["certificates"]:
            assert certificate["ranks"] == {"strength": 0, "endurance": 0, "recovery": 0}
            angle = F(str(certificate["angle"]))
            assert 39 <= angle <= 45
            drain = F(13, 10) + F(2, 5) * min(F(1), (angle - 30) / 10)
            q = 3 * drain / 120
            ratios, low = [], []
            c = 3 * math.sin(math.radians(float(angle))) + .2
            for exert in (False, True):
                for maximum, multiplier, consumption in [(F(9, 20), F(1), F(1)), (F(6, 5), F(11, 10), F(4, 5)),
                                                         (F(3, 2), F(1), F(1)), (F(9, 5), F(9, 10), F(1))]:
                    force = F(13, 5) * multiplier * (F(33, 20) if exert else 1)
                    cost = drain * consumption * (3 if exert else 1)
                    ratios.append(force * min(F(9, 5), maximum + force / 120) / cost)
                force = F(13, 5) * (F(33, 20) if exert else 1)
                v = F(1, 1000) + force / 120
                low.append((c * float(v) / 120 + float(v * v / 2)) / float(F(13, 20) * drain * (3 if exert else 1) / 120))
            ratio = max(ratios)
            assert float(ratio) >= max(low)
            supplied = float(ratio * (F(177, 2) + F(str(certificate["recovery_upper"])) + q) + F(81, 50))
            required = c * (certificate["gate_length"] - 1.8 / 120)
            for actual, expected in [(float(drain), certificate["drain_multiplier"]), (float(q), certificate["qmax"]),
                                     (float(ratio), certificate["ratio"]), (max(low), certificate["crosszero_and_stiction_ratio"]),
                                     (supplied, certificate["supply_upper"]), (required, certificate["necessary_work_lower"])]:
                assert abs(actual - expected) < 1e-9
            angle_checks.append({"angle": float(angle), "length_m": certificate["gate_length"],
                                 "recovery_upper": certificate["recovery_upper"], "drain_exact": str(drain),
                                 "ratio_exact": str(ratio), "supply_upper": supplied,
                                 "necessary_work_lower": required, "shortage": required - supplied})
        extra_files.append(angle_case)
    observed_ledgers = 0
    maximum_seconds_error = 0.0
    for data_file in [OUTPUT / "recovery-bound-search.json"] + extra_files:
        for trial in json.loads(data_file.read_text(encoding="utf-8")).get("trials", []):
            for gate in trial["final_state"]["gate_ledger"].values():
                error = abs(gate["seconds_budget"] - gate["seconds_used"] - gate["seconds_remaining"])
                maximum_seconds_error = max(maximum_seconds_error, error)
                assert error < 1e-8
                assert -1e-8 <= gate["seconds_remaining"] <= gate["seconds_budget"] + 1e-8
                assert gate["recovered_amount"] <= gate["amount_upper_bound_at_entry"] + 1e-8
                assert gate["passed"] == trial["passed"]
                observed_ledgers += 1
    files = [Path(__file__), ROOT / "scripts/boulder_controller.gd",
             Path(__file__).with_name("controller.gd"), Path(__file__).with_name("controller_factory.gd"),
             Path(__file__).with_name("verify_recovery_bound.gd"), Path(__file__).with_name("recovery-bound-certificate.md"),
             OUTPUT / "recovery-bound-search.json"] + extra_files
    report = {"status": "conditionally_accepted_source_equation_certificate", "checks": checks, "arithmetic_extensions": extensions,
              "angle_arithmetic_extensions": angle_checks,
              "observed_gate_metric_checks": {"gate_ledgers": observed_ledgers, "maximum_seconds_conservation_error": maximum_seconds_error,
                                               "absolute_tolerance": 1e-8, "passed_agrees_with_trial": True},
              "scope": "190m dry STONE45, no interior shelf/obstacle/support/purchase, 120Hz, original rank mechanics, finite actual recovery<=80 for zero ranks, recovery_min_stamina=1; other candidates need recalculation",
              "not_proven": ["safe retreat after exhaustion", "human completion time", "all-input impossibility with min_stamina=0", "IEEE formal verification", "grown full route feasibility"],
              "sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
    path = OUTPUT / "proof-review.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(checks))

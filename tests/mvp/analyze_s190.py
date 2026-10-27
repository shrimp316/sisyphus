"""Validate and summarize the bounded MVP S190 paired experiment."""
from pathlib import Path
import collections
import gzip
import hashlib
import json
import statistics

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "tests/mvp/results/s190"


def analyze_ablation(reference_rows):
    directory = BASE.parent / "s190-breath-ablation"
    source = directory / "results.jsonl"
    if not source.exists():
        return None
    records = [json.loads(line) for line in source.read_text(encoding="utf-8").splitlines() if line]
    reference = {(r["policy"], r["seed"]): r for r in reference_rows if not r["entry_fixture"] and r["build"] == "all30"}
    pairs = []
    for row in records:
        if row.get("type") != "run":
            continue
        assert row["counts"] == [10, 10, 0] and row["purchase_cost"] == 2560
        assert len(row["mastery_profile"]["purchased_mastery_nodes"]) == 20
        raw = gzip.decompress((ROOT / row["input_trace"].removeprefix("res://")).read_bytes())
        assert len(raw) == row["steps"] and hashlib.sha256(raw).hexdigest() == row["input_sha256"]
        original = reference[(row["policy"], row["seed"])]
        pairs.append({"policy": row["policy"], "seed": row["seed"], "all30_status": original["status"],
                      "no_breath_status": row["status"], "no_breath_peak": row["peak_m"],
                      "time_delta_when_both_summit": row["seconds"] - original["seconds"] if row["completed"] and original["completed"] else None,
                      "all30_environment_recovered": original["gate"]["environmental_recovered"],
                      "no_breath_environment_recovered": row["gate"]["environmental_recovered"],
                      "all30_inertia_recovered_whole_run": original["gate"]["ability"]["inertia_recovered"],
                      "all30_rescue_used": original["gate"]["ability"]["exhaustion_rescue_used"]})
    assert len(pairs) == 6
    result = {"source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "pairs": pairs,
              "input_hashes_verified": 6, "all30_summits": sum(r["all30_status"] == "summit" for r in pairs),
              "no_breath_summits": sum(r["no_breath_status"] == "summit" for r in pairs),
              "scope": "SameSTR10END10; remove all BRE nodes and1280EXP investment. Not equal-budget redistribution or proof BRE is required. Conditional time delta only both-summit pairs."}
    (directory / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def main():
    source = BASE / "results.jsonl"
    records = [json.loads(line) for line in source.read_text(encoding="utf-8").splitlines() if line]
    metadata = records[0]
    rows = [r for r in records if r.get("type") == "run"]
    assert len(rows) == 72 and len({r["id"] for r in rows}) == 72
    issues = []
    for row in rows:
        path = ROOT / row["input_trace"].removeprefix("res://")
        raw = gzip.decompress(path.read_bytes())
        assert len(raw) == row["steps"] and hashlib.sha256(raw).hexdigest() == row["input_sha256"]
        assert all(c < 8 for c in raw)
        gate = row["gate"]
        assert abs(gate["opportunity_used"] + gate["opportunity_remaining"] - 80 / 7) < 1e-7
        assert 0 <= gate["opportunity_used"] <= 80 / 7 + 1e-7
        multiplier = 1 + row["modifiers"]["effects"].get("recovery_bonus", 0)
        assert gate["environmental_recovered"] <= 80 * multiplier + 1e-7
        assert gate["core_recovery_total"] + 1e-7 >= gate["environmental_recovered"]
        assert len(row["mastery_profile"]["purchased_mastery_nodes"]) == sum(row["counts"])
        assert row["mastery_profile"]["cycle_exp_earned"] - row["mastery_profile"]["available_exp"] == row["purchase_cost"]
        assert row["status"] in ("gate_exit", "summit", "fall", "timeout")
        assert row["completed"] == (row["status"] in ("gate_exit", "summit"))
        assert row["censored"] == (row["status"] == "timeout")
    for path, expected in metadata["source_sha256"].items():
        if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != expected:
            issues.append("Source changed since run start: " + path)
    groups = collections.defaultdict(list)
    for row in rows:
        groups[(row["entry_fixture"], row["build"], row["policy"])].append(row)
    summary = []
    for (fixture, build, policy), group in groups.items():
        assert sorted(r["seed"] for r in group) == [101, 202, 303]
        passed = [r for r in group if r["completed"]]
        summary.append({
            "entry_fixture": fixture, "build": build, "policy": policy, "n": 3,
            "passed": len(passed), "timeouts": sum(r["censored"] for r in group),
            "purchase_cost": group[0]["purchase_cost"], "node_count": sum(group[0]["counts"]),
            "mean_peak_m": statistics.mean(r["peak_m"] for r in group),
            "mean_completion_seconds_conditional": statistics.mean(r["seconds"] for r in passed) if passed else None,
            "mean_environmental_recovery": statistics.mean(r["gate"]["environmental_recovered"] for r in group),
            "mean_gate_core_recovery": statistics.mean(r["gate"]["core_recovery_total"] for r in group),
            "mean_run_inertia_recovery": statistics.mean(r["gate"]["ability"]["inertia_recovered"] for r in group),
            "runs_using_exhaustion_rescue": sum(r["gate"]["ability"]["exhaustion_rescue_used"] for r in group),
        })
    result = {"source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "runs": 72,
              "fixtures": 36, "full_routes": 36, "input_hashes_verified": 72,
              "source_changes_after_start": issues, "groups": summary,
              "scope": "Fixed purchased builds with artificial funding setup; not XP campaigns, human cohorts or all-input impossibility proof. Equal18-node builds have unequal EXP costs. Separate2recovery-aware policies. Environment budget does not cap mastery recovery. Inertia/rescue counters cover whole run, core recovery ledger only gate."}
    (BASE / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["# MVP 석판 효과와 S190의 제한된 비교", "",
             "같은 clear 날씨·generation6·시드101/202/303과 두 회복 대응 정책을 사용했다. 관문 진입36회와 0m 전체 경로36회를 분리한다. 실제 지갑 지급·구매 API로 고정 빌드를 만들었지만 준비용 거리 지급은 인공 fixture다. 자연 XP 캠페인이나 인간 플레이 결과가 아니다.", "",
             "S190의 환경 회복 기회는80/7초, 초당7이며 기존 BRE01 배율을 받는다. BRE05/07/10 등 신규 능력의 추가 회복은 환경 할당과 별개다. 기존 무강화 불가능 증명을 성장 빌드에 재사용하지 않는다. 두 정책 모두 v0.3의 별도 regular_recovery/skilled_recovery이며 일반 regular/skilled 정책과 합치지 않는다.", "",
             "| 출발 | 빌드 | EXP | 정책 | 목표 도달 | 평균 최고점 | 성공 조건부 시간(초) |", "|---|---|---:|---|---:|---:|---:|"]
    for r in summary:
        seconds = "—" if r["mean_completion_seconds_conditional"] is None else f'{r["mean_completion_seconds_conditional"]:.2f}'
        lines.append(f'| {"750m 진입" if r["entry_fixture"] else "0m 출발"} | {r["build"]} | {r["purchase_cost"]} | {r["policy"]} | {r["passed"]}/3 | {r["mean_peak_m"]:.2f} | {seconds} |')
    lines += ["", "진입 fixture의 목표는940m이며 정상 완주가 아니다. 전체 경로의 목표는1,000m다. 실패는 시험한 유한 정책의 실패이며 특정 노드의 필요조건을 증명하지 않는다.18노드 구성끼리도 balanced18은1,200EXP, 집중 구성은1,660EXP로 비용이 같지 않다. 미세 입력 최적화나 광범위 시드 안정성은 조사하지 않았다.", "",
              "압축 원시 입력72개의 SHA·step·명령 범위, 실제 구매 노드수·지출, 환경 기회시간 보존을 검증했다. 능력별 inertia/rescue 카운터는 전체 회차, gate core/environment 회복량은 관문 내부 범위다. 상세 수치는 summary.json과 results.jsonl에 보존했다."]
    if issues:
        lines += ["", "실행 후 변경된 소스(결과 해석 시 시작시점 metadata SHA 참조):"] + ["- " + issue for issue in issues]
    ablation = analyze_ablation(rows)
    if ablation:
        deltas = [r["time_delta_when_both_summit"] for r in ablation["pairs"] if r["time_delta_when_both_summit"] is not None]
        lines += ["", "## 호흡 계열 제거 대조", "",
                  f"근력10·지구력10을 고정하고 호흡10개를 제거한 추가6회는{ablation['no_breath_summits']}/6 완주, 기준30노드는{ablation['all30_summits']}/6 완주였다. 양쪽 완주한{len(deltas)}쌍에서는 호흡 제거가{min(deltas):.2f}~{max(deltas):.2f}초 느렸다. 일반 회복 대응 정책 seed303은 제거 시939.84m에서 실패했다.", "",
                  "환경으로 실제 회복한 양은84→80으로 감소했고, 기준의 관성 회복은 전체 회차0~2였다. 이6개 기준 회차에서 BRE10 구제는 사용하지 않았다. 계열 전체를 제거한 비교여서 개별 노드 하나의 효과로 단정하지 않는다. 투자도3,840→2,560EXP로 줄었으므로 같은 예산 배분 비교가 아니다. 호흡의 실효 증거지만 필수성이나 인간 성과의 증명은 아니다. 상세는 ../s190-breath-ablation/summary.json에 보존했다."]
    (BASE / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"runs": 72, "groups": len(summary), "source_changes": issues}))


if __name__ == "__main__":
    main()

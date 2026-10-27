#!/usr/bin/env python3
"""Aggregate measured v0.3 runs without modifying prior experiment artifacts."""
from __future__ import annotations

import argparse
from collections import defaultdict
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("v02_statistics", Path(__file__).resolve().parents[1] / "adjustment_v02" / "analyze.py")
previous = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(previous)
stats = previous.base
SCHEMA = "adjustment-v03-analysis-1"
EXTRA_FIELDS = ("ablation_stat", "ablation_reference", "purchase_mode", "instrumentation_mode")
FIELDS = previous.FIELDS + EXTRA_FIELDS
IDENTITY = ("seed", "campaign_id", "run_index")
TRACE_NAMESPACE = "tests/balance/results/act1-adjustment-v03/"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resolve_trace(reference, project):
    """Rebase the archived v0.3 suffix, never trust the archived machine prefix."""
    normalized = str(reference).replace("\\", "/").removeprefix("res://")
    if any(part in (".", "..") for part in normalized.split("/")):
        raise ValueError("Input trace traversal or dot segment is forbidden")
    if normalized.startswith(TRACE_NAMESPACE):
        relative = normalized
    elif "/" + TRACE_NAMESPACE in normalized:
        relative = TRACE_NAMESPACE + normalized.split("/" + TRACE_NAMESPACE, 1)[1]
    else:
        raise ValueError("Input trace is outside the v0.3 result namespace")
    suffix_parts = relative[len(TRACE_NAMESPACE):].split("/")
    if any(not part or part in (".", "..") or part.endswith((".", " ")) or ":" in part for part in suffix_parts):
        raise ValueError("Unsafe Windows input trace suffix component")
    project = Path(project).resolve()
    root = (project / TRACE_NAMESPACE).resolve()
    root.relative_to(project)
    resolved = (project / relative).resolve()
    resolved.relative_to(root)
    return resolved


def input_trace_evidence(runs, metadata, project=None):
    project = Path(project or Path(__file__).resolve().parents[3]).resolve()
    traces = []
    for row in runs:
        reference = row.get("input_trace_gzip")
        if not reference:
            continue
        path = resolve_trace(reference, project)
        compressed = path.read_bytes()
        raw = gzip.decompress(compressed)
        digest = hashlib.sha256(raw).hexdigest()
        if digest != row.get("input_sha256"):
            raise ValueError(f"Raw input hash mismatch: {path}")
        if not isinstance(row.get("steps"), int) or isinstance(row["steps"], bool) or len(raw) != row["steps"]:
            raise ValueError(f"Raw input step count mismatch: {path}")
        traces.append({**label(row), **{key: row.get(key) for key in IDENTITY}, "original_reference": reference,
                       "path": path.relative_to(project).as_posix(), "steps": len(raw),
                       "compressed_sha256": hashlib.sha256(compressed).hexdigest(), "raw_sha256_verified": digest})
    policies = {}
    for item in metadata:
        if "policy_source" in item:
            digest = hashlib.sha256(item["policy_source"].encode("utf-8")).hexdigest()
            if digest != item.get("policy_source_sha256"):
                raise ValueError("Embedded policy source hash mismatch")
            policies[digest] = {"sha256_verified": digest, "human_policy": item.get("human_policy"), "policy": item.get("policy")}
    return traces, list(policies.values())


def label(row):
    return {**previous.descriptor(row), **{key: row.get(key) for key in EXTRA_FIELDS}}


def grouped(rows):
    groups = defaultdict(list)
    for row in rows:
        groups[tuple(label(row).values())].append(row)
    return groups.values()


def reused(function, rows, *args):
    # Keep new experimental factors separated before invoking old pure statistics.
    return [{**record, **{key: samples[0].get(key) for key in EXTRA_FIELDS}}
            for samples in grouped(rows) for record in function(samples, *args)]


def raw_gate_rows(runs):
    return [{**label(row), **{key: row.get(key) for key in IDENTITY},
             "run_status": row["status"], "source_jsonl": row["_source"], **gate}
            for row in runs for gate in row["gate_telemetry"]]


def gate_rows(runs, independent=True):
    result = []
    for samples in grouped(runs):
        gates = defaultdict(list)
        for row in samples:
            for gate in row["gate_telemetry"]:
                gates[gate["id"]].append(gate)
        for gate_id, observations in gates.items():
            entered = [g for g in observations if g.get("entry_seconds") is not None]
            info = {**label(samples[0]), "gate_id": gate_id,
                    "observed_run_count": len(samples), "telemetry_count": len(observations),
                    "entered_count": len(entered)}
            known_pass = [g for g in entered if isinstance(g.get("passed"), bool)]
            passed = sum(g["passed"] for g in known_pass)
            proportion = stats.wilson(passed, len(known_pass)) if independent else {
                "n": len(known_pass), "successes": passed,
                "rate": passed / len(known_pass) if known_pass else None}
            result.append({**info, "metric": "pass_conditional_on_entry", **proportion})
            numeric = sorted({key for gate in entered for key, value in gate.items()
                              if isinstance(value, (int, float)) and not isinstance(value, bool)})
            for field in numeric:
                result.append({**info, "metric": field, **stats.stats(g.get(field) for g in entered)})
            result.append({**info, "metric": "pass_seconds_conditional_on_success",
                           **stats.stats(g["exit_seconds"] - g["entry_seconds"] for g in entered
                                         if g.get("passed") and g.get("exit_seconds") is not None)})
    return result


def xp_rows(runs, campaigns):
    result = []
    for row in runs:
        identity = {**label(row), **{key: row.get(key) for key in IDENTITY}, "source_jsonl": row["_source"]}
        for event in row.get("xp_events", []):
            amount = event.get("earned_xp")
            event_type = "xp_award" if isinstance(amount, (int, float)) and amount > 0 else "milestone_no_award" if amount == 0 else "xp_event_unclassified"
            result.append({**identity, "event_type": event_type, **event})
    # Purchases are campaign-level in the inherited simulator; retain that owner.
    for row in campaigns:
        identity = {**label(row), "seed": row["seed"], "campaign_id": row["campaign_id"], "source_jsonl": row["_source"]}
        for event in row.get("purchases", []):
            result.append({**identity, "event_type": "purchase", **event})
    return result


def unlock_geometry_rows(runs):
    """Geometry review of a future rule, never simulated unlock/purchase results."""
    result = []
    for row in runs:
        segments = row.get("geometry_layout", [])
        if not segments or not all("shelf" in segment for segment in segments):
            continue
        shelves = [s for s in segments if s["shelf"]]
        for threshold in (250, 500, 750, 1000):
            at = next((s for s in segments if s["start"] <= threshold < s["end"]), None)
            previous_ends = [s["end"] for s in shelves if s["end"] <= threshold]
            future_starts = [s["start"] for s in shelves if s["start"] >= threshold]
            on_shelf = bool(at["shelf"]) if at else None
            following = threshold if on_shelf else min(future_starts, default=None)
            result.append({**label(row), **{key: row.get(key) for key in IDENTITY},
                           "threshold_m": threshold, "new_eligible_nodes_design_only": 5 if threshold == 1000 else 10,
                           "threshold_reached": row.get("peak_m", 0) >= threshold,
                           "shelf_at_threshold_geometric": on_shelf,
                           "previous_shelf_end_m": max(previous_ends, default=None),
                           "next_shelf_start_m": following,
                           "forward_distance_to_next_shelf_m": following - threshold if following is not None else None,
                           "unlock_implemented": False, "purchase_feasibility": "not_simulated",
                           "can_cause_same_first_summit": False if threshold == 1000 else None})
    return result


def fixture_metrics(rows):
    result = []
    for samples in grouped(rows):
        info = {**label(samples[0]), "observation_unit": "bounded_diagnostic"}
        result.append({**info, "metric": "diagnostic_target_reached_NOT_summit",
                       **stats.wilson(sum(r["status"] == "diagnostic_target" for r in samples), len(samples))})
        for field in ("seconds", "slips", "runaways"):
            result.append({**info, "metric": field, **stats.stats(r.get(field) for r in samples)})
        result.append({**info, "metric": "progress_from_fixture_start_m",
                       **stats.stats(r["peak_m"] - start for r in samples
                                     if (start := (r.get("entry_fixture") or {}).get("distance_m", r.get("initial_state", {}).get("distance"))) is not None)})
    return result


def campaign_review(runs, campaigns):
    records = []
    for campaign in campaigns:
        attempts = sorted((r for r in runs if r.get("campaign_id") == campaign["campaign_id"]), key=lambda r: r["run_index"])
        if not attempts:
            continue
        first = attempts[0]
        purchases = sorted(campaign.get("purchases", []), key=lambda e: e["seconds"])
        checkpoints = {str(target): next((e for e in first.get("xp_events", []) if target <= e.get("peak_m", -1) < target + 50), None)
                       for target in (250, 750)}
        offset = 0.0
        entries = []
        for attempt in attempts:
            start = attempt.get("run_start_seconds", offset)
            if attempt is first or attempt is attempts[-1]:
                for gate in attempt["gate_telemetry"]:
                    before = [p for p in purchases if gate.get("entry_seconds") is not None and p["seconds"] <= start + gate["entry_seconds"]]
                    entries.append({"run_index": attempt["run_index"], "gate_id": gate["id"],
                                    "entry_seconds": gate.get("entry_seconds"), "passed": gate.get("passed"),
                                    "ranks_at_registered_entry": before[-1].get("ranks") if before else attempt.get("start_ranks"),
                                    "is_first_attempt": attempt is first, "is_summit_attempt": bool(attempt.get("completed"))})
            offset = start + attempt["seconds"]
        second = attempts[1] if len(attempts) > 1 else None
        second_start = second.get("run_start_seconds", first["seconds"]) if second else None
        retry = [p for p in purchases if second and second_start <= p["seconds"] <= second_start + second["seconds"]]
        start_ledger = second.get("progression_start", {}) if second else {}
        records.append({**label(campaign), "campaign_id": campaign["campaign_id"], "seed": campaign["seed"],
                        "completed": campaign["completed"], "minutes": campaign["seconds"] / 60, "runs": campaign["runs"],
                        "in_120_180_minutes": campaign["completed"] and 7200 <= campaign["seconds"] <= 10800,
                        "first_attempt_status": first["status"], "first_attempt_peak_m": first.get("peak_m"),
                        "first_attempt_xp": first.get("total_xp"), "first_purchase": purchases[0] if purchases else None,
                        "first_attempt_checkpoints": checkpoints, "gate_entries": entries,
                        "retry_xp_preserved": first.get("total_xp") == start_ledger["total_xp"] if "total_xp" in start_ledger else None,
                        "retry_ranks_preserved": first.get("end_ranks") == start_ledger["ranks"] if "ranks" in start_ledger else None,
                        "first_retry_purchase": retry[0] if retry else None, "final_ranks": campaign.get("end_ranks")})
    return {"campaigns": len(campaigns), "reviewed_campaigns": len(records), "attempts": sum(c.get("runs", 0) for c in campaigns),
            "first_attempt_falls": sum(r["first_attempt_status"] == "fall" for r in records),
            "completed": sum(c["completed"] for c in campaigns),
            "in_120_180_minutes": sum(r["in_120_180_minutes"] for r in records), "records": records}


def write_table(output, name, rows, extra_columns=()):
    path = output / (name + ".csv")
    if rows:
        stats.write_csv(path, rows)
    else:
        path.write_text(",".join(FIELDS + extra_columns) + "\n", encoding="utf-8")


def analyze(paths, output, evidence_paths=()):
    paths = [Path(p).resolve() for p in paths]
    output = Path(output).resolve()
    manifest_path = output / "manifest.json"
    existing = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    if existing and existing.get("schema_version") != SCHEMA:
        raise ValueError("Output must be a new v0.3 analysis directory, not another experiment or execution directory")
    if not existing and any((output / name).exists() for name in ("metrics.csv", "bands.csv", "campaigns.csv")):
        raise ValueError("Output contains unowned analysis tables")
    executions = []
    for path in paths:
        manifest = path.parent / "manifest.json"
        execution = json.loads(manifest.read_text(encoding="utf-8")) if manifest.exists() else {}
        if "source_config" in execution:
            if execution.get("status") != "complete":
                raise ValueError(f"Execution is not complete: {manifest}")
        else:
            execution = None
        executions.append({"jsonl": str(path), "sha256": sha(path), "execution_manifest": execution})
    rows, metadata = previous.read_records(paths)
    all_runs = [r for r in rows if r["type"] == "run"]
    diagnostic_jobs = {j["id"] for item in metadata for j in item.get("config", {}).get("jobs", [])
                       if "stop_after_m" in j or j.get("entry_fixture") is not None}
    fixtures = [r for r in all_runs if r.get("entry_fixture") is not None or r["status"] == "diagnostic_target" or r["job_id"] in diagnostic_jobs]
    diagnostic_ids = {id(r) for r in fixtures}
    runs = [r for r in all_runs if id(r) not in diagnostic_ids]
    campaigns = [r for r in rows if r["type"] == "campaign"]
    singles = [r for r in runs if not r.get("campaign_id")]
    attempts = [r for r in runs if r.get("campaign_id")]
    for row in all_runs:
        missing = [key for key in ("gate_telemetry", "bands", "bands_200", "stamina_metrics", "slip_events", "stall_events") if key not in row]
        direct = (str(row.get("physics_mode", "")).startswith("direct audited production _step_v02")
                  and bool(row.get("input_sha256")) and bool(row.get("input_trace_gzip")))
        if "gate_telemetry" in missing or (missing and not direct):
            raise ValueError(f"Missing v0.3 instrumentation: {row['job_id']} {missing}")
        row["instrumentation_mode"] = "direct_partial" if direct else "full_observer"
        row["_missing_instrumentation"] = missing
        if not isinstance(row["gate_telemetry"], list):
            raise ValueError("gate_telemetry must be an array")
        ids = [g["id"] for g in row["gate_telemetry"]]
        if len(set(ids)) != len(ids):
            raise ValueError("A gate must have one telemetry summary per run, with reentries counted inside it")
    for campaign in campaigns:
        modes = {r["instrumentation_mode"] for r in attempts if r.get("campaign_id") == campaign.get("campaign_id")}
        campaign["instrumentation_mode"] = next(iter(modes)) if len(modes) == 1 else "mixed_or_unobserved"
    traces, policies = input_trace_evidence(all_runs, metadata)
    evidence = {str(Path(p).resolve()): sha(Path(p)) for p in evidence_paths}
    first_attempts = [r for r in attempts if r.get("run_index") == 1]
    first_attempts += [r for r in singles if r.get("experiment_case") == "first_attempt_growth"]
    ablations = [r for r in singles if r.get("ablation_stat") or r.get("experiment_case") == "per_stat_ablation"]
    progression_review = campaign_review(attempts, campaigns)
    output.mkdir(parents=True, exist_ok=True)
    tables = {
        "metrics": reused(previous.metric_rows, singles, "single") + reused(previous.metric_rows, campaigns, "campaign"),
        "bands": reused(previous.band_rows, singles),
        "stamina": reused(previous.stamina_rows, singles),
        "slip": reused(previous.risk_rows, runs),
        "stalls": reused(previous.stall_rows, runs, output),
        "terrain": reused(previous.terrain_rows, singles),
        "gate_telemetry": raw_gate_rows(runs),
        "gates": [{**r, "observation_unit": unit} for sample, unit in ((singles, "single_run"), (attempts, "campaign_attempt_correlated")) for r in gate_rows(sample, independent=unit == "single_run")],
        "xp": xp_rows(runs, campaigns),
        "unlock_geometry": unlock_geometry_rows(singles),
        "first_attempt": reused(previous.metric_rows, first_attempts, "first_attempt"),
        "ablations": reused(previous.metric_rows, ablations, "single_ablation"),
        "diagnostic_fixtures": [{**label(r), **{key: r.get(key) for key in IDENTITY}, "entry_fixture": r.get("entry_fixture"),
                                "diagnostic_kind": "entry_fixture" if r.get("entry_fixture") is not None else "bounded_route",
                                "completed": r["completed"], "status": r["status"], "seconds": r["seconds"], "peak_m": r.get("peak_m"),
                                "gate_telemetry": r["gate_telemetry"], "source_jsonl": r["_source"]} for r in fixtures],
        "fixture_metrics": fixture_metrics(fixtures),
        "fixture_gate_telemetry": raw_gate_rows(fixtures),
        "fixture_gates": gate_rows(fixtures),
        "campaigns": [{**label(r), **{k: v for k, v in r.items() if k not in ("_source", "candidate", "purchases")}} for r in campaigns],
        "campaign_progression": progression_review["records"],
    }
    empty_columns = {"stalls": ("seed", "campaign_id", "run_index", "duration_seconds", "replay_file", "physical_proof_status"),
                     "gate_telemetry": IDENTITY + ("id", "entry_seconds", "passed", "seconds_budget", "seconds_remaining", "seconds_used", "recovered_amount"),
                     "xp": IDENTITY + ("event_type", "seconds", "total_xp", "level", "pending_points")}
    for name, table in tables.items():
        write_table(output, name, table, empty_columns.get(name, ("metric", "n", "value")))
    review_path = output / "campaign-review.json"
    review_path.write_text(json.dumps(progression_review, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    code = (Path(__file__).resolve(), Path(previous.__file__).resolve(), Path(stats.__file__).resolve())
    manifest = {
        "schema_version": SCHEMA, "input_files": executions, "metadata": metadata,
        "observed_counts": {"single_runs": len(singles), "campaigns": len(campaigns), "campaign_run_rows": len(attempts), "actual_runs": len(runs)},
        "raw_run_records_including_fixtures": len(all_runs),
        "observed_events": {key: sum(len(r.get(key, [])) for r in runs) for key in ("slip_events", "stall_events", "gate_telemetry")},
        "instrumented_run_counts": {key: sum(key in r for r in runs) for key in ("slip_events", "stall_events", "stamina_metrics", "bands", "bands_200", "gate_telemetry")},
        "diagnostic_fixture_runs": sum(r.get("entry_fixture") is not None for r in fixtures),
        "bounded_diagnostic_runs": len(fixtures),
        "partial_instrumentation_runs": [{**label(r), **{key: r.get(key) for key in IDENTITY}, "missing": r["_missing_instrumentation"]} for r in all_runs if r["_missing_instrumentation"]],
        "first_attempt_rows": len(first_attempts), "ablation_rows": len(ablations),
        "analysis_code_sha256": {str(p): sha(p) for p in code},
        "output_csv_sha256": {name + ".csv": sha(output / (name + ".csv")) for name in tables},
        "output_json_sha256": {review_path.name: sha(review_path)},
        "evidence_artifacts": evidence,
        "input_trace_checks": traces, "embedded_policy_source_checks": policies,
        "semantics": {"missing": "not zero", "campaigns": "independent campaigns; attempts correlated and excluded from single-run completion estimates",
                      "time": "timeouts remain censored; successful completion time conditional on success",
                      "gate_budget": "finite environmental released-recovery time, consumed even at stamina cap; not a character capacity. Recovery episodes include capped intervals. Positive reserve does not prove safe retreat",
                      "physics": "source-derived test instrumentation; instrumentation metadata overrides inherited generic controller description",
                      "proof": "policy failure and finite input search failure never prove physical impossibility",
                      "future_nodes": "140-node eligibility and prestige are design only; measured progression is current actual cumulative XP"},
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return manifest["observed_counts"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--evidence", action="append", default=[], type=Path)
    args = parser.parse_args()
    try:
        counts = analyze(args.inputs, args.output_dir, args.evidence)
    except (OSError, ValueError, TypeError, KeyError) as error:
        parser.error(str(error))
    print(json.dumps(counts))


if __name__ == "__main__":
    main()

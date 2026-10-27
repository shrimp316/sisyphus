#!/usr/bin/env python3
"""Measured v0.2 adjustment data; never infer physical impossibility from policy failure."""
from __future__ import annotations

import argparse
import hashlib
import gzip
import importlib.util
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

BASE_SPEC = importlib.util.spec_from_file_location("balance_statistics", Path(__file__).resolve().parents[1] / "analyze.py")
base = importlib.util.module_from_spec(BASE_SPEC)
BASE_SPEC.loader.exec_module(base)
FIELDS = ("job_id", "candidate_id", "experiment_case", "policy", "policy_variant", "growth_id", "growth_mode", "level", "strategy")
STAT_METRICS = ("seconds", "peak_m", "earned_xp", "cumulative_xp", "total_xp", "ending_level", "runs",
                "slips", "runaways", "exhaustion_episodes", "ledge_block_episodes", "rollback_m", "shelter_seconds",
                "shelter_rest_seconds", "brace_episodes", "fall_animation_seconds")


def descriptor(row):
    candidate = row.get("candidate", {})
    return {**{field: row.get(field) for field in FIELDS},
            "candidate_id": row.get("candidate_id", candidate.get("id", "unspecified")),
            "policy_variant": row.get("policy_variant", "configured_policy"),
            "experiment_case": row.get("experiment_case", "unspecified")}


def read_records(paths):
    rows, metadata, seen = [], [], set()
    for path in paths:
        with path.open(encoding="utf-8-sig") as stream:
            for line_number, line in enumerate(stream, 1):
                if not line.strip():
                    continue
                row = json.loads(line)
                if not isinstance(row, dict):
                    raise ValueError(f"{path}:{line_number}: expected object")
                if row.get("type") not in ("run", "campaign"):
                    if row.get("type") == "metadata":
                        explicit_witness_metadata = ("source-derived" in row.get("physics_mode", "")
                                                     and row.get("human_policy") is False and bool(row.get("policy_source_sha256")))
                        if row.get("schema_version", 0) < 2 and not explicit_witness_metadata:
                            raise ValueError(f"{path}:{line_number}: unsupported legacy metadata")
                        if any(job.get("growth_mode", "actual") != "actual" for job in row.get("config", {}).get("jobs", [])):
                            raise ValueError(f"{path}:{line_number}: non-actual growth mode")
                    metadata.append(row)
                    continue
                duration = row.get("seconds")
                if (row.get("growth_mode") != "actual" or not isinstance(row.get("completed"), bool)
                        or isinstance(duration, bool) or not isinstance(duration, (float, int))
                        or not math.isfinite(duration) or duration < 0):
                    raise ValueError(f"{path}:{line_number}: invalid measured actual-progression record")
                identity = (row["type"], row.get("job_id"), row.get("campaign_id"), row.get("seed"), row.get("run_index"), row.get("policy_variant"))
                if identity in seen:
                    raise ValueError(f"Duplicate sample: {identity}")
                seen.add(identity)
                row["_source"] = str(path)
                rows.append(row)
    if not rows:
        raise ValueError("No measured run/campaign records")
    return rows, metadata


def groups(rows):
    result = defaultdict(list)
    for row in rows:
        result[tuple(descriptor(row).values())].append(row)
    return result


def statistic(label, metric, values, **extra):
    return {**label, **extra, "metric": metric, **base.stats(values)}


def pooled_rate(items, event_key, exposure_key):
    # Missing instrumentation is not a measured zero.
    if not items or not all(event_key in item and exposure_key in item for item in items):
        return None
    exposure = sum(item[exposure_key] for item in items)
    return 3600 * sum(item[event_key] for item in items) / exposure if exposure > 0 else None


def metric_rows(rows, record_type):
    result = []
    for _, samples in groups(rows).items():
        label = {**descriptor(samples[0]), "record_type": record_type}
        result.append({**label, "metric": "completion_by_cap", **base.wilson(sum(row["completed"] for row in samples), len(samples))})
        result.append({**label, "metric": "censored", "n": len(samples), "count": sum(bool(row.get("censored")) for row in samples)})
        for metric in STAT_METRICS:
            result.append(statistic(label, metric, (row.get(metric) for row in samples)))
        result.append(statistic(label, "completion_seconds_conditional_on_success", (row["seconds"] for row in samples if row["completed"])))
        elapsed = sum(row["seconds"] for row in samples)
        xp = sum(row.get("earned_xp", row.get("cumulative_xp", 0)) for row in samples)
        result.append({**label, "metric": "pooled_xp_per_hour", "n": len(samples), "value": xp * 3600 / elapsed if elapsed else None})
        for reason, count in sorted(Counter(row.get("status", "unknown") for row in samples).items()):
            result.append({**label, "metric": "terminal_status", "category": reason, "n": len(samples), "count": count})
        for reason, count in sorted(Counter(row.get("failure_cause", "unknown") for row in samples if row.get("status") == "fall").items()):
            result.append({**label, "metric": "failure_association_NOT_causal", "category": reason, "n": len(samples), "count": count})
    return result


def band_rows(runs):
    result = []
    for _, samples in groups(runs).items():
        label = descriptor(samples[0])
        for width, field in ((250, "bands"), (200, "bands_200")):
            by_index = defaultdict(list)
            for row in samples:
                for band in row.get(field, []):
                    if band.get("entered"):
                        by_index[band["index"]].append({**band, "later_fall": row.get("status") == "fall"})
            for index, bands in sorted(by_index.items()):
                zone = {**label, "band_width_m": width, "band_index": index, "start_m": index * width,
                        "end_m": (index + 1) * width, "entered_n": len(bands), "exposure_seconds": sum(b["exposure_seconds"] for b in bands)}
                for metric in ("first_passage_seconds", "slips", "runaways", "exhaustion_episodes", "rollback_m",
                               "shelter_seconds", "shelter_rest_seconds", "stamina_consumed", "stamina_recovered", "exhausted_seconds"):
                    result.append(statistic(zone, metric, (b.get(metric) for b in bands)))
                result.append({**zone, "metric": "eventual_fall_after_entry", **base.wilson(sum(b["later_fall"] for b in bands), len(bands))})
                result.append({**zone, "metric": "terminal_origin_in_band", **base.wilson(sum(bool(b.get("death")) for b in bands), len(bands))})
                if all("stamina_integral" in b for b in bands):
                    result.append({**zone, "metric": "exposure_weighted_stamina", "value": sum(b["stamina_integral"] for b in bands) / zone["exposure_seconds"] if zone["exposure_seconds"] else None})
                for metric in ("slips", "runaways", "exhaustion_episodes"):
                    result.append({**zone, "metric": metric + "_per_exposure_hour", "value": pooled_rate(bands, metric, "exposure_seconds")})
    return result


def stamina_rows(runs):
    result = []
    for _, samples in groups(runs).items():
        label = descriptor(samples[0])
        metrics = [row["stamina_metrics"] for row in samples if "stamina_metrics" in row]
        if not metrics:
            result.append({**label, "metric": "instrumentation_unavailable", "n": 0, "omitted_run_count": len(samples)})
            continue
        fields = sorted(set().union(*(item.keys() for item in metrics)))
        for field in fields:
            result.append(statistic(label, field, (item.get(field) for item in metrics), observation_unit="run"))
        visits = [visit for row in samples for visit in row.get("shelter_events", [])]
        for field in ("entry_stamina", "exit_stamina", "moving_recovery", "stationary_recovery", "stationary_seconds", "stationary_rest_seconds"):
            result.append(statistic(label, "shelter_" + field, (item.get(field) for item in visits), observation_unit="visit_within_run"))
        observed_exit = [visit for visit in visits if visit.get("exit_stamina") is not None]
        result.append({**label, "metric": "shelter_visits", "observation_unit": "visit_within_run", "count": len(visits), "complete_visits": len(observed_exit)})
        rested = [visit for visit in visits if "stationary_seconds" in visit]
        result.append({**label, "metric": "shelter_visits_with_stationary_presence", "observation_unit": "visit_within_run",
                       "n": len(rested), "count": sum(visit["stationary_seconds"] > 0 for visit in rested),
                       "value": sum(visit["stationary_seconds"] > 0 for visit in rested) / len(rested) if rested else None})
    return result


def risk_rows(runs):
    result = []
    for _, samples in groups(runs).items():
        label = descriptor(samples[0])
        measured = [row for row in samples if "slip_events" in row]
        if not measured:
            result.append({**label, "row_type": "summary", "metric": "slip_event_instrumentation_unavailable", "n": 0, "omitted_run_count": len(samples)})
            continue
        slips = [event for row in measured for event in row["slip_events"]]
        outcomes = Counter(event.get("outcome", "unresolved") for event in slips)
        result.append({**label, "row_type": "summary", "metric": "slip_outcomes", "n": len(slips), "outcomes": dict(outcomes),
                       "recovered_fraction_all_observed": outcomes["recovered"] / len(slips) if slips else None,
                       "runaway_fraction_all_observed": outcomes["runaway"] / len(slips) if slips else None,
                       "note": "episodes within a run are correlated; proportions are descriptive, no independence CI"})
        result.append(statistic(label, "slip_recovery_seconds_if_recovered", (e.get("recovery_seconds") for e in slips if e.get("outcome") == "recovered"), row_type="summary"))
        command_counts = Counter()
        for event in slips:
            command = event.get("input")
            if isinstance(command, list) and len(command) == 3:
                push, exert, brace = command
                command_counts["brace" if brace else ("exert" if push and exert else ("push" if push else "released"))] += 1
        for name in ("push", "exert", "brace", "released"):
            exposure_keys = ("push_seconds", "exert_seconds", "brace_seconds", "active_seconds")
            instrumented = all(all(key in row.get("stamina_metrics", {}) for key in exposure_keys) for row in samples)
            exposure = None
            if instrumented:
                exposure = sum(row["stamina_metrics"].get(name + "_seconds", 0) if name != "released"
                               else max(0, row["stamina_metrics"]["active_seconds"] - sum(row["stamina_metrics"][key] for key in exposure_keys[:3])) for row in samples)
            result.append({**label, "row_type": "summary", "metric": "slips_per_command_hour", "input_category": name,
                           "event_count": command_counts[name], "exposure_seconds": exposure,
                           "value": command_counts[name] * 3600 / exposure if exposure else None,
                           "note": "command association, not randomized causal effect"})
        rollbacks = [event for row in samples for event in row.get("rollback_events", row.get("recovery_events", []))]
        if any("rollback_events" in row or "recovery_events" in row for row in samples):
            rollback_outcomes = Counter(event.get("outcome", "unresolved") for event in rollbacks)
            result.append({**label, "row_type": "summary", "metric": "rollback_velocity_recovery_outcomes", "n": len(rollbacks),
                           "outcomes": dict(rollback_outcomes),
                           "velocity_recovered_fraction_all_observed": rollback_outcomes["recovered"] / len(rollbacks) if rollbacks else None,
                           "note": "velocity became nonnegative; does not establish regained position or sustained progress"})
            braced = [event for event in rollbacks if event.get("brace_used")]
            result.append({**label, "row_type": "summary", "metric": "braced_rollback_velocity_recovery", "n": len(braced),
                           "recovered_count": sum(event.get("outcome") == "recovered" for event in braced),
                           "censored_count": sum(event.get("outcome") == "censored" for event in braced),
                           "value": sum(event.get("outcome") == "recovered" for event in braced) / len(braced) if braced else None})
        for row in samples:
            identity = {**descriptor(row), "seed": row["seed"], "campaign_id": row.get("campaign_id"), "run_index": row.get("run_index")}
            for index, event in enumerate(row.get("slip_events", [])):
                result.append({**identity, "row_type": "slip_event", "event_index": index, **event})
            for event in row.get("rollback_events", row.get("recovery_events", [])):
                result.append({**identity, "row_type": "rollback_recovery_event", **event})
            for input_name, exposure in row.get("input_exposure", {}).items():
                if isinstance(exposure, dict):
                    result.append({**identity, "row_type": "input_exposure", "input_category": input_name, **exposure})
                else:
                    result.append({**identity, "row_type": "input_exposure", "input_category": input_name, "seconds": exposure})
    return result


def terrain_rows(runs):
    result = []
    for _, samples in groups(runs).items():
        by_surface = defaultdict(list)
        for row in samples:
            for terrain in row.get("terrain", []):
                by_surface[(terrain.get("surface"), terrain.get("angle_bin"), row.get("weather"))].append(terrain)
        for (surface, angle, weather), observations in sorted(by_surface.items(), key=lambda item: str(item[0])):
            label = {**descriptor(samples[0]), "surface": surface, "angle_bin": angle, "weather": weather,
                     "exposure_seconds": sum(item.get("exposure_seconds", 0) for item in observations)}
            for event in ("slips", "runaways", "exhaustion_episodes", "ledge_block_episodes"):
                result.append({**label, "metric": event, "event_count": sum(item[event] for item in observations) if all(event in item for item in observations) else None,
                               "rate_per_exposure_hour": pooled_rate(observations, event, "exposure_seconds")})
    return result


def stall_rows(runs, output):
    result = []
    replay_dir = output / "replays"
    for row in runs:
        identity = {**descriptor(row), "seed": row["seed"], "campaign_id": row.get("campaign_id"), "run_index": row.get("run_index")}
        for index, event in enumerate(row.get("stall_events", [])):
            replay = {"source_jsonl": row.get("_source"), "identity": identity, "event_index": index,
                      "event": event, "terrain_snapshot": row.get("terrain_snapshot"), "geometry_layout": row.get("geometry_layout"),
                      "candidate": row.get("candidate"), "policy_seed": row.get("policy_seed"), "start_ranks": row.get("start_ranks"),
                      "classification": "policy_stall_observed_not_physical_impossibility"}
            digest = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()[:16]
            replay_dir.mkdir(exist_ok=True)
            replay_path = replay_dir / f"{digest}_{index:03d}.json"
            replay_path.write_text(json.dumps(replay, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
            compact = {key: value for key, value in event.items() if key not in ("input_history", "replay_start_state", "replay_end_state", "state")}
            result.append({**identity, "event_index": index, **compact, "replay_file": str(replay_path.relative_to(output)),
                           "classification": replay["classification"], "physical_proof_status": "not_assessed"})
    return result


def input_trace_evidence(runs, metadata, project=None):
    project = project or Path(__file__).resolve().parents[3]
    traces = []
    for row in runs:
        reference = row.get("input_trace_gzip")
        if not reference:
            continue
        path = Path(str(reference).removeprefix("res://"))
        path = (path if path.is_absolute() else project / path).resolve()
        path.relative_to(project)
        compressed = path.read_bytes()
        raw = gzip.decompress(compressed)
        digest = hashlib.sha256(raw).hexdigest()
        if digest != row.get("input_sha256"):
            raise ValueError(f"Raw input hash mismatch: {path}")
        if row.get("steps") is not None and len(raw) != row["steps"]:
            raise ValueError(f"Raw input step count mismatch: {path}")
        traces.append({**descriptor(row), "seed": row["seed"], "run_index": row.get("run_index"),
                       "path": str(path.relative_to(project)).replace("\\", "/"), "steps": len(raw),
                       "compressed_sha256": hashlib.sha256(compressed).hexdigest(), "raw_sha256_verified": digest})
    policies = {}
    for item in metadata:
        if "policy_source" not in item:
            continue
        digest = hashlib.sha256(item["policy_source"].encode("utf-8")).hexdigest()
        if digest != item.get("policy_source_sha256"):
            raise ValueError("Embedded policy source hash mismatch")
        policies[digest] = {"sha256_verified": digest, "human_policy": item.get("human_policy"), "policy": item.get("policy")}
    return traces, list(policies.values())


def analyze(paths, output):
    execution_manifests = {}
    for path in paths:
        source_manifest = path.parent / "manifest.json"
        manifest = json.loads(source_manifest.read_text(encoding="utf-8")) if source_manifest.exists() else {}
        if "source_config" in manifest:
            if manifest.get("status") != "complete":
                raise ValueError(f"Execution is not complete: {source_manifest}")
            execution_manifests[str(path)] = manifest
    rows, metadata = read_records(paths)
    runs = [row for row in rows if base.kind(row) == "run"]
    campaigns = [row for row in rows if base.kind(row) == "campaign"]
    singles = [row for row in runs if not row.get("campaign_id")]
    for row in runs:
        missing = [field for field in ("stamina_metrics", "bands", "bands_200", "slip_events", "stall_events") if field not in row]
        partial_witness = (str(row.get("physics_mode", "")).startswith("direct generated production _step_v02")
                           and bool(row.get("policy_variant")) and bool(row.get("input_sha256"))
                           and bool(row.get("input_trace_gzip")))
        if missing and not partial_witness:
            raise ValueError(f"Not a v0.2 instrumented run: {row.get('job_id')} seed {row.get('seed')}")
        row["_missing_instrumentation"] = missing
    trace_evidence, policy_evidence = input_trace_evidence(runs, metadata)
    output.mkdir(parents=True, exist_ok=True)
    # Aggregate campaign resource exposure separately; never pool their attempts
    # with independent single-climb completion samples.
    dataset = {"metrics": metric_rows(singles, "single") + metric_rows(campaigns, "campaign"),
               "bands": band_rows(singles), "stamina": stamina_rows(singles), "slip": risk_rows(runs),
               "stalls": stall_rows(runs, output),
               "terrain": terrain_rows(singles),
               "geometry": [{**descriptor(row), "seed": row["seed"], "weather": row.get("weather"), "segment_index": index, **segment}
                            for row in singles for index, segment in enumerate(row.get("geometry_layout", []))],
               "campaigns": [{**descriptor(row), **{key: value for key, value in row.items() if key not in ("_source", "purchases", "candidate")}} for row in campaigns]}
    # Preserve evidence even when no event happened: required CSVs keep a header.
    empty_columns = {
        "stalls": ("seed", "campaign_id", "run_index", "event_index", "start_seconds", "detected_seconds", "end_seconds", "distance_m", "duration_seconds", "outcome", "replay_file", "classification", "physical_proof_status"),
        "campaigns": ("seed", "campaign_id", "status", "completed", "censored", "seconds", "runs", "cumulative_xp", "end_ranks"),
        "bands": ("band_width_m", "band_index", "start_m", "end_m", "metric", "n", "value"),
    }
    for name, records in dataset.items():
        if records:
            base.write_csv(output / f"{name}.csv", records)
        else:
            (output / f"{name}.csv").write_text(",".join(FIELDS + empty_columns.get(name, ("row_type", "metric", "n", "value"))) + "\n", encoding="utf-8")
    executions = []
    for path in paths:
        executions.append({"jsonl": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                           "execution_manifest": execution_manifests.get(str(path))})
    info = {"schema_version": "adjustment-v02-analysis-1", "input_files": executions, "metadata": metadata,
            "analysis_code_sha256": {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in (Path(__file__).resolve(), Path(base.__file__).resolve())},
            "output_csv_sha256": {name + ".csv": hashlib.sha256((output / (name + ".csv")).read_bytes()).hexdigest() for name in dataset},
            "controller_semantics": "v0.2 executes an audited scalar-modified copy derived from production _step_v02; it is not an unchanged inherited integration function",
            "metadata_precedence": "instrumentation records with source/generated hashes and anchors override the inherited generic metadata.controller description",
            "observed_counts": {"single_runs": len(singles), "campaigns": len(campaigns), "campaign_run_rows": len(runs) - len(singles), "actual_runs": len(runs)},
            "instrumentation_run_counts": {field: sum(field in row for row in runs) for field in ("bands", "bands_200", "stamina_metrics", "slip_events", "stall_events", "rollback_events", "terrain")},
            "observed_event_counts": {field: sum(len(row.get(field, [])) for row in runs) for field in ("slip_events", "stall_events", "rollback_events")},
            "partial_instrumentation_runs": [{**descriptor(row), "seed": row["seed"], "campaign_id": row.get("campaign_id"), "run_index": row.get("run_index"), "missing": row["_missing_instrumentation"]} for row in runs if row["_missing_instrumentation"]],
            "input_trace_checks": trace_evidence, "embedded_policy_source_checks": policy_evidence,
            "used_mountain_seeds": sorted(set(row["seed"] for row in runs)),
            "statistics": {"quantile": "linear interpolation (n-1)*p", "completion_interval": "Wilson95%; success by observed cap",
                           "censoring": "timeouts/stalls remain censored, not natural falls; success times conditional on completion",
                           "independence": "campaign attempts excluded from single-climb completion samples",
                           "event_rates": "events/exposure; repeated within-run episodes are correlated",
                           "physical_proof": "no policy failure or detected stall is classified as proof; separate bound/replay artifact required"}}
    evidence = [output / name for name in ("generated_controller.gd", "gate-bound-123.json", "proof-review.json", "proof-review-step.json", "gate-growth-search.json", "ledge-v02-diagnostics.json", "diagnostic-review.json")]
    evidence += [Path(__file__).with_name("reachability-certificate.md"), Path(__file__).with_name("proof-review.md")]
    info["evidence_artifacts"] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in evidence if path.is_file()}
    manifest_path = output / "manifest.json"
    existing = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    if "source_config" in existing:  # preserve runner provenance if output is its directory
        existing["analysis"] = info
        info_to_write = existing
    else:
        info_to_write = info
    manifest_path.write_text(json.dumps(info_to_write, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return info["observed_counts"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = analyze(args.inputs, args.output_dir)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        parser.error(str(exc))
    print(json.dumps(result))


if __name__ == "__main__":
    main()

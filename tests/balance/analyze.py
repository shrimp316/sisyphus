#!/usr/bin/env python3
"""Aggregate measured SISYPHUS balance JSONL, using Python's standard library only."""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean, median

GROUP_FIELDS = ("job_id", "policy", "growth_mode", "growth_id", "level", "strategy")
EVENTS = ("slips", "runaways", "exhaustion_episodes", "ledge_block_episodes")


def quantile(values, probability):
    ordered = sorted(values)
    if not ordered:
        return None
    index = (len(ordered) - 1) * probability
    lower = math.floor(index)
    upper = math.ceil(index)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (index - lower)


def stats(values):
    values = [float(v) for v in values if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)]
    return {"n": len(values), "mean": mean(values) if values else None,
            "median": median(values) if values else None,
            "p25": quantile(values, .25), "p75": quantile(values, .75), "p90": quantile(values, .90)}


def wilson(successes, total):
    if not total:
        return {"n": 0, "successes": 0, "rate": None, "lower_95": None, "upper_95": None}
    z = 1.959963984540054
    p = successes / total
    denominator = 1 + z * z / total
    center = (p + z * z / (2 * total)) / denominator
    half = z * math.sqrt((p * (1 - p) + z * z / (4 * total)) / total) / denominator
    return {"n": total, "successes": successes, "rate": p,
            "lower_95": max(0, center - half), "upper_95": min(1, center + half)}


def kind(row):
    return row.get("record_type", row.get("type", "campaign" if "run_seeds" in row else "run"))


def seconds(row):
    return row.get("seconds", row.get("total_seconds", row.get("elapsed_seconds", 0)))


def read_records(paths):
    rows, seen, manifests = [], set(), []
    for path in paths:
        with path.open(encoding="utf-8-sig") as stream:
            for line_number, line in enumerate(stream, 1):
                if not line.strip():
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise ValueError(f"{path}:{line_number}: invalid JSON: {exc}") from exc
                if not isinstance(row, dict):
                    raise ValueError(f"{path}:{line_number}: expected JSON object")
                if kind(row) not in ("run", "campaign"):
                    if row.get("type") == "metadata" and row.get("schema_version", 0) < 2:
                        raise ValueError(f"{path}:{line_number}: superseded pre-current-only schema")
                    if any(job.get("growth_mode", "actual") != "actual" for job in row.get("config", {}).get("jobs", [])):
                        raise ValueError(f"{path}:{line_number}: non-actual growth configuration")
                    manifests.append(row)
                    continue
                if row.get("growth_mode") != "actual":
                    raise ValueError(f"{path}:{line_number}: only implemented actual progression is supported")
                duration = seconds(row)
                if (not isinstance(row.get("completed"), bool)
                        or not any(field in row for field in ("seconds", "total_seconds", "elapsed_seconds"))
                        or not isinstance(duration, (int, float)) or isinstance(duration, bool)
                        or not math.isfinite(duration) or duration < 0):
                    raise ValueError(f"{path}:{line_number}: missing completion/time measurement")
                identity = (kind(row), row.get("job_id"), row.get("campaign_id"), row.get("seed"), row.get("run_index"))
                if identity in seen:
                    raise ValueError(f"Duplicate sample {identity}; do not pool repeated exports or seed runs")
                seen.add(identity)
                row["_source"] = str(path)
                rows.append(row)
    if not rows:
        raise ValueError("No measured run/campaign records found")
    return rows, manifests


def grouped(rows):
    result = defaultdict(list)
    for row in rows:
        key = tuple(row.get(field) for field in GROUP_FIELDS)
        result[key].append(row)
    return result


def label(key):
    return dict(zip(GROUP_FIELDS, key))


def summarize(rows):
    complete = [row for row in rows if row["completed"]]
    elapsed = sum(seconds(row) for row in rows)
    earned = sum(row.get("earned_xp", row.get("cumulative_xp", 0)) for row in rows)
    result = {"n": len(rows), "seeds": sorted(set(row.get("seed") for row in rows if row.get("seed") is not None)),
              "completion_by_cap": wilson(len(complete), len(rows)),
              "censored_n": sum(bool(row.get("censored", False)) for row in rows),
              "status_counts": dict(Counter(row.get("status", "unknown") for row in rows)),
              "failure_association_counts_NOT_causal": dict(Counter(row.get("failure_cause", "unknown") for row in rows if row.get("status") == "fall")),
              "observed_seconds": stats(seconds(row) for row in rows),
              "completion_seconds_conditional_on_success": stats(seconds(row) for row in complete),
              "pooled_xp_per_hour": earned / elapsed * 3600 if elapsed else None}
    for field in ("peak_m", "earned_xp", "cumulative_xp", "total_xp", "starting_level", "ending_level", "pending_points", "rollback_m", "shelter_seconds", "shelter_rest_seconds", "fall_animation_seconds", "fall_descent_m", "runs", *EVENTS):
        result[field] = stats(row.get(field) for row in rows)
    active_exposure = sum(sum(band.get("exposure_seconds", 0) for band in row["bands"]) if row.get("bands") else seconds(row) for row in rows)
    result["event_exposure_seconds"] = active_exposure
    result["event_rates_per_exposure_hour"] = {
        field: sum(row[field] for row in rows) / active_exposure * 3600 if active_exposure and all(field in row for row in rows) else None for field in EVENTS}
    return result


def survival_curve(rows):
    """Kaplan-Meier first-summit curve; meaningful only for repeat-run campaigns."""
    at_time = defaultdict(list)
    for row in rows:
        at_time[seconds(row)].append(row)
    at_risk, survival, result = len(rows), 1.0, []
    for time, batch in sorted(at_time.items()):
        events = sum(bool(row["completed"]) for row in batch)
        censored = len(batch) - events
        survival *= 1 - events / at_risk
        result.append({"seconds": time, "at_risk": at_risk, "summits": events, "censored": censored,
                       "survival_without_summit": survival, "estimated_summit_fraction": 1 - survival})
        at_risk -= len(batch)
    return result


def summarize_bands(rows):
    by_band = defaultdict(list)
    for row in rows:
        for band in row.get("bands", []):
            if band.get("entered", False):
                by_band[band["index"]].append({**band, "subsequent_fall": row.get("status") == "fall"})
    result = []
    for index, bands in sorted(by_band.items()):
        exposure = sum(band.get("exposure_seconds", 0) for band in bands)
        item = {"index": index, "entered_n": len(bands), "exposure_seconds": exposure,
                "terminal_origin_in_this_band": wilson(sum(bool(b.get("death")) for b in bands), len(bands)),
                "eventual_fall_after_reaching_band": wilson(sum(bool(b["subsequent_fall"]) for b in bands), len(bands))}
        for metric in ("first_passage_seconds", "rollback_m", "shelter_seconds", "shelter_rest_seconds", "shelter_visits", "ledge_block_episodes", "slips", "exhaustion_episodes"):
            item[metric] = stats(band.get(metric) for band in bands)
        visits = sum(band.get("shelter_visits", 0) for band in bands)
        item["shelter_seconds_per_visit_pooled"] = sum(band.get("shelter_seconds", 0) for band in bands) / visits if visits else None
        item["shelter_rest_seconds_per_visit_pooled"] = sum(band.get("shelter_rest_seconds", 0) for band in bands) / visits if visits else None
        item["rates_per_exposure_hour"] = {
            event: sum(band[event] for band in bands) / exposure * 3600 if exposure and all(event in band for band in bands) else None for event in EVENTS}
        result.append(item)
    return result


def summarize_terrain(rows):
    by_terrain = defaultdict(list)
    for row in rows:
        for item in row.get("terrain", []):
            by_terrain[(item["surface"], item["angle_bin"])].append(item)
    result = []
    for (surface, angle), items in sorted(by_terrain.items()):
        exposure = sum(item.get("exposure_seconds", 0) for item in items)
        result.append({"surface": surface, "angle_bin": angle, "observations": len(items), "exposure_seconds": exposure,
                       "event_counts": {event: sum(item.get(event, 0) for item in items) for event in EVENTS},
                       "rates_per_exposure_hour": {event: sum(item.get(event, 0) for item in items) / exposure * 3600 if exposure else None for event in EVENTS}})
    return result


def economy_table(campaigns):
    thresholds = []
    for level in range(1, 32):
        points = level - 1
        thresholds.append({"player_level": level, "earned_upgrade_points": points,
                           "required_cumulative_xp": 60 * points + 5 * points * (points - 1),
                           "xp_for_next_level": 60 + 10 * points if level < 31 else 0})
    projections = []
    for key, rows in grouped(campaigns).items():
        exposure = sum(seconds(row) for row in rows)
        xp = sum(row.get("cumulative_xp", 0) for row in rows)
        rate = xp / exposure if exposure else 0
        for target in thresholds:
            required = target["required_cumulative_xp"]
            projections.append({**label(key), "player_level": target["player_level"], "required_xp": required,
                                "linear_rate_projection_seconds_NOT_measured": required / rate if rate else None,
                                "assumption": "observed pooled XP rate stays constant; ignores changing skill, cap, purchases and survivorship"})
    return thresholds, projections


def paired_comparisons(singles):
    """Compare matched mountain/policy seeds without merging different growth fixtures."""
    controls = {}
    for row in singles:
        if str(row.get("job_id", "")).startswith("baseline_"):
            controls[(row.get("policy"), row.get("seed"), row.get("level"), row.get("generation"), row.get("weather"))] = row
    result = []
    for row in singles:
        job = str(row.get("job_id", ""))
        if not job.startswith(("baseline_", "isolated_", "candidate_", "sensitivity_")):
            continue
        growth_comparison = job.startswith(("baseline_", "isolated_"))
        if job.startswith("baseline_") and row.get("level") == 0:
            continue
        reference_level = 0 if growth_comparison else row.get("level")
        control = controls.get((row.get("policy"), row.get("seed"), reference_level, row.get("generation"), row.get("weather")))
        if control is None:
            continue
        result.append({**{field: row.get(field) for field in GROUP_FIELDS}, "seed": row.get("seed"),
                       "reference_job_id": control["job_id"], "comparison": "growth_vs_zero" if growth_comparison else "difficulty_at_same_growth",
                       "ranks": row.get("start_ranks"), "completed_delta": int(row["completed"]) - int(control["completed"]),
                       "peak_m_delta": row.get("peak_m", 0) - control.get("peak_m", 0),
                       "earned_xp_delta": row.get("earned_xp", 0) - control.get("earned_xp", 0),
                       "completion_seconds_delta_if_both_summit": seconds(row) - seconds(control) if row["completed"] and control["completed"] else None,
                       "exhaustion_episodes_delta": row.get("exhaustion_episodes", 0) - control.get("exhaustion_episodes", 0),
                       "slips_delta": row.get("slips", 0) - control.get("slips", 0),
                       "rollback_m_delta": row.get("rollback_m", 0) - control.get("rollback_m", 0),
                       "shelter_rest_seconds_delta": row.get("shelter_rest_seconds", 0) - control.get("shelter_rest_seconds", 0)})
    return result


def write_csv(path, rows):
    fields = list(dict.fromkeys(key for row in rows for key in row))
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: json.dumps(value, ensure_ascii=False, sort_keys=True) if isinstance(value, (dict, list)) else value for key, value in row.items()})


def analyze(paths, output):
    rows, manifests = read_records(paths)
    runs = [row for row in rows if kind(row) == "run"]
    # Repeated runs within a campaign are not independent seed replicates.
    singles = [row for row in runs if not row.get("campaign_id")]
    campaigns = [row for row in rows if kind(row) == "campaign"]
    single_groups, campaign_groups = [], []
    for key, group in grouped(singles).items():
        single_groups.append({**label(key), **summarize(group), "bands": summarize_bands(group), "terrain": summarize_terrain(group)})
    for key, group in grouped(campaigns).items():
        campaign_groups.append({**label(key), **summarize(group), "first_summit_survival": survival_curve(group)})
    thresholds, projections = economy_table(campaigns)
    result = {"schema_version": 2, "scope": "implemented actual progression only", "sources": [str(p) for p in paths], "manifests": manifests,
              "observed_counts": {"run_rows": len(runs), "single_runs": len(singles), "campaigns": len(campaigns), "campaign_run_rows": len(runs) - len(singles)},
              "all_used_mountain_seeds": sorted(set(row["seed"] for row in runs)),
              "statistics": {"quantile": "linear interpolation at (n-1)*p", "interval": "Wilson binomial 95%",
                             "completion": "success by configured cap, censored observations remain in denominator",
                             "time": "all observations are exposure time; completion time is conditional on success only",
                             "campaign_survival": "Kaplan-Meier; assumes noninformative censoring, which stall timeouts may violate",
                             "independence": "single jobs grouped independently; campaign attempts never pooled into a binomial completion CI",
                             "failure_causality": "event associations and terminal status are not proven physical causes"},
              "single_groups": single_groups, "campaign_groups": campaign_groups,
              "current_xp_thresholds": thresholds, "current_xp_rate_projections_NOT_measured": projections,
              "paired_comparisons": paired_comparisons(singles)}
    output.mkdir(parents=True, exist_ok=True)
    (output / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    metric_rows, band_rows, terrain_rows, survival_rows = [], [], [], []
    for group in single_groups + campaign_groups:
        descriptor = {field: group[field] for field in GROUP_FIELDS}
        for metric, value in group.items():
            if isinstance(value, dict) and "n" in value:
                metric_rows.append({**descriptor, "metric": metric, **value})
        for band in group.get("bands", []):
            band_rows.append({**descriptor, **band})
        for terrain in group.get("terrain", []):
            terrain_rows.append({**descriptor, **terrain})
        for point in group.get("first_summit_survival", []):
            survival_rows.append({**descriptor, **point})
    curve_rows, purchase_rows, threshold_rows, death_xp, xp_events = [], [], [], [], []
    cumulative_seconds = defaultdict(float)
    for row in sorted(runs, key=lambda r: (str(r.get("campaign_id", "")), r.get("run_index", 0))):
        descriptor = {field: row.get(field) for field in GROUP_FIELDS}
        campaign_id = row.get("campaign_id")
        identity = (row.get("job_id"), campaign_id)
        cumulative_seconds[identity] += seconds(row)
        curve_rows.append({**descriptor, "campaign_id": campaign_id, "seed": row.get("seed"), "run_index": row.get("run_index"),
                           "elapsed_seconds": cumulative_seconds[identity] if campaign_id else seconds(row),
                           "run_seconds": seconds(row), "peak_m": row.get("peak_m"), "status": row.get("status"),
                           "earned_xp": row.get("earned_xp"), "cumulative_xp": row.get("cumulative_xp"), "ending_level": row.get("ending_level"), "end_ranks": row.get("end_ranks")})
        for event in row.get("xp_events", []):
            xp_events.append({**descriptor, "campaign_id": campaign_id, "seed": row.get("seed"), "run_index": row.get("run_index"), **event})
        if row.get("status") == "fall":
            death_xp.append({**descriptor, "seed": row.get("seed"), "peak_m": row.get("peak_m"), "earned_xp": row.get("earned_xp"), "seconds": seconds(row)})
    for row in campaigns:
        descriptor = {field: row.get(field) for field in GROUP_FIELDS}
        for purchase in row.get("purchases", []):
            purchase_rows.append({**descriptor, "campaign_id": row.get("campaign_id"), **purchase})
        measured_thresholds = {f"all_{rank}_seconds": time for rank, time in row.get("milestone_times", {}).items()}
        measured_thresholds.update(row.get("threshold_times", {}))
        threshold_rows.append({**descriptor, "campaign_id": row.get("campaign_id"), "completed": row["completed"],
                               "end_ranks": row.get("end_ranks"), **measured_thresholds})
    for name, data in [("metrics", metric_rows), ("bands", band_rows), ("terrain", terrain_rows),
                       ("first_summit_curve", survival_rows), ("xp_curve", curve_rows), ("purchases", purchase_rows),
                       ("growth_thresholds", threshold_rows), ("fall_xp", death_xp), ("xp_events", xp_events),
                       ("paired_comparisons", result["paired_comparisons"]),
                       ("current_xp_thresholds", thresholds), ("current_xp_rate_projections_NOT_measured", projections)]:
        write_csv(output / f"{name}.csv", data)
    return result["observed_counts"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path, help="Measured simulator JSONL output paths")
    parser.add_argument("--output-dir", type=Path, default=Path("tests/balance/results/analysis"))
    args = parser.parse_args()
    try:
        counts = analyze(args.inputs, args.output_dir)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        parser.error(str(exc))
    print(json.dumps({"output_dir": str(args.output_dir), **counts}))


if __name__ == "__main__":
    main()

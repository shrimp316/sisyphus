"""Aggregate actual difficulty JSONL; never infer an unobserved completion or human result."""
import argparse
import csv
import gzip
import hashlib
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def wilson(success, n):
    z = 1.959963984540054
    p = success / n
    denominator = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denominator
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denominator
    return [max(0, center - half), min(1, center + half)]


def stats(values):
    if not values:
        return {"n": 0, "mean": None, "median": None, "min": None, "max": None}
    return {"n": len(values), "mean": statistics.mean(values), "median": statistics.median(values), "min": min(values), "max": max(values)}


def table(path, records):
    keys = list(dict.fromkeys(k for r in records for k in r))
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=keys or ["no_observations"])
        writer.writeheader()
        for r in records:
            writer.writerow({k: json.dumps(v, ensure_ascii=False) if isinstance(v, (list, dict)) else v for k, v in r.items()})


def analyze(inputs, output):
    project = Path(__file__).resolve().parents[2]
    records, metadata, seen = [], [], set()
    trace_checks = []
    for path in inputs:
        loaded = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
        meta = [r for r in loaded if r["type"] == "metadata"]
        if len(meta) != 1:
            raise ValueError(f"Expected one metadata record: {path}")
        runs = [r for r in loaded if r["type"] == "run"]
        planned = sum(len(job["seeds"]) for job in meta[0]["config"]["jobs"])
        if len(runs) != planned:
            raise ValueError(f"Incomplete dataset {path}: {len(runs)}/{planned}")
        metadata.append({"input": str(path), "sha256": sha(path), **meta[0]})
        for row in runs:
            if row["id"] in seen:
                raise ValueError("Duplicate run " + row["id"])
            seen.add(row["id"])
            reference = row["input_trace"].removeprefix("res://")
            trace = Path(reference)
            if not trace.is_absolute():
                trace = project / trace
            raw = gzip.decompress(trace.read_bytes())
            if len(raw) != row["steps"] or hashlib.sha256(raw).hexdigest() != row["input_sha256"]:
                raise ValueError("Input trace mismatch: " + row["id"])
            trace_checks.append({"id": row["id"], "steps": len(raw), "gzip_sha256": sha(trace)})
            records.append(row)
    groups = defaultdict(list)
    flat, terrain, slips = [], [], []
    for r in records:
        groups[(r["candidate"], r["build"], r["policy"], r["weather"])].append(r)
        metric = {k: v for k, v in r.items() if k not in ("terrain", "slip_events", "final_state", "modifiers", "config", "type")}
        ability = r["final_state"]["mastery_run"]
        metric["bre10_rescue_used"] = ability["exhaustion_rescue_used"]
        metric["bre07_recovered_stamina"] = ability["inertia_recovered"]
        flat.append(metric)
        for item in r["terrain"]:
            record = {k: r[k] for k in ("id", "candidate", "build", "policy", "seed")}
            record.update(item)
            record["slips_per_100_active_seconds"] = item["slips"] * 100 / item["exposure_seconds"] if item["exposure_seconds"] else None
            record["normal_slips_per_100_normal_push_seconds"] = item["normal_slips"] * 100 / item["normal_push_seconds"] if item["normal_push_seconds"] else None
            terrain.append(record)
        for event in r["slip_events"]:
            slips.append({**{k: r[k] for k in ("id", "candidate", "build", "policy", "seed")}, **event})
    summary = []
    for key, runs in groups.items():
        success = sum(r["completed"] for r in runs)
        result = dict(zip(("candidate", "build", "policy", "weather"), key))
        result.update(n=len(runs), seeds=[r["seed"] for r in runs], summits=success, completion_wilson95=wilson(success, len(runs)),
                      reached_250=sum(r["reached_250"] for r in runs), falls=sum(r["status"] == "fall" for r in runs),
                      timeouts=sum(r["censored"] for r in runs),
                      summit_seconds=stats([r["seconds"] for r in runs if r["completed"]]))
        for field in ("peak_m", "seconds", "normal_slips", "slips", "exhaustions_after_rescue", "exhausted_seconds", "shelter_stationary_released_seconds", "normal_push_seconds"):
            result[field] = stats([r[field] for r in runs])
        summary.append(result)
    lookup = {(r["candidate"], r["build"], r["policy"], r["weather"], r["seed"]): r for r in records}
    pairs = []
    for r in records:
        if r["candidate"] == "legacy":
            continue
        old = lookup.get(("legacy", r["build"], r["policy"], r["weather"], r["seed"]))
        if old:
            pair = {"candidate": r["candidate"], "build": r["build"], "policy": r["policy"], "weather": r["weather"], "seed": r["seed"], "old_status": old["status"], "new_status": r["status"],
                    "old_peak_m": old["peak_m"], "new_peak_m": r["peak_m"]}
            for field in ("peak_m", "normal_slips", "slips", "exhaustions_after_rescue", "shelter_stationary_released_seconds"):
                pair[field + "_new_minus_old"] = r[field] - old[field]
            pair["summit_seconds_new_minus_old"] = r["seconds"] - old["seconds"] if r["completed"] and old["completed"] else None
            pairs.append(pair)
    output.mkdir(parents=True, exist_ok=True)
    for filename, rows in (("metrics.csv", flat), ("terrain.csv", terrain), ("slips.csv", slips), ("paired.csv", pairs)):
        table(output / filename, rows)
    (output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    manifest = {"raw_runs": len(records), "paired_old_new": len(pairs), "source_metadata": metadata, "trace_checks": trace_checks,
                "analysis_sha256": sha(Path(__file__)), "policy_metadata_interpretation": "The generic raw scope sentence about unchanged original policies applies only to names without _aware. Explicit _aware variants are new decision algorithms, with separate source hashes and policy parameter dictionaries. They are never pooled with the original policies.", "outputs_sha256": {p.name: sha(p) for p in output.iterdir() if p.name in ("metrics.csv", "terrain.csv", "slips.csv", "paired.csv", "summary.json")},
                "limitations": ["Fixed purchased fixtures, not XP campaigns", "Synthetic policies, not human cohorts", "Failure does not prove physical impossibility", "Net stamina change is not gross drain; exhaustion is counted after rescue", "Conditional summit duration excludes falls and right-censored timeouts", "Slope/surface exposure excludes runaway descent"]}
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return {"raw_runs": len(records), "paired": len(pairs)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(analyze(args.inputs, args.output_dir)))

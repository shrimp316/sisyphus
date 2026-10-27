"""Audit raw full-route evidence; no simulator or production state is changed."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path


def audit(source: Path) -> dict:
    rows = [json.loads(line) for line in source.read_text(encoding="utf-8").splitlines() if line.strip()]
    runs = [row for row in rows if row.get("type") == "run"]
    campaigns = [row for row in rows if row.get("type") == "campaign"]
    checks = []
    for row in runs:
        raw = gzip.decompress(Path(row["input_trace_gzip"]).read_bytes())
        checks.append({"job_id": row["job_id"], "seed": row["seed"], "run_index": row["run_index"],
                       "trace_matches": len(raw) == row["steps"] and hashlib.sha256(raw).hexdigest() == row["input_sha256"],
                       "xp_conserved": row["progression_end"]["total_xp"] - row["progression_start"]["total_xp"] == row["earned_xp"],
                       "early_250_passed": row["early_250_passed"]})
    summaries = []
    for campaign in campaigns:
        sequence = sorted([row for row in runs if row["campaign_id"] == campaign["campaign_id"]], key=lambda row: row["run_index"])
        continuity = all(previous["progression_end"] == following["progression_start"] for previous, following in zip(sequence, sequence[1:]))
        first = sequence[0]
        summary = {key: campaign[key] for key in ("campaign_id", "seed", "strategy", "status", "completed", "censored", "end_ranks", "total_xp", "runs")}
        summary.update({"minutes": campaign["seconds"] / 60, "all_8_minutes": campaign["milestone_times"].get("8", None),
                        "all_9_minutes": campaign["milestone_times"].get("9", None), "xp_and_rank_continuity": continuity,
                        "natural_falls": sum(row["status"] == "fall" for row in sequence),
                        "timeout_attempts": sum(row["status"] == "timeout" for row in sequence),
                        "maximum_peak_m": max(row["peak_m"] for row in sequence),
                        "first_attempt": {key: first[key] for key in ("status", "seconds", "peak_m", "earned_xp", "end_ranks", "early_250_passed")},
                        "first_attempt_pre_gate_rest": next((event for event in first["gate_observations"] if event["event"] == "pre_gate_full_heal"), None),
                        "first_post_fall_purchase": next((purchase for purchase in campaign["purchases"] if purchase["seconds"] > first["seconds"]), None)})
        for key in ("all_8_minutes", "all_9_minutes"):
            if summary[key] is not None:
                summary[key] /= 60
        summary["successful_gate_entry"] = None
        for attempt in sequence:
            if not any(event["event"] == "gate_passed" for event in attempt["gate_observations"]):
                continue
            entry = next(event for event in attempt["gate_observations"] if event["event"] == "gate_entered")
            seconds = attempt["run_start_seconds"] + entry["state"]["elapsed"]
            ranks = attempt["start_ranks"]
            for purchase in campaign["purchases"]:
                if purchase["seconds"] <= seconds:
                    ranks = purchase["ranks"]
            summary["successful_gate_entry"] = {"ranks": ranks, "stamina": entry["state"]["stamina"], "seconds": seconds,
                                                "seed": attempt["seed"], "run_index": attempt["run_index"]}
            break
        summaries.append(summary)
    return {"source": str(source), "scope": "Ideal 120Hz gate oracle, direct source-derived production integration; excludes UI/loading/purchase deliberation time. Fixed zero does not spend earned XP. Campaigns use actual Progression and natural fall retries; timeout stops the campaign.",
            "run_count": len(runs), "campaign_count": len(campaigns), "trace_and_economy_checks": checks,
            "all_checks_pass": all(check["trace_matches"] and check["xp_conserved"] for check in checks) and all(row["xp_and_rank_continuity"] for row in summaries),
            "campaigns": summaries}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.source)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: result[key] for key in ("run_count", "campaign_count", "all_checks_pass")}))
    raise SystemExit(0 if result["all_checks_pass"] else 1)

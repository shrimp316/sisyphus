"""Independent raw campaign continuity, XP arithmetic, purchase and input audit."""
from pathlib import Path
import collections
import gzip
import hashlib
import json
import math
from analyze import resolve_trace

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "tests/balance/results/act1-adjustment-v03"
INPUT = BASE / "campaigns/results.jsonl"


def level(xp):
    return 1 + max(p for p in range(31) if 5*p*p + 55*p <= xp)


def audit():
    records = [json.loads(line) for line in INPUT.read_text(encoding="utf-8").splitlines() if line.strip()]
    runs = collections.defaultdict(list)
    campaigns = []
    for row in records:
        if row.get("type") == "run":
            runs[row["campaign_id"]].append(row)
        elif row.get("type") == "campaign":
            campaigns.append(row)
    failures, summaries, selected = [], [], []
    counts = collections.Counter()

    def check(ok, label, identity):
        counts["assertions"] += 1
        if not ok:
            failures.append({"check": label, "identity": identity})

    for campaign in campaigns:
        cid = campaign["campaign_id"]
        attempts = sorted(runs[cid], key=lambda r: r["run_index"])
        check(len(attempts) == campaign["runs"], "attempt count", cid)
        elapsed = 0.0
        previous = None
        first_purchases, entry_records = [], []
        for index, row in enumerate(attempts):
            identity = [cid, index+1]
            start, end = row["progression_start"], row["progression_end"]
            check(row["run_index"] == index+1, "consecutive attempts", identity)
            check(row["seed"] == 1 + (campaign["seed"]-1+index*104729) % 2147483646, "fresh deterministic mountain seed", identity)
            check(abs(row["run_start_seconds"]-elapsed) < 1e-6, "cumulative time offset", identity)
            check(start == previous if previous is not None else start["total_xp"] == 0 and sum(start["ranks"].values()) == 0, "exact progression carry including XP and ranks", identity)
            check(row["start_ranks"] == start["ranks"] and row["end_ranks"] == end["ranks"], "physical rank ledger agrees", identity)
            initial = row["initial_state"]
            check(initial["distance"] == 0 and initial["peak"] == 0 and initial["state"] == "climbing" and initial.get("gate_ledger", {}) == {}, "fresh run reset", identity)
            check(abs(initial["stamina"]-100*(1+.02*start["ranks"]["endurance"])) < 1e-7, "fresh capacity from carried endurance", identity)
            milestones = min(20, math.floor(row["peak_m"]/50))
            expected_xp = min(6150, start["total_xp"]+20*milestones+10*max(0, milestones-start["record_milestones"]))
            check(end["total_xp"] == expected_xp == row["total_xp"], "independent milestone XP arithmetic", identity)
            check(end["run_milestones"] == milestones and end["record_milestones"] == max(milestones, start["record_milestones"]), "record/run milestones", identity)
            check(sum(e["earned_xp"] for e in row["xp_events"]) == row["earned_xp"] == expected_xp-start["total_xp"], "XP event sum", identity)
            if index < len(attempts)-1:
                check(row["status"] == "fall" and row["final_state"]["state"] == "result" and row["final_state"]["distance"] == 0 and row["runaways"] >= 1, "natural runaway/fall before retry", identity)
                counts["natural_fall_then_retry"] += 1
            else:
                check(row["status"] == "summit" and row["final_state"]["distance"] == 1000, "terminal summit", identity)
            purchases = [p for p in campaign["purchases"] if elapsed-1e-7 <= p["seconds"] < elapsed+row["seconds"]-1e-7]
            ranks = dict(start["ranks"])
            for purchase in purchases:
                ptime = purchase["seconds"]
                pxp = start["total_xp"]
                for event in row["xp_events"]:
                    if event["seconds"] <= ptime+1e-7:
                        pxp = event["total_xp"]
                position = purchase["distance_m"]
                segment = next(s for s in row["geometry_layout"] if s["start"] <= position < s["end"])
                check(segment["shelf"], "purchase on actual shelf", identity)
                check(not any(g["start_m"] <= position < g["end_m"] for g in row["candidate"]["gates"]), "no purchase inside gate", identity)
                check(purchase["total_xp"] == pxp and purchase["points_spent"] == 1, "purchase uses accumulated XP points without XP spending", identity)
                ranks[purchase["kind"]] += 1
                check(ranks == purchase["ranks"] and max(ranks.values()) <= 10, "single existing rank increment", identity)
                check(purchase["pending_points"] == level(pxp)-1-sum(ranks.values()) >= 0, "current XP cost and pending points", identity)
                counts["purchases"] += 1
            check(ranks == end["ranks"], "no unlogged growth", identity)
            if index == 0:
                first_purchases = purchases
            for gate in row["gate_telemetry"]:
                absolute_entry = elapsed + gate["entry_seconds"]
                entry_ranks = dict(start["ranks"])
                for p in purchases:
                    if p["seconds"] <= absolute_entry+1e-7:
                        entry_ranks = dict(p["ranks"])
                check(abs(gate["entry_recovery_multiplier"]-(1+.02*entry_ranks["recovery"])) < 1e-7, "entry rank uses global purchase timestamps", identity)
                entry_records.append({"run_index": index+1, "gate_id": gate["id"], "passed": gate["passed"], "absolute_entry_seconds": absolute_entry, "entry_ranks": entry_ranks, "end_ranks": end["ranks"]})
            raw_path = row["input_trace_gzip"]
            path = resolve_trace(raw_path, ROOT)
            raw = gzip.decompress(path.read_bytes())
            check(len(raw) == row["steps"] and hashlib.sha256(raw).hexdigest() == row["input_sha256"] and all(c < 8 for c in raw), "raw input SHA/count/commands", identity)
            counts["raw_inputs"] += 1
            previous = end
            elapsed += row["seconds"]
        check(abs(elapsed-campaign["seconds"]) < 1e-6 and previous["total_xp"] == campaign["total_xp"] and previous["ranks"] == campaign["end_ranks"], "campaign terminal summary", cid)
        first = attempts[0]
        gate_entry = next((g for g in first["gate_telemetry"] if g["id"] == "late_gate"), None)
        before_gate = [p for p in first_purchases if gate_entry and p["seconds"] <= gate_entry["entry_seconds"]+1e-7]
        summaries.append({"campaign_id": cid, "attempts": len(attempts), "first_status": first["status"], "first_fall_xp": first["total_xp"], "first_purchase_distance": first_purchases[0]["distance_m"] if first_purchases else None, "first_attempt_purchases_before_gate": len(before_gate), "first_entry_ranks": next((e["entry_ranks"] for e in entry_records if e["run_index"] == 1 and e["gate_id"] == "late_gate"), None), "first_attempt_xp_events": [{"peak_m":e["peak_m"],"total_xp":e["total_xp"]} for e in first["xp_events"]], "gate_entries":entry_records, "success_seconds":campaign["seconds"]})
        selected.extend([attempts[0], attempts[1], attempts[-1]])
    output = {"input": str(INPUT), "input_sha256":hashlib.sha256(INPUT.read_bytes()).hexdigest(), "campaigns":len(campaigns), "attempts":sum(len(a) for a in runs.values()), "counts":dict(counts), "failures":failures, "summaries":summaries, "scope":"Observed first-attempt failure is not proof that every upgraded first-attempt input fails. Purchases are checked against actual geometry/XP timestamps; stationary/climbing guard is enforced in unchanged purchase source and separately checked during selected raw replay. Gate-entry ranks are derived using cumulative run offsets, not campaign terminal ranks."}
    (BASE/"independent-campaign-audit.json").write_text(json.dumps(output, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    selected_path = BASE/"independent-campaign-selected.jsonl"
    selected_path.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in [r for r in records if r.get("type")=="metadata"]+selected)+"\n", encoding="utf-8")
    print(json.dumps({k:output[k] for k in ["campaigns","attempts","counts","failures"]}))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(audit())

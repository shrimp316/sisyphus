"""Synthetic semantic regression tests; fixtures are not gameplay evidence."""
import csv
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("v03_analysis", Path(__file__).with_name("analyze.py"))
a = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(a)


def run(seed=1, campaign_id="", run_index=1):
    return {"type": "run", "job_id": "fixture", "growth_mode": "actual", "growth_id": "balanced_0",
            "candidate": {"id": "test"}, "policy": "regular", "level": 0, "strategy": "balanced",
            "seed": seed, "campaign_id": campaign_id, "run_index": run_index, "status": "timeout",
            "completed": False, "censored": True, "seconds": 20, "peak_m": 30, "earned_xp": 0,
            "bands": [], "bands_200": [], "stamina_metrics": {}, "slip_events": [], "stall_events": [],
            "gate_telemetry": [{"id": "g1", "entry_seconds": 10, "entry_stamina": 90,
                                "seconds_budget": 10, "seconds_remaining": 7, "seconds_used": 3, "recovered_amount": 6,
                                "entries": 2, "passed": False, "exit_seconds": None}]}


class V03AnalysisTests(unittest.TestCase):
    def test_unentered_gates_not_entry_failures_and_missing_not_zero(self):
        one, two = run(), run(2)
        two["gate_telemetry"][0].update(entry_seconds=None, seconds_remaining=None)
        records = a.gate_rows([one, two])
        passage = next(r for r in records if r["metric"] == "pass_conditional_on_entry")
        self.assertEqual((passage["observed_run_count"], passage["entered_count"], passage["n"]), (2, 1, 1))
        reserve = next(r for r in records if r["metric"] == "seconds_remaining")
        self.assertEqual((reserve["n"], reserve["mean"]), (1, 7))

    def test_reentry_is_one_gate_sample_and_attempts_have_no_independent_ci(self):
        records = a.gate_rows([run(campaign_id="c")], independent=False)
        passage = next(r for r in records if r["metric"] == "pass_conditional_on_entry")
        self.assertEqual(passage["n"], 1)
        self.assertNotIn("lower_95", passage)

    def test_extra_ablation_factor_separates_statistics(self):
        one, two = run(), run(2)
        one.update(ablation_stat="strength", seconds=10)
        two.update(ablation_stat="recovery", seconds=30)
        rows = a.reused(a.previous.metric_rows, [one, two], "single")
        times = [r for r in rows if r["metric"] == "seconds"]
        self.assertEqual({(r["ablation_stat"], r["n"], r["mean"]) for r in times}, {("strength", 1, 10), ("recovery", 1, 30)})

    def test_future_unlock_at_shelf_end_is_not_an_actual_purchase(self):
        row = run()
        row["geometry_layout"] = [{"start": 242, "end": 250, "shelf": True},
                                  {"start": 250, "end": 292, "shelf": False},
                                  {"start": 292, "end": 300, "shelf": True}]
        result = a.unlock_geometry_rows([row])
        first = result[0]
        self.assertFalse(first["shelf_at_threshold_geometric"])
        self.assertEqual(first["forward_distance_to_next_shelf_m"], 42)
        self.assertFalse(first["unlock_implemented"])
        self.assertEqual(first["purchase_feasibility"], "not_simulated")
        self.assertFalse(result[-1]["can_cause_same_first_summit"])

    def test_existing_other_analysis_is_immutable(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            original = '{"schema_version":"other-family"}'
            (root / "manifest.json").write_text(original)
            with self.assertRaisesRegex(ValueError, "new v0.3 analysis directory"):
                a.analyze([], root)
            self.assertEqual((root / "manifest.json").read_text(), original)

    def test_running_dataset_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            raw = root / "worker.jsonl"
            raw.write_text(json.dumps(run()) + "\n")
            (root / "manifest.json").write_text(json.dumps({"source_config": "fixture", "status": "running"}))
            with self.assertRaisesRegex(ValueError, "not complete"):
                a.analyze([raw], root / "report")

    def test_campaign_first_attempt_and_xp_are_not_duplicate_singles(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            first, second = run(1, "c", 1), run(2, "c", 2)
            first["xp_events"] = [{"seconds": 8, "total_xp": 20, "earned_xp": 20}]
            campaign = {"type": "campaign", "job_id": "fixture", "growth_mode": "actual",
                        "seed": 1, "campaign_id": "c", "status": "time_limit", "completed": False,
                        "censored": True, "seconds": 40, "runs": 2, "purchases": [{"seconds": 25, "points_spent": 1}]}
            raw = root / "raw.jsonl"
            raw.write_text("\n".join(map(json.dumps, [first, second, campaign])) + "\n")
            output = root / "analysis"
            output.mkdir()
            (output / "summary.md").write_text("owner report")
            result = a.analyze([raw], output)
            self.assertEqual(result, {"single_runs": 0, "campaigns": 1, "campaign_run_rows": 2, "actual_runs": 2})
            rows = list(csv.DictReader(io.StringIO((output / "metrics.csv").read_text(encoding="utf-8"))))
            self.assertEqual({r["record_type"] for r in rows}, {"campaign"})
            first_rows = list(csv.DictReader(io.StringIO((output / "first_attempt.csv").read_text(encoding="utf-8"))))
            self.assertEqual(next(r for r in first_rows if r["metric"] == "completion_by_cap")["n"], "1")
            xp = list(csv.DictReader(io.StringIO((output / "xp.csv").read_text(encoding="utf-8"))))
            self.assertEqual([r["event_type"] for r in xp], ["xp_award", "purchase"])
            self.assertEqual((output / "summary.md").read_text(), "owner report")
            self.assertEqual(len((output / "stalls.csv").read_text().splitlines()), 1)
            a.analyze([raw], output)
            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["first_attempt_rows"], 1)

    def test_duplicate_gate_summary_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            row = run()
            row["gate_telemetry"] *= 2
            raw = root / "raw.jsonl"
            raw.write_text(json.dumps(row) + "\n")
            with self.assertRaisesRegex(ValueError, "one telemetry summary"):
                a.analyze([raw], root / "out")

    def test_partial_entry_target_is_never_a_full_route_completion(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            row = run()
            row.update(entry_fixture={"distance_m": 750}, status="diagnostic_target", censored=False,
                       peak_m=873, physics_mode="direct audited production _step_v02 120Hz; observer omitted",
                       input_sha256="synthetic", input_trace_gzip="synthetic.gz")
            for field in ("bands", "bands_200", "stamina_metrics", "slip_events", "stall_events"):
                row.pop(field)
            raw = root / "raw.jsonl"
            raw.write_text(json.dumps(row) + "\n")
            output = root / "out"
            with patch.object(a, "input_trace_evidence", return_value=([], [])):
                counts = a.analyze([raw], output)
            self.assertEqual(counts["actual_runs"], 0)
            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["diagnostic_fixture_runs"], 1)
            self.assertEqual(len(manifest["partial_instrumentation_runs"]), 1)
            metrics = list(csv.DictReader(io.StringIO((output / "fixture_metrics.csv").read_text(encoding="utf-8"))))
            target = next(r for r in metrics if r["metric"] == "diagnostic_target_reached_NOT_summit")
            self.assertEqual(target["successes"], "1")
            self.assertEqual(len((output / "metrics.csv").read_text().splitlines()), 1)

    def test_capped_xp_milestone_is_not_a_positive_award(self):
        row = run()
        row.update(_source="synthetic", xp_events=[{"seconds": 8, "total_xp": 6150, "earned_xp": 0}])
        result = a.xp_rows([row], [])
        self.assertEqual(result[0]["event_type"], "milestone_no_award")

    def test_campaign_join_uses_absolute_time_and_observed_retry_ledger(self):
        first, second = run(1, "c", 1), run(2, "c", 2)
        first.update(seconds=100, status="fall", total_xp=510, end_ranks={"strength": 2},
                     xp_events=[{"peak_m": 250.001, "total_xp": 150}, {"peak_m": 750.002, "total_xp": 450}])
        first["gate_telemetry"][0]["entry_seconds"] = 90
        second.update(run_start_seconds=100, seconds=50, completed=True,
                      progression_start={"total_xp": 510, "ranks": {"strength": 2}})
        second["gate_telemetry"][0]["entry_seconds"] = 30
        campaign = {"job_id": "fixture", "campaign_id": "c", "seed": 1, "completed": True, "seconds": 150, "runs": 2,
                    "purchases": [{"seconds": 80, "ranks": {"strength": 2}}, {"seconds": 120, "ranks": {"strength": 3}}]}
        reviewed = a.campaign_review([first, second], [campaign])["records"][0]
        self.assertEqual(reviewed["first_attempt_checkpoints"]["250"]["total_xp"], 150)
        self.assertEqual([e["ranks_at_registered_entry"] for e in reviewed["gate_entries"]], [{"strength": 2}, {"strength": 3}])
        self.assertTrue(reviewed["retry_xp_preserved"])
        self.assertTrue(reviewed["retry_ranks_preserved"])
        self.assertEqual(reviewed["first_retry_purchase"]["seconds"], 120)

    def test_bounded_route_target_and_timeout_without_entry_fixture_are_excluded(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            reached, timeout = run(), run(2)
            reached.update(status="diagnostic_target", censored=False)
            metadata = {"type": "metadata", "schema_version": 3,
                        "config": {"jobs": [{"id": "fixture", "stop_after_m": 100}]}}
            raw = root / "raw.jsonl"
            raw.write_text("\n".join(map(json.dumps, [metadata, reached, timeout])) + "\n")
            output = root / "out"
            self.assertEqual(a.analyze([raw], output)["single_runs"], 0)
            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["bounded_diagnostic_runs"], 2)
            self.assertEqual(manifest["diagnostic_fixture_runs"], 0)
            rows = list(csv.DictReader(io.StringIO((output / "fixture_metrics.csv").read_text(encoding="utf-8"))))
            target = next(r for r in rows if r["metric"] == "diagnostic_target_reached_NOT_summit")
            self.assertEqual((target["n"], target["successes"]), ("2", "1"))

    def test_archived_windows_trace_is_rebased_and_verified(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            trace = root / a.TRACE_NAMESPACE / "input-traces" / "fixture.gz"
            trace.parent.mkdir(parents=True)
            raw = bytes((0, 1, 3, 4))
            trace.write_bytes(gzip.compress(raw))
            row = {**run(), "input_trace_gzip": "Z:\\retired\\machine\\" + a.TRACE_NAMESPACE.replace("/", "\\") + "input-traces\\fixture.gz",
                   "steps": 4, "input_sha256": hashlib.sha256(raw).hexdigest()}
            checks, _ = a.input_trace_evidence([row], [], root)
            self.assertEqual(checks[0]["path"], a.TRACE_NAMESPACE + "input-traces/fixture.gz")
            row["steps"] = 3
            with self.assertRaisesRegex(ValueError, "step count mismatch"):
                a.input_trace_evidence([row], [], root)
            row["steps"], row["input_sha256"] = 4, "incorrect"
            with self.assertRaisesRegex(ValueError, "Raw input hash mismatch"):
                a.input_trace_evidence([row], [], root)

    def test_trace_traversal_is_rejected_before_read(self):
        with tempfile.TemporaryDirectory() as temp:
            for bad in ("Z:/old/" + a.TRACE_NAMESPACE + "../outside.gz",
                        "res://" + a.TRACE_NAMESPACE + "input-traces/./fixture.gz",
                        "Z:/old/not-owned/fixture.gz"):
                with self.assertRaises(ValueError):
                    a.resolve_trace(bad, Path(temp))

    def test_windows_normalization_and_ads_suffixes_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            for suffix in ("input-traces/.. /.. /outside.gz", "input-traces/trace.gz:stream",
                           "input-traces//trace.gz", "input-traces/trace.gz.",
                           "input-traces/trace.gz ", "input-traces /trace.gz", "input-traces/", ""):
                with self.subTest(suffix=suffix):
                    with self.assertRaisesRegex(ValueError, "Unsafe Windows"):
                        a.resolve_trace("Z:/old/" + a.TRACE_NAMESPACE + suffix, Path(temp))


if __name__ == "__main__":
    unittest.main()

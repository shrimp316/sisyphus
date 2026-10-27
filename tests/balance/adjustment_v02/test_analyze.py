"""Synthetic fixtures test data semantics; fixtures are not gameplay measurements."""
import csv
import gzip
import hashlib
import importlib.util
import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("adjustment_analysis", Path(__file__).with_name("analyze.py"))
a = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(a)


def run_row(seed=1, campaign_id=""):
    return {"type": "run", "job_id": "A0_regular_0", "growth_mode": "actual", "growth_id": "balanced_0",
            "candidate": {"id": "A0"}, "experiment_case": "fixed_zero", "policy": "regular", "level": 0,
            "strategy": "balanced", "seed": seed, "campaign_id": campaign_id, "run_index": 1,
            "completed": False, "censored": True, "status": "timeout", "seconds": 20, "peak_m": 30,
            "stamina_metrics": {"consumed": 5, "recovered": 2, "mean_stamina": 90, "active_seconds": 20},
            "bands": [{"index": 0, "entered": True, "exposure_seconds": 20, "slips": 1, "stamina_integral": 1800}],
            "bands_200": [{"index": 0, "entered": True, "exposure_seconds": 20, "slips": 1, "stamina_integral": 1800}],
            "slip_events": [{"seconds": 10, "distance_m": 20, "outcome": "censored"}], "stall_events": [],
            "shelter_events": [{"entry_stamina": 50, "exit_stamina": 80, "stationary_seconds": 3}], "earned_xp": 0}


class AdjustmentAnalysisTests(unittest.TestCase):
    def test_both_band_widths_and_absent_rates(self):
        rows = a.band_rows([run_row()])
        self.assertEqual({r["band_width_m"] for r in rows}, {200, 250})
        self.assertEqual([r["value"] for r in rows if r["metric"] == "exposure_weighted_stamina"], [90, 90])
        self.assertTrue(all(r["value"] is None for r in rows if r["metric"] == "runaways_per_exposure_hour"))

    def test_censored_slip_not_recovery_or_runaway(self):
        summary = a.risk_rows([run_row()])[0]
        self.assertEqual(summary["outcomes"], {"censored": 1})
        self.assertEqual(summary["recovered_fraction_all_observed"], 0)
        self.assertEqual(summary["runaway_fraction_all_observed"], 0)

    def test_exposure_rate_and_missing_counter(self):
        self.assertEqual(a.pooled_rate([{"events": 2, "seconds": 30}, {"events": 0, "seconds": 30}], "events", "seconds"), 120)
        self.assertIsNone(a.pooled_rate([{"seconds": 30}], "events", "seconds"))

    def test_input_risk_rates_use_disjoint_command_exposure(self):
        row = run_row()
        row["stamina_metrics"].update(push_seconds=5, exert_seconds=10, brace_seconds=2, active_seconds=20)
        row["slip_events"][0]["input"] = [True, True, False]
        results = [item for item in a.risk_rows([row]) if item.get("metric") == "slips_per_command_hour"]
        by_input = {item["input_category"]: item for item in results}
        self.assertEqual(by_input["exert"]["value"], 360)
        self.assertEqual(by_input["released"]["exposure_seconds"], 3)
        self.assertEqual(by_input["push"]["value"], 0)

    def test_current_policy_failure_not_physical_proof(self):
        row = run_row()
        row["stall_events"] = [{"start_seconds": 5, "end_seconds": 20, "duration_seconds": 15,
                                "distance_m": 30, "input_history": [[5, True, False, False]],
                                "replay_start_state": {"distance": 30}, "replay_end_state": {"distance": 30}}]
        with tempfile.TemporaryDirectory() as temp:
            rows = a.stall_rows([row], Path(temp))
            self.assertEqual(rows[0]["physical_proof_status"], "not_assessed")
            replay = json.loads((Path(temp) / rows[0]["replay_file"]).read_text())
            self.assertEqual(replay["event"]["input_history"], [[5, True, False, False]])

    def test_campaigns_independent_and_required_outputs(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "source.jsonl"
            row = run_row(campaign_id="c1")
            campaign = {"type": "campaign", "job_id": row["job_id"], "growth_mode": "actual", "growth_id": "balanced_0",
                        "policy": "regular", "seed": 1, "campaign_id": "c1", "completed": False, "censored": True,
                        "status": "run_timeout", "seconds": 20, "runs": 1}
            path.write_text(json.dumps(row) + "\n" + json.dumps(campaign) + "\n")
            output = Path(temp) / "report"
            output.mkdir()
            (output / "summary.md").write_text("human-authored report")
            counts = a.analyze([path], output)
            self.assertEqual(counts, {"single_runs": 0, "campaigns": 1, "campaign_run_rows": 1, "actual_runs": 1})
            for name in ("metrics", "bands", "stamina", "slip", "stalls", "campaigns"):
                self.assertTrue((output / f"{name}.csv").exists())
            self.assertIn("duration_seconds", (output / "stalls.csv").read_text())
            self.assertEqual(len((output / "stalls.csv").read_text().splitlines()), 1)
            self.assertEqual((output / "summary.md").read_text(), "human-authored report")
            with (output / "metrics.csv").open() as stream:
                self.assertEqual({r["record_type"] for r in csv.DictReader(stream)}, {"campaign"})

    def test_legacy_instrumentation_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            row = run_row()
            del row["bands_200"]
            path = Path(temp) / "legacy.jsonl"
            path.write_text(json.dumps(row) + "\n")
            with self.assertRaisesRegex(ValueError, "Not a v0.2 instrumented run"):
                a.analyze([path], Path(temp) / "output")

    def test_explicit_gate_witness_partial_metrics_and_policy_separation(self):
        with tempfile.TemporaryDirectory() as temp:
            row = run_row()
            for field in ("stamina_metrics", "bands", "bands_200", "slip_events", "stall_events"):
                del row[field]
            row["physics_mode"] = "direct generated production _step_v02 120Hz"
            row["policy_variant"] = "gate_oracle_1p195"
            row["input_sha256"] = "fixture-only"
            row["input_trace_gzip"] = "fixture-not-actual.bin.gz"
            metadata = {"type": "metadata", "physics_mode": "direct source-derived production _step_v02 at 120Hz; observer wrapper omitted",
                        "human_policy": False, "policy_source_sha256": "fixture-only"}
            path = Path(temp) / "gate.jsonl"
            path.write_text(json.dumps(metadata) + "\n" + json.dumps(row) + "\n")
            output = Path(temp) / "report"
            with patch.object(a, "input_trace_evidence", return_value=([], [])):
                a.analyze([path], output)
            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(len(manifest["partial_instrumentation_runs"]), 1)
            with (output / "stamina.csv").open() as stream:
                records = list(csv.DictReader(stream))
            self.assertEqual(records[0]["metric"], "instrumentation_unavailable")
            ordinary = {**row, "policy_variant": "configured_policy"}
            self.assertEqual(len(a.groups([ordinary, row])), 2)

    def test_raw_input_hash_verified_and_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            raw = bytes([0, 1, 3])
            path = root / "trace.bin.gz"
            path.write_bytes(gzip.compress(raw))
            row = {**run_row(), "input_trace_gzip": str(path), "input_sha256": hashlib.sha256(raw).hexdigest(), "steps": 3}
            evidence, _ = a.input_trace_evidence([row], [], root)
            self.assertEqual(evidence[0]["steps"], 3)
            row["input_sha256"] = "wrong"
            with self.assertRaisesRegex(ValueError, "Raw input hash mismatch"):
                a.input_trace_evidence([row], [], root)

    def test_running_execution_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "worker_00.jsonl"
            source.write_text(json.dumps(run_row()) + "\n")
            (root / "manifest.json").write_text(json.dumps({"source_config": "fixture", "status": "running"}))
            with self.assertRaisesRegex(ValueError, "Execution is not complete"):
                a.analyze([source], root / "report")

    def test_repeated_aggregate_does_not_embed_itself_as_execution_manifest(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "raw.jsonl"
            source.write_text(json.dumps(run_row()) + "\n")
            a.analyze([source], root)
            a.analyze([source], root)
            manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
            self.assertIsNone(manifest["input_files"][0]["execution_manifest"])

    def test_runner_follows_alternate_script_dependencies(self):
        spec = importlib.util.spec_from_file_location("experiment_runner", Path(__file__).resolve().parents[1] / "run_experiments.py")
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            contents = {"project.godot": "", "tests/balance/simulator.gd": "", "tests/balance/balance_controller.gd": "",
                        "tests/balance/policies.json": "{}", "new/simulator.gd": 'extends "res://new/controller.gd"',
                        "new/controller.gd": 'var config = "res://new/policies.json"\nvar output = "res://tests/balance/results/generated.gd"\nvar pattern = "res://data/chunks/zone_%d_%s.tres"',
                        "new/policies.json": "{}"}
            for name, text in contents.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            before = runner.code_hashes(root, "new/simulator.gd")
            self.assertIn("new/controller.gd", before)
            self.assertIn("new/policies.json", before)
            (root / "new/controller.gd").write_text("changed")
            self.assertNotEqual(before, runner.code_hashes(root, "new/simulator.gd"))


if __name__ == "__main__":
    unittest.main()

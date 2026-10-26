"""Small synthetic unit fixtures validate statistics; they are not experiment results."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("balance_analyze", Path(__file__).with_name("analyze.py"))
analyze = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analyze)


class AnalysisTests(unittest.TestCase):
    def test_quantiles_and_missing_values(self):
        self.assertEqual(analyze.stats([0, 10, 20, 30, None]),
                         {"n": 4, "mean": 15, "median": 15, "p25": 7.5, "p75": 22.5, "p90": 27})
        self.assertIsNone(analyze.stats([])["mean"])

    def test_small_sample_interval_does_not_claim_certainty(self):
        self.assertGreater(analyze.wilson(0, 3)["upper_95"], .5)
        self.assertLess(analyze.wilson(3, 3)["lower_95"], .5)
        self.assertIsNone(analyze.wilson(0, 0)["rate"])

    def test_censored_times_excluded_from_success_average(self):
        result = analyze.summarize([
            {"completed": True, "seconds": 100, "status": "summit", "earned_xp": 30},
            {"completed": False, "seconds": 200, "status": "timeout", "censored": True, "earned_xp": 0}])
        self.assertEqual(result["completion_by_cap"]["rate"], .5)
        self.assertEqual(result["completion_seconds_conditional_on_success"]["mean"], 100)
        self.assertEqual(result["observed_seconds"]["mean"], 150)
        self.assertEqual(result["censored_n"], 1)
        self.assertEqual(result["pooled_xp_per_hour"], 360)

    def test_exposure_rates_not_raw_event_ranking(self):
        result = analyze.summarize_terrain([{"terrain": [
            {"surface": "rock", "angle_bin": "10-15", "exposure_seconds": 3600, "slips": 2},
            {"surface": "mud", "angle_bin": "10-15", "exposure_seconds": 60, "slips": 1}]}])
        by_surface = {item["surface"]: item for item in result}
        self.assertEqual(by_surface["rock"]["rates_per_exposure_hour"]["slips"], 2)
        self.assertEqual(by_surface["mud"]["rates_per_exposure_hour"]["slips"], 60)

    def test_survival_tied_censor_event(self):
        points = analyze.survival_curve([
            {"seconds": 10, "completed": True}, {"seconds": 10, "completed": False},
            {"seconds": 20, "completed": True}])
        self.assertAlmostEqual(points[0]["survival_without_summit"], 2 / 3)
        self.assertEqual(points[1]["survival_without_summit"], 0)

    def test_band_event_absence_and_later_fall_are_distinct(self):
        rows = [{"status": "fall", "bands": [{"index": 0, "entered": True, "death": False, "exposure_seconds": 10, "slips": 0}]}]
        band = analyze.summarize_bands(rows)[0]
        self.assertEqual(band["eventual_fall_after_reaching_band"]["rate"], 1)
        self.assertEqual(band["terminal_origin_in_this_band"]["rate"], 0)
        self.assertIsNone(band["rates_per_exposure_hour"]["runaways"])

    def test_exact_economic_costs(self):
        rows, _ = analyze.economy_table([])
        self.assertEqual(rows[24]["required_cumulative_xp"], 4200)
        self.assertEqual(rows[27]["required_cumulative_xp"], 5130)
        self.assertEqual(rows[30]["required_cumulative_xp"], 6150)
        self.assertEqual(rows[30]["xp_for_next_level"], 0)

    def test_duplicate_measurements_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "fixture.jsonl"
            row = {"record_type": "run", "growth_mode": "actual", "job_id": "fixture", "seed": 1, "completed": True, "seconds": 10}
            path.write_text((json.dumps(row) + "\n") * 2, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Duplicate sample"):
                analyze.read_records([path])

    def test_non_actual_growth_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "fixture.jsonl"
            row = {"record_type": "run", "growth_mode": "hypothetical", "seed": 1, "completed": True, "seconds": 10}
            path.write_text(json.dumps(row) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "only implemented actual progression"):
                analyze.read_records([path])

    def test_missing_time_is_not_fabricated_as_zero(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "fixture.jsonl"
            row = {"record_type": "run", "growth_mode": "actual", "seed": 1, "completed": True}
            path.write_text(json.dumps(row) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "missing completion/time measurement"):
                analyze.read_records([path])

    def test_isolated_growth_groups_are_separate(self):
        rows = [{"job_id": "fixture", "growth_mode": "actual", "growth_id": growth} for growth in ["strength_5", "endurance_5"]]
        self.assertEqual(len(analyze.grouped(rows)), 2)

    def test_growth_comparison_uses_same_seed_and_no_failed_time_improvement(self):
        common = {"policy": "regular", "growth_mode": "actual", "seed": 101, "generation": 6, "weather": "clear", "level": 0}
        rows = [{**common, "job_id": "baseline_actual_regular_0", "completed": False, "seconds": 50, "peak_m": 100},
                {**common, "job_id": "isolated_regular_strength_5", "growth_id": "strength_5", "completed": True, "seconds": 600, "peak_m": 1000},
                {**common, "seed": 202, "job_id": "isolated_regular_strength_5", "completed": True, "seconds": 590}]
        pairs = analyze.paired_comparisons(rows)
        self.assertEqual(len(pairs), 1)
        self.assertEqual(pairs[0]["completed_delta"], 1)
        self.assertEqual(pairs[0]["peak_m_delta"], 900)
        self.assertIsNone(pairs[0]["completion_seconds_delta_if_both_summit"])

    def test_campaign_attempts_not_independent_completion_samples(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "fixture.jsonl"
            common = {"job_id": "fixture", "campaign_id": "fixture-1", "policy": "regular", "growth_mode": "actual", "level": 0, "strategy": "balanced"}
            rows = [{**common, "record_type": "run", "seed": i, "run_index": i, "completed": False, "seconds": 10, "earned_xp": 20, "xp_events": [{"seconds": i * 10, "run_seconds": 10, "milestone": 1, "earned_xp": 20, "total_xp": i * 20, "level": 1}]} for i in [1, 2]]
            rows.append({**common, "record_type": "campaign", "seed": 1, "completed": False, "censored": True, "seconds": 20, "runs": 2, "milestone_times": {"3": 15, "8": 19}})
            path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")
            output = Path(temp) / "output"
            counts = analyze.analyze([path], output)
            self.assertEqual(counts, {"run_rows": 2, "single_runs": 0, "campaigns": 1, "campaign_run_rows": 2})
            result = json.loads((output / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(result["single_groups"], [])
            self.assertEqual(result["campaign_groups"][0]["n"], 1)
            self.assertIn("all_8_seconds", (output / "growth_thresholds.csv").read_text())
            self.assertIn("19", (output / "growth_thresholds.csv").read_text())
            self.assertIn("milestone", (output / "xp_events.csv").read_text())
            self.assertEqual(len((output / "xp_events.csv").read_text().splitlines()), 3)


if __name__ == "__main__":
    unittest.main()

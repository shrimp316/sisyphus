extends "res://tests/mvp/s190_experiment.gd"

func funded_profile(_counts: Array):
	return super.funded_profile([10,10,0])

func run() -> void:
	policies=JSON.parse_string(FileAccess.get_file_as_string(policy_path())).policies
	result_directory="res://tests/mvp/results/s190-breath-ablation"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(result_directory))
	var file:=FileAccess.open(result_directory.path_join("results.jsonl"),FileAccess.WRITE)
	file.store_line(JSON.stringify({"type":"metadata","source_sha256":FileAccess.get_sha256("res://tests/mvp/s190_ablation.gd"),"reference":"res://tests/mvp/results/s190/results.jsonl","scope":"Same STR10/END10; remove all BRE nodes. Same seeds/policies/full route; unequal purchase cost intentionally isolates the BRE branch rather than equal-budget allocation. Fixed artificial funding, not campaign."}))
	for policy_name: String in POLICY_NAMES:
		for seed_value: int in [101,202,303]:
			var row: Dictionary=run_case(seed_value,"all30",policy_name,false)
			row.build="strength10_endurance10_breath0"
			row.counts=[10,10,0]
			row.id="route-no_breath-%s-%d"%[policy_name,seed_value]
			row.type="run"
			file.store_line(JSON.stringify(row))
			file.flush()
			print(row.id," ",row.status," peak=",row.peak_m)
	file.close()
	quit(0)

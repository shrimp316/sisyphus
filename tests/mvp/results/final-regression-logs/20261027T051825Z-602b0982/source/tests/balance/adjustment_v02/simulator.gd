extends "res://tests/balance/simulator.gd"

const Terrain = preload("res://tests/balance/adjustment_v02/terrain.gd")
const Factory = preload("res://tests/balance/adjustment_v02/controller_factory.gd")
const EXPERIMENT_KEYS: Array[String] = ["moving_shelf_recovery_scale", "geometry_mode", "geometry_overrides", "late_grip_scale", "late_grip_start_m", "slip_gain_after500_scale", "slip_decay_after750_scale", "uphill_recovery_after_m", "uphill_recovery_scale"]
var factory = Factory.new()
var active_job: Dictionary = {}

func run() -> void:
	if not factory.build():
		printerr("Cannot construct audited v02 controller")
		quit(2)
		return
	super.run()

func policy_path() -> String:
	return "res://tests/balance/adjustment_v02/policies.json"

func metadata_additions() -> Dictionary:
	return factory.patch_manifest

func valid_job(job: Dictionary) -> bool:
	var ordinary: Dictionary = job.duplicate(true)
	var candidate: Dictionary = ordinary.get("candidate", {})
	for key: String in EXPERIMENT_KEYS:
		candidate.erase(key)
	if not super.valid_job(ordinary):
		return false
	candidate = job.get("candidate", {})
	for key: String in ["moving_shelf_recovery_scale", "late_grip_scale", "slip_gain_after500_scale", "slip_decay_after750_scale", "uphill_recovery_scale"]:
		if not is_finite(float(candidate.get(key, 1.0))) or float(candidate.get(key, 1.0)) < 0.0:
			printerr("Experimental scales must be finite and nonnegative")
			return false
	if str(candidate.get("geometry_mode", "B0")) not in ["B0", "B1", "B2", "B3"]:
		printerr("Unknown geometry mode")
		return false
	for override: Dictionary in candidate.get("geometry_overrides", []):
		if int(override.get("chunk_index", -1)) < 5 or int(override.get("chunk_index", -1)) >= 20:
			printerr("Geometry overrides must preserve first 250m")
			return false
		if float(override.get("climb_length", 42.0)) < 0.0 or float(override.get("climb_length", 42.0)) > 50.0 or float(override.get("angle", 20.0)) < 0.0 or float(override.get("angle", 20.0)) > 45.0 or str(override.get("surface", "STONE")) not in ["STONE", "SOIL", "GRAVEL", "MUD", "WET_STONE"]:
			printerr("Invalid explicit geometry override")
			return false
		for interval: Array in override.get("wet_ranges", []):
			if interval.size() != 2 or float(interval[0]) < 0.0 or float(interval[1]) > 50.0 or float(interval[0]) >= float(interval[1]):
				return false
	if float(job.get("stall_seconds", 45.0)) <= 0.0:
		return false
	return true

func create_world(seed_value: int, job: Dictionary) -> MountainManager:
	return Terrain.new(seed_value, false, int(job.get("generation", 6)), str(job.get("weather", "")))

func configure_world(world: MountainManager, candidate: Dictionary) -> void:
	super.configure_world(world, candidate)
	world.configure_experiment(candidate)

func create_controller(world: MountainManager, candidate: Dictionary) -> BoulderController:
	var controller: BoulderController = factory.create(world, candidate)
	controller.stall_seconds = float(active_job.get("stall_seconds", 45.0))
	controller.stall_progress_m = float(active_job.get("stall_progress_m", 0.25))
	return controller

func simulate_run(job: Dictionary, seed_value: int, profile: Dictionary, run_index: int, campaign_id: String) -> Dictionary:
	active_job = job
	return super.simulate_run(job, seed_value, profile, run_index, campaign_id)

func choose_kind(ranks: Dictionary, strategy: String) -> String:
	if strategy in ["endurance", "recovery"]:
		var order: Array[String] = [strategy, "strength", "recovery" if strategy == "endurance" else "endurance"]
		for kind: String in order:
			if int(ranks[kind]) < 10:
				return kind
		return ""
	return super.choose_kind(ranks, strategy)

func identifiers(job: Dictionary, seed_value: int, campaign_id: String) -> Dictionary:
	var result: Dictionary = super.identifiers(job, seed_value, campaign_id)
	result.experiment_case = str(job.get("experiment_case", "repeat_campaign" if str(job.get("mode", "single")) == "campaign" else "fixed_growth"))
	result.proof_status = "not_assessed"
	return result

func augment_result(result: Dictionary, controller: BoulderController, job: Dictionary) -> void:
	var extra: Dictionary = controller.finalize_metrics()
	for index: int in range(4):
		for key: String in ["stamina_consumed", "stamina_recovered", "exhausted_seconds", "stamina_integral", "runaways"]:
			result.bands[index][key] = extra.v02_bands_250[index][key]
	extra.erase("v02_bands_250")
	result.merge(extra)
	result.geometry_layout = controller.mountain.experiment_layout()
	result.ledge_relocations = controller.mountain.ledge_relocations
	result.rest_point_relocations = controller.mountain.rest_point_relocations
	result.runtime_ledges = controller.mountain.ledges
	result.runtime_rest_points = controller.mountain.rest_points
	result.stall_threshold_seconds = float(job.get("stall_seconds", 45.0))
	result.stall_progress_m = float(job.get("stall_progress_m", 0.25))

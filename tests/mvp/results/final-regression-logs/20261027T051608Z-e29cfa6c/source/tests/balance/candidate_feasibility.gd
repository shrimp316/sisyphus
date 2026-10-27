extends "res://tests/balance/simulator.gd"

# Local necessary-force checks using current actual upgrades only. This is not
# a global reachability proof: one-step full-stamina probes omit depletion,
# approach speed, slip history, and whether the tested state can be reached.
func run() -> void:
	var candidates: Dictionary = {"{}": {"candidate": {}, "job_ids": ["baseline"], "sources": []}}
	var paths: Array[String] = ["res://tests/balance/experiments_candidates_pilot.json", "res://tests/balance/experiments_sensitivity_pilot.json"]
	for path: String in paths:
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not config is Dictionary or not config.get("jobs") is Array:
			printerr("Invalid candidate config: " + path)
			quit(2)
			return
		for job: Dictionary in config.jobs:
			var candidate: Dictionary = job.get("candidate", {})
			var key: String = JSON.stringify(candidate, "", true)
			if not candidates.has(key):
				candidates[key] = {"candidate": candidate, "job_ids": [], "sources": []}
			candidates[key].job_ids.append(str(job.id))
			if path not in candidates[key].sources:
				candidates[key].sources.append(path)
	var rows: Array = []
	var probe_count: int = 0
	for key: String in candidates:
		var candidate: Dictionary = candidates[key].candidate
		for rank: int in [0, 8]:
			for weather: String in ["clear", "rain"]:
				var row: Dictionary = {"candidate": candidate, "candidate_sha256": key.sha256_text(), "job_ids": candidates[key].job_ids, "sources": candidates[key].sources, "level": rank, "weather": weather, "seeds": [101, 202, 303], "slope_probes": 0, "nonpositive_start_acceleration": 0, "ledge_probes": 0, "failed_full_stamina_sweet_speed_ledge_probes": 0, "worst_start": {"acceleration": INF}, "worst_ledge": {"force_margin": INF}}
				for seed_value: int in [101, 202, 303]:
					var world := MountainManager.new(seed_value, false, MountainManager.CURRENT_GENERATION, weather)
					configure_world(world, candidate)
					for segment: Dictionary in world.segments:
						if bool(segment.shelf):
							continue
						for meter: int in range(int(ceil(float(segment.start))), int(ceil(float(segment.end)))):
							var position: float = minf(float(meter) + 0.25, float(segment.end) - 0.001)
							var boulder = Controller.new(world)
							apply_growth(boulder, {"strength": rank, "endurance": rank, "recovery": rank}, candidate)
							boulder.stamina = boulder.max_stamina
							boulder.distance = position
							boulder.advance(DT, true, true, false)
							row.slope_probes += 1
							probe_count += 1
							if boulder.acceleration <= 0.0:
								row.nonpositive_start_acceleration += 1
							if boulder.acceleration < float(row.worst_start.acceleration):
								row.worst_start = {"seed": seed_value, "distance_m": position, "surface": world.surface_at(position).id, "slope_degrees": rad_to_deg(world.angle_at(position)), "acceleration": boulder.acceleration}
					for ledge: Dictionary in world.ledges:
						var boulder = Controller.new(world)
						apply_growth(boulder, {"strength": rank, "endurance": rank, "recovery": rank}, candidate)
						boulder.stamina = boulder.max_stamina
						boulder.distance = float(ledge.distance) - 0.001
						boulder.velocity = 0.8
						boulder.advance(DT, true, true, false)
						var margin: float = boulder.push_force - BoulderController.BASE_PUSH * world.grip_at(float(ledge.distance)) * float(ledge.required_push)
						row.ledge_probes += 1
						probe_count += 1
						if not boulder.cleared_ledges.has(str(ledge.id)):
							row.failed_full_stamina_sweet_speed_ledge_probes += 1
						if margin < float(row.worst_ledge.force_margin):
							row.worst_ledge = {"seed": seed_value, "distance_m": ledge.distance, "surface": world.surface_at(float(ledge.distance)).id, "force_margin": margin}
				rows.append(row)
	var target: String = "res://tests/balance/results/candidate-feasibility.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write candidate feasibility output")
		quit(1)
		return
	file.store_string(JSON.stringify({"schema_version": 1, "engine": Engine.get_version_info().string, "generation": MountainManager.CURRENT_GENERATION, "growth_system": "current actual upgrades only", "method": "Meter-spaced uphill stationary full-stamina exert one-step probes; sweet-speed 0.8m/s full-stamina exert ledge crossings. Production integration inherited unchanged. Failure indicates local limitation, not global impossibility; passing does not prove sustained reachability.", "unique_settings": candidates.size(), "probe_count": probe_count, "rows": rows}, "\t"))
	file.close()
	print("CANDIDATE FEASIBILITY: %d settings, %d strata, %d local probes" % [candidates.size(), rows.size(), probe_count])
	quit(0)

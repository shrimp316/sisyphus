extends SceneTree

# Local force probes, not a proof that a whole climb is feasible. Every sample
# advances the production controller; no replacement physics is implemented.
func _init() -> void:
	call_deferred("run")

func run() -> void:
	var rows: Array = []
	for level: int in [0, 10]:
		for weather: String in ["clear", "rain"]:
			var worst_start: Dictionary = {"acceleration": INF}
			var worst_ledge: Dictionary = {"force_margin": INF}
			var failed_starts: int = 0
			var failed_ledges: int = 0
			var slope_count: int = 0
			var ledge_count: int = 0
			for seed_value: int in range(1001, 1101):
				var world := MountainManager.new(seed_value, false, MountainManager.CURRENT_GENERATION, weather)
				for segment: Dictionary in world.segments:
					if bool(segment.shelf):
						continue
					# Meter-spaced probes include exposed wet patches within a climb.
					for meter: int in range(int(segment.start), int(segment.end)):
						var sim := BoulderController.new(world)
						sim.apply_progression({"strength": level, "endurance": level, "recovery": level})
						sim.stamina = sim.max_stamina
						sim.distance = float(meter) + 0.25
						sim.advance(BoulderController.FIXED_DT, true, true, false)
						slope_count += 1
						if sim.acceleration <= 0.0:
							failed_starts += 1
						if sim.acceleration < float(worst_start.acceleration):
							worst_start = {"seed": seed_value, "distance": meter + 0.25, "surface": world.surface_at(meter + 0.25).id, "slope_degrees": rad_to_deg(float(segment.angle)), "acceleration": sim.acceleration}
				for ledge: Dictionary in world.ledges:
					var sim := BoulderController.new(world)
					sim.apply_progression({"strength": level, "endurance": level, "recovery": level})
					sim.stamina = sim.max_stamina
					sim.distance = float(ledge.distance) - 0.001
					sim.velocity = 0.8
					sim.advance(BoulderController.FIXED_DT, true, true, false)
					var margin: float = sim.push_force - BoulderController.BASE_PUSH * world.grip_at(float(ledge.distance)) * float(ledge.required_push)
					ledge_count += 1
					if not sim.cleared_ledges.has(ledge.id):
						failed_ledges += 1
					if margin < float(worst_ledge.force_margin):
						worst_ledge = {"seed": seed_value, "distance": ledge.distance, "force_margin": margin}
			rows.append({"level": level, "weather": weather, "seeds_first": 1001, "seeds_last": 1100, "slope_probes": slope_count, "nonpositive_start_acceleration": failed_starts, "ledge_probes": ledge_count, "failed_full_stamina_sweet_speed_ledge_probes": failed_ledges, "worst_start": worst_start, "worst_ledge": worst_ledge})
	var target: String = "res://tests/balance/results/feasibility.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_error("Cannot open feasibility output")
		quit(1)
		return
	file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "generation": MountainManager.CURRENT_GENERATION, "method": "Production controller one-step full-stamina exert probes. Local full-stamina probes only; no assertion of global reachability or human feasibility.", "rows": rows}, "\t"))
	file.close()
	print("FEASIBILITY " + JSON.stringify(rows))
	quit(0)
